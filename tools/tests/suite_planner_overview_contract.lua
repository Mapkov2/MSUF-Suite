-- Account-wide comparison model: native IDs stay separate and unavailable
-- snapshots never become authoritative zeroes or completed activities.
local root, flavor = arg[1] or ".", arg[2] or "Mainline"
local savedArgs = arg
arg = { root, "--fixture" }
local Fixture = assert(loadfile(root .. "/tools/tests/suite_planning_tools_contract.lua"))()
arg = savedArgs
local st, NS, S, Plan, owner, P = Fixture()
NS.Client.isForever = flavor == "Forever"
assert(loadfile(root .. "/MSUF_Suite_AdventurePlanner/PlanningOverview.lua"))("Test", P)
assert(loadfile(root .. "/MSUF_Suite_AdventurePlanner/PlanningMatrix.lua"))("Test", P)
local Matrix, checks = Plan.Matrix, 0
local function Check(value, message) checks = checks + 1 assert(value, message) end
local function Equal(actual, expected, message)
    Check(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Character(key, fresh, snapshot)
    return { key = key, label = "Same Name - Realm", checked = fresh, snapshot = snapshot }
end
local function Snapshot(progress, locks)
    return { character = "Same Name", realm = "Realm", at = st.time, reset = st.reset,
        vault = { { kind = 2, index = 1, progress = progress, threshold = 4 } },
        reward = false, key = { name = "Dungeon", level = 22 }, lockouts = locks }
end
local function Lock(name, difficulty, expiry)
    return { name = name, difficulty = difficulty, difficultyName = "Difficulty " .. difficulty,
        expires = expiry, raid = true }
end
local one = Character("guid-one", true, Snapshot(3, { Lock("Shared Raid", 16, st.time + 300),
    Lock("Expired Raid", 16, st.time), Lock("Shared Raid", 15, st.time + 600) }))
local two = Character("guid-two", true, Snapshot(1, {}))
local unknown = Character("guid-unknown", true, { at = st.time, reset = st.reset })
local stale = Character("guid-stale", false, Snapshot(4, { Lock("Shared Raid", 16, st.time + 300) }))
-- Offline since the previous reset: nothing done this week, rewards waiting.
stale.snapshot.reset = st.reset - 7 * 24 * 60 * 60
local characters = { one, two, unknown, stale }
local dates, originalDate = 0, Plan.Date
Plan.Date = function(...) dates = dates + 1 return originalDate(...) end
local model = Matrix.Build(characters, st.time)
Equal(Matrix.COLUMNS, 6, "visible character pool bound")
Equal(Matrix.ROWS, 10, "visible activity pool bound")
Equal(#model.columns, 4, "one column per saved character")
Equal(model.columns[1].key, "guid-one", "first GUID retained")
Equal(model.columns[2].key, "guid-two", "equal names never merge character identities")
Equal(dates, 0, "model building does not format character detail dates")
local function Find(kind, field, value)
    for _, row in ipairs(model.rows) do
        if row.kind == kind and (not field or row[field] == value) then return row end
    end
end
local lock = Find("lockout", "lockKey", "16" .. string.char(31) .. "Shared Raid")
local otherDifficulty = Find("lockout", "lockKey", "15" .. string.char(31) .. "Shared Raid")
Check(lock ~= nil, "active raid becomes an activity row")
Check(otherDifficulty ~= nil and otherDifficulty ~= lock, "lockout difficulties have separate identities")
Check(Find("lockout", "lockKey", "16" .. string.char(31) .. "Expired Raid") == nil,
    "expired lockout does not add an activity")
Equal(model.nextExpiry, st.time + 300, "earliest active expiry is model boundary")
local value = Matrix.Value(lock, one, st.time)
Check(value ~= "?" and value ~= "—" and value ~= "", "own active lockout has a value")
Equal(Matrix.Value(lock, two, st.time), "—", "known empty reply is an empty cell")
Equal(Matrix.Value(lock, unknown, st.time), "?", "nil reply stays unknown")
Equal(Matrix.Value(lock, stale, st.time), S.Text("Saved"), "an unexpired lockout of an older snapshot still counts")
Equal(Matrix.Value(lock, one, st.time + 300), "—", "expired lockout drops at exact expiry")
one.snapshot.lockoutsPending = true
Equal(Matrix.Value(lock, one, st.time), "?", "pending server reply is not authoritative")
one.snapshot.lockoutsPending = nil
if not NS.Client.isForever then
    local vault
    for _, row in ipairs(model.rows) do if row.kind == "vault" and row.rewardType == 2 and row.slot == 0 then vault = row end end
    Check(vault ~= nil, "vault categories are activity rows")
    local grouped = { kind = "vault", rewardType = 2, slot = 0 }
    local allSlots = Character("slots", true, Snapshot(0, {}))
    allSlots.snapshot.vault = {
        { kind = 2, index = 1, progress = 4, threshold = 1, level = 10 },
        { kind = 2, index = 2, progress = 4, threshold = 4, level = 8 },
        { kind = 2, index = 3, progress = 4, threshold = 8, level = 6 },
        { kind = 79, index = 1, progress = 2, threshold = 2 },
    }
    local observedModel = Matrix.Build({ allSlots }, st.time)
    Check(observedModel ~= nil, "slot model builds")
    Equal(Matrix.Value(grouped, allSlots, st.time), S.Text("%s (%s)"):format("+10 +8", S.Text("%d / %d"):format(4, 8)),
        "unlocked slots show their reward level, the next slot its progress")
    Equal(Matrix.Value({ kind = "vault", rewardType = 2, slot = 3 }, allSlots, st.time),
        S.Text("%d / %d"):format(4, 8), "exact slot keeps its own threshold")
    local observed = Matrix.Build({ allSlots }, st.time)
    local extra
    for _, row in ipairs(observed.rows) do if row.kind == "vault" and row.rewardType == 79 then extra = row end end
    Check(extra ~= nil, "observed vault categories survive without invented enum identity")
    Equal(select(2, Matrix.Value(extra, allSlots, st.time)), "ok", "a fully unlocked observed category reads as done")
    Equal(Matrix.Value(vault, one, st.time), S.Text("%d / %d"):format(3, 4), "category cell shows progress to the first slot")
    vault = { kind = "vault", rewardType = 2, slot = 1 }
    Equal(Matrix.Value(vault, one, st.time), S.Text("%d / %d"):format(3, 4), "first character progress")
    Equal(Matrix.Value(vault, two, st.time), S.Text("%d / %d"):format(1, 4), "second character stays independent")
    Equal(Matrix.Value(vault, unknown, st.time), "?", "missing vault is unknown")
    Equal(Matrix.Value(vault, stale, st.time), S.Text("%d / %d"):format(0, 4), "offline since the reset means no vault progress")
    local function Row(kind, field)
        for _, row in ipairs(model.rows) do if row.kind == kind and (not field or row.field == field) then return row end end
    end
    Equal(Matrix.Value(Row("summary", "reward"), stale, st.time), S.Text("Ready"),
        "a slot unlocked before the reset waits in the vault")
    Equal(Matrix.Value(Row("runs"), stale, st.time), "0", "offline since the reset means no runs this week")
    Equal(Matrix.Value(Row("runs"), unknown, st.time), "?", "missing run history stays unknown")
    Check(Row("dungeon") == nil, "no dungeon rows without season records")
else
    Check(Find("vault") == nil, "Forever does not promise unavailable vault data")
end
local key = Find("summary", "field", "key")
if key then
    Equal(Matrix.Value(key, one, st.time), "Dungeon (+22)", "key dungeon and level appear in the overview")
end
Check(lock.difficulty == "Difficulty 16" and lock.name == "Shared Raid", "lockout has a separate readable difficulty")

if key then Equal(Matrix.Value(key, stale, st.time), "?", "stale keystone is not current") end
-- A full account and many distinct lockouts extend the data model, never the
-- fixed visible pool. Construction does not build all-character detail strings.
local many = {}
for i = 1, 200 do
    local locks = {}
    for j = 1, 80 do locks[j] = Lock("Raid " .. j, 16, st.time + 300 + j) end
    many[i] = Character("large-" .. i, true, Snapshot(i % 4, locks))
end
dates = 0
local large = Matrix.Build(many, st.time)
Equal(#large.columns, 200, "complete supported account remains available")
Check(#large.rows > Matrix.ROWS, "activity model supports virtualized overflow")
Equal(dates, 0, "large model does no eager detail formatting")
Equal(Matrix.COLUMNS * Matrix.ROWS, 60, "visible comparison cells remain bounded")
Plan.Date = originalDate
-- The always-loaded command never turns on an optional module or writes its
-- settings. The real Board contract exercises the active-window toggle too.
NS.Suite, NS.Text, NS.Print = S, S.Text, S.Print
_G.SlashCmdList = {}
assert(loadfile(root .. "/MSUF_Suite/Core/PlannerCommand.lua"))("Test", NS)
Equal(_G.SLASH_MSUFPLANNER1, "/plan", "simple slash opener")
Check(type(SlashCmdList.MSUFPLANNER) == "function", "slash callback registered at core load")
local planning = S.PlanningTools
S.PlanningTools = nil
local rootDB, config = NS.RootDB, owner.config
SlashCmdList.MSUFPLANNER()
Equal(st.opened, "planningTools", "cold command opens module settings")
Equal(S.PlanningTools, nil, "cold command does not construct or enable planner")
S.PlanningTools, owner.active, st.opened = planning, false, nil
SlashCmdList.MSUFPLANNER()
Equal(st.opened, "planningTools", "disabled command opens module settings")
Equal(owner.active, false, "disabled command never auto-enables")
Equal(NS.RootDB, rootDB, "command preserves root saved data")
Equal(owner.config, config, "command preserves current settings")
st.combat, st.opened = true, nil
Equal(S.OpenPlanner(), false, "combat command refused")
Equal(st.opened, nil, "combat command does not open settings")
Check(st.printed ~= nil, "combat refusal has visible feedback")
print("suite_planner_overview_contract: " .. flavor .. " " .. checks .. " checks")
