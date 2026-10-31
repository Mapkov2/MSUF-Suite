local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
assert(flavor == "Mainline" or flavor == "Forever")
local forever = flavor == "Forever"
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local clock = Support.Clock(1000)

-- The Suite's objective tracker must draw what Blizzard's tracker lists in the
-- modules the first sources missed: the Traveler's Log, Endeavors, the
-- Adventure Guide's tracked collectibles and the zone's widget block. Each
-- source draws its entries, hides when nothing is tracked, refreshes on its
-- events only, follows its show setting and exists only where the client has
-- the content.

------------------------------------------------------------------ frame stand-ins
local function Widget(parent, fontString)
    local w = { parent = parent, shown = true, fontString = fontString }
    function w:CreateTexture() return Widget(self) end
    function w:CreateFontString() return Widget(self, true) end
    function w:GetParent() return self.parent end
    function w:SetParent(newParent) self.parent = newParent end
    function w:SetPoint() end
    function w:ClearAllPoints() end
    function w:SetAllPoints() end
    function w:SetSize(a, b) self.width, self.height = a, b end
    function w:SetWidth(a) self.width = a end
    function w:GetWidth() return self.width or 0 end
    function w:GetHeight() return self.height or 0 end
    function w:SetHeight(a) self.height = a end
    function w:SetScale(a) self.scale = a end
    function w:GetScale() return self.scale or 1 end
    function w:SetAlpha(value) self.alpha = value end
    function w:SetFrameStrata() end
    function w:EnableMouse(value) self.mouse = value end
    function w:EnableMouseWheel() end
    function w:RegisterForClicks() end
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
    function w:SetColorTexture() end
    function w:SetTexture() end
    function w:SetAtlas() end
    function w:SetTexCoord() end
    function w:SetText(text)
        assert(not self.fontString or self.font, "FontString text assigned before font")
        self.text = text
    end
    function w:SetTextColor() end
    function w:SetJustifyH() end
    function w:SetWordWrap() end
    function w:SetFont(_, size) self.font = true; self.fontSize = size; return true end
    function w:GetStringHeight() return (self.fontSize or 12) + 2 end
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
    function w:IsShown() return self.shown end
    return w
end
UIParent = Widget()
CreateFrame = function(_, _, parent, template)
    local frame = Widget(parent)
    if template == "InsecureActionButtonTemplate" then
        -- The client template handles the action before addon post-hooks.
        frame.OnClick = function(button, mouseButton)
            local action = button:GetAttribute("type")
            if action == "click" then button:GetAttribute("clickbutton"):Click(mouseButton or "LeftButton") end
        end
    elseif template == "UIWidgetContainerTemplate" then
        function frame:RegisterForWidgetSet(id)
            self.widgetSetID = id
            self:SetSize(id and 250 or 0, id and 80 or 0)
        end
        function frame:HasAnyWidgetsShowing() return self.widgetSetID ~= nil end
    end
    return frame
end

------------------------------------------------------------------ client stand-ins
-- What the client currently reports; the tests change it and fire events.
local world = {
    log = {}, tasks = {}, trackingEnabled = true, types = { 0, 1, 3 }, tracked = { [0] = {}, [1] = {}, [3] = {} },
    targets = {}, widgetSet = 4321, widgetsShowing = false, zone = "Dornogal",
}
local reads = { log = 0, tasks = 0, collect = 0, achievements = 0, zone = 0 }
local opened, removed, lastMenu = {}, {}, nil
local combat, gamepad, watchToggle = false, false, false

