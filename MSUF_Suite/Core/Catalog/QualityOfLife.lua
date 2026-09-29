local _, NS = ...
local B = NS.CatalogBuild
local Number, Bool, Choice, String = B.Number, B.Bool, B.Choice, B.String

-- This independent recent-cast display starts with a restrained game-like
-- palette, regardless of the profile's global Suite look.
B.Module("actionTracker", {
    title = "Action tracker",
    description = "A compact, movable history of your recent successful spells.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
})
NS.ActionTrackerLooks = {
    [1] = { panelColor = "171316", panelOpacity = 88, borderColor = "563938",
        accentColor = "d4a64c", textColor = "f2eeea" },
    [2] = { panelColor = "0a1220", panelOpacity = 90, borderColor = "41627a",
        accentColor = "57c7df", textColor = "f4f7fb" },
    [3] = { panelColor = "151719", panelOpacity = 90, borderColor = "575b58",
        accentColor = "b9ab86", textColor = "e9e9e4" },
    [4] = { panelColor = "14181b", panelOpacity = 90, borderColor = "9f8960",
        accentColor = "d8b66a", textColor = "f4f3eb" },
}
NS.SuiteCatalog.actionTracker.look = {
    key = "look", presets = NS.ActionTrackerLooks,
    visualKeys = { panelColor = true, panelOpacity = true, borderColor = true,
        accentColor = true, textColor = true }, custom = 5,
}
local actionLook = NS.ActionTrackerLooks[1]
B.Section("actionTracker", "action_tracker", "Recent actions", {
    Choice("look", "Style", 1, { "Classic UI", "Midnight Blue", "Midnight Dark", "MSUF Forever", "Custom" }),
    Choice("displayPreset", "Display preset", 1, { "Standard rows", "Icons only" }),
    Number("rows", "Visible actions", 5, 1, 8),
    Number("width", "Display width", 210, 150, 420, 5),
    Number("rowHeight", "Row height", 31, 24, 48),
    Number("rowGap", "Space between rows", 2, 0, 10),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Number("hideAfter", "Hide after inactivity (seconds; 0 = stay)", 15, 0, 60),
    Bool("showNames", "Show spell names", true),
    Bool("showChevron", "Show gold action markers", true),
    B.Font("font", "Font (empty: MSUF global font)"),
    Number("fontSize", "Spell name size", 12, 9, 20),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -40, -3000, 3000),
})
-- Position is owned by MSUF Edit Mode; these catalog rules remain available
-- for mover persistence, profile import and undo without duplicate sliders.
for _, key in ipairs({ "point", "x", "y" }) do
    NS.SuiteCatalog.actionTracker.rules[key].hidden = true
end
B.Section("actionTracker", "action_tracker_colors", "Colors", {
    B.Color("panelColor", "Row background", actionLook.panelColor),
    Number("panelOpacity", "Row opacity (percent)", actionLook.panelOpacity, 0, 100),
    B.Color("borderColor", "Row border", actionLook.borderColor),
    B.Color("accentColor", "Action marker", actionLook.accentColor),
    B.Color("textColor", "Spell name", actionLook.textColor),
}, { category = "advanced" })

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
    Bool("junkReport", "Report junk sale requests in chat", true),
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
    Bool("skipTrivial", "Leave trivial quests manual"),
    Bool("skipDaily", "Leave daily quests manual"),
    Bool("skipWeekly", "Leave weekly quests manual"),
    onlyIDs, skipIDs,
}, { category = "advanced" })
NS.SuiteCatalog.quests.rules.reward.enableKey = "complete"

B.Module("merchantLevel", {
    title = "Merchant item levels",
    description = "Show the item level on equipment sold by a merchant.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Merchant item levels are available only in Retail" end
        return true
    end,
})

B.Module("vaultSpec", {
    title = "Great Vault loot specialization",
    description = "Show your selected loot specialization in the Great Vault window.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "The Great Vault is available only in Retail" end
        return true
    end,
})

B.Module("tooltipIDs", {
    title = "Tooltip IDs",
    description = "Hold Alt to show item, spell and creature IDs on the main tooltip.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Tooltip IDs are available only in Retail" end
        return true
    end,
})

B.Module("itemCounts", {
    title = "Item counts in tooltips",
    description = "Show your owned item count, including bank and Warband bank, on item tooltips.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Item count tooltips are available only in Retail" end
        return true
    end,
})

