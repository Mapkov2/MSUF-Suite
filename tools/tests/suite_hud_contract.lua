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
    function w:SetAtlas(value) self.atlas = value end
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
GetDifficultyInfo = function(id) return id == 16 and "Mythic" or "Normal" end
GetZoneText = function() return "Dornogal" end
GetSubZoneText = function() return "" end
GetTasksTable = function() return {} end
GetAchievementInfo = function() return nil end
local openedLog, openedQuest = 0, nil
OpenQuestLog = function() openedLog = openedLog + 1 end
-- Blizzard's function opens the quest log on the quest's details.
QuestMapFrame_OpenToQuestDetails = function(id)
    openedLog = openedLog + 1
    openedQuest = id
end
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
local questActivity, openedFinder, foundQuest
C_LFGList = { CanCreateScenarioGroup = function() return true end,
    GetActivityIDForQuestID = function(id) return id == 77 and questActivity or nil end }
PVEFrame_ShowFrame = function() openedFinder = openedFinder and openedFinder + 1 or 1 end
LFGListUtil_FindQuestGroup = function(id) foundQuest = id end
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
Enum.UIWidgetVisualizationType = { ScenarioHeaderTimer = 20 }
Enum.WidgetShownState = { Hidden = 0, Shown = 1 }
local widgetTime, widgetSetLookups, lastWidgetSetID = nil, 0, nil
C_UIWidgetManager = {
    GetAllWidgetsBySetID = function(setID)
        widgetSetLookups, lastWidgetSetID = widgetSetLookups + 1, setID
        return setID == 777 and widgetTime and { { widgetID = 901, widgetType = 20 } } or {}
    end,
    GetScenarioHeaderTimerWidgetVisualizationInfo = function()
        return widgetTime and { shownState = 1, timerMin = 0, timerMax = 180, timerValue = widgetTime }
    end,
}
C_ContentTracking = { GetTrackedIDs = function() return {} end }
C_ContentTracking.StopTracking = function(_, id) stoppedAchievement = id end
-- Neutral answers of the other quest APIs Retail and Forever both have: no
-- timers, quest items, classification, tasks or achievement criteria.
C_QuestLog.GetTimeAllowed = function() return nil end
C_QuestLog.GetLogIndexForQuestID = function() return nil end
C_QuestLog.GetInfo = function() return nil end
C_QuestInfoSystem = { GetQuestClassification = function() return nil end }
C_TaskQuest = { GetQuestTimeLeftSeconds = function() return nil end,
    GetQuestInfoByQuestID = function() return nil end, GetQuestZoneID = function() return nil end }
C_ScenarioInfo = { GetCriteriaInfo = function() return nil end }
C_Scenario.GetStepInfo = function() return nil end
QuestUtil.QuestShowsItemByIndex = function() return false end
QuestUtils_IsQuestWorldQuest = function() return false end
GetQuestProgressBarPercent = function() return nil end
GetAchievementNumCriteria = function() return 0 end
GetAchievementCriteriaInfo = function() return nil end
GetTaskInfo = function() return nil end
GetQuestObjectiveInfo = function() return nil end
GetQuestLogSpecialItemInfo = function() return nil end
UseQuestLogSpecialItem = function() end
-- Blizzard's global strings for the context menu labels.
OBJECTIVES_VIEW_ACHIEVEMENT, OBJECTIVES_STOP_TRACKING = "View achievement", "Stop tracking"
ENCOUNTER_JOURNAL, FIND_A_GROUP = "Adventure Guide", "Find group"
OBJECTIVES_SHOW_QUEST_MAP, OBJECTIVES_VIEW_IN_QUESTLOG = "Show on map", "View in Quest Log"
STOP_SUPER_TRACK_QUEST, SUPER_TRACK_QUEST = "Stop super tracking", "Super track quest"
SHARE_QUEST, ABANDON_QUEST_ABBREV = "Share quest", "Abandon quest"
-- No keystone runs until the Mythic+ section below replaces this.
C_ChallengeMode = { IsChallengeModeActive = function() return false end }
-- Blizzard_GameTooltip builds GameTooltip, with its data accessors, at startup
-- on every supported client.
GameTooltip = { shown = false }
function GameTooltip:SetOwner(owner) self.owner, self.link, self.achievement, self.item, self.text = owner end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:SetHyperlink(link) self.link = link end
function GameTooltip:SetAchievementByID(id) self.achievement = id end
function GameTooltip:SetQuestLogSpecialItem(index) self.item = index end
function GameTooltip:SetText(text) self.text = text end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end
EventRegistry = { TriggerEvent = function() end }
IsInInstance = function() return false end
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
-- A distinct media path proves the modules read MSUF's shared font constant.
local SUITE_FONT = "Interface\\AddOns\\Test\\SuiteFont.ttf"
local suite = { Client = { isMainline = true, isForever = flavor == "Forever" },
    MSUFMedia = { font = SUITE_FONT },
    Suite = { instances = {}, editMode = false },
    Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return false end }
