local _, P = ...
local S = P.Suite
local LAYOUT, PLACEMENT = P.NS.DataTextLayout, P.NS.DataTextPlacement
local Geometry = {}
P.DataTextGeometry = Geometry
local floor, ceil = math.floor, math.ceil
local Snap, Color = P.Appearance.Snap, P.Appearance.Color
local layoutSlots, layoutWidths, layoutLeft = {}, {}, {}

-- The broker width limit of a place, or nil.
local function BrokerLimit(button)
    local extra = button.extra
    return extra and extra.kind == "broker" and extra.maxWidth or nil
end

local function SlotSetting(config, bar, button, index, suffix)
    return config[bar.prefix .. "Slot" .. (button.slot or index) .. suffix]
end

-- Widths of the first count layout slots: equal shares, or (auto layout)
-- text widths scaled to fill the bar.
local function SlotWidths(bar, count, config)
    local style, widths = bar.style, layoutWidths
    local pixel = bar.pixelUnit or 1
    local fit = config[bar.layoutKey] == LAYOUT.FIT
    local configuredWidth = bar.length or Snap(config[bar.widthKey], pixel)
    local inset = not bar.vertical and style.bagBadge and Snap(style.bagBadgeSize + 8, pixel) or 0
    local gaps = (count - 1) * Snap(style.gap, pixel)
    local total = 0
    for i = 1, count do
        local button = layoutSlots[i]
        if fit then
            local demand = ceil(button.label:GetUnboundedStringWidth()) + 2 * style.padding
            if button.extra then demand = demand + P.DataTextSources.IconWidth(button) end
            widths[i] = math.max(44, demand)
        else
            widths[i] = (configuredWidth - inset - gaps) / count
        end
        total = total + widths[i]
    end
    local needed = configuredWidth
    if fit and not config[bar.prefix .. "FullScreen"] then
        needed = Snap(math.min(900, math.max(configuredWidth, total + gaps + inset)), pixel)
    end
    bar.layoutLength = needed
    if bar.vertical then
        bar.frame:SetHeight(needed)
    elseif bar.frame:GetWidth() ~= needed then
        bar.frame:SetWidth(needed)
    end
    local ratio = math.max(0, needed - inset - gaps) / math.max(1, total)
    for i = 1, count do
        widths[i] = widths[i] * ratio
        local limit = BrokerLimit(layoutSlots[i])
        if limit then widths[i] = math.min(widths[i], limit) end
    end
end

-- A centered slot splits the bar into two disjoint regions. Other slots
-- retain their order on either side; the first fill slot uses spare space
-- in its region. Broker limits remain absolute after every redistribution.
local function Segment(bar, first, last, left, right, gap, config)
    if first > last then return end
    local total, fill = 0, nil
    for i = first, last do
        total = total + layoutWidths[i]
        if not fill and SlotSetting(config, bar, layoutSlots[i], i, "Placement") == PLACEMENT.FILL then fill = i end
    end
    local available = math.max(0, right - left - (last - first) * gap)
    if total > available then
        local ratio = available / math.max(1, total)
        for i = first, last do layoutWidths[i] = layoutWidths[i] * ratio end
    elseif fill then
        local width = layoutWidths[fill] + available - total
        local limit = BrokerLimit(layoutSlots[fill])
        layoutWidths[fill] = limit and math.min(width, limit) or width
    end
    for i = first, last do
        layoutLeft[i] = left
        left = left + layoutWidths[i] + gap
    end
end

local function PlaceDivider(bar, index, x, height)
    local style = bar.style
    local divider = bar.dividers[index]
    if not divider then
        divider = S.CreateTexture(bar.visual, nil, "ARTWORK")
        bar.dividers[index] = divider
        Color(divider, style.separatorColor, .8)
    end
    divider:ClearAllPoints()
    local pixel = bar.pixelUnit or 1
    local offset = Snap(x + Snap(style.gap, pixel) / 2, pixel)
    local length = Snap(math.max(6, height - 2 * Snap(style.padding, pixel)), pixel)
    if bar.vertical then
        divider:SetPoint("CENTER", bar.frame, "TOP", 0, -offset)
        divider:SetSize(length, style.separatorSize * pixel)
    else
        divider:SetPoint("CENTER", bar.frame, "LEFT", offset, 0)
        divider:SetSize(style.separatorSize * pixel, length)
    end
    divider:Show()
end

local function PlaceSlot(bar, button, index, config, extra)
    local style, pixel = bar.style, bar.pixelUnit or 1
    local width = layoutWidths[index]
    local height = Snap(config[bar.heightKey], pixel)
    local left, right = Snap(layoutLeft[index], pixel), Snap(layoutLeft[index] + width, pixel)
    local scale = (SlotSetting(config, bar, button, index, "Scale") or 100) / 100
    button:ClearAllPoints()
    if bar.vertical then
        button:SetPoint("TOP", bar.frame, "TOP", 0, -left / scale)
        button:SetSize(height / scale, math.max(0, right - left) / scale)
    else
        button:SetPoint("LEFT", bar.frame, "LEFT", left / scale, 0)
        button:SetSize(math.max(0, right - left) / scale, height / scale)
    end
    local ownPad = SlotSetting(config, bar, button, index, "Padding")
    local inset = Snap(math.max(0, math.min(ownPad or style.padding, floor((width / scale - 4) / 2))), pixel)
    button.labelInset = inset
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", inset, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -inset, 0)
    extra.Paint(button, true)
    return right, height
end

-- Auto-layout bars relayout on value changes, so this allocates nothing.
-- Every frame it moves is an ordinary frame: layout is allowed in combat.
function Geometry.Layout(bar, config, extra)
    local style, slots, widths = bar.style, layoutSlots, layoutWidths
    local pixel = bar.pixelUnit or 1
    local count = 0
    for i = 1, #bar.slots do
        local button = bar.slots[i]
        if button.source then
            count = count + 1
            slots[count] = button
        end
    end
    for _, divider in pairs(bar.dividers) do divider:Hide() end
    if count == 0 then return end
    SlotWidths(bar, count, config)
    local start = not bar.vertical and style.bagBadge and Snap(style.bagBadgeSize + 8, pixel) or 0
    local length = bar.layoutLength or bar.length or bar.frame:GetWidth()
    local gap = Snap(style.gap, pixel)
    local center
    for i = 1, count do
        if SlotSetting(config, bar, slots[i], i, "Placement") == PLACEMENT.CENTER then
            center = i
            break
        end
    end
    if center then
        widths[center] = math.min(widths[center], math.max(0, length - 2 * start))
        local left = (length - widths[center]) / 2
        layoutLeft[center] = left
        Segment(bar, 1, center - 1, start, left - gap, gap, config)
        Segment(bar, center + 1, count, left + widths[center] + gap, length, gap, config)
    else
        Segment(bar, 1, count, start, length, gap, config)
    end
    for i = 1, count do
        local right, height = PlaceSlot(bar, slots[i], i, config, extra)
        if i < count and style.separatorEnabled then PlaceDivider(bar, i, right, height) end
    end
end
