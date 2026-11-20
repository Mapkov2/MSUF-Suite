local _, private = ...
local S = private.Suite
local Offers, Services = private.NavigationHUDQuestOffers, private.NavigationHUDServices
local HandyNotes, Questie = private.NavigationHUDHandyNotes, private.NavigationHUDQuestie
local Points = {}
private.NavigationHUDPoints = Points

local HERB, ORE = 1, 2
local GATHER_SPELL = { [2366] = HERB, [2575] = ORE, [195122] = ORE, [423341] = ORE, [471013] = ORE }
local GATHER_TYPES = { "Herb Gathering", "Mining" }
local LOCAL_LIMIT, IMPORT_LIMIT, NATIVE_LIMIT = 512, 2048, 128
local GRID = 2000
local floor, min = math.floor, math.min
local Finite, Public, Text = S.Finite, S.Public, S.PublicText
Points.gatheringCells = 64

local function Table(value)
    return Public(value) and type(value) == "table"
end

local function Fraction(value)
    return Finite(value) and value >= 0 and value <= 1
end

local function Coordinates(vector)
    if not Table(vector) then return end
    local x, y = vector.x, vector.y
    if Fraction(x) and Fraction(y) then return x, y end
end

function Points.Position(map)
    return Coordinates(C_Map.GetPlayerMapPosition(map, "player"))
end

function Points.PlayerMap()
    local map = C_Map.GetBestMapForUnit("player")
    if Finite(map) and map > 0 then return map end
end

function Points.Size(map)
    local width, height = C_Map.GetMapWorldSize(map)
    if Finite(width) and Finite(height) and width > 0 and height > 0 then return width, height end
end

local function Encode(x, y, category)
    return (floor(x * GRID + .5) * (GRID + 1) + floor(y * GRID + .5)) * 2 + category - 1
end

local function Decode(code)
    local location = floor(code / 2)
    return floor(location / (GRID + 1)) / GRID, location % (GRID + 1) / GRID, code % 2 + 1
end

local function Recorded(map, create)
    local data = S.CharacterData("navigationHUDGathering")
    if not data then return end
    if type(data.zones) ~= "table" then
        if not create then return end
        data.zones = {}
    end
    local slots = data.zones[map]
    if create and type(slots) ~= "table" then
        slots = {}
        data.zones[map] = slots
    end
    if type(slots) == "table" then return slots end
end

function Points.GatherCategory(spell)
    if Finite(spell) then return GATHER_SPELL[spell] end
end

