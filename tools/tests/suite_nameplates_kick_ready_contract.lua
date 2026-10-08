-- Interrupt readiness on enemy nameplate castbars (MSUF_Suite_Nameplates/
-- KickReady.lua), driven end to end by Classic MSUF's real engine
-- (Castbars/MSUF_InterruptReady.lua, handed out by MSUF_HostAPI.GetKickReady)
-- through the Suite's real HostBridge. MSUF owns the switch and the look:
-- its profile (MSUF_DB.general) decides whether nameplates show readiness and
-- how - castbar border at MSUF's outline width, color box at MSUF's size and
-- placement, or MSUF's castbar texture in MSUF's cast colors - plus MSUF's
-- time marker and shade, exactly as MSUF's castbars draw them. Off, or on a
-- host without the engine, nothing is created on Blizzard's castbar.
-- Restricted readiness, interruptibility and times only reach native sinks:
-- a Lua read of a secret raises here, and a compare or truth test on one in
-- KickReady.lua is recorded.
local root = assert(arg[1], "repository root required")
local classic = root .. "/../MidnightSimpleUnitFrames-Classic/MidnightSimpleUnitFrames"

------------------------------------------------------------------ secrets
-- Classic MSUF's strict helper: type() answers a secret's kind,
-- issecretvalue() knows it, any read raises, and Watch records each line that
-- compares, negates or boolean-tests a secret (which the client raises on).
local Secrets = assert(loadfile(classic .. "/../tools/tests/classpower_secrets.lua"))()
Secrets.Install()
-- The Suite reads secrets through S.Public (false while its operand is secret).
Secrets.GUARD_NAMES.falsy.Public = true
local revealed = setmetatable({}, { __mode = "k" })
local function Secret(value)
    local box = Secrets.New(type(value))
    revealed[box] = value
    return box
end
-- What the client's native sinks see.
local function Reveal(value)
    if issecretvalue(value) then return revealed[value] end
    return value
end

------------------------------------------------------------------ client
local frameStamp = 100
GetTime = function() return frameStamp end
CreateColor = function(r, g, b, a)
    return { r = r, g = g, b = b, a = a, GetRGBA = function() return r, g, b, a end }
end
C_CurveUtil = {
    EvaluateColorFromBoolean = function(value, ifTrue, ifFalse)
        if Reveal(value) then return ifTrue end
        return ifFalse
    end,
    EvaluateColorValueFromBoolean = function(value, ifTrue, ifFalse)
        if Reveal(value) then return ifTrue end
        return ifFalse
    end,
}
C_Timer = { After = function() end }
UnitClass = function() return "Mage", "MAGE" end
C_SpecializationInfo = { GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return 62 end }
-- The real engine tracks only learned interrupts; this mage knows Counterspell.
local COUNTERSPELL = 2139
C_SpellBook = { IsSpellKnownOrInSpellBook = function(spellID) return spellID == COUNTERSPELL end }
-- MSUF's profile with every castbar indicator off and its defaults otherwise.
local general = { kickReadyShowTarget = false, kickReadyShowFocus = false, kickReadyShowBoss = false,
    kickReadyShowArena = false, enableFocusKickIcon = false, kickReadyShowNameplates = false,
    kickReadyStyle = "border", kickReadyColor = { ["1"] = 0, ["2"] = 1, ["3"] = 0 },
    kickNotReadyColor = { ["1"] = 1, ["2"] = 0, ["3"] = 0 }, kickReadyAnchor = "RIGHT",
    kickReadyOffsetX = 4, kickReadyOffsetY = 0, kickReadySize = 8 }
MSUF_DB = { general = general }
MSUF_EnsureDB = function() end
MSUF_ApplyCastbarOutline = function() end
NamePlateSetupOptions = { castBarHeight = 12 }
-- Blizzard's pixel rule (SharedXML PixelUtil) on a 1080-pixel-high screen.
local PIXEL = 768 / 1080
PixelUtil = { GetNearestPixelSize = function(size, scale, minPixels)
    local pixels = math.floor(size * scale / PIXEL + .5)
    if minPixels and pixels < minPixels then pixels = minPixels end
    return pixels * PIXEL / scale
end }

