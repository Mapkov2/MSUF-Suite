local root = assert(arg[1])
local base = arg[2] or root
local private, modules, events, points = {}, {}, {}, {}
local secret, combat = {}, false
local counters = { writes = 0, distance = 0 }
local world = { kind = 2, distance = 400, valid = true, clamped = false, speed = 7, x = .3, y = .4, map = 84 }
local function Public(value) return value ~= secret end
local function Finite(value) return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge end
local function PublicText(value) return Public(value) and type(value) == "string" and value or nil end
local methods = {}
local function Frame(parent)
    return setmetatable({ shown = true, parent = parent, alpha = 1, scale = 1, scripts = {}, width = 100, height = 100 }, { __index = methods })
end
function methods:SetScript(key, fn) self.scripts[key] = fn end
function methods:CreateTexture() return Frame(self) end
function methods:CreateFontString() return Frame(self) end
function methods:SetShown(value) self.shown = value counters.writes = counters.writes + 1 end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:IsProtected() return false end
function methods:SetParent(parent) self.parent = parent end
function methods:GetParent() return self.parent end
function methods:SetPoint(...) self.point = { ... } counters.writes = counters.writes + 1 end
function methods:ClearAllPoints() counters.writes = counters.writes + 1 end
function methods:SetAllPoints() end
function methods:SetSize(width, height) self.width, self.height = width, height counters.writes = counters.writes + 1 end
function methods:SetWidth(width) self.width = width counters.writes = counters.writes + 1 end
function methods:GetWidth() return self.width end
function methods:GetFrameLevel() return 1 end
function methods:SetFrameLevel() end
function methods:RegisterForClicks() end
function methods:HookScript(script, callback) self.scripts[script] = callback end
function methods:GetHeight() return self.height end
function methods:GetSize() return self.width, self.height end
function methods:GetCenter() return self == SuperTrackedFrame and 1400 or 500, 300 end
function methods:GetEffectiveScale() return 1 end
function methods:SetAlpha(alpha) self.alpha = alpha counters.writes = counters.writes + 1 end
function methods:GetAlpha() return self.alpha end
function methods:SetScale(scale) self.scale = scale counters.writes = counters.writes + 1 end
function methods:SetRotation(angle) self.angle = angle counters.writes = counters.writes + 1 end
function methods:GetRotation() return self.angle or 0 end
function methods:SetText(text) assert(Public(text)) self.text = text counters.writes = counters.writes + 1 end
function methods:SetVertexColor() counters.writes = counters.writes + 1 end
function methods:SetColorTexture() counters.writes = counters.writes + 1 end
function methods:SetGradient() counters.writes = counters.writes + 1 end
function methods:SetTexture() counters.writes = counters.writes + 1 end
function methods:SetAtlas() counters.writes = counters.writes + 1 end
function methods:EnableMouse(on) self.mouse = on end
function methods:SetFrameStrata() end
function methods:IsMouseOver() return false end
function methods:SetJustifyH() end
function methods:SetWordWrap() end
function methods:SetTextColor() counters.writes = counters.writes + 1 end
UIParent, WorldFrame = Frame(), Frame()
SuperTrackedFrame = Frame(UIParent)
for _, key in ipairs({ "Icon", "Arrow", "DistanceText", "IconBorder" }) do SuperTrackedFrame[key] = Frame(SuperTrackedFrame) end
Enum = { SuperTrackingType = { Quest = 1, UserWaypoint = 2, MapPin = 3, Content = 4, Vignette = 5, Corpse = 6 },
    NavigationState = { Invalid = 0, Occluded = 1, InRange = 2, Disabled = 3 } }
