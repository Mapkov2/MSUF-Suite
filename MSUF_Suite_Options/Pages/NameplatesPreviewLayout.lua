local _, P = ...
local M, W, SB = P.M, P.W, P.M.PreviewSelectionBar
local Public = P.Suite.Public
local Layout = {}
P.NameplatesPreviewLayout = Layout

local TOOL_HEIGHT, TOOL_GAP = 20, 6
local LABEL_INSET = 8
local ZOOM_STEPS = { 0.35, 0.50, 0.75, 1, 1.25, 1.50, 2, 3, 4 }
local FIT_PADDING, MIN_FIT_ZOOM = 20, 0.05

function Layout.RenderName(s, m, Get, SetupNumber, Place)
    local ID = "nameplates"
    local prefix, name, bar = s.prefix, s.name, s.bar
    name:EnableMouse(not m.npcWorldName and not s.static)
    local config = P.S.Config(ID)
    local shared = not (m.npcWorldName or m.skinDisabled) and P.Suite.NameplateText.Shared(config)
    local size = P.Suite.NameplateText.ResolveSize(config, prefix .. "NameSize", shared)
    local anchor = not (m.namesOnly or m.skinDisabled) and Get(ID, "look") ~= 2 and P.Suite.NameplateText.NameAnchor(config, prefix)
    local centered = m.centerName or m.namesOnly and not m.nameOnlyScope
    name:SetHeight(not (m.npcWorldName or m.skinDisabled) and (shared or Get(ID, prefix .. "TextEnabled")) and size > 0 and size
        or SetupNumber("healthBarFontHeight", (m.classic and 10 or m.forever and 14 or 12) * m.vertical))
    name:ClearAllPoints()
    if m.npcWorldName then
        name:SetPoint("CENTER", s.cell, "CENTER", 0, 0)
        name:SetWidth(170)
    elseif m.centerName then
        local spacing = m.nameOnlyScope and m.nameSpacing or 2
        local y = -4 + m.nativeBarHeight / 2 + m.heightDelta + spacing + Get(ID, prefix .. "NameOffsetY")
        name:SetPoint("BOTTOM", s.cell, "CENTER", 0, y)
        name:SetWidth(170)
    elseif centered then
        if m.nameAnchor == 1 then Place(s, name, "CENTER", bar, "CENTER", 0, 0, "Name")
        else Place(s, name, "BOTTOM", bar, "TOP", 0, 2, "Name") end
        name:SetWidth(170)
    elseif anchor then
        Place(s, name, anchor, bar, anchor, 0, 0, "Name")
        name:SetWidth(m.availableNameWidth)
    elseif m.nameAnchor == 3 then
        Place(s, name, "BOTTOM", bar, "TOP", m.classic and 8.625 * m.horizontal or 0, m.nameSpacing, "Name")
        name:SetWidth(m.barWidth - 8 + (m.classic and m.classicInset or 0))
    elseif m.nameAnchor == 2 then
        Place(s, name, "BOTTOMLEFT", bar, "TOPLEFT", 4, m.nameSpacing, "Name")
        name:SetWidth(m.nativeLevel and m.barWidth + m.reserve - 4 or m.availableNameWidth)
    else
        Place(s, name, "LEFT", bar, "LEFT", 4, 0, "Name")
        name:SetWidth(m.availableNameWidth)
    end
    s.nameText:SetWidth(centered and 170 or m.nameAnchor == 3 and name:GetWidth() or m.availableNameWidth)
    local justify = anchor and (anchor:find("LEFT", 1, true) and "LEFT" or anchor:find("RIGHT", 1, true) and "RIGHT" or "CENTER")
    s.nameText:SetJustifyH(justify or ((centered or m.nameAnchor == 3) and "CENTER" or "LEFT"))
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
    local tools, width = ui.tools, ui.body:GetWidth()
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
        PlaceTool(control, tools, "TOPLEFT", x, control == ui.zoomLabel and y - 4 or y)
        x = x + size + TOOL_GAP
    end
    local pickerSize = Layout.FitButton(ui.elementPicker, width, 96)
    local pickerWrapped = x + pickerSize > width
    if pickerWrapped then y = y - step end
    PlaceTool(ui.elementPicker, tools, "TOPRIGHT", 0, y)

    local targetSize = Layout.FitButton(ui.targetStateButton, width, 126)
    local focusSize = Layout.FitButton(ui.focusStateButton, width, 96)
    if targetSize + TOOL_GAP + focusSize <= width then
        y = y - step
        PlaceTool(ui.targetStateButton, tools, "TOPRIGHT", -focusSize - TOOL_GAP, y)
    elseif pickerWrapped and targetSize + TOOL_GAP + pickerSize <= width then
        PlaceTool(ui.targetStateButton, tools, "TOPRIGHT", -pickerSize - TOOL_GAP, y)
        y = y - step
    else
        PlaceTool(ui.targetStateButton, tools, "TOPRIGHT", 0, y - step)
        y = y - 2 * step
    end
    PlaceTool(ui.focusStateButton, tools, "TOPRIGHT", 0, y)
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
    local raidTop = math.min(42 - y, math.max(8, height - ui.raidPalette:GetHeight() - 4))
    ui.raidPalette:ClearAllPoints()
    ui.raidPalette:SetPoint("TOPRIGHT", ui.canvas, "TOPRIGHT", -8, -raidTop)
    ui.fitTop = math.max(8 + ui.samples:GetHeight(), raidTop + ui.raidPalette:GetHeight())
end

function Layout.Apply(self)
    local body, canvas, tools, rail = self.body, self.canvas, self.tools, self.layerRail
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    local editing = not self.compact and not self.groupPreviewEnabled
    tools:SetShown(editing)
    if SB then SB.SetShown(body, editing) end
    rail:SetShown(editing)
    self.samples:SetShown(editing)
    self.raidPalette:SetShown(editing)
    self.hint:SetShown(editing)
    if not editing then
        self.fitTop = 0
        canvas:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 8)
        return
    end
    self:LayoutLayerRail()
    -- Anchor each row above the actual wrapped rail, leaving all remaining
    -- height to the canvas. Width changes therefore need no guessed row count.
    local anchor = rail
    if self.selection then
        self.selection:ClearAllPoints()
        self.selection:SetPoint("BOTTOMLEFT", rail, "TOPLEFT", 0, 6)
        self.selection:SetPoint("BOTTOMRIGHT", rail, "TOPRIGHT", 0, 6)
        anchor = self.selection
    end
    tools:ClearAllPoints()
    tools:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 5)
    tools:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 5)
    canvas:SetPoint("BOTTOMRIGHT", tools, "TOPRIGHT", 0, 4)
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
        local width = ui.canvas:GetWidth() - 2 * FIT_PADDING
        local height = ui.canvas:GetHeight() - 2 * FIT_PADDING - topInset
        ui.zoom = left and math.max(MIN_FIT_ZOOM, math.min(1, width / (right - left), height / (top - bottom))) or 1
        if left then
            x, y = -(left + right) * ui.zoom / 2, -(bottom + top) * ui.zoom / 2 - topInset / 2
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
        ui.hint:SetPoint("RIGHT", expander.button, "LEFT", -124, 0)
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
