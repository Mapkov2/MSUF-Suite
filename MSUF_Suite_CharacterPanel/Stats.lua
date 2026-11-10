local _, NS = ...
local Host, Suite = NS.Host, NS.Suite
local Number, Public, Text = NS.Number, NS.Public, NS.Text
local Forever = Host.Client.isForever
local defenseSkill = Forever and UnitDefenseSkill
local Stats = {}
NS.Stats = Stats

local PLAYER = "player"
-- The loaded Camelot PaperDoll stats use two armor per effective agility.
local FOREVER_ARMOR_PER_AGILITY = 2
local BASE, BONUS, PENALTY = Text("Base"), Text("Bonus"), Text("Penalty")
local RATING = Text("Combat rating")
local RATING_BONUS = Text("Bonus from rating")
local REDUCTION = Text("Damage reduction")
local DR = Text("Diminishing returns")
local DR_DETAIL = Text("Next point: %.1f%% efficiency. Total rating benefit lost so far: %.1f%%.")
local DR_AMOUNT = Text("%.0f rating above the first DR threshold; about %.0f rating-equivalent benefit lost to DR.")
local DR_UNKNOWN = Text("DR data unavailable")

local function Percent(value)
    if value then return string.format("%.2f%%", value) end
end

local function AddValue(tip, label, value)
    if label and value ~= nil then tip:AddDoubleLine(label, tostring(value)) end
end

local function AddFormat(tip, formatText, value)
    if formatText and value ~= nil then tip:AddLine(formatText:format(value), 1, .82, 0, true) end
end

local function Read(getter, ...)
    if getter then return Number(getter(...)) end
end

local function AddBreakdown(tip, base, bonus, penalty)
    AddValue(tip, BASE, base)
    if bonus and bonus ~= 0 then AddValue(tip, BONUS, bonus) end
    if penalty and penalty ~= 0 then AddValue(tip, PENALTY, penalty) end
end

local function AttributeBenefits(tip, id, effective)
    if not effective then return end
    if id == LE_UNIT_STAT_STAMINA then
        local perPoint = Read(UnitHPPerStamina, PLAYER)
        if not perPoint then return end
        local health
        if Forever then
            local below = math.min(STAMINA_BREAK, effective)
            health = below + (effective - below) * perPoint
        else
            local modifier = Read(GetUnitMaxHealthModifier, PLAYER)
            if modifier then health = effective * perPoint * modifier end
        end
        if health then AddValue(tip, HEALTH, math.floor(health + .5)) end
    elseif Forever and id == LE_UNIT_STAT_INTELLECT then
        local crit = Read(GetSpellCritChanceFromStat, id, effective)
        if crit then AddValue(tip, STAT_CRITICAL_STRIKE, Percent(crit * 100)) end
        local mana = Read(UnitPowerMax, PLAYER, Enum.PowerType.Mana)
        if mana and mana > 0 then
            local below = math.min(INTELLECT_BREAK, effective)
            AddValue(tip, MANA, below + (effective - below) * MANA_PER_INTELLECT)
        end
    elseif Forever and (id == LE_UNIT_STAT_AGILITY or id == LE_UNIT_STAT_STRENGTH) then
        local attackPower = Read(GetAttackPowerForStat, id, effective)
        if attackPower and attackPower > 0 then AddValue(tip, STAT_ATTACK_POWER, attackPower) end
        if id == LE_UNIT_STAT_AGILITY then
            local crit = Read(GetCritChanceFromStat, id, effective)
            local dodge = Read(GetDodgeChanceFromAttribute)
            if crit then AddValue(tip, STAT_CRITICAL_STRIKE, Percent(crit * 100)) end
            if dodge then AddValue(tip, STAT_DODGE, Percent(dodge * 100)) end
            AddValue(tip, STAT_ARMOR, effective * FOREVER_ARMOR_PER_AGILITY)
        end
    end
end

