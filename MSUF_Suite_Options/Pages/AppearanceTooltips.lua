local _, P = ...

local Kit, M, Tr = P.SkinPageKit, P.M, P.Tr
local styleKey, styleSection = "theme.itemTooltipStyle", "tooltips"
local presetKeys = { "compact", "detailed", "minimal", "dense", "custom" }
local presetValues = { compact = "Default", detailed = "Detailed", minimal = "Minimal", dense = "Dense", custom = "Custom" }
local typeChoices = {
    { id = "item", label = "Item tooltip style" },
    { id = "spell", label = "Spell tooltip style" },
    { id = "unit", label = "Unit tooltip style" },
    { id = "loot", label = "Loot" },
}
local typeValues = { suite = "Suite style", custom = "Custom" }

function P.UsesSharedTooltipAnchor()
    local mode = P.Get("tooltipDetails", "anchor")
    return P.Get("tooltipDetails", "enabled") and (mode == 2 or mode == 3)
end

function P.BuildSkinTooltipSection(ctx, builder, skin)
    local card = skin and skin.ItemTooltipCard
    if skin and not card then return end
    local row = Kit.Row("dropdown", "Tooltip layout preset", styleKey, styleSection, card and card.Preset,
        function(value)
            Kit.Change(skin, "Tooltip layout preset", styleKey, function()
                return card.SetPreset(value)
            end)
        end, Kit.Values(presetKeys, presetValues))
    local rows = { row }
    for _, spec in ipairs(typeChoices) do
        local field = "theme.tooltipLayout." .. spec.id .. "Style"
        rows[#rows + 1] = Kit.Row("dropdown", spec.label, field, styleSection,
            function() return card.TypeStyle(spec.id) end, function(value)
                Kit.Change(skin, spec.label, field, function() return card.SetTypeStyle(spec.id, value) end)
            end, Kit.Values({ "suite", "custom" }, typeValues))
    end
    return Kit.Section(ctx, builder, styleSection, "Tooltips", nil, rows, true, function(body, y, width)
        if not body then return y end
        local host = P.Suite.HostBridge
        local details = P.QoLView and P.QoLView.FindFeature("tooltipDetails")
        if details and P.Available("tooltipDetails") then
            P.Button(ctx, body, "General tooltip anchor", 16, y, math.min(280, width), function()
                host.OpenExactMenuSetting(M, "suite_skin", P.QoLView.FeatureSectionId(details), "msufsuite.tooltipDetails.anchor")
            end)
            y = y - 34
        end
        if host.UnitFrameTooltipAPI() then return y end
        P.Button(ctx, body, "Unitframe tooltips", 16, y, math.min(280, width), function()
            host.OpenExactMenuSetting(M, "opt_misc", "misc_tooltips", "general.unitTooltipMode")
        end)
        return y - 34
    end, nil, nil, function() return card.SetPreset("compact") end)
end

local unitRows = {
    { "unitTooltipProvider", "Tooltip source", {
        { value = "GAME", text = "GameTooltip (addon-compatible)" }, { value = "MSUF", text = "MSUF custom panel" },
    } },
    { "unitTooltipAnchor", "Tooltip anchor", {
        { value = "EXTERNAL", text = "Addon / Blizzard controlled" }, { value = "FIXED", text = "MSUF fixed position" },
        { value = "CURSOR", text = "MSUF cursor" },
    } },
    { "unitTooltipMode", "Show unitframe tooltips", {
        { value = "ALWAYS", text = "Always" }, { value = "OOC", text = "Out of Combat" },
        { value = "MODIFIER", text = "Modifier Key" }, { value = "NEVER", text = "Never" },
    } },
    { "unitTooltipModifier", "Modifier key", {
        { value = "ALT", text = "Alt" }, { value = "CTRL", text = "Ctrl" }, { value = "SHIFT", text = "Shift" },
    } },
}

