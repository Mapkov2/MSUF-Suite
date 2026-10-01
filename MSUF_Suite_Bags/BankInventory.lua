local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
if NS.Client.isForever then return end
local Model, Index, Bank, Grid = P.InventoryModel, P.InventoryIndex, P.BankInventoryIndex, P.GridView
local Font = Grid.Font
local ALL = { label = "All items", translate = true }
local B = { index = Bank.New(), model = Model.New(), buttons = {}, labels = {}, categories = {},
    scroll = 0, config = {}, context = { transactions = true }, filtered = {}, view = {} }
P.BankInventory = B
local Request, Flush, Render
local MODES = { "Bank tabs", "Combined bank", "Combined warbank", "Bank categories" }
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
    local button = B.buttons[number]
    if not button then
        local actions = P.BankActions
        button = S.CreateFrame("ItemButton", nil, B.frame, "BankItemButtonTemplate")
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
        B.buttons[number] = button
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
    if c.desaturateJunk and item.quality == 0 then SetItemButtonDesaturated(button, true) end
end

local function Select(button)
    B.selected, B.scroll = button.key, 0
    Request()
end

local function RenderNavigation()
    local count = 0
    for i = 1, #B.categories do B.categories[i]:Hide() end
    local function Add(key, text)
        count = count + 1
        local button = B.categories[count]
        if not button then
            button = Button(B.sideChild, "", 132, Select)
            B.categories[count] = button
        end
        button.key = key
        button:SetText(text)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, -(count - 1) * 25)
        button:Show()
    end
    Add("all", Grid.GroupLabel(ALL))
    for i = 1, #B.model.groups do
        local group = B.model.groups[i]
        if group.key ~= "all" then Add(group.key, Grid.GroupLabel(group)) end
    end
    -- Bank tab names are the player's own text.
    if M.config.showBankTabs then
        for i = 1, #B.index.tabs do
            local tab = B.index.tabs[i]
            Add("tab:" .. tab.id, tab.name)
        end
    end
    B.sideChild:SetHeight(math.max(25, count * 25))
end

local function Scroll(delta)
    B.scroll = math.max(0, math.min(B.maxScroll or 0, B.scroll + delta))
    Render()
end

local function NextMode()
    if NS.IsCombatLocked() then return end
    B.selected, B.scroll = "all", 0
    S.Set("bags", "bankView", M.config.bankView % #MODES + 1)
end

local function Create()
    B.frame = S.CreateFrame("Frame", nil, BankFrame.BankPanel)
    local frame = B.frame
    frame:SetAllPoints(BankFrame.BankPanel)
    frame:SetFrameLevel(BankFrame.BankPanel:GetFrameLevel() + 100)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta * 3) end)
    local background = S.CreateTexture(frame, nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0.06, 0.07, 0.08, 1)
    B.title = Font(frame, 14)
    B.title:SetPoint("TOPLEFT", 12, -10)
    B.previous = Button(frame, "Previous", 72, function() Scroll(-B.visibleRows) end)
    B.next = Button(frame, "Next", 72, function() Scroll(B.visibleRows) end)
    B.previous:SetPoint("BOTTOMLEFT", 12, 8)
    B.next:SetPoint("LEFT", B.previous, "RIGHT", 6, 0)
    B.position = Font(frame, 11)
    B.position:SetPoint("LEFT", B.next, "RIGHT", 8, 0)
    B.native = Button(frame, "Manage bank tabs", 145, function() S.Set("bags", "bankView", 1) end)
    B.native:SetPoint("BOTTOMRIGHT", -12, 8)
    B.side = S.CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    B.side:SetPoint("TOPLEFT", 10, -40)
    B.side:SetPoint("BOTTOMLEFT", 10, 40)
    B.side:SetWidth(133)
    B.sideChild = S.CreateFrame("Frame", nil, B.side)
    B.sideChild:SetSize(132, 25)
    B.side:SetScrollChild(B.sideChild)
    -- Below the bank window, opposite Blizzard's bank tabs (BankFrame.xml
    -- TabSystem): the search box and Clean Up button stay free in every view.
    B.modeButton = Button(BankFrame, MODES[1], 142, NextMode)
    B.modeButton:SetPoint("TOPRIGHT", BankFrame, "BOTTOMRIGHT", -22, 2)
    BankFrame:HookScript("OnShow", function() Index.Retry(B.index); Request() end)
    BankFrame:HookScript("OnHide", function()
        if B.frame then B.frame:Hide() end
        P.BankActions.Cancel()
    end)
end

