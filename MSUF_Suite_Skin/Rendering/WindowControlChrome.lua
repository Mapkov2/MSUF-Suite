local _, NS = ...

-- Use Suite material and hover/pressed states for the owned map grip.
local Chrome = {}
NS.WindowControlChrome = Chrome
local Safety = NS.Safety
local function PublicNumber(value) return Safety.Public(value) and type(value) == "number" end
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
    ColorPickerFrame = true, ScriptErrorsFrame = true, ClickBindingFrame = true, QuestFrame = true,
    MailFrame = true, OpenMailFrame = true, ClassTrainerFrame = true, CollectionsJournal = true,
}

function Chrome.Footprint(state)
    local bounds = state.suiteBounds
    if bounds then
        local width, height = Safety.Read(state.frame, "GetWidth"), Safety.Read(state.frame, "GetHeight")
        return math.max(0, bounds.width - (width or bounds.width)), math.max(0, bounds.height - (height or bounds.height)), 0
    end
    if state.inventory and state.name ~= "BankFrame" then return 0, 0, 8 end
    local outside = outsideGrips[state.name] or state.inventory
    return NS.WindowControlPolicy.ExteriorWidth(state, (outside or state.name == "WorldMapFrame") and 21 or 0),
        outside and 21 or 0, state.inventory and state.name ~= "BankFrame" and 18 or 0
end

local function ExteriorGrip(grip, state)
    local frame = state.frame
    local ratio = NS.WindowControlPolicy.ScreenRatio(frame)
    local right, bottom = Safety.Read(frame, "GetRight"), Safety.Read(frame, "GetBottom")
    local topSide = ratio and type(bottom) == "number" and (bottom - 21) * ratio < 0
    if state.name == "HelpFrame" and not topSide then
        grip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        return
    end
    if NS.Client.isForever and state.name == "ProfessionsFrame" and not topSide then
        -- Dock under the lower border. Camelot's Create button starts at y=7,
        -- and the profession tabs sit beyond the right edge.
        grip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 3)
        return
    end
    local uiWidth = UIParent:GetWidth()
    local leftSide = ratio and type(right) == "number" and PublicNumber(uiWidth) and (right + 21) * ratio > uiWidth
    local corner = (topSide and "TOP" or "BOTTOM") .. (leftSide and "LEFT" or "RIGHT")
    local point = (topSide and "BOTTOM" or "TOP") .. (leftSide and "RIGHT" or "LEFT")
    grip:SetPoint(point, frame, corner, leftSide and -1 or 1, topSide and 1 or -1)
end

local function BagHandleEdge(state)
    local ratio = NS.WindowControlPolicy.ScreenRatio(state.frame)
    local top, uiHeight = Safety.Read(state.frame, "GetTop"), UIParent:GetHeight()
    local below = ratio and type(top) == "number" and PublicNumber(uiHeight) and (top + 8) * ratio > uiHeight
    return below and "BOTTOM" or "TOP", below and -7 or 1
end

local function BankGrip(grip, frame)
    -- The Forever bank panel is narrower than its outer frame. Inset the
    -- grip from the visible corner and clear the money row, which ends at 28.
    local panel = Safety.Field(frame, "BankPanel") or frame
    local x, y = -5, 30
    local ratio = NS.WindowControlPolicy.ScreenRatio(frame)
    local right, bottom = Safety.Read(panel, "GetRight"), Safety.Read(panel, "GetBottom")
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if ratio and PublicNumber(right) and PublicNumber(bottom) and PublicNumber(width) and PublicNumber(height) then
        x = math.min(width / ratio - right, math.max(x, grip:GetWidth() - right))
        y = math.max(-bottom, math.min(y, height / ratio - bottom - grip:GetHeight()))
    end
    grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", x, y)
end

