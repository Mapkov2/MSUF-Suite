local _, NS = ...
local Position = NS.Host.CharacterTabs.Position
local ceil, min = math.ceil, math.min
local Overflow = {}
NS.TabOverflow = Overflow

function Overflow.Insets(tabs)
    for index = 1, #tabs do
        if tabs[index].custom then
            local bounds = NS.Host.CharacterTabs.PositionBounds.tab
            return bounds.x, bounds.y
        end
    end
    return 0, 0
end

function Overflow.Fit(buttons, count, width)
    for index = 1, count do
        width = width - buttons[index].naturalWidth
        if width < 0 then return index - 1 end
    end
    return count
end

local function PromotedTab(view, tabs, selected, firstHidden)
    if not view.embedded and not view.nativeRoot then return end
    for i = firstHidden, #tabs do
        if tabs[i].custom and tabs[i].id == selected then return i end
    end
end

function Overflow.SelectionMovesTab(view, tabs, selected)
    return view.tab ~= selected and (view.promotedTab or PromotedTab(view, tabs, selected, view.visibleTabs + 1))
end

function Overflow.Layout(view, tabs, selected, style)
    local buttons, count = view.tabButtons, #tabs
    for i = 1, count do
        local button = buttons[i]
        if not button then
            button = style.new(view)
            buttons[i] = button
        end
        local tab = tabs[i]
        button.id = tab.id
        button.offsetX, button.offsetY = Position(tab)
        style.text(button.label, tab.label)
        button.naturalWidth = min(180, ceil(button.label:GetUnboundedStringWidth()) + 22)
    end
    local insetX, insetY = Overflow.Insets(tabs)
    local width, height = view.bodyWidth - 2 * insetX, style.height - 2 * insetY
    local visible, more = Overflow.Fit(buttons, count, width), view.moreTab
    local promoted
    if visible < count then
        if not more then
            more = style.new(view)
            view.moreTab = more
            style.text(more.label, NS.Text("More"))
        end
        local moreWidth = ceil(more.label:GetUnboundedStringWidth()) + 22
        local available = width - moreWidth
        visible = Overflow.Fit(buttons, count, available)
        promoted = PromotedTab(view, tabs, selected, visible + 1)
        if promoted then visible = Overflow.Fit(buttons, visible, available - buttons[promoted].naturalWidth) end
        style.place(more, view.bodyWidth + style.pad - moreWidth, insetY, moreWidth, height)
    end
    if more then style.visible(more, visible + (promoted and 1 or 0) < count) end
    view.visibleTabs, view.promotedTab = visible, promoted
    local x = style.pad + insetX
    for i, button in ipairs(buttons) do
        local shown = i <= visible or i == promoted
        style.visible(button, shown)
        if shown then
            style.place(button, x + button.offsetX, insetY - button.offsetY, button.naturalWidth, height)
            x = x + button.naturalWidth
        end
    end
end

local function Selected(entry)
    return entry.view.tab == entry.id
end

local function Select(entry)
    local view = entry.view
    if not view.frame:IsShown() or view:IsMinimized() or (view.embedded and NS.Host.InCombat()) then return end
    if entry.tabs == view.tabs then view.callbacks.tab(entry.id) end
end

local function Menu(_, root, view)
    local tabs = view.tabs
    for index = view.visibleTabs + 1, #tabs do
        if index ~= view.promotedTab then
            local tab = tabs[index]
            root:CreateRadio(tab.label, Selected, Select, { id = tab.id, tabs = tabs, view = view })
        end
    end
end

function Overflow.Click(button)
    local view = button.view
    if view.embedded and NS.Host.InCombat() then return end
    if button == view.moreTab then NS.Suite.ContextMenu(button, Menu, view)
    else view.callbacks.tab(button.id) end
end
