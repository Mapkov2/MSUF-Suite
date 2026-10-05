local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Glows inside Blizzard's aura buttons: the glow while an aura is active,
-- the stack glow that an application bar Blizzard fills places (no Lua
-- reads a count), and the native combat gate behind "All glows only in
-- combat". The aura buttons (AuraButtons.lua), their stack sensors
-- (StackColors.lua) and the action-bar bridge (ActionGlows.lua) build and
-- style them through this file; the loops run in C and are styled by
-- widget writes only.
local K = C.Const
local STACK_OP = K.STACK_OP
local AuraGlows = {}
C.AuraGlows = AuraGlows

-- Regions inside Blizzard's aura buttons are created with the client's
-- CreateFrame (see AuraButtons.lua).
local CreateFrame = CreateFrame
local IsCombatLocked = NS.IsCombatLocked
local floor, max, min = math.floor, math.max, math.min
local type, pairs, ipairs, next = type, pairs, ipairs, next
local GOLD = K.GLOW_GOLD
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
local STACK_TEXTURE = K.WHITE
local barOpts = {} -- SetApplicationBar options (Blizzard copies them)

------------------------------------------------------------------ edges
-- Four OVERLAY textures on a region inside an aura button (the client's
-- CreateTexture: no pixel-layout policy on what Blizzard positions).
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
        combatGate = combatGate, combatOnly = false, button = button }
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
-- state driver manager re-reads every driver on each pass, so only a glow
-- that can show (on: its entry uses it) holds one. g.combatOnly is what is
-- registered now. Registering or unregistering a state driver is protected,
-- and the gate is a descendant of a sealed aura button, which refuses
-- tainted Lua while auras are secret, also out of combat (an M+ key, a PvP
-- match; DenyTaintedAccessWhenAurasAreSecret). Under lockdown or while the
-- button refuses access the wish waits in parkedGates for FlushGates.
local parkedGates = {}
local function Writable(g)
    if IsCombatLocked() then return false end
    local ok = g.button:CanBeAccessedInContext()
    return S.Public(ok) and ok == true
end
local function Gate(g, wanted)
    if g.combatOnly == wanted then
        parkedGates[g] = nil
        return
    end
    if not Writable(g) then
        parkedGates[g] = wanted
        return
    end
    parkedGates[g] = nil
    g.combatOnly = wanted
    if wanted then
        RegisterStateDriver(g.combatGate, "visibility", "[combat] show; hide")
    else
        UnregisterStateDriver(g.combatGate, "visibility")
        g.combatGate:Show()
    end
end
local function ApplyCombatGate(g, on, dry)
    local wanted = on == true and C.state.allGlowsCombat == true and not C.state.preview
    if dry then return g.combatOnly ~= wanted end
    Gate(g, wanted)
    return false
end

-- A retired container's glows hold no state driver (parked under lockdown).
function AuraGlows.ReleaseGlows(rec)
    for _, part in ipairs(rec.parts) do
        for i = 1, 3 do
            local g
            if i == 1 then
                g = part.glow
            elseif i == 2 then
                g = part.stack and part.stack.glow
            else
                g = part.stackSensor and part.stackSensor.part.stack.glow
            end
            if g then Gate(g, false) end
        end
    end
end

-- Combat or the restriction ended (or the module let go): every parked wish
-- is applied, or stays parked while the buttons still refuse.
function AuraGlows.FlushGates()
    if IsCombatLocked() then return end
    for g, wanted in pairs(parkedGates) do Gate(g, wanted) end
end
function AuraGlows.HasParkedGates() return next(parkedGates) ~= nil end

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
    return K.GlowSpec(ov, rec.gStyle, rec.gTint, rec.gR, rec.gG, rec.gB)
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
    local op = ov.stackGlowOp
    if op == STACK_OP.MORE_THAN then n = n + 1 end
    local cap = op == STACK_OP.EXACTLY and n + 1 or n
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

-- A stack glow's application bar on its button, at the glow's threshold
-- range (PlaceStack; the native button has one application-bar binding).
local function BindStack(button, stack)
    stack.bound = stack.cap or 1
    barOpts.maxApplications = stack.bound
    button:SetApplicationBar(stack.bar, barOpts)
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

AuraGlows.Edges, AuraGlows.NewGlow, AuraGlows.NewStack = Edges, NewGlow, NewStack
AuraGlows.ApplyGlow, AuraGlows.ApplyStack, AuraGlows.ApplyCombatGate = ApplyGlow, ApplyStack, ApplyCombatGate
AuraGlows.BindStack, AuraGlows.Overlay, AuraGlows.BridgeStack = BindStack, Overlay, BridgeStack
