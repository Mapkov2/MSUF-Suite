local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local private, modules, events = {}, {}, {}
local calls, textWrites, frameCreates, fontWrites = 0, 0, 0, 0
local gamepad, waypointWrites = false, 0
local deferred = {}
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }
local function Flush()
    local jobs = deferred
    deferred = {}
    for _, job in ipairs(jobs) do job() end
end
local secret = setmetatable({}, { __index = function() error("secret read") end })
local function Widget()
    frameCreates = frameCreates + 1
    local w = { shown = true }
    function w:SetPoint(...) self.point = { ... } end
    function w:SetAllPoints() end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetTextColor(...) self.color = { ... } end
    function w:SetText(text) self.text = text; textWrites = textWrites + 1 end
    function w:SetFormattedText(...) self:SetText(string.format(...)) end
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
    CreateTexture = Widget, SetFont = function() fontWrites = fontWrites + 1 end,
    GlobalFontPath = function() return "font" end, GamepadUI = function() return gamepad end,
    Install = function(id, module) modules[id] = module end }
function S.CreateFontString(parent)
    local label = Widget()
    label.owner = parent
    return label
end
function S.CreateFrame(_, _, parent, template)
    if parent == WorldMapFrame and template == nil then
        local holder = Widget()
        holder.parent = parent
        function holder:SetAllPoints(relative) self.relative = relative end
        function holder:SetFrameLevel(level)
            assert(S.Finite(level), "unreadable frame level passed to the renderer")
            self.level = level
        end
        return holder
    end
    Check(parent == nil and template == "MSUFSuiteForeverMapPinTemplate", "only unparented Suite marker frames are created")
    local pin = Widget()
    pin.shown = false
    pin.scripts = {}
    for name, method in pairs(MSUFSuiteForeverMapPinMixin) do pin[name] = method end
    function pin:SetScript(name, callback) self.scripts[name] = callback end
    function pin:GetParent() return self.parent end
    function pin:SetParent(frame) self.parent = frame end
    function pin:GetFrameLevel() return self.level end
    function pin:SetFrameLevel(level) self.level = level end
    function pin:SetScale(scale) self.scale = scale end
    function pin:GetCenter() return self.point[4] * self.scale, self.point[5] * self.scale end
    function pin:Show()
        self.shown = true
        table.insert(WorldMapFrame.activePins, self)
    end
    function pin:Hide()
        self.shown = false
        for i, frame in ipairs(WorldMapFrame.activePins) do
            if frame == self then table.remove(WorldMapFrame.activePins, i); return end
        end
    end
    return pin
