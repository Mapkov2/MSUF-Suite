local _, NS = ...

local Database = { rootSchema = 1 }
NS.Database = Database

-- Saved colors are compared with factory values that went through a hex or
-- /255 conversion; this tolerance absorbs the float noise.
local EPSILON = 0.000001

local function Clamp(value, minimum, maximum)
    value = tonumber(value)
    if not value then return minimum end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function Round(value)
    return math.floor(value + 0.5)
end

local function IsForever()
    return NS.Client and NS.Client.isForever
end

local function MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function IsListed(list, value)
    for index = 1, #list do
        if list[index] == value then return true end
    end
    return false
end

-- Settings which are true unless explicitly disabled.
local function DefaultTrue(settings, keys)
    for index = 1, #keys do
        local key = keys[index]
        settings[key] = settings[key] ~= false
    end
end

-- Clamps every { key, minimum, maximum, integer } range (see Defaults.lua).
local function ClampRanges(settings, ranges)
    for index = 1, #ranges do
        local range = ranges[index]
        local value = Clamp(settings[range[1]], range[2], range[3])
        if range[4] then value = Round(value) end
        settings[range[1]] = value
    end
end

-- Resets every { key, listName } choice whose value is not in NS[listName].
-- Lists are resolved on use: some are defined by files loaded later.
local function KeepListed(settings, choices, defaults)
    for index = 1, #choices do
        local key, listName = choices[index][1], choices[index][2]
        if not IsListed(NS[listName], settings[key]) then
            settings[key] = defaults[key]
        end
    end
end

-- Numeric choices may have been saved as strings.
local function KeepListedNumber(settings, key, list, fallback)
    local value = tonumber(settings[key])
    if IsListed(list, value) then
        settings[key] = value
    else
        settings[key] = fallback
    end
end

-- True when every field of the signature has exactly that value.
local function Matches(settings, signature)
    for key, value in pairs(signature) do
        if settings[key] ~= value then return false end
    end
    return true
end

local function HexChannel(hex, index)
    return tonumber(hex:sub(index * 2 - 1, index * 2), 16) / 255
end

local function SameRGB(color, r, g, b)
    return math.abs(color[1] - r) < EPSILON
        and math.abs(color[2] - g) < EPSILON
        and math.abs(color[3] - b) < EPSILON
end

-- Moves a color that still has the old factory RGB to the new one.
local function ReplaceFactoryRGB(current, old, desired)
    if current and old and desired and SameRGB(current, old[1], old[2], old[3]) then
        current[1], current[2], current[3] = desired[1], desired[2], desired[3]
    end
end

local CHARACTER_DETAIL_TOGGLES = { "enabled", "expanded", "styleEQoL", "inlineGear", "wideLayout" }
local CHARACTER_STAT_TOGGLES = { "enabled", "diminishingReturns" }
local CHARACTER_VIEWS = { modern = true, list = true, classic = true }

local THEME_CHOICES = {
    { "gradientDirection", "GradientDirections" },
    { "hoverStyle", "HoverStyles" },
    { "iconBorderStyle", "IconBorderStyles" },
}

local GEOMETRY_CHOICES = {
    { "family", "GeometryFamilies" },
    { "controlShape", "ControlShapes" },
}

local WINDOW_ACTION_CHOICES = {
    { "style", "WindowActionStyles" },
    { "glyphMode", "WindowActionGlyphModes" },
    { "weight", "WindowActionWeights" },
    { "surfaceShape", "WindowActionShapes" },
}

local MICRO_MENU_CHOICES = {
    { "shape", "MicroMenuShapes" },
    { "barMaterial", "MicroMenuBarMaterials" },
    { "tint", "MicroMenuTintModes" },
    { "iconStyle", "MicroMenuIconStyles" },
    { "hoverStyle", "MicroMenuHoverStyles" },
    { "layoutMode", "MicroMenuLayoutModes" },
    { "visibility", "MicroMenuVisibilityModes" },
    { "orientation", "MicroMenuOrientations" },
    { "growth", "MicroMenuGrowthModes" },
    { "layoutPoint", "MicroMenuPoints" },
    { "layoutRelativePoint", "MicroMenuPoints" },
}

-- Retired Blizzard tracker decoration has no settings in Suite profiles.
local RETIRED_SKINS = { "objectiveTracker", "objectiveTrackerAccents" }
local RETIRED_HUD = {
    "objectiveTrackerStyle", "objectiveTrackerBackground",
    "objectiveTrackerHeaders", "objectiveTrackerBars",
}

