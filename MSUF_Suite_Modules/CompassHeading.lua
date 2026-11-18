local _, private = ...
local S = private.Suite
local Heading = {}
S.CompassHeading = Heading

local DEGREES = 180 / math.pi
local listeners = {}
local pending

function Heading.Read()
    local facing = GetPlayerFacing()
    -- WoW's radians increase toward west, bearings increase toward east.
    if S.Finite(facing) then return (-facing * DEGREES) % 360 end
end

local function Tick()
    pending = nil
    local bearing = Heading.Read()
    for owner, callback in pairs(listeners) do S.Dispatch(callback, owner, bearing) end
    if next(listeners) and not pending then pending = S.ScheduleDataTick("compassHeading", .05, Tick) end
end

function Heading.Watch(owner, callback)
    listeners[owner] = callback
    if callback and not pending then
        pending = S.ScheduleDataTick("compassHeading", .05, Tick)
    elseif not callback and pending and not next(listeners) then
        pending:Cancel()
        pending = nil
    end
end
