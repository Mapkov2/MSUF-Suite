local _, NS = ...
local bounds = NS.Host.CharacterTabs.PositionBounds
local CARD_INSET, ROW_INSET = bounds.card.x, bounds.row.x
local VERTICAL_INSET = bounds.card.y + bounds.row.y
local ceil, floor, max, min = math.ceil, math.floor, math.max, math.min
local GROUP_HEADER, GROUP_ROW, GROUP_GAP = 30, 24, 8
local VALUE_SIZE, BAR_INSET, BAR_BOTTOM, TEXT_GAP = 11, 10, 2, 4
local CreateFrame, CreateTexture = NS.Suite.CreateFrame, NS.Suite.CreateTexture
local Number, ReadText = NS.Number, NS.String
local SCROLL_WIDTH, TRACK_WIDTH, TRACK_INSET, MIN_THUMB = 16, 8, 19, 23
local WHEEL_ROWS, PAGE_FRACTION = 2, .95
local STEP_DELAY, STEP_INTERVAL = .5, .1
local Layout = { HeaderHeight = GROUP_HEADER, Gap = GROUP_GAP, ValueSize = VALUE_SIZE }
NS.GroupLayout = Layout

function Layout.Wrap(text)
    text:SetWordWrap(true)
    text:SetNonSpaceWrap(true)
end

local function MeasurementFont(view)
    local font = NS.Suite.CreateFontString(view.frame, nil, "OVERLAY", "GameFontHighlightSmall")
    Layout.Wrap(font)
    font:Hide()
    return font
end

local function TextMetrics(view)
    local metrics = view.reportMetrics
    if not metrics then
        metrics = { left = MeasurementFont(view), right = MeasurementFont(view), revision = 0 }
        view.reportMetrics = metrics
    end
    local scale = max(.25, Number(view.frame:GetEffectiveScale()) or 1)
    local revision, path, readable = view.fontRevision, view.fontPath, view.readableValues
    local fontChanged = metrics.fontRevision ~= revision or metrics.path ~= path or metrics.readable ~= readable
    if fontChanged then
        metrics.fontRevision, metrics.path, metrics.readable = revision, path, readable
        NS.Suite.SetFont(metrics.left, path, VALUE_SIZE, "")
        NS.Suite.SetFont(metrics.right, path, VALUE_SIZE + (readable and 2 or 0), "")
    end
    if fontChanged or metrics.scale ~= scale then
        metrics.scale = scale
        metrics.padding = ceil(2 / min(1, scale))
        metrics.revision = metrics.revision + 1
    end
    return metrics
end

local function NeededWidth(font, text, padding)
    if not text then return 0 end
    return ceil(Number(font:GetUnboundedStringWidthForText(text)) or 0) + padding
end

local function WrappedHeight(font, text, width, needed)
    if needed <= width and (not text or not text:find("\n", 1, true)) then return 0 end
    font:SetWidth(width)
    font:SetText(text)
    return ceil(Number(font:GetStringHeight()) or 0)
end

local function MeasureRow(geometry, values, width, metrics, barSpace, force)
    local label = ReadText(values.label)
    -- Restricted stats are sent only to the visible row's native formatter.
    local value = not values.displayFormat and ReadText(values.value) or nil
    if not force and geometry.label == label and geometry.value == value and geometry.barSpace == barSpace then return end
    geometry.label, geometry.value, geometry.barSpace = label, value, barSpace

    local available = width - 2 * BAR_INSET - TEXT_GAP
    local leftWidth = min(available - 1, floor(width / 2 + 8))
    local rightNeeded = NeededWidth(metrics.right, value, metrics.padding)
    local leftNeeded = NeededWidth(metrics.left, label, metrics.padding)
    if rightNeeded > available - leftWidth then
        local minLabel = min(leftWidth, max(floor(available / 3), leftNeeded))
        leftWidth = max(minLabel, min(leftWidth, available - rightNeeded))
    end
    local leftHeight = WrappedHeight(metrics.left, label, leftWidth, leftNeeded)
    local rightHeight = WrappedHeight(metrics.right, value, available - leftWidth, rightNeeded)
    geometry.split = BAR_INSET + leftWidth
    geometry.height = max(GROUP_ROW, max(leftHeight, rightHeight) + 6 + barSpace)
end