local function PaintCell(cell, number, sidebar, font)
    local x, y = sidebar + cell.column * 40, -40 - (cell.line - B.scroll) * 40
    if not cell.row then
        B.labelCount = B.labelCount + 1
        Grid.PaintHeader(B.labels, B.labelCount, B.frame, B.frame, x, y - 9, (cell.width or B.columns) * 40 - 4,
            cell.group)
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
    if not B.active or not BankFrame:IsShown() or NS.IsCombatLocked() then return end
    local sidebar = M.config.bankView == 4 and 170 or 12
    B.columns = math.max(4, math.floor((B.frame:GetWidth() - sidebar - 12) / 40))
    B.visibleRows = math.max(2, math.floor((B.frame:GetHeight() - 84) / 40))
    local layout = Model.Layout(B.model, B.columns, M.config.compactGroups)
    B.maxScroll = math.max(0, B.model.lineCount - B.visibleRows)
    B.scroll = math.min(B.scroll, B.maxScroll)
    for i = 1, #B.labels do B.labels[i]:Hide() end
    local shown = 0
    B.labelCount = 0
    local font = Grid.FontPath()
    for i = 1, #layout do
        local cell = layout[i]
        if cell.line >= B.scroll and cell.line < B.scroll + B.visibleRows then
            shown = PaintCell(cell, shown, sidebar, font)
        end
    end
    for i = shown + 1, #B.buttons do B.buttons[i]:Hide() end
    B.side:SetShown(M.config.bankView == 4)
    B.previous:SetEnabled(B.scroll > 0)
    B.next:SetEnabled(B.scroll < B.maxScroll)
    Grid.PositionText(B.position, B.scroll, B.visibleRows, B.model.lineCount)
    B.title:SetText(S.Text(MODES[M.config.bankView]))
    B.frame:Show()
end

local function PrepareModel(state)
    for key, value in pairs(M.config) do B.config[key] = value end
    B.config.inventoryView = M.config.bankView == 4 and 3 or 1
    B.config.groupExpansions = M.config.bankGroupExpansions
    B.config.expansionFirst = M.config.bankGroupExpansions
    B.config.groupEquipmentSlots = M.config.bankGroupEquipmentSlots
    B.config.groupReagentTypes = M.config.bankGroupReagentTypes
    B.config.hideEmptySlots = M.config.bankHideEmptySlots
    B.config.showRecent = false
    local tab = B.selected and tonumber(B.selected:match("^tab:(%-?%d+)$"))
    local items = B.index.items
    if tab then
        local found = false
        for i = 1, #B.index.tabs do if B.index.tabs[i].id == tab then found = true; break end end
        if not found then B.selected, tab, B.scroll = "all", nil, 0 end
    end
    if tab then
        for i = #B.filtered, 1, -1 do B.filtered[i] = nil end
        for i = 1, #items do
            if items[i].bag == tab then B.filtered[#B.filtered + 1] = items[i] end
        end
        items = B.filtered
    end
    local built = Grid.Build(Model, B.model, items, B.config, state, B.context, not tab and B.selected or "all")
    if not tab and built ~= B.selected then B.selected, B.scroll = built, 0 end
end

Flush = function()
    B.queued = false
    if not B.enabled or not M.active or not BankFrame:IsShown() then return end
    if NS.IsCombatLocked() then return end
    if not B.frame then Create() end
    B.modeButton:SetText(S.Text(MODES[M.config.bankView]))
    B.modeButton:Show()
    B.active = M.config.bankView > 1
    M.organizedBankActive = B.active
    if not B.active then B.frame:Hide(); M:UpdateBank(); return end
    M:HideBankLevels()
    local moduleState = S.ModuleState("bags")
    if not moduleState then return end
    local state = Index.State(moduleState, B.view)
    Bank.Read(B.index, M.config.bankView)
    P.InventoryDetails.Index(B.index)
    PrepareModel(state)
    Render()
    RenderNavigation()
end

Request = function()
    if not B.enabled or B.queued or not BankFrame:IsShown() then return end
    B.queued = true
    C_Timer.After(0, Flush)
end

local function Event(_, event, value, success)
    if event == "BAG_UPDATE_COOLDOWN" or event == "INVENTORY_SEARCH_UPDATE" then
        if B.active and B.frame:IsShown() then
            local font = Grid.FontPath()
            for i = 1, #B.buttons do
                local button = B.buttons[i]
                if button:IsShown() then
                    if event == "BAG_UPDATE_COOLDOWN" then button:UpdateCooldown()
                    else button:Refresh(); StyleItem(button, button.record, font) end
                end
            end
        end
        return
    end
    if event == "BAG_UPDATE" or event == "BANKFRAME_OPENED" then P.InventoryDetails.Invalidate() end
    if event == "BANKFRAME_CLOSED" then
        B.active, M.organizedBankActive = false, false
        if B.frame then B.frame:Hide() end
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        -- Arriving item data patches the waiting records; no tab is read again.
        if not Index.ItemDataReceived(B.index, value, success) then return end
        Index.Refresh(B.index, value)
    elseif event == "BAG_UPDATE" or event == "ITEM_LOCK_CHANGED" then
        -- SlotCache marks the changed tab or slot. Equipment slots send
        -- ITEM_LOCK_CHANGED(inventorySlot, nil) and share the bank tab IDs 6-16.
        if not B.index.containers[value] or event == "ITEM_LOCK_CHANGED" and not S.Finite(success) then return end
    end
    Request()
end

function B.Refresh()
    B.enabled = M.active == true
    Grid.RefreshFonts()
    if not B.events then
        B.events = S.CreateFrame("Frame")
        B.events:SetScript("OnEvent", Event)
    end
    for i = 1, #EVENTS do
        if NS.Client.SupportsEvent(EVENTS[i]) then B.events:RegisterEvent(EVENTS[i]) end
    end
    Request()
end

function B.Disable()
    B.enabled, B.active, M.organizedBankActive = false, false, false
    Index.Reset(B.index)
    if B.events then B.events:UnregisterAllEvents() end
    if B.frame then B.frame:Hide(); B.modeButton:Hide() end
end
