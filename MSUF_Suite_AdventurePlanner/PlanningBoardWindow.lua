local _, P = ...
local NS, S, Plan = P.NS, P.Suite, P.PlanningTools
local B = Plan.Board
local Bridge = NS.HostBridge
local SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon"
local FOOTER_TOP = -594
local EndScaleDrag

-- Hiding stops every animation and scroller, so a closed or combat-hidden
-- planner runs no script until the next open.
local function Closed(window)
    EndScaleDrag(window, false)
    B.StopMotion(window)
    window.listScroll:Stop()
    window.detailScroll:Stop()
    Plan.Matrix.Clear(window)
    window.owner, window.spec, window.profile, window.selected = nil, nil, nil, nil
    window.statsRows, window.statsGeneration, window.statsReset = nil, nil, nil
    for i = #window.items, 1, -1 do window.items[i] = nil end
    for i = #window.filtered, 1, -1 do window.filtered[i] = nil end
    window.details:SetText("")
    window.status:SetText("")
    window.search:ClearFocus()
end

local function CloseButton(window)
    local close = Bridge.MenuCloseButton(window)
    if close then
        -- The core renderer draws its close glyph as text; it follows the Suite font.
        local glyph = Bridge.MenuButtonLabel(close)
        if glyph then B.TrackFont(glyph, 12, "danger") end
        close.plannerNativeButton = true
    else
        close = B.Button(window, "X", 26, 26)
    end
    close:SetSize(28, 22)
    close:SetPoint("TOPRIGHT", -12, -8)
    close:SetScript("OnClick", function() B.Dismiss(window.owner) end)
    window.close = close
end

-- The title band: MSUF's logo, the window name and the account summary.
local function Header(window)
    local drag = S.CreateFrame("Button", nil, window)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT", -108, 0)
    drag:SetHeight(40)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() window:StartMoving() end)
    drag:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    local logo = S.CreateTexture(drag, nil, "ARTWORK")
    logo:SetPoint("TOPLEFT", 18, -9)
    logo:SetSize(22, 22)
    logo:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\MSUF_MinimapIcon.tga")
    window.title = B.Label(window, "Adventure planner", 15, "title")
    window.title:SetPoint("TOPLEFT", 48, -6)
    window.title:SetSize(600, 18)
    window.summary = B.Label(window, "", 11, "muted")
    window.summary:SetPoint("TOPLEFT", 48, -24)
    window.summary:SetSize(800, 14)
    -- The slash command is the same in every language and is not translated.
    local shortcut = B.Label(window, "", 11, "muted")
    shortcut:SetText(SLASH_MSUFPLANNER1)
    shortcut:SetPoint("TOPRIGHT", -110, -14)
    shortcut:SetSize(90, 14)
    shortcut:SetJustifyH("RIGHT")
    CloseButton(window)
    B.CreateWindowControls(window)
end

local function SearchChanged(window, box)
    local empty = box:GetText() == ""
    box.hint:SetShown(empty and not box:HasFocus())
    window.clear:SetShown(not empty)
    window.offset, window.selected = 0, nil
    window.listScroll:Reset()
    window.detailScroll:Reset()
    window.matrix.characterOffset = 0
    window.matrix.scroller:Reset()
    window:Refresh()
end

local function SearchFocus(box, focused)
    if box.plannerEdges then B.TintEdges(box, focused and "accent" or "borderSoft") end
    box.hint:SetShown(not focused and box:GetText() == "")
end