local function LayoutRows(list, rowLayout, rows, metrics)
    local width, top = list.rowWidth, GROUP_HEADER
    local force = rowLayout.width ~= width or rowLayout.revision ~= metrics.revision
    rowLayout.width, rowLayout.revision = width, metrics.revision
    for i, values in ipairs(rows) do
        local geometry = rowLayout[i]
        if not geometry then
            geometry = {}
            rowLayout[i] = geometry
        end
        local barSpace = values.reputationFill ~= nil and (list.view.reputationHeight + BAR_BOTTOM) or 0
        MeasureRow(geometry, values, width, metrics, barSpace, force)
        geometry.top = top
        top = top + geometry.height
    end
    return top + 5
end

-- Offsets do not reflow the authored grid. Extra reach is reserved only for
-- custom pages so both native scrolling and the full signed move range work.
local function Build(list, groups)
    local movable = groups[1] and groups[1].layout ~= nil
    local cardInset, rowInset = movable and CARD_INSET or 0, movable and ROW_INSET or 0
    local vertical = movable and VERTICAL_INSET or 0
    list.groups = groups
    if list.cardInset ~= cardInset then
        list.cardInset, list.rowInset = cardInset, rowInset
        list.cardWidth = (list.width - 2 * cardInset - (list.columns - 1) * GROUP_GAP) / list.columns
        list.rowWidth = list.cardWidth - 2 * rowInset
    end
    local top, tallest = vertical, 0
    local above, below = 0, 0
    local metrics = groups[1] and TextMetrics(list.view)
    for i = 1, #groups do
        local group = groups[i]
        local rowLayout = list.rowLayouts[i]
        if not rowLayout then
            rowLayout = {}
            list.rowLayouts[i] = rowLayout
        end
        local height = LayoutRows(list, rowLayout, group.rows, metrics)
        local position = group.layout
        if position then
            above = max(above, position.y + position.rowUp)
            below = max(below, -position.y + position.rowDown)
        end
        list.offsets[i], list.heights[i] = top, height
        tallest = max(tallest, height)
        if i % list.columns == 0 or i == #groups then
            top, tallest = top + tallest + GROUP_GAP, 0
        end
    end
    list.above, list.below = above, below
    return max(1, top + vertical - GROUP_GAP)
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

function Layout.FirstRow(rows, count, earliest)
    local low, high = 1, count + 1
    while low < high do
        local middle = floor((low + high) / 2)
        local row = rows[middle]
        if row.top + row.height <= earliest then low = middle + 1 else high = middle end
    end
    return low
end

local function VerticalScroll(scroll, offset)
    local list = scroll.panelList
    if list.content and not list.layingOut and Number(offset) then list.paint(list, offset) end
end

local function MoveCanvas(list, offset)
    offset = max(0, min(list.range, offset))
    if list.offset == offset then return false end
    list.offset = offset
    list.canvas:SetPoint("TOPLEFT", 0, offset)
    return true
end

local function PaintOwnedScroll(list)
    local start = list.range > 0 and list.thumbTravel * list.offset / list.range or 0
    list.thumbStart = start
    list.thumb:SetPoint("TOP", list.track, "TOP", 0, -start)
    list.up:SetAlpha(list.offset > 0 and 1 or .45)
    list.down:SetAlpha(list.offset < list.range and 1 or .45)
end

local function ScrollOwnedList(list, offset)
    if not MoveCanvas(list, offset) then return end
    PaintOwnedScroll(list)
    list.paint(list, list.offset)
    return true
end

local function NewBarArt(frame, top, middle, bottom)
    local start = CreateTexture(frame, nil, "ARTWORK", nil, 1)
    start:SetAtlas(top, true)
    start:SetPoint("TOP")
    local fill = CreateTexture(frame, nil, "ARTWORK")
    fill:SetAtlas(middle)
    local finish = CreateTexture(frame, nil, "ARTWORK", nil, 1)
    finish:SetAtlas(bottom, true)
    finish:SetPoint("BOTTOM")
    fill:SetPoint("TOPLEFT", start, "BOTTOMLEFT")
    fill:SetPoint("BOTTOMRIGHT", finish, "TOPRIGHT")
    return start, fill, finish
end

local function StopUpdate(control)
    control:SetScript("OnUpdate", nil)
end

local function LeftMouseDown()
    local down = IsMouseButtonDown("LeftButton")
    return NS.Public(down) and down
end

