local root = assert(arg[1], "repository root required")
local money = 100000
GetMoney = function() return money end
UnitGUID = function() return "Player-test" end
local function Scenario(stored, legacy, loggedIn, oldRunning, combat, legacyOnDemand, reloading)
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
        IsCombatLocked = function() return combat == true end,
        Suite = { Start = function() starts = starts + 1 end },
        Print = function() messages = messages + 1 end,
    }
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
