local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local Harness = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function Click(W, button, mouseButton)
    W.Insecure(assert(button:GetScript("OnClick")), button, mouseButton or "LeftButton")
end

local function Search(edit, text)
    edit:SetText(text)
    edit:GetScript("OnTextChanged")(edit)
end

local function World(config)
    local W = Harness.New(root, { client = flavor, config = config })
    W.sizes[0], W.sizes[6], W.sizes[12] = 8, 6, 6
    W.bankTabs[Enum.BankType.Character] = { { ID = 6, name = "Bank tab" } }
    W.bankTabs[Enum.BankType.Account] = { { ID = 12, name = "Warband tab" } }
    W.Define(10, { name = "Potion", class = 0, maxStack = 20 })
    W.Define(40, { name = "Trinket", class = 2, equipLoc = "INVTYPE_WEAPON" })
    W.Put(0, 1, 10, 4)
    W.Put(0, 2, 10, 6)
    W.Put(0, 3, 40, 1)
    W.Put(6, 1, 10, 3)
    W.Put(12, 1, 40, 1)
    W.Apply()
    W.OpenBags()
    W.Settle()
    return W
end

do
    local W = World({ inventoryView = 1 })
    local handle = assert(W.M.windows[W.CF].dragHandle)
    local portrait = W.CF.PortraitButton
    Click(W, handle)
    assert(not portrait:IsMenuOpen(), "a left click on the Backpack heading opened its menu")
    Click(W, handle, "RightButton")
    assert(portrait:IsMenuOpen(), "right click lost the native Backpack sorting options")
    Click(W, handle, "RightButton")
    assert(not portrait:IsMenuOpen(), "second right click did not close the menu")
    assert(handle:GetScript("OnDragStart"), "the heading lost its left drag handler")
end

