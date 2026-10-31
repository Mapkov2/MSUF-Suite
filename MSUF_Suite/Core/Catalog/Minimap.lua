local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_Minimap")
local Number, Bool, Choice, String, Color, Font = B.Number, B.Bool, B.Choice, B.String, B.Color, B.Font

B.Module("minimap", {
    title = "Minimap",
    description = "A clean minimap in its own frame: size, shape, border, zoom, Blizzard buttons, an addon button drawer and information texts. Blizzard's minimap buttons keep working.",
    core = true, page = "suite_minimap",
    -- A dedicated minimap button collector (NS.MinimapButtonCollectors) owns
    -- addon buttons, not the map. The runtime lets it keep those buttons and
    -- leaves the Suite drawer dormant.
    conflicts = { "SexyMap", "Chinchilla", "BasicMinimap", "EllesmereUIMinimap", "ElvUI" },
    cvars = { rotateMinimap = true },
    summary = "stylePreset size point hoverResize hoverWidth shape borderSize styleTexture styleScale styleGlow"
        .. " styleGlowAlpha styleBackdrop styleBackdropAlpha visibility rotate elementRow elementSize"
        .. " showLanding landingIcon collectButtons drawerColumns",
})

local id = "minimap"
function NS.MigrateMinimapSpecialization(modules)
    local old = modules.mapQuickSwitch
    if type(old) ~= "table" then return end
    local minimap = type(modules.minimap) == "table" and modules.minimap or {}
    modules.minimap = minimap
    local keys = { enabled = "specButton", showSpec = "specShowSpec", showLoot = "specShowLoot",
        size = "specSize", x = "specX", y = "specY" }
    for source, target in pairs(keys) do
        if minimap[target] == nil then minimap[target] = old[source] end
    end
    -- The former labels had left/right reversed. Keep the physical position
    -- while the Minimap selector now names the correct corner.
    if minimap.specCorner == nil then minimap.specCorner = ({ 2, 1, 4, 3 })[old.corner or 1] end
    modules.mapQuickSwitch = nil
end

-- Shared by the live button and the movable preview.
NS.MinimapSpecCorners = {
    { "TOPLEFT", "TOPRIGHT", 4, 0 }, { "TOPRIGHT", "TOPLEFT", -4, 0 },
    { "BOTTOMLEFT", "BOTTOMRIGHT", 4, 0 }, { "BOTTOMRIGHT", "BOTTOMLEFT", -4, 0 },
}
function NS.CanShowMinimapSpecialization()
    return not NS.Client.isForever
