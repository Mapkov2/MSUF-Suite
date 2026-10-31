local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Addon-owned stand-ins on aura bar cells: the sample rows the options
-- page and MSUF Edit Mode draw, and the dimmed icons of missing buffs.
local K, AuraButtons = C.Const, C.AuraButtons
local floor, max = math.floor, math.max
local EMPTY, QUESTION = C.EMPTY, K.QUESTION_ICON
local STACK_COLOR = NS.CDM.SPELL_DEFAULTS.stackColor
local Px = K.Px
local holders = {} -- addon-owned samples and missing-aura placeholders per cell

-- A plain, reusable sample shares the live bar's style. It never binds a
-- unit, reads aura state, or writes an entry; menu and Edit Mode use it alike.
function AuraButtons.Sample(parent, row, view, ov, texture, name)
    if not row then
        row = S.CreateFrame("Frame", nil, parent)
        row.rec = { role = "bar", lk = {} }
        local times = S.CreateFrame("Frame", nil, row)
        local stacks = S.CreateFrame("Frame", nil, row)
        times:SetAllPoints(row)
        stacks:SetAllPoints(row)
        local part = { button = row, edges = {}, sample = true,
            timeFrame = times, stackFrame = stacks,
            icon = S.CreateTexture(row, nil, "ARTWORK"), bg = S.CreateTexture(row, nil, "BACKGROUND"),
            bar = S.CreateFrame("StatusBar", nil, row),
            name = S.CreateFontString(times, nil, "OVERLAY"), dur = S.CreateFontString(times, nil, "OVERLAY"),
            count = S.CreateFontString(stacks, nil, "OVERLAY") }
        for i = 1, 4 do part.edges[i] = S.CreateTexture(row, nil, "OVERLAY") end
        part.bar:SetFrameLevel(row:GetFrameLevel())
        row.part = part
        row.name, row.icon, row.bg, row.fill = part.name, part.icon, part.bg, part.bar
    end
    ov = ov or EMPTY
    local px = Px()
    if row.sampleView == view and row.sampleStyle == view.styleGen and row.sampleBehavior == view.behaviorGen
        and row.sampleOv == ov and row.sampleTexture == texture and row.sampleName == name and row.samplePx == px then return row end
    row.sampleView, row.sampleStyle, row.sampleBehavior = view, view.styleGen, view.behaviorGen
    row.sampleOv, row.sampleTexture, row.sampleName = ov, texture, name
    row.samplePx = px
    local rec, part = row.rec, row.part
    rec.stackFill, rec.view = view.barStacks == true, view
    -- The live buttons' look and markers (AuraButtons Look and Style).
    AuraButtons.Look(rec, view)
    AuraButtons.Style(rec, part)
    -- The entry's own border and fill, as on its live button.
    C.AuraLooks.Apply(rec, part, ov, false)
    local stackMax = rec.lk.smax
    local amount = max(1, floor(stackMax * .6))
    part.bar:SetMinMaxValues(0, rec.stackFill and stackMax or 1)
    part.bar:SetValue(rec.stackFill and amount or (view.barFill == K.BAR_FILL.FILL and .4 or .6))
    if rec.stackFill and (view.barStackColorAt or 0) > 0 and amount >= view.barStackColorAt then
        part.bar:SetStatusBarColor(K.HexRGB(view.barStackColor or "ff6633"))
    end
    part.icon:SetTexture(texture or QUESTION)
    part.name:SetText(name or "")
    part.name:SetShown(view.barName ~= false)
    -- The sample's 8 seconds in the countdown's stages (K.Countdown).
    local state = C.state
    part.dur:SetText((state.tenths or 0) > 8 and "8.0" or "8")
    part.dur:SetShown(K.Choice(ov.timeText, K.BarTime(view)))
    local threshold = ov.threshold
    if threshold == nil then threshold = state.threshold or 0 end
    if threshold > 8 then part.dur:SetTextColor(state.thR or 1, state.thG or 1, state.thB or 1) end
    if (state.urgent or 0) > 8 then part.dur:SetTextColor(state.urR or 1, state.urG or 1, state.urB or 1) end
    part.count:SetText(amount > 1 and tostring(amount) or "")
    part.count:SetShown(K.Choice(ov.stackText, K.BarStacks(view, false)))
    if (ov.stackColorAt or 0) > 0 and amount >= ov.stackColorAt then
        local hex = ov.stackColor
        part.count:SetTextColor(K.HexRGB(hex ~= nil and hex ~= "" and hex or STACK_COLOR))
    end
    local level = row:GetFrameLevel()
    local top = K.Choice(ov.textTop, K.BarStacksTop(view))
    part.stackFrame:SetFrameLevel(level + (top and 3 or 2))
    part.timeFrame:SetFrameLevel(level + (top and 2 or 3))
    return row
