local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local W = Harness.New(root, { client = flavor, config = { inventoryView = 1, listView = true,
    hideEmptySlots = true, mergeStacks = false } })
W.sizes[0] = 6
W.Define(10, { name = "Zebra", class = 0, maxStack = 20 })
W.Define(20, { name = "Apple", class = 0, maxStack = 20 })
W.Put(0, 1, 10, 2)
W.Put(0, 2, 20, 4)
W.Apply()
W.OpenBags()
W.Settle()

local view = W.P.InventoryView
local list = assert(view.list, "combined bags never initialized the list")
local first, second
for _, entry in ipairs(list.entries) do
    if entry.row and entry.row.item.itemID then
        if not first then first = entry.row.item else second = entry.row.item; break end
    end
end
assert(first and second and first.itemID == 20 and second.itemID == 10, "item names failed to sort")
assert(first.button == view.index.buttons[2] and second.button == view.index.buttons[1],
    "the list detached items from their native slots")
local columns = W.P.BagListColumns
W.S.Set("bags", "listColumnOrder", "count,name")
W.Settle()
assert(list.fit[1].column.key == "count" and list.fit[2].column.key == "name", "column order ignored")

local function Search(target, query)
    local edit = target.smartSearch
    edit:SetText(query)
    W.Insecure(edit:GetScript("OnTextChanged"), edit)
    W.Settle()
end

local function Expect(target, expected, why)
    local ids = {}
    for _, group in ipairs(target.model.groups) do
        if group.visible then
            for _, row in ipairs(group.rows) do
                if row.item.itemID and not row.alias then ids[#ids + 1] = row.item.itemID end
            end
        end
    end
    table.sort(ids)
    local actual = table.concat(ids, ",")
    assert(actual == expected, why .. ": " .. actual .. " ~= " .. expected)
end

W.Define(30, { name = "Crystal Vial", quality = 1 })
W.Define(40, { name = "Crystallized Quartz", quality = 4 })
W.Define(50, { name = "Kristall Öl" })
W.Define(70, { name = "Crystal Vial", quality = 4, cached = false })
W.Put(0, 3, 30, 2)
W.Put(0, 4, 40, 1)
W.Put(0, 5, 50, 1)
W.Put(0, 6, 70, 1)
W.BagChanged(0)
W.Settle()
for _, query in ipairs({ "cr", "cry", "crys", "cryst", "crysta", "crystal", "yst" }) do
    Search(view, query)
    Expect(view, "30,40", "substring matches after editing " .. query)
end
Search(view, "crystall")
Expect(view, "40", "a narrowed fragment excludes its parent-only match")
Search(view, "crystal")
Expect(view, "30,40", "backspacing restores a match")
Search(view, 'name:"kristall Öl"')
Expect(view, "50", "localized name")
Search(view, 'name:"Crystal Vial')
Expect(view, "", "an unclosed quote shows no match")
Search(view, "name:quartz | id:20")
Expect(view, "20,40", "OR with a numeric branch")
Search(view, "!name:crystal count>2")
Expect(view, "20", "negated name and numeric filter")

Search(view, 'name:"Crystal Vial"')
Expect(view, "30", "pending metadata has only an ID")
W.data[70].cached = true
W.Fire("GET_ITEM_INFO_RECEIVED", 70, true)
W.Settle()
Expect(view, "30,70", "arrival of item details updates the current query")
W.Put(0, 3, 40, 1)
W.Put(0, 4, 30, 2)
W.BagChanged(0)
W.Settle()
Expect(view, "30,70", "items can move while the query stays the same")
assert(view.model.groupsByKey.all.rows[1].item.slot == 4, "search retained a result at its old slot")
W.Item(0, 4).filtered = true
W.Fire("INVENTORY_SEARCH_UPDATE")
W.Settle()
Expect(view, "70", "native filter applies to current indexed matches")
W.Item(0, 4).filtered = nil
W.Fire("INVENTORY_SEARCH_UPDATE")
W.Settle()
Search(view, 'name:"Crystal Vial" count>=2')
Expect(view, "30", "a name match still needs to satisfy the count rule")
W.Put(0, 6, 70, 3)
W.BagChanged(0)
W.Settle()
Expect(view, "30,70", "counts refresh while indexed names stay the same")
Search(view, "")


W.S.InventoryArchive = {
    active = true,
    RecordedAt = function() return GetServerTime() end,
    RecordedCharacters = function() return {} end,
    VisitRecorded = function(_, _, _, visit) visit(10, 7); return GetServerTime() end,
}
local offline = W.P.BagOffline
assert(offline.Enter("Player-Alt", "bank", "Alt"))
W.Settle()
local records = offline.Items()
assert(#records == 1 and records[1].offline and records[1].count == 7 and not records[1].button,
    "the recorded bank acquired a native item button")
Search(view, "apple")
Expect(view, "", "a live name match must not leak into a recorded inventory")
Search(view, "zebra")
Expect(view, "10", "recorded names can be searched")

offline.Leave()
W.Settle()
assert(not offline.Active() and view.index.buttons[1] == second.button, "returning to bags changed native slots")


-- Count the slots that reach the full matcher through the edit box.
local rules = W.NS.InventoryRules
local matches, checks = rules.Matches, 0
rules.Matches = function(rule, item)
    checks = checks + 1
    return matches(rule, item)
end
Search(view, 'name:"Crystal Vial" quality>=3')
Expect(view, "70", "additional filters on indexed positions")
rules.Matches = matches
assert(checks <= 2, "search ran full predicates on slots outside the name index (" .. checks .. " checks)")

local tree = W.P.QueryTree
local rule = tree.Group("and")
local names = tree.Group("or")
names.children = { tree.Term("name", ":", "Apple"), tree.Term("name", ":", "Zebra") }
rule.children = { tree.Term("count", ">", "2"), names }
local expression = assert(tree.Text(rule))
local compiled = assert(W.NS.InventoryRules.Compile(expression))
assert(W.NS.InventoryRules.Matches(compiled, { name = "Apple", search = "apple", count = 4 }))
assert(not W.NS.InventoryRules.Matches(compiled, { name = "Zebra", search = "zebra", count = 2 }),
    "a nested OR dropped its shared count constraint")
W.sizes[6], W.sizes[7] = 2, 2
W.bankTabs[Enum.BankType.Character] = { { ID = 6, name = "First tab" }, { ID = 7, name = "Second tab" } }
W.Put(6, 1, 30)
W.Put(7, 1, 40)
assert(W.S.Set("bags", "bankView", W.NS.BagsBankView.CHARACTER))
W.OpenBank(Enum.BankType.Character)
W.Settle()
local bank = W.P.BankInventory
Search(bank, "vial")
Expect(bank, "30", "combined bank uses the same search")
local function SelectTab(key)
    for _, button in ipairs(bank.categories) do
        if button:IsShown() and button.key == key then
            W.Insecure(button:GetScript("OnClick"), button)
            W.Settle()
            return
        end
    end
    error("bank tab is missing: " .. key)
end
SelectTab("tab:6")
Expect(bank, "30", "searches the selected bank tab")
SelectTab("tab:7")
Expect(bank, "", "a same-sized bank tab cannot reuse another tab's name")
SelectTab("tab:6")
Expect(bank, "30", "returning to the first bank tab restores its match")

print("Bags list, native slot identity, indexed search, bank scopes, column order and nested rules passed")
