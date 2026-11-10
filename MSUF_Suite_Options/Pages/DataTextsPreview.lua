local _, P = ...
local Suite, S, M, T, Tr, HM = P.Suite, P.S, P.M, P.T, P.Tr, P.HM
local Data = P.DataTextsPreviewData
local Preview = {}
P.DataTextsPreview = Preview
local ID, PAGE = "dataTexts", "suite_dataTexts"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local EMPTY_CONFIG = {}
local BADGE = "Interface\\AddOns\\MSUF_Suite_DataTexts\\Media\\BagMedallion.tga"
local OUTLINES, ALIGN = { "OUTLINE", "THICKOUTLINE", "", "MONOCHROME,OUTLINE" }, { "LEFT", "CENTER", "RIGHT" }
local DOCK = Suite.DataTextDock
local DOCK_POINTS = { [DOCK.TOP] = "TOP", [DOCK.BOTTOM] = "BOTTOM", [DOCK.LEFT] = "LEFT", [DOCK.RIGHT] = "RIGHT" }
local VIEW_INSET, VIEW_TOP, VIEW_BOTTOM = 12, 40, 39
local ZOOM_STEPS = { .2, .35, .5, .65, .85, 1, 1.25, 1.5, 2, 3, 4 }
local EDGE_POINTS = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }

local function Edges(parent, layer)
    local edges = {}
    for i, points in ipairs(EDGE_POINTS) do
        local edge = parent:CreateTexture(nil, layer or "OVERLAY")
        edge:SetPoint(points[1], parent, points[1])
        edge:SetPoint(points[2], parent, points[2])
        edges[i] = edge
    end
    return edges
end

local function Border(edges, color, size, shown, alpha)
    local r, g, b = P.RGB(color)
    for i, edge in ipairs(edges) do
        edge:SetColorTexture(r, g, b, alpha or 1)
        if i <= 2 then edge:SetHeight(size) else edge:SetWidth(size) end
        edge:SetShown(shown)
    end
end

local function Metadata(ui, button, key, label)
    if ui.options.interactive == false or not M.RegisterControlMetadata then return end
    local identity = "bar" .. ui.bar .. key
    if button.previewMetadataKey == identity then return end
    button.previewMetadataKey = identity
    M.RegisterControlMetadata(button, P.Meta(PAGE, ID, identity, "ephemeral", PAGE .. "_bar" .. ui.bar),
        label, "button")
end

local function Selection(ui)
    local selected = ui.options.selectedSlot
    if type(selected) == "function" then return selected() end
    return ui.selectedSlot or selected
end

local function Highlight(ui, button)
    local selected = ui.options.interactive ~= false and Selection(ui) == button.slot
    local thickness = 2 * ui.pixel / math.max(.01, (ui.fit or 1) * (button.slotScale or 1))
    P.PreviewInteraction.Outline(button, selected and ui.host:IsVisible(), thickness)
    button.hover:SetShown(button.hovered and not selected)
end

local function ReadConfig(ui)
    local config = ui.options.config
    if config == nil then return S.Config(ID) end
    if type(config) == "function" then config = config() end
    return type(config) == "table" and config or EMPTY_CONFIG
end

local function MarkDrop(ui, target)
    local drag = ui.drag
    if not drag or drag.target == target then return end
    drag.target = target
    local marker = ui.dropMarker
    if not target then
        if marker then marker:Hide() end
        return
    end
    if not marker then
        local overlay = CreateFrame("Frame", nil, ui.sample)
        overlay:SetAllPoints(ui.sample)
        overlay:SetFrameLevel(ui.sample:GetFrameLevel() + 2)
        marker = overlay:CreateTexture(nil, "OVERLAY")
        ui.dropMarker = marker
    end
    local color = T.colors.accent or T.colors.text
    marker:SetColorTexture(color[1], color[2], color[3], 1)
    local thickness = 3 * ui.pixel / ui.fit
    local after = drag.source.slot < target.slot
    marker:ClearAllPoints()
    if ui.vertical then
        local edge = after and "BOTTOM" or "TOP"
        marker:SetPoint("LEFT", target, edge .. "LEFT")
        marker:SetPoint("RIGHT", target, edge .. "RIGHT")
        marker:SetHeight(thickness)
    else
        local edge = after and "RIGHT" or "LEFT"
        marker:SetPoint("TOP", target, "TOP" .. edge)
        marker:SetPoint("BOTTOM", target, "BOTTOM" .. edge)
        marker:SetWidth(thickness)
    end
    marker:Show()
