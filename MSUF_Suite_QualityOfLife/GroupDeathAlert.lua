local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
-- The client's secret test (Platform.lua), called directly on the raid
-- health path.
local IsSecret = NS.IsSecret
local M = {}
local PENDING_DEATH = "pending"
local PARTY, RAID = {}, {}
for i = 1, 4 do PARTY[i] = "party" .. i end
for i = 1, 40 do RAID[i] = "raid" .. i end

-- Blizzard's RaidWarningFrame owns a shared Lua pool. BuffFrame.lua reads it
-- through RaidWarningUtil.UpdateCenterScreenAnchors after updating deadly
-- debuffs; addon messages there can taint the following aura update/scripts.
-- An owned MessageFrame keeps the warning text and fading in the native C UI.
local function PrepareScreen(self)
    if self.config.screen then
        if not self.screen then
            local frame = S.CreateFrame("MessageFrame", "MSUFSuiteGroupDeathAlerts", UIParent)
            frame:SetSize(960, 210)
            frame:SetPoint("TOP", UIParent, "CENTER", 0, 160)
            frame:SetFrameStrata("HIGH")
            frame:EnableMouse(false)
            S.SetFont(frame, nil, 36, "OUTLINE")
            frame:SetShadowColor(0, 0, 0, 1)
            frame:SetShadowOffset(2, -2)
            frame:SetJustifyH("CENTER")
            frame:SetInsertMode("TOP")
            frame:SetSpacing(6)
            frame:SetTimeVisible(6)
            frame:SetFadeDuration(1)
            frame:SetFading(true)
            self.screen = frame
        end
        self.screen:Show()
    elseif self.screen then
        self.screen:Clear()
        self.screen:Hide()
    end
end

local function StopWatching(self)
    self.context:RemoveEvent("UNIT_HEALTH")
    self.context:RemoveEvent("UNIT_FLAGS")
    self.context:RemoveEvent("UNIT_DIED")
    self.context:RemoveEvent("PLAYER_ALIVE")
    self.context:RemoveEvent("PLAYER_UNGHOST")
    self.groupKind = nil
    self.dead = nil
    self.afterDeath = nil
end

-- The player leaves combat by dying (PLAYER_REGEN_ENABLED), but a wipe goes
-- on without them: the other deaths are still told until the player is
-- alive again.
local function PlayerDead()
    local dead = UnitIsDeadOrGhost("player")
    return S.Public(dead) and dead == true
end

-- A release keeps the player a ghost; a resurrection ends the watch.
local function PlayerAlive(self)
    if not (self.afterDeath and PlayerDead()) then StopWatching(self) end
end

local function WatchAfterDeath(self)
    self.afterDeath = true
    self.context:Event("PLAYER_ALIVE", PlayerAlive, IN_COMBAT)
    self.context:Event("PLAYER_UNGHOST", PlayerAlive, IN_COMBAT)
end

local function Announce(self, unit)
    -- UnitDocumentation: UnitName may be identity-restricted. Keep public
    -- roster names by GUID, never by a token that can become another member.
    local guid = self.identities[unit]
    local name = S.PublicText(UnitName(unit)) or (guid and self.names[guid])
    local message = name and string.format(S.Text("%s died"), name) or S.Text("A group member died")
    if self.config.chat ~= false then S.Print(message) end
    if self.config.screen then
        self.screen:AddMessage("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:32|t " .. message, 1, .2, .2)
    end
    if self.config.sound then
        local now = GetTime()
        -- Several simultaneous deaths are one audible notice, not a
        -- stack of overlapping sounds. No timer runs between deaths.
        if S.Finite(now) and (not self.lastSoundAt or now - self.lastSoundAt >= 1) then
            self.lastSoundAt = now
            PlaySound(SOUNDKIT.RAID_WARNING, "Master")
        end
    end
end

-- Every raid member's UNIT_HEALTH and UNIT_FLAGS lands here in combat. A tick
-- that leaves the stored state as it was costs two client calls: the secret
-- test of the token (a table key) and UnitIsDeadOrGhost with the secret test
-- of its answer. Only a change asks UnitExists: a token whose unit is gone
-- reads alive and must leave the stored state alone, as before.
local function OnHealth(self, _, unit)
    local states = self.dead
    if not states or not self.active or IsSecret(unit) then return end
    local before = states[unit]
    if before == nil then return end
    local dead = UnitIsDeadOrGhost(unit)
    if IsSecret(dead) or type(dead) ~= "boolean" or dead == before then return end
    -- UNIT_DIED can precede the public dead flag. A stale alive answer is
    -- not a resurrection; wait for dead -> alive before rearming the alert.
    if before == PENDING_DEATH and not dead then return end
    local exists = UnitExists(unit)
    if IsSecret(exists) or exists ~= true then return end
    if dead then
        local feigned = UnitIsFeignDeath(unit)
        if IsSecret(feigned) or feigned == true then return end
    end
    states[unit] = dead
    if dead and before ~= PENDING_DEATH then Announce(self, unit) end
end

