local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
-- The view modes are the Bags catalog's choice values.
local _, catalog = Support.CatalogDefaults(root, "bags")
local P = { NS = { BagsView = catalog.BagsView } }
-- ItemConstantsDocumentation.lua and ItemQualitiesDocumentation.lua (Retail and Forever).
Enum = { ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6,
        Tradegoods = 7, ItemEnhancement = 8, Recipe = 9, Quiver = 11, Questitem = 12, Key = 13, Miscellaneous = 15 },
    ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 } }
-- Each named mode is the position of its label in the setting's choice list.
do
    local rules = catalog.SuiteCatalog.bags.rules
    local NAMES = {
        { "inventoryView", catalog.BagsView, { ALL = "All items", BY_BAG = "By bag", CATEGORIES = "Categories",
            BLIZZARD_GRID = "Blizzard grid" } },
        { "bankView", catalog.BagsBankView, { TABS = "Bank tabs", CHARACTER = "Combined bank",
            WARBANK = "Combined warbank", CATEGORIES = "Bank categories" } },
        { "sortDirection", catalog.BagsSortDirection, { BLIZZARD = "Blizzard setting", FROM_TOP = "Fill from the top",
            FROM_BOTTOM = "Fill from the bottom" } },
    }
    for _, entry in ipairs(NAMES) do
        local choices, count = rules[entry[1]].choices, 0
        for name, label in pairs(entry[3]) do
            assert(choices[entry[2][name]] == label, entry[1] .. "." .. name .. " does not name " .. label)
            count = count + 1
        end
        assert(count == #choices, entry[1] .. " has a choice without a name")
    end
end
assert(loadfile(root .. "/MSUF_Suite_Bags/InventoryModel.lua"))("Bags", P)
local Model = P.InventoryModel
local function equal(actual, expected, why)
    assert(actual == expected, (why or "value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local categories = {
    { name = "Raid | Mats %", enabled = true, items = { [101] = true, [103] = true } },
    { name = "Hidden", enabled = false, items = { [104] = true } },
}
local encoded = assert(Model.EncodeCategories(categories))
local decoded = Model.DecodeCategories(encoded)
equal(decoded[1].name, categories[1].name, "escaped names round-trip")
assert(decoded[1].items[101] and decoded[1].items[103])
equal(decoded[2].enabled, false)
equal(#Model.DecodeCategories(string.rep("x", 16001)), 0, "bounded profile input")
equal(#Model.DecodeCategories("1|x|12,13\nmalformed\n1|y|-1"), 1, "invalid IDs rejected")

local items = {
    { bag = 0, slot = 1, itemID = 101, link = "item:101:A", count = 5, maxStack = 20, name = "Potion", search = "potion", classID = 0 },
    { bag = 1, slot = 2, itemID = 101, link = "item:101:A", count = 7, maxStack = 20, name = "Potion", search = "potion", classID = 0 },
    { bag = 1, slot = 3, itemID = 101, link = "item:101:B", count = 2, maxStack = 20, name = "Potion", search = "potion", classID = 0 },
    { bag = 0, slot = 2, itemID = 102, link = "item:102", count = 1, maxStack = 1, name = "Helm", search = "helm", equipLoc = "INVTYPE_HEAD", slotName = "Head" },
    { bag = 0, slot = 3 },
}
local config = { inventoryView = 3, mergeStacks = true, customCategories = encoded,
    groupEquipmentSlots = true, hideEmptyCategories = true }
local state = { pinned = {}, recent = {} }
local model = Model.New()
Model.Build(model, items, config, state, {})
-- Custom category groups are keyed by name, not by position.
local custom = "custom:" .. categories[1].name
assert(model.groupsByKey[custom] and not model.groupsByKey["custom:" .. 1], "custom groups must be keyed by their name")
equal(#model.groupsByKey[custom].rows, 2, "only identical links merge")
equal(model.groupsByKey[custom].rows[1].count, 12, "summed quantity")
assert(model.groupsByKey["slot:INVTYPE_HEAD"], "slot grouping")
assert(model.groupsByKey.empty, "drop target remains available")
local representative = model.groupsByKey[custom].rows[1].item
equal(representative.bag, 0, "native identity retained")
equal(representative.slot, 1, "native slot retained")
for _, transaction in ipairs({ "mail", "trade", "auction", "bank", "merchant" }) do
    Model.Build(model, items, config, state, { transactions = transaction })
    equal(#model.groupsByKey[custom].rows, 3, "transaction exposes physical stacks")
end
items[2].bound = true
Model.Build(model, items, config, state, {})
equal(#model.groupsByKey[custom].rows, 3, "binding differs")
items[2].bound, items[2].locked = nil, true
Model.Build(model, items, config, state, {})
equal(#model.groupsByKey[custom].rows, 3, "locked slot never merged")
items[2].locked = false
state.pinned[102], config.showPinned = true, true
state.recent[101], config.showRecent = true, true
for view = 1, 3 do
    config.inventoryView = view
    Model.Build(model, items, config, state, {})
    equal(model.groups[1].key, "pinned", "pinned wins in every view")
    equal(model.groups[2].key, "recent", "recent precedes main inventory")
end
config.hideEmptySlots = true
Model.Build(model, items, config, state, { query = "helm" })
equal(model.rowCount, 1, "search removes other items and empty slots")
Model.Build(model, items, config, state, { selected = "recent" })
equal(model.groupsByKey.pinned.visible, false, "sidebar filters groups")
local layout = Model.Layout(model, 8, true)
for i = 1, #layout do assert(layout[i].line >= 0 and layout[i].column < 8) end
Model.Build(model, items, config, state, {})
Model.Layout(model, 8, true)
equal(model.lineCount, 2, "two small groups share header and item rows")

-- Reordering keeps the key on its category; equal names stay apart.
local swapped = assert(Model.EncodeCategories({ categories[2], categories[1],
    { name = categories[1].name, enabled = true, items = { [102] = true } } }))
config.customCategories = swapped
config.inventoryView, config.showPinned, config.showRecent, config.hideEmptySlots = 3, false, false, false
Model.Build(model, items, config, state, {})
assert(model.groupsByKey[custom].rows[1].item.itemID == 101 and model.groupsByKey[custom].order == 4,
    "a reordered custom category must keep its key")
assert(model.groupsByKey[custom .. "#2"] and model.customIndex[custom] == 2 and model.customIndex[custom .. "#2"] == 3,
    "two categories with one name need distinct keys and their positions")
config.customCategories = encoded

local mixed = {
    { bag = 0, slot = 1, itemID = 601, name = "Potion", search = "potion", classID = 0, expansion = 1 },
    { bag = 0, slot = 2, itemID = 602, name = "Cloth", search = "cloth", classID = 7, expansion = 10 },
}
local bankConfig = { inventoryView = 3, groupExpansions = true, expansionFirst = true, hideEmptyCategories = false }
Model.Build(model, mixed, bankConfig, { pinned = {}, recent = {} }, {})
assert(model.groups[1].key == "reagents:exp:10" and model.groups[2].key == "consumables:exp:1",
    "expansion-first sorts populated groups ahead of synthetic empty categories consistently")
assert(model.groupsByKey.equipment.expansionFirst and #model.groupsByKey.equipment.rows == 0)
for i = 1, 20 do
    Model.Build(model, mixed, bankConfig, { pinned = {}, recent = {} }, {})
    assert(model.groups[1].key == "reagents:exp:10", "pooled groups retain a deterministic expansion order")
end
-- Some reagents report a readable material name but no subclass ID.
do
    local silk = { { bag = 0, slot = 1, itemID = 603, name = "Silk", search = "silk", classID = 7,
        subclassName = "Cloth" } }
    Model.Build(model, silk, { inventoryView = 3, groupReagentTypes = true, hideEmptyCategories = true },
        { pinned = {}, recent = {} }, {})
    local group = model.groupsByKey["reagent:Cloth"]
    assert(group and #group.rows == 1, "a reagent without a subclass ID must group under its material name")
end
local shared = { bag = 0, slot = 1, itemID = 701, name = "Shared helm", search = "shared helm",
    equipLoc = "INVTYPE_HEAD", setName = "Tank", setNames = { "Tank", "Damage" }, expansion = 10 }
local unique = { bag = 0, slot = 2, itemID = 702, name = "Damage chest", search = "damage chest",
    equipLoc = "INVTYPE_CHEST", setName = "Damage", setNames = { "Damage" }, expansion = 10 }
local setConfig = { inventoryView = 3, groupEquipmentSets = true, groupExpansions = true,
    hideEmptyCategories = true, showPinned = true, hideEmptySlots = true }
local setState = { pinned = { [701] = true }, recent = {} }
Model.Build(model, { shared, unique }, setConfig, setState, { selected = "all" })
assert(#model.groupsByKey["set:Tank:exp:10"].rows == 1 and #model.groupsByKey["set:Damage:exp:10"].rows == 2,
    "every set filter retains shared members, including pinned items")
local painted = {}
for _, cell in ipairs(Model.Layout(model, 8, true)) do
    if cell.row then assert(not painted[cell.row.item], "All cannot place one native button twice");painted[cell.row.item] = true end
end
assert(painted[shared] and painted[unique])
Model.Build(model, { shared, unique }, setConfig, setState, { selected = "set:Damage:exp:10" })
local members = 0
for _, cell in ipairs(Model.Layout(model, 8, true)) do if cell.row then members = members + 1 end end
assert(members == 2, "selected secondary set shows all its physical items")
Model.Build(model, { shared, unique }, setConfig, setState, { selected = "set:Damage:exp:10", query = "chest" })
assert(#model.groupsByKey["set:Damage:exp:10"].rows == 1, "set filters still obey explicit search")
setConfig.category_equipment = false
Model.Build(model, { shared, unique }, setConfig, setState, {})
assert(not model.groupsByKey["set:Damage:exp:10"], "disabled equipment category does not reappear through aliases")
local requests, late = 0, false
P.NS = { RootDB = {}, loginKind = "login", BagsView = catalog.BagsView }
P.Suite = { Public = function() return true end, Finite = function(v) return type(v) == "number" end,
    PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end }
UnitGUID = function() return "Player-1" end
local clock = 1000000
GetServerTime = function() return clock end
C_Item = { GetItemInfo = function(link)
    if link == "missing" or link == "late" and not late then return nil end
    return "Potion", link, 1, 1, 1, "Consumable", "Potion", 20, "", nil, 1, 0, 1, 1, 10
end, RequestLoadItemDataByID = function() requests = requests + 1 end }
local slotItems, reads = {}, 0
C_Container = { GetBagName = function() return "Backpack" end,
    GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
    GetContainerItemInfo = function(_, slot)
        reads = reads + 1
        local item = slotItems[slot]
        return item and { itemID = item, hyperlink = "item:" .. item, stackCount = 1 } or nil
    end,
    GetContainerItemQuestInfo = function() return { isQuestItem = false } end }
C_NewItems = { IsNewItem = function() return true end }
assert(loadfile(root .. "/MSUF_Suite_Bags/SlotCache.lua"))("Bags", P)
assert(loadfile(root .. "/MSUF_Suite_Bags/InventoryIndex.lua"))("Bags", P)
local Index, index = P.InventoryIndex, P.InventoryIndex.New()
local button = {}
-- A changed read (new version) builds the record again; one request per item.
Index.ReadButton(index, button, { itemID = 101, hyperlink = "missing", stackCount = 1 }, false, 1, 0, 1)
Index.ReadButton(index, button, { itemID = 101, hyperlink = "missing", stackCount = 1 }, false, 2, 0, 1)
equal(requests, 1, "one asynchronous request per unresolved item")
assert(Index.ItemDataReceived(index, 101))
assert(not Index.ItemDataReceived(index, 999), "unrelated item data ignored")
Index.ReadButton(index, button, { itemID = 201, hyperlink = "missing", stackCount = 1 }, false, 3, 0, 1)
assert(Index.ItemDataReceived(index, 201, false))
local previous = requests
Index.ReadButton(index, button, { itemID = 201, hyperlink = "missing", stackCount = 1 }, false, 4, 0, 1)
assert(requests == previous, "failed metadata does not cause a request/failure loop")
Index.Retry(index)
Index.ReadButton(index, button, { itemID = 201, hyperlink = "missing", stackCount = 1 }, false, 5, 0, 1)
assert(requests == previous + 1, "explicit reopening retries previously failed item data")
-- An unchanged cached read keeps its record: no metadata lookup, no request.
local record = Index.ReadButton(index, button, { itemID = 202, hyperlink = "late", stackCount = 1 }, false, 6, 0, 1)
previous = requests
assert(Index.ReadButton(index, button, nil, false, 6, 0, 1) == record and requests == previous
    and record.itemID == 202 and record.name == "202" and not record.loaded,
    "an unchanged slot read rebuilt its record")
late = true
assert(Index.ItemDataReceived(index, 202) and Index.Refresh(index, 202) and record.name == "Potion" and record.loaded,
    "arriving item data must patch the waiting record without reading the slot")
Index.Reset(index)
assert(index.requestedCount == 0 and next(index.pending) == nil and next(index.records) == nil,
    "disable releases runtime item references and request state")
local buttons = {
    { GetBagID = function() return 0 end, GetID = function() return 2 end },
    { GetBagID = function() return 0 end, GetID = function() return 1 end },
}
local frame = { EnumerateValidItems = function()
    local i = 0
    return function() i = i + 1; if buttons[i] then return i, buttons[i] end end
end }
slotItems[1], slotItems[2] = 301, 301
local fresh, newChecks = true, 0
C_NewItems.IsNewItem = function(_, slot)
    newChecks = newChecks + 1
    return slot == 2 and fresh
end
local moduleState = { recent = { [9] = true }, recentOrder = { 9 }, dismissedRecent = {}, pinned = { [7] = true } }
local view = Index.State(moduleState)
local recent = Index.Recent()
assert(view.pinned[7] and view.recent == recent.items and moduleState.recent == nil and moduleState.recentOrder == nil
    and moduleState.dismissedRecent == nil and P.NS.RootDB.suiteBagRecent["Player-1"] == recent,
    "recent items must live per character outside the profile; pinned items stay in it")
recent.items[301] = true
Index.ClearRecent(recent)
Index.ReadContainer(index, frame, recent)
assert(not recent.items[301] and recent.dismissed[301], "an older identical stack never revives a dismissed fresh stack")
assert(index.items[1].slot == 1 and index.items[2].slot == 2, "slots are listed in physical order")
fresh = false; Index.ReadContainer(index, frame, recent)
assert(not recent.dismissed[301], "dismissals are pruned when the native new-item flag disappears")
-- The client flags an item as new when it arrives, which is a bag change
-- (BAG_UPDATE marks the slot cache); a hover only clears the flag.
fresh = true; P.SlotCache.MarkBag(0); Index.ReadContainer(index, frame, recent)
assert(recent.items[301], "a later genuinely new item is listed again")
reads, newChecks = 0, 0
Index.ReadContainer(index, frame, recent)
assert(reads == 0, "an unchanged bag is not read again")
assert(newChecks == 1, "an unchanged bag asked for the new-item flag of a slot that was not new")

-- Recent items stay across logins, per character, and leave the list once
-- older than recentHours (default 24), so they cannot take over the
-- categories for good. Index.Recent keeps one list per session, so each
-- "login" loads the file again.
local function Login()
    assert(loadfile(root .. "/MSUF_Suite_Bags/InventoryIndex.lua"))("Bags", P)
    Index = P.InventoryIndex
    return Index.Recent()
end
do
    assert(recent.items[301] == clock, "a recent item has no arrival time")
    clock = clock + 3600
    local again = Login()
    assert(again.items[301] and again.order[1] == 301, "a new login emptied the recent items")
    clock = clock + 23 * 3600 + 1
    fresh = false
    Index.ReadContainer(index, frame, again)
    assert(not again.items[301] and #again.order == 0, "a recent item outlived the default 24 hours")
    -- The hours are a Bags setting.
    P.BagsModule = { config = { recentHours = 2 } }
    again.items[401], again.items[402], again.order[1], again.order[2] = clock - 3 * 3600, clock - 3600, 401, 402
    Index.ReadContainer(index, frame, again)
    assert(not again.items[401] and again.items[402] and again.order[1] == 402 and #again.order == 1,
        "recentHours did not decide which recent items stay")
    -- The session list of older builds moves to its character; its items
    -- count from the login. Another character's expired list is dropped.
    P.NS.RootDB.suiteBagRecent = { guid = "Player-1", items = { [501] = true }, order = { 501 }, dismissed = {} }
    local migrated = Login()
    local saved = P.NS.RootDB.suiteBagRecent
    assert(saved["Player-1"] == migrated and migrated.items[501] == clock and saved.guid == nil,
        "the older session list was not kept for its character")
    saved["Player-2"] = { items = { [601] = clock - 10 * 3600 }, order = { 601 }, dismissed = {} }
    saved["Player-3"] = { items = { [701] = clock - 600 }, order = { 701 }, dismissed = {} }
    Login()
    assert(saved["Player-2"] == nil and saved["Player-3"].items[701], "another character's lists were not expired")
    P.BagsModule = nil
    local catalogNS = { Client = { isForever = false }, Text = function(text) return text end, Defaults = {} }
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", catalogNS)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Bags.lua"))("MSUF_Suite", catalogNS)
    local rule = catalogNS.SuiteCatalog.bags.rules.recentHours
    assert(rule.default == 24 and rule.min == 1 and rule.max == 168 and rule.enableKey == "showRecent",
        "Keep recent items for (hours) is not a 1 to 168 hour setting below Show recent items")
end
print("bag categories, stack identity, metadata retry, recent dismissal, expiry and reset contracts passed")
