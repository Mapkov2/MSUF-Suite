local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Gear = { revision = 0, listening = false }
P.PlayerGear = Gear
local CLASS, ARMOR = Enum.ItemClass, Enum.ItemArmorSubclass
local ARMOR_SLOTS = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true }
local CLASS_ARMOR = {
    [1] = ARMOR.Plate, [2] = ARMOR.Plate, [3] = ARMOR.Mail, [4] = ARMOR.Leather, [5] = ARMOR.Cloth,
    [6] = ARMOR.Plate, [7] = ARMOR.Mail, [8] = ARMOR.Cloth, [9] = ARMOR.Cloth, [10] = ARMOR.Leather,
    [11] = ARMOR.Leather, [12] = ARMOR.Leather, [13] = ARMOR.Mail,
}

local EVENTS = { "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "UPDATE_FACTION",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_SPECIALIZATION_CHANGED" }

local function ArmorFits(item)
    if item.classID ~= CLASS.Armor or not ARMOR_SLOTS[item.equipLoc] then return true end
    if Gear.armor == nil then
        local class = select(3, UnitClass("player"))
        Gear.armor = S.Finite(class) and CLASS_ARMOR[class] or false
    end
    return item.subclassID == Gear.armor
end

-- Shared by the character category and upgrade marker. Only changed links or
-- player eligibility events ask the client again; no tooltip scan or polling.
function Gear.CanEquip(item)
    if item.gearRevision == Gear.revision and item.gearLink == item.link and item.gearItemID == item.itemID then
        return item.gearFits
    end
    if item.loaded == false or not S.Finite(item.itemID) then return false end
    local equip = item.equipLoc
    local fits = equip and equip ~= ""
        and equip ~= "INVTYPE_NON_EQUIP_IGNORE" and ArmorFits(item)
    if fits then
        local usable = C_PlayerInfo.CanUseItem(item.itemID)
        if not S.Public(usable) then return false end
        fits = usable == true
    end
    item.gearRevision, item.gearLink, item.gearItemID = Gear.revision, item.link, item.itemID
    item.gearFits = fits == true
    return item.gearFits
end

function Gear.Matches(item)
    local class = item.classID
    return (class == CLASS.Armor or class == CLASS.Weapon) and Gear.CanEquip(item)
end

local function Changed(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and (not S.Public(unit) or unit ~= "player") then return end
    Gear.revision = Gear.revision + 1
    P.InventoryView.Request()
    if not NS.Client.isForever then P.BankInventory.Request() end
end

function Gear.Refresh()
    local c = M.config
    local categories = c.inventoryView == NS.BagsView.CATEGORIES or not NS.Client.isForever and c.bankView == NS.BagsBankView.CATEGORIES
    local wanted = M.active == true and (c.showUpgradeMarker == true or c.category_myArmorSlot == true and categories)
    if wanted == Gear.listening then return end
    Gear.listening, Gear.revision = wanted, Gear.revision + 1
    if wanted then
        if not Gear.events then
            Gear.events = S.CreateFrame("Frame")
            Gear.events:SetScript("OnEvent", Changed)
        end
        for i = 1, #EVENTS do
            if NS.Client.SupportsEvent(EVENTS[i]) then Gear.events:RegisterEvent(EVENTS[i]) end
        end
    elseif Gear.events then
        Gear.events:UnregisterAllEvents()
    end
end

function Gear.Disable()
    if Gear.events then Gear.events:UnregisterAllEvents() end
    Gear.listening, Gear.armor, Gear.revision = false, nil, Gear.revision + 1
end
