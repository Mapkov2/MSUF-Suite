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
-- A frame's own show or hide runs its OnShow or OnHide script, as the client does.
function methods:SetShown(value)
    local was = self.shown
    self.shown = value
    counters.writes = counters.writes + 1
    local script = self.scripts[(value and not was) and "OnShow" or (was and not value) and "OnHide" or 0]
    if script then script(self) end
end
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
-- The client builds the text; the arguments stay numbers on the Lua side,
-- and there are exactly as many as the format takes (no nil at the end).
function methods:SetFormattedText(format, ...)
    assert(Public(format))
    assert(select("#", ...) > 0 and select(select("#", ...), ...) ~= nil, "a formatted text got a nil argument")
    self.text = format:format(...)
    counters.writes = counters.writes + 1
end
function methods:SetVertexColor(r, g, b, a)
    self.vertexR, self.vertexG, self.vertexB, self.vertexA = r, g, b, a
    counters.writes = counters.writes + 1
end
function methods:SetColorTexture() counters.writes = counters.writes + 1 end
function methods:SetGradient(orientation, low, high)
    self.gradient, self.gradientLow, self.gradientHigh = orientation, low, high
    counters.writes = counters.writes + 1
end
function methods:SetBlendMode(mode) self.blend = mode end
function methods:SetTexCoord(left, right, top, bottom) self.texLeft, self.texRight, self.texTop, self.texBottom = left, right, top, bottom end
-- The beam pulse (NavigationVisuals.lua): the group records what it was told.
function methods:CreateAnimationGroup()
    local group = { playing = false, plays = 0, stops = 0, animations = {} }
    function group:SetLooping(kind) self.looping = kind end
    -- An animation keeps the arguments of every setter under the setter's name.
    function group:CreateAnimation(kind)
        local animation = setmetatable({ kind = kind, set = {} }, { __index = function(_, setter)
            return function(animation, ...) animation.set[setter] = { ... } end
        end })
        self.animations[#self.animations + 1] = animation
        return animation
    end
    function group:Play() self.playing, self.plays = true, self.plays + 1 end
    function group:Stop() self.playing, self.stops = false, self.stops + 1 end
    return group
end
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
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
hooksecurefunc = function() end
-- The client's clock: Advance (below) lets a frame of dt seconds pass.
local clock = { now = 100, tickers = {}, fired = false }
GetTime = function() return clock.now end
IsInInstance = function() return world.instance == true end
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
    -- combat is the lockdown: still false at PLAYER_REGEN_DISABLED and false again at PLAYER_REGEN_ENABLED,
    -- so the product asks with the event (MSUF_Suite/Core/Platform.lua, Suite.InCombat). world.fighting is
    -- the player's own combat flag, which a caller without an event also gets.
    IsCombatLocked = function() return combat end,
    InCombat = function(event)
        if event == "PLAYER_REGEN_DISABLED" then return true end
        if event == "PLAYER_REGEN_ENABLED" then return false end
        return combat or world.fighting == true
    end,
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
navigation.PauseMap, navigation.ResumeMap, navigation.PauseGuides = function() end, function() end, function() end
-- The flight map markers (NavigationTaxi.lua, suite_navigation_taxi_contract.lua)
-- start and stop with the module and follow every destination change.
local taxi = { enabled = 0, disabled = 0, refreshed = 0 }
navigation.EnableTaxi = function(owner) assert(owner == module) taxi.enabled = taxi.enabled + 1 end
navigation.DisableTaxi = function(owner) assert(owner == module) taxi.disabled = taxi.disabled + 1 end
navigation.RefreshTaxi = function(owner) assert(owner == module) taxi.refreshed = taxi.refreshed + 1 end
local properties = {}
local context = {}
function context:Property(region, getter, setter, value)
    if combat then return end
    properties[region] = properties[region] or region[getter](region)
    region[setter](region, value)
end
-- The runtime's entry for native frames that stay unprotected in combat
-- (MSUF_Suite_Modules/Runtime.lua).
function context:UnprotectedProperty(region, getter, setter, value)
    if combat and region:IsProtected() then return false end
    properties[region] = properties[region] or region[getter](region)
    region[setter](region, value)
    return true
end
function context:RestoreProperty(region, setter)
    if properties[region] and region:GetAlpha() == 0 then region[setter](region, properties[region]) end
    properties[region] = nil
end
function context:Event(event, fn) events[event] = fn end
function context:RemoveEvent(event) events[event] = nil end
function context:Coalesce(_, fn) return { Request = function() fn(module) end } end
function context:After(_, fn) self.pending = fn end
-- The runtime's tickers (MSUF_Suite_Modules/Timers.lua over C_Timer.NewTicker):
-- a ticker fires in the first frame in which its interval has passed since it
-- last fired, at most once a frame. Asking for a running ticker at its own
-- pace changes nothing; another pace starts it anew. A ticker of a module
-- that is not active fires into nothing.
function context:Ticker(interval, fn)
    local ticker = clock.tickers[fn]
    if ticker and ticker.interval == interval then return end
    clock.tickers[fn] = { interval = interval, waited = 0 }
end
function context:Cancel(fn) clock.tickers[fn] = nil end
-- One frame of dt seconds; clock.fired says whether a ticker fired in it.
-- clock.inside is true while a ticker's callback runs, so an instruction
-- budget can count the product's side of a frame without the clock's own.
local function Advance(dt)
    clock.now, clock.fired = clock.now + dt, false
    for fn, ticker in pairs(clock.tickers) do
        ticker.waited = ticker.waited + dt
        if ticker.waited >= ticker.interval then
            ticker.waited, clock.fired = 0, true
            if module.active then
                clock.inside = true
                fn(module)
                clock.inside = false
            end
        end
    end
end
-- Whether the marker is being ticked at all.
local function Ticking() return next(clock.tickers) ~= nil end
-- Whether the last frame's tick was a sample. At the arrow's pace (1/30 s)
-- only the tick that restarts the arrow's count is one (Navigation.lua, Tick).
local function Sampled() return clock.fired and (module.interval ~= 1 / 30 or module.sampledAt == clock.now) end
module.config, module.context, module.active = config, context, true
module:Enable()
assert(module.view.root:IsShown() and SuperTrackedFrame.Icon:GetAlpha() == 0)
assert(taxi.enabled == 1 and taxi.refreshed > 0, "enabling navigation did not start the flight map markers")
local before, nativeDistanceReads = counters.writes, counters.distance
collectgarbage("collect")
collectgarbage("stop")
local instructions = 0
-- The hook is made before the memory is read: it is the test's, not navigation's.
local function CountInside() if clock.inside then instructions = instructions + 1 end end
local memory = collectgarbage("count")
debug.sethook(CountInside, "", 1)
for _ = 1, 1000 do Advance(.1) end
debug.sethook()
local allocated = collectgarbage("count") - memory
collectgarbage("restart")
assert(counters.writes == before, "unchanged navigation repaints native/widget state")
-- 2026-11-10 Lua 5.1 baseline: 434300 VM instructions (hook every 100, with the test's own call) and
-- 0.1171875 KiB (with the test's hook). 2026-11-11, the ticker: the product's instructions only (a hook on
-- every instruction that counts while the ticker's callback runs), frame script 400000 -> ticker 385000,
-- and 0.0625 KiB in the first 1000 samples.
-- Keep the normal two-percent regression limit, including native distance reads.
assert(allocated <= .0625 * 1.02, "unchanged navigation allocates: " .. allocated .. " KiB")
assert(instructions <= 385000 * 1.02, "unchanged navigation exceeds the instruction budget: " .. instructions)
assert(counters.distance - nativeDistanceReads == 1000, "navigation reread native distance within one sample")
print(("navigation warm budget: %.3f KiB, %d instructions / 1000 samples"):format(allocated, instructions))
world.x = .6
local taxiRefreshes = taxi.refreshed
events.USER_WAYPOINT_UPDATED(module, "USER_WAYPOINT_UPDATED")
assert(module.model.identity:find("0.60000", 1, true), "waypoint identity ignores position")
assert(taxi.refreshed == taxiRefreshes + 1, "a moved map pin did not reach the flight map markers")
world.clamped = true
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
world.distance = secret
Advance(.1)
assert(not module.view.root:IsShown() and not module.model.mode, "secret geometry retained the old marker")
world.distance, world.valid = 400, true
events.NAVIGATION_FRAME_CREATED(module, "NAVIGATION_FRAME_CREATED")
combat, world.kind = true, Enum.SuperTrackingType.Corpse
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
assert(SuperTrackedFrame.Icon:GetAlpha() == 1, "combat fallback hid the native corpse marker")
assert(not Ticking(), "unsupported destination kept the tick alive")
combat, world.kind = false, Enum.SuperTrackingType.UserWaypoint
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
taxiRefreshes = taxi.refreshed
world.kind = Enum.SuperTrackingType.Corpse
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
assert(taxi.refreshed == taxiRefreshes + 1, "a destination the world marker does not follow froze the flight map markers")
world.kind = Enum.SuperTrackingType.UserWaypoint
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
-- A destination that appears in combat (a reload mid-fight, a new guide
-- step): the unprotected native marker is taken over there too.
world.kind = Enum.SuperTrackingType.Corpse
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
combat, world.kind = true, Enum.SuperTrackingType.UserWaypoint
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
assert(module.view.root:IsShown() and SuperTrackedFrame.Icon:GetAlpha() == 0,
    "a destination set in combat left the Suite marker hidden beside the native one")
-- Between two samples a turning direction arrow is placed and turned; nothing
-- else is repainted. A due sample replaces the arrow tick of its frame.
-- 2026-11-10, Lua 5.1, per tick (VM instructions / native calls), before ->
-- after: turning arrow 1417 -> 965 / 16.4 -> 11.4, steady arrow 1107 -> 863 /
-- 10.7 -> 8.7, on-screen sample 773 -> 722, marker that cannot show
-- 1211 -> 503 / 14.7 -> 7.0.
local paints, paint, turn = 0, navigation.Paint, 300
navigation.Paint = function(...) paints = paints + 1 return paint(...) end
SuperTrackedFrame.GetCenter = function() return 1400, turn end
for _ = 1, 2 do
    turn = turn + 40
    local angle = module.model.angle
    Advance(1 / 30)
    assert(module.model.angle ~= angle and module.view.tip.angle == module.model.angle and module.view.root:IsShown(),
        "the direction arrow did not turn between two samples")
end
assert(paints == 0, "a turning direction arrow repainted the whole marker between two samples")
Advance(.1)
assert(paints == 1, "a due sample did not paint once in place of its arrow tick")
navigation.Paint, SuperTrackedFrame.GetCenter = paint, nil
-- A protected native marker cannot be taken over in combat. The Suite marker
-- then stays hidden; a turning direction arrow must not flash it.
world.kind = Enum.SuperTrackingType.Corpse
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
local height = 300
SuperTrackedFrame.IsProtected = function() return true end
SuperTrackedFrame.GetCenter = function() return 1400, height end
world.kind = Enum.SuperTrackingType.UserWaypoint
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
assert(world.clamped and module.model.mode == navigation.DIRECTION, "the off-screen destination is not a direction arrow")
local placed = module.host.point
for _ = 1, 12 do
    height = height + 40
    Advance(1 / 30)
    assert(not module.view.root:IsShown() and SuperTrackedFrame.Icon:GetAlpha() == 1,
        "the Suite marker flickered over a native marker it could not take over")
end
assert(module.host.point == placed, "a marker that cannot show was still placed")
SuperTrackedFrame.IsProtected, SuperTrackedFrame.GetCenter = nil, nil
combat = false
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(module.view.root:IsShown() and SuperTrackedFrame.Icon:GetAlpha() == 0,
    "the Suite marker did not return after combat")
module:Disable()
assert(not Ticking() and SuperTrackedFrame.Icon:GetAlpha() == 1)
assert(taxi.disabled == 1, "disabling navigation left the flight map markers")
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
-- The marker's own ticker keeps its place on the clock; a guide polls every half second.
local clockTicker = context.Ticker
function context:Ticker(interval, fn)
    assert(interval ~= .5, "an absent guide started polling")
    return clockTicker(self, interval, fn)
end
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
-- The minimap pins refresh every 0.2 s and a guide polls every 0.5 s; the marker's ticker stays on the clock.
context.Ticker = function(self, interval, fn)
    if interval == .2 or interval == .5 then
        tickerStarts = tickerStarts + 1
        return
    end
    return clockTicker(self, interval, fn)
end
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
    Advance(.1)
    assert(not module.view.root:IsShown() and SuperTrackedFrame.Icon:GetAlpha() == 1, "disabled navigation kept the marker")
    state, world.distance = Enum.NavigationState.Invalid, 0
    Advance(.25)
    assert(not module.view.root:IsShown(), "a destination without a distance showed a marker")
    world.distance = 245
    Advance(.25)
    assert(module.view.root:IsShown(), "the marker did not return with the distance")
    state = Enum.NavigationState.InRange
end
-- Paused (combat inside an instance, Navigation.lua): the map and the guides
-- run nothing, and both return when the pause ends.
do
    local cancelled, removed = 0, {}
    context.Cancel = function(_, fn)
        cancelled = cancelled + 1
        clock.tickers[fn] = nil
    end
    context.RemoveEvent = function(_, event) removed[event] = true events[event] = nil end
    combat, world.map, tickerStarts = false, points[1].map, 0
    config.minimapPins = true
    navigation.RefreshMap(module)
    assert(tickerStarts == 1 and events.MODIFIER_STATE_CHANGED, "saved places on this map did not start the minimap ticker")
    module.paused, cancelled = true, 0
    navigation.PauseMap(module)
    assert(cancelled == 1 and removed.MODIFIER_STATE_CHANGED and events.MODIFIER_STATE_CHANGED == nil
        and module.placement.mouse == false, "the paused map kept its ticker, its modifier event or its minimap overlay")
    tickerStarts = 0
    navigation.RefreshMap(module)
    assert(tickerStarts == 0, "a refresh during the pause restarted the minimap ticker")
    module.paused = false
    navigation.ResumeMap(module)
    assert(tickerStarts == 1 and events.MODIFIER_STATE_CHANGED, "the map did not return after the pause")
    RXPG_ARROW = Frame(UIParent)
    RXPG_ARROW.element = { zone = 84, x = 10, y = 20, step = { title = "Step" } }
    MapzerothAddon = { Navigation = { IsActive = function() return true end, Start = function() end, Stop = function() end,
        Model = function() return { step = { text = "Travel", path = { { mapID = 84, x = .1, y = .2 } } } } end } }
    config.guideTomTom, config.guideRestedXP, config.guideMapzeroth = false, true, true
    module.paused, tickerStarts = true, 0
    navigation.RefreshGuides(module)
    assert(tickerStarts == 0, "a paused navigation polled a guide")
    cancelled = 0
    navigation.PauseGuides(module)
    assert(cancelled == 2, "pausing the guides did not stop both polls")
    module.paused = false
    navigation.RefreshGuides(module)
    assert(tickerStarts == 2, "the guides were not polled again after the pause")
end
print("PASS navigation: native fallback, lifecycle, stable repaint budget, identity, secrets and atomic import")
