local _, private = ...
local NS, S = private.NS, private.Suite
local QuestieSource = {}
private.NavigationHUDQuestie = QuestieSource

-- Questie.API has no map-marker enumeration. Read already registered map
-- pins from Questie's own HereBeDragons module, never its static database.
-- Verified on Forever v12.11.1, revision 1e74ea4bd7253e5d766782c100078ee58e659246:
-- https://github.com/Questie/Questie/blob/1e74ea4bd7253e5d766782c100078ee58e659246/Modules/Map/QuestieMap.lua
-- The provider's frame positions are percentages. HereBeDragons' x/y are
-- world coordinates and serve only to verify the registered map and owner.
local Public, Finite, Text = S.Public, S.Finite, S.PublicText
local MAX_MARKERS, MAX_REGISTRATIONS = 512, 12000
local attached = setmetatable({}, { __mode = "k" })
local changed, activeMap, pending

local function Table(value)
    return Public(value) and type(value) == "table" and canaccesstable(value)
end

local function Field(source, name)
    if not Table(source) then return end
    local value = source[name]
    if Public(value) then return value end
end

local function Sources()
    if not NS.Client.isForever then return end
    local questie = _G.Questie
    local api = Field(questie, "API")
    if not Table(api) then return end
    local loader = Field(_G.QuestieLoader, "_modules")
    return questie, api, Field(loader, "HBDPins"), Field(loader, "QuestieWaypoints")
end

local function NumberBetween(value, min, max)
    return Finite(value) and value >= min and value <= max
end

local function Asset(icon)
    if Public(icon) and (type(icon) == "string" and icon ~= "" or Finite(icon) and icon > 0) then return icon end
end

local function Marker(frame, points, map)
    if not Table(frame) then return end
    local frameMap = frame.UiMapID
    if not Finite(frameMap) or frameMap ~= map then return end
    if not Public(frame.hidden) or frame.hidden == true or not Public(frame._loaded) or frame._loaded ~= true then return end
    local record = points[frame]
    if not Table(record) then return end
    local registeredMap = record.uiMapID
    if not Finite(registeredMap) or registeredMap ~= map then return end
    local x, y = frame.x, frame.y
    if not NumberBetween(x, 0, 100) or not NumberBetween(y, 0, 100) then return end
    local data = frame.data
    if Table(data) then return data, x / 100, y / 100 end
end

local function Registry(pins, key, questie)
    return Field(Field(pins, key), questie)
end

local function Row(scan, frame, points, native)
    local data, x, y = Marker(frame, points, scan.map)
    if not data then return end
    local label = Text(data.Name) or Text(Field(data.QuestData, "Name"))
    local rawIcon = Field(data, "Icon")
    local texture
    if Public(frame.isManualIcon) and frame.isManualIcon == true then
        texture = Asset(rawIcon)
    elseif type(rawIcon) == "string" or Finite(rawIcon) then
        texture = Asset(Field(scan.icons, rawIcon))
    end
    scan.add(scan.output, x, y, label, nil, "questie", texture, nil, nil, nil, nil, native)
    scan.count = scan.count + 1
    return true
end

local function Collect(scan, owned, points, native, already)
    if not Table(owned) or not Table(points) then return end
    local inspected = 0
    for frame, registered in pairs(owned) do
        if Public(frame) and Public(registered) and registered == true then
            local twin = already and Field(frame, "minimapTwin")
            if not (twin and already[twin]) and Row(scan, frame, points, native) and not already then
                scan.mini[frame] = true
            end
        end
        inspected = inspected + 1
        if scan.count >= MAX_MARKERS or inspected >= MAX_REGISTRATIONS then return end
    end
end

function QuestieSource.Read(output, map, add)
    pending, activeMap = nil, nil
    if not Finite(map) or map <= 0 then return end
    activeMap = map
    local questie, api, pins = Sources()
    if Field(api, "isReady") ~= true or Field(questie, "enabledState") == false then return end
    local conf = Field(Field(questie, "db"), "profile")
    if Field(conf, "enabled") ~= true then return end
    local scan = { output = output, map = map, add = add, icons = Field(questie, "usedIcons"), mini = {}, count = 0 }
    local minimapEnabled = Field(conf, "enableMiniMapIcons")
    if minimapEnabled == true then
        local parent = Field(pins, "Minimap")
        local native = parent and parent == _G.Minimap and true or nil
        local owner = Registry(pins, "minimapPinRegistry", questie)
        Collect(scan, owner, Field(pins, "minimapPins"), native)
    end
    if scan.count < MAX_MARKERS and Field(conf, "enableMapIcons") == true then
        local owner = Registry(pins, "worldmapPinRegistry", questie)
        local native
        if minimapEnabled == false then native = false end
        Collect(scan, owner, Field(pins, "worldmapPins"), native, scan.mini)
    end
end

local function Notify(map)
    if not changed or pending or (map and activeMap and map ~= activeMap) then return end
    pending = true
    S.Dispatch(changed)
end

local function RegistrationChanged(_, owner, frame, map)
    if not changed or not Public(owner) or owner ~= _G.Questie then return end
    if not Finite(map) then map = Field(frame, "UiMapID") end
    Notify(Finite(map) and map or nil)
end

local function VisibilityChanged(frame)
    if not changed then return end
    local map = Field(frame, "UiMapID")
    if Finite(map) then Notify(map) end
end

local function Hook(target, names, callback)
    if not Table(target) then return end
    local methods = attached[target]
    if not methods then
        methods = {}
        attached[target] = methods
    end
    for _, name in ipairs(names) do
        if not methods[name] and type(Field(target, name)) == "function" then
            hooksecurefunc(target, name, callback)
            methods[name] = true
        end
    end
end

local PIN_METHODS = {
    "AddMinimapIconMap", "AddWorldMapIconMap", "RemoveMinimapIcon", "RemoveWorldMapIcon",
    "RemoveAllMinimapIcons", "RemoveAllWorldMapIcons",
}
local MINIMAP_METHODS = { "SetMinimapObject" }
local WAYPOINT_METHODS = { "OwnerChanged" }
local QUESTIE_METHODS = { "RefreshConfig", "SetIcons", "OnEnable", "OnDisable" }

local function AnyChanged() Notify() end

local readyAPI
local function ProviderReady()
    if not changed then return end
    local questie, api, pins, waypoints = Sources()
    if Field(api, "isReady") ~= true then return end
    readyAPI = api
    Hook(pins, PIN_METHODS, RegistrationChanged)
    Hook(pins, MINIMAP_METHODS, AnyChanged)
    Hook(waypoints, WAYPOINT_METHODS, VisibilityChanged)
    Hook(questie, QUESTIE_METHODS, AnyChanged)
    Notify()
end

function QuestieSource.Watch(callback)
    local wasWatching = changed ~= nil
    changed = callback
    if not changed then
        activeMap, pending = nil, nil
        return
    end
    local _, api = Sources()
    if Field(api, "isReady") == true then
        if not wasWatching or readyAPI ~= api then ProviderReady() end
    elseif api and readyAPI ~= api then
        local onReady = Field(api, "RegisterOnReady")
        if type(onReady) == "function" then
            readyAPI = api
            onReady(ProviderReady)
        end
    end
end
