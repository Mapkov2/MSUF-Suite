local _, P = ...
local Suite, M, W, T, Tr = P.Suite, P.M, P.W, P.T, P.Tr
local PAGE = "suite_skin"
local format = string.format
local SearchRow, Button = P.SkinSearchRow, P.SkinSearchButton
local Kit = P.SkinPageKit
local Engine, Change, Meta, Values = Kit.Engine, Kit.Change, Kit.Meta, Kit.Values
local Row, Section, ResetSkinSection = Kit.Row, Kit.Section, Kit.ResetSkinSection
local SkinColorRow, ConfigRow = Kit.SkinColorRow, Kit.ConfigRow

local CATEGORY_LABELS = {
    character = "Character and equipment", inventory = "Bags and bank",
    npc = "Merchants and NPCs", quest = "Quests and gossip",
    social = "Social, mail and guild", group = "Group Finder and PvE",
    profession = "Professions and crafting", economy = "Auction and economy",
    journal = "Collections and journals", map = "Map interfaces",
    calendar = "Calendar", utility = "Utility windows and dialogs",
    ["item-service"] = "Item services and upgrades", expansion = "Expansion interfaces",
    housing = "Housing interfaces", hud = "Blizzard HUD and alerts",
    tutorial = "Tutorials and help overlays",
}
local MICRO_PRESET_LABELS = {
    forever = "MSUF Forever", modern = "Midnight Blue", midnightDark = "Midnight Dark",
    blizzard = "Blizzard original",
}
local BAR_MATERIAL_LABELS = {
    modern = "Midnight Blue", midnightDark = "Midnight Dark",
    forever = "MSUF Forever", theme = "Follow skin look",
}

local function SkinBox(skin, parent, x, y, width, height, role)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, height)
    if skin.Surface and skin.Surface.Attach then skin.Surface.Attach(frame, { role = role }) end
    return frame
end

