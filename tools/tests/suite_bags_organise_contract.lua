-- Bags organisation: the sort modes, the search grammar and saved searches,
-- the optional built-in categories, the free slot count, collapsible
-- category headers and the upgrade marker. The model and grammar run on their
-- own; the views run against the client model of suite_bags_harness.lua with
-- the FULL Bags TOC loaded.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function equal(actual, expected, why)
    assert(actual == expected, (why or "value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

---------------------------------------------------------------- the settings
local _, catalog = Support.CatalogDefaults(root, "bags")
local rules, SORT = catalog.SuiteCatalog.bags.rules, catalog.BagsSort
do
    local labels = { NAME = "Name", QUALITY = "Quality", ITEM_LEVEL = "Item level", TYPE = "Type",
        EXPANSION = "Expansion", STACK = "Stack count", PRICE = "Vendor price" }
    local count = 0
    for name, label in pairs(labels) do
        equal(rules.sortMode.choices[SORT[name]], label, "sortMode choice " .. name)
        count = count + 1
    end
    equal(count, #rules.sortMode.choices, "every sort mode has a name")
    equal(rules.sortMode.default, SORT.NAME, "Name stays the default order")
    -- Purely additive information may start on; the categories start off.
    equal(rules.showFreeSlots.default, true, "free slot count default")
    equal(rules.showUpgradeMarker.default, false, "upgrade marker default (the pinned bag refresh budget)")
    for _, key in ipairs({ "professionGear", "collectibles", "containers" }) do
        equal(rules["category_" .. key].default, false, key .. " category default")
    end
    for _, key in ipairs({ "equipment", "consumables", "reagents", "recipes", "quest", "junk" }) do
        equal(rules["category_" .. key].default, true, key .. " category default")
    end
end

---------------------------------------------------------------- the search grammar
local W0 = H.New(root)
local Rules = W0.NS.InventoryRules
local function Matches(query, item)
    return Rules.Matches(assert(Rules.Compile(query), "does not compile: " .. query), item)
end
local function Invalid(query)
    assert(Rules.Compile(query) == nil, "should not compile: " .. query)
end
do
    local helm = { name = "Sunlit Helm", search = "sunlit helm", itemLevel = 250, quality = 4, count = 1, expansion = 10,
        expansionName = "The War Within", bindType = 2, bound = false, setNames = { "Raid" } }
    -- exp: the expansion's number, or its name.
    assert(Matches("exp:10", helm) and Matches("exp=10", helm) and Matches("exp>=10", helm) and Matches("expansion:10", helm))
    assert(not Matches("exp:11", helm) and not Matches("exp<10", helm) and not Matches("!exp:10", helm))
    assert(Matches("exp:war", helm) and Matches('exp:"war within"', helm) and Matches("exp=WITHIN", helm))
    assert(not Matches("exp:legion", helm) and Matches("!exp:legion", helm))
    assert(not Matches("exp:war", { expansion = 10 }), "an expansion without a name matches by number only")
    Invalid("exp>war")
    -- Binding: Bind on Equip and Warbound until equipped only while unbound.
    assert(Matches("is:boe", helm) and Matches("is:BoE", helm) and not Matches("!is:boe", helm))
    assert(not Matches("is:boe", { bindType = 2, bound = true }), "a bound Bind on Equip item is no longer one")
    assert(Matches("is:wue", { bindType = 9, bound = false }) and not Matches("is:wue", { bindType = 9, bound = true }))
    assert(not Matches("is:wue", helm) and not Matches("is:boe", { bindType = 9 }))
    assert(Matches("is:warbound", { bindType = 7 }) and Matches("is:warbound", { bindType = 8 }))
    assert(not Matches("is:warbound", { bindType = 9 }) and not Matches("is:warbound", helm))
    assert(not Matches("is:boe", { name = "no bind type read" }))
    -- Junk is grey quality; set means an equipment set holds the item.
    assert(Matches("is:junk", { quality = 0 }) and not Matches("is:junk", { quality = 1 }) and not Matches("is:junk", {}))
    assert(Matches("is:set", helm) and not Matches("is:set", { name = "x" }) and Matches("!is:set", { name = "x" }))
    -- Level and number ranges are inclusive and take either order.
    assert(Matches("level=200-300", helm) and Matches("level:250-250", helm) and Matches("level=250-300", helm))
    assert(Matches("level=200-250", helm) and Matches("level=300-200", helm) and Matches("!level=300-400", helm))
    assert(not Matches("level=251-300", helm) and not Matches("level=100-249", helm))
    assert(Matches("quality=3-4", helm) and not Matches("quality=0-3", helm) and Matches("count=1-5", helm))
    assert(not Matches("level=200-300", { name = "no level" }))
    for _, bad in ipairs({ "level=200-", "level>200-300", "level=a-b", "level=1-2-3", "is:nonsense",
        "level=1-99999999" }) do
        Invalid(bad)
    end
    -- Combinations and the earlier grammar keep working.
    assert(Matches("is:boe level=200-300 exp:war", helm) and not Matches("is:boe level=300-400", helm))
    assert(Matches("is:warbound | is:boe", helm) and Matches("quality>=3 !is:bound helm", helm))
    assert(Matches("level>=250 is:equipment", { itemLevel = 250, equipLoc = "INVTYPE_HEAD" }))
end

---------------------------------------------------------------- saved searches
local Saved = W0.P.SavedSearches
do
    local state = {}
    local list = Saved.List(state)
    assert(list == state.searches and #list == 0 and Saved.List(state) == list, "the list lives in the profile state")
    assert(Saved.Add(list, "  is:boe  ") and list[1] == "is:boe", "a saved search is trimmed")
    local ok, why = Saved.Add(list, "is:boe")
    assert(not ok and why == "saved", "the same search twice")
    ok, why = Saved.Add(list, 'name:"unclosed')
    assert(not ok and why == "invalid", "a search that does not compile is not kept")
    ok, why = Saved.Add(list, "   ")
    assert(not ok and why == "invalid", "an empty search is not kept")
    for i = 2, Saved.MAX do assert(Saved.Add(list, "level>" .. i)) end
    equal(#list, 12, "the cap is twelve")
    ok, why = Saved.Add(list, "quality>1")
    assert(not ok and why == "full" and #list == 12, "a thirteenth search")
    Saved.Remove(list, 1)
    assert(#list == 11 and list[1] == "level>2", "removal keeps the order of the rest")
    assert(Saved.Add(list, "quality>1") and #list == 12, "removal makes room")
    Saved.Remove(list, 99)
    equal(#list, 12, "removing nothing")
    -- A hand-edited or damaged list is cleaned: strings only, no duplicates, at most twelve.
    local damaged = { searches = { "a", "a", 5, "", string.rep("x", 600), "b" } }
    local clean = Saved.List(damaged)
    assert(#clean == 2 and clean[1] == "a" and clean[2] == "b" and damaged.searches == clean, "damaged list")
    local many = { searches = {} }
    for i = 1, 20 do many.searches[i] = "word" .. i end
    equal(#Saved.List(many), 12, "an over-long list is cut to the cap")
    assert(Saved.List({ searches = "text" }) ~= nil, "a list that is no table starts over")
end

-- The Filters menu: presets, saved searches, saving and removing.
do
    local state = { searches = { "is:boe", "level=200-300" } }
    local P = { NS = { IsCombatLocked = function() return false end, InventoryRules = Rules }, SavedSearches = Saved }
    local menu
    local function Node(kind, text, callback)
        local node = { kind = kind, text = text, callback = callback, children = {} }
        function node:CreateTitle(title) return self:Add(Node("title", title)) end
        function node:CreateDivider() return self:Add(Node("divider")) end
        function node:CreateButton(label, action) return self:Add(Node("button", label, action)) end
        function node:SetEnabled(value) self.enabled = value end
        function node:Add(child) self.children[#self.children + 1] = child; return child end
        return node
    end
    P.Suite = { Text = function(text) return text end, ModuleState = function() return state end,
        ContextMenu = function(owner, generator) menu = Node("root"); generator(owner, menu) end }
    assert(loadfile(root .. "/MSUF_Suite_Bags/SmartSearch.lua"))("Bags", P)
    local edit = { text = "quality>=3", GetText = function(self) return self.text end,
        SetText = function(self, value) self.text = value end }
    local function Find(parent, text)
        for _, child in ipairs(parent.children) do if child.text == text then return child end end
    end
    P.InventorySearch.Menu({}, edit)
    assert(Find(menu, "Smart search presets") and Find(menu, "Bind on Equip") and Find(menu, "Warbound items"),
        "the presets lost their entries")
    Find(menu, "Bind on Equip").callback()
    equal(edit.text, "is:boe", "a preset fills the box")
    assert(Find(menu, "Saved searches") and Find(menu, "level=200-300"), "saved searches are listed")
    Find(menu, "level=200-300").callback()
    equal(edit.text, "level=200-300", "a saved search fills the box")
    P.InventorySearch.Menu({}, edit)
    assert(Find(menu, "Save this search").enabled == false, "an already saved search offers no save")
    edit.text = "quality>=3"
    P.InventorySearch.Menu({}, edit)
    local save = Find(menu, "Save this search")
    assert(save.enabled == true, "a new valid search can be saved")
    save.callback()
    equal(state.searches[3], "quality>=3", "Save this search stores the box's text")
    P.InventorySearch.Menu({}, edit)
    local remove = assert(Find(menu, "Remove a saved search"), "no way to remove a saved search")
    assert(#remove.children == 3 and Find(remove, "is:boe"), "every saved search can be removed")
    Find(remove, "is:boe").callback()
    assert(#state.searches == 2 and state.searches[1] == "level=200-300", "the chosen search is removed")
    edit.text = ""
    P.InventorySearch.Menu({}, edit)
    assert(Find(menu, "Save this search").enabled == false, "an empty box offers no save")
    -- The menu shows a stored "|" as text, not as an escape code.
    state.searches = { "is:boe | is:wue" }
    P.InventorySearch.Menu({}, edit)
    assert(Find(menu, "is:boe || is:wue"), "a pipe in a saved search must be doubled in the menu")
    state.searches = nil
    P.InventorySearch.Menu({}, edit)
    assert(not Find(menu, "Remove a saved search") and not Find(menu, "Saved searches"), "no saved searches, no list")
end

---------------------------------------------------------------- the model
local Model = W0.P.InventoryModel
local CLASS = Enum.ItemClass
-- Rows in a named order; the model builds from plain index records.
local function Names(group)
    local names = {}
    for i, row in ipairs(group.displayRows) do names[i] = row.item.name end
    return table.concat(names, ",")
end
local function Order(items, config, context)
    local model = Model.New()
    Model.Build(model, items, config, { pinned = {}, recent = {}, collapsed = {} }, context or {})
    return Names(model.groups[1]), model
end
do
    -- Apple: common potion; Bread: epic armor; Cherry: rare weapon with nothing read.
    local apple = { bag = 0, slot = 1, itemID = 1, link = "a", name = "Apple", count = 5, quality = 2, itemLevel = 100,
        classID = 0, subclassID = 1, expansion = 9, sellPrice = 10, maxStack = 20 }
    local bread = { bag = 0, slot = 2, itemID = 2, link = "b", name = "Bread", count = 20, quality = 4, itemLevel = 50,
        classID = 4, subclassID = 2, expansion = 11, sellPrice = 5, maxStack = 20 }
    local cherry = { bag = 0, slot = 3, itemID = 3, link = "c", name = "Cherry", count = 1, quality = 3,
        classID = 2, subclassID = 0, maxStack = 1 }
    local items = { cherry, apple, bread }
    local function Sorted(mode, extra)
        local config = { inventoryView = 1, sortMode = mode }
        for key, value in pairs(extra or {}) do config[key] = value end
        return (Order(items, config))
    end
    equal(Sorted(SORT.NAME), "Cherry,Apple,Bread", "Name keeps the read order outside Categories")
    equal(Sorted(nil), "Cherry,Apple,Bread", "a profile without the setting keeps the read order")
    equal(Sorted(SORT.QUALITY), "Bread,Cherry,Apple", "best quality first")
    equal(Sorted(SORT.ITEM_LEVEL), "Apple,Bread,Cherry", "highest item level first, unread last")
    equal(Sorted(SORT.TYPE), "Apple,Cherry,Bread", "item class order")
    equal(Sorted(SORT.EXPANSION), "Bread,Apple,Cherry", "newest expansion first, unread last")
    equal(Sorted(SORT.STACK), "Bread,Apple,Cherry", "largest stack first")
    equal(Sorted(SORT.PRICE), "Apple,Bread,Cherry", "dearest first, unread last")
    equal(Sorted(SORT.QUALITY, { inventoryView = 2 }), "Bread,Cherry,Apple", "By bag sorts too")
    -- Name is the name order in Categories, as before.
    local _, model = Order(items, { inventoryView = 3, sortMode = SORT.NAME, hideEmptyCategories = true })
    equal(Names(model.groupsByKey.other), "Bread,Cherry", "Categories sorts by name, as before")
    -- Equal numbers fall back to the name; a merged stack counts its total.
    local twin = { bag = 0, slot = 4, itemID = 4, link = "d", name = "Dill", count = 5, quality = 2, itemLevel = 100,
        classID = 0, subclassID = 1, expansion = 9, sellPrice = 10, maxStack = 20 }
    equal((Order({ twin, apple }, { inventoryView = 1, sortMode = SORT.QUALITY })), "Apple,Dill", "ties by name")
    local second = { bag = 0, slot = 5, itemID = 2, link = "b", name = "Bread", count = 20, quality = 4, itemLevel = 50,
        classID = 4, subclassID = 2, expansion = 11, sellPrice = 5, maxStack = 20 }
    local small = { bag = 1, slot = 1, itemID = 5, link = "e", name = "Egg", count = 30, quality = 1, maxStack = 100 }
    equal((Order({ small, bread, second }, { inventoryView = 1, sortMode = SORT.STACK, mergeStacks = true })),
        "Bread,Egg", "merged stacks sort by their total")
    -- A shuffle outranks the mode (quality alone would give Bread, Cherry, Apple).
    apple.shuffle, bread.shuffle, cherry.shuffle = 0.1, 0.9, 0.5
    equal((Order(items, { inventoryView = 1, sortMode = SORT.QUALITY }, { shuffle = true })), "Apple,Cherry,Bread",
        "the shuffle outranks the sort mode")
    apple.shuffle, bread.shuffle, cherry.shuffle = nil, nil, nil
end

-- The optional built-in categories.
do
    local function Item(fields)
        local item = { bag = 0, slot = 1, itemID = 1, name = "x", search = "x", quality = 1 }
        for key, value in pairs(fields) do item[key] = value end
        return item
    end
    local toy = Item({ classID = CLASS.Miscellaneous, subclassID = 4, toy = true })
    local mount = Item({ classID = CLASS.Miscellaneous, subclassID = 5 })
    local pet = Item({ classID = CLASS.Miscellaneous, subclassID = 2 })
    local cagedPet = Item({ classID = CLASS.Battlepet, subclassID = 0 })
    local cosmetic = Item({ classID = CLASS.Armor, subclassID = 5, equipLoc = "INVTYPE_CHEST" })
    local plainMisc = Item({ classID = CLASS.Miscellaneous, subclassID = 4 })
    local bag = Item({ classID = CLASS.Container, subclassID = 0, equipLoc = "INVTYPE_BAG" })
    local tool = Item({ classID = CLASS.Profession, subclassID = 0, equipLoc = "INVTYPE_PROFESSION_TOOL" })
    local helm = Item({ classID = CLASS.Armor, subclassID = 1, equipLoc = "INVTYPE_HEAD" })
    local grayToy = Item({ classID = CLASS.Miscellaneous, subclassID = 5, quality = 0 })
    local function Key(item, config)
        return (Model.Category(item, {}, Model.EnabledOptional(config, {})))
    end
    local off, on = {}, { category_collectibles = true, category_containers = true, category_professionGear = true }
    -- Off, nothing moves: the categories the layout always had.
    equal(Key(toy, off), "other", "toy, categories off")
    equal(Key(mount, off), "other", "mount, categories off")
    equal(Key(bag, off), "equipment", "bag, categories off")
    equal(Key(tool, off), "equipment", "profession tool, categories off")
    equal(Key(cosmetic, off), "equipment", "cosmetic armor, categories off")
    equal((Model.Category(toy, {})), "other", "an older caller without the list")
    for _, item in ipairs({ toy, mount, pet, cagedPet, cosmetic }) do
        equal(Key(item, on), "collectibles", "collectible " .. tostring(item.classID) .. "/" .. tostring(item.subclassID))
    end
    equal(Key(plainMisc, on), "other", "a plain miscellaneous item stays in other items")
    equal(Key(bag, on), "containers", "bags")
    equal(Key(tool, on), "professionGear", "profession gear")
    equal(Key(helm, on), "equipment", "ordinary armor stays equipment")
    equal(Key(grayToy, on), "junk", "junk outranks the optional categories")
    equal(Key(mount, { category_collectibles = true }), "collectibles", "each category has its own switch")
    equal(Key(tool, { category_collectibles = true }), "equipment", "profession gear needs its switch")
    -- The view: groups appear in Categories only when on, also empty when empty categories show.
    local config = { inventoryView = 3, hideEmptyCategories = false }
    local model = Model.New()
    Model.Build(model, { mount, tool }, config, { pinned = {}, recent = {} }, {})
    assert(not model.groupsByKey.collectibles and not model.groupsByKey.professionGear and not model.groupsByKey.containers,
        "off categories are no empty groups")
    equal(#model.groupsByKey.other.rows, 1, "the mount waits in other items")
    config.category_collectibles, config.category_containers = true, true
    Model.Build(model, { mount, tool }, config, { pinned = {}, recent = {} }, {})
    equal(#model.groupsByKey.collectibles.rows, 1, "the mount moved to collectibles")
    equal(#model.groupsByKey.equipment.rows, 1, "the tool stays in equipment")
    assert(model.groupsByKey.containers and #model.groupsByKey.containers.rows == 0, "an empty containers category shows")
    assert(not model.groupsByKey.professionGear, "profession gear stays off")
    equal(model.groupsByKey.collectibles.label, "Collectibles", "label")
    -- Disabling a category sends its items to other items, the optional ones included.
    config.category_collectibles = false
    Model.Build(model, { mount }, config, { pinned = {}, recent = {} }, {})
    assert(model.groupsByKey.other and not model.groupsByKey.collectibles, "switching it off moves the mount back")
end

-- Collapsed groups.
do
    local potion = { bag = 0, slot = 1, itemID = 1, link = "p", name = "Potion", search = "potion", classID = 0,
        maxStack = 20, count = 1 }
    local potion2 = { bag = 0, slot = 2, itemID = 2, link = "q", name = "Elixir", search = "elixir", classID = 0,
        maxStack = 20, count = 1 }
    local cloth = { bag = 0, slot = 3, itemID = 3, link = "c", name = "Cloth", search = "cloth", classID = 7,
        maxStack = 20, count = 1 }
    local items = { potion, potion2, cloth }
    local config = { inventoryView = 3, hideEmptyCategories = true, compactGroups = true }
    local state = { pinned = {}, recent = {}, collapsed = { consumables = true } }
    local model = Model.New()
    Model.Build(model, items, config, state, {})
    local group = model.groupsByKey.consumables
    assert(group.collapsed and #group.displayRows == 0 and group.hidden == 2, "a collapsed group shows no rows")
    equal(#model.groupsByKey.reagents.displayRows, 1, "other groups are untouched")
    local layout = Model.Layout(model, 8, true)
    local headers, cells = {}, 0
    for _, cell in ipairs(layout) do
        if cell.row then cells = cells + 1 else headers[#headers + 1] = cell.group.key end
    end
    assert(cells == 1 and #headers == 2 and (headers[1] == "consumables" or headers[2] == "consumables"),
        "a collapsed group keeps its header in the layout")
    -- A search shows its matches; one selected group shows its items; other views never collapse.
    Model.Build(model, items, config, state, { query = "potion" })
    assert(not model.groupsByKey.consumables.collapsed and #model.groupsByKey.consumables.displayRows == 1, "search")
    Model.Build(model, items, config, state, { selected = "consumables" })
    assert(not model.groupsByKey.consumables.collapsed and #model.groupsByKey.consumables.displayRows == 2, "selected")
    Model.Build(model, items, config, state, { searching = true })
    assert(not model.groupsByKey.consumables.collapsed, "Blizzard's search")
    config.inventoryView = 1
    Model.Build(model, items, config, state, {})
    assert(not model.groupsByKey.all.collapsed and #model.groupsByKey.all.displayRows == 3, "All items never collapses")
    config.inventoryView = 3
    -- The toggle flips a key. A full set drops the keys of groups that are gone before it refuses.
    local set, live = {}, {}
    assert(Model.ToggleCollapsed(set, "a", live) and set.a == true)
    assert(Model.ToggleCollapsed(set, "a", live) and set.a == nil)
    for i = 1, Model.MAX_COLLAPSED do assert(Model.ToggleCollapsed(set, "dead" .. i, live)) end
    assert(Model.ToggleCollapsed(set, "fresh", live) and set.fresh == true and set.dead1 == nil
        and set["dead" .. Model.MAX_COLLAPSED] == nil, "a full set of dead keys must make room")
    set = {}
    for i = 1, Model.MAX_COLLAPSED do
        live["key" .. i] = true
        assert(Model.ToggleCollapsed(set, "key" .. i, live))
    end
    assert(not Model.ToggleCollapsed(set, "one too many", live) and set["one too many"] == nil and set.key1,
        "a set of live groups is capped")
    assert(Model.ToggleCollapsed(set, "key1", live) and set.key1 == nil, "a full set can always expand")
    -- A custom category that was deleted or renamed leaves no collapsed key behind, whatever its suffix.
    local custom = Model.EncodeCategories({ { name = "Kept", enabled = true, items = { [1] = true } } })
    local pruned = { ["custom:Gone"] = true, ["custom:Gone:exp:9"] = true, ["custom:Kept"] = true,
        ["custom:Kept:exp:10"] = true, consumables = true, ["slot:INVTYPE_HEAD"] = true }
    local pruneModel = Model.New()
    Model.Build(pruneModel, items, { inventoryView = 3, customCategories = custom }, { collapsed = pruned }, {})
    assert(pruned["custom:Gone"] == nil and pruned["custom:Gone:exp:9"] == nil, "deleted custom categories stay collapsed")
    assert(pruned["custom:Kept"] and pruned["custom:Kept:exp:10"] and pruned.consumables and pruned["slot:INVTYPE_HEAD"],
        "live and built-in keys must stay")
    Model.Build(pruneModel, items, { inventoryView = 3, customCategories = "" }, { collapsed = pruned }, {})
    assert(pruned["custom:Kept"] == nil and pruned["custom:Kept:exp:10"] == nil and pruned.consumables,
        "a renamed custom category leaves its collapsed keys")
end

-- A rule or a search of blanks is no filter on a category.
do
    assert(not Rules.HasTerms(Rules.Compile("   ")) and not Rules.HasTerms(Rules.Compile('""'))
        and Rules.HasTerms(Rules.Compile("a")) and Rules.HasTerms(Rules.Compile("a | b")) and not Rules.HasTerms(nil),
        "HasTerms")
    local decoded = Model.DecodeCategories('1|Blank|1|   \n1|Quotes|2|""\n1|Real|3|is:boe')
    equal(#decoded, 3, "categories with blank rules are kept")
    assert(decoded[1].rule == nil and decoded[1].query == nil, "a rule of spaces is no rule")
    assert(decoded[2].rule == nil and decoded[2].query == nil, "a rule of empty quotes is no rule")
    assert(decoded[3].rule and decoded[3].query == "is:boe", "a real rule stays")
    local item = { itemID = 99, quality = 1, name = "x", search = "x" }
    assert(Model.Category(item, decoded) ~= "custom:Blank", "a blank rule took an item")
    equal(Model.EncodeCategories({ { name = "Blank", enabled = true, items = {}, query = "   " } }), "1|Blank|",
        "a blank rule is not saved")
    local model = Model.New()
    Model.Build(model, { item }, { inventoryView = 3, customCategories = "1|Blank|1|   " }, { pinned = {}, recent = {} }, {})
    assert(not model.groupsByKey["custom:Blank"] or #model.groupsByKey["custom:Blank"].rows == 0, "a blank rule swallows items")
    Model.Build(model, { item }, { inventoryView = 3 }, { pinned = {}, recent = {} }, { query = "   " })
    assert(model.rowCount == 1, "a search of spaces filters nothing")
    Model.Build(model, { item }, { inventoryView = 3 }, { pinned = {}, recent = {}, collapsed = { other = true } },
        { query = "   " })
    assert(model.groupsByKey.other.collapsed, "a search of spaces is no search: a collapsed group stays collapsed")
end

---------------------------------------------------------------- the views
local function Groups(V) return V.model.groupsByKey end

local function Bags(client, options)
    options = options or {}
    options.client = client
    local W = H.New(root, options)
    W.sizes[0], W.sizes[1], W.sizes[5] = 5, 3, options.reagentSlots or 0
    W.Define(10, { name = "Bread", class = 0, maxStack = 20, quality = 1, sellPrice = 5 })
    W.Define(20, { name = "Sunlit Helm", class = 4, subclass = 1, equipLoc = "INVTYPE_HEAD", quality = 4, level = 300,
        bind = 2 })
    W.Define(21, { name = "Ring C", class = 4, subclass = 0, equipLoc = "INVTYPE_FINGER", quality = 3, level = 250 })
    W.Define(22, { name = "Ring D", class = 4, subclass = 0, equipLoc = "INVTYPE_FINGER", quality = 3, level = 190 })
    W.Define(23, { name = "Plate Helm", class = 4, subclass = 4, equipLoc = "INVTYPE_HEAD", quality = 4, level = 400 })
    W.Define(24, { name = "Forbidden Trinket", class = 4, subclass = 0, equipLoc = "INVTYPE_TRINKET", quality = 4,
        level = 500 })
    W.Define(25, { name = "Worn helm", class = 4, subclass = 1, equipLoc = "INVTYPE_HEAD", quality = 4, level = 250 })
    W.Define(26, { name = "Worn ring A", class = 4, subclass = 0, equipLoc = "INVTYPE_FINGER", quality = 4, level = 280 })
    W.Define(27, { name = "Worn ring B", class = 4, subclass = 0, equipLoc = "INVTYPE_FINGER", quality = 4, level = 200 })
    W.Define(30, { name = "Silk", class = 7, quality = 1, maxStack = 200 })
    return W
end

local function ButtonOf(V, itemID)
    for _, item in ipairs(V.index.items) do
        if item.itemID == itemID then return item.button, item end
    end
end

local function ArrowShown(W, itemID)
    local marker = W.P.InventoryDetails.markers[ButtonOf(W.P.InventoryView, itemID)]
    return marker ~= nil and marker.shown == true
end

for _, client in ipairs({ "Mainline", "Forever" }) do
    ---------------------------------------------------------------- sorting in the view
    do
        local W = Bags(client, { config = { inventoryView = 1, mergeStacks = false, sortMode = SORT.QUALITY } })
        W.Put(0, 1, 10, 5)
        W.Put(0, 2, 21, 1)
        W.Put(0, 3, 20, 1)
        W.Apply()
        W.OpenBags()
        W.Settle()
        local V = W.P.InventoryView
        local ids = {}
        for i, row in ipairs(Groups(V).all.displayRows) do ids[i] = row.item.itemID end
        equal(table.concat(ids, ",", 1, 3), "20,21,10", client .. ": quality order in All items")
        W.config.sortMode = SORT.NAME
        W.Apply()
        W.Settle()
        ids = {}
        for i, row in ipairs(Groups(V).all.displayRows) do ids[i] = row.item.itemID end
        equal(table.concat(ids, ",", 1, 3), "10,21,20", client .. ": Name keeps the physical order")
        -- Item level sorting reads the effective level of gear, never of the rest.
        W.config.sortMode = SORT.ITEM_LEVEL
        W.Apply()
        W.Settle()
        ids = {}
        for i, row in ipairs(Groups(V).all.displayRows) do ids[i] = row.item.itemID end
        equal(table.concat(ids, ",", 1, 3), "20,21,10", client .. ": item level order")
    end

    ---------------------------------------------------------------- free slots
    do
        local W = Bags(client, { reagentSlots = 4, config = { inventoryView = 1 } })
        W.Put(0, 1, 10, 5)
        W.Put(0, 2, 20, 1)
        W.Put(1, 1, 21, 1)
        W.Put(5, 1, 30, 20)
        W.Apply()
        W.OpenBags()
        W.Settle()
        local V = W.P.InventoryView
        assert(V.free and V.free.shown, client .. ": the free slot count is missing")
        equal(V.free.text, "5 free + 3 reagent", client .. ": 8 bag slots, 3 used; 4 reagent slots, 1 used")
        W.Put(0, 3, 22, 1)
        W.BagChanged(0)
        W.Put(5, 2, 30, 20)
        W.Fire("BAG_UPDATE", 5)
        W.Settle()
        equal(V.free.text, "4 free + 2 reagent", client .. ": the count follows bag changes")
        -- Blizzard's own refresh reads every slot; the count adds no read to it.
        local before = W.calls.info
        W.Native(function() W.CF:UpdateItems() end)
        local native = W.calls.info - before
        W.Settle()
        before = W.calls.info
        W.Native(function() W.CF:UpdateItems() end)
        W.Settle()
        equal(W.calls.info - before, native, client .. ": the free slot count read slots again")
        W.sizes[5] = 0
        W.Fire("BAG_UPDATE", 5)
        W.Fire("BAG_UPDATE_DELAYED")
        W.Settle()
        equal(V.free.text, "4 free", client .. ": no reagent bag, no reagent count")
        W.config.showFreeSlots = false
        W.Apply()
        W.Settle()
        assert(not V.free.shown, client .. ": Show the free slot count does not hide it")
    end

    ---------------------------------------------------------------- collapsible headers
    do
        local state = {}
        local view = { inventoryView = 3, hideEmptyCategories = true, groupEquipmentSlots = false }
        local W = Bags(client, { moduleState = state, config = view })
        W.Put(0, 1, 10, 5)
        W.Put(0, 2, 20, 1)
        W.Put(0, 3, 21, 1)
        W.Apply()
        W.OpenBags()
        W.Settle()
        local V = W.P.InventoryView
        local function Hit(key)
            for _, label in ipairs(V.labels) do
                if label.shown and label.hit and label.hit.shown and label.hit.key == key then return label.hit end
            end
        end
        local hit = assert(Hit("equipment"), client .. ": category headers are not clickable")
        assert(ButtonOf(V, 20).shown, client .. ": equipment starts expanded")
        W.Insecure(hit.scripts.OnClick, hit, "LeftButton")
        W.Settle()
        assert(state.collapsed and state.collapsed.equipment == true, client .. ": the collapsed set is not stored")
        assert(not ButtonOf(V, 20).shown and not ButtonOf(V, 21).shown, client .. ": a collapsed group still shows its items")
        assert(ButtonOf(V, 10).shown, client .. ": another group collapsed too")
        hit = assert(Hit("equipment"), client .. ": the collapsed header disappeared")
        assert(hit.plus.shown and hit.collapsed, client .. ": a collapsed header shows no plus sign")
        local label
        for _, candidate in ipairs(V.labels) do if candidate.hit == hit then label = candidate end end
        assert(label.text:find("(2)", 1, true), client .. ": a collapsed header does not count its items: " .. tostring(label.text))
        -- Searching shows the matches of a collapsed group.
        local search = V.smartSearch
        search.text = "sunlit"
        W.Insecure(search.scripts.OnTextChanged, search)
        W.Settle()
        assert(ButtonOf(V, 20).shown, client .. ": a search must show matches inside a collapsed group")
        search.text = ""
        W.Insecure(search.scripts.OnTextChanged, search)
        W.Settle()
        hit = Hit("equipment")
        W.Insecure(hit.scripts.OnClick, hit, "LeftButton")
        W.Settle()
        assert(state.collapsed.equipment == nil and ButtonOf(V, 20).shown, client .. ": a second click expands it again")
        -- All items never collapses and has no header buttons.
        W.config.inventoryView = 1
        W.Apply()
        W.Settle()
        assert(not Hit("equipment"), client .. ": All items has clickable headers")
        W.config.inventoryView = 3
        W.Apply()
        W.Settle()
        hit = Hit("equipment")
        W.Insecure(hit.scripts.OnClick, hit, "LeftButton")
        W.Settle()
        -- A new session on the same profile finds it collapsed.
        local again = Bags(client, { moduleState = state, config = view })
        again.Put(0, 1, 10, 5)
        again.Put(0, 2, 20, 1)
        again.Apply()
        again.OpenBags()
        again.Settle()
        assert(not ButtonOf(again.P.InventoryView, 20).shown, client .. ": the collapsed set did not survive a reload")
    end

    ---------------------------------------------------------------- the search box in combat and set tokens
    do
        local W = Bags(client, { config = { inventoryView = 1, groupEquipmentSets = false, showEquipmentSetNames = false } })
        W.Put(0, 1, 10, 5)
        W.Put(0, 2, 20, 1)
        W.equipmentSets[1] = { name = "Raid", locations = { 100 } }
        W.locations[100] = { isBags = true, bag = 0, slot = 2 }
        W.Apply()
        W.OpenBags()
        W.Settle()
        local V = W.P.InventoryView
        local function Items()
            local ids, all = {}, Groups(V).all
            for _, row in ipairs(all and all.displayRows or {}) do
                if row.item.itemID then ids[#ids + 1] = row.item.itemID end
            end
            return table.concat(ids, ",")
        end
        local function Type(text)
            V.smartSearch.text = text
            W.Insecure(V.smartSearch.scripts.OnTextChanged, V.smartSearch)
            W.Settle()
        end
        -- Every spelling of a set token loads the equipment sets, with no set feature switched on.
        equal(Items(), "10,20", client .. ": both items before a search")
        for _, query in ipairs({ "set=raid", "set:raid", "SET=Raid", "is:set", "!set=nothing is:set" }) do
            Type(query)
            equal(Items(), "20", client .. ": " .. query .. " must find the item of the Raid set")
        end
        Type("!is:set")
        equal(Items(), "10", client .. ": !is:set")
        Type("")
        -- What is typed in combat is kept and built when combat ends; the layout is not touched meanwhile.
        W.EnterCombat()
        V.smartSearch.text = "sunlit"
        W.Insecure(V.smartSearch.scripts.OnTextChanged, V.smartSearch)
        equal(V.smartQuery, "sunlit", client .. ": a search typed in combat is lost to the view")
        equal(#W.combatLayout, 0, client .. ": typing in combat laid the bag out")
        W.LeaveCombat()
        W.Settle()
        equal(Items(), "20", client .. ": the search typed in combat was not built when combat ended")
    end

    ---------------------------------------------------------------- the upgrade marker
    do
        local W = Bags(client, { config = { inventoryView = 1, mergeStacks = false, showUpgradeMarker = true } })
        W.Put(0, 1, 20, 1)  -- cloth helm 300 over worn 250
        W.Put(0, 2, 21, 1)  -- ring 250: beats the lower worn ring (200), not both
        W.Put(0, 3, 22, 1)  -- ring 190: below both
        W.Put(0, 4, 23, 1)  -- plate helm for a cloth wearer
        W.Put(0, 5, 24, 1)  -- a trinket the client says the player cannot use
        W.Put(1, 1, 10, 3)  -- not equipment
        W.worn[1], W.worn[11], W.worn[12] = "item:25", "item:26", "item:27"
        local playerLevel = 70
        C_PlayerInfo.CanUseItem = function(id) return id ~= 24 or playerLevel >= 80 end
        local links = 0
        local read = GetInventoryItemLink
        GetInventoryItemLink = function(...) links = links + 1; return read(...) end
        W.Apply()
        W.OpenBags()
        W.Settle()
        assert(ArrowShown(W, 20), client .. ": a helm of 300 over a worn 250 gets no arrow")
        assert(ArrowShown(W, 21), client .. ": a ring of 250 over the lower worn ring (200) gets no arrow")
        assert(not ArrowShown(W, 22), client .. ": a ring of 190 over worn 280 and 200 got an arrow")
        assert(not ArrowShown(W, 23), client .. ": plate for a cloth wearer got an arrow")
        assert(not ArrowShown(W, 24), client .. ": an item the player cannot use got an arrow")
        assert(not ArrowShown(W, 10), client .. ": a potion got an arrow")
        local _, record = ButtonOf(W.P.InventoryView, 21)
        assert(record.beatsEquipped == true, client .. ": the decision is not on the record")
        -- What is worn is read once per change of equipment, never per repaint.
        local reads = links
        for _ = 1, 3 do
            W.Native(function() W.CF:UpdateItems() end)
            W.Settle()
        end
        equal(links, reads, client .. ": worn equipment was read again without an equipment change")
        -- The second ring is now worn at 250: the ring of 250 no longer beats the lower worn ring.
        W.worn[12] = "item:21"
        W.Fire("PLAYER_EQUIPMENT_CHANGED", 12, true)
        W.Settle()
        assert(links > reads, client .. ": an equipment change did not read the worn equipment")
        assert(not ArrowShown(W, 21), client .. ": a ring equal to the lower worn ring still has an arrow")
        assert(not ArrowShown(W, 22), client .. ": a ring of 190 over worn 280 and 250 got an arrow")
        -- An empty finger slot counts as level 0 for rings.
        W.worn[12] = nil
        W.Fire("PLAYER_EQUIPMENT_CHANGED", 12, false)
        W.Settle()
        assert(ArrowShown(W, 22), client .. ": any ring beats an empty finger")
        -- A level-up can make an item usable: the answers are worked out again.
        assert(not ArrowShown(W, 24), client .. ": the trinket got an arrow before its level")
        playerLevel = 80
        W.Fire("PLAYER_LEVEL_UP", 80)
        W.Settle()
        assert(ArrowShown(W, 24), client .. ": a level-up did not refresh the upgrade arrows")
        -- Switched off: no arrow, no event, no reads.
        W.config.showUpgradeMarker = false
        W.Apply()
        W.Settle()
        assert(not ArrowShown(W, 22) and not ArrowShown(W, 20), client .. ": the arrow shows while the marker is off")
        assert(not W.P.UpgradeMarker.events:IsEventRegistered("PLAYER_EQUIPMENT_CHANGED"),
            client .. ": the marker listens while off")
        local before = links
        W.Fire("PLAYER_EQUIPMENT_CHANGED", 12, false)
        W.Settle()
        equal(links, before, client .. ": worn equipment read while the marker is off")
        GetInventoryItemLink = read
    end
end

---------------------------------------------------------------- the category editor
do
    local W = Bags("Mainline", { config = { inventoryView = 3, customCategories = "1|Mine|10|" } })
    W.Put(0, 1, 10, 5)
    W.Apply()
    W.OpenBags()
    W.Settle()
    W.NS.Registry = { AddListener = function() end, RemoveListener = function() end }
    local Editor = W.P.InventoryEditor
    Editor.Show()
    local function Save(rule)
        Editor.rule.text = rule
        W.Insecure(Editor.save.scripts.OnClick, Editor.save)
        return W.P.InventoryModel.DecodeCategories(W.config.customCategories)[1]
    end
    local saved = Save("   ")
    assert(saved and saved.name == "Mine" and saved.query == nil and saved.rule == nil, "a rule of spaces must be no rule")
    saved = Save("  is:boe  ")
    equal(saved.query, "is:boe", "a rule is trimmed")
    saved = Save("")
    assert(saved.query == nil, "clearing the rule removes it")
    equal(W.config.customCategories, "1|Mine|10", "the saved data of a category without a rule")
end

---------------------------------------------------------------- the bank view
do
    local W = H.New(root, { config = { bankView = 2, hideEmptyCategories = true, bankGroupEquipmentSlots = false,
        showUpgradeMarker = true } })
    W.sizes[0], W.sizes[6], W.sizes[12] = 4, 6, 6
    W.bankTabs[Enum.BankType.Character] = { { ID = 6, name = "Bank tab" } }
    W.bankTabs[Enum.BankType.Account] = { { ID = 12, name = "Warband tab" } }
    W.Define(10, { name = "Bread", class = 0, maxStack = 20, quality = 1, expansion = 9 })
    W.Define(20, { name = "Sunlit Helm", class = 4, subclass = 1, equipLoc = "INVTYPE_HEAD", quality = 4, level = 300,
        bind = 2, expansion = 10 })
    W.Define(21, { name = "Ring C", class = 4, subclass = 0, equipLoc = "INVTYPE_FINGER", quality = 3, level = 250,
        expansion = 9 })
    W.Put(6, 1, 10, 4)
    W.Put(6, 2, 20, 1, { bound = false })
    W.Put(6, 3, 21, 1)
    W.Apply()
    W.OpenBank(Enum.BankType.Character)
    W.Settle()
    local B = W.P.BankInventory
    assert(B.active and B.smartSearch, "the bank view has no smart search")
    assert(B.free and B.free.shown and B.free.text == "3 free", "the bank view's free slot count: " .. tostring(B.free and B.free.text))
    local function Shown()
        local names = {}
        for _, row in ipairs(B.model.groupsByKey.all.displayRows) do
            if row.item.itemID then names[#names + 1] = row.item.name end
        end
        table.sort(names)
        return table.concat(names, ",")
    end
    equal(Shown(), "Bread,Ring C,Sunlit Helm", "an empty search shows every item")
    local function Search(text)
        B.smartSearch.text = text
        W.Insecure(B.smartSearch.scripts.OnTextChanged, B.smartSearch)
        W.Settle()
    end
    Search("helm")
    equal(Shown(), "Sunlit Helm", "the bank view filters by name")
    Search("is:boe")
    equal(Shown(), "Sunlit Helm", "is:boe in the bank")
    Search("level=240-260 | exp:war")
    equal(Shown(), "Ring C,Sunlit Helm", "level ranges and expansion names in the bank")
    Search("quality>=3 !is:boe")
    equal(Shown(), "Ring C", "the earlier grammar in the bank")
    Search("")
    equal(Shown(), "Bread,Ring C,Sunlit Helm", "clearing the search shows everything again")
    -- The count follows the bank.
    W.Put(6, 4, 10, 1)
    W.Fire("BAG_UPDATE", 6)
    W.Settle()
    equal(B.free.text, "2 free", "the bank count follows its tab")
    -- Categories: the bank keeps its own collapsed set.
    W.config.bankView = 4
    W.Apply()
    W.Settle()
    local hit
    for _, label in ipairs(B.labels) do
        if label.shown and label.hit and label.hit.shown and label.hit.key == "equipment" then hit = label.hit end
    end
    assert(hit, "the bank's category headers are not clickable")
    W.Insecure(hit.scripts.OnClick, hit, "LeftButton")
    W.Settle()
    assert(W.moduleState.bankCollapsed and W.moduleState.bankCollapsed.equipment == true
        and not (W.moduleState.collapsed and W.moduleState.collapsed.equipment), "the bank has its own collapsed set")
    assert(B.model.groupsByKey.equipment.collapsed, "the bank's collapsed group")
    -- The upgrade arrow shows in the bank too: a ring of 250 over an empty finger, a potion never.
    W.config.bankView = 2
    W.Apply()
    W.Settle()
    local function BankArrow(itemID)
        for _, button in ipairs(B.buttons) do
            if button.shown and button.record and button.record.itemID == itemID then
                local marker = W.P.InventoryDetails.markers[button]
                return marker ~= nil and marker.shown == true
            end
        end
        error("no bank button shows item " .. itemID)
    end
    assert(BankArrow(21) and BankArrow(20) and not BankArrow(10), "the upgrade arrow in the bank view")
end
print("bags organisation: sort modes, grammar, saved searches, categories, free slots, collapse and upgrade marker passed")
