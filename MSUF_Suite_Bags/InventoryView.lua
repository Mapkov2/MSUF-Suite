local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Model, Index, Grid, FreeSlots = P.InventoryModel, P.InventoryIndex, P.GridView, P.FreeSlots
local VIEW = NS.BagsView
-- layout: "suite" (Suite grid), "combat" (every slot in physical order, no
-- Suite controls) or "native" (Blizzard's own grid is showing).
local InventoryView = { index = Index.New(), model = Model.New(), buttons = {}, labels = {}, scroll = 0, view = {},
    context = {}, layout = "native", freeSlots = {}, geometry = {}, combatGeometry = {} }
InventoryView.nativeCountFonts = setmetatable({}, { __mode = "k" })
InventoryView.visibleButtons, InventoryView.slotState = {}, setmetatable({}, { __mode = "k" })
P.InventoryView = InventoryView
local max, min = math.max, math.min
local Request, Render, Flush
-- Windows that take items one physical stack at a time: merged stacks split
-- up while one is open. Blizzard_GuildBankUI loads on demand.
local Transactions = { "MailFrame", "TradeFrame", "AuctionHouseFrame", "AuctionFrame", "BankFrame", "MerchantFrame",
    "GuildBankFrame" }
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
    "BAG_UPDATE_DELAYED", "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "INVENTORY_SEARCH_UPDATE",
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }

local function State()
    local state = S.ModuleState("bags")
    if not state then return nil end
    return Index.State(state, InventoryView.view)
end

InventoryView.State = State

local function TransactionOpen()
    for i = 1, #Transactions do
        local frame = _G[Transactions[i]]
        if frame and frame:IsShown() then return true end
    end
    return false
end

-- Paging uses the same Suite projection in and out of combat. Protected
-- fallback layouts expose their physical slots instead.
local function MoveScroll(delta)
    Render(delta)
end

InventoryView.MoveScroll = MoveScroll

-- The Suite footer line of Finance.lua follows the chrome.
-- Finance.lua reads its currencies when its line changes visibility only.
local function ShowChrome(shown)
    if InventoryView.chrome then InventoryView.chrome:SetShown(shown) end
    P.BagLayout.HideControl(M.context, BagItemSearchBox, shown)
    P.BagLayout.HideControl(M.context, BagItemAutoSortButton, shown)
    M:UpdatePresentation()
    if InventoryView.chromeShown == shown then return end
    InventoryView.chromeShown = shown
    P.BagFinance.Refresh()
end

InventoryView.ShowChrome = ShowChrome

function InventoryView.SuiteLayout()
    return InventoryView.active == true and InventoryView.layout == "suite"
end

-- The combat layout left room for the Finance.lua footer line.
function InventoryView.CombatLine()
    return InventoryView.active == true and InventoryView.layout == "combat" and InventoryView.combatLine == true
end

-- Hiding the item button that owns Blizzard's stack split window would run
-- its OnHide (StackSplitFrame:Hide()) from Suite code: the Suite grid waits
-- until the split window closes. The combat layout hides no button.
local function SplitOwnerShown()
    return StackSplitFrame:IsShown() and InventoryView.visibleButtons[StackSplitFrame.owner] == true
end

local function SplitClosed()
    if not InventoryView.splitPending then return end
    InventoryView.splitPending = false
    Request()
end

-- Item tooltip post-calls survive Blizzard's 0.2 s tooltip rebuild
-- (see InventoryDetails.lua).
local function StackTooltip(tooltip)
    if not InventoryView.SuiteLayout() or tooltip ~= GameTooltip then return end
    local slot = InventoryView.slotState[tooltip:GetOwner()]
    local row = slot and slot.row
    if not row or row.stacks < 2 then return end
    tooltip:AddLine(string.format(S.Text("Combined: %d items in %d stacks"), row.count, row.stacks), 0.8, 0.8, 0.8)
    tooltip:AddLine(string.format(S.Text("This slot contains %d; clicking uses this physical stack."),
        row.item.count), 0.8, 0.8, 0.8, true)
end
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, StackTooltip)

Render = function(delta)
    if not InventoryView.active or not InventoryView.frame:IsShown() or not P.BagLayout.CanRender() or InventoryView.layout ~= "suite" then return end
    if delta then InventoryView.scroll = max(0, min(InventoryView.maxScroll or 0, InventoryView.scroll + delta)) end
    if SplitOwnerShown() then
        InventoryView.splitPending = true
        return
    end
    P.InventoryRendering.Suite()