local counterspell = { remaining = 5, endTime = 15 }
function counterspell.GetRemainingDuration() return counterspell.remaining end
function counterspell.IsZero() return counterspell.zero end
function counterspell.GetEndTime() return counterspell.endTime end
C_Spell = { GetSpellCooldownDuration = function(spellID)
    assert(spellID == COUNTERSPELL, "only Counterspell is tracked for a mage")
    return counterspell
end }

-- The plate unit's cast as the duration and info getters report it.
local unitCast = { kind = nil, notInterruptible = false, duration = nil }
local function Duration(startTime, endTime)
    return { GetStartTime = function() return startTime end, GetEndTime = function() return endTime end }
end
UnitCastingDuration = function(unit)
    assert(unit == "nameplate1")
    if unitCast.kind == "cast" then return unitCast.duration end
end
UnitChannelDuration = function(unit)
    assert(unit == "nameplate1")
    if unitCast.kind == "channel" or unitCast.kind == "empower" then return unitCast.duration end
end
UnitEmpoweredChannelDuration = function(unit)
    assert(unit == "nameplate1")
    if unitCast.kind == "empower" then return unitCast.empowerDuration end
end
UnitCastingInfo = function()
    if unitCast.kind ~= "cast" then return nil end
    return "Bolt", "", 1, 10000, 13000, false, 7, unitCast.notInterruptible, 1234
end
UnitChannelInfo = function()
    if unitCast.kind ~= "channel" and unitCast.kind ~= "empower" then return nil end
    local empowered = unitCast.kind == "empower"
    if unitCast.secretEmpowered then empowered = Secret(empowered) end
    return "Beam", "", 1, 10000, 13000, false, unitCast.notInterruptible, 1234, empowered, 0
end

