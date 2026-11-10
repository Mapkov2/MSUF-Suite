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

local function Scenario(late, combatAtFlush, listenerFirst, installerFirst, recovery, skinLoaded)
    local frames, timers, starts = {}, {}, 0
    local loggedIn, loadOwner = false, nil
    local earlyRecovery = recovery == "early-regen" or recovery == "early-reentry"
    local startBeforeLockdown = recovery == "forever-combat-reload"
    local forever = recovery ~= "mainline-combat-reload"
    local enterBeforeLockdown = startBeforeLockdown or not forever or recovery == "forever-combat-login"
    local locked = earlyRecovery
    local unitCombat = locked or recovery == "world-entry" or enterBeforeLockdown
    local foreignEnabled, timerOwner, dispatching = false, nil, false
    local scaleSupported = listenerFirst
    local width, layoutWidth, scaleApplies = 2117.5, nil, 0
    local profilesReady = false
    MSUF_ApplyCurrentProfileGlobalUiScale = nil
    if scaleSupported then
        MSUF_ApplyCurrentProfileGlobalUiScale = function()
            Check(startBeforeLockdown and not locked and unitCombat and profilesReady,
                "host scale applied outside the prepared reload layout")
            width = 2541
            scaleApplies = scaleApplies + 1
        end
    end
    MSUFSuiteDB, MapkoSkinDB, MapkoSkin = {}, nil, nil
    MSUF_NS = { LOCALE = "enUS", Client = { Flavor = "Mainline", IsForever = forever } }
    securecallfunction = function(fn, ...) return fn(...) end
    InCombatLockdown = function() return locked end
    UnitAffectingCombat = function(unit)
        assert(unit == "player")
        return unitCombat
    end
    C_AddOns = { IsAddOnLoaded = function(name) return name == "MSUF_Suite_Skin" and skinLoaded == true end }
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
        dispatching = event
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
        Database = {},
        CaptureSessionGold = Noop,
        Skin = { LoadLegacyDatabase = Noop, EnsureEngine = Noop, SetEnabled = Noop, SettleChatColors = Noop,
            IsAvailable = function() return skinLoaded == true end },
        Menu = { Watch = Noop },
        Installer = { IsFirstRunPending = function() return recovery == "installer" end },
        SuiteProfiles = setmetatable({}, { __index = function() return Noop end }),
        ProfileVariants = { Register = Noop, Start = function() profilesReady = true end },
    }
    suite.Skin.ApplyStartupLayout = function()
        Check(startBeforeLockdown and suite.startingBeforeLockdown and not locked,
            "early skin layout was outside the unlocked reload window")
        Check(width == (scaleSupported and 2541 or 2117.5), "skin captured the old UIParent width")
    end
    suite.Skin.FinishStartupLayout = function()
        Check(startBeforeLockdown and suite.startingBeforeLockdown and not locked and starts == 1,
            "early skin refresh was outside the completed module pass")
    end
    suite.Database.Initialize = function()
        suite.RootDB = { skinEnabled = skinLoaded == true }
        return true, "ready", 0
    end
    local layoutRepairs, startupRetries = 0, 0
    suite.SuiteProfiles.EnsureModernPanelLayout = function()
        Check(not locked and (not startBeforeLockdown or not unitCombat), "layout repair ran during combat")
        layoutRepairs = layoutRepairs + 1
    end
    suite.Suite = { Start = function()
        Check(not dispatching or startBeforeLockdown and dispatching == "PLAYER_ENTERING_WORLD",
            "optional runtime loaded before the login/load dispatch finished")
        Check(not locked, "startup ran inside combat lockdown")
        Check(suite.startingModules == true, "initial module startup did not expose its bounded catch-up window")
        layoutWidth = width
        starts = starts + 1
        suite.Suite.started = true
        loadOwner = "MSUF_Suite_Modules"
        Emit("ADDON_LOADED", loadOwner)
        loadOwner = nil
    end, RetryStartup = function()
        Check(startBeforeLockdown and starts == 1 and not locked and not unitCombat,
            "early module retry ran outside its post-combat path")
        startupRetries = startupRetries + 1
    end }
    local installerCalls = 0
    suite.Installer.MaybeShow = function()
        Check(suite.Suite.started, "installer ran before module/profile startup")
        Check((recovery ~= "installer" and not startBeforeLockdown) or not suite.InCombat(),
            "installer opened during combat")
        installerCalls = installerCalls + 1
    end
    assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", suite)
    assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", suite)
    suite.ProfileIO = { StartNameplateProfile = function()
        assert(suite.Suite.started, "nameplate profile applied before module startup")
        return true
    end }
    assert(loadfile(root .. "/MSUF_Suite/Core/Startup.lua"))("MSUF_Suite", suite)
    if startBeforeLockdown and scaleSupported then
        local host = CreateFrame()
        host:RegisterEvent("PLAYER_ENTERING_WORLD")
        host:SetScript("OnEvent", function() width = 2541 end)
    end
    if not listenerFirst then ForeignListener() end
    loggedIn = late
    Emit("ADDON_LOADED", "MSUF_Suite")
    if not late then
        loggedIn = true
        Emit("PLAYER_LOGIN")
    end
    Check(starts == 0, "Suite started synchronously")
    Check(foreignEnabled and timerOwner ~= "MSUF_Suite_Modules", "foreign timer was created in Suite runtime load")
    local function FireTimer(index)
        local callback = assert(table.remove(timers, index or 1), "missing startup callback")
        callback()
    end
    if enterBeforeLockdown then
        -- Observed on Forever: the unit is fighting throughout login and
        -- world entry, but actual lockdown starts before the next frame.
        local isReload = recovery ~= "forever-combat-login"
        Emit("PLAYER_ENTERING_WORLD", not isReload, isReload)
        Check(starts == (startBeforeLockdown and 1 or 0), "incorrect start in the pre-lockdown reload window")
        if startBeforeLockdown then
            Check(layoutWidth == width, "module layout used a viewport superseded by the host world-entry listener")
        end
        Check(installerCalls == 0 and layoutRepairs == 0, "startup follow-up ran before combat ended")
        locked = true
        while #timers > 0 do FireTimer() end
        Check(starts == (startBeforeLockdown and 1 or 0) and installerCalls == 0 and layoutRepairs == 0,
            "post-entry callbacks applied startup work during lockdown")
        locked, unitCombat = false, false
        Emit("PLAYER_REGEN_ENABLED")
        while #timers > 0 do FireTimer() end
    elseif recovery == "world-entry" then
        if #timers > 0 then FireTimer() end
        Check(starts == 0 and #timers == 0, "combat at login did not defer startup")
        unitCombat = false
        Emit("PLAYER_ENTERING_WORLD", false, true)
        Check(#timers == 1, "first world entry did not queue one startup retry")
        FireTimer()
        Check(starts == 1, "first world entry did not recover startup without a combat event")
    elseif earlyRecovery then
        local worldTimer = #timers + 1
        Emit("PLAYER_ENTERING_WORLD", false, true)
        locked = false
        Emit("PLAYER_REGEN_ENABLED")
        if recovery == "early-reentry" then
            unitCombat = false
            Emit("PLAYER_REGEN_DISABLED")
            Check(#timers == 2, "expected pending startup and world-entry callbacks")
            FireTimer(worldTimer == 1 and 2 or 1)
            Check(starts == 0, "startup ignored the combat edge")
            FireTimer()
            Check(starts == 0 and #timers == 0, "world entry forgot the new combat edge")
            Emit("PLAYER_REGEN_ENABLED")
        elseif #timers == 2 then
            -- The world-entry callback can run before or after the queued start.
            FireTimer(worldTimer)
        end
        Check(starts == 0 and #timers == 1, "world entry and early combat exit did not coalesce startup")
        FireTimer()
        Check(starts == 1, "combat exit before the initial timer was lost")
    elseif recovery == "world-timer" then
        Emit("PLAYER_ENTERING_WORLD", false, true)
        Check(#timers == 2, "world entry did not queue its one readiness callback")
        unitCombat = true
        FireTimer()
        Check(starts == 0, "initial timer started with an uncleared combat flag")
        unitCombat = false
        FireTimer()
        Check(starts == 1, "queued world-entry callback did not recheck deferred startup")
    else
        Check(#timers == 1, "startup was not coalesced")
    end
    if installerFirst then
        Emit("PLAYER_ENTERING_WORLD", true, false)
        Check(#timers == 2, "world-entry installer did not schedule its one attempt")
        -- Same-frame timers need not fire in registration order.
        FireTimer(2)
        Check(installerCalls == 0, "world-entry timer opened setup before startup")
    end
    if not enterBeforeLockdown and recovery ~= "world-entry" and not earlyRecovery and recovery ~= "world-timer" then
        locked, unitCombat = combatAtFlush, combatAtFlush
        FireTimer()
    end
    if combatAtFlush then
        Check(starts == 0, "combat entered after queueing did not defer startup")
        if recovery then
            Emit("PLAYER_ENTERING_WORLD", false, true)
            FireTimer()
            Check(starts == 0 and #timers == 0, "world entry started modules or polled during combat")
        end
        locked = false
        unitCombat = recovery == "regen" or recovery == "installer"
        Emit("PLAYER_REGEN_ENABLED")
        Check(starts == 0 and #timers == 1, "combat exit did not queue exactly one startup")
        if recovery == "reentry" or recovery == "lockdown" then
            if recovery == "reentry" then
                -- The new combat edge is authoritative before the native probes catch up.
                Emit("PLAYER_REGEN_DISABLED")
            else
                locked = true
            end
            FireTimer()
            Check(starts == 0 and #timers == 0, "startup ignored a newer combat edge or current lockdown")
            locked = false
            Emit("PLAYER_REGEN_ENABLED")
            Check(#timers == 1, "the next combat exit did not queue exactly one startup")
        end
        FireTimer()
        if recovery == "installer" then
            Check(starts == 1 and installerCalls == 0, "startup did not leave the pending installer safely queued")
            unitCombat = false
            Emit("PLAYER_REGEN_ENABLED")
            if #timers > 0 then FireTimer() end
        end
    end
    Check(starts == 1, "Suite did not start exactly once")
    Check(layoutRepairs == 1, "startup layout repair did not run exactly once")
    Check(scaleApplies == (startBeforeLockdown and scaleSupported and 1 or 0),
        "saved UI scale was not applied exactly once before the reload layout")
    Check(startupRetries == (startBeforeLockdown and 1 or 0), "early module retry did not run exactly once")
    Check(suite.startingModules == nil, "module startup left its catch-up window open")
    Check(suite.startingBeforeLockdown == nil, "startup leaked its pre-lockdown layout scope")
    Check(installerCalls == 1, "queued startup did not make the installer attempt")
    Emit("PLAYER_LOGIN")
    Emit("PLAYER_REGEN_ENABLED")
    Check(starts == 1 and installerCalls == 1 and #timers == 0, "startup or installer ran again after completion")
    for _, frame in ipairs(frames) do
        Check(not frame.events.PLAYER_REGEN_ENABLED and not frame.events.PLAYER_REGEN_DISABLED,
            "startup retained an idle combat listener")
    end
end
for _, late in ipairs({ false, true }) do
    for _, combat in ipairs({ false, true }) do
        for _, first in ipairs({ false, true }) do
            for _, installerFirst in ipairs({ false, true }) do Scenario(late, combat, first, installerFirst) end
        end
    end
end
for _, skinLoaded in ipairs({ false, true }) do
    Scenario(false, false, true, false, "world-entry", skinLoaded)
    Scenario(false, false, true, false, "early-regen", skinLoaded)
    Scenario(false, false, true, false, "early-reentry", skinLoaded)
    Scenario(false, false, true, false, "world-timer", skinLoaded)
    Scenario(false, true, true, false, "regen", skinLoaded)
    Scenario(false, true, true, false, "reentry", skinLoaded)
    Scenario(false, true, true, false, "lockdown", skinLoaded)
    Scenario(false, true, true, false, "installer", skinLoaded)
    Scenario(false, false, true, false, "forever-combat-reload", skinLoaded)
    Scenario(false, false, false, false, "forever-combat-reload", skinLoaded)
    Scenario(false, false, true, false, "mainline-combat-reload", skinLoaded)
    Scenario(false, false, true, false, "forever-combat-login", skinLoaded)
end
print("Suite startup dispatch: " .. checks .. " lifecycle checks passed")
