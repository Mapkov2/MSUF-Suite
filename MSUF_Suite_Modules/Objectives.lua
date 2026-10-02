local _, P = ...
local NS, S = P.NS, P.Suite
local O = P.Objectives
local M, SOURCES = O.M, O.SOURCES
local Create, Render, CollectDirty = O.Create, O.Render, O.CollectDirty
local MythicPlus = S.MythicPlus
local Raid = S.Raid
local Public, Finite = S.Public, S.Finite
local ID = "objectives"
local IN_COMBAT = { inCombat = true }

-- The objective tracker module: events, the refresh flow and the lifecycle
-- (see ObjectivesData.lua for how the files fit together).

------------------------------------------------------------------ refresh flow
local function Flush(self)
    self.flushJob:Clear()
    if not self.active or self.pausedForRaidCombat or self.mplusActive or self.raidActive then return end
    CollectDirty(self)
    O.UpdateQuestItem(self)
    Render(self)
end

-- Events in one frame share a single flush (self.flushJob).
local function Request(self, key)
    if self.pausedForRaidCombat or self.raidActive then return end
    self.dirty[key] = true
    self.flushJob:Request()
end

-- Native scenario headers can change height when their currencies or effects
-- change. Coalesce that layout change with the existing scenario refresh.
function O.RequestScenarioLayout()
    if M.active then
        M.layoutDirty = true
        Request(M, "scenario")
    end
end

local function MarkAllDirty(self)
    for i = 1, #SOURCES do self.dirty[SOURCES[i]] = true end
end

-- The flush and the countdown tick already due are dropped.
local function CancelPending(self)
    self.flushJob:Cancel()
    self.countdownJob:Cancel()
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
    UPDATE_ALL_UI_WIDGETS = { "scenario" },
    ACTIVE_DELVE_DATA_UPDATE = { "scenario" },
    TRACKED_ACHIEVEMENT_UPDATE = { "achievements" },
    CRITERIA_UPDATE = { "achievements" },
    ACHIEVEMENT_EARNED = { "achievements" },
    CONTENT_TRACKING_UPDATE = { "achievements" },
    ZONE_CHANGED = { "world", "bonus" },
    ZONE_CHANGED_INDOORS = { "world", "bonus" },
    SUPER_TRACKING_CHANGED = { "quests" },
    QUEST_POI_UPDATE = { "quests" },
    QUEST_AUTOCOMPLETE = { "quests" },
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
local function EncounterEvent(self, event, ...)
    if event == "ENCOUNTER_START" then
        self.encounterActive = true
        UpdateRaidCombatPause(self)
        if self.pausedForRaidCombat then return end
        local encounterID, encounterName, difficultyID = ...
        if ShowRaid(self) and Raid.Start(self, encounterID, encounterName, difficultyID) then
            Render(self)
        end
        return
    elseif event == "ENCOUNTER_END" then
        self.encounterActive = false
        UpdateRaidCombatPause(self)
        if self.pausedForRaidCombat then return end
        if self.raidActive then
            Raid.End(self, ...)
            Render(self)
        end
    end
end

local function Event(self, event, ...)
    if event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
        EncounterEvent(self, event, ...)
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        self.encounterActive = nil
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
    if event == "UPDATE_UI_WIDGET" then
        local widget = ...
        if Public(widget) and type(widget) == "table" and Finite(widget.widgetSetID)
            and widget.widgetSetID == self.scenarioWidgetSetID then
            Request(self, "scenario")
        end
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
-- Blizzard's tracker is a right-managed Edit Mode frame. A SetParent or Hide
-- from here would run its OnHide (ManagedFrameMixin.OnHide, then
-- RemoveManagedFrame and the right container's Layout, which also places the
-- protected boss and arena frames) inside this addon's call and taint that
-- layout (Blizzard_ManagedFrameSystem/Shared/ManagedFrameSystem.lua). Its
-- SetScale is Blizzard code as well: EditModeSystemMixin replaces it with
-- SetScaleOverride, which re-anchors the tracker with its offsets times the
-- old scale over the new one and runs ManageFramePositions, and an Edit Mode
-- save (BreakFrameSnap) stores offsets divided by the scale
-- (Blizzard_EditMode/Shared/EditModeSystemTemplates.lua). So the tracker
-- itself only loses its alpha and its mouse. Its children (the header, the
-- modules and the Edit Mode selection) take the mouse themselves; each gets
-- a scale so small that it keeps no hit area. They are plain frames, so
-- their SetScale runs no Blizzard code, and the tracker keeps its own place
-- as the last frame of the right column (layoutIndex 50). The modules join
-- the tracker at login (ObjectiveTrackerManager:Init) through AddModule,
-- which a hook follows. The container sets the alpha back to 1 when the UI
-- is shown again; the scales stay. The context restores all of them on
-- disable.
local NATIVE_HIDDEN_SCALE = .001

local function SuppressNativeChildren(context, ...)
    for i = 1, select("#", ...) do
        context:Scale(select(i, ...), NATIVE_HIDDEN_SCALE)
    end