local S = suite.Suite
S.GlobalFontPath = function() return SUITE_FONT end
-- The modules capture the readers when they load; this value stands in for a
-- secret one.
local secret = {}
S.Public = function(value) return value ~= secret end
-- Readable-number helpers as defined by MSUF_Suite_Modules/Runtime.lua.
S.Number = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Finite = function(value) return S.Number(value) and value > -math.huge and value < math.huge end
-- Shared text readers as defined by MSUF_Suite_Modules/Runtime.lua.
S.PublicText = function(value)
    return S.Public(value) and type(value) == "string" and value ~= "" and value or nil
end
S.ReadText = function(fn, ...)
    if type(fn) ~= "function" then return nil end
    return S.PublicText((fn(...)))
end
-- The client's securecallfunction (S.Dispatch) reports an error and returns
-- nothing; the caller goes on.
local reported = {}
S.Dispatch = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
S.CreateFrame = CreateFrame
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.SetStyledFont = function(widget, path, size) widget.fontPath = path; widget:SetFont(path, size) end
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
local moduleStates = {}
S.ModuleState = function(id) moduleStates[id] = moduleStates[id] or {}; return moduleStates[id] end
local function Context()
    local ctx = { events = {}, eventUnits = {}, hidden = {}, parents = {} }
    function ctx:Event(event, callback, _, unit) self.events[event], self.eventUnits[event] = callback, unit end
    function ctx:RemoveEvent(event) self.events[event] = nil end
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
-- The HUD files load in TOC order and share the runtime's private table.
local private = { NS = suite, Suite = S }
for _, file in ipairs({ "MythicPlus", "Raid", "ObjectivesData", "ObjectivesTracker", "Objectives", "Announcements" }) do
    assert(loadfile(root .. "/MSUF_Suite_Modules/" .. file .. ".lua"))("MSUF_Suite_Modules", private)
end
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
-- Hovering a row shows the quest link, the achievement, or the title.
questRow.OnEnter(questRow)
assert(GameTooltip.shown and GameTooltip.owner == questRow and GameTooltip.link == "quest:42",
    "a quest row did not show its quest tooltip")
questRow.OnLeave(questRow)
assert(not GameTooltip.shown, "leaving a quest row kept its tooltip")
local achievementHover = { achievementID = 99, menuTitle = "Heroic" }
questRow.OnEnter(achievementHover)
assert(GameTooltip.owner == achievementHover and GameTooltip.achievement == 99 and not GameTooltip.link,
    "an achievement row did not show its achievement tooltip")
local scenarioHover = { menuTitle = "Delve" }
questRow.OnEnter(scenarioHover)
assert(GameTooltip.owner == scenarioHover and GameTooltip.text == "Delve", "a scenario row did not show its title")
questRow.OnLeave(questRow)
assert(GameTooltip.shown, "leaving another row hid a tooltip it does not own")
questRow.OnLeave(scenarioHover)
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
-- Refreshes reuse collected entry tables and one shared flush callback.
local questEntry, questLine = tracker.sources.quests[1], tracker.sources.quests[1].lines[1]
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
local flushCallback = scheduled[1]
Drain()
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
assert(scheduled[1] == flushCallback, "each refresh request allocated a new callback")
Drain()
assert(tracker.sources.quests[1] == questEntry and tracker.sources.quests[1].lines[1] == questLine
    and questUpdates == 4 and setPoints == before, "a quest refresh allocated new entry tables")
questUpdates = 2
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
assert(#movers.objectives.spec.extraControls == 3
    and movers.objectives.spec.extraControls[1].id == "width"
    and movers.objectives.spec.extraControls[2].id == "height"
    and movers.objectives.spec.extraControls[3].id == "scale",
    "objective tracker popup omitted its scale control")