function P.BuildSkinUnitTooltipSection(ctx, builder)
    local host = P.Suite.HostBridge.UnitFrameTooltipAPI()
    if not host then return end
    local id, title, rows = "unit_tooltips", "Unitframe tooltips", {}
    local shared = P.UsesSharedTooltipAnchor()
    for _, spec in ipairs(unitRows) do
        local field, label = spec[1], spec[2]
        if not shared or field ~= "unitTooltipAnchor" then
            local function Get() return host.GetUnitFrameTooltipSetting(field) or spec[3][1].value end
            local function Set(value)
                if P.Combat() then return end
                local result = P.WithHistory(label, "suite:" .. field, function()
                    return host.SetUnitFrameTooltipSetting(field, value)
                end)
                P.Refresh()
                return result
            end
            local values = {}
            for _, choice in ipairs(spec[3]) do
                values[#values + 1] = { value = choice.value, text = Tr(choice.text) }
            end
            rows[#rows + 1] = Kit.Row("dropdown", label, field, id, Get, Set, values)
        end
    end
    local function Reset()
        if P.Combat() then return false end
        for _, spec in ipairs(unitRows) do
            if (not shared or spec[1] ~= "unitTooltipAnchor") and not host.SetUnitFrameTooltipSetting(spec[1], spec[3][1].value) then return false end
        end
        return true
    end
    return Kit.Section(ctx, builder, id, title, nil, rows, false, nil, nil, nil, Reset)
end

local builderSection = "tooltip_builder"
local fields = { { "icon", "Icon" }, { "level", "Item level" }, { "kind", "Type" },
    { "tint", "Tooltip title color" }, { "rule", "Accent line" } }
local positions = { { "iconSize", "Icon size", 16, 38 }, { "x", "Horizontal offset", 4, 22 },
    { "y", "Vertical offset", -5, 5 }, { "borderWidth", "Tooltip frame thickness", 1, 4 } }
local function EditLayout(skin, label, field, value)
    Kit.Change(skin, label, "theme.tooltipLayout." .. field, function()
        return skin.ItemTooltipCard.Set(field, value)
    end)
end

function P.BuildSkinTooltipBuilder(ctx, builder, skin)
    local card = skin and skin.ItemTooltipCard
    if skin and not card then return end
    local rows = {
        Kit.Row("dropdown", "Tooltip frame", "theme.tooltipLayout.borderMode", builderSection,
            function() return card.Setting("borderMode") end,
            function(value) return EditLayout(skin, "Tooltip frame", "borderMode", value) end,
            Kit.Values({ "suite", "title", "custom", "native" },
                { suite = "Suite style", title = "Match tooltip title", custom = "Custom", native = "Keep" })),
    }
    local function Add(spec, slider)
        local field, label = spec[1], spec[2]
        rows[#rows + 1] = Kit.Row(slider and "slider" or "toggle", label, "theme.tooltipLayout." .. field, builderSection,
            function() return card.Setting(field) end,
            function(value) return EditLayout(skin, label, field, value) end, nil, spec[3], spec[4], 1)
    end
    for _, spec in ipairs(fields) do Add(spec) end
    for _, spec in ipairs(positions) do Add(spec, true) end
    local color = Kit.Row("color", "Tooltip header tint", "theme.tooltipLayout.headerColor", builderSection,
        card and card.HeaderColor, function(r, g, b, a)
            Kit.Change(skin, "Tooltip header tint", "theme.tooltipLayout.headerColor",
                function() return card.SetHeaderColor(r, g, b, a) end)
        end)
    rows[#rows + 1] = color
    rows[#rows + 1] = Kit.Row("color", "Tooltip frame color", "theme.tooltipLayout.borderColor", builderSection,
        card and card.BorderColor, function(r, g, b, a)
            Kit.Change(skin, "Tooltip frame color", "theme.tooltipLayout.borderColor",
                function() return card.SetBorderColor(r, g, b, a) end)
        end)
    return Kit.Section(ctx, builder, builderSection, "Tooltip builder", nil, rows, false,
        nil, nil, nil, function() return card.SetPreset("compact") end)
end
