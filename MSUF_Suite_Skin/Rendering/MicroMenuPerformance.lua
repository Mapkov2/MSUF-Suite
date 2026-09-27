local _, NS = ...

-- Blizzard's performance bar is borrowed while the clean style is active:
-- recolored flat, laid next to the glyph and returned exactly as found.
-- Each property is owned separately and only while it still shows the
-- value we wrote; a later Blizzard write takes the property back.
-- Readers return nil when a value is missing or secret. Given `into`, a
-- scratch table of the button that only serves a comparison, they fill and
-- return it; without it they return a new table that may be kept. State
-- changes (SetNormal, SetPushed) therefore compare without allocating.
local Performance = {}
NS.MicroMenuPerformance = Performance

local Safety = NS.Safety
local HasMethod = Safety.HasMethod
local Clamp = NS.Clamp

-- The game menu button carries Blizzard's latency/framerate bar.
local PERFORMANCE_BUTTON = "MainMenuMicroButton"
local PERFORMANCE_BAR = "MainMenuBarPerformanceBar"

local function AllPublic(...)
    for index = 1, select("#", ...) do
        if not Safety.Public((select(index, ...))) then return false end
    end
    return true
end

local function Near(first, second)
    return type(first) == "number" and type(second) == "number"
        and math.abs(first - second) <= 0.00001
end

local function SameValue(first, second)
    if type(first) == "number" or type(second) == "number" then
        return Near(first, second)
    end
    return first == second
end

local function SameArray(first, second)
    if type(first) ~= "table" or type(second) ~= "table"
        or #first ~= #second then
        return false
    end
    for index = 1, #first do
        if not SameValue(first[index], second[index]) then return false end
    end
    return true
end

-- One anchor: point, relativeTo, relativePoint, x, y. Compared field by
-- field because relativeTo may be nil.
local POINT_FIELDS = 5

local function SamePoint(first, second)
    if type(first) ~= "table" or type(second) ~= "table" then return false end
    for index = 1, POINT_FIELDS do
        if not SameValue(first[index], second[index]) then return false end
    end
    return true
end

local function SamePoints(first, second)
    if type(first) ~= "table" or type(second) ~= "table"
        or #first ~= #second then
        return false
    end
    for index = 1, #first do
        if not SamePoint(first[index], second[index]) then return false end
    end
    return true
end

local function CapturePoints(region, into)
    local count = tonumber(Safety.Read(region, "GetNumPoints"))
    if count == nil then return nil end
    count = math.floor(count)
    local points = into or {}
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = Safety.Call(region, "GetPoint", index)
        if type(point) ~= "string" or not AllPublic(point, relativeTo, relativePoint, x, y) then
            return nil
        end
        local entry = points[index] or {}
        entry[1], entry[2], entry[3] = point, relativeTo, relativePoint
        entry[4], entry[5] = tonumber(x) or 0, tonumber(y) or 0
        points[index] = entry
    end
    for index = #points, count + 1, -1 do points[index] = nil end
    return points
end

local function WritePoints(region, points)
    if not Safety.Invoke(region, "ClearAllPoints") then return false end
    for index = 1, #points do
        region:SetPoint(unpack(points[index]))
    end
    return true
end

local function CaptureTextureSource(region, into)
    if not HasMethod(region, "GetAtlas") and not HasMethod(region, "GetTexture") then
        return nil
    end
    local source = into or {}
    source.atlas = Safety.Read(region, "GetAtlas")
    source.texture = Safety.Read(region, "GetTexture")
    return source
end

local function SameTextureSource(first, second)
    return type(first) == "table" and type(second) == "table"
        and first.atlas == second.atlas and first.texture == second.texture
end

local function WriteTextureSource(region, source)
    if source.atlas ~= nil then
        return Safety.Invoke(region, "SetAtlas", source.atlas)
    end
    return Safety.Invoke(region, "SetTexture", source.texture)
end

-- Four or eight coordinates; a shorter read clears the rest of `into`.
local function CaptureTexCoord(region, into)
    local first, second, third, fourth, fifth, sixth, seventh, eighth =
        Safety.Call(region, "GetTexCoord")
    if first == nil or not AllPublic(first, second, third, fourth, fifth, sixth, seventh, eighth) then
        return nil
    end
    local coords = into or {}
    coords[1], coords[2], coords[3], coords[4] = first, second, third, fourth
    if fifth ~= nil then
        coords[5], coords[6], coords[7], coords[8] = fifth, sixth, seventh, eighth
    else
        coords[8], coords[7], coords[6], coords[5] = nil, nil, nil, nil
    end
    return coords
end

