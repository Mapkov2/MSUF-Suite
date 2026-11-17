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

local CreateFrame, CreateTexture = NS.Suite.CreateFrame, NS.Suite.CreateTexture
local Number = NS.Number
local SCROLL_STEP, SCROLL_WIDTH = 30, 16
local STEP_DELAY, STEP_INTERVAL = .3, .06

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

local function PaintSteppers(list)
    list.up:SetAlpha(list.offset > 0 and 1 or .45)
    list.down:SetAlpha(list.offset < list.range and 1 or .45)
end

local function SyncSlider(list, rangeChanged)
    list.layingOut = true
    if rangeChanged then
        list.slider:SetMinMaxValues(0, max(1, list.range))
        list.bar:SetShown(list.range > 0)
    end
    -- Vertical sliders use zero at the top, like Blizzard's scroll frames.
    list.slider:SetValue(list.offset)
    list.layingOut = false
    PaintSteppers(list)
end

local function ScrollOwnedList(list, offset)
    if not MoveCanvas(list, offset) then return end
    SyncSlider(list, false)
    list.paint(list, list.offset)
end

local function StopStepper(button)
    button:SetScript("OnUpdate", nil)
end

local function MakeStepper(view, bar, edge, icon, step)
    local button = NS.Window.CreateChild(view, "Button", bar)
    button:SetPoint(edge)
    button:SetSize(16, 11)
    button:SetNormalAtlas(icon)
    button:SetHighlightAtlas(icon .. "-over")
    button:SetPushedAtlas(icon .. "-down")
    local delay, repeated
    local function Repeat(self, elapsed)
        delay = delay - elapsed
        if delay > 0 then return end
        local over = self:IsMouseOver()
        if not NS.Public(over) or not over then return end
        step()
        delay, repeated = STEP_INTERVAL, true
    end
    button:SetScript("OnMouseDown", function(self, key)
        if not NS.Public(key) or key ~= "LeftButton" then return end
        delay, repeated = STEP_DELAY, false
        self:SetScript("OnUpdate", Repeat)
    end)
    button:SetScript("OnMouseUp", StopStepper)
    button:SetScript("OnHide", StopStepper)
    button:SetScript("OnClick", function()
        if not repeated then step() end
        repeated = false
    end)
    return button
end

-- Forever's ScrollFrameTemplate runs Blizzard's scrollbar update during
-- construction and range changes. Its steppers and thumb reject secret
-- enabled states. Hosted reports use the list's own public pixel offsets.
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
    bar:Hide()
    local slider = child(view, "Slider", bar)
    slider:SetOrientation("VERTICAL")
    slider:EnableMouse(true)
    slider:SetPoint("TOP", 0, -13)
    slider:SetPoint("BOTTOM", 0, 13)
    slider:SetWidth(10)
    slider:SetMinMaxValues(0, 1)
    local track = CreateTexture(slider, nil, "BACKGROUND")
    track:SetAtlas("!minimal-scrollbar-track-middle")
    track:SetAllPoints(slider)
    local thumb = CreateTexture(slider, nil, "ARTWORK")
    thumb:SetAtlas("minimal-scrollbar-small-thumb-middle")
    thumb:SetSize(8, 23)
    slider:SetThumbTexture(thumb)

    list.scroll, list.canvas, list.bar, list.slider = scroll, canvas, bar, slider
    list.offset, list.range = 0, 0
    list.up = MakeStepper(view, bar, "TOP", "minimal-scrollbar-arrow-top", function()
        ScrollOwnedList(list, list.offset - SCROLL_STEP)
    end)
    list.down = MakeStepper(view, bar, "BOTTOM", "minimal-scrollbar-arrow-bottom", function()
        ScrollOwnedList(list, list.offset + SCROLL_STEP)
    end)
    local function Wheel(_, delta)
        delta = Number(delta)
        if delta then ScrollOwnedList(list, list.offset - delta * SCROLL_STEP) end
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", Wheel)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", Wheel)
    slider:SetScript("OnValueChanged", function(_, value)
        if list.layingOut then return end
        value = Number(value)
        if value and MoveCanvas(list, value) then
            PaintSteppers(list)
            list.paint(list, list.offset)
        end
    end)
end

function Layout.NewList(view, parent, width, height, columns, paint, fixed)
    local list = {
        view = view, parent = parent, groups = {}, paint = paint,
        columns = columns, height = height, width = width - SCROLL_WIDTH, cards = {}, offsets = {}, heights = {},
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

local BAR_INSET, BAR_BOTTOM = 10, 2

function Layout.PositionValueText(row, lift)
    if row.textLift == lift then return end
    row.textLift = lift
    row.left:SetPoint("LEFT", BAR_INSET, lift)
    row.left:SetPoint("RIGHT", row, "CENTER", 18, lift)
    row.right:SetPoint("LEFT", row, "CENTER", 20, lift)
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

local function BarColor(view, reaction)
    if view.reputationRed then return view.reputationRed, view.reputationGreen, view.reputationBlue end
    local color = reaction and FACTION_BAR_COLORS[reaction]
    if color then return color.r, color.g, color.b end
    return unpack(view.reputationAccent)
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
    local r, g, b = BarColor(row.view, reaction)
    if fill.reputationR ~= r or fill.reputationG ~= g or fill.reputationB ~= b then
        fill.reputationR, fill.reputationG, fill.reputationB = r, g, b
        fill:SetColorTexture(r, g, b, .9)
    end
end

function Layout.SetReputationStyle(view, config, accent)
    local height = min(8, max(2, config.reputationBarHeight or 3))
    local hex = config.reputationBarColor or ""
    if view.reputationHeight == height and view.reputationHex == hex and view.reputationAccent == accent then return end
    view.reputationHeight, view.reputationHex, view.reputationAccent = height, hex, accent
    if hex ~= "" then
        view.reputationRed, view.reputationGreen, view.reputationBlue = NS.Suite.RGB(hex)
    else
        view.reputationRed, view.reputationGreen, view.reputationBlue = nil, nil, nil
    end

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
    if moved or rangeChanged then SyncSlider(list, rangeChanged) end
    return list.offset
end

function Layout.UpdateScroll(list, content, reset)
    if list.slider then return UpdateOwnedScroll(list, content, reset) end
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
