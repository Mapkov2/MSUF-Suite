-- Waits on the C-side timed signal map (C_Timer.NewTimedSignalMap, Retail
-- 12.1.5 and WoW Forever; UITimerDocumentation.lua): the context timers and
-- S.Debounce (MSUF_Suite_Modules/Timers.lua), the information-display tick
-- (DataSources.lua) and the cooldown manager's trailing windows
-- (Bootstrap.lua C.Wake). A restart moves a key, a cancel drops it, nothing goes stale. A
-- delay of 0 keeps its next-frame C_Timer.After. Without the map (12.1.0)
-- the older contracts (suite_context_timers_contract, suite_data_scheduler_
-- contract, the cooldown manager contracts) run the C_Timer path.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

-- A signal map like the client's: number keys, absolute times on GetTime's
-- clock, one callback per due key. after/now: the harness's timer and clock.
local function InstallSignals(timer, after, now)
    local log = { maps = 0, at = 0, after = 0, cancel = 0, cancelAll = 0 }
    timer.NewTimedSignalMap = function(callback)
        assert(type(callback) == "function", "a signal map needs a callback")
        log.maps = log.maps + 1
        log.callback = callback
        local due, gen, map = {}, {}, {}
        local function Arm(key, time)
            assert(type(key) == "number" and key == math.floor(key), "signal keys are numbers")
            assert(type(time) == "number" and time == time, "signal times are numbers")
            local g = (gen[key] or 0) + 1
            gen[key], due[key] = g, time
            after(math.max(0, time - now()), function()
                if gen[key] == g and due[key] then
                    due[key] = nil
                    callback(key)
                end
            end)
        end
        function map:SignalAt(key, time) log.at = log.at + 1; Arm(key, time) end
        function map:SignalAfter(key, seconds) log.after = log.after + 1; Arm(key, now() + seconds) end
        function map:CancelSignal(key)
            log.cancel = log.cancel + 1
            gen[key], due[key] = (gen[key] or 0) + 1, nil
        end
        function map:CancelAllSignals()
            log.cancelAll = log.cancelAll + 1
            for key in pairs(due) do gen[key], due[key] = gen[key] + 1, nil end
        end
        function map:HasSignal(key) return due[key] ~= nil end
        function map:GetSignalTime(key) return due[key] end
        return map
    end
    return log
end

