-- The modules Blizzard's objective tracker registers, per client, in the order of
-- ObjectiveTrackerManager:Init (Blizzard_ObjectiveTracker/
-- Blizzard_ObjectiveTrackerManager.lua, "orderedModules").
-- suite_tracker_sources_contract.lua requires the Suite to draw every one of
-- them, so a module Blizzard adds fails that test instead of silently
-- vanishing behind the Suite's tracker.
-- Refresh after a client update from the UI source mirror: git -C <mirror>
-- show <ref>:Interface/AddOns/Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerManager.lua,
-- then copy the names between "local orderedModules = {" and "};" into the
-- list of that ref. Last read: live 12.1.5 (70391) and upstream/forever
-- 1.60.1 (70532), which list the same eleven modules.
return {
    live = {
        "ScenarioObjectiveTracker",
        "UIWidgetObjectiveTracker",
        "CampaignQuestObjectiveTracker",
        "QuestObjectiveTracker",
        "AdventureObjectiveTracker",
        "AchievementObjectiveTracker",
        "MonthlyActivitiesObjectiveTracker",
        "InitiativeTasksObjectiveTracker",
        "ProfessionsRecipeTracker",
        "BonusObjectiveTracker",
        "WorldQuestObjectiveTracker",
    },
    forever = {
        "ScenarioObjectiveTracker",
        "UIWidgetObjectiveTracker",
        "CampaignQuestObjectiveTracker",
        "QuestObjectiveTracker",
        "AdventureObjectiveTracker",
        "AchievementObjectiveTracker",
        "MonthlyActivitiesObjectiveTracker",
        "InitiativeTasksObjectiveTracker",
        "ProfessionsRecipeTracker",
        "BonusObjectiveTracker",
        "WorldQuestObjectiveTracker",
    },
}
