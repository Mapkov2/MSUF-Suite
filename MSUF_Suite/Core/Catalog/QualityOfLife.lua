local _, NS = ...
local B = NS.CatalogBuild
local Number, Bool, Choice, String = B.Number, B.Bool, B.Choice, B.String

-- Comfort modules are opt-in: setup presets and shared profiles never turn on
-- spending, automation, or combat logging.
B.Module("qol", {
    title = "Merchant helpers",
    description = "Repair equipment and sell poor-quality items when a merchant opens. Hold Shift to skip selling.",
    optIn = true, page = "suite_qualityOfLife",
    conflicts = { "EnhanceQoLVendor", "Scrap", "SellJunk" },
})
-- The page switches Repair and Junk independently; the shared addon gate is
-- derived from those two feature switches rather than shown as a third toggle.
NS.SuiteCatalog.qol.rules.enabled.hidden = true
B.Section("qol", "repair", "Repair", {
    Bool("repair", "Automatically repair equipment"),
    Number("repairLimit", "Maximum repair cost (gold)", 100, 0, 10000, 10),
    Bool("guildRepair", "Use guild repair when available"),
    Bool("repairFallback", "Fall back to character money", true),
})
B.Section("qol", "junk", "Junk", {
    Bool("autoJunk", "Sell poor-quality items"),
    Bool("junkReport", "Report sold junk in chat", true),
})
NS.SuiteCatalog.qol.rules.repairLimit.enableKey = "repair"
NS.SuiteCatalog.qol.rules.guildRepair.enableKey = "repair"
NS.SuiteCatalog.qol.rules.repairFallback.enableKey = "guildRepair"
NS.SuiteCatalog.qol.rules.junkReport.enableKey = "autoJunk"

B.Module("quests", {
    title = "Quest helpers",
    description = "Accept and turn in quests automatically. Hold Shift to pause. Reward choices and quests with a money cost stay manual.",
    optIn = true, page = "suite_qualityOfLife",
})
B.Section("quests", "automation", "Quest actions", {
    Bool("accept", "Automatically accept offered quests"),
    Bool("complete", "Automatically complete ready quests"),
    Bool("reward", "Collect rewards without a choice"),
    Bool("gossip", "Select offered or completed quests in dialogue"),
})
local onlyIDs = String("onlyIDs", "Only these quest IDs (empty: all)", "", 1600)
onlyIDs.ids = true
local skipIDs = String("skipIDs", "Never automate these quest IDs", "", 1600)
skipIDs.ids = true
B.Section("quests", "filters", "Quest filters", {
    Bool("firstTime", "Only quests not yet completed on this account"),
    onlyIDs, skipIDs,
}, { category = "advanced" })
NS.SuiteCatalog.quests.rules.reward.enableKey = "complete"

B.Module("loot", {
    title = "Fast loot",
    description = "Collect all unlocked loot slots at once. Blizzard's own Auto Loot setting stays unchanged; roll decisions stay manual.",
    optIn = true, page = "suite_qualityOfLife",
})
NS.SuiteCatalog.loot.rules.enabled.hidden = true
B.Section("loot", "collection", "Collecting loot", {
    Bool("quickLoot", "Collect available loot automatically"),
    Choice("lootModifier", "Collection rule", 2, { "Always", "Except while holding Shift", "Only while holding Shift" }),
})
B.Section("loot", "history", "Loot history", {
    Bool("manageHistory", "Customize loot history visibility"),
    Choice("historyMode", "Loot history behavior", 1, { "Hide automatically", "Close after a delay" }),
    Number("historyDelay", "Close after (seconds)", 5, 1, 30),
})
NS.SuiteCatalog.loot.rules.lootModifier.enableKey = "quickLoot"
NS.SuiteCatalog.loot.rules.historyMode.enableKey = "manageHistory"
NS.SuiteCatalog.loot.rules.historyDelay.enableKey = "manageHistory"

