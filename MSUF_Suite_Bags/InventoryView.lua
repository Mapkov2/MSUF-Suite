local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Model, Index, Grid, FreeSlots = P.InventoryModel, P.InventoryIndex, P.GridView, P.FreeSlots
local VIEW, Keyring = NS.BagsView, P.KeyringInventory
local ONE_BAG = NS.BagsViewsWithReagents
-- Recorded inventories (OfflineInventory.lua); absent in partial loads.
local Offline = P.BagOffline
local Recent = P.BagRecentCounts
local POOR = Enum.ItemQuality.Poor
-- layout: "suite" (Suite grid), "combat" (every slot in physical order, no
-- Suite controls) or "native" (Blizzard's own grid is showing).
local InventoryView = { index = Index.New(), model = Model.New(), buttons = {}, labels = {}, scroll = 0, view = {},
    context = { mergeJunk = NS.Client.isForever }, layout = "native", freeSlots = {}, geometry = {}, combatGeometry = {} }
InventoryView.nativeCountFonts = setmetatable({}, { __mode = "k" })
InventoryView.visibleButtons, InventoryView.slotState = {}, setmetatable({}, { __mode = "k" })
P.InventoryView = InventoryView
local max, min = math.max, math.min
local Request, Render, Flush, RegisterEvents
-- Windows that take items one physical stack at a time: merged stacks split
-- up while one is open. Blizzard_GuildBankUI loads on demand.
local Transactions = { "MailFrame", "TradeFrame", "AuctionHouseFrame", "AuctionFrame", "BankFrame", "MerchantFrame",
    "GuildBankFrame" }
local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED", "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "PLAYER_ENTERING_WORLD", "EQUIPMENT_SETS_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED", "INVENTORY_SEARCH_UPDATE", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }
local ITEM_EVENTS = { "QUEST_REMOVED", "ITEM_LOCK_CHANGED" }
local RECENT_EVENTS = { "MAIL_INBOX_UPDATE", "TRADE_ACCEPT_UPDATE" }
local PET_EVENT = "UNIT_PET"

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

InventoryView.TransactionOpen = TransactionOpen

-- Paging uses the same Suite projection in and out of combat. Protected
-- fallback layouts expose their physical slots instead.
local function MoveScroll(delta)
    Render(delta)
end

InventoryView.MoveScroll = MoveScroll

-- Blizzard reuses this box for the combined bag and the individual backpack.
-- Mainline/ContainerFrame.lua: Retail ab5cb850, Forever d9c22e32.
local function UpdateNativeSearch(chromeShown)
    local edit, frame = BagItemSearchBox, M.frame
    local parent = M.active and M.config.hideSearchBar and frame and edit
        and not NS.Safety.IsForbidden(edit) and edit:GetParent()
    local hidden = S.Public(parent) and parent ~= nil and parent == frame
    local locked = NS.IsCombatLocked()
    if hidden and not InventoryView.nativeSearchHidden and not locked then
        local focused, query = edit:HasFocus(), edit:GetText()
        if S.Public(focused) and focused then edit:ClearFocus() end
        if S.Public(query) and type(query) == "string" and query ~= "" then edit:SetText("") end
        M.context:Property(edit, "IsEnabled", "SetEnabled", false)
        InventoryView.nativeSearchHidden, InventoryView.nativeSearchIcon = true, frame.SearchBoxIcon
        if InventoryView.nativeSearchIcon then M.context:Alpha(InventoryView.nativeSearchIcon, 0) end
    elseif not hidden and InventoryView.nativeSearchHidden and (not locked or P.BagLayout.Frame(edit)) then
        P.BagLayout.RestoreProperty(M.context, edit, "SetEnabled")
        InventoryView.nativeSearchHidden = nil
    end
    if not hidden and InventoryView.nativeSearchIcon and not locked then
        P.BagLayout.RestoreProperty(M.context, InventoryView.nativeSearchIcon, "SetAlpha")
        InventoryView.nativeSearchIcon = nil
    end
    if M.active and locked and (hidden ~= (InventoryView.nativeSearchHidden == true)
        or not hidden and InventoryView.nativeSearchIcon) then
        S.Queue("bags")
    end
    P.BagLayout.HideControl(M.context, edit, chromeShown or hidden and InventoryView.nativeSearchHidden)