function Chrome.PlaceGrip(grip, state)
    grip:ClearAllPoints()
    if state.inventory and state.name ~= "BankFrame" then
        local edge, offset = BagHandleEdge(state)
        grip:SetSize(20, 6)
        grip:SetPoint("BOTTOMRIGHT", state.frame, edge .. "RIGHT", -8, offset)
    elseif state.name == "BankFrame" then
        BankGrip(grip, state.frame)
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

function Chrome.Title(state)
    local text = Safety.Read(TitleRegion(state.frame), "GetText")
    -- Forever's outer container has no title region; all three child panes
    -- use this same localized native caption.
    if state.name == "LFGParentFrame" then text = NS.Safety.Field(_G, "LFG_TITLE") end
    if type(text) == "string" and text ~= "" then return text end
    return (state.name:gsub("Frame$", ""):gsub("(%l)(%u)", "%1 %2"))
end
local captionArt = setmetatable({}, { __mode = "k" })
local function NewCaptionBars()
    local caption = NS.SuiteCore().WindowCaption
    return caption.NewBars and caption.NewBars() or {}
end
local function PaintCaption(button, refreshGlyph)
    local art = captionArt[button]
    local caption = NS.SuiteCore().WindowCaption
    if refreshGlyph then caption.UpdateGlyph(button, art) end
    local active = not art.disabled and (art.hover or art.down)
    local r, g, b, a = NS.Theme.GetColor(art.disabled and "disabled" or "text")
    -- Windows' close cell turns red under the pointer, its cross white.
    if art.kind == "close" and active then r, g, b, a = 1, 1, 1, 1 end
    if caption.PaintGlyph then
        caption.PaintGlyph(art.bars, r, g, b, a)
    else
        for _, texture in ipairs(art.bars) do texture:SetColorTexture(r, g, b, a) end
    end
    if art.kind == "close" then
        r, g, b = NS.Theme.GetColor("danger")
        a = active and (art.down and 1 or 0.85) or 0
    else
        r, g, b = 1, 1, 1
        a = active and (art.down and 0.17 or 0.10) or 0
    end
    if not (Safety.Public(r) and Safety.Public(g) and Safety.Public(b) and Safety.Public(a)) then
        art.fillR = nil
        art.fill:SetColorTexture(r, g, b, a)
    elseif art.fillR ~= r or art.fillG ~= g or art.fillB ~= b or art.fillA ~= a then
        art.fill:SetColorTexture(r, g, b, a)
        art.fillR, art.fillG, art.fillB, art.fillA = r, g, b, a
    end
end
Chrome.PaintActionCell = PaintCaption
local function LayoutCaption(button, kind)
    local art = captionArt[button]
    art.kind = kind
    NS.SuiteCore().WindowCaption.UpdateGlyph(button, art, true)
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
    captionArt[button] = { fill = fill, bars = NewCaptionBars(), disabled = disabled }
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
    return captionArt[button]
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

-- Widget type is fixed for a created frame. Remember only public non-buttons;
-- every candidate obstacle still supplies live visibility, bounds and scale.
local nonButtons = setmetatable({}, { __mode = "k" })
local function IsObstacleButton(child)
    if nonButtons[child] then return false end
    local kind = Safety.Read(child, "GetObjectType")
    if kind == "Button" or kind == "CheckButton" then return true end
    if kind then nonButtons[child] = true end
    return false
end

local function CaptionObstacle(state, scale, right, low, high, ...)
    local obstacle, titleLimit = 0, right
    for index = 1, select("#", ...) do
        local child = select(index, ...)
        if not Safety.Public(child) then return right, nil end
        if child ~= state.close and child ~= state.minimize and child ~= state.maximize
            and IsObstacleButton(child) and Safety.Read(child, "IsShown") then
            local top, bottom = Safety.Read(child, "GetTop"), Safety.Read(child, "GetBottom")
            local x, left = Safety.Read(child, "GetRight"), Safety.Read(child, "GetLeft")
            local childScale = Safety.Read(child, "GetEffectiveScale")
            if top and bottom and x and left and childScale then
                local ratio = childScale / scale
                if bottom * ratio < high and top * ratio > low and left * ratio < right then
                    obstacle = math.max(obstacle, x * ratio + 2)
                    if x * ratio >= (state.captionLeft or 0) then titleLimit = math.min(titleLimit, left * ratio) end
                end
            end
        end
    end
    return obstacle, titleLimit