B.Module("combatLog", {
    title = "Automatic combat logging",
    description = "Start the combat log in the instance types you choose. A log you started manually stays on when you leave.",
    optIn = true, page = "suite_qualityOfLife",
    available = function()
        if type(LoggingCombat) ~= "function" or type(GetInstanceInfo) ~= "function" then
            return false, "Combat logging is unavailable on this client"
        end
        return true
    end,
})
B.Section("combatLog", "log_dungeons", "Dungeons", {
    Bool("dungeonNormal", "Normal dungeons"),
    Bool("dungeonHeroic", "Heroic dungeons"),
    Bool("dungeonMythic", "Mythic dungeons"),
    Bool("dungeonMythicPlus", "Mythic+ dungeons", true),
    Bool("dungeonTimewalking", "Timewalking dungeons"),
})
B.Section("combatLog", "log_raids", "Raids", {
    Bool("raidLFR", "Raid Finder"),
    Bool("raidNormal", "Normal raids", true),
    Bool("raidHeroic", "Heroic raids", true),
    Bool("raidMythic", "Mythic raids", true),
    Bool("raidTimewalking", "Timewalking raids"),
})
B.Section("combatLog", "log_other", "Other instances", {
    Bool("pvp", "Battlegrounds and arenas"),
    Bool("scenario", "Scenarios"),
    Bool("delve", "Delves"),
})
B.Section("combatLog", "log_exit", "When leaving", {
    Choice("stopPolicy", "After leaving selected content", 2,
        { "Stop immediately", "Stop after 30 seconds", "Leave logging on" }),
    Bool("chatNotice", "Show a chat message when MSUF changes logging"),
})

-- The XP display shares the Quality of Life addon but has its own independent
-- profile switch, runtime and Edit Mode element.
B.Module("xpBar", {
    title = "Experience bar",
    description = "Movable experience bar with rested XP, session gain, XP per hour and time to level.",
    optIn = true, page = "suite_qualityOfLife",
    available = function()
        if type(UnitXP) ~= "function" or type(UnitXPMax) ~= "function" or type(UnitLevel) ~= "function" then
            return false, "Experience data is unavailable on this client"
        end
        return true
    end,
})
-- The XP bar paints its look itself; it has no Custom choice.
NS.SuiteCatalog.xpBar.look = { key = "look", global = true }
B.Section("xpBar", "xp_bar", "Experience bar", {
    Choice("look", "MSUF style", NS.Client.isForever and 3 or 2,
        { "Midnight Blue", "Midnight Dark", "MSUF Forever" }),
    Number("width", "Bar width", 400, 220, 800, 5),
    Number("height", "Bar height", 18, 8, 40),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Bool("showSegments", "Show XP bar divisions", true),
    Bool("showRested", "Show rested XP", true),
    Bool("showSession", "Show session XP", true),
    Bool("showRate", "Show XP per hour", true),
    Bool("showETA", "Show time to level", true),
    Bool("hideAtMax", "Hide at maximum level", true),
    Choice("point", "Screen anchor", 2,
        { "Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right" }),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -24, -3000, 3000),
})

