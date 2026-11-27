local _, P = ...
local K, Tr = P.PreviewCanvas, P.Tr
local E, Layers = P.MeterPreviewEditor, P.MeterPreviewLayers
local function Hits(ui, win)
    local preview = ui.meterPreview
    local targets = {}
    local function Properties(handle, size, layer, fallback)
        handle.sizeSetting, handle.layerSetting, handle.defaultSizeSetting = size or false, layer or false, fallback or false
    end
    targets.body = K.Jump(ui, win.body, win.body, "suite_damageMeter_windows")
    targets.body:SetFrameLevel(win.body:GetFrameLevel())
    targets.header = K.Jump(ui, win.header, win.header, "suite_damageMeter_window")
    targets.header:SetFrameLevel(win.header:GetFrameLevel())
    targets.title = K.Jump(ui, win.title, win.header, "suite_damageMeter_window")
    targets.timer = K.Jump(ui, win.timer, win.header, "suite_damageMeter_timer")
    E.Handle(preview, targets.body, win.body, "window", "Window", "window", "suite_damageMeter_windows", "w1Width")
    E.Handle(preview, targets.header, win.header, "window", "Header", "header", "suite_damageMeter_window", "headerHeight")
    E.Handle(preview, targets.title, win.title, "titleOffset", "Title", "title", "suite_damageMeter_window", "titleSize")
    E.Handle(preview, targets.timer, win.timer, "headerTimerOffset", "Combat timer", "timer", "suite_damageMeter_timer", "headerTimerSize")
    targets.timer.settingsKey = "combatTime"
    targets.body.widthSetting, targets.body.heightSetting, targets.body.layerSetting = "windowWidth", "windowHeight", "windowLayer"
    Properties(targets.header, "headerHeight")
    Properties(targets.title, "titleSize", nil, "headerFontSize")
    Properties(targets.timer, "headerTimerSize", nil, "headerFontSize")
    local sections = { settings = "general", reset = "damageMeter_module", session = "windows", type = "windows", target = "button_target" }
    targets.buttons = {}
    local buttonLabels = { settings = "Window settings", reset = "Reset combat data", session = "Fight", type = "Meter", target = "Filter damage by target" }
    local buttonKeys = { settings = "windowCount", reset = "action.reset_data", session = "w1Session", type = "w1Type", target = "targetSelector" }
    for key, button in pairs(win.buttons) do
        button:SetFrameLevel(win.header:GetFrameLevel() + 8)
        local section = "suite_damageMeter_" .. sections[key]
        button:SetScript("OnClick", function() ui:Focus(section) end)
        local target = K.Jump(ui, button, win.header, section)
        target:SetFrameLevel(win.header:GetFrameLevel() + 9)
        targets.buttons[key] = target
        E.Handle(preview, target, button, key .. "Offset", buttonLabels[key], "buttons", section, buttonKeys[key])
        Properties(target, key .. "Size", nil, "headerIconSize")
        if key == "session" then
            target.openSample = function(owner) P.S.DamageMeterOpenPreviewFight(win, owner, ui.refreshPreview) end
        end
        P.HM.SkipHistoryCheckpoint(button)
    end
    targets.rows = {}
    for i, row in ipairs(win.rows) do
        row:SetScript("OnClick", function() ui:Focus("suite_damageMeter_bars") end)
        targets.rows[i] = { barHit = K.Jump(ui, row, row, "suite_damageMeter_bars"),
            name = K.Jump(ui, row.nameText, row, "suite_damageMeter_namesFont"),
            value = K.Jump(ui, row.valueText, row, "suite_damageMeter_valuesFont"),
            icon = K.Jump(ui, row.icon, row, "suite_damageMeter_bars") }
        local hits = targets.rows[i]
        hits.barHit:SetFrameLevel(row:GetFrameLevel() + 1)
        E.Handle(preview, hits.barHit, row, "barsOffset", "Bars", "bars", "suite_damageMeter_bars", "barHeight")
        E.Handle(preview, hits.name, row.nameText, "nameOffset", "Name", "name", "suite_damageMeter_namesFont", "leftSize")
        E.Handle(preview, hits.value, row.valueText, "valueOffset", "Value", "value", "suite_damageMeter_valuesFont", "rightSize")
        E.Handle(preview, hits.icon, row.icon, "iconOffset", "Bar icons", "icon", "suite_damageMeter_bars", "iconStyle")
        Properties(hits.barHit, "barHeight", "barsLayer")
        Properties(hits.name, "leftSize", "nameLayer")
        Properties(hits.value, "rightSize", "valueLayer")
        Properties(hits.icon, "iconSize", "iconLayer", "barHeight")
        if row.rankText then
            hits.rank = K.Jump(ui, row.rankText, row, "suite_damageMeter_namesFont")
            E.Handle(preview, hits.rank, row.rankText, "nameOffset", "Show rank numbers", "name", "suite_damageMeter_namesFont", "rank")
            Properties(hits.rank, "leftSize", "nameLayer")
        end
        P.HM.SkipHistoryCheckpoint(row)
    end
    return targets
