local _, P = ...
local NS, S = P.NS, P.Suite
local ID = "objectives"
local M = { sources = {}, rows = {}, freeRows = {}, dirty = {}, generation = 0, timerToken = 0 }
local FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local ORDER = { "scenario", "focused", "campaign", "important", "complete", "quests", "world", "bonus", "achievements" }
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

local function Public(value) return S.Public(value) end
local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
local function Text(value)
    return Public(value) and type(value) == "string" and value ~= "" and value or nil
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    return ok and Public(value) and value or nil
end
local function QuestItem(questID)
    local index = Call(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, questID)
    if not Number(index) or index < 1 or type(_G.GetQuestLogSpecialItemInfo) ~= "function" then return end
    local complete = Call(C_QuestLog and C_QuestLog.IsComplete, questID) == true
    if QuestUtil and type(QuestUtil.QuestShowsItemByIndex) == "function"
        and Call(QuestUtil.QuestShowsItemByIndex, index, complete) ~= true then return end
    local ok, _, icon, _, showWhenComplete = pcall(_G.GetQuestLogSpecialItemInfo, index)
    if not ok or not Public(icon)
        or (type(icon) ~= "number" and type(icon) ~= "string")
        or (complete and (not Public(showWhenComplete) or showWhenComplete ~= true)) then return end
    return icon
end
local function QuestTimeLeft(questID, task)
    if task then
        local left = Call(C_TaskQuest and C_TaskQuest.GetQuestTimeLeftSeconds, questID)
        return Number(left) and left > 0 and left or nil
    end
    local fn = C_QuestLog and C_QuestLog.GetTimeAllowed
    if type(fn) ~= "function" then return end
    local ok, total, elapsed = pcall(fn, questID)
    if ok and Number(total) and Number(elapsed) and total > elapsed then
        return total - elapsed
    end