local function SearchScripts(window, box)
    box:SetScript("OnEditFocusGained", function(self) SearchFocus(self, true) end)
    box:SetScript("OnEditFocusLost", function(self) SearchFocus(self, false) end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- Escape empties a filled search first, then leaves the field.
    box:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    box:SetScript("OnTextChanged", function(self) SearchChanged(window, self) end)
end

-- Menu2's rounded rail search, sitting in the status bar like MSUF's own.
local function Search(window, bar)
    local box = S.CreateFrame("EditBox", nil, bar)
    box:SetPoint("TOPRIGHT", -46, -16)
    box:SetSize(260, 28)
    box:SetAutoFocus(false)
    box:SetMaxBytes(513)
    box:SetTextInsets(28, 8, 0, 0)
    -- A template-free edit box needs a font before its first text.
    box:SetFontObject("ChatFontNormal")
    B.TrackFont(box, 13, "text")
    SearchScripts(window, box)
    if not Bridge.MenuEditBox(box) then
        B.Fill(box, "coreShadow", .76, "popup")
        B.Edges(box, "borderSoft")
    end
    local icon, c = S.CreateTexture(box, nil, "OVERLAY"), B.Color("muted", "text")
    icon:SetPoint("LEFT", 9, 0)
    icon:SetSize(14, 14)
    icon:SetTexture(SEARCH_ICON)
    icon:SetVertexColor(c[1], c[2], c[3], .9)
    box.hint = B.Label(box, "Search characters or activities", 12, "muted")
    box.hint:SetPoint("LEFT", 28, 0)
    box.hint:SetPoint("RIGHT", -8, 0)
    box.hint:SetHeight(18)
    box.hint:SetJustifyV("MIDDLE")
    box.hint:SetWordWrap(false)
    window.search = box
    window.clear = B.Button(bar, "X", 26, 26, function()
        box:SetText("")
        box:ClearFocus()
    end)
    window.clear:SetPoint("TOPRIGHT", -14, -17)
end

-- Menu2's status bar: the page title, one line about the page and search.
local function StatusBar(window)
    local bar = B.Panel(window.host, 0, 0, B.HOST_WIDTH, 60, "status")
    window.statusBar = bar
    window.pageTitle = B.Label(bar, "", 17, "title")
    window.pageTitle:SetPoint("TOPLEFT", 16, -10)
    window.pageTitle:SetSize(560, 22)
    window.pageHint = B.Label(bar, "", 12, "muted")
    window.pageHint:SetPoint("TOPLEFT", 16, -35)
    window.pageHint:SetSize(600, 16)
    window.pageHint:SetWordWrap(false)
    Search(window, bar)
end

local function Details(window)
    local width = B.BODY_WIDTH - B.LIST_WIDTH - 12
    local panel = B.Panel(window.body, B.LIST_WIDTH + 12, 0, width, B.BODY_HEIGHT, "card")
    window.detailsPanel = panel
    window.detailTitle = B.Label(panel, "Details", 15, "title")
    window.detailTitle:SetPoint("TOPLEFT", 18, -16)
    window.detailTitle:SetSize(width - 36, 36)
    window.detailTitle:SetWordWrap(true)
    B.Rule(panel, 18, -58, width - 36)
    local scroll = S.CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 18, -68)
    scroll:SetSize(width - 50, 434)
    window.detailScrollFrame = scroll
    window.detailsChild = S.CreateFrame("Frame", nil, scroll)
    window.detailsChild:SetSize(width - 50, 434)
    window.details = B.Label(window.detailsChild, "", 13)
    window.details:SetPoint("TOPLEFT")
    window.details:SetSize(width - 50, 434)
    window.details:SetWordWrap(true)
    window.details:SetSpacing(4)
    scroll:SetScrollChild(window.detailsChild)
    window.detailScroll = B.Scroller(window, panel, function(_, offset) scroll:SetVerticalScroll(offset) end, 64)
    window.detailScroll.bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
    window.detailScroll.bar:SetHeight(434)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        if B.Valid(window) then window.detailScroll:Wheel(delta) end
    end)
end

-- The list sits on the host's own surface, like Menu2 page content.
local function List(window)
    local width = B.LIST_WIDTH - 16
    window.list = S.CreateFrame("Frame", nil, window.body)
    window.list:SetPoint("TOPLEFT")
    window.list:SetSize(B.LIST_WIDTH, B.BODY_HEIGHT)
    window.listViewport = S.CreateFrame("Frame", nil, window.list)
    window.listViewport:SetPoint("TOPLEFT", 0, -4)
    window.listViewport:SetSize(width, B.PAGE_ROWS * B.ROW_HEIGHT)
    window.listViewport:SetClipsChildren(true)
    window.listSlider = S.CreateFrame("Frame", nil, window.listViewport)
    window.listSlider:SetPoint("TOPLEFT")
    window.listSlider:SetSize(width, (B.PAGE_ROWS + 1) * B.ROW_HEIGHT)
    window.listScroll = B.Scroller(window, window.list, B.ListScrolled, B.ROW_HEIGHT * 2)
    window.listScroll.bar:SetPoint("TOPRIGHT", 0, -6)
    window.listScroll.bar:SetHeight(B.PAGE_ROWS * B.ROW_HEIGHT - 4)
    window.list:EnableMouseWheel(true)
    window.list:SetScript("OnMouseWheel", function(_, delta)
        if B.Valid(window) then window.listScroll:Wheel(delta) end
    end)
    window.empty = B.Label(window.list, "", 14, "muted")
    window.empty:SetPoint("CENTER")
    window.empty:SetSize(B.LIST_WIDTH - 60, 150)
    window.empty:SetJustifyH("CENTER")
    window.empty:SetJustifyV("MIDDLE")
    window.empty:SetWordWrap(true)
end

local function Body(window)
    window.host = B.Panel(window, B.HOST_X, -44, B.HOST_WIDTH, B.HOST_HEIGHT, "host")
    Bridge.MenuAtmosphere(window, window.host, window.rail)
    StatusBar(window)
    window.body = S.CreateFrame("Frame", nil, window.host)
    window.body:SetPoint("TOPLEFT", B.BODY_X, B.BODY_TOP)
    window.body:SetSize(B.BODY_WIDTH, B.BODY_HEIGHT)
    List(window)
    Details(window)
end

local function Footer(window)
    window.status = B.Label(window.host, "", 11, "muted")
    window.status:SetPoint("TOPLEFT", 14, FOOTER_TOP)
    window.status:SetSize(600, 16)
    window.status:SetWordWrap(false)
    window.counter = B.Label(window.host, "", 11, "muted")
    window.counter:SetPoint("TOPRIGHT", -14, FOOTER_TOP)
    window.counter:SetSize(300, 16)
    window.counter:SetJustifyH("RIGHT")
    window.actions = {}
    for i = 1, 6 do
        local button = B.Button(window.host, "", 148, 28, B.RunAction)
        button.text:SetJustifyH("CENTER")
        button.index, button.window = i, window
        window.actions[i] = button
    end