CreateColor = function(...) return ... end
hooksecurefunc = function() end
GetTime = function() return 100 end
GetUnitSpeed = function() return world.speed end
PlaySound, PlaySoundFile = function() end, function() end
SOUNDKIT = { MAP_PING = 1 }
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
C_Map = {
    GetUserWaypoint = function()
        if world.noPin then return nil end
        return { uiMapID = world.map, position = { x = world.x, y = world.y } }
    end,
    GetBestMapForUnit = function() return world.map end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(point) world.map, world.x, world.y = point.map, point.x, point.y return true end,
}
C_SuperTrack = {
    GetHighestPrioritySuperTrackingType = function() return world.kind end,
    SetSuperTrackedUserWaypoint = function(on) world.kind = on and 2 or nil end,
    ClearAllSuperTracked = function() world.kind = nil end,
    GetSuperTrackedQuestID = function() return 100 end,
    GetSuperTrackedItemName = function() return "Place", "Description" end,
    GetSuperTrackedMapPin = function() return 1, 200 end,
    GetSuperTrackedContent = function() return 1, 300 end,
    GetSuperTrackedVignette = function() return "vignette" end,
}
C_Navigation = { GetFrame = function() return world.valid and SuperTrackedFrame end,
    HasValidScreenPosition = function() return world.valid end,
    GetDistance = function() counters.distance = counters.distance + 1 return world.distance end,
    WasClampedToScreen = function() return world.clamped end,
    GetTargetState = function() return Enum.NavigationState.InRange end }
C_QuestLog = { GetTitleForQuestID = function() return "Quest" end, IsComplete = function() return false end,
    GetLogIndexForQuestID = function() return 0 end }
C_AddOns = { LoadAddOn = function() return true end }
local NS = { Defaults = {}, Client = {}, Public = Public, Finite = Finite, PublicText = PublicText,
    IsCombatLocked = function() return combat end, InCombat = function() return combat end,
    Safety = { IsForbidden = function() return false end } }
NS.Finish = function(fn, ...) return true, fn(...) end
local Suite = { Public = Public, Finite = Finite, PublicText = PublicText, Text = function(text) return text end,
    Install = function(id, module) modules[id] = module end, CreateFrame = function(_, _, parent) return Frame(parent) end,
    CreateTexture = function(parent) return Frame(parent) end, RGB = function() return .5, .7, .9 end,
    ResolveFont = function() return nil end, GlobalFontPath = function() return "font" end,
    SetStyledFont = function() counters.writes = counters.writes + 1 end,
    PlaceEdges = function() counters.writes = counters.writes + 1 end,
    Print = function() end, Dispatch = function(fn, ...) return fn(...) end,
    RegisterSlash = function() end, UnregisterSlash = function() end,
    WaypointPoints = function() return points end, ToolListWindow = { Refresh = function() end } }
