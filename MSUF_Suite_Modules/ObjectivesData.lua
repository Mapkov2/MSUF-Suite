local _, P = ...
local S = P.Suite

-- An MSUF-owned objective tracker, split over three files that share
-- P.Objectives (TOC order): ObjectivesData.lua reads Blizzard's objectives
-- into reused entry tables, ObjectivesTracker.lua owns the frame and draws
-- its rows, and Objectives.lua runs the module (events, refresh flow and
-- lifecycle). Events mark sources dirty; one deferred flush per frame
-- re-reads them, and rows are laid out again only when their content or
-- geometry changed.
local O = {
    -- The module table; Objectives.lua installs it.
    M = {
        sources = {}, rows = {}, freeRows = {}, dirty = {},
        staleFlushes = 0, staleTimers = 0,
    },
    -- The data sources, in collection order.
    SOURCES = { "quests", "world", "bonus", "achievements", "scenario" },
}
P.Objectives = O
local SOURCES = O.SOURCES
local Public, Finite, Text = S.Public, S.Finite, S.PublicText

-- The first result of a client API, or nil while it is secret. APIs are
-- looked up at call time (hooks of other addons replace some of them).
local function Read(fn, ...)
    local value = fn(...)
    return Public(value) and value or nil
end
O.Read = Read

------------------------------------------------------------------ collected entries
-- Each source keeps its entry tables (and their line tables) across flushes;
-- count marks how many are live.
local function ResetSource(self, key)
    local list = self.sources[key]
    if not list then
        list = { count = 0 }
        self.sources[key] = list
    end
    list.count = 0
    return list
end

local function NextEntry(list, id, title, group)
    local index = list.count + 1
    local entry = list[index]
    if not entry then
        entry = { lines = { count = 0 } }
        list[index] = entry
    end
    list.count = index
    entry.id, entry.title, entry.group = id, title, group
    entry.tracked, entry.itemIcon, entry.timeLeft, entry.scenarioID = nil, nil, nil, nil
    entry.findGroup, entry.questGroupSearch = nil, nil
    entry.lines.count = 0
    return entry
end

local function AddLine(entry, text, done, percent)
    local lines = entry.lines
    local index = lines.count + 1
    local line = lines[index]
    if not line then
        line = {}
        lines[index] = line
    end
    line.text, line.done, line.percent = text, done, percent
    lines.count = index
end

local function QuestItem(questID)
    local index = Read(C_QuestLog.GetLogIndexForQuestID, questID)
    if not Finite(index) or index < 1 then return end
    local complete = Read(C_QuestLog.IsComplete, questID) == true
    if Read(QuestUtil.QuestShowsItemByIndex, index, complete) ~= true then return end
    local _, icon, _, showWhenComplete = GetQuestLogSpecialItemInfo(index)
    if not Public(icon) or (type(icon) ~= "number" and type(icon) ~= "string")
        or (complete and (not Public(showWhenComplete) or showWhenComplete ~= true)) then
        return
    end
    return icon
end

local function QuestTimeLeft(questID, task)
    if task then
        local left = Read(C_TaskQuest.GetQuestTimeLeftSeconds, questID)
        return Finite(left) and left > 0 and left or nil
    end
    local total, elapsed = C_QuestLog.GetTimeAllowed(questID)
    if Finite(total) and Finite(elapsed) and total > elapsed then return total - elapsed end
end

local function AddObjectiveLines(entry, questID)
    local objectives = Read(C_QuestLog.GetQuestObjectives, questID)
    if type(objectives) ~= "table" then return end
    for i = 1, #objectives do
        local objective = objectives[i]
        if Public(objective) and type(objective) == "table" then
            local line = Text(objective.text)
            if line then
                local percent
                if Text(objective.type) == "progressbar" then
                    local value = Read(GetQuestProgressBarPercent, questID)
                    if Finite(value) then percent = math.max(0, math.min(100, value)) end
                end
                AddLine(entry, line, Public(objective.finished) and objective.finished == true, percent)
            end
        end
    end
end

local function QuestTitle(questID)
    local title = Read(C_QuestLog.GetTitleForQuestID, questID)
    if Text(title) then return title end
    local index = Read(C_QuestLog.GetLogIndexForQuestID, questID)
    local info = Finite(index) and Read(C_QuestLog.GetInfo, index)
    return type(info) == "table" and Text(info.title) or nil
end