end

function InventoryView.NativeSearchMoved()
    if M.active and M.config.hideSearchBar then UpdateNativeSearch(false) end
end

-- The Suite footer line of Finance.lua follows the chrome.
-- Finance.lua reads its currencies when its line changes visibility only.
local function ShowChrome(shown, closing)
    if InventoryView.chromeShown ~= shown and InventoryView.chrome then InventoryView.chrome:SetShown(shown) end
    if M.config.hideSearchBar or InventoryView.nativeSearchHidden then
        UpdateNativeSearch(shown)
    else
        P.BagLayout.HideControl(M.context, BagItemSearchBox, shown)
    end
    P.BagLayout.HideControl(M.context, BagItemAutoSortButton, shown)
    M:UpdatePresentation(closing)
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
    local price = row.item.sellPrice
    if NS.Client.isForever and not NS.InCombat() and S.Finite(price) and price > 0 then
        tooltip:AddLine(S.Text("Vendor value for %d items: %s (%s each)"):format(
            row.count, S.MoneyText(price * row.count), S.MoneyText(price)), 0.8, 0.8, 0.8, true)
    end
end
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, StackTooltip)

Render = function(delta)
    if not InventoryView.active or not InventoryView.frame:IsVisible() or not P.BagLayout.CanRender() or InventoryView.layout ~= "suite" then return end
    if delta then InventoryView.scroll = max(0, min(InventoryView.maxScroll or 0, InventoryView.scroll + delta)) end
    if SplitOwnerShown() then
        InventoryView.splitPending = true
        return
    end
    P.InventoryRendering.Suite()
end

local function BuildModel(state)
    local config = M.config
    local mode = config.inventoryView
    if ONE_BAG[mode] or mode == VIEW.CATEGORIES and config.collapseCategorySidebar then
        InventoryView.selected = "all"
    end
    -- A recorded inventory (OfflineInventory.lua) builds the same model from
    -- its display records; the live index stays read for the way back.
    local recorded = Offline and Offline.Items()
    if recorded then
        InventoryView.selected = Offline.Build(InventoryView, state, recorded)
        return
    end
    InventoryView.context.transactions = TransactionOpen()
    -- Blizzard's search only dims matching buttons; matches on later pages
    -- would stay unseen, so the Suite grid lists the matches alone.
    InventoryView.context.searching = InventoryView.index.filtered > 0
    InventoryView.context.query = InventoryView.smartQuery
    InventoryView.context.hasKeyring = InventoryView.index.hasKeyring
    InventoryView.context.hasReagent = P.ReagentInventory and P.ReagentInventory.active
    InventoryView.selected = Grid.Build(Model, InventoryView.model, InventoryView.index.items, config, state, InventoryView.context, InventoryView.selected)
end

-- event is the client event that asked for this pass, if any.
Flush = function(event)
    if not InventoryView.active or not M.active or not InventoryView.frame:IsVisible() then return end
    local inCombat = NS.InCombat(event)
    local canLayout = not inCombat or P.BagLayout.CanRender(event)
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
    if not state then
        if InventoryView.layout == "native" then M:UpdatePresentation() end
        return
    end
    if P.ReagentInventory and (M.config.combineReagentBag or ONE_BAG[M.config.inventoryView]
        or P.ReagentInventory.active) then
        P.ReagentInventory.Prepare()
    end
    Index.ReadContainer(InventoryView.index, InventoryView.frame, Index.Recent())
    if Keyring then Keyring.Append(InventoryView.index, InventoryView.frame, inCombat) end
    P.InventoryDetails.Index(InventoryView.index, InventoryView.smartQuery)
    if not canLayout then
        P.InventoryRendering.Combat()
        return
    end
    if SplitOwnerShown() then
        InventoryView.splitPending = true
        if InventoryView.layout == "native" then M:UpdatePresentation() end
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
    if not InventoryView.active or not InventoryView.frame:IsVisible() then return end
    InventoryView.flushJob = InventoryView.flushJob or M.context:Coalesce(0, DeferredFlush)
    InventoryView.flushJob:Request()
