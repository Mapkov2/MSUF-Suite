local root = assert(arg[1], "repository root required")
-- Cooldown manager looks on the render plane (package cdm11-B): the Pixel
-- and Autocast glow styles on cooldown icons (GlowLines.lua through
-- Effects.lua), the bar's swipe color, the countdown's tenths and urgent
-- stage, and the spark of cooldown timer bars. Runs on the render
-- contract's harness up to its glow checks; everything here is new and
-- defaults to today's look.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_render_contract.lua", [=[
do (function()
-- Widget calls these looks make, recorded with their arguments.
Record("SetClipsChildren")
Record("SetBlendMode", function(self, mode) self.blend = mode end)
Record("SetOffset", function(self, x, y) self.offset = { x, y } end)
Record("SetColorTexture", function(self, r, g, b, a) self.color = { r, g, b, a } end)
Record("SetSwipeColor", function(self, r, g, b, a) self.swipe = { r, g, b, a } end)
Record("SetPoint", function(self, a, b, c, d, e) self.point = { a, b, c, d, e } end)
Record("SetDuration", function(self, value) self.duration = value end)
local Lines = assert(C.GlowLines, "GlowLines.lua loads before Effects.lua")
local function Near(a, b) return math.abs(a - b) < 1e-9 end

-- The styles: indices 1 to 4 keep their looks, 5 Pixel and 6 Autocast are new.
local GLOW = K.GLOW
assert(#GLOW == 6, "six glow styles")
assert(GLOW[1].atlas == "UI-HUD-ActionBar-Proc-Loop-Flipbook" and GLOW[1].scale == 1.4 and not GLOW[1].lines, "style 1")
assert(GLOW[2].atlas == "rotationhelper_ants_flipbook" and GLOW[2].scale == 1.2 and not GLOW[2].lines, "style 2")
assert(GLOW[3].edge == 2 and GLOW[3].pulse == .6 and not GLOW[3].lines, "style 3")
assert(GLOW[4].edge == 2 and not GLOW[4].pulse and not GLOW[4].atlas and not GLOW[4].lines, "style 4")
assert(GLOW[5].lines == "pixel" and GLOW[6].lines == "spark" and GLOW[5].lap and GLOW[6].lap, "styles 5 and 6")
assert(K.GlowSpec({ glowStyle = 5 }, 1) == 5 and K.GlowSpec({ glowStyle = 6 }, 2) == 6 and K.GlowSpec({}, 6) == 6
    and K.GlowSpec({}, 7) == 1, "per-spell and bar styles resolve, an unknown one is the alert")
local labels = rules[NS.CDM.KEYS.ess.glowStyle].choices
assert(labels[1] == "Blizzard alert" and labels[2] == "Marching ants" and labels[3] == "Pulse" and labels[4] == "Border"
    and labels[5] == "Pixel" and labels[6] == "Autocast" and #labels == 6, "glow style labels are append-only")
assert(rules[NS.CDM.KEYS.ess.pandemicStyle].choices[6] == "Autocast", "the pandemic window offers them too")

-- A glow in styles 1 to 4 makes no line set: the new styles cost nothing unused.
IndexIconEntries()
local icon = b1.icon
ess.glowStyle, ess.behaviorGen = 1, ess.behaviorGen + 1
overlayed[100] = true
E.Proc(b1, true)
assert(icon.glow and icon.glow.shown and not icon.glow.lines and not icon.glow.linesOn, "style 1: no lines")
overlayed[100] = nil
E.Proc(b1, false)

-- Pixel: four clipping bands, each one looping Translation by one spacing.
ess.glowStyle, ess.behaviorGen = 5, ess.behaviorGen + 1
E.Update(b1)
local made = #all
overlayed[100] = true
E.Proc(b1, true)
local glow = icon.glow
local set = assert(glow.lines, "the first Pixel glow makes its set")
assert(glow.linesOn and set.frame.shown and not glow.flip.shown, "lines show, the alert's art does not")
for i = 1, 4 do assert(not glow.edges[i].shown, "no still border under the lines") end
local w, h, t = icon.w, icon.h, 2
local step = 2 * ((w - t) + (h - t)) / 8
local SHIFT = { { step, 0 }, { 0, -step }, { -step, 0 }, { 0, step } }
local textures = 0
for i = 1, 4 do
    local band = set[i]
    assert(Calls(band.clip, "SetClipsChildren") == 1 and band.group.last.SetLooping == "REPEAT" and band.group.playing,
        "band " .. i .. " clips and loops")
    assert(band.slide.kind == "Translation" and Near(band.slide.offset[1], SHIFT[i][1]) and Near(band.slide.offset[2], SHIFT[i][2]),
        "band " .. i .. " shifts by one spacing")
    assert(Near(band.slide.duration, GLOW[5].lap / 8), "eight lines at 100 percent: a lap in " .. GLOW[5].lap .. " s")
    assert(band.clip.level == glow.level and band.mover.level == glow.level and set.frame.level == glow.level,
        "the line frames stay at the glow's level")
    for _, tex in ipairs(band.tex) do
        if tex.shown then
            textures = textures + 1
            assert(tex.color[1] == 1 and Near(tex.color[2], .82) and tex.color[3] == 0 and tex.blend == "BLEND", "gold lines")
        end
    end
end
assert(textures >= 8 and textures <= 8 + 12, "one row per band covers the lines: " .. textures)
-- Hidden and shown again: the same set, nothing made, nothing painted.
local colors = Calls(set[1].tex[1], "SetColorTexture")
overlayed[100] = nil
E.Proc(b1, false)
for i = 1, 4 do assert(not set[i].group.playing, "a hidden glow stops its loops") end
overlayed[100] = true
E.Proc(b1, true)
assert(icon.glow.lines == set and set[1].group.playing and Calls(set[1].tex[1], "SetColorTexture") == colors,
    "showing the same look again only plays")
-- The bar's lines: a running glow follows (a behavior refresh), its
-- textures are reused and only the missing ones made.
local first, kept = set[1].tex[1], #all
ess.glowLines, ess.glowSpeed, ess.behaviorGen = 12, 200, ess.behaviorGen + 1
E.Update(b1)
assert(set[1].tex[1] == first and set[1].group.playing, "the set and its textures are reused")
assert(Near(set[1].slide.duration, GLOW[5].lap / 12 / 2), "twelve lines at 200 percent")
local frames = 0
for i = kept + 1, #all do
    assert(all[i].kind == "Texture", "a new line count makes only textures, got " .. all[i].kind)
    frames = frames + 1
end
assert(made < kept and frames < 12, "only the missing textures: " .. frames)
-- Autocast: squares twice the thickness, added light.
ess.glowStyle, ess.behaviorGen = 6, ess.behaviorGen + 1
E.Update(b1)
local spark = set[1].tex[1]
assert(spark.blend == "ADD" and spark.w == 4 and spark.h == 4 and set[1].clip.h == 4, "Autocast sparks")
assert(Near(set[1].slide.duration, GLOW[6].lap / 12 / 2), "Autocast laps slower")
-- A tint colors the lines.
ess.glowTint, ess.behaviorGen = true, ess.behaviorGen + 1
E.Update(b1)
assert(Near(spark.color[1], ess.glowR) and Near(spark.color[2], ess.glowG), "the bar's glow color")
-- Back to a border: the lines stop and hide, the edges pulse.
ess.glowStyle, ess.glowTint, ess.behaviorGen = 3, false, ess.behaviorGen + 1
E.Update(b1)
assert(not glow.linesOn and not set.frame.shown and not set[1].group.playing and glow.pulse.playing and glow.edges[1].shown,
    "a border style takes the glow back")
-- A style pass that moves the icon's level moves the lines' frames with it.
ess.glowStyle, ess.behaviorGen = 5, ess.behaviorGen + 1
E.Update(b1)
icon.level = icon.level + 3
ess.styleGen = ess.styleGen + 1
I.Style("ess")
assert(set[1].mover.level == icon.level + K.LEVEL.glow and set.frame.level == icon.level + K.LEVEL.glow, "lines follow the level")
overlayed[100] = nil
E.Proc(b1, false)
ess.glowLines, ess.glowSpeed, ess.glowStyle, ess.behaviorGen = 8, 100, 1, ess.behaviorGen + 1
E.Update(b1)

-- No frame script drives any of it: AnimationGroups only.
for _, file in ipairs({ "GlowLines.lua", "Effects.lua", "AuraGlows.lua", "AssistIcon.lua", "KickMark.lua", "Const.lua", "TrackingBars.lua",
    "AuraButtons.lua", "Icons.lua" }) do
    local handle = assert(io.open(root .. "/MSUF_Suite_CooldownManager/" .. file, "rb"))
    local text = handle:read("*a")
    handle:close()
    assert(not text:find("OnUpdate", 1, true), file .. " sets an OnUpdate")
    if file == "GlowLines.lua" then
        assert(not text:find("SetScript", 1, true) and not text:find("HookScript", 1, true), "the lines set no scripts")
    end
end

-- The swipe's color: black by default, the bar's color or class color,
-- written by the style pass only (no update repaints it).
assert(b1.icon.cd.swipe[1] == 0 and b1.icon.cd.swipe[2] == 0 and b1.icon.cd.swipe[3] == 0 and Near(b1.icon.cd.swipe[4], .7),
    "today's black swipe")
assert(rules[NS.CDM.KEYS.ess.swipeColor].default == "000000" and rules[NS.CDM.KEYS.ess.swipeClass].default == false,
    "swipe color defaults")
ess.swipeR, ess.swipeG, ess.swipeB, ess.styleGen = .2, .4, .6, ess.styleGen + 1
I.Sync("ess")
local swipe = b1.icon.cd.swipe
assert(swipe[1] == .2 and swipe[2] == .4 and swipe[3] == .6 and Near(swipe[4], .7), "the bar's swipe color")
assert(b2.icon.chargeCd.swipe[1] == .2, "the recharge swipe takes it too")
local paints = Calls(b1.icon.cd, "SetSwipeColor")
T.Refresh(b1, "full")
I.Sync("ess")
assert(Calls(b1.icon.cd, "SetSwipeColor") == paints, "an update or unchanged sync writes no swipe color")
ess.swipeClass, ess.styleGen = true, ess.styleGen + 1
I.Sync("ess")
assert(Near(b1.icon.cd.swipe[1], .25) and Near(b1.icon.cd.swipe[2], .78), "class-colored swipe")
ess.swipeClass, ess.swipeR, ess.swipeG, ess.swipeB, ess.styleGen = false, 0, 0, 0, ess.styleGen + 1
I.Sync("ess")

-- The countdown's stages: breakpoints only, one formatter per signature.
local plain = K.CountdownFormatter(3, 1, .5, 0)
assert(#plain.points == 4 and plain.points[1].format == "|cffff8000%.0f|r" and plain.points[1].step == nil
    and plain.points[2].threshold == 3 and plain.points[2].format == "%.0f", "today's warning breakpoints")
assert(K.CountdownFormatter(3, 1, .5, 0, 0, 0) == plain, "no tenths and no urgent stage: today's formatter")
local tenths = K.CountdownFormatter(0, nil, nil, nil, 3)
local p = tenths.points
assert(#p == 4 and p[1].threshold == 0 and p[1].format == "%.1f" and p[1].step == .1 and p[1].rounding == 1
    and p[2].threshold == 3 and p[2].format == "%.0f" and p[3].threshold == 60 and p[4].threshold == 3600, "tenths below 3 s")
local staged = K.CountdownFormatter(3, 1, .5, 0, 5, 2, 1, .125, .125)
p = staged.points
assert(#p == 6, "four stages below a minute")
assert(p[1].threshold == 0 and p[1].format == "|cffff2020%.1f|r" and p[1].step == .1, "urgent with tenths")
assert(p[2].threshold == 2 and p[2].format == "|cffff8000%.1f|r", "warning with tenths")
assert(p[3].threshold == 3 and p[3].format == "%.1f" and p[4].threshold == 5 and p[4].format == "%.0f", "tenths, then whole")
local urgent = K.CountdownFormatter(0, nil, nil, nil, 0, 4, 1, 0, 0)
assert(urgent.points[1].format == "|cffff0000%.0f|r" and urgent.points[2].threshold == 4 and urgent.points[2].format == "%.0f",
    "an urgent stage alone")
assert(K.CountdownFormatter(3, 1, .5, 0, 5, 2, 1, .125, .125) == staged and staged ~= plain and staged ~= tenths
    and K.CountdownFormatter(3, 1, .5, 0, 5, 2, 1, 0, 0) ~= staged and K.CountdownFormatter(3, 1, .5, 0, 4, 2, 1, .125, .125) ~= staged,
    "the cache key holds every stage")
-- The icons ask the Text section's stages: tenths alone still sets a formatter.
assert(K.Countdown(0) == nil, "nothing set: Blizzard's own countdown")
C.state.tenths, C.state.cdExtra = 3, true
assert(K.Countdown(0) == tenths, "tenths alone set a formatter")
ess.styleGen = ess.styleGen + 1
I.Sync("ess")
assert(b1.icon.cd.formatter == tenths, "the cooldown swipe counts tenths")
C.state.tenths, C.state.cdExtra = 0, false
ess.styleGen = ess.styleGen + 1
I.Sync("ess")
assert(b1.icon.cd.formatter == nil, "back to Blizzard's countdown")

-- The spark of cooldown timer bars: anchored to the fill texture's moving
-- edge, so the client carries it; both directions fill from the left.
assert(rules[NS.CDM.KEYS.ess.barSpark].default == false, "no spark by default")
ess.cooldownDuration, ess.styleGen = true, ess.styleGen + 1
I.Sync("ess")
local bar = assert(b1.icon.timerBar, "timer bar")
assert(bar.spark == nil, "no spark made while it is off")
for _, fill in ipairs({ NS.CDM.BAR_FILL.DRAIN, NS.CDM.BAR_FILL.FILL }) do
    ess.barSpark, ess.barFill, ess.styleGen = true, fill, ess.styleGen + 1
    I.Sync("ess")
    local spark = assert(bar.spark, "the spark is made on first use")
    assert(spark.shown and spark.point[1] == "CENTER" and spark.point[2] == bar:GetStatusBarTexture() and spark.point[3] == "RIGHT"
        and spark.point[4] == 0 and spark.point[5] == 0, "the spark rides the fill's edge (fill " .. fill .. ")")
    assert(spark.blend == "ADD" and spark.h == bar.innerHeight and spark.w == 2, "a thin bright line")
end
assert(bar.direction == Enum.StatusBarTimerDirection.ElapsedTime, "the filling bar counts up")
-- Charge segments draw the bar instead: the spark waits.
bar.chargeSegments = true
C.TrackingBars.Charges(b1.icon, { maxCharges = 3, currentCharges = 1, isActive = false }, nil)
assert(bar.segmentMode and not bar.spark.shown, "segments hide the spark")
C.TrackingBars.Charges(b1.icon, nil, nil)
assert(not bar.segmentMode and bar.spark.shown, "the spark returns with the fill")
ess.barSpark, ess.styleGen = false, ess.styleGen + 1
I.Sync("ess")
assert(not bar.spark.shown, "switched off")
ess.cooldownDuration, ess.barFill, ess.styleGen = false, NS.CDM.BAR_FILL.DRAIN, ess.styleGen + 1
I.Sync("ess")
print("suite_cdm_look_render_contract: ok")
end)() end
]=], "------------------------------------------------------------------ Effects: glows")
