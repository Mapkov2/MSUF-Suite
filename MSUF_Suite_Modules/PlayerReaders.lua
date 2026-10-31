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

local function Paragon(id)
    local value, threshold, _, pending = C_Reputation.GetFactionParagonInfo(id)
    if not (Finite(value) and Finite(threshold) and threshold > 0) then return end
    -- A reward waiting to be claimed shows the bar full, as Blizzard's does: its
    -- status bar clamps value + threshold to the maximum, so the step stops at it.
    return PARAGON, Public(pending) and pending == true and threshold or value % threshold, threshold, false
end

local function Renown(id)
    local data = C_MajorFactions.GetMajorFactionData(id)
    if not (Table(data) and Finite(data.renownLevel)) then return end
    local label = RENOWN_LEVEL_LABEL:format(data.renownLevel)
    if C_MajorFactions.HasMaximumRenown(id) then return label, 1, 1, true end
    if Finite(data.renownReputationEarned) and Finite(data.renownLevelThreshold) and data.renownLevelThreshold > 0 then
        return label, data.renownReputationEarned, data.renownLevelThreshold, false
    end
end

-- Nothing for a faction that is no friendship: its friendshipFactionID is 0.
local function Friendship(id)
    local info = C_GossipInfo.GetFriendshipReputation(id)
    if not (Table(info) and Finite(info.friendshipFactionID) and info.friendshipFactionID > 0) then return end
    local label = PublicText(info.reaction)
    if not label then return end
    local lower, upper = info.reactionThreshold, info.nextThreshold
    if Finite(lower) and Finite(upper) and Finite(info.standing) and upper > lower then
        return label, info.standing - lower, upper - lower, false
    end
    return label, 1, 1, true
end

local function Standing(data)
    if not Finite(data.reaction) then return end
    local label = PublicText(GetText("FACTION_STANDING_LABEL" .. data.reaction, UnitSex("player")))
    if not label then return end
    local lower, upper = data.currentReactionThreshold, data.nextReactionThreshold
    if data.reaction < MAX_REPUTATION_REACTION and Finite(lower) and Finite(upper) and Finite(data.currentStanding)
        and upper > lower then
        return label, data.currentStanding - lower, upper - lower, false
    end
    return label, 1, 1, true
end

function S.ReputationProgress()
    local data = C_Reputation.GetWatchedFactionData()
    if not (Table(data) and Finite(data.factionID) and data.factionID ~= 0) then return nil end
    local name, id = PublicText(data.name), data.factionID
    if not name then return nil end
    local label, current, maximum, capped, kind
    if C_Reputation.IsFactionParagonForCurrentPlayer(id) then
        label, current, maximum, capped = Paragon(id)
        kind = "paragon"
    elseif C_Reputation.IsMajorFaction(id) then
        label, current, maximum, capped = Renown(id)
        kind = "renown"
    else
        label, current, maximum, capped = Friendship(id)
        kind = "friendship"
        if not label then
            label, current, maximum, capped = Standing(data)
            kind = "standing"
        end
    end
    if not label then return nil end
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
