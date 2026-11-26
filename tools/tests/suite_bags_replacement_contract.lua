local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local W = H.New(root, { client = arg[2] or "Mainline", config = { inventoryView = 2 } })
W.sizes[0], W.sizes[1], W.sizes[5] = 4, 2, 8
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
local toggles, reagent = 0, E.buttons[Enum.BagIndex.ReagentBag]
ToggleBag = function(bag)
    assert(bag == Enum.BagIndex.ReagentBag)
    toggles = toggles + 1
end
reagent:GetScript("OnClick")(reagent)
assert(toggles == 1, "clicking the equipped reagent bag leaves its contents inaccessible")
W.sizes[5] = 0
reagent:GetScript("OnClick")(reagent)
assert(toggles == 1, "an empty reagent slot must not toggle a window")
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
-- WoW Forever's normal Backpack binding leaves the separate reagent bag closed.
if arg[2] == "Forever" then
    local F = H.New(root, { client = "Forever" })
    local primary, secondary, gamepad = "B", "F12", false
    local overrides, writes = {}, 0
    GetBindingKey = function(action)
        assert(action == "TOGGLEBACKPACK")
        return primary, secondary
    end
    F.S.GamepadUI = function() return gamepad end
    SetOverrideBinding = function(_, priority, key, action)
        assert(not F.combat and not priority, "bag bindings must respect lockdown and other priority overrides")
        writes = writes + 1
        overrides[key] = action
        F.Fire("UPDATE_BINDINGS")
    end
    ClearOverrideBindings = function()
        assert(not F.combat, "bag bindings cleared in combat")
        for key in pairs(overrides) do overrides[key] = nil end
        F.Fire("UPDATE_BINDINGS")
    end
    F.sizes[0], F.sizes[5] = 16, 8
    F.Apply()
    F.OpenBags()
    F.Settle()
    assert(overrides.B == "OPENALLBAGS" and overrides.F12 == "OPENALLBAGS",
        "the usual Backpack keys do not open the reagent bag")
    local before = writes
    F.Fire("BAG_UPDATE", 1)
    F.Fire("BAG_UPDATE", 5)
    assert(writes == before, "ordinary bag changes rewrote the bindings")
    F.EnterCombat()
    primary, secondary = "I", nil
    F.Fire("UPDATE_BINDINGS")
    assert(overrides.B == "OPENALLBAGS" and not overrides.I, "a combat key change ran immediately")
    assert(F.queuedApply, "binding change was not queued for combat end")
    F.LeaveCombat()
    F.queuedApply = nil
    F.Apply()
    F.Settle()
    assert(not overrides.B and not overrides.F12 and overrides.I == "OPENALLBAGS",
        "the new key did not take over after combat")
    F.sizes[5] = 0
    F.Fire("BAG_UPDATE", 5)
    assert(not next(overrides), "Backpack bindings were replaced without an equipped reagent bag")
    F.sizes[5] = 8
    F.Fire("BAG_UPDATE", 5)
    assert(overrides.I == "OPENALLBAGS", "equipping a reagent bag did not restore access")
    gamepad = true
    F.Fire("CVAR_UPDATE", "InputDeviceInterfaceStyle")
    assert(not next(overrides), "Gamepad UI must manage the reagent bag itself")
    gamepad = false
    F.Fire("CVAR_UPDATE", "InputDeviceInterfaceStyle")
    assert(overrides.I == "OPENALLBAGS", "returning to mouse and keyboard left the reagent bag inaccessible")
    F.S.Set("bags", "inventoryView", F.NS.BagsView.BLIZZARD_GRID)
    F.CloseBags()
    F.Native(function() F.Reagent:Hide() end)
    F.EnterCombat()
    primary = "K"
    F.Fire("UPDATE_BINDINGS")
    F.Fire("BAG_UPDATE", 5)
    assert(overrides.I and not overrides.K, "protected binding changed while the bags slept")
    F.LeaveCombat()
    F.Settle()
    assert(overrides.K == "OPENALLBAGS" and not overrides.I, "waking missed a closed-window binding change")
    primary = "I"
    F.Fire("UPDATE_BINDINGS")
    -- Both native bindings open the backpack. Only ToggleAllBags opens the reagent bag too.
    F.OpenBags()
    if overrides.I == "OPENALLBAGS" then F.Native(OpenBag, Enum.BagIndex.ReagentBag) end
    F.Settle()
    assert(F.Reagent:IsShown(), "Blizzard Grid lost the Backpack key that opens the reagent bag")
    assert(not F.P.ReagentInventory.active and F.Reagent:GetAlpha() == 1,
        "Blizzard Grid must keep the reagent bag separate and visible")
    assert(F.S.Set("bags", "enabled", false))
    assert(not next(overrides), "disabling Bags in Blizzard Grid left a binding override behind")
    assert(F.S.Set("bags", "enabled", true))
    assert(overrides.I == "OPENALLBAGS", "enabling Bags directly in Blizzard Grid did not open the reagent bag")
    F.S.Set("bags", "inventoryView", F.NS.BagsView.ALL)
    assert(overrides.I == "OPENALLBAGS", "returning to the Suite view left the reagent bag inaccessible")
    F.S.Set("bags", "enabled", false)
    assert(not next(overrides), "disabling Bags left a binding override behind")
end
print("Bags replacement contract passed")
