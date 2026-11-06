local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local Resize = {}
P.BagResize = Resize

Resize.config, Resize.snapped = {}, {}
local Finish

local function Stop()
    if Resize.driver then Resize.driver:SetScript("OnUpdate", nil) Resize.driver:Hide() end
    Resize.active = nil
end

function Resize.Cancel()
    local active = Resize.active
    Stop()
    if active and M.active and not NS.InCombat() then
        M:RefreshWindowLayout()
        P.InventoryView.Request()
    end
end

function Resize.Reassert()
    if not Resize.active or NS.IsCombatLocked() then return end
    local frame = P.InventoryView.frame
    M.context:Scale(frame, Resize.scale)
    M.context:Anchor(frame, "TOPLEFT", UIParent, "BOTTOMLEFT", Resize.left / Resize.effective, Resize.top / Resize.effective)
    frame:SetSize(Resize.width, Resize.height)
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
    P.BagMotion.StopAll()
    GameTooltip:Hide()
    Resize.Reassert()
    Resize.driver = Resize.driver or P.ChildFrame("Frame", UIParent)
    Resize.driver:SetScript("OnUpdate", Tick)
    Resize.driver:Show()
end
Resize.Begin = Begin

Finish = function(_, button)
    if button and button ~= "LeftButton" or not Resize.active then return end
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
    GameTooltip:SetText(S.Text("Window size"))
    GameTooltip:AddLine(S.Text("Drag to resize"), .75, .8, .85)
    GameTooltip:Show()
end

local function Leave() GameTooltip:Hide() end

function Resize.Create(parent)
    local button = P.ChildFrame("Button", parent)
    button:SetSize(20, 20)
    button:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -1, 1)
    button:SetFrameLevel(parent:GetFrameLevel() + 2)
    button:EnableMouse(true)
    local grip = S.CreateTexture(button, nil, "ARTWORK")
    grip:SetAllPoints(button)
    grip:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    button.grip = grip
    local r, g, b = S.RGB(M.config.accentColor)
    grip:SetVertexColor(r, g, b, .9)
    button.accent = M.config.accentColor
    button:SetScript("OnMouseDown", Begin)
    button:SetScript("OnMouseUp", Finish)
    button:SetScript("OnHide", Resize.Cancel)
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", Leave)
    return button
end

function Resize.Refresh(button)
    button:SetShown(not S.editMode)
    if button.accent == M.config.accentColor then return end
    button.accent = M.config.accentColor
    local r, g, b = S.RGB(button.accent)
    button.grip:SetVertexColor(r, g, b, .9)
end
