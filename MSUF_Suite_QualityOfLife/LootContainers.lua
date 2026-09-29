local _, P = ...
local NS, S = P.NS, P.Suite

-- Only a container newly seen in carried bags is eligible. A saved GUID is
-- marked before use, so a failed/opened container never loops on bag updates.
local M = { snapshot = {}, seen = {}, pending = {}, attempted = {}, dirty = {} }
-- Retail BagIndex constants are Backpack=0 and ReagentBag=5
-- (upstream/live BagIndexConstantsDocumentation.lua). The controller limits
-- this module to Retail; avoid touching Enum while a Forever harness parses it.
local FIRST_BAG, LAST_BAG = 0, 5
local MAX_SEEN_CONTAINERS = 1024

local function BagID(bag)
    return S.Finite(bag) and bag >= FIRST_BAG and bag <= LAST_BAG and bag == math.floor(bag)
end

local function ItemGUID(bag, slot)
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not S.Public(location) or not location then return nil end
    local guid = C_Item.GetItemGUID(location)
    return S.Public(guid) and type(guid) == "string" and guid ~= "" and guid or nil
end

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

local function Visible(frame)
    return frame and not NS.Safety.IsForbidden(frame) and frame:IsShown()
end

local function UIBlocksUse()
    return Visible(_G.MerchantFrame) or Visible(_G.BankFrame) or Visible(_G.MailFrame)
        or Visible(_G.TradeFrame) or Visible(_G.AuctionHouseFrame)
        or Visible(_G.ItemSocketingFrame)
        or Visible(_G.ItemUpgradeFrame)
end

local function ValidCandidate(candidate)
    local guid, info = ReadSlot(candidate.bag, candidate.slot)
    return guid == candidate.guid and info and info.hasLoot == true and info.isLocked == false
end

local Drain
local function LootClosed(self)
    local generation = self.generation
    -- Let Blizzard finish hiding the loot window before opening the next box.
    C_Timer.After(0, function()
        if self.active and self.generation == generation then Drain(self) end
    end)
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
    if not S.Public(pause) or pause or UIBlocksUse() then
        -- A modal UI or Shift means the player keeps control of these items.
        self.pending = {}
        self.context:RemoveEvent("LOOT_CLOSED")
        return
    end
    if Visible(_G.LootFrame) then
        self.context:Event("LOOT_CLOSED", LootClosed)
        return
    end
    local cursorItem = CursorHasItem()
    if not S.Public(cursorItem) or cursorItem then
        self.pending = {}
        self.context:RemoveEvent("LOOT_CLOSED")
        return
    end
    while #self.pending > 0 do
        local candidate = table.remove(self.pending)
        if not self.attempted[candidate.guid] and ValidCandidate(candidate) then
            self.attempted[candidate.guid] = true
            local ok = pcall(C_Container.UseContainerItem, candidate.bag, candidate.slot)
            if not ok then
                self.blocked, self.pending = true, {}
                for _, event in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED",
                    "PLAYER_REGEN_ENABLED", "LOOT_CLOSED" }) do
                    self.context:RemoveEvent(event)
                end
                NS.Print(S.Text("Automatic container opening was blocked by the client."))
                return
            end
            break -- one container at a time; the native loot window owns pickup
        end
    end
    if #self.pending == 0 then self.context:RemoveEvent("LOOT_CLOSED")
    else self.context:Event("LOOT_CLOSED", LootClosed) end
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
            if not baseline and not self.seenSaturated and previous[slot] ~= false
                and not self.seen[guid]
                and info.hasLoot == true and info.isLocked == false
                and not self.attempted[guid] then
                self.pending[#self.pending + 1] = { guid = guid, bag = bag, slot = slot }
            end
            if info.hasLoot == true and not self.seen[guid] and not self.seenSaturated then
                if self.seenCount >= MAX_SEEN_CONTAINERS then
                    -- Stop automation rather than evicting an old GUID: an
                    -- evicted container could otherwise be opened again.
                    self.seenSaturated = true
                    self.pending = {}
                    self.context:RemoveEvent("LOOT_CLOSED")
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
    self.generation = (self.generation or 0) + 1
    self.snapshot, self.seen, self.pending, self.attempted, self.dirty = {}, {}, {}, {}, {}
    self.seenCount, self.seenSaturated = 0, false
    self.blocked = nil
    for bag = FIRST_BAG, LAST_BAG do ScanBag(self, bag, true) end
    self.context:Event("BAG_UPDATE", BagChanged)
    self.context:Event("BAG_UPDATE_DELAYED", BagsSettled)
end

function M:Disable()
    self.generation = (self.generation or 0) + 1
    self.context:RemoveEvent("BAG_UPDATE")
    self.context:RemoveEvent("BAG_UPDATE_DELAYED")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    self.context:RemoveEvent("LOOT_CLOSED")
    self.snapshot, self.seen, self.pending, self.attempted, self.dirty = {}, {}, {}, {}, {}
    self.seenCount, self.seenSaturated = 0, false
    self.blocked = nil
end

S.Install("lootContainers", M)
