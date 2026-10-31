local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
-- Whether equipment in the bags or the bank beats what the player wears in
-- its slot, by effective item level (InventoryDetails.lua reads the level and
-- paints the arrow). What is worn is read when the first item asks after
-- PLAYER_EQUIPMENT_CHANGED, never per repaint; an item's answer is kept until
-- the worn equipment, its link or its level changes.
local Marker = { levels = {}, revision = 0, dirty = true }
P.UpgradeMarker = Marker
local CLASS, ARMOR = Enum.ItemClass, Enum.ItemArmorSubclass

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

-- Armor of another type than the class wears is not an upgrade, though the
-- class can equip it: the slots the armor type applies to, and the type each
-- class wears (class IDs of GetClassInfo).
local ARMOR_SLOTS = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true }
local CLASS_ARMOR = {
    [1] = ARMOR.Plate, [2] = ARMOR.Plate, [3] = ARMOR.Mail, [4] = ARMOR.Leather, [5] = ARMOR.Cloth,
    [6] = ARMOR.Plate, [7] = ARMOR.Mail, [8] = ARMOR.Cloth, [9] = ARMOR.Cloth, [10] = ARMOR.Leather,
    [11] = ARMOR.Leather, [12] = ARMOR.Leather, [13] = ARMOR.Mail,
}

local function Rebuild()
    for i = 1, #WORN do
        local slot = WORN[i]
        local link = GetInventoryItemLink("player", slot)
        local level = S.Public(link) and link and C_Item.GetDetailedItemLevelInfo(link)
        Marker.levels[slot] = S.Finite(level) and level or nil
    end
    Marker.dirty = false
    Marker.revision = Marker.revision + 1
end

-- The lowest worn level among the slots, 0 when none counts.
local function Lowest(slots)
    local lowest
    for i = 1, #slots do
        local worn = Marker.levels[slots[i]]
        if worn or slots.filled then
            worn = worn or 0
            if not lowest or worn < lowest then lowest = worn end
        end
    end
    return lowest or 0
end

local function ArmorFits(item)
    if item.classID ~= CLASS.Armor or not ARMOR_SLOTS[item.equipLoc] then return true end
    Marker.armor = Marker.armor or CLASS_ARMOR[select(3, UnitClass("player"))] or false
    return item.subclassID == Marker.armor
end

-- Whether the player can wear the item: the client's class, proficiency and
-- level check, then the class's own armor type. Asked only for an item that
-- beats what is worn, when its answer is worked out (see Marker.Read).
local function CanEquip(item)
    local usable = C_PlayerInfo.CanUseItem(item.itemID)
    return S.Public(usable) and usable == true and ArmorFits(item)
end

-- Sets item.beatsEquipped (InventoryDetails.lua calls this once per pass for
-- every piece of equipment, after the item's effective level is read). An
-- answer stands until the worn equipment or the player's level changes (both
-- start a new revision), or the item's link or level does.
function Marker.Read(item)
    if Marker.dirty then Rebuild() end
    if item.markRevision == Marker.revision and item.markLink == item.link and item.markLevel == item.itemLevel then
        return
    end
    local slots = SLOTS[item.equipLoc]
    item.markLink, item.markRevision, item.markLevel = item.link, Marker.revision, item.itemLevel
    item.beatsEquipped = slots ~= nil and item.itemLevel ~= nil and item.itemLevel > Lowest(slots) and CanEquip(item)
end

-- The worn equipment or the player's level changed (a level can make an item
-- usable): the next pass works every answer out again, and the windows that
-- show items paint again.
local function EquipmentChanged()
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
        P.InventoryDetails.HideMarkers()
    end
end

function Marker.Disable()
    if Marker.events then Marker.events:UnregisterAllEvents() end
    Marker.listening, Marker.dirty = false, true
    for slot in pairs(Marker.levels) do Marker.levels[slot] = nil end
end
