local _, NS = ...

-- One bounded spring clock for owned artwork. Nothing runs between gestures;
-- channels, callbacks and the active list are reused when a gesture retargets.
local Motion = { active = {}, engaged = {}, deferred = {}, count = 0, combat = false }
NS.Motion = Motion
local Safety = NS.Safety
local exp, abs = math.exp, math.abs
local clock = CreateFrame("Frame")
clock:Hide()

function Motion.Enabled(spec)
    local db = NS.DB
    local theme = db and db.theme
    return db ~= nil and db.enabled ~= false and theme ~= nil
        and theme.menuAnimations ~= false and theme.reduceMotion ~= true
        and (not spec or spec.motion ~= false and (not spec.ownedArt or spec.motion == true))
end

-- Palette snapshots exist before their first transition. Promote that same
-- per-surface record only when it animates; later gestures reuse its channels.
function Motion.New(state, paint, safe, reset, record)
    record = record or {}
    if record.channels then return record end
    record.state, record.paint, record.safe, record.reset = state, paint, safe, reset
    record.channels = { moving = {} }
    for index = 1, 7 do
        record.channels[index] = { value = 0, target = 0, velocity = 0 }
    end
    record.channels[7].value, record.channels[7].target = 1, 1
    return record
end

function Motion.Restore(record)
    if Safety.IsForbidden(record.state.target) then return end
    if Safety.GetProtection(record.state.target) and (Motion.combat or NS.IsCombatLocked()) then
        Motion.deferred[record] = true
    else
        Motion.deferred[record] = nil
        record.paint(record)
    end
end

local function Remove(record)
    local index = record.index
    if not index then return end
    local last = Motion.active[Motion.count]
    Motion.active[index], Motion.active[Motion.count] = last, nil
    if last ~= record then last.index = index end
    record.index = nil
    Motion.count = Motion.count - 1
    if Motion.count == 0 then
        clock:SetScript("OnUpdate", nil)
        clock:Hide()
    end
end

local function FinishStop(record, first)
    Remove(record)
    for index = first, #record.channels do
        local channel = record.channels[index]
        channel.value, channel.velocity = channel.target, 0
    end
    if record.channels[5].target == 0 and record.channels[6].target == 0 then Motion.engaged[record] = nil end
    record.reset(record)
end

function Motion.Stop(record)
    FinishStop(record, 1)
end

function Motion.Clear(record)
    for index = 1, 7 do
        local channel, target = record.channels[index], index == 7 and 1 or 0
        channel.target, channel.value, channel.velocity = target, target, 0
    end
    record.focused, record.state.hovered = false, false
    -- The seven skin channels already reached their rest pose above.
    FinishStop(record, 8)
end

local function Step(_, elapsed)
    local decay = exp(-65 * elapsed)
    for index = Motion.count, 1, -1 do
        local record = Motion.active[index]
        if not Motion.Enabled(record.policy or record.state.spec) or not record.safe(record) then
            Motion.Clear(record)
        else
            record.age = record.age + elapsed
            local moving = false
            local channels = record.channels.moving
            for channelIndex = 1, #channels do
                local channel = channels[channelIndex]
                local delta = channel.value - channel.target
                local carry = channel.velocity + 65 * delta
                channel.value = channel.target + (delta + carry * elapsed) * decay
                channel.velocity = (channel.velocity - 65 * carry * elapsed) * decay
                moving = moving or abs(channel.value - channel.target) > 0.001
                    or abs(channel.velocity) > 0.01
            end
            if not moving or record.age >= record.duration then Motion.Stop(record)
            else record.paint(record) end
        end
    end
end

function Motion.Set(record, index, target, seed)
    local channel = record.channels[index]
    channel.target = target
    if seed ~= nil then channel.value, channel.velocity = seed, 0 end
    -- A live retarget also accepts Set without a following Play. Keep the
    -- same channel order; resting entries may stay until the next gesture.
    if record.index and not channel.scheduled and (channel.value ~= channel.target or channel.velocity ~= 0) then
        local list, position = record.channels.moving, 1
        for earlier = 1, index - 1 do
            if record.channels[earlier].scheduled then position = position + 1 end
        end
        for cursor = #list, position, -1 do
            list[cursor + 1] = list[cursor]
        end
        list[position], channel.scheduled = channel, true
    end
end

-- Small residuals keep evolving; only exact rest is omitted. The list is
-- prepared per gesture and reused without allocations during its frames.
local function PrepareChannels(record)
    local list, count, moving = record.channels.moving, 0, false
    for index = 1, #record.channels do
        local channel = record.channels[index]
        channel.scheduled = channel.value ~= channel.target or channel.velocity ~= 0
        if channel.scheduled then
            count = count + 1
            list[count] = channel
            moving = moving or abs(channel.value - channel.target) > 0.001 or abs(channel.velocity) > 0.01
        end
    end
    for index = count + 1, #list do list[index] = nil end
    return moving
end

function Motion.Play(record, duration)
    if not Motion.Enabled(record.policy or record.state.spec) or not record.safe(record) then
        Motion.Clear(record)
        return
    end
    if not PrepareChannels(record) then
        Motion.Stop(record)
        return
    end
    record.age, record.duration = 0, duration or 0.14
    if record.channels[5].target ~= 0 or record.channels[6].target ~= 0 then Motion.engaged[record] = true end
    if not record.index then
        Motion.count = Motion.count + 1
        record.index = Motion.count
        Motion.active[Motion.count] = record
    end
    record.paint(record)
    clock:SetScript("OnUpdate", Step)
    clock:Show()
end

function Motion.StopAll(preservePalette)
    for index = Motion.count, 1, -1 do
        local record = Motion.active[index]
        if not (preservePalette and record.palette) then Motion.Clear(record) end
    end
    for record in pairs(Motion.engaged) do Motion.Clear(record) end
end

local function StopUnsafe(record)
    if not record.safe(record) then Motion.Clear(record) end
end

clock:SetScript("OnEvent", function(_, event)
    Motion.combat = event == "PLAYER_REGEN_DISABLED"
    for index = Motion.count, 1, -1 do StopUnsafe(Motion.active[index]) end
    for record in pairs(Motion.engaged) do StopUnsafe(record) end
    if not Motion.combat then
        for record in pairs(Motion.deferred) do record.reset(record) end
    end
end)
clock:RegisterEvent("PLAYER_REGEN_DISABLED")
clock:RegisterEvent("PLAYER_REGEN_ENABLED")
NS.Registry.AddListener(Motion, function(_, domain, key)
    local palette = domain == "profile" or domain == "theme"
        and (key == "preset" or key == "look" or key == "colors")
    Motion.StopAll(palette)
end)
