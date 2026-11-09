local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Model, Index, Bank, Grid = P.InventoryModel, P.InventoryIndex, P.BankInventoryIndex, P.GridView
local FreeSlots = P.FreeSlots
local Font = Grid.Font
local ALL = { label = "All items", translate = true }
local VIEW, BANK_VIEW, POOR = NS.BagsView, NS.BagsBankView, Enum.ItemQuality.Poor
local BankInventory = { index = Bank.New(), model = Model.New(), buttons = {}, labels = {}, categories = {},
    scroll = 0, config = {}, context = { transactions = true }, filtered = {}, view = {}, freeSlots = {} }
P.BankInventory = BankInventory
local Request, Flush, Render
local MODES = { [BANK_VIEW.TABS] = "Bank tabs", [BANK_VIEW.CHARACTER] = "Combined bank",
    [BANK_VIEW.WARBANK] = "Combined warbank", [BANK_VIEW.CATEGORIES] = "Bank categories" }
local WATCH_EVENTS = { "BAG_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "GET_ITEM_INFO_RECEIVED", "BANK_TABS_CHANGED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "INVENTORY_SEARCH_UPDATE",
    "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "BANK_TAB_SETTINGS_UPDATED" }
local GRID_TOP = NS.Client.isForever and 68 or 40

local function WatchBank(watching)
    if BankInventory.watching == watching then return end
    BankInventory.watching = watching
    local events = BankInventory.events
    for _, event in ipairs(WATCH_EVENTS) do
        if watching then
            if NS.Client.SupportsEvent(event) then events:RegisterEvent(event) end
        else
            events:UnregisterEvent(event)
        end
    end
end

local function Button(parent, text, width, callback)
    return Grid.Button(parent, text, width, callback, 23)
end

local function ButtonHidden(button)
    -- The native template installs its hover updater on enter, not on show.
    -- A pooled button can leave the page before OnLeave is delivered.
    button:SetScript("OnUpdate", nil)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    P.StackSplitter.OwnerHidden(button)
    P.BankActions.Hidden(button)
end

-- Clicks run BankActions.lua, never BankPanelItemButtonMixin's handlers.
local function AcquireButton(number)
    local button = BankInventory.buttons[number]
    if not button then
        local actions = P.BankActions
        button = P.ChildFrame("ItemButton", BankInventory.frame, "BankItemButtonTemplate")
        button:SetSize(37, 37)
        button:SetScript("OnClick", actions.Click)
        button:SetScript("OnDragStart", actions.Drag)
        button:SetScript("OnReceiveDrag", actions.Receive)
        button:SetScript("OnHide", ButtonHidden)
        -- A warband item hovered while Blizzard's Bank tab is selected gets
        -- the secure tab overlay (BankActions.lua).
        button:HookScript("OnEnter", actions.Enter)
        button.level = Font(button, M.config.itemLevelSize)
        button.level:SetPoint("TOPRIGHT", -1, -1)
        button.levelStyle = { label = button.level }
        BankInventory.buttons[number] = button
    end
    return button
end

-- font: the bag font, read once per render (GridView.FontPath).
local function StyleItem(button, item, font)
    local c = M.config
    if c.showBankItemLevel and item.equipLoc and item.equipLoc ~= "" and item.link and item.level == nil then
        local level = C_Item.GetDetailedItemLevelInfo(item.link)
        if S.Finite(level) then item.level = level end
    end
    local level = c.showBankItemLevel and item.level
    if button.font ~= font or button.levelSize ~= c.itemLevelSize or button.countSize ~= c.itemCountSize then
        S.SetFont(button.Count, font, c.itemCountSize, "OUTLINE")
        button.font, button.levelSize, button.countSize = font, c.itemLevelSize, c.itemCountSize
    end
    M:StyleItemLevel(button.levelStyle)
    M:PaintItemLevelQuality(button.levelStyle, item.quality)
    if S.Finite(level) and level > 0 then
        button.level:SetText(tostring(math.floor(level)))
        button.level:Show()
    else
        button.level:Hide()
    end
    -- Pass the state every time: Blizzard clears the grey only in Refresh
    -- (BankPanelItemButtonMixin:UpdateLocked), which an unchanged slot skips.
    -- A locked slot keeps the grey UpdateLocked gave it.
    local info = button.itemInfo
    local locked = info ~= nil and info.isLocked == true
    SetItemButtonDesaturated(button, locked or c.desaturateJunk and item.quality == POOR or false)
end

local function Select(button)
    BankInventory.selected, BankInventory.scroll = button.key, 0
    Request()
end

-- A header click in the bank's categories: collapse or expand its group. The
-- bank keeps its own collapsed set (Index.State).
local function ToggleGroup(key)
    if NS.IsCombatLocked() then return end
    if Model.ToggleCollapsed(BankInventory.view.collapsed, key, BankInventory.model.groupsByKey) then Request() end
end

-- The navigation button at position, made on first use; returns position.
local function AddNavigation(position, key, text)
    local button = BankInventory.categories[position]
    if not button then
        button = Button(BankInventory.sideChild, "", 132, Select)
        BankInventory.categories[position] = button
    end
    button.key = key
    button:SetText(text)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", 0, -(position - 1) * 25)
    button:Show()
    return position
end

local function RenderNavigation()
    for i = 1, #BankInventory.categories do BankInventory.categories[i]:Hide() end
    local count = AddNavigation(1, "all", Grid.GroupLabel(ALL))
    for i = 1, #BankInventory.model.groups do
        local group = BankInventory.model.groups[i]
        if group.key ~= "all" then count = AddNavigation(count + 1, group.key, Grid.GroupLabel(group)) end
    end
    -- Bank tab names are the player's own text.
    if M.config.showBankTabs then
        for i = 1, #BankInventory.index.tabs do
            local tab = BankInventory.index.tabs[i]
            count = AddNavigation(count + 1, "tab:" .. tab.id, tab.name)
        end
    end
    BankInventory.sideChild:SetHeight(math.max(25, count * 25))
end

local function Scroll(delta)
    BankInventory.scroll = math.max(0, math.min(BankInventory.maxScroll or 0, BankInventory.scroll + delta))
    Render()
end

local function NextMode()
    if NS.IsCombatLocked() then return end
    BankInventory.selected, BankInventory.scroll = "all", 0
    S.Set("bags", "bankView", M.config.bankView % #MODES + 1)
end

-- The smart search box and its Filters button stand in the title row.
local function PlaceSearch(edit, button)
    button:SetPoint("TOPRIGHT", -12, NS.Client.isForever and -34 or -7)
    if NS.Client.isForever then
        edit:SetPoint("TOPLEFT", BankInventory.frame, "TOPLEFT", 12, -34)
    else
        edit:SetPoint("TOPLEFT", BankInventory.title, "TOPRIGHT", 16, 4)
    end
    edit:SetPoint("TOPRIGHT", button, "TOPLEFT", -8, 0)
end

-- Both bank views use the same opaque fill. The organized panel covers the
-- original slots. The native fill sits above Blizzard's background artwork,
-- below its title, slots, tab buttons and deposit controls.
local function PaintBackground()
    local hex = NS.BagsBankColor(M.config)
    if BankInventory.paintedColor == hex then return end
    BankInventory.paintedColor = hex
    local r, g, b = S.RGB(hex)
    BankInventory.background:SetColorTexture(r, g, b, 1)
    BankInventory.nativeBackground:SetColorTexture(r, g, b, 1)
end

local function Create()
    BankInventory.frame = P.ChildFrame("Frame", BankFrame.BankPanel)
    local frame = BankInventory.frame
    frame:SetAllPoints(BankFrame.BankPanel)
    frame:SetFrameLevel(BankFrame.BankPanel:GetFrameLevel() + 100)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta * 3) end)
    BankInventory.background = S.CreateTexture(frame, nil, "BACKGROUND")
    BankInventory.background:SetAllPoints(frame)
    BankInventory.nativeBackground = S.CreateTexture(BankFrame, nil, "BACKGROUND", nil, 1)
    BankInventory.nativeBackground:SetAllPoints(BankFrame)
    BankInventory.nativeBackground:Hide()
    PaintBackground()
    BankInventory.title = Font(frame, 14)
    BankInventory.title:SetPoint("TOPLEFT", 12, -10)
    BankInventory.previous = Button(frame, "Previous", 72, function() Scroll(-BankInventory.visibleRows) end)
    BankInventory.next = Button(frame, "Next", 72, function() Scroll(BankInventory.visibleRows) end)
    BankInventory.previous:SetPoint("BOTTOMLEFT", 12, 8)
    BankInventory.next:SetPoint("LEFT", BankInventory.previous, "RIGHT", 6, 0)
    BankInventory.position = Font(frame, 11)
    BankInventory.position:SetPoint("LEFT", BankInventory.next, "RIGHT", 8, 0)
    BankInventory.native = Button(frame, "Manage bank tabs", 145, function() S.Set("bags", "bankView", BANK_VIEW.TABS) end)
    BankInventory.native:SetPoint("BOTTOMRIGHT", -12, 8)
    BankInventory.free = Font(frame, 11)
    BankInventory.free:SetJustifyH("RIGHT")
    BankInventory.free:SetWordWrap(false)
    BankInventory.free:SetPoint("LEFT", BankInventory.position, "RIGHT", 8, 0)
    BankInventory.free:SetPoint("RIGHT", BankInventory.native, "LEFT", -8, 0)
    P.InventorySearch.Create(BankInventory, Request, frame, PlaceSearch)
    BankInventory.side, BankInventory.sideChild = P.BagWidgets.Scroll(frame, 133)
    BankInventory.side:SetPoint("TOPLEFT", 10, -GRID_TOP)
    BankInventory.side:SetPoint("BOTTOMLEFT", 10, 40)
    -- Below the bank window, opposite Blizzard's bank tabs (BankFrame.xml
    -- TabSystem): the search box and Clean Up button stay free in every view.
    BankInventory.modeButton = Button(BankFrame, MODES[BANK_VIEW.TABS], 142, NextMode)
    BankInventory.modeButton:SetPoint("TOPRIGHT", BankFrame, "BOTTOMRIGHT", -22, 2)
    BankFrame:HookScript("OnShow", function()
        Index.Retry(BankInventory.index)
        Request()
    end)
    BankFrame:HookScript("OnHide", function()
        if BankInventory.frame then BankInventory.frame:Hide() end
        P.BankActions.Cancel()
    end)
