local _, P = ...
local S, Plan = P.Suite, P.PlanningTools
local History = {}
Plan.History = History
local RUN_LIMIT = 100

local function Runs()
    local data = S.CharacterData("runSummary")
    return data and type(data.history) == "table" and data.history or {}
end

local function RunLabel(run)
    return Plan.Text(run.subtitle, 240) or S.Text("Mythic+ dungeon")
end

-- Newest first; the id settles runs saved in the same second.
local function Newer(a, b)
    local left = S.Finite(a.run.recordedAt) and a.run.recordedAt or 0
    local right = S.Finite(b.run.recordedAt) and b.run.recordedAt or 0
    if left ~= right then return left > right end
    return a.run.historyID > b.run.historyID
end

-- A strict weak order. A run saved without a time follows every timed run, so
-- the missing time cannot make the comparison circular.
local function RunOrder(sort)
    return function(a, b)
        if sort == "level" and a.run.level ~= b.run.level then return a.run.level > b.run.level end
        if sort == "time" then
            local timed = S.Finite(a.run.time)
            if timed ~= S.Finite(b.run.time) then return timed end
            if timed and a.run.time ~= b.run.time then return a.run.time < b.run.time end
        end
        return Newer(a, b)
    end
end

function History.Runs(query, minimum, sort)
    local rows = {}
    local notes = Plan.Bucket("runNotes") or {}
    for i, run in ipairs(Runs()) do
        if i > RUN_LIMIT then break end
        if type(run) == "table" and S.Finite(run.historyID) and S.Finite(run.level)
            and run.level >= (minimum or 0) and Plan.Match(query, RunLabel(run), Plan.Date(run.recordedAt)) then
            local key = tostring(run.historyID)
            rows[#rows + 1] = { key = key, label = RunLabel(run), run = run, note = Plan.Text(notes[key], 2000) or "",
                detail = S.Text("%s  |  %s  |  Deaths: %s"):format(Plan.Date(run.recordedAt),
                    S.Finite(run.time) and S.ClockText(run.time) or "--", S.Finite(run.deaths) and run.deaths or "--") }
        end
    end
    table.sort(rows, RunOrder(sort))
    return rows
end

function History.SaveRunNote(key, text)
    if not Plan.CanEdit() then return false end
    text = Plan.Text(text, 2000)
    if not text then return false end
    local found, valid = false, {}
    for i, run in ipairs(Runs()) do
        if i > RUN_LIMIT then break end
        if type(run) == "table" and S.Finite(run.historyID) then
            valid[tostring(run.historyID)] = true
            if tostring(run.historyID) == key then found = true end
        end
    end
    local notes = Plan.Bucket("runNotes")
    if not notes or not found then return false end
    for id in pairs(notes) do if not valid[id] then notes[id] = nil end end
    notes[key] = text ~= "" and text or nil
    Plan.Changed()
    return true
end

local function Difference(a, b, field, label, seconds)
    if not S.Finite(a[field]) or not S.Finite(b[field]) then return S.Text("%s: unavailable"):format(S.Text(label)) end
    local delta = a[field] - b[field]
    return S.Text("%s: %s%s"):format(S.Text(label), delta > 0 and "+" or "",
        seconds and string.format("%.1f s", delta) or tostring(delta))
end

