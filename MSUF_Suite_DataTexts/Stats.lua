local _, P = ...
local NS, S = P.NS, P.Suite
local Sources, NO_VALUE = P.DataTextSources, P.NO_VALUE
local Finite, PublicText = S.Finite, S.PublicText
local STAT = NS.DataTextStat

-- The Secondary stat and Mythic+ rating places. Both read their value on the
-- event that changes it (Sources.lua routes the events) and add detail lines
-- to their tooltip when the pointer rests on them, out of combat.
local GRAY = .7

------------------------------------------------------------------ secondary stats
-- One place shows one stat (bar<N>Slot<M>Stat); the readers are the ones the
-- combat stats strip uses (MSUF_Suite_Modules/PlayerReaders.lua).
local Stat = { delay = .05 }
local READERS = { [STAT.CRIT] = S.ReadCrit, [STAT.HASTE] = S.ReadHaste, [STAT.MASTERY] = S.ReadMastery,
    [STAT.VERSATILITY] = S.ReadVersatility, [STAT.LEECH] = S.ReadLeech }
local SHORT = { [STAT.CRIT] = S.Text("Crit"), [STAT.HASTE] = S.Text("Haste"), [STAT.MASTERY] = S.Text("Mastery"),
    [STAT.VERSATILITY] = S.Text("Vers"), [STAT.LEECH] = S.Text("Leech") }
local FULL = { [STAT.CRIT] = S.Text("Critical strike"), [STAT.HASTE] = S.Text("Haste"),
    [STAT.MASTERY] = S.Text("Mastery"), [STAT.VERSATILITY] = S.Text("Versatility"), [STAT.LEECH] = S.Text("Leech") }

local function Percent(stat)
    local value = READERS[stat]()
    return value and string.format("%.1f%%", value) or NO_VALUE
end

function Stat.Format(binding)
    local stat = READERS[binding.stat] and binding.stat or STAT.CRIT
    return SHORT[stat], Percent(stat)
end

function Stat.Lines(tooltip)
    if NS.InCombat() then return end
    for stat = 1, #FULL do tooltip:AddDoubleLine(FULL[stat], Percent(stat), 1, 1, 1, 1, 1, 1) end
end

Sources.Register("secondaryStat", Stat,
    { "COMBAT_RATING_UPDATE", "MASTERY_UPDATE", "UNIT_STATS", "UNIT_SPELL_HASTE" })

------------------------------------------------------------------ Mythic+ rating
local Rating = { delay = .2 }
local TEXT = {
    label = S.Text("Mythic+ rating"),
    level = S.Text("+%d"),
}
local RUN_ROWS = 12

-- The player's current season score; Mythic+ exists on Retail only.
function Rating.Format()
    if NS.Client.isForever then return TEXT.label, NO_VALUE end
    local score = C_ChallengeMode.GetOverallDungeonScore()
    return TEXT.label, Finite(score) and tostring(math.floor(score + .5)) or NO_VALUE
end

-- The season's dungeons with their score and best key level.
function Rating.Lines(tooltip)
    if NS.Client.isForever or NS.InCombat() then return end
    local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
    local runs = S.Public(summary) and type(summary) == "table" and summary.runs
    if type(runs) ~= "table" then return end
    for index = 1, math.min(#runs, RUN_ROWS) do
        local run = runs[index]
        local name = type(run) == "table" and Finite(run.challengeModeID) and Finite(run.mapScore)
            and PublicText(C_ChallengeMode.GetMapUIInfo(run.challengeModeID))
        if name then
            local level = Finite(run.bestRunLevel) and run.bestRunLevel > 0 and TEXT.level:format(run.bestRunLevel) or ""
            tooltip:AddDoubleLine(level ~= "" and level .. " " .. name or name, tostring(math.floor(run.mapScore + .5)),
                1, 1, 1, GRAY, GRAY, GRAY)
        end
    end
end

-- Forever has no Mythic+, so its place subscribes to nothing.
Sources.Register("mythicRating", Rating, NS.Client.isForever and {}
    or { "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_MAPS_UPDATE" })
