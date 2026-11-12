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
-- The third argument says the handler runs in combat too (the product passes true).
local alwaysRuns = {}
function context:Event(event, fn, always) events[event] = fn alwaysRuns[event] = always end
function context:RemoveEvent(event) events[event], alwaysRuns[event] = nil, nil end
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
print("PASS navigation pause, display and pace: instanced combat runs nothing, off-screen choice, beam and pulse, ticker, readout")
