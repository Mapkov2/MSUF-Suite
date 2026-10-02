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
    function w:GetWidth() return self.width or 0 end
    function w:GetHeight() return self.height or 0 end
    function w:SetHeight(a) self.height = a end
    function w:SetScale(a) self.scale = a end
    function w:GetScale() return self.scale or 1 end
    function w:SetFrameStrata() end
    function w:EnableMouse(value) self.mouse = value end
    function w:IsMouseEnabled() return self.mouse ~= false end
    function w:EnableMouseWheel() end
    function w:RegisterForClicks(...) self.registeredClicks = { ... } end
    function w:SetScript(key, fn) self[key] = fn end
    function w:HookScript(key, fn)
        local inherited = self[key]
        self[key] = function(...)
            if inherited then inherited(...) end
            fn(...)
        end
    end
    function w:SetAttribute(key, value)
        self.attributes = self.attributes or {}
        self.attributes[key] = value
    end
    function w:GetAttribute(key) return self.attributes and self.attributes[key] end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetTexture(value) self.texture = value end
    function w:SetAtlas(value) self.atlas = value end
    function w:SetTexCoord() end
    function w:SetText(text)
        assert(not self.fontString or self.font, "FontString text assigned before font")
        self.text = text
    end
    function w:SetTextColor(...) self.textColor = { ... } end
    -- A C sink: it may receive secret values, which the stand-in only keeps.
    function w:SetFormattedText(format, ...)
        assert(not self.fontString or self.font, "FontString text assigned before font")
        self.text, self.format, self.formatArgs = nil, format, { n = select("#", ...), ... }
    end
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
    function w:SetValue(value) self.value = value end
    function w:SetScrollChild() end
    function w:GetVerticalScrollRange() return 0 end
    function w:GetVerticalScroll() return 0 end
    function w:SetVerticalScroll() end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(value) self.shown = value end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    return w
end
UIParent = Widget()
CreateFrame = function(_, name, parent, template)
    local frame = Widget(parent)
    frame.template = template
    if template == "InsecureActionButtonTemplate" then
        -- The client template handles the action before addon post-hooks:
        -- a click on another button, a macro or the item.
        frame.OnClick = function(button, mouseButton)
            local action = button:GetAttribute("type")
            if action == "click" then
                button:GetAttribute("clickbutton"):Click(mouseButton or "LeftButton")
                return
            elseif action == "macro" then
                button.secureMacro = button:GetAttribute("macrotext")
                return
            end
            if (mouseButton == nil or mouseButton == "LeftButton")
                and not IsModifiedClick("QUESTWATCHTOGGLE") and not IsShiftKeyDown() then
                button.secureUsedItem = button:GetAttribute("item1")
            end
        end
    elseif template == "UIWidgetContainerTemplate" then
        function frame:RegisterForWidgetSet(id)
            if self.widgetSetID == id then return end
            self.widgetSetID = id
            self.registrations = (self.registrations or 0) + 1
            self:SetSize(id and 250 or 0, id and 80 or 0)
        end
        function frame:HasAnyWidgetsShowing() return self.widgetSetID ~= nil end
    end
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
-- Insecure calls of these would taint the LFG list (ObjectivesActions.lua).
PVEFrame_ShowFrame = function() openedFinder = openedFinder and openedFinder + 1 or 1 end
LFGListUtil_FindQuestGroup = function(id) foundQuest = id end
PVEFrame = Widget(UIParent)
PVEFrame:Hide()
local shownPanel
ShowUIPanel = function(frame) shownPanel = frame end
QuestObjectiveFindGroupButtonMixin = { SetUp = function(self, id) self:SetAttribute("questID", id) end }
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
QUEST_WATCH_CLICK_TO_COMPLETE = "(click to complete)"
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
-- The translation lookup (MSUF_Suite_Modules/Runtime.lua); English here.
S.Text = function(value) return value end
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
-- MSUF_Suite/Core/Platform.lua: Dispatch(Finish, fn, ...) tells a call that
-- raised (nothing returned) from one that returned nothing.
suite.Finish = function(callback, ...) return true, callback(...) end
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
-- Splits and raid records belong to the character (MSUF_Suite/Core/CharacterData.lua).
local characterData = {}
S.CharacterData = function(id) characterData[id] = characterData[id] or {}; return characterData[id] end
MutedHost = Widget(UIParent)
-- The shipped context timers (MSUF_Suite_Modules/Timers.lua) on a stub
-- context of module id.
local TimerContext
local function Context(id, module)
    local ctx = TimerContext(id, module, { events = {}, eventUnits = {}, hidden = {}, saved = {}, muted = {} })
    function ctx:Event(event, callback, _, unit) self.events[event], self.eventUnits[event] = callback, unit end
    function ctx:RemoveEvent(event) self.events[event] = nil end
    function ctx:Skin() return nil end
    function ctx:HideControl(frame, value) self.hidden[frame] = value end
    -- Like MSUF_Suite_Modules/Runtime.lua: the first value seen is the one
    -- to restore.
    function ctx:Property(frame, getter, setter, value)
        local saved = self.saved[frame] or {}
        self.saved[frame] = saved
        if saved[setter] == nil then saved[setter] = frame[getter](frame) end
        frame[setter](frame, value)
    end
    function ctx:Scale(frame, value) self:Property(frame, "GetScale", "SetScale", value) end
    -- Runtime.lua mutes a native frame under a shown, invisible host; it works
    -- in combat because only unprotected frames are muted.
    function ctx:Mute(frame)
        self.muted[frame] = self.muted[frame] or frame:GetParent()
        frame:SetParent(MutedHost)
        return true
    end
    function ctx:Unmute(frame)
        if self.muted[frame] and frame:GetParent() == MutedHost then frame:SetParent(self.muted[frame]) end
        self.muted[frame] = nil
    end
    ctx.HideUnprotected = ctx.HideControl
    function ctx:RestoreProperty(frame, setter)
        local saved = self.saved[frame]
        if saved and saved[setter] ~= nil then
            frame[setter](frame, saved[setter])
            saved[setter] = nil
        end
    end
    return ctx
