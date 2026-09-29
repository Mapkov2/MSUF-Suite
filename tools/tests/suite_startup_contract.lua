local root = assert(arg[1], "repository root required")
local money = 100000
-- The client's securecallfunction reports an error to the error handler and
-- returns nothing; this harness models exactly that.
local reported = {}
local function Dispatch(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
GetMoney = function() return money end
UnitGUID = function() return "Player-test" end
-- The core's secret-safe readers (MSUF_Suite/Core/Platform.lua). This harness
-- loads no Platform and switches issecretvalue late, so it checks at call time.
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function PublicText(value)
    return Public(value) and type(value) == "string" and value ~= "" and value or nil
end
local function Finite(value)
    return Public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function Noop() end
local function Scenario(stored, legacy, loggedIn, oldRunning, combat, legacyOnDemand, reloading, failing)
    local frame, loginFrame, starts, messages = nil, nil, 0, 0
    CreateFrame = function()
        local created = { events = {} }
        function created:SetScript(_, callback) self.callback = callback end
        function created:RegisterEvent(event) self.events[event] = true end
        function created:UnregisterEvent(event) self.events[event] = nil end
        function created:UnregisterAllEvents() self.events = {} end
        if not frame then frame = created else loginFrame = created end
        return created
    end
    IsLoggedIn = function() return loggedIn end
    MSUFSuiteDB, MapkoSkinDB = stored, legacy
    MapkoSkin = oldRunning and { Suite = { started = true } } or nil
    local owner = {
        Client = { isForever = false },
        IsCombatLocked = function() return combat == true end,
        Suite = { Start = function() starts = starts + 1 end,
            Normalize = Noop, StyleProfile = Noop },
        Print = function() messages = messages + 1 end,
        Dispatch = Dispatch,
        PublicText = PublicText,
        Finite = Finite,
        -- The modules Startup.lua drives (MapkoSkin.lua, Profiles.lua, Menu.lua,
        -- Installer.lua): no legacy skin database, nothing else to do here.
        Skin = { LoadLegacyDatabase = function() return false end, EnsureEngine = Noop, SetEnabled = Noop },
        SuiteProfiles = { EnsureNewCharacterProfile = Noop, SyncActive = Noop,
            EnsureRetailForeverCooldownLayout = Noop, EnsureRetailResourceStack = Noop },
        Menu = { Watch = Noop },
        Installer = { MaybeShow = Noop },
    }
    if failing then
        owner.Skin = {
            LoadLegacyDatabase = function() return false end,
            EnsureEngine = function() error("skin engine failed") end,
            SetEnabled = function() error("skin switch failed") end,
        }
        owner.Menu = { Watch = function() error("menu watch failed") end }
    end
    if legacyOnDemand then
        owner.Skin = {
            LoadLegacyDatabase = function()
                assert(MSUFSuiteDB == nil and MapkoSkinDB == nil, "legacy data must load before Suite database initialization")
                MapkoSkinDB = legacyOnDemand
            end,
            EnsureEngine = function() return true end,
            SetEnabled = function() return true end,
        }
    end
    assert(loadfile(root .. "/MSUF_Suite/Core/Database.lua"))("MSUF_Suite", owner)
    assert(loadfile(root .. "/MSUF_Suite/Core/SessionGold.lua"))("MSUF_Suite", owner)
    assert(loadfile(root .. "/MSUF_Suite/Core/Startup.lua"))("MSUF_Suite", owner)
    assert(MSUFSuite == owner)
    frame:callback("ADDON_LOADED", "Unrelated")
    assert(owner.DB == nil and starts == 0)
    frame:callback("ADDON_LOADED", "MSUF_Suite")
    if not loggedIn and frame.events.PLAYER_LOGIN then frame:callback("PLAYER_LOGIN") end
    if combat then
        assert(starts == 0 and frame.events.PLAYER_REGEN_ENABLED, "combat load started modules prematurely")
        combat = false
        frame:callback("PLAYER_REGEN_ENABLED")
    end
    assert(loginFrame and loginFrame.events.PLAYER_ENTERING_WORLD,
        "login kind listener was not registered")
    loginFrame:callback("PLAYER_ENTERING_WORLD", not reloading, reloading == true)
    assert(owner.loginKind == (reloading and "reload" or "login") and not next(loginFrame.events),
        "login kind was not captured and released")
    assert(not next(frame.events), "startup left idle events registered")
    return owner, starts, messages
end
local legacy = { activeProfile = "Raid", profiles = {
    Raid = { suite = { schema = 1, modules = { minimap = { enabled = true } } } },
} }
local owner, starts, messages = Scenario(nil, legacy, false, false)
assert(starts == 1 and messages == 0 and MSUFSuiteDB == owner.RootDB)
assert(owner.DB.suite.modules.minimap.enabled and owner.DB ~= legacy.profiles.Raid)
owner, starts = Scenario(nil, nil, true, false, false, legacy)
assert(starts == 1 and owner.DB.suite.modules.minimap.enabled,
    "load-on-demand legacy Suite profile migrates before a fresh Suite database is created")
owner, starts = Scenario(nil, nil, true, false)
assert(starts == 1 and owner.DB and MSUFSuiteDB == owner.RootDB)
owner, starts = Scenario(nil, nil, true, false, true)
assert(starts == 1 and owner.DB and MSUFSuiteDB == owner.RootDB)
local future = { schema = 99, profiles = {} }
owner, starts, messages = Scenario(future, legacy, false, false)
assert(starts == 0 and messages == 1 and MSUFSuiteDB == future and owner.DB == nil)
owner, starts, messages = Scenario(nil, legacy, true, true)
assert(starts == 0 and messages == 1 and owner.startupError == "legacy-runtime-active")
-- Startup steps run isolated: failing skin and menu steps are reported and
-- the modules still start.
owner, starts = Scenario(nil, nil, false, false, false, nil, false, true)
assert(starts == 1 and #reported == 3 and owner.DB, "a failing startup step kept the modules from starting")
local first = Scenario(nil, nil, false, false)
assert(first.RootDB.suiteGold["Player-test"] == 100000,
    "fresh login did not capture the starting gold")
assert(first.goldSessionCaptured == true, "fresh login did not mark its gold baseline valid")
money = 112345
local reloaded = Scenario(first.RootDB, nil, false, false, false, nil, true)
assert(reloaded.RootDB.suiteGold["Player-test"] == 100000,
    "/reload reset the session gold baseline")
assert(reloaded.goldSessionCaptured == true, "/reload lost the gold baseline state")
local nextLogin = Scenario(reloaded.RootDB, nil, false, false)
assert(nextLogin.RootDB.suiteGold["Player-test"] == 112345,
    "a new login kept the previous session gold baseline")
assert(nextLogin.goldSessionCaptured == true, "new login did not mark its gold baseline valid")
money = "secret"
issecretvalue = function(value) return value == "secret" end
local unknown = Scenario(nil, nil, false, false)
assert(unknown.RootDB.suiteGold == nil, "secret money was stored in the Suite database")
assert(unknown.goldSessionCaptured == false, "secret money marked a gold baseline valid")
issecretvalue = nil
print("Standalone startup: migration, late load, future-schema preservation and duplicate-owner protection passed")