-- The docked sample renders with the skin engine's own surfaces.
local function Preview(ctx, b, skin)
    local section, toolbar = W.FixedPreviewSection(ctx, b, { title = Tr("Skin preview"), height = 176 })
    if not section then return end
    local hint = T.Font(toolbar, "GameFontDisableSmall", Tr("Choose a look below; this sample follows your changes."),
        T.colors.muted)
    hint:SetPoint("LEFT", toolbar, "LEFT", 125, 0)
    hint:SetPoint("RIGHT", toolbar, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    local canvas = CreateFrame("Frame", nil, section)
    canvas:SetPoint("TOPLEFT", 14, -42)
    canvas:SetPoint("BOTTOMRIGHT", -14, 9)
    local shell = SkinBox(skin, canvas, 10, -7, 292, 116, "shell")
    local title = T.Font(shell, "GameFontNormal", Tr("Window shell"), T.colors.text)
    title:SetPoint("TOPLEFT", 14, -12)
    local panel = SkinBox(skin, shell, 13, -37, 266, 66, "panel")
    local card = SkinBox(skin, panel, 10, -10, 246, 22, "card")
    local cardLabel = T.Font(card, "GameFontHighlightSmall", Tr("Panel and card layer"), T.colors.text)
    cardLabel:SetPoint("LEFT", 8, 0)
    local button = SkinBox(skin, panel, 10, -40, 76, 19, "buttonPrimary")
    local buttonLabel = T.Font(button, "GameFontHighlightSmall", Tr("Primary"), T.colors.text)
    buttonLabel:SetPoint("CENTER")
    local note = P.Text(canvas, "", 326, -18, 300)
    -- Labels take the token's RGB only; the preview keeps them opaque.
    local function PaintLabel(label, token)
        local r, g, blue = skin.Theme.GetColor(token)
        label:SetTextColor(r, g, blue)
    end
    M.TrackRefresh(ctx, function()
        PaintLabel(title, "title")
        PaintLabel(cardLabel, "text")
        PaintLabel(buttonLabel, "accent")
        local look = skin.LookPresets[skin.DB.theme.look]
        local description = look and look.description or "Your own colors, materials and shape."
        note:SetText(Tr(look and look.label or "Custom") .. "\n"
            .. Tr((skin.L and skin.L[description]) or description))
    end)
end

------------------------------------------------------------------ Micro Bar
local MICRO_PRESETS = { "modern", "midnightDark", "forever", "blizzard" }
local microTabs = { tab = "general" }

local function MicroOption(skin, label, key)
    return function(value)
        Change(skin, label, "micro." .. key, function() return skin.MicroMenuSkin.SetOption(key, value) end)
    end
end

local function MicroRows(skin)
    local settings = function() return skin.DB.icons.microMenu end
    return {
        Row("toggle", "Style the Micro Bar", "skins.microMenu", "micro",
            function() return skin.DB.skins.microMenu end,
            function(value)
                Change(skin, "Micro Bar", "skins.microMenu",
                    function() return skin.Adapters.SetEnabled("microMenu", value) end)
            end),
        Row("dropdown", "Bar direction", "icons.microMenu.orientation", "micro",
            function() return settings().orientation end,
            MicroOption(skin, "Micro Bar direction", "orientation"), Values(skin.MicroMenuOrientations)),
        Row("slider", "Buttons per line", "icons.microMenu.buttonsPerLine", "micro",
            function() return settings().buttonsPerLine end,
            MicroOption(skin, "Micro Bar buttons", "buttonsPerLine"),
            nil, 1, skin.Client and skin.Client.isForever and 14 or 13, 1),
        Row("slider", "Scale", "icons.microMenu.scale", "micro",
            function() return settings().scale end,
            MicroOption(skin, "Micro Bar scale", "scale"), nil, 0.5, 1.5, 0.05),
    }
end

local function MicroLoadRows(skin)
    local rows = {
        Row("dropdown", "Show Micro Bar", "icons.microMenu.visibility", "micro",
            function() return skin.DB.icons.microMenu.visibility end,
            MicroOption(skin, "Micro Bar visibility", "visibility"), Values(skin.MicroMenuVisibilityModes)),
    }
    for _, condition in ipairs(skin.MicroMenuLoadConditions) do
        local key, label = condition[1], condition[2]
        rows[#rows + 1] = Row("toggle", label, "icons.microMenu." .. key, "micro",
            function() return skin.DB.icons.microMenu[key] end,
            MicroOption(skin, "Micro Bar " .. label, key))
    end
    return rows
end

local function MicroHint(preset)
    local label = MICRO_PRESET_LABELS[preset] or preset == "custom" and "Custom" or "Other style"
    local detail = preset == "blizzard"
        and "Blizzard's original Micro Bar and buttons. Use Blizzard Edit Mode to move it."
        or "MSUF looks use Suite glyphs and a player portrait. Blizzard keeps every button action and tooltip."
    return format(Tr("Selected: %s. %s"), Tr(label), Tr(detail))
end

-- Makes sure the Suite owns a styled bar before MSUF Edit Mode opens it.
local function MoveMicroBar(skin)
    if not skin.DB.skins.microMenu then
        Change(skin, "Style Micro Bar", "skins.microMenu",
            function() return skin.Adapters.SetEnabled("microMenu", true) end)
    end
    if skin.DB.icons.microMenu.layoutMode ~= "owned" then
        Change(skin, "Move Micro Bar", "micro.layoutMode",
            function() return skin.MicroMenuSkin.SetOption("layoutMode", "owned") end)
    end
    if skin.OwnedMicroBar then skin.OwnedMicroBar.OpenEditMode() end
end

-- Preset buttons, the selected preset's note and the Edit Mode shortcut.
local function MicroPresetExtra(ctx, skin)
    return function(body, y, width, prepare)
        local half = math.floor((width - 12) / 2)
        for index, style in ipairs(MICRO_PRESETS) do
            local button = Button(ctx, body, MICRO_PRESET_LABELS[style],
                16 + ((index - 1) % 2) * (half + 12), y - math.floor((index - 1) / 2) * 38, half, function()
                    Change(skin, "Micro Bar " .. style, "micro.preset",
                        function() return skin.MicroMenuSkin.ApplyPreset(style) end)
                end, nil, P.Meta(PAGE, "skin", "micro.preset." .. style, "action", "suite_skin_micro"))
            if button then button._msuf2PrepareExactSearchTarget = prepare end
        end
        if ctx.searchRows then
            Button(ctx, body, "Move in MSUF Edit Mode", 0, 0, width, nil, nil,
                P.Meta(PAGE, "skin", "micro.move", "action", "suite_skin_micro"))
            return y
        end
        local description = P.Text(body, "", 16, y - 72, width)
        local function RefreshMicroHint()
            description:SetText(MicroHint(skin.DB.icons.microMenu.preset))
        end
        RefreshMicroHint()
        M.TrackRefresh(ctx, RefreshMicroHint)
        local descHeight = math.max(22, math.ceil(description:GetStringHeight() or 22))
        local move = Button(ctx, body, "Move in MSUF Edit Mode", 16, y - 82 - descHeight, width,
            function() MoveMicroBar(skin) end, nil, P.Meta(PAGE, "skin", "micro.move", "action", "suite_skin_micro"))
        if move then move._msuf2PrepareExactSearchTarget = prepare end
        return y - 120 - descHeight
    end
end

-- { label, key, kind, values, min, max, step } of the detail rows.
local function MicroDetailSpecs(skin)
    return {
        { "Layout engine", "layoutMode", "dropdown", skin.MicroMenuLayoutModes },
        { "Growth direction", "growth", "dropdown", skin.MicroMenuGrowthModes },
        { "Button spacing", "spacing", "slider", nil, -8, 16, 1 },
        { "Bar padding", "padding", "slider", nil, 0, 16, 1 },
        { "Bar material", "barMaterial", "dropdown", skin.MicroMenuBarMaterials },
        { "Icon artwork", "iconStyle", "dropdown", skin.MicroMenuIconStyles },
        { "Icon colors", "tint", "dropdown", skin.MicroMenuTintModes },
        { "Button size", "buttonSize", "slider", nil, 20, 32, 1 },
        { "Glyph size", "iconSize", "slider", nil, 10, 28, 1 },
        { "Mouseover effect", "hoverStyle", "dropdown", skin.MicroMenuHoverStyles },
        { "Bar background", "barBackground", "toggle" },
        { "Bar border", "barBorder", "dropdown", { 0, 1, 2 } },
        { "Button backgrounds", "buttonBackground", "toggle" },
        { "Button borders", "buttonBorder", "dropdown", { 0, 1, 2 } },
        { "Bar and button shape", "shape", "dropdown", skin.MicroMenuShapes },
        { "Corner radius", "radius", "dropdown", skin.GeometryRadii },
        { "Normal icon opacity", "normalOpacity", "slider", nil, 0, 1, 0.05 },
        { "Mouseover icon opacity", "hoverOpacity", "slider", nil, 0, 1, 0.05 },
        { "Pressed icon opacity", "pressedOpacity", "slider", nil, 0, 1, 0.05 },
        { "Disabled icon opacity", "disabledOpacity", "slider", nil, 0, 1, 0.05 },
    }
end

-- A glyph needs 4 px of room inside its button; bigger glyphs grow the button.
local function SetMicroDetail(skin, key, value)
    if key == "iconSize" and value > (skin.DB.icons.microMenu.buttonSize or 28) - 4 then
        local required = math.min(32, math.floor(value + 4.5))
        if skin.MicroMenuSkin.SetOption("buttonSize", required) == false then return false end
    end
    return skin.MicroMenuSkin.SetOption(key, value)
end

-- The style itself is chosen with the preset buttons in the Micro Bar section.
local function MicroDetailRows(skin)
    local details = {}
    for _, spec in ipairs(MicroDetailSpecs(skin)) do
        local label, key, kind = spec[1], spec[2], spec[3]
        local values = kind == "dropdown"
            and Values(spec[4], key == "barMaterial" and BAR_MATERIAL_LABELS or nil) or nil
        details[#details + 1] = Row(kind, label, "icons.microMenu." .. key, "micro",
            function() return skin.DB.icons.microMenu[key] end,
            function(value)
                Change(skin, label, "micro." .. key, function() return SetMicroDetail(skin, key, value) end)
            end, values, spec[5], spec[6], spec[7])
    end
    return details
end

local function BuildMicroBar(ctx, b, skin)
    local sectionId, title = "suite_skin_micro", Tr("Micro Bar")
    local specs = {
        { id = "general", label = "General", title = "Micro Bar", rows = MicroRows(skin),
            help = "Choose a look and when the Suite bar appears. Visibility rules use the Suite layout; Blizzard layout keeps Blizzard's visibility. MSUF Edit Mode reveals the bar for moving.",
            extra = MicroPresetExtra(ctx, skin) },
        { id = "visibility", label = "Visibility", title = "Micro Bar Visibility", rows = MicroLoadRows(skin),
            help = "Hide the Suite Micro Bar when any selected condition is true. The health condition uses your character's health; at full health the transparent bar can still receive clicks. MSUF Edit Mode shows the bar for placement. Blizzard layout keeps Blizzard's visibility." },
        { id = "details", label = "Details", title = "Micro Bar details", rows = MicroDetailRows(skin),
            help = "Optional artwork and spacing controls. Use MSUF Edit Mode for position, nudging, reset, undo and redo.",
            extra = function(body, y, width, prepare)
                local reset = Button(ctx, body, "Reset Micro Bar to client default", 16, y, width, function()
                    Change(skin, "Reset Micro Bar", "micro.reset", skin.MicroMenuSkin.ResetRecommended)
                end, nil, P.Meta(PAGE, "skin", "micro.reset", "action", sectionId))
                if reset then reset._msuf2PrepareExactSearchTarget = prepare end
                return y - 40
            end },
    }
    local body, allRows = P.SkinTabbedSection(ctx, b, sectionId, title, specs, microTabs)
    if not body then return end
    P.AttachRowsSummary(ctx, body, allRows)
    P.AttachSectionReset(ctx, body, title, function() return ResetSkinSection(Engine(), "micro", allRows) end)
end

------------------------------------------------------------------ sections
-- The whole Skinning module: Blizzard windows and Suite windows together.
-- The Skinning page uses these functions for its switch.
function P.SkinningEnabled()
    local skin = _G.MapkoSkin
    if Suite.Skin.enabled == true then return true end
    return type(skin) == "table" and skin.addonName == "MSUF_Suite_Skin" and type(skin.DB) == "table"
        and skin.DB.enabled == true
end

function P.SetSkinningEnabled(value)
    local skin = Engine()
    return Change(skin, "Skinning", "enabled", function()
        local windows = skin.Adapters.SetMasterEnabled(value)
        if not windows then return false end
        return Suite.Skin.SetEnabled(value)
    end)
end

local function BuildFrameBasics(ctx, b, skin)
    local basics = Section(ctx, b, "frame_basic", "Basics",
        "Switch the whole Skinning module here, or adjust Blizzard and Suite windows separately below.", {
            Row("toggle", "Skin Blizzard windows", "enabled.windows", "frame_basic",
                function() return skin.DB.enabled end,
                function(value)
                    Change(skin, "Skin Blizzard windows", "enabled.windows",
                        function() return skin.Adapters.SetMasterEnabled(value) end)
                end),
            Row("toggle", "Skin Suite windows and buttons", "suiteEnabled", "frame_basic",
                function() return Suite.Skin.enabled end,
                function(value)
                    Change(skin, "Skin Suite windows", "suiteEnabled", function() return Suite.Skin.SetEnabled(value) end)
                end),
        }, true)
    if ctx.searchRows then
        SearchRow(ctx, Row("toggle", "Enable Skinning", "enabled", "frame_basic"),
            "suite_skin_frame_basic", Tr("Basics"))
        return
    end
    local enable = W.SectionSwitch(basics, Tr("Enable Skinning"), Tr("Enable"))
    M.BindBoolWidget(ctx, enable, P.SkinningEnabled, P.SetSkinningEnabled, Meta("enabled", "frame_basic"))
    M.TrackRefresh(ctx, function() W.SetControlEnabled(enable, not P.Combat()) end)
end

local function BuildLook(ctx, b, skin)
    local looks = {}
    for _, key in ipairs(skin.LookOrder) do
        looks[#looks + 1] = { value = key, text = Tr(skin.LookPresets[key].label) }
    end
    looks[#looks + 1] = { value = "custom", text = Tr("Custom"), disabled = true }
    local defaultLook = skin.Defaults.theme.look
    local defaultLabel = Tr(skin.LookPresets[defaultLook].label)
    local paletteValues = Values(skin.PaletteOrder, skin.PaletteLabels)
    paletteValues[#paletteValues + 1] = { value = "custom", text = Tr("Custom"), disabled = true }
    -- The section's three dots edit the whole skin palette; MSUF Colors lists
    -- the same colors under Suite skin.
    local paletteRows = {}
    for _, entry in ipairs(skin.ColorOrder or {}) do
        paletteRows[#paletteRows + 1] = SkinColorRow(skin, entry[1], (skin.L and skin.L[entry[2]]) or entry[1])
    end
    Section(ctx, b, "basic", "Choose a look",
        format(Tr("Choosing a look updates Skinning and every enabled Suite module. Modules enabled later inherit it. New skin profiles start with %s."), defaultLabel), {
            Row("dropdown", "Style preset", "theme.look", "basic",
                function() return skin.DB.theme.look end,
                function(value)
                    Change(skin, "Skin look", "look", function() return skin.Theme.ApplyLook(value) end)
                end, looks),
            Row("dropdown", "Color palette", "theme.preset", "basic",
                function() return skin.DB.theme.preset end,
                function(value)
                    Change(skin, "Skin color palette", "palette", function() return skin.Theme.ApplyPreset(value) end)
                end, paletteValues),
        }, true, function(body, y, width)
            local half = math.floor((width - 12) / 2)
            local restore = format(Tr("Restore %s"), defaultLabel)
            Button(ctx, body, restore, 16, y, half, function()
                Change(skin, restore, "look.default", function() return skin.Theme.ApplyLook(defaultLook) end)
            end, nil, P.Meta(PAGE, "skin", "look.default", "action", "suite_skin_basic"))
            Button(ctx, body, "All skin colors", 28 + half, y, half, function()
                if M.SelectPage then M.SelectPage("opt_colors") end
            end, nil, P.Meta(PAGE, "skin", "colors", "navigation", "suite_skin_basic"))
            return y - 40
        end, paletteRows)
end

local HUD_TOGGLES = {
    { "Damage meter windows", "damageMeterWindows" },
    { "Damage meter rows", "damageMeterRows" },
    { "Damage meter details", "damageMeterDetails" },
}

-- The Suite damage meter turns Blizzard's meter off, and the skin leaves it
-- alone then. Its section is built only while Blizzard's meter is in use.
local function BlizzardMeterInUse()
    return not P.S.OwnsBlizzardSurface("damageMeter")
end

-- Which meter the built page was made for; nil while no page is built.
local builtForBlizzardMeter

-- P.Refresh runs after every Suite change (module switch, profile, undo).
-- When the meter changes hands the page is rebuilt: at once while it is
-- shown, otherwise on its next visit.
function P.RefreshSkinPageShape()
    if builtForBlizzardMeter == nil or P.Combat() or BlizzardMeterInUse() == builtForBlizzardMeter then return end
    builtForBlizzardMeter = nil
    local rebuilt = M.activeKey == PAGE and M.RebuildPageKeepingScroll and M.RebuildPageKeepingScroll(PAGE)
    if not rebuilt and M.InvalidatePage then M.InvalidatePage(PAGE) end
end

local function BuildHUD(ctx, b, skin)
    local hud = {
        Row("toggle", "Style Blizzard damage meter", "skins.damageMeter", "hud",
            function() return skin.DB.skins.damageMeter end,
            function(value)
                Change(skin, "Blizzard damage meter", "skins.damageMeter",
                    function() return skin.Adapters.SetEnabled("damageMeter", value) end)
            end),
    }
    for _, spec in ipairs(HUD_TOGGLES) do
        local label, key = spec[1], spec[2]
        hud[#hud + 1] = Row("toggle", label, "hud." .. key, "hud",
            function() return skin.DB.hud[key] end,
            function(value)
                Change(skin, label, "hud." .. key, function()
                    skin.DB.hud[key] = value == true
                    skin.Adapters.Refresh("damageMeter")
                    skin.Registry.NotifyListeners("hud", key)
                    return true
                end)
            end)
    end
    Section(ctx, b, "hud", "Blizzard HUD",
        "Style the Blizzard damage meter. Configure the Suite Objective Tracker and announcements on the HUD page.",
        hud, false)
end

local MATERIAL_SPECS = {
    { "Shaded surfaces", "gradient", "toggle" },
    { "Light direction", "gradientDirection", "dropdown", { "VERTICAL", "HORIZONTAL" } },
    { "Shading strength", "gradientStrength", "slider", nil, 0, 1, 0.05 },
    { "Surface depth", "materialDepth", "slider", nil, 0, 1, 0.05 },
    { "Window opacity", "shellOpacity", "slider", nil, 0.35, 1, 0.05 },
    { "Content opacity", "panelOpacity", "slider", nil, 0.35, 1, 0.05 },
    { "Controls opacity", "controlOpacity", "slider", nil, 0.35, 1, 0.05 },
    { "Outline opacity", "borderOpacity", "slider", nil, 0, 1, 0.05 },
}

local function BuildMaterial(ctx, b, skin)
    local material = {}
    for _, spec in ipairs(MATERIAL_SPECS) do
        ConfigRow(skin, material, "material", spec[1], "theme", spec[2], spec[3], spec[4], spec[5], spec[6], spec[7],
            skin.Theme.SetAppearance)
    end
    Section(ctx, b, "material", "Glass and surfaces",
        "Adjust the glass effect while keeping your colors and window coverage.", material, true)
end

local function BuildShape(ctx, b, skin)
    local shape = {}
    for _, spec in ipairs({
        { "Window corners", "family", skin.GeometryFamilies },
        { "Button corners", "controlShape", skin.ControlShapes },
        { "Corner radius", "radius", skin.GeometryRadii },
        { "Outline thickness", "border", skin.GeometryBorders },
    }) do
        ConfigRow(skin, shape, "shape", spec[1], "geometry", spec[2], "dropdown", spec[3], nil, nil, nil,
            skin.Theme.SetGeometry)
    end
    ConfigRow(skin, shape, "shape", "Hover highlight", "theme", "hoverStyle", "dropdown", skin.HoverStyles,
        nil, nil, nil, skin.Theme.SetAppearance)
    ConfigRow(skin, shape, "shape", "Hover strength", "theme", "hoverIntensity", "slider", nil,
        0, 1, 0.05, skin.Theme.SetAppearance)
    Section(ctx, b, "shape", "Corners and hover", "Window shape, button shape, outlines and mouseover feedback.", shape, false)
end

local FONT_TOGGLES = {
    { "Chat and Communities", "applyChat", "SetApplyChat" },
    { "Quest, mail and combat text", "includeSpecial", "SetIncludeSpecial" },
}

local function BuildFonts(ctx, b, skin)
    local fonts = {
        Row("toggle", "Override Blizzard fonts", "font.enabled", "fonts",
            function() return skin.DB.typography.enabled end,
            function(value)
                Change(skin, "Blizzard fonts", "font.enabled", function() return skin.Typography.SetEnabled(value) end)
            end),
    }
    local function FontValues()
        local values = {}
        for _, key in ipairs(skin.Typography.GetSelectionValues()) do
            values[#values + 1] = { value = key, text = skin.Typography.GetSelectionLabel(key) }
        end
        return values
    end
    fonts[#fonts + 1] = Row("dropdown", "Font", "font.face", "fonts", skin.Typography.GetSelection,
        function(value)
            Change(skin, "Blizzard font", "font.face", function() return skin.Typography.SetSelection(value) end)
        end, FontValues)
    for _, spec in ipairs(FONT_TOGGLES) do
        local label, key, setter = spec[1], spec[2], spec[3]
        fonts[#fonts + 1] = Row("toggle", label, "font." .. key, "fonts",
            function() return skin.DB.typography[key] end,
            function(value)
                Change(skin, label, "font." .. key, function() return skin.Typography[setter](value) end)
            end)
    end
    Section(ctx, b, "fonts", "Fonts", "Blizzard keeps its text sizes and outlines.", fonts, false,
        function(body, y, width)
            if ctx.searchRows then
                SearchRow(ctx, Row("textinput", "Custom font path", "font.path", "fonts"),
                    "suite_skin_fonts", Tr("Fonts"))
                return y
            end
            M.BindTextInputAt(ctx, body, Tr("Custom font path"), 16, y, width,
                function() return skin.DB.typography.customPath or "" end,
                function(value)
                    Change(skin, "Custom font path", "font.path",
                        function() return skin.Typography.SetCustomPath(value or "") end)
                end,
                true, Meta("font.path", "fonts"))
            return y - 60
        end)
end

local function BuildIcons(ctx, b, skin)
    local icons = {}
    for _, spec in ipairs({
        { "Window action style", "style", "dropdown", skin.WindowActionStyles },
        { "Maximize/minimize symbols", "glyphMode", "dropdown", skin.WindowActionGlyphModes },
        { "Line weight", "weight", "dropdown", skin.WindowActionWeights },
        { "Maximize/minimize size", "glyphSize", "slider", nil, 8, 18, 1 },
        { "Close X size", "closeGlyphSize", "slider", nil, 6, 18, 1 },
        { "Action button shape", "surfaceShape", "dropdown", skin.WindowActionShapes },
        { "Action corner radius", "surfaceRadius", "dropdown", skin.GeometryRadii },
        { "Visual inset", "surfaceInset", "slider", nil, 0, 6, 1 },
        { "Glyph horizontal offset", "glyphOffsetX", "slider", nil, -4, 4, 1 },
        { "Glyph vertical offset", "glyphOffsetY", "slider", nil, -4, 4, 1 },
        { "Idle glyph opacity", "opacity", "slider", nil, 0.35, 1, 0.05 },
    }) do
        local label, key, kind = spec[1], spec[2], spec[3]
        icons[#icons + 1] = Row(kind, label, "icons.windowActions." .. key, "icons",
            function() return skin.DB.icons.windowActions[key] end,
            function(value)
                Change(skin, label, "icons.windowActions." .. key,
                    function() return skin.WindowActionSkin.SetOption(key, value) end)
            end,
            kind == "dropdown" and Values(spec[4]) or nil, spec[5], spec[6], spec[7])
    end
    for _, spec in ipairs({
        { "Item icon border", "iconBorderStyle", "dropdown", skin.IconBorderStyles },
        { "Item border thickness", "iconBorderThickness", "slider", nil, 1, 3, 1 },
        { "Item border padding", "iconBorderPadding", "slider", nil, 0, 3, 1 },
        { "Item border opacity", "iconBorderOpacity", "slider", nil, 0, 1, 0.05 },
    }) do
        ConfigRow(skin, icons, "icons", spec[1], "theme", spec[2], spec[3], spec[4], spec[5], spec[6], spec[7],
            skin.Theme.SetAppearance)
    end
    Section(ctx, b, "icons", "Window buttons and icon borders",
        "Close, expand and minimize symbols plus item borders.", icons, false,
        function(body, y, width)
            Button(ctx, body, "Reset window buttons", 16, y, width, function()
                Change(skin, "Reset window buttons", "icons.windowActions.reset",
                    skin.WindowActionSkin.ResetRecommended)
            end, nil, P.Meta(PAGE, "skin", "icons.windowActions.reset", "action", "suite_skin_icons"))
            return y - 40
        end)
end

local function BuildWindowControls(ctx, b, skin)
    Section(ctx, b, "window_controls", "Window position, size and minimize",
        "Drag a window by its top edge; drag the bottom-right corner to scale it. The top-right minus button collapses compatible windows to a restore tab. Bags and protected windows keep their native behavior.", {
            Row("toggle", "Move, resize and minimize Blizzard windows", "windowControls.enabled", "window_controls",
                function() return skin.DB.windowControls.enabled end,
                function(value)
                    Change(skin, "Blizzard window controls", "windowControls.enabled",
                        function() return skin.WindowControls.SetEnabled(value) end)
                end),
        }, false, function(body, y, width)
            Button(ctx, body, "Reset Blizzard window positions and sizes", 16, y, width, function()
                Change(skin, "Reset Blizzard window layout", "windowControls.layout", skin.WindowControls.ResetLayout)
            end, nil, P.Meta(PAGE, "skin", "windowControls.layout", "action", "suite_skin_window_controls"))
            return y - 40
        end)
end

-- Micro Bar and damage meter adapters have their own sections above.
local function BuildWindows(ctx, b, skin)
    local windows = {}
    local order, definitions = skin.Adapters.GetDefinitions()
    for _, id in ipairs(order) do
        if id ~= "microMenu" and id ~= "damageMeter" then
            local definition = definitions[id]
            local label = definition and definition.labelKey and skin.L[definition.labelKey] or id
            windows[#windows + 1] = Row("toggle", label, "skins." .. id, "windows",
                function() return skin.DB.skins[id] end,
                function(value)
                    Change(skin, label, "skins." .. id, function() return skin.Adapters.SetEnabled(id, value) end)
                end)
        end
    end
    Section(ctx, b, "windows", "Blizzard windows",
        "Choose which Blizzard interfaces receive the skin. Blizzard keeps their interactions.", windows, false)
end

local function BuildCoverage(ctx, b, skin)
    local categories = {}
    for _, item in ipairs(skin.GenericWindows.GetCategories()) do
        local id = item.id
        categories[#categories + 1] = Row("toggle", CATEGORY_LABELS[id] or id,
            "coverage." .. id, "coverage", function() return skin.DB.skinCategories[id] end,
            function(value)
                Change(skin, "Skin " .. id, "coverage." .. id,
                    function() return skin.GenericWindows.SetCategoryEnabled(id, value) end)
            end)
    end
    Section(ctx, b, "coverage", "Window categories",
        "Narrow general Blizzard window coverage by category.", categories, false)
end

local CHARACTER_TOGGLES = {
    { "Character details", "characterDetails", "enabled", "CharacterDetails" },
    { "Expanded details", "characterDetails", "expanded", "CharacterDetails" },
    { "Character quality of life style", "characterDetails", "styleEQoL", "CharacterDetails" },
    { "Inline gear", "characterDetails", "inlineGear", "CharacterDetails" },
    { "Wide layout", "characterDetails", "wideLayout", "CharacterDetails" },
    { "Character stats", "characterStats", "enabled", "CharacterStats" },
    { "Diminishing returns", "characterStats", "diminishingReturns", "CharacterStats" },
}

local function BuildCharacter(ctx, b, skin)
    local character = {
        Row("dropdown", "Character view", "character.view", "character",
            function() return skin.DB.characterDetails.view end,
            function(value)
                Change(skin, "Character view", "character.view", function() return skin.CharacterDetails.SetView(value) end)
            end,
            Values({ "modern", "list", "classic" })),
    }
    for _, spec in ipairs(CHARACTER_TOGGLES) do
        local label, group, key, api = spec[1], spec[2], spec[3], spec[4]
        character[#character + 1] = Row("toggle", label, group .. "." .. key, "character",
            function() return skin.DB[group][key] end,
            function(value)
                Change(skin, label, group .. "." .. key, function() return skin[api].SetOption(key, value) end)
            end)
    end
    Section(ctx, b, "character", "Character panel and stats",
        "Choose the detailed character view and its extra information. Changing the view reloads the UI.",
        character, false)
end

local function ResetSkinProfile(skin)
    skin.Database.ResetAll()
    skin.Typography.ApplyConfigured()
    skin.Adapters.ApplyAll()
    skin.Registry.RefreshAll()
    skin.Registry.NotifyListeners("theme", "reset")
    return true
end
P.ResetSkinPage = function()
    local skin = Engine()
    if not skin or P.Combat() then return false end
    if not ResetSkinProfile(skin) then return false end
    return Suite.Skin.SetEnabled(true)
end

local function BuildMaintenance(ctx, b, skin)
    Section(ctx, b, "advanced", "Maintenance",
        "Refresh newly opened Blizzard windows. Use Reset page in the menu toolbar to restore this skin profile.",
        {}, false, function(body, y, width)
            Button(ctx, body, "Refresh Blizzard skins", 16, y, width, function()
                if skin.Adapters.ApplyAll then skin.Adapters.ApplyAll() end
            end, nil, P.Meta(PAGE, "skin", "maintenance.refresh", "action", "suite_skin_advanced"))
            return y - 40
        end)
end

-- Keep visible controls and indexed metadata in the same section order.
local function BuildSections(ctx, b, skin)
    BuildFrameBasics(ctx, b, skin)
    BuildLook(ctx, b, skin)
    BuildMicroBar(ctx, b, skin)
    local blizzardMeter = BlizzardMeterInUse()
    if not ctx.searchRows then builtForBlizzardMeter = blizzardMeter end
    if blizzardMeter then BuildHUD(ctx, b, skin) end
    BuildMaterial(ctx, b, skin)
    BuildShape(ctx, b, skin)
    BuildFonts(ctx, b, skin)
    BuildIcons(ctx, b, skin)
    BuildWindowControls(ctx, b, skin)
    BuildWindows(ctx, b, skin)
    BuildCoverage(ctx, b, skin)
    BuildCharacter(ctx, b, skin)
    BuildMaintenance(ctx, b, skin)
end

function P.SkinSearchRows()
    local ctx, b = { searchRows = {} }, {}
    local skin = _G.MapkoSkin
    if not (skin and skin.addonName == "MSUF_Suite_Skin" and skin.DB and skin.Theme) then
        -- The switch remains discoverable before the optional engine loads.
        SearchRow(ctx, Row("toggle", "Enable Skinning", "enabled", "frame_basic"),
            "suite_skin_frame_basic", Tr("Basics"))
        return ctx.searchRows
    end
    BuildSections(ctx, b, skin)
    return ctx.searchRows
end

local function Build(ctx)
    local b = W.PageBuilder(ctx)
    local skin = Engine()
    if not skin then
        Section(ctx, b, "frame_basic", "Basics",
            P.Combat() and "Open Skinning outside combat to load its settings." or "The Suite skin engine is unavailable.",
            {}, true)
        return
    end
    -- FixedPreviewSection must own the first builder slot so its reserved
    -- header space contains the preview instead of leaving a blank gap.
    Preview(ctx, b, skin)
    BuildSections(ctx, b, skin)
end

P.RegisterPage({ key = PAGE, label = "Skinning", title = "Skinning", build = Build, icon = { 4, 1 },
    nav = "style", navOrder = 1,
    aliases = { "suite_skin", "mapkoskin", "skinning" } })
