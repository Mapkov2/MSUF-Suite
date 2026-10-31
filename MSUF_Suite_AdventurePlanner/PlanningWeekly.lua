local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local Weekly = {}
Plan.Weekly = Weekly
local WEEK = 7 * 24 * 60 * 60

function Weekly.Reset()
    if NS.Client.isForever then return nil end
    local value = C_DateAndTime.GetWeeklyResetStartTime()
    return S.Finite(value) and value or nil
end

-- "fresh": the snapshot is from this reset. "past": it is from an earlier,
-- known reset, so the character has done nothing this week (it was offline).
-- nil: the reset is unknown and so is this week's progress.
function Weekly.Freshness(entry, reset)
    if not reset or not S.Finite(entry.reset) then return nil end
    if entry.reset == reset then return "fresh" end
    if entry.reset < reset then return "past", entry.reset == reset - WEEK end
end

local function Vault()
    if NS.Client.isForever then return nil end
    local activities = C_WeeklyRewards.GetActivities()
    if not S.Public(activities) or type(activities) ~= "table" then return nil end
    local rows = {}
    for i = 1, math.min(#activities, 16) do
        local a = activities[i]
        if S.Public(a) and type(a) == "table" and S.Finite(a.type) and S.Finite(a.index)
            and S.Finite(a.progress) and S.Finite(a.threshold) then
            rows[#rows + 1] = { kind = a.type, index = a.index, progress = a.progress, threshold = a.threshold,
                level = S.Finite(a.level) and a.level or nil }
        end
    end
    local ready = C_WeeklyRewards.HasAvailableRewards()
    if not S.Public(ready) then return rows end
    return rows, ready == true
end

-- Boss names and kills of one saved instance, when the client offers them.
local function Encounters(index, bosses)
    if not GetSavedInstanceEncounterInfo or not S.Finite(bosses) or bosses <= 0 then return nil end
    local list = {}
    for i = 1, math.min(bosses, 30) do
        local name, _, killed = GetSavedInstanceEncounterInfo(index, i)
        name = Plan.Text(name, 120)
        if name and S.Public(killed) then list[#list + 1] = { name = name, killed = killed == true } end
    end
    return list
end

local function Lockouts(now)
    local count = GetNumSavedInstances()
    if not S.Finite(count) then return nil end
    local rows = {}
    for i = 1, math.min(count, 200) do
        local name, _, reset, difficulty, locked, extended, _, raid, _, difficultyName, bosses, defeated = GetSavedInstanceInfo(i)
        name = Plan.Text(name, 120)
        if name and S.Finite(reset) and S.Finite(difficulty) and S.Public(locked) and S.Public(extended)
            and S.Public(raid) and (locked == true or extended == true) then
            rows[#rows + 1] = { name = name, expires = now + math.max(0, reset), difficulty = difficulty,
                difficultyName = Plan.Text(difficultyName, 80), raid = raid == true, extended = extended == true,
                bosses = S.Finite(bosses) and bosses or nil, defeated = S.Finite(defeated) and defeated or nil,
                encounters = Encounters(i, bosses) }
        end
    end
    return rows
end

local function WorldBosses(now)
    local count = GetNumSavedWorldBosses()
    if not S.Finite(count) then return nil end
    local rows = {}
    for i = 1, math.min(count, 30) do
        local name, _, reset = GetSavedWorldBossInfo(i)
        name = Plan.Text(name, 120)
        if name and S.Finite(reset) then rows[#rows + 1] = { name = name, expires = now + math.max(0, reset) } end
    end
    return rows
end

local function Keystone()
    if NS.Client.isForever then return nil end
    local id, _, level = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
    if not S.Public(id) or not S.Public(level) then return nil, nil, nil, true end
    if not S.Finite(id) or id <= 0 then id, _, level = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel(true) end
    if not S.Public(id) or not S.Public(level) then return nil, nil, nil, true end
    if not S.Finite(id) or id <= 0 then return nil end
    if not S.Finite(level) or level <= 0 then return nil, nil, id, true end
    local info = C_LFGList.GetActivityInfoTable(id)
    local name = S.Public(info) and type(info) == "table" and Plan.Text(info.fullName, 120)
    if name == "" then name = nil end
    return name, level, id, not name
end

-- The better of Blizzard's in-time and overtime season bests, as the
-- Mythic+ panel picks it.
local function SeasonBest(id)
    local timed, overtime = C_MythicPlus.GetSeasonBestForMap(id)
    timed = S.Public(timed) and type(timed) == "table" and S.Finite(timed.level) and S.Finite(timed.dungeonScore) and timed or nil
    overtime = S.Public(overtime) and type(overtime) == "table" and S.Finite(overtime.level)
        and S.Finite(overtime.dungeonScore) and overtime or nil
    local best = timed and (not overtime or timed.dungeonScore >= overtime.dungeonScore) and timed or overtime
    if not best then return { id = id, level = 0, score = 0 } end
    return { id = id, level = best.level, score = best.dungeonScore, timed = best == timed }
end

-- Retain the best forty detail rows while counting every readable weekly run.
local function InsertRun(runs, run)
    local count = #runs
    if count == 40 and run.level <= runs[count].level then return end
    local index = math.min(40, count + 1)
    local row = count < 40 and {} or runs[40]
    while index > 1 and runs[index - 1].level < run.level do
        runs[index] = runs[index - 1]
        index = index - 1
    end
    row.map, row.level = run.mapChallengeModeID, run.level
    row.completed = S.Public(run.completed) and run.completed == true
    runs[index] = row
end

-- Season bests, rating and this week's runs arrive with the Mythic+ map
-- data; until CHALLENGE_MODE_MAPS_UPDATE the previous snapshot stays.
local function MythicPlus(entry, previous)
    previous = previous or {}
    entry.dungeons, entry.rating, entry.season = previous.dungeons, previous.rating, previous.season
    local sameReset = previous.reset == entry.reset
    entry.runs = sameReset and previous.runs or nil
    entry.runCount, entry.runHighest = sameReset and previous.runCount or nil, sameReset and previous.runHighest or nil
    if NS.Client.isForever or not Weekly.seasonReady then return end
    local maps, season = C_ChallengeMode.GetMapTable(), C_MythicPlus.GetCurrentSeason()
    if not S.Public(maps) or type(maps) ~= "table" or not S.Finite(season) then return end
    local dungeons = {}
    for i = 1, math.min(#maps, 16) do
        if S.Finite(maps[i]) then dungeons[#dungeons + 1] = SeasonBest(maps[i]) end
    end
    local rating = C_ChallengeMode.GetOverallDungeonScore()
    entry.dungeons, entry.season, entry.rating = dungeons, season, S.Finite(rating) and rating or nil
    local history = C_MythicPlus.GetRunHistory(false, true)
    if not S.Public(history) or type(history) ~= "table" then return end
    local runs, count, highest = {}, 0, 0
    for i = 1, #history do
        local run = history[i]
        if S.Public(run) and type(run) == "table" and S.Finite(run.mapChallengeModeID) and S.Finite(run.level) then
            count, highest = count + 1, math.max(highest, run.level)
            InsertRun(runs, run)
        end
    end
    entry.runs, entry.runCount, entry.runHighest = runs, count, highest
end

-- Level, item level, gold and place: cheap, refreshed on their own events.
local function Vitals(entry, previous)
    previous = previous or {}
    local level, money = UnitLevel("player"), GetMoney()
    local _, equipped = GetAverageItemLevel()
    entry.level = S.Finite(level) and level or previous.level
    entry.ilvl = S.Finite(equipped) and math.floor(equipped * 10 + .5) / 10 or previous.ilvl
    entry.money = S.Finite(money) and money >= 0 and money or previous.money
    entry.zone = Plan.Text(GetRealZoneText(), 80) or previous.zone
end

local function Prune(characters)
    while Plan.Count(characters) > Plan.LIMIT.characters do
        local oldest, at
        for guid, entry in pairs(characters) do
            local stamp = type(entry) == "table" and S.Finite(entry.at) and entry.at or 0
            if not at or stamp < at then oldest, at = guid, stamp end
        end
        if not oldest then break end
        characters[oldest] = nil
    end
end

-- The region's name never changes in a session; read it once.
local region
function Weekly.Region()
    region = region or S.PublicText(GetCurrentRegionName())
    return region
end

local function Player()
    local account = Plan.Account()
    local guid, name = S.PublicText(UnitGUID("player")), S.PublicText(UnitName("player"))
    if not account or not guid or not name then return nil end
    return account, guid, name
end

function Weekly.Capture()
    if not Plan.CanEdit() or not Plan.owner.config.weekly then return false end
    local account, guid, name = Player()
    local now = Plan.Now()
    if not account or not now then return false end
    local characters = Plan.Table(account, "characters")
    local previous = type(characters[guid]) == "table" and characters[guid] or nil
    local realm = S.PublicText(GetRealmName())
    local _, classFile = UnitClass("player")
    local vault, ready = Vault()
    local keyName, keyLevel, keyActivity, keyPending = Keystone()
    local lockouts = Weekly.lockoutsReady and Lockouts(now)
    local entry = { name = realm and name .. " - " .. realm or name, character = name, realm = realm,
        classFile = S.PublicText(classFile), at = now, reset = Weekly.Reset(), region = Weekly.Region(), vault = vault,
        reward = ready, key = keyName and { name = keyName, level = keyLevel, activity = keyActivity }
            or keyPending and previous and previous.key or nil, keyPending = keyPending or nil,
        lockouts = lockouts or previous and previous.lockouts, lockoutsPending = lockouts == nil,
        worldBosses = Weekly.lockoutsReady and WorldBosses(now) or previous and previous.worldBosses }
    Vitals(entry, previous)
    MythicPlus(entry, previous)
    characters[guid] = entry
    Prune(characters)
    Plan.Changed()
    return true
end

-- Bag changes can replace a key without changing weekly progress or lockouts.
function Weekly.UpdateKeystone()
    if NS.Client.isForever or not Plan.CanEdit() or not Plan.owner.config.weekly then return false end
    local account, guid = Player()
    local entry = account and type(account.characters) == "table" and account.characters[guid]
    if type(entry) ~= "table" then return false end
    local name, level, activity, pending = Keystone()
    if pending then
        if entry.keyPending then return false end
        entry.keyPending = true
        Plan.Changed()
        return true
    end
    local key = entry.key
    if not entry.keyPending and (key and name == key.name and level == key.level and activity == key.activity
        or not key and not name) then return false end
    entry.keyPending = nil
    entry.key = name and { name = name, level = level, activity = activity } or nil
    Plan.Changed()
    return true
end

function Weekly.LastSeen()
    if not Plan.CanEdit() or not Plan.owner.config.weekly then return false end
    local account, guid = Player()
    local entry = account and type(account.characters) == "table" and account.characters[guid]
    if type(entry) ~= "table" then return false end
    entry.at = Plan.Now() or entry.at
    return true
end

-- Refreshes only the cheap character fields of the current snapshot.
function Weekly.Vitals()
    if not Plan.CanEdit() or not Plan.owner.config.weekly then return false end
    local account, guid = Player()
    local entry = account and type(account.characters) == "table" and account.characters[guid]
    if type(entry) ~= "table" then return false end
    Vitals(entry, entry)
    entry.at = Plan.Now() or entry.at
    Plan.Changed()
    return true
end

function Weekly.KindLabel(kind)
    local kinds = Enum.WeeklyRewardChestThresholdType
    if kind == kinds.Raid then return S.Text("Raid") end
    if kind == kinds.Activities then return S.Text("Dungeons") end
    if kind == kinds.World then return S.Text("World") end
    return S.Text("Vault")
end

function Weekly.Detail(entry, fresh)
    local lines = { S.Text("Last seen: %s"):format(Plan.Date(entry.at)),
        S.Text(fresh and "Snapshot from this reset; offline changes are unknown." or "Old or unknown reset; log in to refresh.") }
    lines[#lines + 1] = S.Text(entry.reward == true and "Weekly reward available"
        or entry.reward == false and "No recorded reward available" or "Weekly reward status unavailable.")
    if not entry.lockouts then lines[#lines + 1] = S.Text("Lockout data is waiting for the server.") end
    if entry.key then lines[#lines + 1] = S.Text("Keystone: %s +%d"):format(entry.key.name, entry.key.level) end
    for _, row in ipairs(entry.vault or {}) do
        lines[#lines + 1] = S.Text("%s slot %d: %d / %d"):format(Weekly.KindLabel(row.kind), row.index, row.progress, row.threshold)
    end
    for _, row in ipairs(entry.lockouts or {}) do
        if row.difficultyName then
            lines[#lines + 1] = S.Text("%s (%s) until %s"):format(row.name, row.difficultyName, Plan.Date(row.expires))
        else
            lines[#lines + 1] = S.Text("%s (difficulty %d) until %s"):format(row.name, row.difficulty, Plan.Date(row.expires))
        end
    end
    return table.concat(lines, "\n")
end

function Weekly.Request()
    if not Plan.CanEdit() then return end
    Weekly.lockoutsReady = nil
    RequestRaidInfo()
    if not NS.Client.isForever then
        Weekly.seasonReady = nil
        C_MythicPlus.RequestMapInfo()
    end
end

function Weekly.Rows(details)
    local account, rows, reset, home = Plan.Account(), {}, Weekly.Reset(), Weekly.Region()
    for guid, entry in pairs(account and account.characters or {}) do
        -- Regions start their week at different times: another region's
        -- snapshot cannot be judged against this region's reset.
        if type(entry) == "table" and Plan.Text(entry.name, 240) and (not home or not entry.region or entry.region == home) then
            local fresh = reset ~= nil and entry.reset == reset
            rows[#rows + 1] = { key = guid, label = entry.name,
                detail = details ~= false and Weekly.Detail(entry, fresh) or nil, checked = fresh, snapshot = entry }
        end
    end
    table.sort(rows, Plan.SortNames)
    return rows
end
