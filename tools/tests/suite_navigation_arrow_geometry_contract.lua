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
assert(module.view.root:IsShown() and SuperTrackedFrame.Icon:GetAlpha() == 0)
assert(taxi.enabled == 1 and taxi.refreshed > 0, "enabling navigation did not start the flight map markers")
-- 2026-11-10 (Lua 5.1): the parent geometry is read when it is announced
-- (UI_SCALE_CHANGED, DISPLAY_SIZE_CHANGED, Module:Refresh) and on every tenth
-- sample; an unmoved projection centre is not placed again. Before -> after
-- values are in the budget section.
local CADENCE = 10
local main = { cx = 640, cy = 360, width = 1000, height = 500, scale = 1.25 }
local side = { cx = 300, cy = 220, width = 500, height = 400, scale = .8 }
local far = { cx = 200, cy = 150, width = 800, height = 300, scale = .9 }
local proj = { x = 1400, y = 300 }
local reads = { parent = 0, host = 0, projection = 0 }
module.screen = module.screen or {}
local function Bind(frame, g)
    frame.GetCenter = function() reads.parent = reads.parent + 1 return g.cx, g.cy end
    frame.GetSize = function() reads.parent = reads.parent + 1 return g.width, g.height end
    frame.GetEffectiveScale = function() reads.parent = reads.parent + 1 return g.scale end
end
Bind(UIParent, main)
local panel = Frame(UIParent)
Bind(panel, side)
Bind(WorldFrame, far)
module.host.GetParent = function(self) reads.host = reads.host + 1 return self.parent end
SuperTrackedFrame.GetCenter = function() reads.projection = reads.projection + 1 return proj.x, proj.y end
local function Tick() Advance(1 / 30) end
local function Delta(fn)
    local parent, projection = reads.parent + reads.host, reads.projection
    fn()
    return reads.parent + reads.host - parent, reads.projection - projection
end
local function SyncToSample() repeat Tick() until Sampled() end
local function ArrowTick() repeat Tick() until not Sampled() end
-- The same comparison Tick makes for the next tick (Navigation.lua, ARROW_SAMPLE).
local function NextIsSample() return clock.now + 1 / 30 - module.sampledAt >= .09 end
-- A change the product announces: the handler it registered runs with the module.
local function Announce(name) events[name](module, name) end
-- The source scale is UIParent's, which is main.scale in this stub.
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
local function Angle(p, g)
    local x, y = Coordinates(p, g)
    return -math.atan2(x, y)
end
local function Check(x, y, message)
    local px, py = module.host.point[4], module.host.point[5]
    assert(math.abs(px - x) < 1e-9 and math.abs(py - y) < 1e-9, message .. " (placed " .. px .. ", " .. py .. ")")
end
local function CheckFormula(p, g, message)
    local x, y = Expected(p, g)
    Check(x, y, message)
end
-- Counts the arc tangents (one per placement formula) made while fn runs.
local function CountAtan2(fn)
    local calls, real = 0, math.atan2
    math.atan2 = function(...) calls = calls + 1 return real(...) end
    fn()
    math.atan2 = real
    return calls
end
-- Counts the anchor writes made while fn runs.
local function CountPlacements(fn)
    local count, real = 0, module.host.SetPoint
    module.host.SetPoint = function(...) count = count + 1 return real(...) end
    fn()
    module.host.SetPoint = real
    return count
end
local function NoSecretStored(label)
    for field, value in pairs(module.screen) do
        assert(value ~= secret, label .. ": a secret was stored in the cached geometry: " .. field)
    end
end
local function Show()
    events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
    assert(module.view.root:IsShown() and module.model.mode == navigation.DIRECTION, "the marker did not show the direction arrow")
end

world.clamped = true
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
assert(module.model.mode == navigation.DIRECTION, "the off-screen destination is not a direction arrow")
-- The geometry events must reach the module in combat as well.
assert(alwaysRuns.UI_SCALE_CHANGED == true, "UI_SCALE_CHANGED is not registered to run in combat")
assert(alwaysRuns.DISPLAY_SIZE_CHANGED == true, "DISPLAY_SIZE_CHANGED is not registered to run in combat")

