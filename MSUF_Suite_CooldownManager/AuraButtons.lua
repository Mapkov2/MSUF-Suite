local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- What the aura layer draws inside Blizzard's aura buttons, and the stand-in
-- icons it draws on cells. Auras.lua builds the containers and calls in
-- here: a container record (rec) carries the look (rec.lk) and the bar's
-- choices; each button's regions and state live in a part record, never on
-- the button.
--  * Look: every visual value of a container's buttons and the signature
--    that changes exactly when a button needs restyling;
--  * Init (initializeFrame): builds every region of a new button, styles it
--    and binds last (bound regions are sealed);
--  * Style and ApplyEntry restyle a button and apply its per-spell choices
--    (swipe, glows, stack text, countdown, text on top); Mutable says
--    whether sealed buttons accept that now;
--  * kit sensors hear a button show or hide (unknown kit sounds only);
--  * placeholders: a dimmed icon for missing buffs (showMissing) and the
--    sample icon in the preview, on the cell under the slot button.
local K = C.Const
local B = {}
C.AuraButtons = B

-- Regions inside Blizzard's aura buttons are created with the client's
-- CreateFrame: the container lays those buttons out and seals their bound
-- regions, so MSUF's pixel-layout policy (S.CreateFrame) must not round what
-- Blizzard positions. Placeholders sit on our own cells (S.CreateTexture).
local CreateFrame = CreateFrame
local IsCombatLocked = NS.IsCombatLocked
local floor, max, min = math.floor, math.max, math.min
local type, tonumber = type, tonumber
local tconcat = table.concat
local Public = S.Public
local EMPTY = C.EMPTY

local QUESTION = K.QUESTION_ICON
local BAR_TEXTURE = K.BAR_TEXTURE
local TEXT_DEFAULT = {}
-- Init of a button whose group has no entry yet: the bar's choices.
local NO_ENTRY = {}
local TIMER = Enum.StatusBarTimerDirection
local IMMEDIATE = Enum.StatusBarInterpolation.Immediate
-- barFill 1 drains, 2 fills.
local BAR_OPTS = { { direction = TIMER.RemainingTime, interpolation = IMMEDIATE },
    { direction = TIMER.ElapsedTime, interpolation = IMMEDIATE } }
local ROUND = Enum.NumericRuleFormatRounding
local UP, DOWN = ROUND.Up, ROUND.Down
local GOLD = K.GLOW_GOLD
local BAR_LEVEL, ICON_LEVEL = K.AURA_LEVEL, K.AURA_ICON_LEVEL
local PANDEMIC = { 1, .3, .15 }
-- Glow styles (Const): 1 Blizzard alert and 2 marching ants share one
-- flipbook layout, 3 pulses the edges, 4 holds them still.
local GLOW = K.GLOW
local FLIP = GLOW[1]
local PULSE = GLOW[3].pulse
local PULSE_LOW = .25
-- The widest glow reaches this far around its button: the stack gate's size.
local REACH = 1
for i = 1, #GLOW do
    local scale = GLOW[i].scale
    if scale and scale > REACH then REACH = scale end
end
local STACK_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local STACK_COLOR = NS.CDM.SPELL_DEFAULTS.stackColor
-- Every field Look writes: the signature changes exactly when a button needs restyling.
local LOOK = { "w", "h", "px", "bw", "er", "eg", "eb", "l", "r", "t", "b", "font", "flags", "rendering", "shadow", "shadowOpacity",
    "shadowDistance", "cs", "ss", "sp", "cr", "cg", "cb", "sr", "sg", "sb", "swipe", "edge", "tip", "tex", "fr", "fg", "fb", "bgA", "icon", "side",
    "smax", "marks" }
local NO_MARKS = {}

local sig = {}
local textOpts = {}
local countOpts = {} -- stack text options per (N, color)
local barOpts = {}   -- SetApplicationBar options (Blizzard copies them)
local sensed = {}    -- kit sensor frame -> its button record

local Px = K.Px
local function Snap(value, px) return floor(value / px + .5) * px end
local ClassRGB = K.ClassRGB

