local _, P = ...
local NS, S = P.NS, P.Suite

-- The reticle follows the pointer, not the screen center. MSUF's existing
-- combat crosshair continues to own the latter. Blizzard's native cooldown
-- widget animates cast and GCD duration objects without a Lua timer.
local M = {}
local GCD_SPELL = 61304
local TRAIL_COUNT = 5
local TRAIL_INTERVAL = 1 / 30
local TAU = math.pi * 2

local function Ring(parent)
    local pieces = {}
    for i = 1, 20 do
        local piece = S.CreateTexture(parent, nil, "OVERLAY")
        piece:SetColorTexture(1, 1, 1, 1)
        piece:SetSize(4, 2)
        piece:SetPoint("CENTER", parent, "CENTER", math.cos(TAU * i / 20) * 17,
            math.sin(TAU * i / 20) * 17)
        piece:SetRotation(TAU * i / 20 + math.pi / 2)
        pieces[i] = piece
    end
    return pieces
end

local function NativeCooldown(parent, r, g, b)
    local cooldown = S.CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    cooldown:SetPoint("CENTER", parent, "CENTER")
    cooldown:SetSize(28, 28)
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
    host:SetSize(44, 44)
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
        dot:SetSize(3, 3)
        dot:SetColorTexture(1, 1, 1, (TRAIL_COUNT + 1 - i) / (TRAIL_COUNT + 4))
        dot:Hide()
        trail[i] = dot
    end
    self.host, self.pieces, self.trailHost, self.trail = host, Ring(host), trailHost, trail
    self.gcd = NativeCooldown(host, .96, .77, .37)
    self.cast = NativeCooldown(host, .35, .8, 1)
end

local function Draw(self)
    local c = self.config
    local r, g, b = S.RGB(c.color)
    local radius = c.size / 2
    for i = 1, #self.pieces do
        local piece = self.pieces[i]
        local angle = TAU * i / #self.pieces
        piece:ClearAllPoints()
        piece:SetPoint("CENTER", self.host, "CENTER", math.cos(angle) * radius,
            math.sin(angle) * radius)
        piece:SetSize(math.max(3, c.size / 9), math.max(1, c.size / 21))
        piece:SetVertexColor(r, g, b)
    end
    for i = 1, TRAIL_COUNT do
        self.trail[i]:SetColorTexture(r, g, b, (TRAIL_COUNT + 1 - i) / (TRAIL_COUNT + 4))
        self.trail[i]:SetSize(math.max(2, c.size / (7 + i)), math.max(2, c.size / (7 + i)))
        self.trail[i]:SetShown(c.showTrail)
    end
    self.host:SetAlpha(c.opacity / 100)
    self.trailHost:SetAlpha(c.opacity / 100)
    self.gcd:SetSize(c.size - 8, c.size - 8)
    self.cast:SetSize(c.size - 8, c.size - 8)
end

local function ReadCursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not S.Finite(x) or not S.Finite(y) or not S.Finite(scale) or scale <= 0 then return nil end
    return x / scale, y / scale
end

local function Follow(self, elapsed)
    local x, y = ReadCursor()
    if not x then return end
    if x ~= self.x or y ~= self.y then
        self.x, self.y = x, y
        self.host:ClearAllPoints()
        self.host:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end
    if not self.config.showTrail then return end
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

local function FollowUpdate(_, elapsed)
    Follow(M, elapsed)
end

local function UpdateGCD(self)
    if not self.config.showGCD or self.casting then
        self.gcd:Hide()
        return
    end
    local duration = C_Spell.GetSpellCooldownDuration(GCD_SPELL)
    if S.Public(duration) and duration then
        self.gcd:SetCooldownFromDurationObject(duration, true)
        self.gcd:Show()
    else
        self.gcd:Hide()
    end
end

local function UpdateCast(self)
    if not self.config.showCast then
        self.casting = false
        self.cast:Hide()
        UpdateGCD(self)
        return
    end
    local duration = UnitCastingDuration("player")
    if not (S.Public(duration) and duration) then
        duration = UnitChannelDuration("player")
    end
    self.casting = S.Public(duration) and duration ~= nil
    if self.casting then
        self.cast:SetCooldownFromDurationObject(duration, true)
        self.cast:Show()
        self.gcd:Hide()
    else
        self.cast:Hide()
        UpdateGCD(self)
    end
end

local function OnCast(self)
    UpdateCast(self)
end

local function OnGCD(self)
    UpdateGCD(self)
end

local function Active(self)
    local shown = not self.config.combatOnly or NS.IsCombatLocked()
    self.host:SetShown(shown)
    self.trailHost:SetShown(shown and self.config.showTrail)
    self.host:SetScript("OnUpdate", shown and FollowUpdate or nil)
    if not shown then
        for i = 1, TRAIL_COUNT do self.trail[i]:Hide() end
    elseif self.config.showTrail then
        for i = 1, TRAIL_COUNT do self.trail[i]:Show() end
    end
end

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}

local function SyncEvents(self)
    for i = 1, #CAST_EVENTS do
        local event = CAST_EVENTS[i]
        if self.config.showCast then self.context:Event(event, OnCast, true, "player")
        else self.context:RemoveEvent(event) end
    end
    if self.config.showGCD then
        self.context:Event("UNIT_SPELLCAST_SUCCEEDED", OnGCD, true, "player")
    else
        self.context:RemoveEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
    if self.config.combatOnly then
        self.context:Event("PLAYER_REGEN_DISABLED", Active, true)
        self.context:Event("PLAYER_REGEN_ENABLED", Active, true)
    else
        self.context:RemoveEvent("PLAYER_REGEN_DISABLED")
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    end
end

function M:Enable()
    Create(self)
    self.trailX, self.trailY, self.trailElapsed, self.trailIdle = {}, {}, 0, 0
    Draw(self)
    SyncEvents(self)
    UpdateCast(self)
    Active(self)
end

function M:Refresh()
    Draw(self)
    SyncEvents(self)
    UpdateCast(self)
    Active(self)
end

function M:Disable()
    self.host:SetScript("OnUpdate", nil)
    self.host:Hide()
    self.trailHost:Hide()
    self.cast:Hide()
    self.gcd:Hide()
    self.casting = false
end

S.Install("cursorEffects", M)