assert(movers.objectives.spec.extraControls[3].set(125) and tracker.config.scale == 125)
assert(movers.objectives.spec.extraControls[3].set(100))
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
assert(movers.announcements.spec.extraControls[1].id == "scale"
    and movers.announcements.spec.extraControls[1].set(125)
    and banner.config.scale == 125,
    "announcements popup omitted its scale control")
assert(movers.announcements.spec.extraControls[1].set(100))
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
assert(banner.title.fontPath == SUITE_FONT and tracker.font == SUITE_FONT,
    "HUD text must default to MSUF's shared font")
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
-- The hooks run inside Blizzard's DisplayToast and ShowAlert: an error in
-- them is reported and Blizzard's call still completes.
local broken = setmetatable({}, { __index = function() error("unreadable Blizzard data") end })
local toastCompleted = pcall(EventToastManagerFrame.DisplayToast, EventToastManagerFrame, broken)
EventToastManagerFrame.currentDisplayingToast = nil
local alertCompleted = pcall(WorldQuestCompleteAlertSystem.ShowAlert, WorldQuestCompleteAlertSystem, broken)
assert(toastCompleted and alertCompleted and #reported == 2,
    "a raising announcement hook broke Blizzard's toast or alert call")
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
activeQuest.itemButton.OnEnter(activeQuest.itemButton)
assert(GameTooltip.shown and GameTooltip.owner == activeQuest.itemButton and GameTooltip.item == 42,
    "the quest item button did not show its item tooltip")
activeQuest.itemButton.OnLeave(activeQuest.itemButton)
assert(not GameTooltip.shown, "leaving the quest item button kept its tooltip")
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
assert(not tracker.rows["line:quests:42:1"] and moduleStates.objectives.collapsedEntries["quests:42"]
    and tracker.config.collapsedEntries == nil,
    "quest collapse must hide only its objective lines")
tracker.rows["entry:quests:42"].collapse.OnClick(tracker.rows["entry:quests:42"].collapse)
assert(tracker.rows["line:quests:42:6"], "quest expansion must restore every objective")
tracker.rows["section:quests"].OnClick(tracker.rows["section:quests"])
assert(not tracker.rows["entry:quests:42"] and moduleStates.objectives.collapsedGroups.quests
    and tracker.config.collapsedGroups == nil,
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
C_TaskQuest.GetQuestTimeLeftSeconds = function(id) return id == 77 and 300 or nil end
C_Scenario.GetStepInfo = function()
    return "Stage one", "Do the thing", 1, nil, nil, nil, nil, nil, nil, nil, nil, 777
end
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
if flavor == "Mainline" then
    local groupButton = tracker.rows["entry:world:77"].findGroupButton
    assert(groupButton and groupButton.icon.atlas == "socialqueuing-icon-eye",
        "world quests need a group finder button even without a quest activity")
    groupButton.OnClick(groupButton)
    assert(openedFinder == 1 and not foundQuest,
        "a world quest without a quest activity must open the generic finder")
    questActivity = 123
    tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
    Drain()
    groupButton = tracker.rows["entry:world:77"].findGroupButton
    groupButton.OnClick(groupButton)
    assert(foundQuest == 77, "a groupable quest must open its quest-specific search")
end
widgetTime = 90
C_ScenarioInfo.GetCriteriaInfo = function() return { description = "Defend", completed = false } end
local previousLookups = widgetSetLookups
tracker.context.events.UPDATE_UI_WIDGET(tracker, "UPDATE_UI_WIDGET", { widgetSetID = 999 })
Drain()
assert(widgetSetLookups == previousLookups,
    "unrelated widget updates must not re-read the scenario")
tracker.context.events.UPDATE_UI_WIDGET(tracker, "UPDATE_UI_WIDGET", { widgetSetID = 777 })
Drain()
assert(tracker.rows["entry:scenario:0"].timer.text == "1:30"
    and widgetSetLookups == previousLookups + 1 and lastWidgetSetID == 777,
    "scenario header widgets must supply the phase timer when criteria do not")
C_Scenario.GetStepInfo = function() return "Stage one", "Do the thing", 1 end
C_ScenarioInfo.GetCriteriaInfo = function()
    return { description = "Defend", completed = false, duration = 60, elapsed = 10 }
end
previousLookups = widgetSetLookups
tracker.context.events.SCENARIO_UPDATE(tracker, "SCENARIO_UPDATE")
Drain()
assert(tracker.rows["entry:scenario:0"].timer.text == "0:50"
    and tracker.scenarioWidgetSetID == nil and widgetSetLookups == previousLookups,
    "a phase without a widget set must retain the criterion timer fallback")
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
local priorSubzone = GetSubZoneText
GetSubZoneText = function() return "Keystone Hall" end
local zoneQueue = #banner.queue
banner.context.events.ZONE_CHANGED(banner, "ZONE_CHANGED")
Drain()
assert(banner.lastZone == "Dornogal/Keystone Hall" and #banner.queue == zoneQueue,
    "keystone subzone added a zone banner")
GetSubZoneText = priorSubzone
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
        quantity = forces, totalQuantity = 500 }
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
C_ChallengeMode.GetDeathCount = function() return secret, secret end
forces = secret
tracker.context.events.CHALLENGE_MODE_DEATH_COUNT_UPDATED(tracker, "CHALLENGE_MODE_DEATH_COUNT_UPDATED")
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
assert(tracker.mplus.deaths.text == "DEATHS  --     TIME PENALTY  +--:--"
    and tracker.mplus.forces.text == "ENEMY FORCES  --",
    "unreadable challenge values must stay unknown")
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
local insideRaid, instanceKind = false, nil
IsInInstance = function() return insideRaid, instanceKind end
tracker.config.pauseInRaidCombat = true
tracker.config.showTimers = true
tracker:Refresh()
assert(tracker.timerPending, "visible objective timers should schedule before raid combat")
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
insideRaid, instanceKind, combatLocked = true, "raid", true
tracker.context.events.PLAYER_REGEN_DISABLED(tracker, "PLAYER_REGEN_DISABLED")
assert(tracker.pausedForRaidCombat and not tracker.host.shown
    and not tracker.timerPending
    and not tracker.context.events.QUEST_LOG_UPDATE
    and not tracker.context.events.SCENARIO_UPDATE
    and not tracker.context.events.GROUP_ROSTER_UPDATE
    and tracker.context.events.PLAYER_ENTERING_WORLD,
    "raid combat must hide the Suite tracker and unregister its work events")
