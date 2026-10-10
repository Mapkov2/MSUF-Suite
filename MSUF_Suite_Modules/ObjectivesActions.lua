local _, P = ...
local NS, S = P.NS, P.Suite
local O = P.Objectives
local Read = O.Read
local Finite = S.Finite
local Tr = S.Text

-- What the objective tracker's rows do: Blizzard's quest, achievement and
-- group finder actions and the context menus (see ObjectivesData.lua for
-- how the files fit together).

------------------------------------------------------------------ Blizzard actions
-- Quest log/group finder load with Retail/Forever game UI. Achievement and
-- Adventure Guide bootstraps depend on game type, so those two are checked.
-- Each opens a panel of Blizzard's panel manager (ShowUIPanel), which refuses
-- the Suite's call in combat ("Interface action failed because of an AddOn",
-- CheckProtectedFunctionsAllowed) and under WoW Forever's Gamepad UI would
-- run the frame controls manager in it: they act only while
-- S.CanOpenNativeWindow allows (MSUF_Suite_Modules/MicroMenu.lua).
local function OpenQuestDetails(questID)
    if not Finite(questID) or questID <= 0 or not S.CanOpenNativeWindow() then return end
    QuestMapFrame_OpenToQuestDetails(questID)
end

local function OpenTaskMap(questID)
    if not S.CanOpenNativeWindow() then return end
    local mapID = Read(C_TaskQuest.GetQuestZoneID, questID)
    if Finite(mapID) and mapID > 0 then
        OpenQuestLog(mapID)
        EventRegistry:TriggerEvent("MapCanvas.PingQuestID", questID)
    else
        OpenQuestDetails(questID)
    end
end

local function OpenAchievement(achievementID)
    if type(_G.ShowAchievementFrameForAchievement) == "function" and S.CanOpenNativeWindow() then
        _G.ShowAchievementFrameForAchievement(achievementID)
    end
end

local function OpenJournal()
    if type(_G.ToggleEncounterJournal) == "function" and S.CanOpenNativeWindow() then _G.ToggleEncounterJournal() end
end

-- The quest log for the tracker's header, under the same rule.
local function OpenLog()
    if S.CanOpenNativeWindow() then OpenQuestLog() end
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

-- WoW Forever's tracker rows and header are InsecureActionButtonTemplate
-- buttons (ObjectivesTracker.lua). Under its Gamepad UI (S.GamepadUI) a click
-- that would open a Blizzard window or menu from the Suite's code clicks
-- Blizzard's own button from the template's handler instead (out of combat,
-- as the template acts), with the same mouse button. The native tracker
-- stays shown at alpha 0 (Objectives.lua), so its blocks exist for the
-- quests it tracks, and their block headers answer as on Blizzard's tracker
-- (OnBlockHeaderClick, upstream/forever Blizzard_ObjectiveTracker; Blizzard's
-- own gamepad tracker clicks HeaderButton with RightButton the same way,
-- ObjectiveTrackerFrameMixin:OpenQuestOptionsFromTracker):
--   * quest and campaign quests (QuestObjectiveTrackerMixin): left opens the
--     quest's details, right Blizzard's quest menu, Abandon quest included;
--   * world quests (WorldQuestObjectiveTracker, showWorldQuests) and threat
--     quests in the bonus module (BonusObjectiveTrackerMixin): left opens the
--     quest's zone map when it has one, right Blizzard's stop-tracking menu
--     while the quest is watched; other bonus objectives answer nothing.
-- Without such a header a left click uses the quest log micro button, a
-- scenario's the Adventure Guide's (S.PanelButton), and a right click opens
-- the Suite's own menu (S.ContextMenu).
local function TaskHeaderAnswers(module, questID, mouseButton)
    local threat = Read(C_QuestLog.IsThreatQuest, questID) == true
    if not (module.showWorldQuests == true or threat) then return false end
    if mouseButton == "LeftButton" then
        local mapID = Read(C_TaskQuest.GetQuestZoneID, questID)
        return Finite(mapID) and mapID > 0
    end
    return not threat and Read(QuestUtils_IsQuestWatched, questID) == true
end