end

-- Windows caption, right to left: close, maximize/restore, minimize. One
-- cell size for all three, in the panel's own units: the cells scale with the
-- window. The close cell is the part of Blizzard's X inside the panel, so an
-- X that overhangs the corner is drawn inside. Blizzard's X and a native size
-- toggle keep their clicks; their art fades while our cells show.
function Chrome.CaptionSize(state)
    local frame, close = state.frame, state.close
    if not close or not Safety.Read(close, "IsShown") then return nil, nil, 0 end
    local left, top, frameWidth = Safety.Read(frame, "GetLeft"), Safety.Read(frame, "GetTop"), Safety.Read(frame, "GetWidth")
    local scale, closeScale = Safety.Read(frame, "GetEffectiveScale"), Safety.Read(close, "GetEffectiveScale")
    local closeLeft, closeTop = Safety.Read(close, "GetLeft"), Safety.Read(close, "GetTop")
    local closeWidth, closeHeight = Safety.Read(close, "GetWidth"), Safety.Read(close, "GetHeight")
    if not left or not top or not frameWidth or not scale or scale <= 0 or not closeScale or not closeLeft
        or not closeTop or not closeWidth or not closeHeight then return end
    local ratio = closeScale / scale
    local right = left + frameWidth
    closeLeft, closeTop = closeLeft * ratio, closeTop * ratio
    local closeRight, closeBottom = math.min(closeLeft + closeWidth * ratio, right - 1), closeTop - closeHeight * ratio
    if closeLeft >= right then return nil, nil, 0 end
    -- A footer Close action is no caption X (no room: minimize stays alone).
    if closeTop > top + 6 or closeBottom < top - 40 or closeHeight * ratio < 16 then return end
    closeTop = math.min(closeTop, top - 1)
    local width, height = math.min(30, closeRight - closeLeft), math.min(26, closeTop - closeBottom)
    if width < 14 or height < 14 then return nil, nil, 0 end
    local cellLeft, low = closeRight - width, closeTop - height
    state.captionLeft = left + frameWidth / 2
    local obstacle, limit = CaptionObstacle(state, scale, cellLeft, low, closeTop, Safety.Call(frame, "GetChildren"))
    local closeParent = Safety.Read(close, "GetParent")
    if closeParent and closeParent ~= frame then
        local edge, start = CaptionObstacle(state, scale, cellLeft, low, closeTop, Safety.Call(closeParent, "GetChildren"))
        obstacle, limit = math.max(obstacle, edge), limit and start and math.min(limit, start)
    end
    state.captionX, state.captionY = closeRight - right, closeTop - top
    local room = cellLeft - math.max(left + 54, TitleRight(frame, scale) + 6, obstacle)
    return width, height, room, right - cellLeft + width * 2 + 4, limit, right, scale
end
local PlaceMinimize
function Chrome.SyncMinimize(state)
    if not state.minimize then return end
    local art = captionArt[state.minimize]
    local policy = NS.WindowControlPolicy
    local disabled = NS.IsCombatLocked() and (policy.NeedsPark(state) or policy.CanNativeMinimize(state))
    if (art.disabled == true) == disabled then return end
    art.disabled = disabled
    state.minimize:EnableMouse(not disabled)
    PaintCaption(state.minimize)
    if disabled then NS.CombatGate.RunOrDefer("windowControls:captions", NS.WindowControls.Refresh) end
end