function Stats.AttributeTooltip(tip, id)
    local current, effective, bonus, penalty = UnitStat(PLAYER, id)
    current, bonus, penalty = Number(current), Number(bonus), Number(penalty)
    -- PaperDoll's first UnitStat result includes both modifiers.
    local base = current and bonus and penalty and current - bonus - penalty
    AddBreakdown(tip, base, bonus, penalty)
    AttributeBenefits(tip, id, Number(effective))
    local description = NS.String(_G["DEFAULT_STAT" .. id .. "_TOOLTIP"])
    -- Some descriptions take a class-specific numeric argument.
    if description and not description:find("%", 1, true) then tip:AddLine(description, 1, .82, 0, true) end
end

local function ArmorReduction(getter, armor, level)
    local fraction = Read(getter, armor, level)
    return fraction and fraction * 100
end

local function AddArmorReduction(tip, armor, againstPlayer, againstTarget)
    if not armor then return end
    local level = Read(UnitEffectiveLevel, PLAYER)
    if level and level > 0 then
        AddFormat(tip, againstPlayer, ArmorReduction(C_PaperDollInfo.GetArmorEffectiveness, armor, level))
    end
    local fraction = Read(C_PaperDollInfo.GetArmorEffectivenessAgainstTarget, armor)
    AddFormat(tip, againstTarget, fraction and fraction * 100)
end

function Stats.ArmorTooltip(tip)
    local base, effective, _, bonus = UnitArmor(PLAYER)
    AddBreakdown(tip, Number(base), Number(bonus))
    AddArmorReduction(tip, Number(effective), STAT_ARMOR_TOOLTIP, STAT_ARMOR_TARGET_TOOLTIP)
end

function Stats.DefenseTooltip(tip)
    if not defenseSkill then return end
    local base, bonus = defenseSkill(PLAYER)
    AddBreakdown(tip, Number(base), Number(bonus))
end

local function BlockTooltip(tip)
    local block = Read(GetShieldBlock)
    if Forever then
        local chance = Read(GetBlockChance)
        if block and chance then
            tip:AddLine(STAT_BLOCK_VALUE_FLAT_TOOLTIP:format(chance, block), 1, .82, 0, true)
        end
    else
        AddArmorReduction(tip, block, CR_BLOCK_TOOLTIP, STAT_BLOCK_TARGET_TOOLTIP)
    end
end

local ratingResult = {}
local function RatingTooltip(tip, rating, withDR)
    if not rating then return end
    local result = Host.ReadCharacterRating(rating, ratingResult, withDR)
    AddValue(tip, RATING, result.rating)
    local mastery = not Forever and rating == CR_MASTERY
    local bonus = result.bonus
    AddValue(tip, RATING_BONUS, mastery and bonus and string.format("%.2f", bonus) or Percent(bonus))
    if not withDR or Forever then return end
    if not result.penalty then
        tip:AddLine(DR_UNKNOWN, 1, .82, 0, true)
        return
    end
    AddValue(tip, DR, Percent(result.penalty))
    tip:AddLine(DR_DETAIL:format(100 - result.penalty, result.loss), 1, .82, 0, true)
    if result.inDR and result.inDR > 0 then
        tip:AddLine(DR_AMOUNT:format(result.inDR, result.lostRating), 1, .82, 0, true)
    end
end

local function SecondaryTooltip(tip, rating)
    RatingTooltip(tip, rating, true)
    if rating and rating == CR_VERSATILITY_DAMAGE_DONE then
        local reduction = Read(GetCombatRatingBonus, CR_VERSATILITY_DAMAGE_TAKEN)
        local extra = Read(GetVersatilityBonus, CR_VERSATILITY_DAMAGE_TAKEN)
        if reduction and extra then AddValue(tip, REDUCTION, Percent(reduction + extra)) end
    end
end

function Stats.SimpleRatingTooltip(tip, rating)
    if rating then RatingTooltip(tip, rating, false) end
end

function Stats.DodgeTooltip(tip)
    if Forever then
        AddFormat(tip, CR_DODGE_BASE_STAT_TOOLTIP, Read(GetDodgeChance))
    else
        Stats.SimpleRatingTooltip(tip, CR_DODGE)
        AddFormat(tip, CR_DODGE_BASE_STAT_TOOLTIP, Read(GetDodgeChanceFromAttribute))
    end
end

