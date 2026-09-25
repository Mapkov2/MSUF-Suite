local _, Private = ...
local NS, S = Private.NS, Private.Suite
-- The bags catalog entry declares combinedBags, so the controller hands the
-- player's value back when the module is disabled.
local M = { overlays = setmetatable({}, { __mode = "k" }), pending = {}, pendingPool = {}, requested = {} }
local GOLD_FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local OUTLINES = { "OUTLINE", "THICKOUTLINE", "" }
local floor = math.floor
local TEXT = {
    session = S.Text("Session"),
    drag = S.Text("Drag to move"),
    options = S.Text("Click for bag options"),
}
local NO_VALUE = "—"

local Finite = S.Finite

local function PublicMoney()
    if type(_G.GetMoney) ~= "function" then return nil end
    local value = GetMoney()
    if not Finite(value) or value < 0 then return nil end
    return floor(value)
end

local function MoneyText(amount)
    local gold, silver, copper = floor(amount / 10000), floor(amount % 10000 / 100), amount % 100
    local text = gold > 0 and gold .. "g" or nil
    if silver > 0 then text = text and text .. " " .. silver .. "s" or silver .. "s" end
    if copper > 0 or not text then text = text and text .. " " .. copper .. "c" or copper .. "c" end
    return text
end

local function GoldDeltaText(delta)
    return TEXT.session .. " " .. (delta > 0 and "+" or delta < 0 and "-" or "") .. MoneyText(math.abs(delta))
end

-- Own the window surface while Blizzard keeps the item buttons and controls.
-- The native flat background is level 0, its item buttons are level 10, and
-- its decorative NineSlice is level 500 (upstream/live ContainerFrame.xml).
-- A Suite surface at the background level fills the window below controls.
local function WindowTexture(frame, layer, sublevel)
    return S.CreateTexture(frame, nil, layer, nil, sublevel)
end

local function Edge(shell, from, to)
    local texture = WindowTexture(shell, "ARTWORK", -6)
    texture:SetPoint(from, shell, from, 0, 0)
    texture:SetPoint(to, shell, to, 0, 0)
    return texture
end

local function NewGoldLabel(frame)
    local goldLabel = S.CreateFontString(frame.MoneyFrame, nil, "OVERLAY")
    -- Blizzard moves the money row above tracked currencies, so follow
    -- that row rather than keeping the label at the bag's bottom edge.
    goldLabel:SetPoint("LEFT", frame.MoneyFrame, "LEFT", 4, 0)
    -- The combined bag is 430px wide on upstream/live (10 x 37px items,
    -- 5px gaps, 15px padding). Blizzard caps the right-side coin display
    -- at 168px, leaving this area clear of its clickable coin buttons.
    goldLabel:SetWidth(210)
    goldLabel:SetJustifyH("LEFT")
    if type(goldLabel.SetWordWrap) == "function" then goldLabel:SetWordWrap(false) end
    goldLabel:Hide()
    return goldLabel
end

-- Returns the window style: textures [1] shadow, [2] body, [3] header,
-- [4] header line, [5] footer (combined bag only), [6..9] border edges.
local function NewWindowStyle(frame, combined)
    local panel = frame.Bg
    if not panel or not frame.NineSlice then return nil end

    local shadow = WindowTexture(frame, "BACKGROUND", -8)
    shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
    shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)

    local shell = S.CreateFrame("Frame", nil, frame)
    shell:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    shell:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    shell:SetFrameLevel(panel:GetFrameLevel())
    shell:EnableMouse(false)

    local body = WindowTexture(shell, "BACKGROUND", -7)
    body:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", 0, 0)

    local header = WindowTexture(shell, "BORDER", -7)
    header:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", shell, "TOPRIGHT", 0, 0)
    header:SetHeight(combined and 62 or 40)

    local line = WindowTexture(shell, "ARTWORK", -7)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)

    local footer, goldLabel
    if combined then
        footer = WindowTexture(shell, "BORDER", -6)
        footer:SetPoint("BOTTOMLEFT", shell, "BOTTOMLEFT", 0, 0)
        footer:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", 0, 0)
        footer:SetHeight(32)
        goldLabel = NewGoldLabel(frame)
    end

    local top = Edge(shell, "TOPLEFT", "TOPRIGHT")
    top:SetHeight(1)
    local bottom = Edge(shell, "BOTTOMLEFT", "BOTTOMRIGHT")
    bottom:SetHeight(1)
    local left = Edge(shell, "TOPLEFT", "BOTTOMLEFT")
    left:SetWidth(1)
    local right = Edge(shell, "TOPRIGHT", "BOTTOMRIGHT")
    right:SetWidth(1)
    return { shell = shell, shadow, body, header, line, footer, top, bottom, left, right, goldLabel = goldLabel }
