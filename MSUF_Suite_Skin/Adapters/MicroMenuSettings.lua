local _, NS = ...

-- Micro Menu settings: the icon colours they resolve to, option validation,
-- presets and position presets. MicroMenu.lua (loaded before this file)
-- applies them to the native buttons and the owned bar.
local MicroMenuSkin = NS.MicroMenuSkin
-- MicroMenu.lua's private helpers: taken off NS again, so nothing internal
-- stays reachable through _G.MapkoSkin.
local Shared = NS.MicroMenuShared
NS.MicroMenuShared = nil
local Public = NS.Safety.Public
local Clamp = NS.Clamp
local IsListed = NS.IsListed
local Settings = Shared.Settings
local RefreshAfterSetting = Shared.RefreshAfterSetting

local STATE_TOKENS = {
    normal = "microIcon",
    hover = "microIconHover",
    pressed = "microIconPressed",
    disabled = "microIconDisabled",
}

local STATE_OPACITY = {
    normal = "normalOpacity",
    hover = "hoverOpacity",
    pressed = "pressedOpacity",
    disabled = "disabledOpacity",
}

-- Layout ownership and visual styling are intentionally independent. Moving,
-- scaling or unlocking the owned bar must not discard the selected icon look.
local VISUAL_OPTION_KEYS = {
    barBackground = true,
    barBorder = true,
    barMaterial = true,
    buttonBackground = true,
    buttonBorder = true,
    shape = true,
    radius = true,
    iconStyle = true,
    buttonSize = true,
    iconSize = true,
    hoverStyle = true,
    tint = true,
    normalOpacity = true,
    hoverOpacity = true,
    pressedOpacity = true,
    disabledOpacity = true,
}

local POSITION_KEYS = {
    layoutPoint = true,
    layoutRelativePoint = true,
    layoutX = true,
    layoutY = true,
}

local function NormalizeState(stateName)
    if stateName == "highlight" then return "hover" end
    if stateName == "pushed" then return "pressed" end
    if STATE_TOKENS[stateName] then return stateName end
    return "normal"
end

-- Icon colors -------------------------------------------------------------------------

local function ReadOriginalColor(original)
    if type(original) ~= "table" then return 1, 1, 1, 1 end
    local r, g, b, a
    if type(original.GetRGBA) == "function" then
        r, g, b, a = original:GetRGBA()
    end
    if type(r) ~= "number" then
        r, g, b, a = original.r or original[1], original.g or original[2],
            original.b or original[3], original.a or original[4]
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number"
        or not Public(r) or not Public(g) or not Public(b) or not Public(a) then
        return 1, 1, 1, 1
    end
    return Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), Clamp(type(a) == "number" and a or 1, 0, 1)
end

local function ClassColor(stateName)
    local r, g, b, a = NS.Theme.GetPlayerClassColor(false)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        r, g, b, a = 1, 1, 1, 1
    elseif type(a) ~= "number" then
        a = 1
    end
    if stateName == "hover" then
        r, g, b = r + (1 - r) * 0.25, g + (1 - g) * 0.25, b + (1 - b) * 0.25
    elseif stateName == "pressed" then
        r, g, b = r * 0.82, g * 0.82, b * 0.82
    elseif stateName == "disabled" then
        local gray = r * 0.299 + g * 0.587 + b * 0.114
        r, g, b = (r + gray) * 0.5, (g + gray) * 0.5, (b + gray) * 0.5
    end
    return Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1), Clamp(a, 0, 1)
end

function MicroMenuSkin.GetIconColor(stateName, original)
    stateName = NormalizeState(stateName)
    local originalR, originalG, originalB, originalA = ReadOriginalColor(original)
    local settings = Settings() or {}
    local opacity = Clamp(settings[STATE_OPACITY[stateName]] == nil
        and 1 or settings[STATE_OPACITY[stateName]], 0, 1)
    local tint = settings.tint or "native"
    if tint == "native" then
        return originalR, originalG, originalB, originalA * opacity
    end

    local r, g, b, a
    if tint == "class" then
        r, g, b, a = ClassColor(stateName)
        local _, _, _, tokenAlpha = NS.Theme.GetColor(STATE_TOKENS[stateName])
        if type(tokenAlpha) == "number" then a = a * tokenAlpha end
    else
        r, g, b, a = NS.Theme.GetColor(STATE_TOKENS[stateName])
        if tint == "monochrome" and type(r) == "number" and type(g) == "number"
            and type(b) == "number" then
            local luminance = Clamp(r * 0.2126 + g * 0.7152 + b * 0.0722, 0, 1)
            r, g, b = luminance, luminance, luminance
        end
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        r, g, b, a = originalR, originalG, originalB, 1
    end
    return Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1),
        originalA * Clamp(type(a) == "number" and a or 1, 0, 1) * opacity
end

-- Settings -------------------------------------------------------------------------------

local function MutableSettings()
    if not NS.DB then return nil end
    NS.DB.icons = NS.DB.icons or {}
    if not NS.DB.icons.microMenu then
        local defaults = NS.Defaults.icons.microMenu
        NS.DB.icons.microMenu = {}
        for key, value in pairs(defaults) do NS.DB.icons.microMenu[key] = value end
    end
    return NS.DB.icons.microMenu
end

-- Option validators: (value, settings) -> accepted, normalized value.
local function BooleanOption(value)
    return type(value) == "boolean", value
