local _, P = ...
local NS, S = P.NS, P.Suite

-- The merchant's whole stock as one scrolling list on the merchant tab. The
-- rows are Suite buttons that buy through the merchant API and ask before a
-- costly purchase themselves. Blizzard's offer frames and page controls stay
-- where they are, faded out under the list (Context:HideControl, never
-- Hide()), so the buyback tab and a stopped module get them back unchanged.
local M = { rows = {}, requests = S.QoLItemRequests(), offset = 0 }
-- MerchantFrame.xml: offers start 69 below the top, the page buttons sit
-- centred 96 above the bottom; the list covers both.
local LIST_TOP, LIST_WIDTH, LIST_HEIGHT = -64, 316, 300
local ROW_WIDTH, ICON = 304, 36
local MAX_COSTS = 3 -- MAX_ITEM_COST in MerchantFrame.lua
local CONFIRM, QUANTITY, REFUND = "MSUF_SUITE_MERCHANT_BUY", "MSUF_SUITE_MERCHANT_QUANTITY", "MSUF_SUITE_MERCHANT_REFUND"
local PAGE_CONTROLS = { "MerchantPrevPageButton", "MerchantNextPageButton", "MerchantPageText" }
local costParts = {}

local function Showing(self)
    return self.active and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1
end

local function LevelsShown()
    local levels = S.instances.merchantLevel
    return levels ~= nil and levels.active == true
end

local function Conceal(self, hidden)
    if self.concealed == hidden then return end
    local context = self.context
    for i = 1, MERCHANT_ITEMS_PER_PAGE do context:HideControl(_G["MerchantItem" .. i], hidden) end
    for _, name in ipairs(PAGE_CONTROLS) do context:HideControl(_G[name], hidden) end
    self.concealed = hidden
end

-- Gold and item or currency costs of stacks of an offer. Only an offer paid
-- with items or currencies (extended) has costs to read.
local function CostText(index, price, stacks, named, extended)
    wipe(costParts)
    if price > 0 then costParts[1] = C_CurrencyInfo.GetCoinTextureString(price * stacks) end
    local count = extended and GetMerchantItemCostInfo(index)
    for i = 1, S.Finite(count) and math.min(count, MAX_COSTS) or 0 do
        local texture, value, link, currency = GetMerchantItemCostItem(index, i)
        if texture and S.Finite(value) then
            local amount = string.format("%d %s", value * stacks, CreateSimpleTextureMarkup(texture, 0, 0))
            local label = named and (S.PublicText(currency) or S.PublicText(link))
            costParts[#costParts + 1] = label and string.format("%s %s", amount, label) or amount
        end
    end
    return table.concat(costParts, named and ", " or "  ")
end

------------------------------------------------------------------ buying
-- One purchase of quantity items (nil: one stack); nil when the offer is gone.
local function Offer(index, quantity)
    local info = C_MerchantFrame.GetItemInfo(index)
    if not S.Public(info) or type(info) ~= "table" then return nil end
    local stack = S.Finite(info.stackCount) and info.stackCount > 0 and info.stackCount or 1
    local stacks = (quantity or stack) / stack
    local price = S.Finite(info.price) and info.price or 0
    local costs = GetMerchantItemCostInfo(index)
    local extended = S.Finite(costs) and costs > 0
    return {
        index = index, quantity = quantity, amount = quantity or stack,
        link = S.PublicText(GetMerchantItemLink(index)), name = S.PublicText(info.name),
        gold = price * stacks, extended = extended,
        cost = CostText(index, price, stacks, true, extended),
        refundable = C_MerchantFrame.IsMerchantItemRefundable(index) == true,
    }
end

-- Purchases paid with items or currencies, or of at least Blizzard's high
-- price, ask first; Blizzard's own rows do the same.
local function NeedsConfirmation(offer)
    return offer.extended or offer.gold >= MERCHANT_HIGH_PRICE_COST
end

-- A dialog answered after the stock changed must not buy another offer.
local function StillOffered(offer)
    if not M.active or not MerchantFrame:IsShown() then return false end
    local info = C_MerchantFrame.GetItemInfo(offer.index)
    local same = S.PublicText(GetMerchantItemLink(offer.index)) == offer.link
        and S.Public(info) and type(info) == "table" and S.PublicText(info.name) == offer.name
    if not same then NS.Print(S.Text("The merchant's offers changed; nothing was bought.")) end
    return same
end

-- The questions are Blizzard's generic dialogs (S.Confirm and S.AskText,
-- MSUF_Suite_Modules/Dialogs.lua).
local function ConfirmPurchase(offer)
    local item = offer.link or offer.name or ""
    if offer.amount > 1 then item = string.format("%dx %s", offer.amount, item) end
    local text = string.format(S.Text("Buy %s for %s?"), item, offer.cost)
    if not offer.refundable then text = text .. "\n\n" .. S.Text("This purchase cannot be refunded.") end
    S.Confirm(CONFIRM, {
        text = "%s", text_arg1 = text,
        acceptText = S.BlizzardText("YES", "Yes"), cancelText = S.BlizzardText("NO", "No"),
        showAlert = true,
        callback = function()
            if StillOffered(offer) then BuyMerchantItem(offer.index, offer.quantity) end
        end,
    })