end
InventoryView.Request = Request

local RestoreLayout
local function IndexedItem(bag, slot)
    if not InventoryView.frame:IsVisible() or not S.Finite(bag) or not S.Finite(slot) then return nil end
    local index = InventoryView.index
    local button = index.buttons[bag * P.SlotCache.KEY + slot]
    return index.records[button]
end

local function OnEvent(_, event, value, success)
    if not InventoryView.active then
        if InventoryView.restorePending and event == "PLAYER_REGEN_ENABLED" then RestoreLayout() end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        M.resizeCorner = nil
        -- This frame may get the combat edge before the Bags context does.
        if M.config.showTransmogStatus then P.BagTransmog.Pause() end
        -- A fight shows the live bags: every item button must be reachable.
        if Offline then Offline.Leave(true) end
        P.BagWindowMotion.Cancel()
        P.BagResize.Cancel()
        InventoryView.transitionPending, InventoryView.categoryTransitionPending = false, false
        P.InventoryRendering.AllowNextHint(false)
        P.BagMotion.StopNextHint()
        P.BagMotion.StopAll()
        P.EquippedBags.Close()
        M:RefreshWindowLayout()
        -- Sent before InCombatLockdown() turns true: lay out now, not next frame.
        Flush(event)
        return
    end
    if InventoryView.recentCountsActive and (event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_ENABLED"
        or event == "MAIL_INBOX_UPDATE" or event == "TRADE_ACCEPT_UPDATE") then
        Recent.Event(M.config, event, value, success)
    end
    if event == "MAIL_INBOX_UPDATE" or event == "TRADE_ACCEPT_UPDATE" then return end
    if event == PET_EVENT and (not S.Public(value) or value ~= "player") then return end
    if event == "BAG_UPDATE" then
        Index.InvalidateBag(InventoryView.index, value)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        InventoryView.positionsDirty, InventoryView.measureConfig = true, nil
        P.InventoryRendering.AllowNextHint(true)
    end
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        M.resizeCorner = nil
        P.BagWindowMotion.Cancel()
        P.BagResize.Cancel()
        M:RefreshWindowLayout()
    end
    if event == "BAG_UPDATE_DELAYED" or event == "EQUIPMENT_SETS_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        P.InventoryDetails.Invalidate()
    end
    if event == "BAG_CONTAINER_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        Index.InvalidateBags(InventoryView.index)
    end
    if event == "GET_ITEM_INFO_RECEIVED" then
        -- Arriving item data patches the waiting records; no slot is read again.
        local recorded = Offline and Offline.ItemDataReceived(value, success)
        if Index.ItemDataReceived(InventoryView.index, value, success) then
            Index.Refresh(InventoryView.index, value)
        elseif not recorded then
            return
        end
    end
    if event == "BAG_UPDATE_DELAYED" then P.EquippedBags.Refresh() end
    if event == "INVENTORY_SEARCH_UPDATE" then InventoryView.scroll = 0 end
    -- A lock can change which junk slots combine and clear Blizzard's slot tint.
    if event == "ITEM_LOCK_CHANGED" and not (Keyring and Keyring.OwnsBag(value)) then
        local item = IndexedItem(value, success)
        if not item or not (InventoryView.context.mergeJunk and item.quality == POOR
            or M.config.desaturateInactiveQuestItems and P.InventoryRendering.InactiveQuest(item)) then return end
    end
    Request()
end

-- Blizzard re-acquires and re-anchors its item buttons; slot order is read again.
local function NativeLayoutChanged()
    if not M.active then return end
    if not InventoryView.active or not InventoryView.frame:IsVisible() then
        InventoryView.hiddenLayoutDirty = true
        return
    end
    InventoryView.hiddenLayoutDirty = nil
    M.slotStyle = (M.slotStyle or 0) + 1
    InventoryView.positionsDirty = true
    -- Blizzard also moves hidden slots, which the next Suite pass may skip.
    for _, slot in pairs(InventoryView.slotState) do slot.x, slot.y = nil, nil end
    Index.Invalidate(InventoryView.index)
    Request()
