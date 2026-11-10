local _, NS = ...
local Build = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Bool, Number, Choice, Color = Build.Bool, Build.Number, Build.Choice, Build.Color

local spec = Build.Module("navigation", {
    title = "Navigation & waypoints", page = "suite_qualityOfLife", optIn = true, defaultEnabled = false,
    description = "Follow quests, map pins and saved places with a world marker, destination card and direction arrow.",
    available = function()
        return C_Navigation ~= nil, "World navigation is not available on this client."
    end,
})
Build.Section("navigation", "navigation_basics", "Navigation", {
    Choice("look", "Navigation preset", 1, { "Balanced", "Compact", "Atmospheric", "Custom" }),
    Choice("display", "World marker display", 1, { "Automatic", "Waypoint only", "Destination card only" }),
    Number("nearDistance", "Show destination card within (yards)", 80, 10, 500, 5),
    Number("hideDistance", "Hide within (yards, 0 = never)", 0, 0, 50),
    Bool("navigator", "Show direction when the destination is off-screen", true),
    Choice("units", "Distance units", 1, { "Yards", "Meters" }),
    Bool("showDistance", "Show destination distance", true),
    Bool("showETA", "Show estimated travel time"),
    Bool("showName", "Show destination name", true),
    Bool("showInfo", "Show destination details", true),
    Bool("showInCombat", "Show navigation in combat", true),
    Bool("showWithHiddenUI", "Show navigation when the interface is hidden"),
    Bool("fadeOnHover", "Fade navigation under the pointer", true),
    Bool("rightClickClear", "Right-click navigation to stop tracking"),
})
Build.Section("navigation", "navigation_appearance", "Appearance", {
    Number("markerSize", "Waypoint symbol size", 34, 16, 80),
    Choice("shape", "Waypoint symbol shape", 1, { "Diamond", "Circle" }),
    Bool("beam", "Show waypoint light beam", true),
    Number("beamHeight", "Light beam height", 180, 40, 500, 5),
    Number("beamOpacity", "Light beam opacity (percent)", 45, 0, 100, 5),
    Number("opacity", "Navigation opacity (percent)", 95, 10, 100, 5),
    Number("cardWidth", "Destination card width", 280, 180, 480, 10),
    Number("fontSize", "Navigation text size", 14, 10, 24),
    Build.Font("font", "Navigation font"),
    Bool("worldScale", "Scale the waypoint with its distance"),
    Number("minScale", "Minimum waypoint scale (percent)", 65, 30, 100, 5),
    Number("maxScale", "Maximum waypoint scale (percent)", 120, 100, 180, 5),
    Number("navigatorX", "Direction display horizontal offset", 0, -600, 600),
    Number("navigatorY", "Direction display vertical offset", 0, -400, 400),
    Bool("dynamicOffset", "Use adaptive direction spacing"),
    Color("questColor", "Active quest color", "f2cf73"),
    Color("completeColor", "Completed quest color", "8bd6a3"),
    Color("repeatColor", "Repeatable quest color", "80bfff"),
    Color("importantColor", "Campaign quest color", "e9a7ff"),
    Color("pinColor", "Map pin color", "8ecfff"),
    Color("beamColor", "Light beam color", "b5e1ff"),
    Color("backgroundColor", "Destination card background", "111820"),
})
Build.Section("navigation", "navigation_sources", "Destinations & maps", {
    Bool("trackQuests", "Follow the focused quest", true),
    Bool("trackerLinks", "Offer navigation in the objective tracker", true),
    Bool("trackPins", "Follow map waypoints", true),
    Bool("trackPOIs", "Follow tracked points of interest", true),
    Bool("mapPins", "Show saved places on the world map", true),
    Bool("minimapPins", "Show nearby saved places on the minimap", true),
    Bool("minimapPlacement", "Ctrl-click the minimap to save a place"),
    Bool("autoTrackPins", "Follow a newly placed map pin", true),
    Bool("autoTrackLinks", "Follow a map pin opened from chat"),
    Bool("autoNext", "Continue to the next saved route stop on arrival"),
    Number("pinSize", "Saved map pin size", 20, 12, 32),
})
Build.Section("navigation", "navigation_audio", "Sounds", {
    Bool("sound", "Enable navigation sounds"),
    Bool("soundTarget", "Sound when the destination changes", true),
    Bool("soundNear", "Sound on entering the destination area", true),
    Bool("soundLeave", "Sound on leaving the destination area"),
    Number("soundDistance", "Sound proximity (yards)", 30, 5, 200, 5),
    Number("soundFile", "Custom navigation sound file ID (0 = default)", 0, 0, 10000000),
})
Build.Section("navigation", "navigation_integrations", "Guides & routes", {
    Bool("guideTomTom", "Follow TomTom destinations"),
    Bool("guideRestedXP", "Follow RestedXP destinations"),
    Bool("guideAPR", "Follow Azeroth Pilot Reloaded destinations"),
    Bool("guideMapzeroth", "Follow Mapzeroth travel steps"),
    Bool("replaceManual", "Let guide updates replace a manually selected destination"),
    Choice("pathfinding", "Route planning", 1, { "Direct destination", "FarstriderLib", "Mapzeroth" }),
})
spec.look = {
    key = "look", custom = 4,
    presets = {
        [1] = { markerSize = 34, beam = true, beamHeight = 180, beamOpacity = 45, fontSize = 14, opacity = 95 },
        [2] = { markerSize = 24, beam = false, beamHeight = 120, beamOpacity = 25, fontSize = 12, opacity = 90 },
        [3] = { markerSize = 42, beam = true, beamHeight = 300, beamOpacity = 60, fontSize = 16, opacity = 100 },
    },
    visualKeys = { markerSize = true, beam = true, beamHeight = true, beamOpacity = true, fontSize = true, opacity = true },
}
for _, key in ipairs({ "beamHeight", "beamOpacity", "beamColor" }) do spec.rules[key].enableKey = "beam" end
for _, key in ipairs({ "minScale", "maxScale" }) do spec.rules[key].enableKey = "worldScale" end
for _, key in ipairs({ "soundTarget", "soundNear", "soundLeave", "soundDistance", "soundFile" }) do
    spec.rules[key].enableKey = "sound"
end
Build.Tooltip(spec.rules.guideTomTom,
    "Also follows Dugi and SilverDragon when they send their destinations through TomTom. Native map pins use Follow map waypoints.")
Build.Tooltip(spec.rules.pathfinding, "Optional route providers must be installed separately. Plan the selected destination with Plan current route.")
