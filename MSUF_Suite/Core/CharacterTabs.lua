local _, NS = ...
local Text, Client, IsSecret = NS.Text, NS.Client, NS.IsSecret
-- Include the longest named and positioned dynamic source in every row.
local Model = { TabLimit = 8, CardLimit = 6, RowLimit = 12, NameLimit = 80, MaxBytes = 66 * 1024 }
NS.CharacterTabs = Model

local RETAIL, FOREVER = "retail", "forever"
local MAX_ID, MAX_SOURCE_ID = 999999, 2147483647
local ORDER_VERSION, POSITION_VERSION = "1", "2"
-- A fixed bias fits each signed axis into two decimal digits.
local POSITION_BIAS = 50
local RECORD_KINDS = { T = "tab", C = "card", R = "row" }
local POSITION_BOUNDS = { tab = { x = 48, y = 8 }, card = { x = 48, y = 24 }, row = { x = 32, y = 10 } }
Model.PositionBounds = POSITION_BOUNDS
local EMPTY = {}
local cache = setmetatable({}, { __mode = "k" })
local sources, groups, templates = {}, {}, {}

local function Source(id, label, category, sample, client, report)
    local source = { id = id, label = label, text = Text(label), category = category,
        sample = sample, client = client, report = report }
    sources[id] = source
    return source
end

local watched = Source("watchedReputation", "Watched reputation", "Reputation")
watched.kind = "faction"

Model.Sources = {
    Source("itemLevel", "Item Level", "Equipment", "712"),
    Source("durability", "Durability", "Equipment", "88%"),
    Source("missingEnchants", "Missing enchants", "Equipment", "1", RETAIL),
    Source("emptySockets", "Empty sockets", "Equipment", "2", RETAIL),
    Source("health", "Health", "Attributes", "3260"),
    Source("resource", "Resource", "Attributes", "2740"),
    Source("strength", "Strength", "Attributes", "48"),
    Source("agility", "Agility", "Attributes", "56"),
    Source("stamina", "Stamina", "Attributes", "102"),
    Source("intellect", "Intellect", "Attributes", "125"),
    Source("spirit", "Spirit", "Attributes", "76", FOREVER),
    Source("crit", "Critical strike", "Enhancements", "18.25%"),
    Source("haste", "Haste", "Enhancements", "12.60%"),
    Source("mastery", "Mastery", "Enhancements", "24.40%", RETAIL),
    Source("versatility", "Versatility", "Enhancements", "8.25%", RETAIL),
    Source("armor", "Armor", "Defense", "910"),
    Source("dodge", "Dodge", "Defense", "5.80%"),
    Source("defense", "Defense", "Defense", "152", FOREVER),
    Source("avoidance", "Avoidance", "Defense", "3.50%", RETAIL),
    Source("level", "Level", "Progress", "23"),
    Source("xp", "Experience", "Progress", "4500 / 7600"),
    watched,
    Source("reputationReport", "All reputations", "Reports", nil, nil, "reputation"),
    Source("currencyReport", "All currencies", "Reports", nil, nil, "currency"),
    Source("skillsReport", "All skills", "Reports", nil, nil, "skills"),
    Source("pvpReport", "PvP summary", "Reports", nil, nil, "pvp"),
    Source("statisticsReport", "All statistics", "Reports", nil, nil, "statistics"),
    Source("attributesReport", "All attributes", "Reports", nil, nil, "attributes"),
    Source("equipmentReport", "Equipment summary", "Reports", nil, nil, "gear"),
}

local dynamicSources = {
    faction = { label = "Faction reputation", text = Text("Faction reputation"), category = "Reputation" },
    currency = { label = "Currency amount", text = Text("Currency amount"), category = "Currencies" },
}

function Model.DynamicSourceID(kind, id)
    if IsSecret(kind) or IsSecret(id) or not dynamicSources[kind] or type(id) ~= "number" then return end
    if id >= 1 and id <= MAX_SOURCE_ID and id % 1 == 0 then return kind .. ":" .. id end
end

local function ParseDynamicSource(id)
    if type(id) ~= "string" or #id > 19 then return end
    local kind, digits = id:match("^(%l+):([1-9]%d*)$")
    if not dynamicSources[kind] then return end
    local target = tonumber(digits)
    if target <= MAX_SOURCE_ID then return kind, target end
end

local function ValidSource(id)
    return sources[id] ~= nil or ParseDynamicSource(id) ~= nil
end

local function Group(id, label, ...)
    local group = { id = id, label = label, text = Text(label), sources = { ... } }
    groups[id] = group
    return group
end

Model.Groups = {
    Group("equipment", "Equipment check", "itemLevel", "durability", "missingEnchants", "emptySockets"),
    Group("attributes", "Attributes", "health", "resource", "strength", "agility", "stamina", "intellect", "spirit"),
    Group("enhancements", "Enhancements", "crit", "haste", "mastery", "versatility"),
    Group("defense", "Defense", "armor", "dodge", "defense", "avoidance"),
    Group("progress", "Progress", "level", "xp"),
    Group("reputation", "Reputation", "reputationReport"),
}

