local _, NS = ...

local Theme = {}
NS.Theme = Theme

local unpack = unpack

local WHITE = { 1, 1, 1 }

local cachedClassToken
local cachedClassName
local cachedClassColor

local function Clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function Mix(first, second, amount)
    return Clamp01(first + (second - first) * amount)
end

-- A new color moved from r, g, b toward target by amount.
local function Blend(r, g, b, target, amount, alpha)
    return { Mix(r, target[1], amount), Mix(g, target[2], amount), Mix(b, target[3], amount), alpha }
end

local function IsListed(list, value)
    for index = 1, #list do
        if list[index] == value then return true end
    end
    return false
end

local function LinearChannel(value)
    if value <= 0.03928 then return value / 12.92 end
    return ((value + 0.055) / 1.055) ^ 2.4
end

local function RelativeLuminance(r, g, b)
    return LinearChannel(r) * 0.2126
        + LinearChannel(g) * 0.7152
        + LinearChannel(b) * 0.0722
end

local function ContrastRatio(r, g, b, background)
    local foregroundLuminance = RelativeLuminance(r, g, b)
    local backgroundLuminance = RelativeLuminance(background[1], background[2], background[3])
    local lighter = math.max(foregroundLuminance, backgroundLuminance)
    local darker = math.min(foregroundLuminance, backgroundLuminance)
    return (lighter + 0.05) / (darker + 0.05)
end

local function BrightenForContrast(r, g, b, background, minimum)
    if ContrastRatio(r, g, b, background) >= minimum then
        return r, g, b
    end

    local low, high = 0, 1
    for _ = 1, 10 do
        local amount = (low + high) * 0.5
        local testR, testG, testB = Mix(r, 1, amount), Mix(g, 1, amount), Mix(b, 1, amount)
        if ContrastRatio(testR, testG, testB, background) >= minimum then
            high = amount
        else
            low = amount
        end
    end
    return Mix(r, 1, high), Mix(g, 1, high), Mix(b, 1, high)
end

