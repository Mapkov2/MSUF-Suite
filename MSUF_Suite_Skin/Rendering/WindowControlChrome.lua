local _, NS = ...

-- The map grip is our own button. Use the same material and hover/pressed
-- states as Suite controls instead of the old unframed chat grabber artwork.
local Chrome = {}
NS.WindowControlChrome = Chrome
local Safety = NS.Safety
local fills = setmetatable({}, { __mode = "k" })

function Chrome.Parent(state)
    -- WorldMap's root can be LOW while its border and quest log are HIGH.
    -- Inherit the visible border's strata without changing native frames.
    if state.name == "WorldMapFrame" then
        local border = Safety.Field(state.frame, "BorderFrame")
        if Safety.CanDecorate(border, not NS.IsCombatLocked()) and Safety.Read(border, "GetParent") == state.frame then return border end
    end
    return state.frame
end

function Chrome.Level(state)
    local parent = Chrome.Parent(state)
    local level = parent:GetFrameLevel()
    -- Native portrait chrome is raised independently on both clients.
    local borderLevel = Safety.Read(Safety.Field(parent, "NineSlice"), "GetFrameLevel")
    if type(borderLevel) == "number" then level = math.max(level, borderLevel) end
    return level
end

-- Footer actions and native resize handles retain their own hit rectangles.
local outsideGrips = {
    ProfessionsFrame = true, ModelPreviewFrame = true, EventTrace = true, OpacityFrame = true,
    ChatConfigFrame = true, HelpFrame = true, CooldownViewerSettings = true,
    ColorPickerFrame = true, ScriptErrorsFrame = true, ClickBindingFrame = true,
}

function Chrome.Footprint(state)
    if state.inventory and state.name ~= "BankFrame" then return 0, 0, 8 end
    local outside = outsideGrips[state.name] or state.inventory
    return (outside or state.name == "WorldMapFrame") and 21 or 0,
        outside and 21 or 0, state.inventory and state.name ~= "BankFrame" and 18 or 0
end

local function ExteriorGrip(grip, state)
    local frame = state.frame
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right, bottom = Safety.Read(frame, "GetRight"), Safety.Read(frame, "GetBottom")
    local leftSide = right ~= nil and (right + 21) * ratio > UIParent:GetWidth()
    local topSide = bottom ~= nil and (bottom - 21) * ratio < 0
    local corner = (topSide and "TOP" or "BOTTOM") .. (leftSide and "LEFT" or "RIGHT")
    local point = (topSide and "BOTTOM" or "TOP") .. (leftSide and "RIGHT" or "LEFT")
    grip:SetPoint(point, frame, corner, leftSide and -1 or 1, topSide and 1 or -1)
end

local function BagHandleEdge(state)
    local ratio = state.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local top = Safety.Read(state.frame, "GetTop")
    local below = top ~= nil and (top + 8) * ratio > UIParent:GetHeight()
    return below and "BOTTOM" or "TOP", below and -7 or 1
end

function Chrome.PlaceGrip(grip, state)
    grip:ClearAllPoints()
    if state.inventory and state.name ~= "BankFrame" then
        local edge, offset = BagHandleEdge(state)
        grip:SetSize(20, 6)
        grip:SetPoint("BOTTOMRIGHT", state.frame, edge .. "RIGHT", -8, offset)
    elseif state.name == "WorldMapFrame" then
        -- Clear quest scrolling and keep the grip above a maximized map's bottom edge.
        grip:SetPoint("BOTTOMLEFT", state.frame, "BOTTOMRIGHT", 1, 3)
        grip:SetClampedToScreen(true)
    elseif outsideGrips[state.name] or state.inventory then
        -- Flip the exterior corner at screen edges; never clamp onto native input.
        ExteriorGrip(grip, state)
    else
        grip:SetPoint("BOTTOMRIGHT", state.frame, "BOTTOMRIGHT", -3, 3)
    end
end

function Chrome.PlaceTitleDrag(strip, state)
    strip:ClearAllPoints()
    if state.inventory and state.name ~= "BankFrame" then
        -- Native bag titles route portrait-menu clicks over their entire area.
        local edge, offset = BagHandleEdge(state)
        strip:SetPoint("BOTTOMLEFT", state.frame, edge .. "LEFT", 50, offset)
        strip:SetPoint("BOTTOMRIGHT", state.frame, edge .. "RIGHT", -34, offset)
        strip:SetHeight(6)
        if not fills[strip] then Chrome.PaintControl(strip, "buttonFill") end
    elseif state.name == "OpacityFrame" then
        -- This native popup is only 80 wide; its slider starts 35 below the top.
        strip:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 4, -3)
        strip:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", -4, -3)
        strip:SetHeight(20)
    else
        strip:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 50, -1)
        strip:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", -math.max(110, state.captionInset or 0), -1)
        strip:SetHeight(24)
    end
