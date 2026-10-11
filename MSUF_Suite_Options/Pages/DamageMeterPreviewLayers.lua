local _, P = ...
local Layers, Tr, T = {}, P.Tr, P.T
P.MeterPreviewLayers = Layers
local SPECS = {
    { "window", "Window" }, { "header", "Header" }, { "bars", "Bars" },
    { "icon", "Bar icons" }, { "name", "Name" }, { "value", "Value" },
    { "title", "Title" }, { "timer", "Combat timer" }, { "buttons", "Buttons" },
}

function Layers.Layout(preview)
    local width = preview.availableWidth
    local x, row = 10, 0
    for _, button in ipairs(preview.layerButtons) do
        if x > 10 and x + button:GetWidth() > width - 10 then x, row = 10, row + 1 end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", preview.chips, "TOPLEFT", x, -25 - row * 24)
        x = x + button:GetWidth() + 5
    end
    preview.chips:SetSize(width, 50 + row * 24)
end

function Layers.Build(preview)
    preview.layers, preview.layerButtons = {}, {}
    local chips = CreateFrame("Frame", nil, preview.ui.header)
    preview.chips = chips
    local H = P.M.PreviewHelpers or {}
    if H.ApplyPreviewChrome then H.ApplyPreviewChrome(chips, "sidebar", T) end
    local title = T.Font(chips, "GameFontDisableSmall", "Preview Layers", T.colors.muted)
    title:SetPoint("TOPLEFT", chips, "TOPLEFT", 10, -5)
    local measure = T.Font(chips, "GameFontDisableSmall", "", T.colors.muted)
    measure:Hide()
    local opts
    if H.LayerChipButtonOpts then
        opts = H.LayerChipButtonOpts(Tr, T.colors, H.PreviewChromePalette(T), {
            IsOn = function(owner, key) return owner.layers[key] end,
        })
    end
    for i, spec in ipairs(SPECS) do
        local key, label, button = spec[1], spec[2]
        preview.layers[key] = true
        if H.CreateLayerButton and opts then
            button = H.CreateLayerButton(chips, preview, { key = key, label = label, color = { .30, .74, 1 } }, i, 95, opts)
        else
            P.SetTranslatedText(measure, Tr(label))
            button = T.Button(chips, label, math.max(64, measure:GetUnboundedStringWidth() + 30), 20)
            button.key = key
        end
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(_, mouse)
            if mouse == "RightButton" then
                for _, handle in ipairs(preview.handles) do
                    if handle._previewLayerKey == key then return P.MeterPreviewEditor.Open(preview, handle) end
                end
                return false
            end
            preview.layers[key] = not preview.layers[key]
            preview.ui.refreshPreview()
        end)
        P.HM.SkipHistoryCheckpoint(button)
        P.HM.SetCommandAction(button, { kind = "toggle", historyMode = "none",
            get = function() return preview.layers[key] end,
            set = function(value)
                preview.layers[key] = value == true
                preview.ui.refreshPreview()
                return true
            end })
        preview.layerButtons[i] = button
    end
    Layers.Layout(preview)
end

local function Show(region, visible)
    if region then region:SetShown(visible == true) end
end

local function Bars(row, enabled, c)
    Show(row.bar:GetStatusBarTexture(), enabled)
    Show(row.track, enabled)
    Show(row.fillBorder, enabled and c.rowBorderMode ~= 1)
    if row.bar.gradientOverlays then
        for key, texture in pairs(row.bar.gradientOverlays) do
            local direction = key:gsub("^gradient", "gradientDir")
            Show(texture, enabled and c.gradientEnabled and c.gradientStrength > 0 and c[direction])
        end
    end
end

function Layers.Paint(preview, win)
    local layers, targets, c = preview.layers, preview.targets, P.S.Config("damageMeter")
    Show(win.frame, layers.window)
    Show(win.header, layers.header)
    Show(win.title, layers.title)
    Show(targets.title, layers.title)
    local timer = layers.timer and c.combatTime and c.headerTimer and not win.overall
    Show(win.timer, timer)
    Show(targets.timer, timer)
    for key, button in pairs(win.buttons) do
        Show(button, layers.buttons)
        Show(targets.buttons[key], layers.buttons)
    end
    for i, row in ipairs(win.rows) do
        Show(row, not win.capacity or i <= win.capacity)
        Bars(row, layers.bars, c)
        Show(targets.rows[i].barHit, layers.bars)
        Show(row.iconBorder, layers.icon and c.iconStyle ~= 1 and c.iconBorder)
        Show(row.nameText, layers.name)
        Show(row.rankText, layers.name and c.rank)
        Show(row.valueText, layers.value)
        Show(row.icon, layers.icon and c.iconStyle ~= 1)
        Show(targets.rows[i].name, layers.name)
        Show(targets.rows[i].rank, layers.name and c.rank)
        Show(targets.rows[i].value, layers.value)
        Show(targets.rows[i].icon, layers.icon and c.iconStyle ~= 1)
    end
    for _, button in ipairs(preview.layerButtons) do
        if button.Refresh then button:Refresh() else button:SetAlpha(layers[button.key] and 1 or .42) end
    end
end
