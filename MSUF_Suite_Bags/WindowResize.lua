local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Resize = {}
P.BagResize = Resize
local BLIZZARD_GRID = NS.BagsView.BLIZZARD_GRID
local GRIP_SIZE = 20
local GRIP_RIM_HEIGHT = 6

Resize.config, Resize.snapped = {}, {}
local Finish

local function Stop()
    if Resize.driver then
        Resize.driver:SetScript("OnUpdate", nil)
        Resize.driver:UnregisterAllEvents()
        Resize.driver:Hide()
    end
    Resize.active, Resize.nativeDrag = nil, nil
end

function Resize.Cancel(_, event)
    local active = Resize.active
    Stop()
    if active and M.active and not NS.InCombat(event) then
        M:RefreshWindowLayout()
        P.InventoryView.Request()
    end
end

local function Start(tick)
    if not Resize.driver then
        Resize.driver = P.ChildFrame("Frame", UIParent)
        Resize.driver:SetScript("OnEvent", Resize.Cancel)
    end
    Resize.driver:SetScript("OnUpdate", tick)
    Resize.driver:Show()
end

-- Work in screen pixels so scaling the frame does not move the opposite corner.
-- Slide it back inside the viewport if increasing the scale hits an edge.
local function PlaceNative(drag)
    local ratio = drag.value / drag.startValue
    local width, height = drag.width * ratio, drag.height * ratio
    local left, top = drag.left, drag.top
    if ratio ~= 1 then
        left = math.max(drag.screenLeft, math.min(left, drag.screenRight - width))
        top = math.min(drag.screenTop, math.max(top, drag.screenBottom + height))
    end
    local effective = drag.effective * ratio
    drag.windowX = (left + width - drag.screenRight) / effective
    drag.windowY = (top - height - drag.screenBottom) / effective
    M.context:Scale(drag.frame, drag.scale * ratio)
    M.context:Anchor(drag.frame, "TOPLEFT", UIParent, "BOTTOMLEFT", (left - drag.screenLeft) / effective,
        (top - drag.screenBottom) / effective)
end

function Resize.Reassert()
    if not Resize.active then return end
    local drag = Resize.nativeDrag
    if drag then
        if NS.InCombat() then return true end
        local scale = drag.frame:GetScale()
        if not S.Finite(scale) or math.abs(scale - drag.nativeScale) > .0001 then
            Stop()
            return false
        end
        PlaceNative(drag)
        return true
    end
    if not NS.IsCombatLocked() then
        local frame = P.InventoryView.frame
        M.context:Scale(frame, Resize.scale)
        M.context:Anchor(frame, "TOPLEFT", UIParent, "BOTTOMLEFT", Resize.left / Resize.effective, Resize.top / Resize.effective)
        frame:SetSize(Resize.width, Resize.height)
    end
    return true
end

local function Layout(width, height)
    local view, g, c = P.InventoryView, P.InventoryView.geometry, Resize.config
    local columns = math.floor((width - (g.panel and g.rail + 32 or g.sidebar + 12)) / 40)
    local rows = math.floor((height - g.top - g.bottom) / 40)
    if width == Resize.startWidth then columns = Resize.startColumns end
    columns = math.max(8, math.min(20, columns))
    rows = math.max(4, math.min(16, rows))
    local changed = c.inventoryColumns ~= columns or c.inventoryRows ~= rows
    c.inventoryColumns, c.inventoryRows = columns, rows
    Resize.width, Resize.height = width, height
    view.frame:SetSize(width, height)
    if changed then P.InventoryRendering.Suite() end
end

local function Tick()
    local view = P.InventoryView
    if NS.InCombat() or not M.active or not view.active or not view.frame:IsShown() or StackSplitFrame:IsShown() then
        Resize.Cancel()
        return
    end
    if not IsMouseButtonDown("LeftButton") then
        Finish()
        return
    end
    local x, y = GetCursorPosition()
    if not S.Finite(x) or not S.Finite(y) or x == Resize.cursorX and y == Resize.cursorY then return end
    Resize.cursorX, Resize.cursorY = x, y
    local width = math.max(Resize.minW, math.min(Resize.maxW, Resize.startWidth + (x - Resize.mouseX) / Resize.effective))
    local height = math.max(Resize.minH, math.min(Resize.maxH, Resize.startHeight + (Resize.mouseY - y) / Resize.effective))
    if width ~= Resize.width or height ~= Resize.height then Layout(width, height) end
end

local function CanScaleNative()
    return M.active and M.config.inventoryView == BLIZZARD_GRID and not M.nativeMaximized and M.frame:IsShown()
        and not (NS.InCombat() or S.editMode or StackSplitFrame:IsShown() or M.dragWindow)
end

