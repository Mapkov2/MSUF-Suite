local _, P = ...
local NS, S = P.NS, P.Suite

-- A highlight that follows the mouse pointer so it is easy to find; MSUF's
-- combat crosshair owns the screen center. The global cooldown and the
-- current cast fill Blizzard's cooldown swipe inside the ring, animated by
-- the client from duration objects without a Lua timer.
local M = {}
local GCD_SPELL = 61304
local TRAIL_COUNT = 5
local TRAIL_INTERVAL = 1 / 30
local TAU = math.pi * 2
local RING_PIECES = 48
local OPEN_PIECES = 20
-- ringShape choices; zone choices (1 is everywhere); per-element "when"
-- choices (1 always).
local THIN, DOTS, NO_RING = 2, 3, 4
local INSIDE, OUTSIDE = 2, 3
local IN_COMBAT, OUT_OF_COMBAT = 2, 3

local function Ring(parent)
    local pieces = {}
    for i = 1, RING_PIECES do
        local piece = S.CreateTexture(parent, nil, "OVERLAY")
        piece:SetColorTexture(1, 1, 1, 1)
        pieces[i] = piece
    end
    return pieces
end

local function NativeCooldown(parent, r, g, b)
    local cooldown = S.CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    cooldown:SetPoint("CENTER", parent, "CENTER")
    cooldown:SetDrawBling(false)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetSwipeColor(r, g, b, .75)
    cooldown:EnableMouse(false)
    cooldown:Hide()
    return cooldown
end

local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetFrameStrata("TOOLTIP")
    host:EnableMouse(false)
    host:Hide()
    local trailHost = S.CreateFrame("Frame", nil, UIParent)
    trailHost:SetAllPoints(UIParent)
    trailHost:SetFrameStrata("HIGH")
    trailHost:EnableMouse(false)
    trailHost:Hide()
    local trail = {}
    for i = 1, TRAIL_COUNT do
        local dot = S.CreateTexture(trailHost, nil, "OVERLAY")
        dot:Hide()
        trail[i] = dot
    end
    self.host, self.pieces, self.trailHost, self.trail = host, Ring(host), trailHost, trail
    self.gcd = NativeCooldown(host, .96, .77, .37)
    self.cast = NativeCooldown(host, .35, .8, 1)
    -- The pointer's centre dot.
    self.dot = S.CreateTexture(host, nil, "OVERLAY")
    self.dot:SetPoint("CENTER", host, "CENTER")
    self.dot:Hide()
    -- The global cooldown on its own: a fixed circle placed in MSUF Edit Mode.
    local free = S.CreateFrame("Frame", "MSUFSuiteCursorGCD", UIParent)
    free:SetFrameStrata("HIGH")
    free:EnableMouse(false)
    free:Hide()
    self.gcdHost = free
    self.gcdFree = NativeCooldown(free, .96, .77, .37)
    self.gcdFree:SetAllPoints(free)
end

local function PieceCount(c)
    return c.ringShape == THIN and RING_PIECES or OPEN_PIECES
end

-- Shape, size and color are cold settings; showing pieces is Active's job.
local function Draw(self)
    local c = self.config
    local r, g, b = S.RGB(c.color)
    local radius = c.size / 2
    local count = PieceCount(c)
    local thickness = math.max(1, c.size / 21)
    local length = c.ringShape == DOTS and thickness * 1.5
        or c.ringShape == THIN and TAU * radius / count + 1 or math.max(3, c.size / 9)
    for i = 1, count do
        local piece, angle = self.pieces[i], TAU * i / count
        piece:ClearAllPoints()
        piece:SetPoint("CENTER", self.host, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
        piece:SetRotation(angle + math.pi / 2)
        piece:SetSize(length, c.ringShape == DOTS and length or thickness)
        piece:SetVertexColor(r, g, b)
    end
    for i = 1, TRAIL_COUNT do
        local size = math.max(2, c.size / (7 + i))
        self.trail[i]:SetColorTexture(r, g, b, (TRAIL_COUNT + 1 - i) / (TRAIL_COUNT + 4))
        self.trail[i]:SetSize(size, size)
    end
    self.host:SetSize(c.size + 8, c.size + 8)
    self.host:SetAlpha(c.opacity / 100)
    self.trailHost:SetAlpha(c.opacity / 100)
    self.gcd:SetSize(c.size - 8, c.size - 8)
    self.cast:SetSize(c.size - 8, c.size - 8)
    -- The cast fill's moving edge (Blizzard's cooldown edge line).
    self.cast:SetDrawEdge(c.castSpark == true)
    self.dot:SetColorTexture(r, g, b, 1)
    self.dot:SetSize(c.dotSize, c.dotSize)
    local point = NS.AnchorPoints[c.gcdPoint] or "CENTER"
    self.gcdHost:ClearAllPoints()
    self.gcdHost:SetPoint(point, UIParent, point, c.gcdX, c.gcdY)
    self.gcdHost:SetSize(c.gcdSize, c.gcdSize)
    self.gcdHost:SetAlpha(c.gcdOpacity / 100)
