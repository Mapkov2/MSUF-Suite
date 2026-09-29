local _, P = ...
local NS, S = P.NS, P.Suite
local O = P.Objectives
local M, SOURCES, Read = O.M, O.SOURCES, O.Read
local MythicPlus = S.MythicPlus
local Raid = S.Raid
local Finite = S.Finite

-- The objective tracker's frame: rows, clicks and context menus, countdowns,
-- theme and layout (see ObjectivesData.lua for how the files fit together).
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
local SECTION_KEYS = {}
for _, group in ipairs(ORDER) do SECTION_KEYS[group] = "section:" .. group end
local TEXT_RGB, MUTED_RGB, COMPLETE_RGB = { .95, .96, .98 }, { .78, .81, .85 }, { .49, .75, .53 }

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
    headerClick:SetScript("OnClick", function() OpenQuestLog() end)
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
-- The quest log (Blizzard_UIPanels_Game) and the group finder load with the
-- game UI on Retail and Forever. The achievement and Adventure Guide
-- functions come from bootstraps of load-on-demand addons whose TOCs load
-- by game type, so those two are checked.
local function OpenQuestDetails(questID)
    if not Finite(questID) or questID <= 0 then return end
    QuestMapFrame_OpenToQuestDetails(questID)
end

local function OpenTaskMap(questID)
    local mapID = Read(C_TaskQuest.GetQuestZoneID, questID)
    if Finite(mapID) and mapID > 0 then
        OpenQuestLog(mapID)
        EventRegistry:TriggerEvent("MapCanvas.PingQuestID", questID)
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
    return Read(IsModifiedClick, "QUESTWATCHTOGGLE") == true or Read(IsShiftKeyDown) == true
end

local function CanUntrack(button)
    if Finite(button.achievementID) then return true end
    if not Finite(button.questID) or not button.tracked then return false end
    if button.group == "world" then return true end
    return button.group ~= "bonus" and Read(QuestUtil.CanRemoveQuestWatch) == true
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

-- Menu labels are Blizzard's global strings; its own objective tracker uses
-- them on every supported client.
local function BuildAchievementMenu(root, button)
    local achievementID = button.achievementID
    if type(_G.ShowAchievementFrameForAchievement) == "function" then
        root:CreateButton(OBJECTIVES_VIEW_ACHIEVEMENT, function()
            OpenAchievement(achievementID)
        end)
    end
    if CanUntrack(button) then
        root:CreateButton(OBJECTIVES_STOP_TRACKING, function() Untrack(button) end)
    end
end

local function BuildScenarioMenu(root, scenarioID)
    if type(_G.ToggleEncounterJournal) == "function" then
        root:CreateButton(ENCOUNTER_JOURNAL, OpenJournal)
    end
    if Finite(scenarioID) and Read(C_LFGList.CanCreateScenarioGroup, scenarioID) == true then
        root:CreateButton(FIND_A_GROUP, function()
            LFGListUtil_FindScenarioGroup(scenarioID, true)
        end)
    end
end
local function OpenQuestGroup(questID, nativeSearch)
    if NS.IsCombatLocked() or NS.Client.isForever then return end
    if nativeSearch then
        LFGListUtil_FindQuestGroup(questID, true)
    else
        PVEFrame_ShowFrame("GroupFinderFrame", LFGListPVEStub)
    end
end
local function BuildQuestMenu(root, button)
    local questID, group = button.questID, button.group
    local task = group == "world" or group == "bonus"
    if button.findGroup then
        local nativeSearch = button.questGroupSearch
        root:CreateButton(button.questGroupSearch and FIND_A_GROUP or "Open group finder", function()
            OpenQuestGroup(questID, nativeSearch)
        end)
    end
    root:CreateButton(task and OBJECTIVES_SHOW_QUEST_MAP or OBJECTIVES_VIEW_IN_QUESTLOG, function()
        if task then OpenTaskMap(questID) else OpenQuestDetails(questID) end
    end)
    local current = Read(C_SuperTrack.GetSuperTrackedQuestID)
    local selected = Finite(current) and current == questID
    root:CreateButton(selected and STOP_SUPER_TRACK_QUEST or SUPER_TRACK_QUEST, function()
        C_SuperTrack.SetSuperTrackedQuestID(selected and 0 or questID)
    end)
    if CanUntrack(button) then
        root:CreateButton(OBJECTIVES_STOP_TRACKING, function() Untrack(button) end)
    end
    if not task and Read(C_QuestLog.IsPushableQuest, questID) == true
        and Read(IsInGroup) == true then
        root:CreateButton(SHARE_QUEST, function() QuestUtil.ShareQuest(questID) end)
    end
    if not task and Read(C_QuestLog.CanAbandonQuest, questID) == true then
        root:CreateButton(ABANDON_QUEST_ABBREV, function()
            QuestMapQuestOptions_AbandonQuest(questID)
        end)
    end
end