end
NS.MinimapAnchorLabels = NS.AnchorLabels
NS.MinimapAnchorPoints = NS.AnchorPoints
-- The preview and runtime consume the same row geometry. Coordinates are:
-- item point, map point, outward X/Y, then growth X/Y.
NS.MinimapRowGeometry = {
    { "TOPRIGHT", "TOPLEFT", -1, 0, 0, -1 }, { "BOTTOMLEFT", "TOPLEFT", 0, 1, 1, 0 },
    { "TOPLEFT", "TOPRIGHT", 1, 0, 0, -1 }, { "BOTTOMRIGHT", "TOPRIGHT", 0, 1, -1, 0 },
    { "BOTTOMRIGHT", "BOTTOMLEFT", -1, 0, 0, 1 }, { "TOPLEFT", "BOTTOMLEFT", 0, -1, 1, 0 },
    { "BOTTOMLEFT", "BOTTOMRIGHT", 1, 0, 0, 1 }, { "TOPRIGHT", "BOTTOMRIGHT", 0, -1, -1, 0 },
}
NS.MinimapRowLabels = {
    "Top left, downward", "Top left, rightward", "Top right, downward", "Top right, leftward",
    "Bottom left, upward", "Bottom left, rightward", "Bottom right, upward", "Bottom right, leftward",
}
-- Text anchors: the nine inside points plus above and below the map.
NS.MinimapTextAnchorLabels = { "Above the map", "Below the map" }
for i = #NS.AnchorLabels, 1, -1 do table.insert(NS.MinimapTextAnchorLabels, 1, NS.AnchorLabels[i]) end
-- The choice values of the settings below (each is its label's position
-- there); the minimap runtime names its modes through these.
NS.MinimapDungeonAnchors = {
    { "TOPRIGHT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
    { "BOTTOMRIGHT", "TOPRIGHT" }, { "BOTTOMLEFT", "TOPLEFT" },
}
NS.MinimapTextAnchor = { ABOVE = #NS.AnchorLabels + 1, BELOW = #NS.AnchorLabels + 2 }
NS.MinimapShape = { SQUARE = 1, CIRCLE = 2, WIDE = 3 }
NS.MinimapStyleTexture = { NONE = 1, ARCANE_RING = 2, EMBER_RING = 3, ASTRAL_RING = 4, STEEL_FRAME = 5,
    CUSTOM = 6, PARCHMENT_SCROLL = 7 }
NS.MinimapStylePlacement = { ABOVE = 1, BEHIND = 2 }
NS.MinimapStyleBlend = { NORMAL = 1, ADDITIVE = 2 }
NS.MinimapWeatherIcons = { BLIZZARD = 1, FOREVER = 2 }
NS.MinimapVisibility = { ALWAYS = 1, IN_COMBAT = 2, OUT_OF_COMBAT = 3, MOUSEOVER = 4, NEVER = 5 }
NS.MinimapRotate = { BLIZZARD = 1, ROTATE = 2, NORTH_UP = 3 }
NS.MinimapZoomButtons = { MOUSEOVER = 1, ALWAYS = 2, HIDE = 3 }
NS.MinimapMiddleClick = { NOTHING = 1, TRACKING = 2, CALENDAR = 3, WORLD_MAP = 4, MICRO_MENU = 5 }
NS.MinimapLanding = { ALWAYS = 1, MOUSEOVER = 2, NEVER = 3 }
NS.MinimapLandingIcon = { BLIZZARD = 1, BOOK = 2 }
NS.MinimapTextBox = { NONE = 1, BORDER = 2, CUSTOM = 3 }
NS.MinimapWeatherDisplay = { TEXT = 1, ICON = 2, BOTH = 3 }
NS.MinimapClockSource = { REALM = 1, LOCAL = 2, BOTH = 3 }
NS.MinimapDatePosition = { BESIDE = 1, ABOVE = 2, BELOW = 3 }
NS.MinimapClockClick = { CALENDAR = 1, CLOCK = 2 }
NS.MinimapInfoTooltip = { VALUE = 1, LOCKOUTS = 2, VAULT = 3, NONE = 4 }
NS.MinimapLatencySource = { HOME = 1, WORLD = 2, BOTH = 3 }
NS.MinimapCoordinatesMode = { MOUSEOVER = 1, ALWAYS = 2 }
NS.MinimapDurabilityMode = { LOWEST = 1, COMBINED = 2 }
NS.MinimapInstanceKind = { ALL = 1, RAIDS = 2, DUNGEONS = 3 }
-- Colour per difficulty tier (1 normal, 2 heroic, 3 mythic, 4 raid finder or
-- follower, 5 timewalking, 6 keystone): the difficulty text and its preview.
NS.MinimapDifficultyColors = { "e0a060", "4aa8ff", "b36bff", "a0a0a0", "40d8d8", "ff9a33" }

-- Addons that collect the minimap's buttons and take permanent ownership of
-- them (folder names). While one is loaded the Suite drawer stays dormant and
-- leaves the buttons to it; the map itself stays ours.
NS.MinimapButtonCollectors = { "MinimapButtonButton", "HidingBar", "MinimapButtonFrame" }
local collectors = {}
for _, name in ipairs(NS.MinimapButtonCollectors) do collectors[name] = true end
function NS.IsMinimapButtonCollector(name)
    return collectors[name] == true
end
-- The folder name of the first loaded collector, or nil.
function NS.MinimapButtonCollector()
    for _, name in ipairs(NS.MinimapButtonCollectors) do
        if NS.Client.IsAddOnLoaded(name) then return name end
    end
end

-- Addon buttons the player keeps on the map instead of in the drawer: their
-- frame names, one per line, in the hidden setting drawerKeep.
local Kept = {}
NS.MinimapKeptButtons = Kept
local KEPT_LIMIT = 24
-- The names of a stored list in order, and the set of them.
function Kept.Names(text)
    local names, set = {}, {}
    for name in text:gmatch("[^\n]+") do
        if not set[name] then names[#names + 1], set[name] = name, true end
    end
    return names, set
end
-- The list with the name added; nil when the name cannot be stored or the list is full.
function Kept.With(text, name)
    local names, set = Kept.Names(text)
    if set[name] then return text end
    if name:find("%c") or #names >= KEPT_LIMIT then return nil end
    names[#names + 1] = name
    local joined = table.concat(names, "\n")
    if #joined > NS.SuiteCatalog.minimap.rules.drawerKeep.maxLength then return nil end
    return joined
end
function Kept.Without(text, name)
    local names = Kept.Names(text)
    for i = #names, 1, -1 do
        if names[i] == name then table.remove(names, i) end
    end
    return table.concat(names, "\n")
end
-- LibDBIcon names the frame of each icon after the name its addon registered.
local ICON_PREFIX = "LibDBIcon10_"
function Kept.IconFrame(name)
    return ICON_PREFIX .. name
end
-- The button's name as its addon shows it.
function Kept.Label(name)
    return (name:gsub("^" .. ICON_PREFIX, ""))
end

B.Section(id, "layout", "Size and position", {
    Number("size", "Minimap size", 190, 100, 600),
    Choice("point", "Screen anchor", 3, NS.MinimapAnchorLabels),
    Number("x", "Horizontal position", -20, -4000, 4000),
    Number("y", "Vertical position", -20, -3000, 3000),
    Bool("captured", "Blizzard layout imported", false),
})
B.Section(id, "dungeon", "Group finder", {
    Bool("dungeonButton", "Group finder", false),
    Choice("dungeonStyle", "Style", 1, { "Default", "Modern Dark" }),
    Number("dungeonWidth", "Width", 52, 20, 100),
    Number("dungeonHeight", "Height", 26, 16, 60),
    Choice("dungeonAnchor", "Anchor", 1, { "Bottom right", "Bottom left", "Top right", "Top left" }),
    Number("dungeonX", "Horizontal offset", 0, -600, 600),
    Number("dungeonY", "Vertical offset", -12, -600, 600),
})
B.Section(id, "hover_size", "Mouseover size", {
    Bool("hoverResize", "Resize on mouseover", false),
    Number("hoverWidth", "Mouseover width", 300, 100, 600),
    Number("hoverHeight", "Mouseover height", 300, 100, 600),
})
B.Section(id, "shape", "Shape, border and shadow", {
    String("iconSkin", "Icon skin", "CUSTOM", 64),
    Choice("shape", "Map shape", 1, { "Square", "Circle", "Wide rectangle (3:2)" }),
    Number("borderSize", "Border thickness", 1, 0, 4),
    Color("borderColor", "Border color", "000000"),
    Bool("borderClassColor", "Class-colored border", false),
    Number("outerBorderSize", "Outer border size", 0, 0, 6),
    Number("outerBorderGap", "Outer border gap", 4, 0, 20),
    Color("outerBorderColor", "Outer border color", "000000"),
    Number("borderAlpha", "Border opacity (percent)", 100, 0, 100, 5),
    Number("shadowSize", "Outer shadow size", 0, 0, 24),
    Color("shadowColor", "Outer shadow color", "000000"),
    Number("shadowAlpha", "Outer shadow opacity (percent)", 45, 0, 100, 5),
})
-- A preset writes ordinary settings so every result can be tuned afterwards.
-- The texture paths are Suite-owned original art; Custom accepts a local WoW
-- texture path or a file ID. Existing profiles retain the clean default.
NS.MinimapStyleTextureNames = { "None", "Arcane ring", "Ember ring", "Astral ring", "Steel frame",
    "Custom texture", "Parchment scroll" }
NS.MinimapStylePresetNames = { "Custom", "Clean", "Arcane", "Ember", "Astral", "Steel",
    "MSUF Forever", "Midnight Blue", "Midnight Dark", "Antique Map", "Clean Modern", "Class Style" }
local clean = {
    shape = NS.MinimapShape.SQUARE, borderSize = 1, borderColor = "000000", borderClassColor = false, borderAlpha = 100,
    outerBorderSize = 0, outerBorderGap = 4, outerBorderColor = "000000",
    shadowSize = 0, shadowColor = "000000", shadowAlpha = 45,
    styleTexture = NS.MinimapStyleTexture.NONE, styleTexturePath = "", styleColor = "ffffff", styleAlpha = 100,
    styleScale = 100, styleX = 0, styleY = 0, stylePlacement = NS.MinimapStylePlacement.ABOVE,
    styleBlend = NS.MinimapStyleBlend.NORMAL, styleRotation = 0,
    styleGlow = false, styleGlowColor = "7963bf", styleGlowAlpha = 50, styleGlowScale = 145,
    styleBackdrop = false, styleBackdropColor = "090c14", styleBackdropAlpha = 85, styleBackdropPadding = 4,
}
local function Preset(index, changes)
    local values = {}
    for key, value in pairs(clean) do values[key] = value end
    for key, value in pairs(changes or {}) do values[key] = value end
    values.stylePreset = index
    return values
end
NS.MinimapStylePresets = {
    [2] = Preset(2),
    [3] = Preset(3, { shape = 2, borderSize = 2, borderColor = "352458", shadowSize = 8,
        shadowColor = "6146b7", shadowAlpha = 60, styleTexture = 2, styleColor = "b7a4ff",
        styleScale = 124, styleGlow = true, styleGlowColor = "7151d5", styleGlowAlpha = 70,
        styleBackdrop = true, styleBackdropColor = "0b071b" }),
    [4] = Preset(4, { shape = 2, borderSize = 2, borderColor = "6d2b16", shadowSize = 9,
        shadowColor = "e45d23", shadowAlpha = 55, styleTexture = 3, styleColor = "ffc078",
        styleScale = 125, styleGlow = true, styleGlowColor = "ff691c", styleGlowAlpha = 64,
        styleBackdrop = true, styleBackdropColor = "1c0b08" }),
    [5] = Preset(5, { shape = 2, borderSize = 1, borderColor = "1d506e", shadowSize = 10,
        shadowColor = "2686aa", shadowAlpha = 52, styleTexture = 4, styleColor = "a7e8ff",
        styleScale = 125, styleRotation = 6, styleGlow = true, styleGlowColor = "4ac1e9",
        styleGlowAlpha = 70, styleBackdrop = true, styleBackdropColor = "06131e" }),
    [6] = Preset(6, { shape = 1, borderSize = 2, borderColor = "30424d", shadowSize = 7,
        shadowColor = "172a39", shadowAlpha = 55, styleTexture = 5, styleColor = "c1d6df",
        styleScale = 118, styleGlow = true, styleGlowColor = "5a9eb8", styleGlowAlpha = 36,
        styleBackdrop = true, styleBackdropColor = "0c151b" }),
    [7] = Preset(7, { shape = 1, borderSize = 1, borderColor = "9f8960", borderAlpha = 58,
        shadowSize = 8, shadowColor = "14181b", shadowAlpha = 55,
        styleTexture = 1, styleGlow = true, styleGlowColor = "d8b66a", styleGlowAlpha = 20,
        styleGlowScale = 115, styleBackdrop = false }),
    [8] = Preset(8, { shape = 1, borderSize = 1, borderColor = "41627a", borderAlpha = 78,
        shadowSize = 8, shadowColor = "0a1522", shadowAlpha = 54,
        styleGlow = true, styleGlowColor = "57c7df", styleGlowAlpha = 18,
        styleGlowScale = 115, styleBackdrop = true,
        styleBackdropColor = "0a1522", styleBackdropAlpha = 78 }),
    [9] = Preset(9, { shape = 1, borderSize = 1, borderColor = "575b58", borderAlpha = 78,
        shadowSize = 8, shadowColor = "111315", shadowAlpha = 52,
        styleGlow = true, styleGlowColor = "b9ab86", styleGlowAlpha = 13,
        styleGlowScale = 115, styleBackdrop = true,
        styleBackdropColor = "151719", styleBackdropAlpha = 80 }),
    [10] = Preset(10, { shape = 1, borderSize = 0, shadowSize = 0,
        styleTexture = 7, styleScale = 130, styleX = 0, styleY = 0,
        stylePlacement = 1, styleBackdrop = false, styleGlow = false }),
    [11] = Preset(11, { shape = 1, borderSize = 1, borderColor = "333333", borderAlpha = 95,
        shadowSize = 0, styleTexture = 1, styleGlow = false,
        styleBackdrop = true, styleBackdropColor = "101010", styleBackdropAlpha = 82 }),
}
NS.MinimapStylePresets[12] = B.ClassPreset(NS.MinimapStylePresets[11], {
    borderColor = "border", styleGlowColor = "accent",
})
NS.MinimapStylePresets[12].stylePreset = 12
NS.MinimapStyleVisualKeys = {}
for key in pairs(clean) do NS.MinimapStyleVisualKeys[key] = true end
-- The global looks Midnight Blue, Midnight Dark and MSUF Forever are the
-- style presets 8, 9 and 7; Custom is the first choice here.
NS.SuiteCatalog[id].look = {
    key = "stylePreset", presets = NS.MinimapStylePresets, visualKeys = NS.MinimapStyleVisualKeys,
    custom = 1, global = { 8, 9, 7, [5] = 11, [6] = 12 },
}

B.Section(id, "style_presets", "Choose a look", {
    Choice("stylePreset", "Style preset", 2, NS.MinimapStylePresetNames),
})
B.Section(id, "style_art", "Decorative border", {
    Choice("styleTexture", "Border artwork", clean.styleTexture, NS.MinimapStyleTextureNames),
    String("styleTexturePath", "Custom texture path or file ID", clean.styleTexturePath, 260),
    Color("styleColor", "Artwork color", clean.styleColor),
    Number("styleAlpha", "Artwork opacity (percent)", clean.styleAlpha, 0, 100, 5),
    Number("styleScale", "Artwork scale (percent)", clean.styleScale, 60, 200),
    Number("styleX", "Artwork horizontal offset", clean.styleX, -100, 100),
    Number("styleY", "Artwork vertical offset", clean.styleY, -100, 100),
    Choice("stylePlacement", "Artwork layer", clean.stylePlacement, { "Above the map", "Behind the map" }),
    Choice("styleBlend", "Blend", clean.styleBlend, { "Normal", "Additive" }),
    Number("styleRotation", "Rotation (degrees per second, 0: still)", clean.styleRotation, -30, 30),
})
B.Section(id, "style_glow", "Outer glow", {
    Bool("styleGlow", "Show outer glow", clean.styleGlow),
    Color("styleGlowColor", "Glow color", clean.styleGlowColor),
    Number("styleGlowAlpha", "Glow opacity (percent)", clean.styleGlowAlpha, 0, 100, 5),
    Number("styleGlowScale", "Glow scale (percent)", clean.styleGlowScale, 100, 200),
})
B.Section(id, "style_backdrop", "Background plate", {
    Bool("styleBackdrop", "Show background plate", clean.styleBackdrop),
    Color("styleBackdropColor", "Plate color", clean.styleBackdropColor),
    Number("styleBackdropAlpha", "Plate opacity (percent)", clean.styleBackdropAlpha, 0, 100, 5),
    Number("styleBackdropPadding", "Plate padding", clean.styleBackdropPadding, 0, 32),
})
B.Section(id, "behavior", "Map behavior", {
    Choice("visibility", "Show the minimap", 1, { "Always", "In combat", "Out of combat", "Mouseover", "Never" }),
    Choice("rotate", "Map rotation", 1, { "Blizzard setting", "Rotate with the player", "North stays up" }),
    Bool("scrollZoom", "Scroll to zoom", true),
    Number("zoomResetSeconds", "Reset zoom after manual zoom (seconds, 0: never)", 0, 0, 15),
    Choice("zoomButtons", "Zoom buttons", 1, { "Show on mouseover", "Always show", "Hide" }),
    Choice("middleClick", "Middle-click action", 2, { "Nothing", "Tracking menu", "Calendar", "World map", "Micro menu" }),
})
-- Offset labels are built here, so their format strings translate here.
local HORIZONTAL, VERTICAL = NS.Text("%s horizontal offset"), NS.Text("%s vertical offset")
for _, name in ipairs({ "zoomIn", "zoomOut" }) do
    B.Add(id, Number(name .. "X", HORIZONTAL:format(name), 0, -600, 600), "behavior")
    B.Add(id, Number(name .. "Y", VERTICAL:format(name), 0, -600, 600), "behavior")
end
B.Section(id, "elements", "Blizzard buttons", {
    Bool("showTracking", "Tracking button", true),
    Bool("showCalendar", "Calendar button", true),
    Bool("showDayNight", "Day/night indicator", false),
    Bool("showMail", "Mail indicator", true),
    Bool("showCrafting", "Crafting order indicator", true),
    Bool("showDifficulty", "Instance difficulty", true),
    Number("difficultyButtonX", "Difficulty icon horizontal offset", 0, -300, 300),
    Number("difficultyButtonY", "Difficulty icon vertical offset", 0, -300, 300),
    Bool("showCompartment", "Addon compartment", false),
    Choice("elementRow", "Button row placement", 1, NS.MinimapRowLabels),
    Number("elementSize", "Button size", 21, 16, 40),
    Number("elementSpacing", "Button spacing", 2, -20, 40),
    Number("elementDistance", "Distance from the map", 4, -20, 60),
})
-- Row placement remains the default. Each native button can then be moved
-- independently in the preview without replacing Blizzard's click handler.
for _, name in ipairs({ "Tracking", "Calendar", "Mail", "Crafting", "Compartment" }) do
    local prefix, label = "button" .. name, NS.Text(name)
    B.Add(id, Number(prefix .. "X", HORIZONTAL:format(label), 0, -600, 600), "elements").category = "advanced"
    B.Add(id, Number(prefix .. "Y", VERTICAL:format(label), 0, -600, 600), "elements").category = "advanced"
end
B.Section(id, "landing", "Expansion feature button", {
    Choice("showLanding", "Show Omnium Folio / expansion button", 2, { "Always", "Mouseover", "Never" }),
    Choice("landingIcon", "Button icon", 1, { "Blizzard artwork", "Simple book" }),
    Number("landingX", "Folio horizontal offset", 0, -300, 300),
    Number("landingY", "Folio vertical offset", 0, -300, 300),
})
B.Section(id, "specialization", "Minimap specialization menu", {
    Bool("specButton", "Minimap specialization menu", false),
    Bool("specShowSpec", "Show specialization choices", true),
    Bool("specShowLoot", "Show loot specialization choices", true),
    Choice("specCorner", "Minimap corner", 1, { "Top right", "Top left", "Bottom right", "Bottom left" }),
    Number("specSize", "Button size", 24, 18, 40),
    Number("specX", "Horizontal offset", 0, -600, 600),
    Number("specY", "Vertical offset", 0, -600, 600),
})
B.Section(id, "addons", "Addon buttons", {
    Bool("collectButtons", "Collect addon buttons into a drawer", true),
    Choice("drawerRow", "Drawer button placement", 5, NS.MinimapRowLabels),
    Number("drawerButtonSize", "Drawer icon size", 24, 14, 40),
    Number("drawerColumns", "Drawer columns", 4, 1, 8),
    Bool("drawerMouseover", "Show the drawer button only on mouseover", false),
    Number("drawerX", "Drawer horizontal offset", 0, -600, 600),
    Number("drawerY", "Drawer vertical offset", 0, -600, 600),
    -- Edited by the page's picker and list (MinimapButtonList.lua), not as text.
    String("drawerKeep", "Keep these buttons on the minimap", "", 1200),
})

-- Information texts keep their established keys and per-text styling.
local infoFields = { { "Clock", 2, 0, -4, 120, "Show clock" }, { "FPS", 7, 4, 4, 100, "Show FPS" },
    { "Latency", 9, -4, 4, 110, "Show latency" }, { "Coordinates", 1, 4, -4, 100, "Show coordinates" },
    { "Durability", 3, -4, -4, 110, "Show durability" }, { "Location", 8, 0, 4, 220, "Show location" },
    { "CalendarDay", 3, -24, -30, 60, "Calendar day" },
    { "Weather", 11, 0, -4, 120, "Show weather" } }
NS.MinimapInfoFields = {}
for _, field in ipairs(infoFields) do
    local key = field[1]
    local prefix = "info" .. key
    NS.MinimapInfoFields[#NS.MinimapInfoFields + 1] = key
    local section = "info_" .. key:lower()
    local shown = B.Add(id, Bool(prefix, field[6], key == "Clock" or key == "Location" or key == "Weather" and NS.Client.isForever), section, key)
    shown.infoField = key
    local function Info(rule)
        rule.enableKey = prefix
        return B.Add(id, rule, section, key)
    end
    if key == "Weather" then
        Info(Choice("infoWeatherDisplay", "Weather display", NS.MinimapWeatherDisplay.BOTH,
            { "Text only", "Icon only", "Icon and text" }))
        local icons = NS.MinimapWeatherIcons
        Info(Choice("infoWeatherIconStyle", "Weather icons", NS.Client.isForever and icons.FOREVER or icons.BLIZZARD,
            { "Blizzard icons", "Forever artwork" }))
        Info(Number("infoWeatherIconSize", "Icon size", 24, 12, 64))
    end
    Info(Font(prefix .. "Font", "Text font"))
    Info(Number(prefix .. "Size", "Text size", 12, 8, 32))
    Info(Choice(prefix .. "Outline", "Text outline", 2, { "None", "Outline", "Thick outline", "Monochrome outline" }))
    Info(Choice(prefix .. "Rendering", "Font rendering", NS.FontRendering.SLUG, { "Smooth", "Sharp / pixel", "Slug" }))
    Info(Bool(prefix .. "Shadow", "Text shadow"))
    Info(Number(prefix .. "ShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5))
    Info(Choice(prefix .. "ShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }))
    Info(Color(prefix .. "Color", "Text color", "ffffff"))
    Info(Bool(prefix .. "ClassColor", "Use class color"))
    Info(Number(prefix .. "Width", "Text width", field[5], 40, 400))
    Info(Choice(prefix .. "Anchor", "Text anchor", field[2], NS.MinimapTextAnchorLabels))
    Info(Number(prefix .. "X", "Horizontal offset", field[3], -300, 300)).category = "advanced"
    Info(Number(prefix .. "Y", "Vertical offset", field[4], -300, 300)).category = "advanced"
    Info(Choice(prefix .. "Box", "Text background", 1, { "None", "Box in the border color", "Box in custom color" }))
    Info(Color(prefix .. "BoxColor", "Text background color", "000000")).requiresChoice = {
        key = prefix .. "Box", values = { [2] = true, [3] = true },
    }
end
local function InfoOption(key, rule)
    rule.enableKey = "info" .. key
    return B.Add(id, rule, "info_" .. key:lower(), key)
end
InfoOption("Clock", Choice("infoClockSource", "Clock source", 1, { "Realm time", "Local time", "Realm and local time" }))
InfoOption("Clock", Bool("infoClock24Hour", "Use 24-hour format", true))
InfoOption("Clock", Bool("infoClockSeconds", "Show seconds"))
-- The date is Blizzard's localized short date (FormatShortDate).
InfoOption("Clock", Bool("infoClockDate", "Show date"))
InfoOption("Clock", Choice("infoClockDatePosition", "Date position", 1,
    { "Beside the time", "Above the time", "Below the time" }))
InfoOption("Clock", Choice("infoClockClick", "Clock left-click action", 2, { "Calendar", "Clock" }))
for _, field in ipairs({ "Clock", "FPS", "Latency" }) do
    InfoOption(field, Choice("info" .. field .. "Tooltip", "Hover tooltip", 1,
        { "Value and actions", "Instance lockouts", "Great Vault", "No tooltip" })).infoTooltip = true
end
InfoOption("FPS", Number("infoFPSInterval", "FPS update interval (seconds)", 1, 0.1, 5, 0.05))
InfoOption("FPS", Number("infoFPSWarning", "Low FPS threshold", 30, 1, 300))
InfoOption("FPS", Number("infoFPSGood", "Good FPS threshold", 60, 1, 300))
InfoOption("Latency", Choice("infoLatencySource", "Latency source", 2, { "Home", "World", "Home and world" }))
InfoOption("Latency", Number("infoLatencyInterval", "Latency update interval (seconds)", 5, 0.2, 30, 0.1))
InfoOption("Latency", Number("infoLatencyWarning", "Warning latency (ms)", 100, 0, 2000))
InfoOption("Latency", Number("infoLatencyBad", "High latency (ms)", 200, 0, 3000))
InfoOption("Coordinates", Choice("infoCoordinatesMode", "Show coordinates", 2, { "On mouseover", "Always" }))
InfoOption("Coordinates", Bool("infoCoordinatesHideInstance", "Hide coordinates in instances", true))
InfoOption("Coordinates", Number("infoCoordinatesInterval", "Coordinate update interval (seconds)", 0.5, 0.1, 5, 0.05))
InfoOption("Coordinates", Number("infoCoordinatesDecimals", "Coordinate decimal places", 1, 0, 3))
InfoOption("Durability", Bool("infoDurabilityIcon", "Show durability icon", true))
InfoOption("Durability", Choice("infoDurabilityMode", "Durability value", 1, { "Lowest equipped item", "Combined equipped durability" }))
InfoOption("Durability", Bool("infoDurabilityStatusColors", "Use durability status colors", true))
InfoOption("Durability", Number("infoDurabilityBad", "Low durability threshold (percent)", 20, 0, 100))
InfoOption("Durability", Number("infoDurabilityWarning", "Medium durability threshold (percent)", 50, 0, 100))
for _, spec in ipairs({
    { "Good", "High durability color", "75d36f" },
    { "Warning", "Medium durability color", "ffd166" },
    { "Bad", "Low durability color", "ff6677" },
}) do
    InfoOption("Durability", Color("infoDurability" .. spec[1] .. "Color", spec[2], spec[3])).enableKey =
        "infoDurabilityStatusColors"
end
NS.MinimapLocationSource = { CUSTOM = 1, ZONE = 2, SUBZONE = 3, MINIMAP = 4, BOTH = 5 }
InfoOption("Location", Choice("infoLocationSource", "Location source", 1,
    { "Custom", "Zone", "Subzone", "Minimap zone", "Zone + subzone" }))
InfoOption("Location", Bool("infoLocationZone", "Show zone", true))
InfoOption("Location", Bool("infoLocationSubzone", "Show subzone", false))
InfoOption("Location", Bool("infoLocationBelow", "Show subzone below zone"))
InfoOption("Location", Bool("infoLocationZoneColor", "Use zone color", false))
InfoOption("Location", Bool("infoLocationClick", "Click opens the world map", true))
B.Section(id, "info_colors", "Performance colors", {
    Bool("infoStatusColors", "Use performance status colors"),
    Color("infoGoodColor", "Good status color", "75d36f"),
    Color("infoWarningColor", "Warning status color", "ffd166"),
    Color("infoBadColor", "Bad status color", "ff6677"),
})
B.Section(id, "info_tooltips", "Hover details", {
    Number("tooltipScale", "Minimap tooltip scale (percent)", 100, 50, 200, 5),
    Choice("tooltipInstanceKind", "Instance lockout filter", 1, { "Raids and dungeons", "Raids", "Dungeons" }),
    Bool("tooltipExpired", "Include expired lockouts"),
    Bool("tooltipWorldBosses", "Include world bosses", true),
    Bool("tooltipBossProgress", "Show defeated boss count", true),
    Number("tooltipRows", "Maximum lockout rows", 20, 5, 60),
    Bool("tooltipRewardLevels", "Show weekly reward item levels", true),
})
B.Add(id, Bool("infoDifficulty", "Show instance difficulty as text", false), "info_difficulty", "Difficulty")
for _, rule in ipairs({
    Font("infoDifficultyFont", "Text font"),
    Number("infoDifficultySize", "Text size", 12, 8, 24),
    Choice("infoDifficultyOutline", "Text outline", 2, { "None", "Outline", "Thick outline", "Monochrome outline" }),
    Choice("infoDifficultyRendering", "Font rendering", NS.FontRendering.SLUG, { "Smooth", "Sharp / pixel", "Slug" }),
    Bool("infoDifficultyShadow", "Text shadow"),
    Number("infoDifficultyShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
    Choice("infoDifficultyShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
    Bool("infoDifficultyColors", "Color by difficulty", true),
    Color("infoDifficultyColor", "Text color", "ffffff"),
    Number("infoDifficultyWidth", "Text width", 120, 40, 400),
    Choice("infoDifficultyAnchor", "Text anchor", 1, NS.MinimapTextAnchorLabels),
    Number("infoDifficultyX", "Horizontal offset", 4, -300, 300),
    Number("infoDifficultyY", "Vertical offset", -20, -300, 300),
    Choice("infoDifficultyBox", "Text background", 1, { "None", "Box in the border color", "Box in custom color" }),
    Color("infoDifficultyBoxColor", "Text background color", "000000"),
}) do
    rule.enableKey = "infoDifficulty"
    B.Add(id, rule, "info_difficulty", "Difficulty")
end

local rules = NS.SuiteCatalog.minimap.rules
rules.showDayNight.hidden = not NS.Client.isForever or nil
for _, key in ipairs({ "specButton", "specShowSpec", "specShowLoot", "specCorner", "specSize", "specX", "specY" }) do
    rules[key].hidden = NS.Client.isForever or nil
    if key ~= "specButton" then rules[key].enableKey = "specButton" end
end
rules.specX.previewOnly, rules.specY.previewOnly = true, true
if NS.Client.isForever then
    -- Keep the Forever map in Blizzard's familiar upper-right position.
    -- Native capture would overwrite this first-run placement, so new profiles
    -- begin with an authored anchor and can still move the map in Edit Mode.
    rules.enabled.default = true
    rules.size.default = 205
    rules.point.default, rules.x.default, rules.y.default = 3, -20, -20
    rules.captured.default = true
    rules.infoClock.default = false -- The footer owns the clock.
    for key, value in pairs(NS.MinimapStylePresets[7]) do
        if rules[key] then rules[key].default = value end
    end
end
rules.captured.hidden = true
rules.iconSkin.hidden = true
-- The preview selection bar is the sole numeric editor for movable elements.
-- Keep these rules in the catalog for validation, presets and Edit Mode.
rules.x.previewOnly, rules.y.previewOnly = true, true
for key, rule in pairs(rules) do
    local prefix = key:match("^(.+)[XY]$")
    if prefix and type(rule.default) == "number" and (prefix:match("^info[%a]+$")
        or prefix:match("^button[%a]+$") or prefix == "zoomIn" or prefix == "zoomOut"
        or prefix == "drawer" or prefix == "landing" or prefix == "difficultyButton" or prefix == "dungeon"
        or prefix == "style") then rule.previewOnly = true end
end
rules.x.category, rules.y.category, rules.point.category = "advanced", "advanced", "advanced"
for _, key in ipairs({ "zoomInX", "zoomInY", "zoomOutX", "zoomOutY", "drawerX", "drawerY" }) do
    rules[key].category = "advanced"
end
rules.borderColor.disabledBy = "borderClassColor"
rules.landingIcon.requiresChoice = { key = "showLanding", values = { [1] = true, [2] = true } }
rules.zoomResetSeconds.enableKey = "scrollZoom"
rules.hoverWidth.enableKey, rules.hoverHeight.enableKey = "hoverResize", "hoverResize"
rules.drawerKeep.hidden = true
for _, key in ipairs({ "drawerRow", "drawerButtonSize", "drawerColumns", "drawerMouseover", "drawerKeep" }) do
    rules[key].enableKey = "collectButtons"
end
rules.infoDifficultyColor.disabledBy = "infoDifficultyColors"
rules.infoDifficultyBoxColor.requiresChoice = { key = "infoDifficultyBox", values = { [2] = true, [3] = true } }
for _, key in ipairs({ "infoGoodColor", "infoWarningColor", "infoBadColor" }) do rules[key].enableKey = "infoStatusColors" end
for _, key in ipairs({ "infoLocationZone", "infoLocationSubzone" }) do
    rules[key].requiresChoice = { key = "infoLocationSource", values = { [1] = true } }
end
rules.infoLocationBelow.requiresChoice = { key = "infoLocationSource", values = { [1] = true, [5] = true } }
local ART = NS.MinimapStyleTexture
rules.styleTexturePath.requiresChoice = { key = "styleTexture", values = { [ART.CUSTOM] = true } }
for _, key in ipairs({ "styleGlowColor", "styleGlowAlpha", "styleGlowScale" }) do rules[key].enableKey = "styleGlow" end
for _, key in ipairs({ "styleBackdropColor", "styleBackdropAlpha", "styleBackdropPadding" }) do rules[key].enableKey = "styleBackdrop" end
for _, key in ipairs({ "styleColor", "styleAlpha", "styleScale", "styleX", "styleY", "stylePlacement", "styleBlend", "styleRotation" }) do
    rules[key].requiresChoice = { key = "styleTexture", values = { [ART.ARCANE_RING] = true, [ART.EMBER_RING] = true,
        [ART.ASTRAL_RING] = true, [ART.STEEL_FRAME] = true, [ART.CUSTOM] = true, [ART.PARCHMENT_SCROLL] = true } }
end