end

local grips = setmetatable({}, { __mode = "k" })
local GRIP_SPEC = { role = "button", radius = 4, inset = 1, forceEdge = true }

function Chrome.RecolorGrip(grip)
    local lines = grips[grip]
    if not lines then return end
    local r, g, b, a = NS.Theme.GetColor("text")
    for index = 1, #lines do lines[index]:SetColorTexture(r, g, b, a * 0.8) end
end

-- The minimize button and the restore tab are our own frames too: painted
-- from the theme, and painted again after a look, colour or profile change.
function Chrome.RecolorControl(control)
    local fill = fills[control]
    if not fill then return end
    fill.background:SetColorTexture(NS.Theme.GetColor(fill.role))
    if fill.label then fill.label:SetTextColor(NS.Theme.GetColor("text")) end
end

function Chrome.PaintControl(control, role, label)
    local background = control:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    fills[control] = { background = background, role = role, label = label }
    Chrome.RecolorControl(control)
end

function Chrome.StyleGrip(grip)
    NS.Surface.SkinOwnedButton(grip, GRIP_SPEC)
    local lines = grips[grip]
    if not lines then
        lines = {}
        grips[grip] = lines
        for index = 1, 2 do
            local line = grip:CreateLine(nil, "OVERLAY", nil, 1)
            line:SetThickness(1)
            local span = index * 4
            line:SetStartPoint("BOTTOMRIGHT", grip, -5 - span, 5)
            line:SetEndPoint("BOTTOMRIGHT", grip, -5, 5 + span)
            lines[index] = line
        end
    end
    Chrome.RecolorGrip(grip)
end

local function TitleRegion(frame)
    local title = Safety.Call(frame, "GetTitleText")
    if Safety.Public(title) and title then return title end
    return Safety.Field(Safety.Field(frame, "TitleContainer"), "TitleText")
end

-- The window's own (localized) title, else a name derived from its frame.
function Chrome.Title(state)
    local text = Safety.Read(TitleRegion(state.frame), "GetText")
    -- Forever's outer container has no title region; all three child panes
    -- use this same localized native caption.
    if state.name == "LFGParentFrame" then text = NS.Safety.Field(_G, "LFG_TITLE") end
    if type(text) == "string" and text ~= "" then return text end
    return (state.name:gsub("Frame$", ""):gsub("(%l)(%u)", "%1 %2"))
end

local captionArt = setmetatable({}, { __mode = "k" })
local captionBars = {
    minimize = { { -4, -2, 4, -2 } },
    maximize = { { -4, -4, 4, -4 }, { 4, -4, 4, 4 }, { 4, 4, -4, 4 }, { -4, 4, -4, -4 } },
    restore = { { -5, -5, 2, -5 }, { 2, -5, 2, 2 }, { 2, 2, -5, 2 }, { -5, 2, -5, -5 },
        { -2, 2, -2, 5 }, { -2, 5, 5, 5 }, { 5, 5, 5, -2 }, { 5, -2, 2, -2 } },
}

local function PaintCaption(button)
    local art = captionArt[button]
    local r, g, b, a = NS.Theme.GetColor(art.disabled and "disabled" or "text")
    for _, texture in ipairs(art.bars) do texture:SetColorTexture(r, g, b, a) end
    local active = not art.disabled and (art.hover or art.down)
    art.fill:SetColorTexture(1, 1, 1, active and (art.down and 0.17 or 0.10) or 0)
end

local function LayoutCaption(button, kind)
    local art = captionArt[button]
    local pixelUtil = Safety.Field(_G, "PixelUtil")
    local scale = button:GetEffectiveScale()
    local nearest = Safety.Field(pixelUtil, "GetNearestPixelSize")
    local pixel = nearest and nearest(0, scale, 1) or 1
    local unit = nearest and nearest(1, scale, 1) or 1
    unit = math.min(unit, (math.min(button:GetWidth(), button:GetHeight()) - pixel) / 10)
    local bars = captionBars[kind]
    for index, bar in ipairs(bars) do
        local texture = art.bars[index]
        if not texture then
            texture = button:CreateTexture(nil, "OVERLAY")
            Safety.Invoke(texture, "SetRoundLayoutToNearestPixel", true)
            art.bars[index] = texture
        end
        local left, right = math.min(bar[1], bar[3]) * unit, math.max(bar[1], bar[3]) * unit
        local bottom, top = math.min(bar[2], bar[4]) * unit, math.max(bar[2], bar[4]) * unit
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", button, "CENTER", left - pixel / 2, top + pixel / 2)
        texture:SetSize(right - left + pixel, top - bottom + pixel)
        texture:Show()
    end
    for index = #bars + 1, #art.bars do art.bars[index]:Hide() end
    PaintCaption(button)
