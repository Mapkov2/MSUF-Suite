local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Grid, Model, Index = P.GridView, P.InventoryModel, P.InventoryIndex
local Font, Button, VIEW = Grid.Font, Grid.Button, NS.BagsView
local ALL, PINNED = { label = "All items", translate = true }, { label = "Pinned items", translate = true }
local Controls = {}
P.InventoryControls = Controls
local InventoryView
local function State() return InventoryView.State() end
local function Request() InventoryView.Request() end
local function MoveScroll(delta) InventoryView.MoveScroll(delta) end

local function SelectCategory(button, mouseButton)
    if mouseButton == "RightButton" then
        if button.categoryKey == "pinned" then
            P.InventoryEditor.ShowPinned()
        else
            P.InventoryEditor.Show()
        end
        return
    end
    if not P.BagLayout.CanRender() or InventoryView.selected == button.categoryKey then return end
    InventoryView.categoryTransitionPending = true
    InventoryView.selected, InventoryView.scroll = button.categoryKey, 0
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
        local number = InventoryView.model.customIndex[button.categoryKey]
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
    if button.categoryKey == "myArmorSlot" then
        GameTooltip:AddLine(S.Text("Your preferred armor type, usable weapons and wearable accessories."), 0.8, 0.8, 0.8, true)
    end
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
    local button = InventoryView.buttons[order]
    if not button then
        button = Button(InventoryView.sidebarChild, "", 140, SelectCategory)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnReceiveDrag", DropCategory)
        button:HookScript("OnEnter", CategoryEnter)
        button:HookScript("OnLeave", GameTooltip_Hide)
        button.bagNavigation = true
        button:SetFrameLevel(InventoryView.sidebarChild:GetFrameLevel() + 1)
        InventoryView.buttons[order] = button
    end
    local panel = P.BagPresentation.IsPanel(M.config)
    button.bagRail = panel
    button:SetWidth(panel and 88 or 140)
    button.categoryKey = key
    local label = Grid.GroupLabel(group)
    button:SetText(count and Grid.CountLabel(label, count) or label)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", 0, -(order - 1) * 25)
    P.BagAppearance.Button(button, InventoryView.selected == key or key == "all" and not InventoryView.selected)
    button:Show()
    return button
end

-- A header click in the Categories view: collapse or expand its group. The
-- collapsed set belongs to the profile (Index.State).
function Controls.ToggleGroup(key)
    if not P.BagLayout.CanRender() then return end
    local state = State()
    if state and Model.ToggleCollapsed(state.collapsed, key, InventoryView.model.groupsByKey) then Request() end
end

local function ViewSelected(button)
    if button.view == M.config.inventoryView or NS.InCombat() then return end
    InventoryView.transitionPending = true
    InventoryView.scroll, InventoryView.selected = 0, "all"
    if not S.Set("bags", "inventoryView", button.view) then
        InventoryView.transitionPending = false
        P.BagMotion.StopAll()
    end
end

