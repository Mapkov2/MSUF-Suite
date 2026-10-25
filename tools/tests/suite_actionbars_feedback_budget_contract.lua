-- Actual Paint.lua feedback behavior and product-only VM/native/allocation cost.
-- No copied feedback implementation: load the complete chosen product chunk.
-- Measure first. Strict limits come only from an approved measurement file.
local options = { iterations = 1000 }
local at = 1
if arg[1] and arg[1]:sub(1, 2) ~= "--" then
    options.root = arg[1]:gsub("[/\\]+$", "")
    at = 2
end
while at <= #arg do
    local key = arg[at]
    if key == "--measure" then options.measure = true
    elseif key == "--strict" then options.strict = true
    elseif key == "--source" or key == "--baseline" or key == "--candidate"
        or key == "--budgets" or key == "--iterations" or key == "--dump-feedback" then
        at = at + 1
        options[key:sub(3)] = assert(arg[at], "missing value for " .. key)
    else error("unknown argument: " .. tostring(key)) end
    at = at + 1
end
if options.root then
    options.source = options.source or options.root .. "/MSUF_Suite_ActionBars/Paint.lua"
    options.budgets = options.budgets or options.root .. "/tools/tests/actionbars_feedback_budgets.lua"
    if not options.measure then options.strict = true end
end
options.iterations = assert(tonumber(options.iterations), "numeric iteration count required")
assert(options.iterations >= 1 and options.iterations % 1 == 0, "positive integer iterations required")
assert(not (options.measure and options.strict), "choose --measure or --strict")
assert(options.measure or options.strict, "run --measure before setting measured strict budgets")
local limits
if options.strict then
    limits = assert(loadfile(assert(options.budgets, "strict mode needs approved --budgets Lua file")))()
    assert(limits.iterations == options.iterations, "strict budgets use another iteration count")
