local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local M = {}
local IN_COMBAT = { inCombat = true }
local UPDATE_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "WEEKLY_REWARDS_UPDATE",
    "UPDATE_INSTANCE_INFO", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_MAPS_UPDATE", "PLAYER_TALENT_UPDATE",
    "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_SPECIALIZATION_CHANGED", "SELECTED_LOADOUT_CHANGED", "PLAYER_LOOT_SPEC_UPDATED", "BAG_UPDATE_DELAYED",
    "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_MONEY", "PLAYER_LEVEL_UP" }
local WEEK_EVENTS = { WEEKLY_REWARDS_UPDATE = true, UPDATE_INSTANCE_INFO = true, CHALLENGE_MODE_COMPLETED = true,
    CHALLENGE_MODE_MAPS_UPDATE = true, PLAYER_ENTERING_WORLD = true }
-- Level, item level, gold and zone refresh alone; gold and level change
-- nothing else the planner tracks.
local VITAL_EVENTS = { PLAYER_MONEY = true, PLAYER_LEVEL_UP = true, PLAYER_EQUIPMENT_CHANGED = true, PLAYER_AVG_ITEM_LEVEL_UPDATE = true,
    ZONE_CHANGED_NEW_AREA = true }
local VITAL_ONLY = { PLAYER_MONEY = true, PLAYER_LEVEL_UP = true }

local function Refresh(self)
    if not self.active or self.suspended or self.leaving or NS.InCombat() then return end
    local keyOnly = self.keyDirty and not self.weeklyDirty and not self.vitalsDirty and not self.contextDirty
    local captured = self.weeklyDirty and Plan.Weekly.Capture()
    local vitals = not captured and self.vitalsDirty and Plan.Weekly.Vitals()
    local key = not captured and self.keyDirty and Plan.Weekly.UpdateKeystone()
    if self.contextDirty then Plan.Loadouts.Check() Plan.Notes.Entry() end
    self.weeklyDirty, self.contextDirty, self.vitalsDirty, self.keyDirty = nil, nil, nil, nil
    if not captured and not vitals and not key and not keyOnly then Plan.Changed() end
end

local function Queue(self, event)
    if event == "PLAYER_ENTERING_WORLD" then self.leaving = nil end
    if not self.active or self.suspended or self.leaving or NS.InCombat(event) then return end
    if not event or WEEK_EVENTS[event] then self.weeklyDirty = true end
    if VITAL_EVENTS[event] then self.vitalsDirty = true end
    if event == "BAG_UPDATE_DELAYED" then self.keyDirty = true end
    if not event or not WEEK_EVENTS[event] and not VITAL_ONLY[event] and event ~= "BAG_UPDATE_DELAYED"
        or event == "PLAYER_ENTERING_WORLD" then
        self.contextDirty = true
    end
    if event == "UPDATE_INSTANCE_INFO" then Plan.Weekly.lockoutsReady = true end
    if event == "CHALLENGE_MODE_MAPS_UPDATE" then Plan.Weekly.seasonReady = true end
    -- A finished key changes season bests; Blizzard sends them after a request.
    if event == "CHALLENGE_MODE_COMPLETED" and not NS.Client.isForever then C_MythicPlus.RequestMapInfo() end
    -- The server's lockout and map data is asked for on entering the world and
    -- once when the planner starts; a pull changes none of it, and a request
    -- would turn every known lockout into a question mark until the reply.
    if self.config.weekly and (event == "PLAYER_ENTERING_WORLD" or not event and not self.requested) then
        self.requested = true
        Plan.Weekly.Request()
    end
    self.context:After(.2, Refresh)
end

local function Ready(self)
    if self.suspended or not self.config.preparation or NS.InCombat() then return end
    Plan.Notify("preparation", S.Text("Personal preparation"), S.Text("Open Adventure planner for your preparation check."))
end

-- Teardown APIs can return zero before logout; retain the last live values.
local function Leaving(self)
    if not self.leaving then Plan.Weekly.LastSeen() end
    self.leaving = true
    self.context:Cancel(Refresh)
    self.weeklyDirty, self.contextDirty, self.vitalsDirty, self.keyDirty = nil, nil, nil, nil
    Plan.Board.Close(self)
    S.ToolListWindow.Close(self)
end

local function Arm(self)
    for _, event in ipairs(UPDATE_EVENTS) do
        if event ~= "PLAYER_ENTERING_WORLD" and (event ~= "BAG_UPDATE_DELAYED" or not NS.Client.isForever) then
            self.context:Event(event, Queue)
        end
    end
    self.context:Event("READY_CHECK", Ready)
end

local function CombatStart(self)
    self.suspended = true
    self.context:Cancel(Refresh)
    for _, event in ipairs(UPDATE_EVENTS) do
        if event ~= "PLAYER_ENTERING_WORLD" then self.context:RemoveEvent(event) end
    end
    self.context:RemoveEvent("READY_CHECK")
    Plan.Board.Close(self)
    S.ToolListWindow.Close(self)
end

local function CombatEnd(self)
    self.suspended = nil
    Arm(self)
    Queue(self)
end

local function ConfigChanged(self)
    local c = self.config
    local changed = self.fontProfile ~= NS.DB or self.fontWeekly ~= c.weekly or self.fontPreparation ~= c.preparation
        or self.fontLoadouts ~= c.loadouts or self.fontRaid ~= c.raidHistory or self.fontNotes ~= c.entryNotes
        or self.fontAttempts ~= c.keepAttempts
    self.fontProfile, self.fontWeekly, self.fontPreparation = NS.DB, c.weekly, c.preparation
    self.fontLoadouts, self.fontRaid, self.fontNotes, self.fontAttempts = c.loadouts, c.raidHistory, c.entryNotes, c.keepAttempts
    return changed
end

function M:Enable()
    Plan.owner = self
    ConfigChanged(self)
    self.fontRevision = S.FontRevision
    self.context:Event("PLAYER_ENTERING_WORLD", Queue)
    self.context:Event("PLAYER_LEAVING_WORLD", Leaving)
    self.context:Event("PLAYER_LOGOUT", Leaving)
    self.context:Event("PLAYER_REGEN_DISABLED", CombatStart, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", CombatEnd, IN_COMBAT)
    if NS.InCombat() then CombatStart(self) else CombatEnd(self) end
end

function M:Refresh()
    local changed = ConfigChanged(self)
    local fontChanged = self.fontRevision ~= S.FontRevision
    self.fontRevision = S.FontRevision
    Plan.Board.Restyle(self)
    S.ToolListWindow.RefreshFonts(self)
    if fontChanged and not changed then return end
    Queue(self)
end

function M:Disable()
    self.context:Cancel(Refresh)
    Plan.Loadouts.last, Plan.Notes.last = nil, nil
    Plan.Board.Close(self)
    S.ToolListWindow.Close(self)
    self.suspended, self.pull, self.requested, self.leaving = nil, nil, nil, nil
    Plan.owner = nil
end

S.Install(Plan.id, M)