-- Drawn cells over Blizzard's own buttons have no mouse of their own: the
-- native button's hover and press paint them.
local drivers = setmetatable({}, { __mode = "k" })
local cellStates = setmetatable({}, { __mode = "k" })
local function DriveEnter(button)
    local cell = drivers[button]
    if not cell then return end
    CaptionEnter(cell)
    local state = cellStates[cell]
    if state and state.settle and cell:IsShown() and (Safety.Read(button, "GetAlpha") or 0) ~= 0 then
        state.settle("hover")
    end
end
local function DriveLeave(button) if drivers[button] then CaptionLeave(drivers[button]) end end
local function DriveDown(button) if drivers[button] then CaptionDown(drivers[button]) end end
local function DriveUp(button) if drivers[button] then CaptionUp(drivers[button]) end end

local function Drive(button, cell)
    if not Safety.HasMethod(button, "HookScript") or drivers[button] == cell then return end
    if drivers[button] == nil then
        button:HookScript("OnEnter", DriveEnter)
        button:HookScript("OnLeave", DriveLeave)
        button:HookScript("OnMouseDown", DriveDown)
        button:HookScript("OnMouseUp", DriveUp)
    end
    drivers[button] = cell
end

local function DrawnCell(state, key)
    local cell = state[key]
    if cell then return cell end
    cell = Safety.CreateChildFrame("Frame", Chrome.Parent(state))
    local fill = cell:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(cell)
    captionArt[cell] = { fill = fill, bars = NewCaptionBars() }
    cellStates[cell] = state
    state[key] = cell
    return cell
end

local NativeArt = NS.WindowControlNativeArt
local FadeNative, RestoreNative, FadeSockets = NativeArt.Fade, NativeArt.Restore, NativeArt.FadeSockets
local NativeShown, Report = NativeArt.Shown, NativeArt.Report
Chrome.IsFaded = NativeArt.IsFaded
local RefreshFocus = function() end
function Chrome.SetFocusRefresh(callback) RefreshFocus = callback end

local CELLS = { "closeCell", "toggleCell", "maximize", "minimize" }
function Chrome.HideCaption(state, keepMinimize)
    if NS.CaptionTitles then NS.CaptionTitles.Restore(state) end
    for _, key in ipairs(CELLS) do
        if state[key] and (key ~= "minimize" or not keepMinimize) then state[key]:Hide() end
    end
    for target in pairs(state.nativeRoots or {}) do RestoreNative(state, target) end
    RefreshFocus(state.frame)
end

-- These Suite cells are explicitly anchored to one public sibling or parent.
-- A hidden/recycled cell with a second or unreadable anchor is placed afresh.
local function AnchorCell(cell, point, parent, other, x, y)
    local restricted = cell.IsAnchoringRestricted and cell:IsAnchoringRestricted()
    if Safety.Public(restricted) and not restricted and cell.GetNumPoints and cell.GetPoint then
        local count = cell:GetNumPoints()
        if Safety.Public(count) and count == 1 then
            local p, target, relative, dx, dy = cell:GetPoint(1)
            if Safety.Public(p) and Safety.Public(target) and Safety.Public(relative) and Safety.Public(dx) and Safety.Public(dy)
                and p == point and target == parent and relative == other and dx == x and dy == y then return end
        end
    end
    cell:ClearAllPoints()
    cell:SetPoint(point, parent, other, x, y)
end

local function PlaceCell(cell, anchor, width, height, level, kind)
    local w, h, actualLevel = cell:GetWidth(), cell:GetHeight(), cell:GetFrameLevel()
    if not Safety.Public(w) or not Safety.Public(h) or w ~= width or h ~= height then cell:SetSize(width, height) end
    if not Safety.Public(actualLevel) or actualLevel ~= level then cell:SetFrameLevel(level) end
    if anchor then AnchorCell(cell, "RIGHT", anchor, "LEFT", 0, 0) end
    LayoutCaption(cell, kind)
    cell:Show()
    if kind == "minimize" then NS.WindowControlDelegate.Refresh(cell) end
    return cell
