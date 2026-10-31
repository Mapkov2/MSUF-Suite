-- Real planning controller: no registered work, native reads, data writes or
-- scheduled refreshes between the combat edges; one catch-up after leaving.
local root = arg[1] or "."
local savedArgs = arg
arg = { root, "--fixture" }
local Fixture = assert(loadfile(root .. "/tools/tests/suite_planning_tools_contract.lua"))()
arg = savedArgs
local checks = 0
local function Equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local WORK_EVENTS = { "ZONE_CHANGED_NEW_AREA", "WEEKLY_REWARDS_UPDATE",
    "UPDATE_INSTANCE_INFO", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_MAPS_UPDATE", "PLAYER_TALENT_UPDATE",
    "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "SELECTED_LOADOUT_CHANGED", "PLAYER_LOOT_SPEC_UPDATED",
    "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_MONEY", "PLAYER_LEVEL_UP", "READY_CHECK" }
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function WatchReads(state)
    local count = 0
    local function Wrap(parent, key)
        local read = parent[key]
        parent[key] = function(...)
            count = count + 1
            assert(not state.combat, "planner native read during combat: " .. key)
            return read(...)
        end
    end
    for _, key in ipairs({ "GetServerTime", "GetTime", "UnitGUID", "UnitName", "GetRealmName", "GetInstanceInfo",
        "GetNumSavedInstances", "GetSavedInstanceInfo", "RequestRaidInfo", "UnitLevel", "GetMoney", "GetAverageItemLevel",
        "GetRealZoneText", "GetNumSavedWorldBosses", "GetSavedWorldBossInfo", "GetCurrentRegionName" }) do Wrap(_G, key) end
    Wrap(C_MythicPlus, "GetRunHistory")
    Wrap(C_MythicPlus, "RequestMapInfo")
    Wrap(C_ChallengeMode, "GetOverallDungeonScore")
    Wrap(C_DateAndTime, "GetWeeklyResetStartTime")
    Wrap(C_WeeklyRewards, "GetActivities")
    Wrap(C_WeeklyRewards, "HasAvailableRewards")
    return function() return count end
end
local function WorkRegistered(owner, expected, label)
    for _, event in ipairs(WORK_EVENTS) do
        Equal(owner.context.callbacks[event] ~= nil, expected, label .. ": " .. event)
    end
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT" }) do
        Equal(owner.context.callbacks[event] ~= nil, true, "world lifecycle stays armed without combat work: " .. event)
    end
    Equal(owner.context.callbacks.ENCOUNTER_START, nil, "no planner encounter-start listener")
    Equal(owner.context.callbacks.ENCOUNTER_END, nil, "no planner encounter-end listener")
end
local function InstallCounters(Plan)
    local captures, paints = 0, 0
    local capture = Plan.Weekly.Capture
    Plan.Weekly.Capture = function(...)
        captures = captures + 1
        return capture(...)
    end
    Plan.Changed = function() paints = paints + 1 end
    return function() return captures, paints end
