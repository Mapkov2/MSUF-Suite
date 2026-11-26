-- Repeated opening, positioning and recoloring from Perfy #38. Count native
-- writes on glyph bars independently from the caption's background and fill.
local root = assert(arg[1], "Suite root required")
local secret, mode, factor = {}, "windows", 1
issecretvalue = function(value, ...)
    assert(select("#", ...) == 0)
    return rawequal(secret, value)
end
local ns = { Suite = {}, Skin = { GetWindowCaptionMode = function() return mode end } }
PixelUtil = { GetPixelToUIUnitFactor = function() return factor end }
local caption = assert(loadfile(root .. "/MSUF_Suite/Core/WindowCaption.lua"))("Suite", ns)
local geometry, paint = 0, 0
local texture = {}
local function Noop() end
texture.SetAllPoints, texture.SetSnapToPixelGrid, texture.SetTexelSnappingBias = Noop, Noop, Noop
function texture:ClearAllPoints() geometry = geometry + 1; self.owner = nil end
function texture:SetPoint(_, owner, _, x, y)
    geometry = geometry + 1
    self.owner, self.x, self.y = owner, x, y
end
function texture:SetSize(w, h) geometry = geometry + 1; self.w, self.h = w, h end
function texture:Show() geometry = geometry + 1; self.shown = true end
function texture:Hide() geometry = geometry + 1; self.shown = false end
function texture:SetColorTexture(r, g, b, a)
    if self.glyph then paint = paint + 1 end
    self.r, self.g, self.b, self.a = r, g, b, a
end
local function Cell()
    return {
        scripts = {}, width = 20, height = 20, scale = 1, left = 0, top = 20,
        CreateTexture = function(_, _, layer) return setmetatable({ glyph = layer == "OVERLAY" }, { __index = texture }) end,
        GetWidth = function(self) return self.width end, GetHeight = function(self) return self.height end,
        GetLeft = function(self) return self.left end, GetTop = function(self) return self.top end,
        GetEffectiveScale = function(self) return self.scale end,
        SetScript = function(self, name, callback) self.scripts[name] = callback end,
    }
end
local r, g, b, a = .3, .4, .5, 1
local function Colors(role)
    if role == "base" then return .12, .15, .18, 1 end
    return r, g, b, a
end
local cell = caption.Dress(Cell(), "close", Colors, true)
local bars = cell.caption.bars
assert(#bars == 16 and bars[1].x == 6 and bars[1].w == 1 and bars[1].r == r)
geometry, paint = 0, 0
local instructions = 0
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for i = 1, 50 do caption.SetKind(cell, "close") end
debug.sethook()
print(("50 equal close layouts: %d native geometry, %d glyph color writes, ~%d Lua instructions")
    :format(geometry, paint, instructions))
assert(geometry == 0 and paint == 0, "repeated equal owned caption performed native writes")

-- Subpixel position changes affect alignment, whole-pixel movement does not.
cell.left, cell.top = .25, 20.25
caption.SetKind(cell, "close")
assert(geometry > 0 and bars[1].x == 5.75 and bars[1].y == -6.25 and paint == 0)
geometry = 0
cell.left, cell.top = 12.25, 100.25
caption.SetKind(cell, "close")
assert(geometry == 0)
cell.left, cell.top = nil, nil
caption.SetKind(cell, "close")
assert(bars[1].x == 6 and bars[1].y == -6)
cell.scale = 2
caption.SetKind(cell, "close")
assert(#bars == 32 and bars[1].w == .5 and paint == 16 and bars[32].g == g)
cell.scale = 1
caption.SetKind(cell, "minimize")
assert(bars[1].shown and not bars[2].shown and not bars[32].shown)
mode = "plusMinus"
caption.SetKind(cell, "maximize")
assert(bars[2].shown and not bars[3].shown)
cell.width, cell.height = 30, 30
cell.scripts.OnSizeChanged(cell)
assert(bars[1].w == 12)
mode = "chevrons"
caption.Paint(cell)
assert(bars[3].shown and bars[1].w == 1)

-- Hover, down, hide, reopen and a live theme change use the current colors.
caption.SetKind(cell, "close")
cell.scripts.OnEnter(cell)
assert(bars[1].r == 1 and cell.caption.fill.a == .9)
cell.scripts.OnMouseDown(cell)
assert(cell.caption.fill.a == 1)
cell.scripts.OnHide(cell)
assert(bars[1].r == r and cell.caption.fill.a == 0)
r, a = .65, 0
caption.Paint(cell)
assert(bars[1].r == .65 and bars[1].a == 0)
a = nil
caption.Paint(cell)
assert(bars[1].a == 1 and cell.caption.base.r == .12)

-- A public caller's plain array and native art may have been changed since the
-- previous layout. Its next call still repairs geometry, visibility and color.
local external, other = {}, Cell()
caption.Layout(other, "maximize", external, "windows")
external[1].x, external[1].shown = -99, false
caption.Layout(other, "maximize", external, "windows")
assert(external[1].x == 6 and external[1].shown)
caption.PaintGlyph(external, .2, .3, .4, .5)
external[1]:SetColorTexture(1, 1, 1, 1)
caption.PaintGlyph(external, .2, .3, .4, .5)
assert(external[1].r == .2 and external[1].a == .5)
caption.Layout(other, "close", bars, "windows")
assert(bars[1].owner == other)
caption.SetKind(cell, "close")
assert(bars[1].owner == cell)

-- Never compare or store secret components. Native textures may receive them.
-- A temporarily inaccessible layout is retried on the next readable paint.
r = secret
caption.Paint(cell)
assert(rawequal(bars[1].r, secret))
r = .65
caption.Paint(cell)
assert(bars[1].r == .65)
geometry = 0
cell.width = secret
caption.SetKind(cell, "maximize")
assert(geometry == 0)
cell.width = 40
caption.Paint(cell)
assert(geometry > 0 and bars[1].w == 1)
mode = secret
geometry = 0
caption.Paint(cell)
assert(geometry == 0)
mode = "windows"
caption.Paint(cell)
assert(bars[1].w == 12)
-- Four differently sized windows can request the same glyph in one frame.
-- The textures and their pixel geometry remain individual to each window.
local sizes = { 20, 24, 32, 40 }
local alternate, alternatingBars = Cell(), {}
local function FourSizes()
    for _, size in ipairs(sizes) do
        alternate.width, alternate.height = size, size
        local n = math.floor(size * .4 + .5)
        local active = caption.Layout(alternate, "close", alternatingBars, "windows")
        assert(active == 2 * (n - math.max(1, math.floor(n / 12 + .5)) + 1))
        assert(alternatingBars[1].x == math.floor((size - n) / 2))
    end
end
FourSizes()
collectgarbage("collect")
collectgarbage("stop")
local heap = collectgarbage("count")
for i = 1, 100 do FourSizes() end
local allocated = (collectgarbage("count") - heap) * 1024
collectgarbage("restart")
print(("400 alternating glyph layouts: %.0f bytes"):format(allocated))
assert(allocated < 8192, "alternating pixel sizes rebuilt glyph rectangles")
print("Owned caption geometry, colors, access boundaries and native repairs passed")
