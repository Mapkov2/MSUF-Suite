local _, Private = ...
local S, NS = Private.Suite, Private.NS
local Dispatch, Finite, PublicText = S.Dispatch, S.Finite, S.PublicText
local max, abs = math.max, math.abs
local HasSecret = hasanysecretvalues

-- All Suite information displays share one deadline timer. A display owns one
-- reusable task per owner key; the native timer exists only while a task is due.
-- This is not ctx:After (Timers.lua): the owners are plain strings that need no
-- module context, and every due task rides on one native timer, where a wait
-- per context would arm one C_Timer per display and tick. On Retail 12.1.5 and
-- WoW Forever that timer is a C-side timed signal map (C_Timer.NewTimedSignalMap)
-- with one key per task, so a tick makes no timer object; 12.1.0 keeps the
-- shared C_Timer.NewTimer. The first arm picks the way for the session.
local tasks, taskPool, ready, readyGenerations = {}, {}, {}, {}
local timer, timerDue, dispatching = nil, nil, false
local signals, taskOfKey = nil, {}


local Arm
local function FireTimer()
    timer, timerDue = nil, nil
    local now, readyCount = GetTime(), 0
    for owner, task in pairs(tasks) do
        if task.due <= now + 0.001 then
            tasks[owner] = nil
            readyCount = readyCount + 1
            ready[readyCount] = task
            readyGenerations[readyCount] = task.generation
        end
    end
    -- Callbacks usually schedule their next tick. Arm once afterwards. Each
    -- runs isolated: one that raises is reported, the others still run and
    -- the timer is armed again.
    dispatching = true
    for i = 1, readyCount do
        local task, generation = ready[i], readyGenerations[i]
        ready[i], readyGenerations[i] = nil, nil
        if task.generation == generation then Dispatch(task.callback) end
    end
    dispatching = false
    Arm()
end

local function ArmTimer()
    local due
    for _, task in pairs(tasks) do
        if not due or task.due < due then due = task.due end
    end
    if timer and due and timerDue and abs(timerDue - due) <= 0.001 then return end
    if timer then
        timer:Cancel()
        timer, timerDue = nil, nil
    end
    if not due then return end
    timerDue = due
    timer = C_Timer.NewTimer(max(0.05, due - GetTime()), FireTimer)
end

