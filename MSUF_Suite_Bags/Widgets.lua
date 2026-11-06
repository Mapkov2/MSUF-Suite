local _, P = ...
local NS, S, M = P.NS, P.Suite, P.BagsModule
local UI = { panels = setmetatable({}, { __mode = "k" }) }
P.BagWidgets = UI
local min, max = math.min, math.max

local function Surface(frame, material)
    local fill = S.CreateTexture(frame, nil, "BACKGROUND")
    fill:SetAllPoints(frame)
    local r, g, b = S.RGB(S.Config("bags").backgroundColor)
    fill:SetColorTexture(r, g, b, .98)
    if NS.HostBridge.MenuMaterial(frame, material or "card") then fill:Hide() end
    UI.panels[frame] = { fill = fill, material = material or "card" }
end

function UI.Refresh()
    if NS.InCombat() then return end
    for frame, data in pairs(UI.panels) do
        local r, g, b = S.RGB(S.Config("bags").backgroundColor)
        data.fill:SetColorTexture(r, g, b, .98)
        data.fill:SetShown(not NS.HostBridge.MenuMaterial(frame, data.material))
    end
    P.BagCheckStyle.Refresh()
end

function UI.Prepare()
    NS.HostBridge.EnsureMenuTheme()
    NS.HostBridge.WatchMenuAppearance(UI, UI.Refresh)
    UI.Refresh()
end

function UI.Button(parent, text, width, action, height)
    local button = NS.HostBridge.MenuButton(parent, width, height or 24)
    if not button then return P.GridView.Button(parent, text, width, action, height or 24) end
    button:SetText(S.Text(text))
    button:SetScript("OnClick", action)
    return button
end

function UI.Input(parent, x, y, width)
    local edit = P.ChildFrame("EditBox", parent)
    edit:SetSize(width, 24)
    edit:SetPoint("TOPLEFT", x, y)
    edit:SetAutoFocus(false)
    S.SetFont(edit, S.GlobalFontPath(), 12, "")
    edit:SetTextInsets(8, 8, 0, 0)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    if not NS.HostBridge.MenuInput(edit) then Surface(edit, "card") end
    return edit
end

function UI.Window(name, width, height, title)
    UI.Prepare()
    local frame = S.CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Surface(frame, "shell")
    frame:HookScript("OnShow", UI.Refresh)
    NS.HostBridge.MenuAtmosphere(frame)
    local label = P.GridView.Font(frame, 16)
    label:SetPoint("TOPLEFT", 16, -11)
    label:SetText(S.Text(title))
    local close = NS.HostBridge.MenuCloseButton(frame) or UI.Button(frame, "X", 24, function() frame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() frame:Hide() end)
    local drag = P.ChildFrame("Button", frame)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT", -40, 0)
    drag:SetHeight(34)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame.close, frame.dragHandle = close, drag
    UISpecialFrames[#UISpecialFrames + 1] = name
    return frame
end

function UI.Check(parent, x, y, label)
    local check = NS.HostBridge.MenuCheckbox(parent, label and S.Text(label))
    if check then
        check:ClearAllPoints()
        check:SetPoint("TOPLEFT",x,y)
        return check
    end
    check = P.ChildFrame("CheckButton", parent, "MSUFSuiteBagCheckTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    Surface(check, "card")
    P.BagCheckStyle.Apply(check, label)
    return check
end

local function ThumbPressed(bar) P.BagWidgetScroll.Cancel(bar.scroll) end

local function ValueChanged(bar, value)
    if bar.writing then return end
    P.BagWidgetScroll.Cancel(bar.scroll)
    if not P.BagWidgetScroll.CanChange(bar.scroll) then return end
    bar.scroll:SetVerticalScroll(value)
end

function UI.UpdateScroll(scroll)
    local bar = scroll.bagScrollBar
    if bar.writing then return end
    if not P.BagWidgetScroll.CanChange(scroll) then
        P.BagWidgetScroll.Cancel(scroll)
        return
    end
    local child = scroll:GetScrollChild()
    local content, viewport = child:GetHeight(), scroll:GetHeight()
    local range = max(0, content - viewport)
    local offset = scroll:GetVerticalScroll()
    local value = min(range, max(0, offset))
    P.BagWidgetScroll.Clamp(scroll, range, value)
    if bar.content == content and bar.viewport == viewport and bar.offset == value and bar.accent == S.Config("bags").accentColor then return end
    bar.writing = true
    if bar.range ~= range then bar.range = range bar:SetMinMaxValues(0, range) end
    if offset ~= value then scroll:SetVerticalScroll(value) end
    bar:SetValue(value)
    bar:SetShown(range > 0)
    bar.Thumb:SetHeight(max(20, min(viewport, viewport * viewport / max(1, content))))
    local r, g, b = S.RGB(S.Config("bags").accentColor)
    bar.Thumb:SetColorTexture(r, g, b, .8)
    bar.content, bar.viewport, bar.offset, bar.accent = content, viewport, value, S.Config("bags").accentColor
    bar.writing = nil
end

local function ScrollChanged(scroll) UI.UpdateScroll(scroll) end
local function VerticalChanged(scroll)
    if not scroll.bagScrollWriting then P.BagWidgetScroll.Cancel(scroll) end
    UI.UpdateScroll(scroll)
end

function UI.Scroll(parent, width)
    local scroll = P.ChildFrame("ScrollFrame", parent)
    scroll:SetWidth(width)
    scroll:SetFrameLevel(parent:GetFrameLevel() + 1)
    local child = P.ChildFrame("Frame", scroll)
    child:SetWidth(width)
    child:SetHeight(1)
    child:SetFrameLevel(scroll:GetFrameLevel() + 1)
    scroll:SetScrollChild(child)
    local bar = P.ChildFrame("Slider", scroll, "MSUFSuiteBagScrollSliderTemplate")
    bar.scroll = scroll
    scroll.bagScrollBar = bar
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
    bar:SetFrameLevel(scroll:GetFrameLevel() + 4)
    bar:SetValueStep(1)
    bar:SetMinMaxValues(0, 0)
    bar:SetScript("OnValueChanged", ValueChanged)
    bar:HookScript("OnMouseDown", ThumbPressed)
    local track = S.CreateTexture(bar, nil, "BACKGROUND")
    track:SetPoint("TOP")
    track:SetPoint("BOTTOM")
    track:SetWidth(2)
    track:SetColorTexture(.28, .31, .36, .45)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", P.BagWidgetScroll.Wheel)
    scroll:SetScript("OnVerticalScroll", VerticalChanged)
    scroll:SetScript("OnScrollRangeChanged", ScrollChanged)
    scroll:SetScript("OnSizeChanged", ScrollChanged)
    P.BagWidgetScroll.Attach(scroll)
    return scroll, child
end

function UI.Popup(name)
    local frame = S.CreateFrame("Frame", name, UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    Surface(frame, "card")
    frame:HookScript("OnShow", UI.Refresh)
    UISpecialFrames[#UISpecialFrames + 1] = name
    return frame
end