end

local function Purchase(index, quantity, pickup)
    local offer = Offer(index, quantity)
    if not offer then return end
    if NeedsConfirmation(offer) then
        ConfirmPurchase(offer)
    elseif pickup then
        PickupMerchantItem(index)
    else
        BuyMerchantItem(index, quantity)
    end
end

-- How many items of one offer the money and carried cost items pay for,
-- the way MerchantItemButton_OnModifiedClick counts them.
local function Affordable(index, info, most)
    local stack = S.Finite(info.stackCount) and info.stackCount > 0 and info.stackCount or 1
    local limit = most
    if S.Finite(info.price) and info.price > 0 then limit = math.floor(GetMoney() / (info.price / stack)) end
    local count = GetMerchantItemCostInfo(index)
    for i = 1, S.Finite(count) and math.min(count, MAX_COSTS) or 0 do
        local _, value, link, currency = GetMerchantItemCostItem(index, i)
        if link and not currency and S.Finite(value) and value > 0 then
            local carried = C_Item.GetItemCount(link, false, false, true)
            limit = math.min(limit, math.floor(carried / (value / stack)))
        end
    end
    return math.min(limit, most), stack
end

-- Whole stacks only, never more than the dialog offered.
local function QuantityAccepted(data, text)
    local amount = tonumber(text)
    if not amount or not StillOffered(data.offer) then return end
    amount = math.floor(math.min(amount, data.limit) / data.stack) * data.stack
    if amount >= data.stack then Purchase(data.index, amount, false) end
end

-- The edit box belongs to Blizzard's shared dialog frame, whose own code
-- never makes it numeric: the next dialog gets it back as it was.
local function QuantityHidden(dialog)
    dialog:GetEditBox():SetNumeric(false)
end

