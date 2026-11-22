local _, P = ...
local NS, S = P.NS, P.Suite
local Purchase = {}
P.RestockPurchase = Purchase
local MAX_REQUESTS = 40
local ACK_TIMEOUT = 3
local CONFIRM_KEY = "restockPurchase"

local function PositiveInteger(value)
    return S.Finite(value) and value > 0 and value % 1 == 0
end

local function Count(id)
    local value = C_Item.GetItemCount(id, false, false, false)
    return S.Finite(value) and value >= 0 and value or nil
end

local function ReadOffer(index, id)
    if NS.InCombat() then return end
    local frame = NS.Safety.Field(_G, "MerchantFrame")
    local shown, tab = frame and frame:IsShown(), NS.Safety.Field(frame, "selectedTab")
    if not S.Public(shown) or shown ~= true or not S.Finite(tab) or tab ~= 1 then return end
    local merchant = S.PublicText(UnitGUID("npc"))
    local item = GetMerchantItemID(index)
    if not merchant or not S.Finite(item) or item ~= id then return end
    local info = C_MerchantFrame.GetItemInfo(index)
    if not S.Public(info) or type(info) ~= "table" or not canaccesstable(info)
        or not S.Public(info.isPurchasable) or info.isPurchasable ~= true
        or not S.Public(info.hasExtendedCost) or info.hasExtendedCost ~= false
        or not PositiveInteger(info.stackCount) or not PositiveInteger(info.price)
        or not S.Finite(info.numAvailable) then return end
    local limit = GetMerchantItemMaxStack(index)
    if not PositiveInteger(limit) or limit < info.stackCount then return end
    return merchant, info, limit
end

local function Fits(id, quantity)
    local stack = select(8, C_Item.GetItemInfo(id))
    local family = C_Item.GetItemFamily(id)
    if not PositiveInteger(stack) or not S.Finite(family) then return false end
    local items, _, complete = S.InventoryData.Bags()
    if not complete then return false end
    local room = 0
    for _, item in ipairs(items) do
        if item.itemID == id and not item.locked then room = room + math.max(0, stack - item.count) end
    end
    -- Count normal bags and compatible specialty bags. The separate reagent
    -- bag may be unusable for this offer, so the estimate leaves it out.
    for bag = 0, 4 do
        local free, accepts = C_Container.GetContainerNumFreeSlots(bag)
        if S.Finite(free) and S.Finite(accepts) and (accepts == 0 or bit.band(family, accepts) ~= 0) then
            room = room + free * stack
        end
    end
    return room >= quantity
end

local function Timeout(self)
    Purchase.Stop(self, "Restock stopped. Check your bags before trying again.")
end

function Purchase.Stop(self, message)
    if not self.purchase then return end
    self.purchase = nil
    self.context:RemoveEvent("PLAYER_MONEY")
    self.context:Cancel(Timeout)
    if message then NS.Print(S.Text(message)) end
end

local function Next(self)
    local order = self.purchase
    if not order then return end
    if order.remaining == 0 then
        Purchase.Stop(self, "Restock complete.")
        return
    end
    local merchant, info, limit = ReadOffer(order.index, order.id)
    local count, money = Count(order.id), GetMoney()
    if not self.active or not info or merchant ~= order.merchant or info.price ~= order.price
        or info.stackCount ~= order.bundle or count ~= order.count or not S.Finite(money)
        or money < order.remaining / order.bundle * order.price
        or (info.numAvailable >= 0 and info.numAvailable < order.remaining) then
        Purchase.Stop(self, "Restock stopped. The offer or your stock changed.")
        return
    end
    local quantity = math.min(order.remaining, math.floor(limit / order.bundle) * order.bundle)
    order.requests = order.requests + 1
    if order.requests > MAX_REQUESTS then
        Timeout(self)
        return
    end
    order.waiting, order.moneyBefore = quantity, money
    self.context:After(ACK_TIMEOUT, Timeout)
    BuyMerchantItem(order.index, quantity)
end

function Purchase.Delivered(self)
    local order = self.purchase
    if not order or not order.waiting then return end
    local count, money = Count(order.id), GetMoney()
    local expectedCount = order.count + order.waiting
    local expectedMoney = order.moneyBefore - order.waiting / order.bundle * order.price
    if (count ~= order.count and count ~= expectedCount) or not S.Finite(money)
        or (money ~= order.moneyBefore and money ~= expectedMoney) then
        Purchase.Stop(self, "Restock stopped. The offer or your stock changed.")
        return
    end
    -- The merchant may deliver the bag contents and debit the gold in
    -- either order. A matching quantity alone can also come from loot.
    if count ~= expectedCount or money ~= expectedMoney then return end
    order.count, order.remaining = count, order.remaining - order.waiting
    order.waiting = nil
    self.context:Cancel(Timeout)
    Next(self)
end

function Purchase.Available(self, row)
    return row and row.goldOffer and not self.purchase
end

function Purchase.Confirm(self, row)
    if not Purchase.Available(self, row) or not self.active then return end
    local merchant, info, limit = ReadOffer(row.key, row.itemID)
    local count, money = Count(row.itemID), GetMoney()
    if not info or not count or not S.Finite(money) then return end
    local packs = math.ceil(row.missing / info.stackCount)
    local quantity, price = packs * info.stackCount, packs * info.price
    local chunk = math.floor(limit / info.stackCount) * info.stackCount
    if quantity > chunk * MAX_REQUESTS or price > money
        or (info.numAvailable >= 0 and info.numAvailable < quantity) then
        NS.Print(S.Text("The merchant cannot fill this order. Check the stock, price and quantity."))
        return
    end
    if not Fits(row.itemID, quantity) then
        NS.Print(S.Text("Make room in your bags before buying this stock."))
        return
    end
    local order = { index = row.key, id = row.itemID, merchant = merchant, price = info.price,
        bundle = info.stackCount, count = count, remaining = quantity, requests = 0 }
    local context, targets, profile = self.context, self.config.targets, NS.DB
    S.Confirm(CONFIRM_KEY, {
        text = "%s", text_arg1 = S.Text("Buy %d × %s for %s?"):format(quantity, row.name, S.MoneyText(price)),
        callback = function()
            if self.purchase or not self.active or NS.InCombat() or self.context ~= context or NS.DB ~= profile
                or self.config.merchantPreview == false or self.config.targets ~= targets then return end
            if not Fits(order.id, order.remaining) then
                NS.Print(S.Text("Make room in your bags before buying this stock."))
                return
            end
            self.purchase = order
            self.context:Event("PLAYER_MONEY", Purchase.Delivered)
            Next(self)
        end,
    })
end
