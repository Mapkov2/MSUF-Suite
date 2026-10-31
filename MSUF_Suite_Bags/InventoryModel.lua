local _, P = ...
-- Pure layout data: no frame mutation, item movement, or client API calls.
-- The native slot remains the authority even when several stacks share a row.
local Model = {}
P.InventoryModel = Model
local VIEW, SORT = P.NS.BagsView, P.NS.BagsSort
local BY_BAG, CATEGORIES = VIEW.BY_BAG, VIEW.CATEGORIES
-- Item classes, subclasses and qualities: Enum.ItemClass, Enum.ItemArmorSubclass,
-- Enum.ItemMiscellaneousSubclass and Enum.ItemQuality (ItemConstantsDocumentation,
-- ItemQualitiesDocumentation; Retail and Forever).
local CLASS, POOR = Enum.ItemClass, Enum.ItemQuality.Poor
local MISC, COSMETIC = Enum.ItemMiscellaneousSubclass, Enum.ItemArmorSubclass.Cosmetic
local REAGENT_CLASSES = { [CLASS.Reagent] = true, [CLASS.Tradegoods] = true, [CLASS.Gem] = true }
local COLLECTIBLE_MISC = { [MISC.CompanionPet] = true, [MISC.Mount] = true, [MISC.MountEquipment] = true }
local floor, sort = math.floor, table.sort
-- key, label, order, optional. An optional category exists only while its
-- category_<key> setting is on, so a layout made without it does not move.
local BUILTINS = {
    { "equipment", "Equipment", 40 }, { "professionGear", "Profession gear", 45, true },
    { "consumables", "Consumables", 50 }, { "reagents", "Reagents", 60 }, { "recipes", "Recipes", 70 },
    { "collectibles", "Collectibles", 75, true }, { "containers", "Containers", 85, true },
    { "quest", "Quest items", 90 }, { "junk", "Junk", 100 }, { "other", "Other items", 110 },
}
Model.categories = BUILTINS
for i = 1, #BUILTINS do BUILTINS[i].setting = "category_" .. BUILTINS[i][1] end

-- Whether a built-in category is on: the optional ones only when turned on.
local function CategoryOn(config, entry)
    if entry[4] then return config[entry.setting] == true end
    return config[entry.setting] ~= false
end

local function Clear(t)
    for key in pairs(t) do t[key] = nil end
end

