local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Sort = {}
P.PhysicalSort = Sort
local Finite, Public = S.Finite, S.Public
local job, events
local Step
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

local function NativeIgnored(bag)
    local disabled
    if bag == Enum.BagIndex.Backpack then
        disabled = C_Container.GetBackpackAutosortDisabled()
    else
        disabled = C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags.DisableAutoSort)
    end
    return not Public(disabled) or disabled ~= false
end

local function Ready()
    return M.active and M.frame:IsShown() and not NS.InCombat()
        and not StackSplitFrame:IsShown() and not P.AutoSplit.job
        and not P.InventoryView.TransactionOpen()
        and not SpellCanTargetItem() and not SpellCanTargetItemID()
end

local function EmptyCursor()
    local kind = GetCursorInfo()
    return Public(kind) and kind == nil
end

local function CursorHas(token)
    local kind, id, link = GetCursorInfo()
    return Public(kind) and kind == "item" and Finite(id) and id == token.id
        and Public(link) and link == token.link
end

local function ValidInfo(info)
    return type(info) == "table" and Finite(info.itemID) and Finite(info.stackCount)
        and Public(info.hyperlink) and type(info.hyperlink) == "string"
        and Public(info.isBound) and type(info.isBound) == "boolean"
end

local function Metadata(index, bag, slot, link, config)
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

local function AddSlot(group, bag, slot, family, config, index)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not Public(info) or info and (not ValidInfo(info) or not Public(info.isLocked) or info.isLocked ~= false) then return end
    local position = { bag = bag, slot = slot, family = family }
    if info then
        local data = Metadata(index, bag, slot, info.hyperlink, config)
        if not data then return end
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

local function AddBag(groups, byFamily, bag, size, ignored, reverse)
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    if not Finite(family) then return end
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
        if not ignored or ignored[base + slot] ~= true then
            AddSlot(group, bag, slot, family, M.config, P.InventoryView.index)
        end
    end
end

local function Plan()
    local ignored = IgnoredSlots(false)
    local reverse = C_Container.GetSortBagsRightToLeft()
    if not Public(reverse) or type(reverse) ~= "boolean" then return end
    local first, last, increment = Enum.BagIndex.Backpack, NUM_TOTAL_BAG_FRAMES, 1
    if reverse then first, last, increment = last, first, -1 end
    local groups, byFamily = {}, {}
    for bag = first, last, increment do
        local size = Size(bag)
        if size > 0 and not NativeIgnored(bag) then AddBag(groups, byFamily, bag, size, ignored, reverse) end
    end
    local order = P.InventoryModel.SortOrder(M.config.sortMode)
    for i = 1, #groups do table.sort(groups[i].items, order) end
    return { groups = groups, groupIndex = 1, profile = NS.DB }
end

local function Exchange(source, target)
    local a, b = source.token, target.token
    source.token, target.token = b, a
    if a then a.position = target end
    if b then b.position = source end
end

local function Equivalent(a, b)
    return a.link == b.link and a.count == b.count and a.bound == b.bound
end

local function Buffer(group, id)
    local occupied
    for i = #group.slots, group.next + 1, -1 do
        local position = group.slots[i]
        if not position.token then return position end
        if not occupied and position.token.id ~= id then occupied = position end
    end
    return occupied
end

local function NextMove(active)
    local group = active.groups[active.groupIndex]
    while group do
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
                local buffer = Buffer(group, wanted.id)
                if buffer then return target, buffer end
                -- Pickup onto the same item ID may merge the stacks.
                active.skipped = true
                group.next = #group.items + 1
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
    if not ValidInfo(info) or not Public(info.isLocked) then return false end
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
    M.context:Cancel(Step)
    if message then S.Print(message) end
end

-- A native pickup and drop can leave the displaced stack on our cursor.
-- ClearCursor returns that stack to the source. Never clear another cursor.
local function Move(source, target)
    if not SlotState(source, source.token) or not SlotState(target, target.token) then return false end
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
    if CursorHas(item) then ClearCursor() end
    return false
end

local function BagAvailable(position, slot)
    if NativeIgnored(position.bag) then return false end
    local _, family = C_Container.GetContainerNumFreeSlots(position.bag)
    return Finite(family) and family == position.family and Size(position.bag) >= (slot or position.slot)
end

local function BagsAvailable(source, target)
    if source.bag == target.bag then return BagAvailable(source, math.max(source.slot, target.slot)) end
    return BagAvailable(source) and BagAvailable(target)
end

local function Confirm(active)
    local source, target = active.source, active.target
    local atSource, atTarget = SlotState(source, target.token), SlotState(target, source.token)
    if atSource == nil or atTarget == nil then return nil end
    if not atSource or not atTarget then
        -- The first lock event can precede the authoritative bag update.
        return nil
    end
    Exchange(source, target)
    active.source, active.target = nil, nil
    M.context:Cancel(Timeout)
    return true
end

Step = function()
    local active = job
    if not active then return end
    if active.profile ~= NS.DB or not Ready() or not EmptyCursor() then
        Timeout()
        return
    end
    if active.source and not Confirm(active) then return end
    local source, target = NextMove(active)
    if not source then
        Sort.Stop(active.skipped and S.Text("Physical bag sorting skipped stacks that cannot be swapped safely.") or nil)
        return
    end
    if not BagsAvailable(source, target) then
        Timeout()
        return
    end
    active.source, active.target, active.issuing = source, target, true
    local moved = Move(source, target)
    active.issuing = nil
    if job ~= active then return end
    if not moved then
        Timeout()
        return
    end
    M.context:After(3, Timeout)
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
    active.step:Request()
end

function Sort.Start()
    if job or not Ready() or not EmptyCursor() then return false end
    local active = Plan()
    if not active then return false end
    if not events then
        events = S.CreateFrame("Frame")
        events:SetScript("OnEvent", Event)
    end
    active.step = M.context:Coalesce(0, Step)
    job = active
    for i = 1, #EVENTS do
        if NS.Client.SupportsEvent(EVENTS[i]) then events:RegisterEvent(EVENTS[i]) end
    end
    Step()
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
    action:SetEnabled(not job and Ready() and EmptyCursor())
    local exclude = root:CreateButton(S.Text("Exclude slots from custom sort"), function()
        S.ContextMenu(owner, SlotsMenu)
    end)
    exclude:SetEnabled(not job)
end