local function Category(questID, focused)
    if questID == focused then return "focused" end
    if Read(C_QuestLog.IsComplete, questID) == true then return "complete" end
    local kind = Read(C_QuestInfoSystem.GetQuestClassification, questID)
    local kinds = Enum.QuestClassification
    if Finite(kind) then
        if kind == kinds.Campaign then return "campaign" end
        if kind == kinds.Important or kind == kinds.Legendary then return "important" end
    end
    return "quests"
end

local function AddQuest(list, c, id, title, group, tracked, task)
    local entry = NextEntry(list, id, title, group)
    entry.tracked = tracked
    if not P.NS.Client.isForever then
        local activityID = Read(C_LFGList.GetActivityIDForQuestID, id)
        entry.questGroupSearch = Finite(activityID) and activityID > 0 or nil
    end
    entry.findGroup = not P.NS.Client.isForever and (group == "world" or entry.questGroupSearch)
    AddObjectiveLines(entry, id)
    if c.showQuestItems ~= false then entry.itemIcon = QuestItem(id) end
    if c.showTimers ~= false then entry.timeLeft = QuestTimeLeft(id, task) end
end

-- World quests and bonus objectives read the same task list; one flush
-- fetches it once.
local tasksRead, tasksTable = false, nil
local function Tasks()
    if not tasksRead then
        tasksRead = true
        tasksTable = Read(GetTasksTable)
    end
    return type(tasksTable) == "table" and tasksTable or nil
end