-- Revision 38 briefly used a blue palette. Match its factory values
-- when returning to the Forever look from the user's backup.
local RETIRED_FOREVER_COLORS = {
    background = "09141F", ink = "0B1722", surface = "10202C", raised = "192B37",
    card = "12232E", popup = "0A1620", input = "0B1823",
    buttonFill = "192B37", buttonFillAlt = "10202C",
    rim = "806845", border = "A18456", borderSoft = "3C4A4C",
    buttonBorder = "806845", iconBorder = "A18456",
    blue = "1A303B", active = "213846", hover = "29434C", pressed = "18313B",
    accent = "D5AD71", accentBright = "F2D9A9", accentAlt = "BA9867",
    text = "EDE9E0", title = "F3E5CA", muted = "BDB8AD",
    dim = "969C9D", disabled = "747D80",
    blizzardYellow = "D5AD71", blizzardArrow = "D5AD71",
    blizzardExpand = "D5AD71", blizzardExpandPressed = "F2D9A9",
    blizzardExpandHover = "F2D9A9", checkmark = "D5AD71",
    blizzardClose = "F3E5CA", blizzardClosePressed = "D5AD71",
    blizzardCloseHover = "F2D9A9", blizzardCloseDisabled = "747D80",
}
local RETIRED_FOREVER_ALPHA = {
    background = 0.98, ink = 0.97, surface = 0.96, raised = 0.96,
    card = 0.95, popup = 0.99, input = 0.98,
    buttonFill = 0.94, buttonFillAlt = 0.93,
    rim = 0.82, border = 0.86, borderSoft = 0.55,
    buttonBorder = 0.72, iconBorder = 0.86,
}
local RETIRED_FOREVER_APPEARANCE = {
    gradientStrength = 0.16, materialDepth = 0.06,
    shellOpacity = 0.99, panelOpacity = 0.97,
    controlOpacity = 1, borderOpacity = 0.92,
    hoverStyle = "outline", hoverIntensity = 0.72,
    iconBorderOpacity = 0.82,
}
local RETIRED_FOREVER_GEOMETRY = {
    family = "continuous", radius = 4, border = 1, controlShape = "continuous",
}
-- Micro colors of the revision 41 Forever strip.
local RETIRED_FOREVER_MICRO_COLORS = {
    microBarFill = "14181B", microBarFillAlt = "111517", microIcon = "F4F3EB",
}
-- Revision 40 card color, inherited from generic Glass.
local RETIRED_FOREVER_CARD = { 32 / 255, 39 / 255, 42 / 255 }

-- Replaces a color that still holds the retired factory RGB (and alpha, when
-- one is given) with the current preset value. Edited colors stay untouched.
local function RestoreForeverColor(current, hex, desired, retiredAlpha)
    if type(current) ~= "table" or not hex or not desired then return end
    for index = 1, 3 do
        if type(current[index]) ~= "number"
            or math.abs(current[index] - HexChannel(hex, index)) > EPSILON then
            return
        end
    end
    current[1], current[2], current[3] = desired[1], desired[2], desired[3]
    if retiredAlpha and type(current[4]) == "number"
        and math.abs(current[4] - retiredAlpha) < EPSILON then
        current[4] = desired[4]
    end
end

-- Untouched factory Micro Bar looks of earlier revisions. A migration only
-- rewrites a bar that still matches one of these exact signatures.
local FOREVER_NATIVE_STRIP = {
    preset = "forever", barMaterial = "forever", iconStyle = "blizzard",
    tint = "native", buttonSize = 32, iconSize = 24,
}
local FOREVER_BOXED_STRIP = {
    barMaterial = "forever", iconStyle = "line", tint = "theme",
    buttonBackground = true, buttonBorder = 1, buttonSize = 30,
    iconSize = 20, spacing = 3,
}
local FOREVER_LINE_STRIP = {
    preset = "forever", barMaterial = "forever", iconStyle = "line",
    buttonSize = 30, iconSize = 22, buttonBackground = false,
}
local FOREVER_BOLD_STRIP = {
    preset = "forever", barMaterial = "forever", iconStyle = "bold",
    buttonSize = 30, iconSize = 22, buttonBackground = false, buttonBorder = 0,
}
local MODERN_NATIVE_STRIP = {
    preset = "modern", barMaterial = "modern", iconStyle = "blizzard",
    tint = "native", buttonSize = 32, iconSize = 24, spacing = 6,
    padding = 10, buttonBackground = false, buttonBorder = 0,
}
-- The four pre-revision-33 styles differed only slightly.
local LEGACY_MICRO_PRESETS = {
    framed = "forever", midnight = "modern",
    class = "modern", minimal = "modern",
}

