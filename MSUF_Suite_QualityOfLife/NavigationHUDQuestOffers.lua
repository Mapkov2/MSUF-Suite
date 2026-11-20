local _, private = ...
local S = private.Suite
local Offers = {}
private.NavigationHUDQuestOffers = Offers

local Public, Finite, Text = S.Public, S.Finite, S.PublicText
local floor, min = math.floor, math.min
local LIMIT, GRID, MAX_PARENT_MAPS = 128, 10000, 8
local ATLAS = "QuestNormal"
local CLASSIFICATION_ATLASES = {
    Recurring = "UI-QuestPoiRecurring-QuestBang",
    Meta = "quest-wrapper-available",
    Calling = "Quest-DailyCampaign-Available",
    Campaign = "Quest-Campaign-Available",
    Legendary = "UI-QuestPoiLegendary-QuestBang",
    Important = "importantavailablequesticon",
}

local requestedMap
local enum = Enum or {}
local floors = enum.QuestLineFloorLocation or {}
local classification = enum.QuestClassification or {}
local atlasByClassification = {}
for name, atlas in pairs(CLASSIFICATION_ATLASES) do
    local kind = classification[name]
    if kind then atlasByClassification[kind] = atlas end
end

local function Table(value)
    return Public(value) and type(value) == "table" and canaccesstable(value)
end

local function API(namespace, key)
    local value = Table(namespace) and namespace[key]
    if Public(value) and type(value) == "function" then return value end
end

local function True(read, ...)
    if not read then return false end
    local result = read(...)
    return Public(result) and result == true
end

local function InScope(scan, map)
    if not Public(map) then return false end
    if map == nil or map == scan.map then return true end
    if not Finite(map) or map <= 0 then return false end
    local parent, found = map, scan.children[map]
    if found ~= nil then return found end
    -- Build the ancestor answer in our own table rather than extending
    -- Blizzard's shared MapUtil cache from an addon.
    for _ = 1, MAX_PARENT_MAPS do
        local info = scan.mapInfo(parent)
        if not Table(info) then break end
        local nextMap = info.parentMapID
        if not Finite(nextMap) or nextMap <= 0 or nextMap == parent then break end
        if nextMap == scan.map then found = true break end
        parent = nextMap
    end
    scan.children[map] = found == true
    return found == true
end

local function Allowed(scan, offer, questID)
    local progress, hidden, story, completed = offer.inProgress, offer.isHidden, offer.isLocalStory, offer.isAccountCompleted
    if not (Public(progress) and Public(hidden) and Public(story) and Public(completed)) then return false end
    if progress == true or (hidden == true and not scan.hidden) or (story == true and not scan.stories) then return false end
    local level = offer.floorLocation
    if not Public(level) or (level ~= nil and level ~= scan.sameFloor) then return false end
    if completed == true and not scan.completed then
        local line = offer.questLineID
        if not (Finite(line) and line > 0 and True(scan.lineOverride, scan.map, line))
            and not True(scan.questOverride, questID) then return false end
    end
    return InScope(scan, offer.startMapID)
end

local function Icon(scan, questID)
    if scan.classification then
        local classification = scan.classification(questID)
        if Finite(classification) then return atlasByClassification[classification] or ATLAS end
    end
    return ATLAS
end

local function AddOffer(scan, offer, requestedID)
    if not Table(offer) then return end
    local questID, x, y = offer.questID, offer.x, offer.y
    if not Finite(questID) or questID <= 0 or (requestedID and questID ~= requestedID) or scan.ids[questID] then return end
    if not Finite(x) or not Finite(y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
    local label = Text(offer.questName)
    if not label or not Allowed(scan, offer, questID) then return end
    scan.ids[questID] = true
    local key = floor(x * GRID + .5) * (GRID + 1) + floor(y * GRID + .5)
    if scan.positions[key] then return end
    scan.positions[key] = true
    scan.add(scan.output, x, y, label, Icon(scan, questID), "questOffer")
end

local function Gather(scan, available)
    local list = available(scan.map)
    if Table(list) then
        for i = 1, min(#list, LIMIT) do AddOffer(scan, list[i]) end
    end
    local forced = API(C_QuestLine, "GetForceVisibleQuests")
    local info = API(C_QuestLine, "GetQuestLineInfo")
    if not forced or not info then return end
    local forceIDs = forced(scan.map)
    if not Table(forceIDs) then return end
    for i = 1, min(#forceIDs, LIMIT) do
        local id = forceIDs[i]
        if Finite(id) and id > 0 and not scan.ids[id] then
            AddOffer(scan, info(id, scan.map), id)
            scan.ids[id] = true
        end
    end
end

local function MapInfo(mapID)
    if not Finite(mapID) or mapID <= 0 then return end
    local read = API(C_Map, "GetMapInfo")
    local info = read and read(mapID)
    if not Table(info) or not Finite(info.mapType) then return end
    local kinds, mapType = enum.UIMapType, info.mapType
    if kinds and mapType ~= kinds.World and mapType ~= kinds.Continent and mapType ~= kinds.Cosmic then return read end
end

local function Scan(output, mapID, add, mapInfo)
    return {
        output = output, map = mapID, add = add, mapInfo = mapInfo,
        ids = {}, positions = {}, children = {},
        sameFloor = floors.Same,
        hidden = True(API(C_Minimap, "IsTrackingHiddenQuests")),
        completed = True(API(C_Minimap, "IsTrackingAccountCompletedQuests")),
        stories = True(API(C_CVar, "GetCVarBool"), "questPOILocalStory"),
        lineOverride = API(C_QuestLine, "QuestLineIgnoresAccountCompletedFiltering"),
        questOverride = API(C_QuestLog, "QuestIgnoresAccountCompletedFiltering"),
        classification = API(C_QuestInfoSystem, "GetQuestClassification"),
    }
end

-- Like Blizzard's World Map, request once when entering a map or after a
-- QUESTLINE_UPDATE that explicitly asks for new data. The ordinary result
-- event can then rebuild the caller's cached points without another request.
function Offers.Invalidate()
    requestedMap = nil
end

function Offers.Read(output, mapID, add)
    local available = API(C_QuestLine, "GetAvailableQuestLines")
    if not available then return end
    local mapInfo = MapInfo(mapID)
    if not mapInfo then return end
    if requestedMap ~= mapID then
        local request = API(C_QuestLine, "RequestQuestLinesForMap")
        requestedMap = mapID
        if request then request(mapID) end
    end
    Gather(Scan(output, mapID, add, mapInfo), available)
end