local function NativeQuestHeader(row, mouseButton)
    local questID = row.questID
    if not Finite(questID) then return nil end
    local task = row.group == "world" or row.group == "bonus"
    local modules = task and { WorldQuestObjectiveTracker, BonusObjectiveTracker }
        or { QuestObjectiveTracker, CampaignQuestObjectiveTracker }
    for _, module in ipairs(modules) do
        local block = module and module:GetExistingBlock(questID)
        local header = block and block.used and block.HeaderButton
        if header and header:IsShown() and (not task or TaskHeaderAnswers(module, questID, mouseButton)) then
            return header
        end
    end
end

local function WindowButton(row)
    if row.kind == "header" then return S.PanelButton("questLog") end
    if Finite(row.questID) then
        if O.CanCompleteQuest(row.questID) then return nil end
        return NativeQuestHeader(row, "LeftButton") or S.PanelButton("questLog")
    elseif row.group == "scenario" then
        return S.PanelButton("journal")
    end
end

-- PreClick of a Forever row or header: writes only the button's own
-- attributes; row.secureWindow tells the click handler that Blizzard's
-- button took the click.
function O.RowPreClick(row, mouseButton)
    local target
    if row.kind ~= "section" and S.GamepadUI() and not NS.IsCombatLocked() then
        if mouseButton == "LeftButton" then
            target = not WatchTogglePressed() and WindowButton(row) or nil
        elseif mouseButton == "RightButton" then
            target = NativeQuestHeader(row, mouseButton)
        end
    end
    row:SetAttribute("type", target and "click" or nil)
    row:SetAttribute("clickbutton", target)
    row.secureWindow = target ~= nil or nil
end

-- On WoW Forever the tracker's row and header buttons are
-- InsecureActionButtonTemplate buttons whose PreClick (O.RowPreClick) lets
-- the template click Blizzard's own button under the Gamepad UI; the Suite's
-- click handler runs after it. Elsewhere they are plain buttons.
function O.ClickButton(parent, onClick)
    local template = NS.Client.isForever and "InsecureActionButtonTemplate" or nil
    local button = S.CreateFrame("Button", nil, parent, template)
    if template then
        button:SetAttribute("useOnKeyDown", false)
        button:SetScript("PreClick", O.RowPreClick)
        button:HookScript("OnClick", onClick)
    else
        button:SetScript("OnClick", onClick)
    end
    return button
end

function O.OnHeaderClick(header)
    if header.secureWindow then
        header.secureWindow = nil
        return
    end
    OpenLog()
end

------------------------------------------------------------------ group finder
-- The LFG list keeps state that the player's next search or group listing
-- reads (LFGListFrame_BeginFindQuestGroup in LFGList.lua sets the category
-- and the auto-create quest; C_LFGList.Search and CreateListing are
-- restricted). LFGListUtil_FindQuestGroup or PVEFrame_ShowFrame called from
-- here would write that state inside this addon's call and taint it. The
-- row's group button is therefore an InsecureActionButtonTemplate (the
-- tracker stays unprotected and clicks act only out of combat, like the
-- quest item button) that clicks Blizzard's own buttons from Blizzard's
-- click handler:
--   * the green-eye button the hidden native tracker keeps for the quest
--     (QuestObjectiveFindGroupButtonMixin:OnClick runs the quest search);
--   * for a scenario, the find-group button of the native stage block
--     (ScenarioObjectiveTrackerFindGroupButtonMixin:OnClick runs
--     LFGListUtil_FindScenarioGroup, which reaches the same search);
--   * else the group finder micro button, its first tab and Premade Groups.
local NATIVE_QUEST_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker",
    "WorldQuestObjectiveTracker", "BonusObjectiveTracker" }
local SHOW_PREMADE = "/click PVEFrameTab1\n/click GroupFinderFrameGroupButton3"
local OPEN_PREMADE = "/click LFDMicroButton\n" .. SHOW_PREMADE

-- Native modules create their right-edge frames on first use.
local function NativeGroupButton(questID)
    local setUp = QuestObjectiveFindGroupButtonMixin.SetUp
    for i = 1, #NATIVE_QUEST_MODULES do
        local module = _G[NATIVE_QUEST_MODULES[i]]
        local frames = module and module.usedRightEdgeFrames
        for _, frame in pairs(frames or {}) do
            if frame.used and frame.SetUp == setUp and frame:GetAttribute("questID") == questID then
                return frame
            end
        end
    end
end

