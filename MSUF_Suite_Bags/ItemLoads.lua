local _, P = ...
-- Item data loads of the Bags (C_Item.RequestLoadItemDataByID), one tracker
-- per user: the bag item levels (Bags.lua), the bank item levels
-- (BankItemLevel.lua) and each inventory index (InventoryIndex.lua). A
-- tracker asks for an item once while its load is out. A load the client
-- answered with success false is failed and is not asked again until Retry
-- (the next window opening) or Reset: the client would answer each new
-- request with another failure at once. Callers keep their own lists of what
-- waits for an item; GET_ITEM_INFO_RECEIVED reaches them through Received.
local Loads = {}
P.ItemLoads = Loads
local LOADING, FAILED = 1, 2

-- limit: the most items the tracker remembers at once (loading or failed);
-- nil for no limit.
function Loads.New(limit)
    return { state = {}, count = 0, limit = limit }
end

local function Drop(tracker, itemID)
    tracker.state[itemID] = nil
    tracker.count = tracker.count - 1
end

-- Asks for itemID unless its load is out already. Returns whether the load
-- is out: false after a failure or while the tracker is full.
function Loads.Request(tracker, itemID)
    local state = tracker.state[itemID]
    if state == LOADING then return true end
    if state == FAILED or tracker.limit and tracker.count >= tracker.limit then return false end
    tracker.state[itemID] = LOADING
    tracker.count = tracker.count + 1
    C_Item.RequestLoadItemDataByID(itemID)
    return true
end

function Loads.Loading(tracker, itemID)
    return tracker.state[itemID] == LOADING
end

function Loads.Failed(tracker, itemID)
    return tracker.state[itemID] == FAILED
end

-- The client answered the load of itemID; loaded is the caller's reading of
-- its success flag. A failed load is remembered.
function Loads.Received(tracker, itemID, loaded)
    if tracker.state[itemID] ~= LOADING then return end
    if loaded then Drop(tracker, itemID) else tracker.state[itemID] = FAILED end
end

-- Forgets the loads out for items nothing waits for any more (waiting[itemID]
-- unset); a later need asks again.
function Loads.Prune(tracker, waiting)
    for itemID, state in pairs(tracker.state) do
        if state == LOADING and not waiting[itemID] then Drop(tracker, itemID) end
    end
end

-- Forgets the failures: the next need asks again.
function Loads.Retry(tracker)
    for itemID, state in pairs(tracker.state) do
        if state == FAILED then Drop(tracker, itemID) end
    end
end

function Loads.Reset(tracker)
    for itemID in pairs(tracker.state) do tracker.state[itemID] = nil end
    tracker.count = 0
end
