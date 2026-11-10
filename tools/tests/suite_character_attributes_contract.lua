local root = assert(arg[1], "repository root required")
local panel = root .. "/MSUF_Suite_CharacterPanel/"
local Strict = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
local secret = Strict.New("number")
local Forever = false
local statReads, ratingReads = 0, 0
local function Identity(value) return value end
local function Public(value) return not Strict.IsSecret(value) end
local function Number(value)
    if Public(value) and type(value) == "number" then return value end
end

LE_UNIT_STAT_STRENGTH, LE_UNIT_STAT_AGILITY, LE_UNIT_STAT_STAMINA = 1, 2, 3
LE_UNIT_STAT_INTELLECT, LE_UNIT_STAT_SPIRIT = 4, 5
HEALTH, MANA, MANA_REGEN = "Health", "Mana", "Mana regen"
MANA_REGEN_TOOLTIP = "%s out of combat"
TOTAL = "Total"
SPELL_STAT1_NAME, SPELL_STAT2_NAME, SPELL_STAT3_NAME = "Strength", "Agility", "Stamina"
SPELL_STAT4_NAME, SPELL_STAT5_NAME = "Intellect", "Spirit"
STAT_ARMOR, DEFENSE, STAT_DODGE, STAT_PARRY = "Armor", "Defense", "Dodge", "Parry"
STAT_BLOCK, STAT_STAGGER = "Block", "Stagger"
STAT_ARMOR_TOOLTIP, STAT_ARMOR_TARGET_TOOLTIP = "%.2f%% reduction", "%.2f%% against target"
STAT_CRITICAL_STRIKE, STAT_HASTE, STAT_MASTERY, STAT_VERSATILITY = "Crit", "Haste", "Mastery", "Versatility"
STAT_LIFESTEAL, STAT_AVOIDANCE, STAT_SPEED, STAT_MOVEMENT_SPEED = "Leech", "Avoidance", "Speed", "Run speed"
STAT_HIT_CHANCE, STAT_EXPERTISE, STAT_ARMOR_PENETRATION = "Hit", "Expertise", "Armor penetration"
STAT_SPELLPOWER, STAT_SPELLHEALING, STAT_SPELL_PENETRATION = "Spell power", "Healing power", "Spell penetration"
INVTYPE_WEAPONMAINHAND, INVTYPE_WEAPONOFFHAND, INVTYPE_RANGED = "Main hand", "Off hand", "Ranged"
STAT_ATTACK_POWER, RANGED_ATTACK_POWER = "Attack power", "Ranged attack power"
STAT_CATEGORY_WEAPONS, BASE_MOVEMENT_SPEED, MAX_SPELL_SCHOOLS = "Weapons", 7, 7
CR_HIT_MELEE, CR_HIT_RANGED, CR_HIT_SPELL = 6, 7, 8
CR_CRIT_MELEE, CR_CRIT_RANGED, CR_CRIT_SPELL = 9, 10, 11
CR_HASTE_MELEE, CR_HASTE_RANGED, CR_HASTE_SPELL = 18, 19, 20
CR_MASTERY, CR_VERSATILITY_DAMAGE_DONE, CR_VERSATILITY_DAMAGE_TAKEN = 26, 29, 31
CR_LIFESTEAL, CR_SPEED, CR_DODGE, CR_PARRY = 17, 14, 3, 4
Enum = { PowerType = { Mana = 0 } }
local statsRestricted, shield, combat = false, true, false
local function UnitStats(base, effective, bonus, penalty)
    statReads = statReads + 1
    if statsRestricted then return secret, secret, secret, secret end
    return base, effective, bonus, penalty