-- The signal map runs a due task alone (isolated, like FireTimer's batch).
-- A key the map took for a pass before a callback earlier in it moved the
-- task's deadline comes early: it signals again for the rest.
local function TaskDue(key)
    local task = taskOfKey[key]
    if not task or tasks[task.owner] ~= task then return end
    local due = task.due
    if due > GetTime() + 0.001 then return signals:SignalAt(key, due) end
    tasks[task.owner], task.signalAt = nil, nil
    Dispatch(task.callback)
end
-- Every due task holds its own deadline under its key (signalAt). Only a
-- deadline that moved is set again and only a task that went is dropped, so
-- a display's tick costs one native call.
local function ArmSignal(task)
    if tasks[task.owner] == task then
        local key, due = task.key, task.due
        if not key then
            key = #taskOfKey + 1
            task.key, taskOfKey[key] = key, task
        end
        if task.signalAt ~= due then
            task.signalAt = due
            signals:SignalAt(key, due)
        end
    elseif task.signalAt then
        task.signalAt = nil
        signals:CancelSignal(task.key)
    end
end
Arm = function(task)
    local NewTimedSignalMap = C_Timer.NewTimedSignalMap
    if NewTimedSignalMap then signals = NewTimedSignalMap(TaskDue) end
    Arm = signals and ArmSignal or ArmTimer
    return Arm(task)
end

local function CancelTask(task)
    task.generation = task.generation + 1
    local owner = task.owner
    if tasks[owner] == task then
        tasks[owner] = nil
        if not dispatching then Arm(task) end
    end
end

-- Schedules callback once after delay seconds, replacing the owner's pending
-- tick. The returned handle is the owner's task table, reused for every tick;
-- handle:Cancel() cancels the owner's pending tick.
function S.ScheduleDataTick(owner, delay, callback)
    if type(owner) ~= "string" or type(callback) ~= "function" or type(delay) ~= "number" then return nil end
    local task = taskPool[owner]
    if not task then
        task = { owner = owner, Cancel = CancelTask, generation = 0 }
        taskPool[owner] = task
    end
    task.generation = task.generation + 1
    task.due = GetTime() + max(0.05, delay)
    task.callback = callback
    tasks[owner] = task
    if not dispatching then Arm(task) end
    return task
end

------------------------------------------------------------------ shared samples
local snapshots = {}
local memoryScanTime, memoryTotal, memoryRows, listedMemory
local positionMap, positionUntil, positionX, positionY, movingUntil
local worldX, worldY, worldZ, worldInstance

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
    if key == "coordinates" then positionMap, movingUntil = nil, nil end
end

local function Project(map)
    local position = C_Map.GetPlayerMapPosition(map, "player")
    if not S.Public(position) or type(position) ~= "table" then return end
    local px, py = position:GetXY()
    if Finite(px) and px >= 0 and px <= 1 and Finite(py) and py >= 0 and py <= 1 then return px, py end
end

-- The native map projection returns a new Vector2D. In the open world its
-- result can be shared while the public world position is exactly the same.
-- Reproject at least once a second for same-map phasing. While moving use
-- fresh projections directly and check for a stationary interval once per second.
function S.ReadPlayerMapPosition(map, openWorld)
    if not Finite(map) or map <= 0 then return end
    if not UnitPosition then return Project(map) end
    local now = GetTime()
    if movingUntil and now < movingUntil then return Project(map) end
    if not openWorld then
        local inside = IsInInstance()
        if not S.Public(inside) or inside ~= false then
            positionMap = nil
            return Project(map)
        end
    end
    local x, y, z, instance = UnitPosition("player")
    if HasSecret(x, y, z, instance) then
        positionMap = nil
        return Project(map)
    end
    local sameMap = positionMap == map
    local samePosition = sameMap and x == worldX and y == worldY and z == worldZ and instance == worldInstance
    if samePosition and now < positionUntil then return positionX, positionY end
    if not (Finite(x) and Finite(y) and Finite(z) and Finite(instance)) or instance < 0 or (x == 0 and y == 0) then
        positionMap = nil
        return Project(map)
    end
    if sameMap and not samePosition then movingUntil = now + 1 end
    local px, py = Project(map)
    positionMap = nil
    if px then
        worldX, worldY, worldZ, worldInstance = x, y, z, instance
        positionMap, positionUntil, positionX, positionY = map, now + 1, px, py
    end
    return px, py
end

-- Blizzard's process-wide sample is synchronous. Only an explicit request
-- takes it. The data text and the tooltip share the resulting snapshot.
function S.RefreshAddonMemory()
    if not (GetAddOnMemoryUsage and UpdateAddOnMemoryUsage) then return end
    local now = GetTime()
    if memoryScanTime == now then return true end
    local count = C_AddOns.GetNumAddOns()
    if not Finite(count) then return end
    UpdateAddOnMemoryUsage()
    local rows, total, listed, complete = {}, 0, 0, true
    for index = 1, count do
        local usage = GetAddOnMemoryUsage(index)
        if not Finite(usage) or usage < 0 then
            complete = false
        elseif usage > 0 then
            total = total + usage
            local name = C_AddOns.GetAddOnInfo(index)
            if S.Public(name) and type(name) == "string" then
                rows[#rows + 1] = { name = name, kb = usage }
                listed = listed + usage
            end
        end
    end
    memoryScanTime, memoryRows, listedMemory = now, rows, listed
    memoryTotal = complete and total / 1024 or nil
    return true
end

function S.GetAddonMemoryReport()
    return memoryRows, listedMemory
end

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
        return S.ReadPlayerMapPosition(C_Map.GetBestMapForUnit("player"))
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
        return PublicText(GetZoneText()) or "", PublicText(GetSubZoneText()) or "", PublicText(GetMinimapZoneText()) or ""
    end,
    gold = function()
        local value = GetMoney()
        return Finite(value) and value >= 0 and math.floor(value) or nil
    end,
    bags = function()
        local slots, freeSlots = C_Container.GetContainerNumSlots, C_Container.GetContainerNumFreeSlots
        local free, total = 0, 0
        local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
        local forever = NS and NS.Client.isForever
        for bag = 0, lastBag do
            local capacity = slots(bag)
            local available, family = freeSlots(bag)
            if not Finite(capacity) or not Finite(available) then return nil end
            if not (forever and Finite(family) and family ~= 0) then
                total, free = total + capacity, free + available
            end
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
    if key == "memory" then return memoryTotal end
    local reader = readers[key]
    if not reader then return nil end
    return S.ReadSharedData(key, .05, reader)
end