local beforeRaidReads = questUpdates
tracker.context.events.ZONE_CHANGED_NEW_AREA(tracker, "ZONE_CHANGED_NEW_AREA")
Drain()
assert(questUpdates == beforeRaidReads and not tracker.timerPending,
    "raid combat must cancel queued tracker reads and countdown ticks")
combatLocked = false
tracker.context.events.PLAYER_REGEN_ENABLED(tracker, "PLAYER_REGEN_ENABLED")
assert(not tracker.pausedForRaidCombat and tracker.host.shown
    and tracker.context.events.QUEST_LOG_UPDATE
    and questUpdates == beforeRaidReads + 1,
    "leaving raid combat must register events and rebuild current objectives")
combatLocked = true
tracker.context.events.PLAYER_REGEN_DISABLED(tracker, "PLAYER_REGEN_DISABLED")
insideRaid, instanceKind = false, "none"
tracker.context.events.PLAYER_ENTERING_WORLD(tracker, "PLAYER_ENTERING_WORLD")
assert(not tracker.pausedForRaidCombat and tracker.context.events.QUEST_LOG_UPDATE,
    "leaving a raid instance in combat must wake the tracker")
combatLocked = false
tracker.config.pauseInRaidCombat = false
tracker:Refresh()
insideRaid, instanceKind, combatLocked = true, "raid", true
tracker.context.events.PLAYER_REGEN_DISABLED(tracker, "PLAYER_REGEN_DISABLED")
assert(not tracker.pausedForRaidCombat and tracker.context.events.QUEST_LOG_UPDATE,
    "an off toggle must leave raid combat tracker updates enabled")
