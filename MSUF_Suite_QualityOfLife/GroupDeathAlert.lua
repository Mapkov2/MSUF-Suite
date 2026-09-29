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
        if name then S.Print(string.format(S.Text("%s died"), name)) end
    end
end

local function Sync(self, event)
    StopWatching(self)
    if event ~= "PLAYER_REGEN_DISABLED" and not NS.IsCombatLocked() then return end
    local grouped, raid = IsInGroup(), IsInRaid()
    if not S.Public(grouped) or grouped ~= true or not S.Public(raid) then return end
    local units = raid and RAID or PARTY
    local watched = {}
    for i = 1, #units do watched[i] = units[i] end
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