local function BindRepeat(control, step)
    local delay
    local function Repeat(self, elapsed)
        if not LeftMouseDown() then return StopUpdate(self) end
        local over = self:IsMouseOver()
        if not NS.Public(over) or not over then return end
        delay = delay - elapsed
        if delay <= 0 then
            step(false)
            delay = STEP_INTERVAL
        end
    end
    control:SetScript("OnMouseDown", function(self, key)
        if ReadText(key) ~= "LeftButton" or not step(true) then return end
        delay = STEP_DELAY
        self:SetScript("OnUpdate", Repeat)
    end)
    control:SetScript("OnMouseUp", function(self, key)
        if ReadText(key) == "LeftButton" then StopUpdate(self) end
    end)
    control:SetScript("OnHide", StopUpdate)
end

local function MakeStepper(list, edge, icon, direction)
    local button = NS.Window.CreateChild(list.view, "Button", list.bar)
    button:SetPoint(edge)
    button:SetSize(17, 11)
    button:SetNormalAtlas(icon)
    button:SetHighlightAtlas(icon .. "-over")
    button:SetPushedAtlas(icon .. "-down")
    BindRepeat(button, function()
        return ScrollOwnedList(list, list.offset + direction * list.scrollStep)
    end)
    return button
end

local function CursorOnTrack(track)
    local _, y = GetCursorPosition()
    local scale, top = Number(track:GetEffectiveScale()), Number(track:GetTop())
    y = Number(y)
    if y and scale and scale > 0 and top then return top - y / scale end
end

local function MakeTrack(list, child)
    local track = child(list.view, "Frame", list.bar)
    track:SetPoint("TOP", 0, -TRACK_INSET)
    track:SetPoint("BOTTOM", 0, TRACK_INSET)
    track:SetWidth(TRACK_WIDTH)
    track:EnableMouse(true)
    NewBarArt(track, "minimal-scrollbar-track-top", "!minimal-scrollbar-track-middle", "minimal-scrollbar-track-bottom")

    local direction
    BindRepeat(track, function(first)
        local cursor = CursorOnTrack(track)
        if not cursor or list.range == 0 then return end
        local side = 0
        if cursor < list.thumbStart then
            side = -1
        elseif cursor > list.thumbStart + list.thumbHeight then
            side = 1
        end
        if first then direction = side end
        if side == 0 or side ~= direction then return end
        return ScrollOwnedList(list, list.offset + direction * list.height * PAGE_FRACTION)
    end)
    return track
end

local function MakeThumb(list, child)
    local track = list.track
    local thumb = child(list.view, "Button", track)
    thumb:SetPoint("TOP")
    thumb:SetSize(TRACK_WIDTH, MIN_THUMB)
    thumb:SetHitRectInsets(-4, -4, -4, -4)
    thumb:EnableMouse(true)
    local prefix = "minimal-scrollbar-small-thumb-"
    local start, fill, finish = NewBarArt(thumb, prefix .. "top", prefix .. "middle", prefix .. "bottom")

    local grab, hover
    local function ShowState()
        local suffix = grab and "-down" or hover and "-over" or ""
        start:SetAtlas(prefix .. "top" .. suffix, true)
        fill:SetAtlas(prefix .. "middle" .. suffix)
        finish:SetAtlas(prefix .. "bottom" .. suffix, true)
    end
    local function Stop(self)
        grab = nil
        StopUpdate(self)
        ShowState()
    end
    local function Drag(self)
        if not LeftMouseDown() then return Stop(self) end
        local cursor = CursorOnTrack(track)
        if cursor and list.thumbTravel > 0 then
            ScrollOwnedList(list, (cursor - grab) * list.range / list.thumbTravel)
        end
    end
    thumb:SetScript("OnEnter", function()
        hover = true
        ShowState()
    end)
    thumb:SetScript("OnLeave", function()
        hover = false
        ShowState()
    end)
    thumb:SetScript("OnMouseDown", function(self, key)
        if ReadText(key) ~= "LeftButton" or list.thumbTravel <= 0 then return end
        local cursor = CursorOnTrack(track)
        if not cursor then return end
        grab = cursor - list.thumbStart
        ShowState()
        self:SetScript("OnUpdate", Drag)
    end)
    thumb:SetScript("OnMouseUp", function(self, key)
        if ReadText(key) == "LeftButton" then Stop(self) end
    end)
    thumb:SetScript("OnHide", function(self)
        hover = false
        Stop(self)
    end)
    return thumb
end

