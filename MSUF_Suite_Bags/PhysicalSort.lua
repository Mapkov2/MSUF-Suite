local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Sort = {}
P.PhysicalSort = Sort
local Finite, Public = S.Finite, S.Public
local job, events
local Step, MoveTimeout
local EVENTS = { "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "CURSOR_CHANGED", "PLAYER_REGEN_DISABLED" }

local function IgnoredSlots(create)
    local root = NS.RootDB
    local guid = S.PublicText(UnitGUID("player"))
    if type(root) ~= "table" or not guid then return end
    local all = root.suitePhysicalBagSort
    if type(all) ~= "table" then
        if not create then return end
        all = {}
        root.suitePhysicalBagSort = all
    end
    local slots = all[guid]
    if type(slots) ~= "table" then
        if not create then return end
        slots = {}
        all[guid] = slots
    end
    return slots
end

local function Size(bag)
    local count = C_Container.GetContainerNumSlots(bag)
    return Finite(count) and count > 0 and count < P.SlotCache.KEY and count or 0
end

local function CleanupDisabled(bag)
    if bag == Enum.BagIndex.Backpack then
        return C_Container.GetBackpackAutosortDisabled()
    end
    return C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags.DisableAutoSort)
end

local function NativeIgnored(bag)
    local disabled = CleanupDisabled(bag)
    return not Public(disabled) or disabled ~= false and not (NS.Client.isForever and disabled == nil)
end

local function Ready()
    return M.active and P.InventoryView.SuiteLayout() and M.frame:IsShown() and not NS.InCombat()
        and not UnitIsDeadOrGhost("player")
        and not StackSplitFrame:IsShown() and not P.AutoSplit.job
        and not SpellCanTargetItem() and not SpellCanTargetItemID()
end

local function EmptyCursor()
    local kind = GetCursorInfo()
    return Public(kind) and kind == nil
end

local function CursorHas(token)
    local kind, id = GetCursorInfo()
    -- The cursor may format the link differently from the bag slot. Source
    -- and destination are checked separately using the complete slot data.
    return Public(kind) and kind == "item" and Finite(id) and id == token.id
end

local function ValidInfo(info)
    return type(info) == "table" and Finite(info.itemID) and Finite(info.stackCount)
        and Public(info.hyperlink) and (type(info.hyperlink) == "string" or info.hyperlink == nil)
        and Public(info.isBound) and (type(info.isBound) == "boolean" or info.isBound == nil)
end

local function Metadata(index, bag, slot, link, config)
    if not link then return end
    local record = index.records[index.buttons[bag * P.SlotCache.KEY + slot]]
    if record and record.loaded and record.link == link then return record end
    local name, _, _, _, _, _, _, _, _, _, price, class, subclass, _, expansion = C_Item.GetItemInfo(link)
    if not Public(name) or type(name) ~= "string" then return end
    local level
    if config.sortMode == NS.BagsSort.ITEM_LEVEL then level = C_Item.GetDetailedItemLevelInfo(link) end
    return { name = name, itemLevel = Finite(level) and level or nil,
        sellPrice = Finite(price) and price or nil, classID = Finite(class) and class or nil,
        subclassID = Finite(subclass) and subclass or nil, expansion = Finite(expansion) and expansion or nil }
end

