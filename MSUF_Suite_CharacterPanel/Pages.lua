local _, NS = ...
local Host, Suite = NS.Host, NS.Suite
local Number, String, Public, Text = NS.Number, NS.String, NS.Public, NS.Text
local Forever = Host.Client.isForever
local Pages = {}
NS.Pages = Pages

local quickEvents = {
    "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_STATS",
}
local ratingEvents = { "UNIT_SPELL_HASTE", "COMBAT_RATING_UPDATE", "PLAYER_DAMAGE_DONE_MODS" }
if not Forever then
    for index = 1, #ratingEvents do quickEvents[#quickEvents + 1] = ratingEvents[index] end
    quickEvents[#quickEvents + 1] = "MASTERY_UPDATE"
end
local extraStatEvents = { "UNIT_RESISTANCES" }
if Forever then
    for index = 1, #ratingEvents do extraStatEvents[#extraStatEvents + 1] = ratingEvents[index] end
    extraStatEvents[#extraStatEvents + 1] = "SKILL_LINES_CHANGED"
else
    extraStatEvents[#extraStatEvents + 1] = "AVOIDANCE_UPDATE"
end
Pages.ExtraStatEvents = extraStatEvents
Pages.Events = {
    overview = quickEvents,
    reputation = { "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED" },
    skills = { "SKILL_LINES_CHANGED" },
    pvp = Forever and { "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" }
        or { "HONOR_XP_UPDATE", "HONOR_LEVEL_UPDATE" },
    currency = { "CURRENCY_DISPLAY_UPDATE" },
    statistics = { "CRITERIA_UPDATE" },
}

local function IsTable(value)
    return Public(value) and type(value) == "table"
end

local function Flag(value)
    return Public(value) and value == true
end

-- A buffer belongs to its caller's visible groups array. Keep detached rows
-- and groups available for the next paint without exposing stale entries.
local buffers = setmetatable({}, { __mode = "k" })
local function Buffer(groups)
    local buffer = buffers[groups]
    if not buffer then
        buffer = { groups = {}, keys = {}, count = 0 }
        buffers[groups] = buffer
    end
    buffer.count = 0
    return buffer
end

local function Group(buffer, title, action, collapsed, depth, layout)
    local index = buffer.count + 1
    local group = buffer.groups[index]
    if not group then
        group = { rows = {}, pool = {} }
        buffer.groups[index] = group
    end
    buffer.count, group.count = index, 0
    group.title, group.action, group.collapsed, group.depth = title, action, collapsed, depth
    group.layout = layout
    return group
end

local function Row(group, label, value, layout)
    local index = group.count + 1
    local row = group.pool[index]
    if not row then
        row = {}
        group.pool[index] = row
    end
    row.label, row.value, row.layout = label, value or "—", layout
    group.rows[index], group.count = row, index
end

local function Finish(buffer, groups)
    for index = 1, buffer.count do
        local group = buffer.groups[index]
        for row = #group.rows, group.count + 1, -1 do group.rows[row] = nil end
        groups[index] = group
    end
    for index = #groups, buffer.count + 1, -1 do groups[index] = nil end
    return groups
end

local function Percentage(value)
    if value then return string.format("%.2f%%", value) end
end

local function Progress(current, maximum)
    if not current then return nil end
    if maximum and maximum > 0 then return string.format("%d / %d", current, maximum) end
    return current
end

local attributes = {
    LE_UNIT_STAT_STRENGTH, LE_UNIT_STAT_AGILITY, LE_UNIT_STAT_STAMINA, LE_UNIT_STAT_INTELLECT,
}
if Forever then attributes[#attributes + 1] = LE_UNIT_STAT_SPIRIT end

local function Attribute(id)
    if id then return Number(select(2, UnitStat("player", id))) end
end

local function Stat(group, id)
    if not id then return end
    local label = String(_G["SPELL_STAT" .. id .. "_NAME"])
    if label then Row(group, label, Attribute(id)) end
end

local function Health()
    return Number(UnitHealthMax("player"))
end

local function Resource()
    local _, token = UnitPowerType("player")
    token = String(token)
    local label = token and String(_G[token])
    if label then return Number(UnitPowerMax("player")), label end
end

local function Vitals(group)
    Row(group, HEALTH, Health())
    local value, label = Resource()
    if label then Row(group, label, value) end
end

local function Armor()
    return Number(select(2, UnitArmor("player")))
end

local function Dodge()
    return Percentage(Number(GetDodgeChance()))
end

local function Defense()
    local base, bonus = UnitDefenseSkill("player")
    base, bonus = Number(base), Number(bonus)
    return base and bonus and base + bonus
end

local function Avoidance()
    return Percentage(Number(GetAvoidance()))
end

local function Enhancements(group)
    Row(group, STAT_CRITICAL_STRIKE, Percentage(Suite.ReadCrit()))
    Row(group, STAT_HASTE, Percentage(Suite.ReadHaste()))
    if not Forever then
        Row(group, STAT_MASTERY, Percentage(Suite.ReadMastery()))
        Row(group, STAT_VERSATILITY, Percentage(Suite.ReadVersatility()))
    end
end

local function ReadStats(buffer)
    local attributesGroup = Group(buffer, Text("Attributes"))
    Vitals(attributesGroup)
    for index = 1, #attributes do Stat(attributesGroup, attributes[index]) end
    Enhancements(Group(buffer, Text("Enhancements")))
    local defense = Group(buffer, Text("Defense"))
    Row(defense, STAT_ARMOR, Armor())
    Row(defense, STAT_DODGE, Dodge())
    if Forever then
        Row(defense, DEFENSE, Defense())
    else
        Row(defense, STAT_AVOIDANCE, Avoidance())
    end
end

local function PrimaryAttribute()
    local spec = Number(C_SpecializationInfo.GetSpecialization())
    if spec and spec > 0 then
        local sex = Number(UnitSex("player"))
        return Number(select(6, C_SpecializationInfo.GetSpecializationInfo(spec, false, false, nil, sex)))
    end
end

local function ReadQuickStats(buffer)
    local group = Group(buffer, Text("At a glance"))
    local attribute = PrimaryAttribute()
    if Forever then
        Vitals(group)
        Stat(group, attribute)
        Stat(group, LE_UNIT_STAT_SPIRIT)
        Stat(group, LE_UNIT_STAT_STAMINA)
    else
        if attribute then Stat(group, attribute) else Vitals(group) end
        Enhancements(group)
    end
end

function Pages.Overview(groups, fullStats, combat)
    local buffer = Buffer(groups)
    if combat then
        Vitals(Group(buffer, Text("Attributes")))
        Group(buffer, Text("Full stats after combat"))
    elseif fullStats then
        ReadStats(buffer)
    else
        ReadQuickStats(buffer)
    end
    return Finish(buffer, groups)
end

local Model = Host.CharacterTabs
local NO_DATA = Text("No data available")
local statChange = { "UNIT_STATS" }
local ratingChange = { "UNIT_STATS", "COMBAT_RATING_UPDATE" }
local auditChange = {
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED",
    "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED",
}

function Pages.AuditCount(gear, key)
    local count = gear[key] or 0
    if count > 0 or not ((gear.unverified or 0) > 0 or gear.missingLinks) then return count end
end

function Pages.Durability(gear)
    local durability = gear.durability
    if durability then return string.format("%d%%", durability) end
end

function Pages.EquipmentSummary(groups, model)
    local rows = {}
    local durability = Pages.Durability(model)
    if durability then
        rows[#rows + 1] = { label = Text("Durability"), value = durability,
            action = (model.wornSlots or 0) > 0 and "durability" or nil }
    end
    if not Forever then
        local missing = Pages.AuditCount(model, "missingEnchants")
        local empty = Pages.AuditCount(model, "emptySockets")
        rows[#rows + 1] = { label = Text("Missing enchants"), value = missing or "—",
            action = missing and missing > 0 and "enchants" or nil }
        rows[#rows + 1] = { label = Text("Empty sockets"), value = empty or "—",
            action = empty and empty > 0 and "sockets" or nil }
    end
    if #rows == 0 then return end
    groups[#groups + 1] = {
        title = Text("Equipment check"),
        rows = rows,
    }
end

local function ReadAttribute(id)
    return function() return Attribute(id) end
end

local function ReadPercent(reader)
    return function() return Percentage(reader()) end
end

local function ReadXP()
    local current = Number(UnitXP("player"))
    local maximum = Number(UnitXPMax("player"))
    if maximum and maximum > 0 then return Progress(current, maximum) end
end

local function ReadItemLevel(state)
    if state.average then return string.format("%.0f", state.average) end
end

local function ReadDurability(state)
    return Pages.Durability(state.gear)
end

local providers = {
    itemLevel = { ReadItemLevel, { "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }, header = "average" },
    durability = { ReadDurability, { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }, durability = true },
    missingEnchants = { function(state) return Pages.AuditCount(state.gear, "missingEnchants") end, auditChange, audit = true },
    emptySockets = { function(state) return Pages.AuditCount(state.gear, "emptySockets") end, auditChange, audit = true },
    health = { Health, { "UNIT_MAXHEALTH" } },
    resource = { Resource, { "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" } },
    strength = { ReadAttribute(attributes[1]), statChange },
    agility = { ReadAttribute(attributes[2]), statChange },
    stamina = { ReadAttribute(attributes[3]), statChange },
    intellect = { ReadAttribute(attributes[4]), statChange },
    spirit = { ReadAttribute(attributes[5]), statChange },
    crit = { ReadPercent(Suite.ReadCrit), { "UNIT_STATS", "COMBAT_RATING_UPDATE", "PLAYER_DAMAGE_DONE_MODS" } },
    haste = { ReadPercent(Suite.ReadHaste), { "UNIT_SPELL_HASTE", "COMBAT_RATING_UPDATE" } },
    mastery = { ReadPercent(Suite.ReadMastery), { "MASTERY_UPDATE", "COMBAT_RATING_UPDATE" } },
    versatility = { ReadPercent(Suite.ReadVersatility), ratingChange },
    armor = { Armor, { "UNIT_RESISTANCES", "UNIT_STATS" } },
    dodge = { Dodge, ratingChange },
    defense = { Defense, { "SKILL_LINES_CHANGED", "UNIT_STATS" } },
    avoidance = { Avoidance, { "AVOIDANCE_UPDATE", "COMBAT_RATING_UPDATE" } },
    level = { function(state) return state.header.level end, { "PLAYER_LEVEL_UP" }, header = "level" },
    xp = { ReadXP, { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" } },
}

-- Only chosen, supported sources can register events or read values. A row
-- plan caches the display label and source index until the definition changes.
local plans = setmetatable({}, { __mode = "k" })
local combatLockedSources = {
    strength = true, agility = true, stamina = true, intellect = true, spirit = true,
    crit = true, haste = true, mastery = true, versatility = true,
    armor = true, dodge = true, defense = true, avoidance = true,
}

local function AddProvider(plan, provider, unique, events)
    local index = unique[provider]
    if index then return index end
    index = #plan.readers + 1
    unique[provider], plan.readers[index] = index, provider[1]
    for _, event in ipairs(provider[2]) do
        if not events[event] then
            events[event] = true
            plan.events[#plan.events + 1] = event
        end
    end
    if provider.audit then plan.audit = true end
    if provider.durability then plan.durability = true end
    if provider.header then plan[provider.header] = true end
    return index
end

function Pages.CustomPlan(definition)
    local plan = plans[definition]
    if plan then return plan end
    plan = { cards = {}, events = {}, readers = {}, values = {}, labels = {}, samples = {}, combatLocked = {} }
    local unique, events = {}, {}
    for i, card in ipairs(definition.cards) do
        local x, y = Model.Position(card)
        local target = { title = card.title, rows = {}, x = x, y = y, rowUp = 0, rowDown = 0 }
        plan.cards[i] = target
        for j, row in ipairs(card.rows) do
            local source = Model.Source(row.source)
            local provider = Model.SourceAvailable(row.source) and providers[row.source]
            local rowX, rowY = Model.Position(row)
            target.rowUp, target.rowDown = math.max(target.rowUp, rowY), math.max(target.rowDown, -rowY)
            local index = provider and AddProvider(plan, provider, unique, events) or nil
            if index then
                plan.samples[index] = source.sample
                plan.combatLocked[index] = combatLockedSources[row.source]
            end
            target.rows[j] = {
                x = rowX, y = rowY,
                index = index,
                label = row.label ~= "" and row.label or nil,
                defaultLabel = source and source.text or NO_DATA,
            }
        end
    end
    plans[definition] = plan
    return plan
end

local sampleLabels = {}
function Pages.Custom(groups, plan, state, combat)
    local buffer = Buffer(groups)
    local values, labels = plan.values, plan.labels
    if state then
        for i = 1, #plan.readers do
            if combat and plan.combatLocked[i] then
                values[i], labels[i] = nil, nil
            else
                values[i], labels[i] = plan.readers[i](state)
            end
        end
    else
        values, labels = plan.samples, sampleLabels
    end
    for i = 1, #plan.cards do
        local card = plan.cards[i]
        local group = Group(buffer, card.title, nil, nil, nil, card)
        for j = 1, #card.rows do
            local row = card.rows[j]
            Row(group, row.label or labels[row.index] or row.defaultLabel, values[row.index], row)
        end
    end
    if buffer.count == 0 then Group(buffer, NO_DATA) end
    return Finish(buffer, groups)
end

local function ReputationStanding(info, sex)
    local id = Number(info.factionID)
    if id and id > 0 then
        if Flag(C_Reputation.IsMajorFaction(id)) then
            local renown = C_MajorFactions.GetMajorFactionData(id)
            local level = IsTable(renown) and Number(renown.renownLevel)
            if level then return RENOWN_LEVEL_LABEL:format(level) end
        end
        local friendship = C_GossipInfo.GetFriendshipReputation(id)
        local reaction = IsTable(friendship) and String(friendship.reaction)
        if reaction then return reaction end
    end
    local reaction = Number(info.reaction)
    if reaction and sex then return String(GetText("FACTION_STANDING_LABEL" .. reaction, sex)) end
end

local function ReadReputation(buffer)
    local group
    local sex = Number(UnitSex("player"))
    for index = 1, Number(C_Reputation.GetNumFactions()) or 0 do
        local info = C_Reputation.GetFactionDataByIndex(index)
        local name = IsTable(info) and String(info.name)
        if name then
            if Flag(info.isHeader) then
                group = Group(buffer, name, index, Flag(info.isCollapsed), Flag(info.isChild) and 1 or 0)
                if Flag(info.isHeaderWithRep) then Row(group, Text("Reputation"), ReputationStanding(info, sex)) end
            else
                group = group or Group(buffer, Text("Reputation"))
                Row(group, name, ReputationStanding(info, sex))
            end
        end
    end
end

local DEFENSE_SKILL = 95
local CLASS_SKILL_CATEGORY = 7
local function ReadSkills(buffer)
    local group
    for index = 1, Number(C_SkillInfo.GetNumSkillLines()) or 0 do
        local info = C_SkillInfo.GetSkillLineInfo(index)
        local name = IsTable(info) and String(info.name)
        local header = name and Flag(info.isHeader)
        local categoryKey = header and "skillID" or "skillLineCategoryID"
        local category = name and Number(info[categoryKey])
        if name and Number(info.parentSkillLineID) == 0 and category ~= CLASS_SKILL_CATEGORY then
            if header then
                group = Group(buffer, name, index, Flag(info.isCollapsed))
            else
                group = group or Group(buffer, Text("Skills"))
                local rank, maximum = Number(info.rank), Number(info.maxRank)
                local modifier = Number(info.skillID) == DEFENSE_SKILL and Number(select(2, UnitDefenseSkill("player")))
                    or Number(info.modifier)
                local value = Progress(rank, maximum)
                if rank and modifier and modifier ~= 0 then value = string.format("%s (%+d)", value, modifier) end
                Row(group, name, value)
            end
        end
    end
end

local function Profession(group, index)
    index = Number(index)
    if not index then return end
    local name, _, rank, maximum = GetProfessionInfo(index)
    name = String(name)
    if name then Row(group, name, Progress(Number(rank), Number(maximum))) end
end

local function ReadProfessions(buffer)
    local first, second, archaeology, fishing, cooking = GetProfessions()
    local group = Group(buffer, TRADE_SKILLS)
    Profession(group, first)
    Profession(group, second)
    Profession(group, cooking)
    Profession(group, fishing)
    Profession(group, archaeology)
end

local PVP_RANK_FACTION = 2800
local function ReadPvP(buffer)
    local info = C_MajorFactions.GetMajorFactionProgressionInfo(PVP_RANK_FACTION)
    if not IsTable(info) then return end
    local group = Group(buffer, Text("PvP"))
    local rank = Number(info.renownLevel)
    local season = Number(GetCurrentArenaSeason())
    if season and season > 0 then Row(group, Text("Current season"), season) end
    Row(group, Text("Rank"), rank == 0 and PVP_RANK_0_NAME or rank)
    Row(group, Text("Rank progress"), Progress(Number(info.renownReputationEarned), Number(info.renownLevelThreshold)))
    local maximum = Number(info.maxLevel)
    if maximum and maximum > 0 then Row(group, Text("Maximum rank"), maximum) end
end

local function ReadHonor(buffer)
    local group = Group(buffer, Text("PvP"))
    Row(group, Text("Honor level"), Number(UnitHonorLevel("player")))
    Row(group, Text("Honor progress"), Progress(Number(UnitHonor("player")), Number(UnitHonorMax("player"))))
end

local function ReadCurrency(buffer)
    local group
    for index = 1, Number(C_CurrencyInfo.GetCurrencyListSize()) or 0 do
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)
        local name = IsTable(info) and String(info.name)
        if name then
            if Flag(info.isHeader) then
                group = Group(buffer, name, index, not Flag(info.isHeaderExpanded), Number(info.currencyListDepth))
            else
                group = group or Group(buffer, Text("Currencies"))
                Row(group, name, Number(info.quantity))
            end
        end
    end
end

local function ReadStatisticsCategory(buffer, category)
    local title = String(GetCategoryInfo(category))
    local count = Number(GetCategoryNumAchievements(category))
    if not title or not count or count < 1 then return end
    local group
    for index = 1, count do
        local quantity, skip, statistic = GetStatistic(category, index)
        statistic = Number(statistic)
        if Public(skip) and not skip and statistic then
            local name = String(select(2, GetAchievementInfo(statistic)))
            if name then
                group = group or Group(buffer, title)
                local value = String(quantity)
                local amount = Number(quantity) or (value and Number(tonumber(value)))
                Row(group, name, amount and amount > 0 and amount)
            end
        end
    end
end

local function ReadStatistics(buffer)
    local categories = GetStatisticsCategoryList()
    if not IsTable(categories) then return end
    -- Blizzard also handles sparse ordinal keys in the returned category list.
    local keys, count = buffer.keys, 0
    for index, category in pairs(categories) do
        if Number(index) and Number(category) then
            count = count + 1
            keys[count] = index
        end
    end
    for index = #keys, count + 1, -1 do keys[index] = nil end
    table.sort(keys)
    for index = 1, count do ReadStatisticsCategory(buffer, categories[keys[index]]) end
end

local readers = {
    reputation = ReadReputation, currency = ReadCurrency, statistics = ReadStatistics,
    skills = Forever and ReadSkills or ReadProfessions, pvp = Forever and ReadPvP or ReadHonor,
}

function Pages.Read(tab, groups)
    local buffer = Buffer(groups)
    local reader = readers[tab]
    if reader then reader(buffer) end
    if buffer.count == 0 then Group(buffer, Text("No data available")) end
    return Finish(buffer, groups)
end

local function ToggleHeader(info, index, expand, collapse)
    if not IsTable(info) or not Flag(info.isHeader) then return false end
    local collapsed = info.isCollapsed
    if not Public(collapsed) or type(collapsed) ~= "boolean" then return false end
    if collapsed then expand(index) else collapse(index) end
    return true
end

function Pages.Toggle(tab, index)
    if Host.IsCombatLocked() or not Number(index) or index < 1 then return false end
    if tab == "reputation" then
        local info = C_Reputation.GetFactionDataByIndex(index)
        return ToggleHeader(info, index, C_Reputation.ExpandFactionHeader, C_Reputation.CollapseFactionHeader)
    elseif tab == "skills" and Forever then
        local info = C_SkillInfo.GetSkillLineInfo(index)
        return ToggleHeader(info, index, C_SkillInfo.ExpandSkillHeader, C_SkillInfo.CollapseSkillHeader)
    elseif tab == "currency" then
        local info = C_CurrencyInfo.GetCurrencyListInfo(index)
        if not IsTable(info) or not Flag(info.isHeader) then return false end
        local expanded = info.isHeaderExpanded
        if Public(expanded) and type(expanded) == "boolean" then
            C_CurrencyInfo.ExpandCurrencyList(index, not expanded)
            return true
        end
    end
    return false
end