local function AskQuantity(index)
    local most = GetMerchantItemMaxStack(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    if not S.Finite(most) or most <= 1 or not S.Public(info) or type(info) ~= "table" then return end
    local limit, stack = Affordable(index, info, most)
    if limit < stack then return end
    local data = { index = index, stack = stack, limit = limit, offer = Offer(index) }
    data.text = S.Text("Buy how many %s? You can buy up to %d.")
    data.text_arg1, data.text_arg2 = data.offer.link or data.offer.name or "", limit
    data.acceptText, data.cancelText = S.BlizzardText("ACCEPT", "Accept"), S.BlizzardText("CANCEL", "Cancel")
    data.maxLetters = 5
    data.callback = function(text) QuantityAccepted(data, text) end
    local dialog = S.AskText(QUANTITY, data, QuantityHidden)
    if not dialog then return end
    local edit = dialog:GetEditBox()
    edit:SetNumeric(true)
    edit:SetText(tostring(stack))
    edit:HighlightText()
end

------------------------------------------------------------------ selling
-- The bag or equipment slot of the item on the cursor (C_Cursor.GetCursorItem).
local function CursorSlot()
    local location = C_Cursor.GetCursorItem()
    if not location then return end
    if location:IsBagAndSlot() then
        local bag, slot = location:GetBagAndSlot()
        return bag, slot, false
    end
    if location:IsEquipmentSlot() then return 0, location:GetEquipmentSlot(), true end
end

-- An item still refundable, the way ContainerFrame_GetExtendedPriceString
-- decides it: a refund time and a price in gold, items or currencies.
local function Refundable(bag, slot, equipped)
    local info = C_Container.GetContainerItemPurchaseInfo(bag, slot, equipped)
    if not S.Public(info) or type(info) ~= "table" or not S.Finite(info.refundSeconds) then return false end
    return (S.Finite(info.money) and info.money > 0) or (S.Finite(info.itemCount) and info.itemCount > 0)
        or (S.Finite(info.currencyCount) and info.currencyCount > 0)
end

-- Declining keeps the item, as Blizzard's dialog does: it leaves the cursor.
local function Declined()
    ClearCursor()
end

-- An item dropped or clicked onto the list is sold, as on Blizzard's rows
-- (PickupMerchantItem with an item on the cursor); a refundable one asks
-- first and is refunded (C_Container.ContainerRefundItemPurchase), the
-- choice Blizzard's own merchant window offers.
local function SellCursorItem()
    if not Showing(M) or GetCursorInfo() ~= "item" then return end
    local bag, slot, equipped = CursorSlot()
    if not slot or not Refundable(bag, slot, equipped) then
        PickupMerchantItem(0)
        return
    end
    local link = equipped and GetInventoryItemLink("player", slot) or C_Container.GetContainerItemLink(bag, slot)
    S.Confirm(REFUND, {
        text = S.Text("Refund %s for its purchase price?"), text_arg1 = S.PublicText(link) or "",
        acceptText = S.BlizzardText("YES", "Yes"), cancelText = S.BlizzardText("NO", "No"),
        callback = function()
            if M.active and MerchantFrame:IsShown() then
                C_Container.ContainerRefundItemPurchase(bag, slot, equipped)
            end
        end,
        cancelCallback = Declined,
    })
end

local function HidePopups()
    S.HideQuestion(CONFIRM)
    S.HideQuestion(QUANTITY)
    S.HideQuestion(REFUND)
end

------------------------------------------------------------------ rows
-- Right click buys, left click picks the offer up (and asks first where a
-- purchase needs a confirmation), modified clicks link, preview or ask for a
-- quantity. With an item on the cursor a click sells it (SellCursorItem).
local function RowClick(row, button)
    local index = row.index
    if not index or not Showing(M) then return end
    if IsModifiedClick() then
        if row.link and HandleModifiedItemClick(row.link) then return end
        if IsModifiedClick("SPLITSTACK") then AskQuantity(index) end
        return
    end
    if GetCursorInfo() then
        SellCursorItem()
        return
    end
    Purchase(index, nil, button == "LeftButton")
end

local function RowDrag(row)
    RowClick(row, "LeftButton")
end

local function RowEnter(row)
    if not row.index or NS.Safety.IsForbidden(GameTooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetMerchantItem(row.index)
    GameTooltip_ShowCompareItem(GameTooltip)
    SetCursor(CanAffordMerchantItem(row.index) == false and "BUY_ERROR_CURSOR" or "BUY_CURSOR")
end

-- OnLeave hides the shared tooltip only while this row still owns it.
local function RowLeave(row)
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    ResetCursor()
end

local function Text(parent, size, justify)
    local text = S.CreateFontString(parent, nil, "OVERLAY")
    S.SetFont(text, nil, size, "OUTLINE")
    text:SetJustifyH(justify or "LEFT")
    return text
end

local function IconTexture(row, layer, path)
    local texture = S.CreateTexture(row, nil, layer)
    texture:SetSize(ICON, ICON)
    texture:SetPoint("LEFT", row, "LEFT", 4, 0)
    if path then texture:SetTexture(path) end
    return texture
end

local function NewRow(panel)
    local row = S.CreateFrame("Button", nil, panel)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")
    local highlight = S.CreateTexture(row, nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, .08)
    row.icon = IconTexture(row, "ARTWORK")
    row.border = IconTexture(row, "OVERLAY", "Interface\\Common\\WhiteIconFrame")
    row.quest = IconTexture(row, "OVERLAY", TEXTURE_ITEM_QUEST_BANG)
    row.count = Text(row, 10, "RIGHT")
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 2)
    row.stock = Text(row, 10)
    row.stock:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 1, -1)
    row.level = Text(row, 10)
    row.level:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMLEFT", 2, 2)
    row.level:SetTextColor(1, .88, .52)
    row.name = Text(row, 12)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.name:SetWordWrap(false)
    row.cost = Text(row, 10)
    row.cost:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
    row.cost:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnDragStart", RowDrag)
    row:SetScript("OnReceiveDrag", SellCursorItem)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    return row
