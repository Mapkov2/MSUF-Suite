local _, NS = ...
local B = NS.CatalogBuild.ForAddon("MSUF_Suite_BuffReminders")
local Bool, Number, Choice, String, Color = B.Bool, B.Number, B.Choice, B.String, B.Color

B.Module("buffReminders", {
    title = "Buff reminders",
    description = "Clickable reminders for missing personal buffs, chosen aura spells, consumables and weapon enchants. Checks only while out of combat.",
    optIn = true, page = "suite_buffReminders",
    conflicts = { "EllesmereUIAuraBuffReminders" },
    summary = "size columns remindBeforeMinutes instancesOnly point classBuff",
})

local id = "buffReminders"
-- The Warlock demons the demon check knows: their summon spells and the
-- creature family UnitCreatureFamily reports for them (Imp 23, Voidwalker 16,
-- Felhunter 15, Succubus 17, Felguard 29). Other families are never judged.
NS.BuffReminderDemons = {
    { key = "demonImp", label = "Imp", spells = { 688 }, family = 23 },
    { key = "demonVoidwalker", label = "Voidwalker", spells = { 697 }, family = 16 },
    { key = "demonFelhunter", label = "Felhunter", spells = { 691 }, family = 15 },
    { key = "demonSayaad", label = "Succubus or Incubus", spells = { 366222, 712, 713 }, family = 17 },
    { key = "demonFelguard", label = "Felguard", spells = { 30146 }, family = 29 },
}
-- A global look recolors the icon border from its palette.
NS.SuiteCatalog[id].look = {
    extra = function(values, lookIndex)
        values.borderColor = NS.DataTextLooks[lookIndex].border
    end,
}
B.Section(id, "tracking", "What to remind", {
    Bool("classBuff", "Remind me of my known class raid buff", true),
    Bool("groupBuff", "Remind me when others need my group buff", false),
    Bool("otherClassBuffs", "Remind me of missing buffs from classes in my group", false),
    Bool("petPassiveWarning", "Tell me when my pet is set to passive", false),
    Bool("healthstoneFromWarlock", "Healthstone check: none in my bags while a Warlock is grouped with me", false),
    Bool("soulstoneOnAlly", "Tell me while my Soulstone is on nobody in the group", false),
    Bool("beaconOnAlly", "Tell me while one of my Beacons is on nobody in the group", false),
    Bool("campfireBuff", "Tell me while my campfire buff is missing (Forever)", false),
    -- A potion for maps the player picks; Inky Black Potion (item 124640) by default.
    Bool("mapPotion", "Remind me of a potion on maps I pick", false),
    String("mapPotionItem", "Potion for those maps (item ID)", "124640", 10),
    String("mapPotionMaps", "Maps for the potion (map IDs, comma separated)", "", 500),
    String("spellIDs", "Additional self-buff spell IDs", "", 240),
    String("items", "Consumables (item ID:aura ID)", "", 320),
    String("mainHandItem", "Main-hand enchant item ID", "", 10),
    String("offHandItem", "Off-hand enchant item ID", "", 10),
})
B.Section(id, "demons", "Warlock demon choice", {
    Bool("demonChoiceWarning", "Tell me when my demon is not one of the demons below", false),
})
for _, demon in ipairs(NS.BuffReminderDemons) do
    B.Add(id, Bool(demon.key, demon.label, true), "demons")
