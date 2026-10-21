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
        and not Motion.combat and not NS.IsCombatLocked()
        and (not spec or spec.motion ~= false and (not spec.ownedArt or spec.motion == true))
end

function Motion.New(state, paint, safe, reset)
    local record = { state = state, paint = paint, safe = safe, reset = reset, channels = {} }
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

function Motion.Stop(record)
    Remove(record)
    for index = 1, #record.channels do
        local channel = record.channels[index]
        channel.value, channel.velocity = channel.target, 0
    end
    if record.channels[5].target == 0 and record.channels[6].target == 0 then Motion.engaged[record] = nil end
    record.reset(record)
end

function Motion.Clear(record)
    for index = 1, 6 do Motion.Set(record, index, 0, 0) end
    Motion.Set(record, 7, 1, 1)
    record.focused, record.state.hovered = false, false
    Motion.Stop(record)
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
            for channelIndex = 1, #record.channels do
                local channel = record.channels[channelIndex]
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
end

function Motion.Play(record, duration)
    if not Motion.Enabled(record.policy or record.state.spec) or not record.safe(record) then
        Motion.Clear(record)
        return
    end
    local moving = false
    for index = 1, #record.channels do
        local channel = record.channels[index]
        moving = moving or abs(channel.value - channel.target) > 0.001 or abs(channel.velocity) > 0.01
    end
    if not moving then
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

clock:SetScript("OnEvent", function(_, event)
    Motion.combat = event == "PLAYER_REGEN_DISABLED"
    Motion.StopAll()
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
