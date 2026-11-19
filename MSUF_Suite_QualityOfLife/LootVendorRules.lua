local _, P = ...
local NS, S = P.NS, P.Suite

local M = { ids = {} }
local POPUP = "MSUF_SUITE_SELL_MARKED_ITEMS"
-- Retail BagIndex constants (upstream/live BagIndexConstantsDocumentation.lua).
local FIRST_BAG, LAST_BAG = 0, 5
-- At most this many marked item IDs count (itemIDs).
local MAX_IDS = 200
local ItemGUID = S.QoLItemGUID

local function MerchantOpen(self)
    if not self.active or NS.InCombat() or not MerchantFrame:IsShown() then return false end
    local tab = MerchantFrame.selectedTab
    return S.Public(tab) and tab == 1
end

-- Blizzard's click sends an item inside its refund window to the refund
-- dialog; a direct use would sell it. An unreadable answer counts as refundable.
local function Refundable(bag, slot)
    return S.QoLRefundable(bag, slot, false) ~= false
end

local function Eligible(self, bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not S.Public(info) or type(info) ~= "table"
        or not S.Finite(info.itemID) or not self.ids[info.itemID]
        or not S.Finite(info.quality) or info.quality > self.config.maxQuality
        or not S.Public(info.hasNoValue) or info.hasNoValue ~= false
        or not S.Public(info.hasLoot) or info.hasLoot ~= false
        or not S.Public(info.isLocked) or info.isLocked ~= false
        or not S.Public(info.hyperlink) or type(info.hyperlink) ~= "string" then return nil end
    if not self.config.includeGear then
        local equippable = C_Item.IsEquippableItem(info.hyperlink)
        if not S.Public(equippable) or equippable ~= false then return nil end
    end
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    if not S.Public(quest) or type(quest) ~= "table"
        or not S.Public(quest.isQuestItem) or quest.isQuestItem ~= false
        or not S.Public(quest.questID) or quest.questID then return nil end
    local guid = ItemGUID(bag, slot)
    if not guid then return nil end
    if S.InventoryProtection:IsProtected(info.itemID, bag, slot) or Refundable(bag, slot) then return nil end
    return { bag = bag, slot = slot, id = info.itemID, guid = guid,
        count = S.Finite(info.stackCount) and info.stackCount or nil, link = info.hyperlink }
end

local function Candidates(self)
    local list = {}
    if not MerchantOpen(self) or not next(self.ids) then return list end
    S.InventoryProtection:Prepare()
    for bag = FIRST_BAG, LAST_BAG do
        local count = C_Container.GetContainerNumSlots(bag)
        if S.Finite(count) and count >= 0 and count <= 200 and count == math.floor(count) then
            -- Descending order keeps the next slot stable if the client
            -- compacts an inventory location after a sale.
            for slot = count, 1, -1 do
                local item = Eligible(self, bag, slot)
                if item then list[#list + 1] = item end
            end
        end
    end
    return list
end

local function Sell(self, preview)
    -- Another item window open beside the merchant would change what using
    -- an item does; the sale then stays manual.
    if not MerchantOpen(self) or type(preview) ~= "table" or S.QoLItemUseWindow("MerchantFrame") then return end
    local cursorItem = CursorHasItem()
    if not S.Public(cursorItem) or cursorItem then return end
    local sold, rejected = 0, false
    S.InventoryProtection:Prepare()
    for i = 1, #preview do
        if not MerchantOpen(self) or S.QoLItemUseWindow("MerchantFrame") then
            rejected = true
            break
        end
        local expected = preview[i]
        local current = Eligible(self, expected.bag, expected.slot)
        if current and current.guid == expected.guid and current.id == expected.id
            and current.count == expected.count and current.link == expected.link then
            if not S.QoLRestrictedCall(C_Container.UseContainerItem, current.bag, current.slot) then
                rejected = true
                break
            end
            sold = sold + 1
        end
    end
    if rejected then
        NS.Print(S.Text("Marked item sale stopped; earlier items may already have been sold."))
    elseif sold > 0 then
        NS.Print(S.Text("Marked item sale requested."))
    end
    self:UpdateButton()
end

-- Blizzard's generic confirmation (S.Confirm, MSUF_Suite_Modules/Dialogs.lua)
-- asks before the marked stacks are sold.
local function ConfirmSale(preview)
    if #preview == 0 then return end
    local profile, visit = NS.DB, M.visit
    S.Confirm(POPUP, {
        text = S.Text("Sell %d marked item stacks to this merchant?"), text_arg1 = #preview,
        acceptText = S.BlizzardText("SELL", "Sell"), cancelText = S.BlizzardText("CANCEL", "Cancel"),
        showAlert = true,
        callback = function()
            if M.active and NS.DB == profile and M.visit == visit then Sell(M, preview) end
        end,
    })
end

local function Click()
    if MerchantOpen(M) then ConfirmSale(Candidates(M)) end
end

function M:CanSellMatches()
    return MerchantOpen(self) and next(self.ids) ~= nil and not S.QoLItemUseWindow("MerchantFrame")
end

local function MerchantTabChanged(self)
    local ready = self:CanSellMatches()
    if self.quickReady == ready then return end
    self.quickReady = ready
    if S.BagsToolsChanged then S.BagsToolsChanged() end
end

local function SaleOrder(a, b)
    return a.bag < b.bag or a.bag == b.bag and a.slot > b.slot
end

function M:SellMatches(items)
    if not self:CanSellMatches() then return end
    local preview = {}
    S.InventoryProtection:Prepare()
    for i = 1, #items do
        local expected = items[i]
        if S.Finite(expected.bag) and expected.bag >= FIRST_BAG and expected.bag <= LAST_BAG
            and S.Finite(expected.slot) and expected.slot > 0 then
            local item = Eligible(self, expected.bag, expected.slot)
            if item and item.id == expected.itemID and item.count == expected.count and item.link == expected.link then
                preview[#preview + 1] = item
            end
        end
    end
    table.sort(preview, SaleOrder)
    ConfirmSale(preview)
end

-- OnLeave hides the shared tooltip only while this frame still owns it.
local function LeaveTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function Enter(button)
    if NS.Safety.IsForbidden(_G.GameTooltip) then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.Text("Sell marked items"))
    GameTooltip:AddLine(S.Text("Only item IDs in your list are offered. Review the confirmation before selling."),
        0.75, 0.83, 0.9, true)
    GameTooltip:Show()
end

local function EnsureButton(self)
    if self.button or NS.IsCombatLocked() then return end
    local merchant = MerchantFrame
    local button = S.CreateFrame("Button", nil, merchant, "UIPanelButtonTemplate")
    button:SetSize(140, 22)
    -- upstream/live MerchantFrame.xml leaves this gap below the final item
    -- row and above the native footer/junk/repair controls.
    button:SetPoint("BOTTOMLEFT", merchant, "BOTTOMLEFT", 12, 50)
    button:SetFrameLevel(merchant:GetFrameLevel() + 10)
    button:SetText(S.Text("Sell marked items"))
    button:SetScript("OnClick", Click)
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", LeaveTooltip)
    self.button = button
end

function M:UpdateButton()
    if not self.active or not next(self.ids) then
        if self.button then self.button:Hide() end
        return
    end
    if not MerchantFrame:IsShown() or MerchantFrame.selectedTab ~= 1 then
        if self.button then self.button:Hide() end
        return
    end
    if NS.IsCombatLocked() then
        self.context:Event("PLAYER_REGEN_ENABLED", M.UpdateButton)
        if self.button then self.button:Hide() end
        return
    end
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    if not MerchantOpen(self) then
        if self.button then self.button:Hide() end
        return
    end
    EnsureButton(self)
    if not self.button then return end
    local count = #Candidates(self)
    if count > 0 then
        self.button:SetText(string.format(S.Text("Sell marked items (%d)"), count))
    else
        self.button:SetText(S.Text("Sell marked items"))
    end
    self.button:SetEnabled(count > 0)
    self.button:Show()
end

local function MerchantEvent(self, event)
    self.visit = (self.visit or 0) + 1
    if event == "MERCHANT_CLOSED" then
        if self.button then self.button:Hide() end
        S.HideQuestion(POPUP)
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
        return
    end
    self.context:Event("BAG_UPDATE_DELAYED", M.UpdateButton)
    self:UpdateButton()
end

local function StopWatching(self)
    if S.UnwatchMerchant then S.UnwatchMerchant(self) end
    self.quickReady = nil
    self.context:RemoveEvent("MERCHANT_SHOW")
    self.context:RemoveEvent("MERCHANT_CLOSED")
    self.context:RemoveEvent("BAG_UPDATE_DELAYED")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    S.HideQuestion(POPUP)
    if self.button then self.button:Hide() end
end

function M:Refresh()
    self.ids = S.QoLParseIDs(self.config.itemIDs, MAX_IDS)
    if S.BagsToolsChanged then S.BagsToolsChanged() end
    if not next(self.ids) then
        StopWatching(self)
        return
    end
    if S.WatchMerchant then S.WatchMerchant(self, MerchantTabChanged) end
    self.context:Event("MERCHANT_SHOW", MerchantEvent)
    self.context:Event("MERCHANT_CLOSED", MerchantEvent)
    if MerchantFrame:IsShown() then
        self.context:Event("BAG_UPDATE_DELAYED", M.UpdateButton)
    end
    self:UpdateButton()
end

function M:Enable() self:Refresh() end

function M:Disable()
    self.ids = {}
    self.visit = (self.visit or 0) + 1
    StopWatching(self)
    if S.BagsToolsChanged then S.BagsToolsChanged() end
end

S.Install("lootVendorRules", M)
