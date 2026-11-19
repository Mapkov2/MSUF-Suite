local _, P = ...
local NS, S = P.NS, P.Suite
local Data, Lists, M = S.InventoryData, NS.InventoryLists, { merchantPreviewOwner = {} }
local IN_COMBAT = { inCombat = true }
local LIVE_EVENTS = { "MERCHANT_UPDATE", "MERCHANT_CLOSED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_DISABLED" }
local NO_OFFERS = {}

function M:Rows()
    local _, bags, complete = Data.Bags()
    local rows = Data.QuantityRows(Lists.Quantities(self.config.targets) or {}, bags)
    for i = 1, #rows do
        local row = rows[i]
        local missing = math.max(0, row.quantity - (bags[row.itemID] or 0))
        local bank, bankAt, account, accountAt = S.InventoryArchive:Supply(row.itemID)
        row.label = S.Text("%s — missing %d"):format(Data.Name(row.itemID), missing)
        local knownBank = bankAt and S.Text("%d, recorded %s"):format(bank, date("%Y-%m-%d %H:%M", bankAt)) or S.Text("Not recorded")
        local knownAccount = accountAt and S.Text("%d, recorded %s"):format(account, date("%Y-%m-%d %H:%M", accountAt)) or S.Text("Not recorded")
        row.detail = S.Text("Target: %d · In bags: %d · Missing: %d\nBank: %s\nWarband bank: %s", true)
            :format(row.quantity, bags[row.itemID] or 0, missing, knownBank, knownAccount)
        if not complete then
            row.label = S.Text("%s — bag quantity unavailable"):format(Data.Name(row.itemID))
            row.detail = S.Text("Some bag slots are unavailable. Refresh outside combat before using a missing amount.")
        end
    end
    return rows
end

function M:Edit(itemID)
    S.InventoryToolsUI.Quantities(self, "Stock targets", function() return Lists.Quantities(M.config.targets) or {} end,
        function(values)
            local text = Lists.EncodeQuantities(values)
            return text and S.Set(M.id, "targets", text) or false
        end, function() M:Open() end, nil, itemID)
end

local function MerchantOpen(self)
    if not NS.Client.isForever or NS.InCombat() or self.active == false or self.config.merchantPreview == false then return false end
    local frame = MerchantFrame
    return frame and not NS.Safety.IsForbidden(frame) and frame:IsShown()
        and S.Finite(frame.selectedTab) and frame.selectedTab == 1
end

local function TargetQuantities(self)
    local targets = Lists.Quantities(self.config.targets) or {}
    local config = S.Config("dataTexts")
    if config and (config.ammoWarning or 0) > 0 then
        local slot = C_PaperDollInfo.GetInventorySlotInfo("AmmoSlot")
        local id = S.Finite(slot) and GetInventoryItemID("player", slot)
        if S.Finite(id) and id > 0 then
            targets[id] = math.max(targets[id] or 0, config.ammoWarning)
            return targets, id, slot
        end
    end
    return targets
end

local function Offer(index, targets)
    local id = GetMerchantItemID(index)
    if not S.Finite(id) or not targets[id] then return end
    local info = C_MerchantFrame.GetItemInfo(index)
    if not S.Public(info) or type(info) ~= "table" or not canaccesstable(info)
        or not S.Public(info.isPurchasable) or info.isPurchasable ~= true
        or not S.Finite(info.stackCount) or info.stackCount <= 0 or not S.Finite(info.numAvailable)
        or info.numAvailable == 0 then return end
    return id, info
end

local function MerchantRows(self)
    if not MerchantOpen(self) then return NO_OFFERS end
    local targets, ammo, slot = TargetQuantities(self)
    if not next(targets) then return NO_OFFERS end
    local _, bags, complete = Data.Bags()
    if ammo then
        local quantity = GetInventoryItemCount("player", slot)
        if S.Finite(quantity) then bags[ammo] = quantity else targets[ammo] = nil end
    end
    local count = GetMerchantNumItems()
    local rows = {}
    if not complete or not S.Finite(count) then return rows end
    for index = 1, math.min(count, 1000) do
        local id, offer = Offer(index, targets)
        local missing = id and math.max(0, (targets[id] or 0) - (bags[id] or 0)) or 0
        if missing > 0 then
            local name = S.PublicText(offer.name) or Data.Name(id)
            local price = S.Public(offer.hasExtendedCost) and offer.hasExtendedCost == false and S.Finite(offer.price) and offer.price
            local detail = price and S.Text("%d per pack · %s", true):format(offer.stackCount, S.MoneyText(price))
                or S.Text("%d per pack · see merchant offer", true):format(offer.stackCount)
            rows[#rows + 1] = { key = index, itemID = id, label = S.Text("%s — missing %d"):format(name, missing),
                detail = detail }
        end
    end
    return rows
