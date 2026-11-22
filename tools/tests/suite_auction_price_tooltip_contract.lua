local root = assert(arg[1], "repository root required")
local Support = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))()
local locked, fighting, shown, canEquip = false, false, true, true
local added, visits, hooks, reads, layouts, rowReads = {}, 0, 0, 0, 0, 0
local secret = {}
local browseList, buyList = {}, {}
local owner = {}
local list = buyList
function owner:GetItemList()
    rowReads = rowReads + 1
    return list
end

local row = {
    itemKey = { itemID = 42 }, itemLink = "new", quantity = 1, buyoutAmount = 400,
    containsAccountItem = false, containsOwnerItem = false,
}
local data = { id = 42, type = 0, lines = {} }
GameTooltip = {}
function GameTooltip:GetOwner() return owner end
function GameTooltip:IsShown() return true end
function GameTooltip:GetPrimaryTooltipData() return data end
function GameTooltip:Show() layouts = layouts + 1 end
function GameTooltip:AddDoubleLine(label, value)
    added[#added + 1] = { label, value }
end

AuctionHouseFrame = {
    IsShown = function() return shown end,
    ItemBuyFrame = { ItemList = buyList }, BrowseResultsFrame = { ItemList = browseList },
}
AuctionHouseUtil = { SetAuctionHouseTooltip = function() visits = visits + 1 end }
function hooksecurefunc(target, key, callback)
    assert(target == AuctionHouseUtil and key == "SetAuctionHouseTooltip")
    hooks = hooks + 1
    local native = target[key]
    target[key] = function(...)
        native(...)
        callback(...)
    end
end
EventUtil = { ContinueOnAddOnLoaded = function(addon, callback)
    assert(addon == "Blizzard_AuctionHouseUI")
    callback()
end }
Enum = { TooltipDataType = { Item = 0 }, TooltipDataLineType = { SellPrice = 11 } }
local nativeRegistrations = 0
TooltipDataProcessor = { AddTooltipPostCall = function() nativeRegistrations = nativeRegistrations + 1 end }
function canaccesstable() return true end

local equip, resale = "INVTYPE_CHEST", 398
local equipped = { [5] = "old", [11] = "old", [12] = "other", [17] = "off" }
local slots = { ChestSlot = 5, Finger0Slot = 11, Finger1Slot = 12, MainHandSlot = 16, SecondaryHandSlot = 17 }
function GetInventorySlotInfo(name) return slots[name] end
function GetInventoryItemLink(_, slot) reads = reads + 1 return equipped[slot] end
function GetInventoryItemID() return nil end
function CanDualWield() return true end
C_Item = { GetItemInfo = function(item)
    reads = reads + 1
    if item == "new" or item == 42 then
        return "New item", nil, nil, nil, nil, nil, nil, nil, equip, nil, 450
    end
    return item, nil, nil, nil, nil, nil, nil, nil, nil, nil, item == "other" and 175 or resale
end }
C_PlayerInfo = { CanUseItem = function() reads = reads + 1 return canEquip end }

local NS = { Client = { isForever = true },
    InCombat = Support.InCombat(root, function() return locked end, function() return fighting end),
    Safety = { IsForbidden = function() return false end } }
local module
local S = {
    Public = function(value) return value ~= secret end,
    Finite = function(value) return type(value) == "number" and math.abs(value) < math.huge end,
    PublicText = function(value) return type(value) == "string" and value end,
    MoneyText = tostring,
    Text = function(value) return value end,
    Dispatch = function(callback, ...) return callback(...) end,
    Install = function(id, instance)
        assert(id == "auctionPriceTooltip")
        module = instance
    end,
}
local P = { NS = NS, Suite = S }
local path = root .. "/MSUF_Suite_QualityOfLife/"
assert(loadfile(path .. "TooltipLines.lua"))("test", P)
assert(loadfile(path .. "AuctionPriceTooltip.lua"))("test", P)
module.active = true
module:Enable()
module:Enable()
assert(hooks == 1 and nativeRegistrations == 0)

local function Hover(rowData)
    added = {}
    AuctionHouseUtil.SetAuctionHouseTooltip(owner, rowData or row)
end

Hover()
assert(#added == 4 and added[1][1] == "AH buyout price" and added[1][2] == "400")
assert(added[2][2] == "450" and added[3][2] == "old  398" and added[4][2] == "2")
assert(layouts == 1 and visits == 1)
resale = 400
Hover()
assert(added[4][2] == "0")

equip, resale = "INVTYPE_FINGER", 398
Hover()
assert(#added == 6 and added[4][2] == "2" and added[6][2] == "225")
resale = 410
Hover()
assert(added[4][1] == "Gold left after replacing item" and added[4][2] == "10")

list = browseList
local browseRow = { itemKey = { itemID = 42 }, totalQuantity = 10932, minPrice = 300, containsOwnerItem = false }
Hover(browseRow)
assert(#added == 2 and added[1][1] == "AH price from" and added[1][2] == "300")
assert(added[2][1] == "Vendor sell price per item" and added[2][2] == "450")
data.lines = { { type = 11, price = 450 } }
Hover(browseRow)
assert(#added == 1 and added[1][1] == "AH price from" and added[1][2] == "300")

list, data.lines = buyList, {}
row.buyoutAmount = nil
Hover()
assert(#added == 1 and added[1][1] == "Vendor sell price per item")
row.buyoutAmount, row.containsOwnerItem = 400, true
Hover()
assert(#added == 2)
row.containsOwnerItem, row.quantity = false, 2
Hover()
assert(#added == 3 and added[1][1] == "AH stack buyout price" and added[1][2] == "400 for 2 items")
assert(added[2][1] == "AH price per item" and added[2][2] == "200")
row.quantity = 3
Hover()
assert(added[2][1] == "Approximate AH price per item" and added[2][2] == "133")
row.quantity, canEquip = 1, false
Hover()
assert(#added == 2)
canEquip = true
row.quantity, data.id = 1, secret
Hover()
assert(#added == 0)
data.id, equip = 42, "INVTYPE_2HWEAPON"
Hover()
assert(#added == 2)

local previousReads, previousLayouts, previousRows = reads, layouts, rowReads
fighting = true
Hover()
assert(#added == 0 and reads == previousReads and layouts == previousLayouts and rowReads == previousRows)
fighting, locked = false, true
Hover()
assert(#added == 0 and reads == previousReads and layouts == previousLayouts and rowReads == previousRows)
locked, module.active = false, false
Hover()
assert(#added == 0 and reads == previousReads and layouts == previousLayouts)
module.active, shown = true, false
Hover()
assert(#added == 0 and reads == previousReads and layouts == previousLayouts)
print("AH tooltip prices, replacement slots, and no combat item reads")
