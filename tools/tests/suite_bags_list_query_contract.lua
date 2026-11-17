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
offline.Leave()
W.Settle()
assert(not offline.Active() and view.index.buttons[1] == second.button, "returning to bags changed native slots")

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
print("Bags list, native slot identity, recorded bank, column order and nested rules passed")
