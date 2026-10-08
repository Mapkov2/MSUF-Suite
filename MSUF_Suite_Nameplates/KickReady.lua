local _, private = ...
local NS, S = private.NS, private.Suite
local Style = NS.NameplateStyle
local LOOK_BLIZZARD, HIDE = private.Mode.LOOK_BLIZZARD, private.Mode.HIDE
local Public, Finite = S.Public, S.Finite
-- MSUF's interrupt-ready indicator on enemy nameplate castbars, drawn the way
-- MSUF's own castbars draw it. MSUF owns all of it: the switch (Castbars >
-- Interrupt Ready Indicator > Show on enemy nameplates), the style (castbar
-- border, color box, unavailable cast fill), colors, size, placement, the
-- time marker and shade, and the engine (HostBridge.KickReady: Classic MSUF's
-- MSUF.KickReady, nil on other hosts). The engine resolves the player's
-- interrupts, composes both slots, keeps its cooldown event and native wake
-- frames armed while a plate shows readiness, and calls back when readiness,
-- a cooldown's end or MSUF's settings changed. This file only decorates
-- Blizzard's castbar; nothing is created while the switch is off. Restricted
-- readiness, interruptibility and times reach native sinks only
-- (SetVertexColor[FromBoolean], SetAlphaFromBoolean, StatusBar values).
local Kick = {}
private.KickReady = Kick
local M, RepaintCasts
local OWNER = "MSUF_Suite_Nameplates"
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- The cast events that report interruptibility themselves, with their value.
local INTERRUPTIBLE_EVENTS = { UNIT_SPELLCAST_INTERRUPTIBLE = false, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true }
-- MSUF's box anchors (ApplyBoxLayout): the box's side that meets the castbar.
local BOX_SIDE = { RIGHT = "LEFT", LEFT = "RIGHT", TOP = "BOTTOM", BOTTOM = "TOP" }
local showingCount = 0
-- registered: the engine knows this module; shown: MSUF's nameplate switch.
local registered, shown = false, false

-- repaint: the skin's pass over the castbars of its shown plates.
function Kick.Bind(module, repaint) M, RepaintCasts = module, repaint end

local function Safe(region)
    return region and not NS.Safety.IsForbidden(region)
end

-- The running cast of `unit` into state: kind ("cast", "channel", "empower"
-- or nil), its duration (nil when restricted) and notInterruptible (plain,
-- restricted, or nil). A duration getter returns nothing without that kind
-- of cast and may return a restricted object (UnitDocumentation).
local function ReadCast(state, unit)
    local duration = UnitCastingDuration(unit)
    if not Public(duration) or duration ~= nil then
        state.kind = "cast"
        state.raw = select(8, UnitCastingInfo(unit))
    else
        duration = UnitChannelDuration(unit)
        if Public(duration) and duration == nil then
            state.kind, state.duration, state.raw = nil, nil, nil
            return
        end
        local _, _, _, _, _, _, notInterruptible, _, isEmpowered = UnitChannelInfo(unit)
        state.kind, state.raw = "channel", notInterruptible
        -- isEmpowered is NeverSecret; an empowered cast fills like a cast and
        -- its own duration includes the hold at the top stage.
        if Public(isEmpowered) and isEmpowered == true then
            state.kind = "empower"
            duration = UnitEmpoweredChannelDuration(unit)
        end
    end
    if not Public(duration) then duration = nil end
    state.duration = duration
end

local function HideProjection(projection)
    if not projection.shown then return end
    projection.shown = false
    projection.bar:Hide()
    projection.marker:Hide()
    projection.segment:Hide()
end

local function HideBorder(state)
    local border = state.border
    if border then for i = 1, 4 do border.edges[i]:Hide() end end
end

local function HideVisuals(state)
    if state.fill then state.fill:Hide() end
    if state.box then state.box:Hide() end
    HideBorder(state)
    local list = state.projections
    if list then for i = 1, #list do HideProjection(list[i]) end end
end

