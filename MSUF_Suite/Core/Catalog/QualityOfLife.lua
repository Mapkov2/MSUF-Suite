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
    Choice("point", "Screen anchor", 8,
        { "Top left", "Top", "Top right", "Left", "Center", "Right", "Bottom left", "Bottom", "Bottom right" }),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 148, -3000, 3000),
})
