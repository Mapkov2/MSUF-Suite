local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
if NS.Client.isForever then return end
local Model, Index, Bank, Grid = P.InventoryModel, P.InventoryIndex, P.BankInventoryIndex, P.GridView
local Font = Grid.Font
local ALL = { label = "All items", translate = true }
local VIEW, BANK_VIEW, POOR = NS.BagsView, NS.BagsBankView, Enum.ItemQuality.Poor
local BankInventory = { index = Bank.New(), model = Model.New(), buttons = {}, labels = {}, categories = {},
    scroll = 0, config = {}, context = { transactions = true }, filtered = {}, view = {} }
P.BankInventory = BankInventory
local Request, Flush, Render
local MODES = { [BANK_VIEW.TABS] = "Bank tabs", [BANK_VIEW.CHARACTER] = "Combined bank",
    [BANK_VIEW.WARBANK] = "Combined warbank", [BANK_VIEW.CATEGORIES] = "Bank categories" }
local EVENTS = { "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE", "PLAYER_REGEN_ENABLED",
    "GET_ITEM_INFO_RECEIVED", "BANK_TABS_CHANGED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "INVENTORY_SEARCH_UPDATE",
    "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "BANK_TAB_SETTINGS_UPDATED" }

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
        button = S.CreateFrame("ItemButton", nil, BankInventory.frame, "BankItemButtonTemplate")
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
        S.SetFont(button.level, font, c.itemLevelSize, "OUTLINE")
        S.SetFont(button.Count, font, c.itemCountSize, "OUTLINE")
        button.font, button.levelSize, button.countSize = font, c.itemLevelSize, c.itemCountSize
    end
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

local function RenderNavigation()
    local count = 0
    for i = 1, #BankInventory.categories do BankInventory.categories[i]:Hide() end
    local function Add(key, text)
        count = count + 1
        local button = BankInventory.categories[count]
        if not button then
            button = Button(BankInventory.sideChild, "", 132, Select)
            BankInventory.categories[count] = button
        end
        button.key = key
        button:SetText(text)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, -(count - 1) * 25)
        button:Show()
    end
    Add("all", Grid.GroupLabel(ALL))
    for i = 1, #BankInventory.model.groups do
        local group = BankInventory.model.groups[i]
        if group.key ~= "all" then Add(group.key, Grid.GroupLabel(group)) end
    end
    -- Bank tab names are the player's own text.
    if M.config.showBankTabs then
        for i = 1, #BankInventory.index.tabs do
            local tab = BankInventory.index.tabs[i]
            Add("tab:" .. tab.id, tab.name)
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

local function Create()
    BankInventory.frame = S.CreateFrame("Frame", nil, BankFrame.BankPanel)
    local frame = BankInventory.frame
    frame:SetAllPoints(BankFrame.BankPanel)
    frame:SetFrameLevel(BankFrame.BankPanel:GetFrameLevel() + 100)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta * 3) end)
    local background = S.CreateTexture(frame, nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0.06, 0.07, 0.08, 1)
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
    BankInventory.side = S.CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    BankInventory.side:SetPoint("TOPLEFT", 10, -40)
    BankInventory.side:SetPoint("BOTTOMLEFT", 10, 40)
    BankInventory.side:SetWidth(133)
    BankInventory.sideChild = S.CreateFrame("Frame", nil, BankInventory.side)
    BankInventory.sideChild:SetSize(132, 25)
    BankInventory.side:SetScrollChild(BankInventory.sideChild)
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
    local x, y = sidebar + cell.column * 40, -40 - (cell.line - BankInventory.scroll) * 40
    if not cell.row then
        BankInventory.labelCount = BankInventory.labelCount + 1
        Grid.PaintHeader(BankInventory.labels, BankInventory.labelCount, BankInventory.frame, BankInventory.frame,
            x, y - 9, (cell.width or BankInventory.columns) * 40 - 4, cell.group)
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
    BankInventory.columns = math.max(4, math.floor((BankInventory.frame:GetWidth() - sidebar - 12) / 40))
    BankInventory.visibleRows = math.max(2, math.floor((BankInventory.frame:GetHeight() - 84) / 40))
    local layout = Model.Layout(BankInventory.model, BankInventory.columns, M.config.compactGroups)
    BankInventory.maxScroll = math.max(0, BankInventory.model.lineCount - BankInventory.visibleRows)
    BankInventory.scroll = math.min(BankInventory.scroll, BankInventory.maxScroll)
    for i = 1, #BankInventory.labels do BankInventory.labels[i]:Hide() end
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
    BankInventory.title:SetText(S.Text(MODES[M.config.bankView]))
    BankInventory.frame:Show()
end

local function PrepareModel(state)
    for key, value in pairs(M.config) do BankInventory.config[key] = value end
    BankInventory.config.inventoryView = M.config.bankView == BANK_VIEW.CATEGORIES and VIEW.CATEGORIES or VIEW.ALL
    BankInventory.config.groupExpansions = M.config.bankGroupExpansions
    BankInventory.config.expansionFirst = M.config.bankGroupExpansions
    BankInventory.config.groupEquipmentSlots = M.config.bankGroupEquipmentSlots
    BankInventory.config.groupReagentTypes = M.config.bankGroupReagentTypes
    BankInventory.config.hideEmptySlots = M.config.bankHideEmptySlots
    BankInventory.config.showRecent = false
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
end

Flush = function()
    BankInventory.queued = false
    if not BankInventory.enabled or not M.active or not BankFrame:IsShown() then return end
    if NS.IsCombatLocked() then return end
    if not BankInventory.frame then Create() end
    BankInventory.modeButton:SetText(S.Text(MODES[M.config.bankView]))
    BankInventory.modeButton:Show()
    BankInventory.active = M.config.bankView ~= BANK_VIEW.TABS
    M.organizedBankActive = BankInventory.active
    if not BankInventory.active then
        BankInventory.frame:Hide()
        M:UpdateBank()
        return
    end
    M:HideBankLevels()
    local moduleState = S.ModuleState("bags")
    if not moduleState then return end
    local state = Index.State(moduleState, BankInventory.view)
    Bank.Read(BankInventory.index, M.config.bankView)
    P.InventoryDetails.Index(BankInventory.index)
    PrepareModel(state)
    Render()
    RenderNavigation()
end

Request = function()
    if not BankInventory.enabled or BankInventory.queued or not BankFrame:IsShown() then return end
    BankInventory.queued = true
    C_Timer.After(0, Flush)
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
    if event == "BANKFRAME_CLOSED" then
        BankInventory.active, M.organizedBankActive = false, false
        if BankInventory.frame then BankInventory.frame:Hide() end
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

function BankInventory.Refresh()
    BankInventory.enabled = M.active == true
    Grid.RefreshFonts()
    if not BankInventory.events then
        BankInventory.events = S.CreateFrame("Frame")
        BankInventory.events:SetScript("OnEvent", Event)
    end
    for i = 1, #EVENTS do
        if NS.Client.SupportsEvent(EVENTS[i]) then BankInventory.events:RegisterEvent(EVENTS[i]) end
    end
    Request()
end

function BankInventory.Disable()
    BankInventory.enabled, BankInventory.active, M.organizedBankActive = false, false, false
    Index.Reset(BankInventory.index)
    if BankInventory.events then BankInventory.events:UnregisterAllEvents() end
    if BankInventory.frame then
        BankInventory.frame:Hide()
        BankInventory.modeButton:Hide()
    end
end
