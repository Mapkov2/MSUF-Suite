local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Pixel and Autocast glows (styles 5 and 6, K.GLOW): lines or sparks that
-- travel around a rectangle's border. Four bands tile the border like a
-- pinwheel (each owns one corner) and clip what they hold. A band's row of
-- pooled textures, one spacing apart, rides a mover that one looping
-- Translation shifts by exactly that spacing, so the row reads as an
-- endless stream that turns each corner into the next band. Only these four
-- AnimationGroups move anything: no Lua runs per frame. A cooldown icon
-- (Effects.lua) makes its set with its first glow in these styles; an aura
-- button gets one in initializeFrame when its container's region set asks
-- for it (AuraGlows.lua: the button binds the loops then). Both make the
-- textures as they are painted and keep them for the next paint.
local K = C.Const
local GlowLines = {}
C.GlowLines = GlowLines
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local EMPTY = C.EMPTY
local GOLD = K.GLOW_GOLD
-- Clockwise from the top left: the holder's corner a band starts at (its
-- textures count from there) and its direction of travel.
local BANDS = {
    { point = "TOPLEFT", x = 1, y = 0 },
    { point = "TOPRIGHT", x = 0, y = -1 },
    { point = "BOTTOMRIGHT", x = -1, y = 0 },
    { point = "BOTTOMLEFT", x = 0, y = 1 },
}
-- The bar rules' defaults (glowLines, glowThickness, glowSpeed).
local COUNT, THICK, SPEED = 8, 2, 100

local function Play(set)
    for i = 1, 4 do set[i].group:Play() end
end
local function Stop(set)
    for i = 1, 4 do set[i].group:Stop() end
end

-- Frames inside an aura button are the client's, made with their parent
-- (K.Child); a cooldown icon's are ours (S.CreateFrame).
local function NewFrame(own, parent, level)
    local frame
    if own then
        frame = S.CreateFrame("Frame", nil, parent)
    else
        frame = K.Child("Frame", parent)
    end
    frame:SetFrameLevel(level)
    return frame
end

-- A set on parent (a glow's frame). Every frame sits at the glow's level: a
-- child would rise one above it, onto the texts. set:Play() and set:Stop()
-- run the four loops.
function GlowLines.New(parent, own, level)
    local holder = NewFrame(own, parent, level)
    holder:SetAllPoints(parent)
    holder:Hide()
    local set = { frame = holder, own = own, level = level, Play = Play, Stop = Stop }
    for i = 1, 4 do
        local clip = NewFrame(own, holder, level)
        clip:SetClipsChildren(true)
        local mover = NewFrame(own, clip, level)
        mover:SetAllPoints(clip)
        local group = mover:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        set[i] = { clip = clip, mover = mover, group = group, slide = group:CreateAnimation("Translation"), tex = {} }
    end
    return set
end

-- A cooldown icon's style pass moves its glow's level (Icons.lua).
function GlowLines.Level(set, level)
    if set.level == level then return end
    set.level = level
    set.frame:SetFrameLevel(level)
    for i = 1, 4 do
        set[i].clip:SetFrameLevel(level)
        set[i].mover:SetFrameLevel(level)
    end
end

-- An aura button's set loops with its glow (AuraGlows.NewGlow, inside
-- initializeFrame): Blizzard plays it while the button shows, the pandemic
-- window's while the aura is inside it; 12.1.0 has neither, and Lua starts
-- the loops once, as it does the glow's own.
function GlowLines.Bind(set, button, pandemic)
    local add
    if pandemic then
        add = button.AddPandemicActiveAnimation
    else
        add = button.AddAuraShownAnimation
    end
    for i = 1, 4 do
        local group = set[i].group
        if add then add(button, group) end
        if not (pandemic and add) then group:Play() end
    end
end

-- One band: its clip in the holder's corner, its loop's shift, and its row
-- from one spacing (plus a texture) behind the band's start, so the shifted
-- row still covers it, to the band's end. Textures beyond the row hide.
local function PlaceBand(set, band, side, start, length, t, step, size, r, g, b, spark)
    local horizontal = side.y == 0
    local clip, mover = band.clip, band.mover
    clip:ClearAllPoints()
    clip:SetPoint(side.point, set.frame, side.point, 0, 0)
    clip:SetSize(horizontal and length or t, horizontal and t or length)
    band.slide:SetOffset(side.x * step, side.y * step)
    local textures, n = band.tex, 0
    local u = (-start) % step - step * ceil((size + step) / step)
    while u < length do
        n = n + 1
        local tex = textures[n]
        if not tex then
            if set.own then
                tex = S.CreateTexture(mover, nil, "OVERLAY")
            else
                tex = mover:CreateTexture(nil, "OVERLAY")
            end
            textures[n] = tex
        end
        tex:ClearAllPoints()
        tex:SetPoint(side.point, mover, side.point, side.x * u, side.y * u)
        tex:SetSize(horizontal and size or t, horizontal and t or size)
        tex:SetColorTexture(r, g, b, 1)
        tex:SetBlendMode(spark and "ADD" or "BLEND")
        tex:Show()
        u = u + step
    end
    for i = n + 1, #textures do textures[i]:Hide() end