end

-- Title drag handles share these scripts; handle.window is the bag frame.
local function HandleMouseDown(handle) handle.ignoreClick = false end

local function HandleClick(handle, button)
    if handle.ignoreClick then
        handle.ignoreClick = false
        return
    end
    if button ~= "LeftButton" or (type(IsShiftKeyDown) == "function" and IsShiftKeyDown()) then return end
    local menu = handle.window.PortraitButton
    if menu and type(menu.IsMenuOpen) == "function" and type(menu.SetMenuOpen) == "function" then
        menu:SetMenuOpen(not menu:IsMenuOpen())
    end
end

local function HandleDragStart(handle) M:BeginWindowDrag(handle.window) end

local function HandleDragStop(handle)
    handle.ignoreClick = true
    M:EndWindowDrag(handle.window)
end

local function HandleHide(handle)
    if M.dragWindow and M.dragWindow.frame == handle.window then M:CancelWindowDrag() end
end

local function HandleEnter(handle)
    if not GameTooltip then return end
    GameTooltip:SetOwner(handle, "ANCHOR_TOP")
    GameTooltip:SetText(TEXT.drag)
    GameTooltip:AddLine(TEXT.options, 0.75, 0.8, 0.85)
    GameTooltip:Show()
end

local function HandleLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function NewDragHandle(frame)
    local title = frame.TitleContainer
    if not title or not frame.PortraitButton then return nil end
    local handle = S.CreateFrame("Button", nil, frame)
    handle.window = frame
    handle:SetAllPoints(title)
    handle:SetFrameLevel(math.max(title:GetFrameLevel(), frame.PortraitButton:GetFrameLevel()) + 1)
    handle:EnableMouse(true)
    handle:RegisterForClicks("LeftButtonUp")
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnMouseDown", HandleMouseDown)
    handle:SetScript("OnClick", HandleClick)
    handle:SetScript("OnDragStart", HandleDragStart)
    handle:SetScript("OnDragStop", HandleDragStop)
    handle:SetScript("OnHide", HandleHide)
    handle:SetScript("OnEnter", HandleEnter)
    handle:SetScript("OnLeave", HandleLeave)
    return handle
end

local function PaintWindow(textures, c)
    local r, g, b = S.RGB(c.backgroundColor)
    local accentR, accentG, accentB = S.RGB(c.accentColor)
    local opacity = c.backgroundOpacity / 100
    textures[1]:SetColorTexture(0, 0, 0, 0.6 * opacity)
    textures[2]:SetColorTexture(r, g, b, opacity)
    textures[3]:SetColorTexture(r + (1 - r) * 0.12, g + (1 - g) * 0.12, b + (1 - b) * 0.12, opacity)
    textures[4]:SetColorTexture(accentR, accentG, accentB, 0.9)
    if textures[5] then textures[5]:SetColorTexture(r * 0.7, g * 0.7, b * 0.7, opacity) end
    textures[6]:SetColorTexture(accentR, accentG, accentB, 0.8)
    for i = 7, 9 do
        textures[i]:SetColorTexture(r + (1 - r) * 0.2, g + (1 - g) * 0.2, b + (1 - b) * 0.2, 0.95)
    end
    if textures.goldLabel then S.SetFont(textures.goldLabel, GOLD_FONT, 11, "OUTLINE") end
end

