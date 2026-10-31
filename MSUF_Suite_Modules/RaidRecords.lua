local _, P = ...
local S = P.Suite
local Finite = S.Finite

-- The one store of the character's raid encounter records, shared by the
-- objective tracker's raid view (Raid.lua) and the run summary's raid card
-- (RunSummary.lua): CharacterData("objectives").raidRecords[encounterID ..
-- ":" .. difficultyID] = { fastest, kills, best, bestPhases }. The raid view
-- owns best and bestPhases (wipe progress); fastest and kills are recorded
-- here, by whichever module hears the kill first.
local R = {}
S.RaidRecords = R

-- Both modules hear one ENCOUNTER_END; a second report of the same kill within
-- this many seconds is that kill again.
local SAME_KILL = 5
local lastKey, lastAt, lastBest, lastNewBest, lastKills

-- The run summary once kept its own { best, kills } per encounter in its
-- character data. Its best was the fastest kill, now record.fastest. The old
-- records move once and are dropped, so nothing is counted twice.
local function AdoptSummaryRecords(records)
    local legacy = S.CharacterData("runSummary")
    local old = legacy and legacy.raidRecords
    if type(old) ~= "table" then return end
    for key, entry in pairs(old) do
        if type(entry) == "table" then
            local record = type(records[key]) == "table" and records[key] or {}
            records[key] = record
            if Finite(entry.best) and (not Finite(record.fastest) or entry.best < record.fastest) then
                record.fastest = entry.best
            end
            if Finite(entry.kills) and not (Finite(record.kills) and record.kills >= entry.kills) then
                record.kills = entry.kills
            end
        end
    end
    legacy.raidRecords = nil
end

-- The records and the character's data table, or nil while the character is
-- unknown.
function R.Store()
    local data = S.CharacterData("objectives")
    if not data then return nil end
    if type(data.raidRecords) ~= "table" then data.raidRecords = {} end
    AdoptSummaryRecords(data.raidRecords)
    return data.raidRecords, data
end

-- Counts one kill of an encounter in records (nil while the character is
-- unknown: the figures then describe this kill alone) and keeps the fastest
-- time. Returns the fastest time, whether this kill set it and the kill count.
function R.Kill(records, key, elapsed)
    local now = GetTime()
    if key == lastKey and now - lastAt < SAME_KILL then return lastBest, lastNewBest, lastKills end
    local record = records and records[key]
    if records and type(record) ~= "table" then
        record = {}
        records[key] = record
    end
    local best = record and record.fastest
    local newBest = Finite(elapsed) and (not Finite(best) or elapsed < best) or false
    if newBest then best = elapsed end
    local kills = (record and Finite(record.kills) and record.kills or 0) + 1
    if record then record.fastest, record.kills = best, kills end
    lastKey, lastAt, lastBest, lastNewBest, lastKills = key, now, best, newBest, kills
    return best, newBest, kills
end