-- Blizzard's SettingsList uses MinimalScrollBar. Keep its art and controls
-- on Suite frames so native scroll scripts never read hosted secret ranges.
local function MakeOwnedScroll(list)
    local view, width, height = list.view, list.width, list.height
    local child = NS.Window.CreateChild
    local scroll = child(view, "Frame", list.parent)
    scroll:SetPoint("TOPLEFT")
    scroll:SetSize(width + SCROLL_WIDTH, height)

    local viewport = child(view, "Frame", scroll)
    viewport:SetPoint("TOPLEFT")
    viewport:SetSize(width, height)
    viewport:SetClipsChildren(true)
    local canvas = child(view, "Frame", viewport)
    canvas:SetPoint("TOPLEFT")
    canvas:SetSize(width, 1)

    local bar = child(view, "Frame", scroll)
    bar:SetPoint("TOPRIGHT")
    bar:SetSize(SCROLL_WIDTH, height)
    list.scroll, list.canvas, list.bar = scroll, canvas, bar
    list.offset, list.range, list.thumbTravel = 0, 0, 0
    list.scrollStep = GROUP_ROW
    list.track = MakeTrack(list, child)
    list.thumb = MakeThumb(list, child)
    list.up = MakeStepper(list, "TOP", "minimal-scrollbar-arrow-top", -1)
    list.down = MakeStepper(list, "BOTTOM", "minimal-scrollbar-arrow-bottom", 1)
    bar:Hide()

    local function Wheel(_, delta)
        delta = Number(delta)
        if delta then ScrollOwnedList(list, list.offset - delta * WHEEL_ROWS * list.scrollStep) end
    end
    for _, target in ipairs({ scroll, list.track, list.thumb }) do
        target:EnableMouseWheel(true)
        target:SetScript("OnMouseWheel", Wheel)
    end
end

function Layout.NewList(view, parent, width, height, columns, paint, fixed)
    local list = {
        view = view, parent = parent, groups = {}, paint = paint,
        columns = columns, height = height, width = width - SCROLL_WIDTH, cards = {}, offsets = {}, heights = {}, rowLayouts = {},
    }
    if not fixed and view.nativeRoot and NS.Host.Client.isForever then
        MakeOwnedScroll(list)
        return list
    end
    if fixed then
        local canvas = NS.Window.CreateChild(view, "Frame", parent)
        canvas:SetPoint("TOPLEFT")
        canvas:SetSize(list.width, height)
        canvas:SetClipsChildren(true)
        list.canvas = canvas
    else
        local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT")
        scroll:SetSize(list.width, height)
        local canvas = CreateFrame("Frame", nil, scroll)
        canvas:SetSize(list.width, 1)
        scroll:SetScrollChild(canvas)
        list.scroll, list.canvas = scroll, canvas
        scroll.panelList = list
        scroll:HookScript("OnVerticalScroll", VerticalScroll)
    end
    return list
end

function Layout.PositionValueText(row, lift, split)
    split = split or row.textSplit
    if row.textLift == lift and row.textSplit == split then return end
    row.textLift, row.textSplit = lift, split
    row.left:SetPoint("LEFT", BAR_INSET, lift)
    row.left:SetPoint("RIGHT", row, "LEFT", split, lift)
    row.right:SetPoint("LEFT", row, "LEFT", split + TEXT_GAP, lift)
    row.right:SetPoint("RIGHT", -BAR_INSET, lift)
end

local function NewReputationBar(row)
    local track = CreateTexture(row, nil, "ARTWORK", nil, -1)
    track:SetPoint("BOTTOMLEFT", BAR_INSET, BAR_BOTTOM)
    track:SetPoint("BOTTOMRIGHT", -BAR_INSET, BAR_BOTTOM)
    track:SetColorTexture(0, 0, 0, .4)
    local fill = CreateTexture(row, nil, "ARTWORK")
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    row.reputationTrack, row.reputationBar = track, fill
    return track, fill
end

