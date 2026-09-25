local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever")
local scheduled, frames, movers = {}, {}, {}
local setPoints = 0
local function Widget(parent, fontString)
    local w = { parent = parent, shown = true, fontString = fontString }
    function w:CreateTexture() return Widget(self) end
    function w:CreateFontString() return Widget(self, true) end
    function w:CreateAnimationGroup()
        local group = Widget(self)
        function group:CreateAnimation() return Widget(self) end
        function group:Play() self.playing = true end
        function group:Stop() self.playing = false end
        return group
    end
    function w:SetFromAlpha() end
    function w:SetToAlpha() end
    function w:SetDuration() end
    function w:SetAlpha(value) self.alpha = value end
    function w:GetAlpha() return self.alpha or 1 end
    function w:GetParent() return self.parent end
    function w:SetParent(parent) self.parent = parent end
    function w:SetPoint(...)
        self.point = { ... }
        self.pointCalls = (self.pointCalls or 0) + 1
        setPoints = setPoints + 1
    end
    function w:ClearAllPoints() end
    function w:SetAllPoints() end
    function w:SetSize(a, b) self.width, self.height = a, b end
    function w:SetWidth(a) self.width = a end
    function w:SetHeight(a) self.height = a end
    function w:SetScale(a) self.scale = a end
    function w:SetFrameStrata() end
    function w:EnableMouse(value) self.mouse = value end
    function w:IsMouseEnabled() return self.mouse ~= false end
    function w:EnableMouseWheel() end
    function w:RegisterForClicks() end
    function w:SetScript(key, fn) self[key] = fn end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetTexture(value) self.texture = value end
    function w:SetTexCoord() end
    function w:SetText(text)
        assert(not self.fontString or self.font, "FontString text assigned before font")
        self.text = text
    end
    function w:SetTextColor(...) self.textColor = { ... } end
    function w:SetJustifyH() end
    function w:SetWordWrap() end
    function w:SetFont(_, size) self.font = true; self.fontSize = size; return true end
    function w:GetStringHeight()
        return #(self.text or "") > 30 and 50 or (self.fontSize or 12) + 2
    end
    function w:SetShadowColor() end
    function w:SetShadowOffset() end
    function w:SetStatusBarTexture() end
    function w:SetStatusBarColor() end
    function w:SetMinMaxValues() end
    function w:SetValue() end
    function w:SetScrollChild() end
    function w:GetVerticalScrollRange() return 0 end
    function w:GetVerticalScroll() return 0 end
    function w:SetVerticalScroll() end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(value) self.shown = value end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    return w
