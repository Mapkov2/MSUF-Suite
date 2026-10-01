-- Saved data integrity of the Suite core (MSUF_Suite/Core): normalization
-- never keeps the modules or the profile listener from starting, imports and
-- copies take what they should, and the controller never hands out a table a
-- setter could write into by mistake. Real core files in TOC order.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

-- The client's securecallfunction reports an error and returns nothing.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end
local function Reported(text)
    for _, message in ipairs(reported) do
        if message:find(text, 1, true) then return true end
    end
    return false
end
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
Minimap = { SetMaskTexture = Noop }
UnitGUID = function() return "Player-1" end
CreateFrame = function()
    return { SetScript = Noop, RegisterEvent = Noop, UnregisterEvent = Noop, UnregisterAllEvents = Noop }
end
-- No module addon is installed: every module reports itself unavailable.
C_AddOns = { IsAddOnLoaded = function() return false end, DoesAddOnExist = function() return false end,
    GetAddOnEnableState = function() return 0 end, LoadAddOn = Noop }

-- Loads the core in TOC order through ProfileVariants.lua; before(file, ns)
-- runs ahead of each file.
local function LoadCore(before)
    local ns = {}
    for _, file in ipairs(Support.TocFiles(root, "MSUF_Suite")) do
        if file:match("%.lua$") then
            if before then before(file, ns) end
            assert(loadfile(root .. "/MSUF_Suite/" .. file))("MSUF_Suite", ns)
        end
        if file == "Core/ProfileVariants.lua" then break end
    end
    return ns
end

------------------------------------------------------------------ S1.3
-- A raising migration step, repair or prepareConfig is reported; the rest of
-- the normalization, the profile listener and every module start still run.
do
    local Suite = LoadCore(function(file, ns)
        if file == "Core/Suite.lua" then
            -- MIGRATIONS and REPAIRS take their functions when Suite.lua loads.
            ns.MoveRunRecordsToCharacter = function() error("migration step failed") end
            ns.NameplateStyle.RepairGeometry = function() error("repair failed") end
        end
    end)
    local S = Suite.Suite
    S.catalog.dataTexts.prepareConfig = function() error("prepare failed") end
    local profile = { suite = { schema = 1, revision = 0, modules = {
        objectives = { backgroundOpacity = 82 }, minimap = { enabled = "yes" }, dataTexts = { enabled = 7 },
    } } }
    S.Normalize(profile)
    local modules = profile.suite.modules
    Check(Reported("migration step failed") and Reported("repair failed") and Reported("prepare failed"),
        "a raising normalization step was not reported")
    Check(modules.objectives.backgroundOpacity == 0, "the steps before a raising one did not run")
    Check(profile.suite.revision == S.MigrationRevision - 1,
        "a raising step did not hold the revision before it: " .. tostring(profile.suite.revision))
    Check(modules.minimap.enabled == S.catalog.minimap.rules.enabled.default
        and modules.dataTexts.enabled == S.catalog.dataTexts.rules.enabled.default,
        "the catalog rules did not repair the settings after a raising step")

    Suite.RootDB = { schema = 1, activeProfile = "Main", profiles = { Main = profile } }
    Suite.DB = profile
    reported = {}
    S.Start()
    Check(S.started and Reported("migration step failed"), "the start did not normalize the active profile")
    Check(S.states.minimap.unavailable ~= nil and S.states.dataTexts.unavailable ~= nil,
        "a raising normalization kept the modules from starting")
    S.states.minimap.error = "Stopped after an error"
    Suite.Registry.NotifyListeners("profile", "Main")
    Check(S.states.minimap.error == nil, "a raising normalization kept the profile listener from starting")
end

------------------------------------------------------------------ shared core
local Suite = LoadCore()
local S, IO = Suite.Suite, Suite.ProfileIO

------------------------------------------------------------------ S1.4
-- An imported revision counts at most the migrations this build knows.
for _, claimed in ipairs({ 1e9, math.huge, S.MigrationRevision + 1 }) do
    local prepared = assert(IO.PrepareTable({ suite = { schema = 1, revision = claimed, modules = {} } }, true))
    Check(prepared.suite.revision == S.MigrationRevision,
        "an imported revision of " .. tostring(claimed) .. " stayed " .. tostring(prepared.suite.revision))
end
local older = assert(IO.PrepareTable({ suite = { schema = 1, revision = 3, modules = {} } }, true))
Check(older.suite.revision == S.MigrationRevision, "a valid older revision did not migrate on import")