local function ParryTooltip(tip)
    if Forever then
        AddFormat(tip, CR_PARRY_BASE_STAT_TOOLTIP, Read(GetParryChance))
    else
        Stats.SimpleRatingTooltip(tip, CR_PARRY)
        AddFormat(tip, CR_PARRY_BASE_STAT_TOOLTIP, Read(GetParryChanceFromAttribute))
    end
end

local function PercentRow(group, row, label, value, tooltip, argument)
    if label then row(group, label, Percent(value), nil, tooltip, argument) end
end

local function ForeverCrit()
    local melee, ranged, spell = Read(GetCritChance), Read(GetRangedCritChance), Read(GetSpellCritChance)
    if not (melee and ranged and spell) then return end
    if spell >= melee and spell >= ranged then return spell, CR_CRIT_SPELL end
    if ranged >= melee then return ranged, CR_CRIT_RANGED end
    return melee, CR_CRIT_MELEE
end

local function ForeverHaste()
    local melee, spell = Read(GetMeleeHaste), Read(UnitSpellHaste, PLAYER)
    if not (melee and spell and GetRangedHaste) then return end
    local ranged, ammo = GetRangedHaste()
    ranged, ammo = Number(ranged), Number(ammo)
    if not (ranged and ammo) then return end
    ranged = ranged + ammo
    if spell >= melee and spell >= ranged then return spell, CR_HASTE_SPELL end
    if ranged >= melee then return ranged, CR_HASTE_RANGED end
    return melee, CR_HASTE_MELEE
end

function Stats.Enhancements(group, row)
    local crit, critRating, haste, hasteRating
    if Forever then
        crit, critRating = ForeverCrit()
        haste, hasteRating = ForeverHaste()
    else
        crit, critRating = Suite.ReadCrit()
        haste, hasteRating = Suite.ReadHaste(), CR_HASTE_MELEE
    end
    PercentRow(group, row, STAT_CRITICAL_STRIKE, crit, SecondaryTooltip, critRating)
    PercentRow(group, row, STAT_HASTE, haste, SecondaryTooltip, hasteRating)
    if Forever then return end
    PercentRow(group, row, STAT_MASTERY, Suite.ReadMastery(), SecondaryTooltip, CR_MASTERY)
    PercentRow(group, row, STAT_VERSATILITY, Suite.ReadVersatility(), SecondaryTooltip, CR_VERSATILITY_DAMAGE_DONE)
    PercentRow(group, row, STAT_LIFESTEAL, Read(Suite.ReadLeech), Stats.SimpleRatingTooltip, CR_LIFESTEAL)
    PercentRow(group, row, STAT_SPEED, Read(GetSpeed), Stats.SimpleRatingTooltip, CR_SPEED)
end

local function ManaRegenTooltip(tip)
    local base = Read(GetManaRegen)
    if base then AddFormat(tip, MANA_REGEN_TOOLTIP, tostring(math.floor(base * 5))) end
end

local function MovementTooltip(tip)
    local _, ground, flight, swim = GetUnitSpeed(PLAYER)
    ground, flight, swim = Number(ground), Number(flight), Number(swim)
    if ground then AddFormat(tip, STAT_MOVEMENT_GROUND_TOOLTIP, ground / BASE_MOVEMENT_SPEED * 100) end
    if flight and flight > 0 then AddFormat(tip, STAT_MOVEMENT_FLIGHT_TOOLTIP, flight / BASE_MOVEMENT_SPEED * 100) end
    if swim then AddFormat(tip, STAT_MOVEMENT_SWIM_TOOLTIP, swim / BASE_MOVEMENT_SPEED * 100) end
end

function Stats.General(group, row)
    if Forever then
        local _, run = GetUnitSpeed(PLAYER)
        run = Number(run)
        if run then
            PercentRow(group, row, STAT_MOVEMENT_SPEED, run / BASE_MOVEMENT_SPEED * 100, MovementTooltip)
        end
    end
    local mana = Read(UnitPowerMax, PLAYER, Enum.PowerType.Mana)
    if mana and mana > 0 then
        local regen = Number(select(2, GetManaRegen()))
        row(group, MANA_REGEN, regen and math.floor(regen * 5), nil, ManaRegenTooltip)
    end
end

