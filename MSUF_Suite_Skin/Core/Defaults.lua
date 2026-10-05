local _, NS = ...

local function Color(r, g, b, a)
    return { r, g, b, a or 1 }
end

local function Hex(value, alpha)
    value = tostring(value or ""):gsub("#", "")
    return Color(
        tonumber(value:sub(1, 2), 16) / 255,
        tonumber(value:sub(3, 4), 16) / 255,
        tonumber(value:sub(5, 6), 16) / 255,
        alpha
    )
end

local function WithAlpha(color, alpha)
    return Color(color[1], color[2], color[3], alpha)
end

local midnightColors = {
    background = Color(0.020, 0.039, 0.071, 0.940),
    ink = Color(0.027, 0.063, 0.106, 0.920),
    surface = Color(0.035, 0.067, 0.114, 0.900),
    raised = Color(0.055, 0.098, 0.161, 0.900),
    rim = Color(0.102, 0.173, 0.259, 0.860),
    blue = Color(0.141, 0.365, 0.741, 1.000),
    accent = Color(0.231, 0.510, 0.965, 1.000),
    accentBright = Color(0.357, 0.608, 1.000, 1.000),
    text = Color(0.933, 0.957, 1.000, 1.000),
    title = Color(0.957, 0.973, 1.000, 1.000),
    muted = Color(0.659, 0.706, 0.780, 0.960),
    dim = Color(0.500, 0.550, 0.650, 0.920),
    disabled = Color(0.460, 0.510, 0.590, 0.820),
    border = Color(0.102, 0.173, 0.259, 0.860),
    borderSoft = Color(0.086, 0.149, 0.227, 0.720),
    card = Color(0.055, 0.098, 0.161, 0.900),
    popup = Color(0.020, 0.039, 0.071, 0.980),
    input = Color(0.020, 0.039, 0.071, 0.960),
    buttonFill = Color(0.055, 0.098, 0.161, 0.900),
    buttonFillAlt = Color(0.035, 0.067, 0.114, 0.900),
    buttonBorder = Color(0.102, 0.173, 0.259, 0.860),
    iconBorder = Color(0.102, 0.173, 0.259, 0.920),
    microBarFill = Color(0.020, 0.039, 0.071, 0.940),
    microBarFillAlt = Color(0.027, 0.063, 0.106, 0.920),
    microBarBorder = Color(0.102, 0.173, 0.259, 0.900),
    microButtonFill = Color(0.055, 0.098, 0.161, 0.900),
    microButtonFillAlt = Color(0.035, 0.067, 0.114, 0.900),
    microButtonBorder = Color(0.102, 0.173, 0.259, 0.900),
    microIcon = Color(0.933, 0.957, 1.000, 1.000),
    microIconHover = Color(0.357, 0.608, 1.000, 1.000),
    microIconPressed = Color(0.231, 0.510, 0.965, 1.000),
    microIconDisabled = Color(0.500, 0.550, 0.650, 0.820),
    hover = Color(0.063, 0.145, 0.255, 0.960),
    pressed = Color(0.102, 0.247, 0.498, 1.000),
    active = Color(0.141, 0.365, 0.741, 0.960),
    success = Color(0.259, 0.827, 0.573, 1.000),
    warning = Color(0.851, 0.643, 0.255, 1.000),
    blizzardYellow = Color(1.000, 0.820, 0.000, 1.000),
    blizzardArrow = Color(1.000, 0.820, 0.000, 1.000),
    blizzardExpand = Color(1.000, 0.820, 0.000, 1.000),
    blizzardExpandPressed = Color(1.000, 0.820, 0.000, 1.000),
    blizzardExpandHover = Color(1.000, 0.820, 0.000, 1.000),
    checkmark = Color(1.000, 0.820, 0.000, 1.000),
    blizzardClose = Color(0.357, 0.608, 1.000, 1.000),
    blizzardClosePressed = Color(0.231, 0.510, 0.965, 1.000),
    blizzardCloseHover = Color(0.565, 0.733, 1.000, 1.000),
    blizzardCloseDisabled = Color(0.500, 0.550, 0.650, 0.820),
    danger = Color(0.878, 0.322, 0.369, 1.000),
    accentAlt = Color(0.851, 0.643, 0.255, 1.000),
}

