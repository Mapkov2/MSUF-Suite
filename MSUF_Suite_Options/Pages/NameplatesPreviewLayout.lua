local _, P = ...
local M, W, SB = P.M, P.W, P.M.PreviewSelectionBar
local Public = P.Suite.Public
local Layout = {}
P.NameplatesPreviewLayout = Layout

local TOOL_HEIGHT, TOOL_GAP = 20, 6
-- Expanded preview columns: element panel | canvas, tools, selection | inspector.
-- Narrow menus drop the inspector first, then the panel.
local PANEL_WIDTH, INSPECTOR_WIDTH, COLUMN_GAP = 212, 236, 8
local PANEL_MIN_WIDTH, INSPECTOR_MIN_WIDTH = 640, 960
local LABEL_INSET = 8
local ZOOM_STEPS = { 0.35, 0.50, 0.75, 1, 1.25, 1.50, 2, 3, 4 }
local FIT_PADDING, MIN_FIT_ZOOM = 20, 0.05
local CENTERED_NAME_WIDTH = 170

local function ManualNamePlacement(m, anchor)
    if m.namesOnly and not m.nameOnlyScope then
        if m.nameAnchor == 1 then return "CENTER", "CENTER", 0, 0, CENTERED_NAME_WIDTH, "CENTER" end
        return "BOTTOM", "TOP", 0, 2, CENTERED_NAME_WIDTH, "CENTER"
    elseif anchor then
        local justify = anchor:find("LEFT", 1, true) and "LEFT" or anchor:find("RIGHT", 1, true) and "RIGHT" or "CENTER"
        return anchor, anchor, 0, 0, m.availableNameWidth, justify
    elseif m.nameAnchor == 3 then
        local width = m.barWidth - 8 + (m.classic and m.classicInset or 0)
        return "BOTTOM", "TOP", m.classic and 8.625 * m.horizontal or 0, m.nameSpacing, width, "CENTER"
    elseif m.nameAnchor == 2 then
        local width = m.nativeLevel and m.barWidth + m.reserve - 4 or m.availableNameWidth
        return "BOTTOMLEFT", "TOPLEFT", 4, m.nameSpacing, width, "LEFT"
    end
    return "LEFT", "LEFT", 4, 0, m.availableNameWidth, "LEFT"
end

local function NameTextWidth(m, width)
    if m.centerName or m.namesOnly and not m.nameOnlyScope then return CENTERED_NAME_WIDTH end
    if m.nameAnchor == 3 then return width end
    return m.availableNameWidth
end

function Layout.RenderName(s, m, Get, SetupNumber, Place)
    local ID = "nameplates"
    local prefix, name, bar = s.prefix, s.name, s.bar
    name:EnableMouse(not m.npcWorldName and not s.static)
    local config = P.S.Config(ID)
    m.centerName = not (m.npcWorldName or m.skinDisabled) and Get(ID, "look") ~= 2
        and Get(ID, prefix) and Get(ID, m.scope .. "CenterName")
    local shared = not (m.npcWorldName or m.skinDisabled) and P.Suite.NameplateText.Shared(config)
    local size = P.Suite.NameplateText.ResolveSize(config, prefix .. "NameSize", shared)
    local anchor = not (m.centerName or m.namesOnly or m.skinDisabled) and Get(ID, "look") ~= 2 and P.Suite.NameplateText.NameAnchor(config, prefix)
    name:SetHeight(not (m.npcWorldName or m.skinDisabled) and (shared or Get(ID, prefix .. "TextEnabled")) and size > 0 and size
        or SetupNumber("healthBarFontHeight", (m.classic and 10 or m.forever and 14 or 12) * m.vertical))
    name:ClearAllPoints()
    name.previewCenterNameKey, name.previewCenteredNameSample, name.previewCenteredNameMetrics = nil, nil, nil
    local width = CENTERED_NAME_WIDTH
    local justify = m.nameAnchor == 3 and "CENTER" or "LEFT"
    if m.npcWorldName then
        name:SetPoint("CENTER", s.cell, "CENTER", 0, 0)
        if m.namesOnly and not m.nameOnlyScope then justify = "CENTER" end
    elseif m.centerName then
        local spacing = m.namesOnly and not m.nameOnlyScope and 2 or m.nameSpacing
        local baseY = -4 + m.nativeBarHeight / 2 + m.heightDelta + spacing + (shared and shared.fontBaselineOffset or 0)
        name:SetPoint("BOTTOM", s.cell, "CENTER", 0, baseY + Get(ID, prefix .. "NameOffsetY"))
        justify = "CENTER"
        if m.namesOnly and not s.static then
            name.previewCenterNameKey = m.scope .. "CenterName"
            name.previewCenteredNameSample, name.previewCenteredNameMetrics, name.previewCenteredNameBaseY = s, m, baseY
        end
    else
        local point, relative, x, y, manualWidth, manualJustify = ManualNamePlacement(m, anchor)
        Place(s, name, point, bar, relative, x, y, "Name")
        width, justify = manualWidth, manualJustify
    end
    name:SetWidth(width)
    s.nameText:SetWidth(NameTextWidth(m, width))
    s.nameText:SetJustifyH(justify)
