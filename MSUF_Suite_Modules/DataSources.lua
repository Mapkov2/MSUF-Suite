local _, Private = ...
local S = Private.Suite
local Dispatch, Finite, PublicText = S.Dispatch, S.Finite, S.PublicText

-- All Suite information displays share one deadline timer. A display owns one
-- reusable task per owner key; the native timer exists only while a task is due.
-- This is not ctx:After (Timers.lua): the owners are plain strings that need no
-- module context, and every due task rides on one native timer, where a wait
-- per context would arm one C_Timer per display and tick.
local tasks, taskPool, ready = {}, {}, {}
local timer, timerDue, dispatching = nil, nil, false


local Arm
local function FireTimer()
    timer, timerDue = nil, nil
    local now, readyCount = GetTime(), 0
    for owner, task in pairs(tasks) do
        if task.due <= now + 0.001 then
            tasks[owner] = nil
            readyCount = readyCount + 1
            ready[readyCount] = task.callback
        end
    end
    -- Callbacks usually schedule their next tick. Arm once afterwards. Each
    -- runs isolated: one that raises is reported, the others still run and
    -- the timer is armed again.
    dispatching = true
    for i = 1, readyCount do
        local callback = ready[i]
        ready[i] = nil
        Dispatch(callback)
    end
    dispatching = false
    Arm()
end

Arm = function()
    local due
    for _, task in pairs(tasks) do
        if not due or task.due < due then due = task.due end
    end
    if timer and due and timerDue and math.abs(timerDue - due) <= 0.001 then return end
    if timer then
        timer:Cancel()
        timer, timerDue = nil, nil
    end
    if not due then return end
    timerDue = due
    timer = C_Timer.NewTimer(math.max(0.05, due - GetTime()), FireTimer)
end

local function CancelTask(task)
    local owner = task.owner
    if tasks[owner] == task then
        tasks[owner] = nil
        if not dispatching then Arm() end
    end
end

-- Schedules callback once after delay seconds, replacing the owner's pending
-- tick. The returned handle is the owner's task table, reused for every tick;
-- handle:Cancel() cancels the owner's pending tick.
function S.ScheduleDataTick(owner, delay, callback)
    if type(owner) ~= "string" or type(callback) ~= "function" or type(delay) ~= "number" then return nil end
    local task = taskPool[owner]
    if not task then
        task = { owner = owner, Cancel = CancelTask }
        taskPool[owner] = task
    end
    task.due = GetTime() + math.max(0.05, delay)
    task.callback = callback
    tasks[owner] = task
    if not dispatching then Arm() end
    return task
end

------------------------------------------------------------------ shared samples
local snapshots = {}

-- Readers return at most a few values. Reject secret results before reusing
-- the existing tuple, so steady refreshes allocate no Lua tables and a secret
-- read never poisons the cached snapshot.
local function StoreValues(saved, ...)
    local count = select("#", ...)
    for i = 1, count do
        if not S.Public((select(i, ...))) then return nil end
    end
    local values = saved and saved.values or { n = 0 }
    local previous = values.n
    values.n = count
    for i = 1, count do values[i] = (select(i, ...)) end
    for i = count + 1, previous do values[i] = nil end
    return values
end

function S.ReadSharedData(key, ttl, reader)
    if type(key) ~= "string" or type(reader) ~= "function" then return nil end
    local now = GetTime()
    local saved = snapshots[key]
    if saved and saved.untilTime > now then return unpack(saved.values, 1, saved.values.n) end
    local values = StoreValues(saved, reader())
    if not values then return nil end
    local untilTime = now + math.max(0.05, tonumber(ttl) or 0.05)
    if saved then
        saved.untilTime = untilTime
    else
        snapshots[key] = { untilTime = untilTime, values = values }
    end
    return unpack(values, 1, values.n)
end

function S.InvalidateSharedData(key)
    snapshots[key] = nil
end

-- The readers call client APIs Retail and Forever both have; results that
-- are secret or out of range read as nil.
local readers = {
    fps = function()
        local value = GetFramerate()
        return Finite(value) and value >= 0 and value or nil
    end,
    latency = function()
        local _, _, home, world = GetNetStats()
        return Finite(home) and home >= 0 and home or nil,
            Finite(world) and world >= 0 and world or nil
    end,
    clockTime = function()
        local hour, minute = GetGameTime()
        return Finite(hour) and hour or nil, Finite(minute) and minute or nil
    end,
    clockStamp = function()
        local stamp = GetServerTime()
        return Finite(stamp) and stamp or nil
    end,
    coordinates = function()
        local mapID = C_Map.GetBestMapForUnit("player")
        if not Finite(mapID) or mapID <= 0 then return nil end
        -- nil where the map has no player position (instances).
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if not position then return nil end
        local x, y = position:GetXY()
        return Finite(x) and x >= 0 and x <= 1 and x or nil,
            Finite(y) and y >= 0 and y <= 1 and y or nil
    end,
    durability = function()
        local low, total, maximumTotal = nil, 0, 0
        for slot = 1, 19 do
            local current, maximum = GetInventoryItemDurability(slot)
            if not S.Public(current) or not S.Public(maximum) then return nil end
            if Finite(current) and Finite(maximum) and current >= 0 and maximum > 0 then
                current = math.min(current, maximum)
                local ratio = current / maximum
                if not low or ratio < low then low = ratio end
                total, maximumTotal = total + current, maximumTotal + maximum
            end
        end
        return low, total, maximumTotal
    end,
    location = function()
        return PublicText(GetZoneText()) or "", PublicText(GetSubZoneText()) or ""
    end,
    gold = function()
        local value = GetMoney()
        return Finite(value) and value >= 0 and math.floor(value) or nil
    end,
    bags = function()
        local slots, freeSlots = C_Container.GetContainerNumSlots, C_Container.GetContainerNumFreeSlots
        local free, total = 0, 0
        for bag = 0, 4 do
            local capacity, available = slots(bag), freeSlots(bag)
            if not Finite(capacity) or not Finite(available) then return nil end
            total, free = total + capacity, free + available
        end
        return free, total
    end,
    xp = function()
        local level, current, maximum = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
        if not Finite(level) or not Finite(current) or not Finite(maximum) then return nil end
        return level, current, maximum
    end,
}

function S.ReadInfoSource(key)
    local reader = readers[key]
    if not reader then return nil end
    return S.ReadSharedData(key, .05, reader)
end