-- The stage block (Blizzard_ObjectiveTracker loads at startup on every
-- supported client) creates its button on first use, shows it while
-- C_LFGList.CanCreateScenarioGroup allows it and keeps the scenario it was
-- set up for.
local function NativeScenarioGroupButton(scenarioID)
    local stageButton = ScenarioObjectiveTracker.StageBlock.findGroupButton
    if stageButton and stageButton:IsShown() and stageButton.scenarioID == scenarioID then return stageButton end
end

-- PreClick of the row's group button. It runs before Blizzard's click
-- handler and writes only the button's own attributes.
function O.FindGroupPreClick(button)
    local row = button.ownerRow
    local native
    if row.group == "scenario" then
        native = Finite(row.scenarioID) and NativeScenarioGroupButton(row.scenarioID)
    else
        native = row.questGroupSearch and Finite(row.questID) and NativeGroupButton(row.questID)
    end
    if native then
        button:SetAttribute("type", "click")
        button:SetAttribute("clickbutton", native)
    else
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", PVEFrame:IsShown() and SHOW_PREMADE or OPEN_PREMADE)
    end
end

-- A menu action runs in this addon's code: it opens the group finder window
-- through Blizzard's secure panel delegate (ShowUIPanel) and leaves the
-- quest search to the row's group button.
local function OpenGroupFinder()
    if not S.CanOpenNativeWindow() or NS.Client.isForever then return end
    ShowUIPanel(PVEFrame)
end

------------------------------------------------------------------ context menus
-- Menu labels are Blizzard's global strings; its own objective tracker uses
-- them on every supported client. Entries that open a Blizzard window or
-- dialog from the menu's (the Suite's) call are off while
-- S.CanOpenNativeWindow refuses; under the Gamepad UI the menu is the
-- Suite's own list (S.ContextMenu) and Abandon quest is off too
-- (QuestMapQuestOptions_AbandonQuest shows Blizzard's ABANDON_QUEST popup).
local function BuildAchievementMenu(root, button)
    local achievementID = button.achievementID
    if type(_G.ShowAchievementFrameForAchievement) == "function" then
        root:CreateButton(OBJECTIVES_VIEW_ACHIEVEMENT, function()
            OpenAchievement(achievementID)
        end):SetEnabled(S.CanOpenNativeWindow())
    end
    if CanUntrack(button) then
        root:CreateButton(OBJECTIVES_STOP_TRACKING, function() Untrack(button) end)
    end
end

-- LFGListUtil_FindScenarioGroup would write the LFG list state inside this
-- menu call (see "group finder" above): the menu opens the window only and
-- the row's group button runs the scenario search.
local function BuildScenarioMenu(root, scenarioID)
    if type(_G.ToggleEncounterJournal) == "function" then
        root:CreateButton(ENCOUNTER_JOURNAL, OpenJournal):SetEnabled(S.CanOpenNativeWindow())
    end
    if not NS.Client.isForever and Finite(scenarioID)
        and Read(C_LFGList.CanCreateScenarioGroup, scenarioID) == true then
        root:CreateButton(Tr("Open group finder"), OpenGroupFinder):SetEnabled(S.CanOpenNativeWindow())
    end
end

local function BuildQuestMenu(root, button)
    local questID, group = button.questID, button.group
    local task = group == "world" or group == "bonus"
    local windows = S.CanOpenNativeWindow()
    if button.findGroup then root:CreateButton(Tr("Open group finder"), OpenGroupFinder):SetEnabled(windows) end
    root:CreateButton(task and OBJECTIVES_SHOW_QUEST_MAP or OBJECTIVES_VIEW_IN_QUESTLOG, function()
        if task then OpenTaskMap(questID) else OpenQuestDetails(questID) end
    end):SetEnabled(windows)
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
            if not S.GamepadUI() then QuestMapQuestOptions_AbandonQuest(questID) end
        end):SetEnabled(not S.GamepadUI())
    end
end

local function ShowContextMenu(button)
    local group, title = button.group, button.menuTitle or Tr("Objective")
    if not (Finite(button.questID) or Finite(button.achievementID) or group == "scenario") then return end
    S.ContextMenu(button, function(_, root)
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

O.OpenQuestDetails, O.OpenAchievement, O.OpenJournal = OpenQuestDetails, OpenAchievement, OpenJournal
O.WatchTogglePressed, O.Untrack, O.ShowContextMenu = WatchTogglePressed, Untrack, ShowContextMenu