end

local function CancelDrag(ui)
    local drag = ui.drag
    if not drag then return end
    MarkDrop(ui, nil)
    drag.source:SetAlpha(1)
    ui.drag = nil
end

local function StartDrag(button)
    local ui = button.dragPreview
    if ui.disposed or ui.drag or not button:IsVisible() or not ui.entries or #ui.entries < 2 or P.Combat() then return end
    ui.drag = { source = button, current = P.ProfileGuard() }
    button.skipDragClick = true
    button:SetAlpha(.55)
end

local function DropTarget(ui, source)
    local surface = ui.viewport or ui.host
    if not surface:IsVisible() or not surface:IsMouseOver() then return end
    for _, entry in ipairs(ui.entries) do
        local button = entry.button
        if button ~= source and button:IsVisible() and button:IsMouseOver() then return button end
    end
end

local function DragCurrent(ui, drag)
    if not drag.current() or ui.rawConfig ~= ReadConfig(ui) then return false end
    for _, button in ipairs(ui.slots) do
        if ui.config[button.dataKey] ~= button.dataChoice then return false end
    end
    return true
end

local function StopDrag(button)
    local ui = button.dragPreview
    local drag = ui.drag
    if not drag or drag.source ~= button then return end
    local target = DragCurrent(ui, drag) and DropTarget(ui, button)
    CancelDrag(ui)
    if target then ui.options.onMove(button.slot, target.slot) end
end

local function ResetClick(button, key)
    if key == "LeftButton" then button.skipDragClick = false end
end

local function NewSlot(ui, index)
    local button = CreateFrame("Button", nil, ui.sample)
    button.slot, button.dataProgress = index, false
    button.fill = button:CreateTexture(nil, "BACKGROUND")
    button.fill:SetAllPoints(button)
    button.hover = button:CreateTexture(nil, "HIGHLIGHT")
    button.hover:SetAllPoints(button)
    button.hover:SetColorTexture(.34, .78, .87, .12)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetWordWrap(false)
    button.label:SetTextColor(1, 1, 1)
    button.divider = ui.sample:CreateTexture(nil, "ARTWORK")
    HM.SkipHistoryCheckpoint(button)
    HM.AllowCombatClick(button)
    button:EnableMouse(ui.options.interactive ~= false)
    if ui.options.interactive == false then return button end
    button.skipDragClick = false
    if ui.options.onMove then
        button.dragPreview = ui
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", StartDrag)
        button:SetScript("OnDragStop", StopDrag)
        button:SetScript("OnMouseDown", ResetClick)
    end
    button:SetScript("OnEnter", function()
        button.hovered = true
        Highlight(ui, button)
        local drag = ui.drag
        if drag and drag.source ~= button then MarkDrop(ui, button) end
    end)
    button:SetScript("OnLeave", function()
        button.hovered = nil
        Highlight(ui, button)
        if ui.drag and ui.drag.target == button then MarkDrop(ui, nil) end
    end)
    button:SetScript("OnClick", function()
        if button.skipDragClick then
            button.skipDragClick = false
            return
        end
        if ui.disposed then return end
        ui.selectedSlot = index
        if ui.options.onSelect then ui.options.onSelect(index) end
        ui:Refresh()
    end)
    return button
end

local function PaintBackdrop(ui, style, inset)
    local fade = style.backgroundEnabled and style.backgroundGradient
    ui.fill:SetTexture(Suite.ResolveTexture(style.backgroundTexture) or WHITE)
    local r, g, b = P.RGB(style.backgroundColor)
    ui.fill:SetVertexColor(r, g, b, style.backgroundOpacity / 100)
    ui.fill:SetShown(style.backgroundEnabled and not fade)
    ui.gradient:SetShown(fade == true)
    if fade then
        local fr, fg, fb = P.RGB(style.backgroundFadeColor)
        local opacity = style.backgroundOpacity / 100
        ui.gradient:SetGradient("VERTICAL", CreateColor(fr, fg, fb, opacity), CreateColor(r, g, b, opacity))
    end
    Border(ui.edges, style.borderColor, style.borderSize * ui.pixel, style.borderEnabled, .85)
    ui.accent:SetShown(style.accentEnabled)
    ui.accent:ClearAllPoints()
    local top = style.accentPosition == Suite.DataTextAccentPosition.TOP
    local point = top and "TOP" or "BOTTOM"
    ui.accent:SetPoint(point .. "LEFT", ui.sample, point .. "LEFT", top and inset or 0, 0)
    ui.accent:SetPoint(point .. "RIGHT", ui.sample, point .. "RIGHT")
    ui.accent:SetHeight(ui.pixel)
    local ar, ag, ab = P.RGB(style.accentColor)
    ui.accent:SetColorTexture(ar, ag, ab, .9)
    ui.badge:SetShown(style.bagBadge)
    ui.badge:SetSize(style.bagBadgeSize, style.bagBadgeSize)
    ui.badge:ClearAllPoints()
    ui.badge:SetPoint("LEFT", ui.sample, "LEFT", Data.Snap(4, ui.pixel), 0)
