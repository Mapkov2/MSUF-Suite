local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local function Forever()
    if NS.Client.isForever then return true end
    return false, "Available only in WoW Forever"
end

B.Module("foreverWorldMap", {
    title = "World map information (Forever)",
    description = "Zone levels and travel markers on the world map. Click a marker to place a map pin.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", available = Forever,
})
B.Section("foreverWorldMap", "forever_world_map", "World map information", {
    B.Bool("zoneLevels", "Show zone level ranges", true),
    B.Tooltip(B.Bool("layerID", "Show observed layer ID"),
        "Uses nearby NPCs to estimate your layer. The ID can differ between players on the same layer."),
    B.Bool("transports", "Show boats, zeppelins and skycutters", true),
    B.Bool("flightPoints", "Show flight points", true),
    B.Bool("dungeonEntrances", "Show dungeon entrances and approaches", true),
    B.Bool("zoneRoutes", "Show roads to nearby zones", true),
    B.Bool("onlyOwnFaction", "Hide travel markers for the other faction", true),
    B.Number("pinSize", "Map marker size", 20, 12, 32),
})

B.Module("gatheringTooltips", {
    title = "Gathering tooltips (Forever)",
    description = "Show the required and current profession skill for known herbs and ore deposits.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", available = Forever,
})
B.Section("gatheringTooltips", "gathering_tooltips", "Gathering skill", {
    B.Bool("worldTooltips", "Show gathering skill on world objects", true),
    B.Bool("minimapTooltips", "Show gathering skill on minimap nodes", true),
    B.Bool("skillColors", "Color gathering information by skill margin", true),
})
