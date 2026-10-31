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
-- The class reminders: the buffs a class and specialization keep up. The
-- runtime (Entries.lua) compiles them; retail and forever hold the behaviour
-- on each client, and no table there means the reminder does not exist on it.
-- A plan is one of three kinds:
--   aura  a spell whose aura sits on the player; casts are tried in order
--         (prefer[specID] first), and any listed aura satisfies the reminder;
--   imbue weapon or shield enchants, one rule per slot: { slot, spell, equip,
--         specs }, where equip is the item the slot must hold;
--   ally  the player's own aura on a group member (casts, auras and specs as
--         for aura; the icon casts on the player's target).
-- specs is a set of specialization IDs. WoW Forever keeps only the reminders
-- whose spells have one rank (Shadowform, the warrior stances).
local PALADIN_AURAS = { 465, 317920, 32223 }
local WARRIOR_STANCES = { 386164, 386208, 386196 }
local FOREVER_STANCES = { 2457, 71, 2458 }
local SHAMAN_SHIELDS = { 192106, 52127 }
local ELEMENTAL, ENHANCEMENT, RESTORATION = { [262] = true }, { [263] = true }, { [264] = true }
local SHIELD_SPECS = { [262] = true, [263] = true }
NS.BuffReminderClassReminders = {
    { key = "classShadowform", label = "Priest: Shadowform", class = "PRIEST",
        retail = { kind = "aura", casts = { 232698 }, auras = { 232698, 194249 } },
        forever = { kind = "aura", casts = { 15473 }, auras = { 15473 } } },
    { key = "classPaladinAura", label = "Paladin: an aura", class = "PALADIN",
        retail = { kind = "aura", casts = PALADIN_AURAS, auras = PALADIN_AURAS } },
    { key = "classPaladinRite", label = "Paladin: a weapon rite", class = "PALADIN",
        retail = { kind = "imbue", imbues = {
            { slot = 16, spell = 433568, equip = "weapon" }, { slot = 16, spell = 433583, equip = "weapon" } } } },
    { key = "classWarriorStance", label = "Warrior: a stance", class = "WARRIOR",
        retail = { kind = "aura", casts = WARRIOR_STANCES, auras = WARRIOR_STANCES,
            prefer = { [72] = 386196, [73] = 386208 } },
        forever = { kind = "aura", casts = FOREVER_STANCES, auras = FOREVER_STANCES } },
    { key = "classShamanImbues", label = "Shaman: weapon and shield imbues", class = "SHAMAN",
        retail = { kind = "imbue", imbues = {
            { slot = 16, spell = 33757, equip = "weapon", specs = ENHANCEMENT },
            { slot = 17, spell = 318038, equip = "weapon", specs = ENHANCEMENT },
            { slot = 16, spell = 318038, equip = "weapon", specs = ELEMENTAL },
            { slot = 16, spell = 382021, equip = "weapon", specs = RESTORATION },
            { slot = 17, spell = 462757, equip = "shield", specs = SHIELD_SPECS },
            { slot = 17, spell = 457481, equip = "shield", specs = RESTORATION } } } },
    { key = "classShamanShield", label = "Shaman: Lightning Shield or Water Shield", class = "SHAMAN",
        retail = { kind = "aura", casts = SHAMAN_SHIELDS, auras = SHAMAN_SHIELDS, prefer = { [264] = 52127 } } },
    { key = "classEarthShield", label = "Shaman: Earth Shield on an ally", class = "SHAMAN",
        retail = { kind = "ally", casts = { 974 }, auras = { 974 }, specs = RESTORATION } },
    { key = "classSourceOfMagic", label = "Evoker: Source of Magic on an ally", class = "EVOKER",
        retail = { kind = "ally", casts = { 369459 }, auras = { 369459 } } },
    { key = "classBlisteringScales", label = "Evoker: Blistering Scales on an ally", class = "EVOKER",
        retail = { kind = "ally", casts = { 360827 }, auras = { 360827 } } },
    { key = "classSymbiosis", label = "Druid: Symbiotic Relationship with an ally", class = "DRUID",
        retail = { kind = "ally", casts = { 474750 }, auras = { 474750, 474754 } } },
    { key = "classArcaneFamiliar", label = "Mage: Arcane Familiar", class = "MAGE",
        retail = { kind = "aura", casts = { 205022 }, auras = { 210126 } } },
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
local classRules = { Bool("classReminders", "Remind me of my class and specialization buffs", false) }
for _, def in ipairs(NS.BuffReminderClassReminders) do
    classRules[#classRules + 1] = Bool(def.key, def.label, true)
end
B.Section(id, "classReminders", "Class reminders", classRules)
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
    B.Tooltip(Bool("hideResting", "Hide while resting", false),
        "Cities and inns count as resting. The reminders come back when you leave them."),
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
    -- Size 0 keeps Blizzard's own font object, which is today's look.
    Number("readyCheckSize", "Mana note text size (0 keeps the default)", 0, 0, 40),
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
    -- Saved profiles store the index: new sounds go at the end.
    Choice("reminderSound", "New reminder sound", 1,
        { "None", "Raid warning", "Ready check", "Quest log", "Alarm clock", "Map ping", "Whisper" }),
    Choice("reminderSoundChannel", "Reminder sound channel", 1, { "Master", "Sound effects", "Dialog" }),
    Choice("reminderGlow", "Reminder border effect", 1, { "Normal", "Highlight", "Pulse" }),
    Color("reminderGlowColor", "Reminder highlight color", "ffd200"),
    String("iconSkin", "Icon skin", "CUSTOM", 64),
    Choice("iconShape", "Icon shape", 1, NS.IconShapeLabels),
    Number("size", "Icon size", 38, 22, 72),
    Number("spacing", "Icon spacing", 5, 0, 20),
    Number("columns", "Icons per row", 6, 1, 12),
    Color("borderColor", "Border color", NS.Client.isForever and "d8b66a" or "e8b855"),
    B.Font("countFont", "Item count font"),
    Number("countSize", "Item count size", 12, 8, 32),
    Choice("countPosition", "Item count position", 9, NS.AnchorLabels),
    Number("countX", "Item count horizontal offset", -2, -40, 40),
    Number("countY", "Item count vertical offset", 2, -40, 40),
    Number("noticeSize", "Notice text size (0 keeps the default)", 0, 0, 40),
})
-- Every anchor the Suite offers. Saved profiles stored 1 = Center and 2 = Top
-- when those were the only two, so they stay first and the other seven follow
-- in the Suite's order (the runtime lists the same order: R.ScreenPoint).
local screenAnchors = { "Center", "Top" }
for index, point in ipairs(NS.AnchorPoints) do
    if point ~= "CENTER" and point ~= "TOP" then screenAnchors[#screenAnchors + 1] = NS.AnchorLabels[index] end
end
B.Section(id, "position", "Position", {
    Bool("followCursor", "Keep the reminders beside the cursor outside combat", false),
    Number("cursorOffsetX", "Distance from the cursor, horizontal", 24, -300, 300),
    Number("cursorOffsetY", "Distance from the cursor, vertical", 24, -300, 300),
    Choice("point", "Screen anchor", 2, screenAnchors),
    Number("x", "Horizontal offset", 0, -4000, 4000),
    Number("y", "Vertical offset", -145, -3000, 3000),
})

local rules = NS.SuiteCatalog[id].rules
rules.iconSkin.hidden = true
rules.spellIDs.spells = true
rules.mainHandItem.items = true
rules.offHandItem.items = true
rules.mapPotionItem.items = true
rules.keystoneCover.hidden = NS.Client.isForever or nil
rules.keystoneMinutes.hidden = NS.Client.isForever or nil
rules.keystoneMinutes.requiresChoice = { key = "keystoneCover", values = { [3] = true } }
-- Presentation dependencies for the menu: a setting that only matters while
-- its switch is on (or a sound is chosen) is greyed otherwise. Greying never
-- changes a stored value.
-- Each consumable choice follows its category's switch.
for key, switch in pairs({ flaskChoice = "autoFlask", foodChoice = "autoFood", runeChoice = "autoRune",
    oilChoice = "autoWeapon" }) do
    rules[key].items = true
    rules[key].enableKey = switch
end
for _, key in ipairs({ "mapPotionItem", "mapPotionMaps" }) do rules[key].enableKey = "mapPotion" end
for _, key in ipairs({ "readyCheckManaPercent", "readyCheckDuration", "readyCheckSize" }) do
    rules[key].enableKey = "readyCheckMana"
end
for _, key in ipairs({ "cursorOffsetX", "cursorOffsetY" }) do rules[key].enableKey = "followCursor" end
-- A demon's tick counts only while the demon warning is on.
for _, demon in ipairs(NS.BuffReminderDemons) do rules[demon.key].enableKey = "demonChoiceWarning" end
-- The sound channel matters once a sound is chosen (1 is None).
local sounds = {}
for choice = 2, #rules.reminderSound.choices do sounds[choice] = true end
rules.reminderSoundChannel.requiresChoice = { key = "reminderSound", values = sounds }
-- Each class reminder follows the master switch; one a client lacks is hidden.
for _, def in ipairs(NS.BuffReminderClassReminders) do
    rules[def.key].enableKey = "classReminders"
    rules[def.key].hidden = NS.Client.isForever and not def.forever or nil
end
