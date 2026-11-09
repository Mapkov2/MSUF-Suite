local _, P = ...
local S = P.Suite
-- One read of every container slot, shared by the item levels (Bags.lua), the
-- inventory view and the bank view. C_Container.GetContainerItemInfo and
-- GetContainerItemQuestInfo build a new table per call, so a slot is read
-- again only after BAG_UPDATE(bag), ITEM_LOCK_CHANGED(bag, slot), a search
-- change or a quest change said it may differ; the native container frames
-- refresh on the same events (ContainerFrame.lua ContainerFrame_OnEvent).
-- Slot keys are bag * KEY + slot (bank tabs hold 98 slots).
-- bankTabs: the bank tab IDs read through the cache (BankIndex.lua).
local SlotCache = { info = {}, quest = {}, version = {}, sizes = {}, dirtyBags = {}, dirtySlots = {}, bankTabs = {},
    KEY = 1000 }
P.SlotCache = SlotCache
local KEY = SlotCache.KEY
local client = P.NS and P.NS.Client
local KEYRING_BAG = client and client.isForever and KEYRING_CONTAINER or nil
local Finite, Public = S.Finite, S.Public
local bindings, bindLocation = {}, nil
local BIND_NONE, BIND_ON_EQUIP, BIND_UNTIL_EQUIPPED = 0, 2, 9

local function Forget(key)
    SlotCache.info[key], SlotCache.quest[key], SlotCache.dirtySlots[key], bindings[key] = nil, nil, nil, nil
    SlotCache.version[key] = (SlotCache.version[key] or 0) + 1
end

-- Blizzard marks active quest objectives with isQuestItem and quest starters
-- with questID. Only a readable, unmarked slot can hold an inactive quest item.
local function QuestState(quest)
    if not Public(quest) or type(quest) ~= "table" or not Public(quest.isQuestItem) then return nil end
    if quest.isQuestItem == true then return true end
    local questID, active = quest.questID, quest.isActive
    if quest.isQuestItem == false and Public(questID) and questID == nil and Public(active) and active == false then
        return false
    end
end

local function Read(bag, slot)
    local key = bag * KEY + slot
    local info = C_Container.GetContainerItemInfo(bag, slot)
    bindings[key] = nil
    SlotCache.version[key] = (SlotCache.version[key] or 0) + 1
    SlotCache.dirtySlots[key] = nil
    if not Public(info) then
        -- Unreadable now: nothing is kept and the next pass reads it again.
        SlotCache.info[key], SlotCache.quest[key], SlotCache.dirtySlots[key] = nil, nil, true
        return
    end
    SlotCache.info[key] = info or false
    if not info then
        SlotCache.quest[key] = nil
        return
    end
    SlotCache.quest[key] = QuestState(C_Container.GetContainerItemQuestInfo(bag, slot))
end

-- Brings one container up to date and returns its slot count.
function SlotCache.Sync(bag)
    local size
    if bag == KEYRING_BAG then
        size = GetKeyRingSize()
    else
        size = C_Container.GetContainerNumSlots(bag)
    end
    if not Finite(size) or size < 0 or size >= KEY then size = 0 end
    local base = bag * KEY
    local known = SlotCache.sizes[bag]
    if SlotCache.dirtyBags[bag] or known ~= size then
        for slot = 1, size do Read(bag, slot) end
        for slot = size + 1, known or 0 do Forget(base + slot) end
        SlotCache.sizes[bag], SlotCache.dirtyBags[bag] = size, nil
    elseif next(SlotCache.dirtySlots) then
        for slot = 1, size do
            if SlotCache.dirtySlots[base + slot] then Read(bag, slot) end
        end
    end
    return size
end

-- Slot info, quest state (true for an objective, false for confirmed unmarked,
-- nil for a starter or unknown), and read version.
function SlotCache.Get(bag, slot)
    local key = bag * KEY + slot
    local info = SlotCache.info[key]
    return info or nil, SlotCache.quest[key], SlotCache.version[key] or 0
end

function SlotCache.MarkBag(bag)
    if Finite(bag) then SlotCache.dirtyBags[bag] = true end
end