local function WriteTexCoord(region, coords)
    return Safety.Invoke(region, "SetTexCoord", unpack(coords))
end

local function CaptureLayer(region, into)
    local layer, subLevel = Safety.Call(region, "GetDrawLayer")
    if type(layer) ~= "string" or not AllPublic(layer, subLevel) then return nil end
    local captured = into or {}
    captured[1], captured[2] = layer, tonumber(subLevel) or 0
    return captured
end

local function WriteLayer(region, layer)
    return Safety.Invoke(region, "SetDrawLayer", unpack(layer))
end

local function CaptureSize(region, into)
    local width = tonumber(Safety.Read(region, "GetWidth"))
    local height = tonumber(Safety.Read(region, "GetHeight"))
    if width == nil or height == nil then return nil end
    local size = into or {}
    size[1], size[2] = width, height
    return size
end

local function WriteSize(region, size)
    return Safety.Invoke(region, "SetSize", unpack(size))
end

-- Restored in this order; a rollback runs it backwards.
local PERFORMANCE_PROPERTIES = {
    { key = "source", capture = CaptureTextureSource, same = SameTextureSource, write = WriteTextureSource },
    { key = "texCoord", capture = CaptureTexCoord, same = SameArray, write = WriteTexCoord },
    { key = "layer", capture = CaptureLayer, same = SameArray, write = WriteLayer },
    { key = "points", capture = CapturePoints, same = SamePoints, write = WritePoints },
    { key = "size", capture = CaptureSize, same = SameArray, write = WriteSize },
}
-- The first three are set once; points and size follow the button size.
local SOURCE, TEX_COORD, LAYER, POINTS, SIZE = 1, 2, 3, 4, 5
-- The values written once; applied values may keep a reference to them,
-- so they are never mutated.
local FLAT_TEX_COORD = { 0, 1, 0, 1 }
local BAR_LAYER = { "OVERLAY", -5 }

-- The button's comparison scratch, one table per property, made once.
local function CaptureScratch(state)
    local scratch = state.captureScratch
    if not scratch then
        scratch = {}
        for index = 1, #PERFORMANCE_PROPERTIES do
            scratch[PERFORMANCE_PROPERTIES[index].key] = {}
        end
        state.captureScratch = scratch
    end
    return scratch
end

local function HasOwnedPerformanceProperty(applied)
    for index = 1, #PERFORMANCE_PROPERTIES do
        if applied.owned[PERFORMANCE_PROPERTIES[index].key] then return true end
    end
    return false
end

-- Where the bar goes for this button size. Rebuilt only when the size
-- changes; applied values may keep a reference, so it is never mutated.
local function PerformanceLayout(state, visualSize)
    local layout = state.performanceLayout
    if not layout or layout.visualSize ~= visualSize then
        layout = {
            visualSize = visualSize,
            points = { { "CENTER", state.button, "CENTER", math.max(7, visualSize * 0.5 - 3), 0 } },
            size = { 2, Clamp(visualSize - 14, 6, 12) },
        }
        state.performanceLayout = layout
    end
    return layout
end

local function CapturePerformanceRegion(state, region)
    local original = {}
    for index = 1, #PERFORMANCE_PROPERTIES do
        local property = PERFORMANCE_PROPERTIES[index]
        local value = property.capture(region)
        if not value then return false end
        original[property.key] = value
    end
    state.performance = { region = region, original = original }
    return true
end

local function RestorePerformanceRegion(state)
    local performance = state and state.performance
    if not performance or not performance.region or not performance.applied then
        return true
    end
    local region = performance.region
    local original = performance.original
    local applied = performance.applied
    local scratch = CaptureScratch(state)
    applied.restoring = true
    local success = true
    for index = 1, #PERFORMANCE_PROPERTIES do
        local property = PERFORMANCE_PROPERTIES[index]
        local key = property.key
        if applied.owned[key] then
            local current = property.capture(region, scratch[key])
            if not current then
                success = false
            elseif not property.same(current, applied[key]) then
                applied.owned[key] = false
            elseif property.write(region, original[key]) then
                applied.owned[key] = false
            else
                success = false
            end
        end
    end
    if not HasOwnedPerformanceProperty(applied) then
        state.performance = nil
    end
    return success
end

-- Moves an owned property to its desired value unless someone else has
-- taken it over. A failed write puts the previous value back.
local function FollowDesired(region, applied, property, desired, scratch)
    local key = property.key
    if not applied.owned[key] then return true end
    local current = property.capture(region, scratch)
    if not current then return false end
    if not property.same(current, applied[key]) then
        applied.owned[key] = false
        return true
    end
    if property.same(applied[key], desired) then return true end
    local previous = applied[key]
    if property.write(region, desired) then
        applied[key] = desired
        return true
    end
    if not property.write(region, previous) then
        applied[key] = property.capture(region) or previous
    end
    return false
