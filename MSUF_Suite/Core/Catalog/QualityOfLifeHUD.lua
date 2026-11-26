local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local Number, Bool, Choice = B.Number, B.Bool, B.Choice



B.Module("hudVisibility", {
    title = "HUD visibility", description = "Use the same dimming rules for selected HUD modules.",
    optIn = true, defaultEnabled = false, page = "suite_hud",
})
B.Section("hudVisibility", "hud_visibility", "HUD visibility", {
    Choice("mode", "Show HUD at full opacity", 3, { "With a target", "In combat", "In combat or with a target", "Always" }),
    Bool("worldOnly", "Dim only in the open world", true),
    Bool("onTaxi", "Dim while on a flight path", false),
    Bool("hover", "Reveal dimmed bars on hover where supported", true),
    Number("opacity", "Dimmed opacity (percent)", 25, 5, 100, 5),
    Number("delay", "Delay before dimming (seconds)", 2, 0, 20),
    Bool("actionBars", "Include Suite action bars", true),
    Bool("cooldownManager", "Include the Cooldown Manager", true),
    Bool("dataTexts", "Include data bars", true),
    Bool("procAlerts", "Include proc alerts", false),
    Bool("playerBuffGroups", "Include player buff groups", false),
})

B.Module("procAlerts", {
    title = "Proc alerts", description = "Show a separate cue when the game highlights a spell.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", editElement = "alerts",
    available = function()
        if NS.Client.SupportsEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            and NS.Client.SupportsEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE") then return true end
        return false, "Spell glow events are unavailable on this client"
    end,
})
B.Section("procAlerts", "proc_alerts", "Proc alerts", {
    Choice("mode", "Spells to show", 1, { "All spell glows", "Selected spell IDs" }),
    B.String("spells", "Spell IDs separated by commas", "", 480),
    B.Color("color", "Proc alert color", "f5bf67"),
    Bool("pulse", "Pulse while the spell glows", true),
    Number("pulseSpeed", "Pulse duration (milliseconds)", 440, 200, 1200, 20),
    Bool("auraDetails", "Show readable aura timers and stacks", true),
    Number("minimumStacks", "Minimum stacks when count is readable", 0, 0, 40),
    B.String("auraOverrides", "Spell-to-buff IDs (spell:buff, separated by commas)", "", 720),
    Bool("sound", "Play a sound when a proc appears", false),
    Number("scale", "Scale (percent)", 100, 60, 175, 5),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 170, -3000, 3000),
})
do
    local rules = NS.SuiteCatalog.procAlerts.rules
    rules.spells.spells = true
    rules.pulseSpeed.enableKey = "pulse"
    rules.minimumStacks.enableKey, rules.auraOverrides.enableKey = "auraDetails", "auraDetails"
    rules.x.hidden, rules.y.hidden = true, true
end


B.Module("targetDotEstimate", {
    title = "Target DoT estimate",
    description = "Shade estimated remaining damage on the target's health bar when the game provides readable aura and health data.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if not NS.Client.isForever then return false, "Target DoT estimates are available only in WoW Forever" end
        if not (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_UnitAuras
            and C_UnitAuras.GetUnitAuras and canaccesstable) then return false, "Native aura data is unavailable on this client" end
        if not (NS.HostBridge.HasTargetHealthAnchor and NS.HostBridge.HasTargetHealthAnchor()) then
            return false, "Update Midnight Simple Unit Frames for this feature"
        end
        local locale = GetLocale()
        if locale == "deDE" or locale == "enUS" or locale == "enGB" then return true end
        return false, "Target DoT estimates require an English or German game client"
    end,
})

B.Section("targetDotEstimate", "target_dot_estimate", "Target DoT estimate", {
    Number("opacity", "Prediction opacity (percent)", 55, 15, 100, 5),
})

B.Module("castEnhancements", {
    title = "Castbar enhancements", description = "Add castbars to party frames and set colors for individual player spells.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if not (NS.HostBridge.CastEnhancements and NS.HostBridge.CastEnhancements()) then
            return false, "Update Midnight Simple Unit Frames for this feature"
        end
        if UnitCastingDuration and UnitChannelDuration and Enum.StatusBarTimerDirection and Enum.StatusBarInterpolation then
            return true
        end
        return false, "Native cast timers are unavailable on this client"
    end,
})
B.Section("castEnhancements", "cast_extras", "Party castbars and spell colors", {
    Bool("party", "Show party member castbars", true),
    Choice("partyPosition", "Party castbar position", 1, { "Below the frame", "Above the frame", "Along the bottom edge" }),
    Number("partyHeight", "Party castbar height", 13, 8, 30),
    B.Color("partyColor", "Party castbar color", "629bc0"),
    Bool("partyMotion", "Animate castbar appearance", false),
    B.String("playerColors", "Player spell colors (spell ID:hex color)", "", 1800),
})

B.Module("combatStatsHUD", {
    title = "Secondary stats",
    description = "A movable strip for critical strike, haste, mastery and versatility.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Secondary stats are available only in Retail" end
        return true
    end,
    editElement = "combat",
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
    Number("fontSize", "Text size", 15, 10, 24),
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
    editElement = "casts",
})
B.Section("enemyCastStack", "dungeon_casts", "Dungeon cast stack", {
    Bool("glossEnabled", "Glossy bars and icons"),
    Number("glossStrength", "Gloss strength (percent)", 50, 0, 100, 5),
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
NS.AddQoLTextStyle("enemyCastStack", "dungeon_casts", "Dungeon cast stack", 70)
do
    local rules = NS.SuiteCatalog.enemyCastStack.rules
    rules.glossStrength.enableKey = "glossEnabled"
    rules.x.hidden, rules.y.hidden = true, true
    rules.readyStyle.enableKey, rules.stripeColor.enableKey = "readyStripe", "readyStripe"
end
