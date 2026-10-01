-- Run records (Mythic+ history, boss splits, raid records) belong to the
-- character in MSUFSuiteDB.suiteCharacters, not to a profile; one migration
-- moves what older builds kept in a profile's moduleState.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
securecallfunction = function(callback, ...) return callback(...) end
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
CreateFrame = function()
    return { SetScript = function() end, RegisterEvent = function() end, UnregisterEvent = function() end,
        UnregisterAllEvents = function() end }
end
local guid = "Player-1"
UnitGUID = function(unit) assert(unit == "player"); return guid end
C_AddOns = { IsAddOnLoaded = function() return false end, DoesAddOnExist = function() return false end,
    GetAddOnEnableState = function() return 0 end, LoadAddOn = function() end }
local Suite = {}
Support.Load(root, "MSUF_Suite", Suite, "Core/Suite.lua")
assert(loadfile(root .. "/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite", Suite)
local S = Suite.Suite
Suite.RootDB = { schema = 1, profiles = {} }

-- The accessor: one table per character and owner, nothing without a GUID.
local first = assert(Suite.CharacterData("runSummary"))
assert(Suite.CharacterData("runSummary") == first and Suite.CharacterData("objectives") ~= first,
    "one table per character and owner")
assert(Suite.RootDB.suiteCharacters["Player-1"].runSummary == first, "records live in the root, keyed by GUID")
guid = nil
assert(Suite.CharacterData("runSummary") == nil, "an unreadable character must get no store")
guid = "Player-1"

-- Profiles saved before the step that moves the records, whatever its place.
local moveStep, steps = Support.MigrationStep(root, "NS.MoveRunRecordsToCharacter")
assert(steps == S.MigrationRevision, "the MIGRATIONS table was not read completely")

local function Run(id, recordedAt, map)
    return { kind = "mythic", historyID = id, recordedAt = recordedAt, mapID = map, level = 10, time = 900 + map }
end
local function Legacy(extraRun)
    local history = { Run(2, 200, 2), Run(1, 100, 1) }
    if extraRun then table.insert(history, 1, extraRun) end
    return { suite = { schema = 1, revision = moveStep - 1, modules = {}, moduleState = {
        runSummary = { history = history, historySerial = #history, last = history[1],
            raidRecords = { ["9001:16"] = { best = 120, kills = 2 } } },
        objectives = {
            collapsedGroups = { quests = true },
            mythicSplits = { ["42:10"] = { time = 1000, individual = { boss = 300 }, run = { boss = 310 }, serial = 1 } },
            mythicSplitSerial = 1,
            raidRecords = { ["900:16"] = { best = { defeated = 0, remaining = .16 },
                bestPhases = { DBM = { stage = 2, step = 2, remaining = .5 } } } },
        },
    } } }
end

-- The first profile the character loads hands its records over once.
local profile = Legacy()
S.Normalize(profile)
local runs, splits = Suite.CharacterData("runSummary"), Suite.CharacterData("objectives")
assert(#runs.history == 2 and runs.history[1].recordedAt == 200 and runs.history[1].historyID == 2
    and runs.historySerial == 2, "run history was not adopted newest first")
assert(runs.lastKind == "mythic" and runs.last == nil and runs.lastRaid == nil,
    "the last Mythic+ result must not stay a second copy of a history entry")
assert(runs.raidRecords["9001:16"].kills == 2 and splits.mythicSplits["42:10"].individual.boss == 300
    and splits.mythicSplitSerial == 1, "keyed records were not adopted")
assert(splits.raidRecords["900:16"].best.remaining == 16 and splits.raidRecords["900:16"].bestPhases.DBM.remaining == 50,
    "old 0..1 wipe fractions were not converted to percent")
local state = profile.suite.moduleState
assert(state.runSummary.history == nil and state.runSummary.raidRecords == nil and state.runSummary.last == nil
    and state.objectives.mythicSplits == nil and state.objectives.raidRecords == nil,
    "the profile kept records that now belong to the character")
assert(state.objectives.collapsedGroups.quests, "tracker collapse state is profile state and must stay")
assert(profile.suite.revision == S.MigrationRevision, "the migration did not complete the revision")

-- A second profile of the same character merges without duplicates and
-- renumbers the runs (both profiles counted their runs from 1).
local other = Legacy(Run(3, 300, 3))
other.suite.moduleState.objectives.raidRecords["900:16"] = { best = { defeated = 1, remaining = .9 } }
other.suite.moduleState.objectives.raidRecords["901:16"] = { best = { defeated = 0, remaining = .25 } }
S.Normalize(other)
assert(#runs.history == 3 and runs.history[1].recordedAt == 300 and runs.history[1].historyID == 3
    and runs.history[3].historyID == 1 and runs.historySerial == 3, "merged history has duplicates or stale IDs")
assert(splits.raidRecords["900:16"].best.remaining == 16 and splits.raidRecords["901:16"].best.remaining == 25,
    "the character's own record of a key must stay and new keys must arrive in percent")

-- Already migrated profiles run nothing again; an unreadable character
-- leaves the records where they are.
S.Normalize(profile)
assert(#runs.history == 3, "a migrated profile moved records twice")
guid = nil
local unknown = Legacy()
S.Normalize(unknown)
assert(#unknown.suite.moduleState.runSummary.history == 2, "records of an unknown character were dropped")
guid = "Player-1"

-- Profile copies never carry a character's records.
Suite.RootDB.profiles.Main = profile
Suite.RootDB.activeProfile = "Main"
Suite.DB = profile
assert(Suite.Database.Create("Copy", true))
local copy = Suite.RootDB.profiles.Copy.suite.moduleState or {}
assert(not (copy.runSummary and copy.runSummary.history) and not (copy.objectives and copy.objectives.mythicSplits),
    "a profile copy carried run records")
print("Suite character data: per-character store, one-time move from profiles, merge and profile copies passed")