end

local function WindowShown()
    if not InventoryView.active or not InventoryView.frame:IsVisible() then return end
    RegisterEvents()
    P.InventoryDetails.Invalidate()
    if InventoryView.scroll > 0 and S.PublicText(BagItemSearchBox:GetText()) ~= InventoryView.closedSearch then
        InventoryView.scroll = 0
    end
    InventoryView.closedSearch = nil
    if InventoryView.hiddenLayoutDirty then NativeLayoutChanged() end
    -- Blizzard has assigned the physical slots. Keep the panel's shell and
    -- title while the coalesced pass lays them out.
    local opening = not NS.InCombat() and not SplitOwnerShown() and S.ModuleState("bags") and "suite" or "native"
    M:UpdatePresentation(false, opening)
    InventoryView.animate, InventoryView.measureConfig = true, nil
    Index.Invalidate(InventoryView.index)
    Index.Retry(InventoryView.index)
    Request()
end

-- Blizzard lays the bag out again when it opens; until the Suite's own pass
-- (or while protected) its grid is what shows.
local function WindowHidden()
    M.resizeCorner = nil
    if P.ReagentInventory then P.ReagentInventory.Release() end
    P.PhysicalSort.Stop()
    if Offline then Offline.Leave(true) end
    if Keyring then Keyring.Close() end
    if not InventoryView.active then return end
    InventoryView.layout = "native"
    InventoryView.transitionPending, InventoryView.categoryTransitionPending = false, false
    P.BagWindowMotion.Cancel()
    P.BagResize.Cancel()
    P.BagMotion.StopNextHint()
    P.BagMotion.StopAll()
    P.EquippedBags.Close()
    ShowChrome(false, true)
    InventoryView.closedSearch = InventoryView.scroll > 0 and S.PublicText(BagItemSearchBox:GetText()) or nil
    RegisterEvents()
end

-- Only opt-in pickup totals need an observer without the inventory window.
local function ClosedEvent(_, event, first, second)
    Recent.Event(M.config, event, first, second)
end

RegisterEvents = function()
    local events = InventoryView.events
    local recent = Recent and Recent.Wanted(M.config) or false
    InventoryView.recentCountsActive = recent
    if not InventoryView.frame:IsVisible() then
        events:UnregisterAllEvents()
        events:SetScript("OnEvent", ClosedEvent)
        if NS.InCombat() then return end
        if recent then
            events:RegisterEvent("BAG_UPDATE_DELAYED")
            events:RegisterEvent("PLAYER_ENTERING_WORLD")
            for _, event in ipairs(RECENT_EVENTS) do
                if NS.Client.SupportsEvent(event) then events:RegisterEvent(event) end
            end
        end
        return
    end
    events:SetScript("OnEvent", OnEvent)
    for i = 1, #EVENTS do
        local event = EVENTS[i]
        if (event ~= "BAG_UPDATE" or NS.Client.isForever) and NS.Client.SupportsEvent(event) then
            events:RegisterEvent(event)
        end
    end
    for i = 1, #ITEM_EVENTS do
        local event = ITEM_EVENTS[i]
        local lockRefresh = event == "ITEM_LOCK_CHANGED" and (Keyring or InventoryView.context.mergeJunk)
        if (lockRefresh or M.config.desaturateInactiveQuestItems) and NS.Client.SupportsEvent(event) then
            events:RegisterEvent(event)
        else
            events:UnregisterEvent(event)
        end
    end
    if M.config.showPetFood and P.InventoryDetails.PetFoodEnabled() then
        events:RegisterUnitEvent(PET_EVENT, "player")
    else
        events:UnregisterEvent(PET_EVENT)
    end
    if Recent then
        for _, event in ipairs(RECENT_EVENTS) do
            if recent and NS.Client.SupportsEvent(event) then events:RegisterEvent(event) else events:UnregisterEvent(event) end
        end
    end
end

-- CombatIdle pauses the optional closed-window observer for a fight.
-- A protected handback registered by Release owns its own combat-end event.
function InventoryView.Pause()
    if InventoryView.active then InventoryView.events:UnregisterAllEvents() end
