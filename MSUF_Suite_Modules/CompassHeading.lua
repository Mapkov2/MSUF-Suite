local _, private = ...
local S = private.Suite
local Heading = {}
S.CompassHeading = Heading

local DEGREES = 180 / math.pi
local listeners, lastBearings = {}, {}
local pending

function Heading.Read()
    local facing = GetPlayerFacing()
    -- WoW's radians increase toward west, bearings increase toward east.
    if S.Finite(facing) then return (-facing * DEGREES) % 360 end
end

local function Tick()
    pending = nil
    local bearing = Heading.Read()
    for owner, callback in pairs(listeners) do
        local last = lastBearings[owner]
        if last == nil or last ~= (bearing or false) then
            if last ~= nil then lastBearings[owner] = bearing or false end
            S.Dispatch(callback, owner, bearing)
        end
    end
    if next(listeners) and not pending then pending = S.ScheduleDataTick("compassHeading", .05, Tick) end
end

-- A display that only needs turns can pass the bearing it has already painted.
-- Map overlays and fit-width data slots also need samples at a fixed heading.
function Heading.Watch(owner, callback, paintedBearing)
    listeners[owner] = callback
    lastBearings[owner] = paintedBearing
    if callback and not pending then
        pending = S.ScheduleDataTick("compassHeading", .05, Tick)
    elseif not callback and pending and not next(listeners) then
        pending:Cancel()
        pending = nil
    end
end
