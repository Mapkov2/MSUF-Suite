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
local C = { info = {}, quest = {}, version = {}, sizes = {}, dirtyBags = {}, dirtySlots = {}, bankTabs = {},
    KEY = 1000 }
P.SlotCache = C
local KEY = C.KEY
local Finite, Public = S.Finite, S.Public

local function Forget(key)
    C.info[key], C.quest[key], C.dirtySlots[key] = nil, nil, nil
    C.version[key] = (C.version[key] or 0) + 1
end

local function Read(bag, slot)
    local key = bag * KEY + slot
    local info = C_Container.GetContainerItemInfo(bag, slot)
    C.version[key] = (C.version[key] or 0) + 1
    C.dirtySlots[key] = nil
    if not Public(info) then
        -- Unreadable now: nothing is kept and the next pass reads it again.
        C.info[key], C.quest[key], C.dirtySlots[key] = nil, nil, true
        return
    end
    C.info[key] = info or false
    if not info then
        C.quest[key] = nil
        return
    end
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    C.quest[key] = Public(quest) and quest and Public(quest.isQuestItem) and quest.isQuestItem == true
end

-- Brings one container up to date and returns its slot count.
function C.Sync(bag)
    local size = C_Container.GetContainerNumSlots(bag)
    if not Finite(size) or size < 0 or size >= KEY then size = 0 end
    local base = bag * KEY
    local known = C.sizes[bag]
    if C.dirtyBags[bag] or known ~= size then
        for slot = 1, size do Read(bag, slot) end
        for slot = size + 1, known or 0 do Forget(base + slot) end
        C.sizes[bag], C.dirtyBags[bag] = size, nil
    elseif next(C.dirtySlots) then
        for slot = 1, size do
            if C.dirtySlots[base + slot] then Read(bag, slot) end
        end
    end
    return size
end

-- info (nil for an empty or unreadable slot), quest flag, read version.
function C.Get(bag, slot)
    local key = bag * KEY + slot
    local info = C.info[key]
    return info or nil, C.quest[key] == true, C.version[key] or 0
end

function C.MarkBag(bag)
    if Finite(bag) then C.dirtyBags[bag] = true end
end

-- Equipment slots report ITEM_LOCK_CHANGED(inventorySlot, nil); only a
-- container slot changes cached contents.
function C.MarkSlot(bag, slot)
    if Finite(bag) and Finite(slot) then C.dirtySlots[bag * KEY + slot] = true end
end

function C.MarkAll()
    for bag in pairs(C.sizes) do C.dirtyBags[bag] = true end
end

function C.Reset()
    for _, t in ipairs({ C.info, C.quest, C.sizes, C.dirtyBags, C.dirtySlots, C.bankTabs }) do
        for key in pairs(t) do t[key] = nil end
    end
end

local MARK_ALL = { QUEST_ACCEPTED = true, QUEST_REMOVED = true,
    BAG_CONTAINER_UPDATE = true, PLAYER_ENTERING_WORLD = true, BANKFRAME_OPENED = true }

-- A search changes only isFiltered. The bank view never reads it (its native
-- buttons refresh themselves on INVENTORY_SEARCH_UPDATE), so a search marks
-- the bags alone, never the bank tabs.
local function MarkSearched()
    for bag in pairs(C.sizes) do
        if not C.bankTabs[bag] then C.dirtyBags[bag] = true end
    end
end

local function OnEvent(_, event, bag, slot)
    if event == "BAG_UPDATE" then
        C.MarkBag(bag)
    elseif event == "ITEM_LOCK_CHANGED" then
        C.MarkSlot(bag, slot)
    elseif event == "INVENTORY_SEARCH_UPDATE" then
        MarkSearched()
    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if bag == "player" then C.MarkAll() end
    elseif MARK_ALL[event] then
        C.MarkAll()
    end
end

-- UNIT_QUEST_LOG_CHANGED is registered for the player alone (Start): quest
-- changes of group members say nothing about the player's bags.
local EVENTS = { "BAG_UPDATE", "ITEM_LOCK_CHANGED", "INVENTORY_SEARCH_UPDATE",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_CONTAINER_UPDATE", "PLAYER_ENTERING_WORLD", "BANKFRAME_OPENED" }

-- Bags.lua starts the cache before its first read and stops it on disable.
-- Contents can change while the module is off: a start reads everything again.
function C.Start()
    if not C.events then
        C.events = S.CreateFrame("Frame")
        C.events:SetScript("OnEvent", OnEvent)
    end
    if C.listening then return end
    C.Reset()
    for i = 1, #EVENTS do C.events:RegisterEvent(EVENTS[i]) end
    C.events:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
    C.listening = true
end

function C.Stop()
    if C.events then C.events:UnregisterAllEvents() end
    C.listening = false
    C.Reset()
end
