local root = assert(arg[1], "repository root required")

-- A load-on-demand provider is visible to the Suite before its ADDON_LOADED
-- lifecycle callback runs. This used to make profile sync index a nil RootDB.
local frames = {}
CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(_, callback) self.callback = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
local deferred = {}
C_Timer = { After = function(delay, callback)
    assert(delay == 0)
    deferred[#deferred + 1] = callback
end }
IsLoggedIn = function() return false end
-- MSUF is a dependency: Platform.lua asserts its namespace before any Core file.
MSUF_NS = {}
MSUF_ActiveProfile = "mapko final"
MSUFSuiteDB, MapkoSkinDB, MapkoSkin = nil, nil, nil
UnitGUID = function() return "Player-Test" end

local starts, initializations, notifications, skinPasses = 0, 0, 0, 0
local locked = false
local Suite = {
    IsCombatLocked = function() return locked end,
    InCombat = function() return true end,
    CaptureSessionGold = function() end,
    PublicText = function(value) return value end,
    -- Platform.lua's offline boundary helpers (no securecallfunction here).
    Dispatch = function(callback, ...) return callback(...) end,
    Finish = function(callback, ...) return true, callback(...) end,
    Client = {
        isForever = true,
        HasAddOn = function() return false end,
        AddOnEnabled = function() return true end,
        IsAddOnLoaded = function(name) return name == "MSUF_Suite_Skin" end,
    },
    Suite = {},
    Menu = { Watch = function() end },
    Installer = { MaybeShow = function() end },
    Print = function(message) error(message) end,
}
Suite.Suite.Start = function()
    starts = starts + 1
    Suite.Suite.started = true
end
Suite.Database = {
    Initialize = function()
        Suite.RootDB = { skinEnabled = true }
        Suite.DB = {}
        -- Database.Initialize: ok, reason, number of profiles set aside.
        return true, "ready", 0
    end,
    IsProfileName = function(name) return type(name) == "string" and name ~= "" end,
    GetActiveProfileName = function() return "mapko final" end,
}
assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/Profiles.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/ModernDarkMinimap.lua"))("MSUF_Suite", Suite)

local skinFrame, provider
C_AddOns = { LoadAddOn = function(name)
    assert(name == "MSUF_Suite_Skin")
    provider = {
        addonName = name,
        Client = { isForever = true },
        Registry = { FlushStartupLayout = function()
            assert(Suite.startingBeforeLockdown and starts == 1 and not locked,
                "startup skin jobs missed the unlocked module pass")
        end },
        ProfileIO = {},
        InitializeLocalization = function() end,
        PublicAPI = { OnDatabaseReady = function() notifications = notifications + 1 end,
            OnPlayerLogin = function() end },
        GetAPI = function() return {} end,
    }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Bootstrap.lua"))(name, provider)
    local function Noop() end
    provider.Safety = { Dispatch = function(callback, ...) return callback(...) end }
    provider.Theme, provider.BlizzardYellow = { RefreshDynamicLook = Noop }, { Apply = Noop }
    provider.Checkmarks, provider.Typography = { Apply = Noop }, { ApplyConfigured = Noop }
    provider.Adapters = { PrepareReloadWindows = function()
        assert(Suite.startingBeforeLockdown and not locked and starts == 0 and skinPasses == 0,
            "native windows were prepared after the first skin/module pass")
        assert(provider.RootDB.activeProfile == "mapko final", "preparation ran before skin profile selection")
        provider.windowsPrepared = true
    end, ApplyAll = function()
        assert(provider.windowsPrepared, "first skin pass missed its native windows")
        assert(not provider.IsCombatLocked(), "skin login did not use the unlocked startup layout")
        assert(provider.RootDB.activeProfile == "mapko final", "skin login painted the previous character's profile")
        skinPasses = skinPasses + 1
    end }
    provider.Database = {
        Initialize = function()
            initializations = initializations + 1
            provider.RootDB = { activeProfile = "Default", profiles = { Default = {} } }
            provider.DB = provider.RootDB.profiles.Default
        end,
        GetRoot = function() return provider.RootDB end,
        GetProfile = function(name) return provider.RootDB and provider.RootDB.profiles[name] end,
        GetActiveProfileName = function() return provider.RootDB and provider.RootDB.activeProfile or "Default" end,
        CreateProfile = function(name)
            assert(provider.RootDB, "skin profile created before its database")
            provider.RootDB.profiles[name] = {}
            return true, name
        end,
        SetActiveProfile = function(name)
            assert(not provider.IsCombatLocked(), "skin profile selection was blocked before lockdown")
            assert(provider.RootDB.profiles[name])
            provider.RootDB.activeProfile = name
            -- The real provider applies adapters on a profile change once
            -- its login pass is over (DatabaseProfiles.ApplyActiveSettings).
            if not provider.Database.loginPassPending then provider.Adapters.ApplyAll() end
            return true, name
        end,
    }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Lifecycle.lua"))(name, provider)
    skinFrame = frames[#frames]
    MapkoSkin = provider
    return true
end }

Suite.ProfileIO = { StartNameplateProfile = function()
        assert(Suite.Suite.started, "nameplate profile applied before module startup")
        return true
    end }
    assert(loadfile(root .. "/MSUF_Suite/Core/Startup.lua"))("MSUF_Suite", Suite)
local suiteFrame = frames[1]
suiteFrame:callback("ADDON_LOADED", "MSUF_Suite")
assert(provider and skinFrame.events.ADDON_LOADED and provider.RootDB
    and initializations == 1 and notifications == 1,
    "loading the skin provider did not prepare its database before profile sync")
suiteFrame:callback("PLAYER_LOGIN")
assert(starts == 0 and #deferred == 0, "module loading ran inside PLAYER_LOGIN")
skinFrame:callback("PLAYER_LOGIN")
assert(skinPasses == 0 and #deferred == 1, "skin pass ran before the Suite selected the reload profile")
frames[2]:callback("PLAYER_ENTERING_WORLD", false, true)
assert(starts == 1 and provider.RootDB.activeProfile == "mapko final"
    and provider.RootDB.profiles["mapko final"],
    "skin profile race stopped the Suite before its modules started")
assert(skinPasses == 1 and provider.IsCombatLocked(), "skin layout missed or leaked the unlocked reload scope")
locked = true
for _, callback in ipairs(deferred) do callback() end
assert(skinPasses == 1, "deferred module startup repeated the full skin login pass")
skinFrame:callback("ADDON_LOADED", "MSUF_Suite_Skin")
assert(initializations == 1 and notifications == 1,
    "the later skin lifecycle event initialized the database twice")

local early = { IsCombatLocked = function() return false end }
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Database.lua"))("MSUF_Suite_Skin", early)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DatabaseProfiles.lua"))("MSUF_Suite_Skin", early)
local ok, reason = early.Database.CreateProfile("early", true)
assert(ok == false and reason == "database-not-ready")
ok, reason = early.Database.SetActiveProfile("early")
assert(ok == false and reason == "database-not-ready")
ok, reason = early.Database.DeleteProfile("early")
assert(ok == false and reason == "database-not-ready")
ok, reason = early.Database.ReplaceProfiles({ Default = {} }, "Default")
assert(ok == false and reason == "database-not-ready", "all profiles were replaced before the database was ready")

-- Profile creation and deletion wait out combat like every other skin write.
local locked = false
local fighting = {
    IsCombatLocked = function() return locked end,
    Client = { isForever = false },
    FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", fighting)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", fighting)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Database.lua"))("MSUF_Suite_Skin", fighting)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DatabaseProfiles.lua"))("MSUF_Suite_Skin", fighting)