local function Unescape(value)
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function Escape(value)
    return (value:gsub("[%%|\r\n]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function Name(value)
    value = tostring(value or ""):gsub("[\r\n]", " ")
    if #value <= 64 then return value end
    local last = 65
    while last > 1 and value:byte(last) >= 128 and value:byte(last) < 192 do last = last - 1 end
    return value:sub(1, last - 1)
end

Model.CATEGORY_ITEMS = 500

-- Group keys the profile keeps collapsed (Categories view), at most this many,
-- so the profile cannot grow without limit. Keys of groups that are gone (a
-- renamed equipment set, a custom category deleted) make room first.
Model.MAX_COLLAPSED = 64

-- Flips one group in the collapsed set. groups is the model's groupsByKey: a
-- full set drops the keys it does not hold, and only when every key is a live
-- group does the flip fail (false).
function Model.ToggleCollapsed(collapsed, key, groups)
    if collapsed[key] then
        collapsed[key] = nil
        return true
    end
    local count = 0
    for _ in pairs(collapsed) do count = count + 1 end
    if count >= Model.MAX_COLLAPSED then
        for stale in pairs(collapsed) do
            if not groups[stale] then collapsed[stale], count = nil, count - 1 end
        end
        if count >= Model.MAX_COLLAPSED then return false end
    end
    collapsed[key] = true
    return true
end

function Model.CountItems(category)
    local count = 0
    for _, enabled in pairs(category.items) do
        if enabled then count = count + 1 end
    end
    return count
end

function Model.DecodeCategories(text)
    local categories = {}
    if type(text) ~= "string" or #text > 16000 then return categories end
    for line in text:gmatch("[^\r\n]+") do
        local enabled, name, ids, query = line:match("^([01])|([^|]*)|([%d, ]*)|([^|]*)$")
        if not enabled then enabled, name, ids = line:match("^([01])|([^|]*)|([%d, ]*)$") end
        if name and #categories < 24 then
            name = Name(Unescape(name))
            if name:find("%S") then
                local entry = { name = name, enabled = enabled == "1", items = {} }
                if query and query:find("%S") then
                    entry.query = Unescape(query)
                    entry.rule = P.NS.InventoryRules.Compile(entry.query)
                    -- A rule of blanks is no rule: it would take every item.
                    if entry.rule and not P.NS.InventoryRules.HasTerms(entry.rule) then entry.query, entry.rule = nil, nil end
                end
                local count = 0
                for value in ids:gmatch("%d+") do
                    local id = tonumber(value)
                    if id and id > 0 and id < 2147483647 and count < Model.CATEGORY_ITEMS and not entry.items[id] then
                        entry.items[id], count = true, count + 1
                    end
                end
                categories[#categories + 1] = entry
            end
        end
    end
    return categories
end

function Model.EncodeCategories(categories)
    local lines, ids = {}, {}
    for i = 1, math.min(#categories, 24) do
        local category = categories[i]
        Clear(ids)
        for id, enabled in pairs(category.items or {}) do
            if enabled and type(id) == "number" and id == floor(id) and id > 0 and id < 2147483647 then
                ids[#ids + 1] = id
            end
        end
        sort(ids)
        for j = #ids, Model.CATEGORY_ITEMS + 1, -1 do ids[j] = nil end
        local name = Name(category.name)
        if name:find("%S") then
            lines[#lines + 1] = (category.enabled == false and "0|" or "1|")
                .. Escape(name) .. "|" .. table.concat(ids, ",")
                .. (category.query and category.query:find("%S") and "|" .. Escape(category.query) or "")
        end
    end
    local result = table.concat(lines, "\n")
    if #result > 16000 then return nil end
    return result
end

-- Group keys of custom categories follow their names, not their position, so a
-- selected filter stays on its category when categories are reordered.
local function KeyCategories(model)
    local used = {}
    Clear(model.customIndex)
    for i = 1, #model.custom do
        local category = model.custom[i]
        local key, n = "custom:" .. category.name, 1
        while used[key] do
            n = n + 1
            key = "custom:" .. category.name .. "#" .. n
        end
        used[key], category.key, model.customIndex[key] = true, key, i
    end
end

-- What each optional category holds. Collectibles: pets, mounts, toys (the
-- toy flag is read for them alone, InventoryDetails.lua) and cosmetic armor.
local OPTIONAL_TESTS = {
    professionGear = function(item) return item.classID == CLASS.Profession end,
    containers = function(item) return item.classID == CLASS.Container end,
    collectibles = function(item)
        local class = item.classID
        return item.toy == true or class == CLASS.Battlepet
            or class == CLASS.Miscellaneous and COLLECTIBLE_MISC[item.subclassID] == true
            or class == CLASS.Armor and item.subclassID == COSMETIC
    end,
}

-- The optional categories that are on, in BUILTINS order (out is refilled).
local function EnabledOptional(config, out)
    for i = #out, 1, -1 do out[i] = nil end
    for i = 1, #BUILTINS do
        local entry = BUILTINS[i]
        if entry[4] and config[entry.setting] == true then out[#out + 1] = entry end
    end
    return out
end

-- key, label, order of the first of the optional categories that holds the item.
local function Optional(item, optional)
    for i = 1, #optional do
        local entry = optional[i]
        if OPTIONAL_TESTS[entry[1]](item) then return entry[1], entry[2], entry[3] end
    end
end

Model.EnabledOptional = EnabledOptional

-- key, label, order, translate (label is Suite English text). optional is the
-- list of optional categories that are on (Model.EnabledOptional); without it only
-- the categories that are always on exist.
function Model.Category(item, custom, optional)
    for i = 1, #custom do
        local category = custom[i]
        if category.enabled and (category.items[item.itemID]
            or item.itemID and category.rule and P.NS.InventoryRules.Matches(category.rule, item)) then
            return category.key or "custom:" .. category.name, category.name, i + 2, false
        end
    end
    if item.quality == POOR then return "junk", "Junk", 100, true end
    if item.quest then return "quest", "Quest items", 90, true end
    if optional and optional[1] then
        local key, label, order = Optional(item, optional)
        if key then return key, label, order, true end
    end
    if item.equipLoc and item.equipLoc ~= "" and item.equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
        return "equipment", "Equipment", 40, true
    end
    local class = item.classID
    if class == CLASS.Consumable then return "consumables", "Consumables", 50, true end
    if REAGENT_CLASSES[class] then return "reagents", "Reagents", 60, true end
    if class == CLASS.Recipe then return "recipes", "Recipes", 70, true end
    if class == CLASS.Questitem then return "quest", "Quest items", 90, true end
    return "other", "Other items", 110, true
end

-- A custom category that was deleted or renamed leaves its collapsed key
-- behind (also with an expansion suffix): drop the keys the list no longer holds.
local function PruneCollapsed(model, collapsed)
    for key in pairs(collapsed) do
        local base = key:gsub(":exp:%d+$", "")
        if base:sub(1, 7) == "custom:" and not model.customIndex[base] then collapsed[key] = nil end
    end
end

function Model.New()
    return { groups = {}, groupPool = {}, rowPool = {}, groupsByKey = {}, customIndex = {},
        rowCount = 0, groupCount = 0, custom = {}, customText = false }
end

-- translate: label is Suite English text; otherwise it is the player's own
-- text or a name the client already localized. expansionName is composed
-- with the label where it is shown (GridView.GroupLabel).
local function Group(model, key, label, order, expansion, translate, expansionName)
    local group = model.groupsByKey[key]
    if group then return group end
    model.groupCount = model.groupCount + 1
    group = model.groupPool[model.groupCount]
    if not group then
        group = { rows = {}, displayRows = {}, merge = {} }
        model.groupPool[model.groupCount] = group
    end
    Clear(group.rows)
    Clear(group.displayRows)
    Clear(group.merge)
    group.key, group.label, group.order, group.expansion = key, label, order, expansion
    group.translate, group.expansionName = translate == true, expansionName
    group.expansionFirst = model.expansionFirst
    model.groups[model.groupCount], model.groupsByKey[key] = group, group
    return group
end

-- Full link, binding state and location type must agree within a group.
-- Different bonus IDs, upgrade ranks, qualities and bank scopes never share a
-- stack. InventoryIndex builds the key once per changed slot; other records
-- (tests, older callers) get it built here.
local function MergeKey(item)
    local key = item.mergeKey
    if not key then
        key = (item.link or tostring(item.itemID)) .. (item.bound == true and "\031b\031" or "\031u\031")
            .. tostring(item.bankType or "bags")
    end
    return key
end

local function Add(model, group, item, merge, alias)
    local mergeKey = merge and item.itemID and not item.locked and (item.maxStack or 1) > 1 and MergeKey(item)
    local row = mergeKey and group.merge[mergeKey]
    if row then
        row.count, row.stacks = row.count + (item.count or 1), row.stacks + 1
        return
    end
    model.rowCount = model.rowCount + 1
    row = model.rowPool[model.rowCount]
    if not row then
        row = {}
        model.rowPool[model.rowCount] = row
    end
    row.item, row.count, row.stacks = item, item.count or 0, 1
    row.alias = alias == true
    group.rows[#group.rows + 1] = row
    if mergeKey then group.merge[mergeKey] = row end
end

local function SortRows(a, b)
    a, b = a.item, b.item
    if a.shuffle and b.shuffle and a.shuffle ~= b.shuffle then return a.shuffle < b.shuffle end
    if (a.name or "") ~= (b.name or "") then return (a.name or "") < (b.name or "") end
    if (a.itemID or 0) ~= (b.itemID or 0) then return (a.itemID or 0) < (b.itemID or 0) end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

-- The sort modes other than Name: a row's number for the mode, compared
-- largest first (smallest first for Type). Rows with no number come last and
-- rows with equal numbers keep name order. Numbers come from the index
-- record; a row's own count is the sum of its merged stacks.
local TYPE_STRIDE = 1000

local function Ranked(value, descending)
    return function(a, b)
        local x, y = value(a), value(b)
        if x ~= y then
            if x == nil then return false end
            if y == nil then return true end
            if descending then return x > y end
            return x < y
        end
        return SortRows(a, b)
    end
end

local function TypeNumber(row)
    local item = row.item
    return item.classID and item.classID * TYPE_STRIDE + (item.subclassID or 0)
end

local SORTERS = {
    [SORT.QUALITY] = Ranked(function(row) return row.item.quality end, true),
    [SORT.ITEM_LEVEL] = Ranked(function(row) return row.item.itemLevel end, true),
    [SORT.TYPE] = Ranked(TypeNumber, false),
    [SORT.EXPANSION] = Ranked(function(row) return row.item.expansion end, true),
    [SORT.STACK] = Ranked(function(row) return row.count end, true),
    [SORT.PRICE] = Ranked(function(row) return row.item.sellPrice end, true),
}

-- The comparator for a group's rows, or nil for the order they were read in.
-- A shuffle outranks the mode; Name sorts Categories only, as it always has.
local function RowOrder(config, shuffle, categories)
    if shuffle then return SortRows end
    return SORTERS[config.sortMode] or categories and SortRows or nil
end

local function SortGroups(a, b)
    if a.expansionFirst and a.order > 1 and b.order > 1 and a.expansion ~= b.expansion then
        return (a.expansion or -1) > (b.expansion or -1)
    end
    if a.order ~= b.order then return a.order < b.order end
    if a.expansion ~= b.expansion then return (a.expansion or -1) > (b.expansion or -1) end
    return a.key < b.key
end

local function Subgroup(item, config, key, label)
    if key == "equipment" then
        if config.groupEquipmentSets and item.setName then
            return "set:" .. item.setName, item.setName, false
        elseif config.groupEquipmentSlots and item.equipLoc and item.equipLoc ~= "" then
            return "slot:" .. item.equipLoc, item.slotName or item.equipLoc, false
        end
    elseif key == "reagents" and config.groupReagentTypes and item.subclassName then
        -- Some reagents report a readable material name but no subclass ID.
        return "reagent:" .. (item.subclassID or item.subclassName), item.subclassName, false
    end
    return key, label, true
end

-- key, label, order, expansion, translate, expansionName
local function ItemGroup(item, config, state, model)
    if item.itemID and config.showPinned and state.pinned and state.pinned[item.itemID] then
        return "pinned", "Pinned items", 0, nil, true
    end
    if item.itemID and config.showRecent and state.recent and state.recent[item.itemID] then
        return "recent", "Recent items", 1, nil, true
    end
    if config.inventoryView == BY_BAG then
        return "bag:" .. item.bag, item.bagName or tostring(item.bag), 50 + item.bag, nil, false
    end
    if config.inventoryView ~= CATEGORIES then return "all", "All items", 2, nil, true end
    if not item.itemID then return "empty", "Empty slots", 200, nil, true end
    local key, label, order, translate = Model.Category(item, model.custom, model.optional)
    if config["category_" .. key] == false then
        key, label, order, translate = "other", "Other items", 110, true
    end
    if translate then key, label, translate = Subgroup(item, config, key, label) end
    if config.groupExpansions and item.expansion then
        return key .. ":exp:" .. item.expansion, label, order, item.expansion, translate,
            item.expansionName or tostring(item.expansion)
    end
    return key, label, order, nil, translate
end

local function AddSets(model, config, item, key)
    for j = 1, #item.setNames do
        local name = item.setNames[j]
        local setKey, expansion, expansionName = "set:" .. name, nil, nil
        if config.groupExpansions and item.expansion then
            expansion, expansionName = item.expansion, item.expansionName or tostring(item.expansion)
            setKey = setKey .. ":exp:" .. expansion
        end
        if setKey ~= key then
            Add(model, Group(model, setKey, name, 40, expansion, false, expansionName), item, false, true)
        end
    end
end

local function AddEmptyCategories(model, config)
    for i = 1, #BUILTINS do
        local entry = BUILTINS[i]
        if CategoryOn(config, entry) then Group(model, entry[1], entry[2], entry[3], nil, true) end
    end
    for i = 1, #model.custom do
        local category = model.custom[i]
        if category.enabled then Group(model, category.key, category.name, i + 2, nil, false) end
    end
end

-- Orders a group's rows and picks the ones the grid shows. A collapsed group
-- (set by the player, not while one group is selected) keeps its header and
-- shows no rows; hidden counts the rows it holds.
local function Arrange(group, selected, collapsed, order)
    local all = not selected or selected == "all"
    group.visible = all or selected == group.key
    group.collapsed = all and collapsed ~= nil and collapsed[group.key] == true
    group.hidden = 0
    if order then sort(group.rows, order) end
    for j = 1, #group.rows do
        local row = group.rows[j]
        if not all or not row.alias then
            if group.collapsed then
                group.hidden = group.hidden + 1
            else
                group.displayRows[#group.displayRows + 1] = row
            end
        end
    end
end

function Model.Build(model, items, config, state, context)
    Clear(model.groups)
    Clear(model.groupsByKey)
    model.rowCount, model.groupCount = 0, 0
    model.expansionFirst = config.expansionFirst == true
    model.optional = EnabledOptional(config, model.optional or {})
    if model.customText ~= config.customCategories then
        model.customText = config.customCategories
        model.custom = Model.DecodeCategories(config.customCategories)
        KeyCategories(model)
        if state.collapsed then PruneCollapsed(model, state.collapsed) end
    end
    local merge = config.mergeStacks and not (context and context.transactions)
    local selected = context and context.selected
    local categories = config.inventoryView == CATEGORIES
    local showSets = categories and config.groupEquipmentSets and config.category_equipment ~= false
    local query = context and context.query
    if query and not query:find("%S") then query = nil end
    if query and query ~= model.query then
        model.query, model.queryRule = query, P.NS.InventoryRules.Compile(query)
    end
    -- searching: Blizzard's search marks non-matching slots isFiltered.
    local searching = context and context.searching
    for i = 1, #items do
        local item = items[i]
        if not (config.hideEmptySlots and not item.itemID)
            and not (searching and (item.filtered or not item.itemID))
            and (not query or item.itemID and model.queryRule and P.NS.InventoryRules.Matches(model.queryRule, item)) then
            local key, label, order, expansion, translate, expansionName = ItemGroup(item, config, state, model)
            Add(model, Group(model, key, label, order, expansion, translate, expansionName), item, merge)
            -- An item can belong to several equipment sets. Each set filter
            -- includes it, while All keeps one physical native button only.
            if showSets and item.setNames then AddSets(model, config, item, key) end
        end
    end
    if categories and not config.hideEmptyCategories and not query and not searching then
        AddEmptyCategories(model, config)
    end
    sort(model.groups, SortGroups)
    local order = RowOrder(config, context and context.shuffle, categories)
    -- Collapsing applies to the Categories view; a search shows its matches.
    local collapsed = categories and not query and not searching and state.collapsed or nil
    for i = 1, #model.groups do Arrange(model.groups[i], selected, collapsed, order) end
    return model.groups
end

-- Integer grid rows make scrolling deterministic without reparenting any
-- Blizzard item button. Off-screen slots are hidden, never detached/rebound.
function Model.Layout(model, columns, compact)
    local layout = model.layout or {}
    model.layout = layout
    model.layoutPool = model.layoutPool or {}
    Clear(layout)
    local line, column, count, bandHeight = 0, 0, 0, 0
    for g = 1, #model.groups do
        local group = model.groups[g]
        local rows = group.displayRows
        if group.visible and (#rows > 0 or group.collapsed) then
            local span = compact and #rows <= math.floor(columns / 2)
                and math.floor(columns / 2) or columns
            if column + span > columns then line, column, bandHeight = line + bandHeight, 0, 0 end
            count = count + 1
            local header = model.layoutPool[count] or {}
            model.layoutPool[count], layout[count] = header, header
            header.group, header.row, header.line, header.column, header.width = group, nil, line, column, span
            for i = 1, #rows do
                count = count + 1
                local cell = model.layoutPool[count] or {}
                model.layoutPool[count], layout[count] = cell, cell
                cell.group, cell.row = group, rows[i]
                cell.line, cell.column = line + 1 + math.floor((i - 1) / span), column + (i - 1) % span
            end
            bandHeight = math.max(bandHeight, 1 + math.ceil(#rows / span))
            column = column + span
        end
    end
    model.lineCount = line + bandHeight
    return layout
end