end
local function CombatLifecycle(forever)
    local st, NS, S, Plan, owner = Fixture()
    NS.Client.isForever = forever
    _G.InCombatLockdown = function() return false end -- The entry event precedes the native lock flag.
    local Reads, Counts = WatchReads(st), InstallCounters(Plan)
    Plan.History.Attempt(9, "Saved boss", 16, 0, 30)
    local archive = Plan.History.Attempts("")[1].attempt
    owner:Enable()
    WorkRegistered(owner, true, "out of combat work armed")
    Equal(st.pending ~= nil, true, "initial refresh queued")
    local stale = st.pending
    local account, characters = Copy(NS.RootDB), Copy(st.characters)
    st.Event("PLAYER_REGEN_DISABLED")
    Equal(st.pending, nil, "combat entry cancels queued refresh")
    WorkRegistered(owner, false, "combat work suspended")
    local reads, scheduled, captures = Reads(), st.scheduled, Counts()
    for _ = 1, 50 do
        for _, event in ipairs(WORK_EVENTS) do st.Event(event) end
        st.Event("ENCOUNTER_START", 9, "Boss", 16)
        st.Event("ENCOUNTER_END", 9, "Boss", 16, 20, 0)
    end
    st.Event("PLAYER_LEAVING_WORLD")
    st.Event("PLAYER_LOGOUT")
    st.Event("PLAYER_ENTERING_WORLD")
    owner:Refresh() -- A profile/options refresh arriving in combat cannot rearm work.
    stale(owner) -- Simulate a previously delivered callback after cancellation.
    Equal(st.pending, nil, "combat burst leaves no refresh")
    Equal(st.scheduled, scheduled, "combat burst schedules nothing")
    Equal(Reads(), reads, "combat burst reads no native data")
    Equal(Counts(), captures, "combat burst captures nothing")
    Equal(Same(NS.RootDB, account), true, "combat leaves account snapshots unchanged")
    Equal(Same(st.characters, characters), true, "combat leaves character archive unchanged")
    local beforeCaptures, beforePaints = Counts()
    st.Event("PLAYER_REGEN_ENABLED")
    WorkRegistered(owner, true, "post-combat work rearmed")
    Equal(st.scheduled, scheduled + 1, "one post-combat refresh queued")
    Equal(st.Flush(), true, "post-combat refresh executes")
    local afterCaptures, afterPaints = Counts()
    Equal(afterCaptures - beforeCaptures, 1, "one post-combat snapshot")
    Equal(afterPaints - beforePaints, 1, "one post-combat repaint")
    Equal(st.pending, nil, "post-combat refresh does not poll")
    Equal(Plan.History.Attempts("")[1].attempt, archive, "saved raid archive retained")
    Equal(#Plan.History.Attempts(""), 1, "combat records no new pull")
    owner:Refresh()
    Equal(st.pending ~= nil, true, "refresh can resume after combat")
    local pending = st.pending
    owner:Disable()
    owner.active = false
    Equal(st.pending, nil, "disable cancels refresh")
    local disabledCaptures = Counts()
    pending(owner)
    Equal(Counts(), disabledCaptures, "stale disabled callback captures nothing")
    Equal(Plan.owner, nil, "disable releases planner owner")
    Equal(st.closed, true, "disable closes owned planner window")
end
-- Leaving combat repaints from what the game already holds: the lockout and
-- Mythic+ requests belong to entering the world, never to a pull.
local function PullsAskNothing()
    local st, NS, S, Plan, owner = Fixture()
    owner:Enable()
    Equal(st.requests, 1, "enable asks for raid info once")
    Equal(st.mapRequests, 1, "enable asks for Mythic+ map data once")
    st.Event("UPDATE_INSTANCE_INFO")
    st.Flush()
    Equal(Plan.Account().characters[st.guid].lockoutsPending, false, "the lockout reply completes the snapshot")
    for pull = 1, 3 do
        st.Event("PLAYER_REGEN_DISABLED")
        st.Event("PLAYER_REGEN_ENABLED")
        Equal(st.Flush(), true, "pull " .. pull .. " catch-up runs")
    end
    Equal(st.requests, 1, "pulls request no raid info")
    Equal(st.mapRequests, 1, "pulls request no Mythic+ map data")
    Equal(Plan.Account().characters[st.guid].lockoutsPending, false, "pulls never turn known lockouts into question marks")
    st.Event("PLAYER_ENTERING_WORLD")
    Equal(st.requests, 2, "entering the world asks again")
end
local function EnableDuringCombat()
    local st, NS, S, Plan, owner = Fixture()
    local Reads = WatchReads(st)
    st.combat = true
    owner:Enable()
    WorkRegistered(owner, false, "combat enable leaves work suspended")
    Equal(st.pending, nil, "combat enable schedules nothing")
    Equal(st.requests, 0, "combat enable requests no server data")
    Equal(Reads(), 0, "combat enable reads no native data")
    st.Event("PLAYER_REGEN_ENABLED")
    WorkRegistered(owner, true, "leave combat arms newly enabled planner")
    Equal(st.Flush(), true, "newly enabled planner catches up")
    Equal(Plan.Account().characters[st.guid] ~= nil, true, "catch-up captures current character")
    Equal(st.requests, 1, "the first request waits for the end of combat")
end
local function WeeklyDisabled()
    local st, NS, S, Plan, owner = Fixture()
    owner.config.weekly = false
    owner:Enable()
    st.Flush()
    st.Event("PLAYER_REGEN_DISABLED")
    st.Event("PLAYER_REGEN_ENABLED")
    st.Flush()
    Equal(st.requests, 0, "disabled weekly tracking never requests lockouts")
    local account = NS.RootDB.suitePlanning
    Equal(account == nil or account.characters == nil or next(account.characters) == nil, true,
        "disabled weekly tracking creates no character snapshots")
end
CombatLifecycle(false)
CombatLifecycle(true)
PullsAskNothing()
EnableDuringCombat()
WeeklyDisabled()
print("suite_planner_idle_contract: " .. checks .. " strict combat-idle checks passed")