-- The engine keeps its cooldown event and wakes armed while a plate shows.
local function SetShowing(state, showing)
    if state.showing == showing then return end
    state.showing = showing
    showingCount = showingCount + (showing and 1 or -1)
    if registered then NS.HostBridge.KickReady().SetActive(OWNER, showingCount > 0) end
end

-- MSUF's unavailable cast fill: MSUF's castbar texture over Blizzard's fill,
-- in MSUF's cast colors, created on first use.
local function PaintFill(cast, state, engine, look, notInterruptible)
    local target = cast:GetStatusBarTexture()
    if not Safe(target) then return end
    local fill = state.fill
    if not fill then
        fill = cast:CreateTexture(nil, "ARTWORK", nil, 3)
        state.fill = fill
    end
    if state.fillTexture ~= look.texture then
        fill:SetTexture(look.texture)
        state.fillTexture = look.texture
    end
    if state.fillTarget ~= target then
        fill:ClearAllPoints()
        fill:SetAllPoints(target)
        state.fillTarget = target
    end
    -- MSUF_CastbarUtils.lua's tint: not interruptible, else the cast color
    -- while an interrupt is ready and the unavailable color while none is.
    local castColor, nonColor, unavailableColor = engine.FillColors()
    local active = castColor
    if engine.SlotCount() > 0 then active = engine.SelectColor(castColor, unavailableColor) end
    fill:SetVertexColorFromBoolean(notInterruptible, nonColor, active)
    fill:Show()
end

-- MSUF's castbar border: white edges as wide as MSUF's castbar outline,
-- snapped to whole screen pixels at the castbar's scale as MSUF snaps its own
-- (MSUF_CastbarStyle.lua PixelSize; PixelUtil.GetNearestPixelSize is that rule).
local function PaintBorder(cast, state, engine, look, raw)
    local border = state.border
    if not border then
        border = Style.CreateBorder(cast)
        state.border = border
    end
    local scale = cast:GetEffectiveScale()
    local width = look.outline
    if Finite(scale) and scale > 0 then width = PixelUtil.GetNearestPixelSize(width, scale, 1) end
    Style.PaintBorder(border, cast, width, "ffffff")
    local r, g, b, a = engine.RGBA(raw)
    for i = 1, 4 do border.edges[i]:SetVertexColor(r, g, b, a) end
end

-- MSUF's color box (ApplyBoxLayout): the castbar's height or its own size,
-- 8..80, beside the castbar at MSUF's anchor and offsets.
local function PaintBox(cast, state, engine, look, raw, rawSecret)
    local box = state.box
    if not box then
        box = cast:CreateTexture(nil, "OVERLAY", nil, 7)
        box:SetTexture(WHITE)
        state.box = box
    end
    local size = look.boxSize
    if size <= 0 then
        size = cast:GetHeight()
        if not Finite(size) then size = 16 end
    end
    size = math.max(8, math.min(size, 80))
    local anchor, x, y = look.boxAnchor, look.boxOffsetX, look.boxOffsetY
    if state.boxSize ~= size or state.boxAnchor ~= anchor or state.boxX ~= x or state.boxY ~= y then
        state.boxSize, state.boxAnchor, state.boxX, state.boxY = size, anchor, x, y
        box:SetSize(size, size)
        box:ClearAllPoints()
        box:SetPoint(BOX_SIDE[anchor] or anchor, cast, anchor, x, y)
    end
    box:SetVertexColor(engine.RGBA(raw))
    -- A restricted uninterruptible cast hides the box natively.
    if rawSecret then box:SetAlphaFromBoolean(raw, 0, 1) else box:SetAlpha(1) end
    box:Show()
end