end

local function ExtraTargets(preview, win)
    if win.panel and not preview.targets.details then
        local handle = K.Jump(preview.ui, win.panel, win.panel, "suite_damageMeter_detailsFont")
        E.Handle(preview, handle, win.panel, "window", "Details", "details", "suite_damageMeter_detailsFont", "detailsFontCustom")
        preview.targets.details = handle
    end
    if not win.sampleTimer or preview.targets.floatingTimer then return end
    local handle = K.Jump(preview.ui, win.sampleTimer, preview.stage, "suite_damageMeter_timer")
    E.Handle(preview, handle, win.sampleTimer, "timerDock", "Floating timer", "floatingTimer", "suite_damageMeter_timer", "timerSize")
    handle.settingsKey = "combatTime"
    handle.sizeSetting = "timerSize"
    preview.targets.floatingTimer = handle
end

-- Screen placement uses the live window's bottom-right origin and scale,
-- and the free timer's screen-center origin. The styling sample stays fitted.
local function PositionMarker(marker, map, point, x, y, scale, widthHint, heightHint)
    local width, height = map:GetWidth(), map:GetHeight()
    local markerWidth, markerHeight = math.min(width, widthHint), math.min(height, heightHint)
    marker.position:SetSize(markerWidth, markerHeight)
    local halfW, halfH = markerWidth / 2, markerHeight / 2
    local minX, maxX, minY, maxY = halfW, width - halfW, halfH, height - halfH
    if point == "BOTTOMRIGHT" then minX, maxX, minY, maxY = halfW * 2, width, 0, height - halfH * 2 end
    local placedX, placedY = math.max(minX, math.min(maxX, x)), math.max(minY, math.min(maxY, y))
    marker.positionScale = scale
    marker.clampedX, marker.clampedY = (placedX - x) / scale, (placedY - y) / scale
    marker.position:ClearAllPoints()
    marker.position:SetPoint(point, map, "BOTTOMLEFT", placedX, placedY)
end

local function PaintScreen(preview, win)
    local screen, c = preview.screen, P.S.Config("damageMeter")
    local width, height = math.max(1, UIParent:GetWidth()), math.max(1, UIParent:GetHeight())
    local scale = math.min(preview.availableWidth / width, 220 / height)
    screen:SetSize(width * scale, height * scale)
    local marker, timer = screen.window, screen.timer
    local x, y = E.Keys(preview, marker)
    marker:SetShown(x ~= nil)
    if x then
        local zoom = win.previewZoom or 1
        local windowScale = scale * zoom
        PositionMarker(marker, screen, "BOTTOMRIGHT", (width + c[x] * zoom) * scale, c[y] * windowScale, windowScale,
            math.max(84, win.frame:GetWidth() * windowScale), math.max(22, win.frame:GetHeight() * windowScale))
    end
    local timerShown = c.combatTime and c.timer and c.timerAnchor == 1
    timer:SetShown(timerShown)
    if timerShown then
        PositionMarker(timer, screen, "CENTER", (width / 2 + c.timerX) * scale, (height / 2 + c.timerY) * scale, scale, 122, 22)
    end
    return screen:GetHeight()
end

local function LayoutPlacementControls(preview)
    local width = math.floor((preview.availableWidth - 8) / 2)
    preview.buttonGroup.position:SetWidth(math.min(width, 122))
    preview.screenModeButton:SetWidth(math.min(width, 146))
end

local function PlacementButton(preview, parent, label, prefix, layer, section, key)
    local pos = CreateFrame("Frame", nil, parent)
    local button = P.T.Button(parent, label, 122, 22)
    pos:SetSize(122, 22)
    E.Handle(preview, button, pos, prefix, label, layer, "suite_damageMeter_" .. section, key)
    button.position = pos
    if P.M.AddTooltip then P.M.AddTooltip(button, "Drag to move", nil, { hook = true }) end
    return button
end