end

local function PaintCell(cell, number, sidebar, font)
    local x, y = sidebar + cell.column * 40, -GRID_TOP - (cell.line - BankInventory.scroll) * 40
    if not cell.row then
        BankInventory.labelCount = BankInventory.labelCount + 1
        local toggle = M.config.bankView == BANK_VIEW.CATEGORIES and ToggleGroup or nil
        local label = Grid.PaintHeader(BankInventory.labels, BankInventory.labelCount, BankInventory.frame, BankInventory.frame,
            x, y - 9, (cell.width or BankInventory.columns) * 40 - 4, cell.group, toggle)
        local plate = P.BagAppearance.Section(label, BankInventory.frame)
        local rows = math.min(cell.height, BankInventory.visibleRows - cell.line + BankInventory.scroll)
        P.BagAppearance.PaintSection(plate, BankInventory.frame, x, y,
            (cell.width or BankInventory.columns) * 40 - 4, rows * 40 - 5, nil, label)
        return number
    end
    number = number + 1
    local item, button = cell.row.item, AcquireButton(number)
    if button.record ~= item then ButtonHidden(button) end
    button.record = item
    -- Blizzard's Refresh reads the slot again: only after the cached read
    -- changed (SlotCache.lua). Cooldowns and search have their own events.
    if button.bankType ~= item.bankType or button.bankTabID ~= item.bag or button.containerSlotID ~= item.slot then
        button:Init(item.bankType, item.bag, item.slot)
    elseif button.suiteVersion ~= item.version then
        button:Refresh()
    end
    button.suiteVersion = item.version
    if button.x ~= x or button.y ~= y then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", x, y)
        button.x, button.y = x, y
    end
    StyleItem(button, item, font)
    P.InventoryDetails.Paint(button, item, font)
    button:Show()
    return number
