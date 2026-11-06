-- Differential replay against the original seven-channel spring: sparse
-- scheduling must preserve every intermediate value, not just the final pose.
local root = assert(arg[1])
local path = root .. "/MSUF_Suite_Skin/Rendering/Motion.lua"
local override = os.getenv("SUITE_MOTION_OVERRIDE_ROOT")
if override then path = override .. "/Rendering/Motion.lua" end
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local function Noop() end
local clock
local NS = { DB = { enabled = true, theme = {} }, IsCombatLocked = function() return false end,
    Safety = { IsForbidden = function() return false end, GetProtection = function() return false end },
    Registry = { AddListener = Noop } }
local env = setmetatable({ CreateFrame = function()
    clock = { scripts = {} }
    function clock:SetScript(event, callback) self.scripts[event] = callback end
    clock.Hide, clock.Show, clock.RegisterEvent = Noop, Noop, Noop
    return clock
end }, { __index = _G })
setfenv(assert(loadfile(path)), env)("MSUF_Suite_Skin", NS)
local Motion, records, models = NS.Motion, {}, {}
for index = 1, 2 do
    records[index] = Motion.New({ target = {}, spec = {} }, Noop, function() return true end, Noop)
    local model = { active = false, channels = {} }
    models[index] = model
    for channel = 1, 7 do
        model.channels[channel] = { value = channel == 7 and 1 or 0, target = channel == 7 and 1 or 0, velocity = 0 }
    end
end
local function Rest(model)
    model.active = false
    for _, channel in ipairs(model.channels) do channel.value, channel.velocity = channel.target, 0 end
end
local function Set(recordIndex, channelIndex, target, seed)
    Motion.Set(records[recordIndex], channelIndex, target, seed)
    local channel = models[recordIndex].channels[channelIndex]
    channel.target = target
    if seed ~= nil then channel.value, channel.velocity = seed, 0 end
end
local function Velocity(recordIndex, channelIndex, value)
    records[recordIndex].channels[channelIndex].velocity = value
    models[recordIndex].channels[channelIndex].velocity = value
end
local function Play(index, duration)
    Motion.Play(records[index], duration)
    local model, moving = models[index], false
    for _, channel in ipairs(model.channels) do
        moving = moving or math.abs(channel.value - channel.target) > .001 or math.abs(channel.velocity) > .01
    end
    if moving then model.active, model.age, model.duration = true, 0, duration or .14 else Rest(model) end
end
local function Clear(index)
    Motion.Clear(records[index])
    local model = models[index]
    for channel = 1, 7 do model.channels[channel].target = channel == 7 and 1 or 0 end
    Rest(model)
end
local function Predict(model, elapsed)
    if not model.active then return end
    model.age = model.age + elapsed
    local decay, moving = math.exp(-65 * elapsed), false
    -- Frozen numerical behavior of the previous integrator. It deliberately
    -- visits all channels, including exact rest and sub-threshold residue.
    for _, channel in ipairs(model.channels) do
        local delta = channel.value - channel.target
        local carry = channel.velocity + 65 * delta
        channel.value = channel.target + (delta + carry * elapsed) * decay
        channel.velocity = (channel.velocity - 65 * carry * elapsed) * decay
        moving = moving or math.abs(channel.value - channel.target) > .001 or math.abs(channel.velocity) > .01
    end
    if not moving or model.age >= model.duration then Rest(model) end
end
local function Tick(elapsed)
    local callback = clock.scripts.OnUpdate
    for _, model in ipairs(models) do Predict(model, elapsed) end
    if callback then callback(clock, elapsed) end
    local active = 0
    for index, model in ipairs(models) do
        if model.active then active = active + 1 end
        Check((records[index].index ~= nil) == model.active, "record activation changed")
        for channelIndex, expected in ipairs(model.channels) do
            local actual = records[index].channels[channelIndex]
            Check(actual.value == expected.value and actual.velocity == expected.velocity and actual.target == expected.target,
                "intermediate spring pose differs from the previous integrator")
        end
    end
    Check(Motion.count == active and (clock.scripts.OnUpdate ~= nil) == (active > 0), "idle clock lifecycle changed")
end

-- A below-threshold channel must still integrate while another channel moves.
Set(1, 1, 0, .0005)
Velocity(1, 1, .005)
Set(1, 2, 0, -3)
Play(1, .5)
Tick(.007)
-- Velocity alone starts a previously settled channel.
Velocity(2, 4, 2)
Play(2, .5)
Tick(.016)
-- Retarget without Play inserts previously absent channels in original order.
Set(1, 7, .4)
Set(1, 1, 2)
Set(1, 1, 2)
Tick(.009)
Set(1, 1, 0, 0)
Tick(.011)
Clear(2)
Tick(.013)

local random = 12345
local function Next(limit)
    random = (random * 1664525 + 1013904223) % 4294967296
    return random % limit + 1
end
for frame = 1, 400 do
    local index, channel = Next(2), Next(7)
    if frame % 5 == 0 then
        Set(index, channel, (Next(13) - 7) / 3, frame % 10 == 0 and 0 or nil)
        if frame % 15 == 0 then Velocity(index, channel, (Next(9) - 5) * .1) end
        if frame % 20 == 0 then Play(index, .4) end
    end
    if frame % 67 == 0 then Clear(index) end
    Tick(.003 + Next(10) * .001)
end
Clear(1)
Clear(2)
Tick(.5)
-- Preserve Stop's behavior for additional channels, even though skin-owned
-- records currently use seven fixed channels.
records[1].channels[8] = { value = 2, target = 3, velocity = 4 }
models[1].channels[8] = { value = 2, target = 3, velocity = 4 }
Play(1, .5)
Tick(.01)
Clear(1)
Tick(.01)
print("Skin motion replay: " .. checks .. " exact pose, velocity, retarget and lifecycle checks passed")