end

------------------------------------------------------------------ placeholders
-- Addon-owned regions on the cell, under the slot button: a dimmed icon
-- for missing buffs (showMissing) and the sample icon in the preview. The
-- bar's icon skin (barMeta.skinLook) frames the dimmed icon as on the live
-- buttons, from its own frame over the cell (SkinHeld), so showing or hiding
-- a stand-in, also in combat (a buff that drops, the preview's end), shows or
-- hides that frame and asks MSUF nothing.
--
-- The rule is static (settings only): a fixed slot clips its skin to its icon
-- exactly while its stand-in is held (AuraButtons.Held, AuraButtons.lua's
-- Clipped), and the held stand-in draws the skin around its icon, so the
-- shadow and frame outside the slot's icon are drawn once. Documented limit
-- (owner, 2026-10-18): a skin, border or showMissing change while auras are
-- secret (M+, PvP: sealed slots that restyle when auras open) shows the new
-- outer skin around the old inner skin until then. Second documented limit
-- (owner, 2026-10-18): where two live surfaces overlap in one cell without a
-- held stand-in (a running summon or manual timer row over its own active
-- aura's slot; a both entry's player and target slots with both auras up),
-- each draws its whole skin, so translucent layers (the soft shadow) darken
-- there; opaque frame layers look the same, in and out of combat alike.
local function HideSkin(h)
    if h.skinFrame then h.skinFrame:Hide() end
end
local skinnedMode = false -- a bar decorates (AuraButtons.StandIns)
-- The frame hides and waits for a later skin; the mask comes off.
local function Park(cell, h)
    local frame = h.skinFrame
    if frame then
        frame:Hide()
        h.skinFrame, h.parkedSkin = nil, frame
        h.skinLook, h.skinW, h.skinH, h.skinned = nil, nil, nil, nil
    end
    if h.shapeOf then
        h.shapeOf = nil
        NS.HostBridge.ApplyIconShape(cell, K.SQUARE, h.icon, nil, h.icon)
    end
end
-- The stand-in's skin frame in `look` at its size around its icon: MSUF
-- paints only when the look or the size changed; showing or hiding the frame
-- asks it nothing.
local function Draw(cell, h, look, w, height)
    local frame = h.skinFrame
    if look and not frame then
        frame = h.parkedSkin or S.CreateFrame("Frame", nil, cell)
        frame:SetAllPoints(cell)
        h.skinFrame, h.parkedSkin = frame, nil
    end
    if not frame then return end
    if h.skinLook ~= look or h.skinW ~= w or h.skinH ~= height then
        h.skinLook, h.skinW, h.skinH = look, w, height
        h.skinned = NS.HostBridge.PaintIconSkin(frame, look, w, height, h.icon) or nil
    end
    frame:SetShown(h.skinned == true)
end
-- What a stand-in's cell shows: (no bar decorating: parked) the bar's own
-- skin while the stand-in is held, else nothing.
local function Settle(cell, h)
    if not skinnedMode then return Park(cell, h) end
    if h.shown then return Draw(cell, h, h.ownLook, h.ownW, h.ownH) end
    HideSkin(h)
end
local Missing
local function UnholdPlain(cell)
    local h = cell and holders[cell]
    if h and h.glow then Missing(cell, h, nil, nil, false) end
    if h and h.shown then
        h.shown = false
        h.icon:Hide()
        h.bg:Hide()
        h.name:Hide()
        if h.sample then h.sample:Hide() end
    end
end
local function UnholdSkinned(cell)
    UnholdPlain(cell)
    local h = cell and holders[cell]
    if h then Settle(cell, h) end
end

-- The bar's own skin of a held stand-in (Settle draws it) and its shape when
-- that changed (a style pass); a stand-in shown again only shows the skin's
-- frame.
local function SkinHeld(cell, h, lk, bar, look)
    local skin, w, height = look, lk.w - 2 * lk.bw, lk.h - 2 * lk.bw
    if bar then
        if not lk.icon then skin = nil end
        w = height
    end
    h.ownLook, h.ownW, h.ownH = skin, w, height
    Settle(cell, h)
    local shape = lk.shape ~= K.SQUARE and lk.shape or nil
    if h.shapeOf ~= shape then
        h.shapeOf = shape
        NS.HostBridge.ApplyIconShape(cell, lk.shape, h.icon, nil, h.icon)
    end
end
local function HoldPlain(cell, entry, barMeta, dim, view)
    local h = holders[cell]
    if not h then
        h = { bg = S.CreateTexture(cell, nil, "BACKGROUND", nil, 0), icon = S.CreateTexture(cell, nil, "BACKGROUND", nil, 1),
            name = S.CreateFontString(cell, nil, "ARTWORK") }
        h.name:SetWordWrap(false)
        h.name:SetJustifyH("LEFT")
        holders[cell] = h
    end
    local tex = (entry.ov or EMPTY).icon or entry.texture or QUESTION
    if not dim and barMeta.role == "bar" then
        h.shown, h.e, h.look, h.dim = true, nil, nil, nil
        h.icon:Hide()
        h.bg:Hide()
        h.name:Hide()
        h.sample = AuraButtons.Sample(cell, h.sample, view, entry.ov, tex, C.Const.EntryLabel(entry))
        h.sample:SetAllPoints(cell)
        h.sample:Show()
        return
    end
    if h.sample then h.sample:Hide() end
    if h.shown and h.e == entry and h.tex == tex and h.look == barMeta.look and h.dim == dim then return end
    h.shown, h.e, h.tex, h.look, h.dim = true, entry, tex, barMeta.look, dim
    local lk, icon = barMeta.lk, h.icon
    local bw = lk.bw
    icon:SetTexture(tex)
    icon:SetTexCoord(lk.l, lk.r, lk.t, lk.b)
    icon:SetDesaturated(dim)
    icon:SetAlpha(dim and .5 or 1)
    icon:ClearAllPoints()
    if barMeta.role == "bar" then
        local left = lk.side == K.BAR_ICON_SIDE.LEFT
        local point = left and "TOPLEFT" or "TOPRIGHT"
        icon:SetPoint(point, cell, point, left and bw or -bw, -bw)
        icon:SetSize(lk.h - 2 * bw, lk.h - 2 * bw)
        icon:SetShown(lk.icon)
        local bg, name = h.bg, h.name
        bg:ClearAllPoints()
        bg:SetAllPoints(cell)
        bg:SetTexture(lk.tex)
        bg:SetVertexColor(lk.fr * .25, lk.fg * .25, lk.fb * .25, dim and lk.bgA * .6 or lk.bgA)
        bg:Show()
        S.SetStyledFont(name, lk.font, lk.cs, lk.flags, lk.rendering, lk.shadow, lk.shadowOpacity, lk.shadowDistance)
        name:SetTextColor(lk.cr, lk.cg, lk.cb, dim and .6 or 1)
        name:ClearAllPoints()
        local lead = lk.icon and lk.h or 0
        name:SetPoint("LEFT", cell, "LEFT", (left and lead or 0) + 4 * lk.px, 0)
        name:SetPoint("RIGHT", cell, "RIGHT", -(left and 0 or lead) - 4 * lk.px, 0)
        name:SetText(C.Const.EntryLabel(entry))
        name:SetShown(view.barName ~= false)
    else
        icon:SetPoint("TOPLEFT", cell, "TOPLEFT", bw, -bw)
        icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -bw, bw)
        icon:Show()
        h.bg:Hide()
        h.name:Hide()
    end