function History.Compare(first, second)
    if type(first) ~= "table" or type(second) ~= "table" then return S.Text("Select two runs to compare.") end
    local lines = { S.Text("First run compared with second run"), RunLabel(first), RunLabel(second),
        Difference(first, second, "level", "Keystone level"), Difference(first, second, "time", "Time", true),
        Difference(first, second, "deaths", "Deaths") }
    if S.Finite(first.mapID) and S.Finite(second.mapID) and first.mapID ~= second.mapID then
        lines[#lines + 1] = S.Text("Different dungeons: times are not directly comparable.")
    end
    if first.level ~= second.level then lines[#lines + 1] = S.Text("Different keystone levels: compare with care.") end
    local left, right = first.splits, second.splits
    if type(left) == "table" and type(right) == "table" then
        local keys = {}
        for index, value in pairs(left) do
            if S.Finite(index) and S.Finite(value) and S.Finite(right[index]) then keys[#keys + 1] = index end
        end
        table.sort(keys)
        for i = 1, math.min(#keys, 12) do
            local index = keys[i]
            lines[#lines + 1] = S.Text("Split %d: %+.1f s"):format(index, left[index] - right[index])
        end
    end
    return table.concat(lines, "\n")
end

function History.Attempt(encounterID, name, difficulty, success, elapsed, progress)
    if not Plan.Active() or not Plan.owner.config.raidHistory then return end
    if not S.Finite(encounterID) or not S.Finite(difficulty) or not S.Finite(success)
        or (success ~= 0 and success ~= 1) then return end
    local now, data = Plan.Now(), Plan.Character()
    if not now or not data then return end
    local list = Plan.Table(data, "attempts")
    data.attemptSerial = (S.Finite(data.attemptSerial) and data.attemptSerial or 0) + 1
    local entry = { id = data.attemptSerial, encounterID = encounterID, difficulty = difficulty, success = success,
        name = Plan.Text(name, 120) or S.Text("Raid encounter"), at = now }
    if S.Finite(elapsed) and elapsed >= 0 then entry.duration = elapsed end
    if type(progress) == "table" and S.Finite(progress.remaining) and progress.remaining >= 0 and progress.remaining <= 100 then
        entry.remaining = progress.remaining
    end
    table.insert(list, 1, entry)
    local limit = math.min(Plan.LIMIT.attempts, math.max(20, Plan.owner.config.keepAttempts or 100))
    while #list > limit do table.remove(list) end
    Plan.Changed()
end

function History.Attempts(query, today)
    local rows, entries = {}, Plan.Bucket("attempts") or {}
    local day = date("%Y-%m-%d", Plan.Now() or 0)
    for i, entry in ipairs(entries) do
        if i > Plan.LIMIT.attempts then break end
        if type(entry) == "table" and S.Finite(entry.at) and Plan.Text(entry.name, 120)
            and (not today or date("%Y-%m-%d", entry.at) == day) and Plan.Match(query, entry.name, Plan.Date(entry.at)) then
            rows[#rows + 1] = { key = tostring(entry.id), label = entry.name, attempt = entry,
                detail = S.Text("%s  |  %s  |  %s"):format(Plan.Date(entry.at),
                    S.Text(entry.success == 1 and "Kill" or "Wipe"), S.Finite(entry.duration) and S.ClockText(entry.duration) or "--") }
        end
    end
    return rows
end

function History.Goals(query)
    local goals, best, rows = Plan.Bucket("goals") or {}, {}, {}
    for _, row in ipairs(History.Runs("")) do
        local run = row.run
        if S.Finite(run.mapID) and run.onTime == true and (not best[run.mapID] or run.level > best[run.mapID].level) then
            best[run.mapID] = run
        end
    end
    for key, goal in pairs(goals) do
        if type(goal) == "table" and Plan.Text(goal.name, 120) and S.Finite(goal.level) and Plan.Match(query, goal.name) then
            local run = best[tonumber(key)]
            local native
            if not P.NS.Client.isForever then
                local timed = C_MythicPlus.GetSeasonBestForMap(tonumber(key))
                if S.Public(timed) and type(timed) == "table" and S.Finite(timed.level) then native = timed.level end
            end
            local level = native or run and run.level
            rows[#rows + 1] = { key = key, label = goal.name, goal = goal, best = run,
                detail = S.Text("Timed best: %s  |  Target: +%d"):format(level and "+" .. level or "--", goal.level),
                checked = level ~= nil and level >= goal.level }
            local row = rows[#rows]
            row.detail = row.detail .. "\n" .. S.Text(native and "Source: current season." or "Source: saved local runs.")
        end
    end
    table.sort(rows, Plan.SortNames)
    return rows
end

function History.SaveGoal(mapID, name, level)
    if not Plan.CanEdit() or not S.Finite(mapID) or mapID <= 0 or not S.Finite(level)
        or level < 2 or level > 99 or level % 1 ~= 0 then return false end
    name = Plan.Name(name)
    local goals = Plan.Bucket("goals")
    if not name or not goals then return false end
    local key = tostring(mapID)
    if not goals[key] and Plan.Count(goals) >= Plan.LIMIT.goals then return false end
    goals[key] = { name = name, level = level }
    Plan.Changed()
    return true
end
