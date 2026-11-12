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
    local bounds = state.suiteBounds
    if bounds then
        local width, height = Safety.Read(state.frame, "GetWidth"), Safety.Read(state.frame, "GetHeight")
        return math.max(0, bounds.width - (width or bounds.width)), math.max(0, bounds.height - (height or bounds.height)), 0
    end
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
local function PaintCaption(button)
    local art = captionArt[button]
    local active = not art.disabled and (art.hover or art.down)
    local r, g, b, a = NS.Theme.GetColor(art.disabled and "disabled" or "text")
    -- Windows' close cell turns red under the pointer, its cross white.
    if art.kind == "close" and active then r, g, b, a = 1, 1, 1, 1 end
    for _, texture in ipairs(art.bars) do texture:SetColorTexture(r, g, b, a) end
    if art.kind == "close" then
        local dr, dg, db = NS.Theme.GetColor("danger")
        art.fill:SetColorTexture(dr, dg, db, active and (art.down and 1 or 0.85) or 0)
    else
        art.fill:SetColorTexture(1, 1, 1, active and (art.down and 0.17 or 0.10) or 0)
    end
end

-- Glyph bars sit on whole screen pixels (the Suite's shared caption layout).
local function LayoutCaption(button, kind)
    local art = captionArt[button]
    art.kind = kind
    NS.SuiteCore().WindowCaption.Layout(button, kind, art.bars)
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
        if child ~= state.close and child ~= state.minimize and child ~= state.maximize
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
    local obstacle = CaptionObstacle(state, scale, cellLeft, low, closeTop, Safety.Call(frame, "GetChildren"))
    local closeParent = Safety.Read(close, "GetParent")
    if closeParent and closeParent ~= frame then
        obstacle = math.max(obstacle, CaptionObstacle(state, scale, cellLeft, low, closeTop, Safety.Call(closeParent, "GetChildren")))
    end
    state.captionX, state.captionY = closeRight - right, closeTop - top
    local room = cellLeft - math.max(left + 54, TitleRight(frame, scale) + 6, obstacle)
    return width, height, room, right - cellLeft + width * 2 + 4
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

-- Drawn cells over Blizzard's own buttons have no mouse of their own: the
-- native button's hover and press paint them.
local drivers = setmetatable({}, { __mode = "k" })
local cellStates = setmetatable({}, { __mode = "k" })
local function DriveEnter(button)
    local cell = drivers[button]
    if not cell then return end
    CaptionEnter(cell)
    -- Blizzard's button shows again under its cell and the pointer: the
    -- caption fades it.
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
    captionArt[cell] = { fill = fill, bars = {} }
    cellStates[cell] = state
    state[key] = cell
    return cell
end

-- Blizzard's caption buttons under our cells fade, the button and every art
-- region of it (a size toggle: both of its buttons too), so an alpha written to
-- the button later, or an animation of it, still finds no art. While faded, a
-- hook puts 0 back on any alpha write. The alphas they had come back with the
-- caption's end. The window's focus outline leaves faded buttons out.
local faded = setmetatable({}, { __mode = "k" })
local alphaHooked = setmetatable({}, { __mode = "k" })
local RefreshFocus = function() end
function Chrome.SetFocusRefresh(callback) RefreshFocus = callback end
function Chrome.IsFaded(region) return faded[region] ~= nil end

-- Alpha is no protected action: a faded part stays faded in combat too.
local function KeepFaded(region, alpha)
    if faded[region] and alpha ~= 0 and not Safety.IsForbidden(region) then region:SetAlpha(0) end
end

-- The old action skin (box and glyph) leaves Blizzard's buttons while our
-- cells stand for them, so nothing of it can show through.
local function Yield(target, yield)
    NS.WindowActionSkin.Yield(target, yield)
    for _, key in ipairs({ "MaximizeButton", "MinimizeButton" }) do
        local child = Safety.Field(target, key)
        if child then NS.WindowActionSkin.Yield(child, yield) end
    end
end

-- target, its art regions, and a size toggle's buttons with theirs.
local function NativeParts(target)
    local parts = { target, Safety.Call(target, "GetRegions") }
    for _, key in ipairs({ "MaximizeButton", "MinimizeButton" }) do
        local button = Safety.Field(target, key)
        if Safety.Public(button) and button then
            parts[#parts + 1] = button
            for _, region in ipairs({ Safety.Call(button, "GetRegions") }) do parts[#parts + 1] = region end
        end
    end
    return parts
end

local function Fade(state, region)
    if not Safety.Public(region) or not Safety.HasMethod(region, "SetAlpha") then return end
    if state.nativeAlpha[region] == nil then state.nativeAlpha[region] = region:GetAlpha() end
    if not alphaHooked[region] then
        alphaHooked[region] = true
        hooksecurefunc(region, "SetAlpha", KeepFaded)
    end
    faded[region] = state
    region:SetAlpha(0)
end

-- Alpha only, so combat too; the old action skin lets go outside combat.
local function FadeNative(state, target)
    if type(target) ~= "table" or Safety.IsForbidden(target) then return false end
    if Safety.CanDecorate(target, not NS.IsCombatLocked()) then Yield(target, true) end
    state.nativeAlpha = state.nativeAlpha or setmetatable({}, { __mode = "k" })
    state.nativeRoots = state.nativeRoots or setmetatable({}, { __mode = "k" })
    state.nativeRoots[target] = true
    for _, region in ipairs(NativeParts(target)) do Fade(state, region) end
    return true
end

-- Blizzard's top right corner art holds a socket for each native caption
-- button: it fades with them, on the window and on panes laid over it.
local function FadeSockets(state)
    local frame = state.frame
    local right, top = Safety.Read(frame, "GetRight"), Safety.Read(frame, "GetTop")
    if not right or not top then return end
    for _, owner in ipairs({ frame, Safety.Call(frame, "GetChildren") }) do
        local corner = Safety.Field(Safety.Field(owner, "NineSlice"), "TopRightCorner")
        local cornerRight, cornerTop = Safety.Read(owner, "GetRight"), Safety.Read(owner, "GetTop")
        if corner and cornerRight and cornerTop and math.abs(cornerRight - right) < 6 and math.abs(cornerTop - top) < 6
            and Safety.Read(owner, "IsShown") then
            FadeNative(state, corner)
        end
    end
end

local function RestoreNative(state, target)
    if not state.nativeRoots or not state.nativeRoots[target]
        or not Safety.CanDecorate(target, not NS.IsCombatLocked()) then return end
    state.nativeRoots[target] = nil
    state.restores = (state.restores or 0) + 1
    Yield(target, false)
    for _, region in ipairs(NativeParts(target)) do
        local alpha = state.nativeAlpha[region]
        if alpha ~= nil then
            if faded[region] == state then faded[region] = nil end
            region:SetAlpha(alpha)
            state.nativeAlpha[region] = nil
        end
    end
end

-- Field report: one chat line per window when Blizzard's X or size toggle
-- shows under our cells, before the caption fades it again.
local function Report(state, moment)
    local close, cell = state.close, state.closeCell
    if state.reported or not cell or not cell:IsShown() then return end
    local native = Safety.Read(close, "GetAlpha") == 0 and state.sizeToggle or close
    local alpha = Safety.Read(native, "GetAlpha")
    if not alpha or alpha == 0 or not Safety.Read(native, "IsShown") then return end
    state.reported = true
    NS.Print(("caption check: %s %s, %s alpha %.2f, faded %s, owned %s, path %s, restores %d"):format(state.name,
        tostring(moment or "next frame"), native == close and "X" or "toggle", alpha, tostring(faded[native] ~= nil),
        tostring(state.nativeRoots and state.nativeRoots[native] == true), tostring(state.captionPath), state.restores or 0))
end

local CELLS = { "closeCell", "toggleCell", "maximize", "minimize" }
function Chrome.HideCaption(state)
    for _, key in ipairs(CELLS) do
        if state[key] then state[key]:Hide() end
    end
    for target in pairs(state.nativeRoots or {}) do RestoreNative(state, target) end
    RefreshFocus(state.frame)
end

-- The glyph is laid out on the cell's final place (whole screen pixels).
local function PlaceCell(cell, anchor, width, height, level, kind)
    cell:SetSize(width, height)
    cell:SetFrameLevel(level)
    if anchor then
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
    end
    LayoutCaption(cell, kind)
    cell:Show()
    return cell
end

-- Blizzard's size toggle shows its maximize or its restore button.
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

function Chrome.ShowCaption(state, level)
    Chrome.SyncMinimize(state)
    local width, height, room, inset = Chrome.CaptionSize(state)
    local gamepad = NS.Client.IsGamepadUI()
    if state.fit and (not width or gamepad) then
        Chrome.LeaveFit(state)
        width, height, room, inset = Chrome.CaptionSize(state)
    end
    local cells = width and not gamepad and FadeNative(state, state.close)
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
    if not cells then
        state.captionPath = not width and "size" or gamepad and "gamepad" or "protected"
        Chrome.HideCaption(state)
        local minimize = state.minimize
        if not minimize or gamepad or room ~= nil then return end
        minimize:ClearAllPoints()
        PlaceMinimize(minimize, state, state.close)
        return PlaceCell(minimize, nil, 22, 22, level, "minimize")
    end
    state.captionInset, state.captionPath = inset, "cells"
    -- Above Blizzard's own caption buttons, whatever pane raised them.
    for _, native in ipairs({ state.close, state.sizeToggle }) do
        local nativeLevel = Safety.Read(native, "GetFrameLevel")
        if type(nativeLevel) == "number" and nativeLevel + 2 > level then level = nativeLevel + 2 end
    end
    local toggle = state.sizeToggle and Safety.Read(state.sizeToggle, "IsShown")
    -- A tight title shrinks all cells alike before one of them gives way.
    local cells = ((state.maximize or toggle) and 1 or 0) + (state.minimize and 1 or 0)
    if cells > 0 and room < width * cells then width = math.max(18, math.floor(room / cells)) end
    local close = DrawnCell(state, "closeCell")
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", state.frame, "TOPRIGHT", state.captionX, state.captionY)
    PlaceCell(close, nil, width, height, level, "close")
    Drive(state.close, close)
    FadeSockets(state)
    RefreshFocus(state.frame)
    local middle = state.sizeToggle and ToggleCell(state, close, width, height, level)
    local maximize, minimize = state.maximize, state.minimize
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
        minimize:Hide()
    end
end

-- Windows finish their layout after OnShow (Guild sizes itself from its
-- display mode): the caption is laid out again on the next frame, and once
-- more three seconds later. Guild, the AddOn list and Settings show Blizzard's
-- caption buttons again while they open: until then, every frame looks at
-- them under shown cells, and the caption fades them at once. Combat, or the
-- window closing, ends the look; no update runs without an opening window.
local OPENING_SECONDS = 3
local opening = {}
local watcher = CreateFrame("Frame")
watcher:Hide()

local function EndOpening(state)
    opening[state] = nil
    if next(opening) == nil then watcher:SetScript("OnUpdate", nil) watcher:Hide() end
end

local function NativeShown(state)
    if (Safety.Read(state.close, "GetAlpha") or 0) ~= 0 then return true end
    for target in pairs(state.nativeRoots or {}) do
        if (Safety.Read(target, "GetAlpha") or 0) ~= 0 then return true end
    end
    return false
end

local function Watch(_, elapsed)
    local combat = NS.IsCombatLocked()
    for state, age in pairs(opening) do
        age = age + (elapsed or 0)
        opening[state] = age
        local cell = state.closeCell
        if combat or age >= OPENING_SECONDS then
            EndOpening(state)
            if not combat then state.settle(OPENING_SECONDS .. "s") end
        elseif cell and cell:IsVisible() and NativeShown(state) then
            state.settle(("%.2fs"):format(age))
        end
    end
end

function Chrome.Settle(state, level, allowed)
    state.settleLevel, state.settleAllowed = level, allowed
    state.settle = state.settle or function(moment)
        if not state.settleAllowed(state) then return end
        Report(state, moment)
        Chrome.ShowCaption(state, state.settleLevel)
    end
    NS.Registry.QueueJob(state.settle)
    if NS.IsCombatLocked() or Safety.Read(state.frame, "IsVisible") ~= true then return end
    if not state.watchHooked then
        state.watchHooked = true
        state.frame:HookScript("OnHide", function() EndOpening(state) end)
    end
    opening[state] = 0
    watcher:SetScript("OnUpdate", Watch)
    watcher:Show()
end

function Chrome.RecolorCaption(state)
    for _, key in ipairs(CELLS) do
        if state[key] then PaintCaption(state[key]) end
    end
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

-- Blizzard shows the toggle's other button after a size change and hides
-- the toggle on tabs without a small layout (our maximize stands in): the
-- caption follows.
function Chrome.FollowSizeToggle(state, toggle)
    state.sizeToggle = toggle
    local function Relayout()
        local close = state.closeCell
        if close and close:IsShown() and Safety.CanDecorate(close, not NS.IsCombatLocked()) then
            Chrome.ShowCaption(state, state.captionLevel)
        end
    end
    toggle:HookScript("OnShow", Relayout)
    toggle:HookScript("OnHide", Relayout)
    for _, key in ipairs({ "MaximizeButton", "MinimizeButton" }) do
        local button = Safety.Field(toggle, key)
        if Safety.HasMethod(button, "HookScript") then button:HookScript("OnShow", Relayout) end
    end
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
    if state.maximize or state.inventory then return end
    local parent = Chrome.Parent(state)
    local button = Safety.CreateChildFrame("Button", parent)
    state.maximize = button
    Chrome.Control(button, "maximize", level)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", click)
    return button
end
