local root = assert(arg[1])
local secret = {}
issecretvalue = function(value) return value == secret end
local ns = { Suite = {} }
assert(loadfile(root .. "/MSUF_Suite/Appearance/Safety.lua"))("Suite", ns)
local S = ns.Safety
local calls, denied = 0, false
local target = {
    IsForbidden = function() return denied end,
    Get = function(self, first, second)
        assert(self and second == "second")
        calls = calls + 1
        return first, second
    end,
}
local function One(expected, ...)
    assert(select("#", ...) == 1 and (...) == expected)
end
One(false, S.Read(target, "Get", false, "second"))
One(nil, S.Read(target, "Get", secret, "second"))
One(nil, S.Read(target, "Get", nil, "second"))
assert(select("#", S.Call(target, "Get", nil, "second")) == 2)
denied = true
One(nil, S.Read(target, "Get", true, "second"))
denied = secret
One(nil, S.Read(target, "Get", true, "second"))
assert(calls == 4)
One(nil, S.Read(false, "Get"))
denied = false
target.Get = nil
One(nil, S.Read(target, "Get"))
target.Get = function() end
One(nil, S.Read(target, "Get"))

PixelUtil = { GetPixelToUIUnitFactor = function() return 1 end }
local caption = assert(loadfile(root .. "/MSUF_Suite/Core/WindowCaption.lua"))("Suite", ns)
local function Ignore() end
local bar = {
    SetSnapToPixelGrid = Ignore, SetTexelSnappingBias = Ignore,
    ClearAllPoints = Ignore, Show = Ignore, Hide = Ignore,
    SetPoint = function(self, _, owner, _, x, y) self.owner, self.x, self.y = owner, x, y end,
    SetSize = function(self, w, h) self.w, self.h = w, h end,
}
local meta = { __index = bar }
local function Button(scale, left)
    return {
        scale = scale, left = left, size = 20,
        GetWidth = function(self) return self.size end, GetHeight = function(self) return self.size end,
        GetEffectiveScale = function(self) return self.scale end,
        GetLeft = function(self) return self.left end, GetTop = function() return 20 end,
        CreateTexture = function() return setmetatable({}, meta) end,
    }
end
local a, b, bars, other = Button(1, 0), Button(1, .25), {}, {}
assert(caption.Layout(a, "close", bars, "windows") == 16)
assert(caption.Layout(b, "close", other, "plusMinus") == 16)
assert(bars[1].owner == a and other[1].owner == b and bars[1].x == 6 and other[1].x == 5.75)
assert(caption.Layout(a, "maximize", bars, "windows") == 4 and bars[1].w == 8)
assert(caption.Layout(a, "restore", bars, "windows") == 8 and bars[1].w == 6)
assert(caption.Layout(a, "maximize", bars, "plusMinus") == 2)
assert(caption.Layout(a, "minimize", bars, "plusMinus") == 1)
assert(caption.Layout(a, "maximize", bars, "chevrons") == 7)
a.scale = 2
assert(caption.Layout(a, "close", bars, "windows") == 32 and bars[1].w == .5)
a.size = 40
assert(caption.Layout(a, "close", bars, "windows") == 60 and bars[1].w == 1.5)
a.scale, a.size = 1, 20
assert(caption.Layout(a, "close", bars, "windows") == 16 and bars[1].w == 1)

collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for i = 1, 400 do caption.Layout(a, "close", bars, "windows") end
local growth = collectgarbage("count") - before
collectgarbage("restart")
print(("400 warmed close-glyph layouts: %.2f KiB heap growth"):format(growth))
assert(growth < 16, "repeated equal glyph patterns allocated fresh rectangles")