local function ViewTip(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if button.view == VIEW.CATEGORIES then
        GameTooltip:SetText(S.Text("Categories"))
        GameTooltip:AddLine(S.Text("Group items into collapsible sections. Use Edit categories to add your own."), .8, .8, .8, true)
    else
        GameTooltip:SetText(S.Text(button.view == VIEW.BY_BAG and "By bag" or "All items"))
        GameTooltip:AddLine(S.Text("Choose Categories to show separate sections for equipment, consumables and other items."), .8, .8, .8, true)
    end
    GameTooltip:Show()
end

-- The click's own arguments (the button) must not reach Editor.Show,
-- whose first argument selects the pinned list.
local function EditCategories()
    P.InventoryEditor.Show()
end

-- Footer controls stand on Blizzard's money row, which moves up when tracked
-- currencies are shown (ContainerFrameTokenWatcherMixin:UpdateCurrencyFrames).
local function MakeFooter(frame)
    local money = frame.MoneyFrame
    InventoryView.previous = Button(InventoryView.chrome, "Previous", 64, function() MoveScroll(-InventoryView.visibleRows) end)
    InventoryView.next = Button(InventoryView.chrome, "Next", 48, function() MoveScroll(InventoryView.visibleRows) end)
    InventoryView.previous:SetPoint("BOTTOMLEFT", money, "TOPLEFT", 4, 13)
    InventoryView.next:SetPoint("LEFT", InventoryView.previous, "RIGHT", 6, 0)
    InventoryView.position = Font(InventoryView.chrome, 11)
    InventoryView.position:SetPoint("LEFT", InventoryView.next, "RIGHT", 8, 0)
    InventoryView.manage = Button(InventoryView.chrome, "Edit categories", 108, EditCategories)
    InventoryView.manage:SetPoint("BOTTOMRIGHT", money, "TOPRIGHT", -4, 13)
    InventoryView.cleanup = Button(InventoryView.chrome, "Clean up bags", 108, function()
        P.InventoryActions.Cleanup()
    end)
    InventoryView.cleanup:SetPoint("RIGHT", InventoryView.manage, "LEFT", -5, 0)
    -- The free slot count takes the room between the page counter and the buttons.
    InventoryView.free = Font(InventoryView.chrome, 11)
    InventoryView.free:SetJustifyH("RIGHT")
    InventoryView.free:SetWordWrap(false)
    InventoryView.free:SetPoint("LEFT", InventoryView.position, "RIGHT", 8, 0)
    InventoryView.free:SetPoint("RIGHT", InventoryView.cleanup, "LEFT", -6, 0)
end

function Controls.Create()
    InventoryView = P.InventoryView
    local frame = InventoryView.frame
    if InventoryView.chrome then InventoryView.chrome:Hide() end
    InventoryView.chrome = P.ChildFrame("Frame", frame)
    InventoryView.chrome:Hide()
    InventoryView.chrome:SetAllPoints(frame)
    InventoryView.chrome:SetFrameLevel(frame:GetFrameLevel() + 15)
    InventoryView.tabs = {}
    -- The Suite views: the first three inventoryView choices.
    local titles = { [VIEW.ALL] = "All items", [VIEW.BY_BAG] = "By bag", [VIEW.CATEGORIES] = "Categories" }
    for view = VIEW.ALL, VIEW.CATEGORIES do
        local button = Button(InventoryView.chrome, titles[view], 88, ViewSelected)
        button.view, button.bagNavigation = view, true
        button:HookScript("OnEnter", ViewTip)
        button:HookScript("OnLeave", GameTooltip_Hide)
        button:SetFrameLevel(InventoryView.chrome:GetFrameLevel() + 1)
        InventoryView.tabs[view] = button
        button:SetPoint("TOPLEFT", 12 + (view - 1) * 92, -62)
    end
    MakeFooter(frame)
    InventoryView.resize = P.BagResize.Create(InventoryView.chrome)
    P.EquippedBags.Create(InventoryView.chrome)
    if P.EquippedBags.frame:GetParent() ~= InventoryView.chrome then P.EquippedBags.frame:SetParent(InventoryView.chrome) end
    InventoryView.equipped = Button(InventoryView.chrome, "Equipped bags", 116, P.EquippedBags.Toggle)
    InventoryView.equipped:SetPoint("TOPRIGHT", -12, -62)
    P.InventorySearch.Create(InventoryView, Request)
    InventoryView.sidebar, InventoryView.sidebarChild = P.BagWidgets.Scroll(InventoryView.chrome, 142)
    InventoryView.sidebar:SetPoint("TOPLEFT", 12, -122)
    InventoryView.sidebar:SetPoint("BOTTOMLEFT", InventoryView.previous, "TOPLEFT", -4, 8)
    InventoryView.clearRecent = Button(InventoryView.chrome, "Clear recent items", 136, function()
        Index.ClearRecent(Index.Recent())
        Request()
    end)
    InventoryView.clearRecent:SetPoint("TOPRIGHT", -136, -62)
    InventoryView.clearRecent:SetWidth(140)
    frame:HookScript("OnMouseWheel", function(_, delta)
        if InventoryView.active then MoveScroll(-delta * 3) end
    end)
    InventoryView.controlsReady = true
    InventoryView.controlPanel, InventoryView.controlTop = nil, nil
end

function Controls.Sidebar()
    local n = 1
    CategoryButton("all", ALL, nil, n)
    local state = State()
    if M.config.showPinned and not InventoryView.model.groupsByKey.pinned then
        n = n + 1
        CategoryButton("pinned", PINNED, 0, n)
    end
    for i = 1, #InventoryView.model.groups do
        local group = InventoryView.model.groups[i]
        if group.key ~= "all" then
            n = n + 1
            CategoryButton(group.key, group, #group.rows, n)
        end
    end
    for i = n + 1, #InventoryView.buttons do InventoryView.buttons[i]:Hide() end
    InventoryView.sidebarChild:SetHeight(n * 25)
    if InventoryView.categoryCount ~= n or InventoryView.sidebar.bagScrollBar.accent ~= M.config.accentColor then
        P.BagWidgets.UpdateScroll(InventoryView.sidebar)
    end
    local selected = 1
    for i = 1, n do
        if InventoryView.buttons[i].categoryKey == InventoryView.selected then selected = i end
    end
    if InventoryView.sidebar:IsShown() then
        P.BagTabSelection.List(InventoryView, InventoryView.sidebarChild, InventoryView.buttons, selected, M.config,
            InventoryView.categoryTransitionPending, InventoryView.categoryCount ~= n)
    else
        P.BagTabSelection.HideList(InventoryView)
    end
    InventoryView.categoryCount, InventoryView.categoryTransitionPending = n, false
    InventoryView.clearRecent:SetShown(M.config.showRecent and state ~= nil)
end

local function Place(button, frame, point, x, y, width, height)
    button:ClearAllPoints()
    button:SetPoint(point, frame, point, x, y)
    button:SetSize(width, height)
end

local function Tools(panel)
    local view, appearance = InventoryView, P.BagAppearance
    appearance.Tool(view.equipped, "Equipped bags", "Interface\\Icons\\INV_Misc_Bag_08", nil, panel)
    appearance.Tool(view.cleanup, "Clean up bags", nil, "bags-button-autosort-up", panel)
    appearance.Tool(view.manage, "Edit categories", "Interface\\Buttons\\UI-OptionsButton", nil, panel)
    appearance.Tool(view.clearRecent, "Clear recent items", "Interface\\Icons\\INV_Misc_PocketWatch_01", nil, panel)
end

local function PanelControls(g)
    local view, frame = InventoryView, InventoryView.frame
    for mode, button in pairs(view.tabs) do
        button.bagRail = true
        Place(button, frame, "TOPLEFT", 8, -100 - (mode - 1) * 34, 96, 28)
    end
    -- Left of the window's caption (BagCaption.lua).
    local right = P.BagCaption.PANEL_TOOLS
    Place(view.equipped, frame, "TOPRIGHT", -right, -16, 24, 24)
    Place(view.cleanup, frame, "TOPRIGHT", -right - 32, -16, 24, 24)
    Place(view.manage, frame, "TOPRIGHT", -right - 64, -16, 24, 24)
    Place(view.clearRecent, frame, "TOPRIGHT", -right - 96, -16, 24, 24)
    view.free:ClearAllPoints()
    view.free:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 12)
    view.free:SetSize(96, 32)
    view.free:SetJustifyH("LEFT")
    view.free:SetWordWrap(true)
    view.position:SetWidth(g.columns * 40 - 52)
    view.position:SetWordWrap(false)
    view.previous:SetText("<")
    view.next:SetText(">")
    view.previous:SetWidth(24)
    view.next:SetWidth(24)
    view.previous:ClearAllPoints()
    view.previous:SetPoint("BOTTOMLEFT", frame.MoneyFrame, "TOPLEFT", g.rail + 4, 13)
    view.sidebar:ClearAllPoints()
    view.sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -224)
    view.sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 94)
    view.sidebar:SetWidth(88)
    view.sidebarChild:SetWidth(88)
    view.smartSearch:ClearAllPoints()
    view.smartSearch:SetPoint("TOPLEFT", frame, "TOPLEFT", g.rail + 20, -58)
    view.smartSearch:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -104, -58)
    view.filterButton:ClearAllPoints()
    view.filterButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -58)
    P.EquippedBags.frame:ClearAllPoints()
    P.EquippedBags.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", g.rail + 12, -92)
    P.EquippedBags.frame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -92)