end

local function ReadCursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not S.Finite(x) or not S.Finite(y) or not S.Finite(scale) or scale <= 0 then return nil end
    return x / scale, y / scale
end

local function MoveTrail(self, x, y)
    local oldX, oldY = x, y
    for i = 1, TRAIL_COUNT do
        local dot = self.trail[i]
        local nextX, nextY = self.trailX[i], self.trailY[i]
        self.trailX[i], self.trailY[i] = oldX, oldY
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", oldX, oldY)
        oldX, oldY = nextX or x, nextY or y
    end
end

-- The one intentional per-frame surface of the Quality of Life helpers: a
-- pointer highlight must follow the pointer. It runs only while something
-- is shown, moves nothing while the pointer rests and lets the trail settle.
local function Follow(self, elapsed)
    local x, y = ReadCursor()
    if not x then return end
    if x ~= self.x or y ~= self.y then
        self.x, self.y = x, y
        self.host:ClearAllPoints()
        self.host:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end
    if not self.trailShown then return end
    self.trailElapsed = self.trailElapsed + elapsed
    if self.trailElapsed < TRAIL_INTERVAL then return end
    self.trailElapsed = 0
    if x == self.trailLastX and y == self.trailLastY then
        self.trailIdle = self.trailIdle + 1
        if self.trailIdle > TRAIL_COUNT then return end
    else
        self.trailIdle = 0
    end
    self.trailLastX, self.trailLastY = x, y
    MoveTrail(self, x, y)
end

local function FollowUpdate(_, elapsed)
    Follow(M, elapsed)
end

-- One rule for the whole highlight: combat and location.
local function Visible(self)
    local c = self.config
    if c.zone == INSIDE and not self.inInstance or c.zone == OUTSIDE and self.inInstance then return false end
    return not c.combatOnly or self.inCombat == true
end

-- Each part (pointer, global cooldown, cast) can also keep to combat or to
-- the time outside it.
local function When(self, choice)
    if choice == IN_COMBAT then return self.inCombat == true end
    if choice == OUT_OF_COMBAT then return self.inCombat ~= true end
    return true
end

local function NeedsCombat(c)
    return c.combatOnly or c.ringWhen ~= 1 or c.gcdWhen ~= 1 or c.castWhen ~= 1
end

local function UpdateGCD(self)
    if not self.config.showGCD or not Visible(self) then
        self.gcdActive = false
        return
    end
    local duration = C_Spell.GetSpellCooldownDuration(GCD_SPELL)
    local cooldown = C_Spell.GetSpellCooldown(GCD_SPELL)
    self.gcdActive = S.Public(duration) and duration ~= nil
        and (not cooldown or (S.Public(cooldown.isActive) and cooldown.isActive == true))
    if self.gcdActive then
        local target = self.config.gcdDetached and self.gcdFree or self.gcd
        target:SetCooldownFromDurationObject(duration, true)
    end
end

local function UpdateCast(self)
    if not self.config.showCast or not Visible(self) then
        self.casting = false
        return
    end
    local duration = UnitCastingDuration("player")
    if not (S.Public(duration) and duration) then duration = UnitChannelDuration("player") end
    self.casting = S.Public(duration) and duration ~= nil
    if self.casting then self.cast:SetCooldownFromDurationObject(duration, true) end
end

-- A cast replaces the global cooldown inside the ring while it lasts; a
-- global cooldown on its own circle shows next to it.
local function Active(self)
    local c = self.config
    local visible = Visible(self)
    local pointer = visible and When(self, c.ringWhen) and (not c.cameraHoldOnly or self.cameraHeld == true)
    local ring = pointer and c.ringShape ~= NO_RING
    local dot = pointer and c.showDot == true
    local cast = visible and c.showCast and When(self, c.castWhen) and self.casting == true
    local gcdOn = visible and c.showGCD and When(self, c.gcdWhen) and self.gcdActive == true
    local gcd = gcdOn and not c.gcdDetached and not cast
    local free = gcdOn and c.gcdDetached == true
    self.trailShown = pointer and c.showTrail == true
    local count = PieceCount(c)
    for i = 1, #self.pieces do self.pieces[i]:SetShown(ring and i <= count) end
    self.dot:SetShown(dot)
    self.cast:SetShown(cast)
    self.gcd:SetShown(gcd)
    self.gcdFree:SetShown(free)
    self.gcdHost:SetShown(free or S.editMode == true and c.gcdDetached == true)
    self.trailHost:SetShown(self.trailShown)
    for i = 1, TRAIL_COUNT do self.trail[i]:SetShown(self.trailShown) end
    local follow = ring or dot or cast or gcd or self.trailShown
    self.host:SetShown(follow)
    self.host:SetScript("OnUpdate", follow and FollowUpdate or nil)
    if follow then Follow(self, 0) end