B.Module("loadoutReminder", {
    title = "Talent and loot spec reminder",
    description = "Show the active talent build and loot specialization on ready checks or instance entry, with an optional saved expectation.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Talent loadouts are available only in Retail" end
        return true
    end,
})
B.Section("loadoutReminder", "loadout_reminder", "When to remind", {
    Bool("onReadyCheck", "On ready check", true),
    Bool("onInstanceEntry", "On instance entry", true),
    Bool("onlyMismatch", "Show only when saved selection differs"),
    Number("duration", "Display duration (seconds)", 8, 3, 20),
})
B.Section("loadoutReminder", "loadout_expectation", "Saved selection", {
    Number("expectedConfigID", "Expected talent build ID (0: any)", 0, 0, 100000000),
    Number("expectedLootSpecID", "Expected loot spec ID (0: any)", 0, 0, 100000),
    String("expectedCharacterGUID", "Expected character", "", 100),
}, { category = "advanced" })
NS.SuiteCatalog.loadoutReminder.rules.expectedCharacterGUID.hidden = true
NS.SuiteCatalog.loadoutReminder.rules.expectedConfigID.hidden = true
NS.SuiteCatalog.loadoutReminder.rules.expectedLootSpecID.hidden = true

B.Module("quietPopups", {
    title = "Quiet Blizzard popups",
    description = "Independently hide Talking Head, Boss Banner and Quick Join toasts while retaining Blizzard's underlying events.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
})
B.Section("quietPopups", "quiet_popups", "Popups", {
    Bool("talkingHead", "Hide Talking Head"),
    Bool("bossBanner", "Hide Boss Banner"),
    Bool("quickJoin", "Hide Quick Join toast"),
})

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
    Choice("point", "Screen anchor", 2, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -24, -3000, 3000),
})

-- Incoming whispers are only a cue: chat text can be secret in combat, so
-- this feature never tries to infer whether a message requests Innervate.
B.Module("innervateCue", {
    title = "Innervate whisper cue",
    description = "Alert a Druid to incoming combat whispers when Innervate may be ready. Optionally outline a chosen MSUF group frame.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Innervate whisper cue is available only in Retail" end
        local _, class = UnitClass("player")
        if not NS.Public(class) or class ~= "DRUID" then return false, "Available only to Druids" end
        return true
    end,
})
B.Section("innervateCue", "innervate_cue", "Innervate whisper cue", {
    Bool("openWorld", "Alert in the open world", true),
    Bool("party", "Alert in dungeons, delves and PvP", true),
    Bool("raid", "Alert in raids", true),
    Bool("sound", "Play a warning sound", true),
    Bool("highlightTarget", "Outline preferred target's MSUF group frame", true),
    String("targetName", "Preferred target (Name or Name-Realm)", "", 100),
    Number("duration", "Alert duration (seconds)", 4, 2, 10),
    Number("width", "Alert width", 280, 180, 500),
    Number("height", "Alert height", 54, 44, 90),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 180, -3000, 3000),
})
NS.SuiteCatalog.innervateCue.rules.targetName.enableKey = "highlightTarget"

-- The warning reads equipped durability only when its events fire. Its own
-- position is stored in the active Suite profile and exposed to MSUF Edit Mode.
B.Module("durabilityAlert", {
    title = "Low durability warning",
    description = "Show a movable warning when equipped gear needs repair. Hidden during combat.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
})
B.Section("durabilityAlert", "durability_warning", "Low durability warning", {
    Number("threshold", "Warn below (percent)", 40, 1, 99),
    Number("width", "Warning width", 250, 180, 500),
    Number("height", "Warning height", 62, 56, 90),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 180, -3000, 3000),
})

-- The shared battle-resurrection pool is only meaningful during an active
-- Mythic+ run or raid encounter. Blizzard owns the charge countdown itself.
B.Module("battleRes", {
    title = "Battle resurrection",
    description = "Show available shared battle resurrections and the next recharge in Mythic+ and raid encounters.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Shared battle resurrection charges are available only in Retail" end
        return true
    end,
})
B.Section("battleRes", "battle_res", "Battle resurrection", {
    Number("width", "Display width", 146, 146, 350),
    Number("height", "Display height", 44, 44, 80),
    Number("scale", "Scale (percent)", 100, 50, 200, 5),
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", 120, -3000, 3000),
})

-- The flight HUD is Retail-only and remains dormant until explicitly enabled.
B.Module("skyriding", {
    title = "Skyriding HUD",
    description = "Movable MSUF flight display for speed, Vigor, Second Wind and Whirling Surge.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife",
    available = function()
        if NS.Client.isForever then return false, "Skyriding is available only in Retail" end
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
    Choice("point", "Screen anchor", 5, NS.AnchorLabels),
    Number("x", "Horizontal position", 0, -4000, 4000),
    Number("y", "Vertical position", -145, -3000, 3000),
})
B.Section("skyriding", "flight_typography", "Text and bars", {
    B.Font("font", "Font (empty: MSUF global font)"),
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
NS.SuiteCatalog.skyriding.rules.font.defaultLabel = "MSUF global font (default)"
B.LinkFontShadow(NS.SuiteCatalog.skyriding.rules)
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
