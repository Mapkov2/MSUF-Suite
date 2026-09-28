local _, P = ...
local NS, S = P.NS, P.Suite
local O = P.Objectives
local M, SOURCES = O.M, O.SOURCES
local Create, Render, CollectDirty = O.Create, O.Render, O.CollectDirty
local MythicPlus = S.MythicPlus
local Raid = S.Raid
local Public = S.Public
local ID = "objectives"

-- The objective tracker module: events, the refresh flow and the lifecycle
-- (see ObjectivesData.lua for how the files fit together).

------------------------------------------------------------------ refresh flow
local function Flush(self)
    self.scheduled = false
    if not self.active or self.pausedForRaidCombat or self.mplusActive or self.raidActive then return end
    CollectDirty(self)
    Render(self)
end

-- Events in one frame share a single flush through one shared callback.
local function FlushScheduled()
    if M.staleFlushes > 0 then
        M.staleFlushes = M.staleFlushes - 1
        return
    end
    Flush(M)
end

local function Request(self, key)
    if self.pausedForRaidCombat or self.raidActive then return end
    self.dirty[key] = true
    if self.scheduled then return end
    self.scheduled = true
    C_Timer.After(0, FlushScheduled)
end

local function MarkAllDirty(self)
    for i = 1, #SOURCES do self.dirty[SOURCES[i]] = true end
end

-- Waits that were already handed to C_Timer become stale.
local function CancelPending(self)
    if self.scheduled then
        self.staleFlushes = self.staleFlushes + 1
        self.scheduled = false
    end
    if self.timerPending then
        self.staleTimers = self.staleTimers + 1
        self.timerPending = false
    end
end

local function StopMythicPlus(self)
    if not self.mplusActive then return false end
    MythicPlus.Stop(self)
    self.previousFlat = nil
    MarkAllDirty(self)
    return true
end

local function StopRaid(self)
    if not self.raidActive then return false end
    Raid.Stop(self)
    self.previousFlat = nil
    MarkAllDirty(self)
    return true
end

local function ShowRaid(self)
    if not Raid or not Raid.Detect(self) then return false end
    if self.raidActive then return true end
    for _, row in pairs(self.rows) do
        row:Hide()
        row.timerEnd = nil
        if row.timer then row.timer:Hide() end
    end
    CancelPending(self)
    self.timedRows, self.previousFlat = nil, nil
    Raid.Show(self)
    self.scroll:SetVerticalScroll(0)
    Render(self)
    return true
end

local function StartMythicPlus(self, mapID)
    if self.mplusActive and self.mplus and self.mplus.mapID == mapID and not self.mplus.completed then
        return false
    end
    for _, row in pairs(self.rows) do
        row:Hide()
        row.timerEnd = nil
        if row.timer then row.timer:Hide() end
    end
    CancelPending(self)
    self.timedRows = nil
    self.previousFlat = nil
    MythicPlus.Start(self, mapID)
    self.scroll:SetVerticalScroll(0)
    Render(self)
    return true
end

-- Which sources an event can change. Quest log updates also carry world
-- quest and bonus objective progress, like in Blizzard's own tracker.
local EVENT_SOURCES = {
    SCENARIO_UPDATE = { "scenario" },
    SCENARIO_CRITERIA_UPDATE = { "scenario" },
    ACTIVE_DELVE_DATA_UPDATE = { "scenario" },
    TRACKED_ACHIEVEMENT_UPDATE = { "achievements" },
    CRITERIA_UPDATE = { "achievements" },
    ACHIEVEMENT_EARNED = { "achievements" },
    CONTENT_TRACKING_UPDATE = { "achievements" },
    ZONE_CHANGED = { "world", "bonus" },
    ZONE_CHANGED_INDOORS = { "world", "bonus" },
    SUPER_TRACKING_CHANGED = { "quests" },
    QUEST_POI_UPDATE = { "quests" },
    QUEST_WATCH_UPDATE = { "quests", "world" },
    QUEST_WATCH_LIST_CHANGED = { "quests", "world" },
    SCENARIO_BONUS_VISIBILITY_UPDATE = { "bonus", "scenario" },
    SCENARIO_POI_UPDATE = {},
    CHALLENGE_MODE_DEATH_COUNT_UPDATED = {},
}
local QUEST_LOG_SOURCES = { "quests", "world", "bonus" }

local function MythicPlusEvent(self, event)
    if event == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
        MythicPlus.UpdateDeaths(self)
    elseif event == "SCENARIO_UPDATE" or event == "SCENARIO_CRITERIA_UPDATE" or event == "SCENARIO_POI_UPDATE" then
        MythicPlus.UpdateObjectives(self)
    end
end

