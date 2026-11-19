local _, P = ...
local S = P.Suite

-- An MSUF-owned objective tracker, split over files that share
-- P.Objectives (TOC order): ObjectivesData.lua reads Blizzard's objectives
-- into reused entry tables, ObjectivesDetails.lua adds quest icons and
-- scenario headers, ObjectivesActions.lua holds what rows do (Blizzard
-- actions and context menus), ObjectivesContent.lua reads the Traveler's Log,
-- Endeavors, collectibles and zone widgets that Blizzard's modules show
-- beyond quests (ObjectivesContentActions.lua holds what their rows do),
-- ObjectivesRows.lua projects reused display records. ObjectivesTracker.lua
-- draws the rows and Objectives.lua runs events, refreshes and module lifecycle.
-- One deferred flush per frame reads dirty sources and lays out rows only when
-- content or geometry changes.
local O = {
    -- The module table; Objectives.lua installs it.
    M = {
        sources = {}, rows = {}, freeRows = {}, dirty = {}, scenarioProgressWidgets = {},
    },
    -- The data sources, in collection order.
    SOURCES = { "quests", "world", "bonus", "achievements", "scenario" },
}
P.Objectives = O
if not P.NS.Client.isForever then O.SOURCES[#O.SOURCES + 1] = "recipes" end
local SOURCES = O.SOURCES
local Public, Finite, Text = S.Public, S.Finite, S.PublicText

-- The first result of a client API, or nil while it is secret. APIs are
-- looked up at call time (hooks of other addons replace some of them).
local function Read(fn, ...)
    local value = fn(...)
    return Public(value) and value or nil
end
O.Read = Read

-- Set while the watched quests are collected and something a quest shows could
-- not be read: the collected list is then not known to be whole (CollectQuests).
local partial = false

-- Read for what a quest shows: a secret answer also marks the collection partial.
local function Detail(fn, ...)
    local value = fn(...)
    if Public(value) then return value or nil end
    partial = true
end

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
    entry.tracked, entry.itemIcon, entry.itemLink, entry.timeLeft, entry.scenarioID = nil, nil, nil, nil, nil
    entry.findGroup, entry.questGroupSearch = nil, nil
    entry.questIcon, entry.questIconAtlas = nil, nil
    entry.scenarioHeaderSetID = nil
    entry.recipeID, entry.isRecraft = nil, nil
    entry.contentID, entry.contentType = nil, nil
    entry.questHeader, entry.questLabel, entry.dungeonBadge = nil, nil, nil
    entry.lines.count = 0
    return entry
end

local function AddLine(entry, text, done, percent, progressText)
    local lines = entry.lines
    local index = lines.count + 1
    local line = lines[index]
    if not line then
        line = {}
        lines[index] = line
    end
    line.text, line.done, line.percent, line.progressText = text, done, percent, progressText
    lines.count = index
end
O.NextEntry, O.AddLine = NextEntry, AddLine

local function QuestIndex(questID)
    local index = C_QuestLog.GetLogIndexForQuestID(questID)
    if Finite(index) and index >= 1 then return index end
    if not Public(index) then partial = true end
end

local function IsAutoComplete(index)
    local info = Detail(C_QuestLog.GetInfo, index)
    if type(info) == "table" then
        local auto = info.isAutoComplete
        if Public(auto) then return auto == true end
    end
    partial = true
    return false
end

-- Read current completion at click time before opening the native reward dialog.
function O.CanCompleteQuest(questID)
    if not Finite(questID) or questID <= 0 or Read(C_QuestLog.IsComplete, questID) ~= true then return false end
    local index = QuestIndex(questID)
    return index ~= nil and IsAutoComplete(index)
end

local function QuestItem(index, complete)
    if Detail(QuestUtil.QuestShowsItemByIndex, index, complete) ~= true then return end
    local link, icon, _, showWhenComplete = GetQuestLogSpecialItemInfo(index)
    if not Public(link) or not Public(icon) then
        partial = true
        return
    end
    if type(link) ~= "string" or link == "" or (type(icon) ~= "number" and type(icon) ~= "string") then return end
    if complete then
        if not Public(showWhenComplete) then
            partial = true
            return
        end
        if showWhenComplete ~= true then return end
    end
    return icon, link
end

local function QuestTimeLeft(questID, task)
    if task then
        local left = Detail(C_TaskQuest.GetQuestTimeLeftSeconds, questID)
        return Finite(left) and left > 0 and left or nil
    end
    local total, elapsed = C_QuestLog.GetTimeAllowed(questID)
    -- A quest without a time limit has no total: one check, as before.
    if not Public(total) then
        partial = true
    elseif total ~= nil and Finite(total) then
        if Finite(elapsed) then
            if total > elapsed then return total - elapsed end
        elseif not Public(elapsed) then
            partial = true
        end
    end
end

local function SplitQuestProgress(text, objective)
    local current, required = objective.numFulfilled, objective.numRequired
    if not (Finite(current) and current >= 0 and current % 1 == 0
        and Finite(required) and required > 0 and required % 1 == 0) then return text end
    -- Only move a counter when it matches the native progress values at a label boundary.
    local count = tostring(current) .. "/" .. tostring(required)
    local pattern = count:gsub("(%p)", "%%%1")
    local label = text:match("^(.-):%s*" .. pattern .. "%s*$")
        or text:match("^(.-)：%s*" .. pattern .. "%s*$")
        or text:match("^(.-)%s*%(" .. pattern .. "%)%s*$")
        or text:match("^(.-)%s+" .. pattern .. "%s*$")
        or text:match("^" .. pattern .. "%s+(.+)$")
    if label then
        label = label:match("^%s*(.-)%s*$")
        if label ~= "" then return label, count end
    end
    return text
end

-- A quest whose objectives or one of their texts cannot be read keeps the lines
-- that can; the collection is partial (the lines come back once readable).
local function AddObjectiveLines(entry, questID, c)
    local objectives = Detail(C_QuestLog.GetQuestObjectives, questID)
    if type(objectives) ~= "table" then
        partial = true
        return
    end
    local hideCompleted, progressColumn = c.hideCompletedObjectives == true, c.questProgressColumn
    for i = 1, #objectives do
        local objective = objectives[i]
        if Public(objective) and type(objective) == "table" then
            local line = Text(objective.text)
            if line then
                local percent
                local kind = objective.type
                local readableKind = Public(kind)
                if not readableKind then
                    partial = true
                elseif kind == "progressbar" then
                    local value = Detail(GetQuestProgressBarPercent, questID)
                    if Finite(value) then percent = math.max(0, math.min(100, value)) end
                end
                local done = objective.finished
                if Public(done) then
                    done = done == true
                else
                    done, partial = false, true
                end
                if not hideCompleted or not done then
                    local progressText
                    if progressColumn and readableKind and kind ~= "progressbar" then
                        line, progressText = SplitQuestProgress(line, objective)
                    end
                    AddLine(entry, line, done, percent, progressText)
                end
            elseif not Public(objective.text) or objective.text == nil then
                partial = true
            end
        else
            partial = true
        end
    end
end

local function QuestTitle(questID)
    local value = C_QuestLog.GetTitleForQuestID(questID)
    local title = Text(value)
    if title then return title end
    if not Public(value) then partial = true end
    local index = Detail(C_QuestLog.GetLogIndexForQuestID, questID)
    local info = Finite(index) and Detail(C_QuestLog.GetInfo, index)
    return type(info) == "table" and Text(info.title) or nil
end

local function Category(questID, focused, complete)
    if questID == focused then return "focused" end
    if complete then return "complete" end
    local kind = Detail(C_QuestInfoSystem.GetQuestClassification, questID)
    local kinds = Enum.QuestClassification
    if Finite(kind) then
        if kind == kinds.Campaign then return "campaign" end
        if kind == kinds.Important or kind == kinds.Legendary then return "important" end
    end
    return "quests"
end

local function AddQuest(list, c, id, title, group, tracked, task, complete)
    local entry = NextEntry(list, id, title, group)
    entry.tracked = tracked
    if not P.NS.Client.isForever then
        local activityID = Detail(C_LFGList.GetActivityIDForQuestID, id)
        entry.questGroupSearch = Finite(activityID) and activityID > 0 or nil
    end
    entry.findGroup = not P.NS.Client.isForever and (group == "world" or entry.questGroupSearch)
    AddObjectiveLines(entry, id, c)
    local showItem = c.showQuestItems ~= false
    local showCompletion = not task and complete
    local index = (showItem or showCompletion) and QuestIndex(id)
    if showCompletion then
        if index and IsAutoComplete(index) then AddLine(entry, QUEST_WATCH_CLICK_TO_COMPLETE, true)
        elseif c.groupQuestsByHeader then
            AddLine(entry, S.Text("Ready to turn in"), true)
        end
    end
    if index then
        if showItem then
            if task then complete = Detail(C_QuestLog.IsComplete, id) == true end
            entry.itemIcon, entry.itemLink = QuestItem(index, complete)
        end
    end
    if c.questIconStyle == 3 then
        local asset, atlas = QuestUtil.GetQuestIconActiveForQuestID(id)
        if Public(asset) and type(asset) == "string" and Public(atlas) and type(atlas) == "boolean" then
            entry.questIcon, entry.questIconAtlas = asset, atlas
        elseif not Public(asset) or not Public(atlas) then
            partial = true
        end
    end
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

-- A dungeon or micro-map may be a child of the quest's zone. Compare
-- zone IDs, never a continent, so adjacent zones do not count as local.
local function ZoneMap(mapID)
    for _ = 1, 8 do
        if not Finite(mapID) or mapID <= 0 then return end
        local info = Read(C_Map.GetMapInfo, mapID)
        if type(info) ~= "table" or not Finite(info.mapType) then return end
        if info.mapType == Enum.UIMapType.Zone then return mapID end
        if info.mapType < Enum.UIMapType.Zone then return end
        mapID = info.parentMapID
    end
end

-- The zone group a quest's own map puts it in, or nil where it has none.
local function ZoneGroup(questID, zone)
    local questZone = ZoneMap(Read(GetQuestUiMapID, questID, true))
    return questZone and (questZone == zone and "localQuests" or "otherQuests") or nil
end

local function QuestGroup(questID, focused, zone, complete)
    if not zone or questID == focused then return Category(questID, focused, complete) end
    return ZoneGroup(questID, zone) or Category(questID, focused, complete)
end

local function PlayerZone(c)
    return not c.groupQuestsByHeader and c.groupQuestsByZone and ZoneMap(Read(C_Map.GetBestMapForUnit, "player"))
end

-- The quests list carries what it was collected with (CollectQuests): zone is
-- the player's zone (false with the grouping off, nil without a readable one),
-- focus the focused quest, and known tells that every watched quest and all a
-- quest shows was read. Objectives.lua clears known where it empties the list.
--
-- A zone event with zone grouping on (Objectives.lua) collected every watched
-- quest in full on each subzone change, in the frame that also showed the zone
-- banner (the 2026-11-15 outdoor walk). For a list known to be whole it now
-- reads again only what the groups are made from (the player's zone, the
-- focused quest and each quest's own zone) and collects when one of them
-- changed: the zone and focus are compared by what was read, so one that was
-- unreadable collects once it reads differently. A list that is not known
-- (never collected, emptied, or a watch count, quest ID, title, objective or
-- other detail was secret or missing) is collected on every zone event as
-- before, which is what shows a quest or line again once the client gives it.
local function QuestGroupsChanged(self)
    local list = self.sources.quests
    if not list or not list.known then return true end
    local zone = PlayerZone(self.config)
    if zone ~= list.zone or Read(C_SuperTrack.GetSuperTrackedQuestID) ~= list.focus then return true end
    if not zone then return false end
    for i = 1, list.count do
        local entry = list[i]
        local group = entry.group
        if group ~= "focused" then
            local collected = (group == "localQuests" or group == "otherQuests") and group or nil
            if ZoneGroup(entry.id, zone) ~= collected then return true end
        end
    end
    return false
end

local seen = {}
local function CollectQuests(list, c)
    for id in pairs(seen) do seen[id] = nil end
    local focused = Read(C_SuperTrack.GetSuperTrackedQuestID)
    local zone = PlayerZone(c)
    -- The zone, the focus and each quest's own zone are read again by
    -- QuestGroupsChanged; everything else must have been readable here.
    list.zone, list.focus, list.known = zone, focused, false
    partial = false
    if c.groupQuestsByHeader or c.showQuestLogCount then
        O.ReadQuestLog(list, c)
    else
        list.logUsage, list.namedSections, list.sectionByName, list.questHeaders = nil, nil, nil, nil
    end
    local presentation = c.groupQuestsByHeader or c.showQuestLevel or c.questDifficultyColor or c.showDungeonBadge
    local count = C_QuestLog.GetNumQuestWatches()
    if not Finite(count) then return end
    for i = 1, math.min(count, 40) do
        local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if Finite(id) and id > 0 then
            if not seen[id] then
                seen[id] = true
                local title = QuestTitle(id)
                if title then
                    -- One snapshot for the category, completion hint and item in this refresh.
                    local complete = Detail(C_QuestLog.IsComplete, id) == true
                    local group = QuestGroup(id, focused, zone, complete)
                    AddQuest(list, c, id, title, group, true, false, complete)
                    if presentation then O.ApplyQuestLog(list, list[list.count], c) end
                else
                    partial = true
                end
            end
        else
            partial = true
        end
    end
    list.known = not partial
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
                        AddQuestObjective(entry, line, Public(done) and done == true,
                            Finite(percent) and math.max(0, math.min(100, percent)) or nil, c.hideCompletedObjectives)
                    end
                end
                if c.showTimers ~= false then entry.timeLeft = QuestTimeLeft(id, true) end
            end
        end
    end
end

-- One open criterion as Blizzard's achievement module words it
-- (Blizzard_AchievementObjectiveTracker.lua, AddAchievement): a progress
-- criterion is its count before the achievement's description ("74/100
-- Complete 100 victories"), a meta criterion the name of its achievement,
-- any other its own text.
local function CriterionLine(id, index, description)
    local line, kind, done, _, _, _, flags, assetID, quantity = GetAchievementCriteriaInfo(id, index)
    if not Public(done) or done then return end
    quantity = Text(quantity)
    if description and quantity and Finite(flags) and bit.band(flags, EVALUATION_TREE_FLAG_PROGRESS_BAR) ~= 0 then
        -- A money count is coin icons; it takes the line above the description.
        if quantity:lower():find("interface\\moneyframe", 1, true) then return quantity .. "\n" .. description end
        return (quantity:gsub(" / ", "/")) .. " " .. description
    end
    if Public(kind) and kind == CRITERIA_TYPE_ACHIEVEMENT and Finite(assetID) then
        local _, name = GetAchievementInfo(assetID)
        return Text(name) or Text(line)
    end
    return Text(line)
end

-- Blizzard hides an achievement this character earned, not one that only
-- another character completed.
local function CollectAchievements(list)
    local ids = Read(C_ContentTracking.GetTrackedIDs, Enum.ContentTrackingType.Achievement)
    if type(ids) ~= "table" then return end
    for i = 1, math.min(#ids, 15) do
        local id = ids[i]
        if Finite(id) then
            local _, name, _, _, _, _, _, description, _, _, _, _, earned = GetAchievementInfo(id)
            if Text(name) and Public(earned) and not earned then
                local entry = NextEntry(list, id, name, "achievements")
                entry.tracked = true
                description = Text(description)
                local count = Read(GetAchievementNumCriteria, id)
                if Finite(count) and count > 0 then
                    for j = 1, count do
                        local line = CriterionLine(id, j, description)
                        if line then AddLine(entry, line) end
                    end
                elseif description then
                    -- An achievement without criteria is its description.
                    AddLine(entry, description)
                end
            end
        end
    end
end

-- Blizzard attaches stage widgets to the set returned by GetStepInfo.
local function ScenarioWidgetState(widgetSetID, showTimers)
    if not widgetSetID then return nil end
    local manager = C_UIWidgetManager
    local types = Enum.UIWidgetVisualizationType
    local timeLeft, headerSetID
    local widgets = Read(manager.GetAllWidgetsBySetID, widgetSetID)
    if type(widgets) == "table" then
        for i = 1, #widgets do
            local widget = widgets[i]
            if Public(widget) and type(widget) == "table"
                and Finite(widget.widgetID) and Public(widget.widgetType) then
                if showTimers and widget.widgetType == types.ScenarioHeaderTimer then
                    local info = Read(manager.GetScenarioHeaderTimerWidgetVisualizationInfo, widget.widgetID)
                    if type(info) == "table" and Public(info.shownState)
                        and info.shownState ~= Enum.WidgetShownState.Hidden
                        and Finite(info.timerMin) and Finite(info.timerMax) and Finite(info.timerValue)
                        and info.timerMax > info.timerMin then
                        local left = math.min(info.timerValue, info.timerMax) - info.timerMin
                        if left > 0 then timeLeft = left end
                    end
                elseif widget.widgetType == types.ScenarioHeaderDelves then
                    local info = Read(manager.GetScenarioHeaderDelvesWidgetVisualizationInfo, widget.widgetID)
                    if type(info) == "table" and Public(info.shownState)
                        and info.shownState ~= Enum.WidgetShownState.Hidden then
                        headerSetID = widgetSetID
                    end
                end
            end
        end
    end
    return timeLeft, headerSetID, widgets
end

-- Native partitions are absolute contribution milestones, not quest totals.
local function NextMilestone(info, value)
    local goal, partitions = info.barMax, info.partitionValues
    if not Public(partitions) then return end
    if partitions == nil then return goal end
    if type(partitions) ~= "table" then return end
    for i = 1, #partitions do
        local point = partitions[i]
        if not Finite(point) then return end
        if point > value and point > info.barMin and point < goal then goal = point end
    end
    return goal
end

local function ScenarioProgress(entry, widgets, seen)
    if type(widgets) ~= "table" then return end
    local manager, types = C_UIWidgetManager, Enum.UIWidgetVisualizationType
    for i = 1, #widgets do
        local widget = widgets[i]
        if Public(widget) and type(widget) == "table" and Finite(widget.widgetID)
            and Public(widget.widgetType) and types.StatusBar and widget.widgetType == types.StatusBar
            and not seen[widget.widgetID] then
            seen[widget.widgetID] = true
            local info = Read(manager.GetStatusBarWidgetVisualizationInfo, widget.widgetID)
            if type(info) == "table" and Public(info.shownState) and info.shownState == Enum.WidgetShownState.Shown
                and Text(info.text) and Finite(info.barMin) and Finite(info.barMax) and Finite(info.barValue)
                and (info.barMax > info.barMin or (info.barMin == info.barMax and info.barValue == info.barMax and info.barMax > 0)) then
                local value = math.max(info.barMin, math.min(info.barMax, info.barValue))
                local goal = NextMilestone(info, value)
                if goal then
                    -- Blizzard also treats equal nonzero min/max/value as full.
                    local percent = info.barMax > info.barMin and 100 * (value - info.barMin) / (info.barMax - info.barMin) or 100
                    AddLine(entry, string.format("%s  %d/%d", info.text, value, goal), value == info.barMax, percent)
                end
            end
        end
    end
end

-- Only discover the top-center set while a valid scenario is being collected.
-- Reuse the stage snapshot; a native Delve header already displays that set.
local function ScenarioWidgets(entry, c)
    local self, manager = O.M, C_UIWidgetManager
    local widgets
    entry.timeLeft, entry.scenarioHeaderSetID, widgets = ScenarioWidgetState(self.scenarioWidgetSetID, c.showTimers ~= false)
    local seen = self.scenarioProgressWidgets
    for id in pairs(seen) do seen[id] = nil end
    if entry.scenarioHeaderSetID then
        for i = 1, #widgets do
            local widget = widgets[i]
            if Public(widget) and type(widget) == "table" and Finite(widget.widgetID) then seen[widget.widgetID] = true end
        end
    else
        ScenarioProgress(entry, widgets, seen)
    end
    local top = Read(manager.GetTopCenterWidgetSetID)
    self.scenarioTopWidgetSetID = Finite(top) and top > 0 and top or nil
    if self.scenarioTopWidgetSetID and top ~= self.scenarioWidgetSetID then
        ScenarioProgress(entry, Read(manager.GetAllWidgetsBySetID, top), seen)
    end
end

local function ScenarioPercent(value)
    if not Finite(value) then return end
    local percent = math.max(0, math.min(100, value))
    return percent, string.format("%d%%", math.floor(percent + .5))
end

local function CollectScenario(list, c)
    local scenario = C_Scenario
    local name, stage, total, _, _, _, _, _, _, _, _, _, scenarioID = scenario.GetInfo()
    if not Text(name) or not Finite(stage) or not Finite(total) or total < 1 or stage > total then return end
    local entry = NextEntry(list, 0, name, "scenario")
    entry.scenarioID = Finite(scenarioID) and scenarioID or nil
    -- Blizzard's stage block shows its find-group button on the same check.
    local groupable = entry.scenarioID and Read(C_LFGList.CanCreateScenarioGroup, entry.scenarioID)
    entry.findGroup = groupable == true or nil
    local stepName, description, criteriaCount, _, _, _, _, _, _, weightedProgress, _, widgetSetID = scenario.GetStepInfo()
    O.M.scenarioWidgetSetID = Finite(widgetSetID) and widgetSetID > 0 and widgetSetID or nil
    local stageFormat = Text(_G.SCENARIO_STAGE_STATUS)
    local stageText = stageFormat and stageFormat:format(stage, total) or string.format("%d/%d", stage, total)
    local stepText, detail = Text(stepName), Text(description)
    if stepText then stageText = stageText .. ": " .. stepText end
    local percent, percentText = ScenarioPercent(weightedProgress)
    local separateDetail = detail and detail ~= stepText
    AddLine(entry, stageText .. (percent and not separateDetail and "  " .. percentText or ""), false,
        percent and not separateDetail and percent or nil)
    if separateDetail then AddLine(entry, detail .. (percent and "  " .. percentText or ""), false, percent) end
    local criteriaInfo = C_ScenarioInfo.GetCriteriaInfo
    ScenarioWidgets(entry, c)
    -- A step-wide progress bar replaces its individual criteria in Blizzard's tracker.
    if percent or not Finite(criteriaCount) then return end
    for i = 1, criteriaCount do
        local info = Read(criteriaInfo, i)
        if type(info) == "table" then
            local line = Text(info.description)
            if line then
                local weightedState, formattedState = info.isWeightedProgress, info.isFormatted
                local weighted = Public(weightedState) and weightedState == true
                local done = Public(info.completed) and info.completed == true
                local criteriaPercent, criteriaText
                if weighted then
                    criteriaPercent, criteriaText = ScenarioPercent(info.quantity)
                    if criteriaPercent then line = line .. "  " .. criteriaText end
                elseif Public(weightedState) and Public(formattedState) and formattedState ~= true
                    and Finite(info.quantity) and Finite(info.totalQuantity) and info.totalQuantity > 0 then
                    line = string.format("%d/%d %s", info.quantity, info.totalQuantity, line)
                end
                AddLine(entry, line, done, not done and criteriaPercent or nil)
            end
            if c.showTimers ~= false and Finite(info.duration) and Finite(info.elapsed)
                and info.duration > info.elapsed then
                local left = info.duration - info.elapsed
                if not entry.timeLeft then entry.timeLeft = left end
            end
        end
    end
end

------------------------------------------------------------------ tracked recipes
-- Blizzard_ProfessionsRecipeTracker reads both lists, including recipes tracked
-- from customer orders for professions the player has not learned.
local function RecipeReagentCount(reagents)
    local total = 0
    for i = 1, #reagents do
        local reagent = reagents[i]
        if not Public(reagent) or type(reagent) ~= "table" then return end
        local quantity
        if Finite(reagent.itemID) and reagent.itemID > 0 then
            quantity = ItemUtil.GetCraftingReagentCount(reagent.itemID)
        elseif Finite(reagent.currencyID) and reagent.currencyID > 0 then
            local info = Read(C_CurrencyInfo.GetCurrencyInfo, reagent.currencyID)
            if type(info) == "table" then quantity = info.quantity end
        end
        if not Finite(quantity) or quantity < 0 then return end
        total = total + quantity
    end
    return total
end

local function RecipeReagentName(slot, reagent)
    if slot.reagentType == Enum.CraftingReagentType.Modifying then
        local info = slot.slotInfo
        return Public(info) and type(info) == "table" and Text(info.slotText) or nil
    end
    if Finite(reagent.itemID) and reagent.itemID > 0 then
        local name = Read(C_Item.GetItemNameByID, reagent.itemID)
        if not Text(name) then
            local needed = O.M.recipeItemsNeeded or {}
            O.M.recipeItemsNeeded = needed
            needed[reagent.itemID] = true
            local pending = O.M.recipeItemsPending or {}
            O.M.recipeItemsPending = pending
            if not pending[reagent.itemID] then
                pending[reagent.itemID] = true
                C_Item.RequestLoadItemDataByID(reagent.itemID)
            end
        end
        return Text(name)
    elseif Finite(reagent.currencyID) and reagent.currencyID > 0 then
        local info = Read(C_CurrencyInfo.GetCurrencyInfo, reagent.currencyID)
        return type(info) == "table" and Text(info.name) or nil
    end
end

local function RecipeQuantity(slot)
    local variables = slot.variableQuantities
    if Public(variables) and type(variables) == "table" and #variables > 0 then
        local low, high = math.huge, 0
        for i = 1, #variables do
            local value = variables[i]
            local quantity = Public(value) and type(value) == "table" and value.quantity
            if not Finite(quantity) or quantity < 0 then return end
            low, high = math.min(low, quantity), math.max(high, quantity)
        end
        return PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT:format(low, high)
    end
    local quantity = slot.quantityRequired
    if Finite(quantity) and quantity >= 0 then return nil, quantity end
end

local function AddRecipeLine(entry, slot)
    if not Public(slot) or type(slot) ~= "table" or not Public(slot.required) or slot.required ~= true
        or not Finite(slot.reagentType) then return end
    local kind = slot.reagentType
    if kind ~= Enum.CraftingReagentType.Basic and kind ~= Enum.CraftingReagentType.Modifying then return end
    local reagents = slot.reagents
    if not Public(reagents) or type(reagents) ~= "table" or #reagents == 0 then return end
    local reagent = reagents[1]
    if not Public(reagent) or type(reagent) ~= "table" then return end
    local name = RecipeReagentName(slot, reagent)
    if not name then return end
    local range, required = RecipeQuantity(slot)
    if range then
        AddLine(entry, PROFESSIONS_TRACKER_REAGENT_FORMAT:format(range, name), false)
    elseif required then
        local quantity = RecipeReagentCount(reagents)
        local counts = string.format("%s/%d", Finite(quantity) and tostring(quantity) or "?", required)
        AddLine(entry, PROFESSIONS_TRACKER_REAGENT_FORMAT:format(counts, name), Finite(quantity) and quantity >= required)
    end
end

local function CollectRecipeList(list, recraft)
    local ids = Read(C_TradeSkillUI.GetRecipesTracked, recraft)
    if type(ids) ~= "table" then return end
    for i = 1, #ids do
        local id = ids[i]
        if Finite(id) and id > 0 then
            local schematic = Read(C_TradeSkillUI.GetRecipeSchematic, id, recraft)
            local name = type(schematic) == "table" and Text(schematic.name)
            if name then
                local title = recraft and PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER:format(name) or name
                local entry = NextEntry(list, recraft and -id or id, title, "recipes")
                entry.recipeID, entry.isRecraft, entry.tracked = id, recraft, true
                local slots = schematic.reagentSlotSchematics
                if Public(slots) and type(slots) == "table" then
                    -- Match the native order: required modifying slots before basic ones.
                    for pass = 1, 2 do
                        local first, last, step = 1, #slots, 1
                        if pass == 1 then first, last, step = #slots, 1, -1 end
                        for j = first, last, step do
                            local slot = slots[j]
                            if Public(slot) and type(slot) == "table" and Finite(slot.reagentType)
                                and (slot.reagentType == Enum.CraftingReagentType.Modifying) == (pass == 1) then
                                AddRecipeLine(entry, slot)
                            end
                        end
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------ collection pass
local COLLECTORS = {
    recipes = function(list, c)
        local needed = O.M.recipeItemsNeeded
        if needed then for id in pairs(needed) do needed[id] = nil end end
        -- Switched off, nothing is read and no item name is waited for.
        if c.showRecipes then
            CollectRecipeList(list, true)
            CollectRecipeList(list, false)
        end
        local pending = O.M.recipeItemsPending
        if pending then
            for id in pairs(pending) do
                if not O.M.recipeItemsNeeded[id] then pending[id] = nil end
            end
        end
    end,
    quests = function(list, c) CollectQuests(list, c) end,
    world = function(list, c) if c.showWorldQuests then CollectWorld(list, c) end end,
    bonus = function(list, c) if c.showBonus then CollectBonus(list, c) end end,
    achievements = function(list, c) if c.showAchievements then CollectAchievements(list) end end,
    scenario = function(list, c)
        O.M.scenarioWidgetSetID, O.M.scenarioTopWidgetSetID = nil, nil
        if c.showScenario then CollectScenario(list, c) end
    end,
}
-- ObjectivesContent.lua adds its sources here.
O.COLLECTORS = COLLECTORS

-- Re-reads every dirty source into its reused entry list.
function O.CollectDirty(self)
    tasksRead, tasksTable = false, nil
    -- A zone event: the quests are collected unless their list is known and its groups still hold.
    if self.dirty.questZones then
        self.dirty.questZones = nil
        if not self.dirty.quests and QuestGroupsChanged(self) then self.dirty.quests = true end
    end
    local now = GetTime()
    for i = 1, #SOURCES do
        local key = SOURCES[i]
        if self.dirty[key] then
            local list = ResetSource(self, key)
            COLLECTORS[key](list, self.config)
            for index = 1, list.count do
                local entry = list[index]
                entry.timerEnd = Finite(entry.timeLeft) and entry.timeLeft > 0 and now + entry.timeLeft or nil
            end
            self.dirty[key] = nil
        end
    end
    tasksTable = nil
end
