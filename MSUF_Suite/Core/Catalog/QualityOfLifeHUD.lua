local _, NS = ...
local B = NS.CatalogBuild
local Number, Bool, Choice = B.Number, B.Bool, B.Choice

B.Module("combatStatsHUD", {
    title = "Secondary stats",
    description = "A movable strip for critical strike, haste, mastery and versatility.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Secondary stats are available only in Retail" end
        return true
    end,
})
B.Section("combatStatsHUD", "secondary_stats", "Secondary stats", {
    Bool("showCrit", "Show critical strike", true),
    Bool("showHaste", "Show haste", true),
    Bool("showMastery", "Show mastery", true),
    Bool("showVersatility", "Show versatility", true),
    Bool("showLeech", "Add leech"),
    Bool("showAvoidance", "Add avoidance"),
    Bool("showSpeed", "Add speed (the stat, not running speed)"),
    Bool("combatOnly", "Show only in combat"),
    Number("width", "Display width", 300, 180, 480),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    B.Color("backgroundColor", "Background color", "10151b"),
    B.Color("accentColor", "Accent color", "d9ad60"),
    Number("opacity", "Background opacity (percent)", 90, 0, 100, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 0, -3000, 3000),
})
B.Section("combatStatsHUD", "stats_numbers", "Numbers, names and colors", {
    Choice("valueFormat", "Numbers", 1, { "Percentages", "Combat rating", "Both, on two lines" }),
    Choice("labelStyle", "Stat names", 1, { "Short", "Full" }),
    B.Color("leechColor", "Leech color", "9cd7c9"),
    B.Color("avoidanceColor", "Avoidance color", "c9b3f2"),
    B.Color("speedColor", "Speed color", "8cc4e8"),
})
B.Section("combatStatsHUD", "stats_fps", "Frame rate", {
    Choice("fps", "Frame rate readout", 1, { "Hidden", "Below the stats", "On its own" }),
    Number("fpsX", "FPS horizontal position", 0, -4000, 4000),
    Number("fpsY", "FPS vertical position", -55, -3000, 3000),
})
do
    local rules = NS.SuiteCatalog.combatStatsHUD.rules
    for _, key in ipairs({ "point", "x", "y", "fpsX", "fpsY" }) do rules[key].hidden = true end
    rules.leechColor.enableKey, rules.avoidanceColor.enableKey = "showLeech", "showAvoidance"
    rules.speedColor.enableKey = "showSpeed"
end

NS.AddQoLVisualStyle("combatStatsHUD", "secondary_stats", "Secondary stats")

-- The stats strip already exposes direct colors. Keep those existing values
-- as Custom, and let the menu's look bridge copy authored colors on selection.
local statsLook = NS.SuiteCatalog.combatStatsHUD.look
statsLook.presets = {}
for index, palette in pairs(NS.QoLVisualStyles) do
    if index ~= 5 then
        statsLook.presets[index] = { backgroundColor = palette.background, accentColor = palette.accent }
    end
end
statsLook.presets[6] = B.ClassPreset(statsLook.presets[4], { accentColor = "accent" })
statsLook.global = { 1, 2, 3, [5] = 4, [6] = 6 }
statsLook.visualKeys, statsLook.custom = { backgroundColor = true, accentColor = true }, 5
local statsRule = NS.SuiteCatalog.combatStatsHUD.rules.look
statsRule.default = 5
statsRule.max = 6
statsRule.choices[5] = "Custom"
statsRule.choices[6] = "Class Style"

B.Module("enemyCastStack", {
    title = "Dungeon cast stack", page = "suite_qualityOfLife", optIn = true, defaultEnabled = false,
    description = "Lists the casts of enemy nameplates in five-player dungeons, oldest first, with timers the game runs.",
    available = function()
        if NS.Client.isForever then return false, "Dungeon cast stack is available only in Retail" end
        return true
    end,
})
B.Section("enemyCastStack", "dungeon_casts", "Dungeon cast stack", {
    Number("listSize", "Casts listed at once", 4, 1, 12),
    Choice("castKinds", "Cast types", 1, { "Casts and channels", "Casts", "Channels" }),
    Bool("fadeMinor", "Fade casts the game does not mark as important"),
    Bool("onlyImportant", "Hide casts the game does not mark as important"),
    Bool("targetLine", "Show who each cast targets", true),
    Bool("showMarkers", "Show raid markers on the spell icon", true),
    Bool("readyStripe", "Mark interruptible casts while your interrupt is ready"),
    Choice("readyStyle", "Ready mark", 1, { "Stripe at the row's edge", "Whole bar in the ready color" }),
    Bool("dimOutOfRange", "Dim casts of enemies beyond your interrupt's range"),
    Number("interruptSpellID", "Interrupt spell ID (0 = detect)", 0, 0, 2000000),
    Choice("growth", "New casts appear", 1, { "Below the last", "Above the last" }),
    Number("width", "Display width", 280, 180, 550, 5),
    Number("rowHeight", "Row height", 30, 22, 52),
    Number("fontSize", "Text size", 12, 9, 18),
    Number("scale", "Scale (percent)", 100, 60, 160, 5),
    Number("x", "Horizontal position", 350, -4000, 4000),
    Number("y", "Vertical position", 0, -3000, 3000),
    B.Color("castColor", "Cast color", "b88a4a"),
    B.Color("priorityColor", "Important cast color", "d65a5a"),
    B.Color("lockedColor", "Uninterruptible cast color", "7d8290"),
    B.Color("stripeColor", "Ready mark color", "63c88a"),
})
do
    local rules = NS.SuiteCatalog.enemyCastStack.rules
    rules.x.hidden, rules.y.hidden = true, true
    rules.readyStyle.enableKey, rules.stripeColor.enableKey = "readyStripe", "readyStripe"
end
