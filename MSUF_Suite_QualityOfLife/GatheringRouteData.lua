local _, P = ...
local NS, S = P.NS, P.Suite
local Data = {}
P.GatheringRouteData = Data

Data.types = {
    { key = "herbs", label = "Herbalism", database = "Herb Gathering", color = { .40, .92, .51 } },
    { key = "ore", label = "Mining", database = "Mining", color = { 1, .70, .28 } },
    { key = "fish", label = "Fishing", database = "Fishing", color = { .38, .76, 1 } },
    { key = "timber", label = "Timber", database = "Logging", color = { .86, .55, .35 }, retail = true },
    { key = "skinning", label = "Skinning profession", color = { .82, .70, 1 } },
}
Data.yardsToMeters = .9144
Data.arrivalDistanceSquared = (4 / Data.yardsToMeters) ^ 2

function Data.Enabled(config, kind)
    local spec = Data.types[kind]
    return (not spec.retail or not NS.Client.isForever) and config[spec.key] == true
end

-- Tracking spells used by Blizzard_Minimap on Mainline and Camelot.
local TRACKING = { [2383] = 1, [8387] = 1, [2580] = 2, [8388] = 2, [43308] = 3 }
local MAX_OWN_PER_MAP = 512
local MAX_IMPORTED_PER_TYPE = 6000

local function ReadableTable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable(value)
end

function Data.ReadTracking(states)
    wipe(states)
    local count = C_Minimap.GetNumTrackingTypes()
    if not S.Finite(count) then return end
    for i = 1, count do
        local info = C_Minimap.GetTrackingInfo(i)
        if ReadableTable(info) and S.Finite(info.spellID) and S.Public(info.active) then
            local kind = TRACKING[info.spellID]
            if kind and states[kind] ~= true then states[kind] = info.active == true end
        end
    end
end

function Data.MapID(id)
    return S.Finite(id) and id > 0 and id % 1 == 0
end

function Data.ValidXY(x, y)
    return S.Finite(x) and S.Finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

function Data.PlayerXY(map)
    local position = C_Map.GetPlayerMapPosition(map, "player")
    if not S.Public(position) or not position then return end
    local x, y = position:GetXY()
    if Data.ValidXY(x, y) then return x, y end
end

-- Use the parent zone's coordinate system in micro-maps where it is readable.
function Data.Zone(map)
    local info = C_Map.GetMapInfo(map)
    if ReadableTable(info) and S.Public(info.mapType) and info.mapType == Enum.UIMapType.Micro
        and Data.MapID(info.parentMapID) then
        return info.parentMapID
    end
    return map
end

local function Saved(map, create)
    local data = S.CharacterData("gatheringRoutes")
    if not data then return end
    if type(data.nodes) ~= "table" then
        if not create then return end
        data.nodes = {}
    end
    if type(data.nodes[map]) ~= "table" then
        if not create then return end
        data.nodes[map] = {}
    end
    return data.nodes[map]
end

local function ValidNode(point)
    return type(point) == "table" and Data.types[point.kind] and Data.ValidXY(point.x, point.y)
end

local function Key(kind, x, y)
    return kind * 1000000000 + math.floor(x * 10000 + .5) * 10001 + math.floor(y * 10000 + .5)
end

function Data.Save(map, kind, x, y, name)
    local saved = Saved(map, true)
    if not saved then return false end
    for i = #saved, 1, -1 do
        local point = saved[i]
        if i > MAX_OWN_PER_MAP or not ValidNode(point) then
            table.remove(saved, i)
        elseif point.kind == kind and math.abs(point.x - x) < .001 and math.abs(point.y - y) < .001 then
            if name and not point.name then
                point.name = name
                return true, true
            end
            return true, false
        end
    end
    if #saved >= MAX_OWN_PER_MAP then return false end
    saved[#saved + 1] = { kind = kind, x = x, y = y, name = name }
    return true, true
end

function Data.Remove(map, source)
    local saved = Saved(map)
    if not saved then return end
    for i = 1, #saved do
        if saved[i] == source then
            table.remove(saved, i)
            return
        end
    end
end

local function Imported(points, seen, map, kinds)
    local gm = _G.GatherMate2
    if type(gm) ~= "table" or type(gm.gmdbs) ~= "table" or type(gm.GetNodesForZone) ~= "function"
        or type(gm.DecodeLoc) ~= "function" then return end
    for kind, spec in ipairs(Data.types) do
        local database = spec.database
        if kinds[kind] and database and gm.gmdbs[database] then
            local count = 0
            for coord, nodeID in gm:GetNodesForZone(map, database, true) do
                if count >= MAX_IMPORTED_PER_TYPE then break end
                count = count + 1
                if S.Finite(coord) then
                    local x, y = gm:DecodeLoc(coord)
                    if Data.ValidXY(x, y) then
                        local key = Key(kind, x, y)
                        if not seen[key] then
                            local name
                            if type(gm.GetNameForNode) == "function" and gm.reverseNodeIDs
                                and gm.reverseNodeIDs[database] and S.Finite(nodeID) then
                                name = S.PublicText(gm:GetNameForNode(database, nodeID))
                            end
                            points[#points + 1] = { kind = kind, x = x, y = y, key = key, name = name }
                            seen[key] = true
                        end
                    end
                end
            end
        end
    end
end

local function ByX(a, b)
    return a.x == b.x and a.key < b.key or a.x < b.x
end

function Data.Load(points, map, kinds)
    wipe(points)
    if not map then return end
    local seen = {}
    local saved = Saved(map)
    for i = 1, math.min(saved and #saved or 0, MAX_OWN_PER_MAP) do
        local point = saved[i]
        if ValidNode(point) and kinds[point.kind] then
            local key = Key(point.kind, point.x, point.y)
            if not seen[key] then
                points[#points + 1] = { kind = point.kind, x = point.x, y = point.y, key = key,
                    name = S.PublicText(point.name), source = point }
                seen[key] = true
            end
        end
    end
    Imported(points, seen, map, kinds)
    table.sort(points, ByX)
end
