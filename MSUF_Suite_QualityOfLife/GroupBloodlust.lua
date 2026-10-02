local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "groupBloodlust"
local IN_COMBAT = { inCombat = true }
local M = {}
local POINTS = NS.AnchorPoints
local Public, Finite = S.Public, S.Finite
-- The client's secret test (Platform.lua), called directly on the player's
-- aura path.
local IsSecret = NS.IsSecret
-- The player lockout auras of MSUF's SATED preset, including the Exhaustion
-- that the Evoker's Fury of the Aspects applies (390435).
local SPELLS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435 }
local SPELL_SET = {}
for i = 1, #SPELLS do SPELL_SET[SPELLS[i]] = true end
-- The native cooldown animates the 10-minute lockout itself. Aura storms
-- need only one fresh status snapshot per short trailing window
-- (self.auraJob).
local AURA_DELAY = .1
local OnAura, OnRestriction, Paint

local CARD = { width = 172, height = 42, fill = { .06, .07, .09, .92 }, edge = 1, line = { .54, .72, .78, .95 } }

local function Create(self)
    if self.host then return end
    local host, background, edges = S.QoLCard(CARD)
    local icon = S.CreateTexture(host, nil, "ARTWORK")
    icon:SetPoint("LEFT", host, "LEFT", 4, 0)
    icon:SetSize(34, 34)
    icon:SetTexture(C_Spell.GetSpellTexture(57724))
    local cooldown = S.CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetMinimumCountdownDuration(0)
    -- A lockout remembered through a restriction ends here, not by an aura event.
    cooldown:SetScript("OnCooldownDone", function() if M.active then Paint(M) end end)
    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -3)
    S.SetFont(title, nil, 11, "OUTLINE")
    title:SetTextColor(.7, .84, .88)
    title:SetText(S.Text("Bloodlust lockout"))
    local status = S.CreateFontString(host, nil, "OVERLAY")
    status:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 2)
    S.SetFont(status, nil, 14, "OUTLINE")
    host:Hide()
    self.host, self.background, self.edges, self.cooldown, self.title, self.status =
        host, background, edges, cooldown, title, status
end

local function Place(self)
    local c = self.config
    local style = S.PaintQoLCard(ID, c, self.background, self.edges)
    self.title:SetTextColor(S.RGB(style.muted))
    self.host:SetSize(c.width, c.height)
    S.PlaceHost(self.host, c)
end

-- Combat, encounter, keystone and PvP restrictions turn these auras secret
-- unless Blizzard flags a spell otherwise, and GetPlayerAuraBySpellID then
-- returns nothing (RequiresNonSecretAura): "no aura" would read as Ready.
-- C_Secrets tells the two apart before any aura is read.
local function Readable()
    for i = 1, #SPELLS do
        local secret = C_Secrets.ShouldSpellAuraBeSecret(SPELLS[i])
        if not Public(secret) or secret ~= false then return false end
    end
    return true
end

local function LockoutAura()
    for i = 1, #SPELLS do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(SPELLS[i])
        if aura then return aura end
    end
end

-- While the auras are unreadable, aura events carry nothing usable; the
-- end of the restriction (OnRestriction) reads again.
local function WatchAuras(self, readable)
    if readable then
        self.context:Event("UNIT_AURA", OnAura, IN_COMBAT, "player")
    else
        self.context:RemoveEvent("UNIT_AURA")
    end
end

-- A lockout seen before the restriction keeps counting down; once it has
-- run out, the state stays unknown until the auras are readable again.
local function PaintUnreadable(self)
    local now = GetTime()
    if self.lockedUntil and now < self.lockedUntil then
        self.host:Show()
        return
    end
    self.lockedUntil = nil
    self.cooldown:Clear()
    if self.config.onlyWhenLocked then
        self.host:Hide()
        return
    end
    self.status:SetText(S.Text("Unknown"))
    self.status:SetTextColor(S.RGB(S.QoLStyle(self.config).muted))
    self.host:Show()
end

local function PaintLocked(self, aura)
    self.status:SetText(S.Text("Locked"))
    self.status:SetTextColor(1, .65, .3)
    local duration, expiration = aura.duration, aura.expirationTime
    if Finite(duration) and duration > 0 and Finite(expiration)
        and expiration > duration then
        self.cooldown:SetCooldown(expiration - duration, duration)
        self.lockedUntil = expiration
    else
        self.cooldown:Clear()
        self.lockedUntil = nil
    end
    self.host:Show()
end

Paint = function(self)
    if not self.active then return end
    if S.editMode and not NS.IsCombatLocked() then
        self.status:SetText(S.Text("Locked"))
        self.status:SetTextColor(1, .65, .3)
        self.cooldown:Clear()
        self.host:Show()
        return
    end
    if not self.grouped then
        self.cooldown:Clear()
        self.host:Hide()
        return
    end
    local readable = Readable()
    WatchAuras(self, readable)
    if not readable then
        PaintUnreadable(self)
        return
    end
    local aura = LockoutAura()
    self.auraInstanceID = aura and Finite(aura.auraInstanceID) and aura.auraInstanceID or nil
    self.unknownInstanceID = aura ~= nil and self.auraInstanceID == nil
    if aura then
        PaintLocked(self, aura)
    else
        self.lockedUntil = nil
        self.cooldown:Clear()
        if self.config.onlyWhenLocked then
            self.host:Hide()
        else
            self.status:SetText(S.Text("Ready"))
            self.status:SetTextColor(.38, .88, .55)
            self.host:Show()
        end
    end
