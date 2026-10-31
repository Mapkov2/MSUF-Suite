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
    targets.body.widthSetting, targets.body.heightSetting, targets.body.layerSetting = "windowWidth", "windowHeight", "windowLayer"
    Properties(targets.header, "headerHeight")
    Properties(targets.title, "titleSize", nil, "headerFontSize")
    Properties(targets.timer, "headerTimerSize", nil, "headerFontSize")
    local sections = { settings = "general", reset = "damageMeter_module", session = "windows", type = "windows", target = "details" }
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
        P.HM.SkipHistoryCheckpoint(button)
    end
    targets.rows = {}
    for i, row in ipairs(win.rows) do
        row:SetScript("OnClick", function() ui:Focus("suite_damageMeter_bars") end)
        targets.rows[i] = { barHit = K.Jump(ui, row, row, "suite_damageMeter_bars"),
            name = K.Jump(ui, row.nameText, row, "suite_damageMeter_text"),
            value = K.Jump(ui, row.valueText, row, "suite_damageMeter_text"),
            icon = K.Jump(ui, row.icon, row, "suite_damageMeter_bars") }
        local hits = targets.rows[i]
        hits.barHit:SetFrameLevel(row:GetFrameLevel() + 1)
        E.Handle(preview, hits.barHit, row, "barsOffset", "Bars", "bars", "suite_damageMeter_bars", "barHeight")
        E.Handle(preview, hits.name, row.nameText, "nameOffset", "Name", "name", "suite_damageMeter_text", "leftSize")
        E.Handle(preview, hits.value, row.valueText, "valueOffset", "Value", "value", "suite_damageMeter_text", "rightSize")
        E.Handle(preview, hits.icon, row.icon, "iconOffset", "Bar icons", "icon", "suite_damageMeter_bars", "iconStyle")
        Properties(hits.barHit, "barHeight", "barsLayer")
        Properties(hits.name, "leftSize", "nameLayer")
        Properties(hits.value, "rightSize", "valueLayer")
        Properties(hits.icon, "iconSize", "iconLayer", "barHeight")
        if row.rankText then
            hits.rank = K.Jump(ui, row.rankText, row, "suite_damageMeter_text")
            E.Handle(preview, hits.rank, row.rankText, "nameOffset", "Show rank numbers", "name", "suite_damageMeter_text", "rank")
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
    E.Handle(preview, handle, win.sampleTimer, "window", "Floating timer", "floatingTimer", "suite_damageMeter_timer", "timerSize")
    handle.sizeSetting = "timerSize"
    preview.targets.floatingTimer = handle
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
        preview.viewport:SetHeight(height)
        local percent = math.floor(fit * zoom * 100 + .5)
        P.SetTranslatedText(preview.title, percent ~= 100 and Tr("Preview %d%%"):format(percent) or Tr("Preview"))
    end
end

function P.BuildMeterMenuPreview(ui, selected, setSelected)
    if not ui then return end
    local width, choices = ui.width - 32, {}
    for i = 1, P.Suite.DamageMeterMaxWindows do choices[i] = { value = i, text = Tr("Window %d"):format(i) } end
    local picker = P.M.BindDropdownAt(ui.ctx, ui.header, Tr("Window"), 16, -42, choices, width,
        selected, setSelected, P.Meta("suite_damageMeter", "damageMeter", "window.selected", "ephemeral", "suite_damageMeter_windows"))
    ui.ctx.meterWindowPicker = picker
    P.HM.SetSearchTargetPrepare(picker, function() ui.select("window")
    return true end)
    local viewport = CreateFrame("Frame", nil, ui.header)
    viewport:SetPoint("TOPLEFT", 20, -118)
    viewport:SetSize(width - 8, 250)
    local stage = CreateFrame("Frame", nil, viewport)
    stage:SetClipsChildren(true)
    stage:SetPoint("TOPLEFT", 0, 0)
    stage:SetSize(width - 8, 100)
    local title = K.Text(ui.header, "Preview", 16, -94, width)
    local footer = K.Text(ui.header, "", 16, -230, width)
    local preview = { stage = stage, viewport = viewport, title = title, footer = footer,
        ui = ui, selected = selected, availableWidth = width - 8 }
    ui.meterPreview = preview
    E.Build(preview)
    Layers.Build(preview)
    K.Watch(ui, function()
        if not K.Runtime("MSUF_Suite_DamageMeter", "DamageMeterDrawMenuPreview") then
            P.SetTranslatedText(footer, Tr("Preview is available outside combat."))
            return
        end
        local win = P.S.DamageMeterDrawMenuPreview(stage, selected(), preview.layers.details)
        if not preview.targets then preview.targets = Hits(ui, win) end
        ExtraTargets(preview, win)
        Fit(preview, win)
        Layers.Paint(preview, win)
        E.Refresh(preview)
        local handle = viewport._selectedHandle
        local scope = handle and handle.widthSetting == "windowWidth" and Tr("Only the selected window") or Tr("Applies to all windows")
        local hint = handle and handle.canMove and Tr("Click to select; drag or use arrow keys; edit exact X/Y below.")
            or Tr("Sample values. Click an element to open its settings.")
        if preview.scope ~= scope or preview.hint ~= hint then
            preview.scope, preview.hint = scope, hint
            P.SetTranslatedText(footer, scope .. "\n" .. hint)
        end
        local selectionHeight = preview.selectionHeight or 0
        local propertiesHeight = preview.propertiesHeight or 0
        preview.properties:ClearAllPoints()
        preview.properties:SetPoint("TOPLEFT", viewport, "BOTTOMLEFT", 0, -8 - selectionHeight)
        preview.chips:ClearAllPoints()
        preview.chips:SetPoint("TOPLEFT", viewport, "BOTTOMLEFT", 0, -8 - selectionHeight - propertiesHeight)
        footer:ClearAllPoints()
        footer:SetPoint("TOPLEFT", preview.chips, "BOTTOMLEFT", 0, -8)
        P.MenuWorkspace.FitHeader(ui, 144 + preview.height + selectionHeight + propertiesHeight
            + preview.chips:GetHeight() + math.ceil(footer:GetStringHeight() or 28))
    end)
    ui.header:HookScript("OnSizeChanged", function()
        local headerWidth = ui.header:GetWidth()
        if not headerWidth or headerWidth <= 32 then return end
        preview.availableWidth = math.max(200, headerWidth - 40)
        viewport:SetWidth(preview.availableWidth)
        Layers.Layout(preview)
        ui.refreshPreview()
    end)
end
