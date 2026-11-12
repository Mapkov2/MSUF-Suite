local _, NS = ...
local Window = {}
NS.Window = Window

local MARGIN, MIN_SCALE, MAX_SCALE = 14, .65, 2
local HOST_GAP = 2
local MINIMIZED_WIDTH = 450
local min, max, abs = math.min, math.max, math.abs
local Number = NS.Number
-- The Suite core's caption painter (MSUF_Suite/Core/WindowCaption.lua).
local function Caption() return NS.Suite.WindowCaption end
-- Windows caption cells (close, maximize/restore, minimize), flush in the
-- header's top right corner under its accent rule.
local CELL_W, CELL_H = 30, 24
Window.CaptionCell = { width = CELL_W, height = CELL_H }

local function ScreenFit(state)
    local width, height = Number(UIParent:GetWidth()), Number(UIParent:GetHeight())
    if not width or not height or width <= MARGIN * 2 or height <= MARGIN * 2 then return 1 end
    return min(MAX_SCALE, (width - MARGIN * 2) / state.width, (height - MARGIN * 2) / state.height)
end

local function SetScale(state, scale)
    if state.scale ~= scale then
        state.scale = scale
        state.frame:SetScale(scale)
    end
end

local function Place(state, point, x, y, relativePoint)
    local frame = state.frame
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relativePoint or point, x, y)
end

local function Dock(state)
    local offset = MARGIN / state.scale
    if state.dock == "left" then Place(state, "TOPLEFT", offset, -offset)
    elseif state.dock == "right" then Place(state, "TOPRIGHT", -offset, -offset) end
end

local function PlaceFree(state)
    local width, height = Number(UIParent:GetWidth()), Number(UIParent:GetHeight())
    if not width or width <= 0 or not height or height <= 0 then return end
    local frameWidth = state.minimized and MINIMIZED_WIDTH or state.width
    local frameHeight = state.minimized and state.header or state.height
    local rightLimit = max(0, width - frameWidth * state.scale)
    local top = min(height, max(frameHeight * state.scale, state.freeY * height))
    local left = max(0, min(rightLimit, state.freeX * width))
    Place(state, "TOPLEFT", left / state.scale, top / state.scale, "BOTTOMLEFT")
    return true
end

local function SyncControls(state)
    if not state.grip then return end
    local minimized, maximized = state.minimized == true, state.maximized == true
    if minimized == state.captionMinimized and maximized == state.captionMaximized then return end
    state.captionMinimized, state.captionMaximized = minimized, maximized
    state.grip:SetShown(not minimized and not maximized)
    Caption().SetKind(state.maximize, maximized and "restore" or "maximize")
    state.maximize.tooltip = maximized and NS.Text("Restore window") or NS.Text("Maximize window")
    Caption().SetKind(state.minimize, minimized and "restore" or "minimize")
    state.minimize.tooltip = minimized and NS.Text("Restore window") or NS.Text("Minimize window")
end

function Window.New(frame, width, height, header)
    return { frame = frame, width = width, height = height, header = header, scale = 1, point = {} }
end

function Window.Fit(state)
    local fit = ScreenFit(state)
    local desired = state.maximized and fit or state.requestedScale or 1
    SetScale(state, max(min(MIN_SCALE, fit), min(desired, fit)))
    if state.maximized then Place(state, "CENTER", 0, 0)
    elseif state.dock then Dock(state)
    elseif state.freeX then PlaceFree(state) end
    SyncControls(state)
end

local function NativeRailGap(root, right, scale)
    if not NS.Host.Client.isForever then return 0 end
    -- The stock Forever rail is 64px wide, even before its geometry resolves.
    local rail = root.ModeTabs
    if not NS.Public(rail) or not rail then return 64 * scale end
    local railRight = Number(rail:GetRight())
    local railScale = Number(rail:GetEffectiveScale())
    if not railScale or railScale <= 0 then railScale = scale end
    if not right or not railRight then return (Number(rail:GetWidth()) or 64) * railScale end
    return max(0, railRight * railScale - right * scale)
end

function Window.HostNativeView(view)
    local frame, root, plan = view.frame, view.nativeRoot, view.nativeLayout
    frame:SetParent(root)
    frame:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    frame:SetFrameStrata(plan.strata)
    frame:SetFrameLevel((plan.rootLevel or 0) + plan.artLevel)