end
S.Public = function(value) return value ~= secret end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
local mapLoaded, combat = true, false
local NS = { Client = { isForever = true, IsAddOnLoaded = function() return mapLoaded end }, InCombat = function() return combat end,
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

WorldMapFrame = Widget()
WorldMapFrame.id, WorldMapFrame.activePins = 1429, {}
local nativeName = Widget()
nativeName.text = "Elwynn"
WorldMapFrame.dataProviders = { [{ Label = { Name = nativeName } }] = true }
function WorldMapFrame:GetMapID() return self.id end
local canvas = { GetSize = function() return 1000, 800 end, GetLeft = function() return 0 end,
    GetTop = function() return 0 end }
local levels = { GetValidFrameLevel = function() return 25 end }
local cursorX, cursorY, nativeHover = 0, 0, nil
WorldMapFrame.ScrollContainer = { GetGamepadCursorPosition = function() return cursorX, cursorY end }
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetCanvasScale() return self.canvasScale or 1 end
function WorldMapFrame:GetCanvasZoomPercent() return self.zoom or 0 end
function WorldMapFrame:GetGlobalPinScale() return self.globalPinScale or 1 end
function WorldMapFrame:GetPinFrameLevelsManager() return levels end
function WorldMapFrame:GetHoveredPin() return nativeHover end
function WorldMapFrame:UpdateGamepadCursor() end
function WorldMapFrame:ClickHoveredPins() end
function WorldMapFrame:SetGlobalPinScale(value) self.globalPinScale = value end
function WorldMapFrame:OnCanvasSizeChanged() end
function WorldMapFrame:OnCanvasScaleChanged() end
function WorldMapFrame:OnMapChanged() end
function WorldMapFrame:RefreshAllDataProviders() end
function WorldMapFrame:AddDataProvider() error("Suite entered Blizzard's protected provider list") end
function WorldMapFrame:AcquirePin() error("Suite entered Blizzard's native pin pool") end
function WorldMapFrame:RemoveAllPinsByTemplate() error("Suite cleared Blizzard's native pin pool") end
local mapHooks = {}
function WorldMapFrame:HookScript(script, callback)
    Check(not mapHooks[script], "native map hooked twice")
    mapHooks[script] = callback
end
function WorldMapFrame:Show()
    self.shown = true
    self:RefreshAllDataProviders()
    mapHooks.OnShow(self)
end
function WorldMapFrame:Hide()
    self.shown = false
    mapHooks.OnHide(self)
end
local function Load(name) assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. name))("MSUF_Suite_QualityOfLife", private) end
Load("ForeverMapData.lua")
Load("ForeverMapPins.lua")
Load("ForeverMapLabels.lua")
Load("ForeverMapLocations.lua")
Load("ForeverMapLayer.lua")
Load("ForeverWorldMap.lua")
local module = assert(modules.foreverWorldMap)
module.active = true
local waiting = events
module.context = { Event = function(_, event, fn) waiting[event] = fn end,
    RemoveEvent = function(_, event) waiting[event] = nil end }
module.config = { zoneLevels = true, transports = true, flightPoints = true, dungeonEntrances = true,
    zoneRoutes = true, onlyOwnFaction = true, pinSize = 20 }
