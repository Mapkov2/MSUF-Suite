-- The sparse spring spends no work on static channels. Count actual Lua VM
-- instructions separately from native math calls, including full gestures.
local root = assert(arg[1])
local path = root .. "/MSUF_Suite_Skin/Rendering/Motion.lua"
local override = os.getenv("SUITE_MOTION_OVERRIDE_ROOT")
if override then path = override .. "/Rendering/Motion.lua" end
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end
local function Create(mode)
    local clock, native = nil, 0
    local NS = { DB = { enabled = true, theme = {} }, IsCombatLocked = function() return false end,
        Safety = { IsForbidden = function() return false end, GetProtection = function() return false end },
        Registry = { AddListener = Noop } }
    local mathEnv = math
    if mode == "native" then
        mathEnv = setmetatable({ abs = function(value) native = native + 1; return math.abs(value) end,
            exp = function(value) native = native + 1; return math.exp(value) end }, { __index = math })
    end
    local env = setmetatable({ math = mathEnv, CreateFrame = function()
        clock = { scripts = {} }
        function clock:SetScript(event, callback) self.scripts[event] = callback end
        clock.Hide, clock.Show, clock.RegisterEvent = Noop, Noop, Noop
        return clock
    end }, { __index = _G })
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)("MSUF_Suite_Skin", NS)
    return NS.Motion, clock, function(reset)
        local result = native
        if reset then native = 0 end
        return result
    end
end
local function Safe() return true end
local function New(Motion) return Motion.New({ target = {}, spec = {} }, Noop, Safe, Noop) end
local cases = { { name = "y", [2] = true }, { name = "reveal", [7] = true },
    { name = "all", true, true, true, true, true, true, true } }
local function Seed(Motion, record, case)
    for index = 1, 7 do
        local target = index == 7 and 1 or 0
        Motion.Set(record, index, target, case[index] and target + .31 * index or target)
    end
end
local function Measure(case, mode, complete)
    local Motion, clock, natives = Create(mode)
    local record = New(Motion)
    Seed(Motion, record, case)
    if not complete then Motion.Play(record, 10) end
    natives(true)
    local step = not complete and assert(clock.scripts.OnUpdate)
    local instructions = 0
    if mode == "vm" then debug.sethook(function() instructions = instructions + 1 end, "", 1) end
    if complete then
        Seed(Motion, record, case)
        Motion.Play(record, .16)
        for _ = 1, 23 do
            local update = clock.scripts.OnUpdate
            if update then update(clock, .007) end
        end
        Motion.Clear(record)
    else
        for _ = 1, 100 do step(clock, .001) end
    end
    debug.sethook()
    return mode == "vm" and instructions or natives()
end

for _, case in ipairs(cases) do
    local vm, native = Measure(case, "vm"), Measure(case, "native")
    local wholeVM, wholeNative = Measure(case, "vm", true), Measure(case, "native", true)
    -- The old 100-tick path took 24,209/29,709/23,109 instructions and
    -- 400/1,400/200 native math calls for y/reveal/all. Complete 23-tick
    -- gestures took 6,248/7,556/6,026 instructions and 99/336/57 calls.
    -- One reusable list per promoted surface is cold preparation, reused by
    -- retargets. No per-tick/per-gesture tables and no all-channel CPU trade.
    Check(vm <= (case.name == "all" and 23120 or 10500), case.name .. ": spring VM budget regressed")
    Check(native <= 200, case.name .. ": native integration calls regressed")
    Check(wholeVM <= (case.name == "all" and 6026 or 3300), case.name .. ": complete gesture VM budget regressed")
    Check(wholeNative <= (case.name == "all" and 57 or 60), case.name .. ": complete gesture native budget regressed")
    print(case.name .. " motion budget: " .. vm .. " VM / " .. native .. " native; complete " .. wholeVM .. " / " .. wholeNative)
end

local Motion, clock, natives = Create("native")
local record = New(Motion)
Seed(Motion, record, cases[3])
Motion.Play(record)
for _ = 1, 100 do
    local step = clock.scripts.OnUpdate
    if step then step(clock, .01) end
end
Check(Motion.count == 0 and clock.scripts.OnUpdate == nil, "settled skin retained an update driver")
natives(true)
local callbacks = 0
for _ = 1, 10000 do
    local callback = clock.scripts.OnUpdate
    if callback then callbacks = callbacks + 1; callback(clock, .01) end
end
Check(callbacks == 0 and natives() == 0, "static skin consumed animation callbacks or native math")
local channels, subset = record.channels, record.channels.moving
for _ = 1, 100 do
    Seed(Motion, record, cases[1])
    Motion.Play(record)
    Motion.Clear(record)
end
Check(record.channels == channels and record.channels.moving == subset, "repeat gestures replaced reusable channel storage")
local function ColdBytes(case)
    local samples = {}
    for trial = 1, 2 do
        local motion = Create("vm")
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 128 do
            local promoted = New(motion)
            Seed(motion, promoted, case)
            motion.Play(promoted, 10)
        end
        samples[trial] = (collectgarbage("count") - before) * 1024 / 128
        collectgarbage("restart")
    end
    return math.min(samples[1], samples[2])
end
local coldY, coldAll = ColdBytes(cases[1]), ColdBytes(cases[3])
print("Promoted motion bytes: y=" .. coldY .. ", all=" .. coldAll)
Check(coldY <= 2100 and coldAll <= 2250, "one-time sparse channel storage exceeded the cold allocation budget")
-- The list is allocated only when a surface first receives motion channels.
-- Independent old/new measurement records a bounded +80B for one channel.
local function WarmBytes()
    local samples = {}
    for trial = 1, 2 do
        local motion, frame = Create("vm")
        local promoted = New(motion)
        Seed(motion, promoted, cases[3])
        motion.Play(promoted)
        motion.Clear(promoted)
        Seed(motion, promoted, cases[1])
        motion.Play(promoted, 10)
        local step = assert(frame.scripts.OnUpdate)
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do step(frame, .00001) end
        for _ = 1, 100 do
            motion.Clear(promoted)
            Seed(motion, promoted, cases[1])
            motion.Play(promoted)
        end
        samples[trial] = (collectgarbage("count") - before) * 1024
        collectgarbage("restart")
    end
    return math.min(samples[1], samples[2])
end
local warm = WarmBytes()
Check(warm == 0, "steady ticks or repeated gestures allocated Lua storage")
print("Warm motion allocation: " .. warm .. " bytes for 1,000 ticks and 100 retargets")
print("Skin motion budgets: " .. checks .. " checks; 10,000 static frames have zero callbacks and zero native math")
