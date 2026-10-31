local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_QualityOfLife")
local function Forever()
    if NS.Client.isForever then return true end
    return false, "Available only in WoW Forever"
end
local function Retail()
    if not NS.Client.isForever then return true end
    return false, "Available only in Retail"
end
B.Module("questRewardValue", {
    title = "Quest reward value",
    description = "Mark the reward choice with the highest vendor value, including its stack size. Selection stays manual.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", available = Forever,
})
B.Section("questRewardValue", "quest_reward_value", "Quest reward value", {})
B.Module("mailRecipients", {
    title = "Mail recipients",
    description = [[Remember characters visited with this helper enabled.
Click a recipient to fill the address; right-click to hide or restore it.]],
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", available = Retail,
})
B.Section("mailRecipients", "mail_recipients", "Mail recipients", {
    B.Choice("sort", "Recipient order", 1, { "Name", "Level", "Recently visited" }),
    B.Number("minimumLevel", "Minimum character level", 1, 1, 100),
    B.Number("rows", "Visible recipients", 8, 3, 16),
    B.Bool("showHidden", "Show hidden recipients"),
})
B.Module("groupFinderTools", {
    title = "Group finder filters and statistics",
    description = "Apply saved native search filters with one click and count your Mythic+ application outcomes.",
    optIn = true, defaultEnabled = false, page = "suite_qualityOfLife", available = Retail,
    conflicts = { "PremadeGroupsFilter" },
})
B.Section("groupFinderTools", "group_finder_tools", "Search filters", {
    B.Bool("filters", "Show saved filter controls", true),
    B.Choice("difficulty", "Dungeon difficulty", 1, { "All difficulties", "Normal", "Heroic", "Mythic", "Mythic+" }),
    B.Number("minimumRating", "Minimum leader rating", 0, 0, 5000, 50),
    B.String("activities", "Dungeon activity group IDs (empty: all)", "", 400),
    B.Bool("needsRole", "Require room for your selected roles"),
    B.Bool("hasTank", "Require a tank"), B.Bool("hasHealer", "Require a healer"),
})
B.Section("groupFinderTools", "group_finder_statistics", "Application statistics", {
    B.Bool("statistics", "Count Mythic+ applications", true),
    B.Choice("scope", "Statistics scope", 1, { "Session", "Character", "Account" }),
})
B.Module("fishingComfort", {
    title = "Fishing comfort",
    description = [[A secure fishing key with optional rod, lure and a temporary sound profile.
Set Fishing and Apply fishing lure under Keybindings > MSUF Suite.
Each action requires your key press; interacting with the bobber stays manual.]],
    optIn = true, automation = true, defaultEnabled = false, page = "suite_qualityOfLife", available = Forever,
    cvars = { Sound_MusicVolume = true, Sound_AmbienceVolume = true, Sound_SFXVolume = true },
})
B.Section("fishingComfort", "fishing_comfort", "Fishing comfort", {
    B.String("rod", "Fishing rod item ID (empty: equipped rod)", "", 12),
    B.String("lure", "Lure item ID (separate key binding)", "", 12),
    B.Bool("audio", "Use fishing sound profile during your cast"),
    B.Number("music", "Fishing music volume (percent)", 10, 0, 100, 5),
    B.Number("ambience", "Fishing ambience volume (percent)", 20, 0, 100, 5),
    B.Number("effects", "Fishing effects volume (percent)", 100, 0, 100, 5),
})

NS.SuiteCatalog.fishingComfort.rules.rod.hidden = true
NS.SuiteCatalog.fishingComfort.rules.lure.hidden = true
NS.SuiteCatalog.groupFinderTools.rules.activities.hidden = true
NS.AddQoLVisualStyle("mailRecipients", "mail_recipients", "Mail recipients")
NS.AddQoLVisualStyle("groupFinderTools", "group_finder_tools", "Search filters")