end

local function Entries(ui, config, style)
    local entries, prefix = {}, "bar" .. ui.bar .. "Slot"
    local font = Suite.ResolveFont(style.font) or Suite.GlobalFontPath()
    for slot = 1, ui.maxSlots do
        local button, block = ui.slots[slot], prefix .. slot
        local choice = config[block]
        button.dataKey, button.dataChoice = block, choice
        local source = choice and Suite.DataTextSourceKeys[choice]
        button:SetShown(source ~= nil and source ~= false)
        button.divider:Hide()
        if source then
            P.StylePreviewFont(button.label, font, style.fontSize, OUTLINES[style.textOutline] or "OUTLINE",
                style.fontRendering, style.fontShadow, style.fontShadowOpacity, style.fontShadowDistance)
            button.label:SetJustifyH(ALIGN[style.textAlign] or "CENTER")
            button.label:SetText(Data.Text(source, style, config, block))
            local progress = source == "progressBar"
            if progress then Suite.PrepareDataTextProgress(button, button.CreateTexture)
            elseif button.dataProgress then Suite.PaintDataTextProgress(button) end
            local textWidth = progress and Suite.DataTextProgressWidth or button.label:GetUnboundedStringWidth()
            entries[#entries + 1] = { button = button, block = block, textWidth = textWidth, progress = progress,
                placement = config[block .. "Placement"], limit = source == "broker" and config[block .. "MaxWidth"] or nil }
            Metadata(ui, button, "Slot" .. slot .. ".preview", Tr("Choose data for place %d"):format(slot))
        end
    end
    return entries
end

local function PaintSlot(ui, entry, config, style, ordinal, count, vertical, width, height)
    local button, block, pixel = entry.button, entry.block, ui.pixel
    local scale = (config[block .. "Scale"] or 100) / 100
    local left = Data.Snap(entry.offset, pixel)
    local right = Data.Snap(entry.offset + entry.length, pixel)
    button.slotScale = scale
    button:SetScale(scale)
    button:ClearAllPoints()
    if vertical then
        button:SetPoint("TOP", ui.sample, "TOP", 0, -left / scale)
        button:SetSize(width / scale, math.max(1, right - left) / scale)
    else
        button:SetPoint("LEFT", ui.sample, "LEFT", left / scale, 0)
        button:SetSize(math.max(1, right - left) / scale, height / scale)
    end
    local available = vertical and width / scale or (right - left) / scale
    local padding = math.max(0, math.min(config[block .. "Padding"] or style.padding, (available - 4) / 2))
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", button, "LEFT", padding, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -padding, 0)
    if entry.progress then
        Suite.LayoutDataTextProgress(button, available, padding, pixel / scale)
        Suite.PaintDataTextProgress(button, .32, .42)
    end
    local r, g, b = P.RGB(config[block .. "Background"] or "101010")
    button.fill:SetColorTexture(r, g, b, (config[block .. "Alpha"] or 0) / 100)
    Highlight(ui, button)
    local divider = button.divider
    divider:SetShown(style.separatorEnabled and ordinal < count)
    divider:ClearAllPoints()
    local offset = Data.Snap(right + style.gap / 2, pixel)
    local length = math.max(6, (vertical and width or height) - 2 * style.padding)
    if vertical then
        divider:SetPoint("CENTER", ui.sample, "TOP", 0, -offset)
        divider:SetSize(length, style.separatorSize * pixel)
    else
        divider:SetPoint("CENTER", ui.sample, "LEFT", offset, 0)
        divider:SetSize(style.separatorSize * pixel, length)
    end
    local sr, sg, sb = P.RGB(style.separatorColor)
    divider:SetColorTexture(sr, sg, sb, .8)
