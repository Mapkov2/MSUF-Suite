local _, P = ...
local Layers = {}
P.MeterPreviewLayers = Layers
local SPECS = {
    { "window", "Window" }, { "header", "Header" }, { "bars", "Bars" },
    { "icon", "Bar icons" }, { "name", "Name" }, { "value", "Value" },
    { "details", "Details" }, { "floatingTimer", "Floating timer" }, { "title", "Title" }, { "timer", "Combat timer" }, { "buttons", "Buttons" },
}

function Layers.Layout(preview)
    P.PreviewInteraction.LayoutLayerRail(preview, preview.availableWidth)
end

function Layers.Build(preview)
    preview.layers = {}
    for _, spec in ipairs(SPECS) do preview.layers[spec[1]] = spec[1] ~= "details" end
    P.PreviewInteraction.BuildLayerRail(preview, preview.ui.header, SPECS, function(key, enabled)
        preview.layers[key] = enabled
        preview.ui.refreshPreview()
        return true
    end, function(spec)
        for _, handle in ipairs(preview.handles) do
            if handle._previewLayerKey == spec[1] then return P.MeterPreviewEditor.Open(preview, handle) end
        end
        return false
    end)
    Layers.Layout(preview)
end

local function Show(region, visible)
    if region then region:SetShown(visible == true) end
end

local function Bars(row, enabled, c)
    Show(row.bar:GetStatusBarTexture(), enabled)
    Show(row.track, enabled)
    Show(row.rowSeparator, enabled and c.rowSeparators)
    Show(row.iconSeparator, enabled and c.iconSeparator and c.iconStyle ~= 1)
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
    Show(win.panel, layers.details and win.detailsSample)
    Show(targets.details, layers.details and win.detailsSample)
    Show(targets.body, not win.detailsSample)
    local header = layers.header and c.headerVisible ~= false
    Show(win.header, header)
    Show(targets.header, header)
    Show(win.title, header and layers.title)
    Show(targets.title, header and layers.title)
    Show(win.sampleTimer, layers.floatingTimer and win.previewTimerShown)
    Show(targets.floatingTimer, layers.floatingTimer and win.previewTimerShown)
    local timer = header and layers.timer and c.combatTime and c.headerTimer and not win.overall
    Show(win.timer, timer)
    Show(targets.timer, timer)
    for key, button in pairs(win.buttons) do
        local visible = header and layers.buttons and button.configuredShown ~= false
        Show(button, visible)
        Show(targets.buttons[key], visible)
    end
    for i, row in ipairs(win.rows) do
        Show(row, (not win.capacity or i <= win.capacity) and not win.detailsSample)
        Bars(row, layers.bars, c)
        Show(targets.rows[i].barHit, layers.bars)
        Show(row.iconBorder, layers.icon and c.iconStyle ~= 1 and c.iconBorder and not row.iconSkinApplied)
        Show(row.nameText, layers.name)
        Show(row.rankText, layers.name and c.rank)
        Show(row.valueText, layers.value)
        Show(row.icon, layers.icon and c.iconStyle ~= 1)
        Show(targets.rows[i].name, layers.name)
        Show(targets.rows[i].rank, layers.name and c.rank)
        Show(targets.rows[i].value, layers.value)
        Show(targets.rows[i].icon, layers.icon and c.iconStyle ~= 1)
    end
    P.PreviewInteraction.RefreshLayerRail(preview)
end
