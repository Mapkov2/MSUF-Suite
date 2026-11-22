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
-- write, Show sets it, Hide clears it. A name-only category needs a full
-- plate unless the user explicitly chose simplification.
local function Flags(module, key, settings, c, full)
    local custom = false
    for i = 1, #settings do
        if (c[settings[i]] or KEEP) ~= KEEP or full and full[i] then custom = true end
    end
    local before = module.flagsBefore
    if not custom then
        before[key] = nil
        Restore(key)
        return
    end
    local current = C_CVar.GetCVar(key)
    local flags = Style.CVarFlags(current)
    if flags == nil then return end
    if before[key] == nil then
        local baseline = S.CVarBaseline and S.CVarBaseline("nameplates", key, current)
        before[key] = Style.CVarFlags(baseline) or flags
    end
    local mask = 0
    for i = 1, #settings do
        local mode, bit = c[settings[i]] or KEEP, 2 ^ (i - 1)
        local on = mode == SHOW
        if mode == KEEP and not (full and full[i]) then
            on = math.floor(before[key] / bit) % 2 == 1
        end
        if on then mask = mask + bit end
    end
    LowBits(module, key, mask, #settings)
end

-- Blizzard's NamePlateStackType and NamePlateSimplifiedType flags, in order.
local STACKING = { "plateStackEnemy", "plateStackFriendly" }
local SIMPLIFIED = { "plateSimpleMinion", "plateSimpleMinus", "plateSimpleFriendlyPlayer", "plateSimpleFriendlyNpc" }
local function Visibility(module, c, enemyText)
    Flags(module, "nameplateStackingTypes", STACKING, c)
    local playerNames = c.friendlySkinEnabled ~= false
        and (c.friendlyNamesOnly == Mode.ALL_NAMES_ONLY or c.friendlyNamesOnly == Mode.GROUP_NAMES_ONLY)
    -- Blizzard can use either friendly simplification bit for NPCs, including
    -- reaction-neutral NPCs and UnitTreatAsPlayerForDisplay. Minion and minus
    -- are independent of friendship. Simplified plates hide unselected names.
    local friendlyNPCNames = c.friendlyNpcSkinEnabled ~= false and NS.NameplateExtensions
        and c.friendlyNPCs == NS.NameplateExtensions.NPC_PLATE_NAME_ONLY
    local friendlyTemplates = friendlyNPCNames or c.neutralSkinEnabled ~= false and c.neutralPlateNameOnly
    local minor = friendlyTemplates or c.enemySkinEnabled ~= false and c.enemyPlateNameOnly
        or enemyText and (c.enemySkinEnabled ~= false or c.neutralSkinEnabled ~= false)
    local full = { minor, minor, playerNames or friendlyTemplates, friendlyTemplates }
    Flags(module, "nameplateSimplifiedTypes", SIMPLIFIED, c, full)
    if minor or playerNames then
        module.context:CVar("nameplateForceShowUnitName", "1")
    else
        Restore("nameplateForceShowUnitName")
    end
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
    if c.targetScaleEnabled then
        module.context:CVar("nameplateSelectedScale", tostring(Style.Decor.TargetScale(c)))
    else
        Restore("nameplateSelectedScale")
    end
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
    if textMode == KEEP and (rarityMode == KEEP or module.infoTextApplied) then Restore("nameplateInfoDisplay") end
    if textMode ~= KEEP or rarityMode ~= KEEP then
        local flags = Style.CVarFlags(C_CVar.GetCVar("nameplateInfoDisplay"))
        if flags ~= nil then
            local textBits = textMode == KEEP and flags % 4 or (textMode - 1) % 4
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
    if c.look ~= LOOK_BLIZZARD and (c.auraDebuffPadding or -1) >= 0 then
        module.context:CVar("nameplateDebuffPadding", tostring(c.auraDebuffPadding))
    else
        Restore("nameplateDebuffPadding")
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
    { "playerGuildNames", "UnitNamePlayerGuild" },
    { "playerTitles", "UnitNamePlayerPVPTitle" },
    { "plateShowAll", "nameplateShowAll" },
    { "plateEnemyMinions", "nameplateShowEnemyMinions" },
    { "plateEnemyMinus", "nameplateShowEnemyMinus" },
    { "plateFriendlyMinions", "nameplateShowFriendlyPlayerMinions" },
    { "plateOffscreen", "nameplateShowOffscreen" },
    -- The combined minion choices above keep applying; these set each kind alone.
    { "plateEnemyGuardians", "nameplateShowEnemyGuardians" },
    { "plateEnemyTotems", "nameplateShowEnemyTotems" },
    { "plateFriendlyGuardians", "nameplateShowFriendlyPlayerGuardians" },
    { "plateFriendlyTotems", "nameplateShowFriendlyPlayerTotems" },
    { "plateClampTarget", "clampTargetNameplateToScreen" },
}

