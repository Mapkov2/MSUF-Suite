-- Optional addon loads must follow the complete login/load event dispatch.
-- AceAddon enables queued addons on nested ADDON_LOADED when IsLoggedIn is
-- true. A Suite runtime load there can start another addon's repeating timer.
local root = assert(arg[1])
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

local function Scenario(late, combatAtFlush, listenerFirst, installerFirst)
    local frames, timers, starts = {}, {}, 0
    local loggedIn, combat, loadOwner = false, false, nil
    local foreignEnabled, timerOwner, dispatching = false, nil, false
    MSUFSuiteDB, MapkoSkinDB, MapkoSkin = {}, nil, nil
    CreateFrame = function()
        local frame = { events = {} }
        frames[#frames + 1] = frame
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:UnregisterAllEvents() self.events = {} end
        function frame:SetScript(_, callback) self.callback = callback end
        return frame
    end
    C_Timer = { After = function(delay, callback)
        Check(delay == 0, "startup must use a single next-frame callback")
        timers[#timers + 1] = callback
    end }
    IsLoggedIn = function() return loggedIn end
    local function Emit(event, ...)
        local previous = dispatching
        dispatching = true
        for _, frame in ipairs(frames) do
            if frame.events[event] then frame:callback(event, ...) end
        end
        dispatching = previous
    end
    -- The relevant AceAddon rule; additionally verified with the installed
    -- unmodified AceAddon library in the external reproduction.
    local function ForeignListener()
        local frame = CreateFrame()
        frame:RegisterEvent("ADDON_LOADED")
        frame:RegisterEvent("PLAYER_LOGIN")
        frame:SetScript("OnEvent", function(_, event)
            if loggedIn and not foreignEnabled and (event == "ADDON_LOADED" or event == "PLAYER_LOGIN") then
                foreignEnabled = true
                timerOwner = loadOwner or event
            end
        end)
    end
    if listenerFirst then ForeignListener() end
    local suite = {
        InCombat = function() return combat end,
        Print = Noop, Text = function(text) return text end, Dispatch = function(fn, ...) return fn(...) end,
        Database = {},
        Client = { IsAddOnLoaded = function() return false end },
        CaptureSessionGold = Noop,
        Skin = { LoadLegacyDatabase = Noop, EnsureEngine = Noop, SetEnabled = Noop, SettleChatColors = Noop },
        Menu = { Watch = Noop }, Installer = { MaybeShow = Noop, IsFirstRunPending = function() return false end },
        SuiteProfiles = setmetatable({}, { __index = function() return Noop end }),
        ProfileVariants = { Register = Noop, Start = Noop },
        HostBridge = { ActiveFrameProfileName = function() return "Default" end },
    }
    suite.Database.Initialize = function()
        suite.RootDB = { skinEnabled = false }
        return true, "ready", 0
    end
    suite.Suite = { Start = function()
        Check(not dispatching, "optional runtime loaded before the login/load dispatch finished")
        Check(suite.startingModules == true, "initial module startup did not expose its bounded catch-up window")
        starts = starts + 1
        suite.Suite.started = true
        loadOwner = "MSUF_Suite_Modules"
        Emit("ADDON_LOADED", loadOwner)
        loadOwner = nil
    end }
    local installerCalls = 0
    suite.Installer.MaybeShow = function()
        Check(suite.Suite.started, "installer ran before module/profile startup")
        installerCalls = installerCalls + 1
    end
    assert(loadfile(root .. "/MSUF_Suite/Core/Startup.lua"))("MSUF_Suite", suite)
    if not listenerFirst then ForeignListener() end
    loggedIn = late
    Emit("ADDON_LOADED", "MSUF_Suite")
    if not late then
        loggedIn = true
        Emit("PLAYER_LOGIN")
    end
    Check(starts == 0, "Suite started synchronously")
    Check(foreignEnabled and timerOwner ~= "MSUF_Suite_Modules", "foreign timer was created in Suite runtime load")
    Check(#timers == 1, "startup was not coalesced")
    if installerFirst then
        Emit("PLAYER_ENTERING_WORLD", true, false)
        Check(#timers == 2, "world-entry installer did not schedule its one attempt")
        -- Same-frame timers need not fire in registration order.
        table.remove(timers, 2)()
        Check(installerCalls == 0, "world-entry timer opened setup before startup")
    end
    combat = combatAtFlush
    local callback = table.remove(timers, 1)
    callback()
    if combat then
        Check(starts == 0, "combat entered after queueing did not defer startup")
        combat = false
        Emit("PLAYER_REGEN_ENABLED")
        Check(starts == 0 and #timers == 1, "combat exit did not queue exactly one startup")
        table.remove(timers, 1)()
    end
    Check(starts == 1, "Suite did not start exactly once")
    Check(suite.startingModules == nil, "module startup left its catch-up window open")
    Check(installerCalls == 1, "queued startup did not make the installer attempt")
    Emit("PLAYER_LOGIN")
    Emit("PLAYER_REGEN_ENABLED")
    Check(starts == 1 and #timers == 0, "startup retained an idle listener or restarted")
end
for _, late in ipairs({ false, true }) do
    for _, combat in ipairs({ false, true }) do
        for _, first in ipairs({ false, true }) do
            for _, installerFirst in ipairs({ false, true }) do Scenario(late, combat, first, installerFirst) end
        end
    end
end
print("Suite startup dispatch: " .. checks .. " lifecycle checks passed")