function Stats.Defenses(group, row)
    local parry = Read(GetParryChance)
    if parry and parry > 0 then PercentRow(group, row, STAT_PARRY, parry, ParryTooltip) end
    local hasShield = C_PaperDollInfo.OffhandHasShield()
    if Public(hasShield) and hasShield == true then
        PercentRow(group, row, STAT_BLOCK, Read(GetBlockChance), BlockTooltip)
    end
    if Forever then return end
    local stagger = Read(C_PaperDollInfo.GetStaggerPercentage, PLAYER)
    if stagger and stagger > 0 then PercentRow(group, row, STAT_STAGGER, stagger) end
end

local function SpellPower()
    local lowest
    for school = 2, MAX_SPELL_SCHOOLS do
        local bonus = Read(GetSpellBonusDamage, school)
        if not bonus then return end
        lowest = lowest and math.min(lowest, bonus) or bonus
    end
    return lowest
end

local function AttackPower(getter)
    if not getter then return end
    local override = Read(GetOverrideAPBySpellPower)
    if override and override > 0 then
        local damage, healing = SpellPower(), Read(GetSpellBonusHealing)
        return damage and healing and math.min(damage, healing) * override
    end
    local base, bonus, penalty = getter(PLAYER)
    base, bonus, penalty = Number(base), Number(bonus), Number(penalty)
    return base and bonus and penalty and math.max(0, base + bonus + penalty)
end

local function AttackPowerTooltip(tip, getter)
    local override = Read(GetOverrideAPBySpellPower)
    if override and override > 0 then return end
    local base, bonus, penalty = getter(PLAYER)
    AddBreakdown(tip, Number(base), Number(bonus), Number(penalty))
end

local MAIN_HAND, OFF_HAND, RANGED_WEAPON = "main", "off", "ranged"
local function Range(minimum, maximum)
    minimum, maximum = Number(minimum), Number(maximum)
    if minimum and maximum and maximum > 0 then
        return string.format("%d – %d", math.max(1, math.floor(minimum)), math.ceil(maximum))
    end
end

local function WeaponNumbers(kind)
    if kind == RANGED_WEAPON then
        local speed, low, high = UnitRangedDamage(PLAYER)
        return Number(low), Number(high), Number(speed)
    end
    local low, high, offLow, offHigh = UnitDamage(PLAYER)
    local mainSpeed, offSpeed = UnitAttackSpeed(PLAYER)
    if kind == OFF_HAND then return Number(offLow), Number(offHigh), Number(offSpeed) end
    return Number(low), Number(high), Number(mainSpeed)
end

local function WeaponTooltip(tip, kind)
    local low, high, speed = WeaponNumbers(kind)
    if not speed or speed <= 0 then return end
    AddValue(tip, ATTACK_SPEED_SECONDS, string.format("%.2f", speed))
    if low and high then AddValue(tip, STAT_DPS_SHORT, string.format("%.1f", (low + high) / (2 * speed))) end
end

local function WeaponDamage(group, row, mainMin, mainMax, offMin, offMax)
    row(group, INVTYPE_WEAPONMAINHAND, Range(mainMin, mainMax), nil, WeaponTooltip, MAIN_HAND)
    local dualWield = IsDualWielding()
    local offHand = Public(dualWield) and dualWield == true and Range(offMin, offMax)
    if offHand then row(group, INVTYPE_WEAPONOFFHAND, offHand, nil, WeaponTooltip, OFF_HAND) end
    local ranged = IsRangedWeapon()
    if Public(ranged) and ranged == true then
        local _, low, high = UnitRangedDamage(PLAYER)
        row(group, INVTYPE_RANGED, Range(low, high), nil, WeaponTooltip, RANGED_WEAPON)
    end
end

function Stats.Weapons(group, row)
    WeaponDamage(group, row, UnitDamage(PLAYER))
    local melee = AttackPower(UnitAttackPower)
    local ranged = AttackPower(UnitRangedAttackPower)
    if melee and melee > 0 then
        row(group, STAT_ATTACK_POWER, math.floor(melee + .5), nil, AttackPowerTooltip, UnitAttackPower)
    end
    if ranged and ranged > 0 then
        row(group, RANGED_ATTACK_POWER, math.floor(ranged + .5), nil, AttackPowerTooltip, UnitRangedAttackPower)
    end
