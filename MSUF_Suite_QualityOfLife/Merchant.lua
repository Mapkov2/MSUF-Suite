local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local function Public(value) return not (type(issecretvalue) == "function" and issecretvalue(value)) end
local function Number(value) return Public(value) and type(value) == "number" and value == value end
-- Poor quality is 0 on every client (Enum.ItemQuality.Poor where it exists).
local POOR = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0
local BATCH = 12

local function Repair(self)
    if not self.config.repair or type(CanMerchantRepair) ~= "function" or not CanMerchantRepair()
        or type(GetRepairAllCost) ~= "function" or type(RepairAllItems) ~= "function" or type(GetMoney) ~= "function" then
        return
    end
    local cost, canRepair = GetRepairAllCost()
    local money = GetMoney()
    if not Public(cost) or not Public(canRepair) or not Public(money) then return end
    if not canRepair or type(cost) ~= "number" or type(money) ~= "number" or cost <= 0 or cost > self.config.repairLimit * 10000 then return end
    if self.config.guildRepair then
        if type(CanGuildBankRepair) == "function" and type(GetGuildBankWithdrawMoney) == "function" and type(GetGuildBankMoney) == "function" then
            local allowed = CanGuildBankRepair()
            local allowance, funds = GetGuildBankWithdrawMoney(), GetGuildBankMoney()
            if Public(allowed) and allowed and Number(allowance) and Number(funds)
                and (allowance == -1 or allowance >= cost) and funds >= cost then
                RepairAllItems(true)
                return
            end
        end
        if not self.config.repairFallback then return end
    end
    if cost <= money then RepairAllItems(false) end
end

local container = C_Container
local function SlotInfo(bag, slot)
    if not container or type(container.GetContainerItemInfo) ~= "function" then return end
    local info = container.GetContainerItemInfo(bag, slot)
    if not Public(info) or type(info) ~= "table" then return end
    return info
end

-- One bounded pass: at most BATCH poor items per bag update, each slot
-- re-read immediately before selling. Locked or valueless items are skipped.
local function SellJunk(self)
    if not self.merchantOpen or not self.config.autoJunk or NS.IsCombatLocked()
        or (type(IsShiftKeyDown) == "function" and IsShiftKeyDown())
        or not container or type(container.GetContainerNumSlots) ~= "function" or type(container.UseContainerItem) ~= "function" then
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
        return
    end
    local sold, remaining = 0, false
    local lastBag = Number(NUM_BAG_SLOTS) and NUM_BAG_SLOTS or 4
    for bag = 0, math.min(lastBag + 1, 6) do
        local slots = container.GetContainerNumSlots(bag)
        if Number(slots) then
            for slot = 1, math.min(slots, 200) do
                local info = SlotInfo(bag, slot)
                if info and info.quality == POOR and info.hasNoValue ~= true and info.isLocked ~= true and Number(info.itemID)
                    and not self.requested[bag * 1000 + slot] then
                    if sold < BATCH then
                        self.requested[bag * 1000 + slot] = true
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
        self.context:Event("BAG_UPDATE_DELAYED", function(module)
            for key in pairs(module.requested) do module.requested[key] = nil end
            SellJunk(module)
        end)
    else
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
    end
end

local function Merchant(self, event)
    if event == "MERCHANT_CLOSED" then
        self.merchantOpen = false
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
        if self.soldCount > 0 and self.config.junkReport then
            NS.Print(string.format(S.Text("Sold %d junk items."),
                self.soldCount))
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
    local ctx, c = self.context, self.config
    -- Editing settings during a merchant visit must never spend immediately.
    if c.repair or c.autoJunk then
        ctx:Event("MERCHANT_SHOW", Merchant)
        ctx:Event("MERCHANT_CLOSED", Merchant)
    else
        ctx:RemoveEvent("MERCHANT_SHOW")
        ctx:RemoveEvent("MERCHANT_CLOSED")
        ctx:RemoveEvent("BAG_UPDATE_DELAYED")
        self.merchantOpen = false
    end
    if not c.autoJunk then ctx:RemoveEvent("BAG_UPDATE_DELAYED") end
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