end

local function CaptionEnter(button)
    captionArt[button].hover = true
    PaintCaption(button)
end

local function CaptionLeave(button)
    local art = captionArt[button]
    art.hover, art.down = nil, nil
    PaintCaption(button)
end

local function CaptionDown(button)
    captionArt[button].down = true
    PaintCaption(button)
end

local function CaptionUp(button)
    captionArt[button].down = nil
    PaintCaption(button)
end

function Chrome.Control(button, kind, offset, disabled)
    button:SetSize(22, 22)
    button:SetFrameLevel(button:GetParent():GetFrameLevel() + offset)
    local fill = button:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(button)
    captionArt[button] = { fill = fill, bars = {}, disabled = disabled }
    LayoutCaption(button, kind)
    if disabled then
        button:EnableMouse(false)
    else
        button:SetScript("OnEnter", CaptionEnter)
        button:SetScript("OnLeave", CaptionLeave)
        button:SetScript("OnMouseDown", CaptionDown)
        button:SetScript("OnMouseUp", CaptionUp)
        button:SetScript("OnHide", CaptionLeave)
    end
end

local function TitleRight(frame, scale)
    local title = TitleRegion(frame)
    local width, right = Safety.Read(title, "GetStringWidth"), Safety.Read(title, "GetRight")
    local titleScale = Safety.Read(title, "GetEffectiveScale") or scale
    if not width or not right then return 0 end
    local justify = Safety.Read(title, "GetJustifyH")
    if justify == "LEFT" then
        right = (Safety.Read(title, "GetLeft") or right) + width
    elseif justify == "CENTER" then
        right = (Safety.Read(title, "GetCenter") or right) + width / 2
    end
    return right * titleScale / scale
end

local function CaptionObstacle(state, scale, right, low, high, ...)
    local obstacle = 0
    for index = 1, select("#", ...) do
        local child = select(index, ...)
        if not Safety.Public(child) then return right end
        local kind = Safety.Read(child, "GetObjectType")
        if child ~= state.close and child ~= state.minimize and child ~= state.maximize and child ~= state.captionMin
            and (kind == "Button" or kind == "CheckButton") and Safety.Read(child, "IsShown") then
            local top, bottom = Safety.Read(child, "GetTop"), Safety.Read(child, "GetBottom")
            local x, left = Safety.Read(child, "GetRight"), Safety.Read(child, "GetLeft")
            local childScale = Safety.Read(child, "GetEffectiveScale")
            if top and bottom and x and left and childScale then
                local ratio = childScale / scale
                if bottom * ratio < high and top * ratio > low and left * ratio < right then
                    obstacle = math.max(obstacle, x * ratio + 2)
                end
            end
        end
    end
    return obstacle
end

-- Work in the panel's local coordinates. Native close buttons may have a
-- different scale and their rectangles may move when Blizzard changes tabs.
function Chrome.CaptionSize(state)
    local frame, close = state.frame, state.close
    if not close or not Safety.Read(close, "IsShown") or Safety.Read(close, "IsVisible") == false then return nil, nil, 0 end
    local left, top = Safety.Read(frame, "GetLeft"), Safety.Read(frame, "GetTop")
    local scale = Safety.Read(frame, "GetEffectiveScale")
    local closeScale = Safety.Read(close, "GetEffectiveScale")
    local closeLeft, closeTop = Safety.Read(close, "GetLeft"), Safety.Read(close, "GetTop")
    local closeHeight = Safety.Read(close, "GetHeight")
    if not left or not top or not scale or scale <= 0 or not closeScale
        or not closeLeft or not closeTop or not closeHeight then return end
    local ratio = closeScale / scale
    closeLeft, closeTop, closeHeight = closeLeft * ratio, closeTop * ratio, closeHeight * ratio
    local right = left + frame:GetWidth()
    if closeLeft >= right then return nil, nil, 0 end
    if closeTop > top + 6 or closeTop - closeHeight < top - 38 or closeHeight < 16 then return end
    local centerY = closeTop - closeHeight / 2
    -- The native X can overhang the top edge. The added hit rectangles and
    -- hover fills stay inside the panel while sharing the X's vertical center.
    local height = math.min(closeHeight, 28, 2 * (top - centerY))
    if height < 14 then return nil, nil, 0 end
    local low, high = centerY - height / 2, centerY + height / 2
    local obstacle = CaptionObstacle(state, scale, closeLeft, low, high, Safety.Call(frame, "GetChildren"))
    local closeParent = Safety.Read(close, "GetParent")
    if closeParent and closeParent ~= frame then
        local headerObstacle = CaptionObstacle(state, scale, closeLeft, low, high, Safety.Call(closeParent, "GetChildren"))
        obstacle = math.max(obstacle, headerObstacle)
    end
    local room = closeLeft - math.max(left + 54, TitleRight(frame, scale) + 6, obstacle)
    local width = math.min(30, math.floor(room / 2))
    if width < 18 then return nil, height, room end
    return width, height, room, right - closeLeft + width * 2 + 4
