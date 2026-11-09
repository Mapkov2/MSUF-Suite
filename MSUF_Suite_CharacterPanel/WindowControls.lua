local _, NS = ...
local Window = {}
NS.Window = Window

local MARGIN, MIN_SCALE, MAX_SCALE = 14, .65, 2
local MINIMIZED_WIDTH = 450
local min, max, abs = math.min, math.max, math.abs
local Number = NS.Number

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
    state.maximizeLabel:SetText(maximized and "−" or "+")
    state.maximize.tooltip = maximized and NS.Text("Restore window") or NS.Text("Maximize window")
    state.minimizeLabel:SetText(minimized and "+" or "−")
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

function Window.Dock(state, side)
    SetMaximized(state, false)
    state.dock = side
    if state.preferences then state.preferences.dock = side end
    Dock(state)
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