local function NativeSizeChanged(drag)
    -- The resolved rect can round differently at the temporary drag scale.
    local width, height = drag.frame:GetSize(true)
    return not (S.Finite(width) and S.Finite(height))
        or width ~= drag.nativeWidth or height ~= drag.nativeHeight
end

local function TickNative()
    if not CanScaleNative() or NativeSizeChanged(Resize.nativeDrag) then Resize.Cancel() return end
    if not IsMouseButtonDown("LeftButton") then Finish() return end
    local drag = Resize.nativeDrag
    local x, y = GetCursorPosition()
    if not S.Finite(x) or not S.Finite(y) or x == drag.cursorX and y == drag.cursorY then return end
    drag.cursorX, drag.cursorY = x, y
    local delta = ((x - drag.mouseX) + (drag.mouseY - y)) * .5
    local value = math.floor((drag.startValue + delta / drag.pixels) * 100 + .5) / 100
    if delta == 0 then value = drag.startValue end
    value = math.max(drag.minimum, math.min(drag.maximum, value))
    if value == drag.value then return end
    drag.value = value
    PlaceNative(drag)
end

local function BeginNative(_, button)
    if button ~= "LeftButton" or Resize.active or not CanScaleNative() or GetCursorInfo() then return end
    local frame = M.frame
    local left, bottom, width, height = frame:GetScaledRect()
    local screenLeft, screenBottom, screenWidth, screenHeight = UIParent:GetScaledRect()
    local scale, effective = frame:GetScale(), frame:GetEffectiveScale()
    local nativeWidth, nativeHeight = frame:GetSize(true)
    local mouseX, mouseY = GetCursorPosition()
    if not (S.Finite(left) and S.Finite(bottom) and S.Finite(width) and S.Finite(height)
        and S.Finite(screenLeft) and S.Finite(screenBottom) and S.Finite(screenWidth) and S.Finite(screenHeight)
        and S.Finite(scale) and S.Finite(effective) and S.Finite(nativeWidth) and S.Finite(nativeHeight)
        and S.Finite(mouseX) and S.Finite(mouseY))
        or width <= 0 or height <= 0 or scale <= 0 or effective <= 0 then return end
    local rule, value = S.catalog.bags.rules.windowScale, M.config.windowScale
    local fit = value * math.min(screenWidth / width, screenHeight / height)
    P.BagWindowMotion.Cancel()
    P.BagMotion.StopAll()
    GameTooltip:Hide()
    M.resizeCorner = nil
    Resize.active = true
    Resize.nativeDrag = {
        frame = frame, left = left, top = bottom + height, width = width, height = height, scale = scale, effective = effective,
        screenLeft = screenLeft, screenBottom = screenBottom, screenRight = screenLeft + screenWidth, screenTop = screenBottom + screenHeight,
        mouseX = mouseX, mouseY = mouseY, cursorX = mouseX, cursorY = mouseY, pixels = math.max(width, height) / value,
        startValue = value, value = value, minimum = rule.min, maximum = math.max(rule.min, math.min(rule.max, fit)),
        nativeScale = M.nativeScale or scale / value, nativeWidth = nativeWidth, nativeHeight = nativeHeight,
    }
    Start(TickNative)
    Resize.driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    Resize.driver:RegisterEvent("UI_SCALE_CHANGED")
    if NS.Client.SupportsEvent("DISPLAY_SIZE_CHANGED") then Resize.driver:RegisterEvent("DISPLAY_SIZE_CHANGED") end
end

local function Begin(_, button)
    local view = P.InventoryView
    if button ~= "LeftButton" or Resize.active or not M.active or NS.InCombat() or S.editMode or not view.SuiteLayout()
        or view.transitionPending or not view.frame:IsShown() or StackSplitFrame:IsShown() or GetCursorInfo() or M.dragWindow then return end
    P.BagWindowMotion.Cancel()
    local frame, g = view.frame, view.geometry
    local x, y, width, height = frame:GetScaledRect()
    local effective = frame:GetEffectiveScale()
    local mouseX, mouseY = GetCursorPosition()
    if not S.Finite(x) or not S.Finite(y) or not S.Finite(effective) or effective <= 0
        or not S.Finite(mouseX) or not S.Finite(mouseY) then return end
    for key in pairs(Resize.config) do Resize.config[key] = nil end
    for key, value in pairs(M.config) do Resize.config[key] = value end
    Resize.config.autoSizeWindow, Resize.config.panelFullHeight = false, false
    local minimum = P.BagPresentation.Resize({}, M.config, g, 0, 0)
    local maximum = P.BagPresentation.Resize({}, M.config, g, math.huge, math.huge)
    Resize.minW, Resize.minH, Resize.maxW, Resize.maxH = minimum.width, minimum.height, maximum.width, maximum.height
    Resize.left, Resize.top, Resize.scale, Resize.effective = x, y + height, frame:GetScale(), effective
    Resize.startWidth, Resize.startHeight, Resize.startColumns = width / effective, height / effective, M.config.inventoryColumns
    Resize.width, Resize.height = Resize.startWidth, Resize.startHeight
    Resize.mouseX, Resize.mouseY, Resize.cursorX, Resize.cursorY = mouseX, mouseY, mouseX, mouseY
    Resize.active = true
    M.resizeCorner = nil
    P.BagMotion.StopAll()
    GameTooltip:Hide()
    Resize.Reassert()
    Start(Tick)
