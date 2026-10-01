local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Model, Index, Grid = P.InventoryModel, P.InventoryIndex, P.GridView
local Font, Button = Grid.Font, Grid.Button
local ALL, PINNED = { label = "All items", translate = true }, { label = "Pinned items", translate = true }
-- layout: "suite" (Suite grid), "combat" (every slot in physical order, no
-- Suite controls) or "native" (Blizzard's own grid is showing).
local V = { index = Index.New(), model = Model.New(), buttons = {}, labels = {}, scroll = 0, view = {},
    context = {}, layout = "native" }
V.nativeCountFonts = setmetatable({}, { __mode = "k" })
V.visibleButtons, V.slotState = {}, setmetatable({}, { __mode = "k" })
P.InventoryView = V
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
-- Cell size, the space above the first Suite row, the footer above the money
-- row, and the top margin of the combat layout (below the window header).
local CELL, TOP, FOOTER, COMBAT_TOP = 40, 92, 50, 66
local Request, Render, Flush
-- Windows that take items one physical stack at a time: merged stacks split
-- up while one is open. Blizzard_GuildBankUI loads on demand.
local Transactions = { "MailFrame", "TradeFrame", "AuctionHouseFrame", "AuctionFrame", "BankFrame", "MerchantFrame",
    "GuildBankFrame" }
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
    "BAG_UPDATE_DELAYED", "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "INVENTORY_SEARCH_UPDATE" }

local function State()
    local state = S.ModuleState("bags")
    if not state then return nil end
    return Index.State(state, V.view)
end

local function TransactionOpen()
    for i = 1, #Transactions do
        local frame = _G[Transactions[i]]
        if frame and frame:IsShown() then return true end
    end
    return false
end

-- Pages exist in the Suite grid only; in combat every slot is already shown.
local function MoveScroll(delta)
    if V.layout ~= "suite" or NS.IsCombatLocked() then return end
    V.scroll = max(0, min(V.maxScroll or 0, V.scroll + delta))
    Render()
end

local function SelectCategory(button, mouseButton)
    if mouseButton == "RightButton" then
        if button.categoryKey == "pinned" then P.InventoryEditor.ShowPinned()
        else P.InventoryEditor.Show() end
        return
    end
    V.selected, V.scroll = button.categoryKey, 0
    Request()
end

local function DropCategory(button)
    if NS.IsCombatLocked() then return end
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or not S.Finite(itemID) then return end
    local state = State()
    if not state then return end
    if button.categoryKey == "pinned" then
        state.pinned[itemID] = true
    else
        local number = V.model.customIndex[button.categoryKey]
        local categories = Model.DecodeCategories(M.config.customCategories)
        local category = number and categories[number]
        if not category then return end
        if not category.items[itemID] and Model.CountItems(category) >= Model.CATEGORY_ITEMS then
            -- The saved list keeps at most 500 item IDs; never drop one silently.
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(button:GetText())
            GameTooltip:AddLine(S.Text("This category already holds 500 items. Remove one before adding another."),
                1, 0.6, 0.2, true)
            GameTooltip:Show()
            return
        end
        category.items[itemID] = true
        local encoded = Model.EncodeCategories(categories)
        if not encoded then return end
        S.Set("bags", "customCategories", encoded)
    end
    ClearCursor()
    Request()
end

local function CategoryEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(button:GetText())
    if (button.categoryKey == "pinned" and M.config.showPinnedHint)
        or button.categoryKey:match("^custom:") then
        GameTooltip:AddLine(S.Text("Drop an item here to add it without moving it."), 0.8, 0.8, 0.8, true)
    end
    if button.categoryKey == "pinned" and M.config.showPinnedHint then
        GameTooltip:AddLine(S.Text("Right-click to remove pinned items."), 0.8, 0.8, 0.8, true)
    elseif button.categoryKey == "recent" and M.config.showRecentHint then
        GameTooltip:AddLine(S.Text("Use Clear recent items to start a fresh list."), 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end

local function CategoryButton(key, group, count, order)
    local button = V.buttons[order]
    if not button then
        button = Button(V.sidebarChild, "", 140, SelectCategory)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnReceiveDrag", DropCategory)
        button:SetScript("OnEnter", CategoryEnter)
        button:SetScript("OnLeave", GameTooltip_Hide)
        V.buttons[order] = button
    end
    button.categoryKey = key
    local label = Grid.GroupLabel(group)
    button:SetText(count and Grid.CountLabel(label, count) or label)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", 0, -(order - 1) * 25)
    button:Show()
    return button
end

local function ViewSelected(button)
    V.scroll, V.selected = 0, "all"
    V.shuffle = false
    S.Set("bags", "inventoryView", button.view)
end

local function ShuffleItems()
    if NS.IsCombatLocked() then return end
    V.shuffle, V.shufflePending = true, true
    Request()
end

local function ShuffleEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(S.Text("Shuffle displayed items"))
    GameTooltip:AddLine(S.Text("Changes display order without moving items between slots."), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

-- Footer controls stand on Blizzard's money row, which moves up when tracked
-- currencies are shown (ContainerFrameTokenWatcherMixin:UpdateCurrencyFrames).
local function MakeFooter(frame)
    local money = frame.MoneyFrame
    V.previous = Button(V.chrome, "Previous", 72, function() MoveScroll(-V.visibleRows) end)
    V.next = Button(V.chrome, "Next", 72, function() MoveScroll(V.visibleRows) end)
    V.previous:SetPoint("BOTTOMLEFT", money, "TOPLEFT", 4, 13)
    V.next:SetPoint("LEFT", V.previous, "RIGHT", 6, 0)
    V.position = Font(V.chrome, 11)
    V.position:SetPoint("LEFT", V.next, "RIGHT", 8, 0)
    V.manage = Button(V.chrome, "Edit categories", 108, P.InventoryEditor.Show)
    V.manage:SetPoint("BOTTOMRIGHT", money, "TOPRIGHT", -4, 13)
    V.shuffleButton = Button(V.chrome, "", 24, ShuffleItems)
    V.shuffleButton:SetPoint("RIGHT", V.manage, "LEFT", -5, 0)
    V.shuffleButton:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
    V.shuffleButton:SetScript("OnEnter", ShuffleEnter)
    V.shuffleButton:SetScript("OnLeave", GameTooltip_Hide)
end

local function MakeControls()
    local frame = V.frame
    V.chrome = S.CreateFrame("Frame", nil, frame)
    V.chrome:SetAllPoints(frame)
    V.chrome:SetFrameLevel(frame:GetFrameLevel() + 15)
    local titles = { "All items", "By bag", "Categories" }
    for i = 1, 3 do
        local button = Button(V.chrome, titles[i], 100, ViewSelected)
        button.view = i
        button:SetPoint("TOPLEFT", 12 + (i - 1) * 104, -62)
    end
    MakeFooter(frame)
    V.sidebar = S.CreateFrame("ScrollFrame", nil, V.chrome, "UIPanelScrollFrameTemplate")
    V.sidebar:SetPoint("TOPLEFT", 12, -TOP)
    V.sidebar:SetPoint("BOTTOMLEFT", V.previous, "TOPLEFT", -4, 8)
    V.sidebar:SetWidth(142)
    V.sidebarChild = S.CreateFrame("Frame", nil, V.sidebar)
    V.sidebarChild:SetSize(140, 30)
    V.sidebar:SetScrollChild(V.sidebarChild)
    V.clearRecent = Button(V.chrome, "Clear recent items", 136, function()
        Index.ClearRecent(Index.Recent())
        Request()
    end)
    V.clearRecent:SetPoint("TOPRIGHT", -12, -62)
    V.nativeMouseWheel = frame:IsMouseWheelEnabled()
    frame:EnableMouseWheel(true)
    frame:HookScript("OnMouseWheel", function(_, delta)
        if V.active then MoveScroll(-delta * 3) end
    end)
end

local function RenderSidebar()
    for i = 1, #V.buttons do V.buttons[i]:Hide() end
    local n = 1
    CategoryButton("all", ALL, nil, n)
    local state = State()
    if M.config.showPinned and not V.model.groupsByKey.pinned then
        n = n + 1
        CategoryButton("pinned", PINNED, 0, n)
    end
    for i = 1, #V.model.groups do
        local group = V.model.groups[i]
        if group.key ~= "all" then
            n = n + 1
            CategoryButton(group.key, group, #group.rows, n)
        end
    end
    V.sidebarChild:SetHeight(n * 25)
    V.clearRecent:SetShown(M.config.showRecent and state ~= nil)
end

-- The Suite footer line of Finance.lua follows the chrome.
-- Finance.lua reads its currencies when its line changes visibility only.
local function ShowChrome(shown)
    if V.chrome then V.chrome:SetShown(shown) end
    if V.chromeShown == shown then return end
    V.chromeShown = shown
    P.BagFinance.Refresh()
end

function V.SuiteLayout()
    return V.active == true and V.layout == "suite"
end

-- The combat layout left room for the Finance.lua footer line.
function V.CombatLine()
    return V.active == true and V.layout == "combat" and V.combatLine == true
end

-- Hiding the item button that owns Blizzard's stack split window would run
-- its OnHide (StackSplitFrame:Hide()) from Suite code: the Suite grid waits
-- until the split window closes. The combat layout hides no button.
local function SplitOwnerShown()
    return StackSplitFrame:IsShown() and V.visibleButtons[StackSplitFrame.owner] == true
end

local function SplitClosed()
    if not V.splitPending then return end
    V.splitPending = false
    Request()
end

-- Item tooltip post-calls survive Blizzard's 0.2 s tooltip rebuild
-- (see InventoryDetails.lua).
local function StackTooltip(tooltip)
    if not V.SuiteLayout() or tooltip ~= GameTooltip then return end
    local slot = V.slotState[tooltip:GetOwner()]
    local row = slot and slot.row
    if not row or row.stacks < 2 then return end
    tooltip:AddLine(string.format(S.Text("Combined: %d items in %d stacks"), row.count, row.stacks), 0.8, 0.8, 0.8)
    tooltip:AddLine(string.format(S.Text("This slot contains %d; clicking uses this physical stack."),
        row.item.count), 0.8, 0.8, 0.8, true)
end
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, StackTooltip)

local function PlaceSlot(button, x, y, row)
    local slot = V.slotState[button]
    if not slot then
        slot = {}
        V.slotState[button] = slot
    end
    if V.positionsDirty or slot.x ~= x or slot.y ~= y then
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", V.frame, "TOPLEFT", x, y)
        slot.x, slot.y = x, y
    end
    slot.row, V.visibleButtons[button] = row, true
    if not button:IsShown() then button:Show() end
end

-- Blizzard's SetItemButtonCount hides counts of one and shows "*" above its
-- maximum; a merged total must be shown even where the shown stack holds one.
local function SetCount(button, count)
    local text = button.Count
    if not text then return end
    local saved = V.nativeCountFonts[text]
    if not saved then
        saved = { text:GetFont() }
        V.nativeCountFonts[text] = saved
    end
    local path = Grid.FontPath()
    if saved.path ~= path or saved.size ~= M.config.itemCountSize then
        S.SetFont(text, path, M.config.itemCountSize, "OUTLINE")
        saved.path, saved.size = path, M.config.itemCountSize
    end
    if count > 1 then
        text:SetText(tostring(GetFormattedItemQuantity(count, button.maxDisplayCount)))
        text:Show()
    else
        text:Hide()
    end
end

local function PaintSlot(item, x, y, row, count)
    local button = item.button
    PlaceSlot(button, x, y, row)
    SetCount(button, count)
    local junk = M.config.desaturateJunk and item.quality == 0
    SetItemButtonDesaturated(button, item.locked or junk or false)
    P.InventoryDetails.Paint(button, item)
end

local function PaintCell(cell, top, sidebar, columns)
    local row, group = cell.row, cell.group
    local y = -TOP - (cell.line - top) * CELL
    if row then
        PaintSlot(row.item, sidebar + cell.column * CELL, y, row, row.count)
    else
        V.labelCount = V.labelCount + 1
        Grid.PaintHeader(V.labels, V.labelCount, V.chrome, V.frame, sidebar + cell.column * CELL, y - 10,
            (cell.width or columns) * CELL - 5, group)
    end
end

------------------------------------------------------------------ geometry
-- Space from the window's bottom edge to the top of the screen, in the
-- window's own units. The window grows upward from Blizzard's anchor
-- (CONTAINER_OFFSET_Y above the screen bottom) or from its custom position.
local function Available()
    local frame = V.frame
    local bottom, top = frame:GetBottom(), UIParent:GetTop()
    local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if S.Finite(bottom) and S.Finite(top) and S.Finite(scale) and S.Finite(parentScale) and scale > 0 then
        return top * parentScale / scale - bottom
    end
    return (UIParent:GetHeight() - CONTAINER_OFFSET_Y) / frame:GetScale()
end

-- Height of Blizzard's money row above the window bottom, tracked currency
-- rows included.
local function MoneyTop()
    local top, bottom = V.frame.MoneyFrame:GetTop(), V.frame:GetBottom()
    if S.Finite(top) and S.Finite(bottom) and top > bottom then return top - bottom end
    return 24
end

-- Blizzard scaled its bags for its own window size: lay them out again for
-- the Suite size (Bags.lua reapplies the Suite scale and position after it).
local function SetWindowSize(width, height)
    local frame = V.frame
    if frame:GetWidth() == width and frame:GetHeight() == height then return end
    frame:SetSize(width, height)
    M:RefreshWindowLayout()
end

local function ClearVisible()
    for button in pairs(V.visibleButtons) do V.visibleButtons[button] = nil end
    for i = 1, #V.labels do V.labels[i]:Hide() end
    V.labelCount = 0
end

local function HideUnplaced()
    for i = 1, #V.index.items do
        local button = V.index.items[i].button
        if not V.visibleButtons[button] and button:IsShown() then button:Hide() end
    end
    V.positionsDirty = false
end

local function RenderSuite()
    local c = M.config
    local columns = c.inventoryColumns
    local sidebar = c.inventoryView == 3 and 178 or 12
    local layout = Model.Layout(V.model, columns, c.compactGroups)
    local bottom = MoneyTop() + FOOTER
    local visibleRows = max(2, min(c.inventoryRows, floor((Available() - TOP - bottom) / CELL)))
    if c.autoSizeWindow then visibleRows = max(2, min(visibleRows, V.model.lineCount)) end
    V.visibleRows, V.maxScroll = visibleRows, max(0, V.model.lineCount - visibleRows)
    V.scroll = min(V.scroll, V.maxScroll)
    ClearVisible()
    for i = 1, #layout do
        local cell = layout[i]
        if cell.line >= V.scroll and cell.line < V.scroll + visibleRows then
            PaintCell(cell, V.scroll, sidebar, columns)
        end
    end
    HideUnplaced()
    V.layout = "suite"
    ShowChrome(true)
    V.sidebar:SetShown(c.inventoryView == 3)
    V.shuffleButton:SetShown(c.inventoryView == 1)
    V.previous:SetEnabled(V.scroll > 0)
    V.next:SetEnabled(V.scroll < V.maxScroll)
    Grid.PositionText(V.position, V.scroll, visibleRows, V.model.lineCount)
    SetWindowSize(max(500, sidebar + columns * CELL + 12), visibleRows * CELL + TOP + bottom)
end

-- Every slot in physical order without pages, groups, merged or hidden
-- stacks, and without the Suite controls; the currency and Gold history
-- line keeps a row below the slots. Laid out at PLAYER_REGEN_DISABLED, the
-- last moment before combat lockdown, so nothing is out of reach while the
-- layout cannot change.
local function RenderCombat()
    local items = V.index.items
    local total = #items
    local line = P.BagFinance.HasLine() and P.BagFinance.LINE or 0
    V.combatLine = line > 0
    local fit = max(1, floor((Available() - COMBAT_TOP - MoneyTop() - 6 - line) / CELL))
    local columns = max(M.config.inventoryColumns, ceil(total / fit))
    ClearVisible()
    for i = 1, total do
        local item = items[i]
        PaintSlot(item, 12 + (i - 1) % columns * CELL, -COMBAT_TOP - floor((i - 1) / columns) * CELL, nil,
            item.count or 0)
    end
    HideUnplaced()
    V.layout = "combat"
    ShowChrome(false)
    P.BagFinance.Refresh()
    SetWindowSize(max(300, columns * CELL + 24),
        max(1, ceil(total / columns)) * CELL + COMBAT_TOP + MoneyTop() + 6 + line)
end

Render = function()
    if not V.active or not V.frame:IsShown() or NS.IsCombatLocked() or V.layout ~= "suite" then return end
    if SplitOwnerShown() then
        V.splitPending = true
        return
    end
    RenderSuite()
end

local function BuildModel(state)
    for i = 1, #V.index.items do
        local item = V.index.items[i]
        if V.shuffle and (V.shufflePending or not item.shuffle) then item.shuffle = math.random() end
        if not V.shuffle then item.shuffle = nil end
    end
    V.shufflePending = false
    V.context.transactions, V.context.shuffle = TransactionOpen(), V.shuffle
    -- Blizzard's search only dims matching buttons; matches on later pages
    -- would stay unseen, so the Suite grid lists the matches alone.
    V.context.searching = V.index.filtered > 0
    V.selected = Grid.Build(Model, V.model, V.index.items, M.config, state, V.context, V.selected)
end

-- event is the client event that asked for this pass, if any.
Flush = function(event)
    V.queued = false
    if not V.active or not M.active or not V.frame:IsShown() then return end
    if NS.IsCombatLocked() then
        -- A bag opened in combat shows Blizzard's own grid; the Suite controls
        -- must not cover its rows. Everything else waits for the combat end.
        if V.layout ~= "combat" then
            V.layout = "native"
            ShowChrome(false)
        end
        return
    end
    local state = State()
    if not state then return end
    Index.ReadContainer(V.index, V.frame, Index.Recent())
    P.InventoryDetails.Index(V.index)
    if NS.InCombat(event) then
        RenderCombat()
        return
    end
    if SplitOwnerShown() then
        V.splitPending = true
        return
    end
    BuildModel(state)
    RenderSuite()
    RenderSidebar()
end

Request = function()
    if not V.active or V.queued or not V.frame:IsShown() then return end
    V.queued = true
    C_Timer.After(0, Flush)
end
V.Request = Request

local RestoreLayout
local function OnEvent(_, event, value, success)
    if not V.active then
        if V.restorePending and event == "PLAYER_REGEN_ENABLED" then RestoreLayout() end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- Sent before InCombatLockdown() turns true: lay out now, not next frame.
        Flush(event)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then V.positionsDirty = true end
    if event == "BAG_UPDATE_DELAYED" or event == "EQUIPMENT_SETS_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        P.InventoryDetails.Invalidate()
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        -- Arriving item data patches the waiting records; no slot is read again.
        if not Index.ItemDataReceived(V.index, value, success) then return end
        Index.Refresh(V.index, value)
    end
    if event == "INVENTORY_SEARCH_UPDATE" then V.scroll = 0 end
    Request()
end

-- Blizzard re-acquires and re-anchors its item buttons; slot order is read again.
local function NativeLayoutChanged()
    V.positionsDirty = true
    Index.Invalidate(V.index)
    Request()
end

local function WindowShown()
    Index.Invalidate(V.index)
    Index.Retry(V.index)
    Request()
end

-- Blizzard lays the bag out again when it opens; until the Suite's own pass
-- (or during combat) its grid is what shows.
local function WindowHidden()
    if not V.active then return end
    V.layout = "native"
    ShowChrome(false)
end

function V.Refresh()
    if not M.active or NS.IsCombatLocked() then return end
    V.frame = M.frame
    -- Blizzard grid: Blizzard's own layout, with the Suite window style and
    -- item levels of Bags.lua.
    if M.config.inventoryView == NS.BagsBlizzardGrid then
        if V.active then V.Release() end
        return
    end
    if not V.chrome then MakeControls() end
    Grid.RefreshFonts()
    V.frame:EnableMouseWheel(true)
    V.active = true
    if not V.events then
        V.events = S.CreateFrame("Frame")
        V.events:SetScript("OnEvent", OnEvent)
    end
    for i = 1, #EVENTS do
        if NS.Client.SupportsEvent(EVENTS[i]) then V.events:RegisterEvent(EVENTS[i]) end
    end
    if not V.hooked then
        hooksecurefunc(V.frame, "UpdateItems", Request)
        hooksecurefunc(V.frame, "UpdateItemLayout", NativeLayoutChanged)
        hooksecurefunc(V.frame, "UpdateFrameSize", Request)
        V.frame:HookScript("OnShow", WindowShown)
        V.frame:HookScript("OnHide", WindowHidden)
        StackSplitFrame:HookScript("OnHide", SplitClosed)
        V.hooked = true
    end
    Request()
end

-- Blizzard's own layout of the combined bag, from the native methods.
RestoreLayout = function()
    V.restorePending = false
    if not V.active then V.events:UnregisterAllEvents() end
    local frame = V.frame
    frame:UpdateItems()
    for _, button in frame:EnumerateValidItems() do button:Show() end
    frame:UpdateItemLayout()
    frame:UpdateFrameSize()
    UpdateContainerFrameAnchors()
end

-- Hands the combined bag back to Blizzard. Count fonts and the mouse wheel
-- return at once (neither is protected); the layout follows when combat ends,
-- also after a module error stopped the view in combat.
function V.Release()
    V.active, V.layout, V.positionsDirty, V.splitPending = false, "native", true, false
    Index.Reset(V.index)
    if V.events then V.events:UnregisterAllEvents() end
    ShowChrome(false)
    P.InventoryEditor.Hide()
    P.InventoryDetails.Hide()
    local frame = V.frame
    if not frame or not V.chrome then return end
    frame:EnableMouseWheel(V.nativeMouseWheel)
    for label, font in pairs(V.nativeCountFonts) do
        if font[1] then label:SetFont(unpack(font)) end
        V.nativeCountFonts[label] = nil
    end
    if NS.IsCombatLocked() then
        V.restorePending = true
        V.events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    RestoreLayout()
end

function V.Disable()
    V.Release()
end

hooksecurefunc(M, "Refresh", V.Refresh)
hooksecurefunc(M, "Disable", V.Disable)
