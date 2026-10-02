local _, private = ...
local NS, S = private.NS, private.Suite
local Style = NS.NameplateStyle
-- The Blizzard nameplate CVars the Suite settings choose. Choice 1 of each
-- setting keeps Blizzard's value: the context hands back what it changed.
local CVars = {}
private.CVars = CVars

local function Restore(key)
    S.RestoreCVar("nameplates", key)
end

-- Blizzard stores array settings as a version byte plus six-bit data bytes,
-- not as decimal masks. Replaces the lowest `width` bits and keeps the
-- version and every other flag.
local function LowBits(module, key, mask, width)
    local current = C_CVar.GetCVar(key)
    local flags = Style.CVarFlags(current)
    if flags == nil then return end
    local span = 2 ^ width
    local nextFlags = flags - flags % span + mask
    local tail = current:sub(3)
    local value = current:sub(1, 1)
    if nextFlags > 0 or #tail > 0 then value = value .. string.char(64 + nextFlags) .. tail end
    module.context:CVar(key, value)
end

-- A three-way choice: 1 keeps Blizzard's value, 2 writes on, 3 writes off.
local function Toggle(module, mode, key)
    if mode == 1 then
        Restore(key)
    else
        module.context:CVar(key, mode == 2 and "1" or "0")
    end
end

local function Size(module, c)
    if c.nativeStyle == 1 then
        Restore("nameplateStyle")
    elseif c.nativeStyle then
        module.context:CVar("nameplateStyle", tostring(c.nativeStyle - 2))
    end
    if c.nativeSize == 1 then
        Restore("nameplateSize")
    elseif c.nativeSize then
        module.context:CVar("nameplateSize", tostring(c.nativeSize - 1))
    end
end

-- Blizzard's rarity icon is bit 3 of the same CVar as the two health text
-- flags. Compose one write so either control preserves the other.
local function InfoDisplay(module, c)
    local textMode = c.enemy and c.look ~= 2 and c.enemyTextMode or 1
    local rarityMode = c.enemy and c.look ~= 2 and c.enemyRarityIcon or 1
    if textMode == 1 then
        Restore("nameplateForceShowUnitName")
        Restore("nameplateSimplifiedTypes")
    else
        module.context:CVar("nameplateForceShowUnitName", "1")
        LowBits(module, "nameplateSimplifiedTypes", 0, 2)
    end
    if textMode == 1 and (rarityMode == 1 or module.infoTextApplied) then Restore("nameplateInfoDisplay") end
    if textMode ~= 1 or rarityMode ~= 1 then
        local flags = Style.CVarFlags(C_CVar.GetCVar("nameplateInfoDisplay"))
        if flags ~= nil then
            local textBits = textMode == 1 and flags % 4 or textMode - 1
            local currentRarity = flags % 8 - flags % 4
            if rarityMode ~= 1 and module.rarityBefore == nil then module.rarityBefore = currentRarity end
            local rarityBit = rarityMode == 1 and (module.rarityBefore or currentRarity)
                or (rarityMode == 2 and 4 or 0)
            LowBits(module, "nameplateInfoDisplay", textBits + rarityBit, 3)
            if rarityMode == 1 then module.rarityBefore = nil end
        end
    else
        module.rarityBefore = nil
    end
    module.infoTextApplied = textMode ~= 1
end

local function Casts(module, c)
    local castEnabled = c.look == 2 and 1 or c.enemyCastEnabled
    if castEnabled == 1 then
        Restore("nameplateShowCastBars")
    else
        module.context:CVar("nameplateShowCastBars", castEnabled == 3 and "0" or "1")
    end
    if c.enemyCastDisplay == 1 or c.look == 2 then
        Restore("nameplateCastBarDisplay")
    else
        local mask = (c.enemyCastSpellName and 1 or 0)
            + (c.enemyCastSpellIcon and 2 or 0)
            + (c.enemyCastSpellTarget and 4 or 0)
            + (c.enemyCastImportant and 8 or 0)
            + (c.enemyCastTargetHighlight and 16 or 0)
        LowBits(module, "nameplateCastBarDisplay", mask, 5)
    end
end

local function Auras(module, c)
    for _, group in ipairs(Style.AuraGroups) do
        local prefix, key = group.key, group.cvar
        if c.look == 2 or c[prefix .. "AuraMode"] ~= 2 then
            Restore(key)
        else
            local mask = (c[prefix .. "Buffs"] and 1 or 0)
                + (c[prefix .. "Debuffs"] and 2 or 0)
                + (c[prefix .. "Control"] and 4 or 0)
            LowBits(module, key, mask, 3)
        end
    end
    Toggle(module, c.look == 2 and 1 or c.friendlyNpcDebuffs, "nameplateShowDebuffsOnFriendly")
    if c.look == 2 or c.auraScaleMode ~= 2 then
        Restore("nameplateAuraScale")
    else
        module.context:CVar("nameplateAuraScale", string.format("%.1f", c.auraScalePercent / 100))
    end
end

-- Keep Blizzard's health-color bit and any future flags. The Suite
-- role-color overlay is independent of both native warning modes.
local function Signals(module, c)
    if c.look == 2 or c.threatSignalMode ~= 2 then
        Restore("nameplateThreatDisplay")
    elseif Style.CVarFlags(C_CVar.GetCVar("nameplateThreatDisplay")) then
        LowBits(module, "nameplateThreatDisplay", (c.threatHighlight and 1 or 0) + (c.threatFlash and 2 or 0), 2)
    end
    local blizzard = c.look == 2
    Toggle(module, blizzard and 1 or c.softTargetEnemy, "SoftTargetIconEnemy")
    Toggle(module, blizzard and 1 or c.softTargetFriend, "SoftTargetIconFriend")
    Toggle(module, blizzard and 1 or c.softTargetInteract, "SoftTargetIconInteract")
    Toggle(module, blizzard and 1 or c.softTargetIconGate, "SoftTargetNameplateSize")
end

-- Settings without a Blizzard look exception: { setting, CVar }.
local CHOICES = {
    { "classColors", "ShowClassColorInNameplate" },
    { "classColors", "nameplateShowClassColor" },
    { "classColors", "nameplateShowFriendlyClassColor" },
    { "friendlyNameClassColor", "nameplateUseClassColorForFriendlyPlayerUnitNames" },
    { "friendlyRealm", "nameplateShowFriendlyRealmName" },
    { "personalAuras", "nameplateShowAllPersonalAuras" },
    { "friendlyNPCs", "nameplateShowFriendlyNpcs" },
    { "playerGuildNames", "UnitNamePlayerGuild" },
    { "playerTitles", "UnitNamePlayerPVPTitle" },
}

local function Names(module, c)
    -- Names-only choice 3 (group members keep their bar) uses the same CVar.
    local namesOnly = c.friendlyNamesOnly or 1
    if namesOnly == 1 then
        Restore("nameplateShowOnlyNameForFriendlyPlayerUnits")
    else
        module.context:CVar("nameplateShowOnlyNameForFriendlyPlayerUnits",
            (namesOnly == 2 or namesOnly == 3) and "1" or "0")
    end
    for i = 1, #CHOICES do
        local choice = CHOICES[i]
        Toggle(module, c[choice[1]] or 1, choice[2])
    end
end

function CVars.Apply(module)
    local c = module.config
    Size(module, c)
    InfoDisplay(module, c)
    Casts(module, c)
    Auras(module, c)
    Signals(module, c)
    Names(module, c)
end
