local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local W = H.New(root, { client = arg[2] or "Mainline" })
W.sizes[0], W.sizes[1] = 4, 2
W.Define(101, { name = "Sword", equipLoc = "INVTYPE_WEAPON" })
W.Define(102, { name = "Potion", class = 0 })
W.Put(0, 1, 101, 1)
W.Put(0, 2, 102, 5)
W.Apply()
W.OpenBags()
W.Settle()
local V, E = W.P.InventoryView, W.P.EquippedBags
assert(V.cleanup and not V.shuffleButton, "replace random order with explicit native cleanup")
assert(E and V.equipped, "equipped bags must be reachable independently of DataTexts")
assert(#E.buttons == 5, "four bag slots and the reagent bag slot")
local sorts, pickups, drops = 0, {}, {}
C_Container.SortBags = function() sorts = sorts + 1 end
PickupBagFromSlot = function(id) pickups[#pickups + 1] = id end
PutItemInBag = function(id) drops[#drops + 1] = id end
GetInventoryItemTexture = function(_, id) return 1000 + id end
C_Container.GetContainerNumFreeSlots = function() return 2 end
SetItemButtonTexture = function(button, texture) button.texture = texture end
assert(W.P.InventoryActions.Cleanup() and sorts == 1, "cleanup invokes native sorting once")
W.Settle()
W.cursor = { id = 101, count = 1 }
assert(not W.P.InventoryActions.Cleanup() and sorts == 1, "cleanup preserves held cursor items")
W.cursor = nil
E.Toggle()
W.Settle()
assert(E.frame:IsShown(), "equipped-bag drawer opens")
for bag, button in ipairs(E.buttons) do
    assert(button.inventoryID == C_Container.ContainerIDToInventoryID(bag), "native inventory slot mapping")
    button:GetScript("OnDragStart")(button)
    assert(pickups[#pickups] == button.inventoryID, "drag picks the equipped bag")
    button:GetScript("OnReceiveDrag")(button)
    assert(drops[#drops] == button.inventoryID, "drop equips into the selected slot")
    W.cursor = { id = 101, count = 1 }
    button:GetScript("OnClick")(button)
    assert(drops[#drops] == button.inventoryID, "click equips the held bag")
    W.cursor = nil
end
local count = #pickups + #drops
W.fighting = true
W.Fire("PLAYER_REGEN_DISABLED")
for _, button in ipairs(E.buttons) do
    button:GetScript("OnDragStart")(button)
    button:GetScript("OnReceiveDrag")(button)
    button:GetScript("OnClick")(button)
end
assert(#pickups + #drops == count, "combat edge refuses bag equipment actions")
assert(not W.P.InventoryActions.Cleanup() and sorts == 1, "combat edge refuses cleanup")
W.fighting = false
W.Fire("PLAYER_REGEN_ENABLED")
W.Settle()
W.S.Set("bags", "enabled", false)
W.Settle()
assert(not E.frame:IsShown() and not V.active, "disable closes every owned surface")
W.S.Set("bags", "enabled", true)
W.Settle()
assert(V.active and V.shuffle == nil, "reenable has no stale random order")
assert(#W.errors == 0, "replacement reports no client-model errors")
print("Bags replacement contract passed")