end
-- The HUD files load in TOC order and share the runtime's private table.
-- The shared module helpers (S.ClockText, S.PublicField) come from the real
-- Surfaces.lua; this contract keeps its own frame and font stand-ins.
do
    local stubs = {}
    for _, key in ipairs({ "CreateFrame", "CreateTexture", "CreateFontString", "SetStyledFont", "RGB",
        "ResolveFont", "GlobalFontPath" }) do stubs[key] = S[key] end
    suite.Public, suite.Finite, suite.Number = S.Public, S.Finite, S.Number
    suite.RGB, suite.ResolveFont, suite.GlobalFontPath = S.RGB, S.ResolveFont, S.GlobalFontPath
    MSUFSuite = suite
    assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})
    for key, value in pairs(stubs) do S[key] = value end
end
suite.Dispatch = S.Dispatch
TimerContext = dofile(root .. "/tools/tests/suite_test_support.lua").ModuleTimers(root, S, suite)
local private = { NS = suite, Suite = S }
for _, file in ipairs({ "MythicPlusPull", "MythicPlus", "Raid", "ObjectivesData", "ObjectivesDetails", "ObjectivesActions", "ObjectivesTracker", "Objectives", "Announcements" }) do
    assert(loadfile(root .. "/MSUF_Suite_Modules/" .. file .. ".lua"))("MSUF_Suite_Modules", private)
end
local tracker = S.instances.objectives
tracker.context = Context("objectives", tracker)
tracker.config = { width = 310, height = 570, scale = 100, x = -40, y = -240,
    showWorldQuests = true, showBonus = true, showAchievements = true, showScenario = true }
-- Blizzard's tracker is a right-managed Edit Mode frame: a SetParent or Hide
-- from addon code runs its OnHide (RemoveManagedFrame and the container
-- layout that also places the protected boss frames) inside that call.
ObjectiveTrackerFrame = Widget(UIParent)
do
    local native = ObjectiveTrackerFrame
    function native:SetParent() error("the Suite reparented Blizzard's managed objective tracker") end
    function native:Hide() error("the Suite hid Blizzard's managed objective tracker") end
end
local function NativeTrackerSuppressed()
    return tracker.context.hidden[ObjectiveTrackerFrame] == true and ObjectiveTrackerFrame:GetScale() < .01
        and ObjectiveTrackerFrame:GetParent() == UIParent
end
tracker:Enable()
assert(NativeTrackerSuppressed(),
    "native objective tracker must lose alpha, mouse and hit area without a parent change")
-- The right container sets the alpha back when the UI is shown again.
ObjectiveTrackerFrame:SetScale(1)
tracker.context.events.GROUP_ROSTER_UPDATE(tracker, "GROUP_ROSTER_UPDATE")
assert(NativeTrackerSuppressed(), "raid roster changes must restore native tracker suppression")
local combatLocked = false
suite.IsCombatLocked = function() return combatLocked end
-- MSUF_Suite/Core/Platform.lua: the combat edge events decide by themselves.
suite.InCombat = function(event)
    if event == "PLAYER_REGEN_DISABLED" then return true end
    if event == "PLAYER_REGEN_ENABLED" then return false end
    return combatLocked
end
combatLocked = true
ObjectiveTrackerFrame:SetScale(1)
tracker.context.events.GROUP_ROSTER_UPDATE(tracker, "GROUP_ROSTER_UPDATE")
assert(ObjectiveTrackerFrame:GetScale() == 1,
    "protected combat transitions must defer native tracker changes")
combatLocked = false
tracker.context.events.PLAYER_REGEN_ENABLED(tracker, "PLAYER_REGEN_ENABLED")
assert(NativeTrackerSuppressed(), "native tracker must be hidden after combat ends")
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
SCENARIO_STAGE_STATUS = "Stage %d of %d"
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
    and tracker.rows["line:scenario:0:1"].mouse
    and tracker.rows["line:scenario:0:1"].text.text == "Stage 1 of 2: Stage one",
    "achievement and scenario objectives must be interactive rows")
C_Scenario.GetStepInfo = function()
    return "Void Cleansing", "Kill the Void-Enraged beasts.", 2, nil, nil, nil, nil, nil, nil, 37.5
end
C_ScenarioInfo.GetCriteriaInfo = function() error("step-wide progress must replace criteria") end
tracker.context.events.SCENARIO_UPDATE(tracker, "SCENARIO_UPDATE")
Drain()
local stageProgress = tracker.rows["line:scenario:0:2"]
assert(stageProgress and stageProgress.text.text == "Kill the Void-Enraged beasts.  38%"
    and stageProgress.progress.shown and stageProgress.progress.value == 37.5
    and not tracker.rows["line:scenario:0:3"],
    "first scenario stage omitted its native weighted percentage")
C_Scenario.GetStepInfo = function()
    return "Void Cleansing", "Kill the Void-Enraged beasts.", 2, nil, nil, nil, nil, nil, nil, 0
end
tracker.context.events.SCENARIO_UPDATE(tracker, "SCENARIO_UPDATE")
Drain()
assert(stageProgress.text.text == "Kill the Void-Enraged beasts.  0%"
    and stageProgress.progress.shown and stageProgress.progress.value == 0,
    "the first stage must show a real zero-percent progress bar")
C_Scenario.GetStepInfo = function() return "Make Way", "Unbind the sentries.", 2 end
C_ScenarioInfo.GetCriteriaInfo = function(index)
    if index == 1 then return { description = "Sentry activated", quantity = 1, totalQuantity = 3 } end
    return { description = "Void Forces cleared", quantity = 40, isWeightedProgress = true }
