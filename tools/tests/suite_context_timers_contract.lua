-- Context timers (MSUF_Suite_Modules/Timers.lua): ctx:After, ctx:Coalesce,
-- ctx:Ticker, ctx:Cancel and S.Debounce against the client's C_Timer and
-- frame clock (Support.Clock). Covers restarts, coalescing, Release,
-- combat, raising callbacks and steady-state allocation.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

local reported = {}
local locked = false
local S = { instances = {}, catalog = {} }
local NS = {
    Suite = S, Dispatch = Support.Dispatcher(reported),
    Finish = function(callback, ...) return true, callback(...) end,
    IsCombatLocked = function() return locked end,
    Client = { SupportsEvent = function() return true end },
    Skin = { Release = function() end, Acquire = function() return nil end },
    Safety = { IsForbidden = function() return false end },
}
_G.MSUFSuite = NS
CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript() end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterAllEvents() self.events = {} end
    return frame
end
InCombatLockdown = function() return locked end
local clock = Support.Clock()
local files = Support.TocFiles(root, "MSUF_Suite_Modules")
local runtimeAt, timersAt
for i, file in ipairs(files) do
    if file == "Runtime.lua" then runtimeAt = i end
    if file == "Timers.lua" then timersAt = i end
end
assert(runtimeAt and timersAt == runtimeAt + 1, "Timers.lua must load right after Runtime.lua")
local private = Support.Load(root, "MSUF_Suite_Modules", {}, "Timers.lua")
assert(private.Context and S.NewContext and S.Debounce, "the timer primitives did not load")

local module = { active = true }
S.instances.timed = module
local ctx = S.NewContext("timed")

