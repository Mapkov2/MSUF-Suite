local _, P = ...
local NS, S = P.NS, P.Suite
local MythicPlus = S.MythicPlus
local ID = "objectives"

-- An MSUF-owned objective tracker. Events mark sources dirty; one deferred
-- flush per frame re-reads them into reused entry tables, and rows are laid
-- out again only when their content or geometry changed.
local M = {
    sources = {}, rows = {}, freeRows = {}, dirty = {},
    staleFlushes = 0, staleTimers = 0,
}
local FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local ORDER = { "scenario", "focused", "campaign", "important", "complete", "quests", "world", "bonus", "achievements" }
local SOURCES = { "quests", "world", "bonus", "achievements", "scenario" }
local GROUP = {
    scenario = { "SCENARIO", .39, .64, .90 },
    focused = { "FOCUSED", .98, .84, .42 },
    campaign = { "CAMPAIGN", .98, .76, .32 },
    important = { "IMPORTANT", .94, .52, .79 },
    complete = { "READY TO TURN IN", .39, .86, .54 },
    quests = { "QUESTS", .91, .92, .95 },
    world = { "WORLD QUESTS", .73, .58, .94 },
    bonus = { "BONUS OBJECTIVES", .47, .82, .80 },
    achievements = { "ACHIEVEMENTS", .83, .62, .38 },
}
local GROUP_COLOR_KEYS = {
    scenario = "scenarioColor", focused = "focusedColor", campaign = "campaignColor",
    important = "importantColor", complete = "completeGroupColor", quests = "questsColor",
    world = "worldColor", bonus = "bonusColor", achievements = "achievementsColor",
}
local SECTION_KEYS = {}
for _, group in ipairs(ORDER) do SECTION_KEYS[group] = "section:" .. group end
local TEXT_RGB, MUTED_RGB, COMPLETE_RGB = { .95, .96, .98 }, { .78, .81, .85 }, { .49, .75, .53 }

local function Public(value)
    return S.Public(value)
end

local Finite = S.Finite

local function Text(value)
    return Public(value) and type(value) == "string" and value ~= "" and value or nil
end

-- Client APIs differ between Retail and Forever and appear with their
-- addons, so they are looked up at call time. Missing APIs and secret
-- results read as nil.
local function Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local value = fn(...)
    return Public(value) and value or nil
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
    entry.tracked, entry.itemIcon, entry.timeLeft, entry.scenarioID = nil, nil, nil, nil
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
    local questLog = C_QuestLog
    local index = Read(questLog and questLog.GetLogIndexForQuestID, questID)
    if not Finite(index) or index < 1 or type(_G.GetQuestLogSpecialItemInfo) ~= "function" then return end
    local complete = Read(questLog and questLog.IsComplete, questID) == true
    if QuestUtil and type(QuestUtil.QuestShowsItemByIndex) == "function"
        and Read(QuestUtil.QuestShowsItemByIndex, index, complete) ~= true then
        return
    end
    local _, icon, _, showWhenComplete = _G.GetQuestLogSpecialItemInfo(index)
    if not Public(icon) or (type(icon) ~= "number" and type(icon) ~= "string")
        or (complete and (not Public(showWhenComplete) or showWhenComplete ~= true)) then
        return
    end
    return icon
end

local function QuestTimeLeft(questID, task)
    if task then
        local left = Read(C_TaskQuest and C_TaskQuest.GetQuestTimeLeftSeconds, questID)
        return Finite(left) and left > 0 and left or nil
    end
    local timeAllowed = C_QuestLog and C_QuestLog.GetTimeAllowed
    if type(timeAllowed) ~= "function" then return end
    local total, elapsed = timeAllowed(questID)
    if Finite(total) and Finite(elapsed) and total > elapsed then return total - elapsed end
end

