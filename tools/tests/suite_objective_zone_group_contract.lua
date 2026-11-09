local root = assert(arg[1])
local fixture = dofile(root .. "/tools/tests/comfort_fixture.lua").New(root, true)
fixture:Load("MSUF_Suite_Modules/ObjectivesData.lua")
local O, mapReads = fixture.P.Objectives, 0
local maps = { [20] = { mapType = 5, parentMapID = 2 }, [2] = { mapType = 3 }, [3] = { mapType = 3 } }
local current = 20
Enum = { UIMapType = { Zone = 3 }, QuestClassification = { Campaign = 1, Important = 2, Legendary = 3 } }
C_Map = {
    GetBestMapForUnit = function(unit) assert(unit == "player"); return current end,
    GetMapInfo = function(map) return maps[map] end,
}
local questMaps = { 2, 3, fixture.secret, 3 }
GetQuestUiMapID = function(quest, ignoreWaypoints)
    assert(ignoreWaypoints == true)
    mapReads = mapReads + 1
    return questMaps[quest]
end
GetTime = function() return 1 end
C_SuperTrack = { GetSuperTrackedQuestID = function() return 4 end }
C_QuestInfoSystem = { GetQuestClassification = function() end }
C_QuestLog = {
    GetNumQuestWatches = function() return #questMaps end,
    GetQuestIDForQuestWatchIndex = function(i) return i end,
    GetTitleForQuestID = function(id) return "Quest " .. id end,
    GetQuestObjectives = function() end,
    IsComplete = function() return false end,
}
local tracker = O.M
tracker.config = { showQuestItems = false, showTimers = false, groupQuestsByZone = false }
local function Refresh()
    tracker.dirty.quests = true
    O.CollectDirty(tracker)
    return tracker.sources.quests
end
local quests = Refresh()
assert(mapReads == 0 and quests[1].group == "quests", "the opt-out path must do no quest map reads")
tracker.config.groupQuestsByZone = true
quests = Refresh()
assert(quests[1].group == "localQuests" and quests[2].group == "otherQuests", "zone grouping lost the player's parent zone")
assert(quests[3].group == "quests" and quests[4].group == "focused", "unreadable maps and focused quests must remain visible")
current = 3
assert(Refresh()[1].group == "otherQuests" and quests[2].group == "localQuests", "zone changes must update existing rows")
print("suite_objective_zone_group_contract: ok")