local function Forbidden(name) return function() error(name .. " read on Forever", 2) end end
C_PerksActivities = forever and { GetTrackedPerksActivities = Forbidden("Traveler's Log") } or {
    GetTrackedPerksActivities = function()
        reads.log = reads.log + 1
        local ids = {}
        for id in pairs(world.log) do ids[#ids + 1] = id end
        table.sort(ids)
        return { trackedIDs = ids }
    end,
    GetPerksActivityInfo = function(id) return world.log[id] end,
    RemoveTrackedPerksActivity = function(id) removed.log = id end,
}
C_NeighborhoodInitiative = forever and { GetTrackedInitiativeTasks = Forbidden("Endeavors") } or {
    GetTrackedInitiativeTasks = function()
        reads.tasks = reads.tasks + 1
        local ids = {}
        for id in pairs(world.tasks) do ids[#ids + 1] = id end
        table.sort(ids)
        return { trackedIDs = ids }
    end,
    GetInitiativeTaskInfo = function(id) return world.tasks[id] end,
    RemoveTrackedInitiativeTask = function(id) removed.task = id end,
}
Enum = {
    ContentTrackingType = { Appearance = 0, Mount = 1, Achievement = 2, Decor = 3 },
    ContentTrackingTargetType = { JournalEncounter = 0, Vendor = 1, Achievement = 2, Profession = 3 },
    ContentTrackingResult = { Success = 0, DataPending = 1, Failure = 2 },
    ContentTrackingStopType = { Manual = 2 },
}
local types, targets, results = Enum.ContentTrackingType, Enum.ContentTrackingTargetType, Enum.ContentTrackingResult
world.superType, world.superID = nil, nil
C_ContentTracking = {
    GetCollectableSourceTypes = function()
        reads.collect = reads.collect + 1
        return world.types
    end,
    GetTrackedIDs = function(trackableType)
        if trackableType == types.Achievement then
            reads.achievements = reads.achievements + 1
            return {}
        end
        return world.tracked[trackableType]
    end,
    GetCurrentTrackingTarget = function(trackableType, id)
        local target = world.targets[trackableType * 1000 + id]
        if target then return target.targetType, target.targetID end
    end,
    GetTitle = function(trackableType, id) return world.targets[trackableType * 1000 + id].title end,
    GetObjectiveText = function(targetType, targetID, includeHyperlinks)
        assert(includeHyperlinks == false, "the rows draw no hyperlinks")
        return world.objectives and world.objectives[targetType * 1000 + targetID]
    end,
    GetBestMapForTrackable = function(trackableType, id)
        local target = world.targets[trackableType * 1000 + id]
        return target.mapResult or results.Success, target.mapID or 2214
    end,
    IsNavigable = function() return results.Success, true end,
    GetWaypointText = function() return "Dock 4" end,
    StopTracking = function(trackableType, id, stopType) removed.content = { trackableType, id, stopType } end,
}
ContentTrackingUtil = {
    IsContentTrackingEnabled = function() return world.trackingEnabled end,
    MakeCombinedID = function(trackableType, id) return id * 1000 + trackableType end,
    OpenMapToTrackable = function(trackableType, id) opened.map = { trackableType, id } end,
}
C_SuperTrack = {
    GetSuperTrackedQuestID = function() return 0 end,
    GetSuperTrackedContent = function() return world.superType, world.superID end,
}
C_UIWidgetManager = { GetObjectiveTrackerWidgetSetID = function() return world.widgetSet end }
ObjectiveTrackerUIWidgetContainer = Widget(UIParent)
function ObjectiveTrackerUIWidgetContainer:HasAnyWidgetsShowing()
    reads.zone = reads.zone + 1
    return world.widgetsShowing
end
GetRealZoneText = function() return world.zone end
-- Neutral answers of the sources the tests do not exercise.
C_QuestLog = { GetNumQuestWatches = function() return 0 end }
C_TradeSkillUI = { GetRecipesTracked = function()
    assert(not forever, "Forever must not read Retail recipe tracking")
    return {}
end }
GetAchievementInfo = function() return nil end
IsModifiedClick = function(binding) return binding == "QUESTWATCHTOGGLE" and watchToggle end
IsShiftKeyDown = function() return false end
-- The windows the rows open, each recording its call.
EncounterJournal_LoadUI = function() opened.journalLoads = (opened.journalLoads or 0) + 1 end
MonthlyActivitiesFrame_OpenFrameToActivity = function(id) opened.log = id end
HousingFramesUtil = { OpenFrameToTaskID = function(id) opened.task = id end }
ShowAchievementFrameForAchievement = function(id) opened.achievement = id end
ProfessionsUtil = { OpenProfessionFrameToRecipe = function(id)
    opened.profession = id
    return world.professionOpens
end }
TransmogUtil = { OpenCollectionToItem = function(id) opened.collection = id end }
UIErrorsFrame = { AddExternalErrorMessage = function(_, text) opened.error = text end }
GameTooltip = { SetOwner = function() end, SetText = function(_, text) GameTooltip.text = text end, Show = function() end }
-- Blizzard's global strings.
PROFESSIONS_TRACKER_HEADER_PROFESSION = "Professions"
OBJECTIVES_VIEW_IN_TRAVELERS_LOG, OBJECTIVES_VIEW_IN_ENDEAVORS_TAB = "View in Traveler's Log", "View in Endeavors"
CONTENT_TRACKING_OPEN_JOURNAL_OPTION, OBJECTIVES_STOP_TRACKING = "View in collection", "Stop tracking"
CONTENT_TRACKING_RETRIEVING_INFO = "Retrieving info"
CONTENT_TRACKING_LOCATION_UNAVAILABLE, CONTENT_TRACKING_ROUTE_UNAVAILABLE = "Location unavailable", "Route unavailable"
OPTIONAL_QUEST_OBJECTIVE_DESCRIPTION = "Next: %s"
ADVENTURE_TRACKING_OPEN_PROFESSION_ERROR_TEXT = "Cannot open the profession"
hooksecurefunc = function(object, method, callback)
    local original = assert(object[method], method .. " is not a function of the hooked object")
    object[method] = function(self, ...)
        local result = { original(self, ...) }
        callback(self, ...)
        return unpack(result)
    end
end
-- Blizzard's tracker and the module whose layout pass the zone group follows.
ObjectiveTrackerFrame = Widget(UIParent)
function ObjectiveTrackerFrame:GetChildren() end
function ObjectiveTrackerFrame:AddModule() end
if forever then
    function ObjectiveTrackerFrame:FocusGamepad() end
    function ObjectiveTrackerFrame:UnfocusGamepad() end
end
UIWidgetObjectiveTracker = Widget(UIParent)
function UIWidgetObjectiveTracker:MarkDirty() end

------------------------------------------------------------------ the Suite's side
local secret = {}
local suite = { Client = { isMainline = true, isForever = forever }, Suite = { instances = {}, editMode = false },
    Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return combat end,
    IsSecret = function(value) return value == secret end, RestrictedNotice = function() return "restricted" end,
    HUDTextArgs = function() end }
local S = suite.Suite
S.Public = function(value) return value ~= secret end
S.Number = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Finite = function(value) return S.Number(value) and value > -math.huge and value < math.huge end
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
S.Text = function(value) return value end
S.Dispatch = function(callback, ...)
    local ok, err = pcall(callback, ...)
    assert(ok, err)
end
S.CreateFrame = CreateFrame
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.SetStyledFont = function(widget, path, size) widget:SetFont(path, size) end
S.ResolveFont = function(key) return key ~= "" and key or nil end
S.GlobalFontPath = function() return "Interface\\AddOns\\Test\\SuiteFont.ttf" end
S.RGB = function(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
S.ClockText = function(seconds) return tostring(seconds) end
S.Install = function(id, module) S.instances[id] = module end
S.Config = function(id) return S.instances[id].config end
S.GamepadUI = function() return gamepad end
S.CanOpenNativeWindow = function() return not combat and not gamepad end
S.Print = function(text) opened.notice = text end
S.ContextMenu = function(owner, build)
    local menu = { buttons = {}, enabled = {} }
    function menu:CreateTitle(title) self.title = title end
    function menu:CreateButton(label, action)
        self.buttons[#self.buttons + 1] = label
        self.buttons[label] = action
        return { SetEnabled = function(_, value) menu.enabled[label] = value end }
    end
    build(owner, menu)
    lastMenu = menu
end
local moduleStates = {}
S.ModuleState = function(id)
    moduleStates[id] = moduleStates[id] or {}
    return moduleStates[id]
end
suite.Public, suite.Finite, suite.Number = S.Public, S.Finite, S.Number
suite.Dispatch = S.Dispatch
MSUFSuite = suite
local TimerContext = Support.ModuleTimers(root, S, suite)
local private = { NS = suite, Suite = S }
for _, file in ipairs({ "ObjectivesData", "ObjectivesContent", "ObjectivesDetails", "ObjectivesActions",
    "ObjectivesContentActions", "ObjectivesRows", "ObjectivesTracker", "Objectives" }) do
    assert(loadfile(root .. "/MSUF_Suite_Modules/" .. file .. ".lua"))("MSUF_Suite_Modules", private)
end
local O = private.Objectives
local tracker = S.instances.objectives

local function Context()
    local ctx = TimerContext("objectives", tracker, { events = {}, hidden = {}, saved = {} })
    function ctx:Event(event, callback) self.events[event] = callback end
    function ctx:RemoveEvent(event) self.events[event] = nil end
    function ctx:Skin() return nil end
    function ctx:HideControl(frame, value) self.hidden[frame] = value end
    function ctx:Scale() end
    function ctx:RestoreProperty() end
    return ctx
end

local catalogConfig, catalogNS = Support.CatalogDefaults(root, "objectives", "HUD", suite.Client)
local rules = catalogNS.SuiteCatalog.objectives.rules

------------------------------------------------------------------ helpers
local function Fire(event, ...)
    local callback = assert(tracker.context.events[event], event .. " is not registered")
    callback(tracker, event, ...)
    clock.Frame()
end

local function Row(key) return tracker.rows[key] end

local function Snapshot()
    local copy = {}
    for key, value in pairs(reads) do copy[key] = value end
    return copy
end

-- Fires an event and requires that exactly the named sources were read again.
local function ExpectReads(label, changed, fire)
    local before = Snapshot()
    fire()
    for key, value in pairs(reads) do
        local expected = before[key] + (changed[key] and 1 or 0)
        assert(value == expected, string.format("%s: %s read %d times, expected %d", label, key,
            value - before[key], expected - before[key]))
    end
end

local function Activity(id, name, requirements)
    return { ID = id, activityName = name, completed = false, requirementsList = requirements }
end

------------------------------------------------------------------ the guard over Blizzard's modules
-- Blizzard's modules, from the fixture, and the Suite source that draws each
-- (the campaign quests are the quests source's campaign group).
local COVERED = {
    ScenarioObjectiveTracker = "scenario", UIWidgetObjectiveTracker = "zone",
    CampaignQuestObjectiveTracker = "quests", QuestObjectiveTracker = "quests",
    AdventureObjectiveTracker = "collectibles", AchievementObjectiveTracker = "achievements",
    MonthlyActivitiesObjectiveTracker = "travelersLog", InitiativeTasksObjectiveTracker = "endeavors",
    ProfessionsRecipeTracker = "recipes", BonusObjectiveTracker = "bonus", WorldQuestObjectiveTracker = "world",
}
-- Sources a client lacks because its game has no such content.
local RETAIL_ONLY = { recipes = true, travelersLog = true, endeavors = true }
local active = {}
for _, source in ipairs(O.SOURCES) do active[source] = true end
local fixture = dofile(root .. "/tools/fixtures/blizzard_objective_tracker_modules.lua")
local seen = {}
for ref, list in pairs(fixture) do
    assert(#list > 0, ref .. " lists no Blizzard tracker module")
    for _, name in ipairs(list) do
        seen[name] = true
        local source = COVERED[name]
        assert(source, ref .. ": Blizzard's tracker has a module the Suite does not draw: " .. name
            .. " (add a source to ObjectivesContent.lua, then list it in COVERED)")
        assert(active[source] or (forever and RETAIL_ONLY[source]),
            name .. " is not drawn by the Suite on " .. flavor .. ": source " .. source .. " is missing")
    end
end
for name in pairs(COVERED) do assert(seen[name], "COVERED lists a module Blizzard no longer registers: " .. name) end
for source in pairs(RETAIL_ONLY) do
    assert((active[source] == true) == not forever, source .. " must exist exactly where the game has its content")
end

------------------------------------------------------------------ the catalog
for _, key in ipairs({ "showCollectibles", "showZoneEvents" }) do
    assert(rules[key] and rules[key].section == "content" and catalogConfig[key] == true,
        key .. " must be a content setting that restores the group by default")
end
for _, key in ipairs({ "showTravelersLog", "showEndeavors" }) do
    assert((rules[key] ~= nil) == not forever, key .. " must be offered on Retail only")
    if not forever then assert(rules[key].section == "content" and catalogConfig[key] == true, key .. " must default on") end
end

------------------------------------------------------------------ enable: draws what is tracked
world.log[701] = Activity(701, "Slay the Dragons", {
    { completed = false, requirementText = "3 / 5 Dragons slain" },
    { completed = true, requirementText = "Find the nest" },
})
world.log[702] = { ID = 702, activityName = "Already done", completed = true, requirementsList = {} }
world.tasks[55] = { ID = 55, taskName = "Plant the garden", completed = false,
    requirementsList = { { completed = false, requirementText = "2 / 4 Seeds" } } }
world.tracked[types.Appearance] = { 9001 }
world.tracked[types.Mount] = { 12 }
world.tracked[types.Decor] = { 5, 6 }
world.targets[types.Appearance * 1000 + 9001] = { targetType = targets.Vendor, targetID = 77, title = "Mythic Helm" }
world.targets[types.Mount * 1000 + 12] = { targetType = targets.Achievement, targetID = 6006, title = "Drake Reins" }
world.targets[types.Decor * 1000 + 5] = { targetType = targets.Vendor, targetID = 78, title = "Garden Gnome",
    mapResult = results.Failure }
world.targets[types.Decor * 1000 + 6] = { targetType = targets.JournalEncounter, targetID = 90, title = "Trophy Rug",
    mapResult = results.DataPending }
world.objectives = { [targets.Vendor * 1000 + 77] = "Buy from Brann", [targets.Achievement * 1000 + 6006] = "Earn Drake Rider",
    [targets.Vendor * 1000 + 78] = "Buy from Gnomo", [targets.JournalEncounter * 1000 + 90] = "Defeat Rugsy" }
world.widgetsShowing = true

tracker.context = Context()
tracker.config = catalogConfig
tracker.config.showWorldQuests, tracker.config.showBonus, tracker.config.showScenario = false, false, false
tracker:Enable()

local function Entry(group, id) return assert(Row("entry:" .. group .. ":" .. id), group .. " entry " .. id .. " not drawn") end
local function Line(group, id, index)
    return assert(Row("line:" .. group .. ":" .. id .. ":" .. index), group .. " line " .. index .. " not drawn")
end

if not forever then
    assert(Row("section:travelersLog").text.text == "TRAVELER'S LOG", "no Traveler's Log group heading")
    assert(Entry("travelersLog", 701).text.text == "Slay the Dragons")
    assert(Line("travelersLog", 701, 1).text.text == "3/5 Dragons slain", "requirement text is not tidied")
    assert(not Row("line:travelersLog:701:2"), "a completed requirement is still listed")
    assert(not Row("entry:travelersLog:702"), "a completed activity is still listed")
    assert(Row("section:endeavors").text.text == "ENDEAVORS")
    assert(Line("endeavors", 55, 1).text.text == "2/4 Seeds")
else
    assert(not Row("section:travelersLog") and not Row("section:endeavors"), "Forever drew Retail-only groups")
end
assert(Row("section:collectibles").text.text == "COLLECTIBLES")
assert(Entry("collectibles", 9001000).text.text == "Mythic Helm")
assert(Line("collectibles", 9001000, 1).text.text == "Buy from Brann")
assert(not Row("line:collectibles:9001000:2"), "a route line appeared without a super-tracked trackable")
assert(Line("collectibles", 12001, 1).text.text == "Earn Drake Rider" and not Row("line:collectibles:12001:2"),
    "a target without a route got a route line")
assert(Line("collectibles", 5003, 2).text.text == "Location unavailable", "missing location is not explained")
assert(Line("collectibles", 6003, 1).text.text == "Defeat Rugsy" and not Row("line:collectibles:6003:2"),
    "pending location data got a route line")
assert(Row("section:zone").text.text == "ZONE EVENT" and Entry("zone", 0).text.text == "Dornogal")
assert(Entry("zone", 0).scenarioHeader and Entry("zone", 0).scenarioHeader.widgetSetID == world.widgetSet,
    "the zone widgets are not drawn through a container of their set")
assert(tracker.host.shown and tracker.count.text == (forever and "5" or "7"), "the heading counts the new entries")

-- Group order follows Blizzard's modules.
local order = { "zone", "collectibles", "travelersLog", "endeavors" }
local previous = -1
for _, group in ipairs(order) do
    local section = Row("section:" .. group)
    if section then
        assert(section.layoutY > previous, group .. " is out of Blizzard's module order")
        previous = section.layoutY
    end
end

-- The rows are not quests: no quest tooltip, quest click or quest icon.
local helm = Entry("collectibles", 9001000)
assert(helm.questID == nil and helm.achievementID == nil and helm.contentID == 9001 and helm.contentType == types.Appearance,
    "a collectible row carries the identity of a quest")
assert(Entry("zone", 0).mouse == false and Entry("zone", 0).contentID == nil, "the zone widgets answer clicks")

------------------------------------------------------------------ clicks
local function Click(row, button) row.OnClick(row, button or "LeftButton") end

if not forever then
    local log = Entry("travelersLog", 701)
    Click(log)
    assert(opened.log == 701 and opened.journalLoads == 1, "a Traveler's Log row did not open its activity")
    Click(Line("travelersLog", 701, 1))
    assert(opened.journalLoads == 2, "a requirement line does not act like its activity")
    opened.log, opened.journalLoads = nil, nil
    combat = true
    Click(log)
    assert(opened.log == nil and opened.notice == "restricted", "the Traveler's Log opened in combat")
    combat, gamepad = false, true
    opened.notice = nil
    Click(log)
    assert(opened.log == nil, "the Traveler's Log opened from the Suite under the Gamepad UI")
    gamepad = false
    watchToggle = true
    Click(log)
    assert(removed.log == 701 and opened.log == nil, "the watch-toggle click did not stop tracking the activity")
    watchToggle = false
    Click(log, "RightButton")
    assert(lastMenu.title == "Slay the Dragons" and lastMenu.buttons[1] == "View in Traveler's Log"
        and lastMenu.buttons[2] == "Stop tracking" and lastMenu.enabled["View in Traveler's Log"] == true)
    lastMenu.buttons["View in Traveler's Log"]()
    assert(opened.log == 701)
    removed.log = nil
    lastMenu.buttons["Stop tracking"]()
    assert(removed.log == 701, "the menu did not stop tracking the activity")
    Click(Entry("endeavors", 55))
    assert(opened.task == 55, "an Endeavors row did not open its task")
    Click(Entry("endeavors", 55), "RightButton")
    assert(lastMenu.buttons[1] == "View in Endeavors" and lastMenu.buttons[2] == "Stop tracking")
    lastMenu.buttons["Stop tracking"]()
    assert(removed.task == 55, "the menu did not stop tracking the task")
end
Click(helm)
assert(opened.map and opened.map[1] == types.Appearance and opened.map[2] == 9001, "a vendor collectible did not open its map")
Click(Entry("collectibles", 12001))
assert(opened.achievement == 6006, "an achievement target did not open the achievement")
world.targets[types.Mount * 1000 + 12].targetType, world.targets[types.Mount * 1000 + 12].targetID = targets.Profession, 321
Click(Entry("collectibles", 12001))
assert(opened.profession == 321 and opened.error == "Cannot open the profession", "a failed profession open is not reported")
Click(helm, "RightButton")
assert(lastMenu.buttons[1] == "View in collection" and lastMenu.buttons[2] == "Stop tracking",
    "an appearance menu lacks Blizzard's two entries")
lastMenu.buttons["View in collection"]()
assert(opened.collection == 9001)
lastMenu.buttons["Stop tracking"]()
assert(removed.content[1] == types.Appearance and removed.content[2] == 9001 and removed.content[3] == 2,
    "the menu did not stop tracking the appearance manually")
Click(Entry("collectibles", 12001), "RightButton")
assert(#lastMenu.buttons == 1 and lastMenu.buttons[1] == "Stop tracking", "a mount menu offers the appearance window")
watchToggle = true
removed.content = nil
Click(helm)
assert(removed.content and removed.content[2] == 9001, "the watch-toggle click did not stop tracking the collectible")
watchToggle = false

------------------------------------------------------------------ events refresh their own sources
world.superType, world.superID = types.Appearance, 9001
ExpectReads("super tracking", { collect = true }, function() Fire("SUPER_TRACKING_CHANGED") end)
assert(Line("collectibles", 9001000, 2).text.text == "Next: Dock 4", "the super-tracked waypoint line is missing")
world.superType = nil
ExpectReads("unrelated quest event", {}, function() Fire("QUEST_LOG_UPDATE") end)
ExpectReads("achievement tracking", { achievements = true }, function()
    Fire("CONTENT_TRACKING_UPDATE", types.Achievement, 5, true)
end)
ExpectReads("collectible tracking", { collect = true }, function()
    Fire("CONTENT_TRACKING_UPDATE", types.Mount, 12, false)
end)
for _, event in ipairs({ "TRACKING_TARGET_INFO_UPDATE", "TRACKABLE_INFO_UPDATE", "CONTENT_TRACKING_IS_ENABLED_UPDATE" }) do
    ExpectReads(event, { collect = true }, function() Fire(event) end)
end
for _, event in ipairs({ "PERKS_ACTIVITIES_TRACKED_UPDATED", "PERKS_ACTIVITIES_TRACKED_LIST_CHANGED", "PERKS_ACTIVITY_COMPLETED" }) do
    if forever then
        assert(tracker.context.events[event] == nil, "Forever listens to " .. event)
    else
        ExpectReads(event, { log = true }, function() Fire(event) end)
    end
end
for _, event in ipairs({ "INITIATIVE_TASKS_TRACKED_UPDATED", "INITIATIVE_TASKS_TRACKED_LIST_CHANGED", "NEIGHBORHOOD_INITIATIVE_UPDATED" }) do
    if forever then
        assert(tracker.context.events[event] == nil, "Forever listens to " .. event)
    else
        ExpectReads(event, { tasks = true }, function() Fire(event) end)
    end
end
-- Blizzard's widget block marks itself dirty after laying its container out.
ExpectReads("widget layout", { zone = true }, function() UIWidgetObjectiveTracker:MarkDirty() clock.Frame() end)
-- A new area reads every source again.
local everything = { collect = true, achievements = true, zone = true, log = not forever, tasks = not forever }
ExpectReads("new area", everything, function() Fire("ZONE_CHANGED_NEW_AREA") end)

------------------------------------------------------------------ hide when nothing is tracked
-- The zone block leaves first, so its row reaches the pool before the content rows do.
world.widgetsShowing = false
UIWidgetObjectiveTracker:MarkDirty()
clock.Frame()
assert(not Row("section:zone") and tracker.sources.zone.count == 0, "the zone block stays after its widgets are gone")
if not forever then
    world.log[701] = nil
    Fire("PERKS_ACTIVITIES_TRACKED_LIST_CHANGED", 701, false)
    assert(not Row("section:travelersLog") and tracker.sources.travelersLog.count == 0, "an empty Traveler's Log still shows")
    world.log[701] = Activity(701, "Slay the Dragons", {})
    Fire("PERKS_ACTIVITIES_TRACKED_LIST_CHANGED", 701, true)
    assert(Entry("travelersLog", 701) and not Row("line:travelersLog:701:1"), "an activity without open requirements has lines")
    world.log[701], world.tasks[55] = nil, nil
    Fire("PERKS_ACTIVITIES_TRACKED_LIST_CHANGED", 701, false)
    Fire("INITIATIVE_TASKS_TRACKED_LIST_CHANGED", 55, false)
    assert(not Row("section:travelersLog") and not Row("section:endeavors"))
end
world.trackingEnabled = false
Fire("CONTENT_TRACKING_IS_ENABLED_UPDATE")
assert(not Row("section:collectibles"), "collectibles show while content tracking is off")
world.trackingEnabled = true
world.tracked = { [0] = {}, [1] = {}, [3] = {} }
Fire("CONTENT_TRACKING_UPDATE", types.Appearance, 9001, false)
assert(not Row("section:collectibles") and tracker.sources.collectibles.count == 0, "empty collectibles still show")
assert(tracker.count.text == "0" and not tracker.host.shown, "the tracker stays visible with nothing to show")
-- The zone block takes a pooled entry row that held a collectible: the old action must not stay on it.
assert(#tracker.freeRows > 0)
world.widgetsShowing = true
UIWidgetObjectiveTracker:MarkDirty()
clock.Frame()
assert(Entry("zone", 0).contentID == nil and Entry("zone", 0).contentType == nil, "a pooled row kept its collectible action")
world.tracked[types.Appearance] = { 9001 }

------------------------------------------------------------------ show settings
local SETTINGS = {
    { key = "showCollectibles", read = "collect", section = "section:collectibles", event = "TRACKABLE_INFO_UPDATE" },
    { key = "showZoneEvents", read = "zone", section = "section:zone", event = "ZONE_CHANGED_NEW_AREA" },
}
if not forever then
    world.log[701] = Activity(701, "Slay the Dragons", { { completed = false, requirementText = "1 / 2 Eggs" } })
    world.tasks[55] = { ID = 55, taskName = "Plant the garden", completed = false, requirementsList = {} }
    SETTINGS[#SETTINGS + 1] = { key = "showTravelersLog", read = "log", section = "section:travelersLog",
        event = "PERKS_ACTIVITIES_TRACKED_UPDATED" }
    SETTINGS[#SETTINGS + 1] = { key = "showEndeavors", read = "tasks", section = "section:endeavors",
        event = "NEIGHBORHOOD_INITIATIVE_UPDATED" }
end
tracker.config.showAchievements = false
Fire("TRACKABLE_INFO_UPDATE")
for _, setting in ipairs(SETTINGS) do
    tracker:Refresh()
    assert(Row(setting.section), setting.section .. " is missing with its setting on")
    tracker.config[setting.key] = false
    tracker:Refresh()
    assert(not Row(setting.section), setting.key .. " off still shows the group")
    local before = reads[setting.read]
    Fire(setting.event)
    assert(reads[setting.read] == before, setting.key .. " off still reads the client")
    tracker.config[setting.key] = true
    tracker:Refresh()
    assert(Row(setting.section), setting.key .. " on did not bring the group back")
end

------------------------------------------------------------------ disable
tracker:Disable()
for _, source in ipairs({ "collectibles", "zone" }) do
    assert(tracker.sources[source].count == 0, source .. " kept entries after the module was disabled")
end
print("Suite tracker sources: Traveler's Log, Endeavors, collectibles and zone widgets draw, hide, refresh, "
    .. "follow their settings and gate by client (" .. flavor .. ")")
