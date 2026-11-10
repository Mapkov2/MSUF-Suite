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
    for _, file in ipairs({ "Stats", "Pages" }) do
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
end

CheckClient(false)
CheckClient(true)
print("Character panel native skills, PvP and defense verified on Retail and Forever")
