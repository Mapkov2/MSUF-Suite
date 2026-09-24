local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}

-- Unknown difficulties are intentionally left alone. New client difficulties
-- should not silently disable a log that the player or another addon started.
local dungeon = {
    [1] = "dungeonNormal", [150] = "dungeonNormal", [216] = "dungeonNormal",
    [2] = "dungeonHeroic", [23] = "dungeonMythic", [8] = "dungeonMythicPlus",
    [24] = "dungeonTimewalking",
}
local raid = {
    [7] = "raidLFR", [17] = "raidLFR", [151] = "raidLFR",
    [3] = "raidNormal", [4] = "raidNormal", [9] = "raidNormal",
    [14] = "raidNormal", [220] = "raidNormal",
    [5] = "raidHeroic", [6] = "raidHeroic", [15] = "raidHeroic",
    [16] = "raidMythic", [233] = "raidMythic", [33] = "raidTimewalking",
}

local function Public(value)
    return not (type(issecretvalue) == "function" and issecretvalue(value))
end

local function LoggingState()
    local query = C_ChatInfo and C_ChatInfo.IsLoggingCombat or LoggingCombat
    if type(query) ~= "function" then return nil end
    local ok, enabled = pcall(query)
    if not ok or not Public(enabled) or type(enabled) ~= "boolean" then return nil end
    return enabled
end

local function Decision(config)
    if type(GetInstanceInfo) ~= "function" then return nil end
    local ok, _, instanceType, difficulty = pcall(GetInstanceInfo)
    if not ok or not Public(instanceType) then return nil end
    if instanceType == "none" then return false end
    if instanceType == "pvp" or instanceType == "arena" then return config.pvp == true end
    if instanceType == "scenario" then return config.scenario == true end
    if instanceType == "delve" then return config.delve == true end
    if not Public(difficulty) or type(difficulty) ~= "number" then return nil end
    local key = instanceType == "party" and dungeon[difficulty]
        or instanceType == "raid" and raid[difficulty]
    if not key then return nil end
    return config[key] == true
end

local function Notice(self, enabled)
    if self.config.chatNotice and type(NS.Print) == "function" then
        NS.Print(enabled and "Combat logging started." or "Combat logging stopped.")
    end
end

local function CancelStop(self)
    local timer = self.stopTimer
    self.stopTimer = nil
    if timer and type(timer.Cancel) == "function" then timer:Cancel() end
end

local function StopOwned(self)
    if not self.startedBySuite then return end
    local current = LoggingState()
    if current == true then
        local ok = pcall(LoggingCombat, false)
        if ok and LoggingState() == false then Notice(self, false) end
    end
    self.startedBySuite = false
end

local function Evaluate(self)
    local wanted = Decision(self.config)
    if wanted == nil then return end
    local current = LoggingState()
    if current == nil then return end

    if wanted then
        CancelStop(self)
        -- A manual stop during a selected instance wins until the player
        -- leaves that category. No combat-log event stream is sampled.
        if self.startedBySuite and not current then
            self.startedBySuite = false
            self.manualStop = true
        end
        if current or self.manualStop then return end
        if pcall(LoggingCombat, true) and LoggingState() == true then
            self.startedBySuite = true
            Notice(self, true)
        end
        return
    end

    self.manualStop = nil
    if not self.startedBySuite then CancelStop(self); return end
    if not current then
        self.startedBySuite = false
        CancelStop(self)
        return
    end
    local policy = self.config.stopPolicy
    if policy == 3 then
        CancelStop(self)
        self.startedBySuite = false
    elseif policy == 2 and C_Timer and type(C_Timer.NewTimer) == "function" then
        if self.stopTimer then return end
        local timer
        timer = C_Timer.NewTimer(30, function()
            if self.stopTimer ~= timer or not self.active then return end
            self.stopTimer = nil
            -- Zone and difficulty can change without another reliable event
            -- before the timer fires. Recheck before stopping the log.
            if Decision(self.config) == false then StopOwned(self) end
        end)
        self.stopTimer = timer
    else
        CancelStop(self)
        StopOwned(self)
    end
end

function M:Refresh()
    CancelStop(self)
    Evaluate(self)
end

function M:Enable()
    self.startedBySuite = false
    self.manualStop = nil
    local context = self.context
    local function Changed(module) Evaluate(module) end
    context:Event("PLAYER_ENTERING_WORLD", Changed, true)
    context:Event("ZONE_CHANGED_NEW_AREA", Changed, true)
    context:Event("PLAYER_DIFFICULTY_CHANGED", Changed, true)
    context:Event("UPDATE_INSTANCE_INFO", Changed, true)
    context:Event("CHALLENGE_MODE_START", Changed, true)
    context:Event("CHALLENGE_MODE_COMPLETED", Changed, true)
    context:Event("CHALLENGE_MODE_RESET", Changed, true)
    Evaluate(self)
end

function M:Disable()
    CancelStop(self)
    StopOwned(self)
    self.manualStop = nil
end

S.Install("combatLog", M)
