local root = assert(arg[1], "repository root required")
local money = 100000
-- MSUF is a dependency: Platform.lua asserts its namespace before any Core file.
MSUF_NS = {}
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
local lastMessage
-- PLAYER_ENTERING_WORLD settles the chat colours an off skin left behind.
local settled = 0
local function Settle() settled = settled + 1 end
local function Scenario(stored, legacy, loggedIn, oldRunning, combat, legacyOnDemand, reloading, failing, combatBeforeDeferred)
    local frame, loginFrame, starts, messages = nil, nil, 0, 0
    local afterWorldEntry, opened, fighting = {}, 0, false
    C_Timer = { After = function(delay, callback)
        assert(delay == 0, "first login must defer once to the next frame")
        afterWorldEntry[#afterWorldEntry + 1] = callback
    end }
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
        Host = { build = "Main" },
        IsCombatLocked = function() return combat == true end,
        InCombat = function() return combat == true or fighting end,
        Suite = { Start = function() starts = starts + 1 end,
            Normalize = Noop, StyleProfile = Noop },
        Print = function(message)
            messages = messages + 1
            lastMessage = message
        end,
        Text = function(text) return text end,
        Dispatch = Dispatch,
        PublicText = PublicText,
        Finite = Finite,
        -- The modules Startup.lua drives (MapkoSkin.lua, Profiles.lua, Menu.lua,
        -- Installer.lua): no legacy skin database, nothing else to do here.
        Skin = { LoadLegacyDatabase = function() return false end, EnsureEngine = Noop, SetEnabled = Noop,
            SettleChatColors = Settle },
        SuiteProfiles = { EnsureNewCharacterProfile = Noop, SyncActive = Noop,
            EnsureRetailForeverCooldownLayout = Noop, EnsureModernPanelLayout = Noop, EnsureRetailResourceStack = Noop },
        Menu = { Watch = Noop },
        Installer = { MaybeShow = Noop },
    }
    owner.Suite.Start = function() starts = starts + 1; owner.Suite.started = true end
    if failing then
        owner.Skin = {
            LoadLegacyDatabase = function() return false end,
            EnsureEngine = function() error("skin engine failed") end,
            SetEnabled = function() error("skin switch failed") end,
            SettleChatColors = Settle,
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
            SettleChatColors = Settle,
        }
    end
    assert(loadfile(root .. "/MSUF_Suite/Core/Database.lua"))("MSUF_Suite", owner)
    assert(loadfile(root .. "/MSUF_Suite/Core/SessionGold.lua"))("MSUF_Suite", owner)
    assert(loadfile(root .. "/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite", owner)
    SlashCmdList = {}
    assert(loadfile(root .. "/MSUF_Suite/Core/InstallerProfiles.lua"))("MSUF_Suite", owner)
    assert(loadfile(root .. "/MSUF_Suite/Core/InstallerModules.lua"))("MSUF_Suite", owner)
    assert(loadfile(root .. "/MSUF_Suite/Core/Installer.lua"))("MSUF_Suite", owner)
    local maybeShow = owner.Installer.MaybeShow
    owner.Installer.MaybeShow = function(reason)
        if opened > 0 then return false end
        return maybeShow(reason)
    end
    owner.Installer.Open = function()
        if owner.InCombat() then return false, "combat" end
        opened = opened + 1
        return true
    end
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
    local settledBefore = settled
    loginFrame:callback("PLAYER_ENTERING_WORLD", not reloading, reloading == true)
    assert(settled == settledBefore + 1, "the first world entry did not settle the skin's chat colours")
    assert(owner.loginKind == (reloading and "reload" or "login") and not next(loginFrame.events),
        "login kind was not captured and released")
    -- Forever can still report not logged in during the entry event. UI work
    -- resumes on the next frame, after readiness changes; no recurring retry.
    loggedIn = true
    if combatBeforeDeferred then fighting = true end
    for _, callback in ipairs(afterWorldEntry) do callback() end
    if combatBeforeDeferred then
        assert(opened == 0 and frame.events.PLAYER_REGEN_ENABLED,
            "combat after world entry lost the automatic setup retry")
        fighting = false
        frame:callback("PLAYER_REGEN_ENABLED")
        assert(opened == 1 and starts == 1, "combat retry failed or restarted the Suite modules")
    end
    assert(#afterWorldEntry <= 1, "startup queued repeated automatic setup attempts")
    owner.autoOpened = opened
    assert(not next(frame.events), "startup left idle events registered")
    return owner, starts, messages
end
local deferredCombat = Scenario(nil, nil, false, false, false, nil, false, false, true)
assert(deferredCombat.autoOpened == 1, "auto setup never resumed after combat")
local freshSkin = Scenario(nil, { profiles = { Default = { icons = {} } } }, true, false)
assert(freshSkin.freshInstall == true and freshSkin.RootDB.installation.status == "pending",
    "a skin-only database prevented the automatic Suite setup")
local pendingRoot = freshSkin.RootDB
local pendingReload = Scenario(pendingRoot, nil, true, false, false, nil, true)
assert(pendingReload.RootDB.installation.status == "pending",
    "a reload before completing setup lost the pending installer")
local legacy = { activeProfile = "Raid", profiles = {
    Raid = { suite = { schema = 1, modules = { minimap = { enabled = true } } } },
} }
local owner, starts, messages = Scenario(nil, legacy, false, false)
assert(starts == 1 and messages == 0 and MSUFSuiteDB == owner.RootDB)
assert(owner.DB.suite.modules.minimap.enabled and owner.DB ~= legacy.profiles.Raid)
assert(owner.autoOpened == 1, "first login did not open setup when login readiness settled after world entry")
assert(owner.freshInstall and owner.RootDB.installation.status == "pending",
    "legacy migration without standalone saved variables suppressed the automatic setup")
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
-- One malformed saved profile is set aside and reported once; the modules
-- of the readable profiles still start.
local damaged = { schema = 1, activeProfile = "Broken", profiles = {
    Broken = { suite = 7 }, Raid = { suite = { schema = 1, modules = { minimap = { enabled = true } } } },
} }
owner, starts, messages = Scenario(damaged, nil, false, false)
assert(starts == 1 and owner.DB.suite.modules.minimap.enabled and MSUFSuiteDB == owner.RootDB,
    "one malformed profile kept every module from starting")
assert(messages == 1 and lastMessage:find("1", 1, true) and owner.RootDB.quarantinedProfiles[1].profile.suite == 7,
    "the set-aside profile was not reported once with its data kept")
owner, starts, messages = Scenario(owner.RootDB, nil, false, false)
assert(starts == 1 and messages == 0, "a set-aside profile was reported again on the next login")
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
