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
MSUF_ActiveProfile = "mapko final"
MSUFSuiteDB, MapkoSkinDB, MapkoSkin = nil, nil, nil

local starts, initializations, notifications = 0, 0, 0
local Suite = {
    IsCombatLocked = function() return false end,
    Client = {
        HasAddOn = function() return false end,
        AddOnEnabled = function() return true end,
    },
    Suite = { Start = function() starts = starts + 1 end },
    Print = function(message) error(message) end,
}
Suite.Database = {
    Initialize = function()
        Suite.RootDB = { skinEnabled = true }
        Suite.DB = {}
        return true
    end,
    IsProfileName = function(name) return type(name) == "string" and name ~= "" end,
    GetActiveProfileName = function() return "mapko final" end,
}
assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/Profiles.lua"))("MSUF_Suite", Suite)

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
local ok, reason = early.Database.CreateProfile("early", true)
assert(ok == false and reason == "database-not-ready")
ok, reason = early.Database.SetActiveProfile("early")
assert(ok == false and reason == "database-not-ready")
ok, reason = early.Database.DeleteProfile("early")
assert(ok == false and reason == "database-not-ready")

print("Suite skin profile startup: provider database ready before sync, modules start, late event idempotent")
