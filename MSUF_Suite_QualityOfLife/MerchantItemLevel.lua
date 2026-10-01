local _, P = ...
local S = P.Suite

local ID = "merchantLevel"
local M = { labels = {}, requested = {} }

local function CancelPaint(self)
    local timer = self.paintTimer
    self.paintTimer = nil
    if timer then timer:Cancel() end
end

local function Hide(self)
    for _, label in pairs(self.labels) do label:Hide() end
end

local function Label(self, slot, button)
    local label = self.labels[slot]
    if label then return label end
    label = S.CreateFontString(button, nil, "OVERLAY")
    label:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    S.SetFont(label, nil, 10, "OUTLINE")
    label:SetTextColor(1, .88, .52)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    self.labels[slot] = label
    return label
end

local function ItemLoaded(self, _, itemID)
    if not S.Finite(itemID) or self.requested[itemID] ~= true then return end
    self.requested[itemID] = "done"
    -- Several visible items can finish loading in one frame. Repaint their
    -- page once, after the item events have been delivered.
    if self.paintTimer then return end
    local timer
    timer = C_Timer.NewTimer(0, function()
        if self.paintTimer ~= timer then return end
        self.paintTimer = nil
        self:Paint()
    end)
    self.paintTimer = timer
end

-- Asks the client once per merchant visit for an item's data; true while
-- the answer is still outstanding.
local function Request(self, itemID)
    if not S.Finite(itemID) or itemID <= 0 then return false end
    if not self.requested[itemID] then
        self.requested[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return self.requested[itemID] == true
end

function M:Paint()
    CancelPaint(self)
    local frame = MerchantFrame
    if not self.active or not self.open or not frame:IsShown() or frame.selectedTab ~= 1 then
        Hide(self)
        return
    end
    local count, page = GetMerchantNumItems(), frame.page
    if not S.Finite(count) or not S.Finite(page) then Hide(self) return end
    local perPage = MERCHANT_ITEMS_PER_PAGE
    local waiting = false
    for slot = 1, perPage do
        local index = (page - 1) * perPage + slot
        local link = index <= count and S.PublicText(GetMerchantItemLink(index))
        local level = link and S.MerchantOfferLevel(link)
        local label = self.labels[slot]
        if level then
            label = Label(self, slot, _G["MerchantItem" .. slot .. "ItemButton"])
            label:SetText(level)
            label:Show()
        else
            if label then label:Hide() end
            if level == false and Request(self, GetMerchantItemID(index)) then waiting = true end
        end
    end
    if waiting then
        self.context:Event("GET_ITEM_INFO_RECEIVED", ItemLoaded)
    else
        self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function Updated(self)
    if self.open then self:Paint() end
end

local function OnMerchant(self, event)
    if event == "MERCHANT_CLOSED" then
        self.open = false
        CancelPaint(self)
        self.requested = {}
        self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
        Hide(self)
        return
    end
    self.open = true
    self:Paint()
end

-- The merchant list shows these levels on its own rows.
function M:Enable()
    self.open = MerchantFrame:IsShown()
    self.requested = {}
    self.context:Event("MERCHANT_SHOW", OnMerchant)
    self.context:Event("MERCHANT_CLOSED", OnMerchant)
    S.WatchMerchant(self, Updated)
    if self.open then self:Paint() end
    S.RepaintMerchant()
end

function M:Refresh()
    self:Paint()
end

function M:Disable()
    self.open = false
    CancelPaint(self)
    self.requested = {}
    Hide(self)
    S.UnwatchMerchant(self)
    S.RepaintMerchant()
end

S.Install(ID, M)