mapLoaded = false
module:Enable()
Check(not module.map and waiting.ADDON_LOADED, "map readiness waits for the native addon without forcing a load")
waiting.ADDON_LOADED(module, "ADDON_LOADED", "UnrelatedAddon")
Check(not module.map, "unrelated addon cannot attach the marker layer")
mapLoaded = true
waiting.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_WorldMap")
Check(not waiting.ADDON_LOADED, "map attachment releases the startup listener")
local nativeProviders = 0
for _ in pairs(WorldMapFrame.dataProviders) do nativeProviders = nativeProviders + 1 end
Check(nativeProviders == 1, "Suite registered a provider in Blizzard's native refresh loop")
Check(#deferred == 1 and #WorldMapFrame.activePins == 0, "marker paint waits until the native refresh returns")
Flush()
Check(#WorldMapFrame.activePins > 0, "activation refreshes an already open map")
Check(module.label:IsShown() and module.label.text == "Levels 1-10", "missing native ranges use known zone data")
Check(events.TAXI_NODE_STATUS_CHANGED and events.PLAYER_LEVEL_UP,
    "visible map owns its event registrations")
local count = #WorldMapFrame.activePins
local beforeFrames = frameCreates
local releasedPin = WorldMapFrame.activePins[1]
releasedPin:OnMouseEnter()
releasedPin:SetHighlightLocked(true)
WorldMapFrame:Hide()
Check(#WorldMapFrame.activePins == 0, "native blank-map lifecycle releases own pins")
Check(not releasedPin.highlight.shown and not GameTooltip.shown and not releasedPin.record,
    "pool reset clears the previous marker and its active hover state")
WorldMapFrame:Show()
Flush()
Check(#WorldMapFrame.activePins == count, "same-map refresh repopulates all pins after removal")
Check(frameCreates == beforeFrames, "same-map refresh reuses the Suite marker pool")
local function Refresh()
    module:Refresh()
    Flush()
end
local function HasPin(kind)
    for _, pin in ipairs(WorldMapFrame.activePins) do
        if pin.kind == kind then return true end
    end
    return false
end
for setting, kind in pairs({ flightPoints = 1, zoneRoutes = 6, dungeonEntrances = 7 }) do
    Check(HasPin(kind), setting .. " renders its markers on a supported map")
    module.config[setting] = false
    Refresh()
    Check(not HasPin(kind), setting .. " releases its markers when disabled")
    module.config[setting] = true
    Refresh()
    Check(HasPin(kind), setting .. " renders its markers again when re-enabled")
end
module.config.pinSize = 24
Refresh()
for _, pin in ipairs(WorldMapFrame.activePins) do
    Check(pin.width == 24 and pin.height == 24, "marker size applies to reused pins")
end
Check(frameCreates == beforeFrames, "changing settings reuses existing pin artwork")

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
Refresh()
Check(not module.label:IsShown(), "profile refresh can disable an unchanged zone label")
module.config.zoneLevels = true
local beforeFonts = fontWrites
Refresh()
Check(module.label:IsShown(), "profile refresh repaints unchanged text when enabled again")
Check(fontWrites > beforeFonts, "global-font refresh restyles a label with unchanged native identity")

WorldMapFrame.id = 1415
module.config.onlyOwnFaction = false
Refresh()
for _, pin in ipairs(WorldMapFrame.activePins) do
    Check(pin.kind ~= 1 and pin.kind ~= 6, "continent view omits dense flight and road markers")
    Check(pin.x >= 0 and pin.x <= 1 and pin.y >= 0 and pin.y <= 1, "projected pins remain inside the map")
end
Check(HasPin(7), "dungeon approaches remain visible on continents")
Check(HasPin(2) and HasPin(3) and HasPin(4), "boats, zeppelins and skycutters render on continents")
module.config.transports = false
Refresh()
Check(not HasPin(2) and not HasPin(3) and not HasPin(4) and HasPin(7),
    "disabling transports leaves dungeon approaches visible")
module.config.transports = true
Refresh()
Check(HasPin(2) and HasPin(3) and HasPin(4), "re-enabling transports restores all three kinds")
local pin = WorldMapFrame.activePins[1]
Check(pin.parent == canvas and pin.level == 25, "markers use the native canvas coordinates and flight-pin level")
local x, y = pin:GetCenter()
WorldMapFrame.zoom, WorldMapFrame.canvasScale = 1, 1.5
WorldMapFrame:OnCanvasScaleChanged()
local zoomX, zoomY = pin:GetCenter()
Check(math.abs(zoomX - x) < .001 and math.abs(zoomY - y) < .001 and pin.scale == 1 / 1.5,
    "zoom changes marker scale without moving its normalized point")
pin.scripts.OnEnter(pin)
Check(GameTooltip.shown and GameTooltip.text == pin.title and pin.highlight.shown, "mouse entry shows the marker tooltip")
pin.scripts.OnMouseUp(pin, "LeftButton", true)
Check(waypoint and tracked and waypoint[1] == pin.record[1], "manual pin action uses original zone coordinates")
pin.scripts.OnLeave(pin)
Check(not GameTooltip.shown, "leaving owns only its own tooltip")
local nextPin = WorldMapFrame.activePins[2]
gamepad = true
cursorX, cursorY = nextPin:GetCenter()
WorldMapFrame:UpdateGamepadCursor()
local selected = GameTooltip.owner
Check(selected and selected.highlight.shown and selected.kind, "native pad cursor highlights a Suite marker")
local beforeWaypoints = waypointWrites
WorldMapFrame:ClickHoveredPins()
Check(waypointWrites == beforeWaypoints + 1 and waypoint[1] == selected.record[1]
    and waypoint[2] == selected.record[2], "one native pad press activates only the visible pin tooltip")
nativeHover = {}
WorldMapFrame:UpdateGamepadCursor()
WorldMapFrame:ClickHoveredPins()
Check(not selected.highlight.shown and waypointWrites == beforeWaypoints + 1, "native map pins retain gamepad priority")
nativeHover = nil
gamepad = false

WorldMapFrame:Hide()
beforeCalls = calls
Refresh()
Check(calls == beforeCalls + 1, "hidden map does not rebuild or query map data")
Check(not events.TAXI_NODE_STATUS_CHANGED and not events.PLAYER_LEVEL_UP, "hidden map unregisters its events")
WorldMapFrame.id = 1429
module.config.onlyOwnFaction = true
combat = true
WorldMapFrame:Show()
WorldMapFrame:OnMapChanged()
Check(#deferred == 1, "map open and native refresh coalesce into one Suite pass")
Flush()
Check(#WorldMapFrame.activePins > 0, "combat map open paints its markers outside the native refresh")
local combatPin = WorldMapFrame.activePins[1]
combatPin.scripts.OnMouseUp(combatPin, "LeftButton", true)
Check(waypointWrites == beforeWaypoints + 1, "opening the map in combat does not allow a Suite waypoint write")
combat = false
nativeFlights = true
Refresh()
for _, p in ipairs(WorldMapFrame.activePins) do Check(p.kind ~= 1, "native flight markers are not duplicated") end
WorldMapFrame.id = 1413
Refresh()
Check(not HasPin(1), "faction filtering hides opposite-faction flight points")
module.config.onlyOwnFaction = false
Refresh()
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
Refresh()
local found = false
for _, p in ipairs(WorldMapFrame.activePins) do
    Check(p.kind ~= 7, "native entrances replace approximate dungeon approaches")
    found = found or p.kind == 8
end
Check(found, "exact native entrance is shown when Blizzard's filter is off")
filter = true
events.CVAR_UPDATE(module, "CVAR_UPDATE", "showDungeonEntrancesOnMap")
Flush()
for _, p in ipairs(WorldMapFrame.activePins) do Check(p.kind ~= 7 and p.kind ~= 8, "native visible entrances are not duplicated") end
module.active = false
module:Disable()
Check(#WorldMapFrame.activePins == 0 and not module.label.shown, "disable removes only own pins and label")
beforeCalls = calls
nativeName:SetText("Elwynn")
Check(calls == beforeCalls, "disabled permanent label observer is dormant")
module.active = true
module:Enable()
Flush()
Check(module.map == WorldMapFrame and #WorldMapFrame.activePins > 0, "re-enable repaints the marker layer")

do
    local Strict = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
    local public = S.Public
    S.Public = function(value) return not Strict.IsSecret(value) and public(value) end
    local guidCalls, inside = 0, false
    local guids = { nameplate2 = "Creature-0-9001-0-6783-42-0000000011" }
    function UnitGUID(unit)
        assert(not Strict.IsSecret(unit), "unreadable token passed to UnitGUID")
        guidCalls = guidCalls + 1
        return guids[unit]
    end
    function IsInInstance() return inside end
    local forbiddenPlate = { GetUnit = function() error("read a forbidden plate") end }
    local readablePlate = { GetUnit = function() return "nameplate2" end }
    C_NamePlate = { GetNamePlates = function() return { forbiddenPlate, readablePlate } end }
    NS.Safety.IsForbidden = function(frame) return frame == forbiddenPlate end
    local coordLevel = 36
    local coords = { PlayerCoords = { GetFrameLevel = function() return coordLevel end }, CursorCoords = {} }
    WorldMapFrame.overlayFrames = { {}, coords }
    Check(not module.layerLabel and not events.NAME_PLATE_UNIT_ADDED and guidCalls == 0,
        "existing profiles leave layer detection asleep")

    module.config.layerID = true
    module:Refresh()
    local layer = assert(module.layerLabel, "enabling the option creates a Suite-owned readout")
    local holder = layer.owner
    Check(holder.parent == WorldMapFrame and holder.level > coordLevel,
        "the layer label renders above the map artwork at the native coordinate row level")
    Check(layer.shown and layer.text == "Observed layer ID: 6783" and layer.point[2] == holder
        and holder.relative == coords, "uses the fifth GUID field and follows the native coordinate panel")
    Check(#WorldMapFrame.overlayFrames == 2 and next(coords.CursorCoords) == nil,
        "the layer label stays out of the native coordinate layout")

    local function Fire(event, ...)
        assert(events[event], event)(module, event, ...)
    end
    local previousWrites = textWrites
    Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    Check(textWrites == previousWrites, "identical samples skip text writes")
    guids.target = "Vehicle-0-9001-0-18432-42-0000000022"
    Fire("PLAYER_TARGET_CHANGED")
    Check(layer.text == "Observed layer ID: 18432", "vehicle observations can update the raw ID")
    guids.target = "Player-9001-00000101"
    Fire("PLAYER_TARGET_CHANGED")
    guids.target = "Creature-0-9001-0-0-42-0000000011"
    Fire("PLAYER_TARGET_CHANGED")
    Check(layer.text == "Observed layer ID: 18432", "player GUIDs and zero IDs are ignored")

    Fire("ZONE_CHANGED_NEW_AREA")
    Check(layer.text == "Observed layer ID: unknown", "zone change clears the old sample immediately")
    guids.nameplate2 = "Creature-0-9001-0-27-42-0000000022"
    Flush()
    Check(layer.text == "Observed layer ID: 27", "open map reseeds after the zone settles")
    Fire("ZONE_CHANGED_NEW_AREA")
    Fire("SHARD_TRANSFER")
    Flush()
    Check(layer.text == "Observed layer ID: unknown", "shard transfer cancels a pending sample from the old world")

    Strict.Install()
    local stop = Strict.Watch(root .. "/MSUF_Suite_QualityOfLife/ForeverMapLayer.lua", { strict = true })
    guids.target = Strict.New("string")
    Fire("PLAYER_TARGET_CHANGED")
    local previousReads = guidCalls
    Fire("NAME_PLATE_UNIT_ADDED", Strict.New("string"))
    local violations = stop()
    Check(#violations == 0 and guidCalls == previousReads and layer.text == "Observed layer ID: unknown",
        "secret unit tokens and GUIDs are ignored before inspection: " .. table.concat(violations, " | "))

    Fire("PLAYER_LEAVING_WORLD")
    Check(not layer.shown and not events.NAME_PLATE_UNIT_ADDED, "world transition suspends observation")
    inside = true
    Fire("PLAYER_ENTERING_WORLD")
    Flush()
    Check(not layer.shown and not events.PLAYER_TARGET_CHANGED, "instances do not sample or display layer IDs")
    inside = false
    Fire("PLAYER_ENTERING_WORLD")
    Flush()
    Check(layer.shown and layer.text == "Observed layer ID: 27", "return to the open world reseeds visible samples")
    Fire("ZONE_CHANGED_NEW_AREA")
    WorldMapFrame:Hide()
    previousReads = guidCalls
    Flush()
    Check(not layer.shown and not events.SHARD_TRANSFER and guidCalls == previousReads,
        "closing the map removes events and cancels pending native reads")
    WorldMapFrame:Show()
    Check(layer.shown and layer.text == "Observed layer ID: 27", "reopening samples fresh evidence")
    module.config.layerID = false
    module:Refresh()
    Check(not layer.shown and not events.SHARD_TRANSFER and not events.NAME_PLATE_UNIT_ADDED,
        "turning off the setting removes the display and its subscriptions")
    coordLevel = Strict.New("number")
    local fresh = { map = WorldMapFrame, config = { layerID = true }, context = module.context }
    stop = Strict.Watch(root .. "/MSUF_Suite_QualityOfLife/ForeverMapLayer.lua", { strict = true })
    private.ForeverMapLayer.Sync(fresh)
    violations = stop()
    Check(#violations == 0 and not fresh.layerLabel and not events.SHARD_TRANSFER,
        "a secret frame level cannot reach the owned renderer: " .. table.concat(violations, " | "))
end

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
    and not xml:find("<OnLoad", 1, true), "the Suite owns script installation and creation lifecycle")
Check(xml:find('passThroughButtons="RightButton"', 1, true), "right clicks pass through to the map")
print(string.format("Forever world-map contract: %d checks; %d locations; warm label %d VM, %.3f KB/1000",
    checks, #private.ForeverMapData.pins, instructions, allocation))