local UpdateRaidCombatPause
local function Event(self, event, ...)
    if event == "ENCOUNTER_START" then
        local encounterID, encounterName, difficultyID = ...
        if ShowRaid(self) and Raid.Start(self, encounterID, encounterName, difficultyID) then
            Render(self)
        end
        return
    elseif event == "ENCOUNTER_END" then
        if self.raidActive then
            Raid.End(self, ...)
            Render(self)
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if UpdateRaidCombatPause(self) then return end
    elseif self.pausedForRaidCombat then
        return
    end
    if event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_COMPLETED_REWARDS" then
        if self.mplusActive then
            MythicPlus.Complete(self)
            Render(self)
        end
        return
    elseif event == "CHALLENGE_MODE_RESET" then
        if StopMythicPlus(self) then Flush(self) end
        return
    elseif event == "CHALLENGE_MODE_START" or event == "WORLD_STATE_TIMER_START" or event == "WORLD_STATE_TIMER_STOP" then
        local mapID = MythicPlus and MythicPlus.Detect(self)
        if mapID then
            StopRaid(self)
            StartMythicPlus(self, mapID)
        end
        if self.mplusActive then MythicPlus.Tick(self) end
        return
    end
    local newArea = event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
    if newArea then
        self:SuppressNative()
        local mapID = MythicPlus and MythicPlus.Detect(self)
        if mapID then
            StopRaid(self)
            StartMythicPlus(self, mapID)
        elseif Raid and Raid.Detect(self) then
            StopMythicPlus(self)
            ShowRaid(self)
        else
            local stoppedKey, stoppedRaid = StopMythicPlus(self), StopRaid(self)
            if stoppedKey or stoppedRaid then
                Flush(self)
                return
            end
        end
    end
    if self.raidActive then return end
    if self.mplusActive then
        MythicPlusEvent(self, event)
        return
    end
    if newArea then
        for i = 1, #SOURCES do Request(self, SOURCES[i]) end
        return
    end
    local sources = EVENT_SOURCES[event] or QUEST_LOG_SOURCES
    for i = 1, #sources do Request(self, sources[i]) end
end

------------------------------------------------------------------ lifecycle
-- Blizzard's tracker stays hidden by an alpha-zero, mouse-disabled frame
-- under a hidden parent; the context restores both on disable.
function M:SuppressNative()
    if not self.active or NS.IsCombatLocked() then return end
    -- Blizzard_ObjectiveTracker loads at startup on every supported client.
    local native = ObjectiveTrackerFrame
    if NS.Safety.IsForbidden(native) then return end
    if not self.nativeHiddenParent then
        self.nativeHiddenParent = S.CreateFrame("Frame", nil, UIParent)
        self.nativeHiddenParent:Hide()
    end
    self.context:HideControl(native, true)
    self.context:Property(native, "GetParent", "SetParent", self.nativeHiddenParent)
end

local function LoadCollapseState(self)
    local state = S.ModuleState(ID) or {}
    if type(state.collapsedGroups) ~= "table" then state.collapsedGroups = {} end
    if type(state.collapsedEntries) ~= "table" then state.collapsedEntries = {} end
    self.collapsedGroups, self.collapsedEntries = state.collapsedGroups, state.collapsedEntries
end

local function ContentSignature(c)
    return tostring(c.showWorldQuests) .. ":" .. tostring(c.showBonus) .. ":"
        .. tostring(c.showScenario) .. ":" .. tostring(c.showAchievements) .. ":"
        .. tostring(c.showQuestItems) .. ":" .. tostring(c.showTimers)
end

local TRACKER_EVENTS = {
    "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_WATCH_LIST_CHANGED",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "QUEST_POI_UPDATE", "SCENARIO_BONUS_VISIBILITY_UPDATE",
    "SCENARIO_UPDATE", "SCENARIO_CRITERIA_UPDATE", "ACTIVE_DELVE_DATA_UPDATE", "TRACKED_ACHIEVEMENT_UPDATE",
    "CRITERIA_UPDATE", "ACHIEVEMENT_EARNED", "CONTENT_TRACKING_UPDATE", "SCENARIO_POI_UPDATE",
}
local MYTHIC_PLUS_EVENTS = {
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_COMPLETED_REWARDS", "CHALLENGE_MODE_RESET",
    "CHALLENGE_MODE_DEATH_COUNT_UPDATED", "WORLD_STATE_TIMER_START", "WORLD_STATE_TIMER_STOP",
}

local function RaidCombatPauseWanted(self)
    if not self.config.pauseInRaidCombat or not NS.IsCombatLocked() then return false end
    if Raid and Raid.Detect(self) then return false end
    local inside, kind = IsInInstance()
    return Public(inside) and Public(kind) and inside == true and kind == "raid"
end

local function SetWorkEvents(self, enabled)
    for _, event in ipairs(TRACKER_EVENTS) do
        if event ~= "PLAYER_ENTERING_WORLD" and event ~= "ZONE_CHANGED_NEW_AREA" then
            if enabled then self.context:Event(event, Event, true)
            else self.context:RemoveEvent(event) end
        end
    end
    if MythicPlus then
        for _, event in ipairs(MYTHIC_PLUS_EVENTS) do
            if enabled then self.context:Event(event, Event, true)
            else self.context:RemoveEvent(event) end
        end
    end
    if enabled then self.context:Event("GROUP_ROSTER_UPDATE", M.SuppressNative, true)
    else self.context:RemoveEvent("GROUP_ROSTER_UPDATE") end
