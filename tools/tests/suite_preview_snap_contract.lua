-- Preview snapping (MSUF_Suite_Options/Menu/PreviewSnap.lua) and its kit hook
-- (MSUF_Suite/Core/PreviewKit.lua opts.snap): the Edit Mode edge rule, the
-- threshold, whole-unit offsets, Alt and the off switch, followers left out
-- of the targets, one-pixel guides on the pixel grid, and a commit that
-- stores the offset the drag drew.
local root = assert(arg[1], "Suite root required")
unpack = unpack or table.unpack

local cursorX, cursorY, altDown = 0, 0, false
GetCursorPosition = function() return cursorX, cursorY end
IsAltKeyDown = function() return altDown end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
GetCurrentKeyBoardFocus = function() return nil end
local PIXEL = 0.5
PixelUtil = { GetPixelToUIUnitFactor = function() return PIXEL end }

local function Noop() end
local Frame
Frame = function(parent, left, bottom, width, height, scale)
    local f = { parent = parent, points = {}, scripts = {}, shown = true, level = 1,
        left = left or 0, bottom = bottom or 0, width = width or 10, height = height or 10, scale = scale or 1 }
    function f:GetParent() return self.parent end
    function f:GetNumPoints() return #self.points end
    function f:GetPoint(index) return unpack(self.points[index]) end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:GetRect() return self.left, self.bottom, self.width, self.height end
    function f:GetEffectiveScale() return self.scale end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetWidth(value) self.width = value end
    function f:SetHeight(value) self.height = value end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(level) self.level = level end
    function f:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:GetScript(name) return self.scripts[name] end
    function f:CreateTexture() return Frame(self, 0, 0, 0, 0, self.scale) end
    return setmetatable(f, { __index = function(_, key)
        if key:match("^Set") or key:match("^Enable") or key:match("^Register") then return Noop end
    end })
end
CreateFrame = function(_, _, parent) return Frame(parent, parent and parent.left, parent and parent.bottom,
    parent and parent.width, parent and parent.height, parent and parent.scale) end

local states = {}
local P = { M = {}, T = { colors = { accent = { 1, 0.8, 0.4 } } },
    Suite = { Public = function() return true end,
        HostBridge = { GetPersistentMenuState = function(_, name)
            states[name] = states[name] or {}
            return states[name]
        end } } }
assert(loadfile(root .. "/MSUF_Suite_Options/Menu/PreviewSnap.lua"))("MSUF_Suite_Options", P)
local Snap = assert(P.PreviewSnap, "PreviewSnap.lua did not install P.PreviewSnap")
assert(Snap.Enabled() and states.MSUF_Suite_PreviewSnap.off == nil, "new previews should snap by default")