end

local function AxisAnchor(point, low, high)
    if point:find(low, 1, true) then return -.5 end
    if point:find(high, 1, true) then return .5 end
    return 0
end

-- Auto center deliberately ignores the saved X offset. When a user moves
-- sideways, convert from the centered text position to the manual anchor so
-- exiting auto center keeps the dragged text at the same place.
function Layout.ManualNameOffsets(name, x, y)
    local s, m = name.previewCenteredNameSample, name.previewCenteredNameMetrics
    local cellX, cellY = s.cell:GetCenter()
    local barX, barY = s.bar:GetCenter()
    local barWidth, barHeight = s.bar:GetWidth(), s.bar:GetHeight()
    local nameHeight, stringWidth = name:GetHeight(), s.nameText:GetStringWidth()
    if not (Public(cellX) and Public(cellY) and Public(barX) and Public(barY) and Public(barWidth) and Public(barHeight)
        and Public(nameHeight) and Public(stringWidth) and cellX and cellY and barX and barY and barWidth and barHeight
        and nameHeight and stringWidth) then return end
    local point, relative, baseX, baseY, width, justify = ManualNamePlacement(m)
    local textWidth = m.namesOnly and not m.nameOnlyScope and CENTERED_NAME_WIDTH
        or m.nameAnchor == 3 and width or m.availableNameWidth
    local textCenter = (textWidth - math.min(stringWidth, textWidth)) * AxisAnchor(justify, "LEFT", "RIGHT")
        + (textWidth - width) / 2
    local manualX = barX + barWidth * AxisAnchor(relative, "LEFT", "RIGHT") + baseX
        - width * AxisAnchor(point, "LEFT", "RIGHT") + textCenter
    local manualY = barY + barHeight * AxisAnchor(relative, "BOTTOM", "TOP") + baseY
        - nameHeight * AxisAnchor(point, "BOTTOM", "TOP")
    return cellX + x - manualX, cellY + name.previewCenteredNameBaseY + y + nameHeight / 2 - manualY
end

-- Native base point of the health value on the health bar, from
-- Blizzard_NamePlateUnitFrame:UpdateAnchors (live and forever): AboveHealthBar
-- puts it above the bar unless Forever keeps it inside. Layout.lua only offsets
-- the native text, so the preview starts at the same point as the live plate.
function Layout.HealthTextAnchor(nameAnchor, insideWhenAbove, classicBar)
    if nameAnchor == 2 and insideWhenAbove ~= true then return "BOTTOMRIGHT", "TOPRIGHT", -4, 2 end
    return "RIGHT", "RIGHT", -4, nameAnchor == 3 and classicBar == true and -.5 or 0
end

function Layout.PlaceHealthText(s, m, SetupToggle, Place)
    local point, relative, x, y = Layout.HealthTextAnchor(m.nameAnchor,
        SetupToggle("healthTextInsideBarWhenNameAboveHealthBar", false), SetupToggle("useClassicHealthBar", m.classic))
    s.healthText:SetWidth(78)
    s.value:SetJustifyH("RIGHT")
    s.value:SetJustifyV(point == "BOTTOMRIGHT" and "BOTTOM" or "MIDDLE")
    Place(s, s.healthText, point, s.bar, relative, x, y, "HealthText")
end