end

local function ToggleCell(state, anchor, width, height, level)
    local toggle = state.sizeToggle
    local maximize = Safety.Field(toggle, "MaximizeButton")
    if not Safety.Read(toggle, "IsShown") or not FadeNative(state, toggle) then
        if state.toggleCell then state.toggleCell:Hide() end
        return nil
    end
    local cell = DrawnCell(state, "toggleCell")
    Drive(maximize, cell)
    Drive(Safety.Field(toggle, "MinimizeButton"), cell)
    return PlaceCell(cell, anchor, width, height, level, Safety.Read(maximize, "IsShown") and "maximize" or "restore")
end

local function ShowStandaloneMinimize(state, level, besideClose)
    local button, frame = state.minimize, state.frame
    button:ClearAllPoints()
    if besideClose then
        PlaceMinimize(button, state, state.close)
    else
        NS.WindowControlPolicy.PlaceExtraCaption(button, frame)
    end
    return PlaceCell(button, nil, 22, 22, level, "minimize")
end

local function PlaceCloseCell(state, width, height, level)
    local close = DrawnCell(state, "closeCell")
    AnchorCell(close, "TOPRIGHT", state.frame, "TOPRIGHT", state.captionX, state.captionY)
    PlaceCell(close, nil, width, height, level, "close")
    Drive(state.close, close)
    FadeSockets(state)
    RefreshFocus(state.frame)
    return close
end

function Chrome.ShowCaption(state, level)
    Chrome.SyncMinimize(state)
    local width, height, room, inset, limit, right, scale = Chrome.CaptionSize(state)
    local gamepad = NS.Client.IsGamepadUI()
    if state.fit and (not width or gamepad) then
        Chrome.LeaveFit(state)
        width, height, room, inset, limit, right, scale = Chrome.CaptionSize(state)
    end
    local nativeClose = state.name == "CatalogShopFrame"
    local cells = width and not gamepad and not state.nativeCaption and (nativeClose or FadeNative(state, state.close))
    -- Combat leaves a shown caption where it is (a protected window can read
    -- as unsized there): Blizzard's buttons stay faded, the toggle's cell comes
    -- and goes with the toggle, and the window is laid out once combat ends.
    if not cells and NS.IsCombatLocked() and state.closeCell and state.closeCell:IsShown() then
        local toggle, shown = state.sizeToggle, Safety.Read(state.sizeToggle, "IsShown") == true
        if shown then FadeNative(state, toggle) end
        if state.toggleCell then state.toggleCell:SetShown(shown) end
        for target in pairs(state.nativeRoots or {}) do FadeNative(state, target) end
        return NS.CombatGate.RunOrDefer(state.replayKey, state.replayShow)
    end
    state.captionInset, state.captionLevel = nil, level
    local minimize = state.minimize and NS.WindowControlPolicy.OffersMinimize(state) and state.minimize
    if not minimize and state.minimize then state.minimize:Hide() end
    if not cells then
        state.captionPath = not width and "size" or gamepad and "gamepad" or "protected"
        local showMinimize = minimize and not gamepad and Safety.Read(state.close, "IsShown") ~= false
        Chrome.HideCaption(state, showMinimize)
        if not showMinimize then return end
        return ShowStandaloneMinimize(state, level, state.close and room == nil and not state.nativeCaption)
    end
    if NS.CaptionTitles then NS.CaptionTitles.Fit(state, limit, right, scale) end
    state.captionInset, state.captionPath = inset, "cells"
    for _, native in ipairs({ state.close, state.sizeToggle }) do
        local nativeLevel = Safety.Read(native, "GetFrameLevel")
        if type(nativeLevel) == "number" and nativeLevel + 2 > level then level = nativeLevel + 2 end
    end
    local toggle = state.sizeToggle and Safety.Read(state.sizeToggle, "IsShown")
    -- A tight title shrinks all cells alike before one of them gives way.
    local cells = ((state.maximize or toggle) and 1 or 0) + (minimize and 1 or 0)
    if cells > 0 and room < width * cells then width = math.max(18, math.floor(room / cells)) end
    local close = nativeClose and state.close or PlaceCloseCell(state, width, height, level)
    local middle = state.sizeToggle and ToggleCell(state, close, width, height, level)
    local maximize = state.maximize
    if maximize and not middle and room >= width * 2 then
        middle = PlaceCell(maximize, close, width, height, level, state.fit and "restore" or "maximize")
    elseif maximize then
        -- Without its restore cell (Blizzard's size toggle took the place, or
        -- the title is too tight) a fitted window goes back to its own size.
        if state.fit then
            Chrome.LeaveFit(state)
            if not state.fit then return Chrome.ShowCaption(state, level) end
        end
        maximize:Hide()
    end
    if minimize and room >= width * (middle and 2 or 1) then
        PlaceCell(minimize, middle or close, width, height, level, "minimize")
    elseif minimize then
        ShowStandaloneMinimize(state, level, false)
    end