fighting.RootDB = { activeProfile = "Default", profiles = { Default = {}, Spare = {} } }
fighting.DB = fighting.RootDB.profiles.Default
locked = true
ok, reason = fighting.Database.CreateProfile("Raid", false)
assert(ok == false and reason == "combat" and not fighting.RootDB.profiles.Raid,
    "a skin profile was created in combat")
ok, reason = fighting.Database.DeleteProfile("Spare")
assert(ok == false and reason == "combat" and fighting.RootDB.profiles.Spare,
    "a skin profile was deleted in combat")
locked = false
ok = fighting.Database.DeleteProfile("Spare")
assert(ok and not fighting.RootDB.profiles.Spare, "a skin profile could not be deleted out of combat")

-- Replacing one profile or all of them waits out combat too, and says so.
local active = fighting.DB
locked = true
ok, reason = fighting.Database.SetProfile("Default", fighting.CopyValue(fighting.Defaults))
assert(ok == false and reason == "combat" and fighting.RootDB.profiles.Default == active
    and fighting.DB == active, "the active skin profile was replaced in combat")
ok, reason = fighting.Database.ReplaceProfiles({ Default = fighting.CopyValue(fighting.Defaults) }, "Default")
assert(ok == false and reason == "combat" and fighting.DB == active,
    "replacing every skin profile in combat did not report combat: " .. tostring(reason))
