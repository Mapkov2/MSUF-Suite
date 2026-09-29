local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local Public = S.Public
local Number = S.Number

local function GuildRepair(cost)
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
    if not c.repair then return end
    local canRepairHere = CanMerchantRepair()
    if not Public(canRepairHere) or not canRepairHere then return end
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

local function SellJunk(self)
    if not self.config.autoJunk or NS.IsCombatLocked() then return end
    local shift = IsShiftKeyDown()
    if not Public(shift) or shift then return end

    -- Blizzard owns the eligible-item list and honors its backpack and bag
    -- "Exclude Junk Sell" flags. The API does not confirm individual sales.
    local enabled = C_MerchantFrame.IsSellAllJunkEnabled()
    if not Public(enabled) or enabled ~= true then return end
    local count = C_MerchantFrame.GetNumJunkItems()
    if not S.Finite(count) or count < 1 then return end
    C_MerchantFrame.SellAllJunkItems()
    self.saleRequested = true
end

local function Merchant(self, event)
    if event == "MERCHANT_CLOSED" then
        self.merchantOpen = false
        if self.saleRequested and self.config.junkReport then
            NS.Print(S.Text("Junk sale requested."))
        end
        self.saleRequested = false
        return
    end
    if self.merchantOpen or NS.IsCombatLocked() then return end
    self.merchantOpen = true
    self.saleRequested = false
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
end

function M:Enable()
    self.merchantOpen = false
    self.saleRequested = false
    self:Refresh()
end

function M:Disable()
    self.merchantOpen = false
    self.saleRequested = false
end

S.Install("qol", M)
