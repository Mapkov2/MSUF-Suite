local _, Private = ...
local NS, S = Private.NS, Private.Suite
local M = assert(Private.BagsModule, "Bags.lua must load before BagWindow.lua")
-- The bag windows: Suite surface, title drag handles, session gold label and
-- the placement Blizzard's container layout receives after each native pass.
local floor = math.floor
local WindowTexture = M.WindowTexture
local TEXT = {
    session = S.Text("Session"),
    drag = S.Text("Drag to move"),
    options = S.Text("Click for bag options"),
}
local NO_VALUE = "—"

local Finite = S.Finite
local function PublicMoney()
    local value = GetMoney()
    if not Finite(value) or value < 0 then return nil end
    return floor(value)
end

-- Losses use the ASCII hyphen-minus.
local function GoldDeltaText(delta)
    return TEXT.session .. " " .. (delta > 0 and "+" or delta < 0 and "-" or "") .. S.MoneyText(math.abs(delta))
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
    if button ~= "LeftButton" or IsShiftKeyDown() then return end
    -- The portrait button is Blizzard's bag menu DropdownButton.
    local menu = handle.window.PortraitButton
    menu:SetMenuOpen(not menu:IsMenuOpen())
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
    GameTooltip:SetOwner(handle, "ANCHOR_TOP")
    GameTooltip:SetText(TEXT.drag)
    GameTooltip:AddLine(TEXT.options, 0.75, 0.8, 0.85)
    GameTooltip:Show()
end

local function HandleLeave()
    GameTooltip:Hide()
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
    if textures.goldLabel then S.SetFont(textures.goldLabel, S.ResolveFont(c.font), 11, "OUTLINE") end
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
    if not textures.titlePoints then
        local points = {}
        for point = 1, title:GetNumPoints() do points[point] = { title:GetPoint(point) } end
        textures.titlePoints = points
    end
    frame:SetTitleOffsets(8)
    if not textures.dragHandle then textures.dragHandle = NewDragHandle(frame) end
end

function M:StyleWindows()
    self.windows = self.windows or {}
    -- Blizzard_UIPanels_Game declares both windows in ContainerFrame.xml and
    -- loads at startup on Retail and Forever.
    local targets = { ContainerFrameCombinedBags, ContainerFrame6 }
    for i = 1, #targets do
        local frame = targets[i]
        if not self.windows[frame] then self.windows[frame] = NewWindowStyle(frame, i == 1) end
    end
    for frame, textures in pairs(self.windows) do
        textures.shell:Show()
        textures[1]:Show()
        OwnChrome(self, frame, textures)
        if textures.dragHandle then textures.dragHandle:SetShown(not S.editMode) end
        PaintWindow(textures, self.config)
    end
end

function M:UpdateGold()
    local style = self.windows and self.frame and self.windows[self.frame]
    local label = style and style.goldLabel
    if not label then return end
    if not self.config.showSessionGold then
        label:Hide()
        return
    end
    -- The one session baseline of the Bags and DataTexts (Core/Catalog/Bags.lua).
    local money = PublicMoney()
    local baseline = NS.SessionGoldBaseline(money)
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

function M:ApplyGoldEvents()
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

-- MSUF Edit Mode starts a drag from the captured offsets. While a window
-- follows Blizzard's anchor, its saved offsets are unused: start from the
-- live window instead, or the first drag would jump to the saved position.
local function CaptureLiveOffset(values, frame, movedKey, xKey, yKey)
    if not frame or M.config[movedKey] then return end
    local x, y = WindowOffset(frame)
    if x then values[xKey], values[yKey] = x, y end
end

local function CaptureCombinedOffset(values)
    CaptureLiveOffset(values, M.frame, "windowMoved", "windowX", "windowY")
end

local function CaptureReagentOffset(values)
    CaptureLiveOffset(values, ContainerFrame6, "reagentWindowMoved", "reagentWindowX", "reagentWindowY")
end

-- Blizzard recalculates the bag anchors and scale whenever its container
-- layout changes. Reapply the Suite adjustment after that native layout,
-- while leaving the window's item grid and click handlers untouched.
function M.AfterNativeWindowLayout()
    if not M.active or NS.IsCombatLocked() then return end
    local frame = M.frame
    if frame and frame:IsShown() then
        local scale = frame:GetScale()
        if Finite(scale) and scale > 0 then M.nativeScale = scale end
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
    local reagent = ContainerFrame6
    if reagent:IsShown() and c.reagentWindowMoved then
        self.context:Position(reagent, "BOTTOMRIGHT", c.reagentWindowX, c.reagentWindowY)
    end
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
    if NS.IsCombatLocked() or not ((self.frame and self.frame:IsShown()) or ContainerFrame6:IsShown()) then
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

function M:RegisterMovers()
    S.RegisterOwnedMover("bags", "combined", {
        label = "Combined bags", order = 875,
        getFrame = function() return self.frame end,
        isEnabled = function() return self.frame and self.frame:IsShown() end,
        xKey = "windowX", yKey = "windowY", point = "BOTTOMRIGHT",
        capture = CaptureCombinedOffset,
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
        getFrame = function() return ContainerFrame6 end,
        isEnabled = function() return ContainerFrame6:IsShown() end,
        xKey = "reagentWindowX", yKey = "reagentWindowY", point = "BOTTOMRIGHT",
        capture = CaptureReagentOffset,
        moveValues = { reagentWindowMoved = true }, resetKeys = { "reagentWindowMoved" },
        historyKeys = { "reagentWindowMoved" },
    })
end
