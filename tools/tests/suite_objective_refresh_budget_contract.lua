local root = assert(arg[1], "repository root required")
local source = arg[2] or root
local fixture = dofile(root .. "/tools/tests/comfort_fixture.lua").New(root, true)
local function Load(file)
    assert(loadfile(source .. "/MSUF_Suite_Modules/" .. file))("MSUF_Suite_Modules", fixture.P)
end
Load("ObjectivesData.lua")
Load("ObjectivesRows.lua")
local O, secret = fixture.P.Objectives, fixture.secret

local completionReads, indexReads, runs, instructions = 0, 0, 100, 0
local titles, completion, logInfo = {}, {}, {}
local questCount, focus = 25, 1
local objectives = {
    { text = "Find the objective", finished = false },
    { text = "Defeat the target", finished = false },
}
for id = 1, questCount do
    titles[id] = "Quest " .. id
    completion[id] = id % 2 == 0
    logInfo[id] = { isAutoComplete = id % 4 == 0 }
end
Enum = { QuestClassification = { Campaign = 1, Important = 2, Legendary = 3 } }
C_SuperTrack = { GetSuperTrackedQuestID = function() return focus end }
C_QuestInfoSystem = { GetQuestClassification = function() end }
C_QuestLog = {
    GetNumQuestWatches = function() return questCount end,
    GetQuestIDForQuestWatchIndex = function(index) return index end,
    GetTitleForQuestID = function(id) return titles[id] end,
    GetQuestObjectives = function() return objectives end,
    IsComplete = function(id) completionReads = completionReads + 1; return completion[id] end,
    GetLogIndexForQuestID = function(id) indexReads = indexReads + 1; return id end,
    GetInfo = function(index) return logInfo[index] end,
    GetTimeAllowed = function() end,
}
QuestUtil = { QuestShowsItemByIndex = function() return true end }
GetQuestLogSpecialItemInfo = function() return "item:123", 42, nil, false end
GetTime = function() return 1 end
QUEST_WATCH_CLICK_TO_COMPLETE = "Click to complete"

local tracker = O.M
tracker.config = {}
local function Collect()
    tracker.dirty.quests = true
    O.CollectDirty(tracker)
    return tracker.sources.quests
end
local groups = { quests = { "Quests" } }
local sectionKeys = { quests = "section:quests" }
local collapsedGroups, collapsedEntries = {}, {}
local items, flat, previous = {}, {}, {}
local function Project(buffer)
    return O.AddFlat(buffer, 0, "quests", items, tracker.config, collapsedGroups, collapsedEntries, groups, sectionKeys)
end

local entries = Collect()
for i = 1, entries.count do items[i] = entries[i] end
local length = Project(flat)
assert(Project(previous) == length)
local function Measure()
    completionReads, indexReads = 0, 0
    debug.sethook(function() instructions = instructions + 100 end, "", 100)
    for _ = 1, runs do
        Collect()
        local count = Project(flat)
        assert(count == length, "identical quest state changed the display size")
        for i = 1, count do assert(O.SameItem(flat[i], previous[i]), "identical objective row changed") end
        flat, previous = previous, flat
    end
    debug.sethook()
end
Measure()
print(("objective refresh budget: %d flushes, %d Lua instructions, %d completion reads, %d index reads"):format(
    runs, instructions, completionReads, indexReads))
assert(completionReads == runs * questCount, "watched quest completion was reread during a flush")
assert(indexReads == runs * questCount, "completion hint and quest item queried the same quest index twice")
-- The measured candidate uses 2,704,000 instructions. Allow 2% headroom.
assert(instructions <= 2758100, "warm quest collection or row projection exceeded its Lua budget")

assert(entries[1].group == "focused" and entries[1].itemLink == "item:123")
assert(entries[2].group == "complete" and entries[2].lines.count == 2 and not entries[2].itemLink)
assert(entries[4].lines[3].text == QUEST_WATCH_CLICK_TO_COMPLETE and entries[4].lines[3].done)
completion[4], completion[1] = false, true
entries = Collect()
assert(entries[4].group == "quests" and entries[4].lines.count == 2 and entries[4].itemLink == "item:123")
assert(entries[1].group == "focused" and not entries[1].itemLink, "focus must still take priority over completion grouping")
assert(not O.CanCompleteQuest(4), "click-time completion must read the current API")
completion[4] = true
assert(O.CanCompleteQuest(4), "click-time completion must follow native changes before the next flush")

completion[4], logInfo[2].isAutoComplete = secret, secret
entries = Collect()
assert(entries[4].lines.count == 2 and entries[2].lines.count == 2, "secret completion enabled an action")
tracker.config.showQuestItems = false
entries = Collect()
assert(not entries[4].itemLink and entries[8].lines.count == 3, "the item setting changed turn-in hints")

local function Mutate(buffer, index, field, value)
    assert(O.SameItem(buffer[index], previous[index]), "expected matching row before mutation")
    local old = buffer[index][field]
    buffer[index][field] = value
    assert(not O.SameItem(buffer[index], previous[index]), "row equality ignored " .. field)
    buffer[index][field] = old
end
Project(flat)
Project(previous)
Mutate(flat, 1, "collapsed", true)
Mutate(flat, 2, "itemLink", "item:456")
Mutate(flat, 2, "questIconAtlas", true)
Mutate(flat, 2, "timerEnd", 30)
Mutate(flat, 2, "collapseKey", "other")
Mutate(flat, 3, "contentID", 123)
Mutate(flat, 3, "done", true)
Mutate(flat, 3, "percent", 47)
local preview = O.FlatSlot(flat, 3)
assert(not preview.questID and not preview.menuTitle and not preview.done, "preview retained fields from a regular objective")
Project(flat)
assert(O.SameItem(flat[3], previous[3]), "regular objective failed to restore a reused preview slot")
local formerLine = flat[3]
collapsedEntries["quests:1"] = true
Project(flat)
assert(flat[3] == formerLine and formerLine.kind == "entry" and formerLine.questID == 2 and not formerLine.done,
    "row-kind change retained data from the previous line")
print("objective refresh budget, native action state and row reuse passed")