end

local function BuildModel(state)
    InventoryView.context.transactions = TransactionOpen()
    -- Blizzard's search only dims matching buttons; matches on later pages
    -- would stay unseen, so the Suite grid lists the matches alone.
    InventoryView.context.searching = InventoryView.index.filtered > 0
    InventoryView.context.query = InventoryView.smartQuery
    InventoryView.context.hasKeyring = InventoryView.index.hasKeyring
    InventoryView.selected = Grid.Build(Model, InventoryView.model, InventoryView.index.items, M.config, state, InventoryView.context, InventoryView.selected)
end

-- event is the client event that asked for this pass, if any.
Flush = function(event)
    if not InventoryView.active or not M.active or not InventoryView.frame:IsShown() then return end
    local canLayout = not NS.InCombat(event) or P.BagLayout.CanRender(event)
    if NS.IsCombatLocked() and not canLayout then
        -- A protected bag opened in combat shows Blizzard's own grid; the Suite controls
        -- must not cover its rows. Everything else waits for the combat end.
        if InventoryView.layout ~= "combat" then
            InventoryView.layout = "native"
            ShowChrome(false)
        end
        return
    end
    local state = State()
    if not state then return end
    Index.ReadContainer(InventoryView.index, InventoryView.frame, Index.Recent())
    P.InventoryDetails.Index(InventoryView.index, InventoryView.smartQuery)
    if not canLayout then
        P.InventoryRendering.Combat()
        return
    end
    if SplitOwnerShown() then
        InventoryView.splitPending = true
        return
    end
    if M.config.showFreeSlots then FreeSlots.Read(InventoryView.freeSlots, InventoryView.index, true) end
    BuildModel(state)
    P.InventoryRendering.Suite()
    P.InventoryControls.Sidebar()
    if InventoryView.transitionPending then P.BagMotion.Switch(InventoryView, M.config) end
    InventoryView.transitionPending, InventoryView.categoryTransitionPending = false, false
    if InventoryView.animate and M.config.animationMode == NS.BagsAnimation.FULL then
        for i = 1, InventoryView.labelCount do
            local plate = InventoryView.labels[i].plate
            if plate then P.BagMotion.Play(plate, M.config, i - 1) end
        end
    end
    InventoryView.animate = false
end

-- One pass per frame (a ctx:Coalesce job): requests in between ride along.
-- The tail call keeps the pass one stack level shallower (bag refresh budget).
local function DeferredFlush() return Flush() end
Request = function()
    if not InventoryView.active or not InventoryView.frame:IsShown() then return end
    InventoryView.flushJob = InventoryView.flushJob or M.context:Coalesce(0, DeferredFlush)
    InventoryView.flushJob:Request()
end
InventoryView.Request = Request

local RestoreLayout
local function OnEvent(_, event, value, success)
    if not InventoryView.active then
        if InventoryView.restorePending and event == "PLAYER_REGEN_ENABLED" then RestoreLayout() end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        P.BagWindowMotion.Cancel()
        P.BagResize.Cancel()
        InventoryView.transitionPending, InventoryView.categoryTransitionPending = false, false
        P.BagMotion.StopAll()
        P.EquippedBags.Close()
        M:RefreshWindowLayout()
        -- Sent before InCombatLockdown() turns true: lay out now, not next frame.
        Flush(event)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then InventoryView.positionsDirty = true end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        P.BagWindowMotion.Cancel()
        P.BagResize.Cancel()
        M:RefreshWindowLayout()
    end
    if event == "BAG_UPDATE_DELAYED" or event == "EQUIPMENT_SETS_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        P.InventoryDetails.Invalidate()
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        -- Arriving item data patches the waiting records; no slot is read again.
        if not Index.ItemDataReceived(InventoryView.index, value, success) then return end
        Index.Refresh(InventoryView.index, value)
    end
    if event == "BAG_UPDATE_DELAYED" then P.EquippedBags.Refresh() end
    if event == "INVENTORY_SEARCH_UPDATE" then InventoryView.scroll = 0 end
    Request()
end

-- Blizzard re-acquires and re-anchors its item buttons; slot order is read again.
local function NativeLayoutChanged()
    InventoryView.positionsDirty = true
    Index.Invalidate(InventoryView.index)
    Request()
end

