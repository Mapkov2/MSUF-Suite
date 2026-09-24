local root = assert(arg[1], "repository root required")
local Suite = {}
assert(loadfile(root .. "/MSUF_Suite/Core/Database.lua"))("MSUF_Suite", Suite)
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
Check(DB.Prepare({ schema = 1, profiles = { Broken = false } }, legacy) == nil, "invalid existing profiles do not get replaced by legacy data")
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
print("Standalone suite database: " .. checks .. " checks passed")