end

-- Whether an aura delta can change the lockout: a full update, an added
-- lockout spell, or an update or removal of the tracked lockout instance
-- (any update or removal while that instance is unknown). UNIT_AURA is only
-- registered while the lockout spells are readable (C_Secrets), and every
-- restriction change reads again (OnRestriction), so an added aura with a
-- secret spell ID cannot be a lockout: in raid combat most added auras are
-- such secret buffs, and each one used to read every lockout spell. A field
-- the delta leaves out is nil, which is never secret.
local function TouchesLockout(ids, tracked, unknown)
    if ids == nil then return false end
    if IsSecret(ids) or type(ids) ~= "table" then return true end
    -- An unreadable lockout instance cannot be matched to updates/removals,
    -- but an added-only delta can still be excluded by its public spells.
    if unknown and #ids > 0 then return true end
    if tracked then
        for i = 1, #ids do
            local instanceID = ids[i]
            if not Finite(instanceID) or instanceID == tracked then return true end
        end
    end
    return false
end

local function Relevant(updateInfo, tracked, unknown)
    if IsSecret(updateInfo) or type(updateInfo) ~= "table" then return true end
    local full = updateInfo.isFullUpdate
    if IsSecret(full) or full then return true end
    local added = updateInfo.addedAuras
    if added ~= nil then
        if IsSecret(added) or type(added) ~= "table" then return true end
        for i = 1, #added do
            local aura = added[i]
            if IsSecret(aura) or type(aura) ~= "table" then return true end
            local spellID = aura.spellId
            if not IsSecret(spellID) and (not Finite(spellID) or SPELL_SET[spellID]) then return true end
        end
    end
    return TouchesLockout(updateInfo.updatedAuraInstanceIDs, tracked, unknown)
        or TouchesLockout(updateInfo.removedAuraInstanceIDs, tracked, unknown)
end

OnAura = function(self, _, unit, updateInfo)
    if IsSecret(unit) or unit ~= "player" or self.auraJob.pending
        or not Relevant(updateInfo, self.auraInstanceID, self.unknownInstanceID) then return end
    self.auraJob:Request()
end

-- ADDON_RESTRICTION_STATE_CHANGED fires before a restriction is enforced and
-- after it is lifted (RestrictedActionsDocumentation.lua). A lifted one is
-- read now; an activating one after its dispatch, when the lockout spells
-- may have turned secret.
OnRestriction = function(self, _, _, state)
    if not IsSecret(state) and state == Enum.AddOnRestrictionState.Inactive then
        self.auraJob:Clear()
        Paint(self)
    else
        self.auraJob:Request()
    end
end

local function PaintAuras(self)
    if self.grouped then Paint(self) end
end

local function OnGroup(self)
    -- Roster, settings and combat-end edges paint fresh immediately, consuming
    -- any request whose callback is still in flight.
    self.auraJob:Clear()
    local grouped = IsInGroup()
    self.grouped = Public(grouped) and grouped == true
    if self.grouped then
        -- Combat end lifts the most common restriction; read again then.
        self.context:Event("PLAYER_REGEN_ENABLED", OnGroup, IN_COMBAT)
        self.context:Event("ADDON_RESTRICTION_STATE_CHANGED", OnRestriction, IN_COMBAT)
    else
        self.context:RemoveEvent("UNIT_AURA")
        self.context:RemoveEvent("ADDON_RESTRICTION_STATE_CHANGED")
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
        self.auraInstanceID, self.unknownInstanceID, self.lockedUntil = nil, nil, nil
    end
    Paint(self)
end

function M:Enable()
    self.auraJob = self.context:Coalesce(AURA_DELAY, PaintAuras)
    Create(self)
    Place(self)
    self.context:Event("GROUP_ROSTER_UPDATE", OnGroup, IN_COMBAT)
    self.context:Event("PLAYER_ENTERING_WORLD", OnGroup, IN_COMBAT)
    OnGroup(self)
end

function M:Refresh()
    if not self.host then return end
    S.SetFont(self.title, nil, 11, "OUTLINE")
    S.SetFont(self.status, nil, 14, "OUTLINE")
    Place(self)
    OnGroup(self)
end

function M:Disable()
    self.context:RemoveEvent("UNIT_AURA")
    self.context:RemoveEvent("ADDON_RESTRICTION_STATE_CHANGED")
    self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
    self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.grouped, self.auraInstanceID, self.unknownInstanceID, self.lockedUntil = nil, nil, nil, nil
    -- The context's Release drops a pending aura repaint.
    if self.host then
        self.cooldown:Clear()
        self.host:Hide()
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "lockout", {
        label = "Bloodlust lockout", order = 637,
        getFrame = function() return self.host end,
        xKey = "x", yKey = "y", pointKey = "point",
        point = function() return POINTS[self.config.point] or "CENTER" end,
        quickPosition = true, historyKeys = { "width", "height", "scale" },
        sizeKeys = { "width", "height", "scale" },
    })
end

S.Install(ID, M)
