-- Zone grouping of watched quests (ObjectivesData.lua, Objectives.lua).
-- arg[2]: another tree whose module files are loaded instead, for a direct
-- comparison of the counts printed below (the fixture stays this tree's).
local root = assert(arg[1])
local source = arg[2] or root
-- The counts of another tree are that tree's: printed, not held to this tree's budget.
local function Budget(ok, message)
    if ok then return end
    if source == root then error(message, 2) end
    print("  not within this tree's budget: " .. message)
end
local function NewFixture(forever)
    local fixture = dofile(root .. "/tools/tests/comfort_fixture.lua").New(root, forever)
    function fixture.Module(file)
        assert(loadfile(source .. "/MSUF_Suite_Modules/" .. file))("MSUF_Suite_Modules", fixture.P)
    end
    return fixture
end

------------------------------------------------------------------ 1. the collection pass
do
    local fixture = NewFixture(true)
    fixture.Module("ObjectivesData.lua")
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
end

------------------------------------------------------------------ 2. zone events
-- The module with its events (2026-11-15): a subzone change inside the same
-- zone reads again what the zone groups are made from and collects the watched
-- quests again only when a group changed. Every other trigger collects as before.
-- Counts: a scan = one full collection of the watched quests (GetNumQuestWatches).
local QUESTS = 25
local function Run(forever)
    local flavor = forever and "Forever" or "Retail"
    local fixture = NewFixture(forever)
    local P, S, NS, secret = fixture.P, fixture.S, fixture.NS, fixture.secret
    fixture.Module("ObjectivesData.lua")
    local O = P.Objectives
    local calls, renders = {}, 0
    local function Counted(name, fn)
        return function(...)
            calls[name] = (calls[name] or 0) + 1
            return fn(...)
        end
    end
    local function Count(name) return calls[name] or 0 end
    local function Reset()
        for name in pairs(calls) do calls[name] = nil end
        renders = 0
    end

    -- Zone 2 with two small maps inside it, zone 3 with one, and their continent.
    local SMALL, ZONE, CONTINENT = 5, 3, 2
    local maps = { [2] = { mapType = ZONE, parentMapID = 1 }, [3] = { mapType = ZONE, parentMapID = 1 },
        [20] = { mapType = SMALL, parentMapID = 2 }, [21] = { mapType = SMALL, parentMapID = 2 },
        [30] = { mapType = SMALL, parentMapID = 3 }, [1] = { mapType = CONTINENT } }
    local world = { map = 20, focus = 4, questMaps = {}, complete = {}, kinds = {}, inRaid = false }
    for id = 1, QUESTS do world.questMaps[id] = id % 2 == 1 and 2 or 3 end
    -- An unreadable quest map, a quest in a small map of zone 3, a quest on the continent map.
    world.questMaps[3], world.questMaps[5], world.questMaps[7] = secret, 30, 1
    -- Completed: one with a zone of its own, one without.
    world.complete[6], world.complete[7] = true, true

    Enum = { UIMapType = { Zone = ZONE }, QuestClassification = { Campaign = 1, Important = 2, Legendary = 3 },
        ContentTrackingType = { Achievement = 2 } }
    C_Map = {
        GetBestMapForUnit = Counted("GetBestMapForUnit", function(unit) assert(unit == "player") return world.map end),
        GetMapInfo = Counted("GetMapInfo", function(map) return maps[map] end),
    }
    GetQuestUiMapID = Counted("GetQuestUiMapID", function(quest, ignoreWaypoints)
        assert(ignoreWaypoints == true)
        return world.questMaps[quest]
    end)
    GetTime = function() return 1 end
    C_SuperTrack = { GetSuperTrackedQuestID = Counted("GetSuperTrackedQuestID", function() return world.focus end) }
    C_QuestInfoSystem = { GetQuestClassification = Counted("GetQuestClassification", function(id) return world.kinds[id] end) }
    local objectives ={ { text = "Find the objective", finished = false }, { text = "Defeat the target", finished = false } }
    -- What the client withholds (f): an entry replaces the usual answer, NONE is no answer at all.
    local NONE = {}
    local function Answer(withheld, usual)
        if withheld == nil then return usual end
        if withheld == NONE then return nil end
        return withheld
    end
    world.ids, world.titles, world.objectives = {}, {}, {}
    C_QuestLog = {
        GetNumQuestWatches = Counted("GetNumQuestWatches", function() return Answer(world.watches, QUESTS) end),
        GetQuestIDForQuestWatchIndex = Counted("GetQuestIDForQuestWatchIndex", function(index)
            return Answer(world.ids[index], index)
        end),
        GetTitleForQuestID = Counted("GetTitleForQuestID", function(id) return Answer(world.titles[id], "Quest " .. id) end),
        GetQuestObjectives = Counted("GetQuestObjectives", function(id) return Answer(world.objectives[id], objectives) end),
        IsComplete = Counted("IsComplete", function(id)
            if world.complete[id] == secret then return secret end
            return world.complete[id] == true
        end),
        GetLogIndexForQuestID = Counted("GetLogIndexForQuestID", function(id) return Answer(world.logIndex, id) end),
        GetInfo = Counted("GetInfo", function() return Answer(world.info, { isAutoComplete = false }) end),
        GetTimeAllowed = Counted("GetTimeAllowed", function() return world.timeAllowed end),
        GetNumWorldQuestWatches = Counted("GetNumWorldQuestWatches", function() return 0 end),
    }
    C_TaskQuest = { GetQuestInfoByQuestID = function() end }
    C_LFGList = { GetActivityIDForQuestID = Counted("GetActivityIDForQuestID", function() return world.activity end) }
    QuestUtil = { QuestShowsItemByIndex = Counted("QuestShowsItemByIndex", function() return Answer(world.showsItem, true) end) }
    GetQuestLogSpecialItemInfo = Counted("GetQuestLogSpecialItemInfo", function()
        return Answer(world.itemLink, "item:123"), Answer(world.itemIcon, 42), nil, Answer(world.itemWhenComplete, false)
    end)
    GetTasksTable = Counted("GetTasksTable", function() return {} end)
    QUEST_WATCH_CLICK_TO_COMPLETE = "Click to complete"
    IsInInstance = function() return world.inRaid, world.inRaid and "raid" or "none" end
    C_InstanceEncounter = { IsEncounterInProgress = function() return false end }
    hooksecurefunc = function() end
    ObjectiveTrackerFrame = { GetChildren = function() end }
    UIWidgetObjectiveTracker = {}

    -- The parts of the tracker this contract does not draw.
    local host = fixture.Frame()
    O.Create = function(self) self.host = host end
    O.Render = function() renders = renders + 1 end
    O.UpdateQuestItem, O.UpdateTimers = function() end, function() end
    O.StopQuestMotion = function() return false end
    O.CONTENT_EVENTS, O.COLLECTED_EVENTS = {}, {}
    S.Dispatch = function(fn, ...) return fn(...) end
    S.ModuleState = function() return {} end
    S.GamepadUI = function() return false end
    fixture.Module("Objectives.lua")
    local module = assert(fixture.modules.objectives)

    -- The runtime's context (Runtime.lua, Timers.lua): a job runs once on the
    -- next frame however often it was requested.
    local context, jobs = { events = {} }, {}
    function context:Event(event, fn) self.events[event] = fn end
    function context:RemoveEvent(event) self.events[event] = nil end
    function context:HideControl() end
    function context:Scale() end
    function context:Coalesce(_, fn)
        local job = { fn = fn, pending = false }
        function job:Request() self.pending = true end
        function job:Cancel() self.pending = false end
        function job:Clear() self.pending = false end
        jobs[#jobs + 1] = job
        return job
    end
    local function Frame()
        local ran = 0
        for _, job in ipairs(jobs) do
            if job.pending then
                job.pending = false
                job.fn(module)
                ran = ran + 1
            end
        end
        return ran
    end
    local function Fire(event, ...)
        local handler = assert(context.events[event], event .. " is not registered")
        handler(module, event, ...)
    end
    -- One frame's events and the flush after them.
    local function Events(...)
        for i = 1, select("#", ...) do Fire((select(i, ...))) end
        return Frame()
    end

    -- What the groups must be, from the world alone.
    local function Zone(map)
        for _ = 1, 8 do
            local info = map ~= secret and maps[map]
            if not info or info.mapType < ZONE then return nil end
            if info.mapType == ZONE then return map end
            map = info.parentMapID
        end
    end
    local function Expected(id)
        if id == world.focus then return "focused" end
        local zone = module.config.groupQuestsByZone and Zone(world.map)
        local questZone = zone and Zone(world.questMaps[id])
        if questZone then return questZone == zone and "localQuests" or "otherQuests" end
        return world.complete[id] and "complete" or "quests"
    end
    local function CheckGroups(message)
        local list = module.sources.quests
        assert(list.count == QUESTS, flavor .. ": " .. message .. ": " .. list.count .. " quests collected")
        for i = 1, list.count do
            local entry = list[i]
            assert(entry.group == Expected(entry.id), ("%s: %s: quest %d is in '%s', not '%s'"):format(
                flavor, message, entry.id, tostring(entry.group), Expected(entry.id)))
        end
    end
    local function Scans() return Count("GetNumQuestWatches") end

    module.config = { groupQuestsByZone = true, showWorldQuests = true, showBonus = true }
    module.active, module.context = true, context
    module:Enable()
    assert(Scans() == 1 and renders == 1, flavor .. ": enabling did not collect the quests once")
    CheckGroups("enabled")
    local quests = module.sources.quests
    assert(quests[1].group == "localQuests" and quests[2].group == "otherQuests" and quests[3].group == "quests"
        and quests[4].group == "focused" and quests[5].group == "otherQuests" and quests[6].group == "otherQuests"
        and quests[7].group == "complete", flavor .. ": probe: the world does not cover every group")

    -- (a) Subzone changes inside the same zone: the tracker still flushes (world
    -- quests and bonus objectives are read, the rows are projected), and the
    -- zone groups are checked against the client.
    Reset()
    for round = 1, 4 do
        world.map = round % 2 == 0 and 20 or 21
        assert(Events(round % 2 == 0 and "ZONE_CHANGED" or "ZONE_CHANGED_INDOORS") == 1, flavor .. ": a subzone change did not flush")
        CheckGroups("subzone change " .. round)
    end
    print(("%s: 4 subzone changes inside one zone: %d scans, %d titles, %d objective reads, %d completion reads, "
        .. "%d player map reads, %d quest map reads, %d map infos"):format(flavor, Scans(), Count("GetTitleForQuestID"),
        Count("GetQuestObjectives"), Count("IsComplete"), Count("GetBestMapForUnit"), Count("GetQuestUiMapID"), Count("GetMapInfo")))
    assert(renders == 4 and Count("GetTasksTable") == 4 and Count("GetNumWorldQuestWatches") == 4,
        flavor .. ": a subzone change lost the world quest, bonus objective or row refresh")
    assert(Count("GetBestMapForUnit") == 4 and Count("GetSuperTrackedQuestID") == 4,
        flavor .. ": a subzone change did not read the player's zone and the focused quest once")
    assert(Count("GetQuestUiMapID") == 4 * (QUESTS - 1), flavor .. ": a subzone change did not read each unfocused quest's map once")
    Budget(Scans() == 0 and Count("GetTitleForQuestID") == 0 and Count("GetQuestObjectives") == 0
        and Count("IsComplete") == 0 and Count("GetLogIndexForQuestID") == 0 and Count("GetQuestLogSpecialItemInfo") == 0,
        flavor .. ": a subzone change inside the same zone collected the watched quests again")

    -- (b) What a subzone change can bring: each collects again, once.
    local function Regroups(message, change)
        Reset()
        change()
        Events("ZONE_CHANGED")
        assert(Scans() == 1, flavor .. ": " .. message .. ": " .. Scans() .. " scans, not 1")
        CheckGroups(message)
        Reset()
        Events("ZONE_CHANGED")
        Budget(Scans() == 0, flavor .. ": " .. message .. ": the next subzone change collected again")
        CheckGroups(message .. ", settled")
    end
    Regroups("another zone without a new-area event", function() world.map = 30 end)
    assert(quests[1].group == "otherQuests" and quests[2].group == "localQuests" and quests[5].group == "localQuests")
    Regroups("back", function() world.map = 20 end)
    Regroups("a quest's map moved to the other zone", function() world.questMaps[1] = 3 end)
    assert(quests[1].group == "otherQuests")
    Regroups("a quest's map became unreadable", function() world.questMaps[1] = secret end)
    assert(quests[1].group == "quests")
    Regroups("a completed quest's map became unreadable", function() world.questMaps[6] = secret end)
    assert(quests[6].group == "complete", flavor .. ": a completed quest without a zone left the completed group")
    Regroups("the quest maps are readable again", function() world.questMaps[1], world.questMaps[6] = 2, 3 end)
    assert(quests[1].group == "localQuests" and quests[6].group == "otherQuests",
        flavor .. ": the zone no longer comes before the completed group")
    Regroups("a quest without a zone got one", function() world.questMaps[7] = 2 end)
    assert(quests[7].group == "localQuests")
    Regroups("and lost it", function() world.questMaps[7] = 1 end)
    Regroups("the focus moved", function() world.focus = 9 end)
    assert(quests[9].group == "focused" and quests[4].group == "otherQuests")
    Regroups("the focus is unreadable", function() world.focus = secret end)
    Regroups("the focus is back", function() world.focus = 4 end)
    -- The player's zone unreadable, then a continent map, then readable.
    Regroups("the player's map is unreadable", function() world.map = secret end)
    assert(quests[1].group == "quests" and quests[6].group == "complete" and quests[4].group == "focused")
    -- A map without a zone is no zone either: nothing to group by, before and after.
    Reset()
    world.map = 1
    Events("ZONE_CHANGED_INDOORS")
    assert(Count("GetQuestUiMapID") == 0, flavor .. ": quest maps were read without a player zone")
    Budget(Scans() == 0, flavor .. ": a subzone change without a player zone collected the watched quests again")
    CheckGroups("the player is on a map without a zone")
    Regroups("the player's zone is readable again", function() world.map = 21 end)
    assert(quests[1].group == "localQuests" and quests[6].group == "otherQuests")

    -- (c) Every other trigger collects as before, once a frame.
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_POI_UPDATE",
        "QUEST_AUTOCOMPLETE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "SUPER_TRACKING_CHANGED",
        "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        Reset()
        Events(event)
        assert(Scans() == 1 and Count("GetTitleForQuestID") == QUESTS, flavor .. ": " .. event .. " did not collect the quests")
    end
    -- Progress with a subzone change in the same frame: one collection, which reads the zone itself.
    Reset()
    world.complete[1], world.map = true, 20
    Events("ZONE_CHANGED", "QUEST_LOG_UPDATE", "ZONE_CHANGED_INDOORS")
    assert(Scans() == 1 and Count("GetBestMapForUnit") == 1 and Count("IsComplete") >= QUESTS,
        flavor .. ": a quest update with a subzone change did not collect exactly once")
    CheckGroups("a quest update with a subzone change")
    world.questMaps[1] = secret
    Events("QUEST_POI_UPDATE")
    assert(quests[1].group == "complete", flavor .. ": completion was not collected")
    world.questMaps[1], world.complete[1] = 2, nil
    Events("QUEST_LOG_UPDATE")
    CheckGroups("progress")

    -- (d) Settings and lifecycle.
    module.config.groupQuestsByZone = false
    module:Refresh()
    CheckGroups("grouping switched off")
    assert(quests[1].group == "quests" and quests[6].group == "complete")
    Reset()
    world.map = 30
    Events("ZONE_CHANGED")
    assert(Scans() == 0 and Count("GetBestMapForUnit") == 0 and Count("GetQuestUiMapID") == 0 and renders == 1,
        flavor .. ": a subzone change without zone grouping read the zone or the quests")
    module.config.groupQuestsByZone = true
    module:Refresh()
    CheckGroups("grouping switched on")
    assert(quests[1].group == "otherQuests" and quests[5].group == "localQuests")
    Reset()
    Events("ZONE_CHANGED")
    Budget(Scans() == 0, flavor .. ": the subzone change after a settings change collected again")
    -- Hidden in a raid: nothing is heard; leaving collects everything for the zone the player is in then.
    module.config.hideInRaid, world.inRaid = true, true
    Fire("PLAYER_ENTERING_WORLD")
    assert(module.pausedForRaidCombat == true and not context.events.ZONE_CHANGED, flavor .. ": probe: the raid did not pause the tracker")
    world.map, world.inRaid = 20, false
    Reset()
    Fire("PLAYER_ENTERING_WORLD")
    Frame()
    assert(module.pausedForRaidCombat == false and Scans() >= 1, flavor .. ": leaving the raid did not collect the quests")
    CheckGroups("after the raid")
    module.config.hideInRaid = false
    -- A reload or a profile change: disabled and enabled again.
    module:Disable()
    world.map = 30
    module.active = true
    Reset()
    module:Enable()
    assert(Scans() == 1, flavor .. ": enabling again did not collect the quests")
    CheckGroups("enabled again")
    Reset()
    Events("ZONE_CHANGED")
    Budget(Scans() == 0, flavor .. ": the subzone change after enabling collected again")
    CheckGroups("subzone change after enabling")

    -- (f) Recovery (review of 2026-11-15). A collection that could not read a watch count, a quest ID,
    -- a title, the objectives or another detail of a quest is not a list to keep: every subzone change
    -- collects again, as before the zone check, until one collection reads everything. No quest event
    -- is fired between the client withholding the answer and giving it.
    world.map = 20
    Events("ZONE_CHANGED_NEW_AREA")
    local subzone = 20
    local function Subzone()
        subzone = subzone == 20 and 21 or 20
        world.map = subzone
        Reset()
        Events(subzone == 20 and "ZONE_CHANGED" or "ZONE_CHANGED_INDOORS")
        return Scans()
    end
    local function Recovers(message, withhold, give, withheld, restored)
        Budget(Subzone() == 0, flavor .. ": " .. message .. ": probe: the list before it was not kept")
        withhold()
        Events("QUEST_LOG_UPDATE")
        assert(not withheld or withheld(), flavor .. ": " .. message .. ": probe: nothing was withheld")
        for round = 1, 2 do
            assert(Subzone() == 1, ("%s: %s: subzone change %d with the answer withheld made %d scans, not 1"):format(
                flavor, message, round, Scans()))
        end
        give()
        local scans = Subzone()
        assert(scans == 1, flavor .. ": " .. message .. ": the subzone change after the client answered made "
            .. scans .. " scans, not 1")
        CheckGroups(message .. ", readable again")
        assert(not restored or restored(), flavor .. ": " .. message .. ": the quest was not restored")
        for i = 1, quests.count do
            assert(quests[i].lines.count == 2 and quests[i].title == "Quest " .. quests[i].id,
                flavor .. ": " .. message .. ": quest " .. quests[i].id .. " lost a line or its title")
        end
        Budget(Subzone() == 0, flavor .. ": " .. message .. ": the whole list was collected again on the next subzone change")
        CheckGroups(message .. ", settled")
    end
    local function Has(id)
        for i = 1, quests.count do
            if quests[i].id == id then return quests[i] end
        end
    end
    local recovered = 0
    for _, case in ipairs({
        { "the watch count is secret", function() world.watches = secret end, function() world.watches = nil end,
            function() return quests.count == 0 end },
        { "the watch count is missing", function() world.watches = NONE end, function() world.watches = nil end,
            function() return quests.count == 0 end },
        { "a watched quest's ID is secret", function() world.ids[2] = secret end, function() world.ids[2] = nil end,
            function() return not Has(2) and quests.count == QUESTS - 1 end, function() return Has(2) end },
        { "a watched quest's ID is missing", function() world.ids[2] = NONE end, function() world.ids[2] = nil end,
            function() return not Has(2) end, function() return Has(2) end },
        { "a title is secret", function() world.titles[8] = secret end, function() world.titles[8] = nil end,
            function() return not Has(8) and quests.count == QUESTS - 1 end, function() return Has(8) end },
        { "a title is missing", function() world.titles[8] = NONE end, function() world.titles[8] = nil end,
            function() return not Has(8) end, function() return Has(8) end },
        { "a quest's objectives are secret", function() world.objectives[8] = secret end,
            function() world.objectives[8] = nil end, function() return Has(8).lines.count == 0 end },
        { "a quest's objectives are missing", function() world.objectives[8] = NONE end,
            function() world.objectives[8] = nil end, function() return Has(8).lines.count == 0 end },
        { "one objective is secret", function() world.objectives[8] = { objectives[1], secret } end,
            function() world.objectives[8] = nil end, function() return Has(8).lines.count == 1 end },
        { "one objective's text is secret", function() world.objectives[8] = { { text = secret, finished = false }, objectives[2] } end,
            function() world.objectives[8] = nil end, function() return Has(8).lines.count == 1 end },
        { "one objective has no text", function() world.objectives[8] = { { finished = false }, objectives[2] } end,
            function() world.objectives[8] = nil end, function() return Has(8).lines.count == 1 end },
        { "one objective's state is secret", function() world.objectives[8] = { { text = "Find", finished = secret }, objectives[2] } end,
            function() world.objectives[8] = nil end, function() return Has(8).lines[1].text == "Find" end,
            function() return Has(8).lines[1].text == objectives[1].text end },
        { "one objective's kind is secret", function() world.objectives[8] = { { text = "Fill", type = secret }, objectives[2] } end,
            function() world.objectives[8] = nil end, function() return Has(8).lines[1].text == "Fill" end,
            function() return Has(8).lines[1].text == objectives[1].text end },
        -- Quest 6 is complete: read as not complete it shows the item only an open quest shows.
        { "a quest's completion is secret", function() world.complete[6] = secret end, function() world.complete[6] = true end,
            function() return Has(6).itemLink == "item:123" end, function() return Has(6).itemLink == nil end },
        { "a quest's kind is secret", function() world.kinds[3] = secret end, function() world.kinds[3] = nil end },
        { "the quest log index is secret", function() world.logIndex = secret end, function() world.logIndex = nil end,
            function() return Has(8).itemLink == nil end, function() return Has(8).itemLink == "item:123" end },
        { "a quest's log entry is secret", function() world.info = secret end, function() world.info = nil end },
        { "a quest's turn-in state is secret", function() world.info = { isAutoComplete = secret } end,
            function() world.info = nil end },
        { "whether a quest shows its item is secret", function() world.showsItem = secret end, function() world.showsItem = nil end,
            function() return Has(8).itemLink == nil end, function() return Has(8).itemLink == "item:123" end },
        { "the quest item's link is secret", function() world.itemLink = secret end, function() world.itemLink = nil end,
            function() return Has(8).itemLink == nil end, function() return Has(8).itemLink == "item:123" end },
        { "the quest item's icon is secret", function() world.itemIcon = secret end, function() world.itemIcon = nil end,
            function() return Has(8).itemIcon == nil end, function() return Has(8).itemIcon == 42 end },
        { "a completed quest's item rule is secret", function() world.itemWhenComplete = secret end,
            function() world.itemWhenComplete = nil end },
        { "a quest's time limit is secret", function() world.timeAllowed = secret end, function() world.timeAllowed = nil end },
        not forever and { "a quest's group activity is secret", function() world.activity = secret end,
            function() world.activity = nil end } or nil,
    }) do
        Recovers(case[1], case[2], case[3], case[4], case[5])
        recovered = recovered + 1
    end
    -- The zone and the focus are compared by what was read (b): unreadable with a detail withheld,
    -- then all of it readable at once.
    Recovers("the focus, the player's map and a title are secret",
        function() world.focus, world.map, world.titles[8] = secret, secret, secret end,
        function() world.focus, world.titles[8] = 4, nil end,
        function() return not Has(8) and Has(4).group ~= "focused" and Has(1).group == "quests" end,
        function() return Has(8) and Has(4).group == "focused" and Has(1).group == "localQuests" end)
    -- An emptied list is not a collected one: a tree with the zone check may not keep it.
    module.dirty.questZones = true
    O.CollectDirty(module)
    if module.dirty.questZones == nil then
        module:Disable()
        module.active = true
        assert(quests.count == 0, flavor .. ": probe: disabling did not empty the quests")
        module.dirty.questZones = true
        Reset()
        O.CollectDirty(module)
        assert(Scans() == 1 and quests.count == QUESTS, flavor .. ": a zone check kept the emptied quest list")
        module:Enable()
        CheckGroups("enabled after recovery")
    end
    module.dirty.questZones = nil
    print(("%s: %d withheld answers recovered by the next subzone change, each kept list re-checked without a scan"):format(
        flavor, recovered + 1))

    -- (e) Budget (Lua 5.1, a count hook every 100 instructions, this file's stubs included): 100 subzone
    -- changes inside one zone with 25 watched quests, each with its flush. Measured 2026-11-15 on Forever,
    -- before -> after: 1,930,100 -> 397,200 instructions; quest and map calls per change 256 -> 52
    -- (Retail: 2,055,800 -> 397,800 and 281 -> 52). 2% headroom on the instructions. With the known-list
    -- check and section (f) before this run: 397,900 (Retail 398,600), 52 calls.
    world.map = 20
    Events("ZONE_CHANGED_NEW_AREA")
    Reset()
    local instructions, total = 0, 0
    debug.sethook(function() instructions = instructions + 100 end, "", 100)
    for round = 1, 100 do
        world.map = round % 2 == 0 and 20 or 21
        Events("ZONE_CHANGED")
    end
    debug.sethook()
    for name, count in pairs(calls) do
        if name ~= "GetTasksTable" and name ~= "GetNumWorldQuestWatches" then total = total + count end
    end
    print(("%s: 100 subzone changes inside one zone, %d watched quests: %d Lua instructions, %g quest and map calls per change"):format(
        flavor, QUESTS, instructions, total / 100))
    CheckGroups("after the budget run")
    Budget(Scans() == 0, flavor .. ": the budget run collected the watched quests")
    Budget(total / 100 <= 52, flavor .. ": a subzone change inside one zone made " .. total / 100 .. " quest and map calls")
    Budget(instructions <= 397800 * 1.02, flavor .. ": subzone changes inside one zone exceed their Lua budget: " .. instructions)
end
Run(true)
Run(false)
print("suite_objective_zone_group_contract: ok")
