local _, NS = ...

local Theme = {}
NS.Theme = Theme

local unpack = unpack

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

local function ReadColor(color)
    if not color then return nil end
    local r, g, b, a
    local getRGBA
    local ok = pcall(function()
        r, g, b, a = color.r, color.g, color.b, color.a
        getRGBA = color.GetRGBA
    end)
    if (not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number")
        and type(getRGBA) == "function" then
        ok, r, g, b, a = pcall(getRGBA, color)
    end
    if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
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
        local ok, localized, token = pcall(UnitClass, "player")
        if ok then className, classToken = localized, token end
    end

    local r, g, b, a
    if classToken and C_ClassColor and type(C_ClassColor.GetClassColor) == "function" then
        local ok, color = pcall(C_ClassColor.GetClassColor, classToken)
        if ok then r, g, b, a = ReadColor(color) end
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

function Theme.BuildClassPalette(refresh)
    local r, g, b = ResolvePlayerClassColor(refresh == true)
    local defaults = NS.BaseColors or NS.Defaults.theme.colors
    local palette = {}

    local function Tint(key, amount, alpha)
        local source = defaults[key]
        palette[key] = {
            Mix(source[1], r, amount),
            Mix(source[2], g, amount),
            Mix(source[3], b, amount),
            alpha or source[4],
        }
    end

    -- Midnight remains the readability base; the class hue progressively
    -- enters raised layers, borders, controls, and finally the exact accent.
    Tint("background", 0.035)
    Tint("ink", 0.045)
    Tint("surface", 0.065)
    Tint("raised", 0.100)
    Tint("card", 0.075)
    Tint("popup", 0.025)
    Tint("input", 0.030)
    Tint("buttonFill", 0.100)
    Tint("buttonFillAlt", 0.065)
    Tint("buttonBorder", 0.480, 0.90)
    Tint("iconBorder", 0.480, 0.92)
    Tint("rim", 0.420, 0.90)
    Tint("border", 0.480, 0.90)
    Tint("borderSoft", 0.280, 0.76)

    local dark = defaults.background
    palette.blue = { Mix(r, dark[1], 0.48), Mix(g, dark[2], 0.48), Mix(b, dark[3], 0.48), 1 }
    palette.accent = { r, g, b, 1 }
    palette.accentBright = { Mix(r, 1, 0.22), Mix(g, 1, 0.22), Mix(b, 1, 0.22), 1 }
    palette.hover = { Mix(r, dark[1], 0.76), Mix(g, dark[2], 0.76), Mix(b, dark[3], 0.76), 0.96 }
    palette.pressed = { Mix(r, dark[1], 0.52), Mix(g, dark[2], 0.52), Mix(b, dark[3], 0.52), 1 }
    palette.active = { Mix(r, dark[1], 0.58), Mix(g, dark[2], 0.58), Mix(b, dark[3], 0.58), 0.96 }
    palette.blizzardArrow = { r, g, b, 1 }
    palette.blizzardExpand = { r, g, b, 1 }
    palette.blizzardExpandPressed = { r, g, b, 1 }
    palette.blizzardExpandHover = { r, g, b, 1 }
    palette.blizzardClose = { Mix(r, 1, 0.22), Mix(g, 1, 0.22), Mix(b, 1, 0.22), 1 }
    palette.blizzardClosePressed = { r, g, b, 1 }
    palette.blizzardCloseHover = { Mix(r, 1, 0.38), Mix(g, 1, 0.38), Mix(b, 1, 0.38), 1 }
    palette.blizzardCloseDisabled = { Mix(r, dark[1], 0.72), Mix(g, dark[2], 0.72), Mix(b, dark[3], 0.72), 0.82 }
    palette.accentAlt = { Mix(r, 1, 0.12), Mix(g, 1, 0.12), Mix(b, 1, 0.12), 1 }
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
    palette.accentBright = { Mix(focusR, 1, 0.32), Mix(focusG, 1, 0.32), Mix(focusB, 1, 0.32), 0.80 }
    palette.hover = { focusR, focusG, focusB, 0.34 }
    palette.blizzardExpandPressed = { focusR, focusG, focusB, 1 }
    palette.blizzardExpandHover = { Mix(focusR, 1, 0.32), Mix(focusG, 1, 0.32), Mix(focusB, 1, 0.32), 1 }
    palette.checkmark = { focusR, focusG, focusB, 1 }
    palette.blizzardClose = { Mix(focusR, 1, 0.32), Mix(focusG, 1, 0.32), Mix(focusB, 1, 0.32), 1 }
    palette.blizzardClosePressed = { focusR, focusG, focusB, 1 }
    palette.blizzardCloseHover = { Mix(focusR, 1, 0.46), Mix(focusG, 1, 0.46), Mix(focusB, 1, 0.46), 1 }
    palette.blizzardCloseDisabled = { Mix(focusR, dark[1], 0.76), Mix(focusG, dark[2], 0.76), Mix(focusB, dark[3], 0.76), 0.82 }
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

-- Micro Bar colors are first-class editable tokens, but complete palette/look
-- changes should still produce a coherent result. Re-seed them from the final
-- resolved palette whenever the user deliberately applies a full preset.
local microPaletteSources = {
    microBarFill = "background",
    microBarFillAlt = "ink",
    microBarBorder = "border",
    microButtonFill = "buttonFill",
    microButtonFillAlt = "buttonFillAlt",
    microButtonBorder = "buttonBorder",
    microIcon = "text",
    microIconHover = "accentBright",
    microIconPressed = "accent",
    microIconDisabled = "disabled",
}
local microNamedPalettes = {
    modern = "midnight", midnightDark = "midnightDark", forever = "foreverGlass",
}

local function SynchronizeMicroPalette(colors, overrides)
    for target, source in pairs(microPaletteSources) do
        if not (overrides and overrides[target]) and colors[source] then
            colors[target] = NS.CopyValue(colors[source])
        end
    end
end

function Theme.GetColorTable(key)
    local source = microPaletteSources[key]
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
    if microPaletteSources[key] and NS.DB.icons and NS.DB.icons.microMenu then
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

local appearanceKeys = {
    gradientStrength = { 0, 1 },
    materialDepth = { 0, 1 },
    shellOpacity = { 0.35, 1 },
    panelOpacity = { 0.35, 1 },
    controlOpacity = { 0.35, 1 },
    borderOpacity = { 0, 1 },
    hoverIntensity = { 0, 1 },
    iconBorderThickness = { 1, 3 },
    iconBorderPadding = { 0, 3 },
    iconBorderOpacity = { 0, 1 },
}

local requiredLookAppearance = {
    "gradient", "gradientStrength", "materialDepth", "gradientDirection",
    "shellOpacity", "panelOpacity", "controlOpacity", "borderOpacity",
    "hoverStyle", "hoverIntensity", "iconBorderStyle", "iconBorderThickness",
    "iconBorderPadding", "iconBorderOpacity",
}
local allowedLookAppearance = {}
for index = 1, #requiredLookAppearance do
    allowedLookAppearance[requiredLookAppearance[index]] = true
end

local requiredLookGeometry = { "family", "radius", "border", "controlShape" }
local allowedLookGeometry = {}
for index = 1, #requiredLookGeometry do
    allowedLookGeometry[requiredLookGeometry[index]] = true
end

local function IsListed(list, value)
    for index = 1, #list do
        if list[index] == value then return true end
    end
    return false
end

local function InRange(value, minimum, maximum)
    return type(value) == "number" and value >= minimum and value <= maximum
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
    for key in pairs(appearance) do
        if not allowedLookAppearance[key] then return false, "invalid appearance key" end
    end
    for index = 1, #requiredLookAppearance do
        if appearance[requiredLookAppearance[index]] == nil then
            return false, "incomplete appearance"
        end
    end
    if type(appearance.gradient) ~= "boolean"
        or not IsListed(NS.GradientDirections, appearance.gradientDirection)
        or not IsListed(NS.HoverStyles, appearance.hoverStyle)
        or not IsListed(NS.IconBorderStyles, appearance.iconBorderStyle)
        or not InRange(appearance.gradientStrength, 0, 1)
        or not InRange(appearance.materialDepth, 0, 1)
        or not InRange(appearance.shellOpacity, 0.35, 1)
        or not InRange(appearance.panelOpacity, 0.35, 1)
        or not InRange(appearance.controlOpacity, 0.35, 1)
        or not InRange(appearance.borderOpacity, 0, 1)
        or not InRange(appearance.hoverIntensity, 0, 1)
        or not InRange(appearance.iconBorderThickness, 1, 3)
        or appearance.iconBorderThickness % 1 ~= 0
        or not InRange(appearance.iconBorderPadding, 0, 3)
        or appearance.iconBorderPadding % 1 ~= 0
        or not InRange(appearance.iconBorderOpacity, 0, 1) then
        return false, "invalid appearance value"
    end

    local geometry = look.geometry
    if type(geometry) ~= "table" then return false, "missing geometry" end
    for key in pairs(geometry) do
        if not allowedLookGeometry[key] then return false, "invalid geometry key" end
    end
    for index = 1, #requiredLookGeometry do
        if geometry[requiredLookGeometry[index]] == nil then
            return false, "incomplete geometry"
        end
    end
    if not IsListed(NS.GeometryFamilies, geometry.family)
        or not IsListed(NS.GeometryRadii, geometry.radius)
        or not IsListed(NS.GeometryBorders, geometry.border)
        or not IsListed(NS.ControlShapes, geometry.controlShape) then
        return false, "invalid geometry value"
    end
    return true
end

function Theme.SetAppearance(key, value)
    if NS.IsCombatLocked() then return false end
    if key == "gradient" then
        return Theme.SetGradient(value)
    elseif key == "gradientDirection" then
        local valid = false
        for index = 1, #NS.GradientDirections do
            valid = valid or NS.GradientDirections[index] == value
        end
        if not valid then return false end
    elseif key == "hoverStyle" then
        local valid = false
        for index = 1, #NS.HoverStyles do
            valid = valid or NS.HoverStyles[index] == value
        end
        if not valid then return false end
    elseif key == "iconBorderStyle" then
        local valid = false
        for index = 1, #NS.IconBorderStyles do
            valid = valid or NS.IconBorderStyles[index] == value
        end
        if not valid then return false end
    else
        local limits = appearanceKeys[key]
        if not limits then return false end
        value = tonumber(value)
        if not value then return false end
        value = math.max(limits[1], math.min(limits[2], value))
        if key == "iconBorderThickness" or key == "iconBorderPadding" then
            value = math.floor(value + 0.5)
        end
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
    if NS.IsCombatLocked() then
        return false
    end
    if key == "family" then
        local valid = false
        for index = 1, #NS.GeometryFamilies do
            valid = valid or NS.GeometryFamilies[index] == value
        end
        if not valid then return false end
    elseif key == "radius" then
        value = tonumber(value)
        local valid = false
        for index = 1, #NS.GeometryRadii do
            valid = valid or NS.GeometryRadii[index] == value
        end
        if not valid then return false end
    elseif key == "border" then
        value = tonumber(value)
        local valid = false
        for index = 1, #NS.GeometryBorders do
            valid = valid or NS.GeometryBorders[index] == value
        end
        if not valid then return false end
    elseif key == "controlShape" then
        local valid = false
        for index = 1, #NS.ControlShapes do
            valid = valid or NS.ControlShapes[index] == value
        end
        if not valid then return false end
    else
        return false
    end

    NS.DB.geometry[key] = value
    NS.DB.theme.look = "custom"
    NS.Registry.RefreshAll()
    NS.Registry.NotifyListeners("geometry", key)
    return true
end

function Theme.ApplyPreset(presetName)
    local overrides = NS.PresetOverrides[presetName]
    if NS.IsCombatLocked() or not overrides then
        return false
    end
    NS.DB.theme.colors = NS.CopyValue(NS.BaseColors or NS.Defaults.theme.colors)
    overrides = ResolvePaletteOverrides(presetName, presetName == "classColor")
    for key, value in pairs(overrides) do
        NS.DB.theme.colors[key] = NS.CopyValue(value)
    end
    SynchronizeMicroPalette(NS.DB.theme.colors, overrides)
    NS.DB.theme.preset = presetName
    NS.DB.theme.look = "custom"
    NS.Registry.RefreshAll()
    NS.Registry.NotifyListeners("theme", "preset")
    return true
end

function Theme.ApplyLook(lookName)
    local look = NS.LookPresets[lookName]
    if NS.IsCombatLocked() or not Theme.ValidateLook(lookName) then return false end
    NS.DB.theme.colors = NS.CopyValue(NS.BaseColors or NS.Defaults.theme.colors)
    local overrides = ResolvePaletteOverrides(look.palette, look.dynamicPalette ~= nil, look.dynamicPalette)
    for key, value in pairs(overrides) do
        NS.DB.theme.colors[key] = NS.CopyValue(value)
    end
    SynchronizeMicroPalette(NS.DB.theme.colors, overrides)
    for key, value in pairs(look.appearance or {}) do
        NS.DB.theme[key] = value
    end
    for key, value in pairs(look.geometry or {}) do
        NS.DB.geometry[key] = value
    end
    local micro = NS.DB.icons and NS.DB.icons.microMenu
    local microPreset = NS.MicroMenuPresetValues and NS.MicroMenuPresetValues[look.microStyle]
    if micro and microPreset then
        for _, key in ipairs(NS.MicroMenuLookKeys or {}) do
            if microPreset[key] ~= nil then micro[key] = microPreset[key] end
        end
        micro.preset = look.microStyle
    end
    if look.objectiveTrackerStyle then
        NS.DB.hud.objectiveTrackerStyle = look.objectiveTrackerStyle
    end
    NS.DB.theme.preset = look.palette
    NS.DB.theme.look = lookName
    local suite = _G.MSUFSuite
    if type(suite) == "table" and suite.Suite
        and type(suite.Suite.ApplyGlobalLook) == "function" then
        suite.Suite.ApplyGlobalLook(lookName)
    end
    NS.Registry.RefreshAll()
    if NS.Adapters and NS.Adapters.Refresh then
        NS.Adapters.Refresh("objectiveTracker")
    end
    NS.Registry.NotifyListeners("theme", "look")
    return true
end

function Theme.RefreshDynamicLook()
    if not NS.DB then return false end
    local look = NS.LookPresets[NS.DB.theme.look]
    if not look or not look.dynamicPalette or not Theme.ValidateLook(NS.DB.theme.look) then
        return false
    end
    local overrides = ResolvePaletteOverrides(look.palette, true, look.dynamicPalette)
    NS.DB.theme.colors = NS.CopyValue(NS.BaseColors or NS.Defaults.theme.colors)
    for key, value in pairs(overrides) do
        NS.DB.theme.colors[key] = NS.CopyValue(value)
    end
    SynchronizeMicroPalette(NS.DB.theme.colors, overrides)
    for key, value in pairs(look.appearance or {}) do NS.DB.theme[key] = value end
    for key, value in pairs(look.geometry or {}) do NS.DB.geometry[key] = value end
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