end
local function ObjectiveLines(questID)
    local result = {}
    local objectives = Call(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    if type(objectives) ~= "table" then return result end
    for i = 1, #objectives do
        local objective = objectives[i]
        if Public(objective) and type(objective) == "table" then
            local line = Text(objective.text)
            if line then
                local finished = Public(objective.finished) and objective.finished == true
                local percent
                if Text(objective.type) == "progressbar" then
                    local value = Call(_G.GetQuestProgressBarPercent, questID)
                    if Number(value) then percent = math.max(0, math.min(100, value)) end
                end
                result[#result + 1] = { text = line, done = finished, percent = percent }
            end
        end
    end
    return result
end
local function QuestTitle(questID)
    local title = Call(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID)
    if Text(title) then return title end
    local index = Call(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, questID)
    local info = Number(index) and Call(C_QuestLog and C_QuestLog.GetInfo, index)
    return type(info) == "table" and Text(info.title) or nil
end
local function Category(questID, focused)
    if questID == focused then return "focused" end
    if Call(C_QuestLog and C_QuestLog.IsComplete, questID) == true then return "complete" end
    local kind = Call(C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification, questID)
    local kinds = Enum and Enum.QuestClassification
    if Number(kind) and type(kinds) == "table" then
        if kind == kinds.Campaign then return "campaign" end
        if kind == kinds.Important or kind == kinds.Legendary then return "important" end
    end
    return "quests"
end
local function CollectQuests(c)
    local result, seen = {}, {}
    local focused = Call(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID)
    local count = Call(C_QuestLog and C_QuestLog.GetNumQuestWatches)
    if not Number(count) then return result end
    for i = 1, math.min(count, 40) do
        local id = Call(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
        if Number(id) and id > 0 and not seen[id] then
            seen[id] = true
            local title = QuestTitle(id)
            if title then result[#result + 1] = {
                id = id, title = title, group = Category(id, focused), lines = ObjectiveLines(id),
                tracked = true, itemIcon = c.showQuestItems ~= false and QuestItem(id) or nil,
                timeLeft = c.showTimers ~= false and QuestTimeLeft(id, false) or nil,
            } end
        end
    end
    return result
end
local function CollectWorld(c)
    local result, seen = {}, {}
    local count = Call(C_QuestLog and C_QuestLog.GetNumWorldQuestWatches)
    if not Number(count) then return result end
    for i = 1, math.min(count, 25) do
        local id = Call(C_QuestLog.GetQuestIDForWorldQuestWatchIndex, i)
        if Number(id) and id > 0 and not seen[id] then
            seen[id] = true
            local title = QuestTitle(id)
            if not title then
                local task = Call(C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID, id)
                title = Text(task) or type(task) == "table" and Text(task.title)
            end
            if title then result[#result + 1] = {
                id = id, title = title, group = "world", lines = ObjectiveLines(id),
                tracked = true, itemIcon = c.showQuestItems ~= false and QuestItem(id) or nil,
                timeLeft = c.showTimers ~= false and QuestTimeLeft(id, true) or nil,
            } end
        end
    end
    local tasks = Call(_G.GetTasksTable)
    if type(tasks) == "table" then
        for i = 1, math.min(#tasks, 30) do
            local id = tasks[i]
            if Number(id) and id > 0 and not seen[id]
                and Call(_G.QuestUtils_IsQuestWorldQuest, id) == true then
                seen[id] = true
                local title = QuestTitle(id) or Call(C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID, id)
                if Text(title) then result[#result + 1] = {
                    id = id, title = title, group = "world", lines = ObjectiveLines(id),
                    tracked = false, itemIcon = c.showQuestItems ~= false and QuestItem(id) or nil,
                    timeLeft = c.showTimers ~= false and QuestTimeLeft(id, true) or nil,
                } end
            end
        end
    end
    return result
end
local function CollectBonus(c)
    local result = {}
    local tasks = Call(_G.GetTasksTable)
    if type(tasks) ~= "table" then return result end
    for i = 1, math.min(#tasks, 30) do
        local id = tasks[i]
        if Number(id) and id > 0 and Call(_G.QuestUtils_IsQuestWorldQuest, id) ~= true
            and type(GetTaskInfo) == "function" then
            local ok, inArea, _, count, taskName = pcall(GetTaskInfo, id)
            if ok and Public(inArea) and inArea == true and Number(count) and Text(taskName) then
                local lines = {}
                for j = 1, count do
                    local good, line, kind, done = pcall(GetQuestObjectiveInfo, id, j, false)
                    if good and Text(line) then
                        local percent = Text(kind) == "progressbar"
                            and Call(_G.GetQuestProgressBarPercent, id) or nil
                        lines[#lines + 1] = { text = line, done = Public(done) and done == true,
                            percent = Number(percent) and math.max(0, math.min(100, percent)) or nil }
                    end
                end
                result[#result + 1] = { id = id, title = taskName, group = "bonus", lines = lines,
                    timeLeft = c.showTimers ~= false and QuestTimeLeft(id, true) or nil }
            end
        end
    end
    return result
end
local function CollectAchievements()
    local result = {}
    local kind = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
    local ids = kind and Call(C_ContentTracking and C_ContentTracking.GetTrackedIDs, kind)
    if type(ids) ~= "table" then return result end
    for i = 1, math.min(#ids, 15) do
        local id = ids[i]
        if Number(id) and type(GetAchievementInfo) == "function" then
            local ok, _, name, _, complete = pcall(GetAchievementInfo, id)
            if ok and Text(name) and Public(complete) and not complete then
                local entry = { id = id, title = name, group = "achievements", lines = {}, tracked = true }
                local count = Call(_G.GetAchievementNumCriteria, id)
                if Number(count) then
                    for j = 1, count do
                        local good, line, _, done = pcall(GetAchievementCriteriaInfo, id, j)
                        if good and Text(line) and Public(done) and not done then
                            entry.lines[#entry.lines + 1] = { text = line }
                        end
                    end
                end
                result[#result + 1] = entry
            end
        end
    end
    return result
end
local function CollectScenario(c)
    local result = {}
    if not (C_Scenario and type(C_Scenario.GetInfo) == "function") then return result end
    local ok, name, stage, total, _, _, _, _, _, _, _, _, _, scenarioID = pcall(C_Scenario.GetInfo)
    if not ok or not Text(name) or not Number(stage) or not Number(total)
        or total < 1 or stage > total then return result end
    local entry = { id = 0, title = name, group = "scenario", lines = {},
        scenarioID = Number(scenarioID) and scenarioID or nil }
    local stepOK, stepName, description, criteriaCount = pcall(C_Scenario.GetStepInfo)
    if stepOK then
        if Text(stepName) then entry.lines[#entry.lines + 1] = { text = stepName } end
        if Text(description) and description ~= stepName then
            entry.lines[#entry.lines + 1] = { text = description }
        end
        if Number(criteriaCount) and C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
            for i = 1, criteriaCount do
                local info = Call(C_ScenarioInfo.GetCriteriaInfo, i)
                if type(info) == "table" then
                    local line = Text(info.description)
                    if line then entry.lines[#entry.lines + 1] = {
                        text = line, done = Public(info.completed) and info.completed == true,
                    } end
                    if c.showTimers ~= false and Number(info.duration) and Number(info.elapsed)
                        and info.duration > info.elapsed then
                        local left = info.duration - info.elapsed
                        if not entry.timeLeft or left < entry.timeLeft then entry.timeLeft = left end
                    end
                end
            end
        end
    end
    result[1] = entry
    return result
end

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
        if type(_G.OpenQuestLog) == "function" then pcall(_G.OpenQuestLog) end
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

local function OpenQuestDetails(questID)
    if not Number(questID) or questID <= 0 then return end
    if type(_G.QuestMapFrame_OpenToQuestDetails) == "function"
        and pcall(_G.QuestMapFrame_OpenToQuestDetails, questID) then return end
    if type(_G.OpenQuestLog) == "function" then pcall(_G.OpenQuestLog) end
    if type(_G.QuestMapFrame_ShowQuestDetails) == "function" then
        pcall(_G.QuestMapFrame_ShowQuestDetails, questID)
    end
end

local function OpenTaskMap(questID)
    local mapID = Call(C_TaskQuest and C_TaskQuest.GetQuestZoneID, questID)
    if Number(mapID) and mapID > 0 and type(_G.OpenQuestLog) == "function" then
        pcall(_G.OpenQuestLog, mapID)
        local registry = _G.EventRegistry
        if registry and type(registry.TriggerEvent) == "function" then
            pcall(registry.TriggerEvent, registry, "MapCanvas.PingQuestID", questID)
        end
    else
        OpenQuestDetails(questID)
    end
end

local function ShowContextMenu(button)
    local menu = _G.MenuUtil
    if not (menu and type(menu.CreateContextMenu) == "function") then return end
    local questID, achievementID, scenarioID = button.questID, button.achievementID, button.scenarioID
    local group, title, tracked = button.group, button.menuTitle or "Objective", button.tracked
    if not (Number(questID) or Number(achievementID) or group == "scenario") then return end
    menu.CreateContextMenu(button, function(_, root)
        root:CreateTitle(title or "Objective")
        if Number(achievementID) then
            if type(_G.ShowAchievementFrameForAchievement) == "function" then
                root:CreateButton(_G.OBJECTIVES_VIEW_ACHIEVEMENT or "View achievement", function()
                    pcall(_G.ShowAchievementFrameForAchievement, achievementID)
                end)
            end
            local kind = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
            local stop = Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual
            if kind and stop and C_ContentTracking and type(C_ContentTracking.StopTracking) == "function" then
                root:CreateButton(_G.OBJECTIVES_STOP_TRACKING or "Stop tracking", function()
                    pcall(C_ContentTracking.StopTracking, kind, achievementID, stop)
                end)
            end
        elseif group == "scenario" then
            if type(_G.ToggleEncounterJournal) == "function" then
                root:CreateButton(_G.ENCOUNTER_JOURNAL or "Adventure Guide", function()
                    pcall(_G.ToggleEncounterJournal)
                end)
            end
            if Number(scenarioID) and Call(C_LFGList and C_LFGList.CanCreateScenarioGroup, scenarioID) == true
                and type(_G.LFGListUtil_FindScenarioGroup) == "function" then
                root:CreateButton(_G.FIND_A_GROUP or "Find group", function()
                    pcall(_G.LFGListUtil_FindScenarioGroup, scenarioID, true)
                end)
            end
        else
            local task = group == "world" or group == "bonus"
            root:CreateButton(task and (_G.OBJECTIVES_SHOW_QUEST_MAP or "Show on map")
                or (_G.OBJECTIVES_VIEW_IN_QUESTLOG or "View in Quest Log"), function()
                if task then OpenTaskMap(questID) else OpenQuestDetails(questID) end
            end)
            local superTrack = C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
            local current = Call(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID)
            if type(superTrack) == "function" and Number(current) then
                local selected = current == questID
                root:CreateButton(selected and (_G.STOP_SUPER_TRACK_QUEST or "Stop super tracking")
                    or (_G.SUPER_TRACK_QUEST or "Super track quest"), function()
                    pcall(superTrack, selected and 0 or questID)
                end)
            end
            if tracked then
                if group == "world" and QuestUtil and type(QuestUtil.UntrackWorldQuest) == "function" then
                    root:CreateButton(_G.OBJECTIVES_STOP_TRACKING or "Stop tracking", function()
                        pcall(QuestUtil.UntrackWorldQuest, questID)
                    end)
                elseif group ~= "world" and group ~= "bonus"
                    and Call(QuestUtil and QuestUtil.CanRemoveQuestWatch) == true
                    and C_QuestLog and type(C_QuestLog.RemoveQuestWatch) == "function" then
                    root:CreateButton(_G.OBJECTIVES_STOP_TRACKING or "Stop tracking", function()
                        pcall(C_QuestLog.RemoveQuestWatch, questID)
                    end)
                end
            end
            if not task and Call(C_QuestLog and C_QuestLog.IsPushableQuest, questID) == true
                and Call(_G.IsInGroup) == true and QuestUtil
                and type(QuestUtil.ShareQuest) == "function" then
                root:CreateButton(_G.SHARE_QUEST or "Share quest", function()
                    pcall(QuestUtil.ShareQuest, questID)
                end)
            end
            if not task and Call(C_QuestLog and C_QuestLog.CanAbandonQuest, questID) == true
                and type(_G.QuestMapQuestOptions_AbandonQuest) == "function" then
                root:CreateButton(_G.ABANDON_QUEST_ABBREV or "Abandon quest", function()
                    pcall(_G.QuestMapQuestOptions_AbandonQuest, questID)
                end)
            end
        end
    end)
end

local Render
local function NewRow(self, key, kind)
    local pool = self.freeRows
    local match
    for i = #pool, 1, -1 do
        if pool[i].kind == kind then match = i; break end
    end
    local row = match and table.remove(pool, match) or table.remove(pool)
    if row then self.rows[key] = row; return row end
    row = S.CreateFrame("Button", nil, self.content)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(button, mouseButton)
        if mouseButton == "RightButton" then ShowContextMenu(button); return end
        if button.kind == "section" then
            self.collapsedGroups[button.group] = not self.collapsedGroups[button.group] or nil
            Render(self)
            return
        end
        local questID = button.questID
        if Number(questID) then OpenQuestDetails(questID)
        elseif Number(button.achievementID) and type(_G.ShowAchievementFrameForAchievement) == "function" then
            pcall(_G.ShowAchievementFrameForAchievement, button.achievementID)
        elseif button.group == "scenario" and type(_G.ToggleEncounterJournal) == "function" then
            pcall(_G.ToggleEncounterJournal)
        end
    end)
    row:SetScript("OnEnter", function(button)
        local tooltip = _G.GameTooltip
        if not tooltip or not button.menuTitle then return end
        tooltip:SetOwner(button, "ANCHOR_LEFT")
        local shown = false
        if Number(button.questID) and type(tooltip.SetHyperlink) == "function" then
            shown = pcall(tooltip.SetHyperlink, tooltip, "quest:" .. button.questID)
        elseif Number(button.achievementID) and type(tooltip.SetAchievementByID) == "function" then
            shown = pcall(tooltip.SetAchievementByID, tooltip, button.achievementID)
        end
        if not shown then tooltip:SetText(button.menuTitle) end
        tooltip:Show()
    end)
    row:SetScript("OnLeave", function(button)
        local tooltip = _G.GameTooltip
        if tooltip and tooltip:GetOwner() == button then tooltip:Hide() end
    end)
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
    collapse:RegisterForClicks("LeftButtonUp")
    collapse:SetScript("OnClick", function(button)
        local owner = button.ownerRow
        if owner.kind == "section" then
            self.collapsedGroups[owner.group] = not self.collapsedGroups[owner.group] or nil
        elseif owner.collapseKey then
            local base = owner.collapseKey
            self.collapsedEntries[base] = not self.collapsedEntries[base] or nil
        else return end
        Render(self)
    end)
    local glyph = S.CreateFontString(collapse, nil, "OVERLAY")
    glyph:SetPoint("CENTER", collapse, "CENTER", 0, 0)
    collapse.glyph, collapse.ownerRow = glyph, row
    collapse:Hide()
    row.collapse = collapse
    self.rows[key] = row
    return row
end

local function EnsureItemButton(row)
    if row.itemButton then return row.itemButton end
    local button = S.CreateFrame("Button", nil, row)
    button:SetSize(22, 22)
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", function(target, mouseButton)
        if mouseButton == "RightButton" then ShowContextMenu(target.ownerRow); return end
        local id = target.ownerRow.questID
        local index = Number(id) and Call(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, id)
        if Number(index) and type(_G.UseQuestLogSpecialItem) == "function" then
            pcall(_G.UseQuestLogSpecialItem, index)
        end
    end)
    button:SetScript("OnEnter", function(target)
        local tooltip = _G.GameTooltip
        local id = target.ownerRow.questID
        local index = Number(id) and Call(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, id)
        if tooltip and Number(index) and type(tooltip.SetQuestLogSpecialItem) == "function" then
            tooltip:SetOwner(target, "ANCHOR_RIGHT")
            tooltip:SetQuestLogSpecialItem(index)
            tooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(target)
        local tooltip = _G.GameTooltip
        if tooltip and tooltip:GetOwner() == target then tooltip:Hide() end
    end)
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

local function TimerText(seconds)
    seconds = math.max(0, math.ceil(seconds))
    if seconds >= 3600 then return string.format("%d:%02d:%02d", math.floor(seconds / 3600),
        math.floor(seconds / 60) % 60, seconds % 60) end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function UpdateTimers(self)
    if not self.active then return end
    local now, ticking = GetTime(), false
    for row in pairs(self.timedRows or {}) do
        if row.timer and Number(row.timerEnd) then
            local left = row.timerEnd - now
            if left > 0 then
                local value = TimerText(left)
                if row.timerText ~= value then row.timer:SetText(value); row.timerText = value end
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
        self.timerToken = self.timerToken + 1
        local token = self.timerToken
        C_Timer.After(1, function()
            if self.timerToken ~= token then return end
            self.timerPending = false
            UpdateTimers(self)
        end)
    end
end

local function Theme(self)
    local c = self.config
    local skin = self.context and self.context:Skin()
    local font = S.ResolveFont(c.font) or (skin and skin:GetFont()) or FONT
    self.font = font or FONT
    local custom = c.colorStyle == 2
    self.textRGB = custom and { S.RGB(c.textColor) }
        or skin and { skin:GetColor("text") } or { .95, .96, .98 }
    self.mutedRGB = custom and { S.RGB(c.mutedColor) }
        or skin and { skin:GetColor("muted") } or { .78, .81, .85 }
    self.completeRGB = custom and { S.RGB(c.completeColor) } or { .49, .75, .53 }
    self.groupRGB = {}
    for group, key in pairs(GROUP_COLOR_KEYS) do
        self.groupRGB[group] = custom and { S.RGB(c[key]) }
            or { GROUP[group][2], GROUP[group][3], GROUP[group][4] }
    end
    local look = skin and skin:GetLook() or "midnightDark"
    local dark = look == "midnightDark"
    local opacity = (c.backgroundOpacity or 0) / 100
    if custom then
        local r, g, b = S.RGB(c.backgroundColor)
        self.background:SetColorTexture(r, g, b, opacity)
    elseif skin then
        local r, g, b = skin:GetColor("surface")
        self.background:SetColorTexture(r, g, b, opacity)
    else
        self.background:SetColorTexture(dark and .035 or .025, dark and .039 or .055,
            dark and .047 or .085, opacity)
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
    if custom then self.title:SetTextColor(S.RGB(c.titleColor))
    elseif skin then self.title:SetTextColor(skin:GetColor("title"))
    else self.title:SetTextColor(.96, .97, .98) end
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

local function FlatSlot(flat, index)
    local item = flat[index]
    if not item then item = {}; flat[index] = item end
    -- Both flat buffers survive refreshes. Clear fields that belong to another row kind.
    item.key, item.kind, item.group, item.text, item.height = nil, nil, nil, nil, nil
    item.collapsed, item.menuTitle, item.tracked, item.itemIcon = nil, nil, nil, nil
    item.timeLeft, item.hasLines, item.collapseKey = nil, nil, nil
    item.questID, item.achievementID, item.scenarioID = nil, nil, nil
    item.done, item.percent = nil, nil
    return item
end

local function AddFlat(flat, index, group, items, c, collapsedGroups, collapsedEntries)
    if #items == 0 then return index end
    index = index + 1
    local section = FlatSlot(flat, index)
    section.key, section.kind, section.group = "section:" .. group, "section", group
    section.text = GROUP[group][1]
    section.height = math.max(23, (c.sectionSize or 14) + 12)
    section.collapsed = collapsedGroups[group] == true
    if collapsedGroups[group] then return index end
    for i = 1, #items do
        local entry = items[i]
        local base = group .. ":" .. tostring(entry.id)
        local questID = group ~= "achievements" and group ~= "scenario" and entry.id > 0 and entry.id or nil
        local achievementID = group == "achievements" and entry.id or nil
        local scenarioID = group == "scenario" and entry.scenarioID or nil
        index = index + 1
        local item = FlatSlot(flat, index)
        item.key, item.kind, item.group = "entry:" .. base, "entry", group
        item.text, item.height = entry.title, math.max(32, (c.entrySize or 15) + 19)
        item.menuTitle, item.tracked = entry.title, entry.tracked
        item.itemIcon, item.timeLeft = entry.itemIcon, entry.timeLeft
        item.hasLines, item.collapsed, item.collapseKey = #entry.lines > 0, collapsedEntries[base] == true, base
        item.questID, item.achievementID, item.scenarioID = questID, achievementID, scenarioID
        if not collapsedEntries[base] then for j = 1, #entry.lines do
            local line = entry.lines[j]
            index = index + 1
            item = FlatSlot(flat, index)
            item.key, item.kind, item.group = "line:" .. base .. ":" .. j, "line", group
            item.text, item.done, item.percent = line.text, line.done, line.percent
            item.menuTitle, item.tracked = entry.title, entry.tracked
            item.questID, item.achievementID, item.scenarioID = questID, achievementID, scenarioID
            item.height = math.max(line.percent and 28 or 24,
                (c.objectiveSize or 13) + (line.percent and 17 or 13))
        end end
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

Render = function(self)
    if not self.active then return end
    local c = self.config
    local grouped = self.grouped
    if not grouped then grouped = {}; self.grouped = grouped end
    for i = 1, #ORDER do
        local group = ORDER[i]
        local list = grouped[group]
        if not list then list = {}; grouped[group] = list end
        for j = #list, 1, -1 do list[j] = nil end
    end
    for _, source in pairs(self.sources) do
        for i = 1, #source do
            local entry = source[i]
            if grouped[entry.group] then
                local list = grouped[entry.group]
                list[#list + 1] = entry
            end
        end
    end
    local flat, flatCount, totalEntries = self.flatWork or {}, 0, 0
    local liveEntries = self.liveEntries
    if not liveEntries then liveEntries = {}; self.liveEntries = liveEntries end
    for key in pairs(liveEntries) do liveEntries[key] = nil end
    for i = 1, #ORDER do
        local group = ORDER[i]
        for j = 1, #grouped[group] do
            liveEntries[group .. ":" .. tostring(grouped[group][j].id)] = true
        end
    end
    for key in pairs(self.collapsedEntries) do
        if not liveEntries[key] then self.collapsedEntries[key] = nil end
    end
    for i = 1, #ORDER do
        local group = ORDER[i]
        flatCount = AddFlat(flat, flatCount, group, grouped[group], c,
            self.collapsedGroups, self.collapsedEntries)
        totalEntries = totalEntries + #grouped[group]
    end
    if flatCount == 0 and S.editMode then
        flatCount = 1
        local preview = FlatSlot(flat, 1)
        preview.key, preview.kind, preview.group = "preview", "line", "quests"
        preview.text, preview.height = "Tracked objectives appear here", 24
    end
    for i = #flat, flatCount + 1, -1 do flat[i] = nil end
    local previous = self.previousFlat
    local themeChanged = self.retheme or not self.font
    local geometryChanged = self.lastWidth ~= c.width or self.lastHeight ~= c.height
        or self.lastScale ~= c.scale or self.lastX ~= c.x or self.lastY ~= c.y
        or self.lastEditMode ~= S.editMode
    local changed = themeChanged or geometryChanged or not previous or #previous ~= flatCount
    if not changed then
        for i = 1, flatCount do
            if not SameItem(flat[i], previous[i]) then changed = true; break end
        end
    end
    if not changed then self.flatWork = flat; return end
    self.previousFlat, self.flatWork = flat, previous or {}
    self.lastWidth, self.lastHeight, self.lastScale = c.width, c.height, c.scale
    self.lastX, self.lastY, self.lastEditMode = c.x, c.y, S.editMode
    self.retheme = false
    if themeChanged then Theme(self) end
    if themeChanged or geometryChanged then
        self.headerClick:SetHeight(self.headerHeight - 5)
        self.host:SetScale(c.scale / 100)
        self.host:SetWidth(c.width)
        self.host:ClearAllPoints()
        self.host:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", c.x, c.y)
        self.content:SetWidth(c.width - 14)
    end
    local y, used = 0, self.usedRows
    if not used then used = {}; self.usedRows = used end
    for key in pairs(used) do used[key] = nil end
    for i = 1, flatCount do used[flat[i].key] = true end
    local previousByKey = self.previousByKey
    if not previousByKey then previousByKey = {}; self.previousByKey = previousByKey end
    for key in pairs(previousByKey) do previousByKey[key] = nil end
    if previous then
        for i = 1, #previous do previousByKey[previous[i].key] = previous[i] end
    end
    local timedRows = self.timedRows
    if not timedRows then timedRows = {}; self.timedRows = timedRows end
    for row in pairs(timedRows) do timedRows[row] = nil end
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
    for i = 1, flatCount do
        local item = flat[i]
        local row = self.rows[item.key]
        if row and not themeChanged and row.layoutY == y and row.layoutWidth == c.width - 14
            and SameItem(item, previousByKey[item.key]) then
            if row.timerEnd then timedRows[row] = true end
            y = y + row.layoutHeight
        else
            row = row or NewRow(self, item.key, item.kind)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
            row:SetWidth(c.width - 14)
            local color = self.groupRGB[item.group]
            row.stripe:SetColorTexture(color[1], color[2], color[3], item.kind == "line" and .35 or .95)
            local size = item.kind == "section" and (c.sectionSize or 14)
                or item.kind == "entry" and (c.entrySize or 15) or (c.objectiveSize or 13)
            if row.cachedSize ~= size or row.cachedFont ~= self.font then
                S.SetStyledFont(row.text, self.font, size, "OUTLINE", 1, true, 70, 1)
                row.cachedSize, row.cachedFont = size, self.font
            end
            if row.cachedText ~= item.text then row.text:SetText(item.text); row.cachedText = item.text end
            row.kind, row.group, row.collapseKey = item.kind, item.group, item.collapseKey
            local rightInset = 4
            if item.itemIcon and item.kind == "entry" then
                local button = EnsureItemButton(row)
                button.icon:SetTexture(item.itemIcon)
                button:ClearAllPoints()
                button:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0)
                button:Show()
                rightInset = rightInset + 27
            elseif row.itemButton then row.itemButton:Hide() end
            if Number(item.timeLeft) and item.timeLeft > 0 and item.kind == "entry" then
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
                timedRows[row] = true
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
            else row.collapse:Hide() end
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row, "LEFT", 12, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -(rightInset + 2), 0)
            local textHeight = type(row.text.GetStringHeight) == "function" and row.text:GetStringHeight() or nil
            local height = math.max(item.height, Number(textHeight) and textHeight + 10 or 0)
            row:SetHeight(height)
            if item.kind == "section" then
                row.text:SetTextColor(color[1], color[2], color[3])
            elseif item.kind == "line" then
                local muted = self.mutedRGB
                local lineColor = item.done and self.completeRGB or muted
                row.text:SetTextColor(unpack(lineColor))
            else row.text:SetTextColor(unpack(self.textRGB)) end
            row.questID = item.questID
            row.achievementID, row.scenarioID = item.achievementID, item.scenarioID
            row.menuTitle, row.tracked = item.menuTitle, item.tracked
            row:EnableMouse(item.kind == "section" or item.questID ~= nil or item.achievementID ~= nil
                or (item.group == "scenario" and item.kind ~= "section"))
            if item.percent then
                row.progress:SetStatusBarColor(color[1], color[2], color[3], .95)
                row.progress:SetValue(item.percent)
                row.progress:Show()
            else row.progress:Hide() end
            row:Show()
            row.layoutY, row.layoutWidth, row.layoutHeight = y, c.width - 14, height
            y = y + height
        end
    end
    self.content:SetHeight(math.max(1, y))
    self.host:SetHeight(math.min(c.height,
        math.max(S.editMode and 160 or self.headerHeight + 5, y + self.headerHeight + 5)))
    self.count:SetText(tostring(totalEntries))
    self.host:SetShown(totalEntries > 0 or S.editMode)
    UpdateTimers(self)
end

local function Flush(self)
    self.scheduled = false
    if not self.active then return end
    if self.dirty.quests then self.sources.quests = CollectQuests(self.config); self.dirty.quests = nil end
    if self.dirty.world then self.sources.world = self.config.showWorldQuests and CollectWorld(self.config) or {}; self.dirty.world = nil end
    if self.dirty.bonus then self.sources.bonus = self.config.showBonus and CollectBonus(self.config) or {}; self.dirty.bonus = nil end
    if self.dirty.achievements then
        self.sources.achievements = self.config.showAchievements and CollectAchievements() or {}
        self.dirty.achievements = nil
    end
    if self.dirty.scenario then self.sources.scenario = self.config.showScenario and CollectScenario(self.config) or {}; self.dirty.scenario = nil end
    Render(self)
end
local function Request(self, key)
    self.dirty[key] = true
    if self.scheduled then return end
    self.scheduled = true
    local generation = self.generation
    C_Timer.After(0, function() if self.generation == generation then Flush(self) end end)
end
local function Event(self, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        self:SuppressNative()
        Request(self, "quests"); Request(self, "world"); Request(self, "bonus"); Request(self, "scenario")
        Request(self, "achievements")
    elseif event == "SCENARIO_UPDATE" or event == "SCENARIO_CRITERIA_UPDATE"
        or event == "ACTIVE_DELVE_DATA_UPDATE" then Request(self, "scenario")
    elseif event == "TRACKED_ACHIEVEMENT_UPDATE" or event == "CRITERIA_UPDATE"
        or event == "ACHIEVEMENT_EARNED" or event == "CONTENT_TRACKING_UPDATE" then
        Request(self, "achievements")
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        Request(self, "world"); Request(self, "bonus")
    elseif event == "SUPER_TRACKING_CHANGED" or event == "QUEST_POI_UPDATE" then
        Request(self, "quests")
    elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" then
        Request(self, "quests"); Request(self, "world")
    elseif event == "SCENARIO_BONUS_VISIBILITY_UPDATE" then
        Request(self, "bonus"); Request(self, "scenario")
    else Request(self, "quests"); Request(self, "world"); Request(self, "bonus") end
end
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
function M:Enable()
    self.generation = self.generation + 1
    Create(self)
    self.active = true
    self.retheme = true
    local c = self.config
    c.collapsedGroups = type(c.collapsedGroups) == "table" and c.collapsedGroups or {}
    c.collapsedEntries = type(c.collapsedEntries) == "table" and c.collapsedEntries or {}
    self.collapsedGroups, self.collapsedEntries = c.collapsedGroups, c.collapsedEntries
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE",
        "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
        "SUPER_TRACKING_CHANGED", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
        "ZONE_CHANGED_NEW_AREA", "QUEST_POI_UPDATE", "SCENARIO_BONUS_VISIBILITY_UPDATE", "SCENARIO_UPDATE",
        "SCENARIO_CRITERIA_UPDATE", "ACTIVE_DELVE_DATA_UPDATE", "TRACKED_ACHIEVEMENT_UPDATE",
        "CRITERIA_UPDATE", "ACHIEVEMENT_EARNED", "CONTENT_TRACKING_UPDATE" }) do
        self.context:Event(event, Event, true)
    end
    self.context:Event("ADDON_LOADED", function(module, _, name)
        if name == "Blizzard_ObjectiveTracker" then module:SuppressNative() end
    end, true)
    self.context:Event("PLAYER_REGEN_ENABLED", M.SuppressNative, true)
    self.context:Event("GROUP_ROSTER_UPDATE", M.SuppressNative, true)
    self:SuppressNative()
    self.dirty = { quests = true, world = true, bonus = true, scenario = true, achievements = true }
    self.contentSignature = tostring(c.showWorldQuests) .. ":" .. tostring(c.showBonus) .. ":"
        .. tostring(c.showScenario) .. ":" .. tostring(c.showAchievements) .. ":"
        .. tostring(c.showQuestItems) .. ":" .. tostring(c.showTimers)
    Flush(self)
    self:RegisterMovers()
end
function M:Refresh()
    self.retheme = true
    local c = self.config
    c.collapsedGroups = type(c.collapsedGroups) == "table" and c.collapsedGroups or {}
    c.collapsedEntries = type(c.collapsedEntries) == "table" and c.collapsedEntries or {}
    self.collapsedGroups, self.collapsedEntries = c.collapsedGroups, c.collapsedEntries
    local signature = tostring(c.showWorldQuests) .. ":" .. tostring(c.showBonus) .. ":"
        .. tostring(c.showScenario) .. ":" .. tostring(c.showAchievements) .. ":"
        .. tostring(c.showQuestItems) .. ":" .. tostring(c.showTimers)
    if self.contentSignature ~= signature then
        self.contentSignature = signature
        self.dirty.quests, self.dirty.world, self.dirty.bonus = true, true, true
        self.dirty.scenario, self.dirty.achievements = true, true
        Flush(self)
    else
        Render(self)
    end
    self:SuppressNative()
end
function M:Disable()
    self.generation = self.generation + 1
    self.timerToken = self.timerToken + 1
    self.timerPending = false
    self.scheduled = false
    if self.host then self.host:Hide() end
    self.sources = {}
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