end

-- Ordinary windows need only their native hooks, next-frame layout and one late settle.
local OPENING_SECONDS = 3
local opening, finalTimers = {}, {}
local watcher = CreateFrame("Frame")
watcher:Hide()

local function EndOpening(state)
    local timer = finalTimers[state]
    if timer then
        finalTimers[state] = nil
        timer:Cancel()
    end
    if opening[state] then
        opening[state] = nil
        if not next(opening) then
            watcher:SetScript("OnUpdate", nil)
            watcher:Hide()
        end
    end
    if not next(opening) and not next(finalTimers) then watcher:UnregisterEvent("PLAYER_REGEN_DISABLED") end
end
watcher:SetScript("OnEvent", function()
    for state in pairs(opening) do EndOpening(state) end
    for state in pairs(finalTimers) do EndOpening(state) end
end)

local function Watch(_, elapsed)
    for state, age in pairs(opening) do
        age = age + (elapsed or 0)
        opening[state] = age
        local cell = state.closeCell
        if age >= OPENING_SECONDS then
            EndOpening(state)
            if not NS.IsCombatLocked() then state.settle(OPENING_SECONDS .. "s") end
        elseif cell and cell:IsVisible() and NativeShown(state) then
            -- The combat event disarms every opening. Check the edge again
            -- before a repair, even when the native reset precedes that event.
            if NS.IsCombatLocked() then EndOpening(state) else state.settle(("%.2fs"):format(age)) end
        end
    end
end
local function WatchOpening(state)
    if not next(opening) then
        watcher:SetScript("OnUpdate", Watch)
        watcher:Show()
    end
    opening[state] = 0
end

function Chrome.Settle(state, level, allowed)
    if Safety.Read(state.frame, "IsVisible") ~= true then return end
    state.settleLevel, state.settleAllowed = level, allowed
    state.settle = state.settle or function(moment)
        if not state.settleAllowed(state) then return end
        Report(state, moment)
        if finalTimers[state] and state.reported and not opening[state] then WatchOpening(state) end
        Chrome.ShowCaption(state, state.settleLevel)
    end
    if not state.watchHooked then
        state.watchHooked = true
        state.frame:HookScript("OnHide", function()
            NS.Registry.CancelJob(state.settle)
            if opening[state] or finalTimers[state] then EndOpening(state) end
        end)
    end
    NS.Registry.QueueJob(state.settle)
    if NS.IsCombatLocked() then return end
    if not next(opening) and not next(finalTimers) then watcher:RegisterEvent("PLAYER_REGEN_DISABLED") end
    if not NativeArt.NeedsOpeningWatch(state) then
        local previous = finalTimers[state]
        if previous then previous:Cancel() end
        local timer
        timer = C_Timer.NewTimer(OPENING_SECONDS, function()
            if finalTimers[state] ~= timer then return end
            finalTimers[state] = nil
            EndOpening(state)
            if not NS.IsCombatLocked() and Safety.Read(state.frame, "IsVisible") == true then state.settle("3s") end
        end)
        finalTimers[state] = timer
        return
    end
    if finalTimers[state] then finalTimers[state]:Cancel() finalTimers[state] = nil end
    WatchOpening(state)
