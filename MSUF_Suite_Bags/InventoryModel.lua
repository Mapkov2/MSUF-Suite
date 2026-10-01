local _, P = ...
-- Pure layout data: no frame mutation, item movement, or client API calls.
-- The native slot remains the authority even when several stacks share a row.
local Model = {}
P.InventoryModel = Model
local VIEW = P.NS.BagsView
local BY_BAG, CATEGORIES = VIEW.BY_BAG, VIEW.CATEGORIES
-- Item classes and qualities: Enum.ItemClass and Enum.ItemQuality
-- (ItemConstantsDocumentation, ItemQualitiesDocumentation; Retail and Forever).
local CLASS, POOR = Enum.ItemClass, Enum.ItemQuality.Poor
local REAGENT_CLASSES = { [CLASS.Reagent] = true, [CLASS.Tradegoods] = true, [CLASS.Gem] = true }
local floor, sort = math.floor, table.sort
local BUILTINS = {
    { "equipment", "Equipment", 40 }, { "consumables", "Consumables", 50 },
    { "reagents", "Reagents", 60 }, { "recipes", "Recipes", 70 },
    { "quest", "Quest items", 90 }, { "junk", "Junk", 100 }, { "other", "Other items", 110 },
}
Model.categories = BUILTINS

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
        local enabled, name, ids = line:match("^([01])|([^|]*)|([%d, ]*)$")
        if name and #categories < 24 then
            name = Name(Unescape(name))
            if name:find("%S") then
                local entry = { name = name, enabled = enabled == "1", items = {} }
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

-- key, label, order, translate (label is Suite English text).
function Model.Category(item, custom)
    for i = 1, #custom do
        local category = custom[i]
        if category.enabled and category.items[item.itemID] then
            return category.key or "custom:" .. category.name, category.name, i + 2, false
        end
    end
    if item.quality == POOR then return "junk", "Junk", 100, true end
    if item.quest then return "quest", "Quest items", 90, true end
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
    if not row then row = {}; model.rowPool[model.rowCount] = row end
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
local function ItemGroup(item, config, state, custom)
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
    local key, label, order, translate = Model.Category(item, custom)
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
        if config["category_" .. entry[1]] ~= false then Group(model, entry[1], entry[2], entry[3], nil, true) end
    end
    for i = 1, #model.custom do
        local category = model.custom[i]
        if category.enabled then Group(model, category.key, category.name, i + 2, nil, false) end
    end
end

function Model.Build(model, items, config, state, context)
    Clear(model.groups)
    Clear(model.groupsByKey)
    model.rowCount, model.groupCount = 0, 0
    model.expansionFirst = config.expansionFirst == true
    if model.customText ~= config.customCategories then
        model.customText = config.customCategories
        model.custom = Model.DecodeCategories(config.customCategories)
        KeyCategories(model)
    end
    local merge = config.mergeStacks and not (context and context.transactions)
    local selected = context and context.selected
    local categories = config.inventoryView == CATEGORIES
    local showSets = categories and config.groupEquipmentSets and config.category_equipment ~= false
    local query = context and context.query
    if query == "" then query = nil end
    if query then query = query:lower() end
    -- searching: Blizzard's search marks non-matching slots isFiltered.
    local searching = context and context.searching
    for i = 1, #items do
        local item = items[i]
        if not (config.hideEmptySlots and not item.itemID)
            and not (searching and (item.filtered or not item.itemID))
            and (not query or item.search and item.search:find(query, 1, true)) then
            local key, label, order, expansion, translate, expansionName = ItemGroup(item, config, state, model.custom)
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
    for i = 1, #model.groups do
        local group = model.groups[i]
        group.visible = not selected or selected == "all" or selected == group.key
        if categories or context and context.shuffle then sort(group.rows, SortRows) end
        for j = 1, #group.rows do
            local row = group.rows[j]
            if selected and selected ~= "all" or not row.alias then
                group.displayRows[#group.displayRows + 1] = row
            end
        end
    end
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
        if group.visible and #rows > 0 then
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
