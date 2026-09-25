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

NS.CopyValue = CopyValue
NS.BaseColors = midnightColors

-- Forever's Camelot bar has fourteen Micro Buttons, every other client 13.
NS.MicroMenuMaxButtonsPerLine = NS.Client and NS.Client.isForever and 14 or 13

NS.Defaults = {
    revision = 50,
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

-- New palettes are authored as complete five-ramp systems instead of accent
-- swaps.  The compact source form keeps each design reviewable: four neutral
-- layers, four text levels, three action colors, three interaction states and
-- two structural lines.  Shared semantic colors stay stable across looks so
-- success, warning and danger never change meaning.
local function CuratedPalette(spec)
    local neutral, text, action, state, line =
        spec.neutral, spec.text, spec.action, spec.state, spec.line
    local success = Hex("58C78B")
    local warning = Hex("E2B85C")
    local danger = Hex("E45D68")
    return {
        background = WithAlpha(neutral[1], 0.985),
        ink = WithAlpha(neutral[2], 0.980),
        surface = WithAlpha(neutral[3], 0.970),
        raised = WithAlpha(neutral[4], 0.980),
        rim = WithAlpha(line[1], 0.900),
        blue = action[1],
        accent = action[2],
        accentBright = action[3],
        text = text[1],
        title = text[2],
        muted = WithAlpha(text[3], 0.960),
        dim = WithAlpha(text[4], 0.920),
        disabled = WithAlpha(text[4], 0.820),
        border = WithAlpha(line[1], 0.900),
        borderSoft = WithAlpha(line[2], 0.760),
        card = WithAlpha(neutral[4], 0.970),
        popup = WithAlpha(neutral[1], 0.995),
        input = WithAlpha(neutral[1], 0.990),
        buttonFill = WithAlpha(neutral[4], 0.980),
        buttonFillAlt = WithAlpha(neutral[3], 0.970),
        buttonBorder = WithAlpha(line[1], 0.900),
        iconBorder = WithAlpha(line[1], 0.920),
        hover = WithAlpha(state[1], 0.950),
        pressed = state[2],
        active = WithAlpha(state[3], 0.960),
        success = success,
        warning = warning,
        blizzardYellow = warning,
        blizzardArrow = action[3],
        blizzardExpand = action[3],
        blizzardExpandPressed = action[2],
        blizzardExpandHover = action[3],
        checkmark = action[3],
        blizzardClose = action[3],
        blizzardClosePressed = action[2],
        blizzardCloseHover = text[2],
        blizzardCloseDisabled = WithAlpha(text[4], 0.820),
        danger = danger,
        accentAlt = spec.alt,
    }
end

NS.PresetOverrides = {
    custom = {},
    -- Dynamic values are compiled from Blizzard's current player-class color
    -- by Theme.BuildClassPalette.  Keeping the key here makes the persisted
    -- palette identity valid without storing a second source of class data.
    classColor = {},
    dark = darkColors,
    midnight = {},
    violet = {
        blue = Color(0.376, 0.235, 0.741, 1),
        accent = Color(0.545, 0.361, 0.965, 1),
        accentBright = Color(0.671, 0.510, 1.000, 1),
        active = Color(0.376, 0.235, 0.741, 0.96),
        hover = Color(0.157, 0.094, 0.310, 0.96),
        pressed = Color(0.286, 0.173, 0.561, 1),
    },
    emerald = {
        blue = Color(0.078, 0.518, 0.361, 1),
        accent = Color(0.157, 0.827, 0.573, 1),
        accentBright = Color(0.353, 0.925, 0.710, 1),
        active = Color(0.078, 0.518, 0.361, 0.96),
        hover = Color(0.039, 0.216, 0.157, 0.96),
        pressed = Color(0.063, 0.388, 0.271, 1),
    },
    ember = {
        blue = Color(0.706, 0.255, 0.118, 1),
        accent = Color(0.965, 0.420, 0.173, 1),
        accentBright = Color(1.000, 0.604, 0.322, 1),
        active = Color(0.706, 0.255, 0.118, 0.96),
        hover = Color(0.286, 0.098, 0.047, 0.96),
        pressed = Color(0.510, 0.180, 0.078, 1),
    },
    monochrome = {
        blue = Color(0.420, 0.470, 0.550, 1),
        accent = Color(0.690, 0.735, 0.810, 1),
        accentBright = Color(0.855, 0.882, 0.930, 1),
        active = Color(0.300, 0.340, 0.410, 0.96),
        hover = Color(0.130, 0.155, 0.200, 0.96),
        pressed = Color(0.230, 0.270, 0.330, 1),
    },
    studio = {
        background = Color(0.018, 0.020, 0.026, 0.985),
        ink = Color(0.027, 0.031, 0.039, 0.980),
        surface = Color(0.043, 0.047, 0.057, 0.970),
        raised = Color(0.067, 0.073, 0.086, 0.980),
        rim = Color(0.180, 0.196, 0.224, 0.820),
        card = Color(0.052, 0.057, 0.068, 0.970),
        popup = Color(0.016, 0.018, 0.023, 0.995),
        input = Color(0.010, 0.012, 0.016, 0.990),
        buttonFill = Color(0.067, 0.073, 0.086, 0.980),
        buttonFillAlt = Color(0.043, 0.047, 0.057, 0.970),
        buttonBorder = Color(0.200, 0.216, 0.247, 0.860),
        border = Color(0.200, 0.216, 0.247, 0.860),
        borderSoft = Color(0.135, 0.149, 0.176, 0.760),
        hover = Color(0.135, 0.216, 0.337, 0.950),
        pressed = Color(0.125, 0.302, 0.604, 1.000),
    },
    frost = {
        background = Color(0.025, 0.047, 0.067, 0.840),
        ink = Color(0.035, 0.071, 0.094, 0.800),
        surface = Color(0.067, 0.122, 0.153, 0.740),
        raised = Color(0.102, 0.169, 0.204, 0.800),
        buttonFill = Color(0.102, 0.169, 0.204, 0.800),
        buttonFillAlt = Color(0.067, 0.122, 0.153, 0.740),
        buttonBorder = Color(0.337, 0.612, 0.737, 0.720),
        rim = Color(0.337, 0.612, 0.737, 0.720),
        blue = Color(0.098, 0.553, 0.737, 1.000),
        accent = Color(0.243, 0.769, 0.910, 1.000),
        accentBright = Color(0.565, 0.886, 1.000, 1.000),
        active = Color(0.098, 0.553, 0.737, 0.940),
        hover = Color(0.063, 0.251, 0.337, 0.900),
        pressed = Color(0.078, 0.400, 0.553, 1.000),
    },
    grid = {
        background = Color(0.060, 0.060, 0.060, 0.980),
        ink = Color(0.080, 0.080, 0.080, 0.980),
        surface = Color(0.100, 0.100, 0.100, 1.000),
        raised = Color(0.130, 0.130, 0.130, 1.000),
        rim = Color(0.000, 0.000, 0.000, 1.000),
        blue = Color(0.050, 0.320, 0.540, 1.000),
        accent = Color(0.090, 0.520, 0.820, 1.000),
        accentBright = Color(0.250, 0.680, 0.960, 1.000),
        text = Color(0.900, 0.900, 0.900, 1.000),
        title = Color(1.000, 1.000, 1.000, 1.000),
        muted = Color(0.700, 0.700, 0.700, 0.960),
        dim = Color(0.500, 0.500, 0.500, 0.920),
        disabled = Color(0.350, 0.350, 0.350, 0.820),
        border = Color(0.000, 0.000, 0.000, 1.000),
        borderSoft = Color(0.000, 0.000, 0.000, 0.880),
        card = Color(0.100, 0.100, 0.100, 1.000),
        popup = Color(0.060, 0.060, 0.060, 1.000),
        input = Color(0.050, 0.050, 0.050, 1.000),
        buttonFill = Color(0.130, 0.130, 0.130, 1.000),
        buttonFillAlt = Color(0.100, 0.100, 0.100, 1.000),
        buttonBorder = Color(0.000, 0.000, 0.000, 1.000),
        hover = Color(0.180, 0.180, 0.180, 0.950),
        pressed = Color(0.070, 0.300, 0.490, 1.000),
        active = Color(0.090, 0.520, 0.820, 0.920),
        success = Color(0.220, 0.760, 0.360, 1.000),
        warning = Color(0.950, 0.680, 0.200, 1.000),
        blizzardYellow = Color(0.950, 0.780, 0.120, 1.000),
        blizzardArrow = Color(0.900, 0.900, 0.900, 1.000),
        blizzardExpand = Color(0.900, 0.900, 0.900, 1.000),
        blizzardExpandPressed = Color(0.090, 0.520, 0.820, 1.000),
        blizzardExpandHover = Color(0.250, 0.680, 0.960, 1.000),
        checkmark = Color(0.090, 0.520, 0.820, 1.000),
        danger = Color(0.850, 0.180, 0.180, 1.000),
        accentAlt = Color(0.700, 0.700, 0.700, 1.000),
    },
    cleanStudio = {
        background = Color(0.080, 0.080, 0.080, 0.920),
        ink = Color(0.040, 0.040, 0.040, 0.850),
        surface = Color(0.060, 0.060, 0.060, 0.940),
        raised = Color(0.100, 0.100, 0.100, 0.960),
        rim = Color(0.200, 0.200, 0.200, 1.000),
        blue = Color(0.035, 0.450, 0.340, 1.000),
        accent = Color(0.047, 0.824, 0.616, 1.000),
        accentBright = Color(0.270, 0.950, 0.760, 1.000),
        text = Color(0.920, 0.920, 0.920, 1.000),
        title = Color(1.000, 1.000, 1.000, 1.000),
        muted = Color(0.650, 0.650, 0.650, 0.960),
        dim = Color(0.450, 0.450, 0.450, 0.920),
        disabled = Color(0.330, 0.330, 0.330, 0.820),
        border = Color(0.200, 0.200, 0.200, 1.000),
        borderSoft = Color(0.150, 0.150, 0.150, 0.820),
        card = Color(0.040, 0.040, 0.040, 0.900),
        popup = Color(0.030, 0.030, 0.030, 0.980),
        input = Color(0.025, 0.025, 0.025, 0.960),
        buttonFill = Color(0.100, 0.100, 0.100, 0.960),
        buttonFillAlt = Color(0.060, 0.060, 0.060, 0.940),
        buttonBorder = Color(0.200, 0.200, 0.200, 1.000),
        hover = Color(0.100, 0.250, 0.200, 0.900),
        pressed = Color(0.030, 0.550, 0.410, 1.000),
        active = Color(0.047, 0.824, 0.616, 0.780),
        success = Color(0.047, 0.824, 0.616, 1.000),
        warning = Color(0.900, 0.700, 0.200, 1.000),
        blizzardYellow = Color(0.920, 0.920, 0.920, 1.000),
        blizzardArrow = Color(0.047, 0.824, 0.616, 1.000),
        blizzardExpand = Color(0.800, 0.800, 0.800, 1.000),
        blizzardExpandPressed = Color(0.047, 0.824, 0.616, 1.000),
        blizzardExpandHover = Color(0.270, 0.950, 0.760, 1.000),
        checkmark = Color(0.047, 0.824, 0.616, 1.000),
        danger = Color(0.900, 0.250, 0.250, 1.000),
        accentAlt = Color(0.700, 0.700, 0.700, 1.000),
    },
    glass = {
        background = Color(0.018, 0.020, 0.026, 0.820),
        ink = Color(0.027, 0.031, 0.039, 0.760),
        surface = Color(0.043, 0.047, 0.057, 0.780),
        raised = Color(0.067, 0.073, 0.086, 0.760),
        rim = Color(0.667, 0.706, 0.761, 0.320),
        blue = Color(0.180, 0.337, 0.541, 0.620),
        accent = Color(0.439, 0.647, 0.957, 1.000),
        accentBright = Color(0.678, 0.816, 1.000, 0.800),
        text = Color(0.933, 0.957, 1.000, 1.000),
        title = Color(0.957, 0.973, 1.000, 1.000),
        muted = Color(0.773, 0.804, 0.847, 0.960),
        dim = Color(0.580, 0.630, 0.700, 0.920),
        disabled = Color(0.460, 0.510, 0.590, 0.820),
        border = Color(0.557, 0.604, 0.667, 0.380),
        borderSoft = Color(0.412, 0.463, 0.529, 0.260),
        card = Color(0.052, 0.057, 0.068, 0.660),
        popup = Color(0.016, 0.018, 0.023, 0.940),
        input = Color(0.010, 0.012, 0.016, 0.860),
        buttonFill = Color(0.067, 0.073, 0.086, 0.760),
        buttonFillAlt = Color(0.043, 0.047, 0.057, 0.700),
        buttonBorder = Color(0.627, 0.671, 0.729, 0.360),
        iconBorder = Color(0.682, 0.722, 0.773, 0.540),
        hover = Color(0.439, 0.647, 0.957, 0.340),
        pressed = Color(0.180, 0.337, 0.541, 0.560),
        active = Color(0.250, 0.420, 0.640, 0.420),
        success = Color(0.345, 0.780, 0.545, 1.000),
        warning = Color(0.886, 0.722, 0.361, 1.000),
        blizzardYellow = Color(0.933, 0.957, 1.000, 1.000),
        blizzardArrow = Color(0.773, 0.804, 0.847, 1.000),
        blizzardExpand = Color(0.773, 0.804, 0.847, 1.000),
        blizzardExpandPressed = Color(0.439, 0.647, 0.957, 1.000),
        blizzardExpandHover = Color(0.678, 0.816, 1.000, 1.000),
        checkmark = Color(0.439, 0.647, 0.957, 1.000),
        blizzardClose = Color(0.678, 0.816, 1.000, 1.000),
        blizzardClosePressed = Color(0.439, 0.647, 0.957, 1.000),
        blizzardCloseHover = Color(0.957, 0.973, 1.000, 1.000),
        blizzardCloseDisabled = Color(0.460, 0.510, 0.590, 0.820),
        danger = Color(0.894, 0.365, 0.408, 1.000),
        accentAlt = Color(0.659, 0.706, 0.780, 1.000),
    },
    rose = {
        blue = Color(0.635, 0.180, 0.388, 1.000),
        accent = Color(0.925, 0.306, 0.557, 1.000),
        accentBright = Color(1.000, 0.565, 0.741, 1.000),
        active = Color(0.635, 0.180, 0.388, 0.960),
        hover = Color(0.286, 0.071, 0.169, 0.960),
        pressed = Color(0.502, 0.125, 0.298, 1.000),
    },
    bronze = {
        blue = Color(0.596, 0.357, 0.137, 1.000),
        accent = Color(0.871, 0.596, 0.251, 1.000),
        accentBright = Color(1.000, 0.776, 0.420, 1.000),
        active = Color(0.596, 0.357, 0.137, 0.960),
        hover = Color(0.255, 0.149, 0.063, 0.960),
        pressed = Color(0.459, 0.267, 0.102, 1.000),
    },
    carbon = CuratedPalette({
        neutral = { Hex("0B0D10"), Hex("111419"), Hex("171B21"), Hex("202630") },
        text = { Hex("E8ECF2"), Hex("F8FAFC"), Hex("9AA4B2"), Hex("697383") },
        action = { Hex("233F69"), Hex("72A7FF"), Hex("A7C8FF") },
        state = { Hex("1E3049"), Hex("284C80"), Hex("2A4D80") },
        line = { Hex("303947"), Hex("242B35") },
        alt = Hex("AAB4C2"),
    }),
    blueprint = CuratedPalette({
        neutral = { Hex("0B1624"), Hex("101E30"), Hex("172940"), Hex("203650") },
        text = { Hex("EEF5FC"), Hex("F8FBFF"), Hex("9EAFBF"), Hex("66798D") },
        action = { Hex("21486F"), Hex("6AA6E8"), Hex("9CC9F2") },
        state = { Hex("1D3B59"), Hex("28577F"), Hex("2A5A8C") },
        line = { Hex("365474"), Hex("29415C") },
        alt = Hex("7BD0C5"),
    }),
    patina = CuratedPalette({
        neutral = { Hex("071312"), Hex("0B1D1C"), Hex("102826"), Hex("183632") },
        text = { Hex("E9F2EF"), Hex("F5FAF8"), Hex("96AAA4"), Hex("637C75") },
        action = { Hex("1C4B46"), Hex("4FC7B2"), Hex("85E0D0") },
        state = { Hex("123A36"), Hex("1D5D54"), Hex("23655C") },
        line = { Hex("2D514B"), Hex("213D39") },
        alt = Hex("D49A62"),
    }),
    moss = CuratedPalette({
        neutral = { Hex("0F1412"), Hex("151B18"), Hex("1C2520"), Hex("273129") },
        text = { Hex("EDF1EC"), Hex("F8FAF7"), Hex("A5ADA6"), Hex("6F7971") },
        action = { Hex("344A38"), Hex("A8C7A5"), Hex("D0E1CC") },
        state = { Hex("29382B"), Hex("3B523F"), Hex("445C48") },
        line = { Hex("3E4B42"), Hex("303B34") },
        alt = Hex("C9AF7A"),
    }),
    dune = CuratedPalette({
        neutral = { Hex("15110D"), Hex("1C1712"), Hex("251E17"), Hex("30271E") },
        text = { Hex("F2ECE2"), Hex("FBF7F0"), Hex("B4A792"), Hex("7C6F5F") },
        action = { Hex("563626"), Hex("C9875B"), Hex("E7B58C") },
        state = { Hex("38271F"), Hex("5F3D2B"), Hex("714A35") },
        line = { Hex("4B3D2E"), Hex("3B3025") },
        alt = Hex("8CB5A1"),
    }),
    workshop = CuratedPalette({
        neutral = { Hex("101418"), Hex("151A1F"), Hex("1E242A"), Hex("282F36") },
        text = { Hex("F0F3F5"), Hex("FFFFFF"), Hex("A8B0B8"), Hex("717B85") },
        action = { Hex("284B5B"), Hex("6DB6D9"), Hex("A9DCF0") },
        state = { Hex("203B47"), Hex("315E72"), Hex("396E85") },
        line = { Hex("46515B"), Hex("353E47") },
        alt = Hex("F0C45C"),
    }),
    signal = CuratedPalette({
        neutral = { Hex("090A0C"), Hex("0D0F12"), Hex("15181D"), Hex("1D2229") },
        text = { Hex("F2F4F7"), Hex("FFFFFF"), Hex("A4ADB8"), Hex("6A7582") },
        action = { Hex("64220B"), Hex("FF6A2A"), Hex("FF9A6A") },
        state = { Hex("3C1B0F"), Hex("7A2D0E"), Hex("8F3515") },
        line = { Hex("343B44"), Hex("272D35") },
        alt = Hex("73B6FF"),
    }),
    merlot = CuratedPalette({
        neutral = { Hex("130B0E"), Hex("1B0E13"), Hex("26131A"), Hex("321B24") },
        text = { Hex("F5E9ED"), Hex("FFF7FA"), Hex("BEA1AB"), Hex("826773") },
        action = { Hex("592237"), Hex("E67B9B"), Hex("F5ABC0") },
        state = { Hex("461C2A"), Hex("6B2941"), Hex("7E324C") },
        line = { Hex("55303D"), Hex("40242E") },
        alt = Hex("DDBB78"),
    }),
    lilac = CuratedPalette({
        neutral = { Hex("111016"), Hex("17151F"), Hex("201D2A"), Hex("2A2636") },
        text = { Hex("EFECF5"), Hex("FAF8FD"), Hex("A8A1B5"), Hex("736C81") },
        action = { Hex("423362"), Hex("A98CEB"), Hex("CBB9F5") },
        state = { Hex("30264A"), Hex("4D3A75"), Hex("5B4787") },
        line = { Hex("443E55"), Hex("342F41") },
        alt = Hex("8EB8A6"),
    }),
    gallery = CuratedPalette({
        neutral = { Hex("130F16"), Hex("1A141E"), Hex("241C29"), Hex("302638") },
        text = { Hex("F1EDF2"), Hex("FCF9FC"), Hex("B0A5B3"), Hex("786D7C") },
        action = { Hex("2C5140"), Hex("85D7B1"), Hex("B7EBD0") },
        state = { Hex("253C32"), Hex("365A49"), Hex("3F6E59") },
        line = { Hex("51405C"), Hex("3D3046") },
        alt = Hex("D9A86C"),
    }),
    deepSea = CuratedPalette({
        neutral = { Hex("07101A"), Hex("0A1826"), Hex("102337"), Hex("172F46") },
        text = { Hex("E8F2FA"), Hex("F5FAFF"), Hex("94AABD"), Hex("60788F") },
        action = { Hex("173F66"), Hex("369BD6"), Hex("7CC7F2") },
        state = { Hex("122E4C"), Hex("1B4E7A"), Hex("225C8F") },
        line = { Hex("294966"), Hex("1D374E") },
        alt = Hex("E58B6F"),
    }),
    titanium = CuratedPalette({
        neutral = { Hex("17191D"), Hex("202329"), Hex("292D34"), Hex("343941") },
        text = { Hex("F0F2F5"), Hex("FFFFFF"), Hex("B1B7C0"), Hex("7A828D") },
        action = { Hex("414853"), Hex("D6D9DE"), Hex("FFFFFF") },
        state = { Hex("3C414A"), Hex("4A515C"), Hex("535B67") },
        line = { Hex("59616D"), Hex("444B55") },
        alt = Hex("9FB3CE"),
    }),
    citron = CuratedPalette({
        neutral = { Hex("0D100C"), Hex("121610"), Hex("191F17"), Hex("222A1E") },
        text = { Hex("EFF3EC"), Hex("F9FBF7"), Hex("A6B09F"), Hex("707A69") },
        action = { Hex("3D4D1B"), Hex("B8D85A"), Hex("D7ED8E") },
        state = { Hex("283116"), Hex("46591F"), Hex("566C28") },
        line = { Hex("374431"), Hex("2A3426") },
        alt = Hex("8AB8C7"),
    }),
    inkSand = CuratedPalette({
        neutral = { Hex("0A0D16"), Hex("0F1420"), Hex("171D2A"), Hex("212839") },
        text = { Hex("EEF0F6"), Hex("FAFBFF"), Hex("A2A9B8"), Hex("687286") },
        action = { Hex("4E392B"), Hex("E2A77D"), Hex("F4C7A8") },
        state = { Hex("33271F"), Hex("5F4432"), Hex("72543E") },
        line = { Hex("36415A"), Hex("283247") },
        alt = Hex("86A8E7"),
    }),
}

-- Keep Glass's translucency while matching the Forever menu's authored
-- graphite, ivory and muted-gold color roles. The ordinary Glass look stays
-- class-colored for profiles that already use it.
local foreverGlass = {}
for key, value in pairs(NS.PresetOverrides.glass) do
    foreverGlass[key] = { value[1], value[2], value[3], value[4] }
end
local foreverGlassTints = {
    background = "14181B", ink = "111517", surface = "20272A", raised = "292F31",
    card = "292F31", popup = "191D20", input = "111517",
    buttonFill = "292F31", buttonFillAlt = "20272A",
    rim = "9F8960", border = "9F8960", borderSoft = "68716F",
    buttonBorder = "727774", iconBorder = "9F8960",
    blue = "363C3C", active = "363C3C", hover = "454A47", pressed = "363C3C",
    accent = "D8B66A", accentBright = "F1E3C4", accentAlt = "C3B48E",
    text = "F4F3EB", title = "F1E3C4", muted = "D4DCE2",
    dim = "D4DCE2", disabled = "8F9999",
    blizzardYellow = "F4F3EB", blizzardArrow = "D4DCE2",
    blizzardExpand = "D4DCE2", blizzardExpandPressed = "D8B66A",
    blizzardExpandHover = "F1E3C4", checkmark = "D8B66A",
    blizzardClose = "F1E3C4", blizzardClosePressed = "D8B66A",
    blizzardCloseHover = "F4F3EB", blizzardCloseDisabled = "8F9999",
    microBarFill = "0E1C28", microBarFillAlt = "122431", microBarBorder = "9F8960",
    microButtonFill = "292F31", microButtonFillAlt = "20272A", microButtonBorder = "727774",
    microIcon = "D8B66A", microIconHover = "F1E3C4",
    microIconPressed = "D8B66A", microIconDisabled = "8F9999",
}
for key, hex in pairs(foreverGlassTints) do
    local color = foreverGlass[key] or foreverGlass[NS.MicroColorSources[key]]
    foreverGlass[key] = Hex(hex, color[4])
end
NS.PresetOverrides.foreverGlass = foreverGlass

-- A neutral glass variant: the material depth of Forever without its gold
-- trim or the blue cast of the original Midnight palette.
local midnightDark = {}
for key, value in pairs(foreverGlass) do
    midnightDark[key] = { value[1], value[2], value[3], value[4] }
end
local midnightDarkTints = {
    background = "151719", ink = "111315", surface = "202326", raised = "292D31",
    card = "292D31", popup = "1A1C1F", input = "111315",
    buttonFill = "292D31", buttonFillAlt = "202326",
    rim = "62635E", border = "575B58", borderSoft = "414541",
    buttonBorder = "555A56", iconBorder = "77766E",
    blue = "303537", active = "353A37", hover = "A8AD9F", pressed = "303532",
    accent = "B9AB86", accentBright = "D8CEB5", accentAlt = "A9A089",
    text = "E9E9E4", title = "F3F0E7", muted = "B9BDB9",
    dim = "A3A8A3", disabled = "878D88",
    blizzardYellow = "E9E9E4", blizzardArrow = "B9BDB9",
    blizzardExpand = "B9BDB9", blizzardExpandPressed = "B9AB86",
    blizzardExpandHover = "D8CEB5", checkmark = "B9AB86",
    blizzardClose = "E9E9E4", blizzardClosePressed = "B9AB86",
    blizzardCloseHover = "F3F0E7", blizzardCloseDisabled = "878D88",
    microBarFill = "151719", microBarFillAlt = "111315", microBarBorder = "62635E",
    microButtonFill = "292D31", microButtonFillAlt = "202326", microButtonBorder = "555A56",
    microIcon = "E9E9E4", microIconHover = "D8CEB5",
    microIconPressed = "B9AB86", microIconDisabled = "878D88",
}
for key, hex in pairs(midnightDarkTints) do
    midnightDark[key] = Hex(hex, midnightDark[key][4])
end
NS.PresetOverrides.midnightDark = midnightDark

NS.PaletteOrder = {
    "dark", "midnight", "midnightDark", "classColor", "grid", "cleanStudio", "glass", "foreverGlass", "studio",
    "monochrome", "frost", "violet", "emerald", "ember", "rose", "bronze",
    "carbon", "blueprint", "patina", "moss", "dune", "workshop", "signal",
    "merlot", "lilac", "gallery", "deepSea", "titanium", "citron", "inkSand",
}

NS.PaletteLabels = {
    dark = "Dark", midnight = "Midnight Blue", midnightDark = "Midnight Dark", classColor = "Class Color",
    grid = "Classic Grid", cleanStudio = "Clean Studio", glass = "Glass",
    foreverGlass = "MSUF Forever Glass",
    studio = "Studio", monochrome = "Monochrome", frost = "Frost",
    violet = "Violet", emerald = "Emerald", ember = "Ember", rose = "Rose",
    bronze = "Bronze", carbon = "Carbon", blueprint = "Blueprint",
    patina = "Patina", moss = "Moss", dune = "Dune", workshop = "Workshop",
    signal = "Signal", merlot = "Merlot", lilac = "Lilac", gallery = "Gallery",
    deepSea = "Deep Sea", titanium = "Titanium", citron = "Citron",
    inkSand = "Ink & Sand",
}

-- Keep older authored looks loadable for saved profiles and imports. The
-- visible catalog has the same three choices on every supported client.
NS.LookOrder = { "midnight", "midnightDark", "foreverGlass" }
NS.LookPresets = {
    custom = {
        label = "Custom",
        description = "Your current hand-tuned combination of palette, material and geometry.",
    },
    dark = {
        label = "Dark",
        description = "Dense near-black studio layers with restrained neutral controls.",
        palette = "dark",
        appearance = { gradient = false, gradientStrength = 1, materialDepth = 0.14, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 1, hoverStyle = "outline", hoverIntensity = 1 },
        geometry = { family = "continuous", radius = 8, border = 1, controlShape = "round" },
    },
    midnight = {
        label = "Midnight Blue",
        description = "Deep navy materials, clear blue focus and softly rounded controls.",
        palette = "midnight",
        appearance = { gradient = true, gradientStrength = 1, materialDepth = 0.20, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 1, hoverStyle = "outline", hoverIntensity = 1 },
        geometry = { family = "continuous", radius = 8, border = 1, controlShape = "pill" },
    },
    midnightDark = {
        label = "Midnight Dark",
        description = "Neutral charcoal glass with soft ivory text and restrained warm focus.",
        palette = "midnightDark",
        appearance = { gradient = true, gradientStrength = 0.50, materialDepth = 0.14, gradientDirection = "VERTICAL", shellOpacity = 0.92, panelOpacity = 0.92, controlOpacity = 0.96, borderOpacity = 0.72, hoverStyle = "outline", hoverIntensity = 1, iconBorderStyle = "quality", iconBorderThickness = 1, iconBorderPadding = 1, iconBorderOpacity = 0.78 },
        geometry = { family = "continuous", radius = 12, border = 1, controlShape = "continuous" },
    },
    classColor = {
        label = "Class Color",
        description = "Midnight structure with one live Blizzard class color owning every focus state.",
        palette = "classColor",
        dynamicPalette = "playerClass",
        appearance = { gradient = true, gradientStrength = 0.78, materialDepth = 0.18, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 0.96, controlOpacity = 1, borderOpacity = 1, hoverStyle = "outline", hoverIntensity = 1 },
        geometry = { family = "continuous", radius = 8, border = 1, controlShape = "pill" },
    },
    gridClassic = {
        label = "Classic Grid",
        description = "Compact flat panels, hard one-pixel structure and familiar blue selection.",
        palette = "grid",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0.06, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 1, hoverStyle = "softFill", hoverIntensity = 0.72 },
        geometry = { family = "round", radius = 4, border = 1, controlShape = "round" },
    },
    cleanStudio = {
        label = "Clean Studio",
        description = "Neutral matte panels with a single emerald accent and minimal depth.",
        palette = "cleanStudio",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0.04, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 1, hoverStyle = "outline", hoverIntensity = 1 },
        geometry = { family = "round", radius = 4, border = 1, controlShape = "round" },
    },
    glass = {
        label = "Glass",
        description = "Smoked near-black glass with crisp hairlines and restrained class-color focus.",
        palette = "glass",
        dynamicPalette = "playerClassGlass",
        appearance = { gradient = true, gradientStrength = 0.50, materialDepth = 0.14, gradientDirection = "VERTICAL", shellOpacity = 0.92, panelOpacity = 0.92, controlOpacity = 0.96, borderOpacity = 0.72, hoverStyle = "softFill", hoverIntensity = 0.68, iconBorderStyle = "quality", iconBorderThickness = 1, iconBorderPadding = 1, iconBorderOpacity = 0.78 },
        geometry = { family = "continuous", radius = 12, border = 1, controlShape = "continuous" },
    },
    foreverGlass = {
        label = "MSUF Forever Glass",
        description = "The Glass material with MSUF Forever graphite, ivory and muted-gold colors.",
        palette = "foreverGlass",
        appearance = { gradient = true, gradientStrength = 0.50, materialDepth = 0.14, gradientDirection = "VERTICAL", shellOpacity = 0.92, panelOpacity = 0.92, controlOpacity = 0.96, borderOpacity = 0.72, hoverStyle = "softFill", hoverIntensity = 0.68, iconBorderStyle = "quality", iconBorderThickness = 1, iconBorderPadding = 1, iconBorderOpacity = 0.78 },
        geometry = { family = "continuous", radius = 12, border = 1, controlShape = "continuous" },
    },
    studioFlat = {
        label = "Studio Flat",
        description = "Quiet graphite surfaces, compact corners and no decorative shading.",
        palette = "studio",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 0.85, hoverStyle = "softFill", hoverIntensity = 0.55 },
        geometry = { family = "round", radius = 4, border = 1, controlShape = "continuous" },
    },
    obsidian = {
        label = "Obsidian",
        description = "Monochrome depth with softened outlines and cool silver interaction states.",
        palette = "monochrome",
        appearance = { gradient = true, gradientStrength = 0.25, materialDepth = 0.22, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 0.98, controlOpacity = 1, borderOpacity = 0.7, hoverStyle = "outline", hoverIntensity = 0.75 },
        geometry = { family = "continuous", radius = 6, border = 1, controlShape = "continuous" },
    },
    nightGlass = {
        label = "Night Glass",
        description = "Cool transparent blue layers with generous curves and low-key highlights.",
        palette = "frost",
        appearance = { gradient = true, gradientStrength = 0.72, materialDepth = 0.30, gradientDirection = "VERTICAL", shellOpacity = 0.82, panelOpacity = 0.74, controlOpacity = 0.94, borderOpacity = 0.8, hoverStyle = "softFill", hoverIntensity = 0.45 },
        geometry = { family = "squircle", radius = 12, border = 1, controlShape = "pill" },
    },
    arcane = {
        label = "Arcane",
        description = "Horizontal violet energy, stronger framing and sculpted squircle controls.",
        palette = "violet",
        appearance = { gradient = true, gradientStrength = 0.8, materialDepth = 0.20, gradientDirection = "HORIZONTAL", shellOpacity = 1, panelOpacity = 0.94, controlOpacity = 1, borderOpacity = 1, hoverStyle = "outline", hoverIntensity = 1 },
        geometry = { family = "squircle", radius = 8, border = 2, controlShape = "squircle" },
    },
    emberGlow = {
        label = "Ember Glow",
        description = "Warm ember focus over dark materials with soft selected-state fills.",
        palette = "ember",
        appearance = { gradient = true, gradientStrength = 0.9, materialDepth = 0.18, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 0.96, controlOpacity = 1, borderOpacity = 0.9, hoverStyle = "softFill", hoverIntensity = 0.55 },
        geometry = { family = "continuous", radius = 8, border = 1, controlShape = "pill" },
    },
    carbon = {
        label = "Carbon",
        description = "Matte black with cool blue focus and compact corners.",
        palette = "carbon",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 0.80, hoverStyle = "outline", hoverIntensity = 0.80 },
        geometry = { family = "continuous", radius = 6, border = 1, controlShape = "round" },
    },
    blueprint = {
        label = "Blueprint",
        description = "Navy panels, slim blue lines and compact controls.",
        palette = "blueprint",
        appearance = { gradient = true, gradientStrength = 0.25, materialDepth = 0.08, gradientDirection = "HORIZONTAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 0.90, hoverStyle = "outline", hoverIntensity = 0.76 },
        geometry = { family = "round", radius = 4, border = 1, controlShape = "continuous" },
    },
    patina = {
        label = "Patina",
        description = "Dark teal with a small copper secondary accent.",
        palette = "patina",
        appearance = { gradient = true, gradientStrength = 0.45, materialDepth = 0.16, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 0.96, controlOpacity = 1, borderOpacity = 0.88, hoverStyle = "softFill", hoverIntensity = 0.48 },
        geometry = { family = "continuous", radius = 8, border = 1, controlShape = "pill" },
    },
    moss = {
        label = "Moss",
        description = "Warm charcoal with muted green controls.",
        palette = "moss",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0.06, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 0.78, hoverStyle = "softFill", hoverIntensity = 0.40 },
        geometry = { family = "continuous", radius = 8, border = 1, controlShape = "continuous" },
    },
    dune = {
        label = "Dune",
        description = "Warm brown-black panels with sand-copper focus.",
        palette = "dune",
        appearance = { gradient = true, gradientStrength = 0.30, materialDepth = 0.12, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 0.98, controlOpacity = 1, borderOpacity = 0.88, hoverStyle = "softFill", hoverIntensity = 0.44 },
        geometry = { family = "squircle", radius = 8, border = 1, controlShape = "continuous" },
    },
    workshop = {
        label = "Workshop",
        description = "Steel panels, technical blue controls and safety-yellow details.",
        palette = "workshop",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 1, hoverStyle = "outline", hoverIntensity = 0.85 },
        geometry = { family = "round", radius = 4, border = 1, controlShape = "round" },
    },
    signal = {
        label = "Signal",
        description = "Near-black panels with a direct orange focus color.",
        palette = "signal",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0.02, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 1, hoverStyle = "outline", hoverIntensity = 1 },
        geometry = { family = "round", radius = 4, border = 1, controlShape = "round" },
    },
    merlot = {
        label = "Merlot",
        description = "Wine-black panels with dusty rose controls.",
        palette = "merlot",
        appearance = { gradient = true, gradientStrength = 0.28, materialDepth = 0.12, gradientDirection = "HORIZONTAL", shellOpacity = 1, panelOpacity = 0.96, controlOpacity = 1, borderOpacity = 0.86, hoverStyle = "softFill", hoverIntensity = 0.42 },
        geometry = { family = "squircle", radius = 8, border = 1, controlShape = "pill" },
    },
    lilac = {
        label = "Lilac",
        description = "Soft violet-black panels with wide curves.",
        palette = "lilac",
        appearance = { gradient = true, gradientStrength = 0.20, materialDepth = 0.08, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 0.98, controlOpacity = 1, borderOpacity = 0.76, hoverStyle = "outline", hoverIntensity = 0.72 },
        geometry = { family = "squircle", radius = 12, border = 1, controlShape = "continuous" },
    },
    gallery = {
        label = "Gallery",
        description = "Aubergine panels with mint controls and warm details.",
        palette = "gallery",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0.05, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 0.72, hoverStyle = "softFill", hoverIntensity = 0.45 },
        geometry = { family = "continuous", radius = 8, border = 1, controlShape = "continuous" },
    },
    deepSea = {
        label = "Deep Sea",
        description = "Deep navy panels with clean cyan-blue focus.",
        palette = "deepSea",
        appearance = { gradient = true, gradientStrength = 0.38, materialDepth = 0.18, gradientDirection = "VERTICAL", shellOpacity = 0.95, panelOpacity = 0.92, controlOpacity = 0.98, borderOpacity = 0.82, hoverStyle = "softFill", hoverIntensity = 0.48 },
        geometry = { family = "squircle", radius = 12, border = 1, controlShape = "pill" },
    },
    titanium = {
        label = "Titanium",
        description = "Cool gray layers with monochrome controls and thin borders.",
        palette = "titanium",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 0.68, hoverStyle = "outline", hoverIntensity = 0.72 },
        geometry = { family = "round", radius = 4, border = 1, controlShape = "continuous" },
    },
    citron = {
        label = "Citron",
        description = "Black-green panels with a sharp citrus accent.",
        palette = "citron",
        appearance = { gradient = false, gradientStrength = 0, materialDepth = 0.03, gradientDirection = "VERTICAL", shellOpacity = 1, panelOpacity = 1, controlOpacity = 1, borderOpacity = 0.90, hoverStyle = "outline", hoverIntensity = 0.82 },
        geometry = { family = "round", radius = 4, border = 1, controlShape = "round" },
    },
    inkSand = {
        label = "Ink & Sand",
        description = "Blue-black panels with a warm sand accent.",
        palette = "inkSand",
        appearance = { gradient = true, gradientStrength = 0.34, materialDepth = 0.15, gradientDirection = "HORIZONTAL", shellOpacity = 1, panelOpacity = 0.96, controlOpacity = 1, borderOpacity = 0.86, hoverStyle = "softFill", hoverIntensity = 0.46 },
        geometry = { family = "continuous", radius = 8, border = 1, controlShape = "pill" },
    },
}

