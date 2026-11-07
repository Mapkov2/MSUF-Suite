local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local private, modules, events = {}, {}, {}
local calls, textWrites, frameCreates, fontWrites = 0, 0, 0, 0
local gamepad, waypointWrites = false, 0
local secret = setmetatable({}, { __index = function() error("secret read") end })
local function Widget()
    frameCreates = frameCreates + 1
    local w = { shown = true }
    function w:SetPoint(...) self.point = { ... } end
    function w:SetAllPoints() end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetTextColor(...) self.color = { ... } end
    function w:SetText(text) self.text = text; textWrites = textWrites + 1 end
    function w:GetText() return self.text end
    function w:SetSize(x, y) self.width, self.height = x, y end
    function w:SetTexture(texture) self.texture = texture end
    function w:SetAtlas(atlas) self.atlas = atlas end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(shown) self.shown = shown end
    function w:IsShown() calls = calls + 1; return self.shown end
    return w
end
local S = { Text = function(text) return text end,
    CreateTexture = Widget, CreateFontString = Widget, SetFont = function() fontWrites = fontWrites + 1 end,
    GlobalFontPath = function() return "font" end, GamepadUI = function() return gamepad end,
    Install = function(id, module) modules[id] = module end }
S.Public = function(value) return value ~= secret end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
local mapLoaded = true
local NS = { Client = { isForever = true, IsAddOnLoaded = function() return mapLoaded end }, InCombat = function() return false end,
    Safety = { IsForbidden = function() return false end } }
private.NS, private.Suite = NS, S
canaccesstable = function(value) return value ~= secret end
wipe = function(value) for key in pairs(value) do value[key] = nil end return value end
Enum = { UIMapType = { World = 1, Continent = 2, Zone = 3 } }
CreateFromMixins = function(...)
    local out = {}
    for i = 1, select("#", ...) do for k, v in pairs(select(i, ...)) do out[k] = v end end
    return out
end
hooksecurefunc = function(region, method, fn)
    assert(region ~= GameTooltip, "shared tooltip method hook")
    local old = region[method]
    region[method] = function(self, ...) old(self, ...); fn(self, ...) end
end
local exact, nativeFlights, filter, waypoint, tracked = {}, false, false, nil, false
C_Map = {
    GetMapInfo = function(id)
        calls = calls + 1
        local west = id >= 1438 and id <= 1452 or id >= 1411 and id <= 1413 or id == 1454 or id == 1456 or id == 1457
        return { name = "Zone" .. id, mapID = id, mapType = id == 1415 and 2 or 3,
            parentMapID = west and 1414 or id == 2521 and 947 or 1415 }
    end,
    GetAreaInfo = function(id) calls = calls + 1; return "Area" .. id end,
    GetMapRectOnMap = function(_, shown)
        calls = calls + 1
        if shown == 1415 or shown == 1414 then return 0, 1, 0, 1 end
    end,
    GetMapChildrenInfo = function()
        calls = calls + 1
        return { { name = "Elwynn", mapID = 1429 }, { name = "Zephras Isle", mapID = 2521 } }
    end,
    GetMapLevels = function() calls = calls + 1; return 0, 0 end,
    GetMapInfoAtPosition = function(continent)
        calls = calls + 1
        return { mapID = continent == 1414 and 1413 or 1429, mapType = 3 }
    end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(point) waypoint = point; waypointWrites = waypointWrites + 1; return true end,
}
UiMapPoint = { CreateFromCoordinates = function(...) return { ... } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(value) tracked = value end }
C_EncounterJournal = { GetDungeonEntrancesForMap = function() calls = calls + 1; return exact end }
C_TaxiMap = { ShouldMapShowTaxiNodes = function() calls = calls + 1; return nativeFlights end }
C_Texture = { GetAtlasInfo = function() return true end }
GetCVarBool = function() return filter end
UnitFactionGroup = function() return "Alliance" end
UnitLevel = function() calls = calls + 1; return 7 end
GetQuestDifficultyColor = function() return { r = 1, g = 1, b = 0 } end
GameTooltip = { shown = false }
function GameTooltip:IsOwned(pin) return self.owner == pin end
function GameTooltip:SetOwner(pin) self.owner = pin end
function GameTooltip:SetText(text) self.text = text end
function GameTooltip:AddLine() end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end
function GameTooltip:IsShown() return self.shown end

