local _, Private = ...
local NS, S = Private.NS, Private.Suite
local Gold = NS.GoldLedger
local M = assert(Private.BagsModule, "Bags.lua must load before BagWindow.lua")
-- The bag windows: Suite surface, title drag handles, session gold label and
-- the placement Blizzard's container layout receives after each native pass.
local floor = math.floor
local IN_COMBAT = { inCombat = true }
local WindowTexture = M.WindowTexture
local Layout = Private.BagLayout
local GOLD_PERIOD = NS.BagsGoldPeriod
local TEXT = {
    session = S.Text("Session %s"),
    today = S.Text("Today %s"),
    drag = S.Text("Drag to move"),
}
local NO_VALUE = "—"

local Finite = S.Finite
local function PublicMoney()
    local value = GetMoney()
    if not Finite(value) or value < 0 then return nil end
    return floor(value)
end

-- Losses use the ASCII hyphen-minus.
local function GoldDeltaText(format, delta)
    if not delta then return format:format(NO_VALUE) end
    return format:format((delta > 0 and "+" or delta < 0 and "-" or "") .. S.MoneyText(math.abs(delta)))
end

local function Edge(shell, from, to)
    local texture = WindowTexture(shell, "ARTWORK", -6)
    texture:SetPoint(from, shell, from, 0, 0)
    texture:SetPoint(to, shell, to, 0, 0)
    return texture
end

local function NewGoldLabel(frame)
    local goldLabel = S.CreateFontString(frame.MoneyFrame, nil, "OVERLAY")
    -- Follow Blizzard's money row as currencies move it upward.
    goldLabel:SetPoint("LEFT", frame.MoneyFrame, "LEFT", 4, 0)
    -- upstream/live leaves 210px left of the right-side coin buttons.
    goldLabel:SetWidth(210)
    goldLabel:SetJustifyH("LEFT")
    goldLabel:SetWordWrap(false)
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

    -- The combined bag animates a separate shell. Individual bags keep their
    -- skin on the native root's draw layers, beneath the pooled slot buttons
    -- and title, regardless of the frame level of Blizzard's background.
    local shell = frame
    if combined then
        shell = Private.ChildFrame("Frame", frame)
        shell:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        shell:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        shell:SetFrameLevel(panel:GetFrameLevel())
        shell:EnableMouse(false)
    end

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

    local footer, goldLabel, dailyGoldLabel
    if combined then
        footer = WindowTexture(shell, "BORDER", -6)
        footer:SetPoint("BOTTOMLEFT", shell, "BOTTOMLEFT", 0, 0)
        footer:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", 0, 0)
        footer:SetHeight(32)
        goldLabel = NewGoldLabel(frame)
        dailyGoldLabel = NewGoldLabel(frame)
    end

    local top = Edge(shell, "TOPLEFT", "TOPRIGHT")
    top:SetHeight(1)
    local bottom = Edge(shell, "BOTTOMLEFT", "BOTTOMRIGHT")
    bottom:SetHeight(1)
    local left = Edge(shell, "TOPLEFT", "BOTTOMLEFT")
    left:SetWidth(1)
    local right = Edge(shell, "TOPRIGHT", "BOTTOMRIGHT")
    right:SetWidth(1)
    return { shell = shell, shadow, body, header, line, footer, top, bottom, left, right,
        goldLabel = goldLabel, dailyGoldLabel = dailyGoldLabel,
        combined = combined, moneyAnchor = frame.MoneyFrame }
end

-- Title drag handles share these scripts; handle.window is the bag frame.
local function HandleDragStart(handle) M:BeginWindowDrag(handle.window) end

local function HandleDragStop(handle)
    M:EndWindowDrag(handle.window)
end

local function HandleHide(handle)
    if M.dragWindow and M.dragWindow.frame == handle.window then M:CancelWindowDrag() end
end

local function HandleEnter(handle)
    GameTooltip:SetOwner(handle, "ANCHOR_TOP")
    GameTooltip:SetText(TEXT.drag)
    GameTooltip:Show()
end

