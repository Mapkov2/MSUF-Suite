local _, P = ...

local Kit, M, Tr = P.SkinPageKit, P.M, P.Tr
local PAGE = "suite_tooltips"
local styleKey, styleSection = "theme.itemTooltipStyle", "tooltips"
local presetKeys = { "compact", "detailed", "minimal", "dense", "custom" }
local presetValues = { compact = "Default", detailed = "Detailed", minimal = "Minimal", dense = "Dense", custom = "Custom" }
local typeChoices = {
    { id = "item", label = "Item tooltip style" },
    { id = "spell", label = "Spell tooltip style" },
    { id = "unit", label = "Unit tooltip style" },
    { id = "quest", label = "Quest and object tooltips" },
    { id = "loot", label = "Loot" },
}
local typeValues = { suite = "Suite style", custom = "Custom" }

function P.TooltipAnchorMode()
    if not P.Available("tooltipDetails") or not P.Get("tooltipDetails", "enabled") then return end
    local mode = P.Get("tooltipDetails", "anchor")
    if mode == 2 or mode == 3 then return mode end
end

function P.UsesSharedTooltipAnchor()
    return P.TooltipDetailsEnabled()
end

local previewSection = PAGE .. "_preview"
local titlePositions = { x = "Horizontal offset", y = "Vertical offset" }
local anchorModes = { cursorX = 2, cursorY = 2, fixedX = 3, fixedY = 3 }

function P.TooltipPositionTarget(module, key)
    if module == "skin" then
        local axis = key:match("^theme%.tooltipLayout%.([xy])$")
        if axis then
            local meta = Kit.Meta(key, "tooltip_builder")
            meta.sectionId = previewSection
            return meta, titlePositions[axis]
        end
    elseif module == "tooltipDetails" and anchorModes[key] then
        return P.Meta(PAGE, module, key, "setting", previewSection),
            P.catalog[module].rules[key].label, anchorModes[key]
    end
end