local function Template(id, label, ...)
    local template = { id = id, label = label, text = Text(label), groups = { ... } }
    templates[id] = template
    return template
end

Model.Templates = {
    Template("empty", "Empty tab"),
    Template("raid", "Raid check", "equipment", "enhancements"),
    Template("progress", "Progress", "progress"),
    Template("reputation", "Reputation", "reputation"),
}

function Model.Source(id)
    local source = sources[id]
    if source then return source end
    local kind, target = ParseDynamicSource(id)
    if not kind then return end
    local defaults = dynamicSources[kind]
    return { id = id, kind = kind, target = target, label = defaults.label,
        text = defaults.text, category = defaults.category }
end

function Model.SourceAvailable(id)
    local source = sources[id]
    if not source then return ParseDynamicSource(id) ~= nil end
    return not source.client or source.client == (Client.isForever and FOREVER or RETAIL)
end

function Model.Position(entry)
    return entry and entry.x or 0, entry and entry.y or 0
end

local function ClampOffset(value, bound)
    if type(value) ~= "number" or value ~= value then return 0 end
    return math.floor(math.max(-bound, math.min(bound, value)) + .5)
end

function Model.ClampPosition(kind, x, y)
    local bounds = POSITION_BOUNDS[kind]
    if not bounds then return 0, 0 end
    return ClampOffset(x, bounds.x), ClampOffset(y, bounds.y)
end

local function CleanText(value)
    if type(value) ~= "string" then return "" end
    value = value:gsub("[%z\1-\31\127|]", ""):match("^%s*(.-)%s*$")
    if #value <= Model.NameLimit then return value end
    local edge = Model.NameLimit + 1
    while edge > 1 and value:byte(edge) >= 128 and value:byte(edge) < 192 do edge = edge - 1 end
    return (value:sub(1, edge - 1):gsub("%s+$", ""))
end

local function Name(value, fallback)
    value = CleanText(value)
    return value ~= "" and value or fallback
end

local function TabID(id)
    if type(id) ~= "string" or #id > 12 then return end
    local number = tonumber(id:match("^custom([1-9]%d*)$"))
    if number and number <= MAX_ID then return number end
end

local function NextID(tabs, highest)
    local nextID = tabs.nextID
    if type(nextID) ~= "number" or nextID % 1 ~= 0 or nextID > MAX_ID + 1 or nextID <= highest then
        return highest + 1
    end
    return nextID
end

local function HighestID(tabs)
    local highest = 0
    for i = 1, #tabs do highest = math.max(highest, TabID(tabs[i].id) or 0) end
    return highest
end

local function CopyCards(cards)
    local copy = {}
    for i = 1, #cards do
        local card = cards[i]
        local rows = {}
        for j = 1, #card.rows do
            local row = card.rows[j]
            rows[j] = { source = row.source, label = row.label, x = row.x, y = row.y }
        end
        copy[i] = { title = card.title, rows = rows, x = card.x, y = card.y }
    end
    return copy
end

local function FindTab(tabs, id)
    for i = 1, #tabs do
        local tab = tabs[i]
        if tab.id == id then return tab end
    end
end

local function ReadRecord(line, version)
    if version == POSITION_VERSION then
        local tag, key, label, position = line:match("^([TCR])|([^|]*)|([^|]*)|(%d%d%d%d)$")
        if tag then
            local x = tonumber(position:sub(1, 2)) - POSITION_BIAS
            local y = tonumber(position:sub(3, 4)) - POSITION_BIAS
            x, y = Model.ClampPosition(RECORD_KINDS[tag], x, y)
            return tag, key, label, x ~= 0 and x or nil, y ~= 0 and y or nil
        end
    end
    return line:match("^([TCR])|([^|]*)|([^|]*)$")
end

