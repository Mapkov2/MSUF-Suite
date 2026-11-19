local _, Suite = ...
local Bridge = Suite.HostBridge
local attacks = {
    WARRIOR = { 6552, 1464 }, PALADIN = { 35395, 20271 }, HUNTER = { 185358, 193455, 75 },
    ROGUE = { 1752, 53 }, PRIEST = { 585, 589 }, DEATHKNIGHT = { 49998, 49184 },
    SHAMAN = { 403 }, MAGE = { 133, 116 }, WARLOCK = { 686, 29722 },
    MONK = { 100780 }, DRUID = { 5176, 5221, 33917 }, DEMONHUNTER = { 162243, 203782 },
    EVOKER = { 361469 },
}
local specializations = {
    [253] = { 193455, 185358, 75 }, [255] = { 259387, 186270 },
    [263] = { 17364, 187874 }, [103] = { 5221 }, [104] = { 33917 },
    [65] = { 20271, 35395 }, [62] = { 44425, 30451 }, [64] = { 116 },
}
local heals = { PALADIN = { 19750, 82326 }, PRIEST = { 2061, 2060 }, DRUID = { 8936, 774 },
    SHAMAN = { 8004, 331 }, MONK = { 116670 }, EVOKER = { 361469 } }
local pipPowers

function Bridge.NameplateRangeSpell(friendly)
    local _, class = UnitClass("player")
    if not Suite.Public(class) then return 0 end
    local candidates = heals[class]
    if not friendly then candidates = attacks[class] end
    if not friendly and not Suite.Client.isForever then
        local spec = C_SpecializationInfo.GetSpecialization()
        if Suite.Public(spec) and spec then
            local id = C_SpecializationInfo.GetSpecializationInfo(spec)
            if Suite.Public(id) then candidates = specializations[id] or candidates end
        end
    end
    for _, id in ipairs(candidates or {}) do
        local known = C_SpellBook.IsSpellKnown(id)
        if Suite.Public(known) and known == true then
            local info = C_Spell.GetSpellInfo(id)
            if Suite.Public(info) and info and Suite.Finite(info.minRange) and info.minRange == 0
                and Suite.Finite(info.maxRange) and info.maxRange > 0 then return id end
        end
    end
    return 0
end

function Bridge.TargetResourceFrame()
    local host = Bridge.Namespace()
    local frames = host and host.UF and host.UF.frames
    return frames and frames.target or _G.MSUF_target
end

function Bridge.NameplateResource()
    local host = Bridge.Namespace()
    local resolver = host and host.CPBuilders and host.CPBuilders.ClassPowerType
    if not resolver then return end
    if not pipPowers then
        pipPowers = {}
        for _, entry in ipairs({ { "ComboPoints", "COMBO_POINTS" }, { "HolyPower", "HOLY_POWER" },
            { "SoulShards", "SOUL_SHARDS" }, { "Essence", "ESSENCE" }, { "ArcaneCharges", "ARCANE_CHARGES" },
            { "Chi", "CHI" }, { "Runes", "RUNES" } }) do
            local id = Enum.PowerType[entry[1]]
            if id then pipPowers[id] = entry[2] end
        end
    end
    local power, _, aura = resolver()
    if not Suite.Public(power) or not Suite.Public(aura) or type(power) ~= "number" or aura or not pipPowers[power] then return end
    local provider = host.CPClient
    return power, provider and provider.UnitPower or UnitPower, provider and provider.UnitPowerMax or UnitPowerMax, pipPowers[power]
end