end

local PlaceMinimize

function Chrome.SyncMinimize(state)
    if not state.minimize then return end
    local art = captionArt[state.minimize]
    local disabled = NS.IsCombatLocked() and NS.WindowControlPolicy.HasManagedVisibility(state)
    if (art.disabled == true) == disabled then return end
    art.disabled = disabled
    state.minimize:EnableMouse(not disabled)
    PaintCaption(state.minimize)
    if disabled then NS.CombatGate.RunOrDefer("windowControls:captions", NS.WindowControls.Refresh) end
end

function Chrome.ShowCaption(state, level)
    Chrome.SyncMinimize(state)
    local minimize, maximize = state.minimize or state.captionMin, state.maximize
    local width, height, room, inset = Chrome.CaptionSize(state)
    local gamepad = NS.Client.IsGamepadUI()
    if state.fit and (not width or gamepad) then
        Chrome.LeaveFit(state)
        width, height, room, inset = Chrome.CaptionSize(state)
    end
    state.captionInset = nil
    if maximize and width and not gamepad then
        state.captionInset = inset
        maximize:SetSize(width, height)
        minimize:SetSize(width, height)
        maximize:SetFrameLevel(level)
        minimize:SetFrameLevel(level)
        maximize:ClearAllPoints()
        maximize:SetPoint("RIGHT", state.close, "LEFT", 0, 0)
        minimize:ClearAllPoints()
        minimize:SetPoint("RIGHT", maximize, "LEFT", 0, 0)
        LayoutCaption(maximize, state.fit and "restore" or "maximize")
        LayoutCaption(minimize, "minimize")
        maximize:Show()
        minimize:Show()
        return
    end
    if maximize then maximize:Hide() end
    if state.minimize and not gamepad and (room == nil or room >= 25) then
        minimize:SetSize(22, height or 22)
        minimize:SetFrameLevel(level)
        minimize:ClearAllPoints()
        PlaceMinimize(minimize, state.frame, state.close)
        LayoutCaption(minimize, "minimize")
        minimize:Show()
    elseif minimize then
        minimize:Hide()
    end
end

function Chrome.RecolorCaption(state)
    if state.minimize then PaintCaption(state.minimize) end
    if state.captionMin then PaintCaption(state.captionMin) end
    if state.maximize then PaintCaption(state.maximize) end
end

-- Fixed-size native panels fill the available area by scaling uniformly.
-- Keep a small screen margin and include exterior resize handles in the fit.
local function NativeFitExtra(frame, key)
    if NS.IsCombatLocked() then
        -- The panel manager's getter can seed native attributes on first read.
        local value = Safety.Read(frame, "GetAttribute", "UIPanelLayout-" .. key)
        return type(value) == "number" and value or 0
    end
    local read = Safety.Field(_G, "GetUIPanelAttribute")
    local value = read and read(frame, key)
    if Safety.Public(value) and type(value) == "number" then return value end
    return 0
end

function Chrome.Fit(state)
    local frame = state.frame
    if state.fit.applying then return end
    local right, bottom, top = Chrome.Footprint(state)
    local extraWidth = NativeFitExtra(frame, "checkFitExtraWidth")
    local extraHeight = NativeFitExtra(frame, "checkFitExtraHeight")
    right, bottom = math.max(right, extraWidth), math.max(bottom, extraHeight)
    local scaleFactor = frame:GetEffectiveScale() / frame:GetScale() / UIParent:GetEffectiveScale()
    local width, height = frame:GetWidth() + right, frame:GetHeight() + bottom + top
    if scaleFactor <= 0 or width <= 0 or height <= 0 then return end
    local uiWidth, uiHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local scale = math.min((uiWidth - 16) / width, (uiHeight - 16) / height) / scaleFactor
    if scale <= 0 then return end
    state.fit.applying = true
    if frame:GetScale() ~= scale then frame:SetScale(scale) end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", -right / 2, (bottom - top) / 2)
    state.fit.applying = nil
