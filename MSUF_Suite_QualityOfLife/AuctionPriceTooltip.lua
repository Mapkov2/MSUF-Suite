local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end
local Lines = S.TooltipLines
local M = {}
local AUCTION_ADDON = "Blizzard_AuctionHouseUI"

local MAIN_HAND, OFF_HAND = { "MainHandSlot" }, { "SecondaryHandSlot" }
local SLOTS = {
    INVTYPE_HEAD = { "HeadSlot" }, INVTYPE_NECK = { "NeckSlot" },
    INVTYPE_SHOULDER = { "ShoulderSlot" }, INVTYPE_CLOAK = { "BackSlot" },
    INVTYPE_CHEST = { "ChestSlot" }, INVTYPE_ROBE = { "ChestSlot" },
    INVTYPE_WRIST = { "WristSlot" }, INVTYPE_HAND = { "HandsSlot" },
    INVTYPE_WAIST = { "WaistSlot" }, INVTYPE_LEGS = { "LegsSlot" }, INVTYPE_FEET = { "FeetSlot" },
    INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
    INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
    INVTYPE_WEAPONMAINHAND = MAIN_HAND, INVTYPE_2HWEAPON = MAIN_HAND,
    INVTYPE_WEAPONOFFHAND = OFF_HAND, INVTYPE_SHIELD = OFF_HAND, INVTYPE_HOLDABLE = OFF_HAND,
    INVTYPE_RANGED = { "RangedSlot" }, INVTYPE_RANGEDRIGHT = { "RangedSlot" },
    INVTYPE_THROWN = { "RangedSlot" }, INVTYPE_RELIC = { "RangedSlot" },
}
local BOTH_HANDS = { "MainHandSlot", "SecondaryHandSlot" }

local function ReadableTable(value)
    return S.Public(value) and type(value) == "table" and canaccesstable(value)
end

local function PositiveInteger(value)
    return S.Finite(value) and value > 0 and value == math.floor(value)
end

-- Blizzard supplies the row that owns each item tooltip. The browse price
-- describes a bucket of offers. Only an actual listing supplies a buyout.
local function AuctionRow(owner, row)
    local house = _G.AuctionHouseFrame
    if not house or NS.Safety.IsForbidden(house) or not house:IsShown() then return end
    if not S.Public(owner) or not owner or NS.Safety.IsForbidden(owner) or not ReadableTable(row)
        or type(owner.GetItemList) ~= "function" then return end
    local list = owner:GetItemList()
    if not S.Public(list) or not list then return end
    local browse = list == house.BrowseResultsFrame.ItemList
    if not browse and list ~= house.ItemBuyFrame.ItemList then return end
    if not ReadableTable(row.itemKey) or not PositiveInteger(row.itemKey.itemID) then return end
    return row.itemKey.itemID, browse
end

local Copper = S.MoneyText

local function HasVendorLine(data)
    local lines = data.lines
    if not ReadableTable(lines) then return false end
    for i = 1, #lines do
        local line = lines[i]
        if ReadableTable(line) and S.Public(line.type) and line.type == Enum.TooltipDataLineType.SellPrice
            and PositiveInteger(line.price) then return true end
    end
    return false
end

local function EquippedLink(slotName)
    local slot = GetInventorySlotInfo(slotName)
    if not PositiveInteger(slot) then return nil, true end
    local link = GetInventoryItemLink("player", slot)
    if not S.Public(link) then return nil, true end
    if link == nil then
        local id = GetInventoryItemID("player", slot)
        return nil, not S.Public(id) or id ~= nil
    end
    return S.PublicText(link), false
end

local function CompareSlots(equip)
    if equip == "INVTYPE_WEAPON" or equip == "INVTYPE_WEAPONOFFHAND" then
        local dual = CanDualWield()
        if not S.Public(dual) or dual ~= true then
            return equip == "INVTYPE_WEAPON" and MAIN_HAND or nil
        end
        if equip == "INVTYPE_WEAPON" then return BOTH_HANDS end
    end
    return SLOTS[equip]