-- Live plates show Blizzard's TextStatusBar value, abbreviated by
-- AbbreviateLargeNumbers (capNumericDisplay). The sample calls it too, so its
-- spacing, suffix and locale match; one string per sample percent.
local SAMPLE_MAX_HEALTH, sampleHealthText = 3500000, {}
function Layout.HealthValue(percent)
    local text = sampleHealthText[percent]
    if not text then
        local value = math.floor(SAMPLE_MAX_HEALTH * percent / 100)
        text = AbbreviateLargeNumbers and AbbreviateLargeNumbers(value) or tostring(value)
        sampleHealthText[percent] = text
    end
    return text
end

function Layout.StyleButton(button)
    local label = P.HM.GetControlLabel(button)
    if not label then return end
    label:ClearAllPoints()
    label:SetPoint("LEFT", button, "LEFT", LABEL_INSET, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -LABEL_INSET, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetMaxLines(1)
end

local function TextWidth(label)
    local measure = label and (label.GetUnboundedStringWidth or label.GetStringWidth)
    return measure and math.ceil(measure(label)) or 0
end

function Layout.FitButton(button, available, minimum)
    local width = math.min(available, math.max(minimum, TextWidth(P.HM.GetControlLabel(button)) + 2 * LABEL_INSET + 4))
    button:SetWidth(width)
    return width
end

local function PlaceTool(control, tools, point, x, y)
    control:ClearAllPoints()
    control:SetPoint(point, tools, point, x, y)
end

function Layout.Tools(ui)
    local tools, width = ui.tools, ui.centerWidth or ui.body:GetWidth()
    if not width or width < 1 then return end
    local x, y = 0, 0
    local step = TOOL_HEIGHT + TOOL_GAP
    for _, entry in ipairs(ui.zoomControls) do
        local control, minimum = entry[1], entry[2]
        local size
        if control == ui.zoomLabel then
            size = math.min(width, math.max(minimum, TextWidth(control) + 4))
            control:SetWidth(size)
        else
            size = Layout.FitButton(control, width, minimum)
        end
        if x + size > width then x, y = 0, y - step end
        local inset = control == ui.zoomLabel and math.max(0, (TOOL_HEIGHT - control:GetHeight()) / 2) or 0
        PlaceTool(control, tools, "TOPLEFT", x, y - inset)
        x = x + size + TOOL_GAP
    end
    if ui.elementPicker:IsShown() then
        local pickerSize = Layout.FitButton(ui.elementPicker, width, 96)
        if x + pickerSize > width then y = y - step end
        PlaceTool(ui.elementPicker, tools, "TOPRIGHT", 0, y)
    end

    tools:SetHeight(TOOL_HEIGHT - y)
end

function Layout.PrioritizeHandles(s)
    if s.static then return end
    -- Overlapping text and icons should win a click over the bar they decorate.
    local barLevel = s.bar:GetFrameLevel()
    s.name:SetFrameLevel(barLevel + 1)
    s.healthText:SetFrameLevel(barLevel + 2)
    local castLevel = s.castProgress:GetFrameLevel()
    s.castName:SetFrameLevel(castLevel + 1)
    s.castTime:SetFrameLevel(castLevel + 2)
    s.castTarget:SetFrameLevel(castLevel + 3)
    s.castIcon:SetFrameLevel(castLevel + 4)
    s.shield:SetFrameLevel(castLevel + 4)
end

local function LayoutSelectedTools(bar, width)
    if not bar or not bar:IsShown() then return 0 end
    local limit = width - 12
    if limit < 20 then return 0 end
    local title = math.min(limit, TextWidth(bar.title) + 3)
    bar.title:SetWidth(title)
    local x, y, widest = title + 10, 0, title
    for _, button in ipairs(bar.buttons) do
        if button:IsShown() then
            local size = Layout.FitButton(button, limit, 20)
            if x + size > limit then x, y = 0, y + TOOL_HEIGHT + 3 end
            PlaceTool(button, bar, "TOPLEFT", 6 + x, -3 - y)
            widest = math.max(widest, x + size)
            x = x + size + 4
        end
    end
    bar:SetSize(widest + 12, y + TOOL_HEIGHT + 6)
    return bar:GetHeight() + 6
end

function Layout.Samples(ui)
    Layout.Tools(ui)
    local width, height = ui.canvas:GetWidth(), ui.canvas:GetHeight()
    if not width or width <= 24 or not height or height <= 0 then return end
    local firstRow = width - (ui.backgroundButton and ui.backgroundButton:GetWidth() + 22 or 16)
    local x, y, available = 0, 0, firstRow
    for _, button in ipairs(ui.sampleButtons) do
        if button:IsShown() then
            local size = Layout.FitButton(button, width - 16, 20)
            if x + size > available then
                x, y, available = 0, y - 24, width - 16
            end
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", ui.samples, "TOPLEFT", x, y)
            x = x + size + 5
        end
    end
    ui.samples:SetSize(width - 16, 20 - y)
    ui.raidPalette:ClearAllPoints()
    ui.raidPalette:SetPoint("BOTTOMRIGHT", ui.canvas, "BOTTOMRIGHT", -8, 8)
    ui.fitTop = 8 + ui.samples:GetHeight() + LayoutSelectedTools(ui.selectedTools, width - 16)
    ui.fitBottom = 21 + ui.raidPalette:GetHeight()
end

local function PlaceColumn(frame, body, point, width)
    frame:ClearAllPoints()
    frame:SetPoint("TOP" .. point, body, "TOP" .. point, 0, 0)
    frame:SetPoint("BOTTOM" .. point, body, "BOTTOM" .. point, 0, 4)
    frame:SetWidth(width)
end

function Layout.Apply(self)
    local body, canvas, tools = self.body, self.canvas, self.tools
    local panel, inspector = self.elementPanel, self.inspector
    local editing = not self.compact and not self.groupPreviewEnabled
    local width = body:GetWidth() or 0
    local showPanel = editing and width >= PANEL_MIN_WIDTH
    local showInspector = editing and width >= INSPECTOR_MIN_WIDTH
    local left = showPanel and PANEL_WIDTH + COLUMN_GAP or 0
    local right = showInspector and INSPECTOR_WIDTH + COLUMN_GAP or 0
    self.centerWidth = width - left - right
    panel:SetShown(showPanel)
    self.elementPicker:SetShown(editing and not showPanel)
    inspector:SetShown(showInspector)
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", left, 0)
    tools:SetShown(editing)
    if SB then SB.SetShown(body, editing) end
    self.samples:SetShown(editing)
    self.raidPalette:SetShown(editing)
    self.hint:SetShown(editing)
    if not editing then
        self.fitTop, self.fitBottom = 0, 0
        if self.selectedTools then self.selectedTools:Hide() end
        canvas:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)
        return
    end
    if showPanel then PlaceColumn(panel, body, "LEFT", PANEL_WIDTH) end
    if showInspector then PlaceColumn(inspector, body, "RIGHT", INSPECTOR_WIDTH) end
    -- The center column stacks up from the body's bottom edge: selection bar,
    -- tools, then the canvas takes the remaining height.
    tools:ClearAllPoints()
    if self.selection then
        self.selection:ClearAllPoints()
        self.selection:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", left, 4)
        self.selection:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -right, 4)
        tools:SetPoint("BOTTOMLEFT", self.selection, "TOPLEFT", 0, 5)
        tools:SetPoint("BOTTOMRIGHT", self.selection, "TOPRIGHT", 0, 5)
    else
        tools:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", left, 4)
        tools:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -right, 4)
    end
    canvas:SetPoint("BOTTOMRIGHT", tools, "TOPRIGHT", 0, 4)
    self:LayoutElements()
    P.NameplatesInspector.Refresh(self)
    Layout.Samples(self)