end
UIParent = Widget()
CreateFrame = function(_, name, parent)
    local frame = Widget(parent)
    frames[#frames + 1] = frame
    return frame
end
local clock = 100
GetTime = function() return clock end
GetZoneText = function() return "Dornogal" end
GetSubZoneText = function() return "" end
GetTasksTable = function() return {} end
GetAchievementInfo = function() return nil end
local openedLog, openedQuest = 0, nil
OpenQuestLog = function() openedLog = openedLog + 1 end
QuestMapFrame_ShowQuestDetails = function(id) openedQuest = id end
local lastMenu, stoppedQuest, stoppedWorld, stoppedAchievement, superTracked, shared, abandoned
local modifiedWatchClick, shiftDown = false, false
IsModifiedClick = function(binding)
    return binding == "QUESTWATCHTOGGLE" and modifiedWatchClick
end
IsShiftKeyDown = function() return shiftDown end
MenuUtil = { CreateContextMenu = function(owner, build)
    local root = { owner = owner, buttons = {} }
    function root:CreateTitle(title) self.title = title end
    function root:CreateButton(label, action)
        self.buttons[label] = action
        return { SetEnabled = function() end }
    end
    build(owner, root)
    lastMenu = root
end }
QuestUtil = {
    CanRemoveQuestWatch = function() return true end,
    UntrackWorldQuest = function(id) stoppedWorld = id end,
    ShareQuest = function(id) shared = id end,
}
IsInGroup = function() return true end
QuestMapQuestOptions_AbandonQuest = function(id) abandoned = id end
ShowAchievementFrameForAchievement = function(id) openedAchievement = id end
ToggleEncounterJournal = function() openedJournal = true end
LFGListUtil_FindScenarioGroup = function(id) foundScenario = id end
C_LFGList = { CanCreateScenarioGroup = function() return true end }
C_Timer = { After = function(_, callback) scheduled[#scheduled + 1] = callback end }
local function Drain()
    local pending = scheduled
    scheduled = {}
    for _, callback in ipairs(pending) do callback() end
end
local questUpdates = 0
C_QuestLog = {
    GetNumQuestWatches = function() questUpdates = questUpdates + 1; return 1 end,
    GetQuestIDForQuestWatchIndex = function() return 42 end,
    GetNumWorldQuestWatches = function() return 0 end,
    GetTitleForQuestID = function(id) return id == 42 and "A New Hope" or nil end,
    GetQuestObjectives = function() return { { text = "Collect 3 items", type = "monster", finished = false } } end,
    IsComplete = function() return false end,
    RemoveQuestWatch = function(id) stoppedQuest = id end,
    IsPushableQuest = function() return true end,
    CanAbandonQuest = function() return true end,
}
C_SuperTrack = { GetSuperTrackedQuestID = function() return 0 end,
    SetSuperTrackedQuestID = function(id) superTracked = id end }
C_Scenario = { GetInfo = function() return nil end }
Enum = { ContentTrackingType = { Achievement = 1 }, ContentTrackingStopType = { Manual = 2 } }
C_ContentTracking = { GetTrackedIDs = function() return {} end }
C_ContentTracking.StopTracking = function(_, id) stoppedAchievement = id end
Enum.EventToastEventType = { QuestTurnedIn = 12, Scenario = 14, LevelUp = 0,
    LevelUpSpell = 1, LevelUpDungeon = 2, LevelUpRaid = 3, LevelUpPvP = 4,
    LevelUpOther = 15, FlightpointDiscovered = 25 }
hooksecurefunc = function(object, method, callback)
    local original = assert(object[method])
    object[method] = function(self, ...)
        local result = { original(self, ...) }
        callback(self, ...)
        return unpack(result)
    end
end
local suite = { Client = { isMainline = true, isForever = flavor == "Forever" },
    Suite = { instances = {}, editMode = false },
    Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return false end }
local S = suite.Suite
S.Public = function() return true end
S.CreateFrame = CreateFrame
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.SetStyledFont = function(widget, path, size) widget:SetFont(path, size) end
S.ResolveFont = function(key) return key ~= "" and key or nil end
S.RGB = function(hex)
    return tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end
S.RegisterOwnedMover = function(id, element, spec) movers[id] = { element = element, spec = spec } end
S.Install = function(id, module) S.instances[id] = module end
S.Config = function(id) return S.instances[id].config end
S.Set = function(id, key, value) S.Config(id)[key] = value; return true end
local function Context()
    local ctx = { events = {}, hidden = {}, parents = {} }
    function ctx:Event(event, callback) self.events[event] = callback end
    function ctx:Skin() return nil end
    function ctx:HideControl(frame, value) self.hidden[frame] = value end
    function ctx:Property(frame, getter, setter, value)
        if not self.parents[frame] then self.parents[frame] = frame[getter](frame) end
        frame[setter](frame, value)
    end
    function ctx:RestoreProperty(frame, setter)
        if setter == "SetParent" and self.parents[frame] then
            frame:SetParent(self.parents[frame]); self.parents[frame] = nil
        end
    end
    return ctx
end
assert(loadfile(root .. "/MSUF_Suite_Modules/MythicPlus.lua"))("MSUF_Suite_Modules", { NS = suite, Suite = S })
assert(loadfile(root .. "/MSUF_Suite_Modules/Objectives.lua"))("MSUF_Suite_Modules", { NS = suite, Suite = S })
assert(loadfile(root .. "/MSUF_Suite_Modules/Announcements.lua"))("MSUF_Suite_Modules", { NS = suite, Suite = S })
local tracker = S.instances.objectives
tracker.context = Context()
tracker.config = { width = 310, height = 570, scale = 100, x = -40, y = -240,
    showWorldQuests = true, showBonus = true, showAchievements = true, showScenario = true }
ObjectiveTrackerFrame = Widget(UIParent)
tracker:Enable()
assert(tracker.nativeHiddenParent and ObjectiveTrackerFrame:GetParent() == tracker.nativeHiddenParent
    and not ObjectiveTrackerFrame:IsVisible(),
    "native objective tracker must remain hidden by its parent")
ObjectiveTrackerFrame:SetParent(UIParent)
ObjectiveTrackerFrame:Show()
tracker.context.events.GROUP_ROSTER_UPDATE(tracker, "GROUP_ROSTER_UPDATE")
assert(ObjectiveTrackerFrame:GetParent() == tracker.nativeHiddenParent
    and not ObjectiveTrackerFrame:IsVisible(),
    "raid roster changes must restore native tracker suppression")
local combatLocked = false
suite.IsCombatLocked = function() return combatLocked end
combatLocked = true
ObjectiveTrackerFrame:SetParent(UIParent)
tracker.context.events.GROUP_ROSTER_UPDATE(tracker, "GROUP_ROSTER_UPDATE")
assert(ObjectiveTrackerFrame:GetParent() == UIParent,
    "protected combat transitions must defer native parent changes")
combatLocked = false
tracker.context.events.PLAYER_REGEN_ENABLED(tracker, "PLAYER_REGEN_ENABLED")
assert(ObjectiveTrackerFrame:GetParent() == tracker.nativeHiddenParent
    and not ObjectiveTrackerFrame:IsVisible(),
    "native tracker must be hidden after combat ends")
assert(movers.objectives.element == "tracker" and tracker.rows["entry:quests:42"])
assert(tracker.host.shown and tracker.count.text == "1" and questUpdates == 1)
tracker.rows["entry:quests:42"].OnClick(tracker.rows["entry:quests:42"])
assert(openedLog == 1 and openedQuest == 42, "quest title did not open its quest details")
openedQuest = nil
tracker.rows["line:quests:42:1"].OnClick(tracker.rows["line:quests:42:1"])
assert(openedLog == 2 and openedQuest == 42, "objective line did not open its quest details")
tracker.headerClick.OnClick()
assert(openedLog == 3, "tracker header did not open the quest log")
local questRow = tracker.rows["entry:quests:42"]
questRow.OnClick(questRow, "RightButton")
assert(lastMenu.title == "A New Hope" and lastMenu.buttons["Stop tracking"]
    and lastMenu.buttons["Share quest"] and lastMenu.buttons["Abandon quest"]
    and openedLog == 3, "quest right-click did not open its context menu")
lastMenu.buttons["Stop tracking"]()
lastMenu.buttons["Share quest"]()
lastMenu.buttons["Abandon quest"]()
lastMenu.buttons["Super track quest"]()
assert(stoppedQuest == 42 and shared == 42 and abandoned == 42 and superTracked == 42)
stoppedQuest = nil
shiftDown = true
questRow.OnClick(questRow, "LeftButton")
assert(stoppedQuest == 42 and openedLog == 3,
    "Shift-left-click must untrack a quest without opening the quest log")
stoppedQuest = nil
shiftDown, modifiedWatchClick = false, true
questRow.OnClick(questRow, "LeftButton")
assert(stoppedQuest == 42 and openedLog == 3,
    "the configured quest-watch modifier must also untrack")
modifiedWatchClick = false
lastMenu = nil
questRow.collapse.OnClick(questRow.collapse, "RightButton")
assert(lastMenu and lastMenu.title == "A New Hope"
    and lastMenu.buttons["Super track quest"],
    "the quest collapse button must preserve the right-click context menu")
lastMenu = nil
local superTrackGetter = C_SuperTrack.GetSuperTrackedQuestID
C_SuperTrack.GetSuperTrackedQuestID = function() return nil end
questRow.OnClick(questRow, "RightButton")
assert(lastMenu and lastMenu.buttons["Super track quest"],
    "the context menu must offer focus when the current focus is unavailable")
C_SuperTrack.GetSuperTrackedQuestID = function() return 42 end
questRow.OnClick(questRow, "RightButton")
assert(lastMenu and lastMenu.buttons["Stop super tracking"],
    "the focused quest must offer a stop-focus action")
lastMenu.buttons["Stop super tracking"]()
assert(superTracked == 0, "stop-focus must clear Blizzard super tracking")
C_SuperTrack.GetSuperTrackedQuestID = superTrackGetter
tracker.rows["line:quests:42:1"].OnClick(tracker.rows["line:quests:42:1"], "RightButton")
assert(lastMenu.title == "A New Hope", "objective line must use its parent quest menu")
questRow.OnClick({ questID = 77, group = "world", tracked = true, menuTitle = "World Task" }, "RightButton")
assert(lastMenu.buttons["Stop tracking"] and not lastMenu.buttons["Abandon quest"])
lastMenu.buttons["Stop tracking"]()
assert(stoppedWorld == 77 and stoppedQuest == 42, "world quest used the wrong untrack API")
stoppedWorld = nil
shiftDown = true
questRow.OnClick({ questID = 77, group = "world", tracked = true }, "LeftButton")
assert(stoppedWorld == 77 and openedLog == 3,
    "Shift-left-click must use the world quest untrack API")
shiftDown = false
questRow.OnClick({ questID = 88, group = "bonus", menuTitle = "Bonus" }, "RightButton")
assert(lastMenu.buttons["Show on map"] and not lastMenu.buttons["Stop tracking"],
    "automatic bonus objective must not offer an invalid untrack action")
questRow.OnClick({ achievementID = 99, group = "achievements", menuTitle = "Heroic" }, "RightButton")
assert(lastMenu.buttons["View achievement"] and lastMenu.buttons["Stop tracking"])
lastMenu.buttons["Stop tracking"]()
assert(stoppedAchievement == 99, "achievement menu did not use content tracking")
stoppedAchievement = nil
shiftDown = true
questRow.OnClick({ achievementID = 99, group = "achievements", tracked = true }, "LeftButton")
assert(stoppedAchievement == 99 and openedLog == 3,
    "Shift-left-click must untrack an achievement")
shiftDown = false
questRow.OnClick({ group = "scenario", scenarioID = 123, menuTitle = "Delve" }, "RightButton")
assert(lastMenu.buttons["Adventure Guide"] and lastMenu.buttons["Find group"])
lastMenu.buttons["Find group"]()
assert(foundScenario == 123, "scenario menu did not use its scenario ID")
local before = setPoints
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
tracker.context.events.QUEST_WATCH_UPDATE(tracker, "QUEST_WATCH_UPDATE")
assert(#scheduled == 1, "burst should schedule one objective refresh")
Drain()
assert(questUpdates == 2 and setPoints == before, "unchanged objectives should not lay out again")
tracker.config.colorStyle = 2
tracker.config.backgroundColor = "224466"
tracker.config.titleColor = "ffffff"
tracker.config.textColor = "ffffff"
tracker.config.mutedColor = "aaaaaa"
tracker.config.completeColor = "00ff00"
tracker.config.dividerColor = "bbbbbb"
for _, key in ipairs({ "scenarioColor", "focusedColor", "campaignColor", "importantColor",
    "completeGroupColor", "questsColor", "worldColor", "bonusColor", "achievementsColor" }) do
    tracker.config[key] = "ff0000"
end
tracker.config.entrySize = 18
tracker:Refresh()
assert(questUpdates == 2, "tracker color and font changes must reuse collected objectives")
assert(math.abs(tracker.background.color[1] - 34 / 255) < .001
    and tracker.rows["entry:quests:42"].text.textColor[1] == 1
    and tracker.rows["entry:quests:42"].text.fontSize == 18,
    "tracker custom colors must reach its owned frame")
local sectionRow, entryRow = tracker.rows["section:quests"], tracker.rows["entry:quests:42"]
local sectionPoints, entryPoints = sectionRow.pointCalls, entryRow.pointCalls
C_QuestLog.GetQuestObjectives = function()
    return { { text = "Collect 4 items", type = "monster", finished = false } }
end
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
Drain()
assert(tracker.rows["line:quests:42:1"].text.text == "Collect 4 items"
    and sectionRow.pointCalls == sectionPoints and entryRow.pointCalls == entryPoints,
    "changing one objective should leave unchanged row geometry alone")
GetAchievementInfo = function(id) return id, "Heroic", 10, false end
C_ContentTracking.GetTrackedIDs = function() return { 99 } end
C_Scenario.GetInfo = function()
    return "Delve", 1, 2, nil, nil, nil, nil, nil, nil, nil, nil, nil, 123
end
C_Scenario.GetStepInfo = function() return "Stage one", "Do the thing", 0 end
tracker.context.events.CONTENT_TRACKING_UPDATE(tracker, "CONTENT_TRACKING_UPDATE")
tracker.context.events.SCENARIO_UPDATE(tracker, "SCENARIO_UPDATE")
Drain()
local achievementRow = tracker.rows["entry:achievements:99"]
local scenarioRow = tracker.rows["entry:scenario:0"]
assert(achievementRow and achievementRow.mouse and achievementRow.achievementID == 99
    and scenarioRow and scenarioRow.mouse and scenarioRow.scenarioID == 123
    and tracker.rows["line:scenario:0:1"].mouse,
    "achievement and scenario objectives must be interactive rows")
achievementRow.OnClick(achievementRow, "RightButton")
assert(lastMenu.buttons["View achievement"], "achievement row did not expose its menu")
scenarioRow.OnClick(scenarioRow, "RightButton")
assert(lastMenu.buttons["Find group"], "scenario row did not expose its menu")
assert(movers.objectives.spec.xKey == "x" and movers.objectives.spec.yKey == "y")
local banner = S.instances.announcements
banner.context = Context()
banner.config = { zone = true, eventToasts = true, quests = false,
    achievements = true, level = false, scenario = false,
    duration = 4, scale = 100, anchor = 1, x = 0, y = -90 }
ZoneTextFrame = Widget(UIParent)
SubZoneTextFrame = Widget(UIParent)
EventToastManagerFrame = Widget(UIParent)
function EventToastManagerFrame:DisplayToast(info)
    self.currentDisplayingToast = info and { toastInfo = info } or nil
end
local achievement = Widget(UIParent)
AchievementAlertSystem = { alertFramePool = {
    EnumerateActive = function()
        local used = false
        return function() if not used then used = true; return achievement end end
    end,
} }
function AchievementAlertSystem:ShowAlert() achievement:SetParent(UIParent) end
local worldQuest, scenarioAlert = Widget(UIParent), Widget(UIParent)
WorldQuestCompleteAlertSystem = { alertFramePool = {
    EnumerateActive = function()
        local used = false
        return function() if not used then used = true; return worldQuest end end
    end,
} }
function WorldQuestCompleteAlertSystem:ShowAlert() worldQuest:SetParent(UIParent) end
ScenarioAlertSystem = { alertFramePool = {
    EnumerateActive = function()
        local used = false
        return function() if not used then used = true; return scenarioAlert end end
    end,
} }
function ScenarioAlertSystem:ShowAlert() scenarioAlert:SetParent(UIParent) end
banner:Enable()
assert(movers.announcements.element == "banner" and banner.context.hidden[ZoneTextFrame])
assert(ZoneTextFrame:GetParent() == banner.hiddenParent and banner.context.hidden[EventToastManagerFrame])
AchievementAlertSystem:ShowAlert()
assert(achievement:GetParent() == banner.hiddenParent, "native achievement alert must be hidden")
banner.context.events.QUEST_ACCEPTED(banner, "QUEST_ACCEPTED", 42)
assert(not banner.host.shown and #banner.queue == 0, "optional quest alerts must stay off")
GetSubZoneText = function() return "The Coreway" end
banner.context.events.ZONE_CHANGED(banner, "ZONE_CHANGED")
banner.context.events.ZONE_CHANGED_INDOORS(banner, "ZONE_CHANGED_INDOORS")
assert(#scheduled == 1, "zone burst should be coalesced")
Drain()
assert(banner.host.shown and banner.title.text == "The Coreway")
assert(banner.subtitle.text == "Dornogal" and movers.announcements.spec.point() == "TOP"
    and banner.host.point[1] == "TOP", "new announcements should start at top center")
banner.config.anchor, banner.config.y = 2, -170
banner:Refresh()
assert(movers.announcements.spec.point() == "CENTER" and banner.host.point[1] == "CENTER",
    "saved center-anchored announcements should keep their position")
banner.config.colorStyle = 2
banner.config.backgroundColor = "112233"
banner.config.subtitleColor = "ffffff"
banner.config.zoneColor = "00ff00"
for _, key in ipairs({ "questColor", "achievementColor", "levelColor", "scenarioColor", "noticeColor" }) do
    banner.config[key] = "ff0000"
end
local serial = banner.serial
banner:Refresh()
assert(banner.serial == serial and banner.title.textColor[2] == 1
    and math.abs(banner.background.color[1] - 17 / 255) < .001,
    "announcement color changes must repaint without restarting the display timer")
EventToastManagerFrame:DisplayToast({ eventType = 25, eventToastID = 7,
    title = "Flight point discovered", subtitle = "Dornogal" })
assert(banner.context.hidden[EventToastManagerFrame] and #banner.queue == 1,
    "native toast must be hidden and its content queued in MSUF")
banner.config.quests, banner.config.scenario = true, true
banner:Refresh()
WorldQuestCompleteAlertSystem:ShowAlert({ taskName = "World task" })
ScenarioAlertSystem:ShowAlert({ name = "Scenario reward" })
assert(worldQuest:GetParent() == banner.hiddenParent
    and scenarioAlert:GetParent() == banner.hiddenParent and #banner.queue == 3,
    "quest and scenario alerts must be hidden and represented in MSUF")
banner.config.eventToasts, banner.config.achievements = false, false
banner.config.quests, banner.config.scenario = false, false
banner:Refresh()
assert(banner.context.hidden[EventToastManagerFrame] == false
    and achievement:GetParent() == UIParent and worldQuest:GetParent() == UIParent
    and scenarioAlert:GetParent() == UIParent,
    "disabling replacements must restore Blizzard alerts")
local mutedQueue = #banner.queue
EventToastManagerFrame:DisplayToast({ eventType = 25, eventToastID = 8,
    title = "Muted toast", subtitle = "Dornogal" })
assert(#banner.queue == mutedQueue and banner.context.hidden[EventToastManagerFrame] == false,
    "a disabled toast replacement must leave Blizzard's toast alone")
banner.config.eventToasts, banner.config.achievements = true, true
banner:Refresh()
S.editMode = true
banner:Refresh()
assert(banner.host.shown and banner.title.text == "ANNOUNCEMENTS")
tracker:Refresh()
assert(tracker.host.shown, "tracker must remain visible for placement in Edit Mode")
S.editMode = false
banner:Refresh()
assert(banner.title.text == "The Coreway", "leaving Edit Mode must restore the active announcement")
for _, frame in ipairs(frames) do assert(frame.OnUpdate == nil, "HUD registered an OnUpdate") end
tracker.config.colorStyle = 1
tracker.config.backgroundOpacity = nil
tracker:Refresh()
assert(tracker.background.color[4] == 0, "standard objective tracker must have no backdrop")
local usedQuestItem
GetQuestLogSpecialItemInfo = function(index)
    if index == 42 or index == 43 then return "item:777", 1234, 1, true end
end
UseQuestLogSpecialItem = function(index) usedQuestItem = index end
QuestUtil.QuestShowsItemByIndex = function() return true end
C_QuestLog.GetLogIndexForQuestID = function(id) return id end
C_QuestLog.GetTimeAllowed = function() return 120, 30 end
C_QuestLog.GetQuestObjectives = function()
    local lines = {}
    for i = 1, 6 do lines[i] = { text = i == 6 and string.rep("Long objective text ", 5)
        or "Objective " .. i, type = "monster", finished = false } end
    return lines
end
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
Drain()
assert(tracker.rows["line:quests:42:6"], "all quest objectives must remain visible")
assert(tracker.rows["line:quests:42:6"].height > 50,
    "long objective text must receive enough height after wrapping")
local activeQuest = tracker.rows["entry:quests:42"]
assert(activeQuest.itemButton and activeQuest.itemButton.shown and activeQuest.timer.text == "1:30",
    "quest item and time remaining must be visible on the active quest")
activeQuest.itemButton.OnClick(activeQuest.itemButton)
assert(usedQuestItem == 42, "quest item button must use the current quest log index")
activeQuest.itemButton.OnClick(activeQuest.itemButton, "RightButton")
assert(lastMenu.title == "A New Hope" and usedQuestItem == 42,
    "quest item right-click must open the parent quest menu")
stoppedQuest = nil
shiftDown = true
activeQuest.itemButton.OnClick(activeQuest.itemButton, "LeftButton")
assert(stoppedQuest == 42 and usedQuestItem == 42,
    "Shift-left-click on the quest item must untrack instead of using it")
shiftDown = false
clock = 101
Drain()
assert(activeQuest.timer.text == "1:29", "visible quest timer must update without rebuilding rows")
activeQuest.collapse.OnClick(activeQuest.collapse)
assert(not tracker.rows["line:quests:42:1"] and tracker.config.collapsedEntries["quests:42"],
    "quest collapse must hide only its objective lines")
tracker.rows["entry:quests:42"].collapse.OnClick(tracker.rows["entry:quests:42"].collapse)
assert(tracker.rows["line:quests:42:6"], "quest expansion must restore every objective")
tracker.rows["section:quests"].OnClick(tracker.rows["section:quests"])
assert(not tracker.rows["entry:quests:42"] and tracker.config.collapsedGroups.quests,
    "group collapse must hide its entries and persist the group state")
tracker.rows["section:quests"].OnClick(tracker.rows["section:quests"])
local rowFrameCount = #frames
C_QuestLog.GetQuestIDForQuestWatchIndex = function() return 43 end
C_QuestLog.GetTitleForQuestID = function(id) return id == 43 and "Another Quest" or nil end
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
Drain()
assert(tracker.rows["entry:quests:43"] and not tracker.rows["entry:quests:42"]
    and #frames == rowFrameCount, "quest churn must recycle old row frames")
C_QuestLog.GetNumWorldQuestWatches = function() return 1 end
C_QuestLog.GetQuestIDForWorldQuestWatchIndex = function() return 77 end
C_QuestLog.GetTitleForQuestID = function(id)
    return id == 43 and "Another Quest" or id == 77 and "World Task" or nil
end
C_TaskQuest = { GetQuestTimeLeftSeconds = function(id) return id == 77 and 300 or nil end }
C_Scenario.GetStepInfo = function() return "Stage one", "Do the thing", 1 end
C_ScenarioInfo = { GetCriteriaInfo = function()
    return { description = "Finish before time runs out", completed = false,
        duration = 60, elapsed = 10 }
end }
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
tracker.context.events.SCENARIO_UPDATE(tracker, "SCENARIO_UPDATE")
Drain()
assert(tracker.rows["entry:world:77"].timer.text == "5:00"
    and tracker.rows["entry:scenario:0"].timer.text == "0:50",
    "world and scenario countdowns must use their matching Blizzard data")
tracker.config.showTimers = false
tracker:Refresh()
assert(not tracker.rows["entry:quests:43"].timerEnd,
    "disabling countdowns must stop active timer rows")
if flavor == "Mainline" then
local activeKey, elapsed, deaths, penalty = true, 600, 2, 10
local ticker
C_Timer.NewTicker = function(interval, callback)
    assert(interval == 1, "M+ clock must update once per second")
    ticker = { callback = callback }
    function ticker:Cancel() self.cancelled = true end
    function ticker:Fire() if not self.cancelled then self.callback() end end
    return ticker
end
Enum.WorldElapsedTimerTypes = { ChallengeMode = 1 }
C_ChallengeMode = {
    IsChallengeModeActive = function() return activeKey end,
    GetActiveChallengeMapID = function() return activeKey and 500 or nil end,
    GetMapUIInfo = function() return "The Test Dungeon", nil, 1800 end,
    GetActiveKeystoneInfo = function() return 15, { 1, 2 } end,
    GetAffixInfo = function(id) return id == 1 and "Fortified" or "Bursting" end,
    GetDeathCount = function() return deaths, penalty end,
    GetChallengeCompletionInfo = function()
        return { time = 1100000, keystoneUpgradeLevels = 2, onTime = true }
    end,
}
GetWorldElapsedTimers = function() return 7 end
GetWorldElapsedTime = function(id)
    assert(id == 7, "the challenge timer ID must come from Blizzard")
    return "Challenge", elapsed, Enum.WorldElapsedTimerTypes.ChallengeMode
end
C_Scenario.GetStepInfo = function() return "Dungeon", "", 3 end
local secondBossDone, forces = false, 63
C_ScenarioInfo.GetCriteriaInfo = function(index)
    if index == 1 then return { description = "First boss", completed = true, elapsed = 200 } end
    if index == 2 then return { description = "Second boss", completed = secondBossDone,
        elapsed = secondBossDone and 100 or nil } end
    return { description = "Enemy forces", isWeightedProgress = true,
        quantity = forces, totalQuantity = 100 }
end
tracker.config.showMythicPlus = true
local beforeKeyUpdates = questUpdates
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
tracker.context.events.CHALLENGE_MODE_START(tracker, "CHALLENGE_MODE_START")
Drain()
assert(tracker.mplusActive and ticker and tracker.mplus.frame.shown
    and tracker.title.text == "MYTHIC+" and tracker.count.text == "+15"
    and tracker.mplus.clock.text == "10:00 / 30:00"
    and tracker.mplus.chests[1].label.text == "+3  18:00"
    and tracker.mplus.deaths.text == "DEATHS  2     TIME PENALTY  +0:10"
    and tracker.mplus.forces.text == "ENEMY FORCES  63.0%"
    and tracker.mplus.bosses[1].time.text == "6:40"
    and not tracker.rows["entry:quests:43"].shown
    and questUpdates == beforeKeyUpdates,
    "active M+ must replace quest rows and cancel pending quest work")
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
assert(questUpdates == beforeKeyUpdates, "quest updates must not rebuild the hidden tracker")
elapsed = 1100
ticker:Fire()
assert(tracker.mplus.clock.text == "18:20 / 30:00"
    and tracker.mplus.chests[1].remaining.text == "missed"
    and tracker.mplus.chests[2].remaining.text == "5:40 left",
    "chest cutoffs must track Blizzard's elapsed challenge time")
deaths, penalty, secondBossDone, forces = 3, 15, true, 80
tracker.context.events.CHALLENGE_MODE_DEATH_COUNT_UPDATED(tracker, "CHALLENGE_MODE_DEATH_COUNT_UPDATED")
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
assert(tracker.mplus.deaths.text == "DEATHS  3     TIME PENALTY  +0:15"
    and tracker.mplus.forces.text == "ENEMY FORCES  80.0%"
    and tracker.mplus.bosses[2].time.text == "16:40",
    "deaths, penalty, forces and boss progress must update from their own events")
local secret = {}
S.Public = function(value) return value ~= secret end
C_ChallengeMode.GetDeathCount = function() return secret, secret end
forces = secret
tracker.context.events.CHALLENGE_MODE_DEATH_COUNT_UPDATED(tracker, "CHALLENGE_MODE_DEATH_COUNT_UPDATED")
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
assert(tracker.mplus.deaths.text == "DEATHS  --     TIME PENALTY  +--:--"
    and tracker.mplus.forces.text == "ENEMY FORCES  --",
    "unreadable challenge values must stay unknown")
S.Public = function() return true end
C_ChallengeMode.GetDeathCount = function() return deaths, penalty end
forces = 80
activeKey = false
tracker.context.events.CHALLENGE_MODE_COMPLETED(tracker, "CHALLENGE_MODE_COMPLETED")
assert(ticker.cancelled and tracker.mplus.remaining.text == "COMPLETE  +2"
    and not tracker.rows["entry:quests:43"].shown,
    "completed run must freeze its result without waking the ticker")
C_ChallengeMode.GetChallengeCompletionInfo = function()
    return { time = 1100000, keystoneUpgradeLevels = 3, onTime = true }
end
tracker.context.events.CHALLENGE_MODE_COMPLETED_REWARDS(tracker, "CHALLENGE_MODE_COMPLETED_REWARDS")
assert(tracker.mplus.remaining.text == "COMPLETE  +3" and ticker.cancelled,
    "late completion rewards must refresh the result without restarting the clock")
tracker.context.events.PLAYER_ENTERING_WORLD(tracker, "PLAYER_ENTERING_WORLD")
assert(not tracker.mplusActive and not tracker.mplus.frame.shown
    and tracker.rows["entry:quests:43"].shown and questUpdates > beforeKeyUpdates,
    "leaving a completed key must restore normal objectives")
activeKey = true
C_ChallengeMode.GetMapUIInfo = function() return nil end
C_Scenario.GetStepInfo = function() return nil end
tracker.context.events.CHALLENGE_MODE_START(tracker, "CHALLENGE_MODE_START")
assert(tracker.mplusActive and tracker.mplus.remaining.text == "WAITING FOR TIMER"
    and tracker.mplus.chests[1].label.text == "+3  --:--"
    and tracker.mplus.forces.text == "ENEMY FORCES  --"
    and not tracker.mplus.bosses[1].shown,
    "a new run with late data must not show the previous run's values")
C_ChallengeMode.GetMapUIInfo = function() return "The Test Dungeon", nil, 1800 end
C_Scenario.GetStepInfo = function() return "Dungeon", "", 3 end
elapsed = 610
ticker:Fire()
tracker.context.events.SCENARIO_UPDATE(tracker, "SCENARIO_UPDATE")
assert(tracker.mplus.clock.text == "10:10 / 30:00"
    and tracker.mplus.dungeon.text == "The Test Dungeon  +15",
    "the active timer must pick up dungeon data when it becomes available")
local disabledTicker = ticker
tracker.config.showMythicPlus = false
tracker:Refresh()
assert(not tracker.mplusActive and disabledTicker.cancelled
    and tracker.rows["entry:quests:43"].shown,
    "turning off the M+ replacement must cancel its ticker and show quests")
activeKey = false
end
tracker:Disable()
Drain()
tracker.context:RestoreProperty(ObjectiveTrackerFrame, "SetParent")
assert(ObjectiveTrackerFrame:GetParent() == UIParent,
    "disabling the MSUF tracker must restore Blizzard's original parent")
for _, frame in ipairs(frames) do assert(frame.OnUpdate == nil, "HUD registered an OnUpdate") end
print("Suite HUD: owned frames, full objectives, clicks, timers, collapse, row reuse and movers passed: " .. flavor)
