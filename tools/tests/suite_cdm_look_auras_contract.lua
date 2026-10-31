local root = assert(arg[1], "repository root required")
-- Cooldown manager looks inside Blizzard's aura buttons (package cdm11-B):
-- Pixel and Autocast glows built with the button in initializeFrame and
-- bound to its loops (AuraGlows.NewGlow), only where the container's region
-- set asks for them; the swipe colors of buff icons and of the active buff
-- over a cooldown icon; the spark of buff bars on the sealed bar's fill; the
-- countdown's tenths in the duration text binding. Runs on the aura layer
-- contract's harness (sealed-button fakes) up to its glow style checks.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_auras_contract.lua", [=[
-- The harness's checks from its stack text colors on sit in one block inside
-- Features() (the main chunk is near the local limit): both end after these
-- checks, which run with the harness's helpers when Features() is called.
end
do (function()
-- The client's Translation animation and its offset.
local create = Methods.CreateAnimation
function Methods:CreateAnimation(kind)
    if kind ~= "Translation" then return create(self, kind) end
    assert(R[self].kind == "AnimationGroup", "animations live in groups")
    return New(kind, self)
end
Methods.SetOffset = Record("SetOffset")
local K = C.Const
local function LineGroups(root)
    return Find(root, function(obj, s) return s.kind == "AnimationGroup" and Child(obj, "Translation") ~= nil end)
end
-- Textures riding a band's mover (a frame that owns a line loop).
local function LineTextures(root, shown)
    return Find(root, function(_, s)
        if s.kind ~= "Texture" or (shown and not s.shown) then return false end
        local group = Child(s.parent, "AnimationGroup")
        return group ~= nil and Child(group, "Translation") ~= nil
    end)
end
local function Frames(root) return #Find(root, function(_, s) return s.kind == "Frame" end) end
-- The glow while active (not the pandemic window's): its flipbook and the
-- holder of its lines (the frame beside its edges that holds the bands).
local function Flip(button) return AuraGlow(button).flip end
local function Holder(button)
    local frame = R[Flip(button)].parent
    for obj, s in pairs(R) do
        if s.parent == frame and s.kind == "Frame" and s.kids then
            for _, kid in ipairs(s.kids) do
                if R[kid].calls.SetClipsChildren then return obj end
            end
        end
    end
end

-- Pixel on a buff icon bar: the lines are built with the button and play
-- with it (AddAuraShownAnimation), next to the glow's own two loops.
C.views.c5 = View("c5", 2)
local v = C.views.c5
v.glowStyle, v.auraGlow = 5, true
local a1 = Aura("c5", "a5201", "a", "player", Set(5201))
local a2 = Aura("c5", "a5202", "a", "player", Set(5202))
Plan("c5", 2, { a1, a2 })
A.Sync("c5")
local c = Live("c5", "player")
local button = Acquired(c, "g1")
local groups = LineGroups(button)
assert(#groups == 4, "four line loops per glow, got " .. #groups)
assert(R[button].bind.shownAnims == 6, "the glow's two loops and the lines' four play with the button")
for _, group in ipairs(groups) do
    assert(Args(group, "SetLooping")[1] == "REPEAT" and R[group].playing, "a looping line group")
    local slide = Child(group, "Translation")
    assert(Args(slide, "SetOffset") and Args(slide, "SetDuration")[1] == K.GLOW[5].lap / 8, "shift and lap")
end
local lit = LineTextures(button, true)
assert(#lit >= 8, "the lines are painted: " .. #lit)
for _, tex in ipairs(lit) do
    local color = Args(tex, "SetColorTexture")
    assert(color[1] == 1 and math.abs(color[2] - .82) < 1e-9 and color[3] == 0 and Args(tex, "SetBlendMode")[1] == "BLEND",
        "gold pixel lines")
end
assert(not R[Flip(button)].shown and R[Holder(button)].shown, "the lines show, the alert's art stays hidden")
-- An unchanged sync makes and writes nothing.
local made, writes = tally.made, tally.writes
A.Sync("c5")
assert(tally.made == made, "an unchanged sync makes nothing")
-- More lines: the textures are reused and only the missing ones made.
local frames, before = Frames(button), #LineTextures(button)
v.glowLines, v.relook = 14, (v.relook or 0) + 1
A.Sync("c5")
assert(Live("c5", "player") == c, "the line count restyles in place")
assert(Frames(button) == frames and #LineGroups(button) == 4, "no new frames or loops")
local after = #LineTextures(button)
assert(after > before and tally.made - made == (after - before) * 2, "only the missing textures (both buttons)")
assert(Args(Child(groups[1], "Translation"), "SetDuration")[1] == K.GLOW[5].lap / 14, "fourteen lines")

-- A style without lines builds none: Pixel and Autocast cost nothing unused.
v.glowStyle = 1
A.Sync("c5")
local plain = Live("c5", "player")
assert(plain ~= c, "lines are part of the region set")
local pb = Acquired(plain, "g1")
assert(#LineGroups(pb) == 0 and R[pb].bind.shownAnims == 2, "style 1: no line parts")
-- A spell's own Pixel style asks for them on a bar that has another one.
a2.ov = { glowStyle = 5 }
A.Sync("c5")
local mixed = Live("c5", "player")
assert(mixed ~= plain and #LineGroups(Acquired(mixed, "g1")) == 4, "a per-spell line style builds the parts")
local g1, g2 = Acquired(mixed, "g1"), Acquired(mixed, "g2")
assert(R[Holder(g2)].shown and not R[Flip(g2)].shown, "its glow runs lines")
assert(not R[Holder(g1)].shown and R[Flip(g1)].shown, "the bar's alert elsewhere")
a2.ov = C.EMPTY

-- The swipe of buff icons: the bar's color, written on restyle only.
local cd = R[pb].bind.cooldown
local swipe = Args(cd, "SetSwipeColor")
assert(swipe[1] == 0 and swipe[2] == 0 and swipe[3] == 0, "today's black swipe")
v.swipeR, v.swipeG, v.swipeB, v.relook = .1, .2, .3, v.relook + 1
A.Sync("c5")
cd = R[Acquired(Live("c5", "player"), "g1")].bind.cooldown
swipe = Args(cd, "SetSwipeColor")
assert(swipe[1] == .1 and swipe[2] == .2 and swipe[3] == .3, "the bar's swipe color")
local paints = Calls(cd, "SetSwipeColor")
A.Sync("c5")
assert(Calls(cd, "SetSwipeColor") == paints, "an unchanged sync writes no swipe color")
v.swipeClass, v.relook = true, v.relook + 1
A.Sync("c5")
assert(math.abs(Args(cd, "SetSwipeColor")[1] - .25) < 1e-9, "class-colored swipe")
A.Release("c5")

-- Autocast in the pandemic window of a buff bar: bound to the window
-- (AddPandemicActiveAnimation), sparks of added light.
C.views.c6 = View("c6", 3)
local bv = C.views.c6
bv.pandemicStyle = 6
local r1 = Aura("c6", "a6201", "a", "player", Set(6201))
Plan("c6", 3, { r1 })
A.Sync("c6")
local row = Acquired(Live("c6", "player"), "g1")
assert(R[row].bind.panAnims == 6 and #LineGroups(row) == 4, "the pandemic window's two loops and four line loops")
for _, group in ipairs(LineGroups(row)) do
    assert(R[group].panAnim and not R[group].playing, "Blizzard plays them inside the window")
end
local sparks = LineTextures(row, true)
assert(#sparks > 0 and Args(sparks[1], "SetBlendMode")[1] == "ADD", "Autocast sparks")
local pan = Args(sparks[1], "SetColorTexture")
assert(pan[1] == 1 and math.abs(pan[2] - .302) < .01, "in the pandemic window's color")
-- The spark of a buff bar: none by default; on, it rides the sealed bar's fill.
bv.pandemicStyle = 4
A.Sync("c6")
local function Spark(button)
    return Find(button, function(obj, s)
        return s.kind == "Texture" and (Args(obj, "SetBlendMode") or {})[1] == "ADD" and not (Child(s.parent, "AnimationGroup"))
    end)[1]
end
row = Acquired(Live("c6", "player"), "g1")
assert(Spark(row) == nil, "no spark by default")
for _, fill in ipairs({ K.BAR_FILL.DRAIN, K.BAR_FILL.FILL }) do
    bv.barSpark, bv.barFill, bv.relook = true, fill, (bv.relook or 0) + 1
    A.Sync("c6")
    row = Acquired(Live("c6", "player"), "g1")
    local bind = R[row].bind
    local spark = assert(Spark(row), "the spark is made on first use")
    local point = R[spark].points[#R[spark].points]
    assert(point[1] == "CENTER" and point[2] == R[bind.bar].fill and point[3] == "RIGHT", "on the fill's moving edge")
    assert(R[spark].shown and Args(spark, "SetSize")[1] == 2, "a thin line")
    assert(bind.barOpts.direction == (fill == K.BAR_FILL.FILL and 0 or 1), "both directions fill from the left")
end
bv.barSpark, bv.relook = false, bv.relook + 1
A.Sync("c6")
assert(not R[Spark(Acquired(Live("c6", "player"), "g1"))].shown, "switched off")
A.Release("c6")

-- The active buff's swipe over a cooldown icon: today's gold for the
-- default color, the bar's color otherwise (a cooldown bar of its own).
C.views.c1 = View("c1", 1)
local ess = C.views.c1
local host = CreateFrame("Frame", nil, L.EnsureBar("c1").frame)
host.layShown = true
local o = { key = "b9301", src = "b", family = 1, hasAura = true, selfAura = true, unit = "player", auraIDs = Set(9301),
    ov = C.EMPTY, icon = host, slot = "c1", linked = C.EMPTY }
Plan("c1", 1, { o })
A.Sync("c1")
local ob1 = Acquired(Live("c1", "player", true), "s1")
swipe = Args(R[ob1].bind.cooldown, "SetSwipeColor")
assert(swipe[1] == 1 and swipe[2] == .82 and swipe[3] == 0 and swipe[4] == .55, "today's exact gold")
assert(ess.auraSwipeColor == "ffd100" and K.AuraSwipeRGB({}) == 1, "the default is the gold")
ess.auraSwipeColor, ess.auraSwipeR, ess.auraSwipeG, ess.auraSwipeB = "3366ff", .2, .4, 1
ess.relook = (ess.relook or 0) + 1
A.Sync("c1")
swipe = Args(R[Acquired(Live("c1", "player", true), "s1")].bind.cooldown, "SetSwipeColor")
assert(swipe[1] == .2 and swipe[2] == .4 and swipe[3] == 1 and swipe[4] == .55, "the bar's active buff swipe color")
A.Release("c1")

-- The countdown's tenths reach the duration text binding.
local state = C.state
state.tenths, state.cdExtra = 3, true
K.ForgetDurationText()
local opts = C.AuraButtons.TextOpts(0)
local points = opts.binding.calls.SetFormatter.points
assert(points[1].format == "%.1f" and points[1].step == .1 and points[2].threshold == 3, "tenths below three seconds")
state.tenths, state.cdExtra = 0, false
K.ForgetDurationText()
assert(C.AuraButtons.TextOpts(0) ~= opts and C.AuraButtons.TextOpts(0).binding.calls.SetFormatter.points[1].format == "%.0f",
    "back to whole seconds")
print("suite_cdm_look_auras_contract: ok")
end)() end
end
Features()
]=], "------------------------------------------------------------------ aura glow styles")
