local _, Suite = ...

-- Records a character collects while playing (Mythic+ run history, boss
-- splits, raid records) live in MSUFSuiteDB.suiteCharacters[player GUID]
-- [owner], outside every profile: profile copies, variants and exports never
-- carry them, and a profile switch keeps the character's history. The
-- owners cap their own lists (run history, split buckets).
local ROOT_KEY = "suiteCharacters"

local function Table(parent, key)
    local value = parent[key]
    if type(value) ~= "table" then
        value = {}
        parent[key] = value
    end
    return value
end

-- The current character's table of one owner, or nil while the database or
-- the character's GUID is unreadable.
function Suite.CharacterData(owner)
    local root = Suite.RootDB
    local guid = Suite.PublicText(UnitGUID("player"))
    if type(root) ~= "table" or not guid then return nil end
    return Table(Table(Table(root, ROOT_KEY), guid), owner)
end

------------------------------------------------------------------ migration
-- Older builds kept these records in each profile's moduleState.
local MOVED = {
    runSummary = { "history", "historySerial", "last", "raidRecords" },
    objectives = { "mythicSplits", "mythicSplitSerial", "raidRecords" },
}

-- Raid wipe progress was once stored as the 0..1 encounter-end fraction.
local function WipePercent(progress)
    if type(progress) ~= "table" then return end
    local remaining = progress.remaining
    if Suite.Finite(remaining) and remaining >= 0 and remaining <= 1 then progress.remaining = remaining * 100 end
end

local function RaidRecordsInPercent(state)
    if state.raidRecordsHealthScale == 100 or type(state.raidRecords) ~= "table" then return end
    for _, record in pairs(state.raidRecords) do
        if type(record) == "table" then
            WipePercent(record.best)
            if type(record.bestPhases) == "table" then
                for _, phase in pairs(record.bestPhases) do WipePercent(phase) end
            end
        end
    end
end

local function SameRun(a, b)
    return a.recordedAt == b.recordedAt and a.mapID == b.mapID and a.level == b.level and a.time == b.time
end

-- Merges a profile's run list into the character's, newest first, and gives
-- every run a fresh ID (two profiles numbered their runs independently).
local function MergeHistory(data, list)
    local history = {}
    for _, run in ipairs(data.history) do
        if type(run) == "table" then history[#history + 1] = run end
    end
    for _, run in ipairs(list) do
        local known = type(run) ~= "table"
        for i = 1, #history do
            if not known and SameRun(history[i], run) then known = true end
        end
        if not known then history[#history + 1] = run end
    end
    data.history = history
    table.sort(history, function(a, b) return (tonumber(a.recordedAt) or 0) > (tonumber(b.recordedAt) or 0) end)
    for i = 1, #history do history[i].historyID = #history - i + 1 end
    data.historySerial = #history
end

local function Adopt(data, key, value)
    if key == "last" then
        -- One saved result replaces the former copy: raid results stay,
        -- Mythic+ results are the newest history entry.
        if type(value) == "table" and data.lastKind == nil then
            data.lastKind = value.kind == "raid" and "raid" or "mythic"
            if value.kind == "raid" then data.lastRaid = value end
        end
    elseif key == "history" and type(value) == "table" then
        if type(data.history) ~= "table" then data.history = {} end
        MergeHistory(data, value)
    elseif key == "historySerial" then
        data.historySerial = data.historySerial or value
    elseif type(value) == "table" then
        -- Keyed records: the character's own entry of a key stays.
        local target = type(data[key]) == "table" and data[key] or {}
        for record, entry in pairs(value) do
            if target[record] == nil then target[record] = entry end
        end
        data[key] = target
    elseif data[key] == nil then
        data[key] = value
    end
end

local function HasRecords(state, keys)
    for _, key in ipairs(keys) do
        if state[key] ~= nil then return true end
    end
    return false
end

-- MIGRATIONS step (MSUF_Suite/Core/Suite.lua): the character that next
-- loads a profile adopts its records once and the profile drops them.
-- With an unreadable character the records stay where they are and the step
-- returns false, so it runs again at the next normalization.
function Suite.MoveRunRecordsToCharacter(_, db)
    local states = db.moduleState
    if type(states) ~= "table" then return end
    local waiting = false
    for owner, keys in pairs(MOVED) do
        local state = states[owner]
        local data = type(state) == "table" and Suite.CharacterData(owner)
        if data then
            if owner == "objectives" then RaidRecordsInPercent(state) end
            for _, key in ipairs(keys) do
                if state[key] ~= nil then
                    Adopt(data, key, state[key])
                    state[key] = nil
                end
            end
            state.raidRecordsHealthScale = nil
        elseif type(state) == "table" and HasRecords(state, keys) then
            waiting = true
        end
    end
    if waiting then return false end
end