end

-- Runs on every Micro Button state change of the performance button.
local function RefreshOwnedPerformanceRegion(performance, state, visualSize)
    local applied = performance.applied
    local region = performance.region
    local scratch = CaptureScratch(state)
    for index = SOURCE, LAYER do
        local property = PERFORMANCE_PROPERTIES[index]
        local key = property.key
        if applied.owned[key] then
            local current = property.capture(region, scratch[key])
            if not current then return false end
            if not property.same(current, applied[key]) then
                applied.owned[key] = false
            end
        end
    end
    local layout = PerformanceLayout(state, visualSize)
    local success = FollowDesired(region, applied, PERFORMANCE_PROPERTIES[POINTS],
        layout.points, scratch.points)
    return FollowDesired(region, applied, PERFORMANCE_PROPERTIES[SIZE], layout.size, scratch.size)
        and success
end

local function RollbackNewPerformanceRegion(state)
    local performance = state and state.performance
    local applied = performance and performance.applied
    if not performance or not applied then return true end
    local region = performance.region
    local original = performance.original
    local success = true

    -- This is the initial Apply call and Lua cannot yield between the mutation
    -- and this rollback. Restoring every property we successfully touched is
    -- therefore safe even when its post-write getter failed and there is no
    -- usable ownership comparison yet.
    for index = #PERFORMANCE_PROPERTIES, 1, -1 do
        local property = PERFORMANCE_PROPERTIES[index]
        if applied.owned[property.key] then
            if property.write(region, original[property.key]) then
                applied.owned[property.key] = false
            else
                success = false
            end
        end
    end

    if HasOwnedPerformanceProperty(applied) then
        applied.restoring = true
    else
        state.performance = nil
    end
    return success
end

-- Writes value, takes ownership, and records what the client reports back.
local function TakeProperty(region, applied, property, value)
    if not property.write(region, value) then return false end
    local key = property.key
    applied[key] = value
    applied.owned[key] = true
    local captured = property.capture(region)
    if not captured then return false end
    applied[key] = captured
    return true
end

local function ApplyNewPerformanceRegion(state, visualSize, region)
    if not CapturePerformanceRegion(state, region) then return false end
    local performance = state.performance
    local applied = { owned = {}, restoring = false }
    performance.applied = applied

    local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
    if not r then
        state.performance = nil
        return false
    end

    -- A flat white texture keeps the bar's own latency color as its tint.
    local success = false
    if Safety.Invoke(region, "SetColorTexture", 1, 1, 1, 1) then
        applied.owned.source = true
        local captured = CaptureTextureSource(region)
        applied.source = captured or {}
        success = captured ~= nil
        if not Safety.Invoke(region, "SetVertexColor", r, g, b, a) then success = false end
    end
    success = TakeProperty(region, applied, PERFORMANCE_PROPERTIES[TEX_COORD], FLAT_TEX_COORD) and success
    success = TakeProperty(region, applied, PERFORMANCE_PROPERTIES[LAYER], BAR_LAYER) and success
    local layout = PerformanceLayout(state, visualSize)
    success = TakeProperty(region, applied, PERFORMANCE_PROPERTIES[POINTS], layout.points) and success
    success = TakeProperty(region, applied, PERFORMANCE_PROPERTIES[SIZE], layout.size) and success

    if not success then
        RollbackNewPerformanceRegion(state)
        return false
    end
    return true
end

local function ApplyPerformanceRegion(state, visualSize)
    if state.buttonName ~= PERFORMANCE_BUTTON then return true end
    local currentRegion = Safety.Field(state.button, PERFORMANCE_BAR)
    local performance = state.performance

    if performance and performance.region ~= currentRegion then
        if performance.applied and not RestorePerformanceRegion(state) then
            return false
        end
        state.performance = nil
        performance = nil
    end
    if performance and performance.applied and performance.applied.restoring then
        if not RestorePerformanceRegion(state) then return false end
        performance = state.performance
    end
    if not currentRegion then return true end
    if not performance then
        return ApplyNewPerformanceRegion(state, visualSize, currentRegion)
    end
    return RefreshOwnedPerformanceRegion(performance, state, visualSize)
end

Performance.BUTTON = PERFORMANCE_BUTTON
Performance.BAR = PERFORMANCE_BAR
Performance.Apply = ApplyPerformanceRegion
Performance.Restore = RestorePerformanceRegion
