local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end
local Locations = {}
P.ForeverMapLocations = Locations
local FLIGHT, ROAD = 1, 6

local function PublicInfo(info)
    return S.Public(info) and type(info) == "table" and canaccesstable(info)
end

local function Rect(source, target)
    local left, right, top, bottom = C_Map.GetMapRectOnMap(source, target)
    if S.Finite(left) and S.Finite(right) and S.Finite(top) and S.Finite(bottom)
        and right > left and bottom > top then return left, right - left, top, bottom - top end
end

local function Copy(record)
    local copy = {}
    for i = 1, 8 do copy[i] = record[i] end
    return copy
end

local function Resolve(record)
    if record[4] == FLIGHT then return Copy(record) end
    local source = C_Map.GetMapInfo(record[1])
    if not PublicInfo(source) or not S.Finite(source.parentMapID) then return end
    local continent = source.parentMapID
    -- Zephras has its own world map, not an overlapping continent rectangle.
    if continent == 947 then return Copy(record) end
    if continent ~= 1414 and continent ~= 1415 then return end
    local left, width, top, height = Rect(record[1], continent)
    if not left then return end
    local x, y = left + record[2] * width, top + record[3] * height
    local actual = C_Map.GetMapInfoAtPosition(continent, x, y)
    if not PublicInfo(actual) or not S.Finite(actual.mapID) or not S.Finite(actual.mapType)
        or actual.mapType ~= Enum.UIMapType.Zone then return end
    left, width, top, height = Rect(actual.mapID, continent)
    if not left then return end
    x, y = (x - left) / width, (y - top) / height
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    local resolved = Copy(record)
    resolved[1], resolved[2], resolved[3] = actual.mapID, x, y
    return resolved
end

local function Destination(record, mapID)
    if not mapID or mapID <= 0 or mapID == record[1] then return end
    local list = record.destinations
    if not list then
        list = {}
        record.destinations = list
    end
    for i = 1, #list do if list[i] == mapID then return end end
    list[#list + 1] = mapID
end

local function Merge(output, record)
    local kind = record[4]
    if kind > FLIGHT and kind <= ROAD then
        for i = 1, #output do
            local old = output[i]
            if old[1] == record[1] and old[4] == kind and old[6] == record[6]
                and math.abs(old[2] - record[2]) < .002 and math.abs(old[3] - record[3]) < .002 then
                if record.destinations then
                    for _, target in ipairs(record.destinations) do Destination(old, target) end
                end
                return
            end
        end
    end
    output[#output + 1] = record
end

function Locations.Build(records)
    local resolved, groups, output = {}, {}, {}
    for i = 1, #records do
        local record, source = Resolve(records[i]), records[i]
        if record then
            resolved[#resolved + 1] = record
            if source[4] > FLIGHT and source[4] < ROAD and source[9] then
                local group = groups[source[9]]
                if not group then
                    group = {}
                    groups[source[9]] = group
                end
                group[#group + 1] = record
            elseif source[4] == ROAD then
                Destination(record, source[8])
            end
        end
    end
    for _, group in pairs(groups) do
        for i = 1, #group do
            for j = 1, #group do Destination(group[i], group[j][1]) end
        end
    end
    for i = 1, #resolved do
        local record = resolved[i]
        if record[4] ~= ROAD or record.destinations then Merge(output, record) end
    end
    return output
end
