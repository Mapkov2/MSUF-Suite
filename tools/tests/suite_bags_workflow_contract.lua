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