-- Canonicalized from the user-approved MSKIN1 Dark profile. Values retain the
-- exported precision that materially affects rendering; the selected external
-- font alias is mapped below to MapkoSkin's identical bundled media name.
local darkColors = {
    background = Color(0.018, 0.020, 0.026, 0.985),
    ink = Color(0.027, 0.031, 0.039, 0.980),
    surface = Color(0.043, 0.047, 0.057, 0.970),
    raised = Color(0.067, 0.073, 0.086, 0.980),
    rim = Color(0.180, 0.196, 0.224, 0.820),
    blue = Color(0.000, 0.000, 0.000, 1.000),
    accent = Color(0.000, 0.000, 0.000, 1.000),
    accentBright = Color(0.600, 0.600, 0.600, 1.000),
    text = Color(0.933, 0.957, 1.000, 1.000),
    title = Color(0.957, 0.973, 1.000, 1.000),
    muted = Color(0.659, 0.706, 0.780, 0.960),
    dim = Color(0.500, 0.550, 0.650, 0.920),
    disabled = Color(0.460, 0.510, 0.590, 0.820),
    border = Color(0.200, 0.216, 0.247, 0.860),
    borderSoft = Color(0.135, 0.149, 0.176, 0.760),
    card = Color(0.052, 0.057, 0.068, 0.970),
    popup = Color(0.016, 0.018, 0.023, 0.995),
    input = Color(0.010, 0.012, 0.016, 0.990),
    buttonFill = Color(0.067, 0.073, 0.086, 0.980),
    buttonFillAlt = Color(0.043, 0.047, 0.057, 0.970),
    buttonBorder = Color(0.200, 0.216, 0.247, 0.860),
    iconBorder = Color(0.200, 0.216, 0.247, 0.920),
    microBarFill = Color(0.018, 0.020, 0.026, 0.985),
    microBarFillAlt = Color(0.027, 0.031, 0.039, 0.980),
    microBarBorder = Color(0.200, 0.216, 0.247, 0.900),
    microButtonFill = Color(0.067, 0.073, 0.086, 0.980),
    microButtonFillAlt = Color(0.043, 0.047, 0.057, 0.970),
    microButtonBorder = Color(0.200, 0.216, 0.247, 0.900),
    microIcon = Color(0.933, 0.957, 1.000, 1.000),
    microIconHover = Color(1.000, 1.000, 1.000, 1.000),
    microIconPressed = Color(0.780, 0.800, 0.840, 1.000),
    microIconDisabled = Color(0.460, 0.510, 0.590, 0.820),
    hover = Color(0.419608, 0.419608, 0.419608, 0.950),
    pressed = Color(0.050980, 0.121569, 0.247059, 1.000),
    active = Color(0.682353, 0.682353, 0.682353, 0.960),
    success = Color(0.259, 0.827, 0.573, 1.000),
    warning = Color(1.000, 1.000, 1.000, 1.000),
    blizzardYellow = Color(1.000, 1.000, 1.000, 1.000),
    blizzardArrow = Color(1.000, 1.000, 1.000, 1.000),
    blizzardExpand = Color(1.000, 1.000, 1.000, 1.000),
    blizzardExpandPressed = Color(1.000, 1.000, 1.000, 1.000),
    blizzardExpandHover = Color(1.000, 1.000, 1.000, 1.000),
    checkmark = Color(1.000, 1.000, 1.000, 1.000),
    blizzardClose = Color(1.000, 1.000, 1.000, 1.000),
    blizzardClosePressed = Color(0.780, 0.800, 0.840, 1.000),
    blizzardCloseHover = Color(1.000, 1.000, 1.000, 1.000),
    blizzardCloseDisabled = Color(0.460, 0.510, 0.590, 0.820),
    danger = Color(0.878, 0.322, 0.369, 1.000),
    accentAlt = Color(1.000, 1.000, 1.000, 1.000),
}