end

function Window.CreateChild(view, kind, parent)
    if not view.nativeLayout then return NS.Suite.CreateFrame(kind, nil, parent) end
    -- Forever's CreateFrame hook must not discover a native panel ancestor.
    local child = NS.Suite.CreateFrame(kind)
    child:SetParent(parent)
    return child
end

function Window.FitHosted(state, root)
    local parentScale, nativeScale = Number(UIParent:GetEffectiveScale()), Number(root:GetEffectiveScale())
    if not parentScale or parentScale <= 0 or not nativeScale or nativeScale <= 0 then return end
    local left, right, top = Number(root:GetLeft()), Number(root:GetRight()), Number(root:GetTop())
    local x, y, width = UIParent:GetRect()
    x, y, width = Number(x), Number(y), Number(width)
    local railGap = NativeRailGap(root, right, nativeScale) / parentScale
    local scale, onLeft = nativeScale / parentScale, false
    if left and right and top and x and y and width and width > 0 then
        local roomLeft = left * scale - x
        local roomRight = x + width - right * scale - railGap
        onLeft = roomRight < state.width * scale + HOST_GAP and roomLeft > roomRight
        local room = onLeft and roomLeft or roomRight
        local bottomRoom = top * scale - y
        scale = min(scale, max(1, room - HOST_GAP) / state.width, max(1, bottomRoom) / state.height)
    end
    SetScale(state, scale)
    local offset = (onLeft and -HOST_GAP or railGap + HOST_GAP) / scale
    if state.hostedLeft == onLeft and state.hostedOffset == offset then return end
    state.hostedLeft, state.hostedOffset = onLeft, offset
    local frame = state.frame
    frame:ClearAllPoints()
    if onLeft then frame:SetPoint("TOPRIGHT", root, "TOPLEFT", offset, 0)
    else frame:SetPoint("TOPLEFT", root, "TOPRIGHT", offset, 0) end
end

local function AddNativeSlots(plan, rows, size, x, y, stepX, stepY, alternateX)
    for i = 1, #rows do
        plan.slots[#plan.slots + 1] = {
            token = rows[i].token, x = x + (i - 1) * stepX, y = y + (i - 1) * stepY,
            size = size, alternateX = alternateX,
        }
    end
end