end
UnitStat = function(_, id) return UnitStats(id + 40, id + 40, 10, -3) end
UnitArmor = function() return UnitStats(700, 840, 800, 140) end
UnitDefenseSkill = function() return UnitStats(150, 6) end
UnitHealthMax = function() return 300 end
UnitPowerType = function() return 0, "MANA" end
UnitPowerMax = function() return 200 end
UnitEffectiveLevel = function() return statsRestricted and secret or 30 end
GetManaRegen = function() return 3.1, 1.6 end
GetDodgeChance = function() return 4 end
GetParryChance = function() return 5 end
GetBlockChance = function() return 6 end
GetShieldBlock = function() return 20 end
STAT_BLOCK_VALUE_FLAT_TOOLTIP = "%.1f%% chance to block %d damage"
CR_BLOCK_TOOLTIP = "%.2f%% shield reduction"
ATTACK_SPEED_SECONDS, STAT_DPS_SHORT = "Attack speed", "DPS"
UnitHPPerStamina = function() return 10 end
GetUnitMaxHealthModifier = function() return 1.1 end
STAMINA_BREAK = 20
GetAvoidance = function() return 7 end
GetSpeed = function() return statsRestricted and secret or 3 end
GetUnitSpeed = function() return 0, 7.7, 0, 0 end
GetCritChance = function() return 1 end
GetRangedCritChance = function() return 3 end
GetSpellCritChance = function() return 2 end
GetMeleeHaste = function() return 2 end
GetRangedHaste = function() return 2, 3 end
UnitSpellHaste = function() return 4 end
GetCombatRatingBonus = function() return 1 end
GetVersatilityBonus = function() return 1.5 end
GetHitModifier = function() return 2 end
GetOffhandHitModifier = function() return 3 end
GetRangedHitModifier = function() return 1 end
GetSpellHitModifier = function() return 0 end
GetExpertise = function() return 1.2, 2.3, 3.4 end
UnitAttackSpeed = function() return 2, 1.5, 2.7 end
IsDualWielding = function() return true end
GetArmorPenetration = function() return 14 end
GetSpellBonusDamage = function(school) return 30 + school end
GetSpellBonusHealing = function() return 42 end
GetSpellPenetration = function() return 5 end
UnitDamage = function() return UnitStats(10.5, 20.2, 4.5, 8.1) end
UnitAttackPower = function() return UnitStats(50, 20, -10) end
UnitRangedAttackPower = function() return UnitStats(30, 5, 0) end
UnitRangedDamage = function() return 2, 8, 12 end
IsRangedWeapon = function() return true end
C_PaperDollInfo = {
    OffhandHasShield = function() return statsRestricted and secret or shield end,
    GetArmorEffectiveness = function(armor, level)
        assert(level == 30)
        if armor == 840 then return .21 end
        assert(not Forever and armor == 20, "Forever block used the armor conversion")
        return .15
    end,
    GetArmorEffectivenessAgainstTarget = function() return .2 end,
    GetStaggerPercentage = function()
        assert(not Forever, "Forever called Retail stagger")
        return 14
    end,
}

local function Read(override)
    Forever = override
    local suite = {
        ReadCrit = function() assert(not Forever) return 8, CR_CRIT_MELEE end,
        ReadHaste = function() assert(not Forever) return 9 end,
        ReadMastery = function() assert(not Forever) return 10 end,
        ReadVersatility = function() assert(not Forever) return 11 end,
        ReadLeech = function() assert(not Forever) return 12 end,
    }
    local ns = {
        Host = { Client = { isForever = Forever }, CharacterTabs = {}, InCombat = function() return combat end,
            ReadCharacterRating = function(rating, _, withDR)
                ratingReads = ratingReads + 1
                assert(not combat)
                assert(rating == (Forever and CR_CRIT_RANGED or CR_CRIT_MELEE) and withDR)
                return { rating = 350, bonus = 34.5, penalty = 10, loss = 1.43, inDR = 50, lostRating = 5 }
            end },
        Suite = suite, Number = Number, Public = Public, Text = Identity,
        String = function(value) return Public(value) and type(value) == "string" and value or nil end,
    }
    for _, file in ipairs({ "Stats", "Reputation", "Pages" }) do assert(loadfile(panel .. file .. ".lua"))("CharacterPanel", ns) end
    return ns