end

UpdateRaidCombatPause = function(self)
    local wanted = RaidCombatPauseWanted(self)
    if wanted == self.pausedForRaidCombat then return wanted end
    self.pausedForRaidCombat = wanted
    SetWorkEvents(self, not wanted)
    CancelPending(self)
    self.timedRows = nil
    self.previousFlat = nil
    MarkAllDirty(self)
    if wanted then
        if self.mplusActive then MythicPlus.Stop(self) end
        if self.raidActive then Raid.Stop(self) end
        self.host:Hide()
    else
        self.retheme = true
        self.contentSignature = ContentSignature(self.config)
        local mapID = MythicPlus and MythicPlus.Detect(self)
        if mapID then StartMythicPlus(self, mapID)
        elseif not ShowRaid(self) then Flush(self) end
    end
    return true
end

local function RaidCombatEvent(self, event)
    UpdateRaidCombatPause(self)
    if event == "PLAYER_REGEN_ENABLED" then self:SuppressNative() end
end

local function NativeAddonLoaded(module, _, name)
    if name == "Blizzard_ObjectiveTracker" then module:SuppressNative() end
    if Raid and module.raidActive then Raid.Bind(module) end
end

function M:Enable()
    Create(self)
    self.active = true
    self.retheme = true
    LoadCollapseState(self)
    self.pausedForRaidCombat = false
    self.context:Event("PLAYER_ENTERING_WORLD", Event, true)
    self.context:Event("ZONE_CHANGED_NEW_AREA", Event, true)
    self.context:Event("PLAYER_REGEN_DISABLED", RaidCombatEvent, true)
    self.context:Event("PLAYER_REGEN_ENABLED", RaidCombatEvent, true)
    if Raid then
        self.context:Event("ENCOUNTER_START", Event, true)
        self.context:Event("ENCOUNTER_END", Event, true)
    end
    SetWorkEvents(self, true)
    self.context:Event("ADDON_LOADED", NativeAddonLoaded, true)
    self:SuppressNative()
    MarkAllDirty(self)
    self.contentSignature = ContentSignature(self.config)
    if UpdateRaidCombatPause(self) then
        self:RegisterMovers()
        return
    end
    local mapID = MythicPlus and MythicPlus.Detect(self)
    if mapID then StartMythicPlus(self, mapID)
    elseif not ShowRaid(self) then Flush(self) end
    self:RegisterMovers()
end

function M:Refresh()
    self.retheme = true
    if UpdateRaidCombatPause(self) then return end
    local c = self.config
    local mapID = MythicPlus and MythicPlus.Detect(self)
    if mapID then
        StopRaid(self)
        StartMythicPlus(self, mapID)
    end
    local raidWanted = not mapID and Raid and Raid.Detect(self)
    if raidWanted then
        StopMythicPlus(self)
        ShowRaid(self)
        Render(self)
        self:SuppressNative()
        return
    end
    local stoppedRaid = StopRaid(self)
    local stoppedMythicPlus = false
    if self.mplusActive and not mapID and (not self.mplus.completed or not c.showMythicPlus) then
        stoppedMythicPlus = StopMythicPlus(self)
    end
    if self.mplusActive then
        Render(self)
        self:SuppressNative()
        return
    end
    LoadCollapseState(self)
    local signature = ContentSignature(c)
    if self.contentSignature ~= signature or stoppedMythicPlus or stoppedRaid then
        self.contentSignature = signature
        MarkAllDirty(self)
        Flush(self)
    else
        Render(self)
    end
    self:SuppressNative()
end

function M:Disable()
    if MythicPlus then MythicPlus.Stop(self) end
    if Raid then Raid.Stop(self) end
    CancelPending(self)
    self.pausedForRaidCombat = false
    if self.host then self.host:Hide() end
    for i = 1, #SOURCES do
        local list = self.sources[SOURCES[i]]
        if list then list.count = 0 end
    end
    self.previousFlat = nil
    self.flatWork, self.grouped, self.liveEntries = nil, nil, nil
    self.previousByKey, self.usedRows, self.timedRows = nil, nil, nil
end

function M:RegisterMovers()
    S.RegisterOwnedMover(ID, "tracker", {
        label = "Objective Tracker", order = 625, getFrame = function() return self.host end,
        xKey = "x", yKey = "y", point = "TOPRIGHT",
        historyKeys = { "width", "height", "scale" },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 220, max = 520, step = 5,
                get = function() return S.Config(ID).width end,
                set = function(value) return S.Set(ID, "width", value) end },
            { id = "height", label = "Maximum height", kind = "number", min = 220, max = 900, step = 10,
                get = function() return S.Config(ID).height end,
                set = function(value) return S.Set(ID, "height", value) end },
        },
    })
end

S.Install(ID, M)
