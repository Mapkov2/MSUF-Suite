local _, Private = ...
local NS, S = Private.NS, Private.Suite
local Slots = Private.SlotCache
-- The controller restores the player's combinedBags CVar when disabled.
local M = { overlays = setmetatable({}, { __mode = "k" }), pending = {}, pendingPool = {}, requested = {} }
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "" }
-- Surface sits below native item buttons; see upstream/live ContainerFrame.xml.
local function WindowTexture(frame, layer, sublevel)
    return S.CreateTexture(frame, nil, layer, nil, sublevel)
end
M.WindowTexture = WindowTexture

local function Hide(record)
    if not record then return end
    if record.label then record.label:Hide() end
    if record.bindBadge then record.bindBadge:Hide() end
    record.link, record.level, record.quality, record.gear, record.bindLink, record.bindType = nil, nil, nil, nil, nil, nil
end

local function ClearPending(self)
    local pending, pool = self.pending, self.pendingPool
    for itemID, buttons in pairs(pending) do
        for i = #buttons, 1, -1 do buttons[i] = nil end
        pending[itemID] = nil
        pool[#pool + 1] = buttons
    end
end

-- An empty slot shows a quiet Suite surface instead of the bag artwork, and
-- Blizzard's item button keeps all its handlers. Blizzard draws the empty-slot
-- atlas (ContainerFrame.xml emptyBackgroundAtlas) in the item icon, BORDER
-- sublevel 0 (ItemButtonTemplate.xml, SetItemButtonTexture). The Suite never
-- writes that field, which Blizzard reads on every refresh: an empty slot
-- lifts the Suite surface above the icon instead, and an item puts it back
-- below. Both surface textures are opaque, so the atlas never shows.
local SURFACE_BELOW_ICON = { "BACKGROUND", -5, -4 }
local SURFACE_OVER_ICON = { "BORDER", 1, 2 }

local function LayerSurface(record, empty)
    record.slotEmpty = empty
    local layer = empty and SURFACE_OVER_ICON or SURFACE_BELOW_ICON
    record.slotOuter:SetDrawLayer(layer[1], layer[2])
    record.slotInner:SetDrawLayer(layer[1], layer[3])
end

local function StyleSlot(self, button)
    local record = self.overlays[button]
    if not record then
        record = {}
        self.overlays[button] = record
    end
    local activating = not record.slotNativeActive
    if not record.slotOuter or activating then
        if NS.IsCombatLocked() then
            self.needsItemRefresh = true
            S.Queue("bags")
            return
        end
        if not record.slotOuter then
            local below = SURFACE_BELOW_ICON
            local outer = WindowTexture(button, below[1], below[2])
            outer:SetAllPoints(button)
            local inner = WindowTexture(button, below[1], below[3])
            inner:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            record.slotOuter, record.slotInner, record.slotEmpty = outer, inner, false
        end
        record.slotNativeActive = true
    end
    if activating then
        record.slotOuter:Show()
        record.slotInner:Show()
    end
    -- Our own textures: their layer may change in combat, as items are used.
    -- HasItem is 1 or nil (ContainerFrameItemButtonMixin:SetHasItem), never secret.
    local empty = not button:HasItem()
    if record.slotEmpty ~= empty then LayerSurface(record, empty) end
    if button.ItemSlotBackground and (activating or record.nativeBg ~= button.ItemSlotBackground) then
        self.context:Alpha(button.ItemSlotBackground, 0)
        record.nativeBg = button.ItemSlotBackground
    end
    if record.slotStyle ~= self.slotStyle then
        record.slotOuter:SetColorTexture(self.slotOuterR, self.slotOuterG, self.slotOuterB, 1)
        record.slotInner:SetColorTexture(self.slotInnerR, self.slotInnerG, self.slotInnerB, 1)
        record.slotStyle = self.slotStyle
    end
end

local function StyleVisibleSlots(self, frame)
    if not frame:IsShown() then return end
    for _, button in frame:EnumerateValidItems() do StyleSlot(self, button) end
end

local function EnsureLabel(self, button)
    local record = self.overlays[button]
    if record and record.label then return record end
    if NS.IsCombatLocked() then
        self.needsItemRefresh = true
        S.Queue("bags")
        return nil
    end
    record = record or {}
    local label = S.CreateFontString(button, nil, "OVERLAY")
    label:SetDrawLayer("OVERLAY", 7)
    label:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
    label:SetJustifyH("RIGHT")
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    record.label = label
    self.overlays[button] = record
    return record
end

local function Style(self, record)
    if record.style == self.labelStyle then return end
    local c = self.config
    S.SetStyledFont(record.label, self.fontPath, c.itemLevelSize, OUTLINES[c.fontOutline] or "OUTLINE",
        c.fontRendering, c.fontShadow, c.fontShadowOpacity, c.fontShadowDistance)
    record.style = self.labelStyle
    record.quality = nil
end

-- requested[itemID]: true while a load is out, FAILED after the client
-- answered it with success false. A failed load is not asked again until the
-- bag opens next (CombinedShown), as BankItemLevel.lua does for the bank:
-- the client would answer each new request with another failure at once.
local FAILED = "failed"

-- Queues a button until its item data arrives (GET_ITEM_INFO_RECEIVED).
local function WaitForItem(self, pending, itemID, button)
    if self.requested[itemID] == FAILED then return end
    local waiting = pending[itemID]
    if not waiting then
        local pool = self.pendingPool
        waiting = pool[#pool]
        if waiting then pool[#pool] = nil else waiting = {} end
        pending[itemID] = waiting
    end
    if waiting[#waiting] ~= button then waiting[#waiting + 1] = button end
    if not self.requested[itemID] then
        self.requested[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

local function PaintQuality(self, record, quality)
    if record.quality == quality then return end
    local r, g, b = 1, 1, 1
    -- WoW Forever has no global GetItemQualityColor; C_Item has it on both clients.
    if self.config.qualityColor and type(quality) == "number" then
        r, g, b = C_Item.GetItemQualityColor(quality)
        if not S.Public(r) or not S.Public(g) or not S.Public(b) then r, g, b = 1, 1, 1 end
    end
    record.label:SetTextColor(r, g, b)
    record.quality = quality
end

-- info: the slot's cached read (SlotCache.lua); callers checked bag and slot.
local function Paint(self, button, pending, info)
    local record = self.overlays[button]
    if not self.config.showItemLevel or not info or not S.Public(info) then
        Hide(record)
        return
    end
    if S.Public(info.isFiltered) and info.isFiltered then
        Hide(record)
        return
    end
    local link, itemID, quality = info.hyperlink, info.itemID, info.quality
    if not link or not S.Public(link) or not S.Public(itemID) or not S.Public(quality) then
        Hide(record)
        return
    end
    if not record then
        record = {}
        self.overlays[button] = record
    end
    if record.link ~= link then record.link, record.level, record.gear = link, nil, nil end
    if record.gear == nil then
        local equippable = C_Item.IsEquippableItem(link)
        if not S.Public(equippable) then
            Hide(record)
            return
        end
        record.gear = equippable == true
    end
    if not record.gear then
        if record.label then record.label:Hide() end
        return
    end
    record = EnsureLabel(self, button)
    if not record then return end
    Style(self, record)
    if record.level == nil then
        local level = C_Item.GetDetailedItemLevelInfo(link)
        if S.Public(level) and type(level) == "number" and level > 0 then
            record.level = level
            record.label:SetText(tostring(level))
        elseif type(itemID) == "number" then
            WaitForItem(self, pending, itemID, button)
        end
    end
    if not record.level then
        record.label:Hide()
        return
    end
    PaintQuality(self, record, quality)
    record.label:Show()
end

-- Enum.ItemBind (ItemConstantsDocumentation, Retail and Forever). Both
-- account bindings are Warbound; Bind on Equip and Warbound until equipped
-- show only while the item is not bound yet.
local BIND = Enum.ItemBind
local BIND_BADGES = {
    [BIND.OnEquip] = "BoE", [BIND.ToWoWAccount] = "WB", [BIND.ToBnetAccount] = "WB",
    [BIND.ToBnetAccountUntilEquipped] = "WuE",
}
local UNTIL_BOUND = { [BIND.OnEquip] = true, [BIND.ToBnetAccountUntilEquipped] = true }

local function PaintBindBadge(self, button, pending, info)
    local record = self.overlays[button]
    if not self.config.showBindBadge or NS.Client.isForever or not info or not S.Public(info)
        or not S.Public(info.hyperlink) or not S.Public(info.itemID)
        or (S.Public(info.isFiltered) and info.isFiltered) then
        if record and record.bindBadge then record.bindBadge:Hide() end
        return
    end
    record = record or {}
    self.overlays[button] = record
    local link = info.hyperlink
    if record.bindLink ~= link then
        record.bindLink, record.bindType = link, nil
    end
    if record.bindType == nil then
        local bindType = select(14, C_Item.GetItemInfo(link))
        if not S.Finite(bindType) then
            if S.Finite(info.itemID) then WaitForItem(self, pending, info.itemID, button) end
            if record.bindBadge then record.bindBadge:Hide() end
            return
        end
        record.bindType = bindType
    end
    local text = BIND_BADGES[record.bindType]
    if UNTIL_BOUND[record.bindType] and (not S.Public(info.isBound) or info.isBound ~= false) then text = nil end
    if not text then
        if record.bindBadge then record.bindBadge:Hide() end
        return
    end
    if not record.bindBadge then
        if NS.IsCombatLocked() then
            self.needsItemRefresh = true
            S.Queue("bags")
            return
        end
        local badge = S.CreateFontString(button, nil, "OVERLAY")
        badge:SetDrawLayer("OVERLAY", 7)
        badge:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
        badge:SetJustifyH("LEFT")
        badge:SetShadowOffset(1, -1)
        badge:SetShadowColor(0, 0, 0, 1)
        record.bindBadge = badge
    end
    if not record.bindStyled or record.bindFontEpoch ~= self.fontEpoch then
        S.SetFont(record.bindBadge, nil, 10, "OUTLINE")
        record.bindStyled, record.bindFontEpoch = true, self.fontEpoch
    end
    -- A refresh repaints only a badge whose text changed.
    if record.bindText ~= text then
        record.bindBadge:SetText(text)
        record.bindBadge:SetTextColor(text == "BoE" and .55 or .92, text == "BoE" and .85 or .76, .98)
        record.bindText = text
    end
    record.bindBadge:Show()
end

local function ItemInfoReceived(module, _, itemID, success)
    if not S.Public(itemID) then return end
    local waiting = module.pending[itemID]
    local bankWaiting = module.bankPending[itemID]
    if not waiting and not bankWaiting then return end
    local loaded = S.Public(success) and success == true
    module.pending[itemID] = nil
    module.requested[itemID] = waiting and not loaded and FAILED or nil
    if waiting and module.frame and module.frame:IsShown() then
        for i = 1, #waiting do
            local button = waiting[i]
            local bag, slot = button:GetBagID(), button:GetID()
            local info = S.Finite(bag) and S.Finite(slot) and Slots.Get(bag, slot)
            if module.config.showItemLevel then Paint(module, button, module.pending, info) end
            PaintBindBadge(module, button, module.pending, info)
        end
    end
    if waiting then
        for i = #waiting, 1, -1 do waiting[i] = nil end
        module.pendingPool[#module.pendingPool + 1] = waiting
    end
    if bankWaiting then module:OnBankItemInfoReceived(itemID, success, bankWaiting) end
    if not next(module.pending) and not next(module.bankPending) then
        module.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
    end
end
M.ItemInfoReceived = ItemInfoReceived
M.StyleItemLevel = Style
M.PaintItemLevelQuality = PaintQuality

local function HideItemLevels(self)
    if self.itemLevelsHidden then return end
    for _, record in pairs(self.overlays) do
        if record.label then record.label:Hide() end
    end
    ClearPending(self)
    for itemID in pairs(self.requested) do self.requested[itemID] = nil end
    if not next(self.bankPending) then self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED") end
    self.itemLevelsHidden = true
end

local function HideBindBadges(self)
    if self.bindBadgesHidden then return end
    for _, record in pairs(self.overlays) do
        if record.bindBadge then record.bindBadge:Hide() end
    end
    self.bindBadgesHidden = true
end

-- Bags.lua, the inventory view and the bank view read slots through the
-- shared cache (SlotCache.lua): an unchanged bag costs no client call.
function M:UpdateVisible()
    local frame = self.frame
    if not self.active or not frame or not frame:IsShown() then return end
    if NS.IsCombatLocked() then self.needsItemRefresh = true end
    if not self.config.showItemLevel then HideItemLevels(self)
    else self.itemLevelsHidden = false end
    if not self.config.showBindBadge then HideBindBadges(self)
    else self.bindBadgesHidden = false end

    if not self.config.showItemLevel and not self.config.showBindBadge then
        StyleVisibleSlots(self, frame)
        return
    end
    local pending = self.pending
    ClearPending(self)
    for bag = 0, Constants.InventoryConstants.NumBagSlots do Slots.Sync(bag) end
    for _, button in frame:EnumerateValidItems() do
        StyleSlot(self, button)
        local bag, slot = button:GetBagID(), button:GetID()
        local info = S.Finite(bag) and S.Finite(slot) and Slots.Get(bag, slot)
        if not info then
            Hide(self.overlays[button])
        else
            if self.config.showItemLevel then Paint(self, button, pending, info) end
            PaintBindBadge(self, button, pending, info)
        end
    end
    for itemID, request in pairs(self.requested) do
        if request ~= FAILED and not pending[itemID] then self.requested[itemID] = nil end
    end
    if next(pending) or next(self.bankPending) then
        self.context:Event("GET_ITEM_INFO_RECEIVED", ItemInfoReceived, true)
    else
        self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function RefreshMovers()
    if M.active then S.RefreshOwnedMovers("bags") end
end

local function CombinedItemsUpdated()
    if M.active then M:UpdateVisible() end
end

local function CombinedShown()
    if not M.active then return end
    for itemID, request in pairs(M.requested) do
        if request == FAILED then M.requested[itemID] = nil end
    end
    M:UpdateVisible()
    M:RefreshWindowLayout()
    RefreshMovers()
end

local function ReagentItemsUpdated()
    if M.active then StyleVisibleSlots(M, ContainerFrame6) end
end

local function ReagentShown()
    if not M.active then return end
    StyleVisibleSlots(M, ContainerFrame6)
    M:RefreshWindowLayout()
    RefreshMovers()
end

local function InstallHooks(self)
    if self.hooked then return end
    local frame = self.frame
    hooksecurefunc(frame, "UpdateItems", CombinedItemsUpdated)
    frame:HookScript("OnShow", CombinedShown)
    frame:HookScript("OnHide", RefreshMovers)
    hooksecurefunc(ContainerFrame6, "UpdateItems", ReagentItemsUpdated)
    ContainerFrame6:HookScript("OnShow", ReagentShown)
    ContainerFrame6:HookScript("OnHide", RefreshMovers)
    hooksecurefunc("UpdateContainerFrameAnchors", M.AfterNativeWindowLayout)
    self.hooked = true
end

local function CombinedModeChanged(module)
    local mode = C_CVar.GetCVar("combinedBags")
    if S.Public(mode) and mode == "0" then
        if NS.IsCombatLocked() then
            S.Queue("bags")
        else
            module.context:CVar("combinedBags", 1)
        end
    end
end

local function CombatEnded(module)
    module:RefreshWindowLayout()
end

-- The Bags sub-modules, run in this order after this file's own refresh and
-- stop. Each entry: the Private table its file exports, its refresh method,
-- its stop method (nil: nothing to do there); retail: the file loads on
-- Retail only. Their files load after this one.
local SUBMODULES = {
    { "InventoryView", "Refresh", "Disable" },                -- the Suite grid of the combined bag
    { "BankInventory", "Refresh", "Disable", retail = true }, -- the organized bank view
    { "BagFinance", "Enable", "Disable" },                    -- the currency and gold history line
    { "AutoSplit", nil, "Stop" },                             -- a running automatic split
    { "StackSplitter", "Refresh", "Close" },                  -- split presets beside Blizzard's window
    { "SortDirection", "Refresh", "Restore" },                -- Blizzard's bag sorting direction
}
M.SUBMODULES = SUBMODULES
local REFRESH, STOP = 2, 3

local function RunSubmodules(slot)
    for i = 1, #SUBMODULES do
        local entry = SUBMODULES[i]
        local method = entry[slot]
        if method and not (entry.retail and NS.Client.isForever) then Private[entry[1]][method]() end
    end
end

function M:Enable()
    self.frame = ContainerFrameCombinedBags
    Slots.Start()
    InstallHooks(self)
    self.context:Event("USE_COMBINED_BAGS_CHANGED", CombinedModeChanged, true)
    self.context:Event("PLAYER_REGEN_ENABLED", CombatEnded, true)
    self:ApplyBankLevels()
    self:Refresh()
end

-- The settings each refresh step repaints from. The item level text reads
-- every setting of the catalog section "itemLevels" (MSUF_Suite/Core/Catalog/
-- Bags.lua) except its switches, so a new text option joins it on its own.
local SLOT_KEYS = { "backgroundColor", "accentColor" }
local WINDOW_KEYS = { "backgroundOpacity" }
local LEVEL_KEYS = { "showItemLevel", "showBindBadge", "showBankItemLevel" }
local GOLD_KEYS = { "showSessionGold" }
local LABEL_KEYS, VISUAL_KEYS = {}, {}
do
    local switches = {}
    for i = 1, #LEVEL_KEYS do switches[LEVEL_KEYS[i]] = true end
    for _, rule in ipairs(NS.SuiteCatalog.bags.controls) do
        if rule.section == "itemLevels" and not switches[rule.key] then LABEL_KEYS[#LABEL_KEYS + 1] = rule.key end
    end
    for _, keys in ipairs({ SLOT_KEYS, WINDOW_KEYS, LABEL_KEYS, LEVEL_KEYS, GOLD_KEYS }) do
        for i = 1, #keys do VISUAL_KEYS[#VISUAL_KEYS + 1] = keys[i] end
    end
end

local function Changed(c, last, keys)
    for i = 1, #keys do
        if last[keys[i]] ~= c[keys[i]] then return true end
    end
    return false
end

-- slot, window, label, level and gold: whether each step must run again.
local function VisualChanges(c, last)
    if not last then return true, true, true, true, true end
    local slot = Changed(c, last, SLOT_KEYS)
    local window = slot or Changed(c, last, WINDOW_KEYS) or last.editMode ~= S.editMode
    return slot, window, Changed(c, last, LABEL_KEYS), Changed(c, last, LEVEL_KEYS), Changed(c, last, GOLD_KEYS)
end

local function RememberVisuals(self, c)
    local last = self.appliedVisual or {}
    for i = 1, #VISUAL_KEYS do last[VISUAL_KEYS[i]] = c[VISUAL_KEYS[i]] end
    last.editMode = S.editMode
    self.appliedVisual = last
end

function M:Refresh()
    if not self.combinedBagConfigured then
        if not self.context:CVar("combinedBags", 1) then
            error("MSUF Suite Bags could not enable Blizzard's combined bag")
        end
        self.combinedBagConfigured = true
    end
    local c, last = self.config, self.appliedVisual
    local slotChanged, windowChanged, labelChanged, levelChanged, goldChanged = VisualChanges(c, last)
    local fontPath, fontEpoch = S.ResolveFont(c.font) or S.GlobalFontPath(), _G.MSUF_FontApplyEpoch
    if self.fontPath ~= fontPath or self.fontEpoch ~= fontEpoch then
        self.fontPath, self.fontEpoch = fontPath, fontEpoch
        labelChanged = true
        for _, record in pairs(self.overlays) do record.bindStyled = nil end
    end
    if windowChanged then self:StyleWindows() end
    if goldChanged then self:ApplyGoldEvents() end
    if labelChanged then
        if self.windows then
            for _, textures in pairs(self.windows) do
                if textures.goldLabel then S.SetFont(textures.goldLabel, S.ResolveFont(c.font), 11, "OUTLINE") end
            end
        end
        self.labelStyle = (self.labelStyle or 0) + 1
    end
    if slotChanged then
        local r, g, b = S.RGB(c.backgroundColor)
        local accentR, accentG, accentB = S.RGB(c.accentColor)
        self.slotOuterR, self.slotOuterG, self.slotOuterB =
            accentR * 0.18 + r * 0.82, accentG * 0.18 + g * 0.82, accentB * 0.18 + b * 0.82
        self.slotInnerR, self.slotInnerG, self.slotInnerB =
            r + (1 - r) * 0.05, g + (1 - g) * 0.05, b + (1 - b) * 0.05
        self.slotStyle = (self.slotStyle or 0) + 1
    end
    local deferredItems = self.needsItemRefresh
    if slotChanged or labelChanged or levelChanged or deferredItems then self:UpdateVisible() end
    if labelChanged or levelChanged or self.needsBankRefresh then
        self:ApplyBankLevels()
        self.needsBankRefresh = nil
    end
    if slotChanged or deferredItems then StyleVisibleSlots(self, ContainerFrame6) end
    self.needsItemRefresh = nil
    self:RefreshWindowLayout()
    RememberVisuals(self, c)
    RunSubmodules(REFRESH)
end


function M:Disable()
    self:CancelWindowDrag()
    self.combinedBagConfigured = nil
    self.appliedVisual = nil
    self.context:RemoveEvent("PLAYER_MONEY")
    self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
    for _, record in pairs(self.overlays) do
        Hide(record)
        if record.slotOuter then
            record.slotOuter:Hide()
            record.slotInner:Hide()
            record.slotNativeActive = false
            record.nativeBg = nil
        end
    end
    self:HideBankLevels()
    self.context:RemoveEvent("BANKFRAME_OPENED")
    self:RestoreWindows()
    Slots.Stop()
    ClearPending(self)
    self.pending, self.pendingPool, self.requested = {}, {}, {}
    M.NativeAnchorPass()
    self.nativeScale = nil
    self.frame = nil
    RunSubmodules(STOP)
end

Private.BagsModule = M
S.Install("bags", M)
