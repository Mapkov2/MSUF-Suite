local _, NS = ...

-- Reuse the bounded motion clock; only owned fill and border colors blend.
local Palette = { epoch = 0 }
NS.PaletteMotion = Palette
local Motion, Safety, Theme = NS.Motion, NS.Safety, NS.Theme
local palettePolicy = { motion = true }

local function Safe(record)
    local state = record.state
    return state.visible ~= false and Safety.ReadUnprotected(state.target, "IsVisible") == true
end

local function Paint(record)
    local t, current = record.channels[1].value, record.current
    for index = 1, 12 do
        current[index] = record.from[index] + (record.to[index] - record.from[index]) * t
    end
    record.colorFrom = Theme.ReuseColor(record.colorFrom, current[1], current[2], current[3], current[4])
    record.colorTo = Theme.ReuseColor(record.colorTo, current[5], current[6], current[7], current[8])
    local state = record.state
    state.fill:SetVertexColor(1, 1, 1, 1)
    state.fill:SetGradient(record.direction, record.colorFrom, record.colorTo)
    state.edge:SetVertexColor(current[9], current[10], current[11], current[12])
end

local function Reset(record)
    Motion.Set(record, 1, 1, 1)
    Motion.Restore(record)
end

local function ReadTarget(record, material)
    local state, values = record.state, record.to
    local first, last = Theme.GetColorTable(material.from), Theme.GetColorTable(material.to)
    local strength = NS.DB.theme.gradient and (NS.DB.theme.gradientStrength or 1) or 0
    local opacity = Theme.GetMaterialOpacity(material) * (tonumber(state.spec.fillAlphaScale) or 1)
    local edge = Theme.GetColorTable(material.border)
    local borderOpacity, changed = Theme.GetBorderOpacity(), false
    for index = 1, 4 do
        local from = first[index]
        local to = from + (last[index] - from) * strength
        local border = edge[index]
        if index == 4 then from, to, border = from * opacity, to * opacity, border * borderOpacity end
        changed = changed or values[index] ~= from or values[index + 4] ~= to or values[index + 8] ~= border
        values[index], values[index + 4], values[index + 8] = from, to, border
    end
    record.direction = NS.DB.theme.gradientDirection or "VERTICAL"
    return changed
end

local function Enabled(state)
    return Motion.Enabled(state.spec) or state.spec.paletteMotion == true and Motion.Enabled()
end

local function Painted(state, material)
    local record = state.paletteMotion
    if not record then
        if not Enabled(state) then return end
        -- Keep only the last painted colors until a palette change actually
        -- animates. Cold menu construction needs no spring or channel tables.
        record = { state = state, to = {}, current = {}, palette = true }
        record.policy = state.spec.paletteMotion == true and palettePolicy or nil
        state.paletteMotion = record
        ReadTarget(record, material)
        for index = 1, 12 do record.current[index] = record.to[index] end
        record.epoch = Palette.epoch
        return
    end
    local targetChanged = ReadTarget(record, material)
    local changed = false
    for index = 1, 12 do changed = changed or record.current[index] ~= record.to[index] end
    local animate = changed and record.epoch ~= Palette.epoch and Enabled(state) and Safe(record)
    record.epoch = Palette.epoch
    if animate then
        Motion.New(state, Paint, Safe, Reset, record)
        record.from = record.from or {}
        for index = 1, 12 do record.from[index] = record.current[index] end
        Motion.Set(record, 1, 1, 0)
        Motion.Play(record, 0.12)
    elseif record.index and not targetChanged then
        Paint(record)
    elseif record.index then
        Motion.Stop(record)
    else
        for index = 1, 12 do record.current[index] = record.to[index] end
    end
end

local function Changed(_, domain, key)
    if domain == "profile" or domain == "theme" and (key == "preset" or key == "look" or key == "colors") then
        Palette.epoch = Palette.epoch + 1
    end
end
NS.Registry.AddListener(Palette, Changed)
NS.Surface.SetPaletteMotionProvider(Painted)