local function IsPlacedAt(microMenu, point, x, y)
    return microMenu.layoutPoint == point and microMenu.layoutRelativePoint == point
        and microMenu.layoutX == x and microMenu.layoutY == y
end

local function PlaceAtPreset(microMenu, presetName)
    local position = NS.MicroMenuPositionPresets[presetName]
    microMenu.layoutPoint, microMenu.layoutRelativePoint = position.point, position.relativePoint
    microMenu.layoutX, microMenu.layoutY = position.x, position.y
    microMenu.positionPreset = presetName
end

local function ApplyMicroLook(microMenu, presetName)
    local preset = NS.MicroMenuPresetValues[presetName]
    for _, key in ipairs(NS.MicroMenuLookKeys) do microMenu[key] = preset[key] end
end

local function IsForeverGlass(db)
    return IsForever() and db.theme.look == "foreverGlass"
end

-- Profile normalization steps, in the order Normalize runs them.

-- Profiles from before the view selector chose the classic character layout
-- by turning one of its parts off.
local function IsClassicDetailsOptOut(details)
    return type(details) == "table" and details.view == nil
        and (details.enabled == false or details.inlineGear == false
            or details.wideLayout == false)
end

local function NormalizeCharacter(db, classicOptOut)
    local details = db.characterDetails
    DefaultTrue(details, CHARACTER_DETAIL_TOGGLES)
    if classicOptOut then details.view = "classic" end
    if not CHARACTER_VIEWS[details.view] then details.view = "modern" end
    DefaultTrue(db.characterStats, CHARACTER_STAT_TOGGLES)
end

local function NormalizeTheme(theme, revision)
    local defaults = NS.Defaults.theme
    theme.gradient = theme.gradient ~= false
    ClampRanges(theme, NS.AppearanceRanges)
    KeepListed(theme, THEME_CHOICES, defaults)
    if type(theme.look) ~= "string" or not NS.LookPresets[theme.look] then
        theme.look = "custom"
    end
    -- Looks before revision 4 were not complete authored presets.
    if revision > 0 and revision < 4 then theme.look = "custom" end
    if type(theme.preset) ~= "string" or not NS.PresetOverrides[theme.preset] then
        theme.preset = defaults.preset
    end
end

-- Forever Glass before revision 39: return untouched retired values to the
-- current authored look.
local function MigrateRetiredForeverLook(db, revision)
    if not (revision > 0 and revision < 39 and IsForeverGlass(db)) then return end
    local look = NS.LookPresets.foreverGlass
    for key, retired in pairs(RETIRED_FOREVER_APPEARANCE) do
        if db.theme[key] == retired then db.theme[key] = look.appearance[key] end
    end
    if Matches(db.geometry, RETIRED_FOREVER_GEOMETRY) then
        db.geometry.radius = look.geometry.radius
    end
    local colors = db.theme.colors
    local palette = NS.PresetOverrides.foreverGlass
    for key, hex in pairs(RETIRED_FOREVER_COLORS) do
        RestoreForeverColor(colors[key], hex, palette[key], RETIRED_FOREVER_ALPHA[key])
    end
    for target, source in pairs(NS.MicroColorSources) do
        RestoreForeverColor(colors[target], RETIRED_FOREVER_COLORS[source],
            palette[source], RETIRED_FOREVER_ALPHA[source])
    end
    if revision == 38 and db.typography.face == "friz" then
        db.typography.face = NS.Defaults.typography.face
    end
end

-- MergeDefaults has already given every factory color key a full table.
local function NormalizeColors(colors)
    for key in pairs(NS.Defaults.theme.colors) do
        local color = colors[key]
        for index = 1, 4 do color[index] = Clamp(color[index], 0, 1) end
    end
end