end

-- Canvas offsets are in unscaled canvas units; SetPoint offsets are local
-- to the scaled stage. Keep zoom from multiplying a user's pan.
local function PositionStage(ui, x, y)
    local stage, zoom = ui.stage, ui.zoom
    stage:SetScale(zoom)
    stage:ClearAllPoints()
    stage:SetPoint("CENTER", ui.canvas, "CENTER", x / zoom, y / zoom)
    ui.viewX, ui.viewY = x, y
end

local function FitBounds(ui)
    local stage = ui.stage
    local centerX, centerY = stage:GetCenter()
    local stageScale = stage:GetEffectiveScale()
    if not (Public(centerX) and Public(centerY) and Public(stageScale) and centerX and centerY and stageScale > 0) then return end
    local left, right, bottom, top
    for _, handle in ipairs(ui.handles) do
        if handle.previewGhost and handle.previewGhost:IsVisible() then handle = handle.previewGhost end
        local visible = handle:IsVisible()
        if Public(visible) and visible then
            local x, y, w, h = handle:GetRect()
            local scale = handle:GetEffectiveScale()
            if Public(x) and Public(y) and Public(w) and Public(h) and Public(scale) and x and w > 0 and h > 0 then
                scale = scale / stageScale
                left = math.min(left or math.huge, x * scale - centerX)
                bottom = math.min(bottom or math.huge, y * scale - centerY)
                right = math.max(right or -math.huge, (x + w) * scale - centerX)
                top = math.max(top or -math.huge, (y + h) * scale - centerY)
            end
        end
    end
    return left, bottom, right, top
