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
local function NotifyListeners(domain, key)
    for owner, listener in pairs(settingsListeners) do listener(owner, domain, key) end
end
local function Changed(domain)
    NotifyListeners(domain)
    Flush()
end
local categoryCallback, currentCategory = nil, "Example"
EventRegistry = {
    RegisterCallback = function(_, _, callback) categoryCallback = callback end,
    UnregisterCallback = function() categoryCallback = nil end,
}
SettingsPanel = {
    GetCurrentCategory = function()
        reads = reads + 1
        if currentCategory then return { GetName = function() return currentCategory end } end
    end,
}
local enabled = { enabled = false }
local NS = {
    addonName = "MSUF_Suite_Skin", DB = { enabled = true, addonSkins = enabled, skins = { settings = true } },
    AddonSkinDefinitions = { { label = "Example", id = "example", addons = { "ExampleUI" }, roots = { "ExampleWindow" } } },
    IsCombatLocked = function() return false end,
    Safety = { Dispatch = function(callback, ...) return callback(...) end, Public = function() return true end, Field = function(target, key) return target and target[key] end,
        Read = function(target, method) if target and target[method] then return target[method](target) end end },
    AddonSkinVisuals = { Safe = function() return true end, Release = Noop, Tree = Noop, Close = Noop },
    AddonMenus = { AssignAddon = Noop }, GenericWindows = { Disable = function() releases = releases + 1 end,
        ApplyFrame = function() paints = paints + 1 return true end },
    RestedXPSkin = { Invalidate = Noop }, SpokenSkin = { Install = Noop }, PublicAPI = {},
    Registry = { AddListener = function(owner, listener) settingsListeners[owner] = listener end, NotifyListeners = NotifyListeners,
        QueueJob = function(job) calls = calls + 1 jobs[job] = true end },
}
local function Load(name)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/" .. name .. ".lua"))(NS.addonName, NS)
end
local scans = 0
local function LoadSkins()
    Load("AddonSkins")
    NS.AddonSkins.InstallTriggers = Noop
    NS.AddonSkins.Discover = function() scans = scans + 1 end
    NS.AddonSkins.ObserveSecondaryWindows = Noop
    NS.AddonSkins.ObserveRestedXP = Noop
end
local function Window()
    return { visible = true, IsVisible = function(self) return self.visible end,
        HookScript = function(self, _, callback) self.shown = callback end }
end
LoadSkins()
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
ExampleWindow = Window()
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

NS.AddonSkinDefinitions[2] = { label = "RestedXP", id = "restedXP", addons = { "RXPGuides" },
    roots = {}, paths = { { "RXPV2GuideWindow", "frame" } } }
NS.RestedXPSkin.Paint = Noop
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function WorldEntry(savedEnabled)
    frames, settingsListeners, jobs, timers = {}, {}, {}, {}
    ExampleWindow, RXPV2GuideWindow = nil, nil
    categoryCallback, currentCategory = nil, nil
    enabled.enabled = savedEnabled
    LoadSkins()
    Load("AddonSkinSettings")
    Event("ADDON_LOADED", NS.addonName)
    Event("ADDON_LOADED", "RXPGuides")
    Event("PLAYER_LOGIN")
    Flush()

    local foreign = CreateFrame()
    foreign:RegisterEvent("PLAYER_ENTERING_WORLD")
    foreign:SetScript("OnEvent", function(self, event)
        self:UnregisterEvent(event)
        -- Forever can drain the queue during world entry, before foreign
        -- listeners have created or updated the windows for this character.
        Flush()
        ExampleWindow = Window()
        RXPV2GuideWindow = { frame = Window() }
        currentCategory = "Example"
    end)
    local scansBefore, paintsBefore, callsBefore, rowsBefore = scans, paints, calls, addonRows
    Event("PLAYER_ENTERING_WORLD")
    for _, timer in ipairs(timers) do timer() end
    Flush()
    if savedEnabled then
        local roots = NS.AddonSkins.roots
        assert(roots[RXPV2GuideWindow.frame] and roots[RXPV2GuideWindow.frame].applied,
            "saved-enabled startup missed the RestedXP guide window")
        assert(roots[ExampleWindow] and roots[ExampleWindow].applied, "saved-enabled startup missed another addon window")
        assert(scans == scansBefore + 1 and paints == paintsBefore + 2, "world entry did not catch up the active roots once")
        assert(NS.AddonSettings.IsApplied("example") and addonRows == rowsBefore + 1,
            "saved-enabled startup missed the already open addon Settings category")
    else
        assert(#timers == 0 and calls == callsBefore and scans == scansBefore and paints == paintsBefore and addonRows == rowsBefore,
            "world entry started addon skin work for a disabled profile")
    end

    scansBefore, callsBefore = scans, calls
    timers = {}
    Event("PLAYER_ENTERING_WORLD")
    Flush()
    assert(#timers == 0 and calls == callsBefore and scans == scansBefore, "a zone change repeated startup discovery")
end
WorldEntry(true)
WorldEntry(false)
print("optional addon skins: world entry, disabled delivery, restoration, late load and re-enable passed")