NS.LookPresets.modern = NS.CopyValue(NS.LookPresets.glass)
NS.LookPresets.modern.label = "Modern"
NS.LookPresets.modern.description =
    "Floating smoked glass, soft corners and a restrained class-color focus."

-- Item-quality information remains the semantic baseline for every complete
-- look.  Applying a named look also resets these four appearance values so its
-- rendered result cannot inherit an unrelated previous icon configuration.
-- A look may still author a deliberate override, as Glass does for its airier
-- icon treatment.
for _, look in pairs(NS.LookPresets) do
    if look.appearance then
        look.appearance.iconBorderStyle = look.appearance.iconBorderStyle or "quality"
        look.appearance.iconBorderThickness = look.appearance.iconBorderThickness or 1
        look.appearance.iconBorderPadding = look.appearance.iconBorderPadding or 0
        look.appearance.iconBorderOpacity = look.appearance.iconBorderOpacity or 1
    end
end

for name, look in pairs(NS.LookPresets) do
    if name ~= "custom" then
        local classic = name == "foreverGlass" or name == "gridClassic"
            or name == "midnight"
        look.microStyle = classic and name ~= "midnight" and "forever"
            or name == "midnightDark" and "midnightDark" or "modern"
    end
end

-- Only newly created skin profiles use the client's default look.
-- Normalization fills missing fields on existing profiles but never replaces
-- their saved palette, look, opacity, or geometry.
do
    local defaultLookName = NS.Client and NS.Client.isForever and "foreverGlass" or "midnightDark"
    local look = NS.LookPresets[defaultLookName]
    local colors = NS.CopyValue(NS.BaseColors)
    for key, value in pairs(NS.PresetOverrides[look.palette]) do
        colors[key] = NS.CopyValue(value)
    end
    for target, source in pairs(NS.MicroColorSources) do
        if not NS.PresetOverrides[look.palette][target] then
            colors[target] = NS.CopyValue(colors[source])
        end
    end
    NS.Defaults.theme.colors = colors
    for key, value in pairs(look.appearance) do NS.Defaults.theme[key] = value end
    for key, value in pairs(look.geometry) do NS.Defaults.geometry[key] = value end
    local micro = NS.Defaults.icons.microMenu
    for _, key in ipairs(NS.MicroMenuLookKeys) do
        micro[key] = NS.MicroMenuPresetValues[look.microStyle][key]
    end
    micro.preset = look.microStyle
    if NS.Client and NS.Client.isForever then
        local position = NS.MicroMenuPositionPresets.bottomCenter
        micro.layoutPoint, micro.layoutRelativePoint = position.point, position.relativePoint
        micro.layoutX, micro.layoutY = position.x, position.y
        micro.positionPreset = "bottomCenter"
    end
    NS.Defaults.theme.preset = look.palette
    NS.Defaults.theme.look = defaultLookName
end