local seen = {}
local function CollectQuests(list, c)
    for id in pairs(seen) do seen[id] = nil end
    local focused = Read(C_SuperTrack.GetSuperTrackedQuestID)
    local count = Read(C_QuestLog.GetNumQuestWatches)
    if not Finite(count) then return end
    for i = 1, math.min(count, 40) do
        local id = Read(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
        if Finite(id) and id > 0 and not seen[id] then
            seen[id] = true
            local title = QuestTitle(id)
            if title then AddQuest(list, c, id, title, Category(id, focused), true, false) end
        end
    end
end

local function CollectWorld(list, c)
    for id in pairs(seen) do seen[id] = nil end
    local count = Read(C_QuestLog.GetNumWorldQuestWatches)
    if not Finite(count) then return end
    local taskInfo = C_TaskQuest.GetQuestInfoByQuestID
    for i = 1, math.min(count, 25) do
        local id = Read(C_QuestLog.GetQuestIDForWorldQuestWatchIndex, i)
        if Finite(id) and id > 0 and not seen[id] then
            seen[id] = true
            local title = QuestTitle(id)
            if not title then
                local task = Read(taskInfo, id)
                title = Text(task) or type(task) == "table" and Text(task.title)
            end
            if title then AddQuest(list, c, id, title, "world", true, true) end
        end
    end
    local tasks = Tasks()
    if not tasks then return end
    for i = 1, math.min(#tasks, 30) do
        local id = tasks[i]
        if Finite(id) and id > 0 and not seen[id] and Read(QuestUtils_IsQuestWorldQuest, id) == true then
            seen[id] = true
            local title = Text(QuestTitle(id) or Read(taskInfo, id))
            if title then AddQuest(list, c, id, title, "world", false, true) end
        end
    end
end

local function CollectBonus(list, c)
    local tasks = Tasks()
    if not tasks then return end
    for i = 1, math.min(#tasks, 30) do
        local id = tasks[i]
        if Finite(id) and id > 0 and Read(QuestUtils_IsQuestWorldQuest, id) ~= true then
            local inArea, _, count, taskName = GetTaskInfo(id)
            if Public(inArea) and inArea == true and Finite(count) and Text(taskName) then
                local entry = NextEntry(list, id, taskName, "bonus")
                if not P.NS.Client.isForever then
                    local activityID = Read(C_LFGList.GetActivityIDForQuestID, id)
                    entry.questGroupSearch = Finite(activityID) and activityID > 0 or nil
                    entry.findGroup = entry.questGroupSearch
                end
                for j = 1, count do
                    local line, kind, done = GetQuestObjectiveInfo(id, j, false)
                    if Text(line) then
                        local percent = Text(kind) == "progressbar" and Read(GetQuestProgressBarPercent, id) or nil
                        AddLine(entry, line, Public(done) and done == true,
                            Finite(percent) and math.max(0, math.min(100, percent)) or nil)
                    end
                end
                if c.showTimers ~= false then entry.timeLeft = QuestTimeLeft(id, true) end
            end
        end
    end
end

local function CollectAchievements(list)
    local ids = Read(C_ContentTracking.GetTrackedIDs, Enum.ContentTrackingType.Achievement)
    if type(ids) ~= "table" then return end
    for i = 1, math.min(#ids, 15) do
        local id = ids[i]
        if Finite(id) then
            local _, name, _, complete = GetAchievementInfo(id)
            if Text(name) and Public(complete) and not complete then
                local entry = NextEntry(list, id, name, "achievements")
                entry.tracked = true
                local count = Read(GetAchievementNumCriteria, id)
                if Finite(count) then
                    for j = 1, count do
                        local line, _, done = GetAchievementCriteriaInfo(id, j)
                        if Text(line) and Public(done) and not done then AddLine(entry, line) end
                    end
                end
            end
        end
    end
end

-- Blizzard's scenario tracker owns two widget sets that can carry a stage
-- timer even when no scenario criterion has duration/elapsed values.
local SCENARIO_WIDGET_SETS = { 252, 514 }
local function ScenarioWidgetTimeLeft()
    if P.NS.Client.isForever then return nil end
    local manager = C_UIWidgetManager
    local widgetType = Enum.UIWidgetVisualizationType.ScenarioHeaderTimer
    for set = 1, #SCENARIO_WIDGET_SETS do
        local widgets = Read(manager.GetAllWidgetsBySetID, SCENARIO_WIDGET_SETS[set])
        if type(widgets) == "table" then
            for i = 1, #widgets do
                local widget = widgets[i]
                if Public(widget) and type(widget) == "table"
                    and Finite(widget.widgetID) and Public(widget.widgetType)
                    and widget.widgetType == widgetType then
                    local info = Read(manager.GetScenarioHeaderTimerWidgetVisualizationInfo, widget.widgetID)
                    if type(info) == "table" and Public(info.shownState)
                        and info.shownState ~= Enum.WidgetShownState.Hidden
                        and Finite(info.timerMin) and Finite(info.timerMax) and Finite(info.timerValue)
                        and info.timerMax > info.timerMin then
                        local left = math.min(info.timerValue, info.timerMax) - info.timerMin
                        if left > 0 then return left end
                    end
                end
            end
        end
    end
end

local function CollectScenario(list, c)
    local scenario = C_Scenario
    local name, stage, total, _, _, _, _, _, _, _, _, _, scenarioID = scenario.GetInfo()
    if not Text(name) or not Finite(stage) or not Finite(total) or total < 1 or stage > total then return end
    local entry = NextEntry(list, 0, name, "scenario")
    entry.scenarioID = Finite(scenarioID) and scenarioID or nil
    local stepName, description, criteriaCount = scenario.GetStepInfo()
    if Text(stepName) then AddLine(entry, stepName) end
    if Text(description) and description ~= stepName then AddLine(entry, description) end
    local criteriaInfo = C_ScenarioInfo.GetCriteriaInfo
    if c.showTimers ~= false then entry.timeLeft = ScenarioWidgetTimeLeft() end
    if not Finite(criteriaCount) then return end
    for i = 1, criteriaCount do
        local info = Read(criteriaInfo, i)
        if type(info) == "table" then
            local line = Text(info.description)
            if line then AddLine(entry, line, Public(info.completed) and info.completed == true) end
            if c.showTimers ~= false and Finite(info.duration) and Finite(info.elapsed)
                and info.duration > info.elapsed then
                local left = info.duration - info.elapsed
                if not entry.timeLeft then entry.timeLeft = left end
            end
        end
    end
end

------------------------------------------------------------------ collection pass
local COLLECTORS = {
    quests = function(list, c) CollectQuests(list, c) end,
    world = function(list, c) if c.showWorldQuests then CollectWorld(list, c) end end,
    bonus = function(list, c) if c.showBonus then CollectBonus(list, c) end end,
    achievements = function(list, c) if c.showAchievements then CollectAchievements(list) end end,
    scenario = function(list, c) if c.showScenario then CollectScenario(list, c) end end,
}

-- Re-reads every dirty source into its reused entry list.
function O.CollectDirty(self)
    tasksRead, tasksTable = false, nil
    for i = 1, #SOURCES do
        local key = SOURCES[i]
        if self.dirty[key] then
            COLLECTORS[key](ResetSource(self, key), self.config)
            self.dirty[key] = nil
        end
    end
    tasksTable = nil
end