end
Resize.Begin = Begin

Finish = function(_, button)
    if button and button ~= "LeftButton" or not Resize.active then return end
    local native = Resize.nativeDrag
    if native then
        Stop()
        if CanScaleNative() and not NativeSizeChanged(native) and native.value ~= native.startValue then
            if S.SetMany("bags", { windowScale = native.value, windowMoved = true, windowX = native.windowX, windowY = native.windowY }) then
                return
            end
        end
        if M.active and not NS.InCombat() then M:RefreshWindowLayout() end
        return
    end
    local view, c = P.InventoryView, Resize.config
    local changed = Resize.width ~= Resize.startWidth or Resize.height ~= Resize.startHeight
    Stop()
    if not M.active or NS.InCombat() or not view.SuiteLayout() or not view.frame:IsShown() then return end
    if not changed then
        M:RefreshWindowLayout()
        return
    end
    local g = view.geometry
    local width = g.panel and g.rail + c.inventoryColumns * 40 + 32 or math.max(620, g.sidebar + c.inventoryColumns * 40 + 12)
    width = math.min(width, Resize.maxW)
    local height = math.min(math.max(g.minimum, c.inventoryRows) * 40 + g.top + g.bottom, Resize.maxH)
    view.frame:SetSize(width, height)
    local left, bottom, parentWidth = UIParent:GetScaledRect()
    local windowX = (Resize.left + width * Resize.effective - left - parentWidth) / Resize.effective
    local windowY = (Resize.top - height * Resize.effective - bottom) / Resize.effective
    if not S.SetMany("bags", { inventoryColumns = c.inventoryColumns, inventoryRows = c.inventoryRows, autoSizeWindow = false,
        panelFullHeight = false, windowMoved = true, windowX = windowX, windowY = windowY }) then
        M:RefreshWindowLayout()
        view.Request()
    end
end
Resize.Finish = Finish

local function Enter(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    if button == Resize.scaleGrip then
        GameTooltip:SetText(S.Text("Drag to scale this window"))
    else
        GameTooltip:SetText(S.Text("Window size"))
        GameTooltip:AddLine(S.Text("Drag to resize"), .75, .8, .85)
    end
    GameTooltip:Show()
end

local function Leave() GameTooltip:Hide() end

function Resize.Create(parent, native)
    local button = P.ChildFrame("Button", parent)
    button:SetSize(GRIP_SIZE, GRIP_SIZE)
    if native then
        -- Keep the hit area below the coin row and native item slots.
        button:SetPoint("TOPRIGHT", M.frame, "BOTTOMRIGHT", -1, GRIP_RIM_HEIGHT + 1)
    else
        button:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 1)
    end
    button:SetFrameLevel(native and M.frame:GetFrameLevel() + 20 or parent:GetFrameLevel() + 2)
    button:EnableMouse(true)
    local grip = S.CreateTexture(button, nil, "ARTWORK")
    grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    if native then
        grip:SetSize(GRIP_SIZE, GRIP_SIZE)
        grip:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, -GRIP_RIM_HEIGHT)
    else
        grip:SetAllPoints(button)
        local r, g, b = S.RGB(M.config.accentColor)
        grip:SetVertexColor(r, g, b, .9)
        button.accent = M.config.accentColor
    end
    button.grip = grip
    button:SetScript("OnMouseDown", native and BeginNative or Begin)
    button:SetScript("OnMouseUp", Finish)
    button:SetScript("OnHide", Resize.Cancel)
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", Leave)
    return button
end

function Resize.Refresh(button)
    button:SetShown(not S.editMode)
    if button == Resize.scaleGrip or button.accent == M.config.accentColor then return end
    button.accent = M.config.accentColor
    local r, g, b = S.RGB(button.accent)
    button.grip:SetVertexColor(r, g, b, .9)
end

function Resize.RefreshNative(shell)
    local grip = Resize.scaleGrip
    if not M.active or not shell or M.config.inventoryView ~= BLIZZARD_GRID or M.nativeMaximized or S.editMode then
        if grip then grip:Hide() end
        return
    end
    if not grip then
        if NS.InCombat() or not M.frame:IsShown() then return end
        grip = Resize.Create(shell, true)
        Resize.scaleGrip = grip
    end
    Resize.Refresh(grip)
end