end

-- Blizzard's tints: red for what the player cannot buy or use, dimmed for
-- sold out offers and heirlooms already collected.
local function Tint(row, info, heirloom, known, available)
    local red = info.isPurchasable ~= true or (info.isUsable ~= true and not heirloom)
    if (available == 0 or known) and red then
        row.icon:SetVertexColor(.5, 0, 0)
    elseif available == 0 or known then
        row.icon:SetVertexColor(.5, .5, .5)
    elseif red then
        row.icon:SetVertexColor(.9, 0, 0)
    else
        row.icon:SetVertexColor(1, 1, 1)
    end
    row.icon:SetDesaturated(known)
end

-- Name and border in the item's quality color; true while it still loads.
local function Quality(row, link)
    local quality = link and select(3, C_Item.GetItemInfo(link))
    local color = S.Finite(quality) and ITEM_QUALITY_COLORS[quality]
    if color then
        row.name:SetTextColor(color.r, color.g, color.b)
        row.border:SetVertexColor(color.r, color.g, color.b)
    else
        row.name:SetTextColor(1, .82, 0)
    end
    row.border:SetShown(color and true or false)
    return link ~= nil and quality == nil
end

-- Fills one row; returns the item ID whose data the client still loads.
local function Fill(row, index, info)
    local name, texture, available = info.name, info.texture, info.numAvailable
    if info.currencyID then
        local entry = C_CurrencyInfo.GetCurrencyContainerInfo(info.currencyID, available)
        if entry then name, texture, available = entry.name, entry.icon, entry.displayAmount end
    end
    local link, itemID = S.PublicText(GetMerchantItemLink(index)), GetMerchantItemID(index)
    row.index, row.link = index, link
    row.icon:SetTexture(texture)
    row.name:SetText(S.PublicText(name) or "")
    local stack = S.Finite(info.stackCount) and info.stackCount or 1
    row.count:SetText(stack > 1 and stack or "")
    row.stock:SetText(S.Finite(available) and available > 0 and string.format("(%d)", available) or "")
    local extended = S.Public(info.hasExtendedCost) and info.hasExtendedCost == true
    row.cost:SetText(CostText(index, S.Finite(info.price) and info.price or 0, 1, false, extended))
    local shade = CanAffordMerchantItem(index) == false and .6 or 1
    row.cost:SetTextColor(shade, shade, shade)
    row.quest:SetShown(info.isQuestStartItem == true)
    local heirloom = S.Finite(itemID) and C_Heirloom.IsItemHeirloom(itemID) == true
    Tint(row, info, heirloom, heirloom and C_Heirloom.PlayerHasHeirloom(itemID) == true, available)
    local loading = Quality(row, link)
    local level
    if link and LevelsShown() then level = S.MerchantOfferLevel(link) end
    row.level:SetText(level or "")
    row.level:SetShown(level and true or false)
    row:Show()
    if loading or level == false then return itemID end
end

------------------------------------------------------------------ list
-- Item data that arrives in one frame repaints the list once (self.repaint).
local function ItemLoaded(self, _, itemID)
    if not self.requests:Arrived(itemID) then return end
    self.repaint:Request()