------------------------------------------------------------------ regions
local created = 0
local function Region(kind)
    local region = { kind = kind, shown = false, alpha = 1, points = {} }
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetShown(shown) self.shown = shown and true or false end
    function region:IsShown() return self.shown end
    function region:ClearAllPoints() self.points, self.allPoints = {}, nil end
    function region:SetPoint(point, relative, relativePoint, x, y)
        self.points[#self.points + 1] = { point, relative, relativePoint, x, y }
    end
    function region:SetAllPoints(target) self.allPoints = target end
    function region:SetWidth(width) self.width = width end
    function region:SetHeight(height) self.height = height end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function region:SetTexture(texture) self.texture = texture end
    function region:AddMaskTexture(mask) self.mask = mask end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:SetAlphaFromBoolean(value, ifTrue, ifFalse)
        if Reveal(value) then self.alpha = ifTrue else self.alpha = ifFalse end
    end
    function region:SetVertexColor(r, g, b, a)
        self.vertex = { Reveal(r), Reveal(g), Reveal(b), Reveal(a) }
    end
    function region:SetVertexColorFromBoolean(value, ifTrue, ifFalse)
        assert(type(value) == "boolean" or issecretvalue(value), "a native boolean sink needs a boolean")
        assert(ifTrue and ifFalse, "a native boolean sink needs two colors")
        if Reveal(value) then self.vertex = ifTrue else self.vertex = ifFalse end
    end
    return region
end

local fillTexture = Region("native fill")
local cast = Region("cast")
function cast:CreateTexture(_, layer, _, sublevel)
    created = created + 1
    local texture = Region("texture")
    texture.layer, texture.sublevel = layer, sublevel
    return texture
end
function cast:CreateMaskTexture()
    created = created + 1
    return Region("mask")
end
function cast:GetStatusBarTexture() return fillTexture end
function cast:GetEffectiveScale() return .8 end
function cast:GetHeight() return self.height or 12 end
for _, banned in ipairs({ "SetStatusBarTexture", "SetStatusBarColor", "GetStatusBarColor", "UpdateBarFillTexture",
    "GetMinMaxValues", "GetValue", "GetWidth" }) do
    cast[banned] = function() error("the readiness overlay must not touch Blizzard's castbar: " .. banned) end
end

local events, eventHandler, wakes, bars = {}, nil, {}, {}
CreateFrame = function(kind, _, parent)
    if kind == "Cooldown" then
        local wake = { sets = 0 }
        for _, name in ipairs({ "Show", "SetSize", "SetAlpha", "SetDrawSwipe", "SetDrawEdge", "SetDrawBling",
            "SetHideCountdownNumbers", "Clear" }) do wake[name] = function() end end
        function wake.SetCooldownFromDurationObject() wake.sets = wake.sets + 1 end
        function wake.SetScript(_, script, callback) if script == "OnCooldownDone" then wake.done = callback end end
        wakes[#wakes + 1] = wake
        return wake
    elseif kind == "StatusBar" then
        assert(parent == cast, "the projection bar belongs to the castbar")
        created = created + 1
        local bar = Region("projection")
        bar.edge = Region("projection fill")
        function bar:SetStatusBarTexture(texture) self.texture = texture end
        function bar:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a } end
        function bar:GetStatusBarTexture() return self.edge end
        function bar:SetReverseFill(reverse) self.reverse = reverse end
        function bar:SetMinMaxValues(low, high) self.low, self.high = low, high end
        function bar:SetValue(value) self.value = value end
        bars[#bars + 1] = bar
        return bar
    end
    return {
        RegisterEvent = function(_, event) events[event] = true end,
        UnregisterEvent = function(_, event) events[event] = nil end,
        UnregisterAllEvents = function() for event in pairs(events) do events[event] = nil end end,
        SetScript = function(_, script, callback) if script == "OnEvent" then eventHandler = callback end end,
    }
end

------------------------------------------------------------------ host (Classic MSUF)
-- ExportPublic as Kernel/MSUF_Bootstrap.lua: the global and MSUF.Public
-- (the "MSUF_" prefix dropped), which the engine reads MSUF's colors from.
local host = { Public = {} }
host.ExportPublic = function(name, value)
    _G[name] = value
    host.Public[(name:gsub("^MSUF_", ""))] = value
    return value
end
host.Scheduler = { ScheduleAfter = function() error("native wakes need no scheduler") end }
host.Util = { InCombat = function() return false end }
-- Castbars/MSUF_Castbars_Core.lua (not loaded here) owns the castbar texture.
host.Public.GetCastbarTexture = function() return "Interface\\MSUF\\Lucent" end
-- The real boundary runs each consumer callback; none may raise here.
geterrorhandler = function() return function(message) error("unexpected error report: " .. tostring(message), 0) end end
for _, file in ipairs({ "Kernel/MSUF_Boundary.lua", "Runtime/MSUF_HostAPI.lua", "Castbars/MSUF_CastbarUtils.lua",
    "Castbars/MSUF_InterruptReady.lua" }) do
    assert(loadfile(classic .. "/" .. file))("MidnightSimpleUnitFrames", host)
end
C_Timer.After = function() error("native wakes need no Lua timer") end
local engine = host.KickReady

------------------------------------------------------------------ Suite
local function RGB(hex)
    if type(hex) ~= "string" or #hex ~= 6 then return 1, 1, 1 end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255, (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end
local NS = {
    Client = { isMainline = true, isForever = false }, Text = function(text) return text end,
    IsSecret = issecretvalue, Public = function(value) return not issecretvalue(value) end, RGB = RGB,
    Safety = { IsForbidden = function(region) return region.forbidden == true end },
}
for _, file in ipairs({ "SuiteCatalog", "NameplateStyle", "Catalog/Nameplates", "HostBridge" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", NS)
end
-- The module runtime's readers (MSUF_Suite_Modules/Runtime.lua aliases Platform.lua's).
local function Finite(value)
    return not issecretvalue(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local private = { NS = NS, Suite = { Public = NS.Public, RGB = RGB, Finite = Finite } }
for _, file in ipairs({ "Modes.lua", "KickReady.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Nameplates/" .. file))("MSUF_Suite_Nameplates", private)
end
local Kick = private.KickReady
local stopWatch = Secrets.Watch(root .. "/MSUF_Suite_Nameplates/KickReady.lua", { strict = true })
local config = {}
for key, rule in pairs(NS.SuiteCatalog.nameplates.rules) do config[key] = rule.default end
local M = { active = true, config = config, kicks = setmetatable({}, { __mode = "k" }) }
-- The skin's repaint of its shown plates: this harness has one.
local repaints = 0
Kick.Bind(M, function()
    repaints = repaints + 1
    Kick.Paint(cast, "enemy", "nameplate1")
end)

for key in pairs(NS.SuiteCatalog.nameplates.rules) do
    assert(not key:find("Kick", 1, true), "the nameplates keep no interrupt settings of their own: " .. key)
end

local function Fire(event, ...) frameStamp = frameStamp + 1; eventHandler(nil, event, ...) end
-- Plate events and paints arrive in later rendered frames than the engine's last read.
local function OnCast(event) frameStamp = frameStamp + 1; Kick.OnCast(cast, "nameplate1", event) end
local function Paint(prefix) frameStamp = frameStamp + 1; Kick.Paint(cast, prefix or "enemy", "nameplate1") end
-- MSUF's settings path: the castbar menu and profile switches end here.
local function ApplyMSUF() frameStamp = frameStamp + 1; MSUF_KickReady_RefreshAll() end
local function State() return M.kicks[cast] end
local function RGBA(region) local v = region.vertex; return v[1], v[2], v[3], v[4] end
local function Is(region, r, g, b)
    local vr, vg, vb = RGBA(region)
    return vr == r and vg == g and vb == b
end

------------------------------------------------------------------ hosts
-- A host without the engine (Main MSUF, an older Classic): nothing happens.
local engineHost = MSUF_HostAPI
MSUF_HostAPI = { version = 1 }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
Kick.Configure()
unitCast.kind, unitCast.duration = "cast", Duration(10, 13)
Paint()
OnCast("UNIT_SPELLCAST_START")
assert(NS.HostBridge.KickReady() == nil and created == 0 and not engine.HasConsumers(),
    "an old host without the engine got an overlay or a registration")
MSUF_HostAPI = engineHost
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
assert(NS.HostBridge.KickReady() == engine, "the HostBridge did not resolve the host's engine")

-- The running module registers; MSUF's nameplate switch is still off.
Kick.Configure()
assert(engine.HasConsumers(), "the running module did not register with the engine")
assert(next(events) == nil, "a registration alone started the engine")
Paint()
OnCast("UNIT_SPELLCAST_START")
assert(created == 0, "MSUF's nameplate switch is off, yet the castbar was decorated")

------------------------------------------------------------------ border (MSUF's default)
-- MSUF's switch on: its settings call repaints the shown plates.
general.kickReadyShowNameplates = true
ApplyMSUF()
local state = State()
assert(repaints == 1 and events.PLAYER_ENTERING_WORLD, "MSUF's switch did not start the engine and repaint")
assert(state and state.showing and events.SPELL_UPDATE_COOLDOWN and #wakes == 1 and wakes[1].sets >= 1,
    "a plate mid-cast did not show readiness and arm the engine")
local edges = state.border.edges
for i = 1, 4 do assert(edges[i].shown and Is(edges[i], 1, 0, 0), "border edge " .. i .. " is not MSUF's not-ready color") end
local function Snapped(width) return PixelUtil.GetNearestPixelSize(width, .8, 1) end
assert(edges[1].height == Snapped(1) and edges[1].height ~= 1,
    "the border is not MSUF's castbar outline snapped to screen pixels")
assert(not state.fill and not state.box, "the border style created other decorations")

-- Counterspell recovers: the engine's cooldown event repaints in MSUF's ready color.
counterspell.remaining, counterspell.endTime = 0, 9
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)
for i = 1, 4 do assert(Is(edges[i], 0, 1, 0), "border edge " .. i .. " is not MSUF's ready color") end
-- Used again; the native wake at the recovery repaints once more.
counterspell.remaining, counterspell.endTime = 4, 104
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)
assert(Is(edges[1], 1, 0, 0))
counterspell.remaining = 0
frameStamp = frameStamp + 1
wakes[1].done()
assert(Is(edges[1], 0, 1, 0), "the native wake did not repaint the plate")

-- MSUF's colors and outline width follow on MSUF's next apply.
general.kickReadyColor = { ["1"] = .1, ["2"] = .2, ["3"] = .3 }
general.castbarOutlineThickness = 3
ApplyMSUF()
assert(Is(edges[1], .1, .2, .3) and edges[1].height == Snapped(3), "MSUF's color or outline width did not reach the plate")
general.castbarOutlineThickness = 0
ApplyMSUF()
for i = 1, 4 do assert(not edges[i].shown, "a castbar without an outline got a border") end
general.castbarOutlineThickness = nil
general.kickReadyColor = { ["1"] = 0, ["2"] = 1, ["3"] = 0 }
ApplyMSUF()
assert(edges[1].shown and edges[1].height == Snapped(1))

-- Interruptibility events carry their plain answer; uninterruptible shows nothing.
counterspell.remaining = 4
OnCast("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
assert(not edges[1].shown and not state.showing and not events.SPELL_UPDATE_COOLDOWN,
    "an uninterruptible cast kept the border or the engine")
OnCast("UNIT_SPELLCAST_INTERRUPTIBLE")
assert(edges[1].shown and Is(edges[1], 1, 0, 0) and events.SPELL_UPDATE_COOLDOWN)

-- A restricted uninterruptible cast is grey, composed natively, as on MSUF's castbars.
unitCast.notInterruptible = Secret(true)
OnCast("UNIT_SPELLCAST_START")
assert(edges[1].shown and Is(edges[1], .6, .6, .6), "a restricted uninterruptible cast is not MSUF's grey")
unitCast.notInterruptible = Secret(false)
OnCast("UNIT_SPELLCAST_START")
assert(Is(edges[1], 1, 0, 0))
unitCast.notInterruptible = nil
OnCast("UNIT_SPELLCAST_START")
assert(Is(edges[1], 1, 0, 0), "unknown interruptibility hid the readiness")
unitCast.notInterruptible = false

-- Restricted readiness (combat): composed by the engine's native selectors.
counterspell.remaining, counterspell.zero = Secret(3), Secret(false)
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)
assert(Is(edges[1], 1, 0, 0), "a restricted recovering interrupt lost its color")
counterspell.zero = Secret(true)
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)
assert(Is(edges[1], 0, 1, 0), "a restricted ready interrupt lost its color")
counterspell.remaining, counterspell.zero, counterspell.endTime = 4, nil, 104
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)

------------------------------------------------------------------ box
general.kickReadyStyle = "box"
ApplyMSUF()
local box = state.box
assert(box and box.shown and not edges[1].shown, "MSUF's box style did not replace the border")
assert(box.width == 12 and box.height == 12, "an auto-sized box is not as tall as the castbar")
cast:SetHeight(27)
Paint()
assert(box.width == 27 and box.height == 27, "auto size followed setup defaults instead of the styled castbar")
cast:SetHeight(12)
Paint()
local point = box.points[1]
assert(point[1] == "LEFT" and point[2] == cast and point[3] == "RIGHT" and point[4] == 4 and point[5] == 0,
    "the box is not beside the castbar at MSUF's anchor")
assert(Is(box, 1, 0, 0) and box.alpha == 1)
general.kickReadyAutoSize, general.kickReadySize = false, 20
general.kickReadyAnchor, general.kickReadyOffsetX, general.kickReadyOffsetY = "TOP", 0, 2
ApplyMSUF()
point = box.points[1]
assert(box.width == 20 and point[1] == "BOTTOM" and point[3] == "TOP" and point[5] == 2,
    "MSUF's box size or placement did not follow")
general.kickReadySize = 200
ApplyMSUF()
assert(box.width == 80, "the box is not clamped like MSUF's")
unitCast.notInterruptible = Secret(true)
OnCast("UNIT_SPELLCAST_START")
assert(box.shown and box.alpha == 0, "a restricted uninterruptible cast kept the box visible")
unitCast.notInterruptible = false
OnCast("UNIT_SPELLCAST_START")
assert(box.alpha == 1)
general.kickReadyAutoSize, general.kickReadySize, general.kickReadyAnchor = nil, 8, "RIGHT"
general.kickReadyOffsetX, general.kickReadyOffsetY = 4, 0

------------------------------------------------------------------ fill
-- MSUF's unavailable cast fill: MSUF's castbar texture in MSUF's cast colors.
general.kickReadyStyle = "fill"
ApplyMSUF()
local fill = state.fill
assert(fill and fill.shown and not box.shown and fill.allPoints == fillTexture and fill.texture == "Interface\\MSUF\\Lucent",
    "the fill is not MSUF's castbar texture over Blizzard's fill")
local unavailable = fill.vertex
assert(unavailable.r == 1 and math.abs(unavailable.g - .494117647) < 1e-6, "a recovering interrupt is not MSUF's unavailable color")
counterspell.remaining = 0
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)
assert(fill.vertex.r == 0 and fill.vertex.g == .85 and fill.vertex.b == .85, "a ready interrupt is not MSUF's cast color")
-- An uninterruptible cast keeps MSUF's fill in MSUF's non-interruptible color.
OnCast("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
assert(fill.shown and fill.vertex.r == .9 and fill.vertex.g == .1 and not state.showing,
    "an uninterruptible cast lost MSUF's non-interruptible fill")
OnCast("UNIT_SPELLCAST_INTERRUPTIBLE")
assert(fill.vertex.g == .85 and state.showing)
unitCast.notInterruptible = Secret(true)
OnCast("UNIT_SPELLCAST_START")
assert(fill.vertex.r == .9, "a restricted uninterruptible cast is not MSUF's non-interruptible color")
unitCast.notInterruptible = false
OnCast("UNIT_SPELLCAST_START")

------------------------------------------------------------------ marker and shade
general.kickReadyTimeMarker, general.kickReadyTimeSegment = true, true
counterspell.remaining, counterspell.endTime = 4, 15
ApplyMSUF()
local bar = bars[1]
local projection = state.projections[1]
local marker, segment = projection.marker, projection.segment
assert(bar and bar.shown and bar.low == 10 and bar.high == 13 and bar.value == 15 and bar.reverse == false,
    "MSUF's time marker does not span the cast")
assert(marker.shown and marker.mask == state.clip and marker.color[2] == 1 and marker.color[4] == 1)
assert(segment.shown and segment.color[4] == .25, "MSUF's shade is not a quarter of the ready color")
-- A cooldown reduction keeps the readiness and only moves the marker.
counterspell.remaining, counterspell.endTime = 3, 50
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)
assert(bar.value == 50, "a reduced cooldown did not move the marker")
counterspell.endTime = Secret(120)
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)
assert(Reveal(bar.value) == 120, "a restricted recovery time did not reach the marker's native bar")
counterspell.endTime = 104
unitCast.notInterruptible = Secret(true)
OnCast("UNIT_SPELLCAST_START")
assert(marker.alpha == 0 and segment.alpha == 0, "a restricted uninterruptible cast kept the marker")
unitCast.notInterruptible = false
OnCast("UNIT_SPELLCAST_START")
assert(marker.alpha == 1 and not projection.restricted)
-- A restricted cast duration: readiness shows, the marker has nothing to span.
unitCast.duration = Secret(Duration(10, 13))
OnCast("UNIT_SPELLCAST_START")
assert(fill.shown and not marker.shown and not bar.shown, "a restricted cast duration was read or left a stale marker")
unitCast.duration = Duration(10, 14)
OnCast("UNIT_SPELLCAST_DELAYED")
assert(marker.shown and bar.high == 14, "a delayed cast did not re-read its duration")
-- A draining channel places its marker from the far side; an empowered cast
-- fills like a cast; a restricted empowered flag is read as a channel.
unitCast.kind, unitCast.duration = "channel", Duration(20, 26)
OnCast("UNIT_SPELLCAST_CHANNEL_START")
assert(bar.reverse == true and bar.low == 20 and bar.high == 26, "a channel's marker does not run from the far side")
unitCast.kind, unitCast.empowerDuration = "empower", Duration(30, 34)
OnCast("UNIT_SPELLCAST_EMPOWER_START")
assert(bar.reverse == false and bar.high == 34)
unitCast.secretEmpowered = true
OnCast("UNIT_SPELLCAST_EMPOWER_START")
assert(bar.reverse == true and bar.high == 26, "a restricted empowered flag was read in Lua")
unitCast.secretEmpowered, unitCast.kind, unitCast.duration = nil, "cast", Duration(10, 13)
OnCast("UNIT_SPELLCAST_START")
general.kickReadyTimeMarker, general.kickReadyTimeSegment, general.kickReadyStyle = false, false, "border"
ApplyMSUF()