end

local function Hit(rating, getter)
    local bonus, extra = Read(GetCombatRatingBonus, rating), Read(getter)
    if bonus and extra then return bonus + extra end
end

local function HitTooltip(tip)
    AddValue(tip, MELEE, Percent(Hit(CR_HIT_MELEE, GetHitModifier)))
    AddValue(tip, INVTYPE_WEAPONOFFHAND, Percent(Hit(CR_HIT_MELEE, GetOffhandHitModifier)))
    AddValue(tip, RANGED, Percent(Hit(CR_HIT_RANGED, GetRangedHitModifier)))
    AddValue(tip, SPELLS, Percent(Hit(CR_HIT_SPELL, GetSpellHitModifier)))
end

local function HighestHit()
    local melee, offhand = Hit(CR_HIT_MELEE, GetHitModifier), Hit(CR_HIT_MELEE, GetOffhandHitModifier)
    local ranged, spell = Hit(CR_HIT_RANGED, GetRangedHitModifier), Hit(CR_HIT_SPELL, GetSpellHitModifier)
    if melee and offhand and ranged and spell then return math.max(melee, offhand, ranged, spell) end
end

local function PositiveRow(group, row, label, value)
    if label and value and value > 0 then row(group, label, math.floor(value + .5)) end
end

local function ExpertiseTooltip(tip)
    local main, offhand, ranged = GetExpertise()
    AddValue(tip, INVTYPE_WEAPONMAINHAND, Percent(Number(main)))
    local dualWield = IsDualWielding()
    if Public(dualWield) and dualWield == true then
        AddValue(tip, INVTYPE_WEAPONOFFHAND, Percent(Number(offhand)))
    end
    AddValue(tip, INVTYPE_RANGED, Percent(Number(ranged)))
end

local function Expertise()
    local main, offhand, ranged = GetExpertise()
    main, offhand, ranged = Number(main), Number(offhand), Number(ranged)
    if not main then return end
    local dualWield = IsDualWielding()
    if Public(dualWield) and dualWield == true and offhand and (main ~= 0 or offhand ~= 0) then
        return Percent(main) .. " / " .. Percent(offhand)
    end
    if main ~= 0 or (ranged and ranged ~= 0) then return Percent(main) end
end

function Stats.ForeverModifiers(group, row)
    local hit = HighestHit()
    if hit and hit ~= 0 then PercentRow(group, row, STAT_HIT_CHANCE, hit, HitTooltip) end
    local expertise = Expertise()
    if expertise then row(group, STAT_EXPERTISE, expertise, nil, ExpertiseTooltip) end
    PositiveRow(group, row, STAT_ARMOR_PENETRATION, Read(GetArmorPenetration))
    PositiveRow(group, row, STAT_SPELLPOWER, GetSpellBonusDamage and SpellPower())
    PositiveRow(group, row, STAT_SPELLHEALING, Read(GetSpellBonusHealing))
    PositiveRow(group, row, STAT_SPELL_PENETRATION, Read(GetSpellPenetration))
end

local tooltipOwner
local function HideTooltip(button)
    if tooltipOwner ~= button then return end
    tooltipOwner = nil
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

local function ShowTooltip(button)
    local values = button.statValues
    if not values or Host.InCombat() then return end
    tooltipOwner, button.tooltipLabel = button, values.label
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(values.label)
    AddValue(GameTooltip, TOTAL, values.value)
    values.tooltip(GameTooltip, values.tooltipArgument)
    GameTooltip:Show()
end

function Stats.BindTooltip(button)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnHide", HideTooltip)
end

function Stats.UpdateTooltip(button, values)
    local enabled = button.statValues ~= nil or button.action ~= nil
    button.statValues = values.tooltip and values or nil
    local mouseable = button.statValues ~= nil or values.action ~= nil
    if enabled ~= mouseable then button:EnableMouse(mouseable) end
    if tooltipOwner ~= button then return end
    if button.statValues and button.tooltipLabel == values.label and not Host.InCombat() and GameTooltip:IsOwned(button) then
        ShowTooltip(button)
    else
        HideTooltip(button)
    end
end