end
tracker.context.events.SCENARIO_UPDATE(tracker, "SCENARIO_UPDATE")
Drain()
assert(tracker.rows["line:scenario:0:1"].text.text == "Stage 1 of 2: Make Way"
    and tracker.rows["line:scenario:0:3"].text.text == "1/3 Sentry activated"
    and tracker.rows["line:scenario:0:4"].text.text == "Void Forces cleared  40%"
    and tracker.rows["line:scenario:0:4"].progress.value == 40,
    "first-stage criteria lost native counts or weighted progress")
local ordinaryWidgets = C_UIWidgetManager.GetAllWidgetsBySetID
Enum.UIWidgetVisualizationType.ScenarioHeaderDelves = 29
C_UIWidgetManager.GetAllWidgetsBySetID = function(setID)
    if setID == 888 then return { { widgetID = 902, widgetType = 29 } } end
    return ordinaryWidgets(setID)
end
C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo = function()
    return { shownState = 1 }
end
C_Scenario.GetStepInfo = function()
    return "Twilight Crypts", nil, 1, nil, nil, nil, nil, nil, nil, nil, nil, 888
end
local hostages, hostagesDone = 0, false
C_ScenarioInfo.GetCriteriaInfo = function()
    return { description = "Hostages freed", quantity = hostages, totalQuantity = 20,
        isFormatted = false, isWeightedProgress = false, completed = hostagesDone }
end
tracker.context.events.SCENARIO_UPDATE(tracker, "SCENARIO_UPDATE")
Drain()
local delveRow = tracker.rows["entry:scenario:0"]
local delveHeader = assert(delveRow.scenarioHeader)
local hostageRow = tracker.rows["line:scenario:0:2"]
assert(delveHeader.template == "UIWidgetContainerTemplate" and delveHeader.widgetSetID == 888
    and delveHeader.shown and not delveRow.text.shown and delveRow.layoutHeight >= 80
    and hostageRow.text.text == "0/20 Hostages freed",
    "Delves must retain the native header and the initial scenario count")
local headerRegistrations, beforeHostages = delveHeader.registrations, questUpdates
hostages = 1
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
Drain()
assert(hostageRow.text.text == "1/20 Hostages freed" and delveRow.scenarioHeader == delveHeader
    and delveHeader.registrations == headerRegistrations and questUpdates == beforeHostages,
    "criterion progress must update without rebuilding the native header or quest sources")
local oldHostageY = hostageRow.layoutY
delveHeader:SetHeight(110)
delveHeader.OnSizeChanged(delveHeader)
Drain()
assert(delveRow.layoutHeight >= 110 and hostageRow.layoutY > oldHostageY,
    "a changing native header height must reposition the criteria below it")
hostages, hostagesDone = 20, true
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
Drain()
assert(hostageRow.text.text == "20/20 Hostages freed"
    and hostageRow.text.textColor[2] == 1,
    "completed scenario criteria must retain their count and completion color")
delveHeader.OnHide(delveHeader)
assert(delveHeader.widgetSetID == nil, "a hidden tracker must unregister its native widget set")
delveHeader.OnShow(delveHeader)
assert(delveHeader.widgetSetID == 888, "showing the tracker must restore its active native widget set")
C_UIWidgetManager.GetAllWidgetsBySetID = ordinaryWidgets
C_Scenario.GetStepInfo = function() return "Stage one", "Do the thing", 0 end
C_ScenarioInfo.GetCriteriaInfo = function() return nil end
tracker.context.events.SCENARIO_UPDATE(tracker, "SCENARIO_UPDATE")
Drain()
assert(delveHeader.widgetSetID == nil and not delveHeader.shown and delveRow.text.shown,
    "leaving a Delve must remove the native header and restore the ordinary title")
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
banner.context = Context("announcements", banner)
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
assert(movers.announcements.element == "banner" and ZoneTextFrame:GetParent() == MutedHost)
assert(movers.announcements.spec.extraControls[1].id == "scale"
    and movers.announcements.spec.extraControls[1].set(125)
    and banner.config.scale == 125,
    "announcements popup omitted its scale control")