------------------------------------------------------------------ S1.5
-- An import migrates before it drops undocumented keys: the friendly plate
-- step still sees the retired group-only switch of an older string.
do
    local step = Support.MigrationStep(root, "Steps.FriendlyPlayerDisplay")
    local function Imported(plates)
        local prepared = assert(IO.PrepareTable({ suite = { schema = 1, revision = step - 1,
            modules = { nameplates = plates } } }, true))
        return prepared.suite.modules.nameplates
    end
    local groupOnly = Imported({ friendlyGroupOnly = true, friendlyNamesOnly = 2 })
    Check(groupOnly.friendlyNamesOnly == 3 and groupOnly.friendlyGroupOnly == nil,
        "an imported group-only plate lost its choice: " .. tostring(groupOnly.friendlyNamesOnly))
    local former = Imported({ friendlyNamesOnly = 3 })
    Check(former.friendlyNamesOnly == 4, "an imported former third choice was not renumbered")
    local retired = Imported({ friendlyGroupOnly = true, oldTable = { 1 }, oldText = string.rep("x", 300) })
    for key in pairs(retired) do
        Check(S.catalog.nameplates.rules[key], "an undocumented key entered the imported profile: " .. key)
    end
    Check(not IO.PrepareTable({ suite = { schema = 1, modules = { nameplates = { friendlyNamesOnly = "3" } } } }, true),
        "a documented setting of the wrong type was imported")
end

------------------------------------------------------------------ profiles
-- MSUF's codec and frame profiles as addon code meets them: the codec
-- round-trips tables; a frame import creates and activates the profile.
local encodings = {}
MSUF_EncodeCompactTable = function(value)
    encodings[#encodings + 1] = Suite.CopyValue(value)
    return "MSUF3:" .. #encodings
end
MSUF_TryDecodeCompactString = function(text)
    return Suite.CopyValue(encodings[tonumber(text:match("^MSUF3:(%d+)$"))])
end
local frames = { general = {} }
MSUF_GlobalDB, MSUF_DB, MSUF_ActiveProfile = { profiles = { Default = frames } }, frames, "Default"
MSUF_Profiles_ExportSelectionToString = function() return "MSUF3:frames" end
MSUF_SwitchProfile = function(name)
    if not MSUF_GlobalDB.profiles[name] then return false end
    MSUF_ActiveProfile, MSUF_DB = name, MSUF_GlobalDB.profiles[name]
    return true
end
MSUF_Profiles_ImportIntoNewProfile = function(name)
    MSUF_GlobalDB.profiles[name] = { general = {} }
    return MSUF_SwitchProfile(name)
end
MSUF_DeleteProfile = function(name) MSUF_GlobalDB.profiles[name] = nil return true end
assert(Suite.Database.Initialize(nil))
S.Normalize(Suite.DB)
local P, DB = Suite.SuiteProfiles, Suite.Database

------------------------------------------------------------------ S1.6
-- A module imported into a new profile joins the stored settings of the
-- active profile, never the variant values MSUF laid over them.
do
    local stored = Suite.DB.suite.modules.objectives
    local base = stored.width
    local overlay = true
    MSUF_NS.ProfileFields = { RegisterExternal = Noop }
    MSUF_NS.ProfileVariants = {
        BaseSnapshot = function(profile)
            assert(profile == frames, "the base snapshot was not taken from the active frame profile")
            local copy = Suite.CopyValue(stored)
            copy.width = base
            return { suiteModules = { objectives = copy } }
        end,
        HasExternalOverlay = function(field) return overlay and field == "suiteModules" end,
        IsRecording = function() return false end, IsMaterialized = function() return false end,
        Restore = Noop, ResolveCurrent = Noop,
    }
    MSUF_NS.ProfileSync = { RegisterModule = Noop, RebaseExternal = Noop }
    MSUF_NS.ProfileRuntime = { Apply = Noop }
    Check(Suite.ProfileVariants.Register(), "the variant stand-in did not register")
    stored.width = base + 100
    local text = assert(P.ExportModule("minimap"))
    local ok, why = P.ImportModuleIntoNew("Fresh", text)
    Check(ok and DB.GetActiveProfileName() == "Fresh", "the module import into a new profile failed: " .. tostring(why))
    Check(DB.GetProfile("Fresh").suite.modules.objectives.width == base,
        "a module import into a new profile copied the variant overlay as stored settings")
    overlay = false
end

------------------------------------------------------------------ S1.10
-- Renaming the active profile while the switch is refused (MSUF is recording
-- a variant) still names a profile that exists.
do
    local recording = true
    MSUF_NS.ProfileVariants.IsRecording = function() return recording end
    local active = DB.GetActiveProfileName()
    local settings = Suite.DB
    Check(P.OnLifecycle("rename", active, "Renamed") and DB.GetProfile("Renamed") == settings
        and not DB.GetProfile(active), "the active profile was not renamed")
    Check(DB.GetActiveProfileName() == "Renamed" and Suite.DB == settings,
        "a refused switch left the renamed active profile pointing at its old name: "
        .. tostring(DB.GetActiveProfileName()))
    recording = false
end

print("Suite core integrity: " .. checks .. " checks passed")