end

function Layout.UpdateViewport(ui)
    local x, y = ui.panX, ui.panY
    if ui.fitMode then
        local left, bottom, right, top = FitBounds(ui)
        local topInset = ui.fitTop or 0
        local bottomInset = ui.fitBottom or 0
        local width = ui.canvas:GetWidth() - 2 * FIT_PADDING
        local height = ui.canvas:GetHeight() - 2 * FIT_PADDING - topInset - bottomInset
        ui.zoom = left and math.max(MIN_FIT_ZOOM, math.min(1, width / (right - left), height / (top - bottom))) or 1
        if left then
            x, y = -(left + right) * ui.zoom / 2, -(bottom + top) * ui.zoom / 2 + (bottomInset - topInset) / 2
        end
    end
    PositionStage(ui, x, y)
    if ui.zoomLabel then ui.zoomLabel:SetText(string.format("%d%%", math.floor(ui.zoom * 100 + .5))) end
end

function Layout.Fit(ui)
    if ui.kit.drag or ui.panning then return end
    ui.fitMode, ui.panX, ui.panY = true, 0, 0
    Layout.UpdateViewport(ui)
end

function Layout.KeepViewport(ui)
    if not ui.fitMode then return end
    -- Re-fitting after an edit can center the very element that was moved.
    ui.fitMode, ui.panX, ui.panY = nil, ui.viewX, ui.viewY
end

function Layout.SetZoom(ui, zoom)
    if ui.kit.drag or ui.panning then return end
    ui.fitMode, ui.zoom = nil, zoom
    Layout.UpdateViewport(ui)
end

function Layout.StepZoom(ui, direction)
    if direction == 0 then return end
    local first, last, step = 1, #ZOOM_STEPS, 1
    if direction < 0 then first, last, step = last, first, -1 end
    for index = first, last, step do
        local zoom = ZOOM_STEPS[index]
        if (zoom - ui.zoom) * step > .001 then return Layout.SetZoom(ui, zoom) end
    end
end

local function UpdatePan(ui)
    local pan = ui.panning
    local scale = ui.canvas:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = pan.x + (x - pan.cursorX) / scale, pan.y + (y - pan.cursorY) / scale
    if ui.viewX == x and ui.viewY == y then return end
    ui.fitMode, ui.panX, ui.panY = nil, x, y
    PositionStage(ui, x, y)
end

function Layout.StopPan(ui, finish)
    if not ui.panning then return end
    if finish then UpdatePan(ui) end
    ui.panning = nil
    ui.canvas:SetScript("OnUpdate", nil)
end

local function StartPan(ui, button)
    if ui.panning or ui.kit.drag or P.Combat() then return end
    local x, y = GetCursorPosition()
    ui.panning = { button = button, cursorX = x, cursorY = y, x = ui.viewX, y = ui.viewY }
    ui.canvas:SetScript("OnUpdate", function()
        if not IsMouseButtonDown(button) then
            Layout.StopPan(ui, true)
        else
            UpdatePan(ui)
        end
    end)
end

local function EndPan(ui, button)
    if not ui.panning or ui.panning.button ~= button then return false end
    Layout.StopPan(ui, true)
    return true
end

local function BindWheel(frame, wheel)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", wheel)
end

