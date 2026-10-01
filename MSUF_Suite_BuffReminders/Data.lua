local _, P = ...
-- Reminder data: the game IDs the module selects from. Every runtime file
-- reads them from P.BuffReminders (TOC order: Data, Readers, Entries,
-- Controller; Controller installs). Aura names in the comments are the game's
-- spell names; item lists are ordered by the rule their picker uses.
local R = {}
P.BuffReminders = R

-- Healthstones a Warlock's soulwell or ritual can give on Forever: the five
-- classic ranks (5509-5512, 9421) and their improved versions (19004-19013).
R.FOREVER_HEALTHSTONES = { 5509, 5510, 5511, 5512, 9421,
    19004, 19005, 19006, 19007, 19008, 19009, 19010, 19011, 19012, 19013 }
-- Healthstone and the Demonic Healthstone talent version on Retail.
R.HEALTHSTONES = { 5512, 224464 }
-- Forever's Create Soulstone ranks; any of them makes the Soulstone aura.
R.FOREVER_SOULSTONE_SPELLS = { 693, 20752, 20755, 20756, 20757 }
-- The Soulstone aura on its target, and the two Paladin Beacons.
R.SOULSTONE_AURA = 20707
R.BEACON_OF_LIGHT, R.BEACON_OF_FAITH = 53563, 156910
-- WoW Forever's Camp Benefits, the buff a campfire gives. The reminder only
-- runs while the client knows this spell (it has a name).
R.CAMP_BENEFITS = 1229741

-- These spell IDs are already part of MSUF's long-term raid buff presets.
-- The cast spell and observed aura can differ (notably Blessing of the Bronze).
local CLASS_BUFF = {
    DRUID = { cast = 1126, auras = { 1126, 432661 } },
    MAGE = { cast = 1459, auras = { 1459, 432778 } },
    PRIEST = { cast = 21562, auras = { 21562 } },
    SHAMAN = { cast = 462854, auras = { 462854 } },
    WARRIOR = { cast = 6673, auras = { 6673 } },
    EVOKER = {
        cast = 364342,
        auras = { 381732, 381741, 381746, 381748, 381749,
            381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758 }
    },
}
local FOREVER_CLASS_BUFF = {
    DRUID = { cast = 1126, auras = { 1126, 21849 } },
    MAGE = { cast = 1459, auras = { 1459, 23028 } },
    PRIEST = { cast = 1243, auras = { 1243, 21562 } },
    WARRIOR = { cast = 6673, auras = { 6673 } },
}
function R.ClassBuff(class)
    return (P.NS.Client.isForever and FOREVER_CLASS_BUFF or CLASS_BUFF)[class]
end
-- Spell IDs are game identifiers. Assassination favors Deadly Poison;
-- Outlaw and Subtlety favor Instant Poison. Any active poison of the same
-- category satisfies the reminder, including a player's talent choice.
local LETHAL_POISONS = { 2823, 315584, 381664, 8679 }
local ASSASSINATION_LETHAL_POISONS = { 2823, 381664, 315584, 8679 }
local OTHER_LETHAL_POISONS = { 315584, 8679, 2823, 381664 }
local NONLETHAL_POISONS = { 381637, 5761, 3408 }

-- Consumables. Selection runs only on configuration, bag and equipment
-- events, never on a timer. A picker takes the first listed item in the
-- bags; every item list runs from the highest item ID down.
--
-- Midnight flasks: the four kinds in both crafted qualities (241320-241327)
-- and in the second item range of the same flasks (245926-245933).
local FLASKS = {
    245933, 245932, 245931, 245930, 245929, 245928, 245927, 245926,
    241327, 241326, 241325, 241324, 241323, 241322, 241321, 241320,
}
-- Flask of Thalassian Resistance, of the Magisters, of the Blood Knights and
-- of the Shattered Sun. Any of them satisfies the flask reminder.
local FLASK_AURAS = { 1235057, 1235108, 1235110, 1235111 }
-- Midnight augment runes.
local RUNES = { 259085, 243191 }
-- Augment rune auras from the highest spell ID down, like the item lists, so
-- the current rune is found in one lookup: Void-Touched, Soulgorged and
-- Ethereal (Midnight), Crystallization (The War Within), Draconic
-- (Dragonflight), Veiled (Shadowlands). An older rune still counts.
local RUNE_AURAS = { 1264426, 1242347, 1234969, 453250, 393438, 347901 }
-- Midnight weapon oils.
local OILS = { 243738, 243737, 243736, 243735, 243734, 243733 }
local OIL_WEAPON_LOCATIONS = {
    INVTYPE_WEAPON = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
}
-- Food has no item list. The game's own data names every Midnight food: each
-- one sets the hidden Become Well Fed aura (1219179), and its triggers are the
-- eating spells (Refreshment, Hearty Refreshment) that the food items use, and
-- the Well Fed and Hearty Well Fed buffs. Source: the Become Well Fed record of
-- the game data dump of build 12.1.0.69497 (SimulationCraft's SpellDataDump).
-- A bag item whose use spell is one of these eating spells is food the
-- reminder can click. Highest spell ID first.
local EATING_SPELL_LIST = {
    1305159, 1305158, 1283374, 1280485, 1269305, 1259662, 1233770, 1233769,
    1233768, 1233767, 1233766, 1233765, 1233764, 1233763, 1233762, 1233761,
    1233760, 1233759, 1233758, 1233757, 1233756, 1233755, 1233754, 1233753,
    1233752, 1233751, 1233750, 1233749, 1233748, 1233747, 1233746, 1233745,
    1233744, 1233743, 1233742, 1233741, 1233740, 1233739, 1233738, 1232927,
    1232926, 1232925, 1232921, 1232920, 1232919, 1232917, 1232916, 1232915,
    1232914, 1232913, 1232910, 1232909, 1232908, 1232907, 1232906, 1232905,
    1232903, 1232902, 1232901, 1232489, 1232488, 1232487, 1232486, 1232485,
    1232484, 1232483, 1232481, 1232257, 1232256, 1232253, 1232252, 1232251,
    1232250, 1232249, 1232246, 1219187,
}
local EATING_SPELLS = {}
for index = 1, #EATING_SPELL_LIST do EATING_SPELLS[EATING_SPELL_LIST[index]] = true end
-- Well Fed, Become Well Fed and Hearty Well Fed: their IDs and names find the
-- food buff after a reload; a buff learned from a UNIT_AURA delta is known by
-- the Well Fed icon or one of these names.
local FOOD_AURAS = { 104280, 1219179, 1232076 }
local FOOD_ICONS = { [136000] = true }
R.WELL_FED = 104280
R.EATING_SPELLS = EATING_SPELLS
R.CLASS_BUFF = CLASS_BUFF
R.LETHAL_POISONS, R.NONLETHAL_POISONS = LETHAL_POISONS, NONLETHAL_POISONS
R.ASSASSINATION_LETHAL_POISONS, R.OTHER_LETHAL_POISONS = ASSASSINATION_LETHAL_POISONS, OTHER_LETHAL_POISONS
R.FLASKS, R.FLASK_AURAS, R.FOOD_ICONS, R.FOOD_AURAS = FLASKS, FLASK_AURAS, FOOD_ICONS, FOOD_AURAS
R.RUNES, R.RUNE_AURAS, R.OILS, R.OIL_WEAPON_LOCATIONS = RUNES, RUNE_AURAS, OILS, OIL_WEAPON_LOCATIONS
