local root = assert(arg[1], "repository root required")
local source = arg[2] or root
local selected = arg[3]

local function Load(path, private)
    local file = io.open(source .. "/" .. path, "rb")
    local base = root
    if file then file:close(); base = source end
    local chunk = assert(loadfile(base .. "/" .. path))
    return chunk("Suite", private)
end

local function Upvalue(fn, wanted, seen)
    seen = seen or {}
    if seen[fn] then return end
    seen[fn] = true
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    for index = 1, 200 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if type(value) == "function" then
            local found = Upvalue(value, wanted, seen)
            if found then return found end
        end
    end
end

local function New(forever)
    local fixture = dofile(root .. "/tools/tests/comfort_fixture.lua").New(root, forever)
    Load("MSUF_Suite_Modules/ObjectivesData.lua", fixture.P)
    local reads = 0
    Enum = { QuestClassification = { Campaign = 1, Important = 2, Legendary = 3 } }
    GetTime = function() return 100 end
    C_SuperTrack = { GetSuperTrackedQuestID = function() return 1 end }
    C_QuestInfoSystem = { GetQuestClassification = function() end }
    C_QuestLog = {
        GetNumQuestWatches = function() return 1 end,
        GetQuestIDForQuestWatchIndex = function() return 1 end,
        GetTitleForQuestID = function() return "Quest" end,
        GetQuestObjectives = function()
            reads = reads + 1
            return { { text = "Finished", finished = true }, { text = "Unfinished", finished = false },
                { text = "Restricted", finished = fixture.secret } }
        end,
        IsComplete = function() return true end,
        GetLogIndexForQuestID = function() return 1 end,
        GetInfo = function() return { isAutoComplete = true } end,
        GetTimeAllowed = function() return 90, 30 end,
    }
    QuestUtil = { QuestShowsItemByIndex = function() return true end }
    GetQuestLogSpecialItemInfo = function() return "item:123", 42, nil, true end
    QUEST_WATCH_CLICK_TO_COMPLETE = "Click to complete"
    C_LFGList = { GetActivityIDForQuestID = function() return 0 end }
    GetTasksTable = function() return { 2 } end
    QuestUtils_IsQuestWorldQuest = function() return false end
    GetTaskInfo = function() return true, false, 2, "Bonus" end
    GetQuestObjectiveInfo = function(_, index) return "Bonus " .. index, "monster", index == 1 end
    C_TaskQuest = { GetQuestTimeLeftSeconds = function() return 60 end }
    local owner = fixture.P.Objectives.M
    owner.config = { showQuestItems = true, showTimers = true, showBonus = true }
    function fixture.Collect(hidden)
        owner.config.hideCompletedObjectives = hidden
        owner.dirty.quests, owner.dirty.bonus = true, true
        fixture.P.Objectives.CollectDirty(owner)
        return owner.sources.quests[1], owner.sources.bonus[1], reads
    end
    return fixture, owner
end

local function Collection(forever)
    local fixture = New(forever)
    local quest, bonus, reads = fixture.Collect(false)
    assert(quest.lines.count == 4 and bonus.lines.count == 2, "the default must retain all objective lines")
    local item, deadline = quest.itemLink, quest.timerEnd
    local pooled = quest
    quest, bonus = fixture.Collect(true)
    assert(quest == pooled and quest.lines.count == 3, "hidden objectives must work with reused entries")
    assert(quest.lines[1].text == "Unfinished" and quest.lines[2].text == "Restricted",
        "unfinished and unreadable completion states must stay visible")
    assert(quest.lines[3].text == QUEST_WATCH_CLICK_TO_COMPLETE and quest.lines[3].done == true,
        "the actionable completion line must survive the ordinary-objective filter")
    assert(bonus.lines.count == 1 and bonus.lines[1].text == "Bonus 2", "bonus objectives must use the same filter")
    assert(quest.itemLink == item and quest.timerEnd == deadline, "filtering must preserve the quest item and timer")
    quest, bonus, reads = fixture.Collect(false)
    assert(quest.lines.count == 4 and bonus.lines.count == 2 and reads == 3,
        "turning the filter off must restore lines without another API scan per collection")
end

local function ProgressReuse(forever)
    local fixture, owner = New(forever)
    local objective = { text = "Wolf: 1/3", numFulfilled = 1, numRequired = 3, type = "monster" }
    C_QuestLog.GetQuestObjectives = function() return { objective } end
    owner.config.questProgressColumn = true
    local splits = 0
    debug.sethook(function()
        if debug.getinfo(2, "n").name == "gsub" and debug.getinfo(3, "n").name == "SplitQuestProgress" then splits = splits + 1 end
    end, "c")
    local quest = fixture.Collect(false)
    assert(quest.lines[1].text == "Wolf" and quest.lines[1].progressText == "1/3")
    local first = splits
    quest = fixture.Collect(false)
    assert(first > 0 and splits == first, "unchanged public quest progress was parsed again")
    objective.text, objective.numFulfilled = "Wolf: 2/3", 2
    quest = fixture.Collect(false)
    assert(quest.lines[1].text == "Wolf" and quest.lines[1].progressText == "2/3")
    objective.text = "Wolf：2/3"
    quest = fixture.Collect(false)
    assert(quest.lines[1].text == "Wolf" and quest.lines[1].progressText == "2/3", "fullwidth progress separator lost")
    objective.numFulfilled = fixture.secret
    quest = fixture.Collect(false)
    assert(quest.lines[1].text == objective.text and quest.lines[1].progressText == nil)
    debug.sethook()