private.NS, private.Suite = NS, Suite
assert(loadfile(base .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Navigation.lua"))("MSUF_Suite", NS)
local config = {}
for key, rule in pairs(NS.SuiteCatalog.navigation.rules) do config[key] = rule.default end
for _, file in ipairs({ "NavigationModel", "NavigationVisuals", "NavigationSources", "NavigationTargets", "Navigation" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("MSUF_Suite_QualityOfLife", private)
end
local navigation, module = Suite.Navigation, modules.navigation
navigation.RefreshMap, navigation.RefreshMapInput = function() end, function() end
navigation.EnableMap, navigation.DisableMap = function() end, function() end
navigation.RefreshGuides, navigation.DisableGuides = function() end, function() end
local properties = {}
local context = {}
function context:Property(region, getter, setter, value)
    if combat then return end
    properties[region] = properties[region] or region[getter](region)
    region[setter](region, value)
end
function context:RestoreProperty(region, setter)
    if properties[region] and region:GetAlpha() == 0 then region[setter](region, properties[region]) end
    properties[region] = nil
end
function context:Event(event, fn) events[event] = fn end
function context:Coalesce(_, fn) return { Request = function() fn(module) end } end
function context:After(_, fn) self.pending = fn end
module.config, module.context, module.active = config, context, true
module:Enable()
assert(module.view.root:IsShown() and SuperTrackedFrame.Icon:GetAlpha() == 0)
local before, nativeDistanceReads = counters.writes, counters.distance
collectgarbage("collect")
collectgarbage("stop")
local memory = collectgarbage("count")
local instructions = 0
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for _ = 1, 1000 do module.driver.scripts.OnUpdate(module.driver, .1) end
debug.sethook()
local allocated = collectgarbage("count") - memory
collectgarbage("restart")
assert(counters.writes == before, "unchanged navigation repaints native/widget state")
-- 2026-11-10 Lua 5.1 baseline: 434300 VM instructions and 0.1171875 KiB.
-- Keep the normal two-percent regression limit, including native distance reads.
assert(allocated <= .1171875 * 1.02, "unchanged navigation allocates: " .. allocated .. " KiB")
assert(instructions <= 434300 * 1.02, "unchanged navigation exceeds the instruction budget")
assert(counters.distance - nativeDistanceReads == 1000, "navigation reread native distance within one sample")
print(("navigation warm budget: %.3f KiB, %d instructions / 1000 samples"):format(allocated, instructions))
world.x = .6
events.USER_WAYPOINT_UPDATED(module, "USER_WAYPOINT_UPDATED")
assert(module.model.identity:find("0.60000", 1, true), "waypoint identity ignores position")
world.clamped = true
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
world.distance = secret
module.driver.scripts.OnUpdate(module.driver, .1)
assert(not module.view.root:IsShown() and not module.model.mode, "secret geometry retained the old marker")
world.distance, world.valid = 400, true
events.NAVIGATION_FRAME_CREATED(module, "NAVIGATION_FRAME_CREATED")
combat, world.kind = true, Enum.SuperTrackingType.Corpse
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
assert(SuperTrackedFrame.Icon:GetAlpha() == 1, "combat fallback hid the native corpse marker")
assert(module.driver.scripts.OnUpdate == nil, "unsupported destination kept the tick alive")
combat, world.kind = false, Enum.SuperTrackingType.UserWaypoint
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
module:Disable()
assert(module.driver.scripts.OnUpdate == nil and SuperTrackedFrame.Icon:GetAlpha() == 1)
local point = navigation.Parse("/way 84 12.3,45.6 A place", 1)
assert(point and point.map == 84 and math.abs(point.x - .123) < .00001 and math.abs(point.y - .456) < .00001)
assert(not navigation.Parse("/way 84 120 5", 1))
local ok = navigation.Import("/way 84 20 30 One\n/way bad")
assert(not ok and #points == 0, "partial import changed the saved list")
assert(navigation.Import("/way 84 20 30 One\n/way 84 40 50 Two") and #points == 2)
module.active, config.autoNext = true, true
navigation.route = points[1]
navigation.Select(points[1], "saved")
navigation.QueueNext(module)
world.kind = Enum.SuperTrackingType.Quest
context.pending(module)
assert(world.kind == Enum.SuperTrackingType.Quest, "deferred route stole a newer native quest target")
navigation.owner = module
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationRoutes.lua"))("MSUF_Suite_QualityOfLife", private)
local planned = 0
FarstriderLib_API = { FindTrailTo = function(map, x, y)
    planned = planned + 1
    return {}, { {}, { getLocation = function() return { mapId = map, pos = { x = x, y = y }, isUI = true } end } }
end }
config.pathfinding = 2
navigation.Select(points[1], "manual")
assert(navigation.PlanRoute() and planned == 1 and navigation.travel, "explicit route planning failed")
navigation.Select(points[2], "manual")
assert(not navigation.travel, "a manual destination retained the old travel plan")
local canPlace = C_Map.CanSetUserWaypointOnMap
C_Map.CanSetUserWaypointOnMap = function() return false end
assert(not navigation.PlanRoute() and not navigation.travel, "a refused first step armed a route")
C_Map.CanSetUserWaypointOnMap = canPlace
local callbacks = {}
TomTom = {
    RegisterCallback = function(_, event, callback) callbacks[event] = callback end,
    UnregisterCallback = function(_, event) callbacks[event] = nil end,
    private = { GetCrazyArrowTarget = function() return { 84, .8, .9, title = "Guide" }, "Guide" end },
}
function context:Cancel() end
function context:Ticker() error("an absent guide started polling") end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationGuides.lua"))("MSUF_Suite_QualityOfLife", private)
config.guideTomTom, config.replaceManual = true, false
navigation.RefreshGuides(module)
assert(world.x == points[2].x, "a guide replaced a locked manual destination")
config.replaceManual = true
navigation.RefreshGuides(module)
assert(world.x == .8 and callbacks.ArrowTargetChanged, "enabling guide replacement did not seed the existing target")
callbacks.ArrowTargetChanged("ArrowTargetChanged", nil)
assert(world.kind == nil and navigation.selected == nil, "clearing the provider left its navigation active")
navigation.RefreshGuides(module)
navigation.Select(points[1], "manual")
callbacks.ArrowTargetChanged("ArrowTargetChanged", nil)
assert(world.kind == 2 and navigation.selected == points[1], "provider clearing removed a newer manual target")
navigation.DisableGuides(module)
assert(callbacks.ArrowTargetChanged == nil, "disabling guide tracking kept its callback")
Minimap, WorldMapFrame = Frame(UIParent), Frame(UIParent)
Minimap.width, Minimap.height = 300, 150
local canvas = Frame(WorldMapFrame)
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetMapID() return world.map end
function WorldMapFrame:GetCanvasScale() return 1 end
function WorldMapFrame:OnMapChanged() end
function WorldMapFrame:OnCanvasScaleChanged() end
function WorldMapFrame:OnCanvasSizeChanged() end
C_Minimap = { GetViewRadius = function() return 100 end }
C_CVar = { GetCVarBool = function() return false end }
C_Map.GetPlayerMapPosition = function() return { x = .5, y = .5 } end
C_Map.GetMapWorldSize = function() return 1000, 1000 end
GetCursorPosition = function() return 575, 337.5 end
IsControlKeyDown = function() return true end
local tickerStarts = 0
context.Ticker = function() tickerStarts = tickerStarts + 1 end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationMap.lua"))("MSUF_Suite_QualityOfLife", private)
config.minimapPlacement, config.autoTrackPins = true, false
navigation.EnableMap(module)
navigation.RefreshMap(module)
module.placement.scripts.OnClick(module.placement, "LeftButton")
assert(math.abs(points[#points].x - .55) < .00001 and math.abs(points[#points].y - .45) < .00001,
    "rectangular minimap click used the wrong vertical scale")
combat = true
navigation.RefreshMapInput(module)
assert(module.placement.mouse == false, "combat entry kept the Ctrl-click overlay enabled")
combat, world.map, tickerStarts = false, 99, 0
navigation.RefreshMap(module)
assert(tickerStarts == 0, "saved points in another map kept the minimap ticker running")
config.autoTrackPins = true
navigation.ObservePin(module)
world.noPin = true
navigation.ObservePin(module)
world.noPin, world.kind = false, nil
navigation.ObservePin(module)
assert(world.kind == 2, "re-adding the same cleared map pin did not start tracking")
-- Turn-in route from the XP bar: nearest ready quest first, a map pin where the
-- quest's position is readable, the focused quest otherwise; the next stop
-- follows a hand-in, and any other destination ends the route.
do
    local ready = { [11] = true, [12] = true, [13] = true }
    local distances, focused, printed = { [11] = 900, [12] = 100, [13] = 4 }, nil, nil
    C_QuestLog.IsComplete = function(id) return ready[id] == true end
    C_QuestLog.GetDistanceSqToQuest = function(id) return distances[id], id ~= 13 end
    C_QuestLog.GetQuestsOnMap = function(map) return map == 7 and { { questID = 12, x = .25, y = .75 } } or {} end
    GetQuestUiMapID = function(id) return id == 12 and 7 or 0 end
    C_SuperTrack.SetSuperTrackedQuestID = function(id) focused, world.kind = id, Enum.SuperTrackingType.Quest end
    Suite.Print = function(text) printed = text end
    C_Map.ClearUserWaypoint = function() world.noPin = true end
    local changes = 0
    navigation.questsChanged = function() changes = changes + 1 end
    world.noPin, world.valid, world.clamped, world.distance = false, true, false, 400
    local planned, stops = navigation.RouteQuests({ 11, 12, 13, 14 }, 4)
    local route = navigation.quests
    assert(planned and stops == 3 and route.current == 12 and route.pinned and world.map == 7 and world.x == .25
        and world.y == .75 and world.kind == 2 and not focused, "the route did not start at the nearest ready quest's map position")
    assert(changes == 1, "starting a route did not report it once")
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(navigation.quests == route and route.current == 12 and not focused, "an unrelated quest update moved the route")
    ready[12] = nil
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(navigation.quests == route and route.current == 11 and not route.pinned and focused == 11,
        "a hand-in did not continue with the nearest measurable quest")
    assert(world.noPin, "the route left the pin of a finished stop on the map")
    world.noPin = false
    ready[11] = nil
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(route.current == 13 and focused == 13 and not printed, "a quest on another continent was dropped from the route")
    ready[13] = nil
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(not navigation.quests and printed == "Turn-in route complete.", "the finished route stayed armed")
    ready[11], ready[12], focused, changes = true, true, nil, 0
    -- The stop button: the route, its tracking and its own pin go; a second stop is a no-op.
    assert(navigation.RouteQuests({ 11, 12 }, 2) and navigation.quests.pinned and not world.noPin)
    assert(navigation.StopQuests() and not navigation.quests and world.noPin and world.kind == nil and changes == 2,
        "stopping left the route, its tracking or its map pin behind")
    assert(not navigation.StopQuests() and changes == 2, "stopping without a route reported a change")
    world.noPin = false
    assert(navigation.RouteQuests({ 11, 12 }, 2) and navigation.quests.current == 12)
    world.x, ready[12] = .9, nil
    events.QUEST_LOG_UPDATE(module, "QUEST_LOG_UPDATE")
    assert(not navigation.quests and not focused and not world.noPin, "the route replaced or removed the player's own map pin")
    ready[12] = true
    assert(navigation.RouteQuests({ 11, 12 }, 2))
    navigation.Clear()
    assert(not navigation.quests, "stopping navigation kept the route armed")
    assert(navigation.RouteQuests({ 11 }, 1))
    navigation.FocusQuest(100)
    assert(not navigation.quests, "another focused quest kept the route armed")
    ready[11] = nil
    assert(not navigation.RouteQuests({ 11, 14 }, 2) and not navigation.quests, "a route started without a ready quest")
    navigation.questsChanged, world.noPin = nil, false
    -- A destination started by hand says in chat how to stop it.
    local command
    Suite.RegisterSlash = function(_, fn) command = fn end
    navigation.RegisterCommand()
    printed, config.rightClickClear = nil, true
    command("20 30 A spot")
    assert(world.x == .2 and world.y == .3 and printed == "Stop navigation with /msufnav stop or right-click the marker.",
        "a manual destination did not say how to stop")
    config.rightClickClear = false
    navigation.PrintStop()
    assert(printed == "Stop navigation with /msufnav stop.", "the stop hint promised a right-click that is switched off")
    printed = nil
    command("nonsense")
    assert(printed and printed:find("/msufnav list", 1, true), "a failed command printed the stop hint instead of its usage")
end
-- Live on Forever (2026-11-10): with Blizzard's in-game navigation option off
-- the client still places and measures the destination but reports Invalid.
do
    local state = Enum.NavigationState.Invalid
    C_Navigation.GetTargetState = function() return state end
    world.noPin, world.valid, world.clamped, world.distance, world.kind = false, true, false, 245, 2
    events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
    assert(module.view.root:IsShown() and module.model.mode == navigation.WAYPOINT and SuperTrackedFrame.Icon:GetAlpha() == 0,
        "a placed and measured destination stayed hidden behind the native Invalid state")
    state = Enum.NavigationState.Disabled
    module.driver.scripts.OnUpdate(module.driver, .1)
    assert(not module.view.root:IsShown() and SuperTrackedFrame.Icon:GetAlpha() == 1, "disabled navigation kept the marker")
    state, world.distance = Enum.NavigationState.Invalid, 0
    module.driver.scripts.OnUpdate(module.driver, .25)
    assert(not module.view.root:IsShown(), "a destination without a distance showed a marker")
    world.distance = 245
    module.driver.scripts.OnUpdate(module.driver, .25)
    assert(module.view.root:IsShown(), "the marker did not return with the distance")
    state = Enum.NavigationState.InRange
end
print("PASS navigation: native fallback, lifecycle, stable repaint budget, identity, secrets and atomic import")
