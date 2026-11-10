local _, NS = ...
local Host, Suite = NS.Host, NS.Suite
local Number, String, Public, Text = NS.Number, NS.String, NS.Public, NS.Text
local Forever = Host.Client.isForever
local skills = Forever and C_SkillInfo
local defenseSkill = Forever and UnitDefenseSkill
local Pages, Stats, Reputation = {}, NS.Stats, NS.Reputation
NS.Pages = Pages

local quickEvents = {
    "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_STATS",
}
local ratingEvents = { "UNIT_SPELL_HASTE", "COMBAT_RATING_UPDATE", "PLAYER_DAMAGE_DONE_MODS" }
if not Forever then
    for index = 1, #ratingEvents do quickEvents[#quickEvents + 1] = ratingEvents[index] end
    quickEvents[#quickEvents + 1] = "MASTERY_UPDATE"
end
local extraStatEvents = {
    "UNIT_RESISTANCES", "SPEED_UPDATE", "SPELL_POWER_CHANGED", "PLAYER_TALENT_UPDATE",
}
if Forever then
    for index = 1, #ratingEvents do extraStatEvents[#extraStatEvents + 1] = ratingEvents[index] end
    local weaponEvents = { "UNIT_DAMAGE", "UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE", "UNIT_ATTACK_POWER",
        "UNIT_RANGED_ATTACK_POWER", "SKILL_LINES_CHANGED" }
    for index = 1, #weaponEvents do extraStatEvents[#extraStatEvents + 1] = weaponEvents[index] end
else
    extraStatEvents[#extraStatEvents + 1] = "AVOIDANCE_UPDATE"
    extraStatEvents[#extraStatEvents + 1] = "LIFESTEAL_UPDATE"
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

local reputationDetailEvents = { unpack(Pages.Events.reputation) }
reputationDetailEvents[#reputationDetailEvents + 1] = "QUEST_TURNED_IN"
local defaultReputationKey = Reputation.OptionsKey()

function Pages.ReportEvents(tab, config)
    if tab == "reputation" and Reputation.OptionsKey(config) ~= defaultReputationKey then return reputationDetailEvents end
    return Pages.Events[tab]
end

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

local function Row(group, label, value, layout, tooltip, argument)
    local index = group.count + 1
    local row = group.pool[index]
    if not row then
        row = {}
        group.pool[index] = row
    end
    row.label, row.value, row.layout = label, value or "—", layout
    row.tooltip, row.tooltipArgument = tooltip, argument
    row.reputationFill, row.reputationReaction = nil, nil
    group.rows[index], group.count = row, index
    return row
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

local function Stat(group, id, full)
    if not id then return end
    local label = String(_G["SPELL_STAT" .. id .. "_NAME"])
    if label then Row(group, label, Attribute(id), nil, full and Stats.AttributeTooltip or nil, id) end
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
    if not defenseSkill then return end
    local base, bonus = defenseSkill("player")
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
    for index = 1, #attributes do Stat(attributesGroup, attributes[index], true) end
    Stats.General(attributesGroup, Row)

    local enhancements = Group(buffer, Text("Enhancements"))
    Stats.Enhancements(enhancements, Row)
    if Forever then Stats.ForeverModifiers(enhancements, Row) end

    local defense = Group(buffer, Text("Defense"))
    Row(defense, STAT_ARMOR, Armor(), nil, Stats.ArmorTooltip)
    Row(defense, STAT_DODGE, Dodge(), nil, Stats.DodgeTooltip)
    if Forever then
        Row(defense, DEFENSE, Defense(), nil, Stats.DefenseTooltip)
        Stats.Weapons(Group(buffer, STAT_CATEGORY_WEAPONS or Text("Weapons")), Row)
    else
        Row(defense, STAT_AVOIDANCE, Avoidance(), nil, Stats.SimpleRatingTooltip, CR_AVOIDANCE)
    end
    Stats.Defenses(defense, Row)
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
local REPORT = Text("Report")
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

local customEvents = {
    attributes = { unpack(quickEvents) },
    gear = { unpack(auditChange) },
}
for _, event in ipairs(extraStatEvents) do customEvents.attributes[#customEvents.attributes + 1] = event end
customEvents.attributes[#customEvents.attributes + 1] = "PLAYER_EQUIPMENT_CHANGED"
customEvents.gear[#customEvents.gear + 1] = "UPDATE_INVENTORY_DURABILITY"

local function AddEvent(plan, events, event)
    if events[event] then return end
    events[event] = true
    plan.events[#plan.events + 1] = event
end

local function AddProvider(plan, provider, unique, events)
    local index = unique[provider]
    if index then return index end
    index = #plan.readers + 1
    unique[provider], plan.readers[index] = index, provider[1]
    for _, event in ipairs(provider[2]) do
        AddEvent(plan, events, event)
        plan.requiredEvents[event] = true
    end
    if provider.audit then plan.audit = true end
    if provider.durability then plan.durability = true end
    if provider.header then plan[provider.header] = true end
    return index
end

local function BindDataEvent(plan, event, section)
    local targets = plan.dataEvents[event]
    if not targets then
        targets = {}
        plan.dataEvents[event] = targets
    end
    targets[#targets + 1] = section
end

local function AddData(plan, source, events)
    local domain = source.report or (source.kind == "faction" and "reputation" or source.kind)
    if not domain then return end
    local section = plan.data[domain]
    if not section then
        section = { stale = true, entries = {} }
        plan.data[domain] = section
        for _, event in ipairs(customEvents[domain] or Pages.Events[domain]) do
            AddEvent(plan, events, event)
            BindDataEvent(plan, event, section)
            if domain ~= "attributes" then plan.requiredEvents[event] = true end
        end
        if domain == "reputation" then
            plan.reputation = true
            BindDataEvent(plan, "QUEST_TURNED_IN", section)
        elseif domain == "gear" then
            plan.audit, plan.durability = true, true
        end
    end
    local entry = section.entries[source.id]
    if entry then
        -- Only the first instance of a whole report expands. Individual
        -- rows may be placed more than once and share a single read.
        if not source.report then return entry end
        return
    end
    entry = { source = source, value = {} }
    section.entries[source.id] = entry
    if source.report then plan.hasReports = true end
    return entry
end

function Pages.CustomPlan(definition, reset)
    local plan = plans[definition]
    if plan then
        if reset then Pages.InvalidateCustom(plan) end
        return plan
    end
    plan = { cards = {}, events = {}, readers = {}, values = {}, labels = {}, samples = {}, combatLocked = {},
        data = {}, dataEvents = {}, requiredEvents = {} }
    local unique, events = {}, {}
    for i, card in ipairs(definition.cards) do
        local x, y = Model.Position(card)
        local target = { title = card.title, rows = {}, x = x, y = y, rowUp = 0, rowDown = 0 }
        plan.cards[i] = target
        for j, row in ipairs(card.rows) do
            local source = Model.Source(row.source)
            local available = Model.SourceAvailable(row.source)
            local provider = available and providers[row.source]
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
                defaultLabel = source and (source.target and ("%s (%d)"):format(source.text, source.target) or source.text) or NO_DATA,
                data = available and source and (source.kind or source.report) and AddData(plan, source, events) or nil,
            }
        end
    end
    if plan.reputation then
        plan.detailEvents = { unpack(plan.events) }
        plan.detailEvents[#plan.detailEvents + 1] = "QUEST_TURNED_IN"
    end
    plan.combatOptionalEvents = {}
    if plan.data.attributes then
        for _, event in ipairs(extraStatEvents) do
            if not plan.requiredEvents[event] then plan.combatOptionalEvents[#plan.combatOptionalEvents + 1] = event end
        end
    end
    plans[definition] = plan
    return plan
end

function Pages.ReputationKey(tab, config, plan)
    if tab == "reputation" or plan and plan.reputation then return Reputation.OptionsKey(config) end
end

function Pages.CustomEvents(plan, reputationKey)
    plan.eventsInCombat = false
    if plan.detailEvents and reputationKey ~= defaultReputationKey then return plan.detailEvents end
    return plan.events
end

function Pages.SyncCustomEvents(plan, combat, setEvents)
    combat = combat == true
    if not plan or plan.eventsInCombat == combat then return end
    plan.eventsInCombat = combat
    setEvents(plan.combatOptionalEvents, not combat, true)
end

function Pages.InvalidateCustom(plan, event)
    if not plan then return end
    if event then
        local targets = plan.dataEvents[event]
        if targets then for _, section in ipairs(targets) do section.stale = true end end
    else
        for _, section in pairs(plan.data) do section.stale = true end
    end
end

local function ReadCustomValue(row, source, config, sex)
    row.label, row.value, row.tooltip, row.tooltipArgument = nil, nil, nil, nil
    row.reputationFill, row.reputationReaction = nil, nil
    if source.kind == "currency" then
        local info = C_CurrencyInfo.GetCurrencyInfo(source.target)
        if IsTable(info) then row.label, row.value = String(info.name), Number(info.quantity) end
        return
    end
    local info
    if source.target then
        info = C_Reputation.GetFactionDataByID(source.target)
    else
        info = C_Reputation.GetWatchedFactionData()
    end
    local name = IsTable(info) and String(info.name)
    if name and name ~= "" then
        row.label = name
        Reputation.Populate(row, info, sex, Reputation.Options(config))
    end
end

local function ReadCustomData(plan, state, combat, config)
    if state and combat ~= plan.combat then
        plan.combat = combat
        local attributes, gear = plan.data.attributes, plan.data.gear
        if attributes then attributes.stale = true end
        if gear then gear.stale = true end
    end
    for domain, section in pairs(plan.data) do
        if not state or section.stale then
            local sex = domain == "reputation" and (Number(UnitSex("player")) or false)
            for _, entry in pairs(section.entries) do
                local source, value = entry.source, entry.value
                if not source.report then
                    if not state and not entry.preview then entry.preview = {} end
                    ReadCustomValue(state and value or entry.preview, source, config, sex)
                elseif state then
                    if domain == "attributes" then
                        Pages.Overview(value, true, combat)
                    elseif domain == "gear" then
                        wipe(value)
                        Pages.EquipmentSummary(value, state.gear)
                        NS.Gear.EquipmentList(value, state.gear)
                    else
                        Pages.Read(domain, value, config)
                    end
                end
            end
            if state then section.stale = false end
        end
    end
end

local function CopyCustomValue(group, value, label, layout)
    local row = Row(group, label, value.value, layout, value.tooltip, value.tooltipArgument)
    row.reputationFill, row.reputationReaction = value.reputationFill, value.reputationReaction
end

local function AppendCustomData(group, row, state)
    local data = row.data
    local label = row.label or row.defaultLabel
    if not data.source.report then
        local value = state and data.value or data.preview
        CopyCustomValue(group, value, row.label or value.label or row.defaultLabel, row)
        return
    end
    local report = data.value
    Row(group, label, state and (#report > 0 and "" or NO_DATA) or REPORT, row)
    if not state then return end
    for _, section in ipairs(report) do
        if section.title ~= label then Row(group, section.title, "", row) end
        for _, value in ipairs(section.rows) do CopyCustomValue(group, value, value.label, row) end
    end
end

local sampleLabels = {}
function Pages.Custom(groups, plan, state, combat, config)
    local buffer = Buffer(groups)
    ReadCustomData(plan, state, combat, state and state.config or config)
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
            if row.data then
                AppendCustomData(group, row, state)
            else
                Row(group, row.label or labels[row.index] or row.defaultLabel, values[row.index], row)
            end
        end
    end
    if buffer.count == 0 then Group(buffer, NO_DATA) end
    return Finish(buffer, groups)
end

local function ReadReputation(buffer, config)
    local group
    local sex = Number(UnitSex("player")) or false
    local showBars, valueMode, goal = Reputation.Options(config)
    for index = 1, Number(C_Reputation.GetNumFactions()) or 0 do
        local info = C_Reputation.GetFactionDataByIndex(index)
        local name = IsTable(info) and String(info.name)
        if name then
            if Flag(info.isHeader) then
                group = Group(buffer, name, index, Flag(info.isCollapsed), Flag(info.isChild) and 1 or 0)
                if Flag(info.isHeaderWithRep) then
                    Reputation.Populate(Row(group, Text("Reputation")), info, sex, showBars, valueMode, goal)
                end
            else
                group = group or Group(buffer, Text("Reputation"))
                Reputation.Populate(Row(group, name), info, sex, showBars, valueMode, goal)
            end
        end
    end
end

local DEFENSE_SKILL = 95
local CLASS_SKILL_CATEGORY = 7
local function ReadSkills(buffer)
    if not skills then return end
    local group
    for index = 1, Number(skills.GetNumSkillLines()) or 0 do
        local info = skills.GetSkillLineInfo(index)
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
                local modifier = Number(info.skillID) == DEFENSE_SKILL and defenseSkill and Number(select(2, defenseSkill("player")))
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
    if not Forever then return end
    local progression = C_MajorFactions.GetMajorFactionProgressionInfo
    if not progression then return end
    local info = progression(PVP_RANK_FACTION)
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

function Pages.Read(tab, groups, config)
    local buffer = Buffer(groups)
    local reader = readers[tab]
    if reader then reader(buffer, config) end
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
    elseif tab == "skills" and skills then
        local info = skills.GetSkillLineInfo(index)
        return ToggleHeader(info, index, skills.ExpandSkillHeader, skills.CollapseSkillHeader)
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
