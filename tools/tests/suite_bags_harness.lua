-- Offline client model for the Bags contracts (not a test itself). New()
-- loads the Suite core helpers, the shared runtime and the FULL Bags TOC into
-- a world that behaves like the live and Forever UI source in the points the
-- module depends on:
--   * Blizzard's combined bag fills self.Items from bag 4 down to 0 and slot N
--     down to 1 (ContainerFrame.lua UpdateItemSlots) and lays the grid out from
--     the bottom right; a bag opened in combat rebuilds that native grid.
--   * PLAYER_REGEN_DISABLED is delivered before InCombatLockdown() turns true,
--     PLAYER_REGEN_ENABLED after it turned false; the player's combat flag
--     (UnitAffectingCombat) is already set in the first and clear in the second.
--   * GameTooltip_OnUpdate calls owner:UpdateTooltip() every 0.2 s; container
--     buttons rebuild the tooltip there (SetOwner + SetBagItem), and
--     TooltipDataProcessor post-calls run inside SetBagItem.
--   * Native code runs secure; addon code (Suite frames, post-hooks, timers)
--     runs insecure. Addon writes to StackSplitFrame or bank state, and
--     addon-driven Hide()/SetTab calls into Blizzard code, are recorded in
--     W.taint. Layout writes to Blizzard's bag frames from addon code during
--     combat lockdown are recorded in W.combatLayout.
local Support = dofile(arg[1] .. "/tools/tests/suite_test_support.lua")
local H = {}
local unpack = unpack
local KEY = 1000

local function Clear(t) for key in pairs(t) do t[key] = nil end end

---------------------------------------------------------------- Blizzard's frames
-- Blizzard's ContainerFrameItemButtonTemplate: its scripts are native code.
local function ItemButton(W, env, parent, index)
    local button = env.NewWidget("ItemButton", "ContainerFrameCombinedBagsItem" .. index, parent, true)
    button.guarded = true
    button.width, button.height = 37, 37
    button.Count = button:CreateFontString(nil, "ARTWORK")
    button.Count.shown = false
    button.Count.font = { "Fonts/ARIALN.TTF", 14, "OUTLINE,THICK" }
    button.icon = button:CreateTexture(nil, "BORDER")
    button.ItemSlotBackground = button:CreateTexture(nil, "BACKGROUND")
    button.emptyBackgroundAtlas = "bags-item-slot64"
    function button:GetBagID() return self.bagID end
    function button:HasItem() return self.hasItem end
    function button:SetItemButtonTexture(texture)
        if not texture then texture = self.emptyBackgroundAtlas or nil end
        self.icon:SetShown(texture ~= nil)
        self.icon.texture = texture
    end
    function button:Initialize(bag, slot)
        self.bagID = bag
        self:SetID(slot)
        self:Show()
    end
    -- ContainerFrameItemButtonMixin:OnUpdate, installed as UpdateTooltip.
    function button:UpdateTooltip()
        W.GameTooltip:SetOwner(self, "ANCHOR_NONE")
        C_NewItems.RemoveNewItem(self:GetBagID(), self:GetID())
        W.GameTooltip:SetBagItem(self:GetBagID(), self:GetID())
    end
    button.scripts.OnEnter = function(self) self:UpdateTooltip() end
    button.scripts.OnLeave = function() W.GameTooltip:Hide() end
    button.scripts.OnHide = function(self)
        if self.hasStackSplit == 1 then W.StackSplitFrame:Hide() end
    end
    -- ContainerFrameItemButton_OnClick: every left click closes the split window.
    button.scripts.OnClick = function(self, mouseButton)
        if W.modified == "SPLITSTACK" then
            local item = W.Item(self:GetBagID(), self:GetID())
            if not W.cursor and item and not item.locked and item.count > 1 then
                self.SplitStack = function(owner, split) C_Container.SplitContainerItem(owner:GetBagID(), owner:GetID(), split) end
                W.StackSplitFrame:OpenStackSplitFrame(item.count, self, "BOTTOMRIGHT", "TOPRIGHT")
            end
            return
        end
        if mouseButton == "LeftButton" then
            C_Container.PickupContainerItem(self:GetBagID(), self:GetID())
            W.StackSplitFrame:Hide()
        else
            C_Container.UseContainerItem(self:GetBagID(), self:GetID(), nil, BankFrame and BankFrame:GetActiveBankType())
            W.StackSplitFrame:Hide()
        end
    end
    return button
end

local function CombinedBag(W, env)
    local frame = env.NewWidget("Frame", "ContainerFrameCombinedBags", W.UIParent, true)
    frame.guarded = true
    frame.shown = false
    frame.Items, frame.pool, frame.width, frame.height = {}, {}, 400, 300
    frame.Bg, frame.NineSlice = frame:CreateTexture(), env.NewWidget("Frame", nil, frame, true)
    frame.PortraitContainer = env.NewWidget("Frame", nil, frame, true)
    frame.PortraitButton = env.NewWidget("Button", nil, frame, true)
    function frame.PortraitButton:IsMenuOpen() return self.menuOpen == true end
    function frame.PortraitButton:SetMenuOpen(value) self.menuOpen = value end
    frame.TitleContainer = env.NewWidget("Frame", nil, frame, true)
    frame.TitleContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -1)
    frame.TitleContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -1)
    function frame:SetTitleOffsets(left, right)
        self.TitleContainer:SetPoint("TOPLEFT", self, "TOPLEFT", left, -1)
        self.TitleContainer:SetPoint("TOPRIGHT", self, "TOPRIGHT", right or -24, -1)
    end
    frame.MoneyFrame = env.NewWidget("Frame", nil, frame, true)
    frame.MoneyFrame.height = 16
    frame.MoneyFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
    function frame:IsCombinedBagContainer() return true end
    function frame:GetBagSize()
        local size = 0
        for bag = 0, 4 do size = size + (W.sizes[bag] or 0) end
        return size
    end
    function frame:EnumerateValidItems()
        local index = 0
        return function()
            index = index + 1
            if index <= self:GetBagSize() then return index, self.Items[index] end
        end
    end
    -- UpdateItemSlots: bag 4 down to 0, slot N down to 1 (ContainerFrame.lua).
    function frame:UpdateItemSlots()
        for i = 1, #self.pool do self.pool[i].shown = false end
        Clear(self.Items)
        for bag = 4, 0, -1 do
            local size = W.sizes[bag] or 0
            for i = 1, size do
                local index = #self.Items + 1
                local button = self.pool[index] or ItemButton(W, env, self, index)
                self.pool[index] = button
                self.Items[index] = button
                button:Initialize(bag, size - i + 1)
            end
        end
    end
    function frame:UpdateItems()
        for _, button in self:EnumerateValidItems() do
            local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
            button.hasItem = info and info.iconFileID
            button:SetItemButtonTexture(info and info.iconFileID)
            W.SetItemButtonCount(button, info and info.stackCount)
            SetItemButtonDesaturated(button, info and info.isLocked)
            button.matchesSearch = not (info and info.isFiltered)
        end
    end
    -- AnchorUtil.GridLayout(BottomRightToTopLeft, 10 columns) from above the money row.
    function frame:UpdateItemLayout()
        local index = 0
        for _, button in self:EnumerateValidItems() do
            local column, row = index % 10, math.floor(index / 10)
            button:ClearAllPoints()
            button:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -7 - column * 42, 28 + row * 42)
            index = index + 1
        end
    end
    function frame:UpdateFrameSize()
        local rows = math.ceil(self:GetBagSize() / 10)
        self:SetSize(10 * 37 + 9 * 5 + 15, rows * 37 + (rows - 1) * 5 + 75 + 28)
    end
    return frame