MapCanvasDataProviderMixin = {
    OnAdded = function(self, map) self.map = map end,
    OnRemoved = function(self) self.map = nil end,
    GetMap = function(self) return self.map end,
    RegisterEvent = function(self, event) events[event] = self end,
    UnregisterEvent = function(_, event) events[event] = nil end,
}
MapCanvasPinMixin = {
    ClearNudgeSettings = function() end, SetScalingLimits = function() end,
    UseFrameLevelType = function() end, OnReleased = function(self) self.released = true end,
    SetPosition = function(self, x, y) self.x, self.y = x, y end,
    GetMap = function(self) return self.map end,
}
WorldMapFrame = Widget()
WorldMapFrame.id, WorldMapFrame.activePins, WorldMapFrame.pool = 1429, {}, {}
local nativeName = Widget()
nativeName.text = "Elwynn"
WorldMapFrame.dataProviders = { [{ Label = { Name = nativeName } }] = true }
function WorldMapFrame:GetMapID() return self.id end
-- The stick is stationary when the button is pressed. The native movement
-- predicate is false even though the gamepad interface remains active.
function WorldMapFrame:HasGamepadCursorInput() return false end
function WorldMapFrame:AddDataProvider(provider) self.dataProviders[provider] = true; provider:OnAdded(self) end
function WorldMapFrame:RemoveDataProvider(provider)
    provider:RemoveAllData(); self.dataProviders[provider] = nil; provider:OnRemoved(self)
end
function WorldMapFrame:RemoveAllPinsByTemplate()
    for i = #self.activePins, 1, -1 do
        local pin = self.activePins[i]
        pin:OnReleased()
        self.pool[#self.pool + 1] = pin
        self.activePins[i] = nil
    end
end
function WorldMapFrame:AcquirePin(template, ...)
    Check(template == "MSUFSuiteForeverMapPinTemplate", "only own pin template is acquired")
    local pin = table.remove(self.pool)
    if not pin then
        pin = Widget()
        for k, v in pairs(MSUFSuiteForeverMapPinMixin) do pin[k] = v end
        pin:OnLoad()
    end
    pin.map = self
    pin:OnAcquired(...)
    self.activePins[#self.activePins + 1] = pin
    return pin
end
local function Load(name) assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. name))("MSUF_Suite_QualityOfLife", private) end
Load("ForeverMapData.lua")
Load("ForeverMapPins.lua")
Load("ForeverMapLabels.lua")
Load("ForeverMapLocations.lua")
Load("ForeverWorldMap.lua")
local module = assert(modules.foreverWorldMap)
module.active = true
local waiting = {}
module.context = { Event = function(_, event, fn) waiting[event] = fn end,
    RemoveEvent = function(_, event) waiting[event] = nil end }
module.config = { zoneLevels = true, transports = true, flightPoints = true, dungeonEntrances = true,
    zoneRoutes = true, onlyOwnFaction = true, pinSize = 20 }
