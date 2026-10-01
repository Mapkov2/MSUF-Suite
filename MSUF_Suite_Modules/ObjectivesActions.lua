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

-- PreClick of the row's group button. It runs before Blizzard's click
-- handler and writes only the button's own attributes.
function O.FindGroupPreClick(button)
    local row = button.ownerRow
    local native = row.questGroupSearch and Finite(row.questID) and NativeGroupButton(row.questID)
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
    if NS.IsCombatLocked() or NS.Client.isForever then return end
    ShowUIPanel(PVEFrame)
end

------------------------------------------------------------------ context menus
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

local function BuildQuestMenu(root, button)
    local questID, group = button.questID, button.group
    local task = group == "world" or group == "bonus"
    if button.findGroup then root:CreateButton(Tr("Open group finder"), OpenGroupFinder) end
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
    local group, title = button.group, button.menuTitle or Tr("Objective")
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

O.OpenQuestDetails, O.OpenAchievement, O.OpenJournal = OpenQuestDetails, OpenAchievement, OpenJournal
O.WatchTogglePressed, O.Untrack, O.ShowContextMenu = WatchTogglePressed, Untrack, ShowContextMenu
