local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "partyEffects"
local IN_COMBAT = { inCombat = true }
local M = {}
-- Haste spells whose cast by you or your pet starts the banner (public spell
-- records, nether.wowhead.com/tooltip/spell/<id>, 2026-10-01): Bloodlust,
-- Heroism, Time Warp, Primal Rage (pet), Fury of the Aspects, Harrier's Cry,
-- Thunderous Drums. Their buffs carry the same spell IDs; a group member's
-- cast reaches you as that buff (UNIT_AURA on the player).
local LUST = { [2825] = true, [32182] = true, [80353] = true, [264667] = true, [390386] = true,
    [466904] = true, [444257] = true }
local COLORS = { { .8, .1, .7 }, { .1, .7, .95 }, { 1, .6, .05 } }
local OWN_UNITS = { "player", "pet" }

local function Build(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(320, 86)
    host:EnableMouse(false)
    host:SetFrameStrata("HIGH")
    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("CENTER")
    self.animations = {}
    for index, color in ipairs(COLORS) do
        local region = S.CreateTexture(host, nil, "BACKGROUND")
        region:SetAllPoints()
        region:SetColorTexture(color[1], color[2], color[3], .7)
        region:SetAlpha(0)
        local group = region:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        local rise = group:CreateAnimation("Alpha")
        rise:SetFromAlpha(0)
        rise:SetToAlpha(1)
        rise:SetDuration(.45)
        rise:SetStartDelay((index - 1) * .3)
        rise:SetOrder(1)
        local fall = group:CreateAnimation("Alpha")
        fall:SetFromAlpha(1)
        fall:SetToAlpha(0)
        fall:SetDuration(.45)
        fall:SetEndDelay((#COLORS - index) * .3)
        fall:SetOrder(2)
        self.animations[index] = group
    end
    self.host, self.title = host, title
    host:Hide()
end

------------------------------------------------------------------ action bar spin
-- The Suite's own action bar headers turn once around their centre (Rotation
-- animation) while the banner plays. Headers are protected: a turn starts only
-- outside combat (S.VisitPartyActionBars refuses in combat), and stops at
-- PLAYER_REGEN_DISABLED, which arrives before the lockdown, so buttons never
-- sit away from their click areas in a fight. The ActionBars addon stops its
-- headers at that edge too.
local function StopBars(self)
    local spinning = self.spinning
    if not spinning then return end
    self.spinning = nil
    self.context:RemoveEvent("PLAYER_REGEN_DISABLED")
    for header, group in pairs(spinning) do
        spinning[header] = nil
        group:Stop()
    end
    self.idleSpins = spinning
end

local function OnCombatEdge(self) StopBars(self) end

local function SpinBar(self, header)
    local group = self.spinGroups[header]
    if not group then
        group = header:CreateAnimationGroup()
        group:SetLooping("NONE")
        local turn = group:CreateAnimation("Rotation")
        turn:SetDegrees(360)
        turn:SetOrigin("CENTER", 0, 0)
        turn:SetOrder(1)
        group.turn = turn
        self.spinGroups[header] = group
    end
    group:Stop()
    group.turn:SetDuration(self.config.duration)
    group:Play()
    self.spinning[header] = group
end

local function SpinBars(self)
    StopBars(self)
    if not self.config.rotateActionBars or NS.IsCombatLocked() then return end
    -- The ActionBars addon is optional and loads on its own.
    if not S.VisitPartyActionBars then return end
    self.spinGroups = self.spinGroups or {}
    self.spinning = self.idleSpins or {}
    self.idleSpins = nil
    S.VisitPartyActionBars(SpinBar, self)
    if next(self.spinning) then
        self.context:Event("PLAYER_REGEN_DISABLED", OnCombatEdge, IN_COMBAT)
    else
        self.idleSpins, self.spinning = self.spinning, nil
    end
end

------------------------------------------------------------------ banner
-- Also the end of the banner's duration (ctx:After in Play).
local function Stop(self)
    self.context:Cancel(Stop)
    StopBars(self)
    if not self.host then return end
    self.host:Hide()
    for _, group in ipairs(self.animations) do group:Stop() end
end

local function Layout(self, text)
    local c = self.config
    self.host:ClearAllPoints()
    self.host:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
    self.host:SetScale(c.scale / 100)
    S.SetFont(self.title, nil, c.fontSize, "OUTLINE")
    self.title:SetText(text or S.Text("Celebrate!"))
end

-- text names the moment; without one the banner shows its own greeting.
function M:Play(text)
    if not self.active then return end
    Build(self)
    Stop(self)
    Layout(self, text)
    self.host:Show()
    for _, group in ipairs(self.animations) do group:Play() end
    SpinBars(self)
    self.context:After(self.config.duration, Stop)
end

------------------------------------------------------------------ triggers
local Schedule

local function Surprise(self)
    self:Play()
    Schedule(self)
end

-- Random surprises: the next one comes after 80-120 percent of the chosen
-- interval; one deadline at a time, none in Edit Mode.
Schedule = function(self)
    local c = self.config
    if not self.active or not c.random or S.editMode then
        self.context:Cancel(Surprise)
        return
    end
    local delay = math.random(math.floor(c.interval * .8), math.ceil(c.interval * 1.2))
    self.context:After(delay, Surprise)
end

local function OnLevel(self, _, level)
    if S.Finite(level) then self:Play(S.Text("Level %d"):format(level)) else self:Play() end
end

local function OnAchievement(self, _, achievementID, alreadyEarned)
    -- An achievement the account had already earned is no new moment.
    if not S.Finite(achievementID) or S.Public(alreadyEarned) and alreadyEarned == true then return end
    local _, name = GetAchievementInfo(achievementID)
    self:Play(S.PublicText(name))
end

local function LustName(spell)
    return S.PublicText(C_Spell.GetSpellName(spell))
end

-- Registered for player and pet only: their spell IDs are readable.
local function OnCast(self, _, _, _, spell)
    if S.Finite(spell) and LUST[spell] then self:Play(LustName(spell)) end
end

-- A group member's Bloodlust reaches you as its buff. Restricted auras carry
-- secret spell IDs and are skipped; full updates (login, zoning) are not new.
-- Your own or your pet's Bloodlust already played from its cast while that
-- trigger is on, so its buff does not play the banner a second time.
local function OnAura(self, _, _, info)
    if type(info) ~= "table" or info.isFullUpdate == true then return end
    local added = info.addedAuras
    if type(added) ~= "table" then return end
    for i = 1, #added do
        local aura = added[i]
        local spell = aura.spellId
        if S.Finite(spell) and LUST[spell] then
            local own = aura.isFromPlayerOrPlayerPet
            if not (self.config.onLust and S.Public(own) and own == true) then self:Play(LustName(spell)) end
            return
        end
    end
end

local function Listen(self, event, on, callback, units)
    if on then self.context:Event(event, callback, nil, units) else self.context:RemoveEvent(event) end
end

function M:Refresh()
    local c = self.config
    Build(self)
    Stop(self)
    Listen(self, "PLAYER_LEVEL_UP", c.onLevelUp, OnLevel)
    Listen(self, "ACHIEVEMENT_EARNED", c.onAchievement, OnAchievement)
    Listen(self, "UNIT_SPELLCAST_SUCCEEDED", c.onLust, OnCast, OWN_UNITS)
    Listen(self, "UNIT_AURA", c.onGroupLust, OnAura, "player")
    Schedule(self)
    if S.editMode then
        Layout(self)
        self.host:Show()
    end
end

function M:HideEditPreview() Stop(self) end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "effect", { label = "Celebrations", order = 655,
        getFrame = function() return self.host end, xKey = "x", yKey = "y", point = "CENTER",
        sizeKeys = { "scale" } })
end

function M:Enable()
    self:Refresh()
    self:RegisterMovers()
end

-- The context's Release drops the next surprise.
function M:Disable()
    Stop(self)
end

function M:Preview() self:Play() end

S.Install(ID, M)