local function Reported(count, why)
    assert(#reported == count, why .. " (" .. #reported .. " reported: " .. tostring(reported[#reported]) .. ")")
end

------------------------------------------------------------------ After
local runs, lastOwner = 0, nil
local function Once(owner)
    runs = runs + 1
    lastOwner = owner
end
local handle = ctx:After(.5, Once)
assert(handle:Pending() and ctx:After(.5, Once) == handle, "one handle per callback")
clock.Advance(.4)
assert(runs == 0, "After ran before its delay")
clock.Advance(.15)
assert(runs == 1 and lastOwner == module and not handle:Pending(), "After did not run once with the module")
clock.Advance(2)
assert(runs == 1, "After ran twice")

-- A restart moves the deadline. One that extends it keeps the armed tick and
-- arms again once for the rest; one that shortens it arms a new wait.
local native = clock.native
ctx:After(.5, Once)
clock.Advance(.3)
for _ = 1, 20 do ctx:After(.5, Once) end
assert(clock.native == native + 1, "extending restarts called C_Timer again")
clock.Advance(.45)
assert(runs == 1, "a restart did not move the deadline")
clock.Advance(.1)
assert(runs == 2, "the restarted deadline did not run")
ctx:After(5, Once)
ctx:After(.1, Once)
clock.Advance(.15)
assert(runs == 3, "a shorter restart waited for the old deadline")
clock.Advance(6)
assert(runs == 3, "the abandoned long wait ran")
ctx:After(0, Once)
assert(runs == 3, "a zero delay ran inside the call")
clock.Frame()
assert(runs == 4, "a zero delay did not run on the next frame")

-- Inactive modules get no callback; ctx:Cancel drops the run.
module.active = false
ctx:After(.1, Once)
clock.Advance(.2)
module.active = true
assert(runs == 4, "After ran for an inactive module")
ctx:After(.1, Once)
ctx:Cancel(Once)
clock.Advance(.2)
assert(runs == 4 and not handle:Pending(), "ctx:Cancel did not drop the pending run")

------------------------------------------------------------------ Coalesce
local seen, flushes = {}, 0
local requeue = false
local job
local function Flush(owner, keys)
    assert(owner == module)
    flushes = flushes + 1
    for key in pairs(keys) do
        seen[#seen + 1] = key
        keys[key] = nil
    end
    if requeue then
        requeue = false
        job:Request("again")
    end
end
local keys = {}
job = ctx:Coalesce(.25, Flush, keys)
assert(job.pending == false and not job:Pending(), "a new job is idle")
native = clock.native
job:Request("a")
job:Request("b")
job:Request("a")
job:Request()
assert(job.pending and clock.native == native + 1, "a burst armed more than one wait")
clock.Advance(.2)
assert(flushes == 0, "the job ran before its delay")
clock.Advance(.1)
table.sort(seen)
assert(flushes == 1 and #seen == 2 and seen[1] == "a" and seen[2] == "b" and not next(keys),
    "the burst did not run once with every key")
-- A request from inside the run waits a full delay again.
requeue = true
job:Request("first")
clock.Advance(.3)
assert(flushes == 2 and job.pending, "a request made by the run was lost")
clock.Advance(.3)
assert(flushes == 3 and seen[#seen] == "again", "the run's own request did not run")
-- Clear forgets the request; a new one rides on the wait in flight.
job:Request("x")
clock.Advance(.1)
job:Clear()
job:Request("y")
clock.Advance(.16)
assert(flushes == 4, "a request after Clear did not ride on the wait in flight")
-- Cancel makes the wait in flight stale; the next request waits the full delay.
job:Request("z")
clock.Advance(.1)
job:Cancel()
job:Request("w")
clock.Advance(.2)
assert(flushes == 4, "a cancelled wait in flight still ran the job")
clock.Advance(.1)
assert(flushes == 5, "the request after Cancel did not wait the full delay")
assert(ctx:Coalesce(.25, Flush) == job and job.keys == keys, "Coalesce lost the job or its key set")

------------------------------------------------------------------ Ticker
local ticks = 0
local function Tick(owner)
    assert(owner == module)
    ticks = ticks + 1
end
local ticker = ctx:Ticker(1, Tick)
assert(ticker:Running() and ctx:Ticker(1, Tick) == ticker and clock.tickers == 1, "a running ticker restarted")
clock.Advance(3.05)
assert(ticks == 3, "the ticker did not tick every interval")
ctx:Ticker(.5, Tick)
assert(clock.tickers == 2, "a new interval did not restart the ticker")
clock.Advance(1.02)
assert(ticks == 5, "the restarted ticker kept the old interval")
ctx:Cancel(Tick)
clock.Advance(3)
assert(ticks == 5 and not ticker:Running(), "a cancelled ticker kept ticking")

------------------------------------------------------------------ one kind per callback
local ok = pcall(ctx.Coalesce, ctx, 1, Once)
assert(not ok, "one callback served two kinds of timer")

------------------------------------------------------------------ errors
local raises = 0
local function Raise()
    raises = raises + 1
    error("timer callback raised")
end
local function RaiseJob() Raise() end
local function RaiseTick() Raise() end
ctx:After(.1, Raise)
clock.Advance(.2)
Reported(1, "a raising After was not reported")
ctx:After(.1, Raise)
clock.Advance(.2)
assert(raises == 2, "a raising After could not run again")
Reported(2, "the second raise was not reported")
local raisingJob = ctx:Coalesce(.1, RaiseJob)
raisingJob:Request()
clock.Advance(.2)
assert(raises == 3 and not raisingJob.pending, "a raising job stayed pending")
raisingJob:Request()
clock.Advance(.2)
assert(raises == 4, "a raising job could not run again")
ctx:Ticker(1, RaiseTick)
clock.Advance(2.05)
assert(raises == 6, "a raising ticker stopped ticking")
ctx:Cancel(RaiseTick)
Reported(6, "raising callbacks were not reported once each")

------------------------------------------------------------------ combat
-- Timers are not protected: they run in combat, and Release cancels in combat.
locked = true
ctx:After(.1, Once)
clock.Advance(.2)
assert(runs == 5, "After did not run in combat")
job:Request("combat")
clock.Advance(.3)
assert(flushes == 6, "a job did not run in combat")

------------------------------------------------------------------ Release
ctx:After(.2, Once)
job:Request("released")
ctx:Ticker(1, Tick)
ctx:Release()
assert(not job.pending and not ticker:Running() and not handle:Pending(), "Release left a timer pending")
clock.Advance(3)
assert(runs == 5 and flushes == 6 and ticks == 5, "a timer ran after Release")
locked = false
-- The context and its handles stay usable after Release (the next Enable).
ctx:After(.1, Once)
job:Request("next")
ctx:Ticker(1, Tick)
clock.Advance(1.05)
assert(runs == 6 and flushes == 7 and ticks == 6, "timers did not work again after Release")
ctx:Release()
-- A context that never made a timer releases without one.
S.NewContext("timed"):Release()
Reported(6, "Release raised")

------------------------------------------------------------------ S.Debounce
local debounced = 0
local debounce = S.Debounce(.3, function() debounced = debounced + 1 end)
debounce:Request()
clock.Advance(.2)
debounce:Request()
clock.Advance(.2)
assert(debounced == 0 and debounce:Pending(), "a debounce ran before the last request settled")
clock.Advance(.15)
assert(debounced == 1 and not debounce:Pending(), "the debounce did not run once")
debounce:Request()
debounce:Cancel()
clock.Advance(1)
assert(debounced == 1, "a cancelled debounce ran")
local failing = S.Debounce(.1, function() error("debounce raised") end)
failing:Request()
clock.Advance(.2)
Reported(7, "a raising debounce was not reported")

------------------------------------------------------------------ steady state allocates nothing
local function Kilobytes(count)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, count do
        ctx:After(10, Once)
        job:Request("warm")
        job:Request()
    end
    local used = collectgarbage("count") - before
    collectgarbage("restart")
    return used
end
ctx:After(10, Once)
job:Request("warm")
local idle, used = Kilobytes(0), Kilobytes(500)
assert(used - idle < .001, string.format("restarts and pending requests allocated %.3f KB", used - idle))
ctx:Release()
print("suite_context_timers_contract: OK")