local function PlacementControls(preview)
    local ui = preview.ui
    local screen = P.T.Panel(preview.viewport, nil, P.T.colors.panel2, P.T.colors.borderSoft)
    screen:SetPoint("TOP", preview.viewport, "TOP")
    screen:Hide()
    preview.screen = screen
    screen.window = PlacementButton(preview, screen, "Window", "screenWindow", "window", "windows", "w1Width")
    screen.timer = PlacementButton(preview, screen, "Floating timer", "screenTimer", "floatingTimer", "timer", "timerSize")
    screen.timer.settingsKey = "combatTime"
    local mode = P.T.Button(ui.header, "Screen position", 146, 22)
    mode:SetPoint("TOPRIGHT", ui.header, "TOPRIGHT", -16, -90)
    P.HM.SkipHistoryCheckpoint(mode)
    local group = PlacementButton(preview, ui.header, "Buttons", "buttonsOffset", "buttons", "window", "headerIconSize")
    group.position:SetPoint("RIGHT", mode, "LEFT", -8, 0)
    preview.buttonGroup, preview.screenModeButton = group, mode
    preview.showScreen = function(enabled, handle)
        if preview.screenMode ~= enabled then
            E.Select(preview, nil)
            preview.screenMode = enabled
            P.SetButtonText(mode, enabled and Tr("Preview") or Tr("Screen position"))
            ui.refreshPreview()
        end
        if handle and handle:IsVisible() then E.Select(preview, handle) end
    end
    mode:SetScript("OnClick", function() preview.showScreen(not preview.screenMode) end)
end

-- Position search leads to the preview's shared coordinate fields instead of
-- creating extra sliders in the accordions.
function E.ResolvePosition(preview, key)
    local axis = key:sub(-1)
    local window = key:match("^w%d+[XY]$") ~= nil
    if window then key = "w" .. preview.selected() .. axis end
    local screen = window or key == "timerX" or key == "timerY"
    if not screen then
        for _, handle in ipairs(preview.handles) do
            local x, y = E.Keys(preview, handle)
            if x == key or y == key then
                preview.layers.window, preview.layers[handle._previewLayerKey] = true, true
                if handle._previewLayerKey == "buttons" or handle._previewLayerKey == "title"
                    or handle._previewLayerKey == "timer" then preview.layers.header = true end
                if handle._previewLayerKey ~= "floatingTimer" then preview.layers.details = false end
                break
            end
        end
    end
    preview.showScreen(screen)
    preview.ui.refreshPreview()
    for _, handle in ipairs(preview.handles) do
        local x, y = E.Keys(preview, handle)
        if (x == key or y == key) and handle:IsVisible() then
            E.Select(preview, handle)
            return preview.selection and (axis == "X" and preview.selection.axisX or preview.selection.axisY) or handle
        end
    end
    return preview.screenModeButton
end

-- The stage shows the window at its own scale (its Window scale), so the
-- preview grows and shrinks with it, down to what the viewport holds.
local function Fit(preview, win)
    local native = UIParent:GetEffectiveScale() / preview.ui.header:GetEffectiveScale()
    local zoom = win.previewZoom or 1
    local w, h = win.previewWidth or win.frame:GetWidth(), win.previewHeight or win.frame:GetHeight()
    if not win.previewHeight and P.Get("damageMeter", "headerOutside") then h = h + P.Get("damageMeter", "headerHeight") end
    local fit = math.min(1, preview.availableWidth / (w * native * zoom), 250 / (h * native * zoom))
    local scale, height = native * fit * zoom, h * native * fit * zoom
    if preview.scale ~= scale or preview.height ~= height or preview.width ~= w then
        preview.scale, preview.height, preview.width = scale, height, w
        preview.stage:SetScale(scale)
        preview.stage:SetSize(w, h)
        local percent = math.floor(fit * zoom * 100 + .5)
        preview.fitTitle = percent ~= 100 and Tr("Preview %d%%"):format(percent) or Tr("Preview")
    end
end