end

local function Colors(forever)
    local fixture, owner = New(forever)
    local O = fixture.P.Objectives
    Load("MSUF_Suite_Modules/ObjectivesRows.lua", fixture.P)
    Load("MSUF_Suite_Modules/ObjectivesTracker.lua", fixture.P)
    local paint = assert(Upvalue(O.Render, "PaintRowState"))
    local actual
    local row = { text = { SetTextColor = function(_, ...) actual = { ... } end },
        EnableMouse = function() end, progress = { Hide = function() end } }
    owner.textRGB, owner.mutedRGB, owner.completeRGB = { .9, .9, .9 }, { .5, .5, .5 }, { .1, .9, .1 }
    local focus = { .2, .3, .4 }
    local entry = { kind = "entry", group = "focused", questID = 1 }
    paint(owner, row, entry, focus)
    assert(actual[1] == .9, "focus title tint must default off")
    owner.config.focusedTitleColor = true
    paint(owner, row, entry, focus)
    assert(actual[1] == focus[1] and actual[2] == focus[2], "focused title must use its existing group color")
    entry.group = "quests"
    paint(owner, row, entry, focus)
    assert(actual[1] == .9, "other quest titles must keep the normal text color")
    entry.kind, entry.group, entry.done = "line", "focused", true
    paint(owner, row, entry, focus)
    assert(actual[1] == .1 and actual[2] == .9, "completed objective color must remain independent")
end

local function Preview(forever)
    local labels = {}
    local function Noop() end
    local V = { Label = function(_, text, _, _, _, _, color)
        labels[text] = color
        return { SetJustifyH = Noop }
    end, Fill = function() return { SetDrawLayer = Noop } end,
        Color = function(c, key, fallback) return unpack(c[key] or fallback) end }
    local P = { HUDPreview = V, Tr = function(text) return text end,
        Suite = { Client = { isForever = forever } } }
    Load("MSUF_Suite_Options/Pages/HUDPreviewSamples.lua", P)
    local c = { width = 310, height = 570, showHeader = true, titleSize = 18, sectionSize = 14,
        entrySize = 15, objectiveSize = 13, questIconStyle = 1, showTimers = true, backgroundOpacity = 0,
        focusedColor = { .2, .3, .4 }, textColor = { .9, .9, .9 } }
    local ui = { config = c }
    local _, fullHeight = V.Render.objectives(ui, "focused")
    assert(labels["5/5  Defeat enemies"] and labels["Example Quest"][1] == .9, "the default preview must be unchanged")
    for text in pairs(labels) do labels[text] = nil end
    c.hideCompletedObjectives, c.focusedTitleColor = true, true
    local _, compactHeight = V.Render.objectives(ui, "focused")
    assert(not labels["5/5  Defeat enemies"] and labels["3/8  Collect supplies"] and labels["2:34"],
        "the preview filter must keep unfinished objectives and timers")
    assert(compactHeight < fullHeight and labels["Example Quest"][1] == .2,
        "the preview must reflect compact height and the existing focus color")
    labels = {}
    c.questProgressColumn = true
    V.Render.objectives(ui, "focused")
    assert(labels["Collect supplies"] and labels["3/8"] and not labels["3/8  Collect supplies"],
        "the preview must separate progress when the tracker uses a column")
end

local function Signature(forever)
    local fixture = New(forever)
    local O = fixture.P.Objectives
    O.CONTENT_EVENTS, O.COLLECTED_EVENTS = {}, {}
    Load("MSUF_Suite_Modules/Objectives.lua", fixture.P)
    local signature = assert(Upvalue(O.M.Refresh, "ContentSignature"))
    local c = { hideCompletedObjectives = false }
    local before = signature(c)
    c.hideCompletedObjectives = true
    assert(signature(c) ~= before, "changing the filter must invalidate the collected source snapshot")
end

for _, forever in ipairs({ false, true }) do
    for name, run in pairs({ collection = Collection, progressReuse = ProgressReuse, colors = Colors, preview = Preview, signature = Signature }) do
        if not selected or selected == name then
            run(forever)
            print("objective-details " .. name .. " " .. (forever and "Forever" or "Retail") .. ": passed")
        end
    end
end