local function WindowShown()
    InventoryView.animate = true
    Index.Invalidate(InventoryView.index)
    Index.Retry(InventoryView.index)
    Request()
end

-- Blizzard lays the bag out again when it opens; until the Suite's own pass
-- (or while protected) its grid is what shows.
local function WindowHidden()
    if not InventoryView.active then return end
    InventoryView.layout = "native"
    InventoryView.transitionPending, InventoryView.categoryTransitionPending = false, false
    P.BagWindowMotion.Cancel()
    P.BagResize.Cancel()
    P.BagMotion.StopAll()
    P.EquippedBags.Close()
    ShowChrome(false)
end

function InventoryView.Refresh()
    if not M.active or NS.IsCombatLocked() then return end
    P.BagWindowMotion.Cancel()
    P.BagResize.Cancel()
    InventoryView.frame = M.frame
    -- Blizzard grid: Blizzard's own layout, with the Suite window style and
    -- item levels of Bags.lua.
    if M.config.inventoryView == VIEW.BLIZZARD_GRID then
        if InventoryView.active then InventoryView.Release() end
        return
    end
    if InventoryView.nativeMouseWheel == nil then InventoryView.nativeMouseWheel = InventoryView.frame:IsMouseWheelEnabled() end
    if not InventoryView.controlsReady then P.InventoryControls.Create() end
    Grid.RefreshFonts()
    InventoryView.frame:EnableMouseWheel(true)
    if not InventoryView.events then
        InventoryView.events = S.CreateFrame("Frame")
        InventoryView.events:SetScript("OnEvent", OnEvent)
    end
    for i = 1, #EVENTS do
        if NS.Client.SupportsEvent(EVENTS[i]) then InventoryView.events:RegisterEvent(EVENTS[i]) end
    end
    if not InventoryView.hooked then
        hooksecurefunc(InventoryView.frame, "UpdateItems", Request)
        hooksecurefunc(InventoryView.frame, "UpdateItemLayout", NativeLayoutChanged)
        hooksecurefunc(InventoryView.frame, "UpdateFrameSize", Request)
        InventoryView.frame:HookScript("OnShow", WindowShown)
        InventoryView.frame:HookScript("OnHide", WindowHidden)
        StackSplitFrame:HookScript("OnHide", SplitClosed)
        InventoryView.hooked = true
    end
    InventoryView.active = true
    Request()
end

-- Blizzard's own layout of the combined bag, from the native methods.
RestoreLayout = function()
    InventoryView.restorePending = false
    if not InventoryView.active and InventoryView.events then InventoryView.events:UnregisterAllEvents() end
    local frame = InventoryView.frame
    frame:UpdateItems()
    for _, button in frame:EnumerateValidItems() do button:Show() end
    frame:UpdateItemLayout()
    frame:UpdateFrameSize()
    M.NativeAnchorPass()
end

-- Hands the combined bag back to Blizzard. Count fonts and the mouse wheel
-- return at once (neither is protected); the layout follows when combat ends,
-- also after a module error stopped the view in combat.
function InventoryView.Release()
    local wasActive = InventoryView.active
    InventoryView.transitionPending, InventoryView.categoryTransitionPending = false, false
    P.BagWindowMotion.Cancel()
    P.BagResize.Cancel()
    M.combatScale = nil
    InventoryView.active, InventoryView.layout, InventoryView.positionsDirty, InventoryView.splitPending = false, "native", true, false
    Index.Reset(InventoryView.index)
    if InventoryView.events then InventoryView.events:UnregisterAllEvents() end
    ShowChrome(false)
    P.BagMotion.StopAll()
    P.InventoryEditor.Hide()
    P.EquippedBags.Close()
    P.InventoryDetails.Hide()
    local frame = InventoryView.frame
    if frame and InventoryView.nativeMouseWheel ~= nil then
        frame:EnableMouseWheel(InventoryView.nativeMouseWheel)
        InventoryView.nativeMouseWheel = nil
    end
    if not frame or not InventoryView.controlsReady or not (wasActive or InventoryView.restorePending) then return end
    for label, font in pairs(InventoryView.nativeCountFonts) do
        if font[1] then label:SetFont(unpack(font)) end
        InventoryView.nativeCountFonts[label] = nil
    end
    if NS.IsCombatLocked() then
        InventoryView.restorePending = true
        InventoryView.events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    RestoreLayout()
end

function InventoryView.Disable()
    InventoryView.Release()
end