local function HandleLeave()
    GameTooltip:Hide()
end

local function NewDragHandle(frame)
    local title = frame.TitleContainer
    if not title or not frame.PortraitButton then return nil end
    local handle = Private.ChildFrame("Button", frame)
    handle.window = frame
    handle:SetAllPoints(title)
    handle:SetFrameLevel(math.max(title:GetFrameLevel(), frame.PortraitButton:GetFrameLevel()) + 1)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", HandleDragStart)
    handle:SetScript("OnDragStop", HandleDragStop)
    handle:SetScript("OnHide", HandleHide)
    handle:SetScript("OnEnter", HandleEnter)
    handle:SetScript("OnLeave", HandleLeave)
    return handle
end

local PaintWindow = Private.BagAppearance.Window

local function SetSkinShown(textures, shown)
    if textures.combined then
        if not shown then Private.BagMotion.Stop(textures.shell) end
        textures.shell:SetShown(shown)
    else
        for i = 2, 9 do
            local texture = textures[i]
            if texture then texture:SetShown(shown) end
        end
    end
    textures[1]:SetShown(shown and not textures.panel)
end

local function FindPortraitRouter(...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        local route = child.routeToSibling
        if S.Public(route) and route == "PortraitButton" and child.GetRouteSibling then return child end
    end
    return false
end

local function OwnChrome(self, frame, textures)
    local context = self.context
    context:Alpha(frame.Bg, 0)
    context:Alpha(frame.NineSlice, 0)
    if frame.MoneyFrame and frame.MoneyFrame.Border then context:Alpha(frame.MoneyFrame.Border, 0) end
    if frame.PortraitContainer then context:Alpha(frame.PortraitContainer, 0) end
    local standalone = frame ~= self.frame and frame ~= ContainerFrame6
    if standalone then
        if frame.Background1Slot then context:Alpha(frame.Background1Slot, 0) end
        if frame.PortraitButton then context:Alpha(frame.PortraitButton, 0) end
    elseif frame.PortraitButton then
        context:HideControl(frame.PortraitButton, true)
    end
    local title = frame.TitleContainer
    if not title or NS.IsCombatLocked() then return end
    if not textures.titlePoints then
        local points = {}
        for point = 1, title:GetNumPoints() do points[point] = { title:GetPoint(point) } end
        textures.titlePoints = points
    end
    -- The title ends before the window's caption (BagCaption.lua).
    frame:SetTitleOffsets(8, -Private.BagCaption.Inset(textures.combined))
    if not standalone then
        -- The native title proxy still opens the menu when the portrait has
        -- mouse input disabled. Mute the proxy, which Blizzard excludes from gamepad navigation.
        if textures.portraitRouter == nil then textures.portraitRouter = FindPortraitRouter(frame:GetChildren()) end
        if textures.portraitRouter then context:HideControl(textures.portraitRouter, true) end
        if not textures.dragHandle then textures.dragHandle = NewDragHandle(frame) end
    end
end

function M:UpdatePresentation()
    local t = self.windows and self.windows[self.frame]
    if not t then return end
    local combat = Private.InventoryView.layout ~= "suite"
    local panel = Private.BagPresentation.IsPanel(self.config) and not combat or false
    local rail = panel and Private.BagPresentation.Rail(self.config) or 0
    if t.presentation == panel and t.presentationRail == rail then return end
    t.presentation, t.presentationRail, t.combat = panel, rail, combat
    PaintWindow(t, self.config)
    local title = self.frame.TitleContainer
    if title and title.TitleText then
        if panel then
            Layout.Alpha(self.context, title.TitleText, 0)
        else
            Layout.RestoreProperty(self.context, title.TitleText, "SetAlpha")
        end
    end
    if t.dragHandle then
        t.dragHandle:ClearAllPoints()
        if panel then
            t.dragHandle:SetPoint("TOPLEFT", self.frame, "TOPLEFT", rail + 12, -8)
            t.dragHandle:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", -Private.BagCaption.PANEL_TITLE, -46)
        else
            t.dragHandle:SetAllPoints(title)
        end
    end
end

local function StyleWindow(self, frame, combined)
    self.windows = self.windows or {}
    local textures = self.windows[frame]
    if not textures then
        textures = NewWindowStyle(frame, combined)
        if not textures then return end
        self.windows[frame] = textures
    end
    SetSkinShown(textures, true)
    OwnChrome(self, frame, textures)
    Private.BagCaption.Attach(self, frame, textures)
    if textures.dragHandle then textures.dragHandle:SetShown(not S.editMode) end
    PaintWindow(textures, self.config)
    textures.presentation = nil
end

function M:StyleStandaloneWindow(frame)
    local style = self.windows and self.windows[frame]
    if style and style[2]:IsShown() then return end
    if NS.InCombat() then
        if not self.needsStandaloneWindow then
            self.needsStandaloneWindow = true
            S.Queue("bags")
        end
        return
    end
    StyleWindow(self, frame, false)
end

function M:StyleWindows()
    StyleWindow(self, self.frame, true)
    StyleWindow(self, ContainerFrame6, false)
    if self.standaloneFrames and not NS.InCombat() then
        for _, frame in ipairs(self.standaloneFrames) do
            if self.windows[frame] or frame:IsShown() then StyleWindow(self, frame, false) end
        end
        self.needsStandaloneWindow = nil
    end
    self:UpdatePresentation()
end

local function PaintGold(label, format, delta)
    label:SetText(GoldDeltaText(format, delta))
    if delta and delta > 0 then
        label:SetTextColor(0.33, 0.86, 0.62)
    elseif delta and delta < 0 then
        label:SetTextColor(0.94, 0.43, 0.45)
    else
        label:SetTextColor(0.72, 0.77, 0.82)
    end
end

local function UpdateSessionGold(self)
    local style = self.windows and self.windows[self.frame]
    if not style then return end
    local money = PublicMoney()
    local baseline = NS.SessionGoldBaseline(money)
    PaintGold(style.goldLabel, TEXT.session, money and baseline and money - baseline or nil)
end

local function UpdateTodayGold(self)
    local style = self.windows and self.windows[self.frame]
    if not style then return end
    local label = style.goldBoth and style.dailyGoldLabel or style.goldLabel
    local _, _, net = Gold.Today()
    PaintGold(label, TEXT.today, net)
end

-- Follows the money for the configured period; returns which labels show.
local function WatchGold(self)
    local show, period = self.config.showSessionGold, self.config.goldPeriod
    local session = show and period ~= GOLD_PERIOD.TODAY
    local today = show and (period == GOLD_PERIOD.TODAY or period == GOLD_PERIOD.BOTH)
    Gold.WatchToday(self, today and UpdateTodayGold or nil)
    if session then
        self.context:Event("PLAYER_MONEY", UpdateSessionGold, IN_COMBAT)
        self.context:Event("PLAYER_ENTERING_WORLD", UpdateSessionGold, IN_COMBAT)
    else
        self.context:RemoveEvent("PLAYER_MONEY")
        self.context:RemoveEvent("PLAYER_ENTERING_WORLD")
    end
    return show, session, today
end

-- A fight with every bag window closed (CombatIdle.lua): the labels stop
-- following the money; Resume paints them once.
function M:PauseGoldEvents()
    Gold.WatchToday(self, nil)
    self.context:RemoveEvent("PLAYER_MONEY")
end

function M:ResumeGoldEvents()
    local _, session, today = WatchGold(self)
    if session then UpdateSessionGold(self) end
    if today then UpdateTodayGold(self) end
end

function M:ApplyGoldEvents()
    local show, session, today = WatchGold(self)
    local style = self.windows and self.windows[self.frame]
    if not style then return end
    local both = session and today or false
    Private.BagPanelAppearance.Geometry(style, style.panel == true, both)
    style.goldLabel:SetShown(show)
    style.dailyGoldLabel:SetShown(both)
    if session then UpdateSessionGold(self) end
    if today then UpdateTodayGold(self) end
end

-- GetScaledRect and GetCursorPosition are both in screen pixels. Convert the
-- window's current bottom-right edge into its own anchor units so dragging
-- works at any UI scale, including Blizzard's automatic bag scale. The screen
-- rect covers every native anchor: Blizzard anchors only the first open bag
-- to the screen and chains the others into bag columns.
local function WindowOffset(frame)
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

local function ResizeCorner(self)
    local saved, c = self.resizeCorner, self.config
    if not saved then return end
    if not c.keepResizeCorner or saved.profile ~= NS.DB or saved.moved ~= c.windowMoved
        or saved.windowX ~= c.windowX or saved.windowY ~= c.windowY or saved.scale ~= c.windowScale then
        self.resizeCorner = nil
        return
    end
    return saved
end

-- Choose the nearest screen edges from the old rectangle, before any
-- size change. Anchor points retain those edges while the viewport changes.
function M:PinBagResizeCorner()
    local c, frame = self.config, self.frame
    if not c.keepResizeCorner or not frame or not frame:IsShown() or NS.InCombat() then return end
    if ResizeCorner(self) then return end
    local left, bottom, width, height = frame:GetScaledRect()
    local screenX, screenY, screenW, screenH = UIParent:GetScaledRect()
    local scale = frame:GetEffectiveScale()
    if not (Finite(left) and Finite(bottom) and Finite(width) and Finite(height) and Finite(screenX)
        and Finite(screenY) and Finite(screenW) and Finite(screenH) and Finite(scale)) or scale <= 0 then return end
    local x, y = left - screenX, bottom - screenY
    local right, top = x + width - screenW, y + height - screenH
    local atLeft, atTop = math.abs(x) < math.abs(right), math.abs(top) < math.abs(y)
    local point = (atTop and "TOP" or "BOTTOM") .. (atLeft and "LEFT" or "RIGHT")
    x, y = atLeft and x or right, atTop and top or y
    self.resizeCorner = { point = point, x = x, y = y, profile = NS.DB, moved = c.windowMoved,
        windowX = c.windowX, windowY = c.windowY, scale = c.windowScale }
    Layout.Position(self.context, frame, point, x / scale, y / scale)
end

function M:BeginWindowDrag(frame)
    if not self.active or NS.IsCombatLocked() or S.editMode or not frame:IsShown() or self.dragWindow then
        return
    end
    -- StartMoving raises on a frame that is not movable.
    if not frame:IsMovable() then return end
    local x, y, scale = WindowOffset(frame)
    local cursorX, cursorY = GetCursorPosition()
    if not x or not Finite(cursorX) or not Finite(cursorY) then return end
    self.dragWindow = { frame = frame, x = x, y = y, scale = scale, cursorX = cursorX, cursorY = cursorY }
    if frame == self.frame then self.resizeCorner = nil end
    frame:StartMoving()
end

function M:CancelWindowDrag()
    local drag = self.dragWindow
    if not drag then return end
    self.dragWindow = nil
    drag.frame:StopMovingOrSizing()
    if self.active and not NS.IsCombatLocked() then self:RefreshWindowLayout() end
end

local function ScreenOffset(frame, x, y, width, height)
    local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    local horizontal = math.max(0, UIParent:GetWidth() * ratio - width)
    local vertical = math.max(0, UIParent:GetHeight() * ratio - height)
    return math.max(-horizontal, math.min(0, x)), math.max(0, math.min(vertical, y))
end

local function PanelOffset(frame, x, y)
    local companion = Private.BagPresentation.CompanionWidth(M.config)
    local reserve = companion > 0 and companion + 8 or 0
    local height = companion > 0 and math.max(frame:GetHeight(), ContainerFrame6:GetHeight()) or frame:GetHeight()
    return ScreenOffset(frame, x, y, frame:GetWidth() + reserve, height)
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
    if frame == self.frame and Private.BagPresentation.IsPanel(self.config) then x, y = PanelOffset(frame, x, y) end
    local values
    if frame == self.frame then
        values = { windowX = x, windowY = y, windowMoved = true }
    else
        values = { reagentWindowX = x, reagentWindowY = y, reagentWindowMoved = true }
    end
    if not S.SetMany("bags", values) then self:RefreshWindowLayout() end
end

-- MSUF Edit Mode starts a drag from the captured offsets. While a window
-- follows Blizzard's anchor, its saved offsets are unused: start from the
-- live window instead, or the first drag would jump to the saved position.
local function CaptureLiveOffset(values, frame, movedKey, xKey, yKey)
    if not frame or M.config[movedKey] then return end
    local x, y = WindowOffset(frame)
    if x then values[xKey], values[yKey] = x, y end
end

local function CaptureCombinedOffset(values)
    if ResizeCorner(M) then
        local x, y = WindowOffset(M.frame)
        if x then values.windowX, values.windowY = x, y end
    else
        CaptureLiveOffset(values, M.frame, "windowMoved", "windowX", "windowY")
    end
end

local function CaptureReagentOffset(values)
    CaptureLiveOffset(values, ContainerFrame6, "reagentWindowMoved", "reagentWindowX", "reagentWindowY")
end

-- Blizzard recalculates the bag anchors and scale whenever its container
-- layout changes. Reapply the Suite adjustment after that native layout,
-- while leaving the window's item grid and click handlers untouched.
function M.AfterNativeWindowLayout()
    if Private.BagResize.active then
        Private.BagResize.Reassert()
        return
    end
    if Private.BagWindowMotion.active then Private.BagWindowMotion.Cancel(true) end
    if not M.active then return end
    local frame = M.frame
    if NS.IsCombatLocked() and not Layout.Frame(frame) then return end
    if frame and frame:IsShown() then
        local scale = frame:GetScale()
        if Finite(scale) and scale > 0 then M.nativeScale = scale end
    end
    M:ApplyWindowLayout()
end

function M:ApplyWindowLayout()
    if Private.BagResize.active then return end
    local frame = self.frame
    if not self.active then return end
    if NS.IsCombatLocked() and not Layout.Frame(frame) then return end
    local c = self.config
    if frame and frame:IsShown() then
        local nativeScale = self.nativeScale or frame:GetScale()
        local panel = Private.BagPresentation.IsPanel(c)
        local combat = Private.InventoryView.layout == "combat" and self.combatScale
        local scale = combat or (panel and Private.BagPresentation.Scale(c, Private.BagPresentation.CompanionWidth(c))
            or nativeScale * c.windowScale)
        if Finite(scale) and scale > 0 then Layout.Scale(self.context, frame, scale) end
        local corner = not combat and not NS.InCombat() and ResizeCorner(self)
        local effective = corner and frame:GetEffectiveScale()
        if Finite(effective) and effective > 0 then
            Layout.Position(self.context, frame, corner.point, corner.x / effective, corner.y / effective)
        elseif c.windowMoved then
            local x, y = c.windowX, c.windowY
            if panel or combat then x, y = PanelOffset(frame, x, y) end
            Layout.Position(self.context, frame, "BOTTOMRIGHT", x, y)
        elseif panel or combat then
            Layout.Position(self.context, frame, "BOTTOMRIGHT", -12, 12)
        else
            Layout.RestorePoints(self.context, frame)
        end
    end
    local reagent = ContainerFrame6
    local companion = Private.BagPresentation.CompanionWidth(c)
    if companion > 0 then
        Layout.Scale(self.context, reagent, frame:GetScale())
        Layout.Anchor(self.context, reagent, "BOTTOMRIGHT", frame, "BOTTOMLEFT", -8, 0)
    else
        Layout.RestoreProperty(self.context, reagent, "SetScale")
        Layout.RestorePoints(self.context, reagent)
        if reagent:IsShown() and c.reagentWindowMoved then
            local x, y = ScreenOffset(reagent, c.reagentWindowX, c.reagentWindowY, reagent:GetWidth(), reagent:GetHeight())
            Layout.Position(self.context, reagent, "BOTTOMRIGHT", x, y)
        end
    end
    Private.BagCaption.Moved()
end

-- Blizzard's anchor pass (UpdateContainerFrameAnchors) reads the open bags
-- through ContainerFrameSettingsManager:GetBagsShown, which rebuilds and
-- caches that list (bagsShown) after a bag opened or closed. Rebuilt from
-- addon code, the cached list would be tainted for every later Blizzard pass.
-- A bag's OnShow marks the list stale and ContainerFrame_GenerateFrame runs
-- the pass right after the show hooks (ContainerFrame_OnHide runs it at
-- once), so a stale list means Blizzard's own pass is due. Runs the pass only
-- while the list holds; returns whether it ran.
function M.NativeAnchorPass()
    if NS.IsCombatLocked() or ContainerFrameSettingsManager.bagsShown == nil then return false end
    UpdateContainerFrameAnchors()
    return true
end

function M:RefreshWindowLayout()
    if Private.BagResize.active then return end
    if not ((self.frame and self.frame:IsShown()) or ContainerFrame6:IsShown()) then return end
    if NS.IsCombatLocked() then
        self:ApplyWindowLayout()
        return
    end
    -- The post-hook reapplies the Suite layout after Blizzard's layout pass;
    -- while Blizzard's own pass is due, the Suite layout goes on now and again
    -- after that pass.
    if not M.NativeAnchorPass() then self:ApplyWindowLayout() end
end

function M:RestoreWindows()
    if not self.windows then return end
    for frame, textures in pairs(self.windows) do
        if textures.goldLabel then textures.goldLabel:Hide() end
        if textures.dailyGoldLabel then textures.dailyGoldLabel:Hide() end
        if textures.dragHandle then textures.dragHandle:Hide() end
        SetSkinShown(textures, false)
        if textures.titlePoints and frame.TitleContainer and not NS.IsCombatLocked() then
            local title = frame.TitleContainer
            title:ClearAllPoints()
            for i = 1, #textures.titlePoints do title:SetPoint(unpack(textures.titlePoints[i])) end
        end
    end
end

function M:RegisterMovers()
    S.RegisterOwnedMover("bags", "combined", {
        label = "Combined bags", order = 875,
        getFrame = function() return self.frame end,
        isEnabled = function() return self.frame and self.frame:IsShown() end,
        xKey = "windowX", yKey = "windowY", point = "BOTTOMRIGHT",
        capture = CaptureCombinedOffset,
        moveValues = { windowMoved = true }, resetKeys = { "windowMoved" },
        historyKeys = { "windowMoved", "windowScale", "inventoryColumns", "inventoryRows", "autoSizeWindow", "panelFullHeight" },
        extraControls = {
            {
                id = "size", label = "Size %", kind = "number", min = 65, max = 150, step = 1,
                get = function() return floor(S.Config("bags").windowScale * 100 + 0.5) end,
                set = function(value) return S.Set("bags", "windowScale", value / 100) end,
            },
            {
                id = "columns", label = "Items per row", kind = "number", min = 8, max = 20, step = 1,
                get = function() return S.Config("bags").inventoryColumns end,
                set = function(value) return S.Set("bags", "inventoryColumns", value) end,
            },
            {
                id = "rows", label = "Visible rows", kind = "number", min = 4, max = 16, step = 1,
                get = function() return S.Config("bags").inventoryRows end,
                set = function(value)
                    return S.SetMany("bags", {inventoryRows=value, autoSizeWindow=false, panelFullHeight=false})
                end,
            },
        },
    })
    S.RegisterOwnedMover("bags", "reagent", {
        label = "Reagent bag", order = 876,
        getFrame = function() return ContainerFrame6 end,
        isEnabled = function() return ContainerFrame6:IsShown() end,
        xKey = "reagentWindowX", yKey = "reagentWindowY", point = "BOTTOMRIGHT",
        capture = CaptureReagentOffset,
        moveValues = { reagentWindowMoved = true }, resetKeys = { "reagentWindowMoved" },
        historyKeys = { "reagentWindowMoved" },
    })
    -- Retail only: BankWindow.lua returns early on WoW Forever.
    if not NS.Client.isForever then S.RegisterOwnedMover("bags", "bank", Private.BankWindow.mover) end
end