-- Blizzard's title router forwards to PortraitButton, so the bag menu
-- remains available from the heading. Hide the full button: the Suite
-- skin can otherwise leave a styled but empty plate in this corner.
local function OwnChrome(self, frame, textures)
    local context = self.context
    context:Alpha(frame.Bg, 0)
    context:Alpha(frame.NineSlice, 0)
    if frame.PortraitContainer then context:Alpha(frame.PortraitContainer, 0) end
    if frame.PortraitButton then context:HideControl(frame.PortraitButton, true) end
    local title = frame.TitleContainer
    if not title or NS.IsCombatLocked() then return end
    if type(frame.SetTitleOffsets) == "function" then
        if not textures.titlePoints then
            local points = {}
            for point = 1, title:GetNumPoints() do points[point] = { title:GetPoint(point) } end
            textures.titlePoints = points
        end
        frame:SetTitleOffsets(8)
    end
    if not textures.dragHandle then textures.dragHandle = NewDragHandle(frame) end
end

local function StyleWindows(self)
    self.windows = self.windows or {}
    local targets = { _G.ContainerFrameCombinedBags, _G.ContainerFrame6 }
    for i = 1, #targets do
        local frame = targets[i]
        if frame and not self.windows[frame] then self.windows[frame] = NewWindowStyle(frame, i == 1) end
    end
    for frame, textures in pairs(self.windows) do
        textures.shell:Show()
        textures[1]:Show()
        OwnChrome(self, frame, textures)
        if textures.dragHandle then textures.dragHandle:SetShown(not S.editMode) end
        PaintWindow(textures, self.config)
    end
end

-- The login baseline is captured by MSUF Suite at PLAYER_ENTERING_WORLD.
-- When it is unreadable, the first public amount seen here becomes it.
local function GoldBaseline(self, money)
    local key = type(_G.UnitGUID) == "function" and UnitGUID("player") or nil
    if not S.Public(key) or type(key) ~= "string" then key = nil end
    local root = NS.RootDB
    local baseline = type(root) == "table" and type(root.suiteGold) == "table" and key and root.suiteGold[key] or nil
    if NS.loginKind == "login" and NS.goldSessionCaptured ~= true then baseline = nil end
    if Finite(baseline) and baseline >= 0 then return baseline end
    if not money then return nil end
    self.goldFallback = self.goldFallback or money
    if NS.loginKind and type(root) == "table" and key then
        if type(root.suiteGold) ~= "table" then root.suiteGold = {} end
        root.suiteGold[key] = self.goldFallback
        NS.goldSessionCaptured = true
    end
    return self.goldFallback
end

function M:UpdateGold()
    local style = self.windows and self.frame and self.windows[self.frame]
    local label = style and style.goldLabel
    if not label then return end
    if not self.config.showSessionGold then
        label:Hide()
        return
    end
    local money = PublicMoney()
    local baseline = GoldBaseline(self, money)
    if not money or not baseline then
        label:SetText(TEXT.session .. " " .. NO_VALUE)
        label:SetTextColor(0.72, 0.77, 0.82)
    else
        local delta = money - baseline
        label:SetText(GoldDeltaText(delta))
        if delta > 0 then
            label:SetTextColor(0.33, 0.86, 0.62)
        elseif delta < 0 then
            label:SetTextColor(0.94, 0.43, 0.45)
        else
            label:SetTextColor(0.72, 0.77, 0.82)
        end
    end
    label:Show()
end

local function ApplyGoldEvents(self)
    if self.config.showSessionGold then
        self.context:Event("PLAYER_MONEY", M.UpdateGold, true)
        self.context:Event("PLAYER_ENTERING_WORLD", M.UpdateGold, true)
    else
        self.context:RemoveEvent("PLAYER_MONEY")
        self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
    end
    self:UpdateGold()
end

-- GetScaledRect and GetCursorPosition are both in screen pixels. Convert the
-- window's current bottom-right edge into its own anchor units so dragging
-- works at any UI scale, including Blizzard's automatic bag scale.
local function WindowOffset(frame)
    if type(frame.GetScaledRect) ~= "function" or type(frame.GetEffectiveScale) ~= "function"
        or type(UIParent.GetScaledRect) ~= "function" then
        return nil
    end
    local left, bottom, width = frame:GetScaledRect()
    local parentLeft, parentBottom, parentWidth = UIParent:GetScaledRect()
    local scale = frame:GetEffectiveScale()
    if not Finite(left) or not Finite(bottom) or not Finite(width)
        or not Finite(parentLeft) or not Finite(parentBottom) or not Finite(parentWidth)
        or not Finite(scale) or scale <= 0 then
        return nil
    end
    return (left + width - parentLeft - parentWidth) / scale, (bottom - parentBottom) / scale, scale