mapLoaded = false
module:Enable()
Check(not module.map and waiting.ADDON_LOADED, "map readiness waits for the native addon without forcing a load")
waiting.ADDON_LOADED(module, "ADDON_LOADED", "UnrelatedAddon")
Check(not module.map, "unrelated addon cannot attach the provider")
mapLoaded = true
waiting.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_WorldMap")
Check(not waiting.ADDON_LOADED, "map attachment releases the startup listener")
Check(#WorldMapFrame.activePins > 0, "activation refreshes an already open map")
Check(module.label:IsShown() and module.label.text == "Levels 1-10", "missing native ranges use known zone data")
Check(events.TAXI_NODE_STATUS_CHANGED == module.provider and events.PLAYER_LEVEL_UP == module.provider,
    "visible map owns its event registrations")
local count = #WorldMapFrame.activePins
local beforeFrames = frameCreates
module.provider:RemoveAllData()
Check(#WorldMapFrame.activePins == 0, "native blank-map lifecycle releases own pins")
module.provider:RefreshAllData()
Check(#WorldMapFrame.activePins == count, "same-map refresh repopulates all pins after removal")
Check(frameCreates == beforeFrames, "same-map refresh reuses the native pin pool")

-- A repeated native area-label update does no map lookup, native read,
-- string normalization, allocation or own region write.
local beforeCalls, beforeText = calls, textWrites
for _ = 1, 1000 do nativeName:SetText("Elwynn") end
Check(calls == beforeCalls and textWrites == beforeText + 1000, "unchanged native label has no own native work")
local function Allocation()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do nativeName:SetText("Elwynn") end
    local delta = collectgarbage("count") - before
    collectgarbage("restart")
    return delta
end
local allocation = math.min(Allocation(), Allocation())
Check(allocation < 1, "unchanged area label does not allocate")
local instructions = 0
debug.sethook(function() instructions = instructions + 1 end, "", 1)
nativeName:SetText("Elwynn")
debug.sethook()
Check(instructions < 80, "unchanged native label instruction budget")
nativeName:SetText("Zephras Isle")
Check(module.label:IsShown() and module.label.text == "Levels 1-12", "Forever starting zone uses its documented range")
nativeName:SetText("Elwynn (1-10)")
Check(not module.label:IsShown(), "native zone ranges are not duplicated")
nativeName:SetText(secret)
Check(module.labelRaw ~= secret, "secret label never reaches a cache or string operation")
nativeName:SetText("Unknown Zone")
Check(not module.label:IsShown(), "unknown zone range is not invented")
nativeName:SetText("Elwynn")
module.config.zoneLevels = false
module:Refresh()
Check(not module.label:IsShown(), "profile refresh can disable an unchanged zone label")
module.config.zoneLevels = true
local beforeFonts = fontWrites
module:Refresh()
Check(module.label:IsShown(), "profile refresh repaints unchanged text when enabled again")
Check(fontWrites > beforeFonts, "global-font refresh restyles a label with unchanged native identity")

WorldMapFrame.id = 1415
module:Refresh()
for _, pin in ipairs(WorldMapFrame.activePins) do
    Check(pin.kind ~= 1 and pin.kind ~= 6, "continent view omits dense flight and road markers")
    Check(pin.x >= 0 and pin.x <= 1 and pin.y >= 0 and pin.y <= 1, "projected pins remain inside the map")
end
Check(#WorldMapFrame.activePins > 0, "transport and dungeon markers remain on continents")
local pin = WorldMapFrame.activePins[1]
pin:OnMouseEnter()
Check(GameTooltip.shown and GameTooltip.text == pin.title, "mouse and native gamepad entry share the tooltip")
pin:SetHighlightLocked(true)
Check(pin.highlight.shown, "gamepad pin highlighting uses own artwork")
pin:OnMouseClickAction("LeftButton")
Check(waypoint and tracked and waypoint[1] == pin.record[1], "manual pin action uses original zone coordinates")
pin:OnMouseLeave()
Check(not GameTooltip.shown, "leaving owns only its own tooltip")
local nextPin = WorldMapFrame.activePins[2]
gamepad = true
pin:OnMouseEnter()
nextPin:OnMouseEnter()
local beforeWaypoints = waypointWrites
pin:OnMouseClickAction("LeftButton")
nextPin:OnMouseClickAction("LeftButton")
Check(waypointWrites == beforeWaypoints + 1 and waypoint[1] == nextPin.record[1]
    and waypoint[2] == nextPin.record[2], "one native pad press activates only the visible pin tooltip")
gamepad = false

WorldMapFrame.shown = false
module.provider:OnHide()
beforeCalls = calls
module.provider:RefreshAllData()
Check(calls == beforeCalls + 1, "hidden map does not rebuild or query map data")
Check(not events.TAXI_NODE_STATUS_CHANGED and not events.PLAYER_LEVEL_UP, "hidden map unregisters its events")
WorldMapFrame.shown = true
WorldMapFrame.id = 1429
module.provider:RefreshAllData()
module.provider:OnShow()
nativeFlights = true
module:Refresh()
for _, p in ipairs(WorldMapFrame.activePins) do Check(p.kind ~= 1, "native flight markers are not duplicated") end
WorldMapFrame.id = 1413
module.config.onlyOwnFaction = false
module:Refresh()
local oppositeFlight = false
for _, p in ipairs(WorldMapFrame.activePins) do
    if p.kind == 1 then
        Check(p.record[6] == 2, "native own-faction flights remain deduplicated")
        oppositeFlight = true
    end
end
Check(oppositeFlight, "opposite-faction flight points are available when requested")
WorldMapFrame.id = 1429
module.config.onlyOwnFaction = true
exact = { { name = "Native entrance", position = { GetXY = function() return .4, .6 end } } }
module:Refresh()
local found = false
for _, p in ipairs(WorldMapFrame.activePins) do
    Check(p.kind ~= 7, "native entrances replace approximate dungeon approaches")
    found = found or p.kind == 8
end
Check(found, "exact native entrance is shown when Blizzard's filter is off")
filter = true
module.provider:OnEvent("CVAR_UPDATE", "showDungeonEntrancesOnMap")
for _, p in ipairs(WorldMapFrame.activePins) do Check(p.kind ~= 7 and p.kind ~= 8, "native visible entrances are not duplicated") end
module.active = false
module:Disable()
Check(#WorldMapFrame.activePins == 0 and not module.label.shown, "disable removes only own pins and label")
beforeCalls = calls
nativeName:SetText("Elwynn")
Check(calls == beforeCalls, "disabled permanent label observer is dormant")
module.active = true
module:Enable()
Check(module.map == WorldMapFrame, "re-enable reattaches the provider")

-- Continent masks, not overlapping zone rectangles, decide road/transport
-- membership. Multiple routes at one physical signpost share one native pin.
local originalMask = C_Map.GetMapInfoAtPosition
C_Map.GetMapInfoAtPosition = function(_, x) return { mapID = x < .5 and 1413 or 1440, mapType = 3 } end
local resolved = private.ForeverMapLocations.Build({
    { 1411, .2, .2, 6, 0, 3, 0, 1442 }, { 1411, .2001, .2001, 6, 0, 3, 0, 1441 },
    { 1411, .2, .5, 2, 0, 3, 0, 1422, 99 }, { 1411, .8, .5, 2, 0, 3, 0, 1422, 99 },
})
Check(#resolved == 3 and resolved[1][1] == 1413 and #resolved[1].destinations == 2,
    "native membership corrects overlapping Durotar bounds and aggregates a shared signpost")
Check(resolved[2].destinations[1] == 1440 and resolved[3].destinations[1] == 1413,
    "transport destinations follow resolved stops rather than guessed neighboring zones")
C_Map.GetMapInfoAtPosition = originalMask

-- Actual compiled game data, not a handful of fixture-only records.
local kinds = {}
for _, record in ipairs(private.ForeverMapData.pins) do
    Check(record[2] >= 0 and record[2] <= 1 and record[3] >= 0 and record[3] <= 1, "compiled coordinates are normalized")
    kinds[record[4]] = (kinds[record[4]] or 0) + 1
    if record[7] == 25 or record[7] == 80 then Check(record[1] == 1413, "Crossroads and Ratchet belong to the Barrens") end
end
Check(kinds[1] >= 60 and kinds[2] >= 10 and kinds[3] >= 4 and kinds[4] >= 2 and kinds[6] >= 20 and kinds[7] >= 20,
    "compiled data covers flights, ships, zeppelins, skycutters, roads and dungeon approaches")
local file = assert(io.open(root .. "/MSUF_Suite_QualityOfLife/ForeverMapPins.xml", "rb"))
local xml = file:read("*a"); file:close()
Check(xml:find('enableMouseMotion="true"', 1, true) and xml:find('enableMouseClicks="true"', 1, true)
    and not xml:find("<OnLoad", 1, true), "native AcquirePin owns script installation and creation lifecycle")
print(string.format("Forever world-map contract: %d checks; %d locations; warm label %d VM, %.3f KB/1000",
    checks, #private.ForeverMapData.pins, instructions, allocation))
