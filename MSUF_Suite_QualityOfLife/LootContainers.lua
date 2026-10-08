local _, P = ...
local NS, S = P.NS, P.Suite

-- Only a container newly seen in carried bags is eligible. A saved GUID is
-- marked before use, so a failed/opened container never loops on bag updates.
local M = { snapshot = {}, seen = {}, pending = {}, pendingByGUID = {}, attempted = {}, dirty = {}, held = {} }
-- Retail BagIndex constants are Backpack=0 and ReagentBag=5
-- (upstream/live BagIndexConstantsDocumentation.lua). The controller limits
-- this module to Retail; avoid touching Enum while a Forever harness parses it.
local FIRST_BAG, LAST_BAG = 0, 5
local MAX_SEEN_CONTAINERS = 1024

local function BagID(bag)
    return S.Finite(bag) and bag >= FIRST_BAG and bag <= LAST_BAG and bag == math.floor(bag)
end

local ItemGUID = S.QoLItemGUID

local function ReadSlot(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not S.Public(info) then return false end
    if info == nil then return nil end
    if not S.Public(info.hasLoot) then return false end
    if info.hasLoot ~= true then return nil end
    if not S.Public(info.isLocked) or not S.Finite(info.itemID) then return false end
    local guid = ItemGUID(bag, slot)
    if not guid then return false end
    return guid, info
end


local function WarboundAllowed(self, candidate)
    if not self.config or self.config.skipWarbound == false then return true end
    local api = C_Item
    local location = ItemLocation:CreateFromBagAndSlot(candidate.bag, candidate.slot)
    local itemID = C_Container.GetContainerItemID(candidate.bag, candidate.slot)
    if not S.Finite(itemID) then return false end
    local account = api.IsItemBindToAccount(itemID)
    local untilEquip = api.IsBoundToAccountUntilEquip(location)
    return S.Public(account) and S.Public(untilEquip) and account == false and untilEquip == false
end

local function ValidCandidate(candidate)
    local guid, info = ReadSlot(candidate.bag, candidate.slot)
    return guid == candidate.guid and info and info.hasLoot == true and info.isLocked == false
end

local Drain
-- Item/currency identities: Wowhead public tooltips, reviewed 2026-09-30.
-- The payout's chance to contain shards is independently reported on the
-- currency3376 page. Only this Midnight payout is covered; no amount is assumed.
local PAYOUT, SHARD = 246585, 3376

local function CapRoom(self, candidate)
    if not self.config or self.config.holdDundun ~= true or candidate.itemID ~= PAYOUT then return true end
    local info = C_CurrencyInfo.GetCurrencyInfo(SHARD)
    if not S.Public(info) or type(info) ~= "table" then return false end
    if not S.Finite(info.quantity) or info.quantity < 0 or not S.Finite(info.maxQuantity)
        or not S.Public(info.useTotalEarnedForMaxQty) or type(info.useTotalEarnedForMaxQty) ~= "boolean"
        or not S.Public(info.canEarnPerWeek) or type(info.canEarnPerWeek) ~= "boolean" then return false end
    local amount = info.quantity
    if info.useTotalEarnedForMaxQty then amount = info.totalEarned end
    if not S.Finite(amount) or amount < 0 or info.maxQuantity < 0 then return false end
    if info.maxQuantity > 0 and amount >= info.maxQuantity then return false end
    if info.canEarnPerWeek then
        if not S.Finite(info.quantityEarnedThisWeek) or not S.Finite(info.maxWeeklyQuantity)
            or info.quantityEarnedThisWeek < 0 or info.maxWeeklyQuantity < 0 then return false end
        if info.maxWeeklyQuantity > 0 and info.quantityEarnedThisWeek >= info.maxWeeklyQuantity then return false end
    end
    return true
end

local function CurrencyChanged(self, _, currencyID)
    if not self.active or self.blocked or not S.Public(currencyID)
        or currencyID ~= nil and currencyID ~= SHARD then return end
    for guid, candidate in pairs(self.held) do
        self.held[guid] = nil
        if ValidCandidate(candidate) then
            self.pending[#self.pending + 1], self.pendingByGUID[guid] = candidate, candidate
        end
    end
    self.context:RemoveEvent("CURRENCY_DISPLAY_UPDATE")
    Drain(self)
end

-- A burst of currency updates resumes the held payouts once, next frame.
local function CurrencySettled(self)
    CurrencyChanged(self)
end

local function CurrencyEvent(self, _, currencyID)
    if not S.Public(currencyID) or currencyID ~= nil and currencyID ~= SHARD then return end
    self.currencyJob:Request()
end

local function Hold(self, candidate)
    self.held[candidate.guid] = candidate
    self.context:Event("CURRENCY_DISPLAY_UPDATE", CurrencyEvent)
end
-- Let Blizzard finish hiding the loot window before opening the next box.
local function LootClosed(self)
    self.drainJob:Request()
end

Drain = function(self)
    if not self.active or self.blocked or #self.pending == 0 then
        self.context:RemoveEvent("LOOT_CLOSED")
        return
    end
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", Drain)
        return
    end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    local pause = IsShiftKeyDown()
    if not S.Public(pause) or pause or S.QoLItemUseWindow() then
        -- Shift, or a window that would turn opening into selling, depositing
        -- or another item action, leaves these containers to the player.
        self.pending, self.pendingByGUID = {}, {}
        self.context:RemoveEvent("LOOT_CLOSED")
        return
    end
    if LootFrame:IsShown() then
        self.context:Event("LOOT_CLOSED", LootClosed)
        return
    end
    local cursorItem = CursorHasItem()
    if not S.Public(cursorItem) or cursorItem then
        self.pending, self.pendingByGUID = {}, {}
        self.context:RemoveEvent("LOOT_CLOSED")
        return
    end
    while #self.pending > 0 do
        local candidate = table.remove(self.pending)
        self.pendingByGUID[candidate.guid] = nil
        if not self.attempted[candidate.guid] and ValidCandidate(candidate) and WarboundAllowed(self, candidate) then
            if not CapRoom(self, candidate) then
                Hold(self, candidate)
            else
                self.attempted[candidate.guid] = true
                if not S.QoLRestrictedCall(C_Container.UseContainerItem, candidate.bag, candidate.slot) then
                    self.blocked, self.pending, self.held, self.pendingByGUID = true, {}, {}, {}
                    for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED",
                        "PLAYER_REGEN_ENABLED", "LOOT_CLOSED", "CURRENCY_DISPLAY_UPDATE" }) do
                        self.context:RemoveEvent(event)
                    end
                    NS.Print(S.Text("Automatic container opening was blocked by the client."))
                    return
                end
                break -- one container at a time; the native loot window owns pickup
            end
        end
    end
    if #self.pending == 0 then
        self.context:RemoveEvent("LOOT_CLOSED")
    else
        self.context:Event("LOOT_CLOSED", LootClosed)
    end