-- Reads a Blizzard class color: a ColorMixin or a RAID_CLASS_COLORS entry.
local function ReadColor(color)
    if type(color) ~= "table" then return nil end
    local r, g, b, a = color.r, color.g, color.b, color.a
    if (type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number")
        and type(color.GetRGBA) == "function" then
        r, g, b, a = color:GetRGBA()
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    return Clamp01(r), Clamp01(g), Clamp01(b), Clamp01(type(a) == "number" and a or 1)
end

local function ResolvePlayerClassColor(refresh)
    if refresh then
        cachedClassToken, cachedClassName, cachedClassColor = nil, nil, nil
    end
    if cachedClassColor then
        return cachedClassColor[1], cachedClassColor[2], cachedClassColor[3], cachedClassColor[4],
            cachedClassToken, cachedClassName
    end

    local className, classToken
    if type(UnitClass) == "function" then
        className, classToken = UnitClass("player")
    end

    local r, g, b, a
    if classToken and C_ClassColor and type(C_ClassColor.GetClassColor) == "function" then
        r, g, b, a = ReadColor(C_ClassColor.GetClassColor(classToken))
    end
    if not r and classToken and type(RAID_CLASS_COLORS) == "table" then
        r, g, b, a = ReadColor(RAID_CLASS_COLORS[classToken])
    end
    if not r then
        local fallback = (NS.BaseColors or NS.Defaults.theme.colors).accent
        r, g, b, a = fallback[1], fallback[2], fallback[3], fallback[4]
    end

    cachedClassToken = type(classToken) == "string" and classToken or "UNKNOWN"
    cachedClassName = type(className) == "string" and className or "Player"
    cachedClassColor = { r, g, b, a }
    return r, g, b, a, cachedClassToken, cachedClassName
end

function Theme.GetPlayerClassColor(refresh)
    return ResolvePlayerClassColor(refresh == true)
end

function Theme.GetClassLookLabel()
    local _, _, _, _, _, className = ResolvePlayerClassColor(false)
    return "Class: " .. className
end

-- Midnight remains the readability base; the class hue progressively enters
-- raised layers, borders, controls, and finally the exact accent.
-- { key, amount, alpha }; a missing alpha keeps the base color's alpha.
local CLASS_TINTS = {
    { "background", 0.035 },
    { "ink", 0.045 },
    { "surface", 0.065 },
    { "raised", 0.100 },
    { "card", 0.075 },
    { "popup", 0.025 },
    { "input", 0.030 },
    { "buttonFill", 0.100 },
    { "buttonFillAlt", 0.065 },
    { "buttonBorder", 0.480, 0.90 },
    { "iconBorder", 0.480, 0.92 },
    { "rim", 0.420, 0.90 },
    { "border", 0.480, 0.90 },
    { "borderSoft", 0.280, 0.76 },
}

function Theme.BuildClassPalette(refresh)
    local r, g, b = ResolvePlayerClassColor(refresh == true)
    local defaults = NS.BaseColors or NS.Defaults.theme.colors
    local palette = {}
    for index = 1, #CLASS_TINTS do
        local key, amount, alpha = CLASS_TINTS[index][1], CLASS_TINTS[index][2], CLASS_TINTS[index][3]
        local source = defaults[key]
        palette[key] = {
            Mix(source[1], r, amount),
            Mix(source[2], g, amount),
            Mix(source[3], b, amount),
            alpha or source[4],
        }
    end

    local dark = defaults.background
    palette.blue = Blend(r, g, b, dark, 0.48, 1)
    palette.accent = { r, g, b, 1 }
    palette.accentBright = Blend(r, g, b, WHITE, 0.22, 1)
    palette.hover = Blend(r, g, b, dark, 0.76, 0.96)
    palette.pressed = Blend(r, g, b, dark, 0.52, 1)
    palette.active = Blend(r, g, b, dark, 0.58, 0.96)
    palette.blizzardArrow = { r, g, b, 1 }
    palette.blizzardExpand = { r, g, b, 1 }
    palette.blizzardExpandPressed = { r, g, b, 1 }
    palette.blizzardExpandHover = { r, g, b, 1 }
    palette.blizzardClose = Blend(r, g, b, WHITE, 0.22, 1)
    palette.blizzardClosePressed = { r, g, b, 1 }
    palette.blizzardCloseHover = Blend(r, g, b, WHITE, 0.38, 1)
    palette.blizzardCloseDisabled = Blend(r, g, b, dark, 0.72, 0.82)
    palette.accentAlt = Blend(r, g, b, WHITE, 0.12, 1)
    return palette
end

function Theme.BuildGlassPalette(refresh)
    local r, g, b = ResolvePlayerClassColor(refresh == true)
    local palette = NS.CopyValue(NS.PresetOverrides.glass or {})
    local dark = palette.background or { 0, 0, 0, 1 }
    local focusR, focusG, focusB = BrightenForContrast(r, g, b,
        palette.surface or dark, 4.6)

    -- Keep broad selected and pressed fills on the neutral Glass blue ramp.
    -- The player-class hue is reserved for lightweight focus, glyph and edge
    -- details, with dark class colors minimally lifted for readability.
    palette.accent = { focusR, focusG, focusB, 1 }
    palette.accentBright = Blend(focusR, focusG, focusB, WHITE, 0.32, 0.80)
    palette.hover = { focusR, focusG, focusB, 0.34 }
    palette.blizzardExpandPressed = { focusR, focusG, focusB, 1 }
    palette.blizzardExpandHover = Blend(focusR, focusG, focusB, WHITE, 0.32, 1)
    palette.checkmark = { focusR, focusG, focusB, 1 }
    palette.blizzardClose = Blend(focusR, focusG, focusB, WHITE, 0.32, 1)
    palette.blizzardClosePressed = { focusR, focusG, focusB, 1 }
    palette.blizzardCloseHover = Blend(focusR, focusG, focusB, WHITE, 0.46, 1)
    palette.blizzardCloseDisabled = Blend(focusR, focusG, focusB, dark, 0.76, 0.82)
    return palette
end

local function ResolvePaletteOverrides(paletteName, refreshDynamic, dynamicPalette)
    if dynamicPalette == "playerClassGlass" then
        return Theme.BuildGlassPalette(refreshDynamic)
    end
    if paletteName == "classColor" then
        return Theme.BuildClassPalette(refreshDynamic)
    end
    return NS.PresetOverrides[paletteName] or {}
end

-- Micro Bar preset names that always use a named palette's micro colors.
local microNamedPalettes = {
    modern = "midnight", midnightDark = "midnightDark", forever = "foreverGlass",
}

-- Replaces the profile palette with the base colors plus these overrides.
-- Micro Bar colors are first-class editable tokens, but a complete palette
-- or look change should still produce a coherent result: tokens the palette
-- does not author are re-seeded from their base roles.
local function InstallPalette(overrides)
    local colors = NS.CopyValue(NS.BaseColors or NS.Defaults.theme.colors)
    for key, value in pairs(overrides) do
        colors[key] = NS.CopyValue(value)
    end
    for target, source in pairs(NS.MicroColorSources) do
        if not overrides[target] and colors[source] then
            colors[target] = NS.CopyValue(colors[source])
        end
    end
    NS.DB.theme.colors = colors
end

local function InstallLookValues(look)
    for key, value in pairs(look.appearance or {}) do NS.DB.theme[key] = value end
    for key, value in pairs(look.geometry or {}) do NS.DB.geometry[key] = value end
end

function Theme.GetColorTable(key)
    local source = NS.MicroColorSources[key]
    if source then
        local micro = NS.DB and NS.DB.icons and NS.DB.icons.microMenu
        local paletteName = micro and microNamedPalettes[micro.preset]
        if paletteName then
            local palette = NS.PresetOverrides[paletteName]
            return palette[key] or palette[source] or NS.BaseColors[key] or NS.BaseColors[source]
        end
    end
    local colors = NS.DB and NS.DB.theme and NS.DB.theme.colors
    return colors and colors[key] or NS.Defaults.theme.colors[key] or NS.Defaults.theme.colors.text
end

function Theme.GetColor(key)
    local color = Theme.GetColorTable(key)
    return color[1], color[2], color[3], color[4]
end

-- SetGradient takes ColorMixin objects. Reuse one while its values match
-- exactly, so repainting an unchanged theme allocates nothing.
function Theme.ReuseColor(color, r, g, b, a)
    if color and color.r == r and color.g == g and color.b == b and color.a == a then
        return color
    end
    return CreateColor(r, g, b, a)
end

function Theme.GetMaterial(role)
    return NS.Materials[role] or NS.Materials.panel
end

function Theme.GetMaterialOpacity(material)
    local theme = NS.DB and NS.DB.theme or NS.Defaults.theme
    local kind = material and material.opacity or "panel"
    if kind == "shell" then return theme.shellOpacity end
    if kind == "control" then return theme.controlOpacity end
    return theme.panelOpacity
end

function Theme.GetBorderOpacity()
    local theme = NS.DB and NS.DB.theme or NS.Defaults.theme
    return theme.borderOpacity
end

function Theme.SetColor(key, r, g, b, a)
    if NS.IsCombatLocked() or not NS.Defaults.theme.colors[key] then
        return false
    end
    local color = NS.DB.theme.colors[key]
    color[1] = math.max(0, math.min(1, tonumber(r) or color[1]))
    color[2] = math.max(0, math.min(1, tonumber(g) or color[2]))
    color[3] = math.max(0, math.min(1, tonumber(b) or color[3]))
    color[4] = math.max(0, math.min(1, tonumber(a) or color[4]))
    if NS.MicroColorSources[key] and NS.DB.icons and NS.DB.icons.microMenu then
        NS.DB.icons.microMenu.preset = "custom"
    end
    NS.DB.theme.preset = "custom"
    NS.DB.theme.look = "custom"
    NS.Registry.RefreshToken(key)
    NS.Registry.NotifyListeners("color", key)
    return true
end

function Theme.SetGradient(enabled)
    if NS.IsCombatLocked() then
        return false
    end
    NS.DB.theme.gradient = enabled == true
    NS.DB.theme.look = "custom"
    NS.Registry.RefreshAll()
    NS.Registry.NotifyListeners("theme", "gradient")
    return true
end

local appearanceChoices = {
    gradientDirection = "GradientDirections",
    hoverStyle = "HoverStyles",
    iconBorderStyle = "IconBorderStyles",
}

local appearanceRanges = {}
for index = 1, #NS.AppearanceRanges do
    local range = NS.AppearanceRanges[index]
    appearanceRanges[range[1]] = range
end

local requiredLookAppearance = {
    "gradient", "gradientStrength", "materialDepth", "gradientDirection",
    "shellOpacity", "panelOpacity", "controlOpacity", "borderOpacity",
    "hoverStyle", "hoverIntensity", "iconBorderStyle", "iconBorderThickness",
    "iconBorderPadding", "iconBorderOpacity",
}
local requiredLookGeometry = { "family", "radius", "border", "controlShape" }

local geometryChoices = {
    family = "GeometryFamilies",
    radius = "GeometryRadii",
    border = "GeometryBorders",
    controlShape = "ControlShapes",
}

local function KeySet(list)
    local set = {}
    for index = 1, #list do set[list[index]] = true end
    return set
end

local allowedLookAppearance = KeySet(requiredLookAppearance)
local allowedLookGeometry = KeySet(requiredLookGeometry)

-- Exactly the required keys, nothing else.
local function HasExactKeys(values, required, allowed)
    for key in pairs(values) do
        if not allowed[key] then return false, "invalid" end
    end
    for index = 1, #required do
        if values[required[index]] == nil then return false, "incomplete" end
    end
    return true
end

local function ValidAppearanceValues(appearance)
    if type(appearance.gradient) ~= "boolean" then return false end
    for key, listName in pairs(appearanceChoices) do
        if not IsListed(NS[listName], appearance[key]) then return false end
    end
    for index = 1, #NS.AppearanceRanges do
        local range = NS.AppearanceRanges[index]
        local value = appearance[range[1]]
        if type(value) ~= "number" or value < range[2] or value > range[3]
            or (range[4] and value % 1 ~= 0) then
            return false
        end
    end
    return true
end

local function ValidGeometryValues(geometry)
    for key, listName in pairs(geometryChoices) do
        if not IsListed(NS[listName], geometry[key]) then return false end
    end
    return true
end

function Theme.ValidateLook(lookName)
    local look = type(lookName) == "string" and NS.LookPresets[lookName] or nil
    if not look or type(look.label) ~= "string" or look.label == ""
        or type(look.description) ~= "string" or look.description == "" then
        return false, "missing look metadata"
    end
    if type(look.palette) ~= "string" or not NS.PresetOverrides[look.palette] then
        return false, "missing palette"
    end
    if look.dynamicPalette ~= nil and look.dynamicPalette ~= "playerClass"
        and look.dynamicPalette ~= "playerClassGlass" then
        return false, "invalid dynamic palette"
    end
    if look.dynamicPalette == "playerClass" and look.palette ~= "classColor"
        or look.dynamicPalette == "playerClassGlass" and look.palette ~= "glass" then
        return false, "dynamic palette mismatch"
    end

    local appearance = look.appearance
    if type(appearance) ~= "table" then return false, "missing appearance" end
    local exact, problem = HasExactKeys(appearance, requiredLookAppearance, allowedLookAppearance)
    if not exact then
        return false, problem == "invalid" and "invalid appearance key" or "incomplete appearance"
    end
    if not ValidAppearanceValues(appearance) then return false, "invalid appearance value" end

    local geometry = look.geometry
    if type(geometry) ~= "table" then return false, "missing geometry" end
    exact, problem = HasExactKeys(geometry, requiredLookGeometry, allowedLookGeometry)
    if not exact then
        return false, problem == "invalid" and "invalid geometry key" or "incomplete geometry"
    end
    if not ValidGeometryValues(geometry) then return false, "invalid geometry value" end
    return true
end

function Theme.SetAppearance(key, value)
    if NS.IsCombatLocked() then return false end
    if key == "gradient" then return Theme.SetGradient(value) end
    local listName = appearanceChoices[key]
    if listName then
        if not IsListed(NS[listName], value) then return false end
    else
        local range = appearanceRanges[key]
        if not range then return false end
        value = tonumber(value)
        if not value then return false end
        value = math.max(range[2], math.min(range[3], value))
        if range[4] then value = math.floor(value + 0.5) end
    end
    NS.DB.theme[key] = value
    NS.DB.theme.look = "custom"
    if key == "hoverStyle" or key == "hoverIntensity" then
        NS.Registry.RefreshToken("hover")
    else
        NS.Registry.RefreshAll()
    end
    NS.Registry.NotifyListeners("appearance", key)
    return true
end

function Theme.SetGeometry(key, value)
    if NS.IsCombatLocked() then return false end
    local listName = geometryChoices[key]
    if not listName then return false end
    if key == "radius" or key == "border" then value = tonumber(value) end
    if not IsListed(NS[listName], value) then return false end

    NS.DB.geometry[key] = value
    NS.DB.theme.look = "custom"
    NS.Registry.RefreshAll()
    NS.Registry.NotifyListeners("geometry", key)
    return true
end

function Theme.ApplyPreset(presetName)
    if NS.IsCombatLocked() or not NS.PresetOverrides[presetName] then
        return false
    end
    InstallPalette(ResolvePaletteOverrides(presetName, presetName == "classColor"))
    NS.DB.theme.preset = presetName
    NS.DB.theme.look = "custom"
    NS.Registry.RefreshAll()
    NS.Registry.NotifyListeners("theme", "preset")
    return true
end

function Theme.ApplyLook(lookName)
    local look = NS.LookPresets[lookName]
    if NS.IsCombatLocked() or not Theme.ValidateLook(lookName) then return false end
    InstallPalette(ResolvePaletteOverrides(look.palette, look.dynamicPalette ~= nil, look.dynamicPalette))
    InstallLookValues(look)
    local micro = NS.DB.icons and NS.DB.icons.microMenu
    local microPreset = NS.MicroMenuPresetValues and NS.MicroMenuPresetValues[look.microStyle]
    if micro and microPreset then
        for _, key in ipairs(NS.MicroMenuLookKeys or {}) do
            if microPreset[key] ~= nil then micro[key] = microPreset[key] end
        end
        micro.preset = look.microStyle
    end
    NS.DB.theme.preset = look.palette
    NS.DB.theme.look = lookName
    local suite = _G.MSUFSuite
    if type(suite) == "table" and suite.Suite
        and type(suite.Suite.ApplyGlobalLook) == "function" then
        suite.Suite.ApplyGlobalLook(lookName)
    end
    NS.Registry.RefreshAll()
    NS.Registry.NotifyListeners("theme", "look")
    return true
end

function Theme.RefreshDynamicLook()
    if not NS.DB then return false end
    local look = NS.LookPresets[NS.DB.theme.look]
    if not look or not look.dynamicPalette or not Theme.ValidateLook(NS.DB.theme.look) then
        return false
    end
    InstallPalette(ResolvePaletteOverrides(look.palette, true, look.dynamicPalette))
    InstallLookValues(look)
    NS.DB.theme.preset = look.palette
    return true
end

function Theme.ResetColors()
    if NS.IsCombatLocked() then
        return false
    end
    NS.Database.ResetColors()
    NS.DB.theme.look = "custom"
    NS.Registry.RefreshAll()
    NS.Registry.NotifyListeners("theme", "colors")
    return true
end

function Theme.GetRGBA(key)
    return unpack(Theme.GetColorTable(key))
end
