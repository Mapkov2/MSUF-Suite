local _, P = ...
local NS, S = P.NS, P.Suite
-- The columns of the list view (ListView.lua): what each shows, how wide it
-- is and how rows sort by it. Rows are the model's rows (InventoryModel.lua):
-- row.item is a sanitized index record (InventoryIndex.lua) or an offline
-- record (OfflineInventory.lua), row.count the shown total. Client reads
-- happen in Prepare only, once per item link; sorting reads cached fields.
local Columns = {}
P.BagListColumns = Columns
local floor = math.floor

local BIND = Enum.ItemBind or {}
local BIND_ACQUIRE, BIND_EQUIP = BIND.OnAcquire or 1, BIND.OnEquip or 2
local BIND_QUEST = BIND.Quest or 4
local BIND_ACCOUNT, BIND_BNET = BIND.ToWoWAccount or 7, BIND.ToBnetAccount or 8
local BIND_UNTIL_EQUIPPED = BIND.ToBnetAccountUntilEquipped or 9

-- key, label, width (0: takes the rest), setting that shows it (nil: always),
-- drop: the order columns leave a narrow list (high first), first sort
-- direction descending.
Columns.LIST = {
    { key = "name", label = "Name", width = 0, desc = false },
    { key = "level", label = "Item level", short = "Level", width = 46, drop = 2, desc = true },
    { key = "track", label = "Track", width = 82, setting = "listShowTrack", drop = 5, desc = true, retail = true },
    { key = "count", label = "Count", width = 46, drop = 1, desc = true },
    { key = "binding", label = "Binding", width = 70, setting = "listShowBinding", drop = 3, desc = false },
    { key = "value", label = "Vendor value", short = "Value", width = 92, setting = "listShowValue", drop = 4, desc = true },
    { key = "type", label = "Type", width = 92, setting = "listShowType", drop = 6, desc = false },
}
Columns.byKey = {}
for i = 1, #Columns.LIST do Columns.byKey[Columns.LIST[i].key] = Columns.LIST[i] end
Columns.ICON, Columns.GAP, Columns.MIN_NAME = 44, 4, 120

function Columns.Valid(key)
    local column = type(key) == "string" and Columns.byKey[key] or nil
    if not column then return false end
    return not (column.retail and NS.Client.isForever)
end

local function Shown(column, config)
    if column.retail and NS.Client.isForever then return false end
    return not column.setting or config[column.setting] == true
end

