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
IsLoggedIn = function() return false end
-- MSUF is a dependency: Platform.lua asserts its namespace before any Core file.
MSUF_NS = {}
MSUF_ActiveProfile = "mapko final"
MSUFSuiteDB, MapkoSkinDB, MapkoSkin = nil, nil, nil

local starts, initializations, notifications = 0, 0, 0
local Suite = {
    IsCombatLocked = function() return false end,
    -- Platform.lua's offline boundary helpers (no securecallfunction here).
    Dispatch = function(callback, ...) return callback(...) end,
    Finish = function(callback, ...) return true, callback(...) end,
    Client = {
        HasAddOn = function() return false end,
        AddOnEnabled = function() return true end,
    },
    Suite = { Start = function() starts = starts + 1 end },
    Menu = { Watch = function() end },
    Installer = { MaybeShow = function() end },
    Print = function(message) error(message) end,
}
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
assert(loadfile(root .. "/MSUF_Suite/Core/Profiles.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/ProfileVariants.lua"))("MSUF_Suite", Suite)

local skinFrame, provider
C_AddOns = { LoadAddOn = function(name)
    assert(name == "MSUF_Suite_Skin")
    provider = {
        addonName = name,
        ProfileIO = {},
        InitializeLocalization = function() end,
        PublicAPI = { OnDatabaseReady = function() notifications = notifications + 1 end },
        GetAPI = function() return {} end,
    }
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
            assert(provider.RootDB.profiles[name])
            provider.RootDB.activeProfile = name
            return true, name
        end,
    }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Lifecycle.lua"))(name, provider)
    skinFrame = frames[#frames]
    MapkoSkin = provider
    return true
end }

assert(loadfile(root .. "/MSUF_Suite/Core/Startup.lua"))("MSUF_Suite", Suite)
local suiteFrame = frames[1]
suiteFrame:callback("ADDON_LOADED", "MSUF_Suite")
assert(provider and skinFrame.events.ADDON_LOADED and provider.RootDB
    and initializations == 1 and notifications == 1,
    "loading the skin provider did not prepare its database before profile sync")
suiteFrame:callback("PLAYER_LOGIN")
assert(starts == 1 and provider.RootDB.activeProfile == "mapko final"
    and provider.RootDB.profiles["mapko final"],
    "skin profile race stopped the Suite before its modules started")
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

print("Suite skin profile startup: provider database ready before sync, modules start, late event idempotent")