end

Render = function()
    if not BankInventory.active or not BankFrame:IsShown() or NS.IsCombatLocked() then return end
    local categories = M.config.bankView == BANK_VIEW.CATEGORIES
    local sidebar = categories and 170 or 12
    BankInventory.columns = Model.BankColumns(BankInventory.frame:GetWidth(), categories)
    BankInventory.visibleRows = math.max(2, math.floor((BankInventory.frame:GetHeight() - GRID_TOP - 44) / 40))
    local layout = Model.Layout(BankInventory.model, BankInventory.columns, BankInventory.config.compactGroups)
    BankInventory.maxScroll = math.max(0, BankInventory.model.lineCount - BankInventory.visibleRows)
    BankInventory.scroll = math.min(BankInventory.scroll, BankInventory.maxScroll)
    Grid.HideHeaders(BankInventory.labels)
    local shown = 0
    BankInventory.labelCount = 0
    local font = Grid.FontPath()
    for i = 1, #layout do
        local cell = layout[i]
        if cell.line >= BankInventory.scroll and cell.line < BankInventory.scroll + BankInventory.visibleRows then
            shown = PaintCell(cell, shown, sidebar, font)
        end
    end
    for i = shown + 1, #BankInventory.buttons do BankInventory.buttons[i]:Hide() end
    BankInventory.side:SetShown(categories)
    BankInventory.previous:SetEnabled(BankInventory.scroll > 0)
    BankInventory.next:SetEnabled(BankInventory.scroll < BankInventory.maxScroll)
    Grid.PositionText(BankInventory.position, BankInventory.scroll, BankInventory.visibleRows, BankInventory.model.lineCount)
    if M.config.showFreeSlots then FreeSlots.Paint(BankInventory.free, BankInventory.freeSlots) else BankInventory.free:Hide() end
    BankInventory.title:SetText(S.Text(MODES[M.config.bankView]))
    BankInventory.frame:Show()
