local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
-- Whether equipment in the bags or the bank beats what the player wears in
-- its slot, by effective item level (InventoryDetails.lua reads the level and
-- paints the arrow). What is worn is read when the first item asks after
-- PLAYER_EQUIPMENT_CHANGED, never per repaint; an item's answer is kept until
-- the worn equipment, its link or its level changes.
local Marker = { levels = {}, pending = {}, requested = {}, revision = 0, dirty = true }
P.UpgradeMarker = Marker

-- Equip location -> the inventory slots (INVSLOT_*) it can fill. Rings and
-- trinkets are compared with the lower worn item and an empty slot counts as
-- level 0 (filled); a one-hand weapon is compared with the lower worn weapon,
-- an empty hand being no weapon.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_FINGER = { 11, 12, filled = true }, INVTYPE_TRINKET = { 13, 14, filled = true },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
}
local WORN = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

-- PlayerGear owns the shared class armor and client usability policy.

local function ItemEvents()
    if not Marker.events or not Marker.listening then return end
    if next(Marker.pending) then
        Marker.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        Marker.events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    else
        Marker.events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        Marker.events:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    end
end

-- A missing link or level does not establish that a slot is empty. Only a
-- public nil item ID and link do; false keeps occupied/secret slots unknown.
local function MissingLevel(slot, link)
    local itemID = GetInventoryItemID("player", slot)
    if S.Public(link) and link == nil and S.Public(itemID) and itemID == nil then return nil end
    if S.Finite(itemID) and itemID > 0 then
        Marker.pending[itemID] = true
        if not Marker.requested[itemID] then
            Marker.requested[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    return false
end

local function Rebuild()
    for itemID in pairs(Marker.pending) do Marker.pending[itemID] = nil end
    for i = 1, #WORN do
        local slot = WORN[i]
        local link = GetInventoryItemLink("player", slot)
        local level = S.Public(link) and link and C_Item.GetDetailedItemLevelInfo(link)
        if S.Finite(level) and level > 0 then
            Marker.levels[slot] = level
        else
            Marker.levels[slot] = MissingLevel(slot, link)
        end
    end
    ItemEvents()
    Marker.dirty = false
    Marker.revision = Marker.revision + 1
end

-- The lowest worn level among the slots, 0 when none counts.
local function Lowest(slots)
    local lowest
    for i = 1, #slots do
        local worn = Marker.levels[slots[i]]
        if worn == false then return nil end
        if worn or slots.filled then
            worn = worn or 0
            if not lowest or worn < lowest then lowest = worn end
        end
    end
    return lowest or 0
end

-- Sets item.beatsEquipped (InventoryDetails.lua calls this once per pass for
-- every piece of equipment, after the item's effective level is read). An
-- answer stands until the worn equipment or the player's level changes (both
-- start a new revision), or the item's link or level does.
function Marker.Read(item)
    if Marker.dirty then Rebuild() end
    local gearRevision = P.PlayerGear.revision
    if item.markRevision == Marker.revision and item.markLink == item.link and item.markLevel == item.itemLevel
        and item.markGearRevision == gearRevision and item.markLoaded == item.loaded then
        return
    end
    local slots = SLOTS[item.equipLoc]
    item.markLink, item.markRevision, item.markLevel = item.link, Marker.revision, item.itemLevel
    item.markGearRevision, item.markLoaded = gearRevision, item.loaded
    local lowest = slots and Lowest(slots)
    item.beatsEquipped = lowest ~= nil and item.itemLevel ~= nil and item.itemLevel > lowest and P.PlayerGear.CanEquip(item)
end

-- The worn equipment or the player's level changed (a level can make an item
-- usable): the next pass works every answer out again, and the windows that
-- show items paint again.
local function ClearWaiting()
    for itemID in pairs(Marker.pending) do Marker.pending[itemID] = nil end
    for itemID in pairs(Marker.requested) do Marker.requested[itemID] = nil end
end

local function EquipmentChanged(_, event, itemID, success)
    if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if not S.Finite(itemID) or not Marker.pending[itemID] or not S.Public(success) or success ~= true then return end
        Marker.pending[itemID] = nil
    else
        ClearWaiting()
    end
    ItemEvents()
    Marker.dirty = true
    local view, bank = P.InventoryView, P.BankInventory
    view.Request()
    if bank then bank.Request() end
end

-- Listens for worn equipment only while the marker is on.
function Marker.Refresh()
    local wanted = M.active == true and M.config.showUpgradeMarker == true
    if wanted == (Marker.listening == true) then return end
    if not Marker.events then
        Marker.events = S.CreateFrame("Frame")
        Marker.events:SetScript("OnEvent", EquipmentChanged)
    end
    Marker.listening = wanted
    Marker.dirty = true
    if wanted then
        Marker.events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        Marker.events:RegisterEvent("PLAYER_LEVEL_UP")
    else
        Marker.events:UnregisterAllEvents()
        ClearWaiting()
        P.InventoryDetails.HideMarkers()
    end
end

-- A fight with every bag window closed (CombatIdle.lua): the worn equipment
-- may have changed while paused, so Resume works every answer out again, as
-- EquipmentChanged does.
function Marker.Pause()
    if Marker.listening and Marker.events then Marker.events:UnregisterAllEvents() end
end

function Marker.Resume()
    if not Marker.listening or not Marker.events then return end
    Marker.events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    Marker.events:RegisterEvent("PLAYER_LEVEL_UP")
    ClearWaiting()
    ItemEvents()
    Marker.dirty = true
end

function Marker.Disable()
    if Marker.events then Marker.events:UnregisterAllEvents() end
    Marker.listening, Marker.dirty = false, true
    ClearWaiting()
    for slot in pairs(Marker.levels) do Marker.levels[slot] = nil end
end