function Layout.PaintReputationBar(row, progress, reaction)
    local track, fill = row.reputationTrack, row.reputationBar
    if progress == nil or row.panelWidth <= 2 * BAR_INSET then
        if row.reputationProgress ~= nil then
            track:Hide()
            if fill.reputationShown then fill:Hide() end
            fill.reputationShown, row.reputationProgress, row.reputationReaction = false, nil, nil
            Layout.PositionValueText(row, 0)
        end
        return
    end

    local shown = row.reputationProgress ~= nil
    row.reputationProgress, row.reputationReaction = progress, reaction
    if not track then track, fill = NewReputationBar(row) end
    local height = row.view.reputationHeight
    if track.reputationHeight ~= height then
        track.reputationHeight = height
        track:SetHeight(height)
    end
    Layout.PositionValueText(row, (height + BAR_BOTTOM) / 2)
    if not shown then track:Show() end

    local filled = progress > 0
    if fill.reputationShown ~= filled then
        fill.reputationShown = filled
        fill:SetShown(filled)
    end
    if not filled then return end
    local width = (row.panelWidth - 2 * BAR_INSET) * progress
    if fill.reputationWidth ~= width then
        fill.reputationWidth = width
        fill:SetWidth(width)
    end
    local r, g, b = unpack(row.view.reputationPalette[reaction or 0])
    if fill.reputationR ~= r or fill.reputationG ~= g or fill.reputationB ~= b then
        fill.reputationR, fill.reputationG, fill.reputationB = r, g, b
        fill:SetColorTexture(r, g, b, .9)
    end
end

function Layout.SetReputationStyle(view, config, accent)
    local height = min(8, max(2, config.reputationBarHeight or 3))
    local palette = view.reputationPalette
    if not palette then
        palette = {}
        view.reputationPalette = palette
    end
    local changed = NS.Suite.CharacterHeader.UpdateReputationColors(palette, config, unpack(accent))
    if view.reputationHeight == height and not changed then return end
    view.reputationHeight = height

    local report = view.combatReport and view.combatReport.canvas.panelShown and view.combatReport or view.report
    if not report then return end
    for _, card in ipairs(report.cards) do
        if not card.panelShown then break end
        for _, row in ipairs(card.rows) do
            if not row.panelShown then break end
            if row.reputationProgress ~= nil then
                Layout.PaintReputationBar(row, row.reputationProgress, row.reputationReaction)
            end
        end
    end
end

local function UpdateOwnedScroll(list, content, reset)
    if list.content ~= content then
        list.content = content
        list.canvas:SetHeight(content)
    end
    local range = max(0, content - list.height)
    local rangeChanged = list.range ~= range
    list.range = range
    local moved = MoveCanvas(list, reset and 0 or list.offset)
    if rangeChanged then
        if range > 0 then
            local trackHeight = max(0, list.height - 2 * TRACK_INSET)
            list.thumbHeight = min(trackHeight, max(MIN_THUMB, trackHeight * list.height / content))
            list.thumbTravel = trackHeight - list.thumbHeight
            list.thumb:SetHeight(list.thumbHeight)
        else
            list.thumbTravel = 0
        end
        list.bar:SetShown(range > 0)
    end
    if moved or rangeChanged then PaintOwnedScroll(list) end
    return list.offset
end

function Layout.UpdateScroll(list, content, reset)
    if list.track then return UpdateOwnedScroll(list, content, reset) end
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

function Layout.Paint(list, groups, reset)
    local content = Build(list, groups)
    list.paint(list, Layout.UpdateScroll(list, content, reset))
end

local function NewFixedList(list)
    return Layout.NewList(list.view, list.parent, list.width + SCROLL_WIDTH, list.height, 1, list.paint, true)
end

function Layout.ShowList(list, fixed, groups, reset, combat, show, setStyle)
    local view = list.view
    if setStyle and (view.setManager or view.setPane and view.setPane.panelShown) then
        return NS.GearSetsView.ShowList(list, fixed, groups, reset, combat, setStyle)
    end
    if combat then
        -- The native scroll template recalculates the protected range in its scripts.
        show(list.scroll, false)
        fixed = fixed or NewFixedList(list)
        Layout.Paint(fixed, groups, false)
        show(fixed.canvas, true)
    else
        if not fixed and setStyle and view.unit == "player" and not view.embedded then fixed = NewFixedList(list) end
        if fixed then show(fixed.canvas, false) end
        Layout.Paint(list, groups, reset)
        show(list.scroll, true)
    end
    return fixed
end

function Layout.Refresh(view)
    if view.embedded or view:IsMinimized() or not view.frame:IsShown() then return end
    local list, fixed
    if view.gear and view.gear.panelShown then
        list, fixed = view.rail, view.combatRail
    else
        list = view.setReport and view.setReport.scroll.panelShown and view.setReport or view.report
        fixed = view.combatReport
    end
    if fixed and fixed.canvas.panelShown then
        Layout.Paint(fixed, fixed.groups, false)
    elseif list and list.scroll.panelShown then
        Layout.Paint(list, list.groups, false)
    end
end