function Window.NativeLayout(gear, width, height, grid)
    -- The stock flyout uses HIGH, and Forever's native header reaches level 520.
    local plan = {
        width = width, height = height, strata = "HIGH", artLevel = 550,
        modelLevel = 570, slotLevel = 590, reportLevel = 610, closeLevel = 630,
        slots = {}, model = grid.model, close = grid.close,
    }
    local offset = (grid.slotHeight - grid.slotSize) / 2
    local span = (grid.weaponSpan - (#gear.weapons - 1) * grid.weaponGap) / max(1, #gear.weapons)
    AddNativeSlots(plan, gear.left, grid.slotSize, grid.left, grid.top + offset, 0, grid.slotStep)
    plan.rightFirst = #plan.slots + 1
    AddNativeSlots(plan, gear.right, grid.slotSize, grid.right, grid.top + offset, 0, grid.slotStep, grid.alternateRight)
    AddNativeSlots(plan, gear.weapons, grid.slotSize, grid.left, grid.weaponTop + offset, span + grid.weaponGap, 0)
    if NS.Host.Client.isForever then
        plan.slots[#plan.slots + 1] = {
            token = "AmmoSlot", x = grid.ammo.x, y = grid.ammo.y, size = grid.slotSize, optional = true,
        }
    end
    return plan
end

function Window.NativeLevel(view, offset)
    return view.frame:GetFrameLevel() + offset - view.nativeLayout.artLevel
end

-- The art keeps no mouse: Blizzard's X under it takes the click, and its
-- hover lights the art.
function Window.PlaceCloseArt(view, art)
    view.closeArt = art
    art:EnableMouse(false)
    art:SetFrameLevel(Window.NativeLevel(view, view.nativeLayout.closeLevel + 1))
    local native = view.nativeRoot and NS.Public(view.nativeRoot.CloseButton) and view.nativeRoot.CloseButton
    if not native or not native.HookScript then return end
    native:HookScript("OnEnter", function() Caption().SetHover(art, true) end)
    native:HookScript("OnLeave", function() Caption().SetHover(art, false) end)
end

function Window.ReportParent(view)
    if not view.nativeLayout then return view.body end
    local cover = NS.Suite.CreateFrame("Frame", nil, view.body)
    cover:SetAllPoints()
    cover:SetFrameLevel(Window.NativeLevel(view, view.nativeLayout.reportLevel))
    cover:EnableMouse(true)
    cover:EnableMouseWheel(true)
    cover:Hide()
    view.reportCover = cover
    return cover
end

function Window.ApplyNativeGearMode(view, rows, withModel, click, enter, leave)
    withModel = withModel == true
    if view.nativeGearModel == withModel then return end
    view.nativeGearModel = withModel
    local plan, plate = view.nativeLayout, view.plate
    local base = view.frame:GetFrameLevel()
    view.overviewPlateLevel = view.overviewPlateLevel or plate:GetFrameLevel() - base
    local level = withModel and view.overviewPlateLevel or plan.slotLevel - plan.artLevel - 3
    plate:SetFrameLevel(base + level)
    view.gearArtLevel = level + 1
    view.gearMask:SetShown(not withModel)

    local masks = view.nativeSlotMasks or {}
    view.nativeSlotMasks = masks
    for i = 1, #rows do
        local entry = plan.slots[plan.rightFirst + i - 1]
        local mask = masks[i]
        if not mask then
            mask = Window.CreateChild(view, "Button", view.gear)
            mask.view = view
            mask:SetFrameLevel(Window.NativeLevel(view, plan.slotLevel + 1))
            mask:EnableMouse(true)
            mask:RegisterForClicks("LeftButtonUp")
            masks[i] = mask
        end
        mask.slot = rows[i].slot
        mask:SetScript("OnClick", not withModel and click or nil)
        mask:SetScript("OnEnter", not withModel and enter or nil)
        mask:SetScript("OnLeave", not withModel and leave or nil)
        local x = withModel and entry.alternateX or entry.alternateX + entry.size
        mask:ClearAllPoints()
        mask:SetPoint("TOPLEFT", view.frame, "TOPLEFT", x, -entry.y)
        mask:SetSize(entry.x - entry.alternateX, entry.size)
    end
end

local function RememberPoint(state)
    local point = state.point
    point[1], point[2], point[3], point[4], point[5] = state.frame:GetPoint(1)
end

local function RestorePoint(state)
    local point = state.point
    state.frame:ClearAllPoints()
    if point[1] then state.frame:SetPoint(unpack(point, 1, 5))
    else state.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end

local function SetMaximized(state, value)
    if (state.maximized == true) == value then return end
    if value and not state.dock and not state.freeX then RememberPoint(state) end
    state.maximized = value
    Window.Fit(state)
    if not value and not state.dock and not state.freeX then RestorePoint(state) end
end

function Window.ToggleMaximized(state)
    SetMaximized(state, not state.maximized)
end

local function ScreenTopLeft(state)
    local frame = state.frame
    local parentX, parentY, width, height = UIParent:GetRect()
    local effective, parentScale = Number(frame:GetEffectiveScale()), Number(UIParent:GetEffectiveScale())
    local left, top = Number(frame:GetLeft()), Number(frame:GetTop())
    parentX, parentY = Number(parentX), Number(parentY)
    if not effective or effective <= 0 or not parentScale or parentScale <= 0 or not left or not top
        or not parentX or not parentY then return end
    local scale = effective / parentScale
    return left * scale - parentX, top * scale - parentY, Number(width), Number(height)
end

local function KeepTopLeft(state, x, y)
    if x and y then
        Place(state, "TOPLEFT", x / state.scale, y / state.scale, "BOTTOMLEFT")
    end
end

local function RememberFreePosition(state)
    local x, y, width, height = ScreenTopLeft(state)
    if not x or not width or width <= 0 or not height or height <= 0 then return end
    state.freeX, state.freeY = max(0, min(1, x / width)), max(0, min(1, y / height))
    if state.preferences then
        state.preferences.freeX, state.preferences.freeY = state.freeX, state.freeY
    end
end

function Window.SetMinimized(state, minimized)
    if (state.minimized == true) == minimized then return false end
    local x, y = ScreenTopLeft(state)
    state.minimized = minimized
    state.frame:SetSize(minimized and MINIMIZED_WIDTH or state.width, minimized and state.header or state.height)
    if not minimized and state.maximized then Place(state, "CENTER", 0, 0)
    elseif state.dock and not state.maximized then Dock(state)
    elseif minimized or not state.freeX or not PlaceFree(state) then KeepTopLeft(state, x, y) end
    SyncControls(state)
    return true
end

function Window.BeginMove(state)
    SetMaximized(state, false)
    state.moving = true
    state.dock = nil
    if state.preferences then state.preferences.dock = nil end
    state.frame:StartMoving()
end

function Window.EndMove(state)
    if not state.moving then return end
    state.moving = nil
    state.frame:StopMovingOrSizing()
    if not state.dock and not state.maximized then RememberFreePosition(state) end
end

local function EndResize(grip)
    local state = grip.window
    if not state.resizing then return end
    state.resizing = nil
    grip:SetScript("OnUpdate", nil)
    state.requestedScale = state.scale
    if state.preferences then state.preferences.scale = state.scale end
    if not state.dock and state.scale ~= state.startScale then RememberFreePosition(state) end
end

local function Resize(grip)
    if not IsMouseButtonDown("LeftButton") or NS.Host.InCombat() then EndResize(grip) return end
    local state = grip.window
    local x, y = GetCursorPosition()
    x, y = Number(x), Number(y)
    if not x or not y or x == state.cursorX and y == state.cursorY then return end
    state.cursorX, state.cursorY = x, y
    local vertical = (state.startY - y) / (state.parentScale * state.height)
    local delta = vertical
    if state.dock ~= "right" then
        local horizontal = (x - state.startX) / (state.parentScale * state.width)
        if abs(horizontal) > abs(vertical) then delta = horizontal end
    end
    local scale = max(state.minScale, min(state.startScale + delta, state.maxScale))
    if scale == state.scale then return end
    SetScale(state, scale)
    if state.dock then Dock(state) else KeepTopLeft(state, state.left, state.top) end
end

local function BeginResize(grip, button)
    local state = grip.window
    if button ~= "LeftButton" or state.minimized or state.maximized or state.resizing or NS.Host.InCombat() then return end
    local x, y = GetCursorPosition()
    x, y = Number(x), Number(y)
    local parentScale = Number(UIParent:GetEffectiveScale())
    local left, top = ScreenTopLeft(state)
    if not x or not y or not parentScale or parentScale <= 0 or not left then return end
    Window.EndMove(state)
    state.resizing, state.parentScale = true, parentScale
    state.left, state.top = left, top
    state.startX, state.startY, state.startScale = x, y, state.scale
    state.cursorX, state.cursorY = x, y
    state.maxScale = ScreenFit(state)
    state.minScale = min(MIN_SCALE, state.maxScale)
    grip:SetScript("OnUpdate", Resize)
end

function Window.BindGrip(state, grip)
    state.grip = grip
    grip.window = state
    grip:SetScript("OnMouseDown", BeginResize)
    grip:SetScript("OnMouseUp", EndResize)
    grip:SetScript("OnHide", EndResize)
end

function Window.BindTitleDrag(view, drag)
    if view.nativeLayout then
        view.window.nativeTitleDrag = drag
        local action = view.callbacks.windowAction
        if not action then return end
        drag:SetScript("OnDragStart", function() action("moveStart") end)
        drag:SetScript("OnDragStop", function() action("moveStop") end)
        drag:HookScript("OnHide", function() action("moveStop") end)
    else
        drag:SetScript("OnDragStart", function() Window.BeginMove(view.window) end)
        drag:SetScript("OnDragStop", function() Window.EndMove(view.window) end)
    end
end

local function BindNativeGrip(view, grip)
    view.window.nativeGrip = grip
    local action = view.callbacks.windowAction
    if not action then return end
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then action("scaleStart") end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then action("scaleStop") end
    end)
    grip:HookScript("OnHide", function() action("scaleStop") end)
end

function Window.CreateGrip(view, tooltip, paint)
    local state = view.window
    local grip = NS.Suite.CreateFrame("Button", nil, state.frame)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    tooltip(grip, NS.Text("Scale window"))
    for i = 1, 3 do
        local length, offset = i * 4, 3 + (3 - i) * 3
        local horizontal = NS.Suite.CreateTexture(grip, nil, "OVERLAY")
        horizontal:SetSize(length, 1)
        horizontal:SetPoint("BOTTOMRIGHT", -offset, offset)
        paint(horizontal)
        local vertical = NS.Suite.CreateTexture(grip, nil, "OVERLAY")
        vertical:SetSize(1, length)
        vertical:SetPoint("BOTTOMRIGHT", -offset, offset)
        paint(vertical)
    end
    if view.nativeLayout then BindNativeGrip(view, grip)
    elseif not view.embedded then Window.BindGrip(state, grip) end
end

Window.CaptionActions = {
    minimize = function(button) button.view:SetMinimized(not button.view:IsMinimized()) end,
    maximize = function(button)
        local view = button.view
        if view:IsMinimized() then
            view:SetMinimized(false)
            if view.window.maximized or not view.frame:IsShown() then return end
        end
        Window.ToggleMaximized(view.window)
    end,
}

local function NativeAction(button, action)
    local callback = button.view.callbacks.windowAction
    if callback then return callback(action) end
end

Window.NativeCaptionActions = {
    minimize = function(button)
        local minimized = NativeAction(button, "minimize")
        if type(minimized) ~= "boolean" then return end
        Caption().SetKind(button, minimized and "restore" or "minimize")
        button.tooltip = NS.Text(minimized and "Restore window" or "Minimize window")
    end,
    maximize = function(button)
        local maximized = NativeAction(button, "maximize")
        if type(maximized) ~= "boolean" then return end
        Caption().SetKind(button, maximized and "restore" or "maximize")
        button.tooltip = NS.Text(maximized and "Restore window" or "Maximize window")
    end,
}

-- Right to left: close, maximize, minimize. text and base are the view's
-- palette colours for the glyphs and for the header under the hosted close
-- art, which covers Blizzard's own X (that X keeps the click).
local CAPTION = { { "close", "Close" }, { "maximize", "Maximize window" }, { "minimize", "Minimize window" } }

function Window.CreateCaption(view, header, close, tooltip, text, base)
    local window = view.window
    local actions = view.nativeLayout and Window.NativeCaptionActions or Window.CaptionActions
    local function Color(role)
        local color = role == "base" and base or text
        color = view.palette[color] or color
        return color[1], color[2], color[3], color[4] or 1
    end
    local cells = {}
    for index, entry in ipairs(CAPTION) do
        local cell = Window.CreateChild(view, "Button", header)
        cell.view = view
        cell:SetSize(CELL_W, CELL_H)
        cell:SetPoint("TOPRIGHT", header, "TOPRIGHT", (1 - index) * CELL_W, -1)
        Caption().Dress(cell, entry[1], Color, index == 1 and view.nativeLayout ~= nil)
        local action = index == 1 and close or actions[entry[1]]
        if action and not view.embedded then cell:SetScript("OnClick", action) end
        tooltip(cell, NS.Text(entry[2]))
        cells[index] = cell
    end
    window.captionCells, window.maximize, window.minimize = cells, cells[2], cells[3]
    if view.nativeLayout then Window.PlaceCloseArt(view, cells[1]) end
end

function Window.PaintCaption(window)
    for _, cell in ipairs(window.captionCells or {}) do Caption().Paint(cell) end
end

function Window.CancelGestures(state)
    Window.EndMove(state)
    if state.grip then EndResize(state.grip) end
end

function Window.ApplyPreferences(state, preferences)
    if preferences == state.preferences then return end
    Window.CancelGestures(state)
    state.preferences = preferences
    local dock = preferences and preferences.dock
    state.dock = (dock == "left" or dock == "right") and dock or nil
    state.maximized = nil
    state.requestedScale = preferences and Number(preferences.scale)
    local x, y = preferences and Number(preferences.freeX), preferences and Number(preferences.freeY)
    state.freeX, state.freeY = nil, nil
    if x and y then state.freeX, state.freeY = max(0, min(1, x)), max(0, min(1, y)) end
    if not state.dock and not state.freeX then Place(state, "CENTER", 0, 0) end
    Window.Fit(state)
end