end

local function ReagentBag(W, env)
    local frame = env.NewWidget("Frame", "ContainerFrame6", W.UIParent, true)
    frame.guarded, frame.shown, frame.width, frame.height = true, false, 180, 200
    frame.Bg, frame.NineSlice = frame:CreateTexture(), env.NewWidget("Frame", nil, frame, true)
    frame.PortraitContainer = env.NewWidget("Frame", nil, frame, true)
    frame.PortraitButton = env.NewWidget("Button", nil, frame, true)
    function frame.PortraitButton:IsMenuOpen() return false end
    frame.TitleContainer = env.NewWidget("Frame", nil, frame, true)
    function frame:SetTitleOffsets() end
    frame.Items = {}
    function frame:EnumerateValidItems() return ipairs(self.Items) end
    function frame:UpdateItems() end
    return frame
end

-- GameTooltip with GameTooltip_OnUpdate's 0.2 s owner refresh and the
-- TooltipDataProcessor post-calls of TooltipDataHandlerMixin.
local function Tooltip(W, env)
    local tip = env.NewWidget("GameTooltip", "GameTooltip", W.UIParent, true)
    tip.shown, tip.lines, tip.timer = false, {}, 0
    function tip:SetOwner(owner) self.owner, self.lines, self.timer = owner, {}, 0.2; self.shown = false end
    function tip:GetOwner() return self.owner end
    function tip:IsOwned(frame) return self.owner == frame end
    function tip:ClearLines() self.lines = {} end
    function tip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
    function tip:SetText(text) self.lines = { text } end
    function tip:NumLines() return #self.lines end
    function tip:SetBagItem(bag, slot)
        local item = W.Item(bag, slot)
        self:ClearLines()
        if not item then self:Hide(); return end
        self:AddLine(W.data[item.id] and W.data[item.id].name or ("Item " .. item.id))
        for _, fn in ipairs(W.postCalls[Enum.TooltipDataType.Item] or {}) do
            env.Insecure(fn, self, { type = Enum.TooltipDataType.Item, id = item.id })
        end
        self.shown = true
    end
    function tip:Has(text)
        for _, line in ipairs(self.lines) do if line == text or line:find(text, 1, true) then return true end end
        return false
    end
    -- GameTooltip_OnUpdate
    function tip:Advance(seconds)
        local step = 0.05
        while seconds > 0 do
            seconds = seconds - step
            self.timer = self.timer - step
            if self.timer <= 0 then
                self.timer = 0.2
                local owner = self.owner
                if self.shown and owner and owner.UpdateTooltip then W.Native(owner.UpdateTooltip, owner) end
            end
        end
    end
    TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
        W.postCalls[kind] = W.postCalls[kind] or {}
        table.insert(W.postCalls[kind], fn)
    end }
    return tip
end

