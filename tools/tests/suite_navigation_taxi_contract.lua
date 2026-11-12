-- The map pin and the focused quest on the old flight map (TaxiFrame,
-- NavigationTaxi.lua). The taxi map has no UI map: its scale is measured from
-- the flight points, which the client places on both maps.
local root = assert(arg[1])
local base = arg[2] or root
local secret = {}
local function Public(value) return value ~= secret end
local function Finite(value) return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge end
local function PublicText(value) return Public(value) and type(value) == "string" and value or nil end
local methods = {}
local function Frame(parent)
    return setmetatable({ shown = true, parent = parent, level = 1, scripts = {} }, { __index = methods })
end
function methods:SetScript(key, fn) self.scripts[key] = fn end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetPoint(...) self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:SetAllPoints() end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(level) self.level = level end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetRotation(angle) self.angle = angle end
function methods:SetVertexColor(...) self.color = { ... } end
function methods:EnableMouse(on) self.mouse = on end
function methods:SetMouseClickEnabled(on) self.clicks = on end
UIParent = Frame()
TaxiFrame = Frame(UIParent)
TaxiRouteMap = Frame(TaxiFrame)
TaxiRouteMap.level = 5
TAXI_MAP_WIDTH, TAXI_MAP_HEIGHT = 580, 580
GameTooltip = Frame(UIParent)
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
function GameTooltip:SetText(text) self.lines[1] = text end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:IsOwned(owner) return self.owner == owner end
Enum = { SuperTrackingType = { Quest = 1, UserWaypoint = 2, MapPin = 3, Content = 4, Vignette = 5 },
    UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
CreateVector2D = function(x, y) return { x = x, y = y } end

-- The world: continent 13 is 1000 x 1000 world units of instance 0; zone 1433
-- is its part x .4-.6, y .5-.7; zone 1411 lies on another continent. The taxi
-- map shows the continent as x' = .1 + .8x, y' = .05 + .9y.
local ZONE = { x = .4, y = .5, size = .2 }
local function TaxiX(x) return .1 + .8 * x end
local function TaxiY(y) return .05 + .9 * y end
local world = { pin = { map = 1433, x = .5, y = .5 }, quest = 77, questX = .25, questY = .75, player = 1433 }
-- Flight points by slot: continent position, and a hand-made shift on the taxi map.
local nodes = { { .2, .3 }, { .5, .6 }, { .8, .4 }, { .45, .9 }, { .6, .1 }, { .3, .7, shift = .09 } }
local counters = { measured = 0 }
local function Entries(toMap)
    local entries = {}
    for slot, node in ipairs(nodes) do
        entries[#entries + 1] = { slotIndex = slot, nodeID = 100 + slot, isMapLayerTransition = false,
            position = { x = toMap(node[1], ZONE.x), y = toMap(node[2], ZONE.y) } }
    end
    entries[#entries + 1] = { slotIndex = 99, isMapLayerTransition = true, position = { x = 0, y = 0 } }
    return entries
end
C_TaxiMap = { GetAllTaxiNodes = function(map)
    counters.measured = counters.measured + 1
    if world.noNodes then return secret end
    if map == 13 then return world.noContinentNodes and {} or Entries(function(value) return value end) end
    if map == 1433 then return Entries(function(value, origin) return (value - origin) / ZONE.size end) end
    return {}
end }
TaxiNodePosition = function(slot)
    local node = nodes[slot]
    if world.scrambled then return (slot * 37 % 11) / 11, (slot * 53 % 7) / 7 end
    if world.secretNode == slot then return secret, secret end
    return TaxiX(node[1]) + (node.shift or 0), TaxiY(node[2])
end
C_Map = {
    GetBestMapForUnit = function() return world.player end,
    GetMapInfo = function(map)
        if map == 13 then return { mapType = 2, parentMapID = 947 } end
        if map == 1433 then return { mapType = 3, parentMapID = 13 } end
        if map == 1411 then return { mapType = 3, parentMapID = 12 } end
    end,
    GetWorldPosFromMapPos = function(map, position)
        if map == 13 then return 0, { x = position.x * 1000, y = position.y * 1000 } end
        if map == 1433 then
            return 0, { x = (ZONE.x + position.x * ZONE.size) * 1000, y = (ZONE.y + position.y * ZONE.size) * 1000 }
        end
        if map == 1411 then return 1, { x = position.x * 1000, y = position.y * 1000 } end
    end,
    GetMapPosFromWorldPos = function(instance, position, map)
        assert(instance == 0, "a position of another world was converted")
        if map == 13 then return map, { x = position.x / 1000, y = position.y / 1000 } end
        return map, { x = (position.x / 1000 - ZONE.x) / ZONE.size, y = (position.y / 1000 - ZONE.y) / ZONE.size }
    end,
    GetUserWaypoint = function()
        local pin = world.pin
        if pin == secret then return secret end
        return pin and { uiMapID = pin.map, position = { x = pin.x, y = pin.y } } or nil
    end,
}
C_SuperTrack = { GetSuperTrackedQuestID = function() return world.quest end }
C_QuestLog = { GetTitleForQuestID = function() return "Juice Delivery" end,
    GetQuestsOnMap = function(map)
        return map == 1433 and { { questID = 77, x = world.questX, y = world.questY } } or {}
    end }
GetQuestUiMapID = function(id) return id == 77 and 1433 or 0 end

local forbidden = {}
local NS = { Defaults = {}, Client = {}, Public = Public, Finite = Finite, PublicText = PublicText,
    Safety = { IsForbidden = function(frame) return forbidden[frame] == true end } }
local Suite = { Public = Public, Finite = Finite, PublicText = PublicText, Text = function(text) return text end,
    CreateFrame = function(_, _, parent) return Frame(parent) end, CreateTexture = function(parent) return Frame(parent) end,
    RGB = function(color) return color, color, color end, Print = function() end, Dispatch = function(fn, ...) return fn(...) end }
local private = { NS = NS, Suite = Suite }
assert(loadfile(base .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Navigation.lua"))("MSUF_Suite", NS)
local config = {}
for key, rule in pairs(NS.SuiteCatalog.navigation.rules) do config[key] = rule.default end
assert(config.flightMapPins == true, "the flight map markers are not a setting that starts switched on")
for _, file in ipairs({ "NavigationModel", "NavigationSources", "NavigationRoutes", "NavigationTaxi" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("MSUF_Suite_QualityOfLife", private)
end
local navigation = Suite.Navigation
local events, requests, deferred = {}, 0, nil
local owner = { config = config, model = {}, context = {} }
function owner.context:Event(event, fn, inCombat)
    assert(inCombat == true, event .. " is not followed in combat")
    events[event] = fn
end
function owner.context:Coalesce(delay, fn)
    assert(delay == 0)
    deferred = fn
    return { Request = function() requests = requests + 1 end }
end
local function Flush()
    if requests > 0 then requests = 0 deferred(owner) end
end
local function Open()
    events.TAXIMAP_OPENED(owner, "TAXIMAP_OPENED", 0)
    Flush()
end
local created = {}
do
    local create = Suite.CreateFrame
    Suite.CreateFrame = function(kind, name, parent)
        local frame = create(kind, name, parent)
        created[#created + 1] = frame
        return frame
    end
end
local function Marker(title)
    for _, frame in ipairs(created) do
        if frame.title == title and frame:IsShown() then return frame end
    end
end
local function Near(marker, x, y)
    local point = marker and marker.point
    return point and point[1] == "CENTER" and point[2] == TaxiRouteMap and point[3] == "BOTTOMLEFT"
        and math.abs(point[4] - x) < .001 and math.abs(point[5] - y) < .001
end
-- Pin: zone (.5, .5) = continent (.5, .6) = taxi (.5, .59), drawn from the bottom left.
local PIN_X, PIN_Y = TaxiX(.5) * 580, (1 - TaxiY(.6)) * 580
-- Quest: zone (.25, .75) = continent (.45, .65).
local QUEST_X, QUEST_Y = TaxiX(.45) * 580, (1 - TaxiY(.65)) * 580

navigation.EnableTaxi(owner)
assert(events.TAXIMAP_OPENED and events.TAXIMAP_CLOSED, "the flight map is not followed")
navigation.RefreshTaxi(owner)
assert(#created == 0 and counters.measured == 0, "a closed flight map was measured or drawn on")

-- The client lays the taxi frame out in the same event: nothing is read before the next frame.
events.TAXIMAP_OPENED(owner, "TAXIMAP_OPENED", 0)
assert(requests == 1 and #created == 0 and counters.measured == 0, "the flight map was read inside its opening event")
Flush()
local pin, quest = Marker("Map waypoint"), Marker("Juice Delivery")
assert(Near(pin, PIN_X, PIN_Y), "the map pin is not at its place on the flight map")
assert(Near(quest, QUEST_X, QUEST_Y), "the focused quest is not at its place on the flight map")
assert(counters.measured == 1, "one visit measured the flight map more than once")
for _, marker in ipairs({ pin, quest }) do
    assert(marker.parent == TaxiRouteMap and marker.level == TaxiRouteMap.level,
        "a marker is not under the flight points of the taxi map")
    assert(marker.mouse == true and marker.clicks == false, "a marker takes clicks meant for a flight point")
end
assert(pin.icon.color[1] == config.pinColor and quest.icon.color[1] == config.questColor,
    "the markers do not use the navigation colours")
quest.scripts.OnEnter(quest)
assert(GameTooltip.lines[1] == "Juice Delivery" and GameTooltip.lines[2] == "Focused quest" and GameTooltip.shown,
    "the quest marker does not say what it is")
quest.scripts.OnLeave(quest)
assert(not GameTooltip.shown, "leaving a marker kept its tooltip")
pin.scripts.OnEnter(pin)
assert(GameTooltip.lines[1] == "Map waypoint" and #GameTooltip.lines == 1, "the pin marker does not say what it is")
pin.scripts.OnLeave(pin)

-- A destination change while the map is open moves the markers without measuring again.
world.pin = { map = 13, x = .8, y = .4 }
owner.model = { source = "quest", identity = 77, color = "complete" }
config.shape = 2
navigation.RefreshTaxi(owner)
assert(Near(pin, TaxiX(.8) * 580, (1 - TaxiY(.4)) * 580) and counters.measured == 1,
    "a moved map pin stayed, or the flight map was measured again")
assert(quest.icon.color[1] == "complete", "the quest marker ignores the colour of the world marker")
assert(pin.icon.angle == 0 and quest.icon.texture == pin.icon.texture, "the markers ignore the waypoint shape")
config.shape = 1
navigation.RefreshTaxi(owner)
assert(math.abs(pin.icon.angle - math.pi / 4) < .0001, "the diamond shape is not drawn as one")

-- Places the taxi map does not show get no marker.
world.pin = { map = 1411, x = .5, y = .5 }
navigation.RefreshTaxi(owner)
assert(not pin:IsShown() and quest:IsShown(), "a pin on another continent was drawn on this flight map")
world.pin = { map = 13, x = -.2, y = .5 }
navigation.RefreshTaxi(owner)
assert(not pin:IsShown(), "a pin outside the flight map was drawn at its edge")
world.pin = nil
navigation.RefreshTaxi(owner)
assert(not pin:IsShown() and quest:IsShown(), "a removed map pin kept its marker")
world.pin, world.quest = secret, 0
navigation.RefreshTaxi(owner)
assert(not pin:IsShown() and not quest:IsShown(), "a restricted pin or no focused quest kept a marker")
world.pin, world.quest = { map = 1433, x = .5, y = .5 }, 77
world.questX = secret
navigation.RefreshTaxi(owner)
assert(pin:IsShown() and not quest:IsShown(), "a quest without a readable place kept its marker")
world.questX = .25

-- The setting.
config.flightMapPins = false
navigation.RefreshTaxi(owner)
assert(not pin:IsShown() and not quest:IsShown(), "the switched-off markers stayed on the flight map")
config.flightMapPins = true
navigation.RefreshTaxi(owner)
assert(Near(pin, PIN_X, PIN_Y) and Near(quest, QUEST_X, QUEST_Y) and pin:IsShown() and quest:IsShown(),
    "switching the markers back on did not draw them")

-- Closing ends the visit: no markers, and a later destination change reads nothing.
events.TAXIMAP_CLOSED(owner, "TAXIMAP_CLOSED")
assert(not pin:IsShown() and not quest:IsShown(), "a closed flight map kept its markers")
local measured = counters.measured
navigation.RefreshTaxi(owner)
assert(counters.measured == measured and not pin:IsShown(), "a closed flight map was measured")

-- The new flight map (FlightMapFrame) is another frame: the taxi map stays hidden and unread.
TaxiFrame.shown = false
Open()
assert(counters.measured == measured and not pin:IsShown(), "a hidden taxi map was measured or drawn on")
TaxiFrame.shown = true
forbidden[TaxiRouteMap] = true
Open()
assert(counters.measured == measured and not pin:IsShown(), "a forbidden taxi map was read")
forbidden[TaxiRouteMap] = nil

-- A flight point that cannot be read is left out; the others still give the scale.
world.secretNode = 2
Open()
assert(Near(pin, PIN_X, PIN_Y) and pin:IsShown(), "one unreadable flight point lost the whole map")
world.secretNode = nil

-- Where the continent has no flight points to measure, the player's own map does.
world.noContinentNodes = true
Open()
assert(Near(pin, PIN_X, PIN_Y) and Near(quest, QUEST_X, QUEST_Y) and pin:IsShown(),
    "the player's map did not stand in for the continent")
world.noContinentNodes = nil

-- A map whose flight points do not line up is not guessed at, and is asked once per visit.
world.scrambled = true
measured = counters.measured
Open()
assert(not pin:IsShown() and not quest:IsShown(), "a flight map that does not fit got a marker anyway")
local attempts = counters.measured - measured
navigation.RefreshTaxi(owner)
navigation.RefreshTaxi(owner)
assert(attempts > 0 and counters.measured - measured == attempts, "a map that cannot be measured was measured again")
world.scrambled = nil
world.noNodes = true
Open()
assert(not pin:IsShown(), "restricted flight points produced a marker")
world.noNodes = nil

-- Too few flight points to tell a scale, and a taxi frame without its size.
local saved = nodes
nodes = { saved[1] }
Open()
assert(not pin:IsShown(), "a single flight point was taken for a scale")
nodes = saved
TAXI_MAP_WIDTH = nil
Open()
assert(not pin:IsShown() and not quest:IsShown(), "markers were placed without the taxi map's size")
TAXI_MAP_WIDTH = 580

-- Disabling navigation takes the markers along.
Open()
assert(pin:IsShown() and quest:IsShown())
navigation.DisableTaxi(owner)
assert(not pin:IsShown() and not quest:IsShown(), "disabled navigation left its markers on the flight map")
navigation.RefreshTaxi(owner)
assert(not pin:IsShown(), "disabled navigation still follows the open flight map")
assert(#created == 2, "the markers are not reused: " .. #created)
print("PASS flight map markers: pin and focused quest at their measured place, hidden where the map cannot show them")
