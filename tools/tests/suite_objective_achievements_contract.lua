-- Tracked achievements read as Blizzard's achievement module words them
-- (Blizzard_AchievementObjectiveTracker.lua, AddAchievement; live 297d7aaa
-- and forever 4cd0ab75 are identical).
local root = assert(arg[1])
local fixture = dofile(root .. "/tools/tests/comfort_fixture.lua").New(root, true)
fixture:Load("MSUF_Suite_Modules/ObjectivesData.lua")
local O, secret = fixture.P.Objectives, fixture.secret

Enum = { ContentTrackingType = { Achievement = 2 } }
EVALUATION_TREE_FLAG_PROGRESS_BAR, CRITERIA_TYPE_ACHIEVEMENT = 1, 8
bit = { band = function(a, b)
    assert(type(a) == "number" and type(b) == "number", "a secret reached bit.band")
    return a % 2 == 1 and b % 2 == 1 and 1 or 0
end }
GetTime = function() return 1 end

-- id -> { name, description, completed on the account, earned by this character, criteria }
-- criterion: { text, type, completed, flags, assetID, quantityString }
local GOLD = "5 |TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t / 10 |TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local achievements = {
    [1] = { "Deepwind Gorge Veteran", "Complete 100 victories in Deepwind Gorge.", false, false, {
        { "Complete 100 victories in Deepwind Gorge", 0, false, 1, 0, "74 / 100" } } },
    [2] = { "Glory of the Raider", "Complete the raid achievements.", false, false, {
        { "meta criterion", 8, false, 0, 500, "0 / 1" },
        { "Defeat the boss", 0, false, 0, 0, "0 / 1" },
        { "Already done", 0, true, 0, 0, "1 / 1" } } },
    [3] = { "Explorer", "Explore the hidden cave.", false, false, {} },
    [4] = { "Got My Mind On My Money", "Loot 10 gold.", false, false, { { "Loot 10 gold", 0, false, 1, 0, GOLD } } },
    [5] = { "Unreadable", "A description.", false, false, {
        { "secret flags", 0, false, secret, 0, "1 / 2" },
        { "secret count", 0, false, 1, 0, secret },
        { "secret state", 0, secret, 0, 0, "1 / 2" },
        { "secret kind", secret, false, 0, 500, "1 / 2" } } },
    [6] = { "Earned here", "Done.", true, true, { { "Done", 0, true, 0, 0, "1 / 1" } } },
    [7] = { "Earned by an alt", "Win 10 arenas.", true, false, { { "Win 10 arenas", 0, false, 1, 0, "3 / 10" } } },
    [8] = { "Unreadable owner", "Hidden.", false, secret, {} },
    [9] = { "No description", secret, false, false, { { "Win a duel", 0, false, 1, 0, "0 / 1" } } },
    [500] = { "Mythic: The First Boss", "Defeat the first boss.", false, false, {} },
}
GetAchievementInfo = function(id)
    local a = achievements[id]
    if not a then return nil end
    return id, a[1], 10, a[3], nil, nil, nil, a[2], 0, 1234, "", false, a[4], nil, false
end
GetAchievementNumCriteria = function(id) return #achievements[id][5] end
GetAchievementCriteriaInfo = function(id, index)
    local c = achievements[id][5][index]
    return c[1], c[2], c[3], 0, 0, "", c[4], c[5], c[6], 9000 + index, true
end
C_ContentTracking = { GetTrackedIDs = function(kind)
    assert(kind == Enum.ContentTrackingType.Achievement)
    return { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
end }

local tracker = O.M
tracker.config = { showAchievements = true }
tracker.dirty.achievements = true
O.CollectDirty(tracker)
local list, byID = tracker.sources.achievements, {}
for i = 1, list.count do byID[list[i].id] = list[i] end
local function Lines(id)
    local entry, out = assert(byID[id], "achievement " .. id .. " is missing from the tracker"), {}
    for j = 1, entry.lines.count do out[j] = entry.lines[j].text end
    return table.concat(out, " | ")
end
local function Expect(id, want, message)
    local got = Lines(id)
    assert(got == want, message .. ": " .. got)
end

Expect(1, "74/100 Complete 100 victories in Deepwind Gorge.", "a progress criterion must lead with its count")
Expect(2, "Mythic: The First Boss | Defeat the boss", "a meta criterion is the name of its achievement; done criteria stay hidden")
Expect(3, "Explore the hidden cave.", "an achievement without criteria is its description")
Expect(4, GOLD .. "\nLoot 10 gold.", "a money count gets its own line above the description")
Expect(5, "secret flags | secret count | secret kind", "unreadable criterion fields must fall back to the criterion's text")
Expect(7, "3/10 Win 10 arenas.", "an achievement another character earned stays tracked, as in Blizzard's tracker")
Expect(9, "Win a duel", "an unreadable description must leave the criterion's own text")
assert(not byID[6], "an achievement this character earned must leave the tracker")
assert(not byID[8], "an unreadable earned state must not show the achievement")
assert(byID[1].tracked == true and byID[1].group == "achievements" and byID[1].title == "Deepwind Gorge Veteran")
print("suite_objective_achievements_contract: ok")