end

-- The set for a w x h rectangle (px: one physical pixel). spec.lines
-- "pixel" draws lines half a spacing long, "spark" squares twice the
-- thickness; count of them, thickness in pixels, speed in percent of
-- spec.lap seconds per round. Same input: no call.
local function Placed(set, spec, count, thick, speed, r, g, b, w, h, px)
    return set.spec == spec and set.count == count and set.thick == thick and set.speed == speed and set.r == r
        and set.g == g and set.b == b and set.w == w and set.h == h and set.px == px
end
function GlowLines.Paint(set, spec, count, thick, speed, r, g, b, w, h, px)
    if Placed(set, spec, count, thick, speed, r, g, b, w, h, px) then return end
    set.spec, set.count, set.thick, set.speed, set.r, set.g, set.b, set.w, set.h, set.px =
        spec, count, thick, speed, r, g, b, w, h, px
    local spark = spec.lines == "spark"
    local t = min((spark and 2 * thick or thick) * px, w / 3, h / 3)
    local width, height = w - t, h - t
    local step = 2 * (width + height) / count
    local size = t
    if not spark then size = max(t, floor(step / 2 / px + .5) * px) end
    local duration = spec.lap / count * 100 / speed
    local start = 0
    for i = 1, 4 do
        local band, side = set[i], BANDS[i]
        local length = side.y == 0 and width or height
        band.slide:SetDuration(duration)
        PlaceBand(set, band, side, start, length, t, step, size, r, g, b, spark)
        start = start + length
    end
end

local function Look(view)
    return view.glowLines or COUNT, view.glowThickness or THICK, view.glowSpeed or SPEED
end

-- A cooldown icon's glow (Effects.lua's PaintPlain): its bar's lines (a
-- stand-in icon: the defaults) in the glow's color, the alert's gold
-- without one. The plain look's memo is dropped, so a plain style paints
-- again after this one.
function GlowLines.PaintIcon(glow, icon, spec, r, g, b, w, h)
    local set = glow.lines
    if not set then
        set = GlowLines.New(glow, true, glow:GetFrameLevel())
        glow.lines = set
    end
    glow.pStyle = nil
    if glow.flipOn then
        glow.flipOn = false
        glow.flip:Hide()
    end
    if glow.edgesOn then
        glow.edgesOn = false
        for i = 1, 4 do glow.edges[i]:Hide() end
    end
    local entry = icon.entry
    local count, thick, speed = Look(entry and C.views[entry.slot] or EMPTY)
    GlowLines.Paint(set, spec, count, thick, speed, r or GOLD[1], g or GOLD[2], b or GOLD[3], w, h, K.Px())
    if not glow.linesOn then
        glow.linesOn = true
        set.frame:Show()
    end
end

-- Whether a running icon glow's lines differ from its bar's now (Effects.lua's Restyle).
function GlowLines.Changed(glow, view)
    local set = glow.lines
    local count, thick, speed = Look(view)
    return set.count ~= count or set.thick ~= thick or set.speed ~= speed
end

-- A plain style or a shape's rings take the icon's glow: its lines stop and hide.
function GlowLines.Off(glow)
    local set = glow.lines
    glow.linesOn = false
    set:Stop()
    set.frame:Hide()
end

-- An aura button's glow (AuraGlows.lua's PaintGlow, while the button takes
-- writes): its bar's lines (g.lc, g.lt, g.lv: AuraGlows.Reshape keeps them)
-- at the button's size (lk).
function GlowLines.PaintAura(g, spec, r, gg, b, lk)
    g.flip:Hide()
    g.ring:Hide()
    local set = g.lines
    GlowLines.Paint(set, spec, g.lc or COUNT, g.lt or THICK, g.lv or SPEED, r or GOLD[1], gg or GOLD[2], b or GOLD[3],
        lk.w, lk.h, lk.px)
    set.frame:Show()
end
