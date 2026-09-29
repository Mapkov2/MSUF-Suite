local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local COMMANDS = { raid = "MSUFSUITERAID", pull = "MSUFSUITEPULL", mark = "MSUFSUITEMARK" }
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local AUTO_ROLES = { { "autoMarkTank", "TANK", "tankMarker" },
    { "autoMarkHealer", "HEALER", "healerMarker" } }

local function Permitted()
    local grouped, leader, assistant = IsInGroup(), UnitIsGroupLeader("player"), UnitIsGroupAssistant("player")
    return S.Public(grouped) and grouped == true and S.Public(leader) and S.Public(assistant)
        and (leader == true or assistant == true)
end

local function OpenRaidManager()
    if not M.active then return end
    local frame = _G.CompactRaidFrameManager
    local visible = frame and frame:IsShown()
    if not S.Public(visible) or visible ~= true then
        S.Print(S.Text("Enable Blizzard's Raid Manager in MSUF group settings"))
        return
    end
    if not pcall(CompactRaidFrameManager_Expand) then
        S.Print(S.Text("Raid Manager could not be opened by the client."))
    end
end

local function StartPull(message)
    if not M.active or not S.Public(message) or type(message) ~= "string" then return end
    if not Permitted() then
        S.Print(S.Text("Group leader or assistant required"))
        return
    end
    local seconds = message:match("^%s*(%d*)%s*$")
    seconds = seconds == "" and 10 or tonumber(seconds)
    if not S.Finite(seconds) or seconds < 1 or seconds > 60 then
        S.Print(S.Text("Usage: /msufpull [1-60]"))
        return
    end
    local ok, started = pcall(C_PartyInfo.DoCountdown, seconds)
    if not ok or S.Public(started) and started == false then
        S.Print(S.Text("Countdown could not be started"))
    end
end

local function UniqueRole(role)
    local found
    for i = 1, #PARTY_UNITS do
        local unit = PARTY_UNITS[i]
        local exists = UnitExists(unit)
        if not S.Public(exists) then return nil end
        if exists == true then
            local assigned = S.PublicText(UnitGroupRolesAssigned(unit))
            if not assigned then return nil end
            if assigned == role then
                if found then return nil end
                found = unit
            end
        end
    end
    return found
end

local function MarkRole(message)
    if not M.active or not S.Public(message) or type(message) ~= "string" then return end
    local role = message:lower():match("^%s*(%a+)%s*$")
    if role ~= "tank" and role ~= "healer" then
        S.Print(S.Text("Usage: /msufmark tank|healer"))
        return
    end
    local raid = IsInRaid()
    if not S.Public(raid) or raid == true or not Permitted() then
        S.Print(S.Text("Party leader or assistant required"))
        return
    end
    local unit = UniqueRole(role == "tank" and "TANK" or "HEALER")
    if not unit then
        S.Print(S.Text("Exactly one party member with that role is required"))
        return
    end
    local marker = role == "tank" and M.config.tankMarker or M.config.healerMarker
    if not S.Finite(marker) or marker < 1 or marker > 8 then return end
    local existing = GetRaidTargetIndex(unit)
    if not S.Public(existing) then return end
    if existing ~= marker and not pcall(SetRaidTarget, unit, marker) then
        S.Print(S.Text("Raid marker could not be set by the client."))
    end
end

local function MarkerFree(marker, wantedUnit)
    for i = 1, #PARTY_UNITS do
        local unit = PARTY_UNITS[i]
        local exists = UnitExists(unit)
        if not S.Public(exists) then return false end
        if exists == true then
            local current = GetRaidTargetIndex(unit)
            if not S.Public(current) then return false end
            if current == marker and unit ~= wantedUnit then return false end
        end
    end
    return true
end

local function AutoMark(self)
    if not self.active or self.autoBlocked or NS.IsCombatLocked() then return end
    local raid = IsInRaid()
    if not S.Public(raid) or raid == true or not Permitted() then return end
    self.autoAttempts = self.autoAttempts or {}
    for _, spec in ipairs(AUTO_ROLES) do
        if self.config[spec[1]] then
            local unit = UniqueRole(spec[2])
            local marker = self.config[spec[3]]
            if unit and S.Finite(marker) and marker >= 1 and marker <= 8 then
                local existing, guid = GetRaidTargetIndex(unit), UnitGUID(unit)
                if S.Public(existing) and S.PublicText(guid) and (not existing or existing == 0)
                    and MarkerFree(marker, unit) then
                    local key = guid .. ":" .. marker
                    if not self.autoAttempts[key] then
                        if (self.autoAttemptCount or 0) >= 128 then
                            self.autoAttempts, self.autoAttemptCount = {}, 0
                        end
                        self.autoAttempts[key] = true
                        self.autoAttemptCount = (self.autoAttemptCount or 0) + 1
                        local ok = pcall(SetRaidTarget, unit, marker)
                        if not ok then
                            self.autoBlocked = true
                            S.Print(S.Text("Automatic raid markers were blocked by the client."))
                            return
                        end
                    end
                end
            end
        end
    end
end

function M:Refresh()
    local c = self.config
    local options = table.concat({ tostring(c.autoMarkTank), tostring(c.autoMarkHealer),
        tostring(c.tankMarker), tostring(c.healerMarker) }, ":")
    if self.autoOptions ~= options then
        self.autoOptions, self.autoBlocked = options, nil
        self.autoAttempts, self.autoAttemptCount = {}, 0
    end
    if self.config.autoMarkTank or self.config.autoMarkHealer then
        self.context:Event("GROUP_ROSTER_UPDATE", AutoMark)
        self.context:Event("PLAYER_ROLES_ASSIGNED", AutoMark)
        self.context:Event("ROLE_CHANGED_INFORM", AutoMark)
        self.context:Event("PLAYER_REGEN_ENABLED", AutoMark)
        AutoMark(self)
    else
        self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
        self.context:RemoveEvent("PLAYER_ROLES_ASSIGNED")
        self.context:RemoveEvent("ROLE_CHANGED_INFORM")
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    end
end

function M:Enable()
    SlashCmdList[COMMANDS.raid] = OpenRaidManager
    SlashCmdList[COMMANDS.pull] = StartPull
    SlashCmdList[COMMANDS.mark] = MarkRole
    _G["SLASH_" .. COMMANDS.raid .. "1"] = "/msufraid"
    _G["SLASH_" .. COMMANDS.pull .. "1"] = "/msufpull"
    _G["SLASH_" .. COMMANDS.mark .. "1"] = "/msufmark"
    self:Refresh()
end

function M:Disable()
    self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
    self.context:RemoveEvent("PLAYER_ROLES_ASSIGNED")
    self.context:RemoveEvent("ROLE_CHANGED_INFORM")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.autoOptions, self.autoAttempts = nil, nil
    self.autoAttemptCount, self.autoBlocked = nil, nil
    for _, command in pairs(COMMANDS) do
        SlashCmdList[command] = nil
        _G["SLASH_" .. command .. "1"] = nil
    end
end

S.Install("groupRaidShortcuts", M)