end

function Chrome.RecolorCaption(state)
    for _, key in ipairs(CELLS) do
        if state[key] then PaintCaption(state[key], true) end
    end
end

function Chrome.Fit(state)
    local fit, frame = state.fit, state.frame
    if fit.applying then return end
    local scale, current, x, y = fit.initialScale, fit.scale, fit.initialX, fit.initialY
    if scale then
        fit.initialScale, fit.initialX, fit.initialY = nil, nil, nil
    else
        scale, current, x, y = NS.WindowControlPolicy.FitGeometry(state)
        if not scale then return end
    end
    fit.applying = true
    if current ~= scale then frame:SetScale(scale) end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    fit.applying = nil
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
        local scale, current, x, y = NS.WindowControlPolicy.FitGeometry(state)
        if not scale then return false end
        state.fit = { points = points, scale = current, initialScale = scale, initialX = x, initialY = y }
    end
    return true
end

PlaceMinimize = function(button, state, close)
    local anchor = close and Safety.Read(close, "GetPoint", 1)
    if type(anchor) == "string" and anchor:find("TOP", 1, true) then
        button:SetPoint("RIGHT", close, "LEFT", -3, 0)
    else
        button:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", -36, -4)
    end
end

-- Blizzard's own size toggle (a MaximizeMinimizeButton frame), or nil.
function Chrome.NativeSizeToggle(frame, close)
    local header = Safety.Read(close, "GetParent")
    local toggle = NativeCaption(frame) or header ~= frame and NativeCaption(header) or nil
    if Safety.Public(toggle) and Safety.HasMethod(toggle, "HookScript")
        and Safety.Field(toggle, "MaximizeButton") and Safety.Field(toggle, "MinimizeButton") then
        return toggle
    end
end

-- Follow Blizzard's size buttons, and use our maximize cell on tabs
-- where Blizzard hides its toggle.
function Chrome.FollowSizeToggle(state, toggle)
    state.sizeToggle = toggle
    local function Relayout()
        local close = state.closeCell
        if close and Safety.Read(state.frame, "IsVisible") == true and Safety.Read(close, "IsVisible") == true
            and Safety.CanDecorate(close, not NS.IsCombatLocked()) then
            Chrome.ShowCaption(state, state.captionLevel)
        end
    end
    NS.WindowControlPolicy.ObserveCaptionToggle(state, toggle, Relayout)
end

-- Caption buttons share the parent of the grip: the map's border, whose
-- strata is above the map root.
function Chrome.CreateMinimize(state, close, level, click)
    local button = Safety.CreateChildFrame("Button", Chrome.Parent(state))
    Chrome.Control(button, "minimize", level)
    PlaceMinimize(button, state, close)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", click)
    return button
end

local function OnRestoreDragStart(bar)
    local taskbar = NS.SuiteCore().MinimizedWindows
    if not NS.IsCombatLocked() and not (taskbar and taskbar.IsDocked(bar)) then bar:StartMoving() end
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
    local taskbar = NS.SuiteCore().MinimizedWindows
    if taskbar then taskbar.Track(bar) end
    return bar
end

function Chrome.CreateCaption(state, level, click)
    if state.maximize or state.inventory and state.name ~= "BankFrame" then return end
    if not NS.WindowControlPolicy.CanFit(state) then state.closeOnly = true return end
    local parent = Chrome.Parent(state)
    local button = Safety.CreateChildFrame("Button", parent)
    state.maximize = button
    Chrome.Control(button, "maximize", level)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", click)
    return button
end
