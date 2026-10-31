local _, P = ...
local S = P.Suite

-- Item helpers the loot and merchant modules share: ID lists typed into a
-- setting, the GUID of a bag item, its refund state and item data asked for
-- once per visit.

-- The item or spell IDs of a list typed into a setting ("1, 2; 3"): a set
-- of whole IDs below 10,000,000, at most limit of them.
function S.QoLParseIDs(value, limit)
    local ids, count = {}, 0
    if type(value) ~= "string" then return ids end
    for token in value:gmatch("[^,%s;]+") do
        local id = tonumber(token)
        if S.Finite(id) and id > 0 and id < 10000000 and id == math.floor(id) and not ids[id] then
            ids[id] = true
            count = count + 1
            if count >= limit then break end
        end
    end
    return ids
end

-- The GUID of the item in a bag slot, nil while it is unreadable.
function S.QoLLocationGUID(location)
    if not S.Public(location) or not location then return nil end
    local guid = C_Item.GetItemGUID(location)
    return S.Public(guid) and type(guid) == "string" and guid ~= "" and guid or nil
end

function S.QoLItemGUID(bag, slot)
    return S.QoLLocationGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
end

-- An item still refundable, the way ContainerFrame_GetExtendedPriceString
-- decides it: a refund time and a price in gold, items or currencies. Nil
-- while the answer is unreadable; each caller picks its safe side.
function S.QoLRefundable(bag, slot, equipped)
    local info = C_Container.GetContainerItemPurchaseInfo(bag, slot, equipped)
    if not S.Public(info) then return nil end
    if type(info) ~= "table" or not S.Finite(info.refundSeconds) then return false end
    return (S.Finite(info.money) and info.money > 0) or (S.Finite(info.itemCount) and info.itemCount > 0)
        or (S.Finite(info.currencyCount) and info.currencyCount > 0)
end

-- Item data asked for once per visit (a merchant window, for example).
-- Request is true while the answer is outstanding; Arrived takes the item
-- of GET_ITEM_INFO_RECEIVED and is true once for an item this asked for.
local Requests = {}
Requests.__index = Requests

function S.QoLItemRequests()
    return setmetatable({ asked = {} }, Requests)
end

function Requests:Request(itemID)
    if not S.Finite(itemID) or itemID <= 0 then return false end
    local asked = self.asked
    if not asked[itemID] then
        asked[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return asked[itemID] == true
end

function Requests:Arrived(itemID)
    if not S.Finite(itemID) or self.asked[itemID] ~= true then return false end
    self.asked[itemID] = "done"
    return true
end

function Requests:Reset()
    local asked = self.asked
    for itemID in pairs(asked) do asked[itemID] = nil end
end
