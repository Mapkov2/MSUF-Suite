local _, P = ...
local K, Tr = P.PreviewCanvas, P.Tr
local function Hits(ui, win)
    local targets = {}
    targets.body = K.Jump(ui, win.body, win.body, "suite_damageMeter_windows")
    targets.body:SetFrameLevel(win.body:GetFrameLevel())
    targets.header = K.Jump(ui, win.header, win.header, "suite_damageMeter_window")
    targets.header:SetFrameLevel(win.header:GetFrameLevel())
    targets.title = K.Jump(ui, win.title, win.header, "suite_damageMeter_window")
    targets.timer = K.Jump(ui, win.timer, win.header, "suite_damageMeter_timer")
    local sections = { settings = "general", reset = "general", session = "windows", type = "windows" }
    for key, button in pairs(win.buttons) do
        button:SetFrameLevel(win.header:GetFrameLevel() + 8)
        local section = "suite_damageMeter_" .. sections[key]
        button:SetScript("OnClick", function() ui:Focus(section) end)
        P.HM.SkipHistoryCheckpoint(button)
    end
    targets.rows = {}
    for i, row in ipairs(win.rows) do
        row:SetScript("OnClick", function() ui:Focus("suite_damageMeter_bars") end)
        targets.rows[i] = { name = K.Jump(ui, row.nameText, row, "suite_damageMeter_text"),
            value = K.Jump(ui, row.valueText, row, "suite_damageMeter_text"),
            icon = K.Jump(ui, row.icon, row, "suite_damageMeter_bars") }
        P.HM.SkipHistoryCheckpoint(row)
    end
    return targets
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
    stage:SetPoint("TOPLEFT", 0, 0)
    stage:SetSize(width - 8, 100)
    local title = K.Text(ui.header, "Preview", 16, -94, width)
    local footer = K.Text(ui.header, "", 16, -230, width)
    local preview = { stage = stage, viewport = viewport, title = title, footer = footer }
    ui.meterPreview = preview
    K.Watch(ui, function()
        if not K.Runtime("MSUF_Suite_DamageMeter", "DamageMeterDrawMenuPreview") then
            P.SetTranslatedText(footer, Tr("Preview is available outside combat."))
            return
        end
        local win = P.S.DamageMeterDrawMenuPreview(stage, selected())
        if not preview.targets then preview.targets = Hits(ui, win) end
        local native = UIParent:GetEffectiveScale() / ui.header:GetEffectiveScale()
        local w, h = win.frame:GetWidth(), win.frame:GetHeight()
        local fit = math.min(1, (width - 8) / (w * native), 250 / (h * native))
        local scale, height = native * fit, h * native * fit
        if preview.scale ~= scale or preview.height ~= height or preview.width ~= w then
            preview.scale, preview.height, preview.width = scale, height, w
            stage:SetScale(scale)
            stage:SetSize(w, h)
            viewport:SetHeight(height)
            footer:ClearAllPoints()
            footer:SetPoint("TOPLEFT", ui.header, "TOPLEFT", 16, -128 - height)
            P.SetTranslatedText(title, fit < .995 and Tr("Preview %d%%"):format(math.floor(fit * 100 + .5)) or Tr("Preview"))
        end
        local scope = ui.selected == "window" and Tr("Only the selected window") or Tr("Applies to all windows")
        if preview.scope ~= scope then
            preview.scope = scope
            P.SetTranslatedText(footer, scope .. "\n" .. Tr("Sample values. Click an element to open its settings."))
        end
        P.MenuWorkspace.FitHeader(ui, 144 + height + math.ceil(footer:GetStringHeight() or 28))
    end)
end
