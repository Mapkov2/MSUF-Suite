local _, P = ...
local S = P.Suite
local IN_COMBAT = { inCombat = true }

-- What the experience bar tracks. The "track" setting (MSUF_Suite/Core/
-- Catalog/QualityOfLifeIndicators.lua) chooses experience, the watched
-- reputation, honor, or Automatic: experience below the level cap, then the
-- watched reputation, then honor. Experience is the default and the way the
-- bar always worked. ExperienceBar.lua paints; this file resolves the source,
-- reads it and keeps the bar's events to what the choice needs.
local Track = {}
P.ExperienceTrack = Track
local EXPERIENCE, REPUTATION, HONOR, AUTOMATIC = 1, 2, 3, 4
Track.XP, Track.REPUTATION, Track.HONOR = "xp", "reputation", "honor"
local XP, REP, HON = Track.XP, Track.REPUTATION, Track.HONOR

-- The fill color of each source other than experience (which follows the
-- bar's look): standings and friendships green, renown and paragon blue,
-- honor orange.
local COLORS = { standing = "3fb36b", friendship = "3fb36b", renown = "4a9bd6", paragon = "4a9bd6", honor = "e0802f" }
local SAMPLE_STEP = 2500
local HONOR_NAME, REPUTATION_NAME = S.Text("Honor"), S.Text("Reputation")

-- The source the bar shows now. capped: the player has reached the level cap.
function Track.Source(choice, capped)
    if choice == REPUTATION then return REP end
    if choice == HONOR then return HON end
    if choice ~= AUTOMATIC or not capped then return XP end
    -- Honor is Automatic's last stop: with nothing to read the bar hides.
    return S.ReputationProgress() and REP or HON
end

-- Label, current, maximum, fill color, name and whether nothing is left to
-- earn, for a source's progress; nothing while it has none.
function Track.Read(source)
    if source == REP then
        local info = S.ReputationProgress()
        if info then return info.label, info.current, info.maximum, COLORS[info.kind], info.name, info.capped end
        return
    end
    local current, maximum, level = S.HonorProgress()
    if current then return HONOR_LEVEL_LABEL:format(level), current, maximum, COLORS.honor, HONOR_NAME, false end
end

-- The menu preview: the source the setting shows, with sample values (it
-- never reads the game). Automatic shows what a leveling character sees.
function Track.PreviewSource(choice)
    return choice == REPUTATION and REP or choice == HONOR and HON or XP
end

function Track.Sample(source, percent)
    local current = percent * SAMPLE_STEP / 100
    if source == REP then
        return RENOWN_LEVEL_LABEL:format(12), current, SAMPLE_STEP, COLORS.renown, REPUTATION_NAME
    end
    return HONOR_LEVEL_LABEL:format(25), current, SAMPLE_STEP, COLORS.honor, HONOR_NAME
end

------------------------------------------------------------------ events
-- Only the events the choice needs are registered. Automatic follows the
-- source it shows: while leveling experience alone; with a reputation shown,
-- reputation alone; with honor shown (no reputation is watched) both, so a
-- newly watched reputation takes over.
local XP_EVENTS = { PLAYER_XP_UPDATE = true, PLAYER_LEVEL_UP = true, UPDATE_EXHAUSTION = true }
local REPUTATION_EVENTS = { UPDATE_FACTION = true, MAJOR_FACTION_RENOWN_LEVEL_CHANGED = true }
local HONOR_EVENTS = { HONOR_XP_UPDATE = true }
local FOLLOW_HONOR = { UPDATE_FACTION = true, MAJOR_FACTION_RENOWN_LEVEL_CHANGED = true, HONOR_XP_UPDATE = true }

local function Wanted(choice, source)
    if choice == REPUTATION then return REPUTATION_EVENTS end
    if choice == HONOR then return HONOR_EVENTS end
    if choice == AUTOMATIC then
        if source == REP then return REPUTATION_EVENTS end
        if source == HON then return FOLLOW_HONOR end
    end
    return XP_EVENTS
end

-- Registers the choice's events with handler and drops the ones it no longer
-- needs. The set is one of the tables above, so an unchanged set is one compare.
function Track.SyncEvents(self, source, handler)
    local wanted, previous = Wanted(self.config.track, source), self.trackEvents
    if previous == wanted then return end
    if previous then
        for event in pairs(previous) do
            if not wanted[event] then self.context:RemoveEvent(event) end
        end
    end
    for event in pairs(wanted) do
        if not (previous and previous[event]) then self.context:Event(event, handler, IN_COMBAT) end
    end
    self.trackEvents = wanted
end