function Points.Record(category)
    local map = Points.PlayerMap()
    if not map then return false end
    local x, y = Points.Position(map)
    if not x then return false end
    local slots = Recorded(map, true)
    if not slots then return false end
    local code = Encode(x, y, category)
    local count = min(#slots, LOCAL_LIMIT)
    for i = 1, count do if Finite(slots[i]) and slots[i] == code then return false end end
    if count < LOCAL_LIMIT then
        slots[count + 1] = code
    else
        local cursor = Finite(slots.cursor) and floor(slots.cursor) % LOCAL_LIMIT + 1 or 1
        slots[cursor], slots.cursor = code, cursor
    end
    return true
end

local function Add(output, x, y, label, atlas, kind)
    if not Fraction(x) or not Fraction(y) then return end
    local point = { x = x, y = y, label = Text(label), atlas = Text(atlas), kind = kind }
    output[#output + 1] = point
    return point
end

local function AddAddon(output, x, y, label, atlas, kind, texture, left, right, top, bottom, nativeMinimap)
    local point = Add(output, x, y, label, atlas, kind)
    if not point then return end
    if Public(texture) and ((Finite(texture) and texture > 0) or Text(texture)) then
        point.icon = texture
        if Fraction(left) and Fraction(right) and Fraction(top) and Fraction(bottom) then
            point.left, point.right, point.top, point.bottom = left, right, top, bottom
        end
    end
    if Public(nativeMinimap) and type(nativeMinimap) == "boolean" then point.nativeMinimap = nativeMinimap end
end

local function AddPosition(output, vector, label, atlas, kind)
    local x, y = Coordinates(vector)
    if x then Add(output, x, y, label, atlas, kind) end
end

local function ReadAreaPOIs(output, map)
    local ids = C_AreaPoiInfo.GetAreaPOIForMap(map)
    if not Table(ids) then return end
    for i = 1, min(#ids, NATIVE_LIMIT) do
        local id = ids[i]
        local info = Finite(id) and C_AreaPoiInfo.GetAreaPOIInfo(map, id)
        if Table(info) then AddPosition(output, info.position, info.name, info.atlasName, "poi") end
    end
end

local function ReadQuests(output, map)
    local quests = C_QuestLog.GetQuestsOnMap(map)
    if not Table(quests) then return end
    local active = C_SuperTrack.GetSuperTrackedQuestID()
    for i = 1, min(#quests, NATIVE_LIMIT) do
        local pin = quests[i]
        if Table(pin) and Finite(pin.questID) and Fraction(pin.x) and Fraction(pin.y) then
            local title = Text(C_QuestLog.GetTitleForQuestID(pin.questID)) or S.Text("Quest destination")
            local kind = Finite(active) and active == pin.questID and "trackedQuest" or "quest"
            Add(output, pin.x, pin.y, title, nil, kind)
        end
    end
end

local function ReadTravel(output, map)
    local nodes = C_TaxiMap.GetTaxiNodesForMap(map)
    if not Table(nodes) then return end
    local faction = Text(UnitFactionGroup("player"))
    local filters = Enum.FlightPathFaction
    local own = faction and filters[faction]
    for i = 1, min(#nodes, NATIVE_LIMIT) do
        local node = nodes[i]
        if Table(node) and Finite(node.faction) and (node.faction == filters.Neutral or node.faction == own) then
            AddPosition(output, node.position, node.name, node.atlasName, "poi")
        end
    end
end

local function ReadVignettes(output, map)
    local vignettes = C_VignetteInfo.GetVignettes()
    if not Table(vignettes) then return end
    for i = 1, min(#vignettes, NATIVE_LIMIT) do
        local guid = Text(vignettes[i])
        local info = guid and C_VignetteInfo.GetVignetteInfo(guid)
        if Table(info) and ((Public(info.onMinimap) and info.onMinimap) or (Public(info.onWorldMap) and info.onWorldMap)) then
            AddPosition(output, C_VignetteInfo.GetVignettePosition(guid, map), info.name, info.atlasName, "poi")
        end
    end
end

local function ReadGatherMate(output, seen, category, map, label)
    -- The AddOn owns both these tables and its loading. Read the existing
    -- completed store only and let its API resolve expansion-partitioned DBs.
    local stub = _G.LibStub
    local ace = Table(stub) and type(stub.GetLibrary) == "function" and stub:GetLibrary("AceAddon-3.0", true)
    local addon = Table(ace) and type(ace.GetAddon) == "function" and ace:GetAddon("GatherMate2", true)
    local kind = GATHER_TYPES[category]
    if not Table(addon) or not Table(addon.gmdbs) or not Table(addon.gmdbs[kind])
        or type(addon.GetNodesForZone) ~= "function" then return end
    local count = 0
    for key in addon:GetNodesForZone(map, kind, true) do
        if Finite(key) and key >= 0 then
            local x, y = floor(key / 1000000) / 10000, floor(key % 1000000 / 100) / 10000
            if Fraction(x) and Fraction(y) then
                local cell = Encode(x, y, category)
                if not seen[cell] then
                    seen[cell] = true
                    Add(output, x, y, label, nil, category)
                end
            end
        end
        count = count + 1
        if count == IMPORT_LIMIT then break end
    end
end

function Points.GatheringCell(value)
    return min(Points.gatheringCells - 1, floor(value * Points.gatheringCells))
end

function Points.ReadGathering(map)
    local output = {}
    local labels = { S.Text("Herbalism"), S.Text("Mining") }
    local seen, nodes = {}, Recorded(map, false)
    if nodes then
        for i = 1, min(#nodes, LOCAL_LIMIT) do
            local code = nodes[i]
            if Finite(code) and code >= 0 and code == floor(code) and not seen[code] then
                local x, y, category = Decode(code)
                seen[code] = true
                Add(output, x, y, labels[category], nil, category)
            end
        end
    end
    for category = HERB, ORE do S.Dispatch(ReadGatherMate, output, seen, category, map, labels[category]) end
    local cells = {}
    for _, point in ipairs(output) do
        local index = Points.GatheringCell(point.y) * Points.gatheringCells + Points.GatheringCell(point.x)
        local bucket = cells[index]
        if not bucket then
            bucket = {}
            cells[index] = bucket
        end
        bucket[#bucket + 1] = point
    end
    return cells, #output
end

function Points.ReadMap(map, general, waypoint)
    local output = {}
    if waypoint then
        local pin = C_Map.GetUserWaypoint()
        if Table(pin) and Finite(pin.uiMapID) and pin.uiMapID == map then
            AddPosition(output, pin.position, S.Text("Map waypoint"), nil, "waypoint")
        end
    end
    if general then
        ReadAreaPOIs(output, map)
        ReadQuests(output, map)
        ReadTravel(output, map)
        ReadVignettes(output, map)
        for _, point in ipairs(S.WaypointPoints() or {}) do
            if point.map == map then Add(output, point.x, point.y, point.name, nil, "saved") end
        end
    end
    return output
end

function Points.ReadQuestOffers(map)
    local output = {}
    Offers.Read(output, map, Add)
    return output
end

function Points.ReadServices(map, useQuestieDB)
    local output = {}
    Services.Read(output, map, Add, useQuestieDB)
    return output
end

function Points.ReadHandyNotes(map, classifyNative)
    local output = {}
    HandyNotes.Read(output, map, AddAddon, classifyNative)
    return output
end

function Points.ReadQuestie(map)
    local output = {}
    Questie.Read(output, map, AddAddon)
    return output
end

local DEDUP_RESOLUTION = 10000
function Points.AddonBuckets(handyNotes, questie, native, offers, services)
    local buckets, seen, count, minimapCount = {}, {}, 0, 0
    local function PositionKey(point)
        return floor(point.x * DEDUP_RESOLUTION + .5) * (DEDUP_RESOLUTION + 1) + floor(point.y * DEDUP_RESOLUTION + .5)
    end
    local function Seed(other)
        if not other then return end
        for _, point in ipairs(other) do seen[PositionKey(point)] = true end
    end
    local function Merge(other)
        if not other then return end
        for _, point in ipairs(other) do
            local key = PositionKey(point)
            if not seen[key] then
                seen[key] = true
                local cell = Points.GatheringCell(point.y) * Points.gatheringCells + Points.GatheringCell(point.x)
                local bucket = buckets[cell]
                if not bucket then
                    bucket = {}
                    buckets[cell] = bucket
                end
                bucket[#bucket + 1], count = point, count + 1
                if point.nativeMinimap == false then minimapCount = minimapCount + 1 end
            end
        end
    end
    Seed(native)
    Seed(offers)
    Seed(services)
    Merge(questie)
    Merge(handyNotes)
    return buckets, count, minimapCount
end