local function AddSlot(group, bag, slot, family, cleanup)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not Public(info) or info and (not ValidInfo(info) or not Public(info.isLocked) or info.isLocked ~= false) then
        group.skipped = true
        return
    end
    local position = { bag = bag, slot = slot, family = family }
    if info then
        local data = Metadata(P.InventoryView.index, bag, slot, info.hyperlink, M.config)
        if not data then
            if not cleanup then return end
            -- A cold item cache must not turn an occupied slot into a hole.
            local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(info.itemID)
            data = { classID = Finite(class) and class or nil, subclassID = Finite(subclass) and subclass or nil }
        end
        local key = { bag = bag, slot = slot, itemID = info.itemID, name = data.name, itemLevel = data.itemLevel,
            quality = Finite(info.quality) and info.quality or nil, classID = data.classID, subclassID = data.subclassID,
            expansion = data.expansion, sellPrice = data.sellPrice }
        local token = { id = info.itemID, link = info.hyperlink, count = info.stackCount, bound = info.isBound,
            item = key, position = position }
        position.token = token
        group.items[#group.items + 1] = token
    end
    group.slots[#group.slots + 1] = position
end

local function BagFamily(bag)
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    if Finite(family) then return family end
    if not Public(family) or family ~= nil or bag > NUM_BAG_FRAMES then return end
    if bag == Enum.BagIndex.Backpack then return 0 end
    -- Forever permits a missing family. Use the same profession-bag check as
    -- Blizzard before allowing a bag with no family value into the shared group.
    if not IsInventoryItemProfessionBag then return end
    local inventoryID = C_Container.ContainerIDToInventoryID(bag)
    if not Finite(inventoryID) then return end
    local profession = IsInventoryItemProfessionBag("player", inventoryID)
    if Public(profession) and profession == false then return 0 end
end

local function AddBag(groups, byFamily, bag, size, ignored, reverse, cleanup)
    local family = BagFamily(bag)
    if family == nil then return false end
    if cleanup and family ~= 0 then return true end
    -- A reagent bag and a legacy profession bag keep their own inventory.
    local groupKey = family == 0 and bag <= NUM_BAG_FRAMES and -1 or bag
    local group = byFamily[groupKey]
    if not group then
        group = { slots = {}, items = {}, next = 1 }
        groups[#groups + 1], byFamily[groupKey] = group, group
    end
    local first, last, increment = 1, size, 1
    if reverse then first, last, increment = size, 1, -1 end
    local base = bag * P.SlotCache.KEY
    for slot = first, last, increment do
        if not ignored or ignored[base + slot] ~= true then AddSlot(group, bag, slot, family, cleanup) end
    end
    return true
end

local function Reverse()
    local mode = M.config.sortDirection
    if mode ~= NS.BagsSortDirection.BLIZZARD then return mode == NS.BagsSortDirection.FROM_BOTTOM end
    local rightToLeft = C_Container.GetSortBagsRightToLeft()
    if not Public(rightToLeft) or type(rightToLeft) ~= "boolean" then return end
    return rightToLeft
end

local function Plan(cleanup)
    local ignored = IgnoredSlots(false)
    local reverse = false
    if not cleanup then reverse = Reverse() end
    if reverse == nil then return end
    local lastBag = cleanup and NUM_BAG_FRAMES or NUM_TOTAL_BAG_FRAMES
    local first, last, increment = Enum.BagIndex.Backpack, lastBag, 1
    if reverse then first, last, increment = last, first, -1 end
    local groups, byFamily = {}, {}
    local skipped
    for bag = first, last, increment do
        local size = Size(bag)
        if size > 0 and not NativeIgnored(bag) and not AddBag(groups, byFamily, bag, size, ignored, reverse, cleanup) then
            skipped = cleanup
        end
    end
    local order = P.InventoryModel.SortOrder(cleanup and NS.BagsSort.TYPE or M.config.sortMode)
    for i = 1, #groups do
        local group = groups[i]
        local items = group.items
        table.sort(items, order)
        if cleanup then
            group.firstHole, group.lastOccupied = 1, #group.slots
            for rank = 1, #items do items[rank].rank = rank end
            skipped = skipped or group.skipped
        end
    end
    return { groups = groups, groupIndex = 1, profile = NS.DB, cleanup = cleanup, skipped = skipped }
end

local function Exchange(source, target)
    local a, b = source.token, target.token
    source.token, target.token = b, a
    if a then a.position = target end
    if b then b.position = source end
end

local function Equivalent(a, b)
    return a.link ~= nil and a.link == b.link and a.count == b.count and a.bound == b.bound
end

local function Buffer(group, id, limit)
    local occupied
    for i = limit or #group.slots, group.next + 1, -1 do
        local position = group.slots[i]
        if not position.token then return position end
        if not occupied and position.token.id ~= id then occupied = position end
    end
    return occupied
end

-- Close the gaps first using empty destinations. The subsequent ordering
-- pass can swap inside the packed range without relying on occupied slots
-- accepting a drop in order to fill the One Bag.
local function Compact(group)
    local count = #group.items
    while group.firstHole <= count do
        local target = group.slots[group.firstHole]
        if not target.token then
            while group.lastOccupied > count do
                local source = group.slots[group.lastOccupied]
                if source.token then return source, target end
                group.lastOccupied = group.lastOccupied - 1
            end
            return
        end
        group.firstHole = group.firstHole + 1
    end
end

local function NextMove(active)
    local group = active.groups[active.groupIndex]
    while group do
        if active.cleanup then
            local source, target = Compact(group)
            if source then return source, target end
        end
        local target, wanted = group.slots[group.next], group.items[group.next]
        if not wanted then
            active.groupIndex = active.groupIndex + 1
            group = active.groups[active.groupIndex]
        elseif target == wanted.position then
            group.next = group.next + 1
        elseif target.token and target.token.id == wanted.id then
            if Equivalent(target.token, wanted) then
                Exchange(wanted.position, target)
                group.next = group.next + 1
            else
                -- Use an occupied buffer within the packed range for cleanup.
                local buffer = Buffer(group, wanted.id, active.cleanup and #group.items)
                if buffer then return target, buffer end
                if active.cleanup then
                    -- With a full bag, keep same-item stacks in either order.
                    -- Dropping one onto the other could change both stack sizes.
                    local current = target.token
                    group.items[wanted.rank], group.items[current.rank] = current, wanted
                    current.rank, wanted.rank = wanted.rank, current.rank
                    group.next = group.next + 1
                else
                    active.skipped = true
                    group.next = #group.items + 1
                end
            end
        else
            return wanted.position, target
        end
    end
end

local function SlotState(position, expected)
    local info = C_Container.GetContainerItemInfo(position.bag, position.slot)
    if not Public(info) then return false end
    if info == nil then return expected == nil end
    if not ValidInfo(info) or not Public(info.isLocked) or type(info.isLocked) ~= "boolean" then return false end
    if info.isLocked then return nil end
    return expected ~= nil and info.itemID == expected.id and info.stackCount == expected.count
        and info.hyperlink == expected.link and info.isBound == expected.bound
end

local function Timeout()
    Sort.Stop(S.Text("Physical bag sorting stopped."))
end

function Sort.Stop(message)
    if not job then return end
    job = nil
    events:UnregisterAllEvents()
    M.context:Cancel(Timeout)
    M.context:Cancel(MoveTimeout)
    M.context:Cancel(Step)
    if message then S.Print(message) end
end

-- A native pickup and drop can leave the displaced stack on our cursor.
-- ClearCursor returns that stack to the source. Never clear another cursor.
local function Move(source, target, cleanup)
    if not EmptyCursor() or not SlotState(source, source.token) or not SlotState(target, target.token) then return false end
    local item, displaced = source.token, target.token
    C_Container.PickupContainerItem(source.bag, source.slot)
    if not CursorHas(item) then return false end
    if NS.InCombat() then return false end
    C_Container.PickupContainerItem(target.bag, target.slot)
    if EmptyCursor() then return true end
    if NS.InCombat() then return false end
    if displaced and CursorHas(displaced) then
        ClearCursor()
        return EmptyCursor()
    end
    if CursorHas(item) then
        ClearCursor()
        return cleanup and EmptyCursor()
    end
    return false
end

local function BagAvailable(position, slot)
    if NativeIgnored(position.bag) then return false end
    return BagFamily(position.bag) == position.family and Size(position.bag) >= (slot or position.slot)
end

local function BagsAvailable(source, target)
    if source.bag == target.bag then return BagAvailable(source, math.max(source.slot, target.slot)) end
    return BagAvailable(source) and BagAvailable(target)
end

local function Confirm(active)
    local source, target = active.source, active.target
    local atSource, atTarget = SlotState(source, target.token), SlotState(target, source.token)
    if not atSource or not atTarget then return false end
    Exchange(source, target)
    active.source, active.target = nil, nil
    M.context:Cancel(Timeout)
    M.context:Cancel(MoveTimeout)
    return true
end

local function SortStep(active)
    if active.source and not Confirm(active) then return end
    local source, target = NextMove(active)
    if not source then
        local message = active.cleanup and "Physical bag sorting stopped."
            or "Physical bag sorting skipped stacks that cannot be swapped safely."
        Sort.Stop(active.skipped and S.Text(message) or nil)
        return
    end
    if not BagsAvailable(source, target) then
        Timeout()
        return
    end
    active.source, active.target, active.issuing = source, target, true
    local moved = Move(source, target, active.cleanup)
    active.issuing = nil
    if job ~= active then return end
    if not moved then
        Timeout()
        return
    end
    M.context:After(3, active.cleanup and MoveTimeout or Timeout)
    if active.cleanup then active.step:Request() end
end

local function CanSort()
    return Ready() and EmptyCursor() and not P.InventoryView.TransactionOpen()
end

MoveTimeout = function()
    local active = job
    if not active then return end
    if active.profile == NS.DB and M.config.inventoryView == NS.BagsView.ALL and CanSort() then
        if Confirm(active) then
            Step()
            return
        end
        if not active.retried
            and SlotState(active.source, active.source.token) and SlotState(active.target, active.target.token) then
            -- Both slots are unlocked and still match the pre-move state.
            -- Replan once from actual slots after a rejected move.
            local replacement = Plan(true)
            replacement.step, replacement.retried = active.step, true
            job = replacement
            Step()
            return
        end
    end
    Timeout()
end

Step = function()
    local active = job
    if not active then return end
    if active.profile ~= NS.DB or not CanSort() or active.cleanup and M.config.inventoryView ~= NS.BagsView.ALL then
        Timeout()
        return
    end
    SortStep(active)
end

local function Event(_, event, bag, slot)
    local active = job
    if not active then return end
    if event == "PLAYER_REGEN_DISABLED" then
        Timeout()
        return
    end
    if event == "CURSOR_CHANGED" then
        if not active.issuing and not EmptyCursor() then Timeout() end
        return
    end
    if event == "ITEM_LOCK_CHANGED" then
        local source, target = active.source, active.target
        if not source or not Finite(bag) or not Finite(slot) then return end
        if not (bag == source.bag and slot == source.slot or bag == target.bag and slot == target.slot) then return end
    end
    if event == "BAG_UPDATE" then
        local source, target = active.source, active.target
        if not source or not Finite(bag) or bag ~= source.bag and bag ~= target.bag then return end
    end
    active.step:Request()
end

local function Start(cleanup)
    if job then return false end
    if not CanSort() then
        if cleanup then S.Print(S.Text("Physical bag sorting stopped.")) end
        return false
    end
    local active = Plan(cleanup)
    if not active then return false end
    if cleanup and #active.groups == 0 then
        S.Print(S.Text("Physical bag sorting stopped."))
        return false
    end
    if not events then
        events = S.CreateFrame("Frame")
        events:SetScript("OnEvent", Event)
    end
    active.step = M.context:Coalesce(0, Step)
    job = active
    for i = 1, #EVENTS do
        if NS.Client.SupportsEvent(EVENTS[i]) then events:RegisterEvent(EVENTS[i]) end
    end
    if cleanup then
        events:RegisterEvent("BAG_UPDATE")
        if SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then PlaySound(SOUNDKIT.UI_BAG_SORTING_01) end
    end
    Step()
    return true
end

function Sort.Start()
    return Start(false)
end

function Sort.Cleanup()
    if job then return false end
    local equipped, excluded = 0, 0
    local cleanup = NS.Client.isForever and M.config.inventoryView == NS.BagsView.ALL
    local lastBag = cleanup and NUM_BAG_FRAMES or NUM_TOTAL_BAG_FRAMES
    for bag = Enum.BagIndex.Backpack, lastBag do
        if Size(bag) > 0 then
            equipped = equipped + 1
            local disabled = CleanupDisabled(bag)
            if Public(disabled) and disabled == true then excluded = excluded + 1 end
        end
    end
    if equipped > 0 and equipped == excluded then
        S.Print(S.Text("All equipped bags are excluded from cleanup."))
        if cleanup then return false end
    end
    if cleanup then return Start(true) end
    P.SortDirection.Refresh()
    if SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then PlaySound(SOUNDKIT.UI_BAG_SORTING_01) end
    C_Container.SortBags()
    return true
end

local function SlotsMenu(_, root)
    local slots = IgnoredSlots(false)
    local function Selected(key) return slots ~= nil and slots[key] == true end
    local function Toggle(key)
        if job or NS.InCombat() then return end
        slots = slots or IgnoredSlots(true)
        if slots then slots[key] = slots[key] ~= true and true or nil end
    end
    root:CreateTitle(S.Text("Exclude slots from custom sort"))
    for bag = Enum.BagIndex.Backpack, NUM_TOTAL_BAG_FRAMES do
        local count = Size(bag)
        if count > 0 then
            local name = bag == Enum.BagIndex.Backpack and BAG_NAME_BACKPACK or _G["BAG_NAME_BAG_" .. bag]
            if not name then name = C_Container.GetBagName(bag) end
            if Public(name) and type(name) == "string" then
                local branch = root:CreateButton(name)
                local base = bag * P.SlotCache.KEY
                for slot = 1, count do
                    local label = string.format(S.Text("Slot %d"), slot)
                    branch:CreateCheckbox(label, Selected, Toggle, base + slot)
                end
            end
        end
    end
end

function Sort.AddMenu(owner, root)
    local action = root:CreateButton(S.Text("Sort bag slots"), Sort.Start)
    action:SetEnabled(not job and CanSort())
    local exclude = root:CreateButton(S.Text("Exclude slots from custom sort"), function()
        S.ContextMenu(owner, SlotsMenu)
    end)
    exclude:SetEnabled(not job)
end