end

local function ApplyScale(window, preferred)
    local fit = math.min((UIParent:GetWidth() - 40) / B.WIDTH, (UIParent:GetHeight() - 40) / B.HEIGHT)
    local scale = S.Finite(preferred) and math.max(.5, math.min(1.5, preferred)) or 1
    window:SetScale(math.max(.1, math.min(scale, fit)))
end

EndScaleDrag = function(window, save)
    local drag = window.scaleDrag
    window.scaleGrip:SetScript("OnUpdate", nil)
    window.scaleDrag = nil
    if not drag or not save or not B.Valid(window) or window:GetScale() == drag.scale then return end
    local account = Plan.Account()
    if account then account.windowScale = window:GetScale() end
end

local function ScaleDragged(grip)
    local window = grip.window
    local drag = window.scaleDrag
    if not drag then return grip:SetScript("OnUpdate", nil) end
    if not B.Valid(window) or not window:IsShown() then return EndScaleDrag(window, false) end
    if not IsMouseButtonDown("LeftButton") then return EndScaleDrag(window, true) end
    local x, y = GetCursorPosition()
    if not S.Finite(x) or not S.Finite(y) then return end
    local delta = ((x - drag.x) + (drag.y - y)) * .5 / drag.pixels
    local scale = math.min(drag.maximum, math.max(.5, drag.scale + delta))
    if scale == window:GetScale() then return end
    window:SetScale(scale)
    local ratio = window:GetEffectiveScale() / UIParent:GetEffectiveScale()
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", drag.left / ratio, drag.top / ratio)
end

local function ScalePressed(grip, button)
    local window = grip.window
    if button ~= "LeftButton" or not B.Valid(window) then return end
    local x, y = GetCursorPosition()
    local left, top = window:GetLeft(), window:GetTop()
    local uiScale = UIParent:GetEffectiveScale()
    if not S.Finite(x) or not S.Finite(y) or not S.Finite(left) or not S.Finite(top) or uiScale <= 0 then return end
    B.FinishAccordion(window, true)
    B.StopMotion(window)
    local ratio = window:GetEffectiveScale() / uiScale
    local drag = window.scaleStart
    drag.x, drag.y, drag.scale = x, y, window:GetScale()
    drag.left, drag.top = left * ratio, top * ratio - UIParent:GetHeight()
    drag.pixels = math.max(B.WIDTH, B.HEIGHT) * uiScale
    drag.maximum = math.max(.1, math.min(1.5, (UIParent:GetWidth() - drag.left - 20) / B.WIDTH,
        (UIParent:GetHeight() + drag.top - 20) / B.HEIGHT))
    window.scaleDrag = drag
    grip:SetScript("OnUpdate", ScaleDragged)
end

local function ScaleGrip(window)
    local grip = S.CreateFrame("Button", nil, window)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(window:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip.window = window
    window.scaleGrip, window.scaleStart = grip, {}
    grip:SetScript("OnMouseDown", ScalePressed)
    grip:SetScript("OnMouseUp", function() EndScaleDrag(window, true) end)
    grip:SetScript("OnHide", function() EndScaleDrag(window, false) end)
end

local function Create()
    local window = S.CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    window:SetSize(B.WIDTH, B.HEIGHT)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    B.Material(window, "shell", "bg")
    window.items, window.filtered, window.offset = {}, {}, 0
    window.Refresh, window.Selected = B.Update, B.Selected
    window.SetStatus = function(self, text) self.status:SetText(text or "") end
    Header(window)
    B.CreateNav(window)
    ScaleGrip(window)
    Body(window)
    Footer(window)
    B.CreateRows(window)
    Plan.Matrix.Create(window)
    B.CreateMotion(window)
    B.CreateKeyboard(window)
    window:SetScript("OnHide", Closed)
    window:Hide()
    return window
end

function B.Open(owner, spec)
    if not Plan.CanEdit() or owner.active == false or NS.InCombat() then return nil end
    if not B.window then
        Bridge.EnsureMenuTheme()
        B.window = Create()
    end
    local window = B.window
    B.ClearRestore(window)
    if window.maximized and window.normalPoint then
        window:ClearAllPoints()
        window:SetPoint(unpack(window.normalPoint))
    end
    window.maximized = nil
    window.scaleGrip:Show()
    window.restoreGlyph:Hide()
    if window:IsShown() then window:Hide() end
    window.owner, window.spec, window.profile = owner, spec, NS.DB
    window.selected, window.offset = nil, 0
    window.listScroll:Reset()
    window.detailScroll:Reset()
    local account = Plan.Account()
    ApplyScale(window, account and account.windowScale)
    B.LayoutNav(window)
    window.search:SetText("")
    window:Show()
    B.WatchAppearance()
    B.Restyle(owner)
    window:Refresh()
    B.PlayOpen(window)
    return window
end