-- The slot instance, not GetItemInfo's generic enum, identifies Warbound until
-- equipped (Blizzard ContainerFrame_ConsiderItemButtonForWarboundUntilEquipTutorial).
-- Share one result per slot read between the badge and inventory search. Reuse
-- the location object; neither a refresh nor a changed slot allocates one.
function SlotCache.Binding(bag, slot, bindType)
    local key = bag * KEY + slot
    local known = bindings[key]
    if known ~= nil then return known end
    local info = SlotCache.info[key]
    if not info or bindType == nil then return nil end
    if C_Item.IsBoundToAccountUntilEquip then
        if bindLocation then
            bindLocation:SetBagAndSlot(bag, slot)
        else
            bindLocation = ItemLocation:CreateFromBagAndSlot(bag, slot)
        end
        -- Selling or moving an item can empty the slot before its cached read expires.
        local exists = C_Item.DoesItemExist(bindLocation)
        if not Public(exists) or exists ~= true then
            SlotCache.dirtySlots[key] = true
            return nil
        end
        local untilEquipped = C_Item.IsBoundToAccountUntilEquip(bindLocation)
        if not Public(untilEquipped) or untilEquipped == nil then return nil end
        if untilEquipped then
            bindings[key] = BIND_UNTIL_EQUIPPED
            return bindings[key]
        end
        if bindType == BIND_UNTIL_EQUIPPED then bindType = BIND_NONE end
    end
    if bindType == BIND_ON_EQUIP or bindType == BIND_UNTIL_EQUIPPED then
        if not Public(info.isBound) then return nil end
        if info.isBound ~= false then bindType = BIND_NONE end
    end
    bindings[key] = bindType
    return bindType
end

-- Equipment slots report ITEM_LOCK_CHANGED(inventorySlot, nil); only a
-- container slot changes cached contents.
function SlotCache.MarkSlot(bag, slot)
    if Finite(bag) and Finite(slot) then SlotCache.dirtySlots[bag * KEY + slot] = true end
end

function SlotCache.MarkAll()
    for bag in pairs(SlotCache.sizes) do SlotCache.dirtyBags[bag] = true end
end

function SlotCache.Reset()
    for key in pairs(bindings) do bindings[key] = nil end
    for _, t in ipairs({ SlotCache.info, SlotCache.quest, SlotCache.sizes, SlotCache.dirtyBags, SlotCache.dirtySlots, SlotCache.bankTabs }) do
        for key in pairs(t) do t[key] = nil end
    end
end

local MARK_ALL = { QUEST_ACCEPTED = true, QUEST_REMOVED = true,
    BAG_CONTAINER_UPDATE = true, PLAYER_ENTERING_WORLD = true, BANKFRAME_OPENED = true }

-- A search changes only isFiltered. The bank view never reads it (its native
-- buttons refresh themselves on INVENTORY_SEARCH_UPDATE), so a search marks
-- the bags alone, never the bank tabs.
local function MarkSearched()
    for bag in pairs(SlotCache.sizes) do
        if not SlotCache.bankTabs[bag] then SlotCache.dirtyBags[bag] = true end
    end
end

local function OnEvent(_, event, bag, slot)
    if event == "BAG_UPDATE" then
        SlotCache.MarkBag(bag)
    elseif event == "ITEM_LOCK_CHANGED" then
        SlotCache.MarkSlot(bag, slot)
    elseif event == "INVENTORY_SEARCH_UPDATE" then
        MarkSearched()
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if bag == "player" then SlotCache.MarkAll() end
    elseif MARK_ALL[event] then
        SlotCache.MarkAll()
    end
end

-- UNIT_QUEST_LOG_CHANGED is registered for the player alone (Start): quest
-- changes of group members say nothing about the player's bags.
local EVENTS = { "BAG_UPDATE", "ITEM_LOCK_CHANGED", "INVENTORY_SEARCH_UPDATE",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_CONTAINER_UPDATE", "PLAYER_ENTERING_WORLD", "BANKFRAME_OPENED" }

-- Bags.lua starts the cache before its first read and stops it on disable.
-- Contents can change while the module is off: a start reads everything again.
function SlotCache.Start()
    if not SlotCache.events then
        SlotCache.events = S.CreateFrame("Frame")
        SlotCache.events:SetScript("OnEvent", OnEvent)
    end
    if SlotCache.listening then return end
    SlotCache.Reset()
    for i = 1, #EVENTS do SlotCache.events:RegisterEvent(EVENTS[i]) end
    SlotCache.events:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
    SlotCache.listening = true
end

function SlotCache.Stop()
    if SlotCache.events then SlotCache.events:UnregisterAllEvents() end
    SlotCache.listening = false
    SlotCache.Reset()
end
