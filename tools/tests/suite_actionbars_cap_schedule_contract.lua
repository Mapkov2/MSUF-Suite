-- Load the actual dispatcher and actual unit runner; no copied scheduler.
-- Native timer/clock calls, paint outcomes and product-only VM are separate.
local options = { iterations = 20 }
local at = 1
if arg[1] and arg[1]:sub(1, 2) ~= "--" then
    options.root = arg[1]:gsub("[/\\]+$", "")
    at = 2
end
while at <= #arg do
    local key = arg[at]
    if key == "--measure" then options.measure = true
    elseif key == "--strict" then options.strict = true
    elseif key == "--source" or key == "--baseline" or key == "--candidate" or key == "--budgets" then
        at = at + 1
        options[key:sub(3)] = assert(arg[at], "missing " .. key)
    else error("unknown argument: " .. tostring(key)) end
    at = at + 1
end
assert(options.root, "repository root required")
if not options.source and not options.baseline and not options.candidate then
    options.source = options.root .. "/MSUF_Suite_ActionBars/Flush.lua"
end
if not options.measure then options.strict = true end
assert(not (options.measure and options.strict), "choose measure or strict")
local limits
if options.strict then
    limits = assert(loadfile(options.budgets or options.root .. "/tools/tests/actionbars_cap_schedule_budgets.lua"))()
    assert(limits.iterations == options.iterations, "iteration budget mismatch")
