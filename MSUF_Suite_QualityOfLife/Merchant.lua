local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local Public = S.Public
local container = C_Container
-- Poor quality is 0 on every client (Enum.ItemQuality.Poor where it exists).
local POOR = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0
local BATCH = 12

local Number = S.Number

local function GuildRepair(cost)
    if type(CanGuildBankRepair) ~= "function" or type(GetGuildBankWithdrawMoney) ~= "function"
        or type(GetGuildBankMoney) ~= "function" then
        return false
    end
    local allowed = CanGuildBankRepair()
    local allowance, funds = GetGuildBankWithdrawMoney(), GetGuildBankMoney()
    if Public(allowed) and allowed and Number(allowance) and Number(funds)
        and (allowance == -1 or allowance >= cost) and funds >= cost then
        RepairAllItems(true)
        return true
    end
    return false
end

local function Repair(self)
    local c = self.config
    if not c.repair or type(CanMerchantRepair) ~= "function" or not CanMerchantRepair()
        or type(GetRepairAllCost) ~= "function" or type(RepairAllItems) ~= "function"
        or type(GetMoney) ~= "function" then
        return
    end
    local cost, canRepair = GetRepairAllCost()
    local money = GetMoney()
    if not Public(cost) or not Public(canRepair) or not Public(money) then return end
    if not canRepair or type(cost) ~= "number" or type(money) ~= "number"
        or cost <= 0 or cost > c.repairLimit * 10000 then
        return
    end
    if c.guildRepair and (GuildRepair(cost) or not c.repairFallback) then return end
    if cost <= money then RepairAllItems(false) end
end

local function SlotInfo(bag, slot)
    local info = container.GetContainerItemInfo(bag, slot)
    if not Public(info) or type(info) ~= "table" then return nil end
    return info
end

local SellJunk
local function BagsChanged(module)
    for key in pairs(module.requested) do module.requested[key] = nil end
    SellJunk(module)
end

-- One bounded pass: at most BATCH poor items per bag update, each slot
-- re-read immediately before selling. Locked or valueless items are skipped.
SellJunk = function(self)
    if not self.merchantOpen or not self.config.autoJunk or NS.IsCombatLocked()
        or (type(IsShiftKeyDown) == "function" and IsShiftKeyDown())
        or not container or type(container.GetContainerNumSlots) ~= "function"
        or type(container.GetContainerItemInfo) ~= "function"
        or type(container.UseContainerItem) ~= "function" then
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
        return
    end
    local sold, remaining = 0, false
    local requested = self.requested
    local lastBag = Number(NUM_BAG_SLOTS) and NUM_BAG_SLOTS or 4
    for bag = 0, math.min(lastBag + 1, 6) do
        local slots = container.GetContainerNumSlots(bag)
        if Number(slots) then
            for slot = 1, math.min(slots, 200) do
                local info = SlotInfo(bag, slot)
                local key = bag * 1000 + slot
                if info and info.quality == POOR and info.hasNoValue ~= true and info.isLocked ~= true
                    and Number(info.itemID) and not requested[key] then
                    if sold < BATCH then
                        requested[key] = true
                        container.UseContainerItem(bag, slot)
                        sold = sold + 1
                        self.soldCount = self.soldCount + (Number(info.stackCount) and info.stackCount or 1)
                    else
                        remaining = true
                    end
                end
            end
        end
    end
    if remaining then
        self.context:Event("BAG_UPDATE_DELAYED", BagsChanged)
    else
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
    end
end

local function Merchant(self, event)
    if event == "MERCHANT_CLOSED" then
        self.merchantOpen = false
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
        if self.soldCount > 0 and self.config.junkReport then
            NS.Print(string.format(S.Text("Sold %d junk items."), self.soldCount))
        end
        self.soldCount = 0
        return
    end
    if self.merchantOpen or NS.IsCombatLocked() then return end
    self.merchantOpen = true
    self.requested = {}
    self.soldCount = 0
    Repair(self)
    SellJunk(self)
end

function M:Refresh()
    local context, c = self.context, self.config
    -- Editing settings during a merchant visit must never spend immediately.
    if c.repair or c.autoJunk then
        context:Event("MERCHANT_SHOW", Merchant)
        context:Event("MERCHANT_CLOSED", Merchant)
    else
        context:RemoveEvent("MERCHANT_SHOW")
        context:RemoveEvent("MERCHANT_CLOSED")
        self.merchantOpen = false
    end
    if not c.autoJunk then context:RemoveEvent("BAG_UPDATE_DELAYED") end
end

function M:Enable()
    self.merchantOpen = false
    self.requested = {}
    self.soldCount = 0
    self:Refresh()
end

function M:Disable()
    self.merchantOpen = false
    self.requested = {}
    self.soldCount = 0
end

S.Install("qol", M)
