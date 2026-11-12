-- Settle contract (2026-11-10): the settled marker skips samples while nothing it reads can change.
-- The harness below (lines 3-238) is the geometry contract's, copied unchanged.
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

-- Settle contract. A completed sample of a player who stands still is skipped
-- while nothing it reads can have changed (Navigation.lua, Settle and Still).
-- The harness above (lines 3-238 of this file) is the geometry contract's, copied unchanged.
-- Counts: samples = Navigation.Paint calls (wrapped), C_Navigation reads = the
-- four C_Navigation calls, parent reads = host:GetParent and the parent's
-- geometry calls, projection reads = SuperTrackedFrame:GetCenter.

local main = { cx = 640, cy = 360, width = 1000, height = 500, scale = 1.25 }
local proj = { x = 1400, y = 300 }
local reads = { parent = 0, host = 0, projection = 0 }
local mouseCalls, paints, navCalls, mouseOver = 0, 0, 0, false
local function Bind(frame, g)
    frame.GetCenter = function() reads.parent = reads.parent + 1 return g.cx, g.cy end
    frame.GetSize = function() reads.parent = reads.parent + 1 return g.width, g.height end
    frame.GetEffectiveScale = function() reads.parent = reads.parent + 1 return g.scale end
end
Bind(UIParent, main)
module.host.GetParent = function(self) reads.host = reads.host + 1 return self.parent end
SuperTrackedFrame.GetCenter = function() reads.projection = reads.projection + 1 return proj.x, proj.y end
module.view.root.IsMouseOver = function() mouseCalls = mouseCalls + 1 return mouseOver end
local realPaint = navigation.Paint
navigation.Paint = function(...) paints = paints + 1 return realPaint(...) end
for _, name in ipairs({ "HasValidScreenPosition", "GetDistance", "WasClampedToScreen", "GetTargetState" }) do
    local real = C_Navigation[name]
    C_Navigation[name] = function(...) navCalls = navCalls + 1 return real(...) end
end

local function Coordinates(p, g)
    local x = (p.x * main.scale - g.cx * g.scale) / g.scale
    local y = (p.y * main.scale - g.cy * g.scale) / g.scale
    return x, y
end
local function Expected(p, g)
    local x, y = Coordinates(p, g)
    local radiusX, radiusY = math.min(500, g.width * .38), math.min(230, g.height * .3)
    local divisor = math.sqrt(x * x / (radiusX * radiusX) + y * y / (radiusY * radiusY))
    local cfg = module.config
    x, y = x / divisor + cfg.navigatorX, y / divisor + cfg.navigatorY
    if cfg.dynamicOffset then y = y * .9 end
    return x, y
end
local function CheckFormula(message)
    local x, y = Expected(proj, main)
    local px, py = module.host.point[4], module.host.point[5]
    assert(math.abs(px - x) < 1e-9 and math.abs(py - y) < 1e-9, message .. " (placed " .. px .. ", " .. py .. ")")
end
local function Snap()
    return { distance = counters.distance, parent = reads.parent + reads.host, projection = reads.projection,
        mouse = mouseCalls, nav = navCalls, paints = paints }
end
local function Diff(a, b)
    local d = {}
    for k, v in pairs(b) do d[k] = v - a[k] end
    return d
end
-- One tick and what it did. A due tick is one whose sample timer was reset.
local function Step(dt)
    local a = Snap()
    Advance(dt)
    local d = Diff(a, Snap())
    d.due = Sampled()
    return d
end
local function Settled() return module.settled == true end
local function Sample() events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED") end
-- A fresh start: no combat, no protected marker, default geometry, speed 0.
local function Reset(clamped, distance)
    module.config.fadeOnHover, module.config.hideDistance = true, 0
    combat, mouseOver = false, false
    SuperTrackedFrame.IsProtected = nil
    proj.x, proj.y, main.width = 1400, 300, 1000
    world.kind, world.speed, world.clamped, world.distance = 2, 0, clamped, distance
    module:Refresh()
