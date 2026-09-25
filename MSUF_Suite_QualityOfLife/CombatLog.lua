local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local Public = S.Public
-- LoggingCombat(state) exists on every client; the C_ChatInfo query is newer.
local SetLogging = type(LoggingCombat) == "function" and LoggingCombat or nil
local QueryLogging = C_ChatInfo and C_ChatInfo.IsLoggingCombat or SetLogging
local GetInstanceInfo = GetInstanceInfo
local STOP_DELAY = 30
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_DIFFICULTY_CHANGED", "UPDATE_INSTANCE_INFO",
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET",
}

-- Unknown difficulties are intentionally left alone. New client difficulties
-- should not silently disable a log that the player or another addon started.
local dungeon = {
    [1] = "dungeonNormal",
    [150] = "dungeonNormal",
    [216] = "dungeonNormal",
    [2] = "dungeonHeroic",
    [23] = "dungeonMythic",
    [8] = "dungeonMythicPlus",
    [24] = "dungeonTimewalking",
}
local raid = {
    [7] = "raidLFR",
    [17] = "raidLFR",
    [151] = "raidLFR",
    [3] = "raidNormal",
    [4] = "raidNormal",
    [9] = "raidNormal",
    [14] = "raidNormal",
    [220] = "raidNormal",
    [5] = "raidHeroic",
    [6] = "raidHeroic",
    [15] = "raidHeroic",
    [16] = "raidMythic",
    [233] = "raidMythic",
    [33] = "raidTimewalking",
}

local function LoggingState()
    if not QueryLogging then return nil end
    local enabled = QueryLogging()
    if not Public(enabled) or type(enabled) ~= "boolean" then return nil end
    return enabled
end

local function Decision(config)
    if type(GetInstanceInfo) ~= "function" then return nil end
    local _, instanceType, difficulty = GetInstanceInfo()
    if not Public(instanceType) then return nil end
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
        NS.Print(S.Text(enabled and "Combat logging started." or "Combat logging stopped."))
    end
end

local function CancelStop(self)
    local timer = self.stopTimer
    self.stopTimer = nil
    if timer then timer:Cancel() end
end

local function StopOwned(self)
    if not self.startedBySuite then return end
    if LoggingState() == true then
        SetLogging(false)
        if LoggingState() == false then Notice(self, false) end
    end
    self.startedBySuite = false
end

local function StartLogging(self, current)
    CancelStop(self)
    -- A manual stop during a selected instance wins until the player
    -- leaves that category. No combat-log event stream is sampled.
    if self.startedBySuite and not current then
        self.startedBySuite = false
        self.manualStop = true
    end
    if current or self.manualStop or not SetLogging then return end
    SetLogging(true)
    if LoggingState() == true then
        self.startedBySuite = true
        Notice(self, true)
    end
end

local function ScheduleStop(self)
    if self.stopTimer or not C_Timer or type(C_Timer.NewTimer) ~= "function" then return end
    local timer
    timer = C_Timer.NewTimer(STOP_DELAY, function()
        if self.stopTimer ~= timer or not self.active then return end
        self.stopTimer = nil
        -- Zone and difficulty can change without another reliable event
        -- before the timer fires. Recheck before stopping the log.
        if Decision(self.config) == false then StopOwned(self) end
    end)
    self.stopTimer = timer
end

local function Evaluate(self)
    local wanted = Decision(self.config)
    if wanted == nil then return end
    local current = LoggingState()
    if current == nil then return end
    if wanted then
        StartLogging(self, current)
        return
    end

    self.manualStop = nil
    if not self.startedBySuite or not current then
        self.startedBySuite = false
        CancelStop(self)
        return
    end
    local policy = self.config.stopPolicy
    if policy == 3 then
        -- Leave the log running: the player now owns it.
        CancelStop(self)
        self.startedBySuite = false
    elseif policy == 2 and C_Timer and type(C_Timer.NewTimer) == "function" then
        ScheduleStop(self)
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
    for i = 1, #EVENTS do self.context:Event(EVENTS[i], Evaluate, true) end
    Evaluate(self)
end

function M:Disable()
    CancelStop(self)
    StopOwned(self)
    self.manualStop = nil
end

S.Install("combatLog", M)
