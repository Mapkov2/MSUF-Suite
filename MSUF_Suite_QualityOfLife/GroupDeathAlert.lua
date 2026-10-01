local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local PARTY, RAID = {}, {}
for i = 1, 4 do PARTY[i] = "party" .. i end
for i = 1, 40 do RAID[i] = "raid" .. i end

local function StopWatching(self)
    self.context:RemoveEvent("UNIT_HEALTH")
    self.context:RemoveEvent("UNIT_FLAGS")
    self.groupKind = nil
    self.dead = nil
end

local function OnHealth(self, _, unit)
    if not self.active or not self.dead or not S.PublicText(unit) then return end
    if self.dead[unit] == nil then return end
    local exists = UnitExists(unit)
    if not S.Public(exists) or exists ~= true then return end
    local dead = UnitIsDeadOrGhost(unit)
    if not S.Public(dead) or type(dead) ~= "boolean" then return end
    local before = self.dead[unit]
    self.dead[unit] = dead
    if dead and before == false then
        local name = S.PublicText(UnitName(unit))
        if name then
            local message = string.format(S.Text("%s died"), name)
            if self.config.chat ~= false then S.Print(message) end
            if self.config.screen then
                RaidWarningUtil.AddMessage(message, ChatTypeInfo.RAID_WARNING)
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
    end
end

local function Sync(self, event)
    StopWatching(self)
    if not NS.InCombat(event) then return end
    local grouped, raid = IsInGroup(), IsInRaid()
    if not S.Public(grouped) or grouped ~= true or not S.Public(raid) then return end
    local units = raid and RAID or PARTY
    local watched = {}
    for i = 1, #units do
        local unit = units[i]
        -- Like upstream/live CompactUnitFrame, compare identity rather than
        -- token text. Raid lists include the player; watch that identity only
        -- through "player" below, and skip restricted comparisons.
        local isPlayer = raid and UnitIsUnit(unit, "player")
        if S.Public(isPlayer) and not isPlayer then watched[#watched + 1] = unit end
    end
    if self.config.includePlayer then watched[#watched + 1] = "player" end
    local baseline = {}
    for i = 1, #watched do
        local unit = watched[i]
        local exists = UnitExists(unit)
        if S.Public(exists) and exists == true then
            local dead = UnitIsDeadOrGhost(unit)
            if S.Public(dead) and type(dead) == "boolean" then baseline[unit] = dead end
        end
    end
    self.dead = baseline
    self.context:Event("UNIT_HEALTH", OnHealth, true, watched)
    self.context:Event("UNIT_FLAGS", OnHealth, true, watched)
end

function M:Enable()
    self.context:Event("PLAYER_REGEN_DISABLED", Sync, true)
    self.context:Event("PLAYER_REGEN_ENABLED", StopWatching, true)
    self.context:Event("GROUP_ROSTER_UPDATE", Sync, true)
    Sync(self)
end

function M:Refresh()
    Sync(self)
end

function M:Disable()
    StopWatching(self)
end

S.Install("groupDeathAlert", M)