end
-- Suite main's Hold, then the skin: none under a bar's sample row (its own
-- look), else the bar's skin and shape (SkinHeld).
local function HoldSkinned(cell, entry, barMeta, dim, view)
    HoldPlain(cell, entry, barMeta, dim, view)
    local h, lk, look = holders[cell], barMeta.lk, barMeta.skinLook
    -- A bar's sample row: its own look. The stand-in's skin, size and mask
    -- stay current (a settings change in the preview) and its frame hidden,
    -- so the stand-in coming back (the preview closed in combat) only shows it.
    if h.e == nil then
        if look or h.skinFrame or lk.shape ~= K.SQUARE or h.shapeOf then SkinHeld(cell, h, lk, true, look) end
        return HideSkin(h)
    end
    if look or h.skinFrame or lk.shape ~= K.SQUARE or h.shapeOf then SkinHeld(cell, h, lk, barMeta.role == "bar", look) end
end

-- Without a skin or shape on any bar (the settings read, beside
-- Icons.Decorations), stand-ins run Suite main's Hold and Unhold; each
-- stand-in's skin frame is parked and its mask taken off then (out of
-- combat), and a later skin takes the frame back.
local Hold, Unhold = HoldPlain, UnholdPlain
function AuraButtons.StandIns(any)
    any = any == true
    if any == skinnedMode then return end
    skinnedMode = any
    Hold, Unhold = any and HoldSkinned or HoldPlain, any and UnholdSkinned or UnholdPlain
    if any then return end
    for cell, h in pairs(holders) do Park(cell, h) end
end
local function Unholds(slot)
    local bar = C.bars[slot]
    if not bar or not bar.cells then return end
    local cells = bar.cells
    for i = 1, #cells do Unhold(cells[i]) end
end