end

local function Index(groups)
    local rows = {}
    for _, group in ipairs(groups) do
        for _, row in ipairs(group.rows) do rows[row.label] = row end
    end
    return rows
end

local function Hover(row)
    local lines = {}
    local tip = {
        AddDoubleLine = function(_, label, value) lines[label] = value end,
        AddLine = function(_, value) lines[#lines + 1] = value end,
    }
    row.tooltip(tip, row.tooltipArgument)
    return lines
end

for _, isForever in ipairs({ false, true }) do
    local ns, groups = Read(isForever), {}
    local before = ratingReads
    local rows = Index(ns.Pages.Overview(groups, true))
    assert(rows.Health.value == 300 and rows.Mana.value == 200 and rows["Mana regen"].value == 8)
    assert(rows.Strength.value == 41 and rows.Armor.value == 840 and rows.Block.value == "6.00%")
    assert(rows.Parry.value == "5.00%" and rows.Dodge.value == "4.00%")
    assert(ratingReads == before, "rating details were read without a hovered row")
    local primary = Hover(rows.Strength)
    assert(primary.Base == "34" and primary.Bonus == "10" and primary.Penalty == "-3")
    local armor = Hover(rows.Armor)
    assert(armor.Base == "700" and armor.Bonus == "140")
    assert(armor[1] == "21.00% reduction" and armor[2] == "20.00% against target")
    local stamina = Hover(rows.Stamina)
    assert(stamina.Health == (isForever and "250" or "473"))
    local block = Hover(rows.Block)
    assert(block[1] == (isForever and "6.0% chance to block 20 damage" or "15.00% shield reduction"))
    local crit = Hover(rows.Crit)
    assert(crit["Combat rating"] == "350" and crit["Bonus from rating"] == "34.50%")
    if isForever then
        assert(rows.Spirit.value == 45 and rows.Defense.value == 156)
        assert(rows.Crit.value == "3.00%" and rows.Haste.value == "5.00%" and rows["Run speed"].value == "110.00%")
        assert(rows["Main hand"].value == "10 – 21" and rows["Off hand"].value == "4 – 9")
        assert(rows["Ranged"].value == "8 – 12" and rows["Attack power"].value == 60)
        local offhand = Hover(rows["Off hand"])
        assert(offhand["Attack speed"] == "1.50" and offhand.DPS == "4.2")
        assert(rows.Hit.value == "4.00%" and rows.Expertise.value == "1.20% / 2.30%")
        assert(rows["Spell power"].value == 32 and rows["Healing power"].value == 42)
        assert(not (rows.Mastery or rows.Avoidance or crit["Diminishing returns"]))
    else
        assert(rows.Leech.value == "12.00%" and rows.Speed.value == "3.00%" and rows.Stagger.value == "14.00%")
        assert(crit["Diminishing returns"] == "10.00%" and crit[1]:find("90.0%% efficiency"))
        assert(not (rows.Spirit or rows.Hit or rows["Main hand"]))
    end
    local statsBefore = statReads
    rows = Index(ns.Pages.Overview(groups, true, true))
    assert(statReads == statsBefore and not (rows.Strength or rows.Armor or rows.Crit), "restricted stat read on combat entry")
    assert(rows.Health.value == 300 and not rows.Health.tooltip, "pooled attribute tooltip leaked into combat")

    shield = false
    rows = Index(ns.Pages.Overview(groups, true))
    assert(not rows.Block, "block shown without a shield")
    shield = true
    statsRestricted = true
    local stop = Strict.Watch(panel .. "Stats.lua", { strict = true })
    rows = Index(ns.Pages.Overview(groups, true))
    armor = Hover(rows.Armor)
    primary = Hover(rows.Strength)
    stop()
    assert(not (rows.Block or armor.Base or primary.Base), "secret input reached a displayed breakdown")
    statsRestricted = false
end

print("Character attributes, native breakdowns, DR and secret inputs verified on both clients")