end

local function PrepareModel(state)
    Model.BankConfig(BankInventory.config, M.config)
    local tab = BankInventory.selected and tonumber(BankInventory.selected:match("^tab:(%-?%d+)$"))
    local items = BankInventory.index.items
    if tab then
        local found = false
        for i = 1, #BankInventory.index.tabs do
            if BankInventory.index.tabs[i].id == tab then
                found = true
                break
            end
        end
        if not found then BankInventory.selected, tab, BankInventory.scroll = "all", nil, 0 end
    end
    if tab then
        for i = #BankInventory.filtered, 1, -1 do BankInventory.filtered[i] = nil end
        for i = 1, #items do
            if items[i].bag == tab then BankInventory.filtered[#BankInventory.filtered + 1] = items[i] end
        end
        items = BankInventory.filtered
    end
    local built = Grid.Build(Model, BankInventory.model, items, BankInventory.config, state, BankInventory.context, not tab and BankInventory.selected or "all")
    if not tab and built ~= BankInventory.selected then BankInventory.selected, BankInventory.scroll = built, 0 end
    BankInventory.renderedTab = tab
end

Flush = function()
    if not BankInventory.enabled or not M.active or not BankFrame:IsShown() then return end
    local nativeGamepad = NS.Client.isForever and S.GamepadUI()
    local organize = M.config.bankView ~= BANK_VIEW.TABS and not nativeGamepad
    WatchBank(organize or not BankInventory.frame)
    if NS.InCombat() then return end
    if not BankInventory.frame then
        Create()
        if not organize then WatchBank(false) end
    end
    local modeButton = BankInventory.modeButton
    local mode = M.config.bankView
    if modeButton.mode ~= mode then
        modeButton.mode = mode
        modeButton:SetText(S.Text(MODES[mode]))
    end
    local showMode = not nativeGamepad
    if modeButton:IsShown() ~= showMode then modeButton:SetShown(showMode) end
    local wasOrganized = BankInventory.active
    BankInventory.active = organize
    M.organizedBankActive = organize
    if not NS.Client.isForever then BankInventory.nativeBackground:SetShown(not organize) end
    if not BankInventory.active then
        P.BankActions.Cancel()
        BankInventory.frame:Hide()
        if wasOrganized or not NS.Client.isForever then M:UpdateBank() end
        return
    end
    M:HideBankLevels()
    local moduleState = S.ModuleState("bags")
    if not moduleState then return end
    local state = Index.State(moduleState, BankInventory.view, "bankCollapsed")
    Bank.Read(BankInventory.index, M.config.bankView)
    P.InventoryDetails.Index(BankInventory.index, BankInventory.smartQuery)
    FreeSlots.Read(BankInventory.freeSlots, BankInventory.index, false)
    BankInventory.context.query = BankInventory.smartQuery
    PrepareModel(state)
    Render()
    RenderNavigation()
end

-- One pass per frame (a ctx:Coalesce job): requests in between ride along.
Request = function()
    if not BankInventory.enabled or not BankFrame:IsShown() then return end
    BankInventory.flushJob = BankInventory.flushJob or M.context:Coalesce(0, Flush)
    BankInventory.flushJob:Request()
end

local function Event(_, event, value, success)
    if event == "BAG_UPDATE_COOLDOWN" or event == "INVENTORY_SEARCH_UPDATE" then
        if BankInventory.active and BankInventory.frame:IsShown() then
            local font = Grid.FontPath()
            for i = 1, #BankInventory.buttons do
                local button = BankInventory.buttons[i]
                if button:IsShown() then
                    if event == "BAG_UPDATE_COOLDOWN" then button:UpdateCooldown()
                    else
                        button:Refresh()
                        StyleItem(button, button.record, font)
                    end
                end
            end
        end
        return
    end
    if event == "BAG_UPDATE" or event == "BANKFRAME_OPENED" then P.InventoryDetails.Invalidate() end
    if event == "BANKFRAME_CLOSED" or event == "PLAYER_REGEN_DISABLED" then
        if event == "BANKFRAME_CLOSED" then WatchBank(false) end
        BankInventory.active, M.organizedBankActive = false, false
        if BankInventory.frame and not NS.IsCombatLocked() then BankInventory.frame:Hide() end
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        -- Arriving item data patches the waiting records; no tab is read again.
        if not Index.ItemDataReceived(BankInventory.index, value, success) then return end
        Index.Refresh(BankInventory.index, value)
    elseif event == "BAG_UPDATE" or event == "ITEM_LOCK_CHANGED" then
        -- SlotCache marks the changed tab or slot. Equipment slots send
        -- ITEM_LOCK_CHANGED(inventorySlot, nil) and share the bank tab IDs 6-16.
        if not BankInventory.index.containers[value] or event == "ITEM_LOCK_CHANGED" and not S.Finite(success) then return end
    end
    Request()
end

BankInventory.Request = Request

function BankInventory.Refresh()
    BankInventory.enabled = M.active == true
    Grid.RefreshFonts()
    if BankInventory.background then PaintBackground() end
    if not BankInventory.events then
        BankInventory.events = S.CreateFrame("Frame")
        BankInventory.events:SetScript("OnEvent", Event)
    end
    BankInventory.events:RegisterEvent("BANKFRAME_OPENED")
    BankInventory.events:RegisterEvent("BANKFRAME_CLOSED")
    Request()
end

function BankInventory.Disable()
    BankInventory.enabled, BankInventory.active, M.organizedBankActive = false, false, false
    P.BankActions.Cancel()
    Index.Reset(BankInventory.index)
    BankInventory.watching = nil
    if BankInventory.events then BankInventory.events:UnregisterAllEvents() end
    if BankInventory.frame then
        BankInventory.frame:Hide()
        BankInventory.nativeBackground:Hide()
        BankInventory.modeButton:Hide()
    end
end
