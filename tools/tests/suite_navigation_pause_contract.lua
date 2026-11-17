-- Pause, display and pace contract (2026-11-11): combat inside an instance runs nothing; the off-screen choice;
-- the light beam; the ticker at the marker's pace; the readout without strings.
-- The harness below (lines 4-239) is the geometry contract's, copied unchanged.
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
function methods:EnableGamePadStick(active) self.stickEnabled = active end
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
TurnOrActionStart, TurnOrActionStop, CameraZoomIn = function() end, function() end, function() end
MoveViewInStart, MoveViewInStop = function() end, function() end
hooksecurefunc = function(name, callback)
    if type(name) ~= "string" then return end
    local fn = _G[name]
    _G[name] = function(...) fn(...); callback(...) end
end
-- The client's clock: Advance (below) lets a frame of dt seconds pass.
local clock = { now = 100, tickers = {}, fired = false }
GetTime = function() return clock.now end
IsInInstance = function() return world.instance == true end
GetUnitSpeed = function() return world.speed end
-- Exercise the existing sample budgets while an input keeps the view moving.
IsMouselooking = function() return world.mouselook ~= false end
C_GamePad = {
    GetDeviceMappedState = function() return { stickCount = 1, sticks = { { len = world.cameraStick or 0 } } } end,
    StickIndexToConfigName = function() return "Camera" end,
}
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
-- The third argument says the handler runs in combat too (the product passes true).
local alwaysRuns = {}
function context:Event(event, fn, always) events[event] = fn alwaysRuns[event] = always end
function context:RemoveEvent(event) events[event], alwaysRuns[event] = nil, nil end
function context:Coalesce(_, fn) return { Request = function() fn(module) end } end
function context:After(delay, fn)
    if delay == .5 then clock.wake, clock.wakeAt = fn, clock.now + delay
    else self.pending = fn end
end
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
function context:Cancel(fn)
    clock.tickers[fn] = nil
    if clock.wake == fn then clock.wake = nil end
end
-- One frame of dt seconds; clock.fired says whether a ticker fired in it.
-- clock.inside is true while a ticker's callback runs, so an instruction
-- budget can count the product's side of a frame without the clock's own.
local function Advance(dt)
    clock.now, clock.fired = clock.now + dt, false
    if clock.wake and clock.now >= clock.wakeAt then
        local fn = clock.wake
        clock.wake = nil
        fn(module)
    end
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

-- Pause and display contract. The harness above (lines 4-239 of this file) is
-- the geometry contract's, copied unchanged.
-- Counts: C_Navigation reads = the four C_Navigation calls; shown queries =
-- IsShown on the marker's own regions.

local view = module.view
local calls = { pauseMap = 0, resumeMap = 0, pauseGuides = 0, refreshGuides = 0 }
navigation.PauseMap = function(owner) assert(owner == module) calls.pauseMap = calls.pauseMap + 1 end
navigation.ResumeMap = function(owner) assert(owner == module) calls.resumeMap = calls.resumeMap + 1 end
navigation.PauseGuides = function(owner) assert(owner == module) calls.pauseGuides = calls.pauseGuides + 1 end
navigation.RefreshGuides = function(owner) assert(owner == module) calls.refreshGuides = calls.refreshGuides + 1 end
local navCalls, shownQueries = 0, 0
for _, name in ipairs({ "HasValidScreenPosition", "GetDistance", "WasClampedToScreen", "GetTargetState" }) do
    local real = C_Navigation[name]
    C_Navigation[name] = function(...) navCalls = navCalls + 1 return real(...) end
end
for _, key in ipairs({ "root", "waypoint", "card", "tip", "beam", "core", "pulse", "info" }) do
    view[key].IsShown = function(self) shownQueries = shownQueries + 1 return self.shown end
end

-- Registered through a pause: the two events that end it and a map pin the player places meanwhile
-- (Navigation.lua, STAYS); the arrival at a route stop is never removed.
local STAYS = "NAVIGATION_DESTINATION_REACHED,PLAYER_ENTERING_WORLD,PLAYER_REGEN_ENABLED,USER_WAYPOINT_UPDATED"
local function Fire(event, ...)
    local handler = assert(events[event], event .. " is not registered")
    handler(module, event, ...)
end
local function Tick(dt)
    local ticking = Ticking()
    Advance(dt)
    return ticking