-- Targets: the drag's own region and everything it carries along stay out.
local plate = Frame(nil, 0, 0, 400, 200, 2)
local region = Frame(plate, 10, 10, 20, 10, 2)
local child = Frame(region, 12, 12, 4, 4, 2)
local anchored = Frame(plate, 40, 10, 10, 10, 2)
anchored:SetPoint("LEFT", region, "RIGHT", 2, 0)
local chained = Frame(plate, 60, 10, 10, 10, 2)
chained:SetPoint("LEFT", anchored, "RIGHT", 2, 0)
local other = Frame(plate, 100, 50, 40, 10, 2)
other:SetPoint("CENTER", plate, "CENTER", 0, 0)
local hidden = Frame(plate, 150, 50, 10, 10, 2)
hidden:Hide()
local outside = Frame(nil, 100, 50, 10, 10, 2)
local targets = Snap.Targets(region, { region, child, anchored, chained, other, hidden, outside }, plate)
assert(#targets == 1 and targets[1] == other, "snap targets must leave out the region, its followers, hidden and foreign regions")

-- Screen units: region 20..60 x 20..40, other 200..280 x 100..120.
local layer = Frame(nil, 0, 0, 800, 400, 1)
local snapper = Snap.New({ layer = layer, targets = function() return { other } end })
snapper:Begin(region)
local dx, dy = snapper:Apply(88.5, 0, 2)
assert(dx == 90 and dy == 0, "left edge did not snap to the target's left edge: " .. dx .. ", " .. dy)
local guide = snapper.guides[1]
assert(guide and guide:IsShown(), "a snap must show its guide")
local _, _, _, guideX = guide:GetPoint(1)
assert(guideX == 200 and guide.width == PIXEL, "guide must sit on the snapped edge, one physical pixel wide")
assert(not (snapper.guides[2] and snapper.guides[2]:IsShown()), "an axis that did not snap must show no guide")

dx = snapper:Apply(97, 0, 2)
assert(dx == 100, "center did not snap to the target's center: " .. dx)
dx = snapper:Apply(50.4, 0, 2)
assert(dx == 50 and not guide:IsShown(), "a move beyond the threshold must stay free, in whole units")
dx, dy = snapper:Apply(0, 39, 2)
assert(dx == 0 and dy == 40, "bottom edge did not snap to the target's bottom edge: " .. dy)

-- Pixel grid: a guide on a half pixel lands on the nearest whole pixel.
local fractional = Frame(plate, 100.1, 50, 40, 10, 2)
local grid = Snap.New({ layer = layer, targets = function() return { fractional } end })
grid:Begin(region)
grid:Apply(88.5, 0, 2)
local _, _, _, gridX = grid.guides[1]:GetPoint(1)
assert(gridX == 200, "guide was not placed on the pixel grid: " .. gridX)
local gridGuide = grid.guides[1]
local points, color = gridGuide.points, gridGuide.color
for _ = 1, 120 do grid:Apply(88.5, 0, 2) end
assert(gridGuide.points == points and gridGuide.color == color, "stationary drag rewrote guide geometry or styling")
grid.frame.left = 10
grid:Apply(88.5, 0, 2)
local _, _, _, shiftedX = gridGuide:GetPoint(1)
assert(shiftedX == 190, "a moved preview kept stale guide coordinates")
grid:End()

altDown = true
dx = snapper:Apply(88.5, 0, 2)
assert(dx == 89 and not guide:IsShown(), "Alt must place freely")
altDown = false
snapper:End()
assert(not guide:IsShown(), "End must hide the guides")

Snap.SetEnabled(false)
assert(not Snap.Enabled() and states.MSUF_Suite_PreviewSnap.off == true, "the switch must persist in the menu state")
snapper:Begin(region)
dx = snapper:Apply(88.5, 0, 2)
assert(dx == 89, "snapping stayed on after it was switched off")
Snap.SetEnabled(true)
assert(Snap.Enabled() and states.MSUF_Suite_PreviewSnap.off == nil, "the switch did not turn back on")

-- The kit draws the snapped offset and commits that same offset.
local NS = { IsSecret = function() return false end, Number = function(value) return type(value) == "number" end,
    InCombat = function() return false end }
C_Timer = { After = function(_, callback) callback() end }
assert(loadfile(root .. "/MSUF_Suite/Core/PreviewKit.lua"))("MSUF_Suite", NS)
local owner = Frame(nil, 0, 0, 800, 400, 1)
local host = NS.PreviewKit.NewHost(nil, { frame = owner, paint = Noop })
local kitSnapper = Snap.New({ layer = layer, targets = function() return { other } end })
local controller = NS.PreviewKit.Handles(host, { owner = owner, keys = false, manualDrag = true,
    pointerHeld = function() return true end,
    snap = function(_, x, y, scale) return kitSnapper:Apply(x, y, scale) end,
    drag = function(handle, phase)
        if phase == "start" then kitSnapper:Begin(handle) elseif phase ~= "press" then kitSnapper:End() end
    end })
local drawn, stored
controller:Add("region", region, function() return 5, 7 end,
    function(x, y) stored = { x, y } end, { follow = function(_, x, y) drawn = { x, y } end })
cursorX, cursorY = 0, 0
region.scripts.OnMouseDown(region, "LeftButton")
cursorX = 177
region.scripts.OnUpdate(region)
assert(drawn and drawn[1] == 90 and drawn[2] == 0, "the kit drew an unsnapped offset")
region.scripts.OnMouseUp(region, "LeftButton")
assert(stored and stored[1] == 95 and stored[2] == 7, "the commit must store the drawn, snapped offset")
assert(not kitSnapper.guides[1]:IsShown(), "the guides must hide when the drag ends")
print("preview snap contract ok")