end
local sources = {}
if options.baseline then sources[#sources + 1] = { label = "baseline", path = options.baseline } end
if options.candidate then sources[#sources + 1] = { label = "candidate", path = options.candidate } end
if options.source then sources[#sources + 1] = { label = "source", path = options.source } end
assert(#sources > 0, "provide --source, or --baseline and --candidate Paint.lua paths")

local NATIVE = { "duration", "evaluateDesat", "evaluateAlpha", "setDesaturation", "setAlpha" }
local READS = { "config", "desaturateCooldown", "cooldownAlpha" }
local CURVES = { "create", "setType", "clear", "add" }
local COLD_CASES = {
    { name = "unchanged-opacity", beforeD = false, beforeA = 40, afterD = false, afterA = 40 },
    { name = "changed-opacity", beforeD = false, beforeA = 40, afterD = false, afterA = 99 },
    { name = "same-opacity-desat-on", beforeD = false, beforeA = 40, afterD = true, afterA = 40 },
    { name = "same-opacity-desat-off", beforeD = true, beforeA = 40, afterD = false, afterA = 40 },
    { name = "full-opacity-boundary", beforeD = false, beforeA = 40, afterD = false, afterA = 100 },
}
local MODES = {
    { name = "desat", desaturate = true, alpha = 100 },
    { name = "alpha", desaturate = false, alpha = 40 },
    { name = "both", desaturate = true, alpha = 40 },
}
local CASES = {
    { name = "off-idle", desaturate = false, alpha = 100 },
    { name = "off-cleanup", desaturate = false, alpha = 100, feedback = true },
    { name = "alpha-zero", desaturate = false, alpha = 0 },
    { name = "alpha-near-full", desaturate = false, alpha = 99 },
    { name = "both-zero", desaturate = true, alpha = 0 },
    { name = "both-near-full", desaturate = true, alpha = 99 },
}
for _, state in ipairs({ "active", "ready", "inactive", "missing", "secret" }) do
    for _, mode in ipairs(MODES) do
        CASES[#CASES + 1] = {
            name = mode.name .. "-" .. state, desaturate = mode.desaturate, alpha = mode.alpha,
            active = state ~= "inactive", remaining = state == "ready" and 0 or 5,
            noObject = state == "missing", secret = state == "secret",
        }
    end
end

local function Copy(value)
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end

local function New(path)
    local w = { native = {}, reads = {}, curves = {}, values = {}, curveCreates = 0, curveChanges = 0,
        remaining = 5, lastDesat = 0, lastAlpha = 1, secretValue = {}, noObject = false, secret = false }
    for _, key in ipairs(NATIVE) do w.native[key] = 0 end
    for _, key in ipairs(READS) do w.reads[key] = 0 end
    for _, key in ipairs(CURVES) do w.curves[key] = 0 end
    local function Config()
        return setmetatable({}, { __index = function(_, key)
            if w.reads[key] ~= nil then w.reads[key] = w.reads[key] + 1 end
            return w.values[key]
        end })
    end
    w.config = Config()
    local m = setmetatable({}, { __index = function(_, key)
        if key == "config" then w.reads.config = w.reads.config + 1 return w.config end
    end })
    local ab = { M = m,
        ENUM = { PROC_GLOW = { BLIZZARD = 1, PIXEL = 2, NONE = 3 }, BAR = { MAIN = 1 } },
        Diagnostics = {}, UpdateAssist = function() end }
    local curveMethods = {}
    function curveMethods:SetType(kind) self.kind = kind w.curves.setType = w.curves.setType + 1 end
    function curveMethods:ClearPoints()
        self.points = {} w.curveChanges = w.curveChanges + 1 w.curves.clear = w.curves.clear + 1
    end
    function curveMethods:AddPoint(x, y)
        self.points[#self.points + 1] = { x, y } w.curves.add = w.curves.add + 1
    end
    local duration = {}
    function duration:EvaluateRemainingDuration(curve)
        local kind = curve == ab.desatCurve and "evaluateDesat" or "evaluateAlpha"
        assert(curve == ab.desatCurve or curve == ab.alphaCurve, "unexpected curve")
        w.native[kind] = w.native[kind] + 1
        if w.secret then return w.secretValue end
        local value = curve.points[1][2]
        for i = 2, #curve.points do
            if w.remaining >= curve.points[i][1] then value = curve.points[i][2] end
        end
        return value
    end
    local button = { icon = {} }
    function button.icon:SetDesaturation(value)
        w.native.setDesaturation = w.native.setDesaturation + 1
        w.lastDesat = value
    end
    function button:SetAlpha(value)
        w.native.setAlpha = w.native.setAlpha + 1
        w.lastAlpha = value
    end
    local env = setmetatable({
        Enum = { LuaCurveType = { Step = 1 } }, C_Spell = {}, C_SpellActivationOverlay = {},
        C_ActionBar = { GetActionCooldownDuration = function(slot, excludeGCD)
            assert(slot == 7 and excludeGCD == true, "feedback changed slot/GCD semantics")
            w.native.duration = w.native.duration + 1
            if not w.noObject then return duration end
        end },
        C_CurveUtil = { CreateCurve = function()
            w.curveCreates = w.curveCreates + 1
            w.curves.create = w.curves.create + 1
            return setmetatable({ points = {} }, { __index = curveMethods })
        end },
    }, { __index = _G })
    local p = { ActionBars = ab, NS = { IsSecret = function(value) return rawequal(value, w.secretValue) end },
        Suite = { Public = function(value) return not rawequal(value, w.secretValue) end,
            USABLE = { USABLE = 1, NO_POWER = 2, UNUSABLE = 3, OUT_OF_RANGE = 4 },
            USABLE_TINT = { { 1, 1, 1 }, { .5, .5, 1 }, { .4, .4, .4 }, { 1, .1, .1 } } } }
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("MSUF_Suite_ActionBars", p)
    ab.ResolveAPI()
    ab.ResolveAPI()
    assert(w.curveCreates == 2, "ResolveAPI rebuilt its persistent curves")
    w.ab, w.m, w.fn, w.rec = ab, m, ab.Painter.CooldownFeedback, { slot = 7, button = button }
    w.source = debug.getinfo(w.fn, "S").source
    assert(w.source == "@" .. path, "product VM source filter does not match loaded Paint")
    w.replaceConfig = function() w.config = Config() end
    return w
end

local function Reset(w)
    for _, key in ipairs(NATIVE) do w.native[key] = 0 end
    for _, key in ipairs(READS) do w.reads[key] = 0 end
    for _, key in ipairs(CURVES) do w.curves[key] = 0 end
end

local function Prepare(w, case)
    w.values.desaturateCooldown, w.values.cooldownAlpha = case.desaturate, case.alpha
    w.ab.UpdateCurves()
    assert(w.ab.directDuration == (not case.desaturate and case.alpha >= 100), "direct-duration mode drift")
    w.remaining, w.noObject, w.secret = case.remaining or 5, case.noObject == true, case.secret == true
    w.lastDesat, w.lastAlpha = "unwritten", "unwritten"
    Reset(w)
end

local function Loop(w, case, count)
    for _ = 1, count do
        w.rec.feedback = case.feedback
        w.fn(w.rec, case.active ~= false)
    end
end

local function Expected(case, count)
    local result = { duration = 0, evaluateDesat = 0, evaluateAlpha = 0, setDesaturation = 0, setAlpha = 0 }
    if not case.desaturate and case.alpha >= 100 and not case.feedback then return result end
    result.setDesaturation, result.setAlpha = count, count
    if not case.desaturate and case.alpha >= 100 or case.active == false then return result end
    result.duration = count
    if case.noObject then return result end
    result.evaluateDesat = case.desaturate and count or 0
    result.evaluateAlpha = case.alpha < 100 and count or 0
    return result
end

local function EqualCounts(actual, expected, label)
    for _, key in ipairs(NATIVE) do
        assert(actual[key] == expected[key], label .. ": changed native call count " .. key)
    end
end

local function Behavior(w, case)
    Prepare(w, case)
    local changes, creates = w.curveChanges, w.curveCreates
    Loop(w, case, 1)
    EqualCounts(w.native, Expected(case, 1), case.name)
    assert(changes == w.curveChanges and creates == w.curveCreates, "hot feedback changed curves")
    if not case.desaturate and case.alpha >= 100 and not case.feedback then
        assert(w.lastDesat == "unwritten" and w.lastAlpha == "unwritten", "off-idle painted")
        return
    end
    local dynamic = case.active ~= false and not case.noObject
    local desat = dynamic and case.desaturate and (case.secret and w.secretValue or (case.remaining == 0 and 0 or 1)) or 0
    local alpha = dynamic and case.alpha < 100 and (case.secret and w.secretValue or (case.remaining == 0 and 1 or case.alpha / 100)) or 1
    assert(rawequal(w.lastDesat, desat) and rawequal(w.lastAlpha, alpha), case.name .. ": sink arguments changed")
    if not case.desaturate and case.alpha >= 100 then assert(w.rec.feedback == nil, "cleanup flag not cleared") end
end

local function ColdTransitions(w)
    local alphaOnly = { name = "flip", desaturate = false, alpha = 40 }
    Prepare(w, alphaOnly)
    local changes = w.curveChanges
    w.values.desaturateCooldown = true
    w.ab.UpdateCurves()
    Loop(w, alphaOnly, 1)
    assert(w.lastDesat == 1 and w.lastAlpha == .4, "same-alpha enable bypassed cold mode update")
    assert(w.curveChanges == changes, "same-alpha enable rebuilt opacity curve")
    w.values.desaturateCooldown = false
    w.ab.UpdateCurves()
    Loop(w, alphaOnly, 1)
    assert(w.lastDesat == 0 and w.lastAlpha == .4, "same-alpha disable bypassed cold mode update")
    assert(w.curveChanges == changes, "same-alpha disable rebuilt opacity curve")
    local old = w.m.config
    w.replaceConfig()
    assert(w.m.config ~= old, "config replacement fixture reused table")
    w.values.desaturateCooldown, w.values.cooldownAlpha = true, 100
    w.ab.UpdateCurves()
    Loop(w, alphaOnly, 1)
    assert(w.lastDesat == 1 and w.lastAlpha == 1, "replacement config left stale modes")
end

local function ProductInstructions(w, callback)
    Reset(w)
    local instructions = 0
    debug.sethook(function()
        if debug.getinfo(2, "S").source == w.source then instructions = instructions + 1 end
    end, "", 1)
    callback()
    debug.sethook()
    assert(instructions > 0, "product instruction filter counted zero")
    return instructions
end

local function ProductVM(w, case, count)
    return ProductInstructions(w, function() Loop(w, case, count) end)
end

local function ColdCost(w, case)
    w.values.desaturateCooldown, w.values.cooldownAlpha = case.beforeD, case.beforeA
    w.ab.UpdateCurves()
    w.values.desaturateCooldown, w.values.cooldownAlpha = case.afterD, case.afterA
    local instructions = ProductInstructions(w, w.ab.UpdateCurves)
    local changed = case.beforeA ~= case.afterA
    assert(w.curves.create == 0 and w.curves.setType == 0, "refresh recreated persistent curves")
    assert(w.curves.clear == (changed and 1 or 0) and w.curves.add == (changed and 2 or 0),
        "cold opacity refresh changed native curve work")
    EqualCounts(w.native, Expected({ desaturate = false, alpha = 100 }, 1), "cold refresh")
    return { instructions = instructions, curves = Copy(w.curves), reads = Copy(w.reads) }
end

local function Deep(count)
    if count > 0 then Deep(count - 1) end
    return count
end

local function Allocation(w, case, count)
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        Deep(60)
        Reset(w)
        local before = collectgarbage("count")
        Loop(w, case, count)
        local allocated = collectgarbage("count") - before
        collectgarbage("restart")
        minimum = math.min(minimum, allocated)
    end
    return minimum
end

local results = {}
local coldResults = {}
for _, source in ipairs(sources) do
    local w = New(source.path)
    for _, case in ipairs(CASES) do Behavior(w, case) end
    ColdTransitions(w)
    results[source.label] = {}
    coldResults[source.label] = {}
    for _, case in ipairs(COLD_CASES) do
        local value = ColdCost(w, case)
        coldResults[source.label][case.name] = value
        if limits and source.label ~= "baseline" then
            local limit = assert(limits.coldCases[case.name], "missing measured cold budget " .. case.name)
            assert(value.instructions <= limit.instructions, case.name .. ": cold VM budget regressed")
        end
        print(string.format("COLD\t%s\t%s\t%d\t%d,%d,%d,%d\t%d,%d,%d", source.label,
            case.name, value.instructions, value.curves.create, value.curves.setType,
            value.curves.clear, value.curves.add, value.reads.config,
            value.reads.desaturateCooldown, value.reads.cooldownAlpha))
    end
    for _, case in ipairs(CASES) do
        Prepare(w, case)
        Loop(w, case, 100)
        local changes, creates = w.curveChanges, w.curveCreates
        local instructions = ProductVM(w, case, options.iterations)
        local allocated = Allocation(w, case, options.iterations)
        Reset(w)
        Loop(w, case, options.iterations)
        EqualCounts(w.native, Expected(case, options.iterations), source.label .. "/" .. case.name)
        assert(changes == w.curveChanges and creates == w.curveCreates, "measured hot path changed curves")
        local native, reads = Copy(w.native), Copy(w.reads)
        local value = { instructions = instructions, kilobytes = allocated, native = native, reads = reads }
        results[source.label][case.name] = value
        if limits and source.label ~= "baseline" then
            local limit = assert(limits.cases[case.name], "missing measured budget " .. case.name)
            assert(instructions <= limit.instructions, case.name .. ": product VM budget regressed")
            assert(allocated <= limit.kilobytes, case.name .. ": allocation budget regressed")
            if limit.configReads ~= nil then
                assert(reads.config <= limit.configReads and reads.desaturateCooldown <= limit.configReads
                    and reads.cooldownAlpha <= limit.configReads, case.name .. ": cold config was read hot")
            end
        end
        print(string.format("BUDGET\t%s\t%s\t%d\t%.6f\t%d,%d,%d,%d,%d\t%d,%d,%d",
            source.label, case.name, instructions, allocated, native.duration, native.evaluateDesat,
            native.evaluateAlpha, native.setDesaturation, native.setAlpha,
            reads.config, reads.desaturateCooldown, reads.cooldownAlpha))
    end
    if options["dump-feedback"] and source.label ~= "baseline" then
        local handle = assert(io.open(options["dump-feedback"], "wb"))
        handle:write(string.dump(w.fn))
        handle:close()
    end
    print("BEHAVIOR\t" .. source.label .. "\t" .. #CASES .. " cases + same-alpha flips/config replacement passed")
end
if results.baseline and results.candidate then
    for _, case in ipairs(COLD_CASES) do
        local before, after = coldResults.baseline[case.name], coldResults.candidate[case.name]
        for _, key in ipairs(CURVES) do
            assert(before.curves[key] == after.curves[key], "cold native curve counts differ: " .. case.name)
        end
        print(string.format("COLD_DELTA\t%s\t%d", case.name, after.instructions - before.instructions))
    end
    for _, case in ipairs(CASES) do
        local before, after = results.baseline[case.name], results.candidate[case.name]
        EqualCounts(after.native, before.native, "baseline/candidate " .. case.name)
        print(string.format("DELTA\t%s\t%d\t%.6f", case.name,
            after.instructions - before.instructions, after.kilobytes - before.kilobytes))
    end
end
print("Feedback budgets: product VM only; modeled native calls separate; allocation minimum of two; no live CPU/FPS claim")