-- A profile stores one bounded versioned string. Text never contains record delimiters.
local function Decode(value)
    if type(value) ~= "string" or value == "" or #value > Model.MaxBytes then return EMPTY end
    local head, tail = value:match("^(.-)\n(.*)$")
    if not head then return EMPTY end
    local version, sequence = head:match("^([12])|([1-9]%d*)$")
    local nextID = tonumber(sequence)
    if not nextID or nextID > MAX_ID + 1 then return EMPTY end
    local tabs, seen = { nextID = nextID }, {}
    local tab, card
    for line in tail:gmatch("[^\n]+") do
        local kind, key, label, x, y = ReadRecord(line, version)
        if kind == "T" then
            local id = TabID(key)
            if not id or id >= nextID or seen[key] or #tabs >= Model.TabLimit then return EMPTY end
            seen[key] = true
            tab = { id = key, name = Name(label, Text("Custom tab")), cards = {}, x = x, y = y }
            tabs[#tabs + 1], card = tab, nil
        elseif kind == "C" then
            if not tab or key ~= "" or #tab.cards >= Model.CardLimit then return EMPTY end
            card = { title = Name(label, Text("Values")), rows = {}, x = x, y = y }
            tab.cards[#tab.cards + 1] = card
        elseif kind == "R" then
            if not card or not ValidSource(key) or #card.rows >= Model.RowLimit then return EMPTY end
            card.rows[#card.rows + 1] = { source = key, label = CleanText(label), x = x, y = y }
        else
            return EMPTY
        end
    end
    return tabs
end

function Model.Get(config)
    local value = config.customTabs
    if type(value) ~= "string" or value == "" then return EMPTY end
    local record = cache[config]
    if record and record.value == value then return record.tabs end
    local tabs = Decode(value)
    cache[config] = { value = value, tabs = tabs }
    return tabs
end

function Model.Find(config, id)
    return FindTab(Model.Get(config), id)
end

function Model.Copy(config)
    local source = Model.Get(config)
    local tabs = { nextID = source.nextID }
    for i = 1, #source do
        local tab = source[i]
        tabs[i] = { id = tab.id, name = tab.name, cards = CopyCards(tab.cards), x = tab.x, y = tab.y }
    end
    return tabs
end

local function EncodeRecord(lines, kind, entry, record)
    local x, y = Model.ClampPosition(kind, Model.Position(entry))
    if x == 0 and y == 0 then
        lines[#lines + 1] = record
        return false
    end
    lines[#lines + 1] = record .. string.format("|%02d%02d", x + POSITION_BIAS, y + POSITION_BIAS)
    return true
end

local function EncodeCard(lines, card)
    if type(card) ~= "table" or type(card.rows) ~= "table" or #card.rows > Model.RowLimit then return false end
    local positioned = EncodeRecord(lines, "card", card, "C||" .. Name(card.title, Text("Values")))
    for i = 1, #card.rows do
        local row = card.rows[i]
        if type(row) ~= "table" or not ValidSource(row.source) then return false end
        if EncodeRecord(lines, "row", row, "R|" .. row.source .. "|" .. CleanText(row.label)) then positioned = true end
    end
    return true, positioned
end

function Model.Encode(tabs)
    if type(tabs) ~= "table" or #tabs > Model.TabLimit then return end
    local lines, seen, highest, positioned = { "" }, {}, 0, false
    for i = 1, #tabs do
        local tab = tabs[i]
        local number = type(tab) == "table" and TabID(tab.id)
        if not number or seen[tab.id] or type(tab.cards) ~= "table" or #tab.cards > Model.CardLimit then return end
        seen[tab.id], highest = true, math.max(highest, number)
        local record = "T|" .. tab.id .. "|" .. Name(tab.name, Text("Custom tab"))
        if EncodeRecord(lines, "tab", tab, record) then positioned = true end
        for j = 1, #tab.cards do
            local valid, cardPositioned = EncodeCard(lines, tab.cards[j])
            if not valid then return end
            if cardPositioned then positioned = true end
        end
    end
    local nextID = NextID(tabs, highest)
    if #tabs == 0 and nextID == 1 then return "" end
    lines[1] = (positioned and POSITION_VERSION or ORDER_VERSION) .. "|" .. nextID
    if #lines == 1 then lines[2] = "" end
    local encoded = table.concat(lines, "\n")
    if #encoded <= Model.MaxBytes then return encoded end
end

function Model.Normalize(config)
    if config.customTabs == nil or config.customTabs == "" then return end
    config.customTabs = Model.Encode(Model.Get(config)) or ""
end

function Model.NewCard(groupID)
    local group = groups[groupID]
    local card = { title = group and group.text or Text("Values"), rows = {} }
    if group then
        for i = 1, #group.sources do
            local id = group.sources[i]
            if Model.SourceAvailable(id) then card.rows[#card.rows + 1] = { source = id, label = "" } end
        end
    end
    return card
end

local function AddTab(tabs, name, cards, x, y)
    if #tabs >= Model.TabLimit then return end
    local nextID = NextID(tabs, HighestID(tabs))
    local id
    if nextID <= MAX_ID then
        id, nextID = "custom" .. nextID, nextID + 1
    else
        -- A profile with an exhausted sequence may still have room for tabs.
        for number = 1, #tabs + 1 do
            local candidate = "custom" .. number
            if not FindTab(tabs, candidate) then id = candidate break end
        end
    end
    tabs[#tabs + 1], tabs.nextID = { id = id, name = name, cards = cards, x = x, y = y }, nextID
    return id
end

function Model.Create(tabs, templateID, name)
    local template = templates[templateID or "empty"]
    if not template then return end
    local cards = {}
    for i = 1, #template.groups do cards[i] = Model.NewCard(template.groups[i]) end
    local fallback = template.id ~= "empty" and template.text or Text("Custom tab")
    return AddTab(tabs, Name(name, fallback), cards)
end

function Model.Duplicate(tabs, id, name)
    local tab = FindTab(tabs, id)
    if tab then return AddTab(tabs, Name(name, tab.name), CopyCards(tab.cards), tab.x, tab.y) end
end