end

local function WindowControls(g)
    local view, frame = InventoryView, InventoryView.frame
    for mode, button in pairs(view.tabs) do
        button.bagRail = false
        Place(button, frame, "TOPLEFT", 12 + (mode - 1) * 92, -62, 88, 22)
    end
    Place(view.equipped, frame, "TOPRIGHT", -12, -62, 116, 22)
    Place(view.clearRecent, frame, "TOPRIGHT", -136, -62, 140, 22)
    Place(view.manage, frame.MoneyFrame, "BOTTOMRIGHT", -4, 13, 108, 22)
    Place(view.cleanup, view.manage, "TOPLEFT", -113, 0, 108, 22)
    view.free:ClearAllPoints()
    view.free:SetSize(0, 0)
    view.free:SetPoint("LEFT", view.position, "RIGHT", 8, 0)
    view.free:SetPoint("RIGHT", view.cleanup, "LEFT", -6, 0)
    view.free:SetJustifyH("RIGHT")
    view.free:SetWordWrap(false)
    view.position:SetWidth(0)
    view.previous:SetText(S.Text("Previous"))
    view.next:SetText(S.Text("Next"))
    view.previous:SetWidth(64)
    view.next:SetWidth(48)
    view.previous:ClearAllPoints()
    view.previous:SetPoint("BOTTOMLEFT", frame.MoneyFrame, "TOPLEFT", 4, 13)
    view.sidebar:ClearAllPoints()
    view.sidebar:SetPoint("TOPLEFT", 12, -g.top)
    view.sidebar:SetPoint("BOTTOMLEFT", view.previous, "TOPLEFT", -4, 8)
    view.sidebar:SetWidth(142)
    view.sidebarChild:SetWidth(140)
    view.smartSearch:ClearAllPoints()
    view.smartSearch:SetPoint("TOPLEFT", 18, -91)
    view.smartSearch:SetPoint("TOPRIGHT", -104, -91)
    view.filterButton:ClearAllPoints()
    view.filterButton:SetPoint("TOPRIGHT", -12, -91)
    P.EquippedBags.frame:ClearAllPoints()
    P.EquippedBags.frame:SetPoint("TOPLEFT", 12, -118)
    P.EquippedBags.frame:SetPoint("TOPRIGHT", -12, -118)
end

function Controls.Layout(g)
    local view = InventoryView
    P.BagResize.Refresh(view.resize)
    if view.controlPanel == g.panel and view.controlTop == g.top then
        P.BagTabSelection.Refresh(view, M.config)
        return
    end
    view.controlPanel, view.controlTop = g.panel, g.top
    Tools(g.panel)
    P.EquippedBags.Layout(g.panel)
    if g.panel then PanelControls(g) else WindowControls(g) end
    for _, button in pairs(view.tabs) do P.BagAppearance.Button(button, button.view == M.config.inventoryView) end
    P.BagTabSelection.Refresh(view, M.config, true)
end