------------------------------------------------------------------ dedupe after a quiet stretch
-- Without markers, a plate that shows again after the engine went quiet must
-- still follow the next change: no cast, the interrupt recovers unseen, a new
-- cast paints it ready, then the interrupt is used.
counterspell.remaining, counterspell.endTime = 4, 104
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)
assert(Is(edges[1], 1, 0, 0))
unitCast.kind = nil
OnCast("UNIT_SPELLCAST_STOP")
assert(not edges[1].shown and not events.SPELL_UPDATE_COOLDOWN, "a finished cast kept its readiness")
counterspell.remaining = 0
unitCast.kind = "cast"
OnCast("UNIT_SPELLCAST_START")
assert(Is(edges[1], 0, 1, 0))
counterspell.remaining = 4
Fire("SPELL_UPDATE_COOLDOWN", COUNTERSPELL, COUNTERSPELL)
assert(Is(edges[1], 1, 0, 0), "a used interrupt was deduped against readiness from before the plate showed")

------------------------------------------------------------------ plates, switch off, disable
-- Friendly plates, Blizzard's look and a hidden castbar never show readiness.
Paint("friendly")
assert(not state.showing and State().unit == nil)
config.look = private.Mode.LOOK_BLIZZARD
Paint()
assert(not state.showing)
config.look, config.enemyCastEnabled = 4, private.Mode.HIDE
Paint()
assert(not state.showing)
config.enemyCastEnabled = 2
cast.forbidden = true
local before = created
Paint()
assert(created == before, "a forbidden castbar was decorated")
cast.forbidden = nil
Paint()
assert(state.showing and events.SPELL_UPDATE_COOLDOWN)

