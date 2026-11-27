local root = assert(arg[1], "Suite root required")

local function CheckClient(forever)
    local env = setmetatable({}, { __index = _G })
    local calls, collapsed = {}, false
    local function Native(id, owner, fn)
        return function(...)
            assert(owner == forever, "wrong client called " .. id)
            calls[id] = (calls[id] or 0) + 1
            return fn(...)
        end
    end
    local function WrongProperty(_, key) error("Retail read Forever property " .. key) end
    local unavailable = setmetatable({}, { __index = WrongProperty })
    local function Number(v) if type(v) == "number" then return v end end
    local function Text(v) if type(v) == "string" then return v end end
    local ns = { Host = { Client = { isForever = forever }, IsCombatLocked = function() return false end },
        Suite = {}, Public = function() return true end, Number = Number, String = Text, Text = Text,
        Reputation = { OptionsKey = function() return "reputation" end } }
    env.C_SkillInfo = forever and {
        GetNumSkillLines = Native("skills", true, function() return 2 end),
        GetSkillLineInfo = Native("skill", true, function(i)
            if i == 1 then return { name = "Weapons", skillID = 6, parentSkillLineID = 0,
                isHeader = true, isCollapsed = collapsed } end
            return { name = "Defense", skillID = 95, parentSkillLineID = 0, skillLineCategoryID = 6,
                isHeader = false, rank = 150, maxRank = 175 }
        end),
        CollapseSkillHeader = Native("collapse", true, function(i)
            assert(i == 1)
            collapsed = true
        end),
        ExpandSkillHeader = Native("expand", true, function(i)
            assert(i == 1)
            collapsed = false
        end),
    } or unavailable
    env.C_MajorFactions = forever and { GetMajorFactionProgressionInfo = Native("pvp", true, function(id)
        assert(id == 2800)
        return { renownLevel = 3, renownReputationEarned = 2, renownLevelThreshold = 10, maxLevel = 7 }
    end) } or unavailable
    env.UnitDefenseSkill = Native("defense", true, function(unit)
        assert(unit == "player")
        return 150, 6
    end)
    env.GetCurrentArenaSeason = Native("season", true, function() return 1 end)
    env.GetProfessions = Native("professions", false, function() end)
    env.TRADE_SKILLS = "Trade Skills"
    env.UnitHonorLevel = Native("honorLevel", false, function() return 3 end)
    env.UnitHonor = Native("honor", false, function() return 2 end)
    env.UnitHonorMax = Native("honorMax", false, function() return 10 end)
    -- Statistics: two categories; the first statistic of the second is skipped.
    local statCalls, emptyList = 0, false
    local function Stat(id, fn)
        return function(...)
            statCalls, calls[id] = statCalls + 1, (calls[id] or 0) + 1
            return fn(...)
        end
    end
    env.GetStatisticsCategoryList = Stat("categories", function() return emptyList and {} or { 10, 20 } end)
    env.GetCategoryInfo = Stat("categoryInfo", function(id) return id == 10 and "Combat" or "Quests" end)
    env.GetCategoryNumAchievements = Stat("categoryCount", function() return 2 end)
    env.GetStatistic = Stat("statistic", function(category, index)
        if category == 20 and index == 1 then return "--", true, 2001 end
        return tostring(category * 10 + index), false, category * 100 + index
    end)
    env.GetAchievementInfo = Stat("achievement", function(id) return id, "Statistic " .. id end)
    local watchers = {}
    env.CreateFrame = function(kind)
        assert(kind == "Frame" and #watchers == 0, "the statistics cache created more than one watcher")
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterAllEvents() for event in pairs(self.events) do self.events[event] = nil end end
        function frame:SetScript(script, callback) self[script] = callback end
        watchers[1] = frame
        return frame
    end
    for _, file in ipairs({ "Stats", "Pages", "Statistics" }) do
        local chunk = assert(loadfile(root .. "/MSUF_Suite_CharacterPanel/" .. file .. ".lua"))
        setfenv(chunk, env)("MSUF_Suite_CharacterPanel", ns)
    end
    assert(#ns.Pages.Read("skills", {}, {}) > 0 and #ns.Pages.Read("pvp", {}, {}) > 0)
    if forever then
        assert(ns.Pages.Toggle("skills", 1) and collapsed)
        assert(ns.Pages.Toggle("skills", 1) and not collapsed)
        assert(calls.skills == 1 and calls.skill == 4 and calls.pvp == 1 and calls.season == 1)
        assert(calls.collapse == 1 and calls.expand == 1 and calls.defense == 1)
        local lines = 0
        ns.Stats.DefenseTooltip({ AddDoubleLine = function() lines = lines + 1 end })
        assert(lines == 2 and calls.defense == 2)
    else
        assert(not ns.Pages.Toggle("skills", 1))
        ns.Stats.DefenseTooltip({ AddDoubleLine = function() error("Retail rendered Defense") end })
        assert(calls.professions == 1 and calls.honorLevel == 1 and calls.honor == 1 and calls.honorMax == 1)
    end

    -- Statistics change only with achievement criteria: a reopen or tab switch
    -- reuses the last complete read until CRITERIA_UPDATE (Blizzard_Statistics'
    -- own refresh) or RECEIVED_ACHIEVEMENT_LIST drops it.
    local function Labels(list)
        local out = {}
        for _, group in ipairs(list) do
            out[#out + 1] = group.title
            for _, row in ipairs(group.rows) do out[#out + 1] = row.label .. "=" .. tostring(row.value) end
        end
        return table.concat(out, "|")
    end
    local groups = {}
    assert(ns.Pages.Read("statistics", groups, {}) == groups)
    local first = Labels(groups)
    assert(first == "Combat|Statistic 1001=101|Statistic 1002=102|Quests|Statistic 2002=202", first)
    local watcher = assert(watchers[1], "the statistics cache did not watch for criteria changes")
    assert(watcher.events.CRITERIA_UPDATE and watcher.events.RECEIVED_ACHIEVEMENT_LIST and watcher.OnEvent,
        "the statistics cache did not watch both criteria events")
    ns.Pages.Read("pvp", groups, {})
    assert(Labels(groups) ~= first, "the PvP page did not replace the statistics groups")
    local before = statCalls
    assert(ns.Pages.Read("statistics", groups, {}) == groups and Labels(groups) == first and statCalls == before,
        "an unchanged statistics page called the client again or lost rows to another page")
    watcher.OnEvent(watcher, "CRITERIA_UPDATE")
    assert(not next(watcher.events), "the criteria watcher stayed registered after its event")
    ns.Pages.Read("statistics", groups, {})
    assert(statCalls > before and Labels(groups) == first and watcher.events.CRITERIA_UPDATE,
        "a criteria change did not reread the statistics")
    ns.Statistics.Drop()
    assert(not next(watcher.events), "dropping the statistics cache left its watcher registered")
    -- An empty read is never cached: achievement data may not be loaded yet.
    emptyList, before = true, calls.categories
    local empty = {}
    ns.Pages.Read("statistics", empty, {})
    ns.Pages.Read("statistics", empty, {})
    assert(calls.categories == before + 2 and #empty == 1 and empty[1].title == "No data available"
        and not next(watcher.events), "an empty statistics read was cached")
end

CheckClient(false)
CheckClient(true)
print("Character panel native skills, PvP and defense verified on Retail and Forever")
