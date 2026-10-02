local _, P = ...
local NS, S = P.NS, P.Suite
local M = assert(P.BagsModule, "Bags.lua must load before BankItemLevel.lua")
local Loads = P.ItemLoads

M.bankOverlays = setmetatable({}, { __mode = "k" })
M.bankPending, M.bankLoads = {}, Loads.New()

-- The Retail bank owns its pooled buttons, search and tab handling. Only
-- attach a label to a visible native button after Blizzard has refreshed it
-- (upstream/live BankPanelItemButtonMixin:Refresh).
function M:HideBankLevels()
    for _, record in pairs(self.bankOverlays) do
        if record.label then record.label:Hide() end
    end
    for itemID in pairs(self.bankPending) do self.bankPending[itemID] = nil end
    Loads.Reset(self.bankLoads)
end

-- Blizzard_UIPanels_Game creates BankFrame at startup; only the Retail one
-- has a BankPanel (Forever loads the Camelot bank).
local function BankVisible(self)
    return self.active and not self.organizedBankActive and not NS.Client.isForever and self.config.showBankItemLevel
        and BankFrame:IsShown() and BankFrame.BankPanel:IsShown()
end

-- Reads the item level of a bank button's item, or asks for its item data
-- once; OnBankItemInfoReceived repaints the buttons waiting for it. False
-- when that data failed to load: the label then stays hidden.
local function BankLevel(self, button, record, link, itemID)
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if S.Finite(level) and level > 0 then
        record.level = math.floor(level)
        record.label:SetText(tostring(record.level))
        return true
    end
    if not Loads.Request(self.bankLoads, itemID) then return false end
    local pending = self.bankPending[itemID]
    if not pending then
        pending = {}
        self.bankPending[itemID] = pending
    end
    pending[button] = true
    return true
end

local function PaintBankButton(self, button, info)
    local record = self.bankOverlays[button]
    if not BankVisible(self) or not button or NS.Safety.IsForbidden(button)
        or not button:IsShown() or not S.Public(info) or not info
        or (S.Public(info.isFiltered) and info.isFiltered) then
        if record and record.label then record.label:Hide() end
        return
    end
    local link, itemID, quality = info.hyperlink, info.itemID, info.quality
    if not S.Public(link) or type(link) ~= "string" or not S.Finite(itemID)
        or not S.Public(quality) then
        if record and record.label then record.label:Hide() end
        return
    end
    if not record then
        record = {}
        self.bankOverlays[button] = record
    end
    if record.link ~= link then
        record.link, record.level, record.gear, record.quality = link, nil, nil, nil
    end
    if record.gear == nil then
        local equippable = C_Item.IsEquippableItem(link)
        if not S.Public(equippable) then
            if record.label then record.label:Hide() end
            return
        end
        record.gear = equippable == true
    end
    if not record.gear then
        if record.label then record.label:Hide() end
        return
    end
    if not record.label then
        if NS.IsCombatLocked() then
            self.needsBankRefresh = true
            S.Queue("bags")
            return
        end
        record.label = self.OverlayText(button, "TOPRIGHT", -2, -2, "RIGHT")
    end
    self:StyleItemLevel(record)
    if record.level == nil and not BankLevel(self, button, record, link, itemID) then
        record.label:Hide()
        return
    end
    if not record.level then
        record.label:Hide()
        return
    end
    self:PaintItemLevelQuality(record, quality)
    record.label:Show()
end


function M:OnBankItemInfoReceived(itemID, success, waiting)
    self.bankPending[itemID] = nil
    local loaded = S.Public(success) and success == true
    Loads.Received(self.bankLoads, itemID, loaded)
    if loaded and BankVisible(self) then
        for button in pairs(waiting) do
            local info = C_Container.GetContainerItemInfo(button:GetBankTabID(), button:GetContainerSlotID())
            if S.Public(info) and info and S.Public(info.itemID) and info.itemID == itemID then
                PaintBankButton(self, button, info)
            end
        end
    end
end

local BankButtonRefreshed

local function HookBankButton(self, button)
    if not button or NS.Safety.IsForbidden(button) then return end
    local record = self.bankOverlays[button]
    if not record then
        record = {}
        self.bankOverlays[button] = record
    end
    if record.refreshHooked then return end
    hooksecurefunc(button, "Refresh", BankButtonRefreshed)
    record.refreshHooked = true
end

function M:UpdateBank(searchChanged)
    if not BankVisible(self) then
        self:HideBankLevels()
        return
    end
    local panel = BankFrame.BankPanel
    for button in panel:EnumerateValidItems() do
        HookBankButton(self, button)
        -- Native Refresh has already fetched itemInfo. A search change only
        -- updates MatchesSearch, so ask for current filter state in that case.
        local info = button.itemInfo
        if searchChanged then
            info = C_Container.GetContainerItemInfo(button:GetBankTabID(), button:GetContainerSlotID())
        end
        PaintBankButton(self, button, info)
    end
    if next(self.bankPending) then self.context:Event("GET_ITEM_INFO_RECEIVED", M.ItemInfoReceived, true) end
end

BankButtonRefreshed = function(button)
    if not M.active or not M.config.showBankItemLevel then return end
    PaintBankButton(M, button, button.itemInfo)
    if next(M.bankPending) then M.context:Event("GET_ITEM_INFO_RECEIVED", M.ItemInfoReceived, true) end
end

local function BankSearchUpdated(panel)
    if M.active and M.config.showBankItemLevel and panel == BankFrame.BankPanel then
        M:UpdateBank(true)
    end
end

local function BankPanelShown(panel)
    if M.active and M.config.showBankItemLevel and panel == BankFrame.BankPanel then
        M:UpdateBank()
    end
end

local function InstallBankHooks(self)
    if self.bankHooked or NS.Client.isForever then return end
    local panel = BankFrame.BankPanel
    -- XML already copied BankPanelMixin into this native panel before the
    -- Suite loaded. Hook the instance, then attach existing/new pooled buttons
    -- after upstream/live GenerateItemSlotsForSelectedTab has shown them.
    hooksecurefunc(panel, "UpdateSearchResults", BankSearchUpdated)
    hooksecurefunc(panel, "GenerateItemSlotsForSelectedTab", BankPanelShown)
    panel:HookScript("OnShow", BankPanelShown)
    self.bankHooked = true
end

local function BankOpened(self)
    InstallBankHooks(self)
    self:UpdateBank()
end

function M:ApplyBankLevels()
    if NS.Client.isForever or not self.config.showBankItemLevel then
        self.context:RemoveEvent("BANKFRAME_OPENED")
        self:HideBankLevels()
        if not next(self.pending) then self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED") end
        return
    end
    InstallBankHooks(self)
    self.context:Event("BANKFRAME_OPENED", BankOpened)
    self:UpdateBank()
end