-- An invisible native bar spans the cast; its fill edge is where the
-- interrupt recovers, so no restricted time is compared in Lua. The marker
-- sits on that edge (a mask keeps a recovery after the cast off the bar)
-- and the shade covers the cast left after it.
local function Projection(cast, state, index)
    local list = state.projections
    if not list then
        list = {}
        state.projections = list
    end
    local projection = list[index]
    if projection then return projection end
    if not state.clip then
        state.clip = cast:CreateMaskTexture(nil, "ARTWORK")
        state.clip:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        state.clip:SetAllPoints(cast)
    end
    local bar = CreateFrame("StatusBar", nil, cast)
    bar:SetAllPoints(cast)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:Hide()
    local marker = cast:CreateTexture(nil, "ARTWORK", nil, 7)
    marker:SetWidth(2)
    marker:AddMaskTexture(state.clip)
    marker:Hide()
    local segment = cast:CreateTexture(nil, "ARTWORK", nil, 6)
    segment:Hide()
    projection = { bar = bar, marker = marker, segment = segment, shown = false }
    list[index] = projection
    return projection
end

-- A draining channel runs from the far side: its projection fills reversed.
local function PlaceProjection(projection, reverse)
    if projection.reverse == reverse then return end
    projection.reverse = reverse
    local bar, marker, segment = projection.bar, projection.marker, projection.segment
    bar:SetReverseFill(reverse)
    local edge = bar:GetStatusBarTexture()
    marker:ClearAllPoints()
    segment:ClearAllPoints()
    if reverse then
        marker:SetPoint("TOPRIGHT", edge, "TOPLEFT", 0, 0)
        marker:SetPoint("BOTTOMRIGHT", edge, "BOTTOMLEFT", 0, 0)
        segment:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        segment:SetPoint("BOTTOMRIGHT", edge, "BOTTOMLEFT", 0, 0)
    else
        marker:SetPoint("TOPLEFT", edge, "TOPRIGHT", 0, 0)
        marker:SetPoint("BOTTOMLEFT", edge, "BOTTOMRIGHT", 0, 0)
        segment:SetPoint("TOPLEFT", edge, "TOPRIGHT", 0, 0)
        segment:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    end
end

-- MSUF's marker and shade (RefreshTimeProjection): the ready color, the
-- shade at a quarter of its alpha.
local function PaintProjection(projection, look, notInterruptible, rawSecret)
    local marker, segment = projection.marker, projection.segment
    local r, g, b, a = look.readyR, look.readyG, look.readyB, look.readyA
    if projection.r ~= r or projection.g ~= g or projection.b ~= b or projection.a ~= a then
        projection.r, projection.g, projection.b, projection.a = r, g, b, a
        marker:SetColorTexture(r, g, b, a)
        segment:SetColorTexture(r, g, b, .25 * a)
    end
    if rawSecret then
        -- A restricted uninterruptible cast hides both natively.
        marker:SetAlphaFromBoolean(notInterruptible, 0, 1)
        segment:SetAlphaFromBoolean(notInterruptible, 0, 1)
        projection.restricted = true
    elseif projection.restricted then
        marker:SetAlpha(1)
        segment:SetAlpha(1)
        projection.restricted = false
    end
    projection.shown = true
    projection.bar:Show()
    marker:SetShown(look.marker)
    segment:SetShown(look.segment)
end

local function PaintProjections(cast, state, engine, look, showing, notInterruptible, rawSecret)
    local duration = state.duration
    local count = showing and (look.marker or look.segment) and duration and engine.SlotCount() or 0
    local list = state.projections
    if count > 0 then
        local startTime, endTime = duration:GetStartTime(), duration:GetEndTime()
        local reverse = state.kind == "channel"
        for index = 1, count do
            local cooldown = engine.Cooldown(index)
            if cooldown then
                local projection = Projection(cast, state, index)
                PlaceProjection(projection, reverse)
                projection.bar:SetMinMaxValues(startTime, endTime)
                projection.bar:SetValue(cooldown:GetEndTime())
                PaintProjection(projection, look, notInterruptible, rawSecret)
            elseif list and list[index] then
                HideProjection(list[index])
            end
        end
        list = state.projections
    end
    if list then for index = count + 1, #list do HideProjection(list[index]) end end
end