end
B.Section(id, "recommended", "Recommended consumables (Mainline)", {
    Bool("autoRoguePoisons", "Rogue poisons for my specialization", true),
    Bool("autoFlask", "Flask from my bags", true),
    Bool("autoFood", "Food buff (Well Fed)", true),
    Bool("autoRune", "Augment rune from my bags", true),
    Bool("autoWeapon", "Weapon oils for equipped weapons", true),
    Bool("restockNotice", "Show a gray reminder when none is left in my bags", false),
    String("flaskChoice", "Flask to use first (item ID)", "", 10),
    String("foodChoice", "Food to eat first (item ID)", "", 10),
    String("runeChoice", "Augment rune to use first (item ID)", "", 10),
    String("oilChoice", "Weapon oil to use first (item ID)", "", 10),
}, { requires = "modernEquipment" })
B.Section(id, "visibility", "When to show", {
    Bool("instancesOnly", "Show only in dungeons and raids", false),
    Bool("hideMounted", "Hide while mounted", true),
    Number("remindBeforeMinutes", "Remind before expiration (minutes)", 5, 0, 60),
    -- Before a keystone starts, buffs can be asked to last the dungeon's own
    -- timer (C_ChallengeMode) or a number of minutes.
    Choice("keystoneCover", "Before a keystone starts, buffs must last", 1,
        { "The normal warning time", "The dungeon's timer", "The minutes below" }),
    Number("keystoneMinutes", "Minutes buffs must last before a keystone", 30, 1, 120),
    Bool("showWorld", "Open world", true),
    Bool("showDungeonNormal", "Normal dungeons", true),
    Bool("showDungeonHeroic", "Heroic dungeons", true),
    Bool("showDungeonMythic", "Mythic dungeons", true),
    Bool("showMythicPlus", "Mythic+ dungeons", true),
    Bool("showRaidNormal", "Normal and legacy raids", true),
    Bool("showRaidHeroic", "Heroic raids", true),
    Bool("showRaidMythic", "Mythic raids", true),
    Bool("showRaidFinder", "Raid Finder", true),
    Bool("showTimewalking", "Timewalking", true),
    Bool("showScenarios", "Scenarios and delves", true),
})
B.Section(id, "readycheck", "Ready check", {
    Bool("readyCheckMana", "Ready checks: show my healer mana when it is low", false),
    Number("readyCheckManaPercent", "Low means below (percent of mana)", 70, 1, 100),
    Number("readyCheckDuration", "Show the mana note for (seconds)", 8, 3, 30),
})
local AREAS = {
    { "showWorld", "Open world" }, { "showDungeonNormal", "Normal dungeons" },
    { "showDungeonHeroic", "Heroic dungeons" }, { "showDungeonMythic", "Mythic dungeons" },
    { "showMythicPlus", "Mythic+ dungeons" }, { "showRaidNormal", "Normal and legacy raids" },
    { "showRaidHeroic", "Heroic raids" }, { "showRaidMythic", "Mythic raids" },
    { "showRaidFinder", "Raid Finder" }, { "showTimewalking", "Timewalking" },
    { "showScenarios", "Scenarios and delves" },
}
for _, group in ipairs({ { "class", "Class and group reminders" }, { "personal", "Personal spell reminders" },
    { "consumable", "Consumable and weapon reminders" } }) do
    local rules = {
        Choice(group[1] .. "_glow", "Reminder border effect", 1, { "Global setting", "Normal", "Highlight", "Pulse" }),
        Color(group[1] .. "_glowColor", "Reminder highlight color", "ffd200"),
    }
    for _, area in ipairs(AREAS) do rules[#rules + 1] = Bool(group[1] .. "_" .. area[1], area[2], true) end
    B.Section(id, group[1] .. "Visibility", group[2], rules)
end
B.Section(id, "appearance", "Icons", {
    Choice("reminderSound", "New reminder sound", 1, { "None", "Raid warning", "Ready check", "Quest log" }),
    Choice("reminderSoundChannel", "Reminder sound channel", 1, { "Master", "Sound effects", "Dialog" }),
    Choice("reminderGlow", "Reminder border effect", 1, { "Normal", "Highlight", "Pulse" }),
    Color("reminderGlowColor", "Reminder highlight color", "ffd200"),
    Number("size", "Icon size", 38, 22, 72),
    Number("spacing", "Icon spacing", 5, 0, 20),
    Number("columns", "Icons per row", 6, 1, 12),
    Color("borderColor", "Border color", NS.Client.isForever and "d8b66a" or "e8b855"),
    B.Font("countFont", "Item count font"),
    Number("countSize", "Item count size", 12, 8, 32),
    Choice("countPosition", "Item count position", 9, NS.AnchorLabels),
    Number("countX", "Item count horizontal offset", -2, -40, 40),
    Number("countY", "Item count vertical offset", 2, -40, 40),
})
B.Section(id, "position", "Position", {
    Bool("followCursor", "Keep the reminders beside the cursor outside combat", false),
    Number("cursorOffsetX", "Distance from the cursor, horizontal", 24, -300, 300),
    Number("cursorOffsetY", "Distance from the cursor, vertical", 24, -300, 300),
    Choice("point", "Screen anchor", 2, { "Center", "Top" }),
    Number("x", "Horizontal offset", 0, -4000, 4000),
    Number("y", "Vertical offset", -145, -3000, 3000),
})

local rules = NS.SuiteCatalog[id].rules
rules.spellIDs.spells = true
rules.mainHandItem.items = true
rules.offHandItem.items = true
rules.mapPotionItem.items = true
rules.keystoneCover.hidden = NS.Client.isForever or nil
rules.keystoneMinutes.hidden = NS.Client.isForever or nil
rules.keystoneMinutes.requiresChoice = { key = "keystoneCover", values = { [3] = true } }
for _, key in ipairs({ "flaskChoice", "foodChoice", "runeChoice", "oilChoice" }) do
    rules[key].items = true
end
