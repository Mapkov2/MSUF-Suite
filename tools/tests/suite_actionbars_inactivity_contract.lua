-- Real paint, native hooks and native walks; public activity gates secret times.
local root = assert(arg[1])
local function New()
    local w = { duration = 0, desat = 0, alpha = 1, evaluations = 0, writes = 0,
        remaining = 0, hooks = {}, scripts = {}, secret = {}, secretChecks = 0, checks = 0, boundaries = 0 }
    setmetatable(w.secret, { __index = function() error("secret field read") end,
        __eq = function() error("secret comparison") end })
    local function IsSecret(value)
        w.checks = w.checks + 1
        if rawequal(value, w.secret) then w.secretChecks = w.secretChecks + 1; return true end
        return false
    end
    local S = { Public = function(value) return not IsSecret(value) end,
        Dispatch = function(fn, ...) w.boundaries = w.boundaries + 1; return fn(...) end,
        USABLE = { USABLE = 1, NO_POWER = 2, UNUSABLE = 3, OUT_OF_RANGE = 4 }, USABLE_TINT = {} }
    local M = { active = true, config = { desaturateCooldown = true, cooldownAlpha = 40,
        castHighlight = true, hideEmptyCharges = false, procGlow = 1 } }
    local AB = { M = M, records = {}, bars = {}, owned = {}, Diagnostics = {}, UpdateAssist = function() end,
        ENUM = { PROC_GLOW = { BLIZZARD = 1, PIXEL = 2, NONE = 3 }, BAR = { MAIN = 1 } } }
    local duration = {}
    function duration:EvaluateRemainingDuration(curve)
        w.evaluations = w.evaluations + 1
        if w.secretTime then return w.secret end
        local result = curve.points[1][2]
        for i = 2, #curve.points do
            if w.remaining >= curve.points[i][1] then result = curve.points[i][2] end
        end
        return result
    end
    local env = setmetatable({ C_Spell = {}, C_SpellActivationOverlay = {},
        Enum = { LuaCurveType = { Step = 1 } },
        C_ActionBar = { GetActionCooldownDuration = function(slot, ignoreGCD)
            assert(slot == w.rec.slot and ignoreGCD == true, "duration slot/GCD contract")
            w.duration = w.duration + 1
            if not w.noObject then return duration end
        end },
        C_CurveUtil = { CreateCurve = function()
            return { points = {}, SetType = function() end, ClearPoints = function(self) self.points = {} end,
                AddPoint = function(self, x, y) self.points[#self.points + 1] = { x, y } end }
        end },
        ActionButtonSpellAlertManager = {},
        hooksecurefunc = function(target, method, fn)
            if type(target) == "string" then fn, method = method, target end
            local key = type(target) == "string" and target or method
            assert(not w.hooks[key], "duplicate native hook " .. key)
            w.hooks[key] = fn
        end,
    }, { __index = _G })
    local P = { NS = { IsSecret = IsSecret }, Suite = S, ActionBars = AB }
    local function Load(path)
        local chunk = assert(loadfile(path)); setfenv(chunk, env); chunk("MSUF_Suite_ActionBars", P)
    end
    Load(root .. "/MSUF_Suite_ActionBars/Paint.lua")
    AB.ResolveAPI(); AB.UpdateCurves()
    local button = { cooldown = {}, chargeCooldown = {}, lossOfControlCooldown = {}, icon = {},
        IsVisible = function() return true end,
        HookScript = function(_, script, fn) w.scripts[script] = fn end }
    function button.icon:SetDesaturation(value) w.desat = value; w.writes = w.writes + 1 end
    function button:SetAlpha(value) w.alpha = value; w.writes = w.writes + 1 end
    local bar = { native = true, index = 2, buttons = {}, header = { IsVisible = function() return true end } }
    local rec = { native = true, slot = 61, button = button, bar = bar, filled = true }
    bar.buttons[1], AB.records[button], AB.bars[2], AB.owned[1] = rec, rec, bar, rec
    w.ab, w.rec, w.button = AB, rec, button
    Load(os.getenv("SUITE_ACTIONBARS_NATIVE_SOURCE") or root .. "/MSUF_Suite_ActionBars/NativeButtons.lua")
    -- Other native painters are outside this contract; their actual feedback is used.
    AB.Painter.api.InRange = function() end
    AB.RefreshNativeBar(bar)
    setmetatable(button, { __newindex = function() error("Blizzard button field write") end })
    function w:Paint(normal, charge, loss)
        local hook = self.hooks.ActionButton_ApplyCooldown
        if hook then hook(button.cooldown, normal, button.chargeCooldown, charge, button.lossOfControlCooldown, loss) end
    end
    function w:Walk(count)
        for _ = 1, count or 1 do AB.Painter.WalkNative(AB.NativeButtons.Feedback) end
    end
    function w:Reset()
        self.duration, self.evaluations, self.writes, self.checks, self.boundaries = 0, 0, 0, 0, 0
    end
    function w:Invalidate(kind)
        local hook = kind == "show" and self.scripts.OnShow or self.hooks.UpdateAction
        assert(hook, "missing native invalidation hook"); hook(button)
    end
    return w
end
local function Info(active)
    return setmetatable({ isActive = active }, { __index = function(_, key)
        error("gate read cooldown timing or GCD field " .. key)
    end })
end
local idle, active = Info(false), Info(true)
local function Neutral(w, label)
    assert(w.desat == 0 and w.alpha == 1, label .. ": neutral sinks differ")
end
local function Dynamic(w, label)
    assert(w.desat == 1 and w.alpha == .4, label .. ": active sinks differ")
end

-- This is the old-code red assertion: a normal native walk used a duration
-- getter and both evaluations on every inactive button, even with secret times.
local w = New()
w:Paint(idle, idle, idle); w:Reset(); w:Walk(100)
assert(w.duration == 0 and w.evaluations == 0, "inactive native walk exceeded zero duration/evaluation budget")
assert(w.writes == 2, "inactive native walk must paint neutral exactly once")
assert(w.checks == 0 and w.boundaries == 0, "inactive walk added native secret tests or boundaries")
Neutral(w, "inactive")
w:Reset(); w:Paint(idle, idle, idle)
assert(w.checks == 7 and w.boundaries == 1 and w.duration == 0 and w.writes == 0,
    "native paint hook must only check frame/info/activity secrecy and enter one boundary")
w:Walk(100)
assert(w.writes == 0, "repeated native inactive paint reset the neutral gate")
assert(w.hooks.ActionButton_ApplyCooldown and w.hooks.UpdateAction and w.scripts.OnShow, "native hooks absent")
collectgarbage("collect"); collectgarbage("stop")
local memory = collectgarbage("count")
for _ = 1, 1000 do w:Paint(idle, idle, idle); w:Walk() end
local growth = collectgarbage("count") - memory
collectgarbage("restart")
assert(growth < .01, "native inactivity hook/walk allocated per call")

-- Count only instructions in the two actual product chunks. Hook overhead
-- is separate from walks; their native calls are budgeted separately above.
local nativeSource = debug.getinfo(w.ab.NativeButtons.Feedback, "S").source
local paintSource = debug.getinfo(w.ab.Painter.CooldownFeedback, "S").source
local function Instructions(fn)
    local count = 0
    debug.sethook(function()
        local source = debug.getinfo(2, "S").source
        if source == nativeSource or source == paintSource then count = count + 1 end
    end, "", 1)
    fn()
    debug.sethook()
    return count
end
local idleVM = Instructions(function() w:Walk(100) end)
local hookVM = Instructions(function() for _ = 1, 100 do w:Paint(idle, idle, idle) end end)
w:Paint(active, idle, idle)
local fallbackVM = Instructions(function() w:Walk(100) end)
assert(idleVM < fallbackVM, "inactive walk failed to reduce product VM instructions")
print("ActionBars activity VM/100: idle=" .. idleVM .. " hook=" .. hookVM .. " fallback=" .. fallbackVM)

-- Blizzard's UpdateUsable can write desaturation for a level-link lock.
w:Paint(idle, idle, idle); w:Walk(); w.desat = 1
w.hooks.UpdateUsable(w.button); w:Reset(); w:Walk(10)
Neutral(w, "native usability repaint")
assert(w.writes == 2 and w.duration == 0, "native usable paint kept an obsolete neutral stamp")

-- Start, expiry, recharge and LoC retain today's duration-based outputs.
for _, state in ipairs({ { active, idle, idle }, { idle, active, idle }, { idle, idle, active } }) do
    w.remaining = 5; w:Paint(unpack(state)); w:Reset(); w:Walk(2)
    assert(w.duration == 2 and w.evaluations == 4 and w.writes == 4, "active/charge/LoC fallback call budget")
    Dynamic(w, "active/charge/LoC")
    w.remaining = 0; w:Walk(); Neutral(w, "expiry before native paint")
    w:Paint(idle, idle, idle); w:Reset(); w:Walk(50)
    assert(w.duration == 0 and w.writes == 2, "expiry failed to re-arm neutral gate")
    Neutral(w, "expiry")
end

-- Secret timing fields are never accessed; public inactive flags suffice.
w.secretTime = true; w:Paint(idle, idle, idle); w:Reset(); w:Walk(10)
assert(w.duration == 0 and w.writes == 0, "secret time disabled a public inactive gate")
-- Unknown/secret flags and whole payloads always discard previous inactivity.
for _, payload in ipairs({ w.secret, {}, { isActive = w.secret }, { isActive = 0 } }) do
    for index = 1, 3 do
        w:Paint(idle, idle, idle); w:Walk()
        local args = { idle, idle, idle }; args[index] = payload
        local checks = w.secretChecks
        w:Paint(unpack(args)); w:Reset(); w:Walk()
        if rawequal(payload, w.secret) or rawequal(payload.isActive, w.secret) then
            assert(w.secretChecks > checks, "secret payload was used without testing secrecy")
        end
        assert(w.duration == 1 and w.evaluations == 2, "unknown/secret state kept an inactive gate")
        assert(rawequal(w.desat, w.secret) and rawequal(w.alpha, w.secret), "secret sink values changed")
    end
end
for index = 1, 3 do
    w:Paint(idle, idle, idle); w:Walk()
    local args = { idle, idle, idle }; args[index] = nil
    w:Paint(args[1], args[2], args[3]); w:Reset(); w:Walk()
    assert(w.duration == 1, "nil info was treated as public inactive")
end
w.secretTime = false; w.remaining = 5

-- A slot value change is detected even before its native UpdateAction hook.
w:Paint(idle, idle, idle); w:Walk(); w.rec.slot = 62; w:Reset(); w:Walk()
assert(w.duration == 1, "slot remap reused old inactivity"); Dynamic(w, "slot remap")
w:Paint(idle, idle, idle); w:Reset(); w:Walk()
assert(w.duration == 0 and w.writes == 2, "new slot kept old neutral stamp")
for _, kind in ipairs({ "action", "page", "show" }) do
    w:Paint(idle, idle, idle); w:Walk(); w:Invalidate(kind); w:Reset(); w:Walk()
    assert(w.duration == 1, kind .. " did not invalidate native feedback")
    Dynamic(w, kind)
end
-- A nested native paint precedes UpdateAction's post-hook in Blizzard.
w:Paint(idle, idle, idle); w:Invalidate("action"); w:Reset(); w:Walk()
assert(w.duration == 1, "UpdateAction retained a nested stale native paint")

-- Setting refreshes clear the stamp, while disabled feedback cleans up once.
w:Paint(idle, idle, idle); w:Walk()
w.ab.M.config.cooldownAlpha = 25; w.ab.UpdateCurves(); w:Reset(); w.ab.RefreshNativeBar(w.rec.bar)
assert(w.duration == 1 and w.alpha == .25, "settings refresh reused old inactivity")
w.ab.M.config.desaturateCooldown = false; w.ab.M.config.cooldownAlpha = 100
w.ab.UpdateCurves(); w:Reset(); w.ab.RefreshNativeBar(w.rec.bar)
Neutral(w, "disabled feedback"); assert(w.duration == 0 and w.writes == 2, "disabled cleanup budget")
local boundaries, checks = w.boundaries, w.checks
w:Paint(active, active, active); w:Walk(10)
assert(w.duration == 0 and w.writes == 2, "disabled native walk gained work")
assert(w.boundaries == boundaries and w.checks == checks, "disabled feedback entered the native paint observer")
w.ab.M.config.desaturateCooldown = true; w.ab.M.config.cooldownAlpha = 40
w.ab.UpdateCurves(); w.ab.RefreshNativeBar(w.rec.bar); Dynamic(w, "reenable")

-- Existing LoC replacement and missing duration behavior remain unchanged.
w.ab.Painter.api.LoC = function() return { isActive = true, shouldReplaceNormalCooldown = true } end
w.ab.locActive = true; w:Paint(active, idle, active); w:Reset(); w:Walk()
Neutral(w, "LoC replacement"); assert(w.duration == 0, "LoC replacement queried duration")
w.ab.locActive = false; w.noObject = true; w:Paint(active, idle, idle); w:Walk()
Neutral(w, "missing duration")

-- Unregistered cooldown frames, secret frame arguments and disabled modules
-- cannot seed or reset an owned native button's inactivity.
w.noObject = false; w:Paint(idle, idle, idle); w:Walk()
local hook = w.hooks.ActionButton_ApplyCooldown
hook({}, active, {}, active, {}, active)
local checks = w.secretChecks
hook(w.secret, active, {}, active, {}, active)
assert(w.secretChecks == checks + 1, "secret cooldown frame was used without testing secrecy")
w.ab.M.active = false; w:Paint(active, active, active); w.ab.M.active = true
w:Reset(); w:Walk(10)
assert(w.duration == 0 and w.writes == 0, "foreign/disabled hook changed owned inactivity")
print("ActionBars native inactivity: sink equivalence, invalidations, secret fallbacks and zero idle duration calls pass")