end
local function Registered()
    local list = {}
    for event in pairs(events) do list[#list + 1] = event end
    table.sort(list)
    return table.concat(list, ",")
end
-- A fresh start in the open world, out of combat, the player walking.
local function Start(clamped, distance)
    combat, world.instance = false, false
    world.kind, world.valid, world.clamped, world.distance, world.speed = 2, true, clamped, distance, 7
    module:Refresh()
end
local function Running() return Ticking() end

------------------------------------------------------------------ 1. pause
-- Combat inside an instance: no marker, no sampling, no pulse, and no event of
-- the fight is heard. The pause starts at the combat edge: PLAYER_REGEN_DISABLED
-- arrives while the lockdown is still off and nothing but the event says combat.
Start(false, 400)
local ALL = Registered()
assert(view.root.shown and module.model.mode == navigation.WAYPOINT and Running() and view.pulseGroup.playing,
    "the far marker did not start with its beam pulse")
Fire("PLAYER_STARTED_MOVING")
assert(module.moving == true)
world.instance = true
local reads, guides, refreshed = navCalls, calls.refreshGuides, taxi.refreshed
assert(combat == false and not world.fighting, "probe: the lockdown is already on")
Fire("PLAYER_REGEN_DISABLED")
assert(module.paused == true, "combat inside an instance did not pause navigation at the combat edge")
combat = true
assert(not Running(), "paused navigation kept its ticker")
assert(not view.root.shown, "paused navigation kept its marker")
assert(not view.pulseGroup.playing and not view.beam.shown, "paused navigation kept the beam pulse playing")
assert(Registered() == STAYS, "paused navigation kept events: " .. Registered())
assert(calls.pauseMap == 1 and calls.pauseGuides == 1, "the pause did not reach the map and the guides once")
assert(SuperTrackedFrame.Icon:GetAlpha() == 0, "the pause handed the destination back to the native marker")
assert(navCalls == reads, "pausing read C_Navigation")
-- A request from elsewhere (a command, a profile reapplied) starts nothing.
module.refresh:Request()
module:Refresh()
assert(not Running() and not view.root.shown and navCalls == reads and taxi.refreshed == refreshed,
    "a refresh during the pause woke navigation")
assert(not Tick(.5), "a paused marker was sampled")
-- Still in the instance and in combat.
Fire("PLAYER_ENTERING_WORLD")
assert(module.paused == true and Registered() == STAYS and calls.resumeMap == 0 and navCalls == reads,
    "a loading screen inside the same fight ended the pause")
-- What the player does on purpose in the fight is not lost. A map pin placed now is followed when the
-- pause ends, and a route stop reached now queues the next one; neither wakes the marker.
local observed, queued = 0, 0
local realObserve, realQueue = navigation.ObservePin, navigation.QueueNext
navigation.ObservePin = function(owner) observed = observed + 1 return realObserve(owner) end
navigation.QueueNext = function(owner) queued = queued + 1 end
config.autoNext = true
Fire("USER_WAYPOINT_UPDATED")
Fire("NAVIGATION_DESTINATION_REACHED", false)
assert(observed == 0 and queued == 1, "a pin or an arrival in the fight: observed " .. observed .. ", queued " .. queued)
assert(module.paused == true and not Running() and not view.root.shown and navCalls == reads,
    "a pin or an arrival in the fight woke the marker")
config.autoNext = false
guides = calls.refreshGuides
-- The end of the fight: the event says so while the player's combat flag may still be set.
combat, world.fighting = false, true
Fire("PLAYER_REGEN_ENABLED")
world.fighting = false
assert(module.paused == false, "the end of combat did not end the pause")
assert(observed == 1, "the map pin placed in the fight was not looked at after it")
navigation.ObservePin, navigation.QueueNext = realObserve, realQueue
assert(Registered() == ALL, "the events after the pause are " .. Registered())
assert(calls.resumeMap == 1 and calls.refreshGuides == guides + 1, "the pause did not end for the map and the guides once")
assert(module.moving == false, "a movement flag from before the pause outlived it")
assert(Running() and view.root.shown and view.pulseGroup.playing and navCalls > reads,
    "the marker did not come back after the pause")

-- The open world keeps "Show navigation in combat": nothing pauses.
Start(false, 400)
combat = true
Fire("PLAYER_REGEN_DISABLED")
assert(not module.paused and Registered() == ALL and Running() and view.root.shown and calls.pauseMap == 1,
    "open-world combat paused navigation")
combat = false
Fire("PLAYER_REGEN_ENABLED")
assert(not module.paused and calls.resumeMap == 1, "open-world combat ended a pause that never began")

-- Entering an instance while already in combat pauses; leaving it resumes.
combat, world.instance = true, true
Fire("PLAYER_ENTERING_WORLD")
assert(module.paused == true and Registered() == STAYS and not Running() and not view.root.shown,
    "entering an instance in combat did not pause navigation")
world.instance = false
Fire("PLAYER_ENTERING_WORLD")
assert(module.paused == false and Registered() == ALL and Running() and view.root.shown,
    "leaving the instance did not end the pause")
combat = false
Fire("PLAYER_REGEN_ENABLED")

-- Enabled in the middle of instanced combat (a reload): starts paused. The lockdown may not be on yet;
-- the player's combat flag is.
module:Disable()
combat, world.instance, world.fighting = false, true, true
reads = navCalls
module:Enable()
assert(module.paused == true and Registered() == STAYS and not Running() and not view.root.shown and navCalls == reads,
    "navigation enabled in instanced combat did not start paused")
world.fighting = false
Fire("PLAYER_REGEN_ENABLED")
assert(module.paused == false and Registered() == ALL and Running() and view.root.shown,
    "navigation enabled in instanced combat did not start after it")

-- The pause ends with the screen geometry unread: a size or scale change in the fight was not heard.
Start(true, 400)
local geometry = 0
local realSize = UIParent.GetSize
UIParent.GetSize = function(...) geometry = geometry + 1 return realSize(...) end
world.instance = true
Fire("PLAYER_REGEN_DISABLED")
geometry = 0
Fire("PLAYER_REGEN_ENABLED")
assert(geometry == 1, "the marker placed after a pause read the screen size " .. geometry .. " times, not once")
UIParent.GetSize = nil
world.instance = true
-- Disabled while paused: the native marker gets its art back.
combat = true
Fire("PLAYER_REGEN_DISABLED")
assert(module.paused == true and SuperTrackedFrame.Icon:GetAlpha() == 0)
module:Disable()
assert(module.paused == false and SuperTrackedFrame.Icon:GetAlpha() == 1, "disabling a paused navigation kept the native art hidden")
combat, world.instance = false, false
module:Enable()
assert(not module.paused and Registered() == ALL and view.root.shown)

------------------------------------------------------------------ 2. off-screen display
-- Off screen the player chooses the arrow, the symbol or both.
local rules = NS.SuiteCatalog.navigation.rules
assert(rules.navigatorStyle.default == 1 and rules.navigatorStyle.enableKey == "navigator",
    "the off-screen display choice is not an option of the direction display")
local size = config.markerSize
local function Edge(style)
    config.navigatorStyle = style
    Start(true, 400)
    assert(module.model.mode == navigation.DIRECTION and view.root.shown, "the off-screen destination showed no direction")
end
Edge(1)
assert(view.waypoint.shown and view.tip.shown, "arrow and symbol: one of them is missing")
assert(view.tip.point[5] == 20 and view.tip.width == size * .7, "arrow and symbol: the arrow left its place above the symbol")
assert(view.tip.angle == module.model.angle, "arrow and symbol: the arrow does not point at the destination")
Edge(2)
assert(not view.waypoint.shown and view.tip.shown, "arrow only: the symbol is still shown")
assert(view.tip.point[5] == 0 and view.tip.width == size, "arrow only: the arrow did not take the symbol's place and size")
SuperTrackedFrame.GetCenter = function() return 1400, 900 end
local angle = view.tip.angle
assert(Tick(1 / 30) and module.model.angle ~= angle and view.tip.angle == module.model.angle,
    "arrow only: the arrow did not turn between two samples")
SuperTrackedFrame.GetCenter = nil
Edge(3)
assert(view.waypoint.shown and not view.tip.shown, "symbol only: the arrow is still shown")
angle = view.tip.angle
local placed = module.host.point[5]
-- Not where the arrow-only check left the destination: a new angle.
SuperTrackedFrame.GetCenter = function() return 1400, -300 end
assert(Tick(1 / 30) and module.host.point[5] ~= placed, "symbol only: the symbol did not follow the destination")
assert(view.tip.angle == angle, "symbol only: the hidden arrow was still turned")
SuperTrackedFrame.GetCenter = nil
-- The choice is for off screen only: on screen the far marker has no arrow
-- and the near card keeps its own.
world.clamped = false
Fire("SUPER_TRACKING_CHANGED")
assert(module.model.mode == navigation.WAYPOINT and view.waypoint.shown and not view.tip.shown)
world.distance = 20
Fire("SUPER_TRACKING_CHANGED")
assert(module.model.mode == navigation.CARD and view.card.shown and not view.waypoint.shown and view.tip.shown
    and view.tip.point[5] == 20 and view.tip.width == size * .7 and view.tip.angle == math.pi,
    "symbol only took the destination card's arrow")
config.navigatorStyle = 2
Start(false, 400)
assert(module.model.mode == navigation.WAYPOINT and view.waypoint.shown and not view.tip.shown,
    "arrow only hid the symbol of a destination on screen")
config.navigatorStyle = 1

------------------------------------------------------------------ 3. light beam
assert(rules.beamPulse.default == true and rules.beamPulse.enableKey == "beam", "the beam pulse is not an option of the beam")
Start(false, 400)
assert(view.beam.shown and view.core.shown and view.pulse.shown, "the far marker has no light beam")
assert(view.pulseGroup.playing and view.pulseGroup.looping == "REPEAT", "the beam pulse does not play")
assert(view.pulse.alpha == 0, "the pulse does not rest invisible")
-- What makes the beam visible, for the default settings: light added to the world, brightest at the
-- symbol and gone at the top, in the beam colour at the beam opacity.
do
    local r, g, b = Suite.RGB(config.beamColor)
    local opacity = config.beamOpacity / 100
    assert(opacity > 0 and r + g + b > 0, "probe: the default beam is invisible by its settings")
    for _, key in ipairs({ "beam", "core", "pulse" }) do
        assert(view[key].blend == "ADD", "the beam's " .. key .. " is not drawn additively")
    end
    assert(view.beam.texLeft == 0 and view.beam.texRight == 1 and view.beam.texTop == 0 and view.beam.texBottom == .5,
        "the glow is not the upper half of the spark (dark at the top, brightest at the symbol)")
    assert(view.beam.vertexR == r and view.beam.vertexG == g and view.beam.vertexB == b and view.beam.vertexA == opacity,
        "the glow is not in the beam colour at the beam opacity")
    local low, high = view.core.gradientLow, view.core.gradientHigh
    assert(view.core.gradient == "VERTICAL" and low.a == opacity and high.a == 0 and low.r == r and high.b == b,
        "the core does not fade from the beam opacity at the symbol to nothing at the top")
    assert(view.pulse.vertexR > 0 and view.pulse.vertexG > 0 and view.pulse.vertexB > 0 and view.pulse.vertexA == nil,
        "the pulse has no colour of its own, or a fixed alpha that fights the animation")
    -- The pulse: it lights up at the symbol (step 1), then rises and fades (step 2), then waits.
    local light, rise, fade = view.pulseGroup.animations[1], view.pulseGroup.animations[2], view.pulseGroup.animations[3]
    assert(#view.pulseGroup.animations == 3 and rise == view.rise)
    assert(light.kind == "Alpha" and light.set.SetOrder[1] == 1 and light.set.SetFromAlpha[1] == 0 and light.set.SetToAlpha[1] == 1
        and light.set.SetDuration[1] > 0, "the pulse does not light up first")
    assert(rise.set.SetOrder[1] == 2 and rise.set.SetDuration[1] > 0 and rise.set.SetOffset[1] == 0
        and rise.set.SetOffset[2] > 0, "the pulse does not rise as its second step")
    assert(fade.kind == "Alpha" and fade.set.SetOrder[1] == 2 and fade.set.SetFromAlpha[1] == 1 and fade.set.SetToAlpha[1] == 0
        and fade.set.SetDuration[1] == rise.set.SetDuration[1] and fade.set.SetEndDelay[1] > 0,
        "the pulse does not fade out over its rise and wait before the next one")
end
-- The pulse plays only while the marker is really on screen. It starts after the marker is shown, and a
-- parent that hides the marker (the interface, the options page) stops it until the marker is back.
do
    -- A new marker (the options preview makes its own) is not on screen until it was shown.
    local fresh, played = navigation.NewView(Frame(UIParent)), nil
    navigation.Style(fresh, config)
    local freshPlay = fresh.pulseGroup.Play
    fresh.pulseGroup.Play = function(group) played = fresh.root.shown and "shown" or "hidden" return freshPlay(group) end
    assert(module.model.mode == navigation.WAYPOINT, "probe: the model is not a far marker")
    navigation.Paint(fresh, module.model, config)
    assert(fresh.root.shown and fresh.pulseGroup.playing and played == "shown", "a new marker's pulse was started before it was shown")
end
do
    local order = {}
    local realPlay = view.pulseGroup.Play
    view.pulseGroup.Play = function(group) order[#order + 1] = view.root.shown and "shown" or "hidden" return realPlay(group) end
    world.valid = false
    Fire("SUPER_TRACKING_CHANGED")
    assert(not view.root.shown and not view.pulseGroup.playing)
    world.valid = true
    Fire("SUPER_TRACKING_CHANGED")
    assert(view.pulseGroup.playing and #order == 1 and order[1] == "shown", "the pulse was started before the marker was shown")
    view.root.scripts.OnHide(view.root)
    assert(not view.pulseGroup.playing, "a marker hidden with its parent kept the pulse playing")
    Tick(.1)
    assert(not view.pulseGroup.playing, "a sample restarted the pulse of a marker hidden with its parent")
    view.root.scripts.OnShow(view.root)
    assert(view.pulseGroup.playing and #order == 2, "the pulse did not return with the marker's parent")
    view.pulseGroup.Play = realPlay
    -- A marker given a new parent (Module:Refresh) reads whether it is on screen: its pulse does not depend
    -- on the client running a script for that.
    view.visible = false
    module:Refresh()
    assert(view.pulseGroup.playing, "a marker restyled on screen did not play its pulse")
    UIParent.shown = false
    module:Refresh()
    assert(not view.pulseGroup.playing, "a marker restyled under a hidden interface plays its pulse")
    UIParent.shown = true
    module:Refresh()
    assert(view.pulseGroup.playing)
end
assert(view.beam.width == math.max(24, size * 1.5) and view.beam.height == config.beamHeight,
    "the beam glow is " .. view.beam.width .. " x " .. view.beam.height)
assert(view.core.width == math.max(3, size / 6) and view.core.height == config.beamHeight)
assert(view.rise.kind == "Translation" and view.rise.set.SetOffset[2] == config.beamHeight * .8,
    "the pulse does not rise along the beam")
-- 50 samples of a walking player: one unchanged marker, so no client call
-- asks what is shown and the pulse is not started again.
local plays, writes = view.pulseGroup.plays, counters.writes
shownQueries = 0
for _ = 1, 50 do assert(Tick(.1)) end
assert(view.pulseGroup.plays == plays, "a repaint restarted the beam pulse")
assert(shownQueries == 0, "50 repaints of an unchanged marker asked the client what is shown " .. shownQueries .. " times")
assert(counters.writes == writes, "50 repaints of an unchanged marker wrote " .. (counters.writes - writes) .. " times")
config.beamPulse = false
Start(false, 400)
assert(view.beam.shown and view.core.shown and not view.pulseGroup.playing, "a switched-off pulse still plays")
config.beamPulse, config.beam = true, false
Start(false, 400)
assert(not view.beam.shown and not view.core.shown and not view.pulse.shown and not view.pulseGroup.playing,
    "a switched-off beam is still shown")
config.beam = true
-- Only the far marker has the beam, and a hidden marker animates nothing.
Start(false, 20)
assert(module.model.mode == navigation.CARD and not view.beam.shown and not view.pulseGroup.playing,
    "the destination card kept the beam")
Start(true, 400)
assert(module.model.mode == navigation.DIRECTION and not view.beam.shown and not view.pulseGroup.playing,
    "the direction display kept the beam")
Start(false, 400)
assert(view.beam.shown and view.pulseGroup.playing, "the beam did not return with the far marker")
config.hideDistance = 500
Fire("SUPER_TRACKING_CHANGED")
assert(not view.root.shown and not view.pulseGroup.playing, "a marker hidden near its destination kept the pulse playing")
config.hideDistance = 0
Fire("SUPER_TRACKING_CHANGED")
assert(view.root.shown and view.pulseGroup.playing)
world.valid = false
Fire("SUPER_TRACKING_CHANGED")
assert(not view.root.shown and not view.pulseGroup.playing and not Running(), "a lost destination kept the pulse playing")
world.valid = true
Fire("SUPER_TRACKING_CHANGED")
assert(view.root.shown and view.pulseGroup.playing and Running())
------------------------------------------------------------------ 4. the ticker
-- No frame script: a client ticker at the pace the marker needs, and nothing in the frames between.
local function Pace()
    local pace
    for _, ticker in pairs(clock.tickers) do pace = ticker.interval end
    return pace
end
-- A second of frames; the ticks in it.
local function Second(frames)
    local ticks = 0
    for _ = 1, frames do
        Advance(1 / frames)
        if clock.fired then ticks = ticks + 1 end
    end
    return ticks
end
Start(false, 400)
assert(module.driver.scripts.OnUpdate == nil, "the marker runs a frame script again")
assert(Pace() == .1, "a marker on screen is not ticked every 0.1 s")
reads = navCalls
local ticks = Second(120)
assert(ticks >= 9 and ticks <= 10, "a second of 120 frames ticked a marker on screen " .. ticks .. " times")
assert(navCalls - reads == 4 * ticks, "a marker on screen was read outside its ticks")
Start(true, 400)
assert(Pace() == 1 / 30, "an off-screen destination is not ticked at the arrow's pace")
config.hideDistance = 500
Fire("SUPER_TRACKING_CHANGED")
assert(module.model.mode == nil and Pace() == .25, "a hidden marker is not ticked every 0.25 s")
config.hideDistance = 0
world.kind = Enum.SuperTrackingType.Corpse
Fire("SUPER_TRACKING_CHANGED")
assert(Pace() == nil and not Running(), "no destination kept a ticker")
-- The interface hidden and shown again starts nothing without a destination, nor in a pause.
module.driver.scripts.OnHide(module.driver)
module.driver.scripts.OnShow(module.driver)
assert(not Running(), "showing the interface started a ticker without a destination")
world.kind = 2
Start(false, 400)
world.instance = true
Fire("PLAYER_REGEN_DISABLED")
module.driver.scripts.OnHide(module.driver)
module.driver.scripts.OnShow(module.driver)
assert(module.paused == true and not Running(), "showing the interface started a ticker in the pause")
Fire("PLAYER_REGEN_ENABLED")
world.instance = false
-- The pace follows the marker without an event: the destination leaves the screen and comes back.
Start(false, 400)
world.clamped = true
Advance(.1)
assert(module.model.mode == navigation.DIRECTION and Pace() == 1 / 30, "the tick that found the destination off screen kept the pace")
world.clamped = false
for _ = 1, 4 do Advance(1 / 30) end
assert(module.model.mode == navigation.WAYPOINT and Pace() == .1, "the tick that found the destination on screen kept the arrow's pace")
-- At the arrow's pace the samples keep the frame script's cadence at 30 frames per second and below:
-- every third tick at 30 (and every third frame at 22), every second frame at 20 and at 11, every frame
-- at 10. Above 30 a sample falls on a tick of the ticker: at 100 frames per second a tick is four frames
-- and a sample three ticks, 8.3 a second where the frame script made 10 (accepted trade, Navigation.lua).
local function Samples(frames, seconds)
    Start(true, 400)
    local count, distance = 0, counters.distance
    for _ = 1, frames * seconds do Advance(1 / frames) end
    return (counters.distance - distance) / seconds
end
assert(Samples(30, 10) == 10, "30 frames per second off screen: " .. Samples(30, 10) .. " samples a second")
assert(Samples(20, 10) == 10, "20 frames per second off screen: " .. Samples(20, 10) .. " samples a second")
assert(Samples(10, 10) == 10, "10 frames per second off screen: " .. Samples(10, 10) .. " samples a second")
assert(Samples(22, 10) == 7.3, "22 frames per second off screen: " .. Samples(22, 10) .. " samples a second")
assert(Samples(11, 10) == 5.5, "11 frames per second off screen: " .. Samples(11, 10) .. " samples a second")
-- The first tick after a start can come a frame early or late: 83 or 84 samples in ten seconds.
local fast = Samples(100, 10)
assert(fast >= 8.3 and fast <= 8.4, "100 frames per second off screen: " .. fast .. " samples a second")
-- The ticker stops while the driver frame is hidden (the interface hidden) and starts with it;
-- the first tick after that is a full sample even if the marker had settled.
Start(false, 400)
world.speed = 0
Fire("SUPER_TRACKING_CHANGED")
assert(module.settled == true, "probe: the still player did not settle the marker")
UIParent.shown = false
module.driver.scripts.OnHide(module.driver)
assert(not Running(), "a hidden driver frame kept the ticker")
reads = navCalls
Fire("QUEST_LOG_UPDATE")
assert(not Running(), "an event restarted the ticker of a hidden driver frame")
UIParent.shown = true
module.driver.scripts.OnShow(module.driver)
assert(Running() and Pace() == .1 and module.settled == false, "showing the driver frame did not restart the ticker")
reads = navCalls
Advance(.1)
assert(navCalls - reads == 4, "the first tick after the interface returned was not a full sample")
-- Shown when the interface is hidden: the driver's parent is the world frame, which stays visible.
config.showWithHiddenUI = true
UIParent.shown = false
module:Refresh()
assert(module.driver.parent == WorldFrame and Running(), "navigation shown with the interface hidden has no ticker")
config.showWithHiddenUI = false
module:Refresh()
assert(not Running(), "navigation kept its ticker under a hidden interface")
UIParent.shown = true
module:Refresh()
assert(Running())

------------------------------------------------------------------ 5. the readout
-- The text is built by the client from a format and numbers; it reads as before.
local function Shows(distance, speed, expected)
    world.distance, world.speed = distance, speed
    module:Refresh()
    assert(view.distance.text == expected, ("%s yd at speed %s shows '%s', not '%s'"):format(distance, speed, tostring(view.distance.text), expected))
end
world.kind, world.valid, world.clamped = 2, true, false
config.showDistance, config.showETA, config.units = true, false, 1
Shows(437.4, 7, "437 yd")
Shows(1234.4, 7, "1.2 kyd")
-- Exactly between two tenths the larger one shows.
Shows(1250, 7, "1.3 kyd")
config.units = 2
Shows(437.4, 7, "400 m")
Shows(1234.4, 7, "1.1 km")
config.units, config.showETA = 1, true
Shows(140, 7, "140 yd · 20 sec")
Shows(437.4, 7, "437 yd · 1 min 02 sec")
Shows(1234.4, 7, "1.2 kyd · 2 min 56 sec")
-- The travel time alone changes: the distance number is the same, the text is not.
Shows(1234.4, 14, "1.2 kyd · 1 min 28 sec")
-- Half a second rounds up.
Shows(143.5, 7, "144 yd · 21 sec")
Shows(437.4, 1, "437 yd")
config.showDistance = false
Shows(140, 7, "20 sec")
Shows(437.4, 7, "1 min 02 sec")
config.showETA = false
Shows(437.4, 7, "")
config.showDistance = true
-- A distance that changes within the shown number writes nothing.
Shows(1234.4, 7, "1.2 kyd")
writes = counters.writes
world.distance = 1236.6
Advance(.1)
assert(module.model.rounded == 1237 and counters.writes == writes, "a distance change the text does not show was written")
world.distance = 1251
Advance(.1)
assert(view.distance.text == "1.3 kyd" and counters.writes == writes + 1, "the next tenth was not written once")
-- A view that is given another model shows that model's text, whatever its stamp.
do
    local other = { readoutStamp = module.model.readoutStamp, readoutFormat = "%d yd", readoutA = 777,
        mode = navigation.WAYPOINT, distance = 777, title = "Other", color = config.pinColor }
    navigation.Paint(view, other, config)
    assert(view.distance.text == "777 yd", "a second model with the same stamp kept the first model's text")
    navigation.Paint(view, module.model, config)
    assert(view.distance.text == "1.3 kyd", "the first model's text did not return")
end
-- The options preview paints its own view from its own model (Navigation.Sample): a changed option shows.
do
    local stage, sample = Frame(UIParent), {}
    navigation.Sample(sample, config, 1, 450)
    local preview = Suite.DrawNavigationPreview(stage, config, sample)
    assert(preview ~= view and preview.root.shown and preview.distance.text == "450 yd", "the preview shows '" .. tostring(preview.distance.text) .. "'")
    config.units = 2
    navigation.Sample(sample, config, 1, 450)
    assert(Suite.DrawNavigationPreview(stage, config, sample) == preview and preview.distance.text == "411 m",
        "the preview kept the old unit: '" .. tostring(preview.distance.text) .. "'")
    config.units, config.showETA = 1, true
    navigation.Sample(sample, config, 1, 450)
    Suite.DrawNavigationPreview(stage, config, sample)
    assert(preview.distance.text == "450 yd · 1 min 04 sec", "the preview did not show the travel time: '" .. tostring(preview.distance.text) .. "'")
    config.showETA = false
    -- No destination: the preview marker hides and its pulse stops.
    navigation.Sample(sample, config, 4, 450)
    Suite.DrawNavigationPreview(stage, config, sample)
    assert(not preview.root.shown and not preview.pulseGroup.playing, "the preview without a destination kept its marker or pulse")
end
-- A walking player's changing distance leaves no string behind: the format and the numbers go to the
-- client, with the travel time and without it.
local sent
view.distance.SetFormattedText = function(_, format, a) sent = a end
for _, travelTime in ipairs({ true, false }) do
    config.showETA = travelTime
    world.distance, sent = 900, nil
    module:Refresh()
    for _ = 1, 50 do
        world.distance = world.distance - .7
        Advance(.1)
    end
    collectgarbage("collect")
    collectgarbage("stop")
    local memory = collectgarbage("count")
    for _ = 1, 500 do
        world.distance = world.distance - .7
        Advance(.1)
    end
    local allocated = collectgarbage("count") - memory
    collectgarbage("restart")
    assert(sent == math.floor(world.distance + .5), "the client did not get the distance as a number")
    assert(allocated == 0, "500 samples of a walking player allocated " .. allocated .. " KiB")
end
view.distance.SetFormattedText = nil
config.showETA = false

------------------------------------------------------------------ 6. a walking player
-- The 2026-11-15 outdoor walk: the destination on screen, the distance falling, the text changing on every
-- second sample. The readout's formats are read once and not on each change, and while the client reports
-- the player moving and no travel time shows, the speed is not asked for. Every sample still reads the
-- position (the four C_Navigation calls) and writes a changed text.
-- Counts: instructions = the product's only (a hook on every instruction that counts while the ticker's
-- callback runs); speed reads = GetUnitSpeed; lookups = Suite.Text; writes = SetFormattedText on the readout.
-- Another tree's counts are printed, not held to this tree's budget:
-- lua suite_navigation_pause_contract.lua <that tree> <this tree>.
local function Budget(ok, message)
    if ok then return end
    if base == root then error(message, 2) end
    print("  not within this tree's budget: " .. message)
end
local walked = { speed = 0, lookups = 0, formatted = 0 }
local realSpeed, realText, realFormatted = GetUnitSpeed, Suite.Text, view.distance.SetFormattedText
GetUnitSpeed = function(...) walked.speed = walked.speed + 1 return realSpeed(...) end
Suite.Text = function(...) walked.lookups = walked.lookups + 1 return realText(...) end
view.distance.SetFormattedText = function(...) walked.formatted = walked.formatted + 1 return realFormatted(...) end
-- samples a frame of dt seconds apart (0.1 s, or the second of a player the client reports moving: section
-- 6b), each step yards nearer; every sample shows what Shown(distance) says.
local function Walk(samples, step, Shown, dt)
    walked.speed, walked.lookups, walked.formatted = 0, 0, 0
    local nav, instructions = navCalls, 0
    debug.sethook(function() if clock.inside then instructions = instructions + 1 end end, "", 1)
    for sample = 1, samples do
        world.distance = world.distance - step
        Advance(dt or .1)
        assert(clock.fired and view.root.shown and view.distance.text == Shown(world.distance),
            ("walking sample %d at %s yd shows '%s', not '%s'"):format(sample, world.distance, tostring(view.distance.text), Shown(world.distance)))
    end
    debug.sethook()
    return { instructions = instructions, nav = navCalls - nav, speed = walked.speed, lookups = walked.lookups,
        formatted = walked.formatted }
end
local function Yards(distance) return ("%d yd"):format(math.floor(distance + .5)) end
local function TravelTime(speed)
    return function(distance)
        local seconds = math.floor(distance / speed + .5)
        if seconds >= 60 then return ("%s · %d min %02d sec"):format(Yards(distance), math.floor(seconds / 60), seconds % 60) end
        return ("%s · %d sec"):format(Yards(distance), seconds)
    end
end
-- (a) No travel time (the default). 2026-11-15, Lua 5.1, 1000 samples, before -> after: 466500 -> 424500
-- instructions, 500 -> 0 lookups, 1000 -> 0 speed reads; 4000 C_Navigation reads and 500 writes both.
-- The work of one sample is the same since; the samples are a second apart (section 6b).
config.showDistance, config.showETA, config.units = true, false, 1
Start(false, 900)
Fire("PLAYER_STARTED_MOVING")
local walk = Walk(1000, .5, Yards, 1)
print(("walking budget, 1000 samples: %d instructions, %d C_Navigation reads, %d speed reads, %d lookups, %d writes"):format(
    walk.instructions, walk.nav, walk.speed, walk.lookups, walk.formatted))
assert(walk.nav == 4000, "a walking player's marker was not read on every sample: " .. walk.nav .. " C_Navigation reads")
assert(walk.formatted == 500, "a walking player's readout was written " .. walk.formatted .. " times, not on each of its 500 changes")
assert(not module.settled and module.model.mode == navigation.WAYPOINT, "a walking player's marker settled or changed its display")
Budget(walk.lookups == 0, "a walking player's readout looked its formats up " .. walk.lookups .. " times")
Budget(walk.speed == 0, "a walking player without a travel time had the speed read " .. walk.speed .. " times")
Budget(walk.instructions <= 424500 * 1.02, "a walking player exceeds the instruction budget: " .. walk.instructions)
-- (b) With the travel time the speed is read on every sample, and a changed speed shows on the next one.
config.showETA = true
Start(false, 900)
walk = Walk(200, .5, TravelTime(7), 1)
assert(walk.speed == 200 and walk.nav == 800, "a walking player's travel time did not read the speed on every sample")
Budget(walk.lookups == 0, "a walking player's travel time looked its formats up " .. walk.lookups .. " times")
world.speed = 14
walk = Walk(20, .5, TravelTime(14), 1)
assert(walk.speed == 20, "a faster player's travel time did not follow the speed")
-- Too slow for a travel time: the distance alone.
world.speed = 1
Walk(4, .5, Yards, 1)
world.speed = 7
Walk(4, .5, TravelTime(7), 1)
-- The kilometre and the metre readouts of a walking player.
world.distance, config.units = 1400, 2
Walk(4, .5, function(distance)
    return ("%.1f km · %d min %02d sec"):format(math.floor(distance * .9144 / 100 + .5) / 10, math.floor(math.floor(distance / 7 + .5) / 60),
        math.floor(distance / 7 + .5) % 60)
end, 1)
config.units, config.showETA = 1, false
-- (c) The player stops: the standing pace is back at once, the next sample (0.1 s later) reads the speed
-- and settles the marker; turning the camera then
-- moves the projection, and the next tick is a full sample again.
Start(false, 900)
world.speed = 0
Fire("PLAYER_STOPPED_MOVING")
walk = Walk(1, 0, Yards)
assert(walk.speed == 1 and module.settled == true, "the sample after the player stopped did not read the speed and settle")
walk = Walk(3, 0, Yards)
assert(walk.nav == 0 and walk.speed == 0, "a settled marker was sampled")
SuperTrackedFrame.GetCenter = function() return 1300, 320 end
walk = Walk(1, 0, Yards)
assert(walk.nav == 4 and walk.speed == 1 and module.settled == true, "a camera turn of a standing player was not sampled")
SuperTrackedFrame.GetCenter = nil
-- (d) Movement the client reported no event for (the speed alone): the speed is read on every sample and
-- the marker does not settle.
world.speed = 7
Start(false, 900)
walk = Walk(20, .5, Yards)
assert(walk.speed == 20 and walk.nav == 80 and not module.settled, "a player moving without a movement event was not sampled with the speed")
-- (e) After a pause the movement events were not heard: the speed is read again.
Fire("PLAYER_STARTED_MOVING")
world.instance = true
Fire("PLAYER_REGEN_DISABLED")
world.instance = false
Fire("PLAYER_REGEN_ENABLED")
walk = Walk(5, .5, Yards)
assert(walk.speed == 5 and module.moving == false, "the samples after a pause did not read the speed")
GetUnitSpeed, Suite.Text, view.distance.SetFormattedText = realSpeed, realText, nil

------------------------------------------------------------------ 6b. a walking player's second
-- 2026-11-15, owner decision: while the client reports the player moving, a marker shown on screen is
-- sampled once a second, not ten times. The marker itself stays on Blizzard's projection frame, which the
-- client moves; what a sample decides (distance and travel time, hover fade, proximity sound, the change
-- to the arrow or to hidden) follows up to a second later. Measured in elapsed time, at 20 frames per
-- second, where the 0.1 s and the 1 s tickers both fire on whole frames. Ten seconds, before -> after:
-- 100 -> 10 samples, 400 -> 40 C_Navigation reads; with the travel time 100 -> 10 speed reads.
-- Unchanged, and held here: the arrow's and the hidden marker's pace while moving, the standing pace, a
-- destination or settings change at once, no destination, the interface hidden, the pause.
do
    local FRAME = .05
    local function Ticker()
        local found
        for _, ticker in pairs(clock.tickers) do found = ticker end
        return found
    end
    local sourceReads, speedReads, centerReads = 0, 0, 0
    local realKind, realSpeed = C_SuperTrack.GetHighestPrioritySuperTrackingType, GetUnitSpeed
    C_SuperTrack.GetHighestPrioritySuperTrackingType = function(...) sourceReads = sourceReads + 1 return realKind(...) end
    GetUnitSpeed = function(...) speedReads = speedReads + 1 return realSpeed(...) end
    local center = { 1400, 300 }
    SuperTrackedFrame.GetCenter = function() centerReads = centerReads + 1 return center[1], center[2] end
    -- frames of 0.05 s, each step yards nearer: the samples (one distance read each), the C_Navigation and
    -- speed reads, and the frames the samples fell on.
    local function Run(frames, step)
        local samples, nav, speed, on = counters.distance, navCalls, speedReads, {}
        for frame = 1, frames do
            world.distance = world.distance - step
            local before = counters.distance
            Advance(FRAME)
            if counters.distance > before then on[#on + 1] = frame end
        end
        return { samples = counters.distance - samples, nav = navCalls - nav, speed = speedReads - speed, on = table.concat(on, ",") }
    end
    local function Yd(distance) return ("%d yd"):format(math.floor(distance + .5)) end
    config.showDistance, config.showETA, config.units = true, false, 1

    -- (a) The standing pace is as before: a player the client does not report moving (here with a speed
    -- and no event, 6 (d)) is sampled every 0.1 s.
    if module.moving then Fire("PLAYER_STOPPED_MOVING") end
    Start(false, 900)
    assert(module.moving == false and Pace() == .1)
    local ten = Run(200, .35)
    assert(ten.samples == 100 and ten.nav == 400 and ten.speed == 100,
        ("ten seconds without a movement event: %d samples, %d C_Navigation reads, %d speed reads"):format(ten.samples, ten.nav, ten.speed))

    -- (b) The movement event changes the pace of the running ticker at once. It reads nothing: not the
    -- destination, not the position, not the projection, and it writes nothing.
    local nav, source, writes, centers = navCalls, sourceReads, counters.writes, centerReads
    Fire("PLAYER_STARTED_MOVING")
    assert(navCalls == nav and sourceReads == source and counters.writes == writes and centerReads == centers,
        "the movement event sampled the marker or read the destination again")
    -- Ten seconds: ten samples, each a second after the last, and no speed read without a travel time.
    local speedBefore = speedReads
    ten = Run(200, .35)
    print(("walking player on screen, 10 s at 20 frames per second: a tick every %g s, %d samples, %d C_Navigation reads, %d speed reads"):format(
        Pace(), ten.samples, ten.nav, ten.speed))
    assert(Pace() == 1, "a walking player's marker on screen is ticked every " .. tostring(Pace()) .. " s, not every second")
    assert(ten.samples == 10 and ten.nav == 40, ("ten walking seconds: %d samples, %d C_Navigation reads"):format(ten.samples, ten.nav))
    assert(ten.on == "20,40,60,80,100,120,140,160,180,200", "the walking samples fell on frames " .. ten.on)
    assert(ten.speed == 0 and speedReads == speedBefore, "a walking player without a travel time had the speed read")
    assert(view.distance.text == Yd(world.distance) and not module.settled)
    -- One second, frame by frame: no sample, no read and no write before it is over, while the distance
    -- falls and the client moves the projection. The marker hangs on the projection frame.
    nav, source, writes, centers = navCalls, sourceReads, counters.writes, centerReads
    local text = view.distance.text
    for frame = 1, 19 do
        world.distance = world.distance - .35
        center[1], center[2] = center[1] - 3, center[2] + 1
        Advance(FRAME)
        assert(navCalls == nav and sourceReads == source and centerReads == centers,
            "frame " .. frame .. " of a walking second read the position, the destination or the projection")
        assert(counters.writes == writes and view.distance.text == text, "frame " .. frame .. " of a walking second wrote")
        assert(module.host.point[1] == "CENTER" and module.host.point[2] == SuperTrackedFrame and module.host.point[3] == "CENTER"
            and module.host.point[4] == nil and module.anchor == SuperTrackedFrame, "the marker left Blizzard's projection frame")
    end
    world.distance = world.distance - .35
    Advance(FRAME)
    assert(navCalls - nav == 4 and view.distance.text == Yd(world.distance) and view.distance.text ~= text,
        "the sample after a walking second did not read the position once and show the distance")
    assert(sourceReads == source and centerReads == centers and module.host.point[2] == SuperTrackedFrame
        and view.root.shown and module.model.mode == navigation.WAYPOINT, "the walking sample read the destination or moved the marker")
    -- The event again (a jump, another key) leaves the running ticker alone.
    for _ = 1, 5 do Advance(FRAME) end
    local ticker = Ticker()
    nav = navCalls
    Fire("PLAYER_STARTED_MOVING")
    assert(Ticker() == ticker and ticker.waited > 0 and navCalls == nav, "a second movement event started the ticker anew or sampled")
    for _ = 1, 14 do Advance(FRAME) end
    assert(navCalls == nav, "probe: the second is not over")
    Advance(FRAME)
    assert(navCalls - nav == 4, "the sample did not come a second after the last one")

    -- (c) With the travel time the speed is read with each sample, so once a second; switching the option
    -- on (Module:Refresh) shows it at once.
    config.showETA = true
    world.distance, nav = 875, navCalls
    module:Refresh()
    assert(navCalls - nav == 4 and view.distance.text == "875 yd · 2 min 05 sec" and Pace() == 1,
        "a settings change of a walking player was not shown at once: " .. tostring(view.distance.text))
    ten = Run(200, .35)
    print(("walking player on screen with the travel time, 10 s: %d samples, %d C_Navigation reads, %d speed reads"):format(
        ten.samples, ten.nav, ten.speed))
    assert(ten.samples == 10 and ten.nav == 40 and ten.speed == 10,
        ("ten walking seconds with the travel time: %d samples, %d C_Navigation reads, %d speed reads"):format(ten.samples, ten.nav, ten.speed))
    config.showETA = false
    module:Refresh()

    -- (d) A destination event does not wait for the second: a new destination shows at once, a lost one
    -- hides at once and stops the ticker, an arrival is asked about at once. The pace stays the walking one.
    for _ = 1, 3 do Advance(FRAME) end
    world.distance, nav = 500, navCalls
    Fire("SUPER_TRACKING_CHANGED")
    assert(navCalls - nav == 4 and view.distance.text == "500 yd" and Pace() == 1, "a walking player's new destination waited for a sample")
    world.valid = false
    Fire("SUPER_TRACKING_CHANGED")
    assert(not view.root.shown and not Running(), "a walking player's lost destination was not hidden at once")
    world.valid = true
    Fire("SUPER_TRACKING_CHANGED")
    assert(view.root.shown and Pace() == 1, "a walking player's destination did not come back at the walking pace")
    world.distance, nav = 20, navCalls
    Fire("NAVIGATION_DESTINATION_REACHED", true)
    assert(navCalls - nav == 4 and module.model.mode == navigation.CARD and view.card.shown and Pace() == 1,
        "a walking player's arrival waited for a sample")
    world.distance = 500
    Fire("QUEST_LOG_UPDATE")
    assert(module.model.mode == navigation.WAYPOINT and view.distance.text == "500 yd")

    -- (e) The player stops: the standing pace at once, without a sample by the event; the sample 0.1 s
    -- later reads the speed and settles the marker.
    nav, source = navCalls, sourceReads
    world.speed = 0
    Fire("PLAYER_STOPPED_MOVING")
    assert(Pace() == .1 and navCalls == nav and sourceReads == source, "the stop did not bring the standing pace back at once, or sampled")
    Advance(FRAME)
    assert(navCalls == nav, "probe: a standing sample before 0.1 s")
    speedBefore = speedReads
    Advance(FRAME)
    assert(navCalls - nav == 4 and speedReads - speedBefore == 1 and module.settled == true,
        "the sample 0.1 s after the stop did not read the speed and settle")
    -- A settled marker starts walking: no sample is skipped at the walking pace.
    world.speed = 7
    Fire("PLAYER_STARTED_MOVING")
    assert(Pace() == 1 and not module.settled)
    ten = Run(60, .35)
    assert(ten.samples == 3 and ten.on == "20,40,60", "a marker that had settled was sampled on frames " .. ten.on .. " of three walking seconds")

    -- (f) Off screen a walking player's arrow keeps its pace and its samples: 1/30 s, a sample every 0.1 s
    -- (section 4), and the arrow turns between two samples. The movement events leave that ticker alone.
    assert(Samples(30, 10) == 10, "30 frames per second off screen, walking: " .. Samples(30, 10) .. " samples a second")
    assert(Samples(20, 10) == 10, "20 frames per second off screen, walking: " .. Samples(20, 10) .. " samples a second")
    assert(module.moving == true and module.model.mode == navigation.DIRECTION and Pace() == 1 / 30,
        "a walking player's off-screen destination is not ticked at the arrow's pace")
    ticker = Ticker()
    Fire("PLAYER_STOPPED_MOVING")
    Fire("PLAYER_STARTED_MOVING")
    assert(Ticker() == ticker and Pace() == 1 / 30, "a movement event started the arrow's ticker anew")
    local angle = view.tip.angle
    center[1], center[2] = 1400, 900
    Advance(1 / 30)
    assert(view.tip.angle ~= angle and view.tip.angle == module.model.angle, "a walking player's arrow did not turn with the next tick")
    center[1], center[2] = 1400, 300
    -- A hidden marker keeps its 0.25 s while the player walks.
    config.hideDistance = 500
    Fire("SUPER_TRACKING_CHANGED")
    assert(module.model.mode == nil and Pace() == .25, "a walking player's hidden marker is not ticked every 0.25 s")
    nav = navCalls
    for _ = 1, 8 do Advance(.25) end
    assert(navCalls - nav == 32, "a walking player's hidden marker was sampled " .. (navCalls - nav) / 4 .. " times in two seconds, not 8")
    config.hideDistance = 0
    Fire("SUPER_TRACKING_CHANGED")
    assert(module.model.mode == navigation.DIRECTION and Pace() == 1 / 30)
    -- The pace follows what the sample finds: back on screen the walking second, off screen (found by the
    -- sample, so up to a second later: the accepted trade) the arrow's pace.
    world.clamped = false
    for _ = 1, 4 do Advance(1 / 30) end
    assert(module.model.mode == navigation.WAYPOINT and Pace() == 1, "the destination back on screen did not get the walking pace")
    world.clamped = true
    for _ = 1, 19 do Advance(FRAME) end
    assert(module.model.mode == navigation.WAYPOINT and Pace() == 1, "probe: the walking second is not over")
    Advance(FRAME)
    assert(module.model.mode == navigation.DIRECTION and Pace() == 1 / 30 and view.tip.shown,
        "the walking sample that found the destination off screen kept the pace")
    world.clamped = false
    Fire("SUPER_TRACKING_CHANGED")
    assert(module.model.mode == navigation.WAYPOINT and Pace() == 1)

    -- (g) Nothing runs that did not run before: a movement event starts no ticker without a destination,
    -- under a hidden interface or in the pause (where it is not heard), and samples in none of them.
    world.kind = Enum.SuperTrackingType.Corpse
    Fire("SUPER_TRACKING_CHANGED")
    assert(not Running(), "probe: no destination kept a ticker")
    nav = navCalls
    Fire("PLAYER_STOPPED_MOVING")
    Fire("PLAYER_STARTED_MOVING")
    assert(not Running() and navCalls == nav, "a movement event without a destination started a ticker or sampled")
    world.kind = Enum.SuperTrackingType.UserWaypoint
    Fire("SUPER_TRACKING_CHANGED")
    assert(Pace() == 1)
    UIParent.shown = false
    module.driver.scripts.OnHide(module.driver)
    nav, source = navCalls, sourceReads
    Fire("PLAYER_STOPPED_MOVING")
    Fire("PLAYER_STARTED_MOVING")
    assert(not Running() and navCalls == nav and sourceReads == source, "a movement event under a hidden interface started a ticker or sampled")
    UIParent.shown = true
    module.driver.scripts.OnShow(module.driver)
    assert(Pace() == 1, "the interface shown again did not bring a walking player's pace back")
    world.instance = true
    Fire("PLAYER_REGEN_DISABLED")
    assert(module.paused == true and not Running() and events.PLAYER_STARTED_MOVING == nil and events.PLAYER_STOPPED_MOVING == nil,
        "the pause kept a ticker or hears the player's movement")
    world.instance = false
    Fire("PLAYER_REGEN_ENABLED")
    -- The movement events of the fight were not heard: the standing pace, with the speed read, until the next one.
    assert(module.moving == false and Pace() == .1, "the pause did not end at the standing pace")
    Fire("PLAYER_STARTED_MOVING")
    assert(Pace() == 1)
    -- Disabled while walking: no ticker. The player stops meanwhile, which a disabled module does not hear:
    -- enabled again the movement is unknown, so the standing pace with the speed read (as after a pause),
    -- and the standing marker settles. The next movement event brings the walking pace.
    module:Disable()
    assert(not Running(), "disabling a walking player's navigation kept the ticker")
    world.speed = 0
    module:Enable()
    assert(module.moving == false and Pace() == .1 and view.root.shown and module.settled == true,
        "navigation enabled again kept the movement state from before it was disabled")
    nav = navCalls
    for _ = 1, 8 do Advance(FRAME) end
    assert(navCalls == nav and module.settled == true, "a standing player's marker was sampled after navigation was enabled again")
    world.speed = 7
    Fire("PLAYER_STARTED_MOVING")
    assert(Pace() == 1)
    Fire("PLAYER_STOPPED_MOVING")
    assert(Pace() == .1)
    C_SuperTrack.GetHighestPrioritySuperTrackingType, GetUnitSpeed, SuperTrackedFrame.GetCenter = realKind, realSpeed, nil
end

------------------------------------------------------------------ 7. the readout in another language
-- The formats are the translated ones, in every combination, and a format without a translation stays English.
do
    local translations = { ["%d yd"] = "%d Yards", ["%.1f kyd"] = "%.1f Tsd. Yards", ["%.1f km"] = "%.1f Kilometer",
        ["%d sec"] = "%d Sek.", ["%d min %02d sec"] = "%d Min. %02d Sek.", ["%s · %s"] = "%s | %s" }
    local translated = setmetatable({ Text = function(text) return translations[text] or text end }, { __index = Suite })
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationModel.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = translated })
    local readout, model = translated.Navigation.Readout, {}
    local function Reads(distance, speed, units, showDistance, showETA, expected)
        model.rounded = nil
        readout(model, { units = units, showDistance = showDistance, showETA = showETA }, distance, speed)
        local text = model.readoutFormat and model.readoutFormat:format(model.readoutA, model.readoutB, model.readoutC) or ""
        assert(text == expected, ("the translated readout of %s yd shows '%s', not '%s'"):format(distance, text, expected))
    end
    Reads(437.4, 7, 1, true, false, "437 Yards")
    Reads(1234.4, 7, 1, true, false, "1.2 Tsd. Yards")
    Reads(437.4, 7, 2, true, false, "400 m")
    Reads(1234.4, 7, 2, true, false, "1.1 Kilometer")
    Reads(140, 7, 1, true, true, "140 Yards | 20 Sek.")
    Reads(437.4, 7, 1, true, true, "437 Yards | 1 Min. 02 Sek.")
    Reads(1234.4, 7, 2, true, true, "1.1 Kilometer | 2 Min. 56 Sek.")
    Reads(437.4, 7, 2, true, true, "400 m | 1 Min. 02 Sek.")
    Reads(140, 7, 1, false, true, "20 Sek.")
    Reads(437.4, 7, 1, false, true, "1 Min. 02 Sek.")
    Reads(437.4, 7, 1, false, false, "")
end
do
    world.mouselook = false
    Start(true, 900)
    world.speed = 0
    Fire("SUPER_TRACKING_CHANGED")
    for _ = 1, 30 do Advance(.025) end
    assert(view.root.shown and module.model.mode == navigation.DIRECTION and not Running(), "a parked off-screen arrow kept a ticker")
    local before, writes = navCalls, counters.writes
    for _ = 1, 1200 do Advance(.025) end
    assert(navCalls == before and counters.writes == writes and not Running(), "standing for 30 seconds performed navigation work")
    world.distance = 840
    Fire("SUPER_TRACKING_CHANGED")
    assert(module.model.distance == 840 and not Running(), "a new target needed a standing timer")
    world.x = .65
    Fire("USER_WAYPOINT_UPDATED")
    assert(Running(), "a switched waypoint did not give the native projection time to catch up")
    world.distance = 830
    for _ = 1, 30 do Advance(.025) end
    assert(module.model.distance == 830 and not Running(), "a readable but stale projection survived the waypoint swap")
    TurnOrActionStart()
    assert(Pace() == 1 / 30, "turning the camera in place did not wake the arrow")
    TurnOrActionStop()
    for _ = 1, 30 do Advance(.025) end
    assert(not Running(), "releasing the camera left a ticker")
    MoveViewInStart()
    CameraZoomIn()
    assert(Running(), "camera zoom did not wake the arrow")
    for _ = 1, 30 do Advance(.025) end
    assert(not Running(), "camera zoom left a ticker")
    world.cameraStick = 1
    assert(module.driver.scripts.OnGamePadStick(module.driver, "Camera", 1, 0) and Pace() == 1 / 30,
        "the camera stick did not wake the arrow or its input was consumed")
    world.cameraStick = 0
    for _ = 1, 10 do Advance(.025) end
    assert(not Running(), "the GamePad camera kept ticking after an unrelated frame consumed the release")
    world.speed = 7
    Fire("PLAYER_STARTED_MOVING")
    assert(Pace() == 1 / 30, "walking did not restart the smooth arrow")
    Advance(.1)
    world.speed = 0
    Fire("PLAYER_STOPPED_MOVING")
    assert(not Running() and view.root.shown, "stopping left the timer running or hid the arrow")
    world.clamped = false
    Fire("SUPER_TRACKING_CHANGED")
    assert(not Running() and view.root.shown, "a stationary on-screen marker kept a ticker")
    local getFrame = C_Navigation.GetFrame
    C_Navigation.GetFrame = function() return SuperTrackedFrame end
    world.valid = false
    Fire("NAVIGATION_FRAME_CREATED")
    world.valid = true
    for _ = 1, 30 do Advance(.025) end
    assert(view.root.shown and not Running(), "late native projection did not recover and park")
    C_Navigation.GetFrame = getFrame
end
print("PASS navigation pause, display and pace: stationary zero ticks; movement, targeting, native projection, readout and pause")