-- Duration text options per (threshold, warning color): a binding template
-- that Blizzard copies into each button. The fallbacks must ride on the
-- binding, and without a formatter on it no text renders at all.
local function TextOpts(seconds)
    local state = C.state
    if type(seconds) ~= "number" or seconds <= 0 then
        seconds = 0
    else
        seconds = floor(seconds + .5)
    end
    local R, G, B = 0, 0, 0
    if seconds > 0 then R, G, B = floor((state.thR or 1) * 255 + .5), floor((state.thG or 1) * 255 + .5), floor((state.thB or 1) * 255 + .5) end
    local key = seconds * 16777216 + R * 65536 + G * 256 + B
    local opts = textOpts[key]
    if opts then return opts end
    local points = { { threshold = 0, format = "%.0f", rounding = UP } }
    if seconds > 0 then
        points[1].format = ("|cff%02x%02x%02x%%.0f|r"):format(R, G, B)
        points[2] = { threshold = seconds, format = "%.0f", rounding = UP }
    end
    points[#points + 1] = { threshold = 60, format = "%d:%02d", rounding = DOWN, components = { { div = 60, rounding = DOWN }, { mod = 60, rounding = DOWN } } }
    points[#points + 1] = { threshold = 3600, format = "%dh", rounding = DOWN, components = { { div = 3600, rounding = DOWN } } }
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints(points)
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFormatter(formatter)
    binding:SetZeroDurationText("")
    binding:SetExpiredText("")
    binding:SetUpdateInterval(.1)
    binding:SetEnabled(true)
    opts = { binding = binding }
    textOpts[key] = opts
    return opts
end

-- Stack text options per (stackColorAt, stackColor): one formatter per
-- signature, shared by every button. Nothing below two applications (like
-- Blizzard's default), plain from two, colored from N (N = 1 colors a
-- single application too). nil: the plain binding (off).
local function CountOpts(ov)
    local n = ov.stackColorAt
    if type(n) ~= "number" or n < 1 then return nil end
    n = floor(n)
    local hex = ov.stackColor or STACK_COLOR
    local rgb = type(hex) == "string" and #hex == 6 and tonumber(hex, 16)
    if not rgb then return nil end
    local key = n * 16777216 + rgb
    local opts = countOpts[key]
    if opts then return opts end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local points = { { threshold = 0, format = "" } }
    if n > 2 then points[2] = { threshold = 2, format = "%d" } end
    points[#points + 1] = { threshold = n, format = "|cff" .. hex .. "%d|r" }
    formatter:SetBreakpoints(points)
    opts = { formatter = formatter }
    countOpts[key] = opts
    return opts
end

------------------------------------------------------------------ look
-- Every visual value of a container's buttons in rec.lk; the returned
-- string changes exactly when a button needs restyling.
local function Look(rec, view)
    local state, lk, bar = C.state, rec.lk, rec.role == "bar"
    local px = Px()
    local w, h
    if bar then
        w, h = max(px, Snap(view.barWidth or 200, px)), max(px, Snap(view.barHeight or 18, px))
    else
        local size = view.size or 36
        w, h = max(px, Snap(size, px)), max(px, Snap(size * (view.height or 100) / 100, px))
    end
    local bw = floor(view.border or (bar and 1 or 0)) * px
    lk.w, lk.h, lk.px, lk.bw = w, h, px, bw
    local r, g, b
    if view.borderClass then r, g, b = ClassRGB() end
    if not r then r, g, b = view.borderR or 0, view.borderG or 0, view.borderB or 0 end
    lk.er, lk.eg, lk.eb = r, g, b
    -- Same crop as the cooldown icons (a bar's icon is square).
    local iw, ih = w - 2 * bw, h - 2 * bw
    if bar then iw = ih end
    lk.l, lk.r, lk.t, lk.b = K.Crop(view.zoom, iw, ih)
    lk.font, lk.flags = state.font, state.fontFlags
    lk.rendering, lk.shadow, lk.shadowOpacity, lk.shadowDistance =
        state.fontRendering, state.fontShadow, state.fontShadowOpacity, state.fontShadowDistance
    local cs, ss = view.cdSize or 0, view.stackSize or 0
    if cs <= 0 then cs = bar and max(9, floor(h * .55)) or max(10, floor(h * .38)) end
    if ss <= 0 then ss = bar and max(8, floor(h * .45)) or max(9, floor(h * .3)) end
    lk.cs, lk.ss = cs, ss
    local pos = view.stackPos
    lk.sp = (pos and K.POINTS[pos]) and pos or 9
    lk.cr, lk.cg, lk.cb = state.cdR or 1, state.cdG or 1, state.cdB or 1
    lk.sr, lk.sg, lk.sb = state.stackR or 1, state.stackG or 1, state.stackB or 1
    lk.swipe = (view.swipeAlpha or 60) / 100
    lk.edge = view.edge == true
    lk.tip = view.tooltips == true
    if bar then
        lk.tex = S.ResolveTexture(view.barTexture, BAR_TEXTURE)
        r, g, b = nil, nil, nil
        if view.barClass ~= false then r, g, b = ClassRGB() end
        if not r then r, g, b = view.barR or .91, view.barG or .72, view.barB or .33 end
        lk.fr, lk.fg, lk.fb = r, g, b
        lk.bgA = (view.barBgAlpha or 55) / 100
        lk.icon = view.barIcon ~= false
        lk.side = view.barIconSide == 2 and 2 or 1
        -- Stack fill maximum and markers are looks, not region sets: a new
        -- value restyles the buttons in place (application bar rebound,
        -- pooled markers placed), never builds another container.
        lk.smax = max(1, min(99, floor(view.barStackMax or 10)))
        lk.marks = view.barStackEach ~= false and "each" or (view.barStackMarks or "")
    end
    for i = 1, #LOOK do
        local v = lk[LOOK[i]]
        if v == true then
            v = 1
        elseif not v then
            v = 0
        end
        sig[i] = v
    end
    return tconcat(sig, "\031", 1, #LOOK)
end

------------------------------------------------------------------ buttons
local function Edges(owner)
    local set = {}
    for i = 1, 4 do set[i] = owner:CreateTexture(nil, "OVERLAY") end
    return set
end

------------------------------------------------------------------ glows
-- One glow on an aura button, built in initializeFrame: a flipbook texture
-- for styles 1 and 2 and four edges on their own frame for 3 (pulsing) and
-- 4 (still). Both loops run in C. The flipbook rests at alpha 0 and only
-- its loop lifts it, so a stopped loop never shows the whole sheet. 12.1.5
-- and Forever play the loops each time the button shows and stop them when
-- it hides (AddAuraShownAnimation); 12.1.0 has only the start given here.
local function NewGlow(button, parent, level)
    -- This independent native visibility gate never reads aura state and
    -- never requires a Lua mutation of protected descendants in combat.
    local combatGate = CreateFrame("Frame", nil, parent)
    combatGate:SetAllPoints(parent)
    local frame = CreateFrame("Frame", nil, combatGate)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(level)
    frame:Hide()
    local flip = frame:CreateTexture(nil, "OVERLAY")
    flip:SetPoint("CENTER", frame, "CENTER", 0, 0)
    flip:SetAlpha(0)
    flip:Hide()
    local loop = flip:CreateAnimationGroup()
    loop:SetLooping("REPEAT")
    local lift = loop:CreateAnimation("Alpha")
    lift:SetFromAlpha(1)
    lift:SetToAlpha(1)
    lift:SetDuration(FLIP.duration)
    local book = loop:CreateAnimation("FlipBook")
    book:SetFlipBookRows(FLIP.rows)
    book:SetFlipBookColumns(FLIP.cols)
    book:SetFlipBookFrames(FLIP.frames)
    book:SetFlipBookFrameWidth(0)
    book:SetFlipBookFrameHeight(0)
    book:SetDuration(FLIP.duration)
    -- The edges share the glow's level: a child would sit one above it, on
    -- the countdown's level.
    local ring = CreateFrame("Frame", nil, frame)
    ring:SetAllPoints(frame)
    ring:SetFrameLevel(level)
    ring:Hide()
    local pulse = ring:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(1)
    fade:SetDuration(PULSE)
    local g = { frame = frame, flip = flip, ring = ring, edges = Edges(ring), fade = fade,
        combatGate = combatGate, combatOnly = false }
    -- 12.1.0 lacks AddAuraShownAnimation: the loops play without it.
    if button.AddAuraShownAnimation then
        button:AddAuraShownAnimation(loop)
        button:AddAuraShownAnimation(pulse)
    end
    loop:Play()
    pulse:Play()
    return g
end

-- "All glows only in combat": a secure state driver shows the glow's gate
-- in combat only (a sealed button's descendants refuse Lua in combat). The
-- state driver manager re-reads every driver on each pass, and Blizzard
-- pools ten buttons per group, so only a glow that can show (on: its entry
-- uses it) holds one.
local parkedGates = {}
local function ApplyCombatGate(g, on, dry)
    if not dry then parkedGates[g] = nil end
    local wanted = on == true and C.state.allGlowsCombat == true and not C.state.preview
    if g.combatOnly == wanted then return false end
    if dry then return true end
    g.combatOnly = wanted
    if wanted then
        RegisterStateDriver(g.combatGate, "visibility", "[combat] show; hide")
    else
        UnregisterStateDriver(g.combatGate, "visibility")
        g.combatGate:Show()
    end
    return false
end

function B.ReleaseGlows(rec)
    for _, part in ipairs(rec.parts) do
        for i = 1, 3 do
            local g
            if i == 1 then g = part.glow
            elseif i == 2 then g = part.stack and part.stack.glow
            else g = part.stackSensor and part.stackSensor.part.stack.glow end
            if g and g.combatOnly then
                if IsCombatLocked() then
                    parkedGates[g] = true
                else
                    UnregisterStateDriver(g.combatGate, "visibility")
                    g.combatOnly = false
                    g.combatGate:Show()
                end
            end
        end
    end
end

function B.FlushGates()
    if IsCombatLocked() then return end
    for g in pairs(parkedGates) do
        UnregisterStateDriver(g.combatGate, "visibility")
        g.combatOnly = false
        g.combatGate:Show()
        parkedGates[g] = nil
    end
end

-- Style, color (nil: the art's own gold) and the size of what the glow
-- surrounds. Same input: no call.
local function Painted(g, style, r, gg, b, lk)
    return g.st == style and g.cr == r and g.cg == gg and g.cb == b and g.w == lk.w and g.h == lk.h and g.px == lk.px
end
local function PaintGlow(g, style, r, gg, b, lk)
    if Painted(g, style, r, gg, b, lk) then return end
    local w, h, px = lk.w, lk.h, lk.px
    g.st, g.cr, g.cg, g.cb, g.w, g.h, g.px = style, r, gg, b, w, h, px
    local spec = GLOW[style] or FLIP
    if spec.atlas then
        -- Same margin on every side: bars get a band, not a stretched art.
        local grow = (spec.scale - 1) * min(w, h)
        local flip = g.flip
        flip:SetAtlas(spec.atlas)
        flip:SetSize(w + grow, h + grow)
        -- Tinting a golden atlas needs it gray first.
        flip:SetDesaturated(r ~= nil)
        if r then
            flip:SetVertexColor(r, gg, b)
        else
            flip:SetVertexColor(1, 1, 1)
        end
        flip:Show()
        g.ring:Hide()
    else
        K.PlaceEdges(g.edges, g.ring, (spec.edge or 2) * px, r or GOLD[1], gg or GOLD[2], b or GOLD[3], 1)
        g.fade:SetToAlpha(spec.pulse and PULSE_LOW or 1)
        g.ring:Show()
        g.flip:Hide()
    end
end

-- Style and color of an entry's aura glows: per-spell choices first, then
-- the bar's (Build copies them to the record).
local function GlowSpec(rec, ov)
    local style = ov.glowStyle or rec.gStyle
    if not GLOW[style] then style = 1 end
    local hex = ov.glowColor
    if hex then return style, K.HexRGB(hex) end
    if rec.gTint then return style, rec.gR, rec.gG, rec.gB end
    return style
end

-- Stack glow, built in initializeFrame. A gate that clips its children,
-- as large as the widest glow around the button; an invisible StatusBar
-- that Blizzard fills with the aura's applications (SetApplicationBar,
-- maximum N); and the glow host centered on the fill's right edge. The bar
-- is N travels long and ends at the gate's center, so from N applications
-- on the fill edge sits on the center and the glow on the button, and each
-- missing application moves it one travel (more than the gate is wide) to
-- the left, out of the gate. The count stays in C: no Lua compares it.
local function NewStack(button, level)
    local gate = CreateFrame("Frame", nil, button)
    gate:SetPoint("CENTER", button, "CENTER", 0, 0)
    gate:SetFrameLevel(level)
    gate:SetClipsChildren(true)
    gate:Hide()
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetStatusBarTexture(STACK_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetAlpha(0)
    local host = CreateFrame("Frame", nil, gate)
    host:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    local glow = NewGlow(button, host, level)
    glow.frame:Show()
    return { gate = gate, bar = bar, host = host, glow = glow }
end

-- Gate, bar and host for threshold n and the button's size. The bar's
-- range is Blizzard's: every apply sets it to 0..maxApplications.
local function Placed(s, n, lk, cap) return s.n == n and s.cap == cap and s.w == lk.w and s.h == lk.h and s.px == lk.px end
local function PlaceStack(s, n, lk, cap)
    if Placed(s, n, lk, cap) then return end
    local w, h, px = lk.w, lk.h, lk.px
    s.n, s.cap, s.w, s.h, s.px = n, cap, w, h, px
    local grow = (REACH - 1) * min(w, h) + 2 * px
    local gw, gh = w + grow, h + grow
    local travel = max(gw, gh) + 2 * px
    s.gate:SetSize(gw, gh)
    s.host:SetSize(w, h)
    local bar = s.bar
    bar:SetSize(travel * cap, px)
    bar:ClearAllPoints()
    bar:SetPoint("LEFT", s.gate, "CENTER", -travel * n, 0)
end

-- Unknown kit sounds of aura entries (AddAuraSound takes files only): a
-- sensor in the button hears it show (aura gained) and hide (aura lost).
-- The sound, mute, quiet window, pairing and throttle are the alert
-- layer's; the container record is the hush gate of its sensors.
local function Heard(sensor, which)
    local part = sensed[sensor]
    local rec = part and part.rec
    if not rec then return end
    local k = part.pos
    local entry = rec.on[k] and rec.entry[k]
    -- Entries without a sound on the kit bar cost these reads only.
    local ov = entry and entry.ov
    if not ov or ov == EMPTY or not (ov.sound or ov.lossSound) then return end
    C.Alerts.PlayAura(entry.key, which, rec)
end
local function Gained(sensor) Heard(sensor, "gain") end
local function Lost(sensor) Heard(sensor, "loss") end

-- Container switches show or hide buttons without an aura changing:
-- that container's sensors stay silent for a moment.
local function Hush(rec)
    if rec.kit then C.Alerts.Hush(rec) end
end
-- Tainted code may touch sealed aura buttons only out of combat, while
-- auras are not secret and each button says so plainly.
local function Quiet()
    if IsCombatLocked() then return false end
    local secret = C_Secrets.ShouldAurasBeSecret()
    return Public(secret) and not secret
end
local function Open(button)
    local ok = button:CanBeAccessedInContext()
    return Public(ok) and ok == true
end
local function Mutable(rec)
    if not Quiet() then return false end
    local parts = rec.parts
    for i = 1, #parts do
        if not Open(parts[i].button) or not C.StackColors.Open(parts[i]) then
            return false
        end
    end
    return true
end

local function Text(fs, size, r, g, b, lk)
    S.SetStyledFont(fs, lk.font, size, lk.flags, lk.rendering, lk.shadow, lk.shadowOpacity, lk.shadowDistance)
    fs:SetTextColor(r, g, b)
end

-- The stacks a stack-filled bar marks: every stack below the maximum, or
-- the listed ones below it (each once, rising). One list per container,
-- refilled only when the look's markers or maximum changed.
local function MarkValues(rec, lk)
    local values = rec.markValues
    if not values then
        values = {}
        rec.markValues = values
    end
    if rec.mvMarks == lk.marks and rec.mvMax == lk.smax then return values end
    rec.mvMarks, rec.mvMax = lk.marks, lk.smax
    for i = #values, 1, -1 do values[i] = nil end
    local top = lk.smax - 1
    if lk.marks == "each" then
        for n = 1, top do values[n] = n end
        return values
    end
    local listed = {}
    for token in lk.marks:gmatch("%d+") do
        local n = tonumber(token)
        if n > 0 and n <= top then listed[n] = true end
    end
    for n = 1, top do
        if listed[n] then values[#values + 1] = n end
    end
    return values
end

-- Markers come from a per-button pool (made while the button accepts
-- writes, never freed): a new maximum or marker list places them again.
-- Sample rows are our own frames and take the pixel-layout policy.
local function PlaceMarkers(rec, part, lk, bar)
    local values = rec.stackFill and MarkValues(rec, lk) or NO_MARKS
    part.markerValues = values
    local markers = part.markers
    if not markers then
        markers = {}
        part.markers = markers
    end
    local host, px, bw = part.markerHost or bar, lk.px, lk.bw
    local width = lk.w - (lk.icon and lk.h or bw) - bw
    for i = 1, #values do
        local marker = markers[i]
        if not marker then
            marker = part.sample and S.CreateTexture(host, nil, "OVERLAY") or host:CreateTexture(nil, "OVERLAY")
            marker:SetColorTexture(0, 0, 0, .7)
            markers[i] = marker
        end
        marker:ClearAllPoints()
        marker:SetPoint("TOPLEFT", bar, "TOPLEFT", Snap(width * values[i] / lk.smax, px), 0)
        marker:SetSize(px, lk.h - 2 * bw)
        marker:Show()
    end
    for i = #values + 1, #markers do markers[i]:Hide() end
end

-- Every region of one button from rec.lk; idempotent (init and restyle).
local function Style(rec, part)
    local lk, b = rec.lk, part.button
    local bw, px = lk.bw, lk.px
    if not rec.fixed then b:SetSize(lk.w, lk.h) end
    K.PlaceEdges(part.edges, b, bw, lk.er, lk.eg, lk.eb, 1)
    local icon = part.icon
    icon:ClearAllPoints()
    if rec.role == "bar" then
        local left = lk.side == 1
        local inner = lk.h - 2 * bw
        local point = left and "TOPLEFT" or "TOPRIGHT"
        icon:SetPoint(point, b, point, left and bw or -bw, -bw)
        icon:SetSize(inner, inner)
        icon:SetShown(lk.icon)
        local lead = lk.icon and lk.h or bw
        local bg, bar = part.bg, part.bar
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", b, "TOPLEFT", bw, -bw)
        bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -bw, bw)
        bg:SetTexture(lk.tex)
        bg:SetVertexColor(lk.fr * .25, lk.fg * .25, lk.fb * .25, lk.bgA)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", b, "TOPLEFT", left and lead or bw, -bw)
        bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", left and -bw or -lead, bw)
        bar:SetStatusBarTexture(lk.tex)
        bar:SetStatusBarColor(lk.fr, lk.fg, lk.fb, 1)
        if rec.stackFill or part.markers then PlaceMarkers(rec, part, lk, bar) end
        -- The fill's range is its application bar's maximum: a bound button
        -- is rebound in place when the maximum changes.
        if rec.stackFill and part.bound and part.appMax ~= lk.smax then
            part.appMax = lk.smax
            barOpts.maxApplications = lk.smax
            b:SetApplicationBar(bar, barOpts)
        end
        local dur, name = part.dur, part.name
        if dur then
            Text(dur, lk.cs, lk.cr, lk.cg, lk.cb, lk)
            dur:ClearAllPoints()
            dur:SetPoint("RIGHT", bar, "RIGHT", -4 * px, 0)
            dur:SetJustifyH("RIGHT")
        end
        if name then
            Text(name, lk.cs, lk.cr, lk.cg, lk.cb, lk)
            name:ClearAllPoints()
            -- Room for the time text without anchoring to a sealed string.
            name:SetPoint("LEFT", bar, "LEFT", 4 * px, 0)
            name:SetPoint("RIGHT", bar, "RIGHT", dur and -floor(lk.cs * 2.6 + .5) or -4 * px, 0)
            name:SetJustifyH("LEFT")
            name:SetWordWrap(false)
        end
    else
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", bw, -bw)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -bw, bw)
        local cd = part.cd
        if rec.role == "over" then
            cd:SetSwipeColor(GOLD[1], GOLD[2], GOLD[3], .55)
            cd:SetDrawEdge(false)
        else
            cd:SetSwipeColor(0, 0, 0, lk.swipe)
            cd:SetDrawEdge(lk.edge)
        end
        local dur = part.dur
        if dur then
            Text(dur, lk.cs, lk.cr, lk.cg, lk.cb, lk)
            dur:ClearAllPoints()
            dur:SetPoint("CENTER", icon, "CENTER", 0, 0)
        end
    end
    icon:SetTexCoord(lk.l, lk.r, lk.t, lk.b)
    local count, pos = part.count, lk.sp
    local point, inset = K.POINTS[pos], px + bw
    Text(count, lk.ss, lk.sr, lk.sg, lk.sb, lk)
    count:ClearAllPoints()
    count:SetPoint(point, icon, point, K.POINT_X[pos] * inset, K.POINT_Y[pos] * inset)
    count:SetJustifyH(K.JUSTIFY[pos])
    if part.pan then K.PlaceEdges(part.panEdges, part.pan, max(2 * px, bw), PANDEMIC[1], PANDEMIC[2], PANDEMIC[3], 1) end
    b:SetMouseMotionEnabled(lk.tip)
end

-- Glow while active: shown and painted per entry.
local function ApplyGlow(rec, part, ov, dry)
    local g = part.glow
    local on = ov.auraGlow
    if on == nil then on = rec.glowAll end
    if on == true then
        local style, r, gg, b = GlowSpec(rec, ov)
        if part.gOn and Painted(g, style, r, gg, b, rec.lk) then return false end
        if dry then return true end
        PaintGlow(g, style, r, gg, b, rec.lk)
        if not part.gOn then
            part.gOn = true
            g.frame:Show()
        end
    elseif part.gOn then
        if dry then return true end
        part.gOn = false
        g.frame:Hide()
    end
    return false
end

-- Stack glow from N applications: gate shown, bar and glow placed for N.
-- A bound bar is rebound when N changes (a setter replaces its element).
local function ApplyStack(rec, part, ov, dry)
    local s = part.stack
    local n = ov.stackGlow
    if type(n) ~= "number" or n < 1 then
        n = 0
    else
        n = floor(n)
    end
    if n == 0 then
        if not s.on then return false end
        if dry then return true end
        s.on = false
        s.gate:Hide()
        return false
    end
    local lk = rec.lk
    -- Equal uses one extra native range step: counts above N move the
    -- glow beyond the right clip edge instead of clamping at the center.
    local op = ov.stackGlowOp or 1
    if op == 3 then n = n + 1 end
    local cap = op == 2 and n + 1 or n
    local style, r, gg, b = GlowSpec(rec, ov)
    if s.on and Placed(s, n, lk, cap) and Painted(s.glow, style, r, gg, b, lk) and (s.bound == cap or not part.bound) then return false end
    if dry then return true end
    PlaceStack(s, n, lk, cap)
    PaintGlow(s.glow, style, r, gg, b, lk)
    if part.bound and s.bound ~= cap then
        s.bound = cap
        barOpts.maxApplications = cap
        part.button:SetApplicationBar(s.bar, barOpts)
    end
    if not s.on then
        s.on = true
        s.gate:Show()
    end
    return false
end

-- Text on top: the two text frames trade levels (both stay above the glows).
local function Layer(part, top)
    local stacks, texts = part.stackFrame, part.timeFrame
    local a, b = stacks:GetFrameLevel(), texts:GetFrameLevel()
    if a > b then a, b = b, a end
    if top then
        stacks:SetFrameLevel(b)
        texts:SetFrameLevel(a)
    else
        stacks:SetFrameLevel(a)
        texts:SetFrameLevel(b)
    end
end

-- Per-spell choices on one button: swipe mode, glows, stack text (shown,
-- color), countdown (shown, warning threshold) and which is on top. With
-- dry set it only reports whether a write is needed. Unbound
-- (initializeFrame) it prepares what the binding takes. Hidden text is
-- never bound: a bound one is cleared, then hidden by hand.
local function ApplyEntry(rec, part, entry, dry)
    if C.StackColors.Apply(rec, part, entry, dry) then return true end
    local ov = entry.ov or EMPTY
    local cd = part.cd
    if cd and rec.role == "icon" then
        local mode = ov.swipe or 1
        if part.swipe ~= mode then
            if dry then return true end
            part.swipe = mode
            -- 1 normal (aura swipes run reversed), 2 flipped, 3 hidden.
            cd:SetReverse(mode ~= 2)
            cd:SetDrawSwipe(mode ~= 3)
        end
    end
    if part.glow and ApplyGlow(rec, part, ov, dry) then return true end
    if part.glow and ApplyCombatGate(part.glow, part.gOn, dry) then return true end
    if part.stack and ApplyStack(rec, part, ov, dry) then return true end
    if part.stack and ApplyCombatGate(part.stack.glow, part.stack.on, dry) then return true end
    local b = part.button
    local stacks = K.Choice(ov.stackText, rec.stackBar)
    local count = stacks and CountOpts(ov) or nil
    if part.countOn ~= stacks or part.countOpts ~= count then
        if dry then return true end
        local was = part.countOn
        part.countOn, part.countOpts = stacks, count
        if not stacks then
            if part.bound and was then b:ClearApplicationCount() end
            part.count:Hide()
        else
            if was == false then part.count:Show() end
            if part.bound then b:SetApplicationCount(part.count, count) end
        end
    end
    local dur = part.dur
    if dur then
        local shown = K.Choice(ov.timeText, rec.timeBar)
        if part.durOn ~= shown then
            if dry then return true end
            local was = part.durOn
            part.durOn = shown
            if not shown then
                if part.bound and was then b:ClearDurationText() end
                part.textOpts = nil
                dur:Hide()
            elseif was == false then
                dur:Show()
            end
        end
        if shown and part.bound then
            local opts = TextOpts(ov.threshold or C.state.threshold)
            if part.textOpts ~= opts then
                if dry then return true end
                part.textOpts = opts
                b:SetDurationText(dur, opts)
            end
        end
    end
    local top = K.Choice(ov.textTop, rec.topBar)
    if part.top ~= top then
        if dry then return true end
        part.top = top
        Layer(part, top)
    end
    return false
end

-- Every region of a new button, as its descendants, in our own part record.
local function NewPart(rec, button, k)
    local part = { button = button, pos = k, rec = rec }
    part.edges = Edges(button)
    part.icon = button:CreateTexture(nil, "ARTWORK")
    -- Every layer at its own level above the button. Bars (K.AURA_LEVEL):
    -- fill, stack colour (StackColors), markers, glows, countdown and name,
    -- stacks. Icons and overlays (K.AURA_ICON_LEVEL): swipe, glows,
    -- countdown, stacks.
    local base = button:GetFrameLevel()
    local LEVEL = rec.role == "bar" and BAR_LEVEL or ICON_LEVEL
    local lower
    if rec.role == "bar" then
        part.bg = button:CreateTexture(nil, "BACKGROUND")
        lower = CreateFrame("StatusBar", nil, button)
        lower:SetMinMaxValues(0, 1)
        lower:SetValue(0)
        part.bar = lower
        -- Stack markers sit above the threshold colour (Style places them
        -- from a pool; the look says which).
        if rec.stackFill and rec.color then
            local markerHost = CreateFrame("Frame", nil, button)
            markerHost:SetFrameLevel(base + LEVEL.marks)
            part.markerHost = markerHost
        end
    else
        lower = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        lower:SetAllPoints(part.icon)
        lower:SetDrawBling(false)
        lower:SetHideCountdownNumbers(true)
        lower:SetReverse(true)
        part.cd = lower
    end
    lower:SetFrameLevel(base + LEVEL.fill)
    -- Glows over the icon, fill, colour and markers; text above the glows.
    local level = base + LEVEL.glow
    if rec.pandemic then
        local pan = CreateFrame("Frame", nil, button)
        pan:SetAllPoints(button)
        pan:SetFrameLevel(level)
        pan:Hide()
        part.pan, part.panEdges = pan, Edges(pan)
    end
    if rec.glow then part.glow = NewGlow(button, button, level) end
    if rec.stack then part.stack = NewStack(button, level) end
    -- Stacks and countdown (with the name) on two frames above the glows,
    -- stacks on top until the entry's Text on top says otherwise.
    local stacks = CreateFrame("Frame", nil, button)
    stacks:SetAllPoints(button)
    stacks:SetFrameLevel(base + LEVEL.stacks)
    local texts = CreateFrame("Frame", nil, button)
    texts:SetAllPoints(button)
    texts:SetFrameLevel(base + LEVEL.text)
    part.stackFrame, part.timeFrame, part.top = stacks, texts, true
    part.count = stacks:CreateFontString(nil, "OVERLAY")
    if rec.text then part.dur = texts:CreateFontString(nil, "OVERLAY") end
    if rec.name then part.name = texts:CreateFontString(nil, "OVERLAY") end
    if rec.kit then
        -- A new button hides once it is set up: not an aura leaving.
        Hush(rec)
        local sensor = CreateFrame("Frame", nil, button)
        sensor:SetAllPoints(button)
        sensed[sensor] = part
        sensor:SetScript("OnShow", Gained)
        sensor:SetScript("OnHide", Lost)
    end
    return part
end

-- A stack glow's application bar on its button, at the glow's threshold
-- range (PlaceStack; the native button has one application-bar binding).
local function BindStack(button, stack)
    stack.bound = stack.cap or 1
    barOpts.maxApplications = stack.bound
    button:SetApplicationBar(stack.bar, barOpts)
end

-- Hands the styled regions to the button; bound regions are sealed.
local function Bind(rec, part, k)
    local button = part.button
    button:SetIcon(part.icon)
    if part.cd then button:SetDurationCooldown(part.cd) end
    if part.bar then
        if rec.stackFill then
            part.appMax = rec.lk.smax
            barOpts.maxApplications = part.appMax
            button:SetApplicationBar(part.bar, barOpts)
        else
            button:SetDurationBar(part.bar, BAR_OPTS[rec.fill])
        end
    end
    if part.dur and part.durOn then
        local opts = rec.topts[k] or TEXT_DEFAULT
        button:SetDurationText(part.dur, opts)
        part.textOpts = opts
    end
    if part.name then button:SetSpellName(part.name) end
    -- Without a formatter Blizzard shows stacks above 1 only; the per-spell
    -- stack color passes a shared formatter (CountOpts).
    if part.countOn then button:SetApplicationCount(part.count, part.countOpts) end
    if part.stack then BindStack(button, part.stack) end
    -- 12.1.5 and Forever return nothing here; the result is never used.
    if part.pan then button:AddPandemicRegion(part.pan) end
    part.bound = true
end

-- initializeFrame: runs once per button from Blizzard's frame provider
-- (possibly in combat when a group's pool grows). Builds and styles every
-- region as a descendant of the button, binds last (bound regions are
-- sealed), and keeps our state in our own table, never on the button.
local function Init(rec, button, k)
    local part = NewPart(rec, button, k)
    button:SetMouseClickEnabled(false)
    button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT")
    -- Slots are outside the flow layout: they follow their cell or icon.
    if rec.fixed then
        button:ClearAllPoints()
        button:SetAllPoints(rec.anchors[k])
    end
    Style(rec, part)
    ApplyEntry(rec, part, rec.entry[k] or NO_ENTRY, false)
    Bind(rec, part, k)
    local parts = rec.parts
    parts[#parts + 1] = part
end

-- Private drawing primitives reused by the native action-bar aura bridge.
-- The button of a bridge container (a stack sensor of a stack-filled bar,
-- an action-bar glow) covers its target and takes no mouse.
local function Overlay(button, target)
    button:SetAllPoints(target)
    button:SetMouseClickEnabled(false)
    button:SetMouseMotionEnabled(false)
end
-- A bridge button's stack glow: regions placed for ov, bound, then gated.
local function BridgeStack(rec, part, ov, level)
    part.stack = NewStack(part.button, level)
    ApplyStack(rec, part, ov, false)
    BindStack(part.button, part.stack)
    ApplyCombatGate(part.stack.glow, part.stack.on, false)
    part.bound = true
end

B.Bridge = { NewGlow = NewGlow, ApplyStack = ApplyStack, ApplyGlow = ApplyGlow, ApplyCombatGate = ApplyCombatGate,
    Overlay = Overlay, BridgeStack = BridgeStack }

B.TextOpts, B.Look, B.Hush, B.Quiet, B.Mutable = TextOpts, Look, Hush, Quiet, Mutable
B.Style, B.ApplyEntry, B.Init = Style, ApplyEntry, Init