end

local function OnCast(self)
    UpdateCast(self)
    UpdateGCD(self)
    Active(self)
end

local function OnGCD(self)
    UpdateGCD(self)
    Active(self)
end

local function CooldownDone()
    if not M.active then return end
    M.gcdActive = false
    Active(M)
end

-- Turning the camera means holding a mouse button that went down on the 3D
-- world rather than on a frame (GLOBAL_MOUSE_DOWN/UP, any button press).
local CAMERA_BUTTONS = { LeftButton = "cameraLeft", RightButton = "cameraRight" }
local function OnMouse(self, event, button)
    local key = CAMERA_BUTTONS[button]
    if not key then return end
    if event == "GLOBAL_MOUSE_DOWN" then
        local foci = GetMouseFoci()
        local top = foci and foci[1]
        self[key] = top == nil or top == WorldFrame
    else
        self[key] = false
    end
    local held = self.cameraLeft == true or self.cameraRight == true
    if held ~= self.cameraHeld then
        self.cameraHeld = held
        Active(self)
    end
end

-- PLAYER_REGEN_DISABLED arrives before the combat lockdown starts.
local function ContextChanged(self, event)
    self.inCombat = NS.InCombat(event)
    if self.config.zone ~= 1 then
        local inside = IsInInstance()
        self.inInstance = S.Public(inside) and inside == true
    end
    OnCast(self)
end

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
}
-- The global cooldown starts with the cast: at UNIT_SPELLCAST_SUCCEEDED for
-- an instant spell, at the start for a cast-time, channeled or empowered one.
-- With the cast display on, its cast events read the global cooldown too.
local GCD_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED" }
local GCD_START_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
}
local COMBAT_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local MOUSE_EVENTS = { "GLOBAL_MOUSE_DOWN", "GLOBAL_MOUSE_UP" }
local ZONE_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }

local function Listen(self, events, wanted, callback, unit)
    for i = 1, #events do
        if wanted then self.context:Event(events[i], callback, true, unit)
        else self.context:RemoveEvent(events[i]) end
    end
end

local function SyncEvents(self)
    local c = self.config
    Listen(self, CAST_EVENTS, c.showCast, OnCast, "player")
    if not c.showCast then Listen(self, GCD_START_EVENTS, c.showGCD, OnGCD, "player") end
    Listen(self, GCD_EVENTS, c.showGCD, OnGCD, "player")
    Listen(self, COMBAT_EVENTS, NeedsCombat(c), ContextChanged)
    Listen(self, ZONE_EVENTS, c.zone ~= 1, ContextChanged)
    Listen(self, MOUSE_EVENTS, c.cameraHoldOnly, OnMouse)
    if not c.cameraHoldOnly then self.cameraLeft, self.cameraRight, self.cameraHeld = false, false, false end
end

-- The detached circle shows a sample swipe while MSUF Edit Mode places it.
local function EditSample(self)
    if S.editMode and self.config.gcdDetached then
        self.gcdFree:SetCooldown(GetTime(), 3600)
        self.gcdFree:Show()
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover("cursorEffects", "gcd", {
        label = "Global cooldown circle", order = 649,
        getFrame = function() return self.gcdHost end,
        xKey = "gcdX", yKey = "gcdY", pointKey = "gcdPoint",
        point = function() return NS.AnchorPoints[self.config.gcdPoint] or "CENTER" end,
        visible = function() return self.config.gcdDetached == true end,
        quickPosition = true, sizeKeys = { "gcdSize" },
    })
end

function M:HideEditPreview()
    self.gcdFree:Clear()
    self.gcdHost:Hide()
end

function M:Enable()
    Create(self)
    self.trailX, self.trailY, self.trailElapsed, self.trailIdle = {}, {}, 0, 0
    Draw(self)
    SyncEvents(self)
    self.gcd:SetScript("OnCooldownDone", CooldownDone)
    self.gcdFree:SetScript("OnCooldownDone", CooldownDone)
    ContextChanged(self)
    EditSample(self)
    self:RegisterMovers()
end

function M:Refresh()
    Draw(self)
    SyncEvents(self)
    ContextChanged(self)
    EditSample(self)
end

function M:Disable()
    self.host:SetScript("OnUpdate", nil)
    self.host:Hide()
    self.trailHost:Hide()
    self.cast:Hide()
    self.gcd:Hide()
    self.dot:Hide()
    self.gcdFree:Hide()
    self.gcdHost:Hide()
    self.gcdActive, self.casting = false, false
    self.cameraLeft, self.cameraRight, self.cameraHeld = false, false, false
end

S.Install("cursorEffects", M)