end
local sources = {}
for _, label in ipairs({ "baseline", "candidate", "source" }) do
    if options[label] then sources[#sources + 1] = { label = label, path = options[label] } end
end
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end
local runtimePath = options.root .. "/MSUF_Suite_Modules/Runtime.lua"
local runtime = Read(runtimePath)
local first = assert(runtime:find("function S.NewUnitRunner()", 1, true))
local last = assert(runtime:find("------------------------------------------------------------------ CVar ownership", first, true))
local runnerSource = "local S, NS = ...\nlocal Dispatch = S.Dispatch\n" .. runtime:sub(first, last - 1)
local COUNTERS = { "timerZero", "timerCap", "clock", "cooldown", "usable", "state", "count",
    "nativeFeedback", "nativeState", "nativeCount", "paint", "grid", "routing", "errors" }
local function New(path, native)
    local w = { now = 10, sequence = 0, nodes = {}, counters = {}, records = {}, fail = 0 }
    for _, key in ipairs(COUNTERS) do w.counters[key] = 0 end
    for i = 1, 32 do w.nodes[i] = {} end
    local function Sink(key)
        return function()
            w.counters[key] = w.counters[key] + 1
            if key == "cooldown" then
                if w.reenter then w.reenter = false w.ab.Mark("cooldown") end
                if w.fail > 0 then w.fail = w.fail - 1 error("injected cooldown failure") end
            end
        end
    end
    local bar = { buttons = {}, filled = {} }
    for i = 1, 3 do
        local rec = { slot = i, filled = true, bar = bar, button = {} }
        bar.buttons[i], bar.filled[i], w.records[i] = rec, rec, rec
    end
    local m = { active = true, config = { hideEmptyCharges = false, castHighlight = true, procGlow = 1 } }
    local ab = { M = m, ENUM = { PROC_GLOW = { PIXEL = 2 } }, BAR_COUNT = 1, bars = { bar },
        SNIPPET = { GRID = "fixture grid" }, directDuration = not native }
    ab.Execute, ab.UpdateRouting = Sink("grid"), Sink("routing")
    local painter = { slotMap = { [1] = { w.records[1] } } }
    function painter.Visible() return not w.hidden end
    function painter.Walk(fn)
        if w.hidden then return end
        for i = 1, #w.records do fn(w.records[i]) end
    end
    function painter.WalkNative(fn) if native and not w.hidden then fn(w.records[1]) end end
    function painter.SpellRouted(rec) return rec.routed end
    painter.Cooldown, painter.Usable = Sink("cooldown"), Sink("usable")
    painter.State, painter.Count = Sink("state"), Sink("count")
    painter.Paint, painter.PaintBar = Sink("paint"), Sink("paint")
    painter.Icon, painter.Refill, painter.GlowCheck, painter.AllKeyTexts = Sink("paint"), function() end, function() end, function() end
    ab.Painter = painter
    ab.NativeButtons = { Feedback = Sink("nativeFeedback"), State = Sink("nativeState"), Count = Sink("nativeCount"),
        Color = function() end, Retint = function() end }
    local ns = { Finish = function(fn, a, b) fn(a, b) return true end,
        IsCombatLocked = function() return w.combat == true end }
    local s = { Dispatch = function(fn, ...)
        local ok, result = pcall(fn, ...)
        if not ok then w.counters.errors = w.counters.errors + 1 return nil end
        return result
    end }
    local runner = assert(loadstring(runnerSource, "@" .. runtimePath))
    runner(s, ns)
    local env = setmetatable({
        GetTime = function() w.counters.clock = w.counters.clock + 1 return w.now end,
        C_Timer = { After = function(delay, fn)
            local key = delay == 0 and "timerZero" or "timerCap"
            w.counters[key] = w.counters[key] + 1
            w.sequence = w.sequence + 1
            for i = 1, #w.nodes do
                local node = w.nodes[i]
                if not node.fn then
                    node.fn, node.at, node.sequence, node.zero = fn, w.now + delay, w.sequence, delay == 0
                    return
                end
            end
            error("timer fixture capacity exceeded")
        end },
    }, { __index = _G })
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("MSUF_Suite_ActionBars", { NS = ns, Suite = s, ActionBars = ab })
    w.ab, w.m, w.bar, w.source = ab, m, bar, "@" .. path
    return w
end

local function Pending(w, zero)
    local total = 0
    for i = 1, #w.nodes do
        local node = w.nodes[i]
        if node.fn and (zero == nil or node.zero == zero) then total = total + 1 end
    end
    return total
end
local function Fire(w, zero)
    local picked
    for i = 1, #w.nodes do
        local node = w.nodes[i]
        if node.fn and (zero == nil or node.zero == zero)
            and (not picked or node.at < picked.at or node.at == picked.at and node.sequence < picked.sequence) then
            picked = node
        end
    end
    assert(picked, "missing fixture timer")
    local callback, due = picked.fn, picked.at
    picked.fn = nil
    w.now = math.max(w.now, due)
    callback()
end
local function First(w, kind)
    w.ab.Mark(kind)
    Fire(w, true)
end
local function Wait(w, kind)
    w.now = w.now + .01
    First(w, kind)
    assert(Pending(w, false) == 1, "cap did not retain exactly one trailing timer")
end
local function ClearCounters(w)
    for _, key in ipairs(COUNTERS) do w.counters[key] = 0 end
end

local function Behavior(path, native)
    local w = New(path, native)
    w.ab.Mark("cooldown") w.ab.Mark("cooldown")
    assert(Pending(w, true) == 1, "same-frame marks scheduled twice")
    Fire(w, true)
    assert(w.counters.cooldown == 3, "leading paint changed")
    Wait(w, "cooldown")
    w.ab.Mark("state") Fire(w, true)
    assert(w.counters.state == 3, "uncapped state waited for cooldown")
    w.ab.Mark("count") Fire(w, true)
    assert(w.counters.count == 3, "uncapped count waited for cooldown")
    First(w, "usable")
    assert(w.counters.usable == 3, "fresh capped kind lost its leading paint")
    w.ab.Dirty.slots[1] = true w.ab.Dirty.Schedule() Fire(w, true)
    w.ab.MarkBar(w.bar) Fire(w, true)
    assert(w.counters.paint == 2, "slot/bar work waited for cap")
    w.ab.Regrid(w.bar) Fire(w, true)
    assert(w.counters.grid == 1, "protected grid waited for cap")
    Fire(w, false)
    assert(w.counters.cooldown == 6 and w.counters.nativeFeedback == (native and 2 or 0), "trailing paint changed")

    -- A dominant kind absorbs the child mark without clearing its old due.
    -- A new child event is fresh work even before that old deadline expires.
    for _, pair in ipairs({ { "actionbarCooldown", "cooldown", "cooldown" },
        { "unreported", "usable", "usable" } }) do
        w = New(path, native)
        First(w, pair[1]) Wait(w, pair[1])
        First(w, pair[2])
        assert(w.counters[pair[3]] == 6, "dominant kind did not absorb the waiting child")
        w.now = 10.02
        w.ab.Mark(pair[1])
        assert(Pending(w, true) == 1, "fresh absorbed " .. pair[1] .. " mark was suppressed by stale waiting proof")
        Fire(w, true) Fire(w, false)
        assert(w.counters[pair[3]] == 9, "fresh child mark lost its trailing paint after dominance")
    end

    -- A kind's deadline can precede the shared timer belonging to another kind.
    w = New(path, native)
    First(w, "usable")
    w.now = 10.02 First(w, "cooldown")
    w.now = 10.03 First(w, "cooldown")
    w.now = 10.04 First(w, "usable")
    assert(Pending(w, false) == 1, "different kinds allocated separate trailing timers")
    w.now = 10.105
    w.ab.Mark("usable")
    assert(Pending(w, true) == 1, "expired kind deadline was suppressed by another kind's later timer")
    Fire(w, true)
    assert(w.counters.usable == 6, "expired kind failed its leading flush")
    Fire(w, false)
    assert(w.counters.cooldown == 6, "shared later deadline lost cooldown")

    -- A mark before its own due still needs a next frame when the shared
    -- timer is later: that next frame can cross the earlier kind's deadline.
    w = New(path, native)
    First(w, "usable")
    w.now = 10.02 First(w, "cooldown")
    w.now = 10.03 First(w, "cooldown")
    w.now = 10.04 First(w, "usable")
    assert(Pending(w, false) == 1, "pre-deadline setup lost shared timer")
    w.now = 10.095
    w.ab.Mark("usable")
    assert(Pending(w, true) == 1, "pre-deadline mark was suppressed by later shared timer")
    w.now = 10.105
    Fire(w, true)
    assert(w.counters.usable == 6, "pre-deadline mark missed its first eligible next frame")
    assert(w.counters.cooldown == 3, "pre-deadline mark painted the later kind early")
    Fire(w, false)
    assert(w.counters.cooldown == 6 and w.counters.usable == 6, "later shared timer lost work or duplicated earlier paint")

    -- An expired but unprocessed native timer must not suppress a fresh event.
    w = New(path, native) First(w, "cooldown") Wait(w, "cooldown")
    w.now = 10.11 w.ab.Mark("cooldown")
    assert(Pending(w, true) == 1, "expired trailing timer blocked fresh mark")
    Fire(w, false) Fire(w, true)
    assert(w.counters.cooldown == 6, "pending next-frame handoff lost work")

    w = New(path, native) First(w, "cooldown") Wait(w, "cooldown")
    w.ab.MarkAll() Fire(w, true)
    assert(w.counters.paint == 1 and w.counters.routing == 1 and w.counters.grid == 1, "full refresh waited for cap")
    Fire(w, false)
    assert(w.counters.cooldown == (native and 6 or 3), "full refresh lost native cooldown catch-up")
    w = New(path, native) First(w, "cooldown") Wait(w, "cooldown")
    w.ab.Dirty.Reset() w.m.active = false
    Fire(w, false)
    assert(w.counters.cooldown == 3, "disable kept parked paint")
    w.m.active = true w.ab.Mark("cooldown")
    assert(Pending(w, true) == 1, "reset kept stale waiting proof")
    Fire(w, true)
    assert(w.counters.cooldown == 6, "re-enable lost leading paint")

    -- Reset drops kinds, not a native callback already pending. Re-enable
    -- can reuse its earlier wake, which then rearms for the new kind's due.
    w = New(path, native) First(w, "cooldown") Wait(w, "cooldown")
    w.ab.Dirty.Reset() w.m.active = false
    w.m.active = true First(w, "usable")
    w.now = 10.02 First(w, "usable")
    w.now = 10.03 w.ab.Mark("usable")
    if Pending(w, true) > 0 then Fire(w, true) end
    Fire(w, false)
    assert(w.counters.usable == 3 and Pending(w, false) == 1, "reset changed pending callback handoff")
    Fire(w, false)
    assert(w.counters.usable == 6, "re-enabled kind lost final paint after earlier shared wake")

    -- Actual NewUnitRunner: one error is restored, a second retry is dropped.
    w = New(path, native) w.fail = 2
    First(w, "cooldown")
    assert(w.counters.errors == 1 and Pending(w) == 0, "failure repeated without next mark")
    w.now = 10.11 First(w, "cooldown")
    assert(w.counters.errors == 2 and Pending(w) == 0, "retry failure repeated itself")
    w.now = 10.22 w.ab.Mark("state") Fire(w, true)
    assert(w.counters.cooldown == 2, "dropped retry was resurrected by unrelated work")
    First(w, "cooldown")
    assert(w.counters.cooldown == 5, "fresh mark after dropped retry was suppressed")

    w = New(path, native) w.fail = 1
    w.ab.Mark("cooldown") w.ab.Mark("count") Fire(w, true)
    assert(w.counters.count == 3 and w.counters.errors == 1, "failed combined paint lost uncapped count")
    w.now = 10.11 First(w, "cooldown")
    assert(w.counters.cooldown == 4, "restored retry was lost")
    w = New(path, native) w.reenter = true
    First(w, "cooldown")
    assert(Pending(w, true) == 1, "reentrant fresh mark did not schedule")
    Fire(w, true) Fire(w, false)
    assert(w.counters.cooldown == 6, "reentrant mark was absorbed")
end

local function Repeat(w, case, iterations)
    for _ = 1, iterations do
        w.now = w.now + case.spacing
        w.ab.Mark(case.kind)
        if Pending(w, true) > 0 then Fire(w, true) end
    end
end
local function Deep(n) if n > 0 then Deep(n - 1) end return n end
local function Allocation(w, case)
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect") collectgarbage("stop") Deep(60)
        if case.waiting then w.now = 10.02 end
        local before = collectgarbage("count")
        Repeat(w, case, options.iterations)
        minimum = math.min(minimum, collectgarbage("count") - before)
        collectgarbage("restart")
    end
    return minimum
end
local cases = {
    { name = "waiting-cooldown", kind = "cooldown", spacing = .001, waiting = true },
    { name = "waiting-actionbarCooldown", kind = "actionbarCooldown", spacing = .001, waiting = true },
    { name = "waiting-usable", kind = "usable", spacing = .001, waiting = true },
    { name = "waiting-unreported", kind = "unreported", spacing = .001, waiting = true },
    { name = "fresh-state", kind = "state", spacing = .001 },
    { name = "fresh-cooldown", kind = "cooldown", spacing = .11 },
}
local measured = {}
for _, source in ipairs(sources) do
    measured[source.label] = {}
    for _, native in ipairs({ false, true }) do
        Behavior(source.path, native)
        for _, case in ipairs(cases) do
            local kind = case.kind
            local name = (native and "native/" or "owned/") .. case.name
            local w = New(source.path, native)
            if case.waiting then First(w, kind) Wait(w, kind) end
            ClearCounters(w)
            local instructions = 0
            debug.sethook(function()
                if debug.getinfo(2, "S").source == w.source then instructions = instructions + 1 end
            end, "", 1)
            Repeat(w, case, options.iterations)
            debug.sethook()
            assert(instructions > 0, "product instruction filter counted zero")
            local zero, cap, clock = w.counters.timerZero, w.counters.timerCap, w.counters.clock
            local wanted = kind == "state" and "state" or (kind == "usable" or kind == "unreported") and "usable" or "cooldown"
            local paints = case.waiting and 0 or options.iterations * 3
            assert(w.counters[wanted] == paints, "paint calls changed during measurement")
            local feedback = native and wanted == "cooldown" and not case.waiting and options.iterations or 0
            assert(w.counters.nativeFeedback == feedback, "native feedback changed during measurement")
            local allocated = Allocation(w, case)
            if case.waiting then
                Fire(w, false)
                assert(w.counters[wanted] == 3, "repeated marks lost final paint")
                assert(w.counters.nativeFeedback == (native and wanted == "cooldown" and 1 or 0), "trailing native feedback changed")
            else
                assert(Pending(w) == 0, "fresh work left unexpected deferred callbacks")
            end
            if limits and source.label ~= "baseline" then
                local limit = assert(limits.cases[name], "missing measured budget " .. name)
                assert(zero <= limit.timerZero, name .. ": redundant next-frame timer budget regressed")
                assert(cap <= limit.timerCap, name .. ": trailing timer budget regressed")
                assert(clock <= limit.clock, name .. ": clock native budget regressed")
                assert(instructions <= limit.instructions, name .. ": product VM budget regressed")
                assert(allocated <= limit.kilobytes, name .. ": allocation budget regressed")
            end
            measured[source.label][name] = { instructions = instructions, timerZero = zero, timerCap = cap,
                clock = clock, kilobytes = allocated, paintCalls = paints, nativeFeedback = feedback }
            print(string.format("SCHEDULE\t%s\t%s\t%d\t%d\t%d\t%d\t%.6f\t%d\t%d", source.label, name,
                instructions, zero, cap, clock, allocated, paints, feedback))
        end
    end
    print("BEHAVIOR\t" .. source.label .. "\tfresh/uncapped/shared deadlines/full/reset/disable/re-enable/failure/retry/reentrant passed")
end
if measured.baseline and measured.candidate then
    for name, after in pairs(measured.candidate) do
        local before = measured.baseline[name]
        print(string.format("DELTA\t%s\t%d\t%d\t%d\t%d\t%.6f", name,
            after.instructions - before.instructions, after.timerZero - before.timerZero,
            after.timerCap - before.timerCap, after.clock - before.clock, after.kilobytes - before.kilobytes))
    end
end
print("ActionBars cap schedule: actual dispatcher/unit runner, product VM, modeled native clocks/timers and minimum-of-two allocation; no live CPU/FPS claim")