end

local function ValueColor(style)
    if not style.valueClassColor then return end
    local _, class = UnitClass("player")
    if Suite.IsSecret(class) or not class then return end
    if S.ClassHex then
        style.valueColor = S.ClassHex(class) or style.valueColor
    else
        local color = C_ClassColor.GetClassColor(class)
        if color then style.valueColor = color:GenerateHexColor():sub(3) end
    end
end

local function RefreshSelection(ui)
    local target = ui.slots[Selection(ui)]
    if target and target:IsShown() and ui.options.onSelect then
        local thickness = 2 * ui.pixel / math.max(.01, ui.fit * (target.slotScale or 1))
        P.PreviewInteraction.Select(ui.selection, target, "Data texts", ui.openSelected, thickness)
    else
        P.PreviewInteraction.Select(ui.selection, nil)
    end
end

local function PlaceCamera(ui, x, y)
    local maxX = math.max(0, (ui.sampleWidth * ui.fit - ui.viewWidth) / 2)
    local maxY = math.max(0, (ui.sampleHeight * ui.fit - ui.viewHeight) / 2)
    x = math.max(-maxX, math.min(maxX, x))
    y = math.max(-maxY, math.min(maxY, y))
    ui.canPan = maxX > 0 or maxY > 0
    if not ui.stageMoved and ui.panX == x and ui.panY == y then return end
    ui.panX, ui.panY, ui.stageMoved = x, y, false
    ui.stage:ClearAllPoints()
    ui.stage:SetPoint("CENTER", ui.viewport, "CENTER", x, y)
end

local function UpdateZoom(ui)
    local native = UIParent:GetEffectiveScale() / ui.viewport:GetEffectiveScale()
    ui.viewWidth = math.max(1, ui.width - 2 * VIEW_INSET - 16)
    ui.viewHeight = math.max(1, ui.height - VIEW_TOP - VIEW_BOTTOM - 12)
    local fitZoom = math.min(1, ui.viewWidth / (ui.sampleWidth * native), ui.viewHeight / (ui.sampleHeight * native))
    local zoom = ui.zoom or (ui.fitRequested and fitZoom or math.max(.85, fitZoom))
    local scale = zoom * native
    if ui.fit ~= scale then
        ui.fit = scale
        ui.sample:SetScale(scale)
    end
    if ui.viewZoom ~= zoom then
        ui.viewZoom = zoom
        P.SetTranslatedText(ui.zoomLabel, ("%d%%"):format(math.floor(zoom * 100 + .5)))
    end
end

local function RevealSlot(ui, slot)
    for _, entry in ipairs(ui.entries) do
        if entry.button.slot == slot then
            local length = ui.vertical and ui.sampleHeight or ui.sampleWidth
            local center = (entry.offset + entry.length / 2 - length / 2) * ui.fit
            local half = entry.length * ui.fit / 2
            if ui.vertical then
                if math.abs(ui.panY - center) + half > ui.viewHeight / 2 then PlaceCamera(ui, ui.panX, center) end
            elseif math.abs(ui.panX + center) + half > ui.viewWidth / 2 then
                PlaceCamera(ui, -center, ui.panY)
            end
            return
        end
    end
end

-- The stage moves natively while held. Only the release resolves and clamps
-- the new position, so panning never repaints or polls the sample.
local function StopPan(ui, commit)
    local startX, startY = ui.panStartX, ui.panStartY
    if not startX then return end
    ui.panStartX, ui.panStartY = nil, nil
    ui.stage:StopMovingOrSizing()
    ui.stage:SetUserPlaced(false)
    local x, y = ui.panX, ui.panY
    if commit then
        local cursorX, cursorY = GetCursorPosition()
        local scale = ui.viewport:GetEffectiveScale()
        x, y = x + (cursorX - startX) / scale, y + (cursorY - startY) / scale
    end
    PlaceCamera(ui, x, y)
end

local function SetZoom(ui, zoom)
    if not ui.viewZoom or (ui.zoom == zoom and ui.fitRequested == (zoom == nil)) then return end
    CancelDrag(ui)
    StopPan(ui, false)
    local previous = ui.fit
    ui.zoom, ui.fitRequested = zoom, zoom == nil
    UpdateZoom(ui)
    local ratio = zoom and ui.fit / previous or 0
    PlaceCamera(ui, ui.panX * ratio, ui.panY * ratio)
    RefreshSelection(ui)