locked = false
ok, reason = fighting.Database.ReplaceProfiles("not profiles")
assert(ok == false and reason == "invalid-profiles", "invalid profiles were not refused as invalid")
ok = fighting.Database.SetProfile("Default", fighting.CopyValue(fighting.Defaults))
assert(ok and fighting.DB ~= active and fighting.DB == fighting.RootDB.profiles.Default,
    "the active skin profile could not be replaced out of combat")

-- A Suite reset must also clear skin profiles when this load-on-demand addon
-- was disabled during the reset and its old SavedVariables load only now.
local oldSkin = { activeProfile = "Raid", profiles = { Raid = { private = "old" } } }
MSUFSuiteDB = { pendingSkinFactoryReset = true }
MSUFSuiteSkinDB = oldSkin
MapkoSkinDB = { activeProfile = "Legacy", profiles = { Legacy = {} } }
fighting.Database.Initialize()
assert(fighting.RootDB.activeProfile == "Default" and fighting.RootDB.profiles.Raid == nil
    and fighting.RootDB.profiles.Legacy == nil and MSUFSuiteDB.pendingSkinFactoryReset == nil,
    "pending Suite reset did not discard old and legacy skin profiles")
assert(oldSkin.profiles.Raid.private == "old" and MapkoSkinDB.profiles.Legacy,
    "pending Suite reset mutated unrelated old or legacy data")

-- MidnightSkinDB belongs to the pre-rename MidnightSkin bridge addon. It is
-- handed over only when this engine takes its profiles from it.
-- The skin's profile names follow the Suite's rule (MSUF_Suite/Core/Database.lua).
dofile(root .. "/tools/tests/suite_test_support.lua").SuiteProfileNames(root)
local bridge = { activeProfile = "Bridge", profiles = { Bridge = {} } }
MSUFSuiteDB = {}
MSUFSuiteSkinDB, MapkoSkinDB, MidnightSkinDB = { activeProfile = "Default", profiles = { Default = {} } }, nil, bridge
fighting.Database.Initialize()
assert(MidnightSkinDB == bridge and bridge.profiles.Bridge and fighting.RootDB.profiles.Bridge == nil,
    "the bridge addon's profiles were cleared although this engine did not take them")
MSUFSuiteSkinDB, MapkoSkinDB, MidnightSkinDB = nil, nil, bridge
fighting.Database.Initialize()
assert(MidnightSkinDB == nil and MSUFSuiteSkinDB.profiles.Bridge,
    "the bridge addon's profiles were not handed over to the Suite skin")

print("Suite skin profile startup: provider database ready before sync, modules start, late event idempotent")