assert(movers.announcements.spec.extraControls[1].set(100))
assert(SubZoneTextFrame:GetParent() == MutedHost and banner.context.hidden[EventToastManagerFrame])
AchievementAlertSystem:ShowAlert()
assert(achievement:GetParent() == MutedHost, "native achievement alert must be hidden")
-- Blizzard shows alerts and toasts in combat too: suppressing them there as
-- well keeps the banner from showing the same event twice.
combatLocked = true
banner.context.hidden[EventToastManagerFrame] = nil
AchievementAlertSystem:ShowAlert()
EventToastManagerFrame:DisplayToast(nil)
combatLocked = false
assert(achievement:GetParent() == MutedHost and banner.context.hidden[EventToastManagerFrame] ~= nil,
    "combat let Blizzard's alert or toast show next to the banner")
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
assert(worldQuest:GetParent() == MutedHost
    and scenarioAlert:GetParent() == MutedHost and #banner.queue == 3,
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
banner.queue = {}
local resumedDismiss = assert(table.remove(scheduled), "Edit Mode exit did not rearm the banner timer")
resumedDismiss()
assert(banner.leave.playing, "a banner resumed from Edit Mode never started fading out")
banner.leave.OnFinished()
assert(not banner.showing and not banner.host.shown and not banner.current,
    "a resumed banner must finish and release its current announcement")
local zoneBeforeEdit, subzoneBeforeEdit = GetZoneText, GetSubZoneText
GetSubZoneText = function() return "Expired area" end
banner.context.events.ZONE_CHANGED(banner, "ZONE_CHANGED")
Drain()
S.editMode = true
banner:Refresh()
local editStart = clock
clock = clock + banner.config.duration + 1
Drain()
assert(banner.title.text == "ANNOUNCEMENTS" and banner.host.shown,
    "an old dismissal callback must not hide the Edit Mode preview")
S.editMode = false
banner:Refresh()
assert(not banner.showing and not banner.host.shown and not banner.current,
    "a banner that expired in Edit Mode must not become permanent on exit")
clock = editStart
S.editMode = true
banner:Refresh()
GetZoneText = function() return "Silvermoon City" end
GetSubZoneText = function() return "The Bazaar" end
banner.context.events.ZONE_CHANGED_NEW_AREA(banner, "ZONE_CHANGED_NEW_AREA")
Drain()
GetZoneText = function() return "Zul'Aman" end
GetSubZoneText = function() return "Broken Throne" end
banner.context.events.ZONE_CHANGED_NEW_AREA(banner, "ZONE_CHANGED_NEW_AREA")
Drain()
assert(#banner.queue == 1 and banner.queue[1].title == "Broken Throne",
    "moving during Edit Mode must replace announcements from areas already left")
S.editMode = false
banner:Refresh()
assert(banner.current.title == "Broken Throne" and banner.subtitle.text == "Zul'Aman",
    "Edit Mode exit must show the current area instead of the old Bazaar banner")
GetZoneText, GetSubZoneText = zoneBeforeEdit, subzoneBeforeEdit
banner.queue, banner.current, banner.showing = {}, nil, false
banner.host:Hide()
banner.config.scenario = true
EventToastManagerFrame:DisplayToast({ eventType = Enum.EventToastEventType.Scenario,
    eventToastID = 91, title = "Wave 2", subtitle = "New Stage" })
EventToastManagerFrame:DisplayToast({ eventType = Enum.EventToastEventType.Scenario,
    eventToastID = 92, title = "Wave 3", subtitle = "New Stage" })
assert(banner.showing and banner.title.text == "Wave 2" and #banner.queue == 1,
    "active scenario stages must still use the announcement queue")
local activeScenarioInfo = C_Scenario.GetInfo
C_Scenario.GetInfo = function() return nil end
banner.context.events.ZONE_CHANGED_NEW_AREA(banner, "ZONE_CHANGED_NEW_AREA")
assert(not banner.showing and not banner.host.shown and #banner.queue == 0,
    "leaving a scenario area kept its active or queued wave announcement")
EventToastManagerFrame:DisplayToast({ eventType = Enum.EventToastEventType.Scenario,
    eventToastID = 93, title = "Wave 3", subtitle = "New Stage" })
assert(not banner.showing and #banner.queue == 0,
    "a late scenario toast appeared after the scenario ended")
C_Scenario.GetInfo = activeScenarioInfo
EventToastManagerFrame:DisplayToast({ eventType = 25, eventToastID = 94,
    title = "Flight point discovered", subtitle = "Silvermoon" })
assert(banner.showing and banner.title.text == "Flight point discovered",
    "scenario cleanup suppressed an unrelated announcement")
-- QUEST_TURNED_IN carries questID, xpReward, moneyReward; QUEST_ACCEPTED
-- only the questID (QuestLogDocumentation.lua).
banner.config.quests, banner.queue = true, {}
banner.context.events.QUEST_TURNED_IN(banner, "QUEST_TURNED_IN", 42, 1500, 300)
assert(#banner.queue == 1 and banner.queue[1].title == "A New Hope"
    and banner.queue[1].subtitle == "QUEST COMPLETE",
    "a turned-in quest must announce its own title, not the quest named by its XP reward")
banner.config.quests, banner.queue = false, {}
for _, frame in ipairs(frames) do assert(frame.OnUpdate == nil, "HUD registered an OnUpdate") end
tracker.config.colorStyle = 1
tracker.config.backgroundOpacity = nil
tracker:Refresh()
assert(tracker.background.color[4] == 0, "standard objective tracker must have no backdrop")
local questItemLink = "item:777"
GetQuestLogSpecialItemInfo = function(index)
    if index == 42 or index == 43 then return questItemLink, 1234, 1, true end
end
UseQuestLogSpecialItem = function() error("addon called protected UseQuestLogSpecialItem") end
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
assert(activeQuest.itemButton.template == "InsecureActionButtonTemplate"
    and activeQuest.itemButton.registeredClicks[1] == "AnyDown"
    and activeQuest.itemButton.registeredClicks[2] == "AnyUp"
    and activeQuest.itemButton:GetAttribute("type1") == "item"
    and activeQuest.itemButton:GetAttribute("item1") == "item:777"
    and activeQuest.itemButton:GetAttribute("shift-type1") == ""
    and activeQuest.itemButton:GetAttribute("modifiers") == "QUESTWATCHTOGGLE:shift",
    "quest item lacks the client action template or its current item link")
activeQuest.itemButton.OnClick(activeQuest.itemButton)
assert(activeQuest.itemButton.secureUsedItem == "item:777",
    "quest item button did not retain the inherited item action")
activeQuest.itemButton.OnEnter(activeQuest.itemButton)
assert(GameTooltip.shown and GameTooltip.owner == activeQuest.itemButton and GameTooltip.item == 42,
    "the quest item button did not show its item tooltip")
activeQuest.itemButton.OnLeave(activeQuest.itemButton)
assert(not GameTooltip.shown, "leaving the quest item button kept its tooltip")
activeQuest.itemButton.OnClick(activeQuest.itemButton, "RightButton")
assert(lastMenu.title == "A New Hope" and activeQuest.itemButton.secureUsedItem == "item:777",
    "quest item right-click must open the parent quest menu")
stoppedQuest = nil
shiftDown = true
activeQuest.itemButton.secureUsedItem = nil
activeQuest.itemButton.OnClick(activeQuest.itemButton, "LeftButton")
assert(stoppedQuest == 42 and not activeQuest.itemButton.secureUsedItem,
    "Shift-left-click on the quest item must untrack instead of using it")
shiftDown = false
questItemLink = "item:778"
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
Drain()
activeQuest = tracker.rows["entry:quests:42"]
assert(activeQuest.itemButton:GetAttribute("item1") == "item:778",
    "a quest item link change with the same icon kept the stale action")
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
    -- A hardware click runs PreClick, then the template's own OnClick.
    local function Click(button)
        if button.PreClick then button.PreClick(button, "LeftButton") end
        button.OnClick(button, "LeftButton")
    end
    local groupButton = tracker.rows["entry:world:77"].findGroupButton
    assert(groupButton and groupButton.icon.atlas == "socialqueuing-icon-eye"
        and groupButton.template == "InsecureActionButtonTemplate",
        "world quests need a group finder button even without a quest activity")
    Click(groupButton)
    assert(groupButton.secureMacro == "/click LFDMicroButton\n/click PVEFrameTab1\n/click GroupFinderFrameGroupButton3"
        and not openedFinder and not foundQuest,
        "a world quest without a quest activity must open Premade Groups through Blizzard's buttons")
    PVEFrame:Show()
    Click(groupButton)
    assert(groupButton.secureMacro == "/click PVEFrameTab1\n/click GroupFinderFrameGroupButton3",
        "an open group finder must only switch to Premade Groups")
    PVEFrame:Hide()
    questActivity = 123
    -- The hidden native tracker keeps Blizzard's green-eye button per quest.
    local nativeEye = Widget(UIParent)
    nativeEye.SetUp, nativeEye.used = QuestObjectiveFindGroupButtonMixin.SetUp, true
    nativeEye:SetUp(77)
    function nativeEye:Click() self.clickedQuest = self:GetAttribute("questID") end
    WorldQuestObjectiveTracker = { usedRightEdgeFrames = { eye = nativeEye } }
    tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
    Drain()
    groupButton = tracker.rows["entry:world:77"].findGroupButton
    Click(groupButton)
    assert(nativeEye.clickedQuest == 77 and not foundQuest and not openedFinder,
        "a groupable quest must run Blizzard's own quest search")
    local worldRow = tracker.rows["entry:world:77"]
    worldRow.OnClick(worldRow, "RightButton")
    lastMenu.buttons["Open group finder"]()
    assert(shownPanel == PVEFrame and not foundQuest and not openedFinder,
        "the menu must open the group finder through the secure panel delegate")
    WorldQuestObjectiveTracker = nil
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
assert(banner.lastZone == "Dornogal/Keystone Hall" and #banner.queue <= zoneQueue,
    "keystone subzone added a zone banner")
for _, item in ipairs(banner.queue) do
    assert(item.kind ~= "zone", "keystone subzone retained a banner from an area already left")
end
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
local splitRecords = S.CharacterData("objectives")
splitRecords.mythicSplits = { ["500:15"] = { time = 1200, individual = { ["First boss"] = 380, ["Second boss"] = 990 },
    run = { ["First boss"] = 390, ["Second boss"] = 990 }, serial = 1 },
    ["500:all"] = { time = 1000, individual = { ["First boss"] = 300 }, run = { ["First boss"] = 310 }, serial = 2 } }
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
tracker.mplus.bar.OnSizeChanged(tracker.mplus.bar, 400)
assert(tracker.mplus.thresholds[1].point[4] == 240 and tracker.mplus.thresholds[2].point[4] == 320,
    "timer threshold markers must follow the actual native bar width")
-- WoW's stock fonts have no check mark glyph: a defeated boss shows Blizzard's atlas.
assert(tracker.mplus.bosses[1].name.text:find("|A:common-icon-checkmark:12:12|a", 1, true) == 1
    and not tracker.mplus.bosses[2].name.text:find("|A:", 1, true), "defeated boss mark is not the check mark atlas")
-- Boss pace: 2 best time per boss at this level, 4 fastest run at this
-- level, 5 fastest run at any level; target times only when asked for.
tracker.config.bossPace = 2
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
assert(tracker.mplus.bosses[1].time.text == "6:40  +0:20" and tracker.mplus.bosses[2].time.text == "",
    "a boss still alive showed a target time by default")
tracker.config.bossTargets = true
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
assert(tracker.mplus.bosses[1].time.text == "6:40  +0:20" and tracker.mplus.bosses[2].time.text == "16:30")
tracker.config.bossPace = 4
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
assert(tracker.mplus.bosses[1].time.text == "6:40  +0:10")
tracker.config.bossPace = 5
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
assert(tracker.mplus.bosses[1].time.text == "6:40  +1:30")
tracker.config.bossPace = 3
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
assert(tracker.mplus.bosses[1].time.text == "6:40  +1:40")
tracker.config.bossTargets = false
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
assert(tracker.mplus.bosses[2].time.text == "")
-- Every bucket of this run is held: criteria updates read no records again.
local readCharacter, characterReads = S.CharacterData, 0
S.CharacterData = function(id) characterReads = characterReads + 1; return readCharacter(id) end
tracker.context.events.SCENARIO_CRITERIA_UPDATE(tracker, "SCENARIO_CRITERIA_UPDATE")
S.CharacterData = readCharacter
assert(characterReads == 0, "boss pace read the character records again for a bucket it holds")
tracker.config.bossPace = 1
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
assert(splitRecords.mythicSplits["500:15"].time == 1100
    and splitRecords.mythicSplits["500:15"].run["Second boss"] == 1000
    and splitRecords.mythicSplits["500:15"].individual["First boss"] == 380
    and splitRecords.mythicSplits["500:all"].time == 1000)
local splitSerial = splitRecords.mythicSplitSerial
C_ChallengeMode.GetChallengeCompletionInfo = function()
    return { time = 1100000, keystoneUpgradeLevels = 3, onTime = true }
end
tracker.context.events.CHALLENGE_MODE_COMPLETED_REWARDS(tracker, "CHALLENGE_MODE_COMPLETED_REWARDS")
assert(tracker.mplus.remaining.text == "COMPLETE  +3" and ticker.cancelled,
    "late completion rewards must refresh the result without restarting the clock")
assert(splitRecords.mythicSplitSerial == splitSerial, "reward event duplicated split persistence")
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
C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
tracker.config.hideInRaid = true
insideRaid, instanceKind = true, "raid"
tracker:Refresh()
assert(tracker.pausedForRaidCombat and not tracker.host.shown and not tracker.context.events.QUEST_LOG_UPDATE,
    "entire-raid hiding must apply outside combat and suspend ordinary work")
insideRaid, instanceKind = false, "none"
tracker.context.events.ZONE_CHANGED_NEW_AREA(tracker, "ZONE_CHANGED_NEW_AREA")
assert(not tracker.pausedForRaidCombat and tracker.host.shown, "leaving the raid must restore the tracker")
tracker.config.hideInRaid, tracker.config.hideDuringBoss = false, true
insideRaid, instanceKind = true, "raid"
tracker:Refresh()
assert(not tracker.pausedForRaidCombat, "boss-only hiding must leave raid trash visible")
tracker.context.events.ENCOUNTER_START(tracker, "ENCOUNTER_START", 800, "Test", 16)
assert(tracker.pausedForRaidCombat and not tracker.host.shown, "boss start must hide independently of generic combat")
tracker.context.events.ENCOUNTER_END(tracker, "ENCOUNTER_END", 800, "Test", 16, 20, 1)
assert(not tracker.pausedForRaidCombat and tracker.host.shown, "boss end must restore the tracker")
tracker.config.hideDuringBoss, tracker.config.showHeader = false, false
tracker:Refresh()
assert(not tracker.title.shown and not tracker.count.shown and not tracker.headerClick.shown
    and tracker.headerHeight == 8, "hidden heading must release its layout space")
tracker.config.showHeader = true
tracker:Refresh()
assert(tracker.title.shown and tracker.headerClick.shown and tracker.headerHeight >= 40,
    "restoring the heading must restore its layout and click target")
insideRaid, instanceKind = false, nil
tracker.config.pauseInRaidCombat = true
tracker.config.showTimers = true
tracker:Refresh()
assert(tracker.countdownJob.pending, "visible objective timers should schedule before raid combat")
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
-- The client sends PLAYER_REGEN_DISABLED before InCombatLockdown() turns true.
insideRaid, instanceKind = true, "raid"
tracker.context.events.PLAYER_REGEN_DISABLED(tracker, "PLAYER_REGEN_DISABLED")
combatLocked = true
assert(tracker.pausedForRaidCombat and not tracker.host.shown
    and not tracker.countdownJob.pending
    and not tracker.context.events.QUEST_LOG_UPDATE
    and not tracker.context.events.SCENARIO_UPDATE
    and not tracker.context.events.GROUP_ROSTER_UPDATE
    and tracker.context.events.PLAYER_ENTERING_WORLD,
    "raid combat must hide the Suite tracker and unregister its work events")
local beforeRaidReads = questUpdates
tracker.context.events.ZONE_CHANGED_NEW_AREA(tracker, "ZONE_CHANGED_NEW_AREA")
Drain()
assert(questUpdates == beforeRaidReads and not tracker.countdownJob.pending,
    "raid combat must cancel queued tracker reads and countdown ticks")
combatLocked = false
tracker.context.events.PLAYER_REGEN_ENABLED(tracker, "PLAYER_REGEN_ENABLED")
assert(not tracker.pausedForRaidCombat and tracker.host.shown
    and tracker.context.events.QUEST_LOG_UPDATE
    and questUpdates == beforeRaidReads + 1,
    "leaving raid combat must register events and rebuild current objectives")
tracker.context.events.PLAYER_REGEN_DISABLED(tracker, "PLAYER_REGEN_DISABLED")
combatLocked = true
insideRaid, instanceKind = false, "none"
tracker.context.events.PLAYER_ENTERING_WORLD(tracker, "PLAYER_ENTERING_WORLD")
assert(not tracker.pausedForRaidCombat and tracker.context.events.QUEST_LOG_UPDATE,
    "leaving a raid instance in combat must wake the tracker")
combatLocked = false
tracker.config.pauseInRaidCombat = false
tracker:Refresh()
insideRaid, instanceKind = true, "raid"
tracker.context.events.PLAYER_REGEN_DISABLED(tracker, "PLAYER_REGEN_DISABLED")
combatLocked = true
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
    -- UnitHealthPercent returns 0..1; Blizzard's ScaleTo100 curve maps it
    -- to display percent (Blizzard_SharedXMLBase/CurveConstants.lua).
    CurveConstants = { ScaleTo100 = {} }
    local function HealthPercent(percent, curve)
        return curve == CurveConstants.ScaleTo100 and percent or percent / 100
    end
    UnitHealthPercent = function(_, _, curve) return HealthPercent(70, curve) end
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
    -- The one-time move from profiles converted old 0..1 fractions
    -- (suite_character_data_contract); the store holds display percent.
    characterData.objectives = { raidRecords = {
        ["900:16"] = {
            best = { defeated = 0, remaining = 16, boss = "Zul'jan" },
            bestPhases = { BigWigs = { stage = 1, step = 1, remaining = 16, boss = "Zul'jan" } },
        },
    } }
    tracker.config.showRaid = true
    tracker.config.pauseInRaidCombat = true
    tracker:Refresh()
    assert(tracker.raidActive and tracker.title.text == "RAID"
        and tracker.raid.name.text == "Waiting for raid encounter",
        "raid option must provide its own objective HUD view")
    assert(tracker.raid.records == characterData.objectives.raidRecords
        and tracker.raid.records["900:16"].best.remaining == 16
        and tracker.raid.records["900:16"].bestPhases.BigWigs.remaining == 16,
        "raid records must come from the character's store")
    tracker:Refresh()
    assert(tracker.raid.records["900:16"].best.remaining == 16,
        "stored raid records must never be rescaled at runtime")
    tracker.context.events.PLAYER_REGEN_DISABLED(tracker, "PLAYER_REGEN_DISABLED")
    combatLocked = true
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
    -- Health storms share one native read and one deferred redraw. Other full
    -- paints still drain pending health before showing a stage or clock update.
    local livePercent, pendingCallbacks, healthReads = 70, #scheduled, 0
    UnitHealthPercent = function(_, _, curve)
        healthReads = healthReads + 1
        return HealthPercent(livePercent, curve)
    end
    tracker.context.events.UNIT_HEALTH(tracker, "UNIT_HEALTH", "raid7")
    assert(#scheduled == pendingCallbacks, "a raid member's health tick reached the raid view")
    for _, value in ipairs({ 60, 55, 50 }) do
        livePercent = value
        tracker.context.events.UNIT_HEALTH(tracker, "UNIT_HEALTH", "boss1")
    end
    assert(#scheduled == pendingCallbacks + 1 and healthReads == 0
        and tracker.raid.current.text:find("First Guardian 70.0%%", 1, false),
        "boss health events fetched snapshots before their shared redraw")
    table.remove(scheduled)()
    assert(healthReads == 1 and tracker.raid.live[1].percent == 50
        and tracker.raid.current.text:find("First Guardian 50.0%%", 1, false),
        "the deferred redraw did not show the latest boss health")
    pendingCallbacks=#scheduled
    tracker.context.events.UNIT_HEALTH(tracker,"UNIT_HEALTH","boss1")
    collectgarbage("collect");collectgarbage("stop")
    local healthMemory=collectgarbage("count")
    for _=1,1000 do tracker.context.events.UNIT_HEALTH(tracker,"UNIT_HEALTH","boss1") end
    local healthAllocated=collectgarbage("count")-healthMemory
    collectgarbage("restart")
    assert(healthAllocated<1,"raid health storms allocated per event")
    assert(#scheduled==pendingCallbacks+1 and healthReads==1,"a health storm repeated native reads")
    -- Budget of one boss health event while the live redraw is due (shipped
    -- code only; measured 2026-10-02 on the hand-rolled pending flag, +2 %).
    local healthInstructions = 0
    debug.sethook(function()
        local source = debug.getinfo(2, "S").source:gsub("\\", "/")
        if source:find("/MSUF_Suite[%w_]*/") and not source:find("/tools/", 1, true) then
            healthInstructions = healthInstructions + 1
        end
    end, "", 1)
    tracker.context.events.UNIT_HEALTH(tracker, "UNIT_HEALTH", "boss1")
    debug.sethook()
    local HEALTH_BUDGET = 22
    assert(healthInstructions <= math.floor(HEALTH_BUDGET * 1.02),
        "a boss health event cost " .. healthInstructions .. " instructions, budget " .. HEALTH_BUDGET)
    livePercent=40;raidTicker:Fire()
    assert(healthReads==2 and tracker.raid.current.text:find("First Guardian 40.0%%"),
        "the clock paint did not drain the latest pending health")
    table.remove(scheduled)()
    assert(healthReads==2,"an already drained boss was fetched again")
    UnitHealthPercent = function() return secret end
    tracker.context.events.UNIT_HEALTH(tracker, "UNIT_HEALTH", "boss1")
    table.remove(scheduled)()
    local current = tracker.raid.current
    assert(not tracker.raid.live[1].percent and current.format == "ACTIVE BOSSES  First Guardian %.1f%%"
        and current.formatArgs.n == 1 and current.formatArgs[1] == secret,
        "secret boss health must reach only SetFormattedText, never Lua formatting or comparisons")
    raidTicker:Fire()
    assert(current.format and current.formatArgs[1] == secret,
        "the one-second paint must keep secret boss health in its C sink")
    UnitHealthPercent = function(_, _, curve) return HealthPercent(35, curve) end
    tracker.context.events.UNIT_HEALTH(tracker, "UNIT_HEALTH", "boss1")
    table.remove(scheduled)()
    assert(current.text and current.text:find("First Guardian 35.0%", 1, true),
        "readable boss health must return to plain text after a secret reading")
    tracker.context.events.UNIT_HEALTH(tracker,"UNIT_HEALTH","boss1")
    local existsBeforeEnd=UnitExists
    UnitExists=function() return false end
    clock = 220
    tracker.context.events.ENCOUNTER_END(tracker, "ENCOUNTER_END", 800, "Twin Guardians", 16, 20, 0,
        { { creatureName = "First Guardian", remainingHealthPercent = .16 },
          { creatureName = "Previous Phase", remainingHealthPercent = .9 } })
    assert(raidTicker.cancelled and not tracker.context.events.UNIT_HEALTH
        and tracker.raid.records["800:16"].best.remaining == 16
        and tracker.raid.records["800:16"].bestPhases.DBM.stage == 2
        and tracker.raid.current.text:find("16.0%", 1, true)
        and tracker.raid.best.text:find("16.0%", 1, true),
        "first wipe must display 0.16 encounter-end health as 16.0 percent")
    UnitExists=function() error("a stopped raid callback fetched boss data") end
    table.remove(scheduled)()
    UnitExists=existsBeforeEnd
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
    -- A raising boss mod is reported through Dispatch and never stops the
    -- encounter view; its stage stays unknown.
    local reportedBefore = #reported
    DBM.GetStage = function() error("DBM stage API changed") end
    clock = 300
    tracker.context.events.ENCOUNTER_START(tracker, "ENCOUNTER_START", 800, "Twin Guardians", 16, 20)
    assert(tracker.raid.pull and tracker.raid.phase.text == "PHASE  --" and #reported == reportedBefore + 1
        and raidTicker and not raidTicker.cancelled, "a raising DBM stage read stopped the encounter start")
    bigWigsStage("BigWigs_SetStage", { IsEncounterID = function() error("BigWigs module API changed") end }, 2)
    assert(tracker.raid.phase.text == "PHASE  --" and #reported == reportedBefore + 2,
        "a raising BigWigs module changed the stage or its error escaped")
    BigWigs = { IterateBossModules = function()
        return function(_, key) if not key then return 1, { IsEncounterID = function() error("broken") end } end end
    end }
    clock = 320
    tracker.context.events.ENCOUNTER_END(tracker, "ENCOUNTER_END", 800, "Twin Guardians", 16, 20, 0, {})
    tracker.context.events.ENCOUNTER_START(tracker, "ENCOUNTER_START", 800, "Twin Guardians", 16, 20)
    assert(tracker.raid.pull and #reported == reportedBefore + 4,
        "a raising BigWigs module during the initial stage read stopped the encounter start")
    BigWigs = nil
    clock = 330
    tracker.context.events.ENCOUNTER_END(tracker, "ENCOUNTER_END", 800, "Twin Guardians", 16, 20, 0, {})
    combatLocked = false
    tracker.context.events.PLAYER_REGEN_ENABLED(tracker, "PLAYER_REGEN_ENABLED")
    tracker.config.showRaid = false
    tracker:Refresh()
    assert(not tracker.raidActive and not tracker.raid.frame.shown
        and tracker.rows["entry:quests:43"].shown and unboundDBM and unboundBigWigs,
        "disabling raid view must restore objectives without losing records")
end
-- Community Engagement (95413) completes from the tracker without an NPC.
-- Keep reward selection in Blizzard's dialog; only completed auto quests use
-- that action, and clicks must re-read state instead of trusting a painted row.
local autoComplete, questComplete = true, true
C_QuestLog.GetQuestIDForQuestWatchIndex = function() return 95413 end
C_QuestLog.GetTitleForQuestID = function() return "Community Engagement" end
C_QuestLog.GetQuestObjectives = function()
    return { { text = "1/1 Buy an item from an endeavor trader", type = "monster", finished = questComplete } }
end
C_QuestLog.GetLogIndexForQuestID = function(id) return id == 95413 and 1 or nil end
C_QuestLog.GetInfo = function(index) return index == 1 and { isAutoComplete = autoComplete } or nil end
C_QuestLog.IsComplete = function(id) return id == 95413 and questComplete or false end
local completionActions, offeredRewards = {}, nil
-- The tracker method also marks Blizzard's tracker dirty in the caller's
-- code; the client function only removes the popup.
QuestObjectiveTracker = { RemoveAutoQuestPopUp = function()
    error("the Suite called Blizzard's tracker method from addon code")
end }
RemoveAutoQuestPopUp = function(id)
    completionActions[#completionActions + 1] = "remove:" .. id
end
ShowQuestComplete = function(id)
    completionActions[#completionActions + 1] = "show:" .. id
    offeredRewards = id
end
assert(tracker.context.events.QUEST_AUTOCOMPLETE, "auto-completion event is not registered")
Drain()
local pendingCompletion = #scheduled
for _ = 1, 3 do tracker.context.events.QUEST_AUTOCOMPLETE(tracker, "QUEST_AUTOCOMPLETE", 95413) end
assert(#scheduled == pendingCompletion + 1, "completion burst did not coalesce into one refresh")
Drain()
local completedRow = assert(tracker.rows["entry:complete:95413"])
local completeLine = assert(tracker.rows["line:complete:95413:2"])
assert(completeLine.text.text == QUEST_WATCH_CLICK_TO_COMPLETE and completeLine.shown,
    "completed auto quest lacks Blizzard's click-to-complete hint")
local logBeforeComplete = openedLog
completedRow.OnClick(completedRow, "LeftButton")
assert(offeredRewards == 95413 and openedLog == logBeforeComplete
    and completionActions[1] == "remove:95413" and completionActions[2] == "show:95413",
    "auto quest opened the map instead of Blizzard's reward dialog")
offeredRewards = nil
completeLine.OnClick(completeLine, "LeftButton")
assert(offeredRewards == 95413 and openedLog == logBeforeComplete,
    "objective line did not open its auto quest's reward dialog")
offeredRewards, stoppedQuest = nil, nil
shiftDown = true
completedRow.OnClick(completedRow, "LeftButton")
shiftDown = false
assert(stoppedQuest == 95413 and not offeredRewards and openedLog == logBeforeComplete,
    "Shift-click completed an auto quest instead of untracking it")
completedRow.OnClick(completedRow, "RightButton")
lastMenu.buttons["View in Quest Log"]()
assert(not offeredRewards and openedQuest == 95413 and openedLog == logBeforeComplete + 1,
    "explicit quest-details menu action opened reward selection")
autoComplete = false
completedRow.OnClick(completedRow, "LeftButton")
assert(not offeredRewards and openedLog == logBeforeComplete + 2,
    "completed NPC quest incorrectly used automatic turn-in")
autoComplete, questComplete = true, false
completedRow.OnClick(completedRow, "LeftButton")
assert(not offeredRewards and openedLog == logBeforeComplete + 3,
    "stale completed row offered rewards for an incomplete auto quest")
questComplete = secret
assert(not private.Objectives.CanCompleteQuest(95413), "secret completion enabled automatic turn-in")
questComplete, autoComplete = true, secret
assert(not private.Objectives.CanCompleteQuest(95413), "secret auto-completion flag enabled turn-in")
C_QuestLog.GetInfo = function() return secret end
assert(not private.Objectives.CanCompleteQuest(95413), "secret quest metadata enabled turn-in")
C_QuestLog.GetInfo = function() return nil end
assert(not private.Objectives.CanCompleteQuest(95413), "missing quest metadata enabled turn-in")
C_QuestLog.GetLogIndexForQuestID = function() return nil end
assert(not private.Objectives.CanCompleteQuest(95413), "removed quest enabled turn-in")
tracker.context.events.QUEST_LOG_UPDATE(tracker, "QUEST_LOG_UPDATE")
Drain()
assert(tracker.sources.quests[1].lines.count == 1 and not completeLine.shown,
    "reused completed rows retained a stale turn-in hint")
tracker:Disable()
Drain()
tracker.context:RestoreProperty(ObjectiveTrackerFrame, "SetScale")
assert(ObjectiveTrackerFrame:GetScale() == 1 and ObjectiveTrackerFrame:GetParent() == UIParent,
    "disabling the MSUF tracker must restore Blizzard's original scale")
for _, frame in ipairs(frames) do assert(frame.OnUpdate == nil, "HUD registered an OnUpdate") end
print("Suite HUD: owned frames, full objectives, clicks, timers, collapse, row reuse and movers passed: " .. flavor)