local function CopyValue(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[CopyValue(key, seen)] = CopyValue(child, seen)
    end
    return copy
end

-- Value helpers the settings code shares (Database, Theme, rendering). This
-- file loads before all of them.
local function IsListed(list, value)
    for index = 1, #list do
        if list[index] == value then return true end
    end
    return false
end

-- A number between minimum and maximum; minimum for anything else, NaN
-- included (it fails every comparison, so it takes the first branch).
local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if not (value >= minimum) then return minimum end
    if value > maximum then return maximum end
    return value
end

NS.CopyValue = CopyValue
NS.IsListed = IsListed
NS.Clamp = Clamp
NS.BaseColors = midnightColors

-- Forever's Camelot bar has fourteen Micro Buttons, every other client 13.
NS.MicroMenuMaxButtonsPerLine = NS.Client.isForever and 14 or 13

NS.Defaults = {
    revision = 52,
    enabled = true,
    characterDetails = { view = "modern", enabled = true, expanded = true, styleEQoL = true, inlineGear = true, wideLayout = true },
    characterStats = { enabled = true, diminishingReturns = true },
    windowControls = { enabled = true, scales = {}, positions = {} },
    theme = {
        colors = darkColors,
        gradient = false,
        gradientStrength = 1,
        materialDepth = 0.14,
        gradientDirection = "VERTICAL",
        shellOpacity = 1,
        panelOpacity = 1,
        controlOpacity = 1,
        borderOpacity = 1,
        hoverStyle = "outline",
        hoverIntensity = 1,
        iconBorderStyle = "quality",
        iconBorderThickness = 1,
        iconBorderPadding = 0,
        iconBorderOpacity = 1,
        preset = "dark",
        look = "dark",
    },
    geometry = {
        family = "continuous",
        radius = 8,
        border = 1,
        controlShape = "round",
    },
    typography = {
        enabled = true,
        followMSUF = true,
        face = "sharedMedia",
        sharedMediaFont = "MapkoSkin - Expressway ExtraBold",
        customPath = "",
        applyChat = true,
        includeSpecial = true,
    },
    skins = {
        blizzardWindows = true,
        colorPicker = true,
        settings = true,
        addonList = true,
        gameMenu = true,
        worldMap = true,
        playerSpells = true,
        encounterJournal = true,
        chatFrames = true,
        damageMeter = true,
        editMode = true,
        communities = true,
        microMenu = true,
    },
    skinCategories = {
        character = true,
        inventory = true,
        npc = true,
        quest = true,
        social = true,
        group = true,
        profession = true,
        economy = true,
        journal = true,
        map = true,
        calendar = true,
        utility = true,
        ["item-service"] = true,
        expansion = true,
        housing = true,
        hud = true,
        tutorial = true,
    },
    hud = {
        damageMeterWindows = true,
        damageMeterRows = true,
        damageMeterDetails = true,
    },
    icons = {
        windowActions = {
            style = "bare",
            glyphMode = "plusMinus",
            weight = "fine",
            glyphSize = 12,
            closeGlyphSize = 16,
            glyphOffsetX = 0,
            glyphOffsetY = 0,
            surfaceInset = 2,
            surfaceShape = "global",
            surfaceRadius = 4,
            opacity = 0.78,
        },
        microMenu = {
            preset = "forever",
            layoutMode = "owned",
            visibility = "always",
            loadHideInHousing = false,
            loadHideInCombat = false,
            loadHideInGroup = false,
            loadHideInInstance = false,
            loadHideInVehicle = false,
            loadHideMounted = false,
            loadHideNoTarget = false,
            loadHideOutOfCombat = false,
            loadHideOutOfCombatNoTarget = false,
            loadHideResting = false,
            loadHideSolo = false,
            loadHideStealthed = false,
            loadShowWhenInjured = false,
            locked = true,
            orientation = "horizontal",
            growth = "LEFT_UP",
            buttonsPerLine = NS.MicroMenuMaxButtonsPerLine,
            spacing = -2,
            scale = 1.00,
            padding = 6,
            layoutPoint = "BOTTOMRIGHT",
            layoutRelativePoint = "BOTTOMRIGHT",
            layoutX = -24,
            layoutY = 24,
            positionPreset = "bottomRight",
            barBackground = true,
            barBorder = 1,
            buttonBackground = true,
            buttonBorder = 1,
            shape = "continuous",
            radius = 6,
            iconStyle = "line",
            buttonSize = 28,
            iconSize = 18,
            hoverStyle = "outline",
            tint = "theme",
            normalOpacity = 1,
            hoverOpacity = 1,
            pressedOpacity = 1,
            disabledOpacity = 0.75,
        },
    },
}

NS.ColorOrder = {
    { "background", "COLOR_BACKGROUND" },
    { "ink", "COLOR_INK" },
    { "surface", "COLOR_SURFACE" },
    { "raised", "COLOR_RAISED" },
    { "rim", "COLOR_RIM" },
    { "blue", "COLOR_BLUE" },
    { "accent", "COLOR_ACCENT" },
    { "accentBright", "COLOR_ACCENT_BRIGHT" },
    { "text", "COLOR_TEXT" },
    { "title", "COLOR_TITLE" },
    { "muted", "COLOR_MUTED" },
    { "dim", "COLOR_DIM" },
    { "disabled", "COLOR_DISABLED" },
    { "border", "COLOR_BORDER" },
    { "borderSoft", "COLOR_BORDER_SOFT" },
    { "card", "COLOR_CARD" },
    { "popup", "COLOR_POPUP" },
    { "input", "COLOR_INPUT" },
    { "buttonFill", "COLOR_BUTTON_FILL" },
    { "buttonFillAlt", "COLOR_BUTTON_FILL_ALT" },
    { "buttonBorder", "COLOR_BUTTON_BORDER" },
    { "iconBorder", "COLOR_ICON_BORDER" },
    { "microBarFill", "COLOR_MICRO_BAR_FILL" },
    { "microBarFillAlt", "COLOR_MICRO_BAR_FILL_ALT" },
    { "microBarBorder", "COLOR_MICRO_BAR_BORDER" },
    { "microButtonFill", "COLOR_MICRO_BUTTON_FILL" },
    { "microButtonFillAlt", "COLOR_MICRO_BUTTON_FILL_ALT" },
    { "microButtonBorder", "COLOR_MICRO_BUTTON_BORDER" },
    { "microIcon", "COLOR_MICRO_ICON" },
    { "microIconHover", "COLOR_MICRO_ICON_HOVER" },
    { "microIconPressed", "COLOR_MICRO_ICON_PRESSED" },
    { "microIconDisabled", "COLOR_MICRO_ICON_DISABLED" },
    { "hover", "COLOR_HOVER" },
    { "pressed", "COLOR_PRESSED" },
    { "active", "COLOR_ACTIVE" },
    { "success", "COLOR_SUCCESS" },
    { "warning", "COLOR_WARNING" },
    { "blizzardYellow", "COLOR_BLIZZARD_YELLOW" },
    { "blizzardArrow", "COLOR_BLIZZARD_ARROW" },
    { "blizzardExpand", "COLOR_BLIZZARD_EXPAND" },
    { "blizzardExpandPressed", "COLOR_BLIZZARD_EXPAND_PRESSED" },
    { "blizzardExpandHover", "COLOR_BLIZZARD_EXPAND_HOVER" },
    { "checkmark", "COLOR_CHECKMARK" },
    { "blizzardClose", "COLOR_BLIZZARD_CLOSE" },
    { "blizzardClosePressed", "COLOR_BLIZZARD_CLOSE_PRESSED" },
    { "blizzardCloseHover", "COLOR_BLIZZARD_CLOSE_HOVER" },
    { "blizzardCloseDisabled", "COLOR_BLIZZARD_CLOSE_DISABLED" },
    { "danger", "COLOR_DANGER" },
    { "accentAlt", "COLOR_ACCENT_ALT" },
}

NS.GeometryFamilies = { "round", "continuous", "squircle" }
NS.GeometryRadii = { 4, 6, 8, 12 }
NS.GeometryBorders = { 0, 1, 2 }
NS.ControlShapes = { "pill", "round", "continuous", "squircle" }
NS.GradientDirections = { "VERTICAL", "HORIZONTAL" }
NS.HoverStyles = { "outline", "softFill", "solidFill", "off" }
NS.IconBorderStyles = { "quality", "theme", "off" }
NS.WindowActionStyles = { "bare", "soft", "outline", "native" }
NS.WindowActionGlyphModes = { "plusMinus", "chevrons" }
NS.WindowActionWeights = { "fine", "bold" }
NS.WindowActionShapes = { "global", "round", "continuous", "squircle" }
NS.MicroMenuPresets = { "modern", "midnightDark", "forever", "blizzard" }
NS.MicroMenuBarMaterials = { "forever", "modern", "midnightDark", "theme" }
NS.MicroMenuTintModes = { "native", "theme", "class", "monochrome" }
NS.MicroMenuIconStyles = { "line", "bold", "blizzardIcons", "blizzard" }
NS.MicroMenuHoverStyles = { "outline", "softFill", "solidFill", "iconOnly", "off" }
NS.MicroMenuShapes = { "global", "round", "continuous", "squircle" }
NS.MicroMenuLayoutModes = { "owned", "blizzard" }
NS.MicroMenuVisibilityModes = { "always", "combat", "outOfCombat", "mouseover", "never" }
NS.MicroMenuLoadConditions = {
    { "loadHideInHousing", "Housing" },
    { "loadHideInCombat", "In combat", "[combat] hide" },
    { "loadHideInGroup", "In group", "[group] hide" },
    { "loadHideInInstance", "In instance" },
    { "loadHideInVehicle", "In vehicle", "[@player,unithasvehicleui] hide; [vehicleui] hide" },
    { "loadHideMounted", "Mounted", "[mounted] hide" },
    { "loadHideNoTarget", "No target", "[@target,noexists] hide" },
    { "loadHideOutOfCombat", "Out of combat", "[nocombat] hide" },
    { "loadHideOutOfCombatNoTarget", "Out of combat and no target", "[nocombat,@target,noexists] hide" },
    { "loadHideResting", "Resting", "[resting] hide" },
    { "loadHideSolo", "Solo", "[nogroup] hide" },
    { "loadHideStealthed", "Stealthed", "[stealth] hide" },
    { "loadShowWhenInjured", "Show only below 100% health" },
}
NS.MicroMenuOrientations = { "horizontal", "vertical" }
NS.MicroMenuGrowthModes = { "RIGHT_DOWN", "LEFT_DOWN", "RIGHT_UP", "LEFT_UP" }
NS.MicroMenuPoints = {
    "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
NS.MicroMenuPositionPresets = {
    bottomLeft = {
        point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 18, y = 18,
    },
    bottomRight = {
        point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -24, y = 24,
    },
    bottomCenter = {
        point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 120,
    },
    topRight = {
        point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -24, y = -24,
    },
    topCenter = {
        point = "TOP", relativePoint = "TOP", x = 0, y = -18,
    },
}
NS.MicroMenuPresetValues = {
    forever = {
        layoutMode = "owned",
        barBackground = true, barBorder = 1, barMaterial = "forever",
        buttonBackground = false, buttonBorder = 0,
        shape = "continuous", radius = 8,
        iconStyle = "bold", buttonSize = 30, iconSize = 22,
        hoverStyle = "softFill", tint = "theme",
        spacing = -3, scale = 1.00, padding = 5,
        normalOpacity = 1, hoverOpacity = 1, pressedOpacity = 1, disabledOpacity = 1,
    },
    modern = {
        layoutMode = "owned",
        barBackground = true, barBorder = 1, barMaterial = "modern",
        buttonBackground = false, buttonBorder = 0,
        shape = "continuous", radius = 8,
        iconStyle = "bold", buttonSize = 30, iconSize = 22,
        hoverStyle = "softFill", tint = "theme",
        spacing = 1, scale = 1.00, padding = 6,
        normalOpacity = 1, hoverOpacity = 1, pressedOpacity = 1, disabledOpacity = 1,
    },
    midnightDark = {
        layoutMode = "owned",
        barBackground = true, barBorder = 1, barMaterial = "midnightDark",
        buttonBackground = false, buttonBorder = 0,
        shape = "continuous", radius = 8,
        iconStyle = "bold", buttonSize = 30, iconSize = 22,
        hoverStyle = "softFill", tint = "theme",
        spacing = 1, scale = 1.00, padding = 6,
        normalOpacity = 1, hoverOpacity = 1, pressedOpacity = 1, disabledOpacity = 1,
    },
    blizzard = {
        layoutMode = "blizzard",
        barBackground = false, barBorder = 0, barMaterial = "theme",
        buttonBackground = false, buttonBorder = 0,
        shape = "global", radius = 8,
        iconStyle = "blizzard", buttonSize = 32, iconSize = 24,
        hoverStyle = "off", tint = "native",
        spacing = 0, scale = 1, padding = 0,
        normalOpacity = 1, hoverOpacity = 1, pressedOpacity = 1, disabledOpacity = 1,
    },
}

-- Presets choose the Suite or Blizzard layout without changing the saved
-- position, orientation, visibility or number of buttons per line.
NS.MicroMenuLookKeys = {
    "barBackground", "barBorder", "barMaterial", "buttonBackground", "buttonBorder",
    "shape", "radius", "iconStyle", "buttonSize", "iconSize",
    "hoverStyle", "tint", "spacing", "padding", "normalOpacity",
    "hoverOpacity", "pressedOpacity", "disabledOpacity",
}

function NS.IsRetailPanelMicroBar(micro)
    return NS.Client.isMainline and not NS.Client.isForever
        and type(micro) == "table" and micro.orientation == "vertical"
        and micro.buttonsPerLine == 6
        and micro.scale == 0.7 and micro.layoutPoint == "BOTTOMRIGHT"
        and micro.layoutRelativePoint == "BOTTOMRIGHT" and micro.layoutY == 0
        and type(micro.layoutX) == "number" and math.abs(micro.layoutX + 522) <= 6
end

function NS.AlignRetailPanelMicroBar(micro)
    if not NS.IsRetailPanelMicroBar(micro) or micro.layoutMode ~= "owned" then return false end
    micro.spacing, micro.padding = 5, 5
    return true
end

-- Micro Bar color tokens follow these base palette roles whenever a palette
-- does not author them. Shared by the defaults, profile migrations and Theme.
NS.MicroColorSources = {
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

-- Numeric setting ranges as { key, minimum, maximum, integer }. Profile
-- normalization clamps to them; interactive setters reject values outside.
NS.AppearanceRanges = {
    { "gradientStrength", 0, 1 },
    { "materialDepth", 0, 1 },
    { "shellOpacity", 0.35, 1 },
    { "panelOpacity", 0.35, 1 },
    { "controlOpacity", 0.35, 1 },
    { "borderOpacity", 0, 1 },
    { "hoverIntensity", 0, 1 },
    { "iconBorderThickness", 1, 3, true },
    { "iconBorderPadding", 0, 3, true },
    { "iconBorderOpacity", 0, 1 },
}

NS.WindowActionRanges = {
    { "glyphSize", 8, 18, true },
    { "closeGlyphSize", 6, 18, true },
    { "glyphOffsetX", -4, 4, true },
    { "glyphOffsetY", -4, 4, true },
    { "surfaceInset", 0, 6, true },
    { "opacity", 0.35, 1 },
}

-- iconSize is clamped separately because its maximum follows buttonSize.
NS.MicroMenuRanges = {
    { "buttonsPerLine", 1, NS.MicroMenuMaxButtonsPerLine, true },
    { "spacing", -8, 16, true },
    { "scale", 0.5, 1.5 },
    { "padding", 0, 16, true },
    { "layoutX", -4096, 4096, true },
    { "layoutY", -4096, 4096, true },
    { "barBorder", 0, 2, true },
    { "buttonBorder", 0, 2, true },
    { "buttonSize", 20, 32, true },
    { "normalOpacity", 0, 1 },
    { "hoverOpacity", 0, 1 },
    { "pressedOpacity", 0, 1 },
    { "disabledOpacity", 0, 1 },
}

-- Saved Blizzard window scales and positions.
NS.WindowLayoutLimits = {
    minScale = 0.70,
    maxScale = 1.50,
    maxOffset = 8192,
    maxNameLength = 80,
    maxEntries = 128,
}

NS.Materials = {
    shell = { from = "background", to = "ink", border = "rim", opacity = "shell" },
    panel = { from = "surface", to = "ink", border = "borderSoft", opacity = "panel" },
    card = { from = "card", to = "surface", border = "borderSoft", opacity = "panel" },
    popup = { from = "popup", to = "ink", border = "border", opacity = "shell" },
    input = { from = "input", to = "ink", border = "borderSoft", opacity = "panel" },
    button = { from = "buttonFill", to = "buttonFillAlt", border = "buttonBorder", opacity = "control" },
    buttonPrimary = { from = "active", to = "blue", border = "accentBright", opacity = "control" },
    buttonDanger = { from = "buttonFill", to = "buttonFillAlt", border = "danger", opacity = "control" },
    buttonSuccess = { from = "buttonFill", to = "buttonFillAlt", border = "success", opacity = "control" },
    navigation = { from = "ink", to = "background", border = "borderSoft", opacity = "control" },
    navigationActive = { from = "active", to = "blue", border = "accentBright", opacity = "control" },
    status = { from = "surface", to = "ink", border = "borderSoft", opacity = "panel" },
    microBar = { from = "microBarFill", to = "microBarFillAlt", border = "microBarBorder", opacity = "control" },
    microBarForever = { from = "microBarFill", to = "microBarFillAlt", border = "microBarBorder", opacity = "control" },
    microBarModern = { from = "microBarFill", to = "microBarFillAlt", border = "microBarBorder", opacity = "control" },
    microBarDark = { from = "microBarFill", to = "microBarFillAlt", border = "microBarBorder", opacity = "control" },
    microButton = { from = "microButtonFill", to = "microButtonFillAlt", border = "microButtonBorder", opacity = "control" },
}

-- The value helpers and the dark palette the authored looks build on
-- (DefaultsLooks.lua, which loads right after this file).
NS.DefaultsShared = { Color = Color, Hex = Hex, WithAlpha = WithAlpha, darkColors = darkColors }