end

local function ScanBag(self, bag, baseline)
    local count = C_Container.GetContainerNumSlots(bag)
    if not S.Finite(count) or count < 0 or count > 200 or count ~= math.floor(count) then return end
    local previous = self.snapshot[bag] or {}
    local current = {}
    for slot = 1, count do
        local guid, info = ReadSlot(bag, slot)
        -- false records an unreadable slot. Its later resolution must not look
        -- like a newly acquired container.
        current[slot] = guid
        if guid then
            local pending = self.pendingByGUID[guid] or self.held[guid]
            if pending then pending.bag, pending.slot = bag, slot end
            if not baseline and not self.seenSaturated and previous[slot] ~= false
                and not self.seen[guid]
                and info.hasLoot == true and info.isLocked == false
                and not self.attempted[guid] then
                local candidate = { guid = guid, bag = bag, slot = slot, itemID = info.itemID }
                self.pending[#self.pending + 1], self.pendingByGUID[guid] = candidate, candidate
            end
            if info.hasLoot == true and not self.seen[guid] and not self.seenSaturated then
                if self.seenCount >= MAX_SEEN_CONTAINERS then
                    -- Stop automation rather than evicting an old GUID: an
                    -- evicted container could otherwise be opened again.
                    self.seenSaturated = true
                    self.pending, self.held, self.pendingByGUID = {}, {}, {}
                    self.context:RemoveEvent("LOOT_CLOSED")
                    self.context:RemoveEvent("CURRENCY_DISPLAY_UPDATE")
                else
                    self.seen[guid] = true
                    self.seenCount = self.seenCount + 1
                end
            end
        end
    end
    self.snapshot[bag] = current
end

local function BagChanged(self, _, bag)
    if BagID(bag) then self.dirty[bag] = true end
end

local function BagsSettled(self)
    if not self.active or self.blocked then return end
    for bag in pairs(self.dirty) do
        self.dirty[bag] = nil
        ScanBag(self, bag, false)
    end
    Drain(self)
end

function M:Enable()
    self.currencyJob = self.context:Coalesce(0, CurrencySettled)
    self.drainJob = self.context:Coalesce(0, Drain)
    self.snapshot, self.seen, self.pending, self.attempted, self.dirty, self.held = {}, {}, {}, {}, {}, {}
    self.pendingByGUID = {}
    self.seenCount, self.seenSaturated = 0, false
    self.blocked = nil
    for bag = FIRST_BAG, LAST_BAG do ScanBag(self, bag, true) end
    self.context:Event("BAG_UPDATE", BagChanged)
    self.context:Event("BAG_UPDATE_DELAYED", BagsSettled)
end

function M:Refresh()
    if self.active then CurrencyChanged(self) end
end

-- The context's Release drops a resume or a drain still due.
function M:Disable()
    self.context:RemoveEvent("BAG_UPDATE")
    self.context:RemoveEvent("BAG_UPDATE_DELAYED")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.context:RemoveEvent("LOOT_CLOSED")
    self.context:RemoveEvent("CURRENCY_DISPLAY_UPDATE")
    self.snapshot, self.seen, self.pending, self.attempted, self.dirty, self.held = {}, {}, {}, {}, {}, {}
    self.pendingByGUID = {}
    self.seenCount, self.seenSaturated = 0, false
    self.blocked = nil
end

S.Install("lootContainers", M)