-- The flight HUD is Retail-only and remains dormant until explicitly enabled.
B.Module("skyriding", {
    title = "Skyriding HUD",
    description = "Movable MSUF flight display for speed, Vigor, Second Wind and Whirling Surge.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if not NS.Client.isMainline or NS.Client.isForever then
            return false, "Skyriding is available only in Retail"
        end
        if not (C_PlayerInfo and type(C_PlayerInfo.GetGlidingInfo) == "function"
            and C_Spell and type(C_Spell.GetSpellCharges) == "function") then
            return false, "Skyriding data is unavailable on this client"
        end
        return true
    end,
})
NS.SkyridingLookPresets = {
    [1] = { panelColor = "0a1220", borderColor = "41627a", trackColor = "102033",
        accentColor = "57c7df", windColor = "558bdd", textColor = "f4f7fb",
        mutedColor = "aab5c2", thrillColor = "d8b66a" },
    [2] = { panelColor = "151719", borderColor = "575b58", trackColor = "202326",
        accentColor = "b9ab86", windColor = "8b9cb2", textColor = "e9e9e4",
        mutedColor = "b9bdb9", thrillColor = "e2c57c" },
    [3] = { panelColor = "14181b", borderColor = "9f8960", trackColor = "20272a",
        accentColor = "d8b66a", windColor = "668db8", textColor = "f4f3eb",
        mutedColor = "d4dce2", thrillColor = "f0d284" },
}
NS.SkyridingLookVisualKeys = {
    panelColor = true, borderColor = true, trackColor = true, accentColor = true,
    windColor = true, textColor = true, mutedColor = true, thrillColor = true,
    panelOpacity = true, trackOpacity = true, borderSize = true,
}
NS.SuiteCatalog.skyriding.look = {
    key = "look", presets = NS.SkyridingLookPresets, visualKeys = NS.SkyridingLookVisualKeys,
    custom = 4, global = true,
}
local initialSky = NS.SkyridingLookPresets[1]
B.Section("skyriding", "flight_hud", "Skyriding HUD", {
    Choice("look", "MSUF style", 1, { "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom" }),
    Number("width", "HUD width", 350, 220, 600, 5),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Bool("airborneOnly", "Show only while airborne"),
    Bool("showSpeed", "Show speed and Thrill threshold", true),
    Bool("showVigor", "Show Vigor charges", true),
    Bool("showSecondWind", "Show Second Wind charges", true),
    Bool("showWhirlingSurge", "Show Whirling Surge cooldown", true),
    Number("speedMax", "Speed bar maximum (percent)", 1200, 500, 2000, 50),
    Number("thrillSpeed", "Thrill speed (percent)", 830, 300, 1500, 10),
    Choice("point", "Screen anchor", 5,
        { "Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right" }),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -145, -3000, 3000),
})
B.Section("skyriding", "flight_typography", "Text and bars", {
    B.Font("font", "Font (MSUF Expressway by default)"),
    Number("fontSize", "Font size", 11, 9, 18),
    Choice("fontOutline", "Text outline", 1, { "None", "Outline", "Thick outline" }),
    Choice("fontRendering", "Font rendering", 3, { "Smooth", "Sharp / pixel", "Slug" }),
    Bool("fontShadow", "Text shadow"),
    Number("fontShadowOpacity", "Shadow opacity (percent)", 100, 20, 100, 5),
    Choice("fontShadowDistance", "Shadow distance", 1, { "1 px", "2 px" }),
    B.Texture("barTexture", "Bar texture"),
    Number("barHeight", "Bar height", 10, 6, 18),
    Number("rowGap", "Space between rows", 0, 0, 12),
})
NS.SuiteCatalog.skyriding.rules.font.defaultLabel = "MSUF Expressway (default)"
local skyTextRules = NS.SuiteCatalog.skyriding.rules
skyTextRules.fontShadow.requiresChoice = { key = "fontRendering", values = { [1] = true, [2] = true } }
for _, key in ipairs({ "fontShadowOpacity", "fontShadowDistance" }) do
    skyTextRules[key].enableKey = "fontShadow"
    skyTextRules[key].requiresChoice = skyTextRules.fontShadow.requiresChoice
end
B.Section("skyriding", "flight_colors", "Colors and panel", {
    B.Color("panelColor", "Panel color", initialSky.panelColor),
    Number("panelOpacity", "Panel opacity (percent)", 94, 0, 100),
    B.Color("borderColor", "Border color", initialSky.borderColor),
    Number("borderSize", "Border thickness", 1, 0, 3),
    B.Color("trackColor", "Empty bar color", initialSky.trackColor),
    Number("trackOpacity", "Empty bar opacity (percent)", 100, 0, 100),
    B.Color("accentColor", "Vigor and speed color", initialSky.accentColor),
    B.Color("windColor", "Second Wind color", initialSky.windColor),
    B.Color("thrillColor", "Thrill speed color", initialSky.thrillColor),
    B.Color("textColor", "Value text color", initialSky.textColor),
    B.Color("mutedColor", "Label text color", initialSky.mutedColor),
})
NS.SuiteCatalog.skyriding.rules.speedMax.enableKey = "showSpeed"
NS.SuiteCatalog.skyriding.rules.thrillSpeed.enableKey = "showSpeed"
