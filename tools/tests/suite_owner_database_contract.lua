local root = assert(arg[1], "repository root required")
-- MSUF is a dependency: Platform.lua asserts its namespace before any Core file.
MSUF_NS = {}
-- The parts of the core the database uses (Platform.lua and the controller).
local Suite = { Client = { isForever = false }, OnProfileChanged = function() end,
    Suite = { MigrationRevision = 0, Normalize = function() end, StyleProfile = function() end } }
assert(loadfile(root .. "/MSUF_Suite/Core/Database.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite", Suite)
local DB, checks = Suite.Database, 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local legacy = {
    activeProfile = "Raid",
    profiles = {
        Raid = { suite = { schema = 1, modules = { chat = { enabled = true } } }, theme = { private = "skin" } },
        Solo = { suite = { schema = 1, modules = {} } },
    },
    suiteChat = { player = { lines = { "saved message" } } },
    suiteRuns = { { map = 12 } },
    suiteRecovery = { player = { minimap = { rotateMinimap = { before = "0", applied = "1" } } } },
}
local prepared, reason = DB.Prepare(nil, legacy)
Check(reason == "migrated" and prepared.activeProfile == "Raid", "legacy active suite profile migrates")
Check(prepared.profiles.Raid.theme == nil, "skin configuration is not owned by the suite")
Check(prepared.profiles.Raid.suite ~= legacy.profiles.Raid.suite, "migration does not share profile tables")
Check(prepared.suiteRecovery.player ~= legacy.suiteRecovery.player, "pending native restoration is copied independently")
prepared.profiles.Raid.suite.modules.chat.enabled = false
prepared.suiteChat.player.lines[1] = "changed"
Check(legacy.profiles.Raid.suite.modules.chat.enabled and legacy.suiteChat.player.lines[1] == "saved message", "original legacy data stays intact")
local future = { schema = 99, profiles = {} }
Check(DB.Prepare(future, legacy) == nil and future.schema == 99, "future root schema is preserved and rejected")
-- One unreadable profile is set aside with its data; the others still load.
local brokenSuite = { suite = "not a table" }
local damaged = { schema = 1, activeProfile = "Broken", profiles = {
    Broken = false, Odd = brokenSuite, Raid = { suite = { schema = 1, modules = { chat = { enabled = true } } } },
    [string.rep("x", 81)] = { suite = { schema = 1, modules = {} } },
} }
local repaired, repairedReason, quarantined = DB.Prepare(damaged, legacy)
Check(repaired and repairedReason == "ready" and quarantined == 3,
    "one malformed profile rejected the whole Suite database")
Check(repaired.profiles.Raid.suite.modules.chat.enabled and repaired.activeProfile == "Raid"
    and repaired.profiles.Broken == nil and repaired.profiles.Odd == nil,
    "the readable profiles did not load after a malformed one was set aside")
local kept = {}
for _, entry in ipairs(repaired.quarantinedProfiles) do kept[entry.name] = entry.profile end
Check(kept.Broken == false and kept.Odd.suite == "not a table" and kept[string.rep("x", 81)],
    "a quarantined profile lost its saved data")
Check(damaged.profiles.Broken == false and damaged.quarantinedProfiles == nil and damaged.activeProfile == "Broken",
    "quarantine mutated the stored root before it was published")
Check(repaired.profiles.Raid == nil or legacy.profiles.Raid.suite ~= repaired.profiles.Raid.suite,
    "invalid existing profiles do not get replaced by legacy data")
local again, _, quarantinedAgain = DB.Prepare(repaired, nil)
Check(quarantinedAgain == 0 and #again.quarantinedProfiles == 3,
    "set-aside profiles were reported again or lost on the next load")
local legacyBad = { activeProfile = "Raid", profiles = { Raid = legacy.profiles.Raid,
    [string.rep("y", 90)] = { suite = { schema = 1, modules = {} } } } }
local fromLegacy, legacyReason, legacyQuarantined = DB.Prepare(nil, legacyBad)
Check(fromLegacy and legacyReason == "migrated" and legacyQuarantined == 1 and fromLegacy.profiles.Raid
    and fromLegacy.quarantinedProfiles[1].name == string.rep("y", 90),
    "one legacy profile with an unusable name stopped the whole migration")
legacy.profiles.Solo.suite.schema = 99
prepared = assert(DB.Prepare(nil, legacy))
Check(prepared.profiles.Solo.suite.schema == 99, "future module schema survives migration without reinterpretation")
Check(DB.Initialize(prepared, legacy), "independent suite owner initializes")
Check(Suite.RootDB ~= prepared and Suite.DB ~= prepared.profiles.Raid, "publishing the owner does not modify its input")
local locked = true
Suite.IsCombatLocked = function() return locked end
Check(not DB.Activate("Solo") and not DB.Create("New", true), "profile mutations defer during combat")
locked = false
Check(DB.Create("New", true) and not DB.Create("New", false), "creating a profile preserves an existing name")
Check(DB.Activate("New") and DB.GetActiveProfileName() == "New", "suite profile activates independently of the skin")
Suite.DB.suite.modules.chat.enabled = false
Check(legacy.activeProfile == "Raid", "suite switching never changes the skin profile")
local previous = Suite.RootDB
Check(not DB.Initialize(future, legacy) and Suite.RootDB == previous, "failed initialization leaves current runtime ownership untouched")
local empty = assert(DB.Prepare(nil, nil))
Check(empty.activeProfile == "Default" and empty.profiles.Default.suite.modules.chat == nil, "a fresh standalone install needs no MapkoSkin database")
local established = { schema = 1, activeProfile = "Default", profiles = { Default = { suite = { schema = 1, modules = {} } } } }
local resumed = assert(DB.Prepare(established, legacy))
Check(resumed.profiles.Raid == nil and resumed.migration == nil, "existing suite databases are never reimported from the skin")
local history = { Player = { lines = { "kept" } } }
local saved = { schema = 1, activeProfile = "Default", chatHistory = history,
    profiles = { Default = { suite = { schema = 1, modules = {} } } } }
local reloaded = assert(DB.Prepare(saved, nil))
Check(reloaded.chatHistory == history and reloaded.profiles.Default ~= saved.profiles.Default,
    "login copies the profiles but carries runtime history over without copying it")

local oldRoot = Suite.RootDB
oldRoot.suiteGold = { ["Realm-Player"] = 1000 }
oldRoot.installation, oldRoot.skinEnabled = { status = "complete" }, false
oldRoot.quarantinedProfiles = { { name = "Old", profile = {} } }
local oldSkin = { profiles = { Raid = { theme = { private = "skin" } } } }
MSUFSuiteDB, MSUFSuiteSkinDB = oldRoot, oldSkin
MSUF_GlobalDB = { profiles = { Raid = { player = "untouched" } } }
locked = true
Check(not DB.StageFactoryReset() and MSUFSuiteDB == oldRoot and MSUFSuiteSkinDB == oldSkin,
    "factory reset refuses combat without changing saved variables")
locked = false
Check(DB.StageFactoryReset() and Suite.RootDB == MSUFSuiteDB and Suite.RootDB ~= oldRoot,
    "factory reset replaces all Suite profiles")
Check(Suite.RootDB.activeProfile == "Default" and Suite.RootDB.profiles.Raid == nil
    and Suite.RootDB.profiles.Default.suite.modules.chat == nil and Suite.RootDB.pendingSkinFactoryReset == true,
    "factory reset stages a fresh Suite profile")
Check(type(MSUFSuiteSkinDB) == "table" and next(MSUFSuiteSkinDB) == nil and oldSkin.profiles.Raid ~= nil,
    "factory reset stages a fresh skin root without mutating the old one")
Check(MSUF_GlobalDB.profiles.Raid.player == "untouched" and legacy.profiles.Raid.suite.modules.chat.enabled == true,
    "factory reset leaves MSUF and legacy addon data alone")
-- The reset replaces the settings only. Runtime data the modules keep in the
-- root stays: the saved CVars a module still has to hand back, gold and run
-- history. The setup runs again and the skin switch starts over.
Check(oldRoot.suiteRecovery and Suite.RootDB.suiteRecovery == oldRoot.suiteRecovery
    and Suite.RootDB.suiteRuns == oldRoot.suiteRuns and Suite.RootDB.suiteChat == oldRoot.suiteChat
    and Suite.RootDB.suiteGold == oldRoot.suiteGold, "factory reset deleted the modules' runtime data")
Check(Suite.RootDB.installation == nil and Suite.RootDB.skinEnabled == nil and Suite.RootDB.migration == nil
    and Suite.RootDB.quarantinedProfiles == nil, "factory reset kept the old settings")
print("Standalone suite database: " .. checks .. " checks passed")
