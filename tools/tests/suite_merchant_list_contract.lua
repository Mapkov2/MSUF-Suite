local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end

local templates = {}
local function Widget(parent)
    local w = { parent = parent, shown = true, alpha = 1, mouse = false, scripts = {}, points = {} }
    function w:SetScript(name, callback) self.scripts[name] = callback end
    function w:HookScript(name, callback)
        local old = self.scripts[name]
        self.scripts[name] = function(...) if old then old(...) end; callback(...) end
    end
    function w:Show()
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function w:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function w:SetShown(value) if value then self:Show() else self:Hide() end end
    function w:IsShown() return self.shown end
    function w:SetAlpha(value) self.alpha = value end
    function w:GetAlpha() return self.alpha end
    function w:EnableMouse(value) self.mouse = value end
    function w:IsMouseEnabled() return self.mouse end
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:ClearAllPoints() self.points = {} end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetFrameLevel(level) self.level = level end
    function w:GetFrameLevel() return self.level or 1 end
    function w:SetText(value) self.text = value end
    function w:SetTextColor(...) self.textColor = { ... } end
    function w:SetVertexColor(...) self.vertex = { ... } end
    function w:SetTexture(value) self.texture = value end
    function w:SetDesaturated(value) self.desaturated = value end
    function w:SetFont(...) self.font = { ... } end
    function w:SetMinMaxValues(low, high)
        self.low, self.high = low, high
        local value = math.max(low, math.min(high, self.value or 0))
        if value ~= self.value then self:SetValue(value) end
    end
    function w:SetValue(value)
        if value == self.value then return end
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    for _, name in ipairs({ "SetAllPoints", "SetColorTexture", "SetJustifyH", "SetWordWrap", "RegisterForClicks",
        "RegisterForDrag", "EnableMouseWheel", "SetOrientation", "SetThumbTexture", "SetValueStep",
        "SetObeyStepOnDrag" }) do
        w[name] = function() end
    end
    return w
end

-- Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua as far as the list
-- meets it: MerchantFrame_Update shows the page controls on the merchant
-- tab for more than ten offers and hides them on the buyback tab, which shows
-- MerchantItem11 and 12; it never shows MerchantItem1-10 themselves.
MERCHANT_ITEMS_PER_PAGE, MERCHANT_HIGH_PRICE_COST = 10, 1500000
MerchantFrame = Widget()
MerchantFrame.shown, MerchantFrame.selectedTab, MerchantFrame.page, MerchantFrame.level = false, 1, 1, 5
for i = 1, 12 do
    local item = Widget(MerchantFrame)
    item.ItemButton = Widget(item)
    item.ItemButton.mouse = true
    _G["MerchantItem" .. i], _G["MerchantItem" .. i .. "ItemButton"] = item, item.ItemButton
end
MerchantItem11.shown, MerchantItem12.shown = false, false
MerchantPrevPageButton, MerchantNextPageButton, MerchantPageText = Widget(MerchantFrame), Widget(MerchantFrame), Widget(MerchantFrame)
MerchantPrevPageButton.mouse, MerchantNextPageButton.mouse = true, true
local offers = 30
GetMerchantNumItems = function() return offers end
local nativeUpdates = 0
MerchantFrame_Update = function()
    nativeUpdates = nativeUpdates + 1
    local paged = MerchantFrame.selectedTab == 1 and offers > MERCHANT_ITEMS_PER_PAGE
    for _, control in ipairs({ MerchantPrevPageButton, MerchantNextPageButton, MerchantPageText }) do
        control:SetShown(paged)
    end
    MerchantItem11:SetShown(MerchantFrame.selectedTab == 2)
    MerchantItem12:SetShown(MerchantFrame.selectedTab == 2)
end
MerchantFrame:SetScript("OnShow", function() MerchantFrame_Update() end)
hooksecurefunc = function(name, callback)
    local original = _G[name]
    _G[name] = function(...) original(...); callback(...) end
end
local deferred = {}
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }
-- Every wait here is for the next frame; the frame clock stands still.
GetTime = function() return 100 end
local function RunFrame()
    local queue = deferred
    deferred = {}
    for _, callback in ipairs(queue) do callback() end