end

local function NativeModuleAdded()
    if M.active then M:SuppressNative() end
end

function M:SuppressNative()
    if not self.active or NS.IsCombatLocked() then return end
    -- Blizzard_ObjectiveTracker loads at startup on every supported client.
    local native = ObjectiveTrackerFrame
    if NS.Safety.IsForbidden(native) then return end
    if not self.nativeModuleHook then
        self.nativeModuleHook = true
        hooksecurefunc(native, "AddModule", NativeModuleAdded)
    end
    self.context:HideControl(native, true)
    SuppressNativeChildren(self.context, native:GetChildren())
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
        .. tostring(c.showQuestItems) .. ":" .. tostring(c.showTimers) .. ":" .. tostring(c.questIconStyle)
end

local TRACKER_EVENTS = {
    "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_WATCH_LIST_CHANGED",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_AUTOCOMPLETE", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "QUEST_POI_UPDATE", "SCENARIO_BONUS_VISIBILITY_UPDATE",
    "SCENARIO_UPDATE", "SCENARIO_CRITERIA_UPDATE", "ACTIVE_DELVE_DATA_UPDATE", "TRACKED_ACHIEVEMENT_UPDATE",
    "UPDATE_ALL_UI_WIDGETS", "UPDATE_UI_WIDGET",
    "CRITERIA_UPDATE", "ACHIEVEMENT_EARNED", "CONTENT_TRACKING_UPDATE", "SCENARIO_POI_UPDATE",
}
local MYTHIC_PLUS_EVENTS = {
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_COMPLETED_REWARDS", "CHALLENGE_MODE_RESET",
    "CHALLENGE_MODE_DEATH_COUNT_UPDATED", "WORLD_STATE_TIMER_START", "WORLD_STATE_TIMER_STOP",
}

-- event is the combat edge being handled: PLAYER_REGEN_DISABLED runs before
-- lockdown starts, so it decides "in combat" itself (Suite.InCombat).
local function RaidCombatPauseWanted(self, event)
    local c = self.config
    if not c.hideInRaid and not c.hideDuringBoss and not c.pauseInRaidCombat then return false end
    local inside, kind = IsInInstance()
    if not Public(inside) or not Public(kind) or inside ~= true or kind ~= "raid" then return false end
    if c.hideInRaid then return true end
    if c.hideDuringBoss then
        local active = self.encounterActive
        if active == nil then active = C_InstanceEncounter.IsEncounterInProgress() end
        if Public(active) and active == true then return true end
    end
    if not c.pauseInRaidCombat or not NS.InCombat(event) then return false end
    return not Raid or not Raid.Detect(self)
end

local function SetWorkEvents(self, enabled)
    for _, event in ipairs(TRACKER_EVENTS) do
        if event ~= "PLAYER_ENTERING_WORLD" and event ~= "ZONE_CHANGED_NEW_AREA" then
            if enabled then self.context:Event(event, Event, IN_COMBAT)
            else self.context:RemoveEvent(event) end
        end
    end
    if MythicPlus then
        for _, event in ipairs(MYTHIC_PLUS_EVENTS) do
            if enabled then self.context:Event(event, Event, IN_COMBAT)
            else self.context:RemoveEvent(event) end
        end
    end
    if enabled then self.context:Event("GROUP_ROSTER_UPDATE", M.SuppressNative, IN_COMBAT)
    else self.context:RemoveEvent("GROUP_ROSTER_UPDATE") end
end

UpdateRaidCombatPause = function(self, event)
    local wanted = RaidCombatPauseWanted(self, event)
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
    UpdateRaidCombatPause(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:SuppressNative()
        O.UpdateQuestItem(self)
    end
end

local function NativeAddonLoaded(module, _, name)
    if name == "Blizzard_ObjectiveTracker" then module:SuppressNative() end
    if Raid and module.raidActive then Raid.Bind(module) end
end

function M:Enable()
    self.flushJob = self.context:Coalesce(0, Flush)
    self.countdownJob = self.context:Coalesce(1, O.UpdateTimers)
    Create(self)
    self.active = true
    self.retheme = true
    LoadCollapseState(self)
    self.pausedForRaidCombat = false
    self.context:Event("PLAYER_ENTERING_WORLD", Event, IN_COMBAT)
    self.context:Event("ZONE_CHANGED_NEW_AREA", Event, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_DISABLED", RaidCombatEvent, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", RaidCombatEvent, IN_COMBAT)
    self.context:Event("ENCOUNTER_START", Event, IN_COMBAT)
    self.context:Event("ENCOUNTER_END", Event, IN_COMBAT)
    SetWorkEvents(self, true)
    self.context:Event("ADDON_LOADED", NativeAddonLoaded, IN_COMBAT)
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
    O.UpdateQuestItem(self, true)
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
            { id = "scale", label = "Scale %", kind = "number", min = 60, max = 160, step = 1,
                get = function() return S.Config(ID).scale end,
                set = function(value) return S.Set(ID, "scale", value) end },
        },
    })
end

S.Install(ID, M)