end

function M:BeginWindowDrag(frame)
    if not self.active or NS.IsCombatLocked() or S.editMode or not frame:IsShown()
        or type(_G.GetCursorPosition) ~= "function" or self.dragWindow then
        return
    end
    -- StartMoving raises on a frame that is not movable.
    if type(frame.IsMovable) == "function" and not frame:IsMovable() then return end
    local x, y, scale = WindowOffset(frame)
    local cursorX, cursorY = GetCursorPosition()
    if not x or not Finite(cursorX) or not Finite(cursorY) then return end
    self.dragWindow = { frame = frame, x = x, y = y, scale = scale, cursorX = cursorX, cursorY = cursorY }
    frame:StartMoving()
end

function M:CancelWindowDrag()
    local drag = self.dragWindow
    if not drag then return end
    self.dragWindow = nil
    drag.frame:StopMovingOrSizing()
    if self.active and not NS.IsCombatLocked() then self:RefreshWindowLayout() end
end

function M:EndWindowDrag(frame)
    local drag = self.dragWindow
    if not drag or drag.frame ~= frame then return end
    self.dragWindow = nil
    frame:StopMovingOrSizing()
    if not self.active or NS.IsCombatLocked() then return end
    local cursorX, cursorY = GetCursorPosition()
    if not Finite(cursorX) or not Finite(cursorY) then
        self:RefreshWindowLayout()
        return
    end
    local x = floor((drag.x + (cursorX - drag.cursorX) / drag.scale) * 10 + 0.5) / 10
    local y = floor((drag.y + (cursorY - drag.cursorY) / drag.scale) * 10 + 0.5) / 10
    local values
    if frame == self.frame then
        values = { windowX = x, windowY = y, windowMoved = true }
    else
        values = { reagentWindowX = x, reagentWindowY = y, reagentWindowMoved = true }
    end
    if not S.SetMany("bags", values) then self:RefreshWindowLayout() end
end

-- The value S.Set would store: offsets are whole units within the rule's range.
local function OffsetSetting(key, value)
    local rule = S.catalog and S.catalog.bags and S.catalog.bags.rules[key]
    if rule then value = math.max(rule.min, math.min(rule.max, value)) end
    return floor(value)
end

-- Blizzard anchors the combined bag's BOTTOMRIGHT to UIParent's BOTTOMRIGHT.
-- Other anchors (a chained bag column) are no UIParent offset and are skipped.
local function NativeOffset(frame)
    local point, relative, relativePoint, x, y = frame:GetPoint(1)
    if not S.Public(point) or not S.Public(relative) or not S.Public(relativePoint)
        or point ~= "BOTTOMRIGHT" or relative ~= UIParent or relativePoint ~= "BOTTOMRIGHT"
        or not Finite(x) or not Finite(y) then
        return nil
    end
    return OffsetSetting("windowX", x), OffsetSetting("windowY", y)
end

-- MSUF Edit Mode starts a drag from windowX/windowY. While the window follows
-- Blizzard's anchor, those settings mirror it through the normal settings
-- path one frame later (never inside Enable/Refresh); a combat defers the
-- write until PLAYER_REGEN_ENABLED.
local function SyncNativeOffset()
    M.nativeSyncQueued = nil
    local c = M.config
    if not M.active or not c or c.windowMoved or not M.nativeX then return end
    if c.windowX == M.nativeX and c.windowY == M.nativeY then return end
    if NS.IsCombatLocked() then
        M.nativeSyncPending = true
        return
    end
    M.nativeSyncPending = nil
    S.SetMany("bags", { windowX = M.nativeX, windowY = M.nativeY })
end

local function RecordNativeOffset(frame)
    local x, y = NativeOffset(frame)
    if not x then return end
    M.nativeX, M.nativeY = x, y
    if (x ~= M.config.windowX or y ~= M.config.windowY) and not M.nativeSyncQueued
        and C_Timer and type(C_Timer.After) == "function" then
        M.nativeSyncQueued = true
        C_Timer.After(0, SyncNativeOffset)
    end
end