-- In a dungeon or raid a group member who dies stays in combat: the
-- UNIT_HEALTH and UNIT_FLAGS of that moment can still read them alive, and
-- the next flag change is the end of combat, so the death was told only
-- then. The client tells the death itself with UNIT_DIED (UnitDocumentation
-- .lua, live and forever). Its GUID is used only when identity is public
-- (SecretWhenUnitIdentityRestricted); every other unit that dies near the
-- group costs one secret test or one table miss. A death already told
-- through OnHealth reads dead here and is not told twice.
local function OnDied(self, _, guid)
    local states = self.dead
    if not states or not self.active or IsSecret(guid) then return end
    local unit = self.guids[guid]
    if not unit or states[unit] ~= false then return end
    -- Feign Death is not a death.
    local feigned = UnitIsFeignDeath(unit)
    if IsSecret(feigned) or feigned == true then return end
    states[unit] = PENDING_DEATH
    Announce(self, unit)
end

local function PreviousStates(self)
    local previous = self.previous or {}
    self.previous = previous
    for guid in pairs(previous) do previous[guid] = nil end
    if self.dead then
        for guid, unit in pairs(self.guids) do previous[guid] = self.dead[unit] end
    end
    return previous
end

-- Reuse the roster tables, preserving combat history by public GUID even
-- when raid tokens move. Idle roster updates cache names without health
-- listeners. A newly joined dead member remains a silent baseline.
local function PrepareRoster(self, raid, previous)
    local units = raid and RAID or PARTY
    local watched, baseline, guids = self.watched or {}, self.baseline or {}, self.guids or {}
    local identities, names = self.identities or {}, self.names or {}
    self.watched, self.baseline, self.guids = watched, baseline, guids
    self.identities, self.names = identities, names
    for i = #watched, 1, -1 do watched[i] = nil end
    for unit in pairs(baseline) do baseline[unit] = nil end
    for guid in pairs(guids) do guids[guid] = nil end
    for unit in pairs(identities) do identities[unit] = nil end
    for i = 1, #units do
        local unit = units[i]
        -- Like upstream/live CompactUnitFrame, compare identity rather than
        -- token text. Raid lists include the player; watch that identity only
        -- through "player" below, and skip restricted comparisons.
        local isPlayer = raid and UnitIsUnit(unit, "player")
        if S.Public(isPlayer) and not isPlayer then watched[#watched + 1] = unit end
    end
    if self.config.includePlayer then watched[#watched + 1] = "player" end
    for i = 1, #watched do
        local unit = watched[i]
        local exists = UnitExists(unit)
        if S.Public(exists) and exists == true then
            local dead = UnitIsDeadOrGhost(unit)
            if S.Public(dead) and type(dead) == "boolean" then
                local guid = S.PublicText(UnitGUID(unit))
                local before = guid and previous[guid]
                if before == nil then baseline[unit] = dead else baseline[unit] = before end
                if guid then
                    guids[guid], identities[unit] = unit, guid
                    names[guid] = S.PublicText(UnitName(unit)) or names[guid]
                end
            end
        end
    end
    for guid in pairs(names) do
        if not guids[guid] then names[guid] = nil end
    end
end

local function Sync(self, event)
    local afterDeath = self.afterDeath == true and not NS.InCombat(event) and PlayerDead()
    local continuing, previous = self.dead ~= nil, PreviousStates(self)
    -- Context:Event does not change an existing unit filter. Re-register it
    -- after roster/includePlayer changes, while retaining the GUID history.
    StopWatching(self)
    local grouped, raid = IsInGroup(), IsInRaid()
    if not S.Public(grouped) or grouped ~= true or not S.Public(raid) then return end
    PrepareRoster(self, raid, previous)
    if not afterDeath and not NS.InCombat(event) then return end
    self.dead = self.baseline
    local watched = self.watched
    self.context:Event("UNIT_HEALTH", OnHealth, IN_COMBAT, watched)
    self.context:Event("UNIT_FLAGS", OnHealth, IN_COMBAT, watched)
    self.context:Event("UNIT_DIED", OnDied, IN_COMBAT)
    if afterDeath then WatchAfterDeath(self) end
    if continuing then
        for i = 1, #watched do OnHealth(self, event, watched[i]) end
    end
end

-- The player's own death ends their combat, possibly before the client told
-- it or the deaths around it. The watch keeps its states, so each of those
-- still reads as a change from alive.
local function CombatEnded(self)
    if self.dead and PlayerDead() then
        WatchAfterDeath(self)
    else
        StopWatching(self)
    end
end

function M:Enable()
    PrepareScreen(self)
    self.context:Event("PLAYER_REGEN_DISABLED", Sync, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", CombatEnded, IN_COMBAT)
    self.context:Event("GROUP_ROSTER_UPDATE", Sync, IN_COMBAT)
    Sync(self)
end

function M:Refresh()
    PrepareScreen(self)
    Sync(self)
end

function M:Disable()
    StopWatching(self)
    if self.screen then
        self.screen:Clear()
        self.screen:Hide()
    end
end

S.Install("groupDeathAlert", M)
