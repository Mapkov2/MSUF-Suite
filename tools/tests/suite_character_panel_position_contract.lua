local root = assert(arg[1])
local width, height, uiScale, originX, originY = 1600, 900, .8, 30, 20
UIParent = {
    GetRect = function() return originX, originY, width, height end,
    GetWidth = function() return width end,
    GetHeight = function() return height end,
    GetEffectiveScale = function() return uiScale end,
}
local ns = { Number = function(value) if type(value) == "number" then return value end end }
assert(loadfile(root .. "/MSUF_Suite_CharacterPanel/WindowControls.lua"))("MSUF_Suite_CharacterPanel", ns)
local Window = ns.Window
local PANEL_WIDTH, PANEL_HEIGHT, HEADER = 800, 480, 64

local Frame = {}
function Frame:SetPoint(point, parent, relativePoint, x, y)
    assert(parent == UIParent)
    self.point, self.relativePoint, self.x, self.y = point, relativePoint, x, y
end
function Frame:ClearAllPoints() self.point = nil end
function Frame:GetPoint() return self.point, UIParent, self.relativePoint, self.x, self.y end
function Frame:SetScale(scale) self.scale = scale end
function Frame:GetEffectiveScale() return self.scale * uiScale end
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = nil end

function Frame:TopLeft()
    local scaledWidth, scaledHeight = self.width * self.scale, self.height * self.scale
    if self.point == "CENTER" then return (width - scaledWidth) / 2, (height + scaledHeight) / 2 end
    local x, y = self.x * self.scale, self.y * self.scale
    if self.point == "TOPRIGHT" then return width + x - scaledWidth, height + y end
    if self.relativePoint == "TOPLEFT" then return x, height + y end
    assert(self.relativePoint == "BOTTOMLEFT")
    return x, y
end

function Frame:GetLeft()
    local x = self:TopLeft()
    return (originX + x) / self.scale
end

function Frame:GetTop()
    local _, y = self:TopLeft()
    return (originY + y) / self.scale
end

function Frame:DragTo(x, y)
    assert(self.moving)
    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / self.scale, y / self.scale)
end

local function New(preferences)
    local frame = setmetatable({ scale = 1, width = PANEL_WIDTH, height = PANEL_HEIGHT }, { __index = Frame })
    local state = Window.New(frame, PANEL_WIDTH, PANEL_HEIGHT, HEADER)
    Window.ApplyPreferences(state, preferences)
    return state, frame
end

local function CloseEnough(actual, expected)
    assert(math.abs(actual - expected) < 1e-6, tostring(actual) .. " ~= " .. tostring(expected))
end

local function Position(frame, expectedX, expectedY)
    local x, y = frame:TopLeft()
    CloseEnough(x, expectedX)
    CloseEnough(y, expectedY)
end

local preferences = { scale = 1.25 }
local state, frame = New(preferences)
assert(frame.point == "CENTER", "older profiles retain their default position")
Window.BeginMove(state)
frame:DragTo(376, 775)
Window.EndMove(state)
assert(preferences.freeX and preferences.freeY, "drag did not persist free position")
CloseEnough(preferences.freeX, 376 / width)
CloseEnough(preferences.freeY, 775 / height)

state, frame = New(preferences)
Position(frame, 376, 775)
Window.ToggleMaximized(state)
assert(frame.point == "CENTER")
Window.ToggleMaximized(state)
Position(frame, 376, 775)
Window.SetMinimized(state, true)
Position(frame, 376, 775)
Window.SetMinimized(state, false)
Position(frame, 376, 775)

width, height, uiScale = 1200, 800, 1.05
Window.Fit(state)
Position(frame, 200, 775 / 900 * height)
width, height, uiScale = 1600, 900, .8
Window.Fit(state)
Position(frame, 376, 775)

Window.Dock(state, "right")
state, frame = New(preferences)
assert(preferences.dock == "right" and frame.point == "TOPRIGHT")
Window.SetMinimized(state, true)
Window.BeginMove(state)
frame:DragTo(1000, 400)
Window.EndMove(state)
assert(preferences.dock == nil, "drag did not leave the dock")
Position(frame, 1000, 400)
Window.SetMinimized(state, false)
Position(frame, 600, 600)

Window.BeginMove(state)
frame:DragTo(110, 650)
local nextProfile = { freeX = .1, freeY = .8 }
Window.ApplyPreferences(state, nextProfile)
CloseEnough(preferences.freeX, 110 / width)
CloseEnough(preferences.freeY, 650 / height)
Position(frame, 160, 720)
assert(not frame.moving and not state.moving, "profile switch left the departing drag active")
Window.ApplyPreferences(state, { freeX = "bad", freeY = .2 })
assert(frame.point == "CENTER", "incomplete saved position replaced the default")
print("Character Panel position: reload, UI scale, clamping, docking, collapse, maximize, and profile change passed")