end

local function OpenMerchant(self)
    if not MerchantOpen(self) then return end
    S.ToolListWindow.Open(self.merchantPreviewOwner, {
        title = "Missing stock at this merchant", rows = function() return self.merchantRows or NO_OFFERS end,
        valid = function() return MerchantOpen(self) end,
        empty = "This merchant has no items you need from your stock targets.",
        help = "Use the merchant window to buy items.",
        actions = { { label = "Back", run = function() self:Open() end } },
    })
end

local function HideMerchant(self)
    self.merchantRows = nil
    if self.merchantBadge then self.merchantBadge:Hide() end
    S.ToolListWindow.Close(self.merchantPreviewOwner)
end

local function PaintMerchant(self)
    if not MerchantOpen(self) then
        HideMerchant(self)
        return
    end
    local rows = MerchantRows(self)
    self.merchantRows = rows
    if not self.merchantBadge and #rows > 0 then
        local button = S.CreateFrame("Button", nil, MerchantFrame, "UIPanelButtonTemplate")
        button:SetSize(200, 22)
        button:SetPoint("TOPLEFT", MerchantFrameTab2 or MerchantFrame, "TOPRIGHT", 4, -3)
        button:SetScript("OnClick", function() OpenMerchant(self) end)
        self.merchantBadge = button
    end
    if self.merchantBadge then
        local first = rows[1]
        local label = #rows == 1 and first.label or S.Text("Missing stock (%d)"):format(#rows)
        self.merchantBadge:SetText(label)
        self.merchantBadge:SetShown(#rows > 0)
    end
end

local function MerchantTabChanged(self)
    if NS.InCombat() then return end
    PaintMerchant(self)
    S.ToolListWindow.Refresh(self.merchantPreviewOwner)
end

local function MerchantEvent(self, event)
    if event == "PLAYER_REGEN_DISABLED" or event == "MERCHANT_CLOSED" then
        for i = 1, #LIVE_EVENTS do self.context:RemoveEvent(LIVE_EVENTS[i]) end
        HideMerchant(self)
        return
    end
    if self.config.merchantPreview == false or NS.InCombat(event) then return end
    if event == "MERCHANT_SHOW" or event == "PLAYER_REGEN_ENABLED" then
        if not MerchantOpen(self) then return end
        for i = 1, #LIVE_EVENTS do self.context:Event(LIVE_EVENTS[i], MerchantEvent, IN_COMBAT) end
    end
    MerchantTabChanged(self)
end

function M:Open()
    S.ToolListWindow.Open(self, { title = "Stock targets", rows = M.Rows,
        help = "Missing amounts use your current bags. Bank amounts show the last archive snapshot and may have changed.",
        empty = "No stock targets yet. Choose Edit targets to add your consumables or materials.",
        actions = {
            { label = "Edit targets", run = function(owner) owner:Edit() end, drop = function(owner, id) owner:Edit(id) end },
            { label = "Refresh", run = function() S.ToolListWindow.Refresh(M) end },
        } })
end
function M:Refresh()
    if NS.InCombat() then return end
    if self.context and self.active and NS.Client.isForever then
        if self.config.merchantPreview == false then
            self.context:RemoveEvent("MERCHANT_SHOW")
            self.context:RemoveEvent("PLAYER_REGEN_ENABLED")
            MerchantEvent(self, "MERCHANT_CLOSED")
        else
            self.context:Event("MERCHANT_SHOW", MerchantEvent)
            self.context:Event("PLAYER_REGEN_ENABLED", MerchantEvent, IN_COMBAT)
            if MerchantOpen(self) then MerchantEvent(self, "MERCHANT_SHOW") end
        end
    end
    S.ToolListWindow.Refresh(self)
end
local function BagsChanged(self, event)
    if NS.InCombat(event) then return end
    S.ToolListWindow.Refresh(self)
    if MerchantOpen(self) then
        PaintMerchant(self)
        S.ToolListWindow.Refresh(self.merchantPreviewOwner)
    end
end
function M:Enable()
    self.context:Event("BAG_UPDATE_DELAYED", BagsChanged)
    if NS.Client.isForever then
        self.context:Callback("MerchantFrame.MerchantTabShow", MerchantTabChanged)
        self.context:Callback("MerchantFrame.BuyBackTabShow", MerchantTabChanged)
    end
    self:Refresh()
end
function M:Disable()
    HideMerchant(self)
    S.ToolListWindow.Close(self)
end
S.Install("restockPlanner", M)