-- Blizzard recalculates the combined bag's anchor and scale whenever its
-- container layout changes. Reapply the Suite adjustment after that native
-- layout, while leaving the window's item grid and click handlers untouched.
local function AfterNativeWindowLayout()
    if not M.active or NS.IsCombatLocked() then return end
    local frame = M.frame
    if frame and frame:IsShown() then
        local scale = frame:GetScale()
        if (type(_G.UpdateContainerFrameAnchors) == "function" or not M.nativeScale)
            and Finite(scale) and scale > 0 then
            M.nativeScale = scale
        end
        if not M.config.windowMoved then RecordNativeOffset(frame) end
    end
    M:ApplyWindowLayout()
end

function M:ApplyWindowLayout()
    local frame = self.frame
    if not self.active or NS.IsCombatLocked() then return end
    local c = self.config
    if frame and frame:IsShown() then
        local nativeScale = self.nativeScale or frame:GetScale()
        if Finite(nativeScale) and nativeScale > 0 then self.context:Scale(frame, nativeScale * c.windowScale) end
        if c.windowMoved then self.context:Position(frame, "BOTTOMRIGHT", c.windowX, c.windowY) end
    end
    local reagent = _G.ContainerFrame6
    if reagent and reagent:IsShown() and c.reagentWindowMoved then
        self.context:Position(reagent, "BOTTOMRIGHT", c.reagentWindowX, c.reagentWindowY)
    end
end

function M:RefreshWindowLayout()
    local reagent = _G.ContainerFrame6
    if NS.IsCombatLocked() or not ((self.frame and self.frame:IsShown())
        or (reagent and reagent:IsShown())) then
        return
    end
    if type(_G.UpdateContainerFrameAnchors) == "function" then
        UpdateContainerFrameAnchors()
        if not self.nativeAnchorHooked then AfterNativeWindowLayout() end
    else
        AfterNativeWindowLayout()
    end
end

local function Hide(record)
    if not record then return end
    if record.label then record.label:Hide() end
    record.link, record.level, record.quality, record.gear = nil, nil, nil, nil
end