local PET_WORLD_NAMES_ONLY = 4
local function PetDisplay(module, mode, plateCVar, nameCVar)
    mode = mode or KEEP
    if mode == PET_WORLD_NAMES_ONLY then
        Toggle(module, HIDE, plateCVar)
        Toggle(module, SHOW, nameCVar)
    else
        Toggle(module, mode, plateCVar)
        Toggle(module, mode == HIDE and HIDE or KEEP, nameCVar)
    end
end

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
    PetDisplay(module, c.plateEnemyPets, "nameplateShowEnemyPets", "UnitNameEnemyPetName")
    PetDisplay(module, c.plateFriendlyPets, "nameplateShowFriendlyPlayerPets", "UnitNameFriendlyPetName")
    local npcs = c.friendlyNpcSkinEnabled ~= false
    local worldNames = npcs and c.friendlyNPCs == Mode.NPC_NAMES_ONLY
    Toggle(module, (c.enemySkinEnabled ~= false or c.neutralSkinEnabled ~= false) and SHOW or HIDE, "nameplateShowEnemies")
    if c.friendlySkinEnabled == false then
        Toggle(module, HIDE, "nameplateShowFriendlyPlayers")
    else
        S.ForgetCVar("nameplates", "nameplateShowFriendlyPlayers")
    end
    if not npcs or worldNames then
        Toggle(module, HIDE, "nameplateShowFriendlyNpcs")
    else
        if module.friendlyNpcNamesOnly then Restore("nameplateShowFriendlyNpcs") end
        S.ForgetCVar("nameplates", "nameplateShowFriendlyNpcs")
    end
    module.friendlyNpcNamesOnly = worldNames
    -- Blizzard's NPC Names = All (SettingsDefinitions_Frame/Nameplates.lua).
    Toggle(module, worldNames and SHOW or KEEP, "UnitNameNPC")
end

-- The "Customize" pairs of Distance and stacking: { mode setting, number
-- setting, CVar, divisor from the shown unit (yards, percent) to the CVar's }.
local PERCENT = 100
local CUSTOM_VALUES = {
    { "plateMaxDistanceMode", "plateMaxDistance", "nameplateMaxDistance", 1 },
    { "plateOccludedMode", "plateOccludedPercent", "nameplateOccludedAlphaMult", PERCENT },
    { "plateSpacingMode", "plateOverlapV", "nameplateOverlapV", PERCENT },
    { "plateSpacingMode", "plateOverlapH", "nameplateOverlapH", PERCENT },
    { "plateInsetMode", "plateTopInset", "nameplateOtherTopInset", PERCENT },
    { "plateInsetMode", "plateBottomInset", "nameplateOtherBottomInset", PERCENT },
}
-- Its presets, { setting, CVar, value per choice }; choice 1 keeps Blizzard's.
-- Fade and shrink set the far end of Blizzard's range (nameplateMinAlpha 0.6,
-- nameplateMinScale 0.8): None, Subtle, Strong. Motion speed (0.025): Slow,
-- Fast, Instant. Neither touches the current target's scale or the dimming
-- of other plates (Size, Selection.lua): those are separate values.
local PRESETS = {
    { "plateFadeDistance", "nameplateMinAlpha", { [2] = 1, [3] = 0.8, [4] = 0.3, [5] = 0.6 } },
    { "plateShrinkDistance", "nameplateMinScale", { [2] = 1, [3] = 0.9, [4] = 0.6, [5] = 0.8 } },
    { "plateMotionSpeed", "nameplateMotionSpeed", { [2] = 0.01, [3] = 0.1, [4] = 1, [5] = 0.025 } },
}

local function Space(module, c)
    for i = 1, #CUSTOM_VALUES do
        local row = CUSTOM_VALUES[i]
        if c[row[1]] == CUSTOMIZE then
            module.context:CVar(row[3], tostring(c[row[2]] / row[4]))
        else
            Restore(row[3])
        end
    end
    for i = 1, #PRESETS do
        local row = PRESETS[i]
        local value = row[3][c[row[1]]]
        if value then module.context:CVar(row[2], tostring(value)) else Restore(row[2]) end
    end
end

-- Blizzard may lock CVars during combat: a write then waits for its end
-- (Skin.lua OnCombatEnded) instead of failing half applied.
function CVars.Apply(module)
    if NS.InCombat() then
        module.cvarsPending = true
        return
    end
    -- The controller's queued refresh may run before the module's regen
    -- event. Reconcile the native action before either path reapplies Off.
    if module.friendlyVisibilityPending then NS.SyncFriendlyNameplates(module) end
    module.cvarsPending = nil
    module.flagsBefore = module.flagsBefore or {}
    local c = module.config
    Size(module, c)
    InfoDisplay(module, c)
    Visibility(module, c, module.infoTextApplied)
    Casts(module, c)
    Auras(module, c)
    Signals(module, c)
    local visibilityWriting = module.friendlyVisibilityWriting
    module.friendlyVisibilityWriting = true
    Names(module, c)
    NS.CaptureFriendlyNameplates(module)
    module.friendlyVisibilityWriting = visibilityWriting
    Space(module, c)
end