------------------------------------------------------------------ context timers and S.Debounce
do
    local reported = {}
    local S = { instances = {}, catalog = {} }
    local NS = {
        Suite = S, Dispatch = Support.Dispatcher(reported),
        Finish = function(callback, ...) return true, callback(...) end,
        IsCombatLocked = function() return false end,
        Client = { SupportsEvent = function() return true end },
        Skin = { Release = function() end, Acquire = function() return nil end },
        Safety = { IsForbidden = function() return false end },
    }
    _G.MSUFSuite = NS
    CreateFrame = function()
        local frame = { events = {} }
        function frame:SetScript(name, fn) self[name] = fn end
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterAllEvents() self.events = {} end
        return frame
    end
    InCombatLockdown = function() return false end
    local clock = Support.Clock()
    local rawAfter = C_Timer.After
    local log = InstallSignals(C_Timer, rawAfter, GetTime)
    local afterCalls = 0
    C_Timer.After = function(...) afterCalls = afterCalls + 1; return rawAfter(...) end
    local private = Support.Load(root, "MSUF_Suite_Modules", {}, "Timers.lua")
    assert(private.Context and S.NewContext and S.Debounce, "the timer primitives did not load")
    assert(log.maps == 0, "the timers made a signal map before their first wait")
    local module = { active = true }
    S.instances.timed = module
    local ctx = S.NewContext("timed")

    -- After: one signal per deadline; a restart moves it, a cancel drops it.
    local runs = 0
    local function Once(owner) assert(owner == module); runs = runs + 1 end
    local handle = ctx:After(.5, Once)
    assert(log.maps == 1 and log.at == 1 and afterCalls == 0 and handle:Pending(),
        "the first wait makes the one signal map, signals its deadline and calls no C_Timer.After")
    clock.Advance(.4)
    assert(runs == 0, "After ran before its delay")
    clock.Advance(.15)
    assert(runs == 1 and not handle:Pending(), "After did not run once at its deadline")
    clock.Advance(2)
    assert(runs == 1, "After ran twice")
    ctx:After(.5, Once)
    clock.Advance(.3)
    local signaled = log.at
    for _ = 1, 20 do ctx:After(.5, Once) end
    assert(log.at == signaled, "restarts that extend the wait must keep the signal (no native call)")
    clock.Advance(.45)
    assert(runs == 1, "a restart did not move the deadline")
    clock.Advance(.1)
    assert(runs == 2 and afterCalls == 0, "the restarted deadline did not run once")
    ctx:After(5, Once)
    ctx:After(.1, Once)
    clock.Advance(.15)
    assert(runs == 3, "a shorter restart waited for the old deadline")
    clock.Advance(6)
    assert(runs == 3, "the replaced long wait ran")
    local cancels = log.cancel
    ctx:After(.5, Once)
    ctx:Cancel(Once)
    assert(log.cancel == cancels + 1, "a cancel did not drop the signal")
    clock.Advance(1)
    assert(runs == 3, "a cancelled After ran")

    -- Coalesce: a window with a delay is one signal; a delay of 0 keeps
    -- C_Timer.After for the next frame.
    local jobRuns, seen = 0, nil
    local function Window(owner, keys)
        assert(owner == module)
        jobRuns, seen = jobRuns + 1, keys.x
        keys.x = nil
    end
    local job = ctx:Coalesce(.2, Window)
    local signalsBefore = log.at
    job:Add("x")
    job:Request()
    job:Request()
    assert(log.at == signalsBefore + 1 and afterCalls == 0, "a coalesced window signals once and calls no C_Timer.After")
    clock.Advance(.25)
    assert(jobRuns == 1 and seen == true, "the window did not run once with its keys")
    job:Request()
    cancels = log.cancel
    job:Cancel()
    assert(log.cancel == cancels + 1, "a cancelled window kept its signal")
    clock.Advance(.5)
    assert(jobRuns == 1, "a cancelled window ran")
    job:Request()
    job:Clear()
    job:Request()
    clock.Advance(.25)
    assert(jobRuns == 2, "a request after a clear did not ride on the window")
    -- A key the map hands over early (taken for a pass before a callback
    -- earlier in it set the key again) waits for the rest.
    local earlyRuns = 0
    local early = ctx:Coalesce(.2, function() earlyRuns = earlyRuns + 1 end)
    early:Request()
    early:Cancel()
    early:Request()
    local resignals = log.at
    log.callback(early.key)
    assert(earlyRuns == 0 and log.at == resignals + 1, "an early key ran its window at once")
    clock.Advance(.25)
    assert(earlyRuns == 1, "the window of an early key did not run once")
    clock.Advance(.5)
    assert(earlyRuns == 1, "the window of an early key ran twice")
    local earlyDeadline = ctx:After(.3, function() earlyRuns = earlyRuns + 1 end)
    log.callback(earlyDeadline.key)
    assert(earlyRuns == 1, "an early key ran its deadline at once")
    clock.Advance(.35)
    assert(earlyRuns == 2, "the deadline of an early key did not run once")
    local nextFrame = 0
    local function Soon() nextFrame = nextFrame + 1 end
    local zero = ctx:Coalesce(0, Soon)
    zero:Request()
    assert(afterCalls == 1 and nextFrame == 0, "a zero delay must stay a next-frame C_Timer.After")
    clock.Frame()
    assert(nextFrame == 1, "the next-frame job did not run")
    -- A deadline of 0 is the next frame too (a restart within the frame
    -- rides on it), never inside the call.
    local function SoonAfter() nextFrame = nextFrame + 1 end
    ctx:After(0, SoonAfter)
    ctx:After(0, SoonAfter)
    assert(afterCalls == 2 and nextFrame == 1, "After(0) must stay a next-frame C_Timer.After")
    clock.Frame()
    assert(nextFrame == 2, "After(0) did not run once next frame")
    local merged = S.Debounce(0, function() nextFrame = nextFrame + 1 end)
    merged:Request()
    merged:Request()
    assert(afterCalls == 3 and nextFrame == 2, "Debounce(0) must stay a next-frame C_Timer.After")
    clock.Frame()
    assert(nextFrame == 3, "Debounce(0) did not run once next frame")
    -- A deadline moved from a signal to the next frame drops the signal.
    local cancelled = log.cancel
    ctx:After(.5, SoonAfter)
    ctx:After(0, SoonAfter)
    assert(log.cancel == cancelled + 1, "a next-frame restart kept the signal")
    clock.Advance(1)
    assert(nextFrame == 4, "the moved deadline did not run once")
    local both = 0
    local function Both() both = both + 1 end
    ctx:After(0, Both)
    ctx:After(.5, Both)
    clock.Frame()
    assert(both == 0, "a deadline moved from the next frame to a delay ran next frame")
    clock.Advance(.6)
    assert(both == 1, "a deadline moved from the next frame to a delay did not run once")
    clock.Advance(1)
    assert(both == 1, "a deadline moved from the next frame to a delay ran twice")

    -- S.Debounce: the last request counts.
    local debounced = 0
    local debounce = S.Debounce(.3, function() debounced = debounced + 1 end)
    debounce:Request()
    clock.Advance(.2)
    debounce:Request()
    clock.Advance(.2)
    assert(debounced == 0, "a debounce ran before its last request's delay")
    clock.Advance(.15)
    assert(debounced == 1, "a debounce did not run once")
    debounce:Request()
    debounce:Cancel()
    clock.Advance(.5)
    assert(debounced == 1, "a cancelled debounce ran")

    -- Release drops every signal; an inactive module runs nothing; a
    -- raising callback is reported and the others still run.
    ctx:After(.2, Once)
    job:Request()
    ctx:CancelTimers()
    clock.Advance(.5)
    assert(runs == 3 and jobRuns == 2, "a released context ran a callback")
    module.active = false
    ctx:After(.1, Once)
    clock.Advance(.2)
    assert(runs == 3, "an inactive module ran a callback")
    module.active = true
    local after = 0
    local function Raise() error("expected signal failure") end
    local function Other() after = after + 1 end
    ctx:After(.1, Raise)
    ctx:After(.1, Other)
    clock.Advance(.2)
    assert(#reported == 1 and after == 1, "a raising callback stopped the others")
    -- The map holds a wait only while its signal is set: one nobody keeps
    -- can go once it fired.
    local weak = setmetatable({}, { __mode = "k" })
    do
        local gone = S.Debounce(.1, function() end)
        weak[gone] = true
        gone:Request()
    end
    clock.Advance(.2)
    collectgarbage("collect")
    assert(next(weak) == nil, "a fired signal kept its wait alive")
    -- Every wait keeps its one key: restarts make no new ones.
    local keyed = handle.key
    for _ = 1, 50 do ctx:After(.1, Once) end
    assert(handle.key == keyed and job.key ~= nil and job.key ~= keyed, "a wait changed or shared its signal key")
end

------------------------------------------------------------------ the information-display tick
do
    local now, queue, reported = 0, {}, {}
    local S = { Public = function() return true end, Finite = function(v) return type(v) == "number" end,
        PublicText = function(v) return v end }
    S.Dispatch = function(fn, ...)
        local ok, why = coroutine.resume(coroutine.create(fn), ...)
        if not ok then reported[#reported + 1] = why end
    end
    GetTime = function() return now end
    local function After(delay, fn) queue[#queue + 1] = { at = now + delay, fn = fn } end
    C_Timer = { NewTimer = function() error("the signal map path made a timer object") end }
    local log = InstallSignals(C_Timer, After, GetTime)
    assert(loadfile(root .. "/MSUF_Suite_Modules/DataSources.lua"))("MSUF_Suite_Modules", { Suite = S })
    assert(log.maps == 0, "the display tick made a signal map before its first tick")
    local function Advance(target)
        while true do
            local best
            for i, entry in ipairs(queue) do
                if entry.at <= target and (not best or entry.at < queue[best].at) then best = i end
            end
            if not best then now = target return end
            local entry = table.remove(queue, best)
            now = entry.at
            entry.fn()
        end
    end
    local calls = {}
    local function Count(owner) return function() calls[owner] = (calls[owner] or 0) + 1 end end
    local one = S.ScheduleDataTick("one", 1, Count("one"))
    local two = S.ScheduleDataTick("two", 2, Count("two"))
    assert(log.maps == 1 and log.at == 2 and log.cancelAll == 0, "each display owner signals its own deadline once on one map")
    local oneKey, twoKey = one.key, two.key
    assert(oneKey and twoKey and oneKey ~= twoKey, "the display owners share a signal key")
    Advance(1)
    assert(calls.one == 1 and not calls.two, "the first owner did not tick alone")
    Advance(2)
    assert(calls.two == 1, "the second owner did not tick")
    -- A callback schedules its next tick on its own key; a reschedule moves it.
    local again = 0
    local function Again()
        again = again + 1
        if again == 1 then assert(S.ScheduleDataTick("one", 1, Again) == one, "the owner's task changed") end
    end
    S.ScheduleDataTick("one", 1, Again)
    local signaled = log.at
    Advance(3)
    assert(log.at == signaled + 1, "a tick that schedules its next one set more than its own key")
    Advance(3.99)
    assert(again == 1, "the rescheduled tick ran early")
    Advance(4)
    assert(again == 2, "the rescheduled tick did not run")
    S.ScheduleDataTick("one", 5, Again)
    S.ScheduleDataTick("one", .01, Again)
    Advance(4.06)
    assert(again == 3, "a reschedule did not move the tick (or ignored the 0.05 s floor)")
    Advance(10)
    assert(again == 3, "a replaced tick ran")
    -- With both owners due, one's reschedule sets its key alone and one's
    -- cancel drops its key alone: the other still ticks.
    S.ScheduleDataTick("two", 2, Count("two"))
    signaled = log.at
    one = S.ScheduleDataTick("one", 1, function() error("cancelled tick ran") end)
    assert(log.at == signaled + 1, "a reschedule set the other owner's key again")
    local cancels = log.cancel
    one:Cancel()
    assert(log.cancel == cancels + 1, "a cancel kept the signal")
    Advance(13)
    assert(calls.two == 2 and log.cancelAll == 0, "a cancel dropped the other owner's tick")
    -- A key handed over early (a callback earlier in the map's pass moved its
    -- deadline) waits for the rest.
    local late = 0
    S.ScheduleDataTick("two", 1, function() late = late + 1 end)
    log.callback(twoKey)
    assert(late == 0, "an early key ran its tick at once")
    Advance(14.1)
    assert(late == 1, "the tick of an early key did not run once")
    -- A raising callback is isolated.
    S.ScheduleDataTick("one", 1, function() error("expected tick failure") end)
    S.ScheduleDataTick("two", 1, Count("two"))
    Advance(16)
    assert(#reported == 1 and calls.two == 3, "a raising tick stopped the other owner")
    assert(one.key == oneKey and two.key == twoKey, "a display owner's signal key changed")
    assert(log.cancel == 1, "the display tick dropped a key that had no signal")
end

------------------------------------------------------------------ the cooldown manager's trailing windows
-- The main cooldown manager contract up to its first activation, with the
-- signal map added to its C_Timer (no new main-chunk local: that chunk is at
-- Lua 5.1's 200-local limit).
do
    local f = assert(io.open(root .. "/tools/tests/suite_cooldown_manager_contract.lua", "rb"))
    local code = f:read("*a")
    f:close()
    code = code:sub(1, assert(code:find("------------------------------------------------------------------ enable: capture", 1, true)) - 1)
    local hook = "local function Run(advance)"
    local at = assert(code:find(hook, 1, true), "the harness's timer loop moved")
    local inject = "C_Timer.signalLog=SIGNAL_HARNESS(C_Timer,C_Timer.After,GetTime)\n"
    code = code:sub(1, at - 1) .. inject .. code:sub(at)
    SIGNAL_HARNESS = InstallSignals
    local checks = [=[
local log=C_Timer.signalLog
-- A wake signals once and fires once.
local fired=0
local key=C.NewWake(function() fired=fired+1 end)
local signals=log.after
C.Wake(key,.2)
assert(log.after==signals+1,"a wake signals its window")
Run(.25)
assert(fired==1,"a wake did not fire once")
-- A raising wake is reported; another wake of the same pass still runs.
local raising=C.NewWake(function() error("expected wake failure") end)
local errors=#dispatch.errors
dispatch.expect=true
C.Wake(raising,.1)
C.Wake(key,.1)
Run(.2)
dispatch.expect=false
assert(#dispatch.errors==errors+1 and fired==2,"a raising wake stopped the other one")
-- A disable leaves the module's windows to their wakes (12.1.0's
-- C_Timer.After cannot be cancelled either): a wake that fires while the
-- module is off frees its window, and a re-enable inside a window rides on
-- it until its wake fired.
local config=S.Config(ID)
module.config=config
module.context=S.NewContext(ID)
local function Activate() module.active=true;module:Enable();Run() end
local function Deactivate() module.active=false;module:Disable();module.context:Release();Run(5) end
local function Arms(request,why)
    local before=log.after
    request()
    assert(log.after==before+1,why)
end
local function Keys() C.Keybinds.Request(false) end
local function Glows() C.ActionGlows.RouteChanged(true) end
Activate()
Run(.5)
Arms(Keys,"the keybind window did not arm on the signal map")
Arms(Glows,"the action glow window did not arm on the signal map")
Deactivate()
Activate()
Arms(Keys,"a keybind wake that fired while the module was off left its window armed")
Arms(Glows,"an action glow wake that fired while the module was off left its window armed")
module.active=false;module:Disable();module.context:Release()
module.active=true;module:Enable()
signals=log.after
Keys()
Glows()
assert(log.after==signals,"a re-enable inside a window armed it twice")
Run(.5)
Arms(Keys,"a keybind window that outlived a disable never arms again")
Arms(Glows,"an action glow window that outlived a disable never arms again")
Deactivate()
print("suite_signal_timers_contract: ok")
]=]
    local realLoad = loadfile
    local chunk = assert(loadstring(code .. "\n" .. checks, "@suite_cooldown_manager_contract.lua:signals"))
    local ok, why = xpcall(chunk, debug.traceback)
    loadfile = realLoad
    assert(ok, why)
end
