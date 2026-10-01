-- The inventory view against the client model of suite_bags_harness.lua,
-- with the FULL Bags TOC loaded: physical slot order, incremental reads.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")

local function Cell(W, button)
    local _, relative, _, x, y = button:GetPoint(1)
    assert(relative == W.CF, "a Suite cell must anchor to the bag window")
    return x, y
end

local function Bags(options)
    local W = H.New(root, options)
    W.sizes[0], W.sizes[1], W.sizes[2], W.sizes[3], W.sizes[4] = 6, 4, 0, 0, 2
    W.Define(10, { name = "Potion", class = 0, maxStack = 20 })
    W.Define(11, { name = "Hearthstone", class = 15 })
    W.Define(12, { name = "Cloth", class = 7, maxStack = 200 })
    W.Put(0, 1, 11, 1)
    W.Put(0, 2, 10, 5)
    W.Put(1, 3, 12, 40)
    W.Put(4, 2, 10, 3)
    W.Apply()
    return W
end

---------------------------------------------------------------- physical order
do
    local W = Bags({ config = { inventoryView = 1, inventoryColumns = 8, hideEmptySlots = false, mergeStacks = false } })
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    assert(V.active, "the inventory view did not take over the combined bag")
    -- Blizzard's Items list starts with bag 4's last slot.
    assert(W.CF.Items[1]:GetBagID() == 4 and W.CF.Items[1]:GetID() == 2, "client model must fill Items from bag 4")
    local items = V.index.items
    assert(#items == 12, "every slot of bags 0-4 is indexed")
    local previous = -1
    for i = 1, #items do
        local key = items[i].bag * 1000 + items[i].slot
        assert(key > previous, "slots must be listed in physical order: bag 0 slot 1 first")
        previous = key
    end
    local function ButtonFor(bag, slot)
        for _, button in W.CF:EnumerateValidItems() do
            if button:GetBagID() == bag and button:GetID() == slot then return button end
        end
    end
    local x1, y1 = Cell(W, ButtonFor(0, 1))
    local x2, y2 = Cell(W, ButtonFor(0, 2))
    local xLast, yLast = Cell(W, ButtonFor(4, 2))
    assert(y1 == y2 and x2 > x1, "backpack slot 2 must follow slot 1 on the first row")
    assert(yLast < y1, "bag 4 must come after the backpack")
    assert(x1 == 12, "the first cell of All items is the backpack's first slot at the top left")

    -- An unchanged bag reads nothing again; a changed bag reads its own slots.
    local reads = W.calls.info
    W.Native(function() W.CF:UpdateItems() end)
    reads = W.calls.info - reads
    W.Settle()
    local view = W.calls.info
    W.Native(function() W.CF:UpdateItems() end)
    W.Settle()
    assert(W.calls.info == view + reads, "an unchanged native refresh must cost only Blizzard's own reads")
    W.Put(1, 1, 12, 7)
    view = W.calls.info
    W.Fire("BAG_UPDATE", 1)
    W.Native(function() W.CF:UpdateItems() end)
    W.Settle()
    assert(W.calls.info == view + reads + W.sizes[1], "a BAG_UPDATE must read only that bag again")
    assert(ButtonFor(1, 1).shown and V.index.items[7].itemID == 12, "the changed slot shows its new item")
end

---------------------------------------------------------------- combat
-- A max-level inventory: backpack 20 slots, four 36-slot bags (164 slots).
local function FullBags(options)
    local W = H.New(root, options)
    W.sizes[0] = 20
    for bag = 1, 4 do W.sizes[bag] = 36 end
    W.Define(10, { name = "Potion", class = 0, maxStack = 20 })
    W.Define(11, { name = "Hearthstone", class = 15 })
    W.Put(0, 3, 10, 1)
    W.Put(2, 7, 10, 4)
    W.Put(4, 36, 11, 1)
    W.Apply()
    return W
end

local function ButtonFor(W, bag, slot)
    for _, button in W.CF:EnumerateValidItems() do
        if button:GetBagID() == bag and button:GetID() == slot then return button end
    end
end

local function Inside(W, button)
    local l, b, w, h = W.Rect(W.CF)
    local bl, bb, bw, bh = W.Rect(button)
    return bl >= l - 0.01 and bb >= b - 0.01 and bl + bw <= l + w + 0.01 and bb + bh <= b + h + 0.01
end

local function Footer(W)
    return W.P.BagFinance.button
end

do
    -- Open before the pull: every slot must stay reachable through the fight.
    local W = FullBags({ config = { mergeStacks = true } })
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    assert(V.layout == "suite" and V.maxScroll > 0, "the default view pages a full inventory")
    assert(not ButtonFor(W, 4, 36).shown, "the hearthstone in bag 4 starts on a later page")
    assert(not ButtonFor(W, 2, 7).shown, "the second potion stack starts merged into the first")
    local merged = ButtonFor(W, 0, 3).Count
    assert(merged.text == "5" and merged.shown,
        "a merged total must show although the shown physical stack holds one item")
    assert(Footer(W) and Footer(W).shown, "the Suite footer line shows in the Suite grid")
    W.EnterCombat()
    assert(V.layout == "combat" and not V.chrome.shown,
        "combat must start with every slot laid out and no Suite controls")
    -- The currency and Gold history line stays, in its own row below the slots.
    local line = Footer(W)
    assert(line.shown and Inside(W, line), "the currency and Gold history line left the bag in combat")
    local _, lineBottom, _, lineHeight = W.Rect(line)
    local seen = {}
    for _, button in W.CF:EnumerateValidItems() do
        assert(button.shown, "a slot is out of reach in combat: bag " .. button:GetBagID() .. " slot " .. button:GetID())
        assert(Inside(W, button), "a slot lies outside the bag window in combat")
        local _, slotBottom = W.Rect(button)
        assert(slotBottom >= lineBottom + lineHeight - 0.01, "the currency line covers a slot in combat")
        local x, y = Cell(W, button)
        local key = x .. ":" .. y
        assert(not seen[key], "two slots share one cell in combat")
        seen[key] = true
    end
    W.Insecure(line.scripts.OnClick, line, "LeftButton")
    assert(W.P.BagFinance.window and W.P.BagFinance.window.shown, "the Gold history does not open in combat")
    W.Insecure(W.P.BagFinance.window.Hide, W.P.BagFinance.window)
    local _, bottom, _, height = W.Rect(W.CF)
    assert(bottom + height <= W.screenHeight + 0.01, "the combat layout runs off the top of the screen")
    assert(not ButtonFor(W, 0, 3).Count.shown, "a physical stack of one shows no merged total in combat")
    assert(ButtonFor(W, 2, 7).Count.text == "4" and ButtonFor(W, 2, 7).Count.shown,
        "each potion stack must show its own count in combat")
    -- The mouse wheel and the hidden page buttons change nothing in combat.
    local scroll = V.scroll
    W.Insecure(W.CF.scripts.OnMouseWheel, W.CF, -1)
    W.Insecure(V.next.scripts.OnClick, V.next, "LeftButton")
    assert(V.scroll == scroll and #W.combatLayout == 0, "scrolling moved Blizzard's bag in combat")
    -- Looting in combat: Blizzard refreshes its buttons; the Suite moves nothing.
    W.Put(3, 1, 10, 2)
    W.BagChanged(3)
    W.Settle()
    assert(ButtonFor(W, 3, 1).shown and #W.combatLayout == 0,
        "the Suite changed the bag layout during combat: " .. table.concat(W.combatLayout, ", "))
    W.LeaveCombat()
    W.Settle()
    assert(V.layout == "suite" and V.chrome.shown and Footer(W).shown and not ButtonFor(W, 4, 36).shown,
        "the Suite grid must return after combat")
    assert(#W.combatLayout == 0, "layout writes happened during combat lockdown")
    -- Hidden empty slots come back for the fight as well.
    assert(W.S.Set("bags", "hideEmptySlots", true))
    W.Settle()
    assert(not ButtonFor(W, 1, 1).shown, "empty slots start hidden")
    W.EnterCombat()
    for _, button in W.CF:EnumerateValidItems() do
        assert(button.shown, "an empty slot stayed hidden in combat")
    end
    W.LeaveCombat()
    W.Settle()
    assert(not ButtonFor(W, 1, 1).shown and #W.combatLayout == 0, "hidden empty slots return after combat")
end

do
    -- A bag opened in combat shows Blizzard's grid; Suite controls stay away.
    local W = FullBags()
    W.EnterCombat()
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    assert(not V.chrome or not V.chrome.shown, "Suite controls cover Blizzard's grid in a bag opened in combat")
    assert(not Footer(W) or not Footer(W).shown, "the Suite footer line covers Blizzard's bottom row in combat")
    for _, button in W.CF:EnumerateValidItems() do
        local point, relative = button:GetPoint(1)
        assert(button.shown and point == "BOTTOMRIGHT" and relative == W.CF,
            "a bag opened in combat must keep Blizzard's own grid")
    end
    assert(#W.combatLayout == 0, "the Suite moved Blizzard's bag in combat: " .. table.concat(W.combatLayout, ", "))
    W.LeaveCombat()
    W.Settle()
    assert(V.layout == "suite" and V.chrome.shown, "the Suite grid must take over after combat")
end

do
    -- Reopened in combat after a Suite session: no frame of Suite controls
    -- over Blizzard's grid, not even before the Suite's next pass.
    local W = FullBags()
    W.OpenBags()
    W.Settle()
    assert(Footer(W).shown, "the footer line shows in the Suite grid")
    W.CloseBags()
    W.EnterCombat()
    W.OpenBags()
    assert(not Footer(W).shown and not W.P.InventoryView.chrome.shown,
        "Suite controls showed over Blizzard's grid when the bag reopened in combat")
    W.Settle()
    assert(not Footer(W).shown and #W.combatLayout == 0, "the reopened bag must keep Blizzard's grid in combat")
    W.LeaveCombat()
    W.Settle()
    assert(Footer(W).shown, "the footer line returns after combat")
end

---------------------------------------------------------------- geometry
do
    -- 16 visible rows on a 768-unit screen: the window must fit, and the
    -- footer stands above tracked currency rows.
    local W = FullBags({ config = { inventoryRows = 16, autoSizeWindow = false } })
    W.OpenBags()
    W.Settle()
    local _, bottom, _, height = W.Rect(W.CF)
    assert(bottom + height <= W.screenHeight + 0.01, "the bag window runs off the top of the screen")
    local V = W.P.InventoryView
    W.CF.MoneyFrame:ClearAllPoints()
    W.CF.MoneyFrame:SetPoint("BOTTOMLEFT", W.CF, "BOTTOMLEFT", 8, 40)
    W.Native(function() W.CF:UpdateFrameSize() end)
    W.Settle()
    local _, previousBottom = W.Rect(V.previous)
    local _, moneyBottom, _, moneyHeight = W.Rect(W.CF.MoneyFrame)
    assert(previousBottom >= moneyBottom + moneyHeight, "the Suite footer overlaps Blizzard's money row")
    local lowest = math.huge
    for _, button in W.CF:EnumerateValidItems() do
        if button.shown then
            local _, b = W.Rect(button)
            lowest = math.min(lowest, b)
        end
    end
    local _, footerBottom, _, footerHeight = W.Rect(Footer(W))
    assert(lowest >= footerBottom + footerHeight - 0.01, "item rows overlap the Suite footer")
end

---------------------------------------------------------------- tooltips
do
    local W = H.New(root, { config = { mergeStacks = true, showEquipmentSetNames = true, showUpgradeTrack = true } })
    W.sizes[0] = 4
    W.Define(10, { name = "Potion", class = 0, maxStack = 20 })
    W.Define(20, { name = "Helm", class = 4, equipLoc = "INVTYPE_HEAD", level = 650 })
    W.Put(0, 1, 10, 2)
    W.Put(0, 2, 10, 3)
    W.Put(0, 3, 20, 1)
    W.equipmentSets[5] = { name = "Tank", locations = { 1003 } }
    W.locations[1003] = { isBags = true, bag = 0, slot = 3 }
    W.upgrades["item:20"] = { currentLevel = 3, maxLevel = 8, trackString = "Hero" }
    W.Apply()
    W.OpenBags()
    W.Settle()
    local tip = W.GameTooltip
    W.Hover(ButtonFor(W, 0, 1))
    assert(tip:Has("Combined: 5 items in 2 stacks"), "the merged stack tooltip lacks its total")
    tip:Advance(0.5)
    assert(tip:Has("Combined: 5 items in 2 stacks") and tip:Has("This slot contains 2"),
        "the merged stack lines vanished with Blizzard's 0.2 s tooltip refresh")
    W.Hover(ButtonFor(W, 0, 3))
    tip:Advance(0.5)
    assert(tip:Has("Tank") and tip:Has("Hero 3/8"), "set and upgrade lines vanished with the tooltip refresh")
    assert(not tip:Has("Combined"), "a single stack must not show merged lines")
    -- Item tooltips of anything else stay as Blizzard built them.
    W.Native(function()
        tip:SetOwner(UIParent)
        tip:SetBagItem(0, 1)
    end)
    assert(#tip.lines == 1, "Suite lines were added to a tooltip the Suite does not own")
end

---------------------------------------------------------------- re-read records
-- A BAG_UPDATE re-reads the whole bag. An item that stayed in its slot keeps
-- what was derived from its link (upgrade track) and its shuffle key; only
-- a changed item reads again.
do
    local W = H.New(root, { config = { showUpgradeTrack = true } })
    W.sizes[0] = 4
    W.Define(10, { name = "Potion", class = 0, maxStack = 20 })
    W.Define(20, { name = "Helm", class = 4, equipLoc = "INVTYPE_HEAD", level = 650 })
    W.Define(21, { name = "Chest", class = 4, equipLoc = "INVTYPE_CHEST", level = 660 })
    W.Put(0, 1, 20, 1)
    W.Put(0, 2, 10, 2)
    W.Put(0, 3, 10, 3)
    W.upgrades["item:20"] = { currentLevel = 3, maxLevel = 8, trackString = "Hero" }
    W.upgrades["item:21"] = { currentLevel = 1, maxLevel = 6, trackString = "Champion" }
    W.Apply()
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    local upgradeReads, itemInfo = 0, W.calls.itemInfo
    local read = C_Item.GetItemUpgradeInfo
    C_Item.GetItemUpgradeInfo = function(link) upgradeReads = upgradeReads + 1; return read(link) end
    local function Record(slot)
        for _, item in ipairs(V.index.items) do if item.bag == 0 and item.slot == slot then return item end end
    end
    assert(Record(1).upgrade == "3/8" and Record(1).loaded, "the helm's upgrade track was not read")
    V.shuffle, V.shufflePending = true, true
    W.BagChanged(0)
    W.Settle()
    local helm, potion = Record(1), Record(2)
    local helmKey, potionKey = helm.shuffle, potion.shuffle
    assert(helmKey and potionKey, "shuffling gave the items no shuffle key")
    upgradeReads, itemInfo = 0, W.calls.itemInfo
    -- A record that already holds its metadata never copies it again.
    local cached = V.index.metadata["item:20"]
    V.index.metadata["item:20"] = setmetatable({ name = "Copied again" }, { __index = cached })
    W.Put(0, 3, 10, 5)
    for _ = 1, 3 do
        W.BagChanged(0)
        W.Settle()
    end
    assert(Record(1) == helm and helm.upgrade == "3/8" and helm.upgradeTrack == "Hero",
        "re-reading an unchanged slot dropped its upgrade track")
    assert(upgradeReads == 0, "BAG_UPDATE re-read the upgrade track of unchanged items: " .. upgradeReads)
    assert(W.calls.itemInfo == itemInfo and helm.name == "Helm",
        "BAG_UPDATE looked up or copied the item metadata of unchanged items again")
    V.index.metadata["item:20"] = cached
    assert(helm.shuffle == helmKey and potion.shuffle == potionKey,
        "BAG_UPDATE re-rolled the shuffle keys of unchanged items")
    assert(Record(3).count == 5 and Record(3).loaded, "a changed stack lost its new count or its metadata")
    -- A different item in the same slot is a new record.
    W.Put(0, 1, 21, 1)
    W.BagChanged(0)
    W.Settle()
    assert(Record(1).upgrade == "1/6" and Record(1).upgradeTrack == "Champion" and upgradeReads == 1,
        "a new item in the slot kept the previous item's upgrade track")
    assert(Record(1).name == "Chest" and Record(1).shuffle ~= helmKey, "a new item kept the previous item's record")
    C_Item.GetItemUpgradeInfo = read
end

---------------------------------------------------------------- stack split owner
do
    local W = FullBags()
    W.Put(0, 1, 10, 5)
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    local owner = ButtonFor(W, 0, 1)
    assert(owner.shown, "the potion stack starts on the first page")
    W.ShiftClick(owner)
    assert(StackSplitFrame:IsShown() and #W.taint == 0, "Blizzard's split window did not open natively")
    W.Insecure(V.next.scripts.OnClick, V.next, "LeftButton")
    W.Settle()
    assert(owner.shown and StackSplitFrame:IsShown() and #W.taint == 0,
        "a page change hid the split owner from Suite code: " .. table.concat(W.taint, ", "))
    W.SplitOkay()
    W.Settle()
    assert(#W.taint == 0, "closing the split window natively tainted it: " .. table.concat(W.taint, ", "))
    assert(not owner.shown and V.scroll > 0, "the page change must run once the split window closed")
end

---------------------------------------------------------------- search
do
    local W = FullBags()
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    assert(not ButtonFor(W, 4, 36).shown, "the hearthstone starts on a later page")
    W.Search(function(item) return item.id == 11 end)
    W.Settle()
    assert(ButtonFor(W, 4, 36).shown and V.scroll == 0, "a search match on a later page must be shown")
    for _, button in W.CF:EnumerateValidItems() do
        if button ~= ButtonFor(W, 4, 36) then assert(not button.shown, "a non-matching slot stayed in the grid") end
    end
    W.Search(nil)
    W.Settle()
    assert(not ButtonFor(W, 4, 36).shown and ButtonFor(W, 1, 1).shown, "clearing the search restores the grid")
end

---------------------------------------------------------------- guild bank
do
    local W = FullBags({ config = { mergeStacks = true } })
    W.OpenBags()
    W.Settle()
    assert(not ButtonFor(W, 2, 7).shown, "the second potion stack starts merged")
    W.OpenGuildBank()
    W.Settle()
    assert(ButtonFor(W, 2, 7).shown, "the guild bank must expose every physical stack for deposits")
    W.CloseGuildBank()
    W.Settle()
    assert(not ButtonFor(W, 2, 7).shown, "stacks merge again after the guild bank closed")
end

---------------------------------------------------------------- custom category limit
do
    local ids = {}
    for id = 1, 500 do ids[#ids + 1] = 1000 + id end
    local W = FullBags({ config = { inventoryView = 3, hideEmptyCategories = false,
        customCategories = "1|Full|" .. table.concat(ids, ",") } })
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    local target
    for _, button in ipairs(V.buttons) do
        if button.categoryKey == "custom:Full" then target = button end
    end
    assert(target, "the full custom category has no sidebar button")
    W.cursor = { id = 50, link = "item:50" }
    W.Insecure(target.scripts.OnReceiveDrag, target)
    local stored = W.P.InventoryModel.DecodeCategories(W.config.customCategories)[1]
    assert(not stored.items[50] and stored.items[1500] and W.P.InventoryModel.CountItems(stored) == 500,
        "a 501st item must be refused without dropping a stored one")
    assert(W.cursor and W.GameTooltip:Has("500 items"), "the refused drop must say why and keep the cursor item")
end

---------------------------------------------------------------- disable in combat
do
    local W = FullBags()
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    local count = ButtonFor(W, 0, 3).Count
    local nativeFont = V.nativeCountFonts[count] and V.nativeCountFonts[count][1]
    assert(nativeFont, "the Suite did not take over the count font")
    W.EnterCombat()
    -- A module error stops the module in combat (Suite.lua Stop).
    W.M.active = false
    W.M:Disable()
    assert(count.font[1] == nativeFont and W.CF.wheel == V.nativeMouseWheel,
        "count fonts and the mouse wheel must return at once")
    assert(#W.combatLayout == 0, "the restore moved Blizzard's bag in combat: " .. table.concat(W.combatLayout, ", "))
    W.LeaveCombat()
    W.Settle()
    for _, button in W.CF:EnumerateValidItems() do
        local point, relative = button:GetPoint(1)
        assert(button.shown and point == "BOTTOMRIGHT" and relative == W.CF,
            "Blizzard's grid must come back when combat ends")
    end
end

---------------------------------------------------------------- WoW Forever
do
    -- Forever loads the same Mainline TOC; the Retail bank files stand aside.
    local W = FullBags({ client = "Forever" })
    W.OpenBags()
    W.Settle()
    assert(W.NS.Client.isForever and W.P.BankInventory == nil and W.P.BankActions == nil,
        "the Retail bank view must not load on WoW Forever")
    assert(W.P.InventoryView.layout == "suite" and ButtonFor(W, 0, 3).shown, "the bag view must run on WoW Forever")
    W.EnterCombat()
    assert(W.P.InventoryView.layout == "combat" and ButtonFor(W, 4, 36).shown, "every slot must be reachable on Forever")
    W.LeaveCombat()
end

---------------------------------------------------------------- Blizzard grid
do
    local W = FullBags({ config = { inventoryView = 4 } })
    W.Define(20, { name = "Helm", class = 4, equipLoc = "INVTYPE_HEAD", level = 650 })
    W.Put(0, 5, 20, 1)
    W.OpenBags()
    W.Settle()
    local V = W.P.InventoryView
    local function Native()
        for _, button in W.CF:EnumerateValidItems() do
            local point, relative = button:GetPoint(1)
            if not (button.shown and point == "BOTTOMRIGHT" and relative == W.CF) then return false end
        end
        return true
    end
    assert(not V.active and not (V.chrome and V.chrome.shown) and Native(),
        "Blizzard grid must keep Blizzard's own layout without Suite controls")
    assert(not Footer(W) or not Footer(W).shown, "the Suite footer line covers Blizzard's grid")
    local helm = W.M.overlays[ButtonFor(W, 0, 5)]
    assert(helm and helm.label and helm.label.text == "650" and helm.label.shown and W.M.windows[W.CF].shell.shown,
        "item levels and the Suite window surface must stay in Blizzard grid")
    assert(W.S.Set("bags", "inventoryView", 1))
    W.Settle()
    assert(V.active and V.layout == "suite" and not Native(), "a Suite view must take over again")
    assert(W.S.Set("bags", "inventoryView", 4))
    W.Settle()
    assert(not V.active and Native() and not V.chrome.shown, "Blizzard grid must give the layout back")
end

---------------------------------------------------------------- category editor
-- "Edit categories" opens the category editor with no argument: the click's
-- button must never reach Editor.Show as its pinned flag.
do
    local W = H.New(root, { config = { inventoryView = 3 } })
    W.sizes[0] = 4
    local show, arguments = W.P.InventoryEditor.Show, nil
    W.P.InventoryEditor.Show = function(...)
        arguments = select("#", ...)
        return show(...)
    end
    W.Apply()
    W.OpenBags()
    W.Settle()
    local manage = assert(W.P.InventoryView.manage, "the inventory view has no category editor button")
    manage:Click("LeftButton")
    assert(arguments == 0 and W.P.InventoryEditor.frame.shown and not W.P.InventoryEditor.editPins,
        "Edit categories passed its click arguments to the editor")
end

print("bag view client model: order, reads, combat, geometry, tooltips, split owner, search, guild bank,"
    .. " category limit, combat disable, Blizzard grid and the category editor passed")