-- StackSplitFrame (Blizzard_FrameXML StackSplitFrame.lua). Every field write
-- and every method call from addon code is recorded as taint.
local function StackSplit(W, env)
    local store = env.NewWidget("Frame", "StackSplitFrame", W.UIParent, true)
    store.shown, store.down = false, {}
    local proxy = setmetatable({}, {
        __index = store,
        __newindex = function(_, key, value)
            env.Taint("StackSplitFrame." .. tostring(key))
            store[key] = value
        end,
    })
    _G.StackSplitFrame = proxy
    local function Guard(name) env.Taint("StackSplitFrame:" .. name) end
    function store:OpenStackSplitFrame(maxStack, parent)
        Guard("OpenStackSplitFrame")
        if store.owner then store.owner.hasStackSplit = 0 end
        store.maxStack, store.owner, store.minSplit, store.split, store.typing = maxStack, parent, 1, 1, 0
        parent.hasStackSplit = 1
        store:ClearAllPoints()
        store:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, 0)
        store.shown = true
        env.RunScript(proxy, "OnShow")
    end
    function store:UpdateStackSplitFrame() Guard("UpdateStackSplitFrame") end
    function store:UpdateStackText() Guard("UpdateStackText") end
    function store:Hide()
        if not store.shown then return end
        Guard("Hide")
        store.shown = false
        for key in pairs(store.down) do
            if not W.secure then W.taint[#W.taint + 1] = "RunBinding(" .. key .. ", up)" end
            store.down[key] = nil
        end
        if store.owner then store.owner.hasStackSplit = 0 end
        env.RunScript(proxy, "OnHide")
    end
    -- The player's own input on the native window (secure).
    -- StackSplitMixin:OnChar / the arrow buttons end in UpdateStackText.
    function W.SplitType(amount)
        W.Native(function()
            store.split, store.typing = amount, 1
            proxy:UpdateStackText()
        end)
    end
    function W.SplitCancel() W.Native(function() proxy:Hide() end) end
    function W.SplitOkay()
        W.Native(function()
            store:Hide()
            if store.owner then store.owner.SplitStack(store.owner, store.split) end
        end)
    end
    function W.SplitHoldKey(key) store.down[key] = true end
    W.StackSplitStore = store
    return proxy
end

local function Bank(W, env)
    local bank = env.NewWidget("Frame", "BankFrame", W.UIParent, true)
    bank.shown, bank.width, bank.height = false, 738, 460
    bank:SetPoint("TOPLEFT", W.UIParent, "TOPLEFT", 20, -100)
    if env.forever then return bank end
    local panel = env.NewWidget("Frame", "BankPanel", bank, true)
    panel.width, panel.height, panel.bankType = 738, 460, Enum.BankType.Character
    panel:SetPoint("LEFT", bank, "LEFT", 0, 0)
    bank.BankPanel = panel
    bank.TabSystem = env.NewWidget("Frame", nil, bank, true)
    bank.TabSystem:SetPoint("TOPLEFT", bank, "BOTTOMLEFT", 22, 2)
    bank.TabSystem.width, bank.TabSystem.height = 300, 32
    local search = env.NewWidget("EditBox", "BankItemSearchBox", bank, true)
    search.width, search.height = 110, 20
    search:SetPoint("TOPRIGHT", bank, "TOPRIGHT", -56, -33)
    bank.BankItemSearchBox = search
    panel.AutoSortButton = env.NewWidget("Button", nil, panel, true)
    panel.AutoSortButton.width, panel.AutoSortButton.height = 28, 26
    panel.AutoSortButton:SetPoint("LEFT", search, "RIGHT", 8, -1)
    bank.TabIDToBankType = { [1] = Enum.BankType.Character, [2] = Enum.BankType.Account }
    function panel:GetActiveBankType() return self.bankType end
    function panel:SetBankType(kind) env.Taint("BankPanel:SetBankType"); self.bankType = kind end
    function panel:EnumerateValidItems() return function() end end
    function panel:UpdateSearchResults() end
    function panel:GenerateItemSlotsForSelectedTab() end
    function bank:SetTab(id)
        W.calls.setTab = W.calls.setTab + 1
        env.Taint("BankFrame:SetTab")
        self.BankPanel:SetBankType(self.TabIDToBankType[id])
    end
    -- TabSystemOwnerMixin: Blizzard's tab buttons select their tab
    -- (TabSystemButtonMixin:OnClick -> BankFrame:SetTab).
    bank.characterBankTabID, bank.accountBankTabID, bank.tabButtons = 1, 2, {}
    for id = 1, 2 do
        local button = env.NewWidget("Button", nil, bank.TabSystem, true)
        button.scripts.OnClick = function() bank:SetTab(id) end
        bank.tabButtons[id] = button
    end
    function bank:GetTabButton(id) return self.tabButtons[id] end
    function bank:GetActiveBankType() return self.BankPanel:IsShown() and self.BankPanel:GetActiveBankType() or nil end
    -- The bank tabs a test buys: W.bankTabs[type] = { { ID =, name = }, ... }.
    W.bankTabs = { [Enum.BankType.Character] = {}, [Enum.BankType.Account] = {} }
    C_Bank = {
        CanViewBank = function(kind) return (W.bankAccess or {})[kind] ~= false end,
        CanUseBank = function(kind) return (W.bankAccess or {})[kind] ~= false end,
        FetchPurchasedBankTabData = function(kind)
            local copy = {}
            for i, tab in ipairs(W.bankTabs[kind]) do copy[i] = { ID = tab.ID, name = tab.name } end
            return copy
        end,
    }
    -- BankItemButtonTemplate (BankPanelItemButtonMixin) for Suite-created buttons.
    W.templates.BankItemButtonTemplate = function(button)
        button.Count = button:CreateFontString()
        button.icon = button:CreateTexture()
        function button:Init(kind, tab, slot)
            self.bankType, self.bankTabID, self.containerSlotID = kind, tab, slot
            self:Refresh()
        end
        function button:GetBankTabID() return self.bankTabID end
        function button:GetContainerSlotID() return self.containerSlotID end
        function button:GetBankType() return self.bankType end
        function button:Refresh()
            self.itemInfo = C_Container.GetContainerItemInfo(self.bankTabID, self.containerSlotID)
            W.SetItemButtonCount(self, self.itemInfo and self.itemInfo.stackCount or 0)
        end
        function button:UpdateCooldown() self.cooldowns = (self.cooldowns or 0) + 1 end
        button.scripts.OnEnter = function(self)
            W.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            W.GameTooltip:SetBagItem(self:GetBankTabID(), self:GetContainerSlotID())
        end
        button.scripts.OnClick = function(self, mouseButton)
            -- BankPanelItemButtonMixin:OnClick reads the active bank type.
            if mouseButton == "LeftButton" then C_Container.PickupContainerItem(self.bankTabID, self.containerSlotID)
            else C_Container.UseContainerItem(self.bankTabID, self.containerSlotID) end
        end
    end
    BankPanelItemButtonMixin = { OnClick = function() error("BankPanelItemButtonMixin.OnClick called from addon code") end,
        OnDragStart = function() error("BankPanelItemButtonMixin.OnDragStart called from addon code") end,
        OnReceiveDrag = function() error("BankPanelItemButtonMixin.OnReceiveDrag called from addon code") end }
    return bank
end

function H.BuildClient(W, env)
    W.GameTooltip = Tooltip(W, env)
    W.StackSplitFrame = StackSplit(W, env)
    W.CF = CombinedBag(W, env)
    W.Reagent = ReagentBag(W, env)
    W.BankFrame = Bank(W, env)
    -- ContainerFrameSettingsManager:GetBagsShown caches the open bags in
    -- bagsShown; ContainerFrame_OnShow and ContainerFrame_OnHide mark it stale
    -- (OnHide also runs the anchor pass). A list rebuilt from addon code is
    -- tainted for Blizzard's later passes, so that rebuild is recorded.
    ContainerFrameSettingsManager = {}
    function ContainerFrameSettingsManager:MarkBagsShownDirty() self.bagsShown = nil end
    function ContainerFrameSettingsManager:GetBagsShown()
        if not self.bagsShown then
            env.Taint("ContainerFrameSettingsManager.bagsShown")
            local shown = {}
            for _, frame in ipairs({ W.CF, W.Reagent }) do
                if frame.shown then shown[#shown + 1] = frame end
            end
            self.bagsShown = shown
        end
        return self.bagsShown
    end
    for _, frame in ipairs({ W.CF, W.Reagent }) do
        frame.scripts.OnShow = function() ContainerFrameSettingsManager:MarkBagsShownDirty() end
        frame.scripts.OnHide = function()
            ContainerFrameSettingsManager:MarkBagsShownDirty()
            UpdateContainerFrameAnchors()
        end
    end
    for _, name in ipairs({ "MailFrame", "TradeFrame", "MerchantFrame" }) do
        local frame = env.NewWidget("Frame", name, W.UIParent, true)
        frame.shown = false
    end
    -- Blizzard_GuildBankUI loads on demand at the guild vault.
    function W.OpenGuildBank()
        if not _G.GuildBankFrame then
            local frame = env.NewWidget("Frame", "GuildBankFrame", W.UIParent, true)
            frame.shown = false
        end
        W.Native(function() GuildBankFrame:Show() end)
        W.Fire("GUILDBANKFRAME_OPENED")
    end
    function W.CloseGuildBank()
        W.Native(function() GuildBankFrame:Hide() end)
        W.Fire("GUILDBANKFRAME_CLOSED")
    end
    -- The player types into the bag search box (C_Container.SetItemSearch).
    function W.Search(match)
        for _, slots in pairs(W.items) do
            for _, item in pairs(slots) do item.filtered = match ~= nil and not match(item) end
        end
        W.Fire("INVENTORY_SEARCH_UPDATE")
    end
    -- UpdateContainerFrameAnchors: the first open bag sits at the bottom right.
    UpdateContainerFrameAnchors = function()
        W.anchorPasses = (W.anchorPasses or 0) + 1
        ContainerFrameSettingsManager:GetBagsShown()
        local frame = W.CF
        if frame.shown then
            frame:SetScale(W.nativeScale or 1)
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMRIGHT", W.UIParent, "BOTTOMRIGHT", -10, 85 / frame.scale)
        end
    end
    -- OpenAllBags -> ContainerFrame_GenerateFrame (native, also in combat).
    function W.OpenBags()
        W.Native(function()
            local frame = W.CF
            frame:UpdateItemSlots()
            frame:Show()
            frame:UpdateFrameSize()
            frame:UpdateItemLayout()
            frame:UpdateItems()
            UpdateContainerFrameAnchors()
        end)
    end
    function W.CloseBags() W.Native(function() W.CF:Hide() end) end
    -- BAG_UPDATE -> BagUpdaterFrame -> container:Update -> UpdateItems (native).
    function W.BagChanged(bag)
        W.Fire("BAG_UPDATE", bag)
        W.Fire("BAG_UPDATE_DELAYED")
        if W.CF.shown then W.Native(function() W.CF:UpdateItems() end) end
    end
    function W.Hover(button)
        W.Native(function() button.scripts.OnEnter(button) end)
    end
    function W.ShiftClick(button)
        W.modified = "SPLITSTACK"
        W.Native(function() button.scripts.OnClick(button, "LeftButton") end)
        W.modified = nil
    end
    function W.OpenBank(kind)
        W.Native(function()
            W.BankFrame:Show()
            W.BankFrame.BankPanel.bankType = kind or Enum.BankType.Character
            W.BankFrame.BankPanel:Show()
        end)
        W.Fire("BANKFRAME_OPENED")
    end
    function W.CloseBank()
        W.Native(function() W.BankFrame:Hide() end)
        W.Fire("BANKFRAME_CLOSED")
    end
    MenuUtil = { CreateContextMenu = function(anchor, generator) W.menu = { anchor = anchor, generator = generator } end }
end

function H.New(root, options)
    options = options or {}
    local W = { root = root, secure = false, combat = false, taint = {}, combatLayout = {}, timers = {},
        now = 1000, events = {}, calls = { info = 0, quest = 0, newItem = 0, itemInfo = 0, splits = {}, pickups = {},
        uses = {}, setTab = 0, sort = {} }, items = {}, sizes = {}, data = {}, newItems = {}, postCalls = {},
        frames = {}, cursor = nil, money = options.money or 500000, popups = {}, errors = {} }
    W.client = options.client or "Mainline"
    local forever = W.client == "Forever"

    ---------------------------------------------------------------- execution context
    function W.Native(fn, ...)
        local was = W.secure
        W.secure = true
        local results = { fn(...) }
        W.secure = was
        return unpack(results, 1, table.maxn(results))
    end
    local function Insecure(fn, ...)
        local was = W.secure
        W.secure = false
        local results = { fn(...) }
        W.secure = was
        return unpack(results, 1, table.maxn(results))
    end
    W.Insecure = Insecure
    local function Taint(what) if not W.secure then W.taint[#W.taint + 1] = what end end
    W.Taint = Taint

    ---------------------------------------------------------------- widgets
    local Widget = {}
    Widget.__index = Widget
    local function NewWidget(kind, name, parent, native)
        local w = setmetatable({ kind = kind, name = name, parent = parent, shown = true, scripts = {},
            points = {}, width = 0, height = 0, scale = 1, alpha = 1, level = parent and (parent.level or 0) + 1 or 0,
            native = native == true, children = {}, mouse = false, wheel = false, text = nil }, Widget)
        if parent and parent.children then parent.children[#parent.children + 1] = w end
        W.frames[#W.frames + 1] = w
        if name then _G[name] = w end
        return w
    end
    W.NewWidget = NewWidget
    local function GuardLayout(self, method)
        if self.guarded and W.combat and not W.secure then
            W.combatLayout[#W.combatLayout + 1] = (self.name or self.kind) .. ":" .. method
        end
    end
    local function RunScript(self, script, ...)
        local handler = self.scripts[script]
        if handler then handler(self, ...) end
    end
    W.RunScript = RunScript
    function Widget:GetName() return self.name end
    function Widget:GetObjectType() return self.kind end
    function Widget:GetParent() return self.parent end
    function Widget:SetParent(parent) self.parent = parent end
    function Widget:IsForbidden() return false end
    function Widget:SetPoint(point, relative, relativePoint, x, y)
        GuardLayout(self, "SetPoint")
        if type(relative) == "number" then relative, relativePoint, x, y = nil, nil, relative, relativePoint end
        relative = relative or self.parent
        relativePoint = relativePoint or point
        for i = 1, #self.points do
            if self.points[i][1] == point then
                self.points[i] = { point, relative, relativePoint, x or 0, y or 0 }
                return
            end
        end
        self.points[#self.points + 1] = { point, relative, relativePoint, x or 0, y or 0 }
    end
    function Widget:ClearAllPoints() GuardLayout(self, "ClearAllPoints"); Clear(self.points) end
    function Widget:SetAllPoints(target)
        target = target or self.parent
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        self:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
    end
    function Widget:GetNumPoints() return #self.points end
    function Widget:GetPoint(index)
        local p = self.points[index or 1]
        if p then return p[1], p[2], p[3], p[4], p[5] end
    end
    function Widget:SetSize(width, height) GuardLayout(self, "SetSize"); self.width, self.height = width, height end
    function Widget:SetWidth(width) GuardLayout(self, "SetWidth"); self.width = width end
    function Widget:SetHeight(height) GuardLayout(self, "SetHeight"); self.height = height end
    function Widget:GetSize() return self:GetWidth(), self:GetHeight() end
    function Widget:SetScale(scale) GuardLayout(self, "SetScale"); self.scale = scale end
    function Widget:GetScale() return self.scale end
    function Widget:GetEffectiveScale()
        local scale, frame = 1, self
        while frame do scale = scale * (frame.scale or 1); frame = frame.parent end
        return scale
    end
    function Widget:SetAlpha(alpha) self.alpha = alpha end
    function Widget:GetAlpha() return self.alpha end
    function Widget:SetFrameLevel(level) self.level = level end
    -- Suite code may keep its own `level` field on a frame (the bank item
    -- level text); the client's frame level is separate from Lua fields.
    function Widget:GetFrameLevel()
        if type(self.level) == "number" then return self.level end
        return self.parent and self.parent:GetFrameLevel() + 1 or 0
    end
    function Widget:SetFrameStrata(strata) self.strata = strata end
    function Widget:GetFrameStrata() return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
    function Widget:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
    function Widget:SetToplevel() end
    function Widget:Raise() end
    function Widget:SetClampedToScreen(value) self.clamped = value end
    function Widget:SetMovable(value) self.movable = value end
    function Widget:IsMovable() return self.movable == true end
    function Widget:StartMoving() self.moving = true end
    function Widget:StopMovingOrSizing() self.moving = false end
    function Widget:RegisterForDrag(...) self.drag = { ... } end
    function Widget:RegisterForClicks(...) self.clicks = { ... } end
    function Widget:EnableMouse(value) self.mouse = value end
    function Widget:IsMouseEnabled() return self.mouse end
    function Widget:EnableMouseWheel(value) self.wheel = value end
    function Widget:IsMouseWheelEnabled() return self.wheel end
    function Widget:EnableKeyboard(value) self.keyboard = value end
    function Widget:SetPropagateKeyboardInput(value) self.propagate = value end
    function Widget:IsVisible()
        local frame = self
        while frame do
            if not frame.shown then return false end
            frame = frame.parent
        end
        return true
    end
    function Widget:IsShown() return self.shown end
    function Widget:Show()
        GuardLayout(self, "Show")
        if self.shown then return end
        self.shown = true
        RunScript(self, "OnShow")
    end
    function Widget:Hide()
        GuardLayout(self, "Hide")
        if not self.shown then return end
        self.shown = false
        RunScript(self, "OnHide")
    end
    function Widget:SetShown(value) if value then self:Show() else self:Hide() end end
    function Widget:SetScript(script, handler) self.scripts[script] = handler end
    function Widget:GetScript(script) return self.scripts[script] end
    function Widget:HookScript(script, handler)
        local previous = self.scripts[script]
        self.scripts[script] = function(...)
            if previous then previous(...) end
            Insecure(handler, ...)
        end
    end
    function Widget:RegisterEvent(event)
        W.events[event] = W.events[event] or {}
        for i = 1, #W.events[event] do if W.events[event][i] == self then return end end
        table.insert(W.events[event], self)
    end
    Widget.RegisterUnitEvent = Widget.RegisterEvent
    function Widget:UnregisterEvent(event)
        local list = W.events[event]
        if not list then return end
        for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
    end
    function Widget:UnregisterAllEvents()
        for _, list in pairs(W.events) do
            for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
        end
    end
    function Widget:IsEventRegistered(event)
        for _, frame in ipairs(W.events[event] or {}) do if frame == self then return true end end
        return false
    end
    function Widget:CreateTexture(name, layer, template, sublevel)
        local texture = NewWidget("Texture", name, self, self.native)
        texture.layer, texture.sublevel = layer, sublevel
        return texture
    end
    function Widget:CreateFontString(name, layer)
        local text = NewWidget("FontString", name, self, self.native)
        text.layer = layer
        return text
    end
    function Widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function Widget:SetTexture(texture) self.texture = texture end
    function Widget:GetTexture() return self.texture end
    function Widget:SetAtlas(atlas) self.atlas = atlas end
    function Widget:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
    function Widget:SetDesaturated(value) self.desaturated = value end
    function Widget:SetTexCoord() end
    function Widget:SetText(text) self.text = text end
    function Widget:SetFormattedText(format, ...) self.text = format:format(...) end
    function Widget:GetText() return self.text end
    function Widget:SetFont(path, size, flags) self.font = { path, size, flags }; return true end
    function Widget:GetFont() if self.font then return unpack(self.font) end end
    function Widget:SetFontObject() end
    function Widget:SetJustifyH(value) self.justify = value end
    function Widget:SetJustifyV() end
    function Widget:SetWordWrap(value) self.wordWrap = value end
    function Widget:SetTextColor(r, g, b) self.textColor = { r, g, b } end
    function Widget:SetShadowColor(...) self.shadowColor = { ... } end
    function Widget:SetShadowOffset(...) self.shadowOffset = { ... } end
    function Widget:GetStringHeight() return 12 end
    function Widget:GetStringWidth() return #(self.text or "") * 6 end
    function Widget:SetEnabled(value) self.enabled = value end
    function Widget:IsEnabled() return self.enabled ~= false end
    function Widget:Enable() self.enabled = true end
    function Widget:Disable() self.enabled = false end
    function Widget:SetChecked(value) self.checked = value end
    function Widget:GetChecked() return self.checked end
    function Widget:SetNormalTexture(texture) self.normalTexture = texture end
    function Widget:SetHighlightTexture() end
    function Widget:SetPushedTexture() end
    function Widget:SetScrollChild(child) self.scrollChild = child end
    function Widget:SetVerticalScroll(value) self.verticalScroll = value end
    function Widget:SetAutoFocus(value) self.autoFocus = value end
    function Widget:SetMaxLetters(value) self.maxLetters = value end
    function Widget:SetNumeric(value) self.numeric = value end
    function Widget:SetFocus() self.focus = true end
    function Widget:ClearFocus() self.focus = false end
    function Widget:HighlightText() end
    function Widget:SetID(id) self.id = id end
    function Widget:GetID() return self.id or 0 end
    function Widget:SetAttribute(key, value) self.attributes = self.attributes or {}; self.attributes[key] = value end
    function Widget:GetAttribute(key) return self.attributes and self.attributes[key] end
    function Widget:IsMouseMotionFocus() return false end
    function Widget:IsMouseOver() return false end
    function Widget:Click(button)
        local handler = self.scripts.OnClick
        if handler then handler(self, button or "LeftButton") end
    end

    -- Rects in UIParent units for single-anchor frames and SetAllPoints.
    local OFFSET = { TOPLEFT = { 0, 1 }, TOP = { .5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, .5 }, CENTER = { .5, .5 },
        RIGHT = { 1, .5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { .5, 0 }, BOTTOMRIGHT = { 1, 0 } }
    local function Rect(frame)
        if frame == W.UIParent then return 0, 0, W.screenWidth, W.screenHeight end
        local p = frame.points[1]
        if not p then return nil end
        local scale = frame:GetEffectiveScale()
        local width, height = frame.width * scale, frame.height * scale
        if #frame.points >= 2 and frame.points[1][1] == "TOPLEFT" and frame.points[2][1] == "BOTTOMRIGHT"
            and frame.points[1][2] == frame.points[2][2] then
            local l, b, w, h = Rect(frame.points[1][2])
            if not l then return nil end
            local tl, br = frame.points[1], frame.points[2]
            return l + tl[4] * scale, b + br[5] * scale, w - tl[4] * scale + br[4] * scale, h + tl[5] * scale - br[5] * scale
        end
        local l, b, w, h = Rect(p[2])
        if not l then return nil end
        local rel = OFFSET[p[3]]
        local x = l + w * rel[1] + p[4] * scale
        local y = b + h * rel[2] + p[5] * scale
        local own = OFFSET[p[1]]
        return x - width * own[1], y - height * own[2], width, height
    end
    W.Rect = Rect
    function Widget:GetLeft() local l = Rect(self); return l and l / self:GetEffectiveScale() end
    function Widget:GetBottom() local _, b = Rect(self); return b and b / self:GetEffectiveScale() end
    function Widget:GetRight() local l, _, w = Rect(self); return l and (l + w) / self:GetEffectiveScale() end
    function Widget:GetTop() local _, b, _, h = Rect(self); return b and (b + h) / self:GetEffectiveScale() end
    -- A frame stretched by two anchors (SetAllPoints) takes its size from them.
    function Widget:GetWidth()
        if #self.points >= 2 then
            local _, _, width = Rect(self)
            if width then return width / self:GetEffectiveScale() end
        end
        return self.width
    end
    function Widget:GetHeight()
        if #self.points >= 2 then
            local _, _, _, height = Rect(self)
            if height then return height / self:GetEffectiveScale() end
        end
        return self.height
    end
    function Widget:GetScaledRect() return Rect(self) end

    ---------------------------------------------------------------- globals
    W.screenWidth, W.screenHeight = options.screenWidth or 1366, options.screenHeight or 768
    W.UIParent = NewWidget("Frame", "UIParent", nil, true)
    W.UIParent.width, W.UIParent.height = W.screenWidth, W.screenHeight
    UIParent = W.UIParent
    function UIParent:GetWidth() return W.screenWidth end
    function UIParent:GetHeight() return W.screenHeight end
    GetScreenHeight = function() return W.screenHeight end
    GetScreenWidth = function() return W.screenWidth end
    CreateFrame = function(kind, name, parent, template)
        local frame = NewWidget(kind, name, parent, false)
        if template and W.templates[template] then W.templates[template](frame) end
        return frame
    end
    W.templates = {
        BasicFrameTemplateWithInset = function(frame) frame.TitleText = frame:CreateFontString() end,
        -- SecureActionButtonTemplate (Blizzard_FrameXML/SecureTemplates.lua): a
        -- protected button whose OnClick is Blizzard's secure code. An
        -- unprefixed type matches unmodified clicks only; "click" clicks its
        -- clickbutton from secure code. W.SecureClick runs a hardware click.
        SecureActionButtonTemplate = function(frame)
            frame.protected = true
            frame.scripts.OnClick = function(self, mouseButton)
                local suffix = mouseButton == "LeftButton" and "1" or mouseButton == "RightButton" and "2" or "3"
                local kind = not IsModifiedClick() and (self:GetAttribute("type" .. suffix) or self:GetAttribute("type"))
                local target = kind == "click" and (self:GetAttribute("clickbutton" .. suffix) or self:GetAttribute("clickbutton"))
                if target then W.Native(function() target:Click(mouseButton) end) end
            end
        end,
    }
    function W.SecureClick(frame, mouseButton)
        mouseButton = mouseButton or "LeftButton"
        W.Native(frame.scripts.OnClick, frame, mouseButton)
        if frame.scripts.PostClick then Insecure(frame.scripts.PostClick, frame, mouseButton) end
    end
    RegisterStateDriver = function(frame, state, value) frame.stateDrivers = frame.stateDrivers or {}; frame.stateDrivers[state] = value end
    InCombatLockdown = function() return W.combat end
    UnitAffectingCombat = function(unit) return unit == "player" and (W.combat or W.fighting == true) end
    securecallfunction = function(fn, ...) return fn(...) end
    issecretvalue = nil
    hooksecurefunc = function(target, key, hook)
        if type(target) == "string" then target, key, hook = _G, target, key end
        local original = target[key]
        assert(type(original) == "function", "hooksecurefunc target missing: " .. tostring(key))
        rawset(target, key, function(...)
            local results = { original(...) }
            Insecure(hook, ...)
            return unpack(results, 1, table.maxn(results))
        end)
    end
    -- C_Timer on the client clock: a zero delay runs on the next frame
    -- (W.Frame), a longer wait once W.Advance has reached it.
    W.later = {}
    GetTime = function() return W.now end
    C_Timer = {
        After = function(delay, callback)
            if delay > 0 then
                W.later[#W.later + 1] = { due = W.now + delay, callback = callback }
            else
                W.timers[#W.timers + 1] = callback
            end
        end,
    }
    C_EventUtils = { IsEventValid = function() return true end }
    C_AddOns = { IsAddOnLoaded = function() return true end, DoesAddOnExist = function() return true end,
        GetAddOnEnableState = function() return 2 end, LoadAddOn = function() return true end }
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
    GameEvent = forever and { RegisterCamelotEvents = function() end } or nil
    MSUF_NS = { L = {} }
    UnitGUID = function() return W.guid or "Player-1-0001" end
    UnitName = function() return W.playerName or "Tester", nil end
    UnitFullName = function() return W.playerName or "Tester", W.realmShort or "TestRealm" end
    GetRealmName = function() return W.realm or "Test Realm" end
    GetMoney = function() return W.money end
    GOLD_AMOUNT_SYMBOL, SILVER_AMOUNT_SYMBOL, COPPER_AMOUNT_SYMBOL = "g", "s", "c"
    GetServerTime = function() return W.serverTime or 1790000000 end
    date, time = os.date, os.time
    GetCursorPosition = function() return 500, 500 end
    IsShiftKeyDown = function() return false end
    IsModifiedClick = function(action) return W.modified == (action or true) or (action == nil and W.modified ~= nil) end
    HandleModifiedItemClick = function() return false end
    ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    END_REFUND = "The item will no longer be refundable."
    CONTAINER_OFFSET_Y = 85
    CursorHasItem = function() return W.cursor ~= nil end
    GetCursorInfo = function()
        if W.cursor then return "item", W.cursor.id, W.cursor.link end
    end
    ClearCursor = function() W.cursor = nil end
    C_Cursor = { GetCursorItem = function() return W.cursor and W.cursor.location end }
    GameTooltip_Hide = function() W.GameTooltip:Hide() end
    UIErrorsFrame = { AddExternalErrorMessage = function(_, text) W.errors[#W.errors + 1] = text end,
        AddMessage = function(_, text) W.errors[#W.errors + 1] = text end }
    UISpecialFrames = {}
    StaticPopupDialogs = {}
    StaticPopup_Show = function(which, a, b, data)
        W.popups[#W.popups + 1] = { which = which, data = data, info = StaticPopupDialogs[which] }
        return W.popups[#W.popups]
    end
    StaticPopup_Hide = function() end
    YES, NO, OKAY, CANCEL = "Yes", "No", "Okay", "Cancel"
    GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    CONTAINER_OFFSET_Y = 85
    NUM_BAG_FRAMES = 4
    NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    Constants = { InventoryConstants = { NumBagSlots = 4, NumReagentBagSlots = 1 } }
    Enum = { BankType = { Character = 1, Account = 2 }, TooltipDataType = { Item = 0 },
        ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4, Unused1 = 5, Unused2 = 6,
            ToWoWAccount = 7, ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9 },
        ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6,
            Tradegoods = 7, ItemEnhancement = 8, Recipe = 9, Quiver = 11, Questitem = 12, Key = 13, Miscellaneous = 15 },
        ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 },
        BagIndex = { Backpack = 0, ReagentBag = 5, CharacterBankTab_1 = 6, AccountBankTab_1 = 12 } }
    MenuResponse = { Open = 1, Close = 2 }
    INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED = 1, 19
    INVTYPE_HEAD, INVTYPE_CHEST = "Head", "Chest"
    EXPANSION_NAME10 = "The War Within"
    bit = bit or { band = function(a, b) return a % (b + b) >= b and b or 0 end }
    GetFormattedItemQuantity = function(quantity, maximum)
        if quantity > (maximum or 9999) then return "*" end
        return quantity
    end
    SetItemButtonDesaturated = function(button, value)
        local icon = button.icon
        if icon then icon:SetDesaturated(value) end
        button.desaturatedState = value
    end
    W.SetItemButtonCount = function(button, count)
        count = count or 0
        button.count = count
        if count > 1 then
            button.Count:SetText(GetFormattedItemQuantity(count, button.maxDisplayCount))
            button.Count:Show()
        else
            button.Count:Hide()
        end
    end
    SetItemButtonCount = W.SetItemButtonCount
    -- W.equipmentSets[id] = { name =, locations = { location, ... } }; W.locations[location] = { isBags, bag, slot }
    W.equipmentSets, W.locations, W.upgrades = {}, {}, {}
    EquipmentManager_GetLocationData = function(location) return W.locations[location] or {} end
    C_EquipmentSet = {
        GetEquipmentSetIDs = function()
            local ids = {}
            for id in pairs(W.equipmentSets) do ids[#ids + 1] = id end
            return ids
        end,
        GetEquipmentSetInfo = function(id) return W.equipmentSets[id] and W.equipmentSets[id].name end,
        GetItemLocations = function(id) return W.equipmentSets[id] and W.equipmentSets[id].locations end,
    }
    C_MythicPlus = { GetOwnedKeystoneLevel = function() return W.keyLevel end,
        GetOwnedKeystoneChallengeMapID = function() return W.keyMap end }
    C_ChallengeMode = { GetMapUIInfo = function(id) return W.mapNames and W.mapNames[id] end }
    C_CVar = { GetCVar = function(key) return (W.cvars or {})[key] end,
        SetCVar = function(key, value) W.cvars[key] = tostring(value) end }
    W.cvars = { combinedBags = "1" }
    C_CurrencyInfo = { GetCurrencyInfo = function() return nil end, GetCurrencyListSize = function() return 0 end }

    ---------------------------------------------------------------- items
    -- W.data[id] = { name, class, subclass, subclassName, equipLoc, maxStack, quality, level, expansion,
    -- bind, reagent, cached }; W.items[bag][slot] = { id, count, locked, bound, filtered, quest, link }
    function W.Define(id, fields)
        local data = { name = "Item " .. id, class = 15, subclass = 0, equipLoc = "", maxStack = 1, quality = 1,
            level = 0, cached = true }
        for key, value in pairs(fields or {}) do data[key] = value end
        W.data[id] = data
        return data
    end
    function W.Put(bag, slot, id, count, fields)
        W.items[bag] = W.items[bag] or {}
        local item = { id = id, count = count or 1, link = "item:" .. id }
        for key, value in pairs(fields or {}) do item[key] = value end
        W.items[bag][slot] = item
        return item
    end
    function W.Item(bag, slot) return W.items[bag] and W.items[bag][slot] end
    local function Data(id) return W.data[id] or W.Define(id) end
    C_Container = {
        GetContainerNumSlots = function(bag) return W.sizes[bag] or 0 end,
        GetContainerNumFreeSlots = function(bag)
            local free = 0
            for slot = 1, W.sizes[bag] or 0 do if not W.Item(bag, slot) then free = free + 1 end end
            return free, (W.families or {})[bag] or 0
        end,
        GetContainerItemInfo = function(bag, slot)
            W.calls.info = W.calls.info + 1
            local item = W.Item(bag, slot)
            if not item then return nil end
            local data = Data(item.id)
            return { itemID = item.id, hyperlink = item.link, stackCount = item.count, quality = data.quality,
                isLocked = item.locked == true, isBound = item.bound == true, isFiltered = item.filtered == true,
                iconFileID = 100 + item.id, hasNoValue = false }
        end,
        GetContainerItemQuestInfo = function(bag, slot)
            W.calls.quest = W.calls.quest + 1
            local item = W.Item(bag, slot)
            return { isQuestItem = item and item.quest == true or false }
        end,
        GetBagName = function(bag) return bag == 0 and "Backpack" or "Bag " .. bag end,
        GetContainerItemLink = function(bag, slot) local item = W.Item(bag, slot); return item and item.link end,
        SplitContainerItem = function(bag, slot, amount)
            W.calls.splits[#W.calls.splits + 1] = { bag, slot, amount }
            local item = assert(W.Item(bag, slot), "split from an empty slot")
            assert(not W.cursor, "split with an item on the cursor")
            item.count = item.count - amount
            W.cursor = { id = item.id, link = item.link, count = amount, from = { bag, slot } }
            W.Fire("ITEM_LOCK_CHANGED", bag, slot)
            W.Fire("CURSOR_CHANGED")
        end,
        PickupContainerItem = function(bag, slot)
            W.calls.pickups[#W.calls.pickups + 1] = { bag, slot }
            local item = W.Item(bag, slot)
            if W.cursor then
                local cursor = W.cursor
                W.cursor = item and { id = item.id, link = item.link, count = item.count, from = { bag, slot } } or nil
                W.Put(bag, slot, cursor.id, cursor.count, { refundable = cursor.refundable })
            elseif item then
                W.items[bag][slot] = nil
                W.cursor = { id = item.id, link = item.link, count = item.count, refundable = item.refundable,
                    from = { bag, slot }, location = { bag = bag, slot = slot } }
            end
            W.Fire("CURSOR_CHANGED")
            W.Fire("BAG_UPDATE", bag)
            W.Fire("BAG_UPDATE_DELAYED")
        end,
        UseContainerItem = function(bag, slot, unit, bankType)
            W.calls.uses[#W.calls.uses + 1] = { bag, slot, bankType }
        end,
        GetSortBagsRightToLeft = function() return W.sortRightToLeft == true end,
        SetSortBagsRightToLeft = function(value)
            W.calls.sort[#W.calls.sort + 1] = value
            W.sortRightToLeft = value
        end,
    }
    C_NewItems = { IsNewItem = function(bag, slot)
        W.calls.newItem = W.calls.newItem + 1
        return W.newItems[bag * KEY + slot] == true
    end, RemoveNewItem = function(bag, slot) W.newItems[bag * KEY + slot] = nil end }
    C_Item = {
        GetItemInfo = function(link)
            W.calls.itemInfo = W.calls.itemInfo + 1
            local id = tonumber(tostring(link):match("item:(%d+)") or link)
            local data = id and W.data[id]
            if not data or not data.cached then return nil end
            return data.name, link, data.quality, data.level, 1, "Type", data.subclassName or "Sub", data.maxStack,
                data.equipLoc, 1, 1, data.class, data.subclass, data.bind or 0, data.expansion or 10, nil, data.reagent
        end,
        RequestLoadItemDataByID = function(id) W.requested = W.requested or {}; W.requested[id] = (W.requested[id] or 0) + 1 end,
        GetDetailedItemLevelInfo = function(link)
            local data = W.data[tonumber(tostring(link):match("item:(%d+)"))]
            return data and data.level ~= 0 and data.level or nil
        end,
        IsEquippableItem = function(link)
            local data = W.data[tonumber(tostring(link):match("item:(%d+)"))]
            return data ~= nil and data.equipLoc ~= ""
        end,
        GetItemQualityColor = function() return 1, 1, 1 end,
        GetItemUpgradeInfo = function(link) return W.upgrades[link] end,
        IsItemKeystoneByID = function(id) return W.data[id] and W.data[id].keystone == true end,
        GetItemFamily = function() return 0 end,
        GetItemGUID = function(location) return location and ("guid:" .. location.bag .. ":" .. location.slot) end,
        CanBeRefunded = function(location)
            if not location then return false end
            local item = W.Item(location.bag, location.slot)
            return (item and item.refundable) or (W.cursor and W.cursor.location == location and W.cursor.refundable) or false
        end,
    }

    ---------------------------------------------------------------- events and frames of the client
    function W.Fire(event, ...)
        local list = W.events[event]
        if not list then return end
        local copy = {}
        for i = 1, #list do copy[i] = list[i] end
        for i = 1, #copy do
            local frame = copy[i]
            local handler = frame.scripts.OnEvent
            if handler then
                if frame.native then W.Native(handler, frame, event, ...) else Insecure(handler, frame, event, ...) end
            end
        end
    end
    -- Runs one frame of the client: queued C_Timer callbacks (insecure).
    function W.Frame()
        local list = W.timers
        W.timers = {}
        for i = 1, #list do Insecure(list[i]) end
    end
    function W.Advance(seconds)
        W.now = W.now + seconds
        local due = {}
        for i = #W.later, 1, -1 do
            if W.later[i].due <= W.now then table.insert(due, 1, table.remove(W.later, i)) end
        end
        for i = 1, #due do Insecure(due[i].callback) end
    end
    function W.Settle(limit)
        for _ = 1, limit or 10 do
            if #W.timers == 0 then return end
            W.Frame()
        end
        assert(#W.timers == 0, "timers keep rescheduling")
    end
    function W.EnterCombat()
        W.fighting = true
        W.Fire("PLAYER_REGEN_DISABLED")
        W.combat = true
    end
    function W.LeaveCombat()
        W.combat, W.fighting = false, false
        W.Fire("PLAYER_REGEN_ENABLED")
    end

    H.BuildClient(W, { NewWidget = NewWidget, Data = Data, Taint = Taint, Insecure = Insecure,
        RunScript = RunScript, forever = forever })

    ---------------------------------------------------------------- Suite core and runtime
    local NS = {}
    W.NS = NS
    MSUF_EditModeAPI = nil
    assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", NS)
    if forever then NS.Client.isForever = true end
    NS.Client.isForever = forever
    NS.Client.modernEquipment = not forever
    assert(loadfile(root .. "/MSUF_Suite/Core/SessionGold.lua"))("MSUF_Suite", NS)
    assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
    assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Bags.lua"))("MSUF_Suite", NS)
    NS.RootDB = options.rootDB or {}
    NS.loginKind = options.loginKind or "login"
    NS.goldSessionCaptured = true
    NS.Skin = { Acquire = function() return nil end, Release = function() end, SurfacesChanged = function() end }
    local S = { catalog = NS.SuiteCatalog, instances = {}, states = { bags = { active = false } }, editMode = false,
        queued = 0 }
    NS.Suite = S
    _G.MSUFSuite = NS
    local configs = { bags = {}, dataTexts = { enabled = true, trackAltGold = options.trackAltGold == true } }
    for key, rule in pairs(NS.SuiteCatalog.bags.rules) do configs.bags[key] = rule.default end
    configs.bags.enabled = true
    for key, value in pairs(options.config or {}) do configs.bags[key] = value end
    W.config = configs.bags
    W.moduleState = options.moduleState or {}
    function S.Config(id) return configs[id] end
    function S.ModuleState(id) assert(id == "bags"); return W.moduleState end
    function S.Queue(id) S.queued = S.queued + 1; W.queuedApply = true end
    local function Apply()
        local module = S.instances.bags
        if W.combat then S.Queue("bags"); return end
        if configs.bags.enabled then
            module.config, module.active = configs.bags, true
            module.context = module.context or S.NewContext("bags")
            if S.states.bags.active then module:Refresh() else module:Enable() end
            S.states.bags.active = true
        elseif S.states.bags.active then
            S.states.bags.active, module.active = false, false
            module:Disable()
            module.context:Release()
        end
    end
    W.Apply = Apply
    local function Check(key, value)
        local rule = NS.SuiteCatalog.bags.rules[key]
        assert(rule, "unknown bags setting " .. tostring(key))
        assert(type(value) == type(rule.default), "bad type for " .. key)
        if type(value) == "number" then
            assert(value >= rule.min and value <= rule.max, key .. " out of range")
        end
    end
    function S.Set(id, key, value)
        if W.combat then return false end
        if id ~= "bags" then configs[id][key] = value; return true end
        Check(key, value)
        configs.bags[key] = value
        Apply()
        return true
    end
    function S.SetMany(id, values)
        if W.combat then return false end
        for key, value in pairs(values) do Check(key, value) end
        for key, value in pairs(values) do configs.bags[key] = value end
        Apply()
        return true
    end
    function S.ResetKeys(id, values) return S.SetMany(id, values) end
    function S.CommitEditPosition(id, values) return S.SetMany(id, values) end
    function S.RegisterOwnedMover(id, element, spec) W.movers = W.movers or {}; W.movers[element] = spec end
    function S.RefreshOwnedMovers() end
    local runtime = {}
    assert(loadfile(root .. "/MSUF_Suite_Modules/Runtime.lua"))("MSUF_Suite_Modules", runtime)
    assert(loadfile(root .. "/MSUF_Suite_Modules/Timers.lua"))("MSUF_Suite_Modules", runtime)
    assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})
    W.S = S

    ---------------------------------------------------------------- the Bags addon
    W.P = {}
    for _, file in ipairs(Support.TocFiles(root, "MSUF_Suite_Bags", "Mainline")) do
        -- Addon code: its main chunks run insecure.
        if file:match("%.lua$") then
            Insecure(assert(loadfile(root .. "/MSUF_Suite_Bags/" .. file)), "MSUF_Suite_Bags", W.P)
        end
    end
    W.M = assert(S.instances.bags, "Bags did not install its module")
    return W
end

return H