local function ClearPending(self)
    local pending, pool = self.pending, self.pendingPool
    for itemID, buttons in pairs(pending) do
        for i = #buttons, 1, -1 do buttons[i] = nil end
        pending[itemID] = nil
        pool[#pool + 1] = buttons
    end
end

-- The native empty-slot icon atlas and combined-bag background are separate
-- from the actual item icon. Keep Blizzard's item button and all its handlers,
-- but let an empty slot show a quiet Suite surface instead of the bag artwork.
local function RefreshEmptyIcon(button)
    local hasItem = button:HasItem()
    if S.Public(hasItem) and not hasItem then button:SetItemButtonTexture(nil) end
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
            local outer = WindowTexture(button, "BACKGROUND", -5)
            outer:SetAllPoints(button)
            local inner = WindowTexture(button, "BACKGROUND", -4)
            inner:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            record.slotOuter, record.slotInner = outer, inner
        end
        self.context:Field(button, "emptyBackgroundAtlas", false, RefreshEmptyIcon)
        RefreshEmptyIcon(button)
        record.slotNativeActive = true
    end
    if activating then
        record.slotOuter:Show()
        record.slotInner:Show()
    end
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
    if not frame or not frame:IsShown() then return end
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

-- Queues a button until its item data arrives (GET_ITEM_INFO_RECEIVED).
local function WaitForItem(self, pending, itemID, button)
    local waiting = pending[itemID]
    if not waiting then
        local pool = self.pendingPool
        waiting = pool[#pool]
        if waiting then pool[#pool] = nil else waiting = {} end
        pending[itemID] = waiting
    end
    waiting[#waiting + 1] = button
    if not self.requested[itemID] and type(C_Item.RequestLoadItemDataByID) == "function" then
        self.requested[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

local function PaintQuality(self, record, quality)
    if record.quality == quality then return end
    local r, g, b = 1, 1, 1
    if self.config.qualityColor and type(quality) == "number" and type(GetItemQualityColor) == "function" then
        r, g, b = GetItemQualityColor(quality)
        if not S.Public(r) or not S.Public(g) or not S.Public(b) then r, g, b = 1, 1, 1 end
    end
    record.label:SetTextColor(r, g, b)
    record.quality = quality
end

local function Paint(self, button, pending)
    local bag, slot = button:GetBagID(), button:GetID()
    if not S.Public(bag) or not S.Public(slot) then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
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

local function ItemInfoReceived(module, _, itemID)
    if not S.Public(itemID) then return end
    local waiting = module.pending[itemID]
    if not waiting then return end
    module.pending[itemID], module.requested[itemID] = nil, nil
    if module.frame and module.frame:IsShown() then
        for i = 1, #waiting do Paint(module, waiting[i], module.pending) end
    end
    for i = #waiting, 1, -1 do waiting[i] = nil end
    module.pendingPool[#module.pendingPool + 1] = waiting
    if not next(module.pending) then module.context:RemoveEvent("GET_ITEM_INFO_RECEIVED") end
end

local function HideItemLevels(self)
    if self.itemLevelsHidden then return end
    for _, record in pairs(self.overlays) do
        if record.label then record.label:Hide() end
    end
    ClearPending(self)
    for itemID in pairs(self.requested) do self.requested[itemID] = nil end
    self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
    self.itemLevelsHidden = true
end

function M:UpdateVisible(nativeItemsReady)
    local frame = self.frame
    if not self.active or not frame or not frame:IsShown() then return end
    if NS.IsCombatLocked() then self.needsItemRefresh = true end
    if not self.config.showItemLevel then
        StyleVisibleSlots(self, frame)
        HideItemLevels(self)
        return
    end
    self.itemLevelsHidden = false
    local pending = self.pending
    ClearPending(self)
    for _, button in frame:EnumerateValidItems() do
        StyleSlot(self, button)
        -- Blizzard's UpdateItems has already refreshed HasItem before its
        -- post-hook. Empty slots need no second GetContainerItemInfo call.
        local hasItem = nativeItemsReady and button:HasItem()
        if nativeItemsReady and S.Public(hasItem) and not hasItem then
            Hide(self.overlays[button])
        else
            Paint(self, button, pending)
        end
    end
    for itemID in pairs(self.requested) do
        if not pending[itemID] then self.requested[itemID] = nil end
    end
    if next(pending) then
        self.context:Event("GET_ITEM_INFO_RECEIVED", ItemInfoReceived, true)
    else
        self.context:RemoveEvent("GET_ITEM_INFO_RECEIVED")
    end
end

local function RefreshMovers()
    if M.active and S.RefreshOwnedMovers then S.RefreshOwnedMovers("bags") end
end

local function CombinedItemsUpdated()
    if M.active then M:UpdateVisible(true) end
end

local function CombinedShown()
    if not M.active then return end
    M:UpdateVisible()
    M:RefreshWindowLayout()
    RefreshMovers()
end

local function ReagentItemsUpdated()
    if M.active then StyleVisibleSlots(M, _G.ContainerFrame6) end
end

local function ReagentShown()
    if not M.active then return end
    StyleVisibleSlots(M, _G.ContainerFrame6)
    M:RefreshWindowLayout()
    RefreshMovers()
end

local function InstallHooks(self)
    if self.hooked then return end
    local frame = self.frame
    hooksecurefunc(frame, "UpdateItems", CombinedItemsUpdated)
    frame:HookScript("OnShow", CombinedShown)
    frame:HookScript("OnHide", RefreshMovers)
    local reagent = _G.ContainerFrame6
    if reagent then
        hooksecurefunc(reagent, "UpdateItems", ReagentItemsUpdated)
        reagent:HookScript("OnShow", ReagentShown)
        reagent:HookScript("OnHide", RefreshMovers)
    end
    if type(_G.UpdateContainerFrameAnchors) == "function" then
        hooksecurefunc("UpdateContainerFrameAnchors", AfterNativeWindowLayout)
        self.nativeAnchorHooked = true
    end
    self.hooked = true
end

local function CombinedModeChanged(module)
    local mode = GetCVar("combinedBags")
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
    if module.nativeSyncPending then SyncNativeOffset() end
end

function M:Enable()
    self.frame = _G.ContainerFrameCombinedBags
    InstallHooks(self)
    self.context:Event("USE_COMBINED_BAGS_CHANGED", CombinedModeChanged, true)
    self.context:Event("PLAYER_REGEN_ENABLED", CombatEnded, true)
    self:Refresh()
end

local function VisualChanges(c, last)
    local slot = not last or last.backgroundColor ~= c.backgroundColor or last.accentColor ~= c.accentColor
    local window = slot or last.backgroundOpacity ~= c.backgroundOpacity or last.editMode ~= S.editMode
    local label = not last or last.font ~= c.font
        or last.itemLevelSize ~= c.itemLevelSize or last.qualityColor ~= c.qualityColor
        or last.fontOutline ~= c.fontOutline or last.fontRendering ~= c.fontRendering
        or last.fontShadow ~= c.fontShadow or last.fontShadowOpacity ~= c.fontShadowOpacity
        or last.fontShadowDistance ~= c.fontShadowDistance
    local level = not last or last.showItemLevel ~= c.showItemLevel
    local gold = not last or last.showSessionGold ~= c.showSessionGold
    return slot, window, label, level, gold
end

local function RememberVisuals(self, c)
    local last = self.appliedVisual or {}
    last.backgroundColor, last.backgroundOpacity, last.accentColor =
        c.backgroundColor, c.backgroundOpacity, c.accentColor
    last.font, last.itemLevelSize, last.qualityColor = c.font, c.itemLevelSize, c.qualityColor
    last.fontOutline, last.fontRendering, last.fontShadow = c.fontOutline, c.fontRendering, c.fontShadow
    last.fontShadowOpacity, last.fontShadowDistance = c.fontShadowOpacity, c.fontShadowDistance
    last.showItemLevel, last.showSessionGold, last.editMode = c.showItemLevel, c.showSessionGold, S.editMode
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
    if windowChanged then StyleWindows(self) end
    if goldChanged then ApplyGoldEvents(self) end
    if labelChanged then
        if not last or last.font ~= c.font then self.fontPath = S.ResolveFont(c.font) end
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
    if slotChanged or deferredItems then StyleVisibleSlots(self, _G.ContainerFrame6) end
    self.needsItemRefresh = nil
    self:RefreshWindowLayout()
    RememberVisuals(self, c)
end

local function RestoreWindows(self)
    if not self.windows then return end
    for frame, textures in pairs(self.windows) do
        if textures.goldLabel then textures.goldLabel:Hide() end
        if textures.dragHandle then textures.dragHandle:Hide() end
        textures.shell:Hide()
        textures[1]:Hide()
        if textures.titlePoints and frame.TitleContainer and not NS.IsCombatLocked() then
            local title = frame.TitleContainer
            title:ClearAllPoints()
            for i = 1, #textures.titlePoints do title:SetPoint(unpack(textures.titlePoints[i])) end
        end
    end
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
    RestoreWindows(self)
    ClearPending(self)
    self.pending, self.pendingPool, self.requested = {}, {}, {}
    if type(_G.UpdateContainerFrameAnchors) == "function" and not NS.IsCombatLocked() then
        UpdateContainerFrameAnchors()
    end
    self.nativeScale, self.nativeX, self.nativeY, self.nativeSyncPending = nil, nil, nil, nil
    self.frame = nil
end

function M:RegisterMovers()
    S.RegisterOwnedMover("bags", "combined", {
        label = "Combined bags", order = 875,
        getFrame = function() return self.frame end,
        isEnabled = function() return self.frame and self.frame:IsShown() end,
        xKey = "windowX", yKey = "windowY", point = "BOTTOMRIGHT",
        moveValues = { windowMoved = true }, resetKeys = { "windowMoved" },
        historyKeys = { "windowMoved", "windowScale" },
        extraControls = {
            {
                id = "size", label = "Size %", kind = "number", min = 65, max = 150, step = 1,
                get = function() return floor(S.Config("bags").windowScale * 100 + 0.5) end,
                set = function(value) return S.Set("bags", "windowScale", value / 100) end,
            },
        },
    })
    S.RegisterOwnedMover("bags", "reagent", {
        label = "Reagent bag", order = 876,
        getFrame = function() return _G.ContainerFrame6 end,
        isEnabled = function() return _G.ContainerFrame6 and _G.ContainerFrame6:IsShown() end,
        xKey = "reagentWindowX", yKey = "reagentWindowY", point = "BOTTOMRIGHT",
        moveValues = { reagentWindowMoved = true }, resetKeys = { "reagentWindowMoved" },
        historyKeys = { "reagentWindowMoved" },
    })
end

S.Install("bags", M)