-- 1: an arrow tick between samples reads no parent geometry and the projection
-- once. A due sample reads the projection once, and the parent geometry (five
-- reads) only on a cadence tick: the sample after a read leaves age 0.
local arrowTicks, sampleTicks = 0, 0
for _ = 1, 30 do
    local parent, projection = Delta(Tick)
    if Sampled() then
        sampleTicks = sampleTicks + 1
        local read = module.screen.age == 0
        assert(parent == (read and 5 or 0), "a sample tick read the parent geometry " .. parent .. " times, not " .. (read and 5 or 0))
        assert(projection == 1, "a sample tick read the projection GetCenter " .. projection .. " times, not 1")
    else
        arrowTicks = arrowTicks + 1
        assert(parent == 0, "an arrow tick that is not a sample read the parent geometry " .. parent .. " times, not 0")
        assert(projection == 1, "an arrow tick that is not a sample read the projection GetCenter " .. projection .. " times, not 1")
    end
end
assert(arrowTicks > 0 and sampleTicks > 0, "the ticks did not mix arrow ticks and samples")

-- 1b (cadence): after a fresh refresh, 30 consecutive samples read the parent
-- geometry on samples 10, 20 and 30 only: 15 parent reads.
module:Refresh()
local readSamples, samples, parentReads = {}, 0, 0
while samples < 30 do
    local parent = Delta(Tick)
    if Sampled() then
        samples = samples + 1
        if parent > 0 then
            readSamples[#readSamples + 1] = samples
            parentReads = parentReads + parent
        end
    end
end
assert(table.concat(readSamples, ",") == "10,20,30", "the parent geometry was read on samples " .. table.concat(readSamples, ",") .. ", not 10,20,30")
assert(parentReads == 15, "30 samples read the parent geometry " .. parentReads .. " times, not 15")

-- 3 and 6: the anchor offset and the arrow angle equal the original formula for
-- several projection centres, with a UI scale other than 1 and a parent centre
-- other than 500, 300.
for _, p in ipairs({ { 1400, 300 }, { 100, 700 }, { 900, 120 }, { 1200, 650 } }) do
    proj.x, proj.y = p[1], p[2]
    ArrowTick()
    local x, y = Expected(proj, main)
    Check(x, y, "an arrow tick at " .. p[1] .. ", " .. p[2] .. " placed the marker away from the formula")
    assert(math.abs(module.model.angle - Angle(proj, main)) < 1e-9, "an arrow tick at " .. p[1] .. ", " .. p[2] .. " turned the arrow away from the formula")
end
-- The same formula with a parent of its own scale and centre (the host's parent is UIParent in
-- normal use, so the scales above are equal; this checks the two scale terms separately). A
-- parent switch has no event of its own; the announcement stands in for the re-read it causes.
module.host:SetParent(panel)
Announce("DISPLAY_SIZE_CHANGED")
SyncToSample()
assert(module.host.point[2] == panel, "the sample did not anchor to the parent it was given")
CheckFormula(proj, side, "a parent with its own scale and centre did not use its own geometry")
module.host:SetParent(UIParent)
module:Refresh()

-- 4: an unannounced parent geometry change is not used before the tenth sample
-- after the last read, and is used from it on.
module:Refresh()
local old = { cx = main.cx, cy = main.cy, width = main.width, height = main.height, scale = main.scale }
main.width, main.cx = 600, 500
proj.x, proj.y = 1000, 520
local oldX, oldY = Expected(proj, old)
local newX, newY = Expected(proj, main)
assert(math.abs(oldX - newX) + math.abs(oldY - newY) > 1, "the parent geometry change does not move the marker")
samples = 0
local readAt
while not readAt do
    local parent = Delta(Tick)
    if Sampled() then
        samples = samples + 1
        if parent > 0 then
            assert(parent == 5, "the read of the changed geometry took " .. parent .. " parent reads, not 5")
            readAt = samples
            Check(newX, newY, "the tenth sample did not use the changed parent geometry")
        else
            Check(oldX, oldY, "sample " .. samples .. " used the unannounced parent geometry change")
        end
    else
        Check(oldX, oldY, "an arrow tick used the unannounced parent geometry change")
    end
end
assert(readAt == CADENCE, "the unannounced change was read at sample " .. readAt .. ", not " .. CADENCE)
main.width, main.cx = 1000, 640
module:Refresh()

-- 5: unreadable parent geometry, announced. The read happens at the next
-- placement; the sample that reads it hides the marker and places nothing.
main.width = secret
Announce("DISPLAY_SIZE_CHANGED")
SyncToSample()
assert(not module.view.root:IsShown() and not module.model.mode, "unreadable parent geometry kept the marker shown")
assert(module.screen.valid == false, "unreadable parent geometry left the cached geometry marked valid")
NoSecretStored("unreadable parent width")
assert(CountPlacements(function() for _ = 1, 9 do Tick() end end) == 0, "arrow ticks placed a marker whose parent geometry could not be read")
main.width = 1000
Announce("DISPLAY_SIZE_CHANGED")
Show()

-- 5b: a parent switch made while the module is inactive. Refresh invalidates the
-- cached geometry without a paint, so the next arrow tick reads the new parent.
SyncToSample()
module.active, module.config.showWithHiddenUI = false, true
assert(Delta(function() module:Refresh() end) == 0, "Refresh without a sample read the parent geometry")
assert(module.host.parent == WorldFrame, "the host was not reparented to WorldFrame")
proj.x, proj.y = 900, 120
-- Only an active module is ticked.
module.active = true
local parent, projection = Delta(Tick)
assert(not Sampled() and projection == 1, "probe: the tick after the switch is not an arrow tick")
assert(parent == 5, "the arrow tick after a parent switch read the parent geometry " .. parent .. " times, not 5")
assert(module.host.point[2] == WorldFrame, "an arrow tick after a parent switch anchored to the old parent")
local farX, farY = Expected(proj, far)
Check(farX, farY, "an arrow tick after a parent switch used the old parent geometry")
parent = Delta(Tick)
assert(parent == 0 and not Sampled(), "a second arrow tick after a parent switch read the geometry again")
module.active, module.config.showWithHiddenUI = true, false
module:Refresh()
assert(module.host.parent == UIParent and module.view.root:IsShown(), "the marker did not return to UIParent")

-- 5c: each parent value unreadable or out of range hides the marker at the next
-- sample and stores nothing unvalidated. The parent is WorldFrame. Each change
-- is announced, as the product would do it, so the sample reads it.
module.config.showWithHiddenUI = true
module:Refresh()
local cases = { { "cx", secret }, { "cy", secret }, { "scale", secret }, { "scale", 0 }, { "scale", -1 },
    { "width", secret }, { "height", secret }, { "width", 0 }, { "height", 0 }, { "width", -5 }, { "height", -1 },
    { "cx", 0 / 0 }, { "scale", math.huge } }
for _, case in ipairs(cases) do
    local key, bad = case[1], case[2]
    local label = "parent " .. key .. " " .. tostring(bad == secret and "secret" or bad)
    assert(module.host.point[2] == WorldFrame and module.view.root:IsShown(), "probe: not anchored to a shown WorldFrame marker")
    local keep = far[key]
    far[key] = bad
    Announce("DISPLAY_SIZE_CHANGED")
    local placements = CountPlacements(SyncToSample)
    far[key] = keep
    assert(not module.view.root:IsShown() and not module.model.mode, label .. " kept the marker shown")
    assert(module.screen.valid == false, label .. " left the cached geometry marked valid")
    assert(placements == 0, label .. " placed the marker")
    NoSecretStored(label)
    Announce("DISPLAY_SIZE_CHANGED")
    Show()
end
module.config.showWithHiddenUI = false
module:Refresh()
Show()

-- 5d: an unreadable projection centre. An arrow tick places nothing; a sample hides the marker.
SyncToSample()
local placedX, placedY = module.host.point[4], module.host.point[5]
proj.x = secret
assert(CountPlacements(Tick) == 0 and not Sampled(), "an arrow tick with an unreadable projection centre placed the marker")
assert(module.view.root:IsShown() and module.host.point[4] == placedX and module.host.point[5] == placedY,
    "an arrow tick with an unreadable projection centre moved the marker")
SyncToSample()
assert(not module.view.root:IsShown() and not module.model.mode, "an unreadable projection centre kept the marker shown")
NoSecretStored("unreadable projection centre")
-- 5e: the native art is not owned (the failed sample gave it back). Unreadable
-- samples take nothing over: no native alpha write, and the regions stay at 1.
assert(module.ownsArt == false, "probe: the native art is still owned after a failed sample")
local alphaWrites, wrapped = 0, {}
for _, key in ipairs({ "Icon", "Arrow", "DistanceText", "IconBorder" }) do
    local region = SuperTrackedFrame[key]
    local real = region.SetAlpha
    wrapped[#wrapped + 1] = region
    region.SetAlpha = function(self, alpha) alphaWrites = alphaWrites + 1 return real(self, alpha) end
end
for _ = 1, 10 do SyncToSample() end
for _, region in ipairs(wrapped) do region.SetAlpha = nil end
assert(alphaWrites == 0, "unreadable samples wrote the native alpha " .. alphaWrites .. " times, not 0")
for _, key in ipairs({ "Icon", "Arrow", "DistanceText", "IconBorder" }) do
    assert(SuperTrackedFrame[key]:GetAlpha() == 1, "unreadable samples left the native " .. key .. " at alpha " .. SuperTrackedFrame[key]:GetAlpha())
end
proj.x = 1400
Show()

-- R2: a due sample resets the arrow timer. Ten seconds of 1/144 ticks after a fresh
-- refresh read the projection once per arrow tick and once per sample; without the
-- reset an arrow tick would also fire on the frame after every sample.
Show()
local projectionBefore = reads.projection
for _ = 1, 1440 do Advance(1 / 144) end
local timerReads = reads.projection - projectionBefore
assert(timerReads == 288, "ten seconds of 1/144 ticks read the projection GetCenter " .. timerReads .. " times, not 288")

-- 7: the flow is back in its normal state (UIParent, main geometry).
assert(module.host.parent == UIParent and module.view.root:IsShown())

-- B: announced changes are read at the next placement, and the host follows the new geometry.
assert(events.UI_SCALE_CHANGED and events.DISPLAY_SIZE_CHANGED, "the module does not listen for the UI scale and the display size")
-- A UI scale change moves the marker only when the parent has a scale of its own
-- (with UIParent as parent the source and parent scales cancel), so this part
-- uses the side panel as the parent.
module.host:SetParent(panel)
Announce("DISPLAY_SIZE_CHANGED")
SyncToSample()
local beforeX, beforeY = Expected(proj, side)
main.scale = 1.1
Announce("UI_SCALE_CHANGED")
local readParent, readProjection = Delta(Tick)
assert(readParent == 5 and readProjection == 1, "the next tick after a UI scale change read the parent geometry " .. readParent .. " times, not 5")
local newX, newY = Expected(proj, side)
assert(math.abs(newX - beforeX) + math.abs(newY - beforeY) > 1, "probe: the UI scale change does not move the marker on the panel")
CheckFormula(proj, side, "the next tick after a UI scale change did not use the new scale")
main.scale = 1.25
module.host:SetParent(UIParent)
Announce("DISPLAY_SIZE_CHANGED")
SyncToSample()
main.width = 700
Announce("DISPLAY_SIZE_CHANGED")
readParent = Delta(Tick)
assert(readParent == 5, "the next tick after a display size change read the parent geometry " .. readParent .. " times, not 5")
CheckFormula(proj, main, "the next tick after a display size change did not use the new size")
main.width = 1000
Announce("DISPLAY_SIZE_CHANGED")
Show()

-- C (memo): an unmoved projection centre costs one projection read on an arrow
-- tick: no parent read, no anchor write, the same angle.
SyncToSample()
local angle, placedPoint = module.model.angle, module.host.point
local parent, projection
local count, formulas = 0, 0
formulas = CountAtan2(function() count = CountPlacements(function() parent, projection = Delta(Tick) end) end)
assert(not Sampled() and parent == 0 and projection == 1,
    "an unmoved projection centre read " .. parent .. " parent and " .. projection .. " projection values, not 0 and 1")
assert(formulas == 0, "an unmoved projection centre recomputed the placement formula " .. formulas .. " times, not 0")
assert(count == 0 and module.host.point == placedPoint, "an unmoved projection centre placed the marker again")
assert(module.model.angle == angle, "an unmoved projection centre changed the angle")
local original = { x = proj.x, y = proj.y }
-- A move of 100 is placed and the angle follows.
SyncToSample()
proj.x = proj.x + 100
count = CountPlacements(function() parent, projection = Delta(Tick) end)
assert(not Sampled() and parent == 0 and projection == 1, "a moved projection centre read the parent geometry on an arrow tick")
assert(count == 1, "a projection move of 100 placed the marker " .. count .. " times, not 1")
CheckFormula(proj, main, "a projection move of 100 did not place the marker by the formula")
assert(math.abs(module.model.angle - Angle(proj, main)) < 1e-9, "a projection move of 100 did not update the angle")
-- Moving back places it back: the memo holds only the last input.
SyncToSample()
proj.x, proj.y = original.x, original.y
CountPlacements(function() Delta(Tick) end)
CheckFormula(proj, main, "moving the projection centre back did not place the marker back")
-- A move smaller than the 0.25 anchor threshold: the angle follows, the host does not move.
SyncToSample()
placedPoint = module.host.point
local smallAngle = module.model.angle
proj.x = proj.x + .05
count = CountPlacements(function() Delta(Tick) end)
assert(count == 0 and module.host.point == placedPoint, "a projection move under the anchor threshold moved the host")
assert(module.model.angle ~= smallAngle and math.abs(module.model.angle - Angle(proj, main)) < 1e-9,
    "a projection move under the anchor threshold did not update the angle")
proj.x, proj.y = original.x, original.y
SyncToSample()
CheckFormula(proj, main, "the marker did not return to the original projection centre")

-- C2: a move of the y coordinate alone is placed too (the memo compares both).
SyncToSample()
proj.y = proj.y + 100
count = CountPlacements(function() parent, projection = Delta(Tick) end)
assert(not Sampled() and parent == 0 and projection == 1 and count == 1, "a move of the y coordinate alone was not placed on the arrow tick")
CheckFormula(proj, main, "a move of the y coordinate alone did not place the marker by the formula")
assert(math.abs(module.model.angle - Angle(proj, main)) < 1e-9, "a move of the y coordinate alone did not update the angle")
proj.y = original.y
SyncToSample()
CheckFormula(proj, main, "the marker did not return after the y coordinate move")

-- S2: a move of 0.001 is not taken as unchanged: the angle follows the formula.
SyncToSample()
local beforeAngle = module.model.angle
proj.x = proj.x + .001
local tinyTick = Delta(Tick)
assert(not Sampled() and tinyTick == 0, "probe: the tiny move was not an arrow tick")
assert(module.model.angle ~= beforeAngle, "a move of 0.001 left the arrow angle unchanged")
assert(math.abs(module.model.angle - Angle(proj, main)) < 1e-9, "a move of 0.001 did not set the arrow angle by the formula")
proj.x = original.x
SyncToSample()
CheckFormula(proj, main, "the marker did not return after the 0.001 move")

-- E: the memo does not survive the on-screen path, which anchors the host to the
-- projection centre itself; back on the clamped path the same centre is placed again.
SyncToSample()
world.clamped = false
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
assert(module.model.mode == navigation.WAYPOINT and module.host.point[2] == SuperTrackedFrame, "the on-screen path did not anchor to the projection centre")
world.clamped = true
Show()
assert(module.host.point[2] == UIParent, "the clamped path after the on-screen path did not anchor to the parent again")
CheckFormula(proj, main, "the clamped path after the on-screen path did not place the marker by the formula")

-- F: a projection centre exactly on the parent centre has no direction (divisor 0):
-- the marker hides, and that centre is not remembered, so the same centre hides
-- again on the next samples and no anchor is written.
SyncToSample()
assert(module.view.root:IsShown() and module.ownsArt, "probe: the marker does not own the art before the centre case")
local away = { x = proj.x, y = proj.y }
proj.x, proj.y = main.cx, main.cy
SyncToSample()
assert(not module.view.root:IsShown() and not module.model.valid, "a projection centre on the parent centre kept the marker shown")
for round = 2, 3 do
    local placements = CountPlacements(SyncToSample)
    assert(not module.view.root:IsShown() and not module.model.valid and placements == 0,
        "sample " .. round .. " with the projection centre on the parent centre showed or placed the marker")
end
proj.x, proj.y = away.x, away.y
SyncToSample()
assert(module.view.root:IsShown() and module.model.mode == navigation.DIRECTION, "the marker did not show again once the centre moved away")
CheckFormula(proj, main, "the marker did not return by the formula once the centre moved away from the parent centre")

-- D: the memo is dropped when an input other than the projection centre changes.
local navigatorX = module.config.navigatorX
module.config.navigatorX = navigatorX + 20
module:Refresh()
SyncToSample()
CheckFormula(proj, main, "a changed navigator offset was not placed at the next sample")
module.config.navigatorX = navigatorX
module:Refresh()
SyncToSample()
CheckFormula(proj, main, "restoring the navigator offset did not place the marker back")
-- After an announced geometry change an arrow tick with an unmoved projection re-places the host.
SyncToSample()
local beforeX, beforeY = Expected(proj, main)
main.width = 700
Announce("DISPLAY_SIZE_CHANGED")
parent, projection = Delta(Tick)
assert(not Sampled() and parent == 5 and projection == 1, "the arrow tick after an announced change read " .. parent .. " parent values, not 5")
local newPlacedX, newPlacedY = Expected(proj, main)
assert(math.abs(newPlacedX - beforeX) + math.abs(newPlacedY - beforeY) > 1, "probe: the size change does not move the marker")
CheckFormula(proj, main, "an arrow tick with an unmoved projection did not re-place the marker after a size change")
main.width = 1000
Announce("DISPLAY_SIZE_CHANGED")
Show()

-- 8: budget. Native calls are exact counts. The steady-tick instructions use a
-- count hook every 100 instructions, like the existing contract; single ticks use a
-- count hook on every instruction. Allocation is measured without any hook.
-- Limits are the measured values of this package, with the 1.02 margin in the asserts.
-- 2026-11-11, the ticker: a client ticker at the marker's pace replaced the frame
-- script, and the instruction counts below are the product's only: a hook on every
-- instruction that counts while a ticker callback runs (clock.inside), so the frame
-- clock of this test is left out. They are not the numbers of the list below, which
-- included the test's own call. Same measure, frame script -> ticker:
--   3000 steady ticks 795200 -> 768200; one arrow tick unmoved 147 -> 136, moving 243 -> 232;
--   one clamped sample without a geometry read 470 -> 465, with a read 782 -> 777;
--   one on-screen sample 400 -> 385; a three-tick cycle 795.2 -> 768.2. The reads did not change.
-- What the frame script cost in the frames between two ticks (two additions and two
-- comparisons, 120 times a second at 120 frames per second) is gone and is not in these numbers.
-- Accepted trades: at the arrow's pace every tick reads the clock (GetTime, one client call,
-- 30 a second), which keeps the frame script's sample cadence at 30 frames per second and below.
-- Above that a sample falls on a tick of the ticker, so where 1/30 s is not a whole number of
-- frames the marker is sampled and placed up to a sixth less often (the pause contract, section 4).
-- A change of pace makes one client ticker object.
-- 2026-11-10, Lua 5.1. Columns: before (pristine original code) -> previous package ->
-- this package. This package: the parent geometry is read when announced
-- (UI_SCALE_CHANGED, DISPLAY_SIZE_CHANGED, Module:Refresh) and on every tenth sample;
-- an unmoved projection centre is not placed again; the art is taken over only after
-- the marker is placed, so an unreadable position writes no native alpha (0 writes,
-- as before the change).
--   3000 steady ticks (2000 arrow ticks, 1000 samples, projection unmoved):
--       instructions 2020800 -> 1213500 -> 849100 (hook every 100)
--       parent geometry reads 20000 -> 5000 -> 500 (exact); projection reads 4000 -> 3000 -> 3000 (exact)
--       allocation 0 KiB -> 0 KiB -> 0 KiB (no hook, GC stopped, after a warm-up)
--   one arrow tick, unmoved projection: instructions 413 -> 198 -> 149; parent reads 5 -> 0 -> 0; projection 1 -> 1 -> 1
--   one arrow tick, moving projection: instructions 413 -> 233 -> 245; parent reads 5 -> 0 -> 0; projection 1 -> 1 -> 1
--   one clamped sample without a geometry read: instructions 1120 -> (every sample read) -> 492; parent reads 10 -> 5 -> 0; projection 2 -> 1 -> 1
--   one clamped sample with a geometry read: instructions 1120 -> 775 -> 804; parent reads 10 -> 5 -> 5; projection 2 -> 1 -> 1
--   one on-screen sample tick: instructions 420 -> 414 -> 423
--   a three-tick cycle (2 unmoved arrow ticks + 1 clamped sample, averaged over reads): 1946 -> 1171 -> 821.2
--   settling (skip samples while nothing moves) costs a moving player's sample 483 -> 492 (clamped, no read),
--       795 -> 804 (clamped, with read), 414 -> 423 (on-screen), no native call
-- Accepted trade: an unannounced geometry change is used after at most CADENCE
-- samples that place the direction arrow (about a second at 10 frames per second
-- or more, longer below); samples that place nothing do not count, and while
-- unannounced unreadable geometry lasts less than that it no longer hides the
-- marker. The announced changes are used at the next placement.
local MIX_INSTRUCTIONS, ARROW_UNMOVED, ARROW_MOVED = 768200, 136, 232
local SAMPLE_NOREAD, SAMPLE_READ, ONSCREEN, CYCLE = 465, 777, 385, 768.2
local instructions = 0
local function Counted() if clock.inside then instructions = instructions + 1 end end
local count = 0
local function Exact() if clock.inside then count = count + 1 end end
local function Measure(tickFn)
    debug.sethook(Exact, "", 1)
    tickFn()
    debug.sethook()
end
proj.x, proj.y = 1000, 520
SyncToSample()
for _ = 1, 3000 do Tick() end
local parentBefore, projectionBefore = reads.parent + reads.host, reads.projection
debug.sethook(Counted, "", 1)
for _ = 1, 3000 do Tick() end
debug.sethook()
local parentTotal = reads.parent + reads.host - parentBefore
local projectionTotal = reads.projection - projectionBefore
assert(parentTotal == 500, "3000 steady ticks read the parent geometry " .. parentTotal .. " times, not 500")
assert(projectionTotal == 3000, "3000 steady ticks read the projection GetCenter " .. projectionTotal .. " times, not 3000")
assert(instructions <= MIX_INSTRUCTIONS * 1.02, "3000 steady ticks exceed the instruction budget: " .. instructions)

-- Allocation: no hook, GC stopped, after a warm-up.
SyncToSample()
for _ = 1, 3000 do Tick() end
collectgarbage("collect")
collectgarbage("stop")
local memory = collectgarbage("count")
for _ = 1, 3000 do Tick() end
local allocated = collectgarbage("count") - memory
collectgarbage("restart")
assert(allocated == 0, "steady ticks allocated " .. allocated .. " KiB")

-- Single ticks, exact instruction counts.
count = 0
local unmovedInstructions, unmovedParent, unmovedProjection = 0, 0, 0
for _ = 1, 1000 do
    SyncToSample()
    count = 0
    local p, q = reads.parent + reads.host, reads.projection
    Measure(Tick)
    unmovedInstructions = unmovedInstructions + count
    unmovedParent = unmovedParent + reads.parent + reads.host - p
    unmovedProjection = unmovedProjection + reads.projection - q
end
assert(unmovedParent == 0 and unmovedProjection == 1000,
    "unmoved arrow ticks read " .. unmovedParent .. " parent and " .. unmovedProjection .. " projection values")
local movedInstructions, movedParent, movedProjection = 0, 0, 0
for i = 1, 1000 do
    SyncToSample()
    proj.x = proj.x + (i % 2 == 0 and 100 or -100)
    count = 0
    local p, q = reads.parent + reads.host, reads.projection
    Measure(Tick)
    movedInstructions = movedInstructions + count
    movedParent = movedParent + reads.parent + reads.host - p
    movedProjection = movedProjection + reads.projection - q
end
assert(movedParent == 0 and movedProjection == 1000, "moved arrow ticks read " .. movedParent .. " parent and " .. movedProjection .. " projection values")
proj.x, proj.y = 1000, 520
local readInstructions, noReadInstructions, readCount, noReadCount = 0, 0, 0, 0
for _ = 1, 1000 do
    while not NextIsSample() do Tick() end
    count = 0
    local p = reads.parent + reads.host
    Measure(Tick)
    if reads.parent + reads.host - p > 0 then
        readInstructions, readCount = readInstructions + count, readCount + 1
    else
        noReadInstructions, noReadCount = noReadInstructions + count, noReadCount + 1
    end
end
assert(readCount == 100 and noReadCount == 900, "1000 samples read the geometry " .. readCount .. " times, not 100")
world.clamped = false
events.SUPER_TRACKING_CHANGED(module, "SUPER_TRACKING_CHANGED")
assert(module.model.mode == navigation.WAYPOINT, "the on-screen destination is not a waypoint marker")
local onscreen = 0
-- On screen the ticker runs at the sample interval: every 0.1 s frame is a sample.
local function SampleFrame() Advance(.1) end
for _ = 1, 1000 do
    count = 0
    Measure(SampleFrame)
    assert(Sampled(), "probe: a 0.1 s frame on screen was not a sample")
    onscreen = onscreen + count
end
world.clamped = true
Show()
local arrowUnmoved, arrowMoved = unmovedInstructions / 1000, movedInstructions / 1000
local sampleNoRead, sampleRead = noReadInstructions / noReadCount, readInstructions / readCount
local sampleAverage = (noReadInstructions + readInstructions) / 1000
assert(arrowUnmoved <= ARROW_UNMOVED * 1.02, "an unmoved arrow tick exceeds the budget: " .. arrowUnmoved)
assert(arrowMoved <= ARROW_MOVED * 1.02, "a moved arrow tick exceeds the budget: " .. arrowMoved)
assert(sampleNoRead <= SAMPLE_NOREAD * 1.02, "a clamped sample without a read exceeds the budget: " .. sampleNoRead)
assert(sampleRead <= SAMPLE_READ * 1.02, "a clamped sample with a read exceeds the budget: " .. sampleRead)
assert(onscreen / 1000 <= ONSCREEN * 1.02, "an on-screen sample tick exceeds the budget: " .. onscreen / 1000)
local cycle = 2 * arrowUnmoved + sampleAverage
assert(cycle <= CYCLE * 1.02, "a three-tick cycle exceeds the budget: " .. cycle)
print(("arrow geometry: %d instructions / 3000 steady ticks, %d parent reads and %d projection reads, %d KiB allocated")
    :format(instructions, parentTotal, projectionTotal, allocated))
print(("arrow geometry: per tick %.3f arrow unmoved, %.3f arrow moved, %.3f clamped sample without a read, %.3f with a read, %.3f on-screen sample; cycle %.3f")
    :format(arrowUnmoved, arrowMoved, sampleNoRead, sampleRead, onscreen / 1000, cycle))
print("PASS navigation arrow geometry: announced geometry, cadence reads, unmoved projection not placed again")