end

local function ShowReplacement(tooltip, slot, price)
    local link = EquippedLink(slot)
    if not link then return end
    local name, _, _, _, _, _, _, _, _, _, vendor = C_Item.GetItemInfo(link)
    name = S.PublicText(name)
    if not name or not S.Finite(vendor) or vendor < 0 or vendor ~= math.floor(vendor) then return end
    Lines.Line(tooltip, "Vendor sell price of equipped item", name .. "  " .. Copper(vendor))
    local difference = price - vendor
    if difference < 0 then
        Lines.Line(tooltip, "Gold left after replacing item", Copper(-difference))
    else
        Lines.Line(tooltip, "Net cost after selling equipped item", Copper(difference))
    end
end

-- The second slot is only a replacement when it can be used with the weapon
-- already in the main hand. A two-hander can change both slots at once.
local function Compare(tooltip, equip, price)
    local slots = CompareSlots(equip)
    if not slots then return end
    if equip == "INVTYPE_2HWEAPON" then
        local offHand, restricted = EquippedLink("SecondaryHandSlot")
        if offHand or restricted then return end
    end
    for i = 1, #slots do
        local slot = slots[i]
        if slot ~= "SecondaryHandSlot" then
            ShowReplacement(tooltip, slot, price)
        else
            local main, restricted = EquippedLink("MainHandSlot")
            local mainEquip = main and S.PublicText(select(9, C_Item.GetItemInfo(main)))
            if not restricted and (not main or mainEquip and mainEquip ~= "INVTYPE_2HWEAPON") then
                ShowReplacement(tooltip, slot, price)
            end
        end
    end
end

local function CanEquip(id)
    local usable = C_PlayerInfo.CanUseItem(id)
    return S.Public(usable) and usable == true
end

local function ShowPrices(tooltip, data, row, id, browse)
    local price = row.buyoutAmount
    if browse then price = row.minPrice end
    local hasPrice = PositiveInteger(price)
    if hasPrice then
        Lines.Line(tooltip, browse and "AH price from" or "AH buyout price", Copper(price))
    end

    local link = S.PublicText(row.itemLink)
    local _, _, _, _, _, _, _, _, equip, _, vendor = C_Item.GetItemInfo(link or id)
    local addVendor = PositiveInteger(vendor) and not HasVendorLine(data)
    if addVendor then
        Lines.Line(tooltip, "Vendor sell price per item", Copper(vendor))
    end

    equip = S.PublicText(equip)
    local quantity, owned, ownedByCharacter = row.quantity, row.containsAccountItem, row.containsOwnerItem
    if not browse and link and equip and hasPrice
        and S.Public(quantity) and quantity == 1 and S.Public(owned) and owned == false
        and S.Public(ownedByCharacter) and ownedByCharacter == false and CanEquip(id) then
        Compare(tooltip, equip, price)
    end
    if hasPrice or addVendor then Lines.Grow(tooltip) end
end

-- This callback belongs to the auction house, so item tooltips elsewhere
-- have no additional callback, combat event, timer or background price read.
local function AuctionTooltip(owner, row)
    if not M.active or S.InCombat() then return end
    local id, browse = AuctionRow(owner, row)
    if not id then return end
    local tooltip, data = Lines.Open()
    if not tooltip or not S.Public(data.type) or data.type ~= Enum.TooltipDataType.Item
        or not PositiveInteger(data.id) or data.id ~= id then return end
    local tooltipOwner = tooltip:GetOwner()
    if not S.Public(tooltipOwner) or tooltipOwner ~= owner then return end
    S.Dispatch(ShowPrices, tooltip, data, row, id, browse)
end

local function HookAuction()
    hooksecurefunc(AuctionHouseUtil, "SetAuctionHouseTooltip", AuctionTooltip)
end

function M:Enable()
    if not self.hookRequested then
        self.hookRequested = true
        EventUtil.ContinueOnAddOnLoaded(AUCTION_ADDON, HookAuction)
    end
end

S.Install("auctionPriceTooltip", M)