-- A native relayout also moves the slots the Suite has hidden during a search.
-- Once the query clears, every slot must return to the Suite grid.
do
    local W = World({ inventoryView = 1, hideEmptySlots = false })
    local V = W.P.InventoryView
    local positions = {}
    for _, button in W.CF:EnumerateValidItems() do
        assert(button:IsShown(), "the unfiltered slot is missing")
        positions[button] = { button:GetPoint() }
    end

    Search(V.smartSearch, "Potion")
    W.Settle()
    local hidden = 0
    for button in pairs(positions) do
        if not button:IsShown() then hidden = hidden + 1 end
    end
    assert(hidden == 6, "the search must hide the six non-matching slots")
    W.Native(function()
        W.CF:UpdateFrameSize()
        W.CF:UpdateItemLayout()
        UpdateContainerFrameAnchors()
    end)
    W.Settle()
    Search(V.smartSearch, "")
    W.Settle()

    for button, expected in pairs(positions) do
        local point, frame, relative, x, y = button:GetPoint()
        assert(button:IsShown(), "the cleared search left a slot hidden")
        assert(point == expected[1] and frame == expected[2] and relative == expected[3]
            and x == expected[4] and y == expected[5], "the cleared search left a slot at its native position")
    end
    assert(#W.errors == 0 and #W.taint == 0, "the search relayout raised an error or caused taint")
end

do
    local W = World({ inventoryView = 1, hideEmptySlots = false, mergeStacks = false })
    W.sizes[1], W.sizes[2] = 4, 3
    W.Put(1, 2, 40, 1)
    W.Put(2, 3, 10, 5)
    if flavor == "Forever" then
        local recent = W.P.InventoryIndex.Recent()
        recent.items[10] = GetServerTime()
        recent.order[1] = 10
        W.P.InventoryView.State().pinned[40] = true
        W.S.Set("bags", "sortMode", W.NS.BagsSort.QUALITY)
        W.S.Set("bags", "mergeStacks", true)
        W.S.Set("bags", "sortDirection", W.NS.BagsSortDirection.FROM_TOP)
    end
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    if flavor == "Forever" then
        local rows = V.model.groupsByKey.all.displayRows
        assert(#rows == 15 and rows[1].item.button == V.index.buttons[1] and rows[2].item.button == V.index.buttons[2],
            "Forever One Bag keeps every native slot in place even for pinned, recent or identical items")
        assert(not V.model.groupsByKey.pinned and not V.model.groupsByKey.recent,
            "pinned and recent items must stay in their slots in One Bag")
    end
    local last = V.index.buttons[2002]
    local _, _, _, x, y = last:GetPoint()
    local function UseSlot(button)
        W.Native(button:GetScript("OnClick"), button, "LeftButton")
        W.Settle()
    end
    UseSlot(V.index.buttons[1002])
    UseSlot(last)
    local rows = V.model.groupsByKey.all.displayRows
    local _, _, _, dropX, dropY = last:GetPoint()
    assert(W.Item(2, 2).id == 40 and rows[14].item.button == last and dropX == x and dropY == y,
        "the last native slot must stay under the drop position after a manual move")
    local pickups = #W.calls.pickups
    if flavor == "Forever" then
        -- Model displaced stacks returning to the original slot on ClearCursor.
        local pickup = C_Container.PickupContainerItem
        C_Container.PickupContainerItem = function(bag, slot)
            local held = W.cursor
            pickup(bag, slot)
            if held and W.cursor then W.cursor.from = held.from end
        end
        ClearCursor = function()
            local held = assert(W.cursor)
            W.Put(held.from[1], held.from[2], held.id, held.count)
            W.cursor = nil
            W.BagChanged(held.from[1])
        end
        -- Cursor links can differ from slot links, and the second bag's item
        -- may have arrived before the client loaded its metadata.
        local cursorInfo = GetCursorInfo
        GetCursorInfo = function()
            local kind, id = cursorInfo()
            if kind then return kind, id, "cursor:" .. id end
        end
        W.Define(10, { name = "Potion", class = 0, maxStack = 20, cached = false })
        W.S.Set("bags", "sortDirection", W.NS.BagsSortDirection.BLIZZARD)
        W.sortRightToLeft = true
        C_Container.SortBags = function() error("Blizzard cleanup is broken in Forever") end
    end
    Click(W, V.cleanup)
    W.Settle()
    local occupied
    if flavor == "Forever" then
        assert(#W.calls.pickups > pickups and not W.cursor, "One Bag cleanup must move items using the Suite sorter")
        assert(W.Item(0, 4).id == 40 and W.Item(0, 5).id == 40, "equipment is grouped after consumables")
        occupied = 5
        local potionCount = 0
        for slot = 1, 3 do
            assert(W.Item(0, slot).id == 10, "potions belong together at the start of the grid")
            potionCount = potionCount + W.Item(0, slot).count
        end
        assert(potionCount == 15, "cleanup preserves every item")
    else
        assert(W.calls.cleanup == 1 and #W.calls.pickups == pickups and not W.cursor,
            "Mainline Cleanup must call Blizzard once without picking up items")
        assert(W.Item(2, 2).id == 40, "the view waits for actual native slot updates")
        occupied = 3
        W.Put(0, 1, 40, 1)
        W.Put(0, 2, 40, 1)
        W.Put(0, 3, 10, 15)
        W.items[2][2], W.items[2][3] = nil, nil
        W.Fire("BAG_UPDATE", 0)
        W.Fire("BAG_UPDATE", 2)
        W.Native(function() W.CF:UpdateItems() end)
        W.Settle()
        assert(V.model.groupsByKey.all.displayRows[3].count == 15)
    end
    rows = V.model.groupsByKey.all.displayRows
    assert(#rows == 15)
    for i = 1, #rows do
        assert((rows[i].item.itemID ~= nil) == (i <= occupied), "free slots must follow the occupied slots")
    end
    pickups = #W.calls.pickups
    if flavor == "Forever" then
        Click(W, V.cleanup)
        W.Settle()
        assert(#W.calls.pickups == pickups, "already sorted slots require no moves")
    end
    UseSlot(V.index.buttons[flavor == "Forever" and 4 or 1])
    UseSlot(last)
    W.Advance(10)
    W.BagChanged(2)
    W.Settle()
    assert(W.Item(2, 2).id == 40 and V.model.groupsByKey.all.displayRows[14].item.button == last,
        "a later manual move stays where it was placed")
    Click(W, V.tabs[W.NS.BagsView.BY_BAG])
    W.Settle()
    local individual = V.model.groupsByKey["bag:2"].displayRows
    if flavor == "Forever" then
        assert(V.model.groupsByKey.pinned and V.model.groupsByKey.recent, "the other views retain item grouping")
        assert(W.Item(2, 2).id == 40, "grouping in another view does not move items")
    else
        assert(not individual[1].item.itemID and individual[2].item.itemID == 40, "By bag retains physical slot order")
    end
    assert(W.calls.cleanup == (flavor ~= "Forever" and 1 or nil) and not W.cursor and #W.errors == 0 and #W.taint == 0,
        "bag updates and timers must not reissue cleanup")
end

local function Menus(W)
    local rows = {}
    local menu = {}
    function menu:CreateTitle() end
    function menu:CreateDivider() end
    function menu:CreateButton(label, action)
        rows[label] = action
        return self
    end
    function menu:SetEnabled() end
    W.P.BagFilterMenu.Show = function(owner, generator)
        for label in pairs(rows) do rows[label] = nil end
        generator(owner, menu)
    end
    return rows
end

do
    local W = World({ inventoryView = 3, bankView = 4, mergeStacks = true })
    local V = W.P.InventoryView
    local menus = Menus(W)
    local moved, archiveScope, sortOpened
    W.S.instances.bankTransfer = {
        CanBatch = function() return BankFrame:IsShown(), BankFrame:GetActiveBankType() end,
        Batch = function(_, items, direction) moved = { items = items, direction = direction } end,
    }
    W.S.InventoryArchive = { active = true, Browse = function(_, scope) archiveScope = scope end }
    W.P.InventoryActions.SortMenu = function() sortOpened = true end

    Click(W, V.filterButton)
    assert(not menus["Deposit matching stacks"], "closed bank exposed a transfer action")
    menus["Inventory archive"]()
    menus["Sort bag slots"]()
    assert(archiveScope == "bags" and sortOpened, "bag actions were not available in the search menu")

    W.OpenBank(Enum.BankType.Character)
    W.Settle()
    Click(W, V.filterButton)
    assert(not menus["Deposit matching stacks"], "an unfiltered inventory would transfer by default")
    Search(V.smartSearch, "Potion")
    Click(W, V.filterButton)
    assert(not menus["Deposit matching stacks"], "stale search results were offered for transfer")
    W.Settle()
    Click(W, V.filterButton)
    menus["Deposit matching stacks"]()
    assert(moved.direction == "deposit" and #moved.items == 2, "expected both physical matching stacks")
    assert(moved.items[1].slot ~= moved.items[2].slot and moved.items[2].itemID == 10, "unexpected deposit candidates")

    Search(V.smartSearch, "")
    W.Settle()
    for _, group in ipairs(V.model.groups) do
        if group.key ~= "all" and group.rows[1] and group.rows[1].item.itemID == 10 then V.selected = group.key break end
    end
    V.Request()
    W.Settle()
    Click(W, V.filterButton)
    menus["Deposit matching stacks"]()
    assert(moved.direction == "deposit" and #moved.items == 2, "selected category included a different item's stack")

    local B = assert(W.P.BankInventory)
    assert(B.active and B.frame:IsShown(), "organized bank did not open")
    if flavor == "Forever" then
        for _, button in ipairs(B.buttons) do
            if button:IsShown() and button.record.bag == 12 then W.P.BankActions.Enter(button) end
        end
    end
    W.EnterCombat()
    assert(not B.active and not B.frame:IsShown(), "organized bank covered the native bank in combat")
    W.LeaveCombat()
    W.Settle()
    assert(B.active and B.frame:IsShown(), "organized bank did not recover after combat")
    Search(B.smartSearch, "Potion")
    W.Settle()
    Click(W, B.filterButton)
    menus["Withdraw matching stacks"]()
    assert(moved.direction == "withdraw" and #moved.items == 1 and moved.items[1].bag == 6, "bank search chose the wrong stacks")
    menus["Inventory archive"]()
    assert(archiveScope == "bank", "bank launcher opened the wrong archive scope")
    W.CloseBank()
    W.Settle()
    assert(not B.active and not B.watching, "closed bank kept its update subscriptions")
    assert(#W.errors == 0 and #W.taint == 0, "modeled native bank failure")
end

print("bag workflows: native title input, filtered transfers, archive navigation and bank lifecycle passed (" .. flavor .. ")")
