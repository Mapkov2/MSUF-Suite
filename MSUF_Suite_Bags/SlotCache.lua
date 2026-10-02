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
local Finite, Public = S.Finite, S.Public

local function Forget(key)
    SlotCache.info[key], SlotCache.quest[key], SlotCache.dirtySlots[key] = nil, nil, nil
    SlotCache.version[key] = (SlotCache.version[key] or 0) + 1
end

local function Read(bag, slot)
    local key = bag * KEY + slot
    local info = C_Container.GetContainerItemInfo(bag, slot)
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
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    SlotCache.quest[key] = Public(quest) and quest and Public(quest.isQuestItem) and quest.isQuestItem == true
end

-- Brings one container up to date and returns its slot count.
function SlotCache.Sync(bag)
    local size = C_Container.GetContainerNumSlots(bag)
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

-- info (nil for an empty or unreadable slot), quest flag, read version.
function SlotCache.Get(bag, slot)
    local key = bag * KEY + slot
    local info = SlotCache.info[key]
    return info or nil, SlotCache.quest[key] == true, SlotCache.version[key] or 0
end

function SlotCache.MarkBag(bag)
    if Finite(bag) then SlotCache.dirtyBags[bag] = true end
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