end

function InventoryView.Resume()
    if not InventoryView.active then return end
    RegisterEvents()
    if InventoryView.recentCountsActive then Recent.Event(M.config, "PLAYER_REGEN_ENABLED") end
    if InventoryView.frame:IsVisible() then
        Index.InvalidateBags(InventoryView.index)
        P.InventoryDetails.Invalidate()
    end
end

function InventoryView.Refresh()
    if not M.active or NS.IsCombatLocked() then return end
    P.BagWindowMotion.Cancel()
    P.BagResize.Cancel()
    InventoryView.frame = M.frame
    if M.config.hideSearchBar or InventoryView.nativeSearchHidden or InventoryView.nativeSearchIcon then
        UpdateNativeSearch(InventoryView.chromeShown)
    end
    -- Blizzard grid: Blizzard's own layout, with the Suite window style and
    -- item levels of Bags.lua.
    if M.config.inventoryView == VIEW.BLIZZARD_GRID then
        if InventoryView.active then InventoryView.Release() end
        return
    end
    Model.Prepare(InventoryView.model, M.config)
    P.InventoryRendering.AllowNextHint(not NS.InCombat())
    InventoryView.measureConfig = nil
    InventoryView.context.physicalSlots = NS.BagsPhysicalOrder(M.config)
    if InventoryView.nativeMouseWheel == nil then InventoryView.nativeMouseWheel = InventoryView.frame:IsMouseWheelEnabled() end
    if not InventoryView.controlsReady then P.InventoryControls.Create() end
    P.InventorySearch.RefreshBagVisibility(InventoryView, M.config.hideSearchBar)
    Grid.RefreshFonts()
    InventoryView.frame:EnableMouseWheel(true)
    if not InventoryView.events then
        InventoryView.events = S.CreateFrame("Frame")
        InventoryView.events:SetScript("OnEvent", OnEvent)
    end
    RegisterEvents()
    if Recent then
        if Recent.Wanted(M.config) then Recent.Event(M.config, "Refresh") else Recent.Reset() end
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
    if P.ReagentInventory then P.ReagentInventory.Release() end
    if Keyring then Keyring.Hide() end
    InventoryView.restorePending = false
    if not InventoryView.active and InventoryView.events then InventoryView.events:UnregisterAllEvents() end
    local frame = InventoryView.frame
    -- Opening the bag generates its native buttons before laying them out.
    if not frame:IsShown() then return end
    -- The iterator uses the bag size, which can include a slot without a button.
    for _, button in frame:EnumerateValidItems() do
        if not button then return end
    end
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
    if Recent then Recent.Reset() end
    if P.ReagentInventory then P.ReagentInventory.Release() end
    P.PhysicalSort.Stop()
    if Offline then Offline.Leave(true) end
    if InventoryView.list then P.BagList.Hide(InventoryView.list) end
    local wasActive = InventoryView.active
    InventoryView.transitionPending, InventoryView.categoryTransitionPending = false, false
    P.BagWindowMotion.Cancel()
    P.BagResize.Cancel()
    M.combatScale = nil
    InventoryView.active, InventoryView.layout, InventoryView.positionsDirty, InventoryView.splitPending = false, "native", true, false
    Index.Reset(InventoryView.index)
    if Keyring then Keyring.Hide() end
    if InventoryView.events then InventoryView.events:UnregisterAllEvents() end
    ShowChrome(false)
    P.BagMotion.StopNextHint()
    P.BagMotion.StopAll()
    P.InventoryEditor.Hide()
    P.EquippedBags.Close()
    P.InventoryDetails.Hide()
    if M.config.showTransmogStatus then P.BagTransmog.HideBadges(true) end
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
        InventoryView.events:SetScript("OnEvent", OnEvent)
        InventoryView.events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    RestoreLayout()
end

function InventoryView.Disable()
    InventoryView.Release()
    InventoryView.nativeSearchHidden, InventoryView.nativeSearchIcon = nil, nil
    if Offline then Offline.Reset() end
    P.QueryEditor.Close()
end