-- MSUF's switch off: everything is restored and the engine stops.
general.kickReadyShowNameplates = false
ApplyMSUF()
assert(next(events) == nil, "the engine kept running after MSUF's switch was turned off")
for i = 1, 4 do assert(not edges[i].shown) end
assert(not state.showing)
Paint()
assert(not state.showing, "the off state painted again")

-- The module's disable unregisters.
general.kickReadyShowNameplates = true
ApplyMSUF()
assert(state.showing and events.PLAYER_ENTERING_WORLD)
M.active = false
Kick.Disable()
assert(not engine.HasConsumers() and next(events) == nil and not state.showing,
    "disabling the module left the engine running")

------------------------------------------------------------------ skin wiring
-- Skin.lua owns the plate lifecycle; each hook sits in the function that
-- owns that moment (suite_nameplates_contract.lua runs it with the engine).
local skinFile = assert(io.open(root .. "/MSUF_Suite_Nameplates/Skin.lua", "rb"))
local skin = skinFile:read("*a"):gsub("\r\n", "\n")
skinFile:close()
local function Body(header)
    local start = assert(skin:find(header, 1, true), "Skin.lua lost " .. header)
    local finish = assert(skin:find("\nend\n", start, true))
    return skin:sub(start, finish)
end
local function Has(header, call)
    assert(Body(header):find(call, 1, true), header .. " must call " .. call)
end
Has("local function Paint(uf)", "KickReady.Paint(cast, prefix, M.units[health])")
Has("local function RestorePlate(uf)", "KickReady.Restore(cast)")
Has("local function OnCastChanged(module, event, unit)", "KickReady.OnCast(cast, unit, event)")
Has("local function RepaintCasts()", "KickReady.Paint(cast, Prefix(uf), M.units[health])")
Has("function M:Disable()", "KickReady.Disable()")
local refresh = Body("function M:Refresh()")
assert(refresh:find("KickReady.Configure()", 1, true) < refresh:find("EachPlate(ApplyPlate)", 1, true),
    "the engine registration must precede the plate pass")
assert(skin:find("\nKickReady.Bind(M, RepaintCasts)\n", 1, true), "Skin.lua must bind the readiness module")

local violations = stopWatch()
assert(#violations == 0, "KickReady.lua compares or tests a secret:\n" .. table.concat(violations, "\n"))

print("nameplate interrupt readiness: MSUF's switch, look, engine, restricted values and lifecycle passed")