local function ShowContextMenu(button)
    local group, title = button.group, button.menuTitle or "Objective"
    if not (Finite(button.questID) or Finite(button.achievementID) or group == "scenario") then return end
    MenuUtil.CreateContextMenu(button, function(_, root)
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

-- GameTooltip and its SetHyperlink, SetAchievementByID and
-- SetQuestLogSpecialItem accessors exist on every supported client.
local function OnRowEnter(button)
    if not button.menuTitle then return end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    if Finite(button.questID) then
        GameTooltip:SetHyperlink("quest:" .. button.questID)
    elseif Finite(button.achievementID) then
        GameTooltip:SetAchievementByID(button.achievementID)
    else
        GameTooltip:SetText(button.menuTitle)
    end
    GameTooltip:Show()
end

local function OnOwnedLeave(button)
    if GameTooltip:GetOwner() == button then GameTooltip:Hide() end
end
local function OnFindGroupClick(button)
    local row = button.ownerRow
    if Finite(row.questID) then OpenQuestGroup(row.questID, row.questGroupSearch) end
end
local function OnFindGroupEnter(button)
    local row = button.ownerRow
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.questGroupSearch and TOOLTIP_TRACKER_FIND_GROUP_BUTTON or "Open group finder")
    GameTooltip:Show()
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
    local index = Finite(id) and Read(C_QuestLog.GetLogIndexForQuestID, id)
    if Finite(index) then
        -- TODO(in-game): confirm this is not blocked for addon code.
        UseQuestLogSpecialItem(index)
    end
end

local function OnItemEnter(target)
    local id = target.ownerRow.questID
    local index = Finite(id) and Read(C_QuestLog.GetLogIndexForQuestID, id)
    if Finite(index) then
        GameTooltip:SetOwner(target, "ANCHOR_RIGHT")
        GameTooltip:SetQuestLogSpecialItem(index)
        GameTooltip:Show()
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
local function EnsureFindGroupButton(row)
    if row.findGroupButton then return row.findGroupButton end
    local button = S.CreateFrame("Button", nil, row)
    button:SetSize(22, 22)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", OnFindGroupClick)
    button:SetScript("OnEnter", OnFindGroupEnter)
    button:SetScript("OnLeave", OnOwnedLeave)
    local icon = S.CreateTexture(button, nil, "ARTWORK")
    icon:SetAtlas("socialqueuing-icon-eye")
    icon:SetSize(15, 15)
    icon:SetPoint("CENTER")
    button.icon, button.ownerRow = icon, row
    row.findGroupButton = button
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
    self.font = S.ResolveFont(c.font) or S.GlobalFontPath()
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
    item.findGroup, item.questGroupSearch = nil, nil
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
        item.findGroup, item.questGroupSearch = entry.findGroup, entry.questGroupSearch
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
        and a.findGroup == b.findGroup and a.questGroupSearch == b.questGroupSearch
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

local function RenderRaid(self, c)
    local themeChanged = self.retheme or not self.font
    if themeChanged then
        Theme(self)
        Raid.Theme(self)
        self.retheme = false
    end
    PlaceHost(self, c, themeChanged)
    self.title:SetText("RAID")
    self.count:SetText(self.raid.difficultyName or "")
    self.content:SetHeight(self.raid.height)
    self.host:SetHeight(math.min(c.height, self.headerHeight + self.raid.height + 5))
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

-- The widgets right of a row's text, right to left: group finder, quest item,
-- timer and collapse button. Returns the inset the text keeps free.
local function PaintRowWidgets(self, row, item, color, size)
    local rightInset = 4
    if item.findGroup and item.kind == "entry" then
        local button = EnsureFindGroupButton(row)
        button:ClearAllPoints()
        button:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0)
        button:Show()
        rightInset = rightInset + 25
    elseif row.findGroupButton then
        row.findGroupButton:Hide()
    end
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
    return rightInset
end

-- Text color by row kind, click targets and the progress bar.
local function PaintRowState(self, row, item, color)
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
    row.findGroup, row.questGroupSearch = item.findGroup, item.questGroupSearch
    row:EnableMouse(item.kind == "section" or item.questID ~= nil or item.achievementID ~= nil
        or (item.group == "scenario" and item.kind ~= "section"))
    if item.percent then
        row.progress:SetStatusBarColor(color[1], color[2], color[3], .95)
        row.progress:SetValue(item.percent)
        row.progress:Show()
    else
        row.progress:Hide()
    end
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
    local rightInset = PaintRowWidgets(self, row, item, color, size)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -(rightInset + 2), 0)
    local textHeight = row.text:GetStringHeight()
    local height = math.max(item.height, Finite(textHeight) and textHeight + 10 or 0)
    row:SetHeight(height)
    PaintRowState(self, row, item, color)
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
            if row.findGroupButton then row.findGroupButton:Hide() end
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
    if self.raidActive and self.raid then
        RenderRaid(self, c)
        return
    end
    if self.raid then self.raid.frame:Hide() end
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

O.Create, O.Render = Create, Render
