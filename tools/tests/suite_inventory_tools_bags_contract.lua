local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local W = H.New(root, { config = { inventoryView = 3, hideEmptyCategories = true, groupEquipmentSets = false,
    showEquipmentSetNames = false, customCategories = "1|Set rule||SET:raid" } })
W.sizes[0] = 4
W.Define(12, { name = "Raid helm", class = 4, equipLoc = "INVTYPE_HEAD", quality = 4 })
W.Define(13, { name = "Potion", class = 0, quality = 1 })
W.Put(0, 1, 12, 1)
W.Put(0, 2, 13, 3)
W.equipmentSets[1] = { name = "Raid", locations = { 100 } }
W.locations[100] = { isBags = true, bag = 0, slot = 1 }
W.Apply()
W.OpenBags()
W.Settle()
local V = W.P.InventoryView
assert(V.model.groupsByKey['custom:Set rule'], 'uppercase SET rule needs equipment metadata')
assert(#V.model.groupsByKey['custom:Set rule'].rows == 1, 'rule category contains matched physical item')
local categories = W.P.InventoryModel.DecodeCategories(W.config.customCategories)
assert(categories[1].query == 'SET:raid', 'rule persisted')
categories[1].items[13] = true
assert(W.P.InventoryModel.DecodeCategories(W.P.InventoryModel.EncodeCategories(categories))[1].query == 'SET:raid',
    'manual ID edits preserve automatic rules')
V.smartSearch:SetText('SET:raid')
V.smartSearch.scripts.OnTextChanged(V.smartSearch)
W.Settle()
assert(V.model.rowCount == 1, 'smart query visible result')
V.smartSearch:SetText('!is:bound')
V.smartSearch.scripts.OnTextChanged(V.smartSearch)
W.Settle()
assert(V.model.rowCount <= 2, 'negated queries cannot match empty slots')
W.EnterCombat()
V.smartSearch:SetText('quality=0')
V.smartSearch.scripts.OnTextChanged(V.smartSearch)
assert(#W.combatLayout == 0, 'combat query edits never mutate the active layout')
assert(V.smartQuery == 'quality=0', 'the view must keep what the box holds, to build it when combat ends')
W.LeaveCombat()
W.Settle()
assert(V.model.rowCount == 0, 'the query typed in combat is built when combat ends')
print('inventory smart search: rule categories, uppercase fields, manual ID coexistence and combat boundaries passed')