end

local function ValidClose(candidate)
    if candidate and Safety.Read(candidate, "GetObjectType") == "Button"
        and not Safety.GetProtection(candidate) then
        return candidate
    end
end

function Chrome.FindClose(frame, name)
    return ValidClose(Safety.Field(frame, "ClosePanelButton"))
        or ValidClose(Safety.Field(Safety.Field(frame, "Border"), "CloseButton"))
        or ValidClose(Safety.Field(Safety.Field(frame, "BorderFrame"), "CloseButton"))
        or ValidClose(Safety.Field(_G, name .. "CloseButton"))
        or ValidClose(Safety.Field(frame, "CloseButton"))
end

local function NativeCaption(frame)
    return Safety.Field(frame, "MinimizeButton") or Safety.Field(frame, "MaximizeButton")
        or Safety.Field(frame, "MaximizeMinimize") or Safety.Field(frame, "MaximizeMinimizeFrame")
        or Safety.Field(frame, "MaximizeMinimizeButton") or Safety.Field(frame, "MaxMinButtonFrame")
end

function Chrome.HasNativeCaption(frame, name, close)
    local header = Safety.Read(close, "GetParent")
    return NativeCaption(frame) or (header ~= frame and NativeCaption(header))
        or Safety.Field(_G, name .. "MinimizeButton") or Safety.Field(_G, name .. "MaximizeButton")
end

function Chrome.LeaveFit(state)
    local fit = state.fit
    if not fit or not NS.WindowControlPolicy.CanChangeGeometry(state.frame) then return end
    local frame = state.frame
    state.fit = nil
    frame:SetScale(fit.scale)
    frame:ClearAllPoints()
    for _, point in ipairs(fit.points) do frame:SetPoint(unpack(point)) end
end

function Chrome.EndFit(state)
    local fit = state.fit
    if NS.WindowControlPolicy.CanChangeGeometry(state.frame) then
        Chrome.LeaveFit(state)
    else
        NS.CombatGate.RunOrDefer(fit, function()
            if state.fit == fit then
                Chrome.LeaveFit(state)
                if state.frame:IsShown() then NS.WindowControls.Refresh() end
            end
        end)
    end
end

function Chrome.ToggleFit(state, capturePoints)
    if state.fit then
        Chrome.LeaveFit(state)
    else
        local points = capturePoints(state.frame)
        if not points then return false end
        state.fit = { points = points, scale = state.frame:GetScale() }
    end
    return true
end

PlaceMinimize = function(button, frame, close)
    local anchor = close and Safety.Read(close, "GetPoint", 1)
    if type(anchor) == "string" and anchor:find("TOP", 1, true) then
        button:SetPoint("RIGHT", close, "LEFT", -3, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -4)
    end
end

function Chrome.CreateMinimize(state, close, level, click)
    local button = Safety.CreateChildFrame("Button", state.frame)
    Chrome.Control(button, "minimize", level)
    PlaceMinimize(button, state.frame, close)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", click)
    return button
end

local function OnRestoreDragStart(bar)
    if not NS.IsCombatLocked() then bar:StartMoving() end
end

local function OnRestoreDragStop(bar)
    bar:StopMovingOrSizing()
end

function Chrome.CreateRestore(state, click)
    local bar = CreateFrame("Button", nil, UIParent)
    bar:SetSize(154, 26)
    bar:SetFrameStrata("DIALOG")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar:SetScript("OnDragStart", OnRestoreDragStart)
    bar:SetScript("OnDragStop", OnRestoreDragStop)
    Chrome.PaintControl(bar, "popup")
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 10, 0)
    label:SetPoint("RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    state.restoreLabel = label
    bar:SetScript("OnClick", click)
    bar:Hide()
    return bar
end

function Chrome.CreateCaption(state, level, click)
    if state.maximize or state.inventory or not Chrome.CaptionSize(state) then return end
    local frame = state.frame
    local button = Safety.CreateChildFrame("Button", frame)
    state.maximize = button
    Chrome.Control(button, "maximize", level)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", click)
    if not state.minimize then
        state.captionMin = Safety.CreateChildFrame("Button", frame)
        Chrome.Control(state.captionMin, "minimize", level, true)
    end
    return button
end