end
wipe = function(t) for key in pairs(t) do t[key] = nil end return t end

-- Offers: 1 an epic sword with an item level, 2 paid in a currency, 3 at a
-- high price and not refundable, 4 sold in stacks of 20, 5 still loading.
local loaded = { [5] = false }
local infoReads = 0
C_MerchantFrame = {
    GetItemInfo = function(index)
        infoReads = infoReads + 1
        if index > offers then return nil end
        local info = { name = "Offer " .. index, texture = 100 + index, price = 10, stackCount = 1, numAvailable = -1,
            isPurchasable = true, isUsable = true, hasExtendedCost = false, isQuestStartItem = false }
        if index == 1 then info.name = "Sword" end
        if index == 2 then info.price, info.hasExtendedCost = 0, true end
        if index == 3 then info.price = 2000000 end
        if index == 4 then info.stackCount = 20 end
        if index == 6 then info.isUsable, info.numAvailable = false, 3 end
        return info
    end,
    IsMerchantItemRefundable = function(index) return index ~= 3 end,
}
GetMerchantItemLink = function(index) if index <= offers then return "item:" .. index end end
GetMerchantItemID = function(index) return index end
GetMerchantItemCostInfo = function(index) return index == 2 and 1 or 0 end
GetMerchantItemCostItem = function(index, i) if index == 2 and i == 1 then return 777, 50, nil, "Valorstones" end end
GetMerchantItemMaxStack = function(index) return index == 4 and 200 or 1 end
CanAffordMerchantItem = function(index) return index ~= 3 end
GetMoney = function() return 1000000 end
local requests = {}
C_Item = {
    GetItemInfo = function(link)
        local id = tonumber(link:match("%d+"))
        if loaded[id] == false then return nil end
        return "Offer", link, id == 1 and 4 or 1
    end,
    IsEquippableItem = function(link) return link == "item:1" end,
    GetDetailedItemLevelInfo = function() return 600.4 end,
    GetItemCount = function() return 0 end,
    RequestLoadItemDataByID = function(id) requests[#requests + 1] = id end,
}
C_Heirloom = { IsItemHeirloom = function() return false end, PlayerHasHeirloom = function() return false end }
C_CurrencyInfo = { GetCoinTextureString = function(value) return value .. "c" end,
    GetCurrencyContainerInfo = function() return nil end }
CreateSimpleTextureMarkup = function(texture) return "|T" .. texture .. "|t" end
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [4] = { r = .64, g = .21, b = .93 } }
TEXTURE_ITEM_QUEST_BANG = "bang"
local bought, picked = {}, {}
BuyMerchantItem = function(index, quantity) bought[#bought + 1] = { index, quantity } end
PickupMerchantItem = function(index) picked[#picked + 1] = index end
local cursor, modifier, chatLink = nil, nil, false
GetCursorInfo = function() return cursor end
IsModifiedClick = function(kind) if kind then return modifier == kind end return modifier ~= nil end
HandleModifiedItemClick = function() return chatLink end
local tooltip = {}
GameTooltip = { SetOwner = function(_, owner) tooltip.owner = owner end,
    SetMerchantItem = function(_, index) tooltip.index = index end }
GameTooltip_ShowCompareItem = function() end
GameTooltip_HideResetCursor = function() end
SetCursor = function(kind) tooltip.cursor = kind end

-- StaticPopup_Show runs the dialog's OnShow; tests answer it.
StaticPopupDialogs = {}
local popups = {}
StaticPopup_Show = function(which, first, second, data)
    local edit = { text = "" }
    function edit:SetNumeric() end
    function edit:SetMaxLetters() end
    function edit:SetText(value) self.text = value end
    function edit:GetText() return self.text end
    function edit:HighlightText() end
    local dialog = { which = which, data = data, args = { first, second } }
    function dialog:GetEditBox() return edit end
    function dialog:Hide() popups[which] = nil end
    function edit:GetParent() return dialog end
    popups[which] = dialog
    local spec = StaticPopupDialogs[which]
    if spec.OnShow then spec.OnShow(dialog, data) end
    return dialog
end
StaticPopup_Hide = function(which) popups[which] = nil end
local function Accept(which)
    local dialog = assert(popups[which], "no " .. which .. " dialog")
    StaticPopupDialogs[which].OnAccept(dialog, dialog.data)
    popups[which] = nil
end

local S, modules, printed = { instances = {} }, {}, {}
S.Public = function(value) return value ~= "secret" end
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Text = function(value) return value end
S.BlizzardText = function(_, fallback) return fallback end
S.SetFont = function(w, ...) w:SetFont(...) end
S.Dispatch = function(callback, ...) return callback(...) end
S.CreateFrame = function(_, _, parent, template)
    templates[#templates + 1] = template or false
    return Widget(parent)
end
S.CreateTexture = function(parent) return Widget(parent) end
S.CreateFontString = S.CreateTexture
S.Install = function(id, module) modules[id] = module end
local combat = false
local NS = { Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return combat end,
    Print = function(text) printed[#printed + 1] = text end, Dispatch = S.Dispatch }
-- S.Debounce and the context timers (MSUF_Suite_Modules/Timers.lua).
local TimerContext = dofile(root .. "/tools/tests/suite_test_support.lua").ModuleTimers(root, S, NS)
-- Context:HideControl as MSUF_Suite_Modules/Runtime.lua runs it: alpha and
-- mouse are recorded and restored, never Show/Hide; in combat it only queues.
local queued = false
local function Context()
    local context = { events = {}, records = {} }
    function context:Event(name, callback) self.events[name] = callback end
    function context:RemoveEvent(name) self.events[name] = nil end
    function context:HideControl(frame, hidden)
        local record = self.records[frame]
        if hidden then
            if combat then queued = true return end
            if not record then self.records[frame] = { alpha = frame:GetAlpha(), mouse = frame:IsMouseEnabled() } end
            frame:SetAlpha(0)
            frame:EnableMouse(false)
        elseif record then
            frame:SetAlpha(record.alpha)
            frame:EnableMouse(record.mouse)
            self.records[frame] = nil
        end
    end
    return context
end
for _, file in ipairs({ "MerchantWatch", "SharedItems", "MerchantList" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("test", { NS = NS, Suite = S })
end
local list = modules.merchantList
list.active, list.context, list.config = true, TimerContext("merchantList", list, Context()), { rowHeight = 44 }
list:Enable()
Check(not list.panel or not list.panel.shown, "the list showed without an open merchant")

------------------------------------------------------------------ merchant tab
MerchantFrame:Show()
local panel = list.panel
Check(panel and panel.shown and panel.parent == MerchantFrame, "opening the merchant did not show the list")
for _, template in ipairs(templates) do
    Check(template ~= "MerchantItemTemplate", "the list built Blizzard's merchant item rows from addon code")
end
Check(MerchantItem1.shown and MerchantItem1.alpha == 0 and MerchantPrevPageButton.shown
    and MerchantPrevPageButton.alpha == 0 and not MerchantPrevPageButton.mouse,
    "Blizzard's offers and page buttons were hidden instead of faded under the list")
Check(panel.mouse and panel.level > MerchantItem1ItemButton:GetFrameLevel(),
    "the faded offers can still be reached by the mouse")
local rows = list.rows
Check(#rows == 6 and rows[1].index == 1 and rows[6].index == 6 and panel.bar.high == 24,
    "the list does not fit six of thirty offers with a scroll range of 24")
Check(rows[1].name.text == "Sword" and rows[1].name.textColor[1] == .64 and rows[1].border.shown,
    "the epic offer lost its quality colour")
Check(rows[1].cost.text == "10c" and rows[2].cost.text == "50 |T777|t" and rows[3].cost.textColor[1] == .6,
    "prices, currency costs or the unaffordable shade are wrong")
Check(rows[6].icon.vertex[1] == .9 and rows[6].icon.vertex[2] == 0 and rows[6].stock.text == "(3)",
    "an unusable offer was not tinted red or lost its stock")
Check(not rows[1].level.shown, "item levels showed without the merchant item level module")
Check(requests[1] == 5 and list.context.events.GET_ITEM_INFO_RECEIVED, "a loading offer was not requested")

-- Bursts of Blizzard updates (bag and currency changes) repaint once.
local reads = infoReads
for _ = 1, 5 do MerchantFrame_Update() end
Check(infoReads == reads and #deferred == 1, "merchant updates were not coalesced")
RunFrame()
Check(infoReads == reads + 6, "the coalesced repaint did not repaint the visible rows once")
-- A repaint reads item and currency costs only for the offer paid with them.
local costReads, costInfo = {}, GetMerchantItemCostInfo
GetMerchantItemCostInfo = function(index) costReads[#costReads + 1] = index; return costInfo(index) end
MerchantFrame_Update()
RunFrame()
Check(#costReads == 1 and costReads[1] == 2 and rows[1].cost.text == "10c" and rows[2].cost.text == "50 |T777|t",
    "a repaint read the item and currency costs of gold offers")
GetMerchantItemCostInfo = costInfo
loaded[5] = true
for _ = 1, 3 do list.context.events.GET_ITEM_INFO_RECEIVED(list, "GET_ITEM_INFO_RECEIVED", 5) end
Check(#deferred == 1, "item data arrivals were not coalesced")
RunFrame()
Check(rows[5].name.textColor[1] == 1 and not list.context.events.GET_ITEM_INFO_RECEIVED,
    "the loaded offer did not repaint or its event stayed registered")

-- Item levels from the merchant item level module.
S.instances.merchantLevel = { active = true }
list:Refresh()
Check(rows[1].level.shown and rows[1].level.text == 600 and not rows[2].level.shown,
    "the list did not show the item level of equipment")

-- Scrolling.
panel.scripts.OnMouseWheel(panel, -1)
Check(rows[1].index == 2 and panel.bar.value == 1, "the mouse wheel did not scroll by one offer")
panel.bar:SetValue(24)
Check(rows[1].index == 25 and rows[6].index == 30, "the scroll bar did not reach the last offers")
panel.scripts.OnMouseWheel(panel, -1)
Check(rows[1].index == 25, "the list scrolled past its last offer")
panel.bar:SetValue(0)

------------------------------------------------------------------ buying
local function Click(index, button)
    local row = rows[index]
    row.scripts.OnClick(row, button)
end
Click(1, "RightButton")
Check(bought[1][1] == 1 and bought[1][2] == nil, "a right click did not buy the offer")
Click(1, "LeftButton")
Check(picked[1] == 1 and #bought == 1, "a left click did not pick the offer up")
Click(2, "RightButton")
Check(#bought == 1 and popups.MSUF_SUITE_MERCHANT_BUY
    and popups.MSUF_SUITE_MERCHANT_BUY.args[1] == "Buy item:2 for 50 |T777|t Valorstones?",
    "a currency purchase did not ask first")
Accept("MSUF_SUITE_MERCHANT_BUY")
Check(bought[2][1] == 2, "the confirmed currency purchase was not bought")
Click(2, "LeftButton")
Check(#picked == 1 and popups.MSUF_SUITE_MERCHANT_BUY, "a left click picked up an offer that needs a confirmation")
offers = 1
Accept("MSUF_SUITE_MERCHANT_BUY")
Check(#bought == 2 and printed[1], "a confirmation answered after the stock changed bought something")
offers = 30
MerchantFrame_Update()
Click(3, "RightButton")
local text = popups.MSUF_SUITE_MERCHANT_BUY.args[1]
Check(text:find("2000000c", 1, true) and text:find("cannot be refunded", 1, true),
    "a high price purchase did not ask or did not name that it cannot be refunded")
popups.MSUF_SUITE_MERCHANT_BUY = nil
modifier = "SPLITSTACK"
Click(4, "LeftButton")
local quantity = popups.MSUF_SUITE_MERCHANT_QUANTITY
Check(quantity and quantity.args[2] == 200 and quantity:GetEditBox():GetText() == "20",
    "Shift-click did not ask for a quantity up to the affordable stack limit")
quantity:GetEditBox():SetText("45")
Accept("MSUF_SUITE_MERCHANT_QUANTITY")
Check(bought[3][1] == 4 and bought[3][2] == 40, "the quantity was not bought in whole stacks")
chatLink = true
Click(4, "LeftButton")
Check(not popups.MSUF_SUITE_MERCHANT_QUANTITY, "a linked offer still asked for a quantity")
modifier, chatLink = nil, false
-- An item from the bags on the cursor is sold by a click or a drop on the
-- list, never bought against; a refundable one asks to be refunded instead,
-- as Blizzard's merchant window does.
local purchase, refunds, cleared, cursorItem = nil, {}, 0, nil
C_Cursor = { GetCursorItem = function() return cursorItem end }
C_Container = {
    GetContainerItemPurchaseInfo = function() return purchase end,
    GetContainerItemLink = function() return "bagitem" end,
    ContainerRefundItemPurchase = function(bag, slot, equipped) refunds[#refunds + 1] = { bag, slot, equipped } end,
}
ClearCursor = function() cleared = cleared + 1 end
cursor = "item"
cursorItem = { IsBagAndSlot = function() return true end, GetBagAndSlot = function() return 0, 3 end,
    IsEquipmentSlot = function() return false end }
Click(1, "LeftButton")
Check(#bought == 3 and #picked == 2 and picked[2] == 0, "a click with a bag item did not sell it")
panel.scripts.OnReceiveDrag(panel)
Check(#picked == 3 and picked[3] == 0 and #bought == 3, "dropping a bag item on the list did not sell it")
purchase = { refundSeconds = 3600, money = 5000, itemCount = 0, currencyCount = 0 }
Click(2, "RightButton")
Check(#picked == 3 and #bought == 3 and popups.MSUF_SUITE_MERCHANT_REFUND
    and popups.MSUF_SUITE_MERCHANT_REFUND.args[1] == "bagitem", "a refundable item was sold without asking")
Accept("MSUF_SUITE_MERCHANT_REFUND")
Check(refunds[1] and refunds[1][1] == 0 and refunds[1][2] == 3 and refunds[1][3] == false, "the accepted refund did not run")
panel.scripts.OnMouseUp(panel)
StaticPopupDialogs.MSUF_SUITE_MERCHANT_REFUND.OnCancel()
Check(cleared == 1 and #refunds == 1 and #picked == 3, "declining the refund did not put the item back")
popups.MSUF_SUITE_MERCHANT_REFUND = nil
cursor, cursorItem, purchase = nil, nil, nil
rows[1].scripts.OnEnter(rows[1])
Check(tooltip.owner == rows[1] and tooltip.index == 1 and tooltip.cursor == "BUY_CURSOR",
    "hovering an offer did not show its merchant tooltip")

------------------------------------------------------------------ buyback tab
MerchantFrame.selectedTab = 2
MerchantFrame_Update()
Check(not panel.shown and MerchantItem1.alpha == 1 and MerchantItem1ItemButton.mouse,
    "the buyback tab did not get Blizzard's offers back at once")
Check(not MerchantPrevPageButton.shown and not MerchantNextPageButton.shown and not MerchantPageText.shown
    and MerchantItem11.shown, "the page controls came back on the buyback tab")
MerchantFrame.selectedTab = 1
MerchantFrame_Update()
Check(panel.shown and MerchantItem1.alpha == 0, "the merchant tab did not take the list back")

------------------------------------------------------------------ closing, combat, disable
panel.bar:SetValue(3)
Click(2, "RightButton")
list.context.events.MERCHANT_CLOSED(list, "MERCHANT_CLOSED")
MerchantFrame:Hide()
Check(list.offset == 0 and not popups.MSUF_SUITE_MERCHANT_BUY and MerchantItem1.alpha == 1,
    "closing the merchant kept the scroll position, a dialog or the faded offers")
combat = true
MerchantFrame:Show()
Check(not panel.shown and MerchantItem1.alpha == 1, "a merchant opened in combat lost Blizzard's offers")
combat = false
list:Refresh()
Check(panel.shown and MerchantItem1.alpha == 0, "the list did not take over after combat")
list.active = false
list:Disable()
Check(not panel.shown and MerchantItem1.alpha == 1 and MerchantPrevPageButton.alpha == 1
    and MerchantPrevPageButton.mouse, "disable did not hand Blizzard's offers back")
local before = infoReads
MerchantFrame.page = 2
MerchantFrame_Update()
RunFrame()
Check(infoReads == before and not panel.shown, "the stopped list still painted")
print("Merchant list: " .. checks .. " checks passed")
