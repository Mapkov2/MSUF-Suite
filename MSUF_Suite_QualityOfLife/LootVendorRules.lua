local _, P = ...
local NS, S = P.NS, P.Suite

local M = { ids = {} }
local POPUP = "MSUF_SUITE_SELL_MARKED_ITEMS"
-- Retail BagIndex constants (upstream/live BagIndexConstantsDocumentation.lua).
local FIRST_BAG, LAST_BAG = 0, 5

local function ParseIDs(value)
    local ids, count = {}, 0
    if type(value) ~= "string" then return ids end
    for token in value:gmatch("[^,%s;]+") do
        local id = tonumber(token)
        if S.Finite(id) and id > 0 and id < 10000000 and id == math.floor(id)
            and not ids[id] then
            ids[id] = true
            count = count + 1
            if count >= 200 then break end
        end
    end
    return ids
end

local function MerchantOpen(self)
    return self.active and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1
        and not NS.IsCombatLocked()
end

local function ItemGUID(bag, slot)
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not S.Public(location) or not location then return nil end
    local guid = C_Item.GetItemGUID(location)
    return S.Public(guid) and type(guid) == "string" and guid ~= "" and guid or nil
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
    return { bag = bag, slot = slot, id = info.itemID, guid = guid }
end

local function Candidates(self)
    local list = {}
    if not MerchantOpen(self) or not next(self.ids) then return list end
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
    for i = 1, #preview do
        local expected = preview[i]
        local current = Eligible(self, expected.bag, expected.slot)
        if current and current.guid == expected.guid and current.id == expected.id then
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

local function OnAccept(_, preview)
    if M.active then Sell(M, preview) end
end

local function EnsurePopup()
    if StaticPopupDialogs[POPUP] then return end
    StaticPopupDialogs[POPUP] = {
        text = S.Text("Sell %d marked item stacks to this merchant?"),
        button1 = S.BlizzardText("SELL", "Sell"), button2 = S.BlizzardText("CANCEL", "Cancel"),
        OnAccept = OnAccept,
        timeout = 0, whileDead = false, hideOnEscape = true,
        preferredIndex = 3, showAlert = true,
    }
end

local function Click()
    if not MerchantOpen(M) then return end
    local preview = Candidates(M)
    if #preview > 0 then StaticPopup_Show(POPUP, #preview, nil, preview) end
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
    if event == "MERCHANT_CLOSED" then
        if self.button then self.button:Hide() end
        StaticPopup_Hide(POPUP)
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
        return
    end
    self.context:Event("BAG_UPDATE_DELAYED", M.UpdateButton)
    self:UpdateButton()
end

function M:Refresh()
    self.ids = ParseIDs(self.config.itemIDs)
    if not next(self.ids) then
        self.context:RemoveEvent("MERCHANT_SHOW")
        self.context:RemoveEvent("MERCHANT_CLOSED")
        self.context:RemoveEvent("BAG_UPDATE_DELAYED")
        self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
        StaticPopup_Hide(POPUP)
        if self.button then self.button:Hide() end
        return
    end
    EnsurePopup()
    self.context:Event("MERCHANT_SHOW", MerchantEvent)
    self.context:Event("MERCHANT_CLOSED", MerchantEvent)
    if MerchantFrame:IsShown() then
        self.context:Event("BAG_UPDATE_DELAYED", M.UpdateButton)
    end
    self:UpdateButton()
end

function M:Enable() self:Refresh() end

function M:Disable()
    self.context:RemoveEvent("MERCHANT_SHOW")
    self.context:RemoveEvent("MERCHANT_CLOSED")
    self.context:RemoveEvent("BAG_UPDATE_DELAYED")
    self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
    StaticPopup_Hide(POPUP)
    if self.button then self.button:Hide() end
    self.ids = {}
end

S.Install("lootVendorRules", M)