local cachedText, cachedOrder
local function Ordered(config)
    local text = config.listColumnOrder or ""
    if text == "" then return Columns.LIST end
    if text == cachedText then return cachedOrder end
    local order, seen = {}, {}
    for key in text:gmatch("%a+") do
        local column = Columns.byKey[key]
        if column and not seen[column] then
            order[#order + 1], seen[column] = column, true
        end
    end
    for i = 1, #Columns.LIST do
        local column = Columns.LIST[i]
        if not seen[column] then order[#order + 1] = column end
    end
    cachedText, cachedOrder = text, order
    return order
end

function Columns.Move(config, key, neighbor)
    local order = Ordered(config)
    local keys, first, second = {}
    for i = 1, #order do
        local columnKey = order[i].key
        keys[i] = columnKey
        if columnKey == key then first = i end
        if columnKey == neighbor then second = i end
    end
    if not first or not second or first == second then return false end
    keys[first], keys[second] = keys[second], keys[first]
    return S.Set("bags", "listColumnOrder", table.concat(keys, ","))
end

------------------------------------------------------------------ values
local function Equipment(item)
    local slot = item.equipLoc
    return slot ~= nil and slot ~= "" and slot ~= "INVTYPE_NON_EQUIP_IGNORE"
end
Columns.Equipment = Equipment

-- Live items show their effective level (upgrades included), read once per
-- link; offline records only know the base level of the item type.
local function ReadLevel(item)
    if item.offline or not item.link then
        item.listLevel = Equipment(item) and S.Finite(item.itemLevel) and item.itemLevel or nil
        return
    end
    if item.listLevelLink == item.link then return end
    item.listLevelLink = item.link
    local level = Equipment(item) and C_Item.GetDetailedItemLevelInfo(item.link) or nil
    item.listLevel = S.Finite(level) and level > 0 and floor(level) or nil
end

-- The upgrade track of a live item: "Hero 3/6". Read once per link.
local function ReadTrack(item)
    if item.offline or not item.link or item.listTrackLink == item.link then return end
    item.listTrackLink, item.listTrack, item.listTrackRank = item.link, nil, nil
    if not Equipment(item) then return end
    local data = C_Item.GetItemUpgradeInfo(item.link)
    if not S.Public(data) or type(data) ~= "table" then return end
    local current, maximum = data.currentLevel, data.maxLevel
    if not S.Finite(current) or not S.Finite(maximum) or maximum <= 0 or current < 0 or current > maximum then return end
    local track = S.PublicText(data.trackString)
    item.listTrack = (track and track .. " " or "") .. current .. "/" .. maximum
    item.listTrackRank = current
end

-- Instance binding of a live item (SlotCache resolved it), the item type's
-- binding of an offline record. order sorts the column.
local BINDINGS = {
    [BIND_EQUIP] = { "BoE", 1 }, [BIND_UNTIL_EQUIPPED] = { "WuE", 2 },
    [BIND_ACCOUNT] = { "Warbound", 3 }, [BIND_BNET] = { "Warbound", 3 },
    [BIND_QUEST] = { "Quest", 5 },
}
local SOULBOUND = { "Soulbound", 4 }

local function Binding(item)
    local entry
    if item.offline then
        entry = item.bindType == BIND_ACQUIRE and SOULBOUND or BINDINGS[item.bindType]
    else
        local binding = item.binding
        if binding == nil or binding == false then binding = item.bindType end
        entry = BINDINGS[binding]
        if not entry and item.bound == true then entry = SOULBOUND end
    end
    return entry
end

function Columns.Prepare(item, config)
    if not item or not item.itemID then return end
    ReadLevel(item)
    if config.listShowTrack and not NS.Client.isForever then ReadTrack(item) end
end

local function Value(row)
    local price = row.item.sellPrice
    if not S.Finite(price) or price <= 0 then return nil end
    return price * (row.count or 1)
end

-- The number or text a row sorts by in a column; nil sorts last.
local SORT_VALUES = {
    name = function(row) return row.item.name end,
    level = function(row) return row.item.listLevel end,
    track = function(row) return row.item.listTrackRank end,
    count = function(row) return row.count end,
    binding = function(row)
        local entry = Binding(row.item)
        return entry and entry[2]
    end,
    value = Value,
    type = function(row) return row.item.subclassName or row.item.className end,
}

-- The text a row shows in a column ("" for nothing).
function Columns.Text(key, row)
    local item = row.item
    if key == "name" then return item.name or "" end
    if key == "level" then return item.listLevel and tostring(item.listLevel) or "" end
    if key == "track" then return item.listTrack or "" end
    if key == "count" then return tostring(row.count or 1) end
    if key == "binding" then
        local entry = Binding(item)
        return entry and S.Text(entry[1]) or ""
    end
    if key == "value" then
        local value = Value(row)
        return value and S.MoneyText(value) or ""
    end
    if key == "type" then return item.subclassName or item.className or "" end
    return ""
end

------------------------------------------------------------------ sorting
local function Tie(a, b)
    local x, y = a.item, b.item
    local nx, ny = x.name or "", y.name or ""
    if nx ~= ny then return nx < ny end
    if (x.itemID or 0) ~= (y.itemID or 0) then return (x.itemID or 0) < (y.itemID or 0) end
    if (x.bag or 0) ~= (y.bag or 0) then return (x.bag or 0) < (y.bag or 0) end
    return (x.slot or 0) < (y.slot or 0)
end

local comparators = {}

local function MakeComparator(key, desc)
    local value = SORT_VALUES[key]
    return function(a, b)
        local x, y = value(a), value(b)
        if x ~= y then
            if x == nil then return false end
            if y == nil then return true end
            if type(x) ~= type(y) then return type(x) == "number" end
            if desc then return x > y end
            return x < y
        end
        return Tie(a, b)
    end
end

-- The comparator of a column and direction, made once.
function Columns.Comparator(key, desc)
    if not SORT_VALUES[key] then key = "name" end
    local id = key .. (desc and ":d" or ":a")
    local comparator = comparators[id]
    if not comparator then
        comparator = MakeComparator(key, desc == true)
        comparators[id] = comparator
    end
    return comparator
end

------------------------------------------------------------------ fitting
-- The shown columns for a list width, left to right: the name takes what the
-- others leave, and the lowest priority columns leave when it would get less
-- than MIN_NAME. out is refilled with { column, x, width } entries.
local function Wanted(config, width, out)
    local fixed, dropped = Columns.ICON, 0
    local order = Ordered(config)
    for i = #out, 1, -1 do out[i] = nil end
    for i = 1, #order do
        local column = order[i]
        if Shown(column, config) then
            out[#out + 1] = column
            fixed = fixed + column.width + Columns.GAP
        end
    end
    while width - fixed < Columns.MIN_NAME do
        local worst, index
        for i = 1, #out do
            local drop = out[i].drop
            if drop and (not worst or drop > worst) then worst, index = drop, i end
        end
        if not index then break end
        fixed = fixed - out[index].width - Columns.GAP
        table.remove(out, index)
        dropped = dropped + 1
    end
    return fixed, dropped
end

function Columns.Fit(config, width, out, scratch)
    local fixed = Wanted(config, width, scratch)
    local x = Columns.ICON
    for i = 1, #scratch do
        local column = scratch[i]
        local entry = out[i] or {}
        out[i] = entry
        local span = column.width
        if span == 0 then span = math.max(40, width - fixed) end
        entry.column, entry.x, entry.width = column, x, span
        x = x + span + Columns.GAP
    end
    for i = #scratch + 1, #out do out[i] = nil end
    return out
end

-- A key that changes whenever Fit would answer differently.
function Columns.FitKey(config, width)
    local key = tostring(width) .. ":" .. (config.listColumnOrder or "")
    for i = 1, #Columns.LIST do
        local column = Columns.LIST[i]
        if column.setting then key = key .. (config[column.setting] == true and "1" or "0") end
    end
    return key
end