local function MigrateColors(db, revision)
    local theme = db.theme
    local colors = theme.colors
    -- The factory Midnight Dark soft-fill hover of revision 47 became a
    -- visible outline. Only the untouched factory hover color moves.
    if revision > 0 and revision < 48 and theme.look == "midnightDark"
        and theme.hoverStyle == "softFill"
        and math.abs(theme.hoverIntensity - 0.68) < EPSILON
        and SameRGB(colors.hover, 66 / 255, 71 / 255, 67 / 255) then
        local refreshed = NS.PresetOverrides.midnightDark.hover
        colors.hover[1], colors.hover[2], colors.hover[3] = refreshed[1], refreshed[2], refreshed[3]
        theme.hoverStyle = "outline"
        theme.hoverIntensity = 1
    end
    if revision < 23 then
        -- Micro Bar tokens did not exist before revision 23. Seed them from
        -- the profile's established palette so existing custom looks upgrade
        -- coherently instead of receiving unrelated factory colors.
        for target, source in pairs(NS.MicroColorSources) do
            colors[target] = NS.CopyValue(colors[source])
        end
    end
    if revision > 0 and revision < 41 and IsForeverGlass(db) then
        -- Revision 40 still inherited these colors from generic Glass.
        -- Replace only untouched factory RGB and keep custom alpha intact.
        local palette = NS.PresetOverrides.foreverGlass
        ReplaceFactoryRGB(colors.card, RETIRED_FOREVER_CARD, palette.card)
        for key, source in pairs(NS.MicroColorSources) do
            ReplaceFactoryRGB(colors[key], palette[source], palette[key])
        end
    end
end

local function NormalizeGeometry(geometry)
    local defaults = NS.Defaults.geometry
    KeepListed(geometry, GEOMETRY_CHOICES, defaults)
    KeepListedNumber(geometry, "radius", NS.GeometryRadii, defaults.radius)
    KeepListedNumber(geometry, "border", NS.GeometryBorders, defaults.border)
end

local LEGACY_MEDIA_PREFIX = "Midnight Skin - "

