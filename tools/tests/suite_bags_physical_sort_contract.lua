local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function World()
    local W = H.New(root, { client = arg[2] or "Mainline" })
    local protectedBags = {}
    C_Container.GetBackpackAutosortDisabled = function() return protectedBags[0] == true end
    C_Container.GetBagSlotFlag = function(bag, flag)
        assert(flag == Enum.BagSlotFlags.DisableAutoSort)
        return protectedBags[bag] == true
    end
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

local MERCHANT_MESSAGE = "Sorting stopped until the merchant window is closed."

for _, view in ipairs({ "ALL", "BY_BAG" }) do
    local W = World()
    W.sizes[0] = 3
    W.Put(0, 2, 101)
    W.Put(0, 3, 102)
    Open(W)
    W.S.Set("bags", "inventoryView", W.NS.BagsView[view])
    W.Settle()
    local idle = Subscribers(W)
    MerchantFrame:Show()
    W.Fire("MERCHANT_SHOW")
    W.Settle()
    assert(not W.P.InventoryActions.Cleanup(), "merchant cleanup must refuse before moving items")
    assert(W.errors[#W.errors] == MERCHANT_MESSAGE, "merchant cleanup needs an actionable explanation")
    assert(not W.P.PhysicalSort.Start(), "custom sorting must also refuse at a merchant")
    assert(W.errors[#W.errors] == MERCHANT_MESSAGE and #W.errors == 2)
    assert(#W.calls.pickups == 0 and not W.calls.cleanup and Subscribers(W) == idle and not W.cursor,
        "merchant refusal must not touch the native sorter, items, cursor or job listeners")
    MerchantFrame:Hide()
    W.Fire("MERCHANT_CLOSED")
    W.Settle()
    assert(#W.calls.pickups == 0 and not W.calls.cleanup, "closing the merchant must not sort automatically")
    assert(W.P.InventoryActions.Cleanup(), "cleanup must become available again after closing the merchant")
    for _ = 1, 8 do Update(W) end
    assert(#W.errors == 2 and not W.cursor and Subscribers(W) == idle)
end

for _, cleanup in ipairs({ false, true }) do
    if not cleanup or arg[2] == "Forever" then
        for _, trigger in ipairs({ "shown-event", "early-event", "bag-update", "timeout" }) do
            local W = World()
            W.sizes[0] = 4
            W.Put(0, 1, 101)
            W.Put(0, 2, 103)
            W.Put(0, 3, 104)
            W.Put(0, 4, 102)
            Open(W)
            local idle = Subscribers(W)
            local start = cleanup and W.P.PhysicalSort.Cleanup or W.P.PhysicalSort.Start
            assert(start() and #W.calls.pickups == 2 and not W.cursor)
            if trigger ~= "early-event" then MerchantFrame:Show() end
            if trigger == "bag-update" then
                Update(W)
            elseif trigger == "timeout" then
                W.Advance(3)
            else
                W.Fire("MERCHANT_SHOW")
            end
            assert(Subscribers(W) == idle and #W.errors == 1 and W.errors[1] == MERCHANT_MESSAGE,
                "opening a merchant must stop an active sort with merchant feedback: " .. trigger)
            W.Advance(4)
            Update(W)
            assert(#W.calls.pickups == 2 and #W.errors == 1 and not W.cursor,
                "stopped sorting must cancel pending moves and report only once")
            MerchantFrame:Hide()
            W.Fire("MERCHANT_CLOSED")
            W.Settle()
            assert(start(), "a stopped sort must permit a fresh manual restart")
            for _ = 1, 8 do Update(W) end
            assert(Subscribers(W) == idle and not W.cursor and #W.errors == 1)
        end
    end
end

if arg[2] == "Forever" then
    local W = World()
    W.sizes[0], W.sizes[1], W.sizes[2], W.sizes[3], W.sizes[4], W.sizes[5] = 2, 2, 2, 2, 2, 2
    W.families[2] = 64
    W.protectedBags[3] = true
    W.Put(0, 2, 103)
    W.Put(1, 2, 104)
    W.Put(2, 1, 105)
    W.Put(3, 2, 105)
    W.Put(4, 2, 102)
    W.Put(5, 2, 101, 3)
    local pickup = C_Container.PickupContainerItem
    local rejecting = true
    C_Container.PickupContainerItem = function(bag, slot)
        if rejecting and W.cursor then
            -- One dropped request, rolled back by the client's ClearCursor.
            rejecting = false
            W.calls.pickups[#W.calls.pickups + 1] = { bag, slot }
            return
        end
        pickup(bag, slot)
    end
    Open(W)
    local idle = Subscribers(W)
    assert(W.P.InventoryActions.Cleanup() and #W.calls.pickups == 2)
    assert(not W.Item(0, 1) and not W.cursor, "a rejected drop returns its item to the source")
    Has(W, 4, 2, 102)
    W.Advance(3)
    Has(W, 0, 1, 102)
    Update(W)
    Has(W, 1, 1, 104)
    assert(not W.Item(1, 2) and not W.Item(4, 2), "cleanup packs general bags before attempting swaps")
    W.Fire("BAG_UPDATE", 1)
    W.Settle()
    for _ = 1, 4 do Update(W) end
    Has(W, 0, 1, 102)
    Has(W, 0, 2, 103)
    Has(W, 1, 1, 104)
    Has(W, 2, 1, 105)
    Has(W, 3, 2, 105)
    Has(W, 5, 2, 101, 3)
    assert(Subscribers(W) == idle and not W.calls.cleanup and not W.cursor and #W.errors == 0,
        "cleanup leaves the reagent window and protected bags alone")
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
    W.S.Set("bags", "inventoryView", W.NS.BagsView.BY_BAG)
    W.Settle()
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
    function node:CreateTitle(label) self.title = label end
    function node:SetEnabled(enabled) self.enabled = enabled end
    function node:SetScrollMode() end
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

do
    local W = World()
    Open(W)
    MerchantFrame:Show()
    local menu = Menu()
    W.P.PhysicalSort.AddMenu(W.P.InventoryView.cleanup, menu)
    assert(not menu["Sort bag slots"].enabled and menu.title == MERCHANT_MESSAGE,
        "the disabled custom sort menu must explain the merchant restriction")
end

do
    local W = World()
    W.sizes[0] = 4
    W.Put(0, 1, 101)
    W.Put(0, 2, 102)
    W.Put(0, 3, 104)
    Open(W)
    C_Item.GetItemNameByID = function(id) return id == 101 and "Bark" or id == 102 and "Antler" or "Dust" end
    local menu
    W.S.ContextMenu = function(owner, generator)
        menu = Menu()
        generator(owner, menu)
    end
    W.P.InventoryActions.SortMenu(W.P.InventoryView.cleanup)
    menu["Reserve bag slots for items"].action()
    local first = assert(menu.Backpack["Slot 1 · Bark"])
    local second = assert(menu.Backpack["Slot 2 · Antler"])
    first.toggle(first.key)
    second.toggle(second.key)
    assert(first.selected(first.key) and second.selected(second.key))
    W.Put(0, 1, 102)
    W.Put(0, 2, 101)
    Update(W)
    local idle = Subscribers(W)
    assert(W.P.PhysicalSort.Start())
    for _ = 1, 8 do Update(W) end
    Has(W, 0, 1, 101)
    Has(W, 0, 2, 102)
    Has(W, 0, 3, 104)
    assert(not W.cursor and Subscribers(W) == idle and #W.errors == 0)
end

print("Suite physical bag sorting contract passed")