function P.BuildSkinTooltipSection(ctx, builder, skin)
    local card = skin and skin.ItemTooltipCard
    if skin and not card then return end
    local choices = Kit.Values(presetKeys, presetValues)
    for _, entry in ipairs(skin and skin.TooltipPalette and skin.TooltipPalette.choices or {}) do
        choices[#choices + 1] = { value = entry.key, text = Tr(entry.label) }
    end
    local row = Kit.Row("dropdown", "Tooltip layout preset", styleKey, styleSection, card and card.Preset,
        function(value)
            Kit.Change(skin, "Tooltip layout preset", styleKey, function()
                return card.SetPreset(value)
            end)
        end, choices)
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
                host.OpenExactMenuSetting(M, PAGE, P.QoLView.FeatureSectionId(details), "msufsuite.tooltipDetails.anchor")
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

local EditLayout
local function HealthTextFormats()
    return Kit.Values({ "", "off", "percent", "value" },
        { [""] = "Default", off = "Disabled", percent = "Percentage", value = "Current / maximum" })
end

local function HealthTextSizes()
    local sizes = { { value = 0, text = Tr("Default") } }
    for n = 6, 32 do sizes[#sizes + 1] = { value = n, text = tostring(n) } end
    return sizes
end

local function HealthTextColor(skin, id)
    local field = "unitHealthTextColor"
    local key = "theme.tooltipLayout." .. field
    return Kit.Row("color", "Health text", key, id, function() return skin.ItemTooltipCard.UnitBarColor(field) end,
        function(r, g, b, a)
            return Kit.Change(skin, "Health text", key, function()
                return skin.ItemTooltipCard.SetUnitBarColor(field, r, g, b, a)
            end)
        end)
end

function P.OpenTooltipHealthTextMenu(preview)
    if P.Combat() then return false end
    local owner = preview.handles.healthText
    if not owner:IsShown() then
        owner = preview.tabs[3]
        for _, button in ipairs(preview.layerButtons or {}) do
            if button.key == "healthText" then owner = button break end
        end
    end
    local skin, card = preview.skin, preview.card
    P.AnchoredContextMenu(owner, function(_, menu)
        menu:CreateTitle(Tr("Health text"))
        local function Options(label, field, choices)
            local group = menu:CreateButton(Tr(label))
            if group.SetScrollMode then group:SetScrollMode(325) end
            for _, entry in ipairs(choices) do
                group:CreateRadio(entry.text, function(value) return card.Setting(field) == value end,
                    function(value) EditLayout(skin, label, field, value) end, entry.value)
            end
        end
        Options("Format", "unitHealthTextFormat", HealthTextFormats())
        Options("Font", "unitHealthTextFont", P.FontValues(card.Setting("unitHealthTextFont"), "Blizzard"))
        Options("Font size", "unitHealthTextSize", HealthTextSizes())
        if P.W.OpenContextColors then
            menu:CreateButton(Tr("Color picker"), function()
                P.W.OpenContextColors(owner, { title = Tr("Health text"), getTargets = function()
                    return { P.SkinColorTarget(skin, HealthTextColor(skin, "unit_tooltips")) }
                end })
            end)
        end
    end)
    return true
end

local function UnitVitalsRows(skin, id, rows)
    local card = skin and skin.ItemTooltipCard
    local function Add(kind, label, field, choices)
        local key = "theme.tooltipLayout." .. field
        local row = Kit.Row(kind, label, key, id, function() return card.Setting(field) end,
            function(value) return EditLayout(skin, label, field, value) end, choices,
            kind == "slider" and card and card.Range(field) or nil,
            kind == "slider" and card and select(2, card.Range(field)) or nil, 1)
        rows[#rows + 1] = row
        return row
    end
    local function BarAppearance(field, label)
        local name = Tr(label)
        local function Label(row, setting)
            row.label = Tr("%s - %s"):format(name, Tr(setting))
            row.searchLabel = row.label
        end
        local function Texture(suffix, caption)
            local key = field .. suffix
            local row = Add("dropdown", caption, key, P.TextureValues(card and card.Setting(key)))
            Label(row, caption)
        end
        local function Color(suffix, caption)
            local color = field .. suffix
            local key = "theme.tooltipLayout." .. color
            local row = Kit.Row("color", caption, key, id, function() return card.UnitBarColor(color) end,
                function(r, g, b, a)
                    return Kit.Change(skin, label, key, function() return card.SetUnitBarColor(color, r, g, b, a) end)
                end)
            Label(row, caption)
            rows[#rows + 1] = row
        end
        Texture("Texture", "Bar texture")
        Texture("Background", "Bar background")
        Label(Add("slider", "Bar width", field .. "Width"), "Bar width")
        Label(Add("slider", "Bar height", field .. "Height"), "Bar height")
        Color("Color", "Bar color")
        Color("BackgroundColor", "Bar background color")
    end
    Add("dropdown", "Health bar", "unitHealth",
        Kit.Values({ "native", "show", "hide" }, { native = "Blizzard", show = "Custom", hide = "Disabled" }))
    Add("toggle", "Resource Bar", "unitPower")
    Add("toggle", "Show bar values", "unitValueText")
    Add("dropdown", "Health text", "unitHealthTextFormat", HealthTextFormats())
    local font = Add("dropdown", "Font", "unitHealthTextFont",
        P.FontValues(card and card.Setting("unitHealthTextFont"), "Blizzard"))
    local size = Add("dropdown", "Font size", "unitHealthTextSize", HealthTextSizes())
    for _, row in ipairs({ font, size }) do row.label = Tr("%s - %s"):format(Tr("Health text"), row.label) end
    rows[#rows + 1] = HealthTextColor(skin, id)
    BarAppearance("unitHealth", "Health bar")
    BarAppearance("unitPower", "Resource Bar")
end

function P.BuildSkinUnitTooltipSection(ctx, builder, skin)
    local host = P.Suite.HostBridge.UnitFrameTooltipAPI()
    local vitals = skin and skin.TooltipVitals or ctx.searchRows and P.Suite.Client.AddOnEnabled("MSUF_Suite_Skin")
    if not host and not vitals then return end
    local id, title, rows = "unit_tooltips", "Unitframe tooltips", {}
    local shared = P.UsesSharedTooltipAnchor()
    for _, spec in ipairs(unitRows) do
        local field, label = spec[1], spec[2]
        if host and (not shared or field ~= "unitTooltipAnchor") then
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
    if vitals then UnitVitalsRows(skin, id, rows) end
    local function Reset()
        if P.Combat() then return false end
        if host then
            for _, spec in ipairs(unitRows) do
                if (not shared or spec[1] ~= "unitTooltipAnchor")
                    and not host.SetUnitFrameTooltipSetting(spec[1], spec[3][1].value) then return false end
            end
        end
        return not vitals or skin.ItemTooltipCard.ResetUnitVitals()
    end
    return Kit.Section(ctx, builder, id, title, nil, rows, false, nil, nil, nil, Reset)
end

local builderSection = "tooltip_builder"
local fields = { { "icon", "Icon" }, { "level", "Item level" }, { "kind", "Type" },
    { "tint", "Tooltip title color" }, { "rule", "Accent line" }, { "palette", "Custom colors" },
    { "paletteGradient", "Shaded surfaces" } }
local paletteColors = { { "fillColor", "Background" }, { "endColor", "Gradient color" },
    { "titleColor", "Title text" }, { "accentColor", "Accent color" } }
local sizes = { { "iconSize", "Icon size", 16, 38 }, { "borderWidth", "Tooltip frame thickness", 1, 4 },
    { "height", "Header height", 36, 48 } }
EditLayout = function(skin, label, field, value)
    return Kit.Change(skin, label, "theme.tooltipLayout." .. field, function()
        return skin.ItemTooltipCard.Set(field, value)
    end)
end

function P.TooltipPaletteRows(skin)
    local rows, card = {}, skin and skin.ItemTooltipCard
    for _, spec in ipairs(paletteColors) do
        local field, label = spec[1], spec[2]
        local key = "theme.tooltipLayout." .. field
        rows[#rows + 1] = Kit.Row("color", label, key, builderSection,
            function() return skin.TooltipPalette.Color(field) end,
            function(r, g, b, a)
                Kit.Change(skin, label, key, function() return card.SetPaletteColor(field, r, g, b, a) end)
            end)
    end
    return rows
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
    for _, spec in ipairs(sizes) do Add(spec, true) end
    rows[#rows + 1] = Kit.Row("dropdown", "Gradient direction", "theme.tooltipLayout.paletteDirection", builderSection,
        function() return card.Setting("paletteDirection"):lower() end,
        function(value) return EditLayout(skin, "Gradient direction", "paletteDirection", value:upper()) end,
        Kit.Values({ "vertical", "horizontal" }, { vertical = "Vertical", horizontal = "Horizontal" }))
    for _, row in ipairs(P.TooltipPaletteRows(skin)) do rows[#rows + 1] = row end
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
    rows[#rows + 1] = Kit.Row("dropdown", "Tooltip card background", "theme.tooltipLayout.cardSurface", builderSection,
        function() return card.Setting("cardSurface") end,
        function(value) return EditLayout(skin, "Tooltip card background", "cardSurface", value) end,
        Kit.Values({ "unified", "split" }, { unified = "Unified", split = "Separate header" }))
    rows[#rows + 1] = Kit.Row("dropdown", "Loot row background", "theme.tooltipLayout.lootSurface", builderSection,
        function() return card.Setting("lootSurface") end,
        function(value) return EditLayout(skin, "Loot row background", "lootSurface", value) end,
        Kit.Values({ "auto", "match", "native" }, { auto = "Default", match = "Match tooltip", native = "Blizzard" }))
    return Kit.Section(ctx, builder, builderSection, "Tooltip builder", nil, rows, false,
        nil, nil, nil, function() return card.SetPreset("compact", true) end)
end


function P.BuildTooltipSearchRows(ctx, builder, skin)
    if skin or P.Suite.Client.AddOnEnabled("MSUF_Suite_Skin") then
        P.BuildSkinTooltipSection(ctx, builder, skin)
        P.BuildSkinTooltipBuilder(ctx, builder, skin)
        for axis, label in pairs(titlePositions) do
            local meta = P.TooltipPositionTarget("skin", "theme.tooltipLayout." .. axis)
            meta.kind, meta.label, meta.searchLabel = "slider", Tr(label), label
            P.SkinSearchRow(ctx, meta, previewSection, Tr("Tooltips"))
        end
    end
    P.BuildSkinUnitTooltipSection(ctx, builder, skin)
end

function P.BindTooltipPositionSearch(preview, selectTitle, paint)
    if not M.RegisterControlMetadata then return end
    local HM = P.HM
    local function Bind(module, key)
        local meta, label, mode = P.TooltipPositionTarget(module, key)
        local region = CreateFrame("Frame", nil, preview.root)
        local axis = key:lower():sub(-1) == "x" and "axisX" or "axisY"
        local selection = preview.selection
        region:SetAllPoints(selection and selection[axis] or preview.titleButton)
        local function Prepare()
            if not mode then return selectTitle(preview) end
            if P.Combat() or not preview.root:IsVisible() or mode ~= P.TooltipAnchorMode() then return false end
            paint(preview)
            preview.kit:Select(preview.anchorButton)
            return true
        end
        HM.SetSearchTargetPrepare(region, Prepare)
        P.RegisterWorkspaceSearch(region, meta, { key = key, label = label }, "suiteWorkspace", Prepare, Tr(label))
    end
    Bind("skin", "theme.tooltipLayout.x")
    Bind("skin", "theme.tooltipLayout.y")
    if P.Available("tooltipDetails") then
        for _, key in ipairs({ "cursorX", "cursorY", "fixedX", "fixedY" }) do Bind("tooltipDetails", key) end
    end
end

function P.TooltipPreviewUsesPanel()
    local host = P.Suite.HostBridge.UnitFrameTooltipAPI()
    return host and host.GetUnitFrameTooltipSetting("unitTooltipProvider") == "MSUF"
end

function P.TooltipDetailsEnabled()
    return P.Available("tooltipDetails") and P.Get("tooltipDetails", "enabled")
end

function P.PaintTooltipPreviewBody(preview, sample)
    local rows = sample.rows
    local extra = 0
    local details = rows and P.Suite.Client.modernEquipment and P.TooltipDetailsEnabled()
        and not (sample.id == "unit" and P.TooltipPreviewUsesPanel())
    local function Row(index, label, value, detail)
        local row = preview.rows[index]
        row[1]:SetText(label)
        row[1]:SetTextColor(detail and .65 or 1, detail and .81 or 1, detail and .87 or 1)
        row[2]:SetText(value)
        row[2]:SetTextColor(detail and .9 or .62, detail and .9 or .83, detail and .9 or 1)
    end
    local function Add(key, label, value)
        if not P.Get("tooltipDetails", key) then return end
        extra = extra + 1
        Row(3 + extra, Tr(label), value, true)
    end
    if not rows then return 0 end
    for i, data in ipairs(rows) do
        local value = data[2]
        Row(i, Tr(data[1]), type(value) == "function" and value() or value, false)
    end
    if details then
        if sample.id == "unit" and not preview.restricted then
            Add("guildRank", "Guild rank", Tr("Officer"))
            Add("target", "Target", Tr("Player Name"))
            Add("itemLevel", "Item level", "160")
            if P.Get("tooltipDetails", "itemLevel") then Add("spec", "Specialization", Tr("Paladin")) end
        elseif sample.id == "item" then
            Add("iconID", "Item icon ID", tostring(sample.icon))
        elseif sample.id == "spell" then
            Add("iconID", "Spell icon ID", tostring(sample.icon))
        end
    end
    for i = 4 + extra, #preview.rows do Row(i, "", "", false) end
    return extra * 19
end

local function BuildPage(ctx)
    local builder = P.W.PageBuilder(ctx)
    local skin = Kit.Engine()
    if not skin or not skin.ItemTooltipCard then
        P.BuildSkinUnitTooltipSection(ctx, builder)
        P.QoLOwners.Build(ctx, builder, PAGE, nil, "tooltips")
        return
    end
    local workspace, ui = P.MenuWorkspace.Builder(ctx, { page = PAGE, module = "skin", title = "Tooltips",
        builder = builder, tabs = { { id = "tooltips", label = "Settings", sections = "" } },
        buildSelector = function() end,
    })
    if ui then ui.refreshPreview = function() P.ShowSkinTooltipPreview(ui, skin, true) end end
    P.BuildSkinTooltipSection(ctx, workspace, skin)
    P.BuildSkinTooltipBuilder(ctx, workspace, skin)
    P.BuildSkinUnitTooltipSection(ctx, workspace, skin)
    P.QoLOwners.Build(ctx, ui and ui.groups.tooltips.builder or workspace, PAGE, nil, "tooltips")
    P.MenuWorkspace.Finish(ui)
end

local function ResetPage()
    local skin = Kit.Engine()
    if skin and skin.ItemTooltipCard and not skin.ItemTooltipCard.Reset() then return false end
    return P.QoLOwners.Reset(PAGE, true)
end

P.RegisterPage({ key = PAGE, label = "Tooltips", title = "Tooltips", build = BuildPage,
    resetPage = ResetPage, icon = { 4, 0 }, nav = "style", navOrder = 2, aliases = { "suite_tooltips" } })
