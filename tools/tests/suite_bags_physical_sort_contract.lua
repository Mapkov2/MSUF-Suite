local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function World()
    local W = H.New(root, { client = arg[2] or "Mainline" })
    local protectedBags = {}
    Enum.BagSlotFlags = { DisableAutoSort = 1 }
    NUM_TOTAL_BAG_FRAMES = Constants.InventoryConstants.NumBagSlots + Constants.InventoryConstants.NumReagentBagSlots
    C_Container.GetBackpackAutosortDisabled = function() return protectedBags[0] == true end
    C_Container.GetBagSlotFlag = function(bag, flag)
        assert(flag == Enum.BagSlotFlags.DisableAutoSort)
        return protectedBags[bag] == true
    end
    SpellCanTargetItem = function() return false end
    SpellCanTargetItemID = function() return false end
    W.S.Print = function(message) W.errors[#W.errors + 1] = message end
    W.families = {}
    W.protectedBags = protectedBags
    W.Define(101, { name = "Bark", quality = 1, maxStack = 20 })
    W.Define(102, { name = "Antler", quality = 4 })
    W.Define(103, { name = "Cloth", quality = 3 })
    W.Define(104, { name = "Dust", quality = 2 })
    W.Define(105, { name = "Essence", quality = 5 })

    -- Treat ClearCursor as the client's automatic return to the pickup slot.
    -- Model same-ID drops as stacking so that a dangerous swap fails the test.
    C_Container.PickupContainerItem = function(bag, slot)
        local item, cursor = W.Item(bag, slot), W.cursor
        assert(not item or not item.locked, "attempt to pick up a locked slot")
        W.calls.pickups[#W.calls.pickups + 1] = { bag, slot }
        if cursor then
            assert(not item or item.id ~= cursor.id, "attempt to merge two physical stacks during a swap")
            W.items[bag] = W.items[bag] or {}
            W.items[bag][slot] = cursor.item
            W.cursor = item and { item = item, id = item.id, link = item.link, from = cursor.from } or nil
        elseif item then
            W.items[bag][slot] = nil
            W.cursor = { item = item, id = item.id, link = item.link, from = { bag, slot } }
        end
        W.Fire("CURSOR_CHANGED")
    end
    ClearCursor = function()
        local cursor = assert(W.cursor, "clear without a cursor item")
        local bag, slot = cursor.from[1], cursor.from[2]
        assert(not W.Item(bag, slot), "pickup origin must be empty before return")
        W.items[bag][slot], W.cursor = cursor.item, nil
        W.Fire("CURSOR_CHANGED")
    end
    return W
end

local function Open(W, mode)
    W.Apply()
    W.S.Set("bags", "sortMode", mode or W.P.NS.BagsSort.QUALITY)
    W.OpenBags()
    W.Settle()
end

local function Has(W, bag, slot, id, count)
    local item = W.Item(bag, slot)
    assert(item and item.id == id and (not count or count == item.count), ("unexpected slot %d:%d"):format(bag, slot))
end

local function Update(W)
    W.Fire("BAG_UPDATE_DELAYED")
    W.Settle()
end

local function Subscribers(W)
    return #(W.events.CURSOR_CHANGED or {})
end

do
    local W = World()
    W.sizes[0], W.sizes[1], W.sizes[2], W.sizes[5] = 4, 3, 2, 2
    W.families[5] = 64
    W.protectedBags[2] = true
    local NS = W.P.NS
    NS.RootDB.suitePhysicalBagSort = { [UnitGUID("player")] = { [2] = true } }
    W.Put(0, 1, 101, 10)
    W.Put(0, 2, 104, 1)
    W.Put(0, 4, 103, 1)
    W.Put(1, 2, 102, 1)
    W.Put(2, 2, 105, 1)
    W.Put(5, 2, 104, 1)
    Open(W)
    local idle = Subscribers(W)
    assert(W.P.PhysicalSort.Start())
    Has(W, 0, 1, 102)
    assert(#W.calls.pickups == 2 and Subscribers(W) == idle + 1 and W.cursor == nil)
    W.Settle()
    assert(#W.calls.pickups == 2, "no next move before an authoritative event")
    for _ = 1, 8 do Update(W) end
    Has(W, 0, 1, 102)
    Has(W, 0, 2, 104)
    Has(W, 0, 3, 103)
    Has(W, 0, 4, 101, 10)
    Has(W, 2, 2, 105)
    Has(W, 5, 1, 104)
    assert(W.Item(1, 2) == nil and W.Item(5, 2) == nil and Subscribers(W) == idle and W.cursor == nil)
end

do
    local W = World()
    W.sizes[0] = 3
    W.Put(0, 1, 101, 3)
    W.Put(0, 2, 101, 12)
    Open(W, W.P.NS.BagsSort.STACK)
    assert(W.P.PhysicalSort.Start())
    for _ = 1, 8 do Update(W) end
    Has(W, 0, 1, 101, 12)
    Has(W, 0, 2, 101, 3)
    assert(W.Item(0, 3) == nil and W.cursor == nil)
end

do
    local W = World()
    W.sizes[0] = 2
    W.Put(0, 1, 101, 3)
    W.Put(0, 2, 101, 12)
    Open(W, W.P.NS.BagsSort.STACK)
    local idle = Subscribers(W)
    assert(W.P.PhysicalSort.Start())
    assert(#W.calls.pickups == 0 and Subscribers(W) == idle and #W.errors == 1,
        "a full group of matching stacks must not merge or leave listeners running")
end

do
    local W = World()
    W.sizes[0], W.sizes[1] = 3, 2
    W.Put(0, 1, 101)
    W.Put(0, 2, 104)
    local nextItem = W.Put(1, 1, 103)
    W.Put(1, 2, 105)
    Open(W)
    local idle = Subscribers(W)
    assert(W.P.PhysicalSort.Start() and #W.calls.pickups == 2)
    W.Item(0, 1).locked = true
    Update(W)
    assert(#W.calls.pickups == 2 and Subscribers(W) == idle + 1, "the in-flight pair still awaits its unlock")
    W.Item(0, 1).locked = false
    nextItem.locked = true
    W.Fire("ITEM_LOCK_CHANGED", 0, 1)
    W.Settle()
    assert(#W.calls.pickups == 2 and Subscribers(W) == idle, "the next pair cannot pick up a newly locked stack")
    Has(W, 1, 1, 103)
    Has(W, 0, 2, 104)
    assert(W.cursor == nil and #W.errors == 1)
end

do
    local W = World()
    W.sizes[0] = 3
    W.Put(0, 1, 101)
    W.Put(0, 2, 103)
    W.Put(0, 3, 102)
    Open(W)
    local idle = Subscribers(W)
    assert(W.P.PhysicalSort.Start() and #W.calls.pickups == 2)
    W.EnterCombat()
    assert(Subscribers(W) == idle, "combat entry immediately releases the temporary listener")
    Update(W)
    assert(#W.calls.pickups == 2 and Subscribers(W) == idle and not W.P.PhysicalSort.Start())
    W.LeaveCombat()
    W.Settle()
    W.cursor = { id = 999, link = "item:999" }
    assert(not W.P.PhysicalSort.Start() and W.cursor.id == 999)
    W.cursor = nil
    assert(W.P.InventoryActions.Cleanup() and W.calls.cleanup == 1, "native cleanup is still available")
end

local function Menu()
    local node = {}
    function node:CreateButton(label, action)
        local child = Menu()
        child.action = action
        self[label] = child
        return child
    end
    function node:CreateCheckbox(label, selected, toggle, key)
        self[label] = { selected = selected, toggle = toggle, key = key }
    end
    function node:CreateTitle() end
    function node:SetEnabled(enabled) self.enabled = enabled end
    return node
end

do
    local W = World()
    W.sizes[0] = 2
    W.Put(0, 1, 101)
    W.Put(0, 2, 102)
    Open(W)
    local menu
    W.S.ContextMenu = function(owner, generator)
        menu = Menu()
        generator(owner, menu)
    end
    W.P.InventoryActions.SortMenu(W.P.InventoryView.cleanup)
    assert(menu["Clean up bags"] and menu["Sort bag slots"].enabled, "both sort actions are reachable")
    menu["Exclude slots from custom sort"].action()
    local slot = assert(menu.Backpack["Slot 1"])
    assert(not slot.selected(slot.key))
    slot.toggle(slot.key)
    assert(slot.selected(slot.key))
    assert(W.P.PhysicalSort.Start() and #W.calls.pickups == 0, "the selected slot is excluded from custom sorting")
    slot.toggle(slot.key)
    assert(not slot.selected(slot.key))
    assert(W.P.PhysicalSort.Start() and #W.calls.pickups == 2, "the cleared exclusion takes effect")
end

print("Suite physical bag sorting contract passed")