end

local function StepZoom(ui, direction)
    local current = ui.viewZoom
    if not current then return end
    if direction > 0 then
        for _, zoom in ipairs(ZOOM_STEPS) do
            if zoom > current + .001 then return SetZoom(ui, zoom) end
        end
    else
        for i = #ZOOM_STEPS, 1, -1 do
            if ZOOM_STEPS[i] < current - .001 then return SetZoom(ui, ZOOM_STEPS[i]) end
        end
    end
end

local function PlaceSample(ui, config, prefix)
    local point, x, y = "CENTER", 0, 8
    if ui.options.compact then
        point = DOCK_POINTS[config[prefix .. "Dock"]] or Suite.DataTextPoints[config[prefix .. "Point"]] or point
        x = point:find("LEFT", 1, true) and 12 or point:find("RIGHT", 1, true) and -12 or 0
        y = point:find("TOP", 1, true) and -8 or point:find("BOTTOM", 1, true) and 8 or 0
        x, y = x / ui.fit, y / ui.fit
    end
    ui.sample:ClearAllPoints()
    ui.sample:SetPoint(point, ui.host, point, x, y)
end

local function Paint(ui)
    CancelDrag(ui)
    StopPan(ui, false)
    if ui.disposed or not ui.host:IsVisible() then return end
    local bar = ui.barId
    if type(bar) == "function" then bar = bar() end
    if not bar then
        ui.sample:Hide()
        ui.add:Hide()
        return
    end
    ui.bar = bar
    ui.rawConfig = ReadConfig(ui)
    local config, prefix = ui.config, "bar" .. bar
    local style = Suite.DataTextEffectiveStyle(config, bar)
    local vertical = config[prefix .. "Vertical"] == true
    ui.vertical = vertical
    if vertical then style.bagBadge = false end
    ValueColor(style)
    ui.pixel = S.PixelUnit and S.PixelUnit() or 1
    local entries = Entries(ui, config, style)
    local span = vertical and UIParent:GetHeight() or UIParent:GetWidth()
    local width, height, inset = Data.Layout(entries, config, bar, style, ui.pixel, span)
    local badge = style.bagBadge and style.bagBadgeSize or 0
    ui.sample:SetSize(width, height)
    ui.entries = entries
    if ui.viewport then
        ui.sampleWidth, ui.sampleHeight = math.max(1, width), math.max(1, height, badge)
        UpdateZoom(ui)
        PlaceCamera(ui, ui.panX, ui.panY)
        local selected = Selection(ui)
        if ui.revealedBar ~= bar or ui.revealedSlot ~= selected then
            ui.revealedBar, ui.revealedSlot = bar, selected
            RevealSlot(ui, selected)
        end
    else
        local availableHeight = ui.height - (ui.options.compact and 16 or 86)
        local fit = math.min(1, (ui.width - 24) / math.max(1, width), availableHeight / math.max(1, height, badge))
        ui.fit = math.max(.01, fit)
        ui.sample:SetScale(ui.fit)
        PlaceSample(ui, config, prefix)
    end
    ui.sample:Show()
    PaintBackdrop(ui, style, inset)
    for i, entry in ipairs(entries) do PaintSlot(ui, entry, config, style, i, #entries, vertical, width, height) end
    local status = config[prefix .. "Name"]
    if type(status) ~= "string" or status == "" then status = Tr("Bar %d"):format(bar) end
    if config[prefix .. "FullScreen"] then status = Tr("%s - Full screen"):format(status) end
    if not config[prefix .. "Enabled"] then status = Tr("%s - Hidden"):format(status) end
    P.SetTranslatedText(ui.status, status)
    ui.empty:SetShown(#entries == 0)
    ui.add:SetShown(not ui.options.compact and ui.options.interactive ~= false and ui.options.onAdd ~= nil)
    ui.add:SetEnabled(#entries < ui.maxSlots and not P.Combat())
    Metadata(ui, ui.add, ".preview.add", Tr("Add data"))
    RefreshSelection(ui)
end

local function BindWheel(ui, frame)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", ui.wheel)
end

local function ZoomButton(ui, label, tip, x, width, click)
    local button = T.Button(ui.host, label, width, 23)
    button:SetPoint("TOPRIGHT", ui.host, "TOPRIGHT", x, -8)
    button:SetScript("OnClick", click)
    HM.SkipHistoryCheckpoint(button)
    HM.AllowCombatClick(button)
    M.AddTooltip(button, tip)
    BindWheel(ui, button)
    return button
end

local function BuildViewport(ui, chrome)
    local viewport = CreateFrame("Frame", nil, ui.host, "BackdropTemplate")
    viewport:SetPoint("TOPLEFT", ui.host, "TOPLEFT", VIEW_INSET, -VIEW_TOP)
    viewport:SetPoint("BOTTOMRIGHT", ui.host, "BOTTOMRIGHT", -VIEW_INSET, VIEW_BOTTOM)
    viewport:SetClipsChildren(true)
    viewport:EnableMouse(true)
    if chrome and chrome.ApplyPreviewChrome then
        chrome.ApplyPreviewChrome(viewport, "canvas", T)
    else
        local backdrop = viewport:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints(viewport)
        backdrop:SetColorTexture(.07, .09, .12, .96)
    end
    local guide = viewport:CreateTexture(nil, "BACKGROUND", nil, -1)
    guide:SetColorTexture(.65, .78, .87, .16)
    guide:SetPoint("TOP", viewport, "TOP", 0, -6)
    guide:SetPoint("BOTTOM", viewport, "BOTTOM", 0, 6)
    guide:SetWidth(1)
    local stage = CreateFrame("Frame", nil, viewport)
    stage:SetSize(1, 1)
    stage:SetMovable(true)
    ui.viewport, ui.stage, ui.stageMoved = viewport, stage, true
    ui.panX, ui.panY = 0, 0
    viewport:RegisterForDrag("LeftButton")
    viewport:SetScript("OnDragStart", function()
        if ui.canPan and not ui.drag and not ui.panStartX then
            ui.panStartX, ui.panStartY = GetCursorPosition()
            ui.stageMoved = true
            stage:StartMoving()
        end
    end)
    viewport:SetScript("OnDragStop", function() StopPan(ui, true) end)
    ui.wheel = function(_, delta)
        if IsControlKeyDown() then
            StepZoom(ui, delta)
        elseif M.ForwardMenuScrollWheel then
            M.ForwardMenuScrollWheel(delta)
        else
            local scroll = M.scrollFrame
            local handler = scroll and scroll:GetScript("OnMouseWheel")
            if handler then handler(scroll, delta) end
        end
    end
    BindWheel(ui, viewport)
end

local function BuildZoomTools(ui)
    ui.zoomOut = ZoomButton(ui, "-", "Zoom out", -176, 26, function() StepZoom(ui, -1) end)
    ui.zoomLabel = T.Font(ui.host, "GameFontDisableSmall", "", T.colors.muted)
    ui.zoomLabel:SetPoint("LEFT", ui.zoomOut, "RIGHT", 3, 0)
    ui.zoomLabel:SetSize(38, 23)
    ui.zoomLabel:SetJustifyH("CENTER")
    ui.zoomIn = ZoomButton(ui, "+", "Zoom in", -106, 26, function() StepZoom(ui, 1) end)
    ui.zoomFit = ZoomButton(ui, "Fit", "Fit", -49, 54, function() SetZoom(ui) end)
    ui.zoomOne = ZoomButton(ui, "1:1", "Preview", -12, 34, function() SetZoom(ui, 1) end)
end

local function MakeCanvas(ui)
    local parent = ui.stage or ui.host
    local sample = CreateFrame("Frame", nil, parent)
    sample:SetPoint("CENTER", parent, "CENTER", 0, ui.viewport and 0 or (ui.options.compact and 0 or 8))
    ui.sample = sample
    ui.fill = sample:CreateTexture(nil, "BACKGROUND")
    ui.fill:SetAllPoints(sample)
    ui.gradient = sample:CreateTexture(nil, "BACKGROUND")
    ui.gradient:SetTexture(WHITE)
    ui.gradient:SetAllPoints(sample)
    ui.edges = Edges(sample, "BORDER")
    ui.accent = sample:CreateTexture(nil, "ARTWORK")
    ui.badge = sample:CreateTexture(nil, "OVERLAY")
    ui.badge:SetTexture(BADGE)
    for slot = 1, ui.maxSlots do
        local button = NewSlot(ui, slot)
        ui.slots[slot] = button
        if ui.viewport then BindWheel(ui, button) end
    end
end

local function LayoutWidth(ui)
    local width = ui.width
    ui.status:SetWidth(math.max(1, width - (ui.viewport and 222 or 24)))
    ui.empty:SetWidth(math.max(1, width - 24))
    local selectionWidth = math.max(24, width - 166)
    ui.selection:SetWidth(selectionWidth)
    local labelWidth = selectionWidth - ui.selection.button:GetWidth()
    ui.selection.label:SetWidth(math.max(20, labelWidth - 28))
    ui.selection.label:SetShown(labelWidth >= 68)
end

local function Lifecycle(ui)
    function ui:Refresh() Paint(self) end
    function ui:SetBar(bar)
        self.selectedSlot = nil
        self.barId = bar
        self:Refresh()
    end
    function ui:SetSelectedSlot(slot)
        self.selectedSlot = slot
        self:Refresh()
    end
    function ui:Dispose()
        CancelDrag(self)
        StopPan(self, false)
        self.disposed = true
        self.host:Hide()
    end
    ui.host:SetScript("OnShow", function() ui:Refresh() end)
    ui.host:SetScript("OnSizeChanged", function(_, width, height)
        ui.width, ui.height, ui.revealedBar = width, height, nil
        LayoutWidth(ui)
        ui:Refresh()
    end)
    ui.host:SetScript("OnHide", function()
        CancelDrag(ui)
        StopPan(ui, false)
        for _, button in ipairs(ui.slots) do button.hovered = nil end
    end)
    M.TrackRefresh(ui.ctx, function() ui:Refresh() end)
end

local function ConfigView(ui)
    return setmetatable({}, { __index = function(_, key)
        local value = ui.rawConfig and ui.rawConfig[key]
        if value ~= nil then return value end
        local rule = P.catalog[ID].rules[key]
        return rule and rule.default
    end })
end

function Preview.Build(ctx, parent, barId, options)
    options = options or {}
    local width, height = options.width or 640, options.height or 180
    local host = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local x, y = options.x or 16, options.y or -16
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if options.stretch then
        host:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -x, y)
        host:SetHeight(height)
    else
        host:SetSize(width, height)
    end
    host:SetClipsChildren(true)
    local ui = { host = host, frame = host, barId = barId, options = options, ctx = ctx, slots = {}, pixel = 1,
        width = width, height = height, bottomY = (options.y or -16) - height,
        maxSlots = options.maxSlots or Suite.DataTextSlotLimit }
    ui.config = ConfigView(ui)
    local chrome = M.PreviewHelpers
    local zoomable = not options.compact and options.interactive ~= false
    if chrome and chrome.ApplyPreviewChrome then chrome.ApplyPreviewChrome(host, zoomable and "outer" or "canvas", T) end
    if zoomable then
        BuildViewport(ui, chrome)
        BuildZoomTools(ui)
    end
    local statusWidth = math.max(1, width - (zoomable and 222 or 24))
    ui.status = P.Text(host, "", 12, -13, statusWidth, T.colors.accent or T.colors.text)
    ui.status:SetWordWrap(false)
    ui.openSelected = function() ui.options.onSelect(Selection(ui)) end
    local emptyText = options.compact and "Empty bar" or "Add your first data source to this bar."
    ui.empty = P.Text(host, emptyText, 12, -math.floor(height / 2), width - 24)
    ui.empty:SetJustifyH("CENTER")
    local hint = options.onMove and "Click a data text to edit it. Drag to reorder."
        or "Sample values. Click a data text to edit it."
    ui.selection = P.PreviewInteraction.Bar(ctx, host, width - 166, hint)
    ui.selection:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 12, 8)
    ui.add = T.Button(host, "Add data", 136, 26)
    ui.add:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -10, 8)
    HM.SkipHistoryCheckpoint(ui.add)
    ui.add:SetScript("OnClick", function()
        if not ui.disposed and ui.options.interactive ~= false and not P.Combat() and ui.options.onAdd then
            ui.options.onAdd(ui.add)
        end
    end)
    ui.status:SetShown(not options.compact)
    ui.selection:SetShown(not options.compact and options.interactive ~= false)
    MakeCanvas(ui)
    Lifecycle(ui)
    ui:Refresh()
    return ui
end
