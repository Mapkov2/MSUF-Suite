local _, NS = ...
local bounds = NS.Host.CharacterTabs.PositionBounds
local CARD_INSET, ROW_INSET = bounds.card.x, bounds.row.x
local VERTICAL_INSET = bounds.card.y + bounds.row.y
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min
local Layout = {}
NS.GroupLayout = Layout

-- Offsets do not reflow the authored grid. Extra reach is reserved only for
-- custom pages so both native scrolling and the full signed move range work.
function Layout.Build(list, groups, headerHeight, rowHeight, gap)
    local movable = groups[1] and groups[1].layout ~= nil
    local cardInset, rowInset = movable and CARD_INSET or 0, movable and ROW_INSET or 0
    local vertical = movable and VERTICAL_INSET or 0
    list.groups = groups
    if list.cardInset ~= cardInset then
        list.cardInset, list.rowInset = cardInset, rowInset
        list.cardWidth = (list.width - 2 * cardInset - (list.columns - 1) * gap) / list.columns
        list.rowWidth = list.cardWidth - 2 * rowInset
    end
    local top, tallest = vertical, 0
    local above, below = 0, 0
    for i = 1, #groups do
        local group = groups[i]
        local height = headerHeight + #group.rows * rowHeight + 5
        local position = group.layout
        if position then
            above = max(above, position.y + position.rowUp)
            below = max(below, -position.y + position.rowDown)
        end
        list.offsets[i], list.heights[i] = top, height
        tallest = max(tallest, height)
        if i % list.columns == 0 or i == #groups then
            top, tallest = top + tallest + gap, 0
        end
    end
    list.above, list.below = above, below
    return max(1, top + vertical - gap)
end

-- Binary search remains on unshifted row origins. A card moved down from a
-- preceding row can still intersect the viewport and needs to be considered.
function Layout.FirstCard(list, offset)
    local low, high = 1, ceil(#list.groups / list.columns)
    local earliest = offset - list.below
    while low < high do
        local middle = floor((low + high + 1) / 2)
        local index = (middle - 1) * list.columns + 1
        if list.offsets[index] <= earliest then low = middle else high = middle - 1 end
    end
    return (low - 1) * list.columns + 1
end

local CreateFrame = NS.Suite.CreateFrame
local Number = NS.Number

local function VerticalScroll(scroll, offset)
    local list = scroll.panelList
    if list.content and not list.layingOut and Number(offset) then list.paint(list, offset) end
end

function Layout.NewList(view, parent, width, height, columns, paint, fixed)
    local scroll, canvas
    if fixed then
        canvas = NS.Window.CreateChild(view, "Frame", parent)
        canvas:SetPoint("TOPLEFT")
        canvas:SetSize(width - 16, height)
        canvas:SetClipsChildren(true)
    else
        scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT")
        scroll:SetSize(width - 16, height)
        canvas = CreateFrame("Frame", nil, scroll)
        canvas:SetSize(width - 16, 1)
        scroll:SetScrollChild(canvas)
    end
    local list = {
        view = view, scroll = scroll, canvas = canvas, groups = {}, paint = paint,
        columns = columns, height = height, width = width - 16, cards = {}, offsets = {}, heights = {},
    }
    if scroll then
        scroll.panelList = list
        scroll:HookScript("OnVerticalScroll", VerticalScroll)
    end
    return list
end

function Layout.UpdateScroll(list, content, reset)
    local scroll = list.scroll
    if not scroll then return 0 end
    local oldOffset = Number(scroll:GetVerticalScroll())
    if not oldOffset or not Number(scroll:GetVerticalScrollRange()) then return oldOffset or 0 end
    list.layingOut = true
    if list.content ~= content then
        list.content = content
        list.canvas:SetHeight(content)
    end
    local offset = reset and 0 or min(oldOffset, max(0, content - list.height))
    if offset ~= oldOffset and Number(scroll:GetVerticalScrollRange()) then scroll:SetVerticalScroll(offset) end
    list.layingOut = false
    return offset
end
