local _, private = ...
local NS, S = private.NS, private.Suite
local Mode, Key = private.Mode, private.Key
local KEEP, SHOW, CUSTOMIZE, HIDE, LOOK_BLIZZARD = Mode.KEEP, Mode.SHOW, Mode.CUSTOMIZE, Mode.HIDE, Mode.LOOK_BLIZZARD
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

-- Several settings that each choose one flag of the same array CVar, flag i
-- from settings[i]: Keep takes the flag the CVar had before the first custom
-- write (or forced[i] when given), Show sets it, Hide clears it. One write
-- carries all of them; with every setting on Keep and nothing forced,
-- Blizzard's value comes back.
local function Flags(module, key, settings, c, forced)
    local custom = false
    for i = 1, #settings do
        if (c[settings[i]] or KEEP) ~= KEEP or forced and forced[i] ~= nil then custom = true end
    end
    local before = module.flagsBefore
    if not custom then
        before[key] = nil
        Restore(key)
        return
    end
    local flags = Style.CVarFlags(C_CVar.GetCVar(key))
    if flags == nil then return end
    if before[key] == nil then before[key] = flags end
    local mask = 0
    for i = 1, #settings do
        local mode, bit = c[settings[i]] or KEEP, 2 ^ (i - 1)
        local on = mode == SHOW
        if mode == KEEP then
            if forced and forced[i] ~= nil then
                on = forced[i]
            else
                on = math.floor(before[key] / bit) % 2 == 1
            end
        end
        if on then mask = mask + bit end
    end
    LowBits(module, key, mask, #settings)
end

-- Blizzard's NamePlateStackType and NamePlateSimplifiedType flags, in order.
local STACKING = { "plateStackEnemy", "plateStackFriendly" }
local SIMPLIFIED = { "plateSimpleMinion", "plateSimpleMinus", "plateSimpleFriendlyPlayer", "plateSimpleFriendlyNpc" }
-- Forced full enemy minion and minor plates (InfoDisplay's names) unless the
-- player chose otherwise.
local FULL_ENEMY_PLATES = { false, false }

local function Visibility(module, c, namesForced)
    Flags(module, "nameplateStackingTypes", STACKING, c)
    Flags(module, "nameplateSimplifiedTypes", SIMPLIFIED, c, namesForced and FULL_ENEMY_PLATES or nil)
end

-- A three-way choice: keep Blizzard's value, write on (SHOW) or off.
local function Toggle(module, mode, key)
    if mode == KEEP then
        Restore(key)
    else
        module.context:CVar(key, mode == SHOW and "1" or "0")
    end
end

local function Size(module, c)
    if c.nativeStyle == KEEP then
        Restore("nameplateStyle")
    elseif c.nativeStyle then
        module.context:CVar("nameplateStyle", tostring(c.nativeStyle - 2))
    end
    if c.nativeSize == KEEP then
        Restore("nameplateSize")
    elseif c.nativeSize then
        module.context:CVar("nameplateSize", tostring(c.nativeSize - 1))
    end
end

-- Blizzard's rarity icon is bit 3 of the same CVar as the two health text
-- flags. Compose one write so either control preserves the other.
local function InfoDisplay(module, c)
    local textMode = c.enemy and c.look ~= LOOK_BLIZZARD and c.enemyTextMode or KEEP
    local rarityMode = c.enemy and c.look ~= LOOK_BLIZZARD and c.enemyRarityIcon or KEEP
    -- Forced names also need full minion and minor plates (Visibility).
    if textMode == KEEP then
        Restore("nameplateForceShowUnitName")
    else
        module.context:CVar("nameplateForceShowUnitName", "1")
    end
    if textMode == KEEP and (rarityMode == KEEP or module.infoTextApplied) then Restore("nameplateInfoDisplay") end
    if textMode ~= KEEP or rarityMode ~= KEEP then
        local flags = Style.CVarFlags(C_CVar.GetCVar("nameplateInfoDisplay"))
        if flags ~= nil then
            local textBits = textMode == KEEP and flags % 4 or textMode - 1
            local currentRarity = flags % 8 - flags % 4
            if rarityMode ~= KEEP and module.rarityBefore == nil then module.rarityBefore = currentRarity end
            local rarityBit = rarityMode == KEEP and (module.rarityBefore or currentRarity)
                or (rarityMode == SHOW and 4 or 0)
            LowBits(module, "nameplateInfoDisplay", textBits + rarityBit, 3)
            if rarityMode == KEEP then module.rarityBefore = nil end
        end
    else
        module.rarityBefore = nil
    end
    module.infoTextApplied = textMode ~= KEEP
end

local function Casts(module, c)
    local castEnabled = c.look == LOOK_BLIZZARD and KEEP or c.enemyCastEnabled
    if castEnabled == KEEP then
        Restore("nameplateShowCastBars")
    else
        module.context:CVar("nameplateShowCastBars", castEnabled == HIDE and "0" or "1")
    end
    if c.enemyCastDisplay == KEEP or c.look == LOOK_BLIZZARD then
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
        local keys, key = Key[group.key], group.cvar
        if c.look == LOOK_BLIZZARD or c[keys.AuraMode] ~= CUSTOMIZE then
            Restore(key)
        else
            local mask = (c[keys.Buffs] and 1 or 0)
                + (c[keys.Debuffs] and 2 or 0)
                + (c[keys.Control] and 4 or 0)
            LowBits(module, key, mask, 3)
        end
    end
    Toggle(module, c.look == LOOK_BLIZZARD and KEEP or c.friendlyNpcDebuffs, "nameplateShowDebuffsOnFriendly")
    if c.look == LOOK_BLIZZARD or c.auraScaleMode ~= CUSTOMIZE then
        Restore("nameplateAuraScale")
    else
        module.context:CVar("nameplateAuraScale", string.format("%.1f", c.auraScalePercent / 100))
    end
end

-- Keep Blizzard's health-color bit and any future flags. The Suite
-- role-color overlay is independent of both native warning modes.
local function Signals(module, c)
    if c.look == LOOK_BLIZZARD or c.threatSignalMode ~= CUSTOMIZE then
        Restore("nameplateThreatDisplay")
    elseif Style.CVarFlags(C_CVar.GetCVar("nameplateThreatDisplay")) then
        LowBits(module, "nameplateThreatDisplay", (c.threatHighlight and 1 or 0) + (c.threatFlash and 2 or 0), 2)
    end
    local blizzard = c.look == LOOK_BLIZZARD
    Toggle(module, blizzard and KEEP or c.softTargetEnemy, "SoftTargetIconEnemy")
    Toggle(module, blizzard and KEEP or c.softTargetFriend, "SoftTargetIconFriend")
    Toggle(module, blizzard and KEEP or c.softTargetInteract, "SoftTargetIconInteract")
    Toggle(module, blizzard and KEEP or c.softTargetIconGate, "SoftTargetNameplateSize")
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
    { "plateShowAll", "nameplateShowAll" },
    { "plateEnemyMinions", "nameplateShowEnemyMinions" },
    { "plateEnemyMinus", "nameplateShowEnemyMinus" },
    { "plateFriendlyMinions", "nameplateShowFriendlyPlayerMinions" },
    { "plateOffscreen", "nameplateShowOffscreen" },
}

local function Names(module, c)
    -- Names only for party / raid (group members keep their bar) uses the same CVar.
    local namesOnly = c.friendlyNamesOnly or KEEP
    if namesOnly == KEEP then
        Restore("nameplateShowOnlyNameForFriendlyPlayerUnits")
    else
        module.context:CVar("nameplateShowOnlyNameForFriendlyPlayerUnits",
            (namesOnly == Mode.ALL_NAMES_ONLY or namesOnly == Mode.GROUP_NAMES_ONLY) and "1" or "0")
    end
    for i = 1, #CHOICES do
        local choice = CHOICES[i]
        Toggle(module, c[choice[1]] or KEEP, choice[2])
    end
end

-- Blizzard may lock CVars during combat: a write then waits for its end
-- (Skin.lua OnCombatEnded) instead of failing half applied.
function CVars.Apply(module)
    if NS.InCombat() then
        module.cvarsPending = true
        return
    end
    module.cvarsPending = nil
    module.flagsBefore = module.flagsBefore or {}
    local c = module.config
    Size(module, c)
    InfoDisplay(module, c)
    Visibility(module, c, module.infoTextApplied)
    Casts(module, c)
    Auras(module, c)
    Signals(module, c)
    Names(module, c)
end