function Layout.BindViewportInput(ui)
    local canvas = ui.canvas
    ui.wheel = function(_, delta)
        if IsControlKeyDown() then
            Layout.StepZoom(ui, delta)
        elseif M.ForwardMenuScrollWheel then
            M.ForwardMenuScrollWheel(delta)
        else
            local scroll = M.scrollFrame
            local handler = scroll and scroll:GetScript("OnMouseWheel")
            if handler then handler(scroll, delta) end
        end
    end
    BindWheel(canvas, ui.wheel)
    for _, entry in ipairs(ui.zoomControls) do
        if entry[1] ~= ui.zoomLabel then BindWheel(entry[1], ui.wheel) end
    end
    if ui.backgroundButton then BindWheel(ui.backgroundButton, ui.wheel) end
    canvas:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" or button == "RightButton" or button == "MiddleButton" then StartPan(ui, button) end
    end)
    canvas:SetScript("OnMouseUp", function(_, button) EndPan(ui, button) end)
end

function Layout.BindHandleInput(ui, handle)
    BindWheel(handle, ui.wheel)
    local down, up, click = handle:GetScript("OnMouseDown"), handle:GetScript("OnMouseUp"), handle:GetScript("OnClick")
    handle:SetScript("OnMouseDown", function(self, button)
        self.previewPanClick = button == "MiddleButton" or button == "LeftButton" and IsControlKeyDown()
        if self.previewPanClick then
            StartPan(ui, button)
        elseif not ui.panning then
            down(self, button)
        end
    end)
    handle:SetScript("OnMouseUp", function(self, button)
        if not EndPan(ui, button) then up(self, button) end
    end)
    handle:SetScript("OnClick", function(self, button)
        if not self.previewPanClick and not ui.panning then click(self, button) end
        self.previewPanClick = nil
    end)
end

function Layout.Attach(ui, section, toolbar, record)
    local body, ctx = ui.body, ui.ctx
    local function Refresh()
        ui:Layout()
        ui:Paint()
    end
    body.Refresh = Refresh
    function body:ApplyCompactPreviewPresentation(compact)
        compact = compact == true
        -- Settings links and header resizing reapply the current presentation.
        -- Keep the selected element and its X/Y input during a reflow.
        if ui.compact ~= compact then
            ui:CancelDrag()
            ui:Select(nil)
            ui.compact = compact
        end
        Refresh()
    end
    -- Use the same page ownership lifecycle as UF/GF. The fixed section owns
    -- the header anchor; scrolling only moves the settings wrapper below it.
    if W.AttachPinnedPreview then
        W.AttachPinnedPreview(section, body, { stateKey = "nameplatePreview",
            pageKey = ctx.key, wrapper = ctx.wrapper })
    end
    local expander
    if W.AttachFixedPreviewExpander then
        expander = W.AttachFixedPreviewExpander(section, toolbar, body, {
            pageKey = ctx.key, wrapper = ctx.wrapper,
            compactHeight = 116, compactTop = -38,
            expandedHeight = 480, expandedTop = -38, expandedSectionHeight = 526,
            refreshPreview = Refresh,
        })
    end
    ui.expander = expander
    if expander and expander.button then
        ui.hint:ClearAllPoints()
        ui.hint:SetPoint("LEFT", section.title or toolbar, section.title and "RIGHT" or "LEFT", section.title and 12 or 160, 0)
        -- The hint ends before Compare all, whose width follows its caption.
        if ui.groupPreviewButton then
            ui.hint:SetPoint("RIGHT", ui.groupPreviewButton, "LEFT", -8, 0)
        else
            ui.hint:SetPoint("RIGHT", expander.button, "LEFT", -124, 0)
        end
    end
    -- FixedPreviewSection reserves the compact height on construction. The
    -- expander registers controls but does not initialize their presentation.
    -- Initialize before activation even if another page selected Compact.
    if ui.groupPreviewButton then
        ui.groupPreviewButton:ClearAllPoints()
        ui.groupPreviewButton:SetPoint("RIGHT", expander and expander.button or toolbar, expander and "LEFT" or "RIGHT", -8, 0)
    end
    body:ApplyCompactPreviewPresentation(expander ~= nil)
    body:SetScript("OnSizeChanged", Refresh)
    body:SetScript("OnShow", Refresh)
    if record then
        record.onActivate = function()
            -- Ownership settling can hide the body before the wrapper shows.
            -- Compact activation must wake it just as the expander does.
            body:SetFrameLevel(section:GetFrameLevel() + 2)
            body:Show()
            if expander and expander.expanded then expander:Relayout("NAMEPLATES_PREVIEW") end
            Refresh()
        end
    end
end