local function NormalizeTypography(typography)
    local defaults = NS.Defaults.typography
    typography.enabled = typography.enabled == true
    if not IsListed(NS.FontFaces, typography.face) then typography.face = defaults.face end
    if type(typography.sharedMediaFont) ~= "string" then
        typography.sharedMediaFont = defaults.sharedMediaFont
    end
    local font = typography.sharedMediaFont
    if font:sub(1, #LEGACY_MEDIA_PREFIX) == LEGACY_MEDIA_PREFIX then
        typography.sharedMediaFont = "MapkoSkin - " .. font:sub(#LEGACY_MEDIA_PREFIX + 1)
    end
    if type(typography.customPath) ~= "string" then typography.customPath = "" end
    typography.applyChat = typography.applyChat ~= false
    typography.includeSpecial = typography.includeSpecial ~= false
end

local function NormalizeToggleSet(settings, defaults)
    for key in pairs(defaults) do settings[key] = settings[key] ~= false end
end

local function NormalizeToggles(db)
    NormalizeToggleSet(db.skins, NS.Defaults.skins)
    NormalizeToggleSet(db.skinCategories, NS.Defaults.skinCategories)
    NormalizeToggleSet(db.hud, NS.Defaults.hud)
    for index = 1, #RETIRED_SKINS do db.skins[RETIRED_SKINS[index]] = nil end
    for index = 1, #RETIRED_HUD do db.hud[RETIRED_HUD[index]] = nil end
end

local function NormalizeWindowActions(windowActions, revision)
    local defaults = NS.Defaults.icons.windowActions
    KeepListed(windowActions, WINDOW_ACTION_CHOICES, defaults)
    -- Revision 36 enlarged the close glyph; hand-picked sizes stay.
    if revision < 36 and windowActions.closeGlyphSize == 10 then
        windowActions.closeGlyphSize = 16
    end
    ClampRanges(windowActions, NS.WindowActionRanges)
    KeepListedNumber(windowActions, "surfaceRadius", NS.GeometryRadii, defaults.surfaceRadius)
end

local function ValidLayoutName(name, limits)
    return type(name) == "string" and #name <= limits.maxNameLength
        and name:match("^[%w_]+$") ~= nil
end

local function ValidLayoutScale(scale, limits)
    return type(scale) == "number" and scale == scale
        and scale >= limits.minScale and scale <= limits.maxScale
end

local function ValidLayoutPosition(point, limits)
    return type(point) == "table" and type(point.x) == "number" and type(point.y) == "number"
        and point.x == point.x and point.y == point.y
        and math.abs(point.x) <= limits.maxOffset and math.abs(point.y) <= limits.maxOffset
end

-- Keeps at most maxEntries valid window entries.
local function PruneLayoutEntries(entries, isValid)
    local limits = NS.WindowLayoutLimits
    local kept = 0
    for name, value in pairs(entries) do
        if kept >= limits.maxEntries or not ValidLayoutName(name, limits)
            or not isValid(value, limits) then
            entries[name] = nil
        else
            kept = kept + 1
        end
    end
end

local function NormalizeWindowControls(windowControls)
    windowControls.enabled = windowControls.enabled ~= false
    if type(windowControls.scales) ~= "table" then windowControls.scales = {} end
    PruneLayoutEntries(windowControls.scales, ValidLayoutScale)
    if type(windowControls.positions) ~= "table" then windowControls.positions = {} end
    PruneLayoutEntries(windowControls.positions, ValidLayoutPosition)
end

-- Micro Bar migrations. They run in this exact order: a later step sees the
-- result of an earlier one.

-- Two shipped Forever positions put the bar over the chat. Move only those
-- exact signatures; preserve every other custom layout.
local function MoveForeverBarOffChat(db, microMenu, revision)
    local oldFactoryBottom = revision <= 48 and IsPlacedAt(microMenu, "BOTTOM", 463, 0)
    local oldFactoryLeft = revision <= 49 and IsPlacedAt(microMenu, "BOTTOMLEFT", 18, 18)
    if IsForeverGlass(db) and microMenu.preset == "forever"
        and microMenu.layoutMode == "owned" and microMenu.positionPreset == "custom"
        and (oldFactoryBottom or oldFactoryLeft) then
        PlaceAtPreset(microMenu, "bottomCenter")
    end
end

local function RestoreForever38Strip(db, microMenu, revision)
    if revision ~= 38 or not IsForeverGlass(db) then return end
    if microMenu.positionPreset == "bottomLeft" and IsPlacedAt(microMenu, "BOTTOMLEFT", 18, 18) then
        PlaceAtPreset(microMenu, "bottomRight")
    end
    if microMenu.preset == "forever" then
        if microMenu.barBorder == 1 then microMenu.barBorder = 2 end
        if microMenu.padding == 5 then microMenu.padding = 3 end
    end
end

local function RestoreForeverNativeStrip(_, microMenu, revision)
    if revision >= 38 and revision < 40 and IsForever()
        and Matches(microMenu, FOREVER_NATIVE_STRIP) then
        ApplyMicroLook(microMenu, "forever")
    end
end

-- Update the old boxed factory strip once. Keep hand-tuned visual choices
-- and all custom positions intact.
local function RefreshForeverBoxedStrip(db, microMenu, revision)
    if not (revision > 0 and revision < 42 and IsForeverGlass(db)
        and microMenu.preset == "forever") then
        return
    end
    if Matches(microMenu, FOREVER_BOXED_STRIP) then ApplyMicroLook(microMenu, "forever") end
    if microMenu.positionPreset == "bottomRight"
        and IsPlacedAt(microMenu, "BOTTOMRIGHT", -24, 24) then
        PlaceAtPreset(microMenu, "bottomCenter")
    end
    local palette = NS.PresetOverrides.foreverGlass
    for key, hex in pairs(RETIRED_FOREVER_MICRO_COLORS) do
        RestoreForeverColor(db.theme.colors[key], hex, palette[key])
    end
end

-- Keep the factory strip clear of the default action bars.
local function LiftForeverStrip(_, microMenu, revision)
    if revision > 0 and revision < 43 and IsForever()
        and microMenu.positionPreset == "bottomCenter"
        and IsPlacedAt(microMenu, "BOTTOM", 0, 18) then
        microMenu.layoutY = NS.MicroMenuPositionPresets.bottomCenter.y
    end
end

-- Upgrade only the untouched named Retail factory style. User-tuned bars keep
-- their saved artwork, geometry and position.
local function UpgradeModernNativeStrip(_, microMenu, revision)
    if revision > 0 and revision < 45 and Matches(microMenu, MODERN_NATIVE_STRIP) then
        ApplyMicroLook(microMenu, "modern")
    end
end

-- Move only the named factory look to the fuller gold icon artwork.
local function BoldForeverLineStrip(db, microMenu, revision)
    if revision > 0 and revision < 44 and IsForeverGlass(db)
        and Matches(microMenu, FOREVER_LINE_STRIP) then
        microMenu.iconStyle = NS.MicroMenuPresetValues.forever.iconStyle
    end
end

local function DarkenModernStrip(db, microMenu, revision)
    if not (revision > 0 and revision < 47 and db.theme.look == "midnightDark"
        and microMenu.preset == "modern") then
        return
    end
    local modern = NS.MicroMenuPresetValues.modern
    for _, key in ipairs(NS.MicroMenuLookKeys) do
        if microMenu[key] ~= modern[key] then return end
    end
    ApplyMicroLook(microMenu, "midnightDark")
    microMenu.preset = "midnightDark"
end

-- Tighten only the untouched Forever strip and allow all fourteen Camelot
-- buttons on one line. Preserve hand-tuned spacing and rows.
local function TightenForeverBoldStrip(_, microMenu, revision)
    if revision > 0 and revision < 46 and IsForever()
        and Matches(microMenu, FOREVER_BOLD_STRIP) then
        if microMenu.spacing == 0 then microMenu.spacing = -3 end
        if microMenu.buttonsPerLine == 13 then microMenu.buttonsPerLine = 14 end
    end
end

-- Move the four old named styles to the authored looks while leaving
-- user-edited bars alone.
local function MapLegacyMicroPresets(_, microMenu, revision)
    if revision >= 33 then return end
    microMenu.preset = LEGACY_MICRO_PRESETS[microMenu.preset] or microMenu.preset
    if NS.MicroMenuPresetValues[microMenu.preset] then
        ApplyMicroLook(microMenu, microMenu.preset)
    elseif microMenu.preset == "custom" then
        microMenu.barMaterial = "theme"
    end
end

local MICRO_MENU_MIGRATIONS = {
    MoveForeverBarOffChat,
    RestoreForever38Strip,
    RestoreForeverNativeStrip,
    RefreshForeverBoxedStrip,
    LiftForeverStrip,
    UpgradeModernNativeStrip,
    BoldForeverLineStrip,
    DarkenModernStrip,
    TightenForeverBoldStrip,
    MapLegacyMicroPresets,
}

local function NormalizeMicroMenu(microMenu)
    local defaults = NS.Defaults.icons.microMenu
    if microMenu.preset ~= "custom" and not IsListed(NS.MicroMenuPresets, microMenu.preset) then
        microMenu.preset = defaults.preset
    end
    if microMenu.iconStyle == "glyph" then microMenu.iconStyle = "line" end
    KeepListed(microMenu, MICRO_MENU_CHOICES, defaults)
    if microMenu.positionPreset ~= "custom"
        and not NS.MicroMenuPositionPresets[microMenu.positionPreset] then
        microMenu.positionPreset = defaults.positionPreset
    end
    microMenu.locked = microMenu.locked ~= false
    for _, condition in ipairs(NS.MicroMenuLoadConditions) do
        local key = condition[1]
        if type(microMenu[key]) ~= "boolean" then microMenu[key] = defaults[key] end
    end
    if type(microMenu.barBackground) ~= "boolean" then
        microMenu.barBackground = defaults.barBackground
    end
    if type(microMenu.buttonBackground) ~= "boolean" then
        microMenu.buttonBackground = defaults.buttonBackground
    end
    ClampRanges(microMenu, NS.MicroMenuRanges)
    microMenu.iconSize = Round(Clamp(microMenu.iconSize, 10, math.min(28, microMenu.buttonSize - 4)))
    KeepListedNumber(microMenu, "radius", NS.GeometryRadii, defaults.radius)
end

function Database.Normalize(db)
    if type(db) ~= "table" then return nil end
    local revision = tonumber(db.revision) or 0
    local classicOptOut = IsClassicDetailsOptOut(db.characterDetails)
    MergeDefaults(db, NS.Defaults)
    db.revision = NS.Defaults.revision
    db.enabled = db.enabled ~= false
    NormalizeCharacter(db, classicOptOut)
    NormalizeTheme(db.theme, revision)
    MigrateRetiredForeverLook(db, revision)
    NormalizeColors(db.theme.colors)
    MigrateColors(db, revision)
    NormalizeGeometry(db.geometry)
    NormalizeTypography(db.typography)
    NormalizeToggles(db)
    NormalizeWindowActions(db.icons.windowActions, revision)
    NormalizeWindowControls(db.windowControls)
    local microMenu = db.icons.microMenu
    for index = 1, #MICRO_MENU_MIGRATIONS do
        MICRO_MENU_MIGRATIONS[index](db, microMenu, revision)
    end
    NormalizeMicroMenu(microMenu)
    return db
end

local function SanitizeValue(value, fallback)
    if type(fallback) == "table" then
        local source = type(value) == "table" and value or {}
        local result = {}
        for key, childDefault in pairs(fallback) do
            result[key] = SanitizeValue(source[key], childDefault)
        end
        return result
    end
    if type(value) ~= type(fallback) then return fallback end
    return value
end

local function CopyScale(scale)
    return scale
end

local function CopyPosition(point)
    return { x = point.x, y = point.y }
end

-- Copies at most maxEntries valid window entries of an untrusted profile.
local function CopyLayoutEntries(source, target, isValid, copy)
    if type(source) ~= "table" then return end
    local limits = NS.WindowLayoutLimits
    local copied = 0
    for name, value in pairs(source) do
        if copied < limits.maxEntries and ValidLayoutName(name, limits)
            and isValid(value, limits) then
            target[name] = copy(value)
            copied = copied + 1
        end
    end
end

function Database.SanitizeProfile(profile)
    if type(profile) ~= "table" then return nil end
    local safe = SanitizeValue(profile, NS.Defaults)
    local windowControls = profile.windowControls
    if type(windowControls) == "table" then
        CopyLayoutEntries(windowControls.scales, safe.windowControls.scales,
            ValidLayoutScale, CopyScale)
        CopyLayoutEntries(windowControls.positions, safe.windowControls.positions,
            ValidLayoutPosition, CopyPosition)
    end
    return Database.Normalize(safe)
end

function Database.NormalizeProfileName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("[%z\1-\31]", ""):match("^%s*(.-)%s*$") or ""
    if name == "" then return nil end
    if #name > 40 then name = name:sub(1, 40) end
    return name
end

-- Forever starts from the Suite's shipped factory skin profile when MSUF can
-- decode it; every other client starts from the defaults.
local function CreateFactoryProfile()
    local suite = _G.MSUFSuite
    local encoded = suite and suite.ForeverFactorySkinCompact
    local decode = _G.MSUF_TryDecodeCompactString
    if IsForever() and type(encoded) == "string" and type(decode) == "function" then
        local envelope = decode("MSUF3:" .. encoded:sub(8))
        if type(envelope) == "table"
            and (envelope.addon == "MapkoSkin" or envelope.addon == "MidnightSkin")
            and envelope.format == 1 and envelope.kind == "profile" then
            local profile = Database.SanitizeProfile(envelope.payload)
            if profile then return profile end
        end
    end
    return Database.Normalize(NS.CopyValue(NS.Defaults))
end
Database.CreateFactoryProfile = CreateFactoryProfile

local function NewRoot(profile)
    return {
        schema = Database.rootSchema,
        activeProfile = "Default",
        profiles = { Default = Database.Normalize(profile or CreateFactoryProfile()) },
    }
end

local function NormalizeRoot(root)
    root.schema = Database.rootSchema
    if type(root.profiles) ~= "table" then root.profiles = {} end
    local normalized = {}
    for rawName, profile in pairs(root.profiles) do
        local name = Database.NormalizeProfileName(rawName)
        if name and type(profile) == "table" then
            normalized[name] = Database.Normalize(profile)
        end
    end
    if not next(normalized) then normalized.Default = CreateFactoryProfile() end
    root.profiles = normalized
    local active = Database.NormalizeProfileName(root.activeProfile)
    if not active or not normalized[active] then
        active = normalized.Default and "Default" or next(normalized)
    end
    root.activeProfile = active
    return root
end

function Database.Initialize()
    local stored = _G.MSUFSuiteSkinDB
    if type(stored) ~= "table" then stored = _G.MapkoSkinDB end
    if type(stored) ~= "table" then stored = _G.MidnightSkinDB end
    local root
    if type(stored) == "table" and type(stored.profiles) == "table" then
        root = NormalizeRoot(stored)
    elseif type(stored) == "table" then
        -- One-time migration from the 0.7 flat SavedVariables layout. Keep the
        -- entire normalized profile; no setting is dropped.
        root = NewRoot(stored)
    else
        root = NewRoot()
    end
    _G.MSUFSuiteSkinDB = root
    _G.MidnightSkinDB = nil
    NS.RootDB = root
    NS.DB = root.profiles[root.activeProfile]
    return NS.DB
end

function Database.GetRoot()
    return NS.RootDB
end

function Database.GetActiveProfileName()
    return NS.RootDB and NS.RootDB.activeProfile or "Default"
end

function Database.GetProfile(name)
    return NS.RootDB and NS.RootDB.profiles and NS.RootDB.profiles[name]
end

function Database.GetProfileNames()
    local names = {}
    for name in pairs(NS.RootDB and NS.RootDB.profiles or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function ApplyActiveSettings(reason)
    if NS.Theme and NS.Theme.RefreshDynamicLook then NS.Theme.RefreshDynamicLook() end
    if NS.Typography then NS.Typography.ApplyConfigured() end
    if NS.Adapters then NS.Adapters.ApplyAll() end
    if NS.Registry then
        NS.Registry.RefreshAll()
        NS.Registry.NotifyListeners("profile", reason or "changed")
    end
end

function Database.SetProfile(name, profile)
    name = Database.NormalizeProfileName(name)
    profile = Database.SanitizeProfile(profile)
    if not name or not profile or not NS.RootDB then return false, "invalid-profile" end
    NS.RootDB.profiles[name] = profile
    if NS.RootDB.activeProfile == name then NS.DB = profile end
    return true, name
end

function Database.CreateProfile(name, copyCurrent)
    name = Database.NormalizeProfileName(name)
    if not name then return false, "invalid-name" end
    if not NS.RootDB then return false, "database-not-ready" end
    if NS.RootDB.profiles[name] then return false, "profile-exists" end
    NS.RootDB.profiles[name] = copyCurrent and Database.SanitizeProfile(NS.DB)
        or CreateFactoryProfile()
    return true, name
end

function Database.SetActiveProfile(name)
    name = Database.NormalizeProfileName(name)
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.RootDB then return false, "database-not-ready" end
    if not name or not NS.RootDB.profiles[name] then return false, "missing-profile" end
    if NS.Typography then NS.Typography.Restore() end
    NS.RootDB.activeProfile = name
    NS.DB = NS.RootDB.profiles[name]
    ApplyActiveSettings("activate")
    return true, name
end

function Database.DeleteProfile(name)
    name = Database.NormalizeProfileName(name)
    if not NS.RootDB then return false, "database-not-ready" end
    if not name or not NS.RootDB.profiles[name] then return false, "missing-profile" end
    local count = 0
    for _ in pairs(NS.RootDB.profiles) do count = count + 1 end
    if count <= 1 then return false, "last-profile" end
    local wasActive = name == NS.RootDB.activeProfile
    NS.RootDB.profiles[name] = nil
    if wasActive then
        local replacement = NS.RootDB.profiles.Default and "Default" or next(NS.RootDB.profiles)
        NS.RootDB.activeProfile = replacement
        NS.DB = NS.RootDB.profiles[replacement]
        ApplyActiveSettings("delete")
    end
    return true, wasActive and NS.RootDB.activeProfile or name
end

function Database.ReplaceProfiles(profiles, activeName)
    if NS.IsCombatLocked() or type(profiles) ~= "table" then return false, "invalid-profiles" end
    local clean = {}
    local count = 0
    for rawName, profile in pairs(profiles) do
        count = count + 1
        if count > 64 then return false, "too-many-profiles" end
        local name = Database.NormalizeProfileName(rawName)
        if name and type(profile) == "table" then clean[name] = Database.SanitizeProfile(profile) end
    end
    if not next(clean) then return false, "empty-profiles" end
    activeName = Database.NormalizeProfileName(activeName)
    if not activeName or not clean[activeName] then
        activeName = clean.Default and "Default" or next(clean)
    end
    if NS.Typography then NS.Typography.Restore() end
    NS.RootDB.profiles = clean
    NS.RootDB.activeProfile = activeName
    NS.DB = clean[activeName]
    ApplyActiveSettings("import-all")
    return true, activeName
end

function Database.ResetColors()
    NS.DB.theme.colors = NS.CopyValue(NS.Defaults.theme.colors)
    NS.DB.theme.preset = NS.Defaults.theme.preset
end

function Database.ResetAll()
    local profile = CreateFactoryProfile()
    local name = Database.GetActiveProfileName()
    if not NS.RootDB then NS.RootDB = NewRoot(profile) end
    NS.RootDB.profiles[name] = profile
    NS.DB = profile
    _G.MSUFSuiteSkinDB = NS.RootDB
    return profile
end

return Database
