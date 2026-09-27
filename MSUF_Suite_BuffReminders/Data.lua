local _, P = ...
-- Reminder data: the game IDs the module selects from. The tables change
-- only with a season. Every runtime file reads them from P.BuffReminders
-- (TOC order: Data, Readers, Entries, Controller; Controller installs).
local R = {}
P.BuffReminders = R
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
-- Spell IDs are game identifiers. Assassination favors Deadly Poison;
-- Outlaw and Subtlety favor Instant Poison. Any active poison of the same
-- category satisfies the reminder, including a player's talent choice.
local LETHAL_POISONS = { 2823, 315584, 381664, 8679 }
local ASSASSINATION_LETHAL_POISONS = { 2823, 381664, 315584, 8679 }
local OTHER_LETHAL_POISONS = { 315584, 8679, 2823, 381664 }
local NONLETHAL_POISONS = { 381637, 5761, 3408 }
-- Current-season item IDs.
-- Selection runs only on configuration/bag/equipment events, never on a timer.
local FLASKS = {
    241324, 241325, 245931, 245930, 241322, 241323, 245933, 245932,
    241326, 241327, 245929, 245928, 241320, 241321, 245926, 245927,
}
local FLASK_AURAS = { 1235110, 1235108, 1235111, 1235057 }
local FOODS = {
    242275, 255847, 255848, 242274, 242285, 242284,
    242272, 242273, 242744, 242745, 242746, 242747,
}
local RUNES = { 259085, 243191 }
local RUNE_AURAS = { 1264426, 453250, 1234969, 1242347, 393438, 347901 }
local OILS = { 243733, 243734, 243735, 243736, 243737, 243738 }
local OIL_WEAPON_LOCATIONS = {
    INVTYPE_WEAPON = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
}
local FOOD_ICONS = { [136000] = true, [133950] = true }
-- Visible Well Fed variants. Every food rescan looks these IDs and their
-- spell name up. Other food auras are learned by icon from UNIT_AURA deltas
-- and re-checked by instance ID on each rescan (combat end, zone change, full
-- update), so this list matters only for food active before a login/reload.
local FOOD_AURAS = { 104280, 1219179, 1285644 }
R.CLASS_BUFF = CLASS_BUFF
R.LETHAL_POISONS, R.NONLETHAL_POISONS = LETHAL_POISONS, NONLETHAL_POISONS
R.ASSASSINATION_LETHAL_POISONS, R.OTHER_LETHAL_POISONS = ASSASSINATION_LETHAL_POISONS, OTHER_LETHAL_POISONS
R.FLASKS, R.FLASK_AURAS, R.FOODS, R.FOOD_ICONS, R.FOOD_AURAS = FLASKS, FLASK_AURAS, FOODS, FOOD_ICONS, FOOD_AURAS
R.RUNES, R.RUNE_AURAS, R.OILS, R.OIL_WEAPON_LOCATIONS = RUNES, RUNE_AURAS, OILS, OIL_WEAPON_LOCATIONS