end

-- 1. Settling. One completed sample, then 10 s of 0.1 s ticks: samples on ticks 10, 20, ... 100.
Reset(false, 400)
Sample()
assert(Settled(), "one completed sample of a still player did not settle the marker")
local onscreen = {}
for tick = 1, 100 do
    local d = Step(.1)
    assert(d.due, "tick " .. tick .. " of 0.1 s was not a due tick")
    if d.paints > 0 then
        onscreen[#onscreen + 1] = tick
        assert(d.distance == 1, "the settled sample on tick " .. tick .. " did not read the distance once")
    else
        assert(d.distance == 0 and d.nav == 0, "skipped tick " .. tick .. " read C_Navigation")
        assert(d.projection == 1, "skipped tick " .. tick .. " read the projection " .. d.projection .. " times, not 1")
        assert(d.parent == 0, "skipped tick " .. tick .. " read the parent geometry")
    end
end
assert(table.concat(onscreen, ",") == "10,20,30,40,50,60,70,80,90,100",
    "settled samples at 0.1 s ticks fell on " .. table.concat(onscreen, ","))

-- 1b. Clamped direction arrow at 1/30 s ticks: 10 s give exactly 10 samples, on ticks 30, 60, ... 300.
-- Every other tick reads the projection once (an arrow tick, or a skipped due tick); a sample reads it twice
-- (placement and the settle read). Total: 290 * 1 + 10 * 2 = 310.
Reset(true, 400)
Sample()
assert(Settled() and module.model.mode == navigation.DIRECTION, "the clamped marker did not settle as a direction arrow")
local clamped, arrowTicks, projectionTotal = {}, 0, 0
for tick = 1, 300 do
    local d = Step(1 / 30)
    projectionTotal = projectionTotal + d.projection
    if d.paints > 0 then
        clamped[#clamped + 1] = tick
        assert(d.projection == 2, "the settled sample on tick " .. tick .. " read the projection " .. d.projection .. " times, not 2")
    elseif d.due then
        assert(d.distance == 0 and d.nav == 0 and d.projection == 1, "skipped due tick " .. tick .. " read more than the projection once")
    else
        arrowTicks = arrowTicks + 1
        assert(d.distance == 0 and d.nav == 0 and d.parent == 0, "arrow tick " .. tick .. " read C_Navigation or the parent geometry")
        assert(d.projection == 1, "arrow tick " .. tick .. " read the projection " .. d.projection .. " times, not 1")
    end
end
assert(table.concat(clamped, ",") == "30,60,90,120,150,180,210,240,270,300",
    "clamped settled samples at 1/30 s ticks fell on " .. table.concat(clamped, ","))
assert(arrowTicks > 0, "the arrow ticks did not run between the settled samples")
assert(projectionTotal == 310, "300 clamped ticks read the projection " .. projectionTotal .. " times, not 310")

-- 2. Hover. With fadeOnHover every due tick makes exactly one IsMouseOver call, skipped or not.
Reset(false, 400)
Sample()
assert(Settled() and module.config.fadeOnHover == true)
for tick = 1, 50 do
    local d = Step(.1)
    assert(d.mouse == (d.due and 1 or 0), "tick " .. tick .. " made " .. d.mouse .. " IsMouseOver calls")
end
assert(Settled() and module.model.hovered == false, "probe: the marker is not settled and unhovered before the pointer moves")
-- The pointer enters the marker: the very next due tick is a full sample that records the hover.
mouseOver = true
local entered = Step(.1)
assert(entered.due and entered.paints == 1, "the first due tick after the pointer entered was not a full sample")
assert(module.model.hovered == true, "the sample after the pointer entered did not record the hover")
-- The pointer leaves: the next due tick is a full sample again and clears the hover.
mouseOver = false
local left = Step(.1)
assert(left.paints == 1 and module.model.hovered == false, "the sample after the pointer left did not clear the hover")
-- fadeOnHover off (through Module:Refresh): skipped ticks make no IsMouseOver call.
module.config.fadeOnHover = false
module:Refresh()
assert(Settled(), "probe: the marker did not settle after Refresh with fadeOnHover off")
for tick = 1, 30 do
    local d = Step(.1)
    assert(d.mouse == 0, "with fadeOnHover off, tick " .. tick .. " made " .. d.mouse .. " IsMouseOver calls")
end

-- 3. Projection move. A moved projection centre makes the next due tick a full sample, and the marker settles again.
Reset(false, 400)
Sample()
for _ = 1, 25 do Step(.1) end
proj.x = proj.x + 100
local moved = Step(.1)
assert(moved.due and moved.paints == 1 and moved.distance == 1, "the due tick after the on-screen projection moved was not a full sample")
assert(Settled(), "the sample after the on-screen projection moved did not settle again")
assert(Step(.1).paints == 0, "the marker did not skip again after the on-screen projection moved")
-- A move of the y coordinate alone is a move too.
Reset(false, 400)
Sample()
for _ = 1, 25 do Step(.1) end
proj.y = proj.y + 100
local movedY = Step(.1)
assert(movedY.due and movedY.paints == 1, "the due tick after the on-screen projection moved in y was not a full sample")
assert(Settled(), "the sample after the on-screen projection moved in y did not settle again")
Reset(true, 400)
Sample()
for _ = 1, 40 do Step(1 / 30) end
proj.x = proj.x + 100
local movedClamped
repeat movedClamped = Step(1 / 30) until movedClamped.due
assert(movedClamped.paints == 1, "the due tick after the clamped projection moved was not a full sample")
CheckFormula("the sample after the clamped projection moved did not place the marker by the formula")
assert(Settled(), "the sample after the clamped projection moved did not settle again")
local afterMove
repeat afterMove = Step(1 / 30) until afterMove.due
assert(afterMove.paints == 0, "the clamped marker did not skip again after the projection move")

-- 4. Own movement. While the player moves every due tick is a sample; with speed 7 and no events too.
Reset(false, 400)
Sample()
assert(Settled(), "probe: the marker did not settle before the movement")
events.PLAYER_STARTED_MOVING(module, "PLAYER_STARTED_MOVING")
assert(module.moving == true and not Settled(), "a moving player's marker stayed settled")
for tick = 1, 40 do
    local d = Step(.1)
    assert(d.due and d.paints == 1, "a due tick while the player moves was not a sample (tick " .. tick .. ")")
end
events.PLAYER_STOPPED_MOVING(module, "PLAYER_STOPPED_MOVING")
assert(module.moving == false and not Settled(), "the stop event itself settled the marker")
local stopped = Step(.1)
assert(stopped.due and stopped.paints == 1 and Settled(), "the marker did not settle on the sample after the player stopped")
-- 4b. The player's own movement is not a new destination (2026-11-11): neither event reads the source, the pin,
-- the flight map or the position, and neither paints; the next tick samples. Before, each event read all of them
-- again (a map pin is two client tables and a string per read).
do
    local sourceReads, pinReads = 0, 0
    local realKind, realPin = C_SuperTrack.GetHighestPrioritySuperTrackingType, C_Map.GetUserWaypoint
    C_SuperTrack.GetHighestPrioritySuperTrackingType = function(...) sourceReads = sourceReads + 1 return realKind(...) end
    C_Map.GetUserWaypoint = function(...) pinReads = pinReads + 1 return realPin(...) end
    Reset(false, 400)
    Sample()
    sourceReads, pinReads = 0, 0
    local flights, a = taxi.refreshed, Snap()
    events.PLAYER_STARTED_MOVING(module, "PLAYER_STARTED_MOVING")
    events.PLAYER_STOPPED_MOVING(module, "PLAYER_STOPPED_MOVING")
    events.PLAYER_STARTED_MOVING(module, "PLAYER_STARTED_MOVING")
    local d = Diff(a, Snap())
    assert(sourceReads == 0 and pinReads == 0 and taxi.refreshed == flights,
        "a movement event read the destination again: source " .. sourceReads .. ", pin " .. pinReads)
    assert(d.paints == 0 and d.nav == 0 and d.projection == 0 and d.parent == 0, "a movement event sampled the marker")
    assert(module.moving == true and not Settled(), "a movement event left the marker settled")
    d = Step(.1)
    assert(d.due and d.paints == 1 and d.distance == 1, "the tick after a movement event was not a sample")
    C_SuperTrack.GetHighestPrioritySuperTrackingType, C_Map.GetUserWaypoint = realKind, realPin
    events.PLAYER_STOPPED_MOVING(module, "PLAYER_STOPPED_MOVING")
end
-- 4c. A destination the client could not give in full is still asked again by the player's movement, as every
-- movement event did before: a name that arrives later, a source that was unreadable, native art not handed back.
do
    local name
    local realName = C_SuperTrack.GetSuperTrackedItemName
    C_SuperTrack.GetSuperTrackedItemName = function() return name, "Description" end
    Reset(false, 400)
    world.kind = Enum.SuperTrackingType.MapPin
    Sample()
    assert(module.model.incomplete == true and module.view.name.text == "Tracked point of interest",
        "probe: the point of interest without a name is not marked incomplete")
    name = "Stormwind Harbor"
    for _ = 1, 20 do Step(.1) end
    assert(module.view.name.text == "Tracked point of interest", "probe: a sample read the destination's name")
    events.PLAYER_STARTED_MOVING(module, "PLAYER_STARTED_MOVING")
    assert(module.model.incomplete == false and module.view.name.text == "Stormwind Harbor",
        "the name that arrived later was not read at the player's next movement")
    local sourceReads = 0
    local realKind = C_SuperTrack.GetHighestPrioritySuperTrackingType
    C_SuperTrack.GetHighestPrioritySuperTrackingType = function(...) sourceReads = sourceReads + 1 return realKind(...) end
    events.PLAYER_STOPPED_MOVING(module, "PLAYER_STOPPED_MOVING")
    assert(sourceReads == 0, "a complete destination was read again by a movement event")
    C_SuperTrack.GetHighestPrioritySuperTrackingType = realKind
    -- An unreadable source stops the marker; the next movement brings it back.
    world.kind = secret
    Sample()
    assert(module.model.incomplete == true and not Ticking() and not module.view.root:IsShown(),
        "probe: an unreadable source did not stop the marker as incomplete")
    world.kind = Enum.SuperTrackingType.MapPin
    events.PLAYER_STARTED_MOVING(module, "PLAYER_STARTED_MOVING")
    assert(Ticking() and module.view.root:IsShown(), "the marker did not come back with the player's movement")
    events.PLAYER_STOPPED_MOVING(module, "PLAYER_STOPPED_MOVING")
    C_SuperTrack.GetSuperTrackedItemName = realName
    -- A quest whose title the client has not loaded, and a map pin it cannot read yet.
    local title
    local realTitle, realPin = C_QuestLog.GetTitleForQuestID, C_Map.GetUserWaypoint
    C_QuestLog.GetTitleForQuestID = function() return title end
    world.kind = Enum.SuperTrackingType.Quest
    Sample()
    assert(module.model.incomplete == true and module.view.name.text == "Quest destination", "probe: the quest without a title is not incomplete")
    title = "The Missing Diplomat"
    events.PLAYER_STARTED_MOVING(module, "PLAYER_STARTED_MOVING")
    assert(module.model.incomplete == false and module.view.name.text == "The Missing Diplomat",
        "the quest title that arrived later was not read at the player's next movement")
    events.PLAYER_STOPPED_MOVING(module, "PLAYER_STOPPED_MOVING")
    C_QuestLog.GetTitleForQuestID = realTitle
    C_Map.GetUserWaypoint = function() return secret end
    world.kind = Enum.SuperTrackingType.UserWaypoint
    Sample()
    assert(module.model.incomplete == true and not Ticking(), "probe: an unreadable map pin did not stop the marker as incomplete")
    C_Map.GetUserWaypoint = function() return { uiMapID = world.map, position = { x = secret, y = world.y } } end
    events.PLAYER_STARTED_MOVING(module, "PLAYER_STARTED_MOVING")
    assert(module.model.incomplete == true and not Ticking(), "a map pin with an unreadable position counts as complete")
    C_Map.GetUserWaypoint = realPin
    events.PLAYER_STOPPED_MOVING(module, "PLAYER_STOPPED_MOVING")
    assert(module.model.incomplete == false and Ticking() and module.view.root:IsShown(),
        "the map pin did not come back with the player's movement")
    -- Native art that could not be handed back (the native marker was protected) is handed back at the next movement.
    Reset(false, 400)
    Sample()
    assert(module.ownsArt and SuperTrackedFrame.Icon:GetAlpha() == 0, "probe: the marker does not own the native art")
    SuperTrackedFrame.IsProtected = function() return true end
    world.kind = Enum.SuperTrackingType.Corpse
    Sample()
    assert(module.restorePending == true and not module.model.incomplete and SuperTrackedFrame.Icon:GetAlpha() == 0,
        "probe: the protected native marker got its art back")
    SuperTrackedFrame.IsProtected = nil
    events.PLAYER_STARTED_MOVING(module, "PLAYER_STARTED_MOVING")
    assert(not module.restorePending and SuperTrackedFrame.Icon:GetAlpha() == 1,
        "the native art was not handed back at the player's next movement")
    events.PLAYER_STOPPED_MOVING(module, "PLAYER_STOPPED_MOVING")
    world.kind = Enum.SuperTrackingType.UserWaypoint
end
world.speed = 7
Sample()
assert(not Settled(), "a player with speed 7 settled")
for tick = 1, 30 do
    local d = Step(.1)
    assert(d.due and d.paints == 1, "a due tick at speed 7 was not a sample (tick " .. tick .. ")")
end
world.speed = 0

-- 5. Safeguard and trade.
-- (a) A distance change with no event: the readout waits for the safeguard sample, on tick 10 (1.0 s).
Reset(false, 400)
Sample()
local readout = module.view.distance.text
world.distance = 300
local readoutAt
for tick = 1, 10 do
    local d = Step(.1)
    if d.paints > 0 then
        readoutAt = tick
        break
    end
    assert(module.view.distance.text == readout, "the readout changed on skipped tick " .. tick)
end
assert(readoutAt == 10, "the safeguard sample for the changed distance is on tick " .. tostring(readoutAt) .. ", not 10")
assert(module.view.distance.text ~= readout, "the safeguard sample did not update the readout")
-- (b) A parent geometry change with no event, clamped: the first sample after the quiet second (tick 30 at 1/30 s)
-- reads the parent geometry (5 reads) and places the marker by the new geometry; skipped ticks place nothing.
Reset(true, 400)
Sample()
local placed = module.host.point
main.width = 700
local safeguardAt
for tick = 1, 30 do
    local d = Step(1 / 30)
    if d.paints > 0 then
        safeguardAt = tick
        assert(d.parent == 5, "the safeguard sample read the parent geometry " .. d.parent .. " times, not 5")
        break
    end
    assert(module.host.point == placed, "skipped tick " .. tick .. " placed the marker by the changed parent geometry")
end
assert(safeguardAt == 30, "the safeguard sample for the changed parent geometry is on tick " .. tostring(safeguardAt) .. ", not 30")
CheckFormula("the safeguard sample did not place the marker by the new parent geometry")
main.width = 1000

-- 6. Unsettled outcomes keep sampling on every due tick. A sample is counted by its distance read, which a failed
-- sample also makes (Navigation.Paint is not called then).
-- (a) An unreadable distance hides the marker; every due tick samples.
Reset(false, 400)
Sample()
world.distance = secret
Sample()
assert(not module.model.mode and not Settled(), "an unreadable distance left the marker settled")
for tick = 1, 20 do
    local d = Step(.1)
    assert(d.distance == (d.due and 1 or 0), "an unreadable distance: tick " .. tick .. " sampled " .. d.distance .. " times")
end
world.distance = 400
-- (b) A protected native marker in combat cannot be owned: every due tick samples.
Reset(false, 400)
-- A Corpse destination releases the native art (as the waypoint contract does); then the native marker is protected.
world.kind = Enum.SuperTrackingType.Corpse
Sample()
assert(not module.ownsArt, "probe: the native art was not released")
world.kind = Enum.SuperTrackingType.UserWaypoint
SuperTrackedFrame.IsProtected = function() return true end
combat = true
events.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
assert(not Settled(), "a protected marker in combat stayed settled")
for tick = 1, 20 do
    local d = Step(.1)
    assert(d.distance == (d.due and 1 or 0), "a protected marker in combat: tick " .. tick .. " sampled " .. d.distance .. " times")
end
combat = false
SuperTrackedFrame.IsProtected = nil
events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(Settled() and module.view.root:IsShown(), "the marker did not settle again after combat")
-- (c) An unreadable projection centre: every due tick samples.
Reset(false, 400)
Sample()
assert(Settled(), "probe: the marker did not settle before the unreadable centre")
proj.x = secret
for tick = 1, 20 do
    local d = Step(.1)
    assert(d.distance == (d.due and 1 or 0), "an unreadable projection centre: tick " .. tick .. " sampled " .. d.distance .. " times")
end
proj.x = 1400

-- 7. Events repaint at once and settle again; Disable clears the settle, Enable samples.
Reset(false, 400)
Sample()
for _ = 1, 3 do Step(.1) end
local a = Snap()
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
local repaint = Diff(a, Snap())
assert(repaint.paints == 1 and Settled(), "SUPER_TRACKING_CHANGED did not sample at once and settle")
for _ = 1, 3 do Step(.1) end
a = Snap()
module:Refresh()
repaint = Diff(a, Snap())
assert(repaint.paints == 1 and Settled(), "Module:Refresh did not sample at once and settle")
-- Refresh while the module is inactive runs no sample, so it must clear the settle itself.
Sample()
assert(Settled(), "probe: the marker did not settle before the inactive Refresh")
module.active = false
module:Refresh()
module.active = true
assert(module.settled == false, "Refresh while inactive left the marker settled")
module:Disable()
assert(module.settled == false, "Disable left the marker settled")
a = Snap()
module:Enable()
local enabled = Diff(a, Snap())
assert(enabled.paints == 1 and Settled(), "Enable did not take a sample that settles the marker")
assert(Ticking() and module.view.root:IsShown(), "Enable did not restart the marker")

-- 8. Hidden by mode: with the distance below hideDistance the marker is not shown.
-- Unsettled, every 0.25 s tick samples; settled, one sample in four due ticks.
Reset(false, 20)
module.config.hideDistance = 50
Sample()
assert(module.model.mode == nil, "a marker nearer than hideDistance is still shown")
events.PLAYER_STARTED_MOVING(module, "PLAYER_STARTED_MOVING")
assert(not Settled(), "probe: a moving player settled the hidden marker")
for tick = 1, 8 do
    local d = Step(.25)
    assert(d.due and d.paints == 1, "a hidden unsettled marker was not sampled on 0.25 s tick " .. tick)
end
events.PLAYER_STOPPED_MOVING(module, "PLAYER_STOPPED_MOVING")
assert(Step(.25).paints == 1 and Settled(), "probe: the hidden marker did not settle on the sample after the stop")
local hiddenSamples = {}
for tick = 1, 16 do
    local d = Step(.25)
    assert(d.due, "0.25 s tick " .. tick .. " was not a due tick")
    if d.paints > 0 then hiddenSamples[#hiddenSamples + 1] = tick end
end
assert(table.concat(hiddenSamples, ",") == "4,8,12,16", "settled hidden samples fell on " .. table.concat(hiddenSamples, ","))
assert(module.model.mode == nil, "the hidden marker was shown while settled")
module.config.hideDistance = 0

-- 10. An announced geometry change while settled: the very next tick is a full sample. It reads the new
-- geometry and places the marker by it; a skipped tick would place it one arrow tick late.
local side = { cx = 300, cy = 220, width = 500, height = 400, scale = .8 }
local panel = Frame(UIParent)
Bind(panel, side)
local function CheckPlacedBy(g, message)
    local x, y = Expected(proj, g)
    local px, py = module.host.point[4], module.host.point[5]
    assert(math.abs(px - x) < 1e-9 and math.abs(py - y) < 1e-9, message .. " (placed " .. px .. ", " .. py .. ")")
end
-- UI_SCALE_CHANGED: the UI scale is the placement's source scale, and the panel has a scale of its own, so it moves the marker.
Reset(true, 400)
module.host:SetParent(panel)
events.DISPLAY_SIZE_CHANGED(module, "DISPLAY_SIZE_CHANGED")
Sample()
assert(Settled() and module.host.point[2] == panel, "probe: the marker did not settle on the panel")
local oldX, oldY = Expected(proj, side)
main.scale = 1.1
local newX, newY = Expected(proj, side)
assert(math.abs(newX - oldX) + math.abs(newY - oldY) > 1, "probe: the UI scale change does not move the marker on the panel")
events.UI_SCALE_CHANGED(module, "UI_SCALE_CHANGED")
local beforeScale = module.host.point
local scaled = Step(.1)
assert(scaled.due and scaled.paints == 1 and scaled.distance == 1, "the tick after a UI_SCALE_CHANGED was not a full sample")
assert(scaled.parent == 5, "the tick after a UI_SCALE_CHANGED read the parent geometry " .. scaled.parent .. " times, not 5")
assert(module.host.point ~= beforeScale, "the tick after a UI_SCALE_CHANGED did not move the marker")
CheckPlacedBy(side, "the tick after a UI_SCALE_CHANGED did not place the marker by the new scale")
assert(Settled(), "the marker did not settle again after UI_SCALE_CHANGED")
assert(Step(.1).paints == 0, "the marker did not skip again after UI_SCALE_CHANGED")
main.scale = 1.25
-- DISPLAY_SIZE_CHANGED: the same check with the parent's own size changed.
Reset(true, 400)
Sample()
assert(Settled() and module.model.mode == navigation.DIRECTION, "probe: the clamped marker did not settle before the size change")
main.width = 700
events.DISPLAY_SIZE_CHANGED(module, "DISPLAY_SIZE_CHANGED")
local beforeSize = module.host.point
local sized = Step(.1)
assert(sized.due and sized.paints == 1 and sized.distance == 1, "the tick after a DISPLAY_SIZE_CHANGED was not a full sample")
assert(sized.parent == 5, "the tick after a DISPLAY_SIZE_CHANGED read the parent geometry " .. sized.parent .. " times, not 5")
assert(module.host.point ~= beforeSize, "the tick after a DISPLAY_SIZE_CHANGED did not move the marker")
CheckPlacedBy(main, "the tick after a DISPLAY_SIZE_CHANGED did not place the marker by the new size")
assert(Settled(), "the marker did not settle again after DISPLAY_SIZE_CHANGED")
assert(Step(.1).paints == 0, "the marker did not skip again after DISPLAY_SIZE_CHANGED")
main.width = 1000

-- 9. Budget, per settled second (2026-11-10, Lua 5.1). Exact sample and read counts; instructions with a count
-- hook every 100 instructions, 2% margin. Before (base, no settle; measured with the same code) -> after:
-- Per settled second, clamped 1/30 s: samples 10 -> 1, C_Navigation reads 40 -> 4, parent reads 5 -> 5,
-- projection reads 30 -> 31, instructions 8640 -> 5250.
-- Per settled second, on-screen 0.1 s: samples 10 -> 1, C_Navigation reads 40 -> 4, parent reads 0 -> 0,
-- projection reads 0 -> 10, instructions 4600 -> 1850.
-- Settled samples read the parent once per second (the safeguard), so parent reads stay 5 per second clamped.
-- 2026-11-11, the ticker: the instructions are the product's only (a hook on every instruction that counts while
-- a ticker callback runs), so they are not the numbers above. Same measure, frame script -> ticker: a settled
-- clamped second 5093 -> 4788, a settled on-screen second 1771 -> 1586. Samples and reads did not change.
local function Measure(dt, seconds)
    local ticks = math.floor(seconds / dt + .5)
    local a = Snap()
    local instructions = 0
    debug.sethook(function() if clock.inside then instructions = instructions + 1 end end, "", 1)
    for _ = 1, ticks do Advance(dt) end
    debug.sethook()
    local d = Diff(a, Snap())
    return { samples = d.paints / seconds, nav = d.nav / seconds, parent = d.parent / seconds,
        projection = d.projection / seconds, instructions = instructions / seconds }
end
Reset(true, 400)
Sample()
for _ = 1, 300 do Step(1 / 30) end
local perClamped = Measure(1 / 30, 10)
Reset(false, 400)
Sample()
for _ = 1, 100 do Step(.1) end
local perOnscreen = Measure(.1, 10)
print(("settle budget per settled second: clamped 1/30 samples %g nav %g parent %g projection %g instructions %g; "
    .. "on-screen 0.1 samples %g nav %g parent %g projection %g instructions %g"):format(
    perClamped.samples, perClamped.nav, perClamped.parent, perClamped.projection, perClamped.instructions,
    perOnscreen.samples, perOnscreen.nav, perOnscreen.parent, perOnscreen.projection, perOnscreen.instructions))
assert(perClamped.samples == 1 and perClamped.nav == 4 and perClamped.parent == 5 and perClamped.projection == 31,
    "a settled clamped second changed its sample or read counts")
assert(perClamped.instructions <= 4788 * 1.02, "a settled clamped second exceeds the instruction budget: " .. perClamped.instructions)
assert(perOnscreen.samples == 1 and perOnscreen.nav == 4 and perOnscreen.parent == 0 and perOnscreen.projection == 10,
    "a settled on-screen second changed its sample or read counts")
assert(perOnscreen.instructions <= 1586 * 1.02, "a settled on-screen second exceeds the instruction budget: " .. perOnscreen.instructions)

-- Allocation: no hook, GC stopped, after a warm-up, 3000 settled ticks of 0.1 s.
Reset(false, 400)
Sample()
for _ = 1, 3000 do Advance(.1) end
collectgarbage("collect")
collectgarbage("stop")
local memory = collectgarbage("count")
for _ = 1, 3000 do Advance(.1) end
local allocated = collectgarbage("count") - memory
collectgarbage("restart")
assert(allocated == 0, "3000 settled ticks allocated " .. allocated .. " KiB")
assert(Settled(), "the allocation run was not settled")
print(("settle allocation: %g KiB over 3000 settled ticks"):format(allocated))
print("PASS navigation settle: skipped samples on a still player, every event and trade checked")
