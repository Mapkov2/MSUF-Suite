local _, Private = ...
local S = Private.Suite
local Finite, PublicText, Public = S.Finite, S.PublicText, S.Public

-- Readers of the player's own state that more than one Suite surface shows:
-- the secondary stats (the combat stats strip, the Secondary stat DataText)
-- and the watched reputation and honor (the experience bar, the XP /
-- reputation DataText). Each returns nil while the client withholds a value.

------------------------------------------------------------------ secondary stats
-- Percent of one stat as the character sheet shows it.
function S.ReadPercent(read)
    local value = read()
    return Finite(value) and value or nil
end
local ReadPercent = S.ReadPercent

-- Match Blizzard's PaperDollFrame crit display: the highest of melee,
-- ranged and the lowest spell-school value. One restricted school leaves the
-- result unknown rather than silently showing a misleading partial maximum.
-- The second result is the combat rating constant of the winning type.
function S.ReadCrit()
    local melee = ReadPercent(GetCritChance)
    local ranged = ReadPercent(GetRangedCritChance)
    if not melee or not ranged then return nil end
    local spell
    for school = 2, 7 do
        local value = GetSpellCritChance(school)
        if not Finite(value) then return nil end
        spell = spell and math.min(spell, value) or value
    end
    if spell >= ranged and spell >= melee then return spell, _G.CR_CRIT_SPELL end
    if ranged >= melee then return ranged, _G.CR_CRIT_RANGED end
    return melee, _G.CR_CRIT_MELEE
end

function S.ReadHaste()
    return ReadPercent(GetHaste)
end

function S.ReadMastery()
    return ReadPercent(GetMasteryEffect)
end

function S.ReadVersatility()
    local rating = CR_VERSATILITY_DAMAGE_DONE
    local fromRating = GetCombatRatingBonus(rating)
    local fromEffects = GetVersatilityBonus(rating)
    if Finite(fromRating) and Finite(fromEffects) then return fromRating + fromEffects end
end

function S.ReadLeech()
    return ReadPercent(GetLifesteal)
end

------------------------------------------------------------------ reputation
-- Where the watched faction stands, as Blizzard's reputation bar reads it
-- (ReputationStatusBarMixin:Update, live and forever): paragon progress, then
-- renown, then friendship ranks, then the plain standing. S.ReputationProgress()
-- returns one table that the next call overwrites, or nil without a watched
-- faction:
--   name     the faction
--   label    the standing in the client's words ("Friendly", "Renown 12", "Paragon")
--   current  progress inside the current step (0-based)
--   maximum  size of that step; current >= maximum for a capped faction
--   kind     "standing", "renown", "friendship" or "paragon"
--   capped   true when nothing is left to earn (Exalted, maximum renown or rank)
local progress = {}
local PARAGON = S.Text("Paragon")

local function Table(value)
    return Public(value) and type(value) == "table"
end

local function Flag(value)
    return Public(value) and value == true
end

local function Paragon(id)
    local value, threshold, _, pending, tooLowLevel = C_Reputation.GetFactionParagonInfo(id)
    if not (Finite(value) and Finite(threshold) and threshold > 0) then return end
    -- A waiting reward fills the current bar, matching the native status bar.
    pending = Flag(pending)
    local claimable = pending and Public(tooLowLevel) and tooLowLevel ~= true
    return PARAGON, pending and threshold or value % threshold, threshold, false, nil, claimable
end

local function Renown(id, detailed)
    local data = C_MajorFactions.GetMajorFactionData(id)
    if not (Table(data) and Finite(data.renownLevel)) then return end
    local level = data.renownLevel
    local label = RENOWN_LEVEL_LABEL:format(level)
    if not detailed then return label end
    if Flag(C_MajorFactions.HasMaximumRenown(id)) then return label, 1, 1, true end
    if Finite(data.renownReputationEarned) and Finite(data.renownLevelThreshold) and data.renownLevelThreshold > 0 then
        return label, data.renownReputationEarned, data.renownLevelThreshold, false, level + 1
    end
    return label
end

local function Friendship(id, detailed)
    local info = C_GossipInfo.GetFriendshipReputation(id)
    if not (Table(info) and Finite(info.friendshipFactionID) and info.friendshipFactionID > 0) then return end
    local label = PublicText(info.reaction)
    if not label or not detailed then return label end
    local upper = info.nextThreshold
    if not Public(upper) then return label end
    if upper == nil then return label, 1, 1, true end
    local lower, value = info.reactionThreshold, info.standing
    if Finite(lower) and Finite(upper) and Finite(value) and upper > lower then
        return label, value - lower, upper - lower, false
    end
    return label
end

local labelsBySex = {}
function S.ReputationStandingLabel(reaction, sex)
    if not Finite(reaction) or not Finite(sex) then return end
    local labels = labelsBySex[sex]
    if not labels then
        labels = {}
        labelsBySex[sex] = labels
    end
    local label = labels[reaction]
    if not label then
        label = PublicText(GetText("FACTION_STANDING_LABEL" .. reaction, sex))
        labels[reaction] = label
    end
    return label
end

local function Standing(data, sex, detailed)
    local reaction = data.reaction
    if sex == nil then sex = UnitSex("player") end
    local label = S.ReputationStandingLabel(reaction, sex)
    if not label or not detailed then return label end
    if reaction == MAX_REPUTATION_REACTION then return label, 1, 1, true end
    local lower, upper, value = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
    if Finite(lower) and Finite(upper) and Finite(value) and upper > lower then
        return label, value - lower, upper - lower, false, reaction + 1
    end
    return label
end

-- Reuse the caller's faction data. The list reader already holds the native
-- row and the player's sex, so no watched lookup or second scan is needed.
function S.ReadFactionReputation(data, sex, detailed)
    local id = data.factionID
    if Finite(id) and id > 0 then
        if detailed and Flag(C_Reputation.IsFactionParagonForCurrentPlayer(id)) then
            local label, current, maximum, capped, nextLevel, pending = Paragon(id)
            if label then return "paragon", label, current, maximum, capped, nextLevel, pending end
        end
        if Flag(C_Reputation.IsMajorFaction(id)) then
            local label, current, maximum, capped, nextLevel = Renown(id, detailed)
            if label then return "renown", label, current, maximum, capped, nextLevel end
        end
        local label, current, maximum, capped = Friendship(id, detailed)
        if label then return "friendship", label, current, maximum, capped end
    end
    return "standing", Standing(data, sex, detailed)
end

function S.ReputationProgress()
    local data = C_Reputation.GetWatchedFactionData()
    if not (Table(data) and Finite(data.factionID) and data.factionID ~= 0) then return nil end
    local name = PublicText(data.name)
    if not name then return nil end
    local kind, label, current, maximum, capped = S.ReadFactionReputation(data, nil, true)
    if not label or not current or not maximum then return nil end
    progress.name, progress.label, progress.current, progress.maximum = name, label, current, maximum
    progress.kind, progress.capped = kind, capped
    return progress
end

------------------------------------------------------------------ honor
-- Honor earned toward the next honor level: current, maximum and the level.
function S.HonorProgress()
    local current, maximum, level = UnitHonor("player"), UnitHonorMax("player"), UnitHonorLevel("player")
    if Finite(current) and Finite(maximum) and maximum > 0 and Finite(level) then return current, maximum, level end
end
