-- Exercise the actual optional-window and Settings owners, including the
-- load-on-demand case where login has already happened.
local root = assert(arg[1])
local frames, settingsListeners, jobs = {}, {}, {}
local calls, reads, releases, paints, loadDeliveries, categoryDeliveries = 0, 0, 0, 0, 0, 0
local function Noop() end
local deferred = false
function CreateFrame()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, script) self.dispatch = script end
    frames[#frames + 1] = frame
    return frame
end
local function Event(event, addon)
    for _, frame in ipairs(frames) do
        if frame.events[event] then
            if event == "ADDON_LOADED" then loadDeliveries = loadDeliveries + 1 end
            frame:dispatch(event, addon)
        end
    end
end
local function Flush()
    if deferred then return end
    while next(jobs) do
        local job = next(jobs)
        jobs[job] = nil
        job()
    end
end
local function Changed(domain)
    for owner, listener in pairs(settingsListeners) do listener(owner, domain) end
    Flush()
end
local categoryCallback
EventRegistry = {
    RegisterCallback = function(_, _, callback) categoryCallback = callback end,
    UnregisterCallback = function() categoryCallback = nil end,
}
SettingsPanel = {
    GetCurrentCategory = function()
        reads = reads + 1
        return { GetName = function() return "Example" end }
    end,
}
local enabled = { enabled = false }
local NS = {
    addonName = "MSUF_Suite_Skin", DB = { enabled = true, addonSkins = enabled, skins = { settings = true } },
    AddonSkinDefinitions = { { label = "Example", id = "example", addons = { "ExampleUI" }, roots = { "ExampleWindow" } } },
    IsCombatLocked = function() return false end,
    Safety = { Public = function() return true end, Field = function(target, key) return target and target[key] end,
        Read = function(target, method) if target and target[method] then return target[method](target) end end },
    AddonSkinVisuals = { Safe = function() return true end, Release = Noop, Tree = Noop, Close = Noop },
    AddonMenus = { AssignAddon = Noop }, GenericWindows = { Disable = function() releases = releases + 1 end,
        ApplyFrame = function() paints = paints + 1 return true end },
    RestedXPSkin = { Invalidate = Noop }, SpokenSkin = { Install = Noop }, PublicAPI = {},
    Registry = { AddListener = function(owner, listener) settingsListeners[owner] = listener end,
        QueueJob = function(job) calls = calls + 1 jobs[job] = true end },
}
local function Load(name)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/" .. name .. ".lua"))(NS.addonName, NS)
end
Load("AddonSkins")
local scans = 0
NS.AddonSkins.InstallTriggers = Noop
NS.AddonSkins.Discover = function() scans = scans + 1 end
NS.AddonSkins.ObserveSecondaryWindows = Noop
Load("AddonSkinSettings")
-- Already logged in: only the engine's own ADDON_LOADED is delivered.
local database = NS.DB
NS.DB = nil
Changed("profile")
assert(frames[1].events.ADDON_LOADED, "an early flush dropped the bootstrap listener before the database was ready")
NS.DB = database
Event("ADDON_LOADED", NS.addonName)
Flush()
local function Idle()
    local jobsBefore, readsBefore, releasesBefore = calls, reads, releases
    local loadsBefore, categoriesBefore = loadDeliveries, categoryDeliveries
    for _ = 1, 1000 do
        Event("ADDON_LOADED", "UnrelatedAddon")
        if categoryCallback then categoryDeliveries = categoryDeliveries + 1 categoryCallback() end
        if ExampleWindow then ExampleWindow:shown() end
        Changed("color")
    end
    assert(loadDeliveries == loadsBefore and categoryDeliveries == categoriesBefore
        and calls == jobsBefore and reads == readsBefore and releases == releasesBefore,
        ("disabled: %d loads, %d categories, %d queued, %d reads, %d releases"):format(loadDeliveries - loadsBefore,
            categoryDeliveries - categoriesBefore, calls - jobsBefore, reads - readsBefore, releases - releasesBefore))
end
Idle()
enabled.enabled = true
Changed("profile")
assert(NS.AddonSettings.IsApplied("example") and categoryCallback and scans == 1)
ExampleWindow = { visible = true, IsVisible = function(self) return self.visible end,
    HookScript = function(self, _, callback) self.shown = callback end }
Event("ADDON_LOADED", "ExampleUI")
Flush()
assert(paints == 1, "enabled listener missed the late window")
local previousScans = scans
Event("ADDON_LOADED", "UnrelatedAddon")
Flush()
assert(scans == previousScans, "unrelated addon triggered discovery")
ExampleWindow.visible = false
Changed("profile")
assert(paints == 1, "profile change painted a hidden window")
ExampleWindow.visible = true
ExampleWindow:shown()
Flush()
assert(paints == 2, "hidden window kept its previous profile after reopening")
-- A settings job can reach the registry just before combat postpones its flush.
deferred = true
NS.DB.enabled = false
Changed("adapter")
NS.DB.enabled = true
Changed("profile")
deferred = false
Flush()
assert(paints == 3 and categoryCallback and NS.AddonSettings.IsApplied("example"),
    "the delayed master change left the final profile inactive")
NS.DB.enabled = false
Changed("adapter")
assert(releases > 0 and not NS.AddonSettings.IsApplied("example"))
Idle()
NS.DB.enabled = true
Changed("adapter")
assert(paints == 4 and categoryCallback and NS.AddonSettings.IsApplied("example"), "master re-enable missed existing roots")
-- With the native Settings adapter off, the addon adapter owns just its
-- category rows and continues to paint windows opened by that addon.
local addonRows = 0
NS.Safety.HasMethod = function(target, method) return type(target[method]) == "function" end
NS.AdapterKit = { RegisterRowCallback = Noop, UnregisterRowCallback = Noop }
SettingsPanel.GetSettingsList = function()
    return { ScrollBox = { ForEachFrame = function(_, visit) visit({}) end } }
end
NS.GenericWindows.ApplyDescendant = function() addonRows = addonRows + 1 return true end
NS.DB.blizzardWindowsEnabled = false
Changed("adapter")
assert(paints == 5 and addonRows == 1 and NS.AddonSettings.IsApplied("example"),
    "native windows switch broke addon windows or their Settings category")
enabled.enabled = false
Changed("profile")
Event("PLAYER_LOGIN")
Flush()
Idle()
print("optional addon skins: disabled delivery, restoration, late load and re-enable passed")