-- Paints one castbar from its cast state in MSUF's look. Border, box and
-- marker show readiness on an interruptible cast; the fill style colors
-- every cast like MSUF's castbars, an uninterruptible one included.
local function Apply(cast, state, engine, look)
    local raw = state.raw
    local rawSecret = not Public(raw)
    local casting = state.kind ~= nil
    local showing = casting and engine.SlotCount() > 0 and (rawSecret or raw ~= true)
    SetShowing(state, showing)
    -- Interruptibility as the boolean the native sinks take.
    local notInterruptible = false
    if rawSecret then
        notInterruptible = raw
    elseif raw == true then
        notInterruptible = true
    end
    local style = look.style
    if casting and style == "fill" then
        PaintFill(cast, state, engine, look, notInterruptible)
    elseif state.fill then
        state.fill:Hide()
    end
    if showing and style == "border" and look.outline > 0 then
        PaintBorder(cast, state, engine, look, raw)
    else
        HideBorder(state)
    end
    if showing and style == "box" then
        PaintBox(cast, state, engine, look, raw, rawSecret)
    elseif state.box then
        state.box:Hide()
    end
    PaintProjections(cast, state, engine, look, showing, notInterruptible, rawSecret)
end

function Kick.Restore(cast)
    local state = cast and M.kicks[cast]
    if not state then return end
    state.unit, state.kind, state.duration, state.raw = nil, nil, nil, nil
    SetShowing(state, false)
    HideVisuals(state)
end

local function RestoreAll()
    for cast in pairs(M.kicks) do Kick.Restore(cast) end
end

-- The skin's paint pass: readiness on enemy castbars while MSUF's switch is
-- on. Turning it off restored every castbar, so the off state costs one test.
function Kick.Paint(cast, prefix, unit)
    if not shown or not Safe(cast) then return end
    local c = M.config
    if not unit or prefix ~= "enemy" or c.look == LOOK_BLIZZARD or not c.enemy
        or c.enemyCastEnabled == HIDE then
        Kick.Restore(cast)
        return
    end
    local state = M.kicks[cast]
    if not state then
        state = { showing = false }
        M.kicks[cast] = state
    end
    if state.unit ~= unit then
        state.unit = unit
        ReadCast(state, unit)
    end
    local engine = NS.HostBridge.KickReady()
    Apply(cast, state, engine, engine.Look())
end

-- A cast event of the plate's unit: re-read the cast, then repaint. The
-- interruptibility events carry their plain answer.
function Kick.OnCast(cast, unit, event)
    local state = shown and M.kicks[cast]
    if not state or state.unit ~= unit then return end
    ReadCast(state, unit)
    local raw = INTERRUPTIBLE_EVENTS[event]
    if raw ~= nil and state.kind then state.raw = raw end
    local engine = NS.HostBridge.KickReady()
    Apply(cast, state, engine, engine.Look())
end

-- The engine's calls: readiness or a cooldown's end moved (plates that show
-- readiness repaint; a moved end matters only to the marker and shade), or
-- MSUF's settings were applied (the switch and the look are read again).
local function OnEngineChange(reason)
    local engine = NS.HostBridge.KickReady()
    local look = engine.Look()
    if reason == "settings" then
        shown = look.show == true
        if shown then RepaintCasts() else RestoreAll() end
        return
    end
    if reason == "projection" and not (look.marker or look.segment) then return end
    for cast, state in pairs(M.kicks) do
        if state.showing then Apply(cast, state, engine, look) end
    end
end

-- Registered with the engine while the module runs; MSUF's switch decides
-- whether anything shows. Settings apply outside combat.
function Kick.Configure()
    local engine = M.active == true and NS.HostBridge.KickReady() or nil
    if engine and not registered then
        registered = true
        engine.Register(OWNER, OnEngineChange)
    elseif not engine and registered then
        registered = false
        NS.HostBridge.KickReady().Unregister(OWNER)
    end
    local nextShown = engine ~= nil and engine.Look().show == true
    if shown and not nextShown then RestoreAll() end
    shown = nextShown
end

function Kick.Disable()
    RestoreAll()
    shown = false
    if not registered then return end
    registered = false
    NS.HostBridge.KickReady().Unregister(OWNER)
end