local function AddObjectiveLines(entry, questID)
    local objectives = Read(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    if type(objectives) ~= "table" then return end
    for i = 1, #objectives do
        local objective = objectives[i]
        if Public(objective) and type(objective) == "table" then
            local line = Text(objective.text)
            if line then
                local percent
                if Text(objective.type) == "progressbar" then
                    local value = Read(_G.GetQuestProgressBarPercent, questID)
                    if Finite(value) then percent = math.max(0, math.min(100, value)) end
                end
                AddLine(entry, line, Public(objective.finished) and objective.finished == true, percent)
            end
        end
    end
end

local function QuestTitle(questID)
    local questLog = C_QuestLog
    local title = Read(questLog and questLog.GetTitleForQuestID, questID)
    if Text(title) then return title end
    local index = Read(questLog and questLog.GetLogIndexForQuestID, questID)
    local info = Finite(index) and Read(questLog and questLog.GetInfo, index)
    return type(info) == "table" and Text(info.title) or nil
end

local function Category(questID, focused)
    if questID == focused then return "focused" end
    if Read(C_QuestLog and C_QuestLog.IsComplete, questID) == true then return "complete" end
    local kind = Read(C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification, questID)
    local kinds = Enum and Enum.QuestClassification
    if Finite(kind) and type(kinds) == "table" then
        if kind == kinds.Campaign then return "campaign" end
        if kind == kinds.Important or kind == kinds.Legendary then return "important" end
    end
    return "quests"
end

local function AddQuest(list, c, id, title, group, tracked, task)
    local entry = NextEntry(list, id, title, group)
    entry.tracked = tracked
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
        tasksTable = Read(_G.GetTasksTable)
    end
    return type(tasksTable) == "table" and tasksTable or nil
end

local seen = {}
local function CollectQuests(list, c)
    for id in pairs(seen) do seen[id] = nil end
    local focused = Read(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID)
    local count = Read(C_QuestLog and C_QuestLog.GetNumQuestWatches)
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
    local count = Read(C_QuestLog and C_QuestLog.GetNumWorldQuestWatches)
    if not Finite(count) then return end
    local taskInfo = C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID
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
        if Finite(id) and id > 0 and not seen[id] and Read(_G.QuestUtils_IsQuestWorldQuest, id) == true then
            seen[id] = true
            local title = Text(QuestTitle(id) or Read(taskInfo, id))
            if title then AddQuest(list, c, id, title, "world", false, true) end
        end
    end
end

local function CollectBonus(list, c)
    local tasks = Tasks()
    if not tasks or type(GetTaskInfo) ~= "function" or type(GetQuestObjectiveInfo) ~= "function" then return end
    for i = 1, math.min(#tasks, 30) do
        local id = tasks[i]
        if Finite(id) and id > 0 and Read(_G.QuestUtils_IsQuestWorldQuest, id) ~= true then
            local inArea, _, count, taskName = GetTaskInfo(id)
            if Public(inArea) and inArea == true and Finite(count) and Text(taskName) then
                local entry = NextEntry(list, id, taskName, "bonus")
                for j = 1, count do
                    local line, kind, done = GetQuestObjectiveInfo(id, j, false)
                    if Text(line) then
                        local percent = Text(kind) == "progressbar" and Read(_G.GetQuestProgressBarPercent, id) or nil
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
    local kind = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
    local ids = kind and Read(C_ContentTracking and C_ContentTracking.GetTrackedIDs, kind)
    if type(ids) ~= "table" or type(GetAchievementInfo) ~= "function" then return end
    for i = 1, math.min(#ids, 15) do
        local id = ids[i]
        if Finite(id) then
            local _, name, _, complete = GetAchievementInfo(id)
            if Text(name) and Public(complete) and not complete then
                local entry = NextEntry(list, id, name, "achievements")
                entry.tracked = true
                local count = Read(_G.GetAchievementNumCriteria, id)
                if Finite(count) and type(GetAchievementCriteriaInfo) == "function" then
                    for j = 1, count do
                        local line, _, done = GetAchievementCriteriaInfo(id, j)
                        if Text(line) and Public(done) and not done then AddLine(entry, line) end
                    end
                end
            end
        end
    end
end

local function CollectScenario(list, c)
    local scenario = C_Scenario
    if not (scenario and type(scenario.GetInfo) == "function") then return end
    local name, stage, total, _, _, _, _, _, _, _, _, _, scenarioID = scenario.GetInfo()
    if not Text(name) or not Finite(stage) or not Finite(total) or total < 1 or stage > total then return end
    local entry = NextEntry(list, 0, name, "scenario")
    entry.scenarioID = Finite(scenarioID) and scenarioID or nil
    if type(scenario.GetStepInfo) ~= "function" then return end
    local stepName, description, criteriaCount = scenario.GetStepInfo()
    if Text(stepName) then AddLine(entry, stepName) end
    if Text(description) and description ~= stepName then AddLine(entry, description) end
    local criteriaInfo = C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo
    if not Finite(criteriaCount) or type(criteriaInfo) ~= "function" then return end
    for i = 1, criteriaCount do
        local info = Read(criteriaInfo, i)
        if type(info) == "table" then
            local line = Text(info.description)
            if line then AddLine(entry, line, Public(info.completed) and info.completed == true) end
            if c.showTimers ~= false and Finite(info.duration) and Finite(info.elapsed)
                and info.duration > info.elapsed then
                local left = info.duration - info.elapsed
                if not entry.timeLeft or left < entry.timeLeft then entry.timeLeft = left end
            end
        end
    end
end

------------------------------------------------------------------ frames
local function Create(self)
    if self.host then return end
    local host = S.CreateFrame("Frame", "MSUFSuiteObjectiveTracker", UIParent)
    host:SetFrameStrata("LOW")
    host:EnableMouse(true)
    local background = S.CreateTexture(host, nil, "BACKGROUND")
    background:SetAllPoints(host)
    local title = S.CreateFontString(host, nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 11, -7)
    title:SetJustifyH("LEFT")
    local headerClick = S.CreateFrame("Button", nil, host)
    headerClick:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    headerClick:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    headerClick:SetHeight(34)
    headerClick:RegisterForClicks("LeftButtonUp")
    headerClick:SetScript("OnClick", function()
        if type(_G.OpenQuestLog) == "function" then _G.OpenQuestLog() end
    end)
    local count = S.CreateFontString(host, nil, "OVERLAY")
    count:SetPoint("TOPRIGHT", -11, -10)
    local divider = S.CreateTexture(host, nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 11, -33)
    divider:SetPoint("TOPRIGHT", -11, -33)
    divider:SetHeight(1)
    local scroll = S.CreateFrame("ScrollFrame", nil, host)
    scroll:SetPoint("TOPLEFT", 7, -40)
    scroll:SetPoint("BOTTOMRIGHT", -7, 5)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(frame, delta)
        local max = math.max(0, frame:GetVerticalScrollRange())
        frame:SetVerticalScroll(math.max(0, math.min(max, frame:GetVerticalScroll() - delta * 38)))
    end)
    local content = S.CreateFrame("Frame", nil, scroll)
    content:SetWidth(300)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    self.host, self.background, self.title, self.count, self.divider = host, background, title, count, divider
    self.headerClick = headerClick
    self.scroll, self.content = scroll, content
end

------------------------------------------------------------------ Blizzard actions
local function OpenQuestDetails(questID)
    if not Finite(questID) or questID <= 0 then return end
    if type(_G.QuestMapFrame_OpenToQuestDetails) == "function" then
        _G.QuestMapFrame_OpenToQuestDetails(questID)
        return
    end
    if type(_G.OpenQuestLog) == "function" then _G.OpenQuestLog() end
    if type(_G.QuestMapFrame_ShowQuestDetails) == "function" then _G.QuestMapFrame_ShowQuestDetails(questID) end
end

local function OpenTaskMap(questID)
    local mapID = Read(C_TaskQuest and C_TaskQuest.GetQuestZoneID, questID)
    if Finite(mapID) and mapID > 0 and type(_G.OpenQuestLog) == "function" then
        _G.OpenQuestLog(mapID)
        local registry = _G.EventRegistry
        if registry and type(registry.TriggerEvent) == "function" then
            registry:TriggerEvent("MapCanvas.PingQuestID", questID)
        end
    else
        OpenQuestDetails(questID)
    end
end

local function OpenAchievement(achievementID)
    if type(_G.ShowAchievementFrameForAchievement) == "function" then
        _G.ShowAchievementFrameForAchievement(achievementID)
    end
end

local function OpenJournal()
    if type(_G.ToggleEncounterJournal) == "function" then _G.ToggleEncounterJournal() end
end

local function WatchTogglePressed()
    -- Blizzard's QUESTWATCHTOGGLE binding defaults to Shift. Keep Shift working
    -- even when that binding has been customized by the player.
    return Read(_G.IsModifiedClick, "QUESTWATCHTOGGLE") == true or Read(_G.IsShiftKeyDown) == true
end

local function CanUntrack(button)
    if Finite(button.achievementID) then
        local kind = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
        local stop = Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual
        return kind and stop and C_ContentTracking and type(C_ContentTracking.StopTracking) == "function"
    end
    if not Finite(button.questID) or not button.tracked then return false end
    if button.group == "world" then
        return QuestUtil and type(QuestUtil.UntrackWorldQuest) == "function"
    end
    return button.group ~= "bonus"
        and Read(QuestUtil and QuestUtil.CanRemoveQuestWatch) == true
        and C_QuestLog and type(C_QuestLog.RemoveQuestWatch) == "function"
end

local function Untrack(button)
    if not CanUntrack(button) then return end
    if Finite(button.achievementID) then
        C_ContentTracking.StopTracking(Enum.ContentTrackingType.Achievement,
            button.achievementID, Enum.ContentTrackingStopType.Manual)
    elseif button.group == "world" then
        QuestUtil.UntrackWorldQuest(button.questID)
    else
        C_QuestLog.RemoveQuestWatch(button.questID)
    end
end

local function BuildAchievementMenu(root, button)
    local achievementID = button.achievementID
    if type(_G.ShowAchievementFrameForAchievement) == "function" then
        root:CreateButton(_G.OBJECTIVES_VIEW_ACHIEVEMENT or "View achievement", function()
            OpenAchievement(achievementID)
        end)
    end
    if CanUntrack(button) then
        root:CreateButton(_G.OBJECTIVES_STOP_TRACKING or "Stop tracking", function() Untrack(button) end)
    end
end

local function BuildScenarioMenu(root, scenarioID)
    if type(_G.ToggleEncounterJournal) == "function" then
        root:CreateButton(_G.ENCOUNTER_JOURNAL or "Adventure Guide", OpenJournal)
    end
    if Finite(scenarioID) and Read(C_LFGList and C_LFGList.CanCreateScenarioGroup, scenarioID) == true
        and type(_G.LFGListUtil_FindScenarioGroup) == "function" then
        root:CreateButton(_G.FIND_A_GROUP or "Find group", function()
            _G.LFGListUtil_FindScenarioGroup(scenarioID, true)
        end)
    end
end

local function BuildQuestMenu(root, button)
    local questID, group = button.questID, button.group
    local task = group == "world" or group == "bonus"
    root:CreateButton(task and (_G.OBJECTIVES_SHOW_QUEST_MAP or "Show on map")
        or (_G.OBJECTIVES_VIEW_IN_QUESTLOG or "View in Quest Log"), function()
        if task then OpenTaskMap(questID) else OpenQuestDetails(questID) end
    end)
    local superTrack = C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
    if type(superTrack) == "function" then
        local current = Read(C_SuperTrack.GetSuperTrackedQuestID)
        local selected = Finite(current) and current == questID
        root:CreateButton(selected and (_G.STOP_SUPER_TRACK_QUEST or "Stop super tracking")
            or (_G.SUPER_TRACK_QUEST or "Super track quest"), function()
            superTrack(selected and 0 or questID)
        end)
    end
    if CanUntrack(button) then
        root:CreateButton(_G.OBJECTIVES_STOP_TRACKING or "Stop tracking", function() Untrack(button) end)
    end
    if not task and Read(C_QuestLog and C_QuestLog.IsPushableQuest, questID) == true
        and Read(_G.IsInGroup) == true and QuestUtil and type(QuestUtil.ShareQuest) == "function" then
        root:CreateButton(_G.SHARE_QUEST or "Share quest", function() QuestUtil.ShareQuest(questID) end)
    end
    if not task and Read(C_QuestLog and C_QuestLog.CanAbandonQuest, questID) == true
        and type(_G.QuestMapQuestOptions_AbandonQuest) == "function" then
        root:CreateButton(_G.ABANDON_QUEST_ABBREV or "Abandon quest", function()
            _G.QuestMapQuestOptions_AbandonQuest(questID)
        end)
    end
end

local function ShowContextMenu(button)
    local menu = _G.MenuUtil
    if not (menu and type(menu.CreateContextMenu) == "function") then return end
    local group, title = button.group, button.menuTitle or "Objective"
    if not (Finite(button.questID) or Finite(button.achievementID) or group == "scenario") then return end
    menu.CreateContextMenu(button, function(_, root)
        root:CreateTitle(title)
        if Finite(button.achievementID) then
            BuildAchievementMenu(root, button)
        elseif group == "scenario" then
            BuildScenarioMenu(root, button.scenarioID)
        else
            BuildQuestMenu(root, button)
        end
    end)
end

------------------------------------------------------------------ rows
local Render

-- Collapse state is module-owned runtime state (S.ModuleState), never a setting.
local function ToggleGroup(self, group)
    self.collapsedGroups[group] = not self.collapsedGroups[group] or nil
    Render(self)
end

local function OnRowClick(button, mouseButton)
    if mouseButton == "RightButton" then
        ShowContextMenu(button)
        return
    end
    if button.kind == "section" then
        ToggleGroup(M, button.group)
        return
    end
    if WatchTogglePressed() and (Finite(button.questID) or Finite(button.achievementID)) then
        Untrack(button)
        return
    end
    if Finite(button.questID) then
        OpenQuestDetails(button.questID)
    elseif Finite(button.achievementID) then
        OpenAchievement(button.achievementID)
    elseif button.group == "scenario" then
        OpenJournal()
    end
end

local function OnRowEnter(button)
    local tooltip = _G.GameTooltip
    if not tooltip or not button.menuTitle then return end
    tooltip:SetOwner(button, "ANCHOR_LEFT")
    if Finite(button.questID) and type(tooltip.SetHyperlink) == "function" then
        tooltip:SetHyperlink("quest:" .. button.questID)
    elseif Finite(button.achievementID) and type(tooltip.SetAchievementByID) == "function" then
        tooltip:SetAchievementByID(button.achievementID)
    else
        tooltip:SetText(button.menuTitle)
    end
    tooltip:Show()
end

local function OnOwnedLeave(button)
    local tooltip = _G.GameTooltip
    if tooltip and tooltip:GetOwner() == button then tooltip:Hide() end
end

local function OnCollapseClick(button, mouseButton)
    local owner = button.ownerRow
    if mouseButton == "RightButton" then
        ShowContextMenu(owner)
        return
    end
    if owner.kind == "section" then
        ToggleGroup(M, owner.group)
    elseif owner.collapseKey then
        local base = owner.collapseKey
        M.collapsedEntries[base] = not M.collapsedEntries[base] or nil
        Render(M)
    end
end

local function NewRow(self, key, kind)
    local pool = self.freeRows
    local match
    for i = #pool, 1, -1 do
        if pool[i].kind == kind then
            match = i
            break
        end
    end
    local row = match and table.remove(pool, match) or table.remove(pool)
    if row then
        self.rows[key] = row
        return row
    end
    row = S.CreateFrame("Button", nil, self.content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", OnOwnedLeave)
    local stripe = S.CreateTexture(row, nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 2, -3)
    stripe:SetPoint("BOTTOMLEFT", 2, 3)
    stripe:SetWidth(2)
    local text = S.CreateFontString(row, nil, "OVERLAY")
    text:SetPoint("LEFT", 12, 0)
    text:SetPoint("RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    local progress = S.CreateFrame("StatusBar", nil, row)
    progress:SetPoint("BOTTOMLEFT", 12, 1)
    progress:SetPoint("BOTTOMRIGHT", -5, 1)
    progress:SetHeight(2)
    progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    progress:SetMinMaxValues(0, 100)
    progress:Hide()
    row.stripe, row.text, row.progress = stripe, text, progress
    local collapse = S.CreateFrame("Button", nil, row)
    collapse:SetSize(18, 18)
    collapse:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    collapse:SetScript("OnClick", OnCollapseClick)
    local glyph = S.CreateFontString(collapse, nil, "OVERLAY")
    glyph:SetPoint("CENTER", collapse, "CENTER", 0, 0)
    collapse.glyph, collapse.ownerRow = glyph, row
    collapse:Hide()
    row.collapse = collapse
    self.rows[key] = row
    return row
end

-- Blizzard's own tracker item button is a plain Button that calls
-- UseQuestLogSpecialItem from its OnClick; this one does the same.
local function OnItemClick(target, mouseButton)
    if mouseButton == "RightButton" then
        ShowContextMenu(target.ownerRow)
        return
    end
    if WatchTogglePressed() then
        Untrack(target.ownerRow)
        return
    end
    local id = target.ownerRow.questID
    local index = Finite(id) and Read(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, id)
    if Finite(index) and type(_G.UseQuestLogSpecialItem) == "function" then
        -- TODO(in-game): confirm this is not blocked for addon code.
        _G.UseQuestLogSpecialItem(index)
    end
end

local function OnItemEnter(target)
    local tooltip = _G.GameTooltip
    local id = target.ownerRow.questID
    local index = Finite(id) and Read(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, id)
    if tooltip and Finite(index) and type(tooltip.SetQuestLogSpecialItem) == "function" then
        tooltip:SetOwner(target, "ANCHOR_RIGHT")
        tooltip:SetQuestLogSpecialItem(index)
        tooltip:Show()
    end
end

local function EnsureItemButton(row)
    if row.itemButton then return row.itemButton end
    local button = S.CreateFrame("Button", nil, row)
    button:SetSize(22, 22)
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", OnItemClick)
    button:SetScript("OnEnter", OnItemEnter)
    button:SetScript("OnLeave", OnOwnedLeave)
    local icon = S.CreateTexture(button, nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(.08, .92, .08, .92)
    button.icon, button.ownerRow = icon, row
    row.itemButton = button
    return button
end

local function EnsureTimer(row)
    if row.timer then return row.timer end
    local timer = S.CreateFontString(row, nil, "OVERLAY")
    timer:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    timer:SetJustifyH("RIGHT")
    row.timer = timer
    return timer
end

------------------------------------------------------------------ countdowns
local function TimerText(seconds)
    seconds = math.max(0, math.ceil(seconds))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- One shared one-second callback runs while a visible countdown remains.
-- C_Timer.After cannot be cancelled: a cancelled wait only counts as stale.
local UpdateTimers
local function TimerTick()
    if M.staleTimers > 0 then
        M.staleTimers = M.staleTimers - 1
        return
    end
    M.timerPending = false
    UpdateTimers(M)
end

UpdateTimers = function(self)
    if not self.active or self.pausedForRaidCombat or not self.timedRows then return end
    local now, ticking = GetTime(), false
    for row in pairs(self.timedRows) do
        if row.timer and Finite(row.timerEnd) then
            local left = row.timerEnd - now
            if left > 0 then
                local value = TimerText(left)
                if row.timerText ~= value then
                    row.timer:SetText(value)
                    row.timerText = value
                end
                row.timer:Show()
                ticking = true
            else
                row.timer:Hide()
                row.timerEnd = nil
                self.timedRows[row] = nil
            end
        end
    end
    if ticking and not self.timerPending then
        self.timerPending = true
        C_Timer.After(1, TimerTick)
    end
end

------------------------------------------------------------------ theme and layout
local function RGB(hex)
    return { S.RGB(hex) }
end

local function Theme(self)
    local c = self.config
    local skin = self.context and self.context:Skin()
    self.font = S.ResolveFont(c.font) or (skin and skin:GetFont()) or FONT
    local custom = c.colorStyle == 2
    self.textRGB = custom and RGB(c.textColor) or skin and { skin:GetColor("text") } or TEXT_RGB
    self.mutedRGB = custom and RGB(c.mutedColor) or skin and { skin:GetColor("muted") } or MUTED_RGB
    self.completeRGB = custom and RGB(c.completeColor) or COMPLETE_RGB
    self.groupRGB = self.groupRGB or {}
    for group, key in pairs(GROUP_COLOR_KEYS) do
        local spec = GROUP[group]
        self.groupRGB[group] = custom and RGB(c[key]) or { spec[2], spec[3], spec[4] }
    end
    local dark = (skin and skin:GetLook() or "midnightDark") == "midnightDark"
    local opacity = (c.backgroundOpacity or 0) / 100
    if custom then
        local r, g, b = S.RGB(c.backgroundColor)
        self.background:SetColorTexture(r, g, b, opacity)
    elseif skin then
        local r, g, b = skin:GetColor("surface")
        self.background:SetColorTexture(r, g, b, opacity)
    else
        self.background:SetColorTexture(dark and .035 or .025, dark and .039 or .055, dark and .047 or .085, opacity)
    end
    S.SetStyledFont(self.title, self.font, c.titleSize or 18, "OUTLINE", 1, true, 70, 1)
    local headerHeight = math.max(40, (c.titleSize or 18) + 23)
    if self.headerHeight ~= headerHeight then
        self.headerHeight = headerHeight
        self.divider:ClearAllPoints()
        self.divider:SetPoint("TOPLEFT", 11, 7 - headerHeight)
        self.divider:SetPoint("TOPRIGHT", -11, 7 - headerHeight)
        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", 7, -headerHeight)
        self.scroll:SetPoint("BOTTOMRIGHT", -7, 5)
    end
    self.title:SetText("OBJECTIVES")
    if custom then
        self.title:SetTextColor(S.RGB(c.titleColor))
    elseif skin then
        self.title:SetTextColor(skin:GetColor("title"))
    else
        self.title:SetTextColor(.96, .97, .98)
    end
    S.SetStyledFont(self.count, self.font, math.max(9, (c.sectionSize or 14)), "OUTLINE", 1, false)
    if custom then
        self.count:SetTextColor(unpack(self.mutedRGB))
        local r, g, b = S.RGB(c.dividerColor)
        self.divider:SetColorTexture(r, g, b, .35)
    elseif skin then
        self.count:SetTextColor(skin:GetColor("muted"))
        local r, g, b = skin:GetColor("borderSoft")
        self.divider:SetColorTexture(r, g, b, .35)
    else
        self.count:SetTextColor(.72, .75, .80)
        self.divider:SetColorTexture(.69, .72, .78, .35)
    end
end

-- Placement follows the settings only when they changed since the last layout.
local function PlaceHost(self, c, force)
    local changed = force or self.lastWidth ~= c.width or self.lastHeight ~= c.height
        or self.lastScale ~= c.scale or self.lastX ~= c.x or self.lastY ~= c.y
        or self.lastEditMode ~= S.editMode
    if not changed then return false end
    self.lastWidth, self.lastHeight, self.lastScale = c.width, c.height, c.scale
    self.lastX, self.lastY, self.lastEditMode = c.x, c.y, S.editMode
    self.headerClick:SetHeight(self.headerHeight - 5)
    self.host:SetScale(c.scale / 100)
    self.host:SetWidth(c.width)
    self.host:ClearAllPoints()
    self.host:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", c.x, c.y)
    self.content:SetWidth(c.width - 14)
    return true
end

local function FlatSlot(flat, index)
    local item = flat[index]
    if not item then
        item = {}
        flat[index] = item
    end
    -- Both flat buffers survive refreshes. Clear fields that belong to another row kind.
    item.key, item.kind, item.group, item.text, item.height = nil, nil, nil, nil, nil
    item.collapsed, item.menuTitle, item.tracked, item.itemIcon = nil, nil, nil, nil
    item.timeLeft, item.hasLines, item.collapseKey = nil, nil, nil
    item.questID, item.achievementID, item.scenarioID = nil, nil, nil
    item.done, item.percent = nil, nil
    return item
end

-- Row keys are cached per entry so an unchanged tracker builds no strings.
local function EntryBase(entry, group)
    if entry.keyGroup ~= group or entry.keyID ~= entry.id then
        entry.keyGroup, entry.keyID = group, entry.id
        entry.base = group .. ":" .. tostring(entry.id)
        entry.entryKey = "entry:" .. entry.base
        local lineKeys = entry.lineKeys or {}
        for j = #lineKeys, 1, -1 do lineKeys[j] = nil end
        entry.lineKeys = lineKeys
    end
    return entry.base
end

local function LineKey(entry, index)
    local key = entry.lineKeys[index]
    if not key then
        key = "line:" .. entry.base .. ":" .. index
        entry.lineKeys[index] = key
    end
    return key
end

local function AddFlat(flat, index, group, items, c, collapsedGroups, collapsedEntries)
    if #items == 0 then return index end
    index = index + 1
    local section = FlatSlot(flat, index)
    section.key, section.kind, section.group = SECTION_KEYS[group], "section", group
    section.text = GROUP[group][1]
    section.height = math.max(23, (c.sectionSize or 14) + 12)
    section.collapsed = collapsedGroups[group] == true
    if collapsedGroups[group] then return index end
    local entryHeight = math.max(32, (c.entrySize or 15) + 19)
    local objectiveSize = c.objectiveSize or 13
    for i = 1, #items do
        local entry = items[i]
        local base = EntryBase(entry, group)
        local questID = group ~= "achievements" and group ~= "scenario" and entry.id > 0 and entry.id or nil
        local achievementID = group == "achievements" and entry.id or nil
        local scenarioID = group == "scenario" and entry.scenarioID or nil
        local lines = entry.lines
        index = index + 1
        local item = FlatSlot(flat, index)
        item.key, item.kind, item.group = entry.entryKey, "entry", group
        item.text, item.height = entry.title, entryHeight
        item.menuTitle, item.tracked = entry.title, entry.tracked
        item.itemIcon, item.timeLeft = entry.itemIcon, entry.timeLeft
        item.hasLines, item.collapsed, item.collapseKey = lines.count > 0, collapsedEntries[base] == true, base
        item.questID, item.achievementID, item.scenarioID = questID, achievementID, scenarioID
        if not collapsedEntries[base] then
            for j = 1, lines.count do
                local line = lines[j]
                index = index + 1
                item = FlatSlot(flat, index)
                item.key, item.kind, item.group = LineKey(entry, j), "line", group
                item.text, item.done, item.percent = line.text, line.done, line.percent
                item.menuTitle, item.tracked = entry.title, entry.tracked
                item.questID, item.achievementID, item.scenarioID = questID, achievementID, scenarioID
                item.height = math.max(line.percent and 28 or 24, objectiveSize + (line.percent and 17 or 13))
            end
        end
    end
    return index
end

local function SameItem(a, b)
    return b and a.key == b.key and a.kind == b.kind and a.group == b.group
        and a.text == b.text and a.height == b.height and a.done == b.done
        and a.percent == b.percent and a.tracked == b.tracked
        and a.questID == b.questID and a.achievementID == b.achievementID
        and a.scenarioID == b.scenarioID and a.collapsed == b.collapsed
        and a.itemIcon == b.itemIcon and a.timeLeft == b.timeLeft
        and a.hasLines == b.hasLines and a.menuTitle == b.menuTitle
        and a.collapseKey == b.collapseKey
end

local function RenderMythicPlus(self, c)
    local themeChanged = self.retheme or not self.font
    if themeChanged then
        Theme(self)
        MythicPlus.Theme(self)
        self.retheme = false
    end
    PlaceHost(self, c, themeChanged)
    self.title:SetText("MYTHIC+")
    self.count:SetText(self.mplus.level and ("+" .. self.mplus.level) or "")
    self.content:SetHeight(self.mplus.height)
    self.host:SetHeight(math.min(c.height, self.headerHeight + self.mplus.height + 5))
    self.host:Show()
end

-- Groups the collected entries in display order and forgets collapse state
-- of entries that are gone.
local function GroupEntries(self)
    local grouped = self.grouped
    if not grouped then
        grouped = {}
        self.grouped = grouped
    end
    for i = 1, #ORDER do
        local list = grouped[ORDER[i]]
        if not list then
            list = {}
            grouped[ORDER[i]] = list
        end
        for j = #list, 1, -1 do list[j] = nil end
    end
    local liveEntries = self.liveEntries
    if not liveEntries then
        liveEntries = {}
        self.liveEntries = liveEntries
    end
    for key in pairs(liveEntries) do liveEntries[key] = nil end
    for s = 1, #SOURCES do
        local source = self.sources[SOURCES[s]]
        for i = 1, source and source.count or 0 do
            local entry = source[i]
            local list = grouped[entry.group]
            if list then
                list[#list + 1] = entry
                liveEntries[EntryBase(entry, entry.group)] = true
            end
        end
    end
    for key in pairs(self.collapsedEntries) do
        if not liveEntries[key] then self.collapsedEntries[key] = nil end
    end
    return grouped
end

local function PaintRow(self, row, item, c, width, y)
    local color = self.groupRGB[item.group]
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
    row:SetWidth(width)
    row.stripe:SetColorTexture(color[1], color[2], color[3], item.kind == "line" and .35 or .95)
    local size = item.kind == "section" and (c.sectionSize or 14)
        or item.kind == "entry" and (c.entrySize or 15) or (c.objectiveSize or 13)
    if row.cachedSize ~= size or row.cachedFont ~= self.font then
        S.SetStyledFont(row.text, self.font, size, "OUTLINE", 1, true, 70, 1)
        row.cachedSize, row.cachedFont = size, self.font
    end
    if row.cachedText ~= item.text then
        row.text:SetText(item.text)
        row.cachedText = item.text
    end
    row.kind, row.group, row.collapseKey = item.kind, item.group, item.collapseKey
    local rightInset = 4
    if item.itemIcon and item.kind == "entry" then
        local button = EnsureItemButton(row)
        button.icon:SetTexture(item.itemIcon)
        button:ClearAllPoints()
        button:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0)
        button:Show()
        rightInset = rightInset + 27
    elseif row.itemButton then
        row.itemButton:Hide()
    end
    if Finite(item.timeLeft) and item.timeLeft > 0 and item.kind == "entry" then
        local timer = EnsureTimer(row)
        if row.timerFont ~= self.font or row.timerSize ~= size then
            S.SetStyledFont(timer, self.font, math.max(10, size - 1), "OUTLINE", 1, true, 70, 1)
            row.timerFont, row.timerSize = self.font, size
        end
        timer:ClearAllPoints()
        timer:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0)
        timer:SetWidth(58)
        timer:SetTextColor(unpack(self.mutedRGB))
        row.timerEnd = GetTime() + item.timeLeft
        self.timedRows[row] = true
        rightInset = rightInset + 62
    else
        row.timerEnd = nil
        if row.timer then row.timer:Hide() end
    end
    if item.kind == "section" or (item.kind == "entry" and item.hasLines) then
        row.collapse:ClearAllPoints()
        row.collapse:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0)
        S.SetStyledFont(row.collapse.glyph, self.font, math.max(10, size), "OUTLINE", 1, true, 70, 1)
        row.collapse.glyph:SetText(item.collapsed and "+" or "-")
        row.collapse.glyph:SetTextColor(color[1], color[2], color[3])
        row.collapse:Show()
        rightInset = rightInset + 20
    else
        row.collapse:Hide()
    end
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -(rightInset + 2), 0)
    local textHeight = type(row.text.GetStringHeight) == "function" and row.text:GetStringHeight() or nil
    local height = math.max(item.height, Finite(textHeight) and textHeight + 10 or 0)
    row:SetHeight(height)
    if item.kind == "section" then
        row.text:SetTextColor(color[1], color[2], color[3])
    elseif item.kind == "line" then
        row.text:SetTextColor(unpack(item.done and self.completeRGB or self.mutedRGB))
    else
        row.text:SetTextColor(unpack(self.textRGB))
    end
    row.questID = item.questID
    row.achievementID, row.scenarioID = item.achievementID, item.scenarioID
    row.menuTitle, row.tracked = item.menuTitle, item.tracked
    row:EnableMouse(item.kind == "section" or item.questID ~= nil or item.achievementID ~= nil
        or (item.group == "scenario" and item.kind ~= "section"))
    if item.percent then
        row.progress:SetStatusBarColor(color[1], color[2], color[3], .95)
        row.progress:SetValue(item.percent)
        row.progress:Show()
    else
        row.progress:Hide()
    end
    row:Show()
    row.layoutY, row.layoutWidth, row.layoutHeight = y, width, height
    return height
end

local function ReleaseUnusedRows(self, used)
    for key, row in pairs(self.rows) do
        if not used[key] then
            row:Hide()
            row.timerEnd = nil
            if row.itemButton then row.itemButton:Hide() end
            if row.timer then row.timer:Hide() end
            row.collapse:Hide()
            self.rows[key] = nil
            self.freeRows[#self.freeRows + 1] = row
        end
    end
end

local function Scratch(self, key)
    local scratch = self[key]
    if not scratch then
        scratch = {}
        self[key] = scratch
    end
    for field in pairs(scratch) do scratch[field] = nil end
    return scratch
end

Render = function(self)
    if not self.active then return end
    local c = self.config
    if self.mplusActive and self.mplus then
        RenderMythicPlus(self, c)
        return
    end
    if self.mplus then self.mplus.frame:Hide() end
    local grouped = GroupEntries(self)
    local flat, flatCount, totalEntries = self.flatWork or {}, 0, 0
    for i = 1, #ORDER do
        local group = ORDER[i]
        flatCount = AddFlat(flat, flatCount, group, grouped[group], c, self.collapsedGroups, self.collapsedEntries)
        totalEntries = totalEntries + #grouped[group]
    end
    if flatCount == 0 and S.editMode then
        flatCount = 1
        local preview = FlatSlot(flat, 1)
        preview.key, preview.kind, preview.group = "preview", "line", "quests"
        preview.text, preview.height = "Tracked objectives appear here", 24
    end
    for i = #flat, flatCount + 1, -1 do flat[i] = nil end
    -- Compare with the previous layout first; an unchanged tracker stops here.
    local previous = self.previousFlat
    local themeChanged = self.retheme or not self.font
    local geometryChanged = self.lastWidth ~= c.width or self.lastHeight ~= c.height
        or self.lastScale ~= c.scale or self.lastX ~= c.x or self.lastY ~= c.y
        or self.lastEditMode ~= S.editMode
    local changed = themeChanged or geometryChanged or not previous or #previous ~= flatCount
    if not changed then
        for i = 1, flatCount do
            if not SameItem(flat[i], previous[i]) then
                changed = true
                break
            end
        end
    end
    if not changed then
        self.flatWork = flat
        return
    end
    self.previousFlat, self.flatWork = flat, previous or {}
    self.retheme = false
    if themeChanged then Theme(self) end
    self.title:SetText("OBJECTIVES")
    PlaceHost(self, c, themeChanged)
    local used = Scratch(self, "usedRows")
    for i = 1, flatCount do used[flat[i].key] = true end
    local previousByKey = Scratch(self, "previousByKey")
    if previous then
        for i = 1, #previous do previousByKey[previous[i].key] = previous[i] end
    end
    self.timedRows = Scratch(self, "timedRows")
    ReleaseUnusedRows(self, used)
    local y, width = 0, c.width - 14
    for i = 1, flatCount do
        local item = flat[i]
        local row = self.rows[item.key]
        if row and not themeChanged and row.layoutY == y and row.layoutWidth == width
            and SameItem(item, previousByKey[item.key]) then
            if row.timerEnd then self.timedRows[row] = true end
            y = y + row.layoutHeight
        else
            row = row or NewRow(self, item.key, item.kind)
            y = y + PaintRow(self, row, item, c, width, y)
        end
    end
    self.content:SetHeight(math.max(1, y))
    self.host:SetHeight(math.min(c.height, math.max(S.editMode and 160 or self.headerHeight + 5,
        y + self.headerHeight + 5)))
    self.count:SetText(tostring(totalEntries))
    self.host:SetShown(totalEntries > 0 or S.editMode)
    UpdateTimers(self)
end

------------------------------------------------------------------ refresh flow
local COLLECTORS = {
    quests = function(list, c) CollectQuests(list, c) end,
    world = function(list, c) if c.showWorldQuests then CollectWorld(list, c) end end,
    bonus = function(list, c) if c.showBonus then CollectBonus(list, c) end end,
    achievements = function(list, c) if c.showAchievements then CollectAchievements(list) end end,
    scenario = function(list, c) if c.showScenario then CollectScenario(list, c) end end,
}

local function Flush(self)
    self.scheduled = false
    if not self.active or self.pausedForRaidCombat or self.mplusActive then return end
    tasksRead, tasksTable = false, nil
    for i = 1, #SOURCES do
        local key = SOURCES[i]
        if self.dirty[key] then
            COLLECTORS[key](ResetSource(self, key), self.config)
            self.dirty[key] = nil
        end
    end
    tasksTable = nil
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
    if self.pausedForRaidCombat then return end
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
local function Event(self, event)
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
        if mapID then StartMythicPlus(self, mapID) end
        if self.mplusActive then MythicPlus.Tick(self) end
        return
    end
    local newArea = event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
    if newArea then
        self:SuppressNative()
        local mapID = MythicPlus and MythicPlus.Detect(self)
        if mapID then
            StartMythicPlus(self, mapID)
        elseif StopMythicPlus(self) then
            Flush(self)
            return
        end
    end
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
    local native = _G.ObjectiveTrackerFrame
    if not native or NS.Safety.IsForbidden(native) then return end
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
    if not self.config.pauseInRaidCombat or not NS.IsCombatLocked()
        or type(_G.IsInInstance) ~= "function" then return false end
    local inside, kind = _G.IsInInstance()
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
        self.host:Hide()
    else
        self.retheme = true
        self.contentSignature = ContentSignature(self.config)
        local mapID = MythicPlus and MythicPlus.Detect(self)
        if mapID then StartMythicPlus(self, mapID) else Flush(self) end
    end
    return true
end

local function RaidCombatEvent(self, event)
    UpdateRaidCombatPause(self)
    if event == "PLAYER_REGEN_ENABLED" then self:SuppressNative() end
end

local function NativeAddonLoaded(module, _, name)
    if name == "Blizzard_ObjectiveTracker" then module:SuppressNative() end
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
    if mapID then StartMythicPlus(self, mapID) else Flush(self) end
    self:RegisterMovers()
end

function M:Refresh()
    self.retheme = true
    if UpdateRaidCombatPause(self) then return end
    local c = self.config
    local mapID = MythicPlus and MythicPlus.Detect(self)
    if mapID then StartMythicPlus(self, mapID) end
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
    if self.contentSignature ~= signature or stoppedMythicPlus then
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
