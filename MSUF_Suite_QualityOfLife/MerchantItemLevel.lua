local _, P = ...
local NS, S = P.NS, P.Suite

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

function M:Paint()
    CancelPaint(self)
    local frame = _G.MerchantFrame
    if not self.active or not self.open or not frame or NS.Safety.IsForbidden(frame)
        or not frame:IsShown() or frame.selectedTab ~= 1 then
        Hide(self)
        return
    end
    local count, page = GetMerchantNumItems(), frame.page
    if not S.Finite(count) or not S.Finite(page) then Hide(self) return end
    local perPage = MERCHANT_ITEMS_PER_PAGE
    if not S.Finite(perPage) or perPage < 1 then perPage = 10 end
    perPage = math.min(perPage, 20)
    local waiting = false
    for slot = 1, perPage do
        local button = _G["MerchantItem" .. slot .. "ItemButton"]
        local label = self.labels[slot]
        local index = (page - 1) * perPage + slot
        if index <= count and button and not NS.Safety.IsForbidden(button) then
            local link = S.PublicText(GetMerchantItemLink(index))
            if link then
                local equippable = C_Item.IsEquippableItem(link)
                if S.Public(equippable) and equippable == true then
                    local level = C_Item.GetDetailedItemLevelInfo(link)
                    if S.Finite(level) and level > 0 then
                        Label(self, slot, button):SetText(math.floor(level))
                        self.labels[slot]:Show()
                    else
                        if label then label:Hide() end
                        local itemID = GetMerchantItemID(index)
                        if S.Finite(itemID) and itemID > 0 and not self.requested[itemID] then
                            self.requested[itemID] = true
                            C_Item.RequestLoadItemDataByID(itemID)
                        end
                        if S.Finite(itemID) and self.requested[itemID] == true then waiting = true end
                    end
                elseif label then
                    label:Hide()
                end
            elseif label then
                label:Hide()
            end
        elseif label then
            label:Hide()
        end
    end
    if waiting then
        self.context:Event("GET_ITEM_INFO_RECEIVED", ItemLoaded)
    else
        self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function Updated()
    if M.active and M.open then M:Paint() end
end

local function EnsureHook(self)
    if self.hooked or type(_G.MerchantFrame_Update) ~= "function" then return end
    hooksecurefunc("MerchantFrame_Update", Updated)
    self.hooked = true
    self.context:RemoveEvent("ADDON_LOADED")
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
    EnsureHook(self)
    self:Paint()
end

local function OnAddon(self, _, addon)
    if addon == "Blizzard_UIPanels_Game" then EnsureHook(self) end
end

function M:Enable()
    self.open = false
    self.requested = {}
    self.context:Event("MERCHANT_SHOW", OnMerchant)
    self.context:Event("MERCHANT_CLOSED", OnMerchant)
    EnsureHook(self)
    if not self.hooked then self.context:Event("ADDON_LOADED", OnAddon) end
    local frame = _G.MerchantFrame
    if frame and not NS.Safety.IsForbidden(frame) and frame:IsShown() then
        self.open = true
        self:Paint()
    end
end

function M:Refresh()
    self:Paint()
end

function M:Disable()
    self.open = false
    CancelPaint(self)
    self.requested = {}
    Hide(self)
end

S.Install(ID, M)