local function Paint(preview)
    local ui = preview.ui
    if not K.Runtime("MSUF_Suite_DamageMeter", "DamageMeterDrawMenuPreview") then
        P.SetTranslatedText(preview.footer, Tr("Preview is available outside combat."))
        return
    end
    local win = P.S.DamageMeterDrawMenuPreview(preview.stage, preview.selected(), preview.layers.details)
    if not preview.targets then preview.targets = Hits(ui, win) end
    ExtraTargets(preview, win)
    Fit(preview, win)
    Layers.Paint(preview, win)
    local screenMode = preview.screenMode == true
    local heading = screenMode and Tr("Screen position") or preview.fitTitle
    if heading ~= preview.heading then
        preview.heading = heading
        P.SetTranslatedText(preview.title, heading)
    end
    preview.stage:SetShown(not screenMode)
    preview.screen:SetShown(screenMode)
    preview.chips:SetShown(not screenMode)
    preview.buttonGroup:SetShown(not screenMode and preview.layers.window and preview.layers.header and preview.layers.buttons
        and P.Get("damageMeter", "headerVisible"))
    local height = screenMode and PaintScreen(preview, win) or preview.height
    if preview.viewport:GetHeight() ~= height then preview.viewport:SetHeight(height) end
    E.Refresh(preview)
    local handle = preview.viewport._selectedHandle
    local onlyWindow = handle and (handle.widthSetting == "windowWidth" or handle.offsetPrefix == "screenWindow")
    local scope = onlyWindow and Tr("Only the selected window") or not screenMode and Tr("Applies to all windows") or ""
    local hint = (screenMode or E.Keys(preview, handle)) and Tr("Drag or use arrows to move; click for settings.")
        or Tr("Sample values. Click an element to open its settings.")
    if preview.scope ~= scope or preview.hint ~= hint then
        preview.scope, preview.hint = scope, hint
        P.SetTranslatedText(preview.footer, scope ~= "" and scope .. "\n" .. hint or hint)
    end
    local selectionHeight = preview.selectionHeight or 0
    local propertiesHeight = preview.propertiesHeight or 0
    preview.properties:ClearAllPoints()
    preview.properties:SetPoint("TOPLEFT", preview.viewport, "BOTTOMLEFT", 0, -8 - selectionHeight)
    preview.chips:ClearAllPoints()
    preview.chips:SetPoint("TOPLEFT", preview.viewport, "BOTTOMLEFT", 0, -8 - selectionHeight - propertiesHeight)
    preview.footer:ClearAllPoints()
    preview.footer:SetPoint("TOPLEFT", preview.chips, screenMode and "TOPLEFT" or "BOTTOMLEFT", 0, -8)
    local chipsHeight = not screenMode and preview.chips:GetHeight() or 0
    P.MenuWorkspace.FitHeader(ui, 168 + height + selectionHeight + propertiesHeight
        + chipsHeight + math.ceil(preview.footer:GetStringHeight() or 28))
end

local choiceCount, choices
local function WindowChoices()
    local count = P.Get("damageMeter", "windowCount")
    if count ~= choiceCount then
        choiceCount, choices = count, {}
        for i = 1, count do choices[i] = { value = i, text = Tr("Window %d"):format(i) } end
    end
    return choices
end

function P.BindMeterWindowPicker(ctx, parent, y, width, selected, setSelected)
    return P.M.BindDropdownAt(ctx, parent, Tr("Window"), 16, y, WindowChoices, width, selected, setSelected,
        P.Meta("suite_damageMeter", "damageMeter", "window.selected", "ephemeral", "suite_damageMeter_windows"))
end

function P.BuildMeterMenuPreview(ui, selected, setSelected)
    if not ui then return end
    local width = ui.width - 32
    local picker = P.BindMeterWindowPicker(ui.ctx, ui.header, -42, width, selected, setSelected)
    ui.ctx.meterWindowPicker = picker
    P.HM.SetSearchTargetPrepare(picker, function() ui.select("window")
    return true end)
    local viewport = CreateFrame("Frame", nil, ui.header)
    viewport:SetPoint("TOPLEFT", 20, -142)
    viewport:SetSize(width - 8, 250)
    local stage = CreateFrame("Frame", nil, viewport)
    stage:SetClipsChildren(true)
    stage:SetPoint("TOPLEFT", 0, 0)
    stage:SetSize(width - 8, 100)
    local title = K.Text(ui.header, "Preview", 16, -118, width)
    local footer = K.Text(ui.header, "", 16, -230, width)
    local preview = { stage = stage, viewport = viewport, title = title, footer = footer,
        ui = ui, selected = selected, availableWidth = width - 8 }
    ui.meterPreview = preview
    E.Build(preview)
    PlacementControls(preview)
    LayoutPlacementControls(preview)
    Layers.Build(preview)
    K.Watch(ui, function() Paint(preview) end)
    ui.header:HookScript("OnSizeChanged", function()
        local headerWidth = ui.header:GetWidth()
        if not headerWidth or headerWidth <= 32 then return end
        preview.availableWidth = math.max(200, headerWidth - 40)
        viewport:SetWidth(preview.availableWidth)
        LayoutPlacementControls(preview)
        Layers.Layout(preview)
        ui.refreshPreview()
    end)
end
