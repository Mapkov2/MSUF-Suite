local _, P = ...
local NS, S = P.NS, P.Suite
local IN_COMBAT = { inCombat = true }
-- The client's secret test (Platform.lua), called directly on the raid
-- health path.
local IsSecret = NS.IsSecret
local M = {}
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
            frame:SetSize(800, 100)
            frame:SetPoint("BOTTOM", RaidWarningFrame, "TOP", 0, 8)
            frame:SetFrameStrata("HIGH")
            frame:EnableMouse(false)
            frame:SetFontObject(GameFontNormalHuge)
            frame:SetJustifyH("CENTER")
            frame:SetInsertMode("TOP")
            frame:SetTimeVisible(10)
            frame:SetFadeDuration(3)
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

local function Announce(self, unit)
    local name = S.PublicText(UnitName(unit))
    if not name then return end
    local message = string.format(S.Text("%s died"), name)
    if self.config.chat ~= false then S.Print(message) end
    if self.config.screen then
        local color = ChatTypeInfo.RAID_WARNING
        self.screen:AddMessage(message, color.r, color.g, color.b)
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
    local exists = UnitExists(unit)
    if IsSecret(exists) or exists ~= true then return end
    states[unit] = dead
    if dead then Announce(self, unit) end
end

-- The unit list and the baseline are reused for every combat.
local function Sync(self, event)
    local afterDeath = self.afterDeath == true and not NS.InCombat(event) and PlayerDead()
    StopWatching(self)
    if not afterDeath and not NS.InCombat(event) then return end
    local grouped, raid = IsInGroup(), IsInRaid()
    if not S.Public(grouped) or grouped ~= true or not S.Public(raid) then return end
    local units = raid and RAID or PARTY
    local watched, baseline = self.watched or {}, self.baseline or {}
    self.watched, self.baseline = watched, baseline
    for i = #watched, 1, -1 do watched[i] = nil end
    for unit in pairs(baseline) do baseline[unit] = nil end
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
            if S.Public(dead) and type(dead) == "boolean" then baseline[unit] = dead end
        end
    end
    self.dead = baseline
    self.afterDeath = afterDeath or nil
    self.context:Event("UNIT_HEALTH", OnHealth, IN_COMBAT, watched)
    self.context:Event("UNIT_FLAGS", OnHealth, IN_COMBAT, watched)
    if afterDeath then
        self.context:Event("PLAYER_ALIVE", PlayerAlive, IN_COMBAT)
        self.context:Event("PLAYER_UNGHOST", PlayerAlive, IN_COMBAT)
    end
end

local function CombatEnded(self, event)
    if self.dead and PlayerDead() then
        self.afterDeath = true
        Sync(self, event)
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
