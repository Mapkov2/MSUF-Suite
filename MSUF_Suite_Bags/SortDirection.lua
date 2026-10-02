local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Sort = {}
P.SortDirection = Sort
local DIRECTION = NS.BagsSortDirection
-- Blizzard's bag sorting direction (C_Container.SetSortBagsRightToLeft). No
-- Blizzard UI sets it, so a player cannot undo it by hand: the value from
-- before the Suite first changed it is kept per character in RootDB, and
-- "Blizzard setting" or a module stop puts it back, also after /reload.
local function Store(create)
    local root, guid = NS.RootDB, S.PublicText(UnitGUID("player"))
    if type(root) ~= "table" or not guid then return nil end
    if type(root.suiteBagSort) ~= "table" then
        if not create then return nil end
        root.suiteBagSort = {}
    end
    return root.suiteBagSort, guid
end

local function Current()
    local current = C_Container.GetSortBagsRightToLeft()
    if S.Public(current) and type(current) == "boolean" then return current end
end

function Sort.Restore()
    local store, guid = Store(false)
    local record = store and store[guid]
    if not record then return end
    local current = Current()
    -- Unreadable now: the record waits for the next restore.
    if current == nil then return end
    if type(record) == "table" and type(record.before) == "boolean" and current == record.applied then
        C_Container.SetSortBagsRightToLeft(record.before)
    end
    store[guid] = nil
    if not next(store) then NS.RootDB.suiteBagSort = nil end
end

function Sort.Refresh()
    if not M.active then return end
    local mode = M.config.sortDirection
    if mode == DIRECTION.BLIZZARD then
        Sort.Restore()
        return
    end
    local current = Current()
    local store, guid = Store(true)
    if current == nil or not store then return end
    local record = store[guid]
    if type(record) ~= "table" or type(record.before) ~= "boolean" then
        record = { before = current }
        store[guid] = record
    elseif record.applied ~= current then
        -- Changed outside the Suite since: that value is the one to give back.
        record.before = current
    end
    -- Fill from the bottom: Blizzard sorts right to left.
    local value = mode == DIRECTION.FROM_BOTTOM
    if current ~= value then C_Container.SetSortBagsRightToLeft(value) end
    record.applied = value
end
