local _, Private = ...
local S = Private.Suite

-- All Suite information displays share one deadline timer. A display owns a
-- cancellable task; the native timer exists only while at least one task does.
local tasks, timer, timerDue, dispatching = {}, nil, nil, false
local ready = {}
local function Now()
    local value = type(GetTime) == "function" and GetTime()
    return S.Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge and value or 0
end
local Arm
local function FireTimer()
    timer, timerDue = nil, nil
    local now, readyCount = Now(), 0
    for owner, task in pairs(tasks) do
        if task.due <= now + 0.001 then
            tasks[owner] = nil
            readyCount = readyCount + 1
            ready[readyCount] = task.callback
        end
    end
    dispatching = true
    local failure
    for i = 1, readyCount do
        local callback = ready[i]
        ready[i] = nil
        local ok, err = pcall(callback)
        if not ok and not failure then failure = err end
    end
    dispatching = false
    Arm()
    if failure then error(failure) end
end
Arm = function()
    local due
    for _, task in pairs(tasks) do
        if not due or task.due < due then due = task.due end
    end
    if timer and due and timerDue and math.abs(timerDue - due) <= 0.001 then return end
    if timer then timer:Cancel(); timer = nil; timerDue = nil end
    if not due or not C_Timer or type(C_Timer.NewTimer) ~= "function" then return end
    timerDue = due
    timer = C_Timer.NewTimer(math.max(0.05, due - Now()), FireTimer)
end

local function CancelTask(task)
    local owner = task.owner
    if tasks[owner] == task then
        tasks[owner] = nil
        if not dispatching then Arm() end
    end
end
function S.ScheduleDataTick(owner, delay, callback)
    if type(owner) ~= "string" or type(callback) ~= "function" or type(delay) ~= "number"
        or type(GetTime) ~= "function" or not C_Timer or type(C_Timer.NewTimer) ~= "function" then return nil end
    -- The task itself is the cancellation handle. Reusing one method avoids
    -- allocating a second table and a closure at every sampled display tick.
    local task = { owner = owner, due = Now() + math.max(0.05, delay), callback = callback, Cancel = CancelTask }
    tasks[owner] = task
    if not dispatching then Arm() end
    return task
end

local snapshots = {}
-- Readers return at most a few values. Validate the protected-call results
-- before reusing the existing tuple, so a failed or secret read never poisons
-- the cached snapshot and steady refreshes allocate no Lua tables.
local function StoreValues(saved, ...)
    local count = select("#", ...)
    if count == 0 or select(1, ...) ~= true then return nil end
    for i = 2, count do
        local value = select(i, ...)
        if not S.Public(value) then return nil end
    end
    local values = saved and saved.values or { n = 0 }
    local previous = values.n
    values.n = count - 1
    for i = 2, count do values[i - 1] = select(i, ...) end
    for i = count, previous do values[i] = nil end
    return values
end
function S.ReadSharedData(key, ttl, reader)
    if type(key) ~= "string" or type(reader) ~= "function" then return nil end
    local now = Now()
    local saved = snapshots[key]
    if saved and saved.untilTime > now then return unpack(saved.values, 1, saved.values.n) end
    local values = StoreValues(saved, pcall(reader))
    if not values then return nil end
    local untilTime = now + math.max(0.05, tonumber(ttl) or 0.05)
    if saved then saved.untilTime = untilTime
    else snapshots[key] = { untilTime = untilTime, values = values } end
    return unpack(values, 1, values.n)
end
function S.InvalidateSharedData(key) snapshots[key] = nil end

local function Number(value)
    return S.Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function PublicText(reader)
    if type(reader) ~= "function" then return "" end
    local value = reader()
    return S.Public(value) and type(value) == "string" and value or ""
end
local readers = {
    fps = function()
        if type(GetFramerate) ~= "function" then return nil end
        local value = GetFramerate()
        return Number(value) and value >= 0 and value or nil
    end,
    latency = function()
        if type(GetNetStats) ~= "function" then return nil end
        local _, _, home, world = GetNetStats()
        return Number(home) and home >= 0 and home or nil,
            Number(world) and world >= 0 and world or nil
    end,
    clockTime = function()
        if type(GetGameTime) ~= "function" then return nil end
        local hour, minute = GetGameTime()
        return Number(hour) and hour or nil, Number(minute) and minute or nil
    end,
    clockStamp = function()
        if type(GetServerTime) ~= "function" then return nil end
        local stamp = GetServerTime()
        return Number(stamp) and stamp or nil
    end,
    coordinates = function()
        if not C_Map or type(C_Map.GetBestMapForUnit) ~= "function"
            or type(C_Map.GetPlayerMapPosition) ~= "function" then return nil end
        local mapID = C_Map.GetBestMapForUnit("player")
        if not Number(mapID) or mapID <= 0 then return nil end
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if not S.Public(position) or (type(position) ~= "table" and type(position) ~= "userdata")
            or type(position.GetXY) ~= "function" then return nil end
        local x, y = position:GetXY()
        return Number(x) and x >= 0 and x <= 1 and x or nil,
            Number(y) and y >= 0 and y <= 1 and y or nil
    end,
    durability = function()
        if type(GetInventoryItemDurability) ~= "function" then return nil end
        local low, total, maximumTotal = nil, 0, 0
        for slot = 1, 19 do
            local current, maximum = GetInventoryItemDurability(slot)
            if not S.Public(current) or not S.Public(maximum) then return nil end
            if Number(current) and Number(maximum) and current >= 0 and maximum > 0 then
                current = math.min(current, maximum)
                local ratio = current / maximum
                if not low or ratio < low then low = ratio end
                total, maximumTotal = total + current, maximumTotal + maximum
            end
        end
        return low, total, maximumTotal
    end,
    location = function() return PublicText(GetZoneText), PublicText(GetSubZoneText) end,
    gold = function()
        if type(GetMoney) ~= "function" then return nil end
        local value = GetMoney()
        return Number(value) and value >= 0 and math.floor(value) or nil
    end,
    bags = function()
        local container = C_Container
        local slots = container and container.GetContainerNumSlots or _G.GetContainerNumSlots
        local freeSlots = container and container.GetContainerNumFreeSlots or _G.GetContainerNumFreeSlots
        if type(slots) ~= "function" or type(freeSlots) ~= "function" then return nil end
        local free, total = 0, 0
        for bag = 0, 4 do
            local capacity, available = slots(bag), freeSlots(bag)
            if not Number(capacity) or not Number(available) then return nil end
            total, free = total + capacity, free + available
        end
        return free, total
    end,
    xp = function()
        if type(UnitLevel) ~= "function" or type(UnitXP) ~= "function" or type(UnitXPMax) ~= "function" then return nil end
        local level, current, maximum = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
        if not Number(level) or not Number(current) or not Number(maximum) then return nil end
        return level, current, maximum
    end,
}
function S.ReadInfoSource(key)
    local reader = readers[key]
    if not reader then return nil end
    return S.ReadSharedData(key, .05, reader)
end