combatLocked = false
if flavor == "Mainline" then
    local raidTicker
    C_Timer.NewTicker = function(interval, callback)
        assert(interval == 1, "raid clock must tick once per second")
        raidTicker = { callback = callback }
        function raidTicker:Cancel() self.cancelled = true end
        function raidTicker:Fire() if not self.cancelled then self.callback() end end
        return raidTicker
    end
    local activeBoss = "First Guardian"
    UnitExists = function(unit) return unit == "boss1" and activeBoss == "First Guardian"
        or unit == "boss2" and activeBoss == "Second Guardian" end
    UnitName = function() return activeBoss end
    UnitHealthPercent = function() return 70 end
    local dbmStage, bigWigsStage, unboundDBM, unboundBigWigs
    local initialDBMStage = true
    DBM = {
        GetStage = function() if initialDBMStage then return 1, 1, 800 end end,
        RegisterCallback = function(_, event, callback)
            assert(event == "DBM_SetStage")
            dbmStage = callback
        end,
        UnregisterCallback = function(_, event, callback)
            assert(event == "DBM_SetStage" and callback == dbmStage)
            unboundDBM = true
        end,
    }
    BigWigsLoader = {
        RegisterMessage = function(_, event, callback)
            assert(event == "BigWigs_SetStage")
            bigWigsStage = callback
        end,
        UnregisterMessage = function(_, event)
            assert(event == "BigWigs_SetStage")
            unboundBigWigs = true
        end,
    }
    moduleStates.objectives.raidRecords = {
        ["900:16"] = {
            best = { defeated = 0, remaining = .16, boss = "Zul'jan" },
            bestPhases = { BigWigs = { stage = 1, step = 1, remaining = .16, boss = "Zul'jan" } },
        },
    }
    tracker.config.showRaid = true
    tracker.config.pauseInRaidCombat = true
    tracker:Refresh()
    assert(tracker.raidActive and tracker.title.text == "RAID"
        and tracker.raid.name.text == "Waiting for raid encounter",
        "raid option must provide its own objective HUD view")
    assert(tracker.raid.records["900:16"].best.remaining == 16
        and tracker.raid.records["900:16"].bestPhases.BigWigs.remaining == 16,
        "stored fractional wipe health must migrate to display percent")
    tracker:Refresh()
    assert(tracker.raid.records["900:16"].best.remaining == 16,
        "wipe health migration must run only once")
    combatLocked = true
    tracker.context.events.PLAYER_REGEN_DISABLED(tracker, "PLAYER_REGEN_DISABLED")
    assert(not tracker.pausedForRaidCombat and tracker.raidActive,
        "raid view must stay visible when objective pause is enabled")
    clock = 200
    tracker.context.events.ENCOUNTER_START(tracker, "ENCOUNTER_START", 800, "Twin Guardians", 16, 20)
    assert(tracker.raid.pull and tracker.raid.name.text == "Twin Guardians"
        and tracker.count.text == "Mythic"
        and tracker.raid.current.text:find("First Guardian 70.0%%", 1, false)
        and tracker.context.events.UNIT_HEALTH and raidTicker and dbmStage and bigWigsStage,
        "raid pull must show its boss and subscribe to live health only while active")
    assert(tracker.raid.phase.text == "PHASE  1  ·  DBM",
        "raid view must recover a stage that DBM reported before ENCOUNTER_START")
    dbmStage("DBM_SetStage", {}, "test-mod", 1, 800, 1)
    dbmStage("DBM_SetStage", {}, "test-mod", 2, 800, 2)
    assert(tracker.raid.phase.text == "PHASE  2  ·  DBM",
        "same-boss stage transition must come from the encounter module")
    clock = 211
    raidTicker:Fire()
    assert(tracker.raid.elapsed.text == "0:11", "raid clock did not advance")
    local bossUnits = tracker.context.eventUnits.UNIT_HEALTH
    assert(type(bossUnits) == "table" and #bossUnits == 5 and bossUnits[1] == "boss1" and bossUnits[5] == "boss5",
        "live boss health must subscribe to the five boss tokens, not every raid member")
    -- Health ticks only move the boss row: several ticks share one deferred
    -- redraw, and a raid member's tick never reaches the view.
    local livePercent, pendingCallbacks = 70, #scheduled
    UnitHealthPercent = function() return livePercent end
    tracker.context.events.UNIT_HEALTH(tracker, "UNIT_HEALTH", "raid7")
    assert(#scheduled == pendingCallbacks, "a raid member's health tick reached the raid view")
    for _, value in ipairs({ 60, 55, 50 }) do
        livePercent = value
        tracker.context.events.UNIT_HEALTH(tracker, "UNIT_HEALTH", "boss1")
    end
    assert(#scheduled == pendingCallbacks + 1 and tracker.raid.live[1].percent == 50
        and tracker.raid.current.text:find("First Guardian 70.0%%", 1, false),
        "boss health ticks must update the data at once and share one deferred redraw")
    table.remove(scheduled)()
    assert(tracker.raid.current.text:find("First Guardian 50.0%%", 1, false),
        "the deferred redraw did not show the latest boss health")
    UnitHealthPercent = function() return secret end
    tracker.context.events.UNIT_HEALTH(tracker, "UNIT_HEALTH", "boss1")
    assert(not tracker.raid.live[1].percent,
        "secret boss health must never be compared, formatted or stored")
    clock = 220
    tracker.context.events.ENCOUNTER_END(tracker, "ENCOUNTER_END", 800, "Twin Guardians", 16, 20, 0,
        { { creatureName = "First Guardian", remainingHealthPercent = .16 } })
    assert(raidTicker.cancelled and not tracker.context.events.UNIT_HEALTH
        and tracker.raid.records["800:16"].best.remaining == 16
        and tracker.raid.records["800:16"].bestPhases.DBM.stage == 2
        and tracker.raid.current.text:find("16.0%", 1, true)
        and tracker.raid.best.text:find("16.0%", 1, true),
        "first wipe must display 0.16 encounter-end health as 16.0 percent")
    initialDBMStage = false
    activeBoss = "Second Guardian"
    clock = 230
    tracker.context.events.ENCOUNTER_START(tracker, "ENCOUNTER_START", 800, "Twin Guardians", 16, 20)
    dbmStage("DBM_SetStage", {}, "test-mod", 3, 800, 3)
    bigWigsStage("BigWigs_SetStage", { IsEncounterID = function(_, id) return id == 800 end }, 4)
    tracker.context.events.INSTANCE_ENCOUNTER_ENGAGE_UNIT(tracker, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    assert(tracker.raid.current.text:find("Second Guardian", 1, true)
        and tracker.raid.phase.text == "PHASE  3  ·  DBM",
        "a later boss phase must replace the active boss row")
    clock = 250
    tracker.context.events.ENCOUNTER_END(tracker, "ENCOUNTER_END", 800, "Twin Guardians", 16, 20, 0,
        { { creatureName = "First Guardian", remainingHealthPercent = 0 },
          { creatureName = "Second Guardian", remainingHealthPercent = .75 } })
    local best = tracker.raid.records["800:16"].best
    assert(best.defeated == 1 and best.remaining == 75 and best.boss == "Second Guardian",
        "a later phase must beat an earlier boss at 16 percent")
    assert(tracker.raid.records["800:16"].bestPhases.DBM.stage == 3
        and tracker.raid.best.text:find("PHASE 3", 1, true),
        "a later phase of the same boss must beat an earlier phase at 16 percent")
    clock = 251
    tracker.context.events.ENCOUNTER_START(tracker, "ENCOUNTER_START", 800, "Twin Guardians", 16, 20)
    bigWigsStage("BigWigs_SetStage", { IsEncounterID = function(_, id) return id == 800 end }, 4)
    clock = 256
    tracker.context.events.ENCOUNTER_END(tracker, "ENCOUNTER_END", 800, "Twin Guardians", 16, 20, 0,
        { { creatureName = "First Guardian", remainingHealthPercent = .60 },
          { creatureName = "Second Guardian", remainingHealthPercent = .50 } })
    assert(tracker.raid.records["800:16"].bestPhases.BigWigs.stage == 4
        and tracker.raid.records["800:16"].bestPhases.BigWigs.remaining == 50
        and tracker.raid.records["800:16"].bestPhases.DBM.stage == 3,
        "a phased-out boss must not replace the current boss percent in phase records")
    clock = 260
    tracker.context.events.ENCOUNTER_START(tracker, "ENCOUNTER_START", 800, "Twin Guardians", 16, 20)
    clock = 285
    tracker.context.events.ENCOUNTER_END(tracker, "ENCOUNTER_END", 800, "Twin Guardians", 16, 20, 1, {})
    assert(tracker.raid.records["800:16"].fastest == 25,
        "successful encounter must save fastest kill time")
    combatLocked = false
    tracker.context.events.PLAYER_REGEN_ENABLED(tracker, "PLAYER_REGEN_ENABLED")
    tracker.config.showRaid = false
    tracker:Refresh()
    assert(not tracker.raidActive and not tracker.raid.frame.shown
        and tracker.rows["entry:quests:43"].shown and unboundDBM and unboundBigWigs,
        "disabling raid view must restore objectives without losing records")
end
tracker:Disable()
Drain()
tracker.context:RestoreProperty(ObjectiveTrackerFrame, "SetParent")
assert(ObjectiveTrackerFrame:GetParent() == UIParent,
    "disabling the MSUF tracker must restore Blizzard's original parent")
for _, frame in ipairs(frames) do assert(frame.OnUpdate == nil, "HUD registered an OnUpdate") end
print("Suite HUD: owned frames, full objectives, clicks, timers, collapse, row reuse and movers passed: " .. flavor)