-- Whether a fixed slot's cell holds a stand-in under its button: in the
-- preview every entry's sample, else a missing buff the entry or its bar
-- shows (AuraButtons.lua clips the slot button's skin over it).
local function Held(entry, view, preview)
    if preview then return true end
    if entry.src == "p" then return false end
    local ov = entry.ov or EMPTY
    local show = ov.showMissing
    if show == nil then show = view.showMissing == true end
    -- A glow while missing glows on the stand-in, so it holds one.
    return (show or ov.missingGlow == true) and true or false
end
AuraButtons.Held = Held

------------------------------------------------------------------ glow while missing
-- "Glow while missing" (missingGlow): a missing buff's stand-in glows in its
-- spell's glow style and color (else the bar's). Textures of a frame at its
-- cell's level, so the slot button above covers it while the buff is
-- active: nothing runs per aura event. The flipbook styles play inside the
-- icon, the edge styles draw its border (Pulse pulses; Pixel and Autocast
-- hold a still border). Made on first use, kept per cell. "All glows only
-- in combat" shows it in combat only (MissingCombat, the combat edges).
local lit = {} -- cell -> its glow frame while one is wanted
local function Allowed() return not C.state.allGlowsCombat or C.state.inCombat or C.state.preview end
local function Paint(g, style, r, gg, b)
    local spec = K.GLOW[style]
    local px = Px()
    if g.st == style and g.r == r and g.g == gg and g.b == b and g.px == px then return end
    g.st, g.r, g.g, g.b, g.px = style, r, gg, b, px
    g.book:Stop()
    g.pulse:Stop()
    if spec.atlas then
        g.flip:SetAtlas(spec.atlas)
        g.flip:SetDesaturated(r ~= nil)
        g.flip:SetVertexColor(r or 1, gg or 1, b or 1)
        K.SetFlipBook(g.book, spec)
        K.PlaceEdges(g.edges, g, 0)
    else
        local gold = K.GLOW_GOLD
        K.PlaceEdges(g.edges, g, K.Pixels(spec.edge), r or gold[1], gg or gold[2], b or gold[3], 1)
    end
    g.flip:SetShown(spec.atlas ~= nil)
    g.anim = (spec.atlas and g.book) or (spec.pulse and g.pulse) or nil
end
function Missing(cell, h, entry, view, on)
    local g = h.glow
    if not on then
        if g and lit[cell] then
            lit[cell] = nil
            if g.anim then g.anim:Stop() end
            g:Hide()
        end
        return
    end
    if not g then
        g = S.CreateFrame("Frame", nil, cell)
        g:SetAllPoints(cell)
        g.flip = S.CreateTexture(g, nil, "OVERLAY")
        g.flip:SetAllPoints(g)
        g.book, g.edges, g.pulse = K.FlipBook(g.flip, K.GLOW[1]), K.NewEdges(g), K.Pulse(g, K.GLOW[3].pulse)
        h.glow = g
    end
    -- Under the slot button: the cell's own level.
    g:SetFrameLevel(cell:GetFrameLevel())
    Paint(g, K.GlowSpec(entry.ov or EMPTY, view.glowStyle, view.glowTint, view.glowR, view.glowG, view.glowB))
    lit[cell] = g
    g:SetShown(Allowed())
    if g.anim then g.anim:Play() end
end
-- Combat edges and the "only in combat" switch: lit glows show or hide.
function AuraButtons.MissingCombat()
    local allowed = Allowed()
    for _, g in pairs(lit) do g:SetShown(allowed) end
end
C.MissingGlowGate = AuraButtons.MissingCombat
-- Diagnostics and tests: the glow a cell's stand-in shows (nil: none).
function C.Diagnostics.MissingGlow(cell) return lit[cell] end

-- preview: the aura layer's preview state (every entry shows its sample).
local function Placeholders(slot, view, plan, barMeta, preview)
    -- The bar and its cells exist once the layout built them.
    local bar = C.bars[slot]
    if not (bar and bar.cells) then return end
    local Cell = C.Layout.Cell
    local entries = plan.entries
    local cap = #entries
    local limit = view.maxIcons
    if type(limit) == "number" and limit > 0 and limit < cap then cap = limit end
    for i = 1, cap do
        local entry = entries[i]
        local show, glow = preview, false
        if not show and barMeta.fixed and entry.src ~= "p" then
            local ov = entry.ov or EMPTY
            show, glow = ov.showMissing, ov.missingGlow == true
            if show == nil then show = view.showMissing == true end
            show = show or glow
        end
        if show then
            local cell = Cell(slot, i)
            Hold(cell, entry, barMeta, not preview, view)
            local h = holders[cell]
            if glow or h.glow then Missing(cell, h, entry, view, glow) end
        else
            Unhold(bar.cells[i])
        end
    end
    local cells = bar.cells
    for i = cap + 1, #cells do Unhold(cells[i]) end
end

AuraButtons.Unholds, AuraButtons.Placeholders = Unholds, Placeholders