end

local function Scroll(offset)
    offset = math.max(0, math.min(M.most or 0, offset))
    if offset == M.offset then return end
    M.offset = offset
    M:Paint()
end

local function BarMoved(_, value)
    if not M.layingOut then Scroll(math.floor(value + .5)) end
end

local function Wheel(_, delta)
    Scroll(M.offset - delta)
end

local function Build(self)
    if self.panel then return self.panel end
    local panel = S.CreateFrame("Frame", nil, MerchantFrame)
    panel:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", 8, LIST_TOP)
    panel:SetSize(LIST_WIDTH, LIST_HEIGHT)
    panel:SetFrameLevel(MerchantFrame:GetFrameLevel() + 20)
    -- The mouse over the faded offers and page buttons reaches the list only.
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", Wheel)
    panel:SetScript("OnMouseUp", SellCursorItem)
    panel:SetScript("OnReceiveDrag", SellCursorItem)
    local bar = S.CreateFrame("Slider", nil, panel)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    bar:SetSize(8, LIST_HEIGHT)
    local track = S.CreateTexture(bar, nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, .35)
    local thumb = S.CreateTexture(bar, nil, "OVERLAY")
    thumb:SetSize(8, 28)
    thumb:SetColorTexture(.8, .68, .42, .9)
    bar:SetThumbTexture(thumb)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    bar:SetScript("OnValueChanged", BarMoved)
    panel.bar = bar
    panel:Hide()
    self.panel = panel
    return panel
end

-- Rows for the current row height; returns how many fit.
local function Layout(self, count)
    local height = self.config.rowHeight
    local visible = math.floor(LIST_HEIGHT / height)
    for i = #self.rows + 1, visible do self.rows[i] = NewRow(self.panel) end
    if self.laidOut ~= height then
        for i, row in ipairs(self.rows) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.panel, "TOPLEFT", 0, -(i - 1) * height)
            row:SetSize(ROW_WIDTH, height - 2)
        end
        self.laidOut = height
    end
    self.most = math.max(0, count - visible)
    self.offset = math.min(self.offset, self.most)
    local bar = self.panel.bar
    self.layingOut = true
    bar:SetMinMaxValues(0, self.most)
    bar:SetValue(self.offset)
    self.layingOut = nil
    bar:SetShown(self.most > 0)
    return visible
end

local function Leave(self)
    Conceal(self, false)
    if self.panel then self.panel:Hide() end
end

-- The list needs the faded offers; in combat it does not take them over.
function M:Paint()
    local count = Showing(self) and GetMerchantNumItems()
    if not S.Finite(count) or (not self.concealed and NS.IsCombatLocked()) then
        Leave(self)
        return
    end
    local panel = Build(self)
    Conceal(self, true)
    local visible = Layout(self, count)
    local waiting = false
    for i, row in ipairs(self.rows) do
        local index = self.offset + i
        local info = i <= visible and index <= count and C_MerchantFrame.GetItemInfo(index)
        if S.Public(info) and type(info) == "table" then
            local loading = Fill(row, index, info)
            -- Asked once per merchant visit; true while the answer is open.
            if loading and self.requests:Request(loading) then waiting = true end
        else
            row.index, row.link = nil, nil
            row:Hide()
        end
    end
    if waiting then
        self.context:Event("GET_ITEM_INFO_RECEIVED", ItemLoaded)
    else
        self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
    end
    panel:Show()
end

local function Closed(self)
    self.offset = 0
    self.repaint:Clear()
    self.requests:Reset()
    self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
    HidePopups()
    Leave(self)
end

function M:Enable()
    self.repaint = self.context:Coalesce(0, M.Paint)
    self.offset = 0
    self.context:Event("MERCHANT_CLOSED", Closed)
    S.WatchMerchant(self, self.Paint)
    self:Paint()
end

function M:Refresh()
    self:Paint()
end

function M:Disable()
    S.UnwatchMerchant(self)
    Closed(self)
end

S.Install("merchantList", M)