end

local function ListedOption(listName)
    return function(value) return IsListed(NS[listName], value), value end
end

local function RangeOption(minimum, maximum, integer)
    return function(value)
        value = tonumber(value)
        if not value or value < minimum or value > maximum then return false end
        return true, integer and math.floor(value + 0.5) or value
    end
end

local BorderRange = RangeOption(0, 2, true)
local ButtonSizeRange = RangeOption(20, 32, true)

local function BorderOption(value)
    if type(value) == "boolean" then value = value and 1 or 0 end
    return BorderRange(value)
end

local function OpacityOption(value)
    value = tonumber(value)
    return value ~= nil, value and Clamp(value, 0, 1)
end

local optionValidators = {
    layoutMode = ListedOption("MicroMenuLayoutModes"),
    visibility = ListedOption("MicroMenuVisibilityModes"),
    locked = BooleanOption,
    orientation = ListedOption("MicroMenuOrientations"),
    growth = ListedOption("MicroMenuGrowthModes"),
    buttonsPerLine = RangeOption(1, Shared.buttonCount, true),
    spacing = RangeOption(-8, 16, true),
    scale = RangeOption(0.5, 1.5, false),
    padding = RangeOption(0, 16, true),
    layoutPoint = ListedOption("MicroMenuPoints"),
    layoutRelativePoint = ListedOption("MicroMenuPoints"),
    layoutX = RangeOption(-4096, 4096, true),
    layoutY = RangeOption(-4096, 4096, true),
    positionPreset = function(value)
        return value == "custom" or NS.MicroMenuPositionPresets[value] ~= nil, value
    end,
    barBackground = BooleanOption,
    barBorder = BorderOption,
    barMaterial = ListedOption("MicroMenuBarMaterials"),
    buttonBackground = BooleanOption,
    buttonBorder = BorderOption,
    shape = ListedOption("MicroMenuShapes"),
    radius = function(value)
        value = tonumber(value)
        return IsListed(NS.GeometryRadii, value), value
    end,
    iconStyle = ListedOption("MicroMenuIconStyles"),
    buttonSize = function(value, settings)
        local accepted
        accepted, value = ButtonSizeRange(value)
        if accepted and tonumber(settings.iconSize) and settings.iconSize > value - 4 then
            settings.iconSize = value - 4
        end
        return accepted, value
    end,
    iconSize = function(value, settings)
        local maximum = math.min(28, (tonumber(settings.buttonSize) or 28) - 4)
        return RangeOption(10, maximum, true)(value)
    end,
    hoverStyle = ListedOption("MicroMenuHoverStyles"),
    tint = ListedOption("MicroMenuTintModes"),
    normalOpacity = OpacityOption,
    hoverOpacity = OpacityOption,
    pressedOpacity = OpacityOption,
    disabledOpacity = OpacityOption,
}
for _, condition in ipairs(NS.MicroMenuLoadConditions) do
    optionValidators[condition[1]] = BooleanOption
end

function MicroMenuSkin.ApplyPreset(presetName)
    if NS.IsCombatLocked() then return false, "combat" end
    if presetName == "recommended" or presetName == "default" then
        presetName = NS.Defaults.icons.microMenu.preset
    end
    local preset = NS.MicroMenuPresetValues[presetName]
    local settings = MutableSettings()
    if not preset or not settings then return false, "invalid preset" end
    for key in pairs(optionValidators) do
        if preset[key] ~= nil then settings[key] = preset[key] end
    end
    settings.preset = presetName
    return RefreshAfterSetting()
end

function MicroMenuSkin.SetOption(key, value)
    if NS.IsCombatLocked() then return false, "combat" end
    if key == "preset" then return MicroMenuSkin.ApplyPreset(value) end
    local validate = optionValidators[key]
    if not validate then return false, "unknown option" end
    local settings = MutableSettings()
    if not settings then return false, "settings" end
    local accepted
    accepted, value = validate(value, settings)
    if not accepted then return false, "invalid value" end

    settings[key] = value
    if VISUAL_OPTION_KEYS[key] then
        settings.preset = "custom"
    elseif key == "layoutMode" and settings.preset == "blizzard" and value ~= "blizzard" then
        settings.preset = "custom"
    elseif POSITION_KEYS[key] then
        settings.positionPreset = "custom"
    end
    return RefreshAfterSetting()
end

function MicroMenuSkin.ResetRecommended()
    if NS.IsCombatLocked() then return false, "combat" end
    local defaults = NS.Defaults.icons.microMenu
    local settings = MutableSettings()
    if not settings then return false, "settings" end
    for key in pairs(optionValidators) do
        if defaults[key] ~= nil then settings[key] = defaults[key] end
    end
    settings.preset = defaults.preset
    return RefreshAfterSetting()
end

function MicroMenuSkin.SetPositionPreset(presetName)
    if NS.IsCombatLocked() then return false, "combat" end
    local preset = NS.MicroMenuPositionPresets[presetName]
    local settings = MutableSettings()
    if not preset or not settings then return false, "invalid preset" end
    settings.layoutPoint = preset.point
    settings.layoutRelativePoint = preset.relativePoint or preset.point
    settings.layoutX = preset.x or 0
    settings.layoutY = preset.y or 0
    settings.positionPreset = presetName
    return RefreshAfterSetting()
end
