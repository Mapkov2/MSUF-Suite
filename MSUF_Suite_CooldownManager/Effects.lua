local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Glows, usable/range tint and the assisted-combat overlay. Glows are C
-- animations (flipbooks, alpha bounce, the Pixel and Autocast lines'
-- translations) started and stopped only on edges; nothing is animated
-- from Lua. Glow reasons (proc, ready, aura) share one glow per icon; the
-- assist suggestion has its own ants overlay (the standalone assisted icon
-- is AssistIcon.lua's). Range checks are reference counted per spell so
-- shared spells stay enabled until their last icon lets go.
local K = C.Const
local KIND = K.KIND
local USABLE = S.USABLE
local USABLE_TINT = S.USABLE_TINT
local Effects = {}
C.Effects = Effects
local Public = S.Public
local issecret = _G.issecretvalue
local EMPTY = C.EMPTY
-- Pixel and Autocast (GlowLines.lua loads first).
local Lines = C.GlowLines
local IsUsable = C_Spell.IsSpellUsable
local InRange = C_Spell.IsSpellInRange
local function EnableRangeCheck(spell, enabled) S.SetNativeSpellRange("cooldownManager", spell, enabled) end
local IsOverlayed = C_SpellActivationOverlay.IsSpellOverlayed
local IsUsableItem = C_Item.IsUsableItem
local rangeRefs = {}
local ranged = {}
local fxIcons = {}
local REASONS = { proc = "gProc", ready = "gReady", aura = "gAura" }
local assistSpell
-- The assisted icon (AssistIcon.lua) reads the suggestion.
function Effects.AssistSpell() return assistSpell end
-- The press flash: a white overlay over the icon texture that fades out,
-- made at the first press (Effects.Press, Suite main's code) or, for a shaped
-- icon, by its decoration out of combat, so the shape's mask takes it then
-- (Icons.lua's Shape masks the flash animation's parent, either one). One
-- the decoration made and nothing played yet (unplayed) goes with the shape
-- (Effects.ParkPulse), so the recycle path stops none, as on Suite main; its
-- first play clears that mark once.
local unplayed = setmetatable({}, { __mode = "k" })
local function Played(flash)
    flash:SetScript("OnPlay", nil)
    unplayed[flash] = nil
end
function Effects.ParkPulse(icon)
    local flash = icon.pressPulse
    if flash and unplayed[flash] then icon.pressPulse, icon.parkedPulse = nil, flash end
end
function Effects.PreparePulse(icon)
    if icon.pressPulse then return end
    local parked = icon.parkedPulse
    if parked then
        icon.pressPulse, icon.parkedPulse = parked, nil
        return
    end
    local overlay = S.CreateTexture(icon.over, nil, "OVERLAY")
    overlay:SetAllPoints(icon.tex)
    overlay:SetColorTexture(1, 1, 1, 1)
    overlay:SetAlpha(0)
    local flash = overlay:CreateAnimationGroup()
    local alpha = flash:CreateAnimation("Alpha")
    alpha:SetFromAlpha(.35)
    alpha:SetToAlpha(0)
    alpha:SetDuration(.18)
    unplayed[flash] = true
    flash:SetScript("OnPlay", Played)
    icon.pressPulse = flash
end

function Effects.Press(entry)
    local icon = entry.icon
    local bar = C.bars[entry.slot]
    if not icon or not icon:IsShown() or entry.hidden or not bar or bar.hidden then return end
    local pulse = icon.pressPulse
    if not pulse then
        local tex = S.CreateTexture(icon.over, nil, "OVERLAY")
        tex:SetAllPoints(icon.tex)
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetAlpha(0)
        pulse = tex:CreateAnimationGroup()
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(.35)
        fade:SetToAlpha(0)
        fade:SetDuration(.18)
        icon.pressPulse = pulse
    end
    pulse:Stop()
    pulse:Play()
end
local function GlowsAllowed()
    return not C.state.allGlowsCombat or C.state.inCombat or C.state.preview
end
local function GlowGate(icon)
    local gate = icon.effectGate
    if not gate then
        gate = S.CreateFrame("Frame", nil, icon)
        gate:SetAllPoints(icon)
        gate:SetShown(GlowsAllowed() == true)
        icon.effectGate = gate
    end
    return gate
end

------------------------------------------------------------------ glow frames
local function EnsureGlow(icon)
    local glow = icon.glow
    if glow then return glow end
    glow = S.CreateFrame("Frame", nil, GlowGate(icon))
    glow:SetAllPoints(icon)
    glow:SetFrameLevel(icon:GetFrameLevel() + K.LEVEL.glow)
    glow:Hide()
    local flip = S.CreateTexture(glow, nil, "OVERLAY")
    flip:SetPoint("CENTER", icon, "CENTER")
    flip:Hide()
    glow.flip, glow.flipOn = flip, false
    glow.flipAnim = K.FlipBook(flip, K.GLOW[1])
    local edges = K.NewEdges(glow)
    for i = 1, 4 do edges[i]:Hide() end
    glow.edges, glow.edgesOn = edges, false
    glow.pulse = K.Pulse(glow, K.GLOW[3].pulse)
    icon.glow = glow
    fxIcons[icon] = true
    return glow
end

-- Style and color for an entry: per-spell choices first, then the bar.
local function GlowSpec(entry, view)
    return K.GlowSpec(entry and entry.ov or EMPTY, view.glowStyle, view.glowTint, view.glowR, view.glowG, view.glowB)
end

-- The painted look (atlas or edges, size, tint) stays on the glow frame
-- while it is hidden: showing the same look again only shows and plays.
-- Pixel and Autocast paint their lines (GlowLines.PaintIcon).
local function PaintPlain(glow, icon, spec, style, r, g, b, w, h)
    if spec.lines then return Lines.PaintIcon(glow, icon, spec, r, g, b, w, h) end
    local px = K.Px()
    if glow.pStyle == style and glow.pR == r and glow.pG == g and glow.pB == b and glow.pW == w and glow.pH == h and glow.pPx == px then return end
    glow.pStyle, glow.pR, glow.pG, glow.pB, glow.pW, glow.pH, glow.pPx = style, r, g, b, w, h, px
    local flip, edges = glow.flip, glow.edges
    if glow.linesOn then Lines.Off(glow) end
    if spec.atlas then
        flip:SetAtlas(spec.atlas)
        flip:SetSize(w * spec.scale, h * spec.scale)
        -- Tinting a golden atlas needs it gray first.
        flip:SetDesaturated(r ~= nil)
        if r then
            flip:SetVertexColor(r, g, b)
        else
            flip:SetVertexColor(1, 1, 1)
        end
        K.SetFlipBook(glow.flipAnim, spec)
        if glow.edgesOn then
            glow.edgesOn = false
            for i = 1, 4 do
                edges[i]:Hide()
            end
        end
        if not glow.flipOn then
            glow.flipOn = true
            flip:Show()
        end
    else
        local gold = K.GLOW_GOLD
        K.PlaceEdges(edges, icon, K.Pixels(spec.edge), r or gold[1], g or gold[2], b or gold[3], 1)
        glow.edgesOn = true
        if glow.flipOn then
            glow.flipOn = false
            flip:Hide()
        end
    end
end

-- A shaped icon's edge glow: rings of its shape around the icon texture (the
-- bars offer no STAR, whose ring only works behind the icon: SuiteCatalog.lua)
-- in place of the square edges, placed when the glow's look changes (style,
-- color, pixel grid, shape); a new size moves them with the texture, so a
-- relayout places nothing. The Blizzard alert keeps its square art.
local function PaintShaped(glow, icon, spec, style, r, g, b, w, h)
    local shape = icon.shape
    if not shape or spec.atlas then
        if glow.ringsOn then
            glow.ringsOn = false
            K.PlaceRings(glow.rings, glow, icon.tex, nil, 0)
        end
        return PaintPlain(glow, icon, spec, style, r, g, b, w, h)
    end
    local px = K.Px()
    if glow.ringsOn and glow.rStyle == style and glow.rR == r and glow.rG == g and glow.rB == b and glow.rPx == px
        and glow.rShape == shape then return end
    glow.rStyle, glow.rR, glow.rG, glow.rB, glow.rPx, glow.rShape = style, r, g, b, px, shape
    glow.pStyle = nil
    if glow.linesOn then Lines.Off(glow) end
    K.PlaceEdges(glow.edges, icon, 0)
    glow.edgesOn = false
    if glow.flipOn then
        glow.flipOn = false
        glow.flip:Hide()
    end
    local gold = K.GLOW_GOLD
    glow.rings = glow.rings or {}
    K.PlaceRings(glow.rings, glow, icon.tex, shape, math.max(1, math.floor(spec.edge + .5)), r or gold[1], g or gold[2], b or gold[3])
    glow.ringsOn = true
end
-- The most rings an edge glow style draws (PaintShaped: one per edge pixel).
local MAX_RINGS = 1
for _, spec in pairs(K.GLOW) do
    if spec.edge then MAX_RINGS = math.max(MAX_RINGS, math.floor(spec.edge + .5)) end
end
-- ShowGlow and PrepareGlow paint through this: Suite main's PaintPlain while
-- no icon has a shape (Icons.lua's Shape tells: Effects.Shapes).
local Paint = PaintPlain
function Effects.Shapes(any) Paint = any and PaintShaped or PaintPlain end

-- Prepare optional action feedback on its cold binding path, so the first
-- usable/cooldown event creates no frames, regions or animation groups.
function Effects.PrepareGlow(icon)
    local entry = icon.entry
    local view = entry and C.views[entry.slot] or EMPTY
    local style, r, g, b = GlowSpec(entry, view)
    Paint(EnsureGlow(icon), icon, K.GLOW[style], style, r, g, b, icon.w, icon.h)
end

local function ShowGlow(icon, style, r, g, b)
    local glow = EnsureGlow(icon)
    local spec = K.GLOW[style]
    local w, h = icon.w or icon:GetWidth(), icon.h or icon:GetHeight()
    Paint(glow, icon, spec, style, r, g, b, w, h)
    local anim = (spec.atlas and glow.flipAnim) or (glow.linesOn and glow.lines) or (spec.pulse and glow.pulse) or nil
    if anim then anim:Play() end
    glow.anim = anim
    glow:Show()
    icon.gStyle, icon.gR, icon.gG, icon.gB, icon.gW, icon.gH = style, r, g, b, w, h
end

-- Only the running animation is stopped; hiding the glow frame hides every part.
local function HideGlow(icon)
    local glow = icon.glow
    icon.gStyle = nil
    if not glow then return end
    local anim = glow.anim
    if anim then
        glow.anim = nil
        anim:Stop()
    end
    glow:Hide()
end

-- Reasons are a union: the animation starts on the first reason and stops
-- after the last one; repeated calls without an edge do nothing.
function Effects.SetGlow(icon, reason, on)
    if not icon then return end
    on = on and true or false
    if reason == "assist" then return Effects.Ants(icon, on) end
    local field = REASONS[reason]
    if not field or (icon[field] or false) == on then return end
    icon[field] = on
    local want = (icon.gProc or icon.gReady or icon.gAura) and true or false
    if want == (icon.gStyle ~= nil) then return end
    if want then
        local entry = icon.entry
        local view = entry and C.views[entry.slot] or EMPTY
        ShowGlow(icon, GlowSpec(entry, view))
    else
        HideGlow(icon)
    end
end

-- A running glow follows style, color and size changes and its bar's
-- Pixel or Autocast lines (cold path).
local function Restyle(icon, entry, view)
    if icon.gStyle == nil then return end
    local style, r, g, b = GlowSpec(entry, view)
    if style == icon.gStyle and r == icon.gR and g == icon.gG and b == icon.gB and icon.gW == icon.w and icon.gH == icon.h
        and not (icon.glow.linesOn and Lines.Changed(icon.glow, view)) then return end
    HideGlow(icon)
    ShowGlow(icon, style, r, g, b)
end

------------------------------------------------------------------ assist ants
local function EnsureAnts(icon)
    local ants = icon.ants
    if ants then return ants end
    local spec = K.GLOW[K.ASSIST_STYLE]
    ants = S.CreateFrame("Frame", nil, GlowGate(icon))
    ants:SetAllPoints(icon)
    ants:SetFrameLevel(icon:GetFrameLevel() + K.LEVEL.assist)
    ants:Hide()
    local tex = S.CreateTexture(ants, nil, "OVERLAY")
    tex:SetAtlas(spec.atlas)
    tex:SetPoint("CENTER", icon, "CENTER")
    ants.tex = tex
    ants.anim = K.FlipBook(tex, spec)
    icon.ants = ants
    fxIcons[icon] = true
    return ants
end

local function SizeAnts(icon)
    local w, h = icon.w or icon:GetWidth(), icon.h or icon:GetHeight()
    if icon.aW == w and icon.aH == h then return end
    local spec = K.GLOW[K.ASSIST_STYLE]
    icon.ants.tex:SetSize(w * spec.scale, h * spec.scale)
    icon.aW, icon.aH = w, h
end

function Effects.Ants(icon, on)
    on = on and true or false
    if (icon.antsOn or false) == on then return end
    icon.antsOn = on
    if on then
        local ants = EnsureAnts(icon)
        SizeAnts(icon)
        ants:Show()
        ants.anim:Play()
    elseif icon.ants then
        icon.ants.anim:Stop()
        icon.ants:Hide()
    end
end

------------------------------------------------------------------ tint
-- One vertex color from a memoized code: out of range beats usable state.
function Effects.Tint(entry)
    local icon = entry.icon
    if not icon then return end
    local view = C.views[entry.slot]
    local code = entry.outOfRange and USABLE.OUT_OF_RANGE or entry.usableCode or USABLE.USABLE
    local gen = view and view.behaviorGen or 0
    if icon.tint == code and icon.tintGen == gen then return end
    icon.tint, icon.tintGen = code, gen
    if code == USABLE.OUT_OF_RANGE then
        icon.tex:SetVertexColor(view and view.rangeR or .8, view and view.rangeG or .18, view and view.rangeB or .18)
    else
        local color = USABLE_TINT[code]
        icon.tex:SetVertexColor(color[1], color[2], color[3])
    end
end
local Tint = Effects.Tint

-- A ready glow that waits for enough resources (readyResources).
local function NeedsResources(entry, view)
    if view == nil then return false end
    local value = (entry.ov or EMPTY).readyResources
    if value == nil then value = view.readyResources end
    return value == true
end
-- Event eligibility is unchanged while individual icons are hidden. Only
-- the broadcast defers them; whole bars catch up through Visibility.Paint.
function Effects.UsableShown(entry)
    if not entry.icon then return false end
    local bar = C.bars[entry.slot]
    if not bar or bar.hidden == true then return false end
    return not entry.outOfRange or NeedsResources(entry, C.views[entry.slot])
end

function Effects.Usable(entry, queries)
    -- Range tint wins while the action is out of range. Defer the native
    -- usability query until a range/target edge makes its result visible.
    local view = C.views[entry.slot]
    local needResources = NeedsResources(entry, view)
    if entry.outOfRange and not needResources then return end
    local code = USABLE.USABLE
    local previousResources = entry.resourcesAvailable
    entry.resourcesAvailable = nil
    if view and (view.usable or needResources) and entry.src ~= "p" then
        local usable, noPower, id, reader
        if entry.src == "i" then
            id, reader = entry.itemID or entry.id, IsUsableItem
        elseif not (entry.equipSlot or entry.src == "e") then
            local spell, category = entry.spell, entry.spellCategory
            if category and category ~= 0 then spell = entry.catSpell end
            id, reader = spell, IsUsable
        end
        if id and reader then
            -- The flush owns separate spell/item maps and clears them before
            -- returning. Resolve overrides by their current ID on every pass.
            if queries and not issecret(id) then
                if queries.seen[id] then
                    usable, noPower = queries.usable[id], queries.noPower[id]
                else
                    usable, noPower = reader(id)
                    queries.seen[id] = true
                    queries.usable[id], queries.noPower[id] = usable, noPower
                end
            else
                usable, noPower = reader(id)
            end
        end
        entry.resourcesAvailable = not issecret(noPower) and noPower == false or nil
        if view.usable and not issecret(usable) and usable == false then
            code = (not issecret(noPower) and noPower) and USABLE.NO_POWER or USABLE.UNUSABLE
        end
    end
    entry.usableCode = code
    local icon = entry.icon
    -- Usability broadcasts usually leave the visible tint unchanged. Avoid
    -- another Lua function call on that common path, while still repainting
    -- after a range or behavior change. All compared values are local codes.
    if icon and (icon.tint ~= code
        or icon.tintGen ~= (view and view.behaviorGen or 0)) then Tint(entry) end
    if needResources and (not queries or previousResources ~= entry.resourcesAvailable) then Effects.RefreshReady(entry) end
    entry.usablePending = nil
end

------------------------------------------------------------------ range
local function Hold(spell)
    local count = rangeRefs[spell] or 0
    rangeRefs[spell] = count + 1
    if count == 0 then EnableRangeCheck(spell, true) end
end

local function Drop(spell)
    local count = (rangeRefs[spell] or 1) - 1
    if count > 0 then
        rangeRefs[spell] = count
        return
    end
    rangeRefs[spell] = nil
    EnableRangeCheck(spell, false)
end

local function Seed(entry, spell)
    local inRange = InRange(spell)
    entry.outOfRange = (Public(inRange) and inRange == false) or nil
end

-- Holds one reference on the entry's base spell (the ID Blizzard's viewer
-- checks) while wanted; there is no initial range event, so it seeds once.
function Effects.EnableRange(entry, on)
    local want
    if on and entry.hasRange and entry.src ~= "p" then want = entry.base or entry.spell end
    local held = entry.rangeSpell
    if held == want then return end
    if held then
        Drop(held)
        entry.rangeSpell, entry.outOfRange, ranged[entry] = nil, nil, nil
    end
    if want then
        Hold(want)
        entry.rangeSpell, ranged[entry] = want, true
        Seed(entry, want)
    end
    Tint(entry)
end

-- SPELL_RANGE_CHECK_UPDATE: pass nil when checksRange is false.
function Effects.Range(entry, inRange)
    if not entry.rangeSpell then return end
    local out = (Public(inRange) and inRange == false) or nil
    if entry.outOfRange == out then return end
    local wasOut = entry.outOfRange
    entry.outOfRange = out
    if wasOut and not out then
        Effects.Usable(entry)
    else
        Tint(entry)
    end
end

-- Target changes: re-read the held check without touching references.
function Effects.ReadRange(entry)
    local spell = entry.rangeSpell
    if not spell then return end
    local before = entry.outOfRange
    Seed(entry, spell)
    if before ~= entry.outOfRange then
        if before and not entry.outOfRange then
            Effects.Usable(entry)
        else
            Tint(entry)
        end
    end
end

------------------------------------------------------------------ reasons
-- Entry keys that showed a real spell alert this session: the options
-- simulation plays the alert glow only on spells that raise one.
local procced = {}
function Effects.Procced(key) return procced[key] == true end

local function ProcWanted(entry, view)
    if not entry.procOn then return false end
    return K.Pick(entry.ov or EMPTY, view, "procGlow")
end

-- Glow when ready / when all charges are ready, from a cooling and a
-- full-charges state; the simulation (Preview.Glows) feeds its own.
local function ReadyRule(ov, view, cooling, full)
    return (not cooling and K.Pick(ov, view, "readyGlow")) or (full == true and K.Pick(ov, view, "fullChargeGlow"))
end
Effects.ReadyRule = ReadyRule

local function ReadyWanted(entry, view)
    local ov = entry.ov or EMPTY
    if entry.hidden or not ReadyRule(ov, view, entry.cooling, entry.fullyCharged) then return false end
    if K.Pick(ov, view, "readyResources") and entry.resourcesAvailable ~= true then return false end
    local state = C.state
    if state.readyGlowCombat and not state.inCombat and not state.preview then return false end
    return true
end

------------------------------------------------------------------ show conditions
-- "Show only when usable" and "Show only during a spell alert" (per-spell,
-- cooldown icons): entry.gated, which the time layer folds into
-- entry.hidden (Time.Refresh, icon.gate). Usability comes from the usable
-- sweep's shared answers (Index.gated, GateUsable below), the alert from
-- the proc events; Time's curves seed both (SeedGate). A flip of the
-- hidden state relayouts the bar like a hideReady edge; unchanged answers
-- write nothing.
local function Regate(entry)
    local ov, icon = entry.ov or EMPTY, entry.icon
    local gated = (ov.usableOnly == true and entry.unusable == true) or (ov.procOnly == true and entry.procOn ~= true)
    if entry.gated == gated then return end
    entry.gated = gated
    if not (icon and icon.gate) then return end
    local hidden = (not C.state.preview and ((icon.hideReady and not entry.cooling) or entry.empty or gated)) and true or false
    if (entry.hidden == true) == hidden then return end
    entry.hidden = hidden
    C.Layout.Request(entry.slot)
    Effects.RefreshReady(entry)
end
Effects.Regate = Regate
-- One usability answer for the gate, also while the icon is hidden (it is
-- what shows it again), also while its bar is hidden: from the flush's
-- maps (queries: the usable sweep's spells and items) or, outside the
-- sweep, the client. A secret answer shows the icon.
function Effects.GateUsable(entry, queries)
    if not entry.icon then return end
    if queries then queries.used = true end
    local id, reader
    if entry.src == "i" then
        id, reader, queries = entry.itemID or entry.id, IsUsableItem, queries and queries.items
    else
        local spell, category = entry.spell, entry.spellCategory
        if category and category ~= 0 then spell = entry.catSpell end
        id, reader, queries = spell, IsUsable, queries and queries.spells
    end
    if not id then return end
    local usable
    if queries and not issecret(id) then
        if not queries.seen[id] then
            local noPower
            usable, noPower = reader(id)
            queries.seen[id], queries.usable[id], queries.noPower[id] = true, usable, noPower
        end
        usable = queries.usable[id]
    else
        usable = reader(id)
    end
    entry.unusable = (not issecret(usable) and usable == false) or nil
    Regate(entry)
end

-- The first answers of an entry's show conditions, or letting go of them:
-- Time's curves ask when the entry's choices or bar behavior changed (cold).
function Effects.SeedGate(entry, queries)
    local ov, spell = entry.ov or EMPTY, entry.spell
    if ov.procOnly and spell then
        local shown = IsOverlayed(spell)
        entry.procOn = (Public(shown) and shown) and true or false
        if entry.procOn then procced[entry.key] = true end
    end
    if ov.usableOnly then return Effects.GateUsable(entry, queries) end
    Regate(entry)
end

-- A simulated icon (icon.simFx, Preview.lua) keeps the simulation's glows.
function Effects.Proc(entry, on)
    entry.procOn = on and true or false
    if on then procced[entry.key] = true end
    if entry.ov.procOnly then Regate(entry) end
    local icon = entry.icon
    if not icon or icon.simFx then return end
    local view = C.views[entry.slot]
    Effects.SetGlow(icon, "proc", view and ProcWanted(entry, view) or false)
end

-- Rebinds and show catch-up share the same synchronous query domain.
local function SeedUsable(entry, queries)
    if queries then
        queries.used = true
        queries = entry.src == "i" and queries.items or queries.spells
    end
    Effects.Usable(entry, queries)
end
-- Changed icon, spell, choices or bar behavior: bind proc, range and usable state.
local function Bind(entry, icon, view, queries)
    icon.fxEntry, icon.fxOv, icon.fxGen, icon.fxSpell = entry, entry.ov, view.behaviorGen, entry.spell
    if entry.src == "p" then return end
    local spell = entry.spell
    if spell then
        local shown = IsOverlayed(spell)
        entry.procOn = (Public(shown) and shown) and true or false
        if entry.procOn then procced[entry.key] = true end
    end
    -- Entries bound after the last suggestion change still match it.
    local assist = assistSpell
    entry.assistOn = assist ~= nil and (spell == assist or entry.base == assist or entry.override == assist)
    Effects.EnableRange(entry, view.range == true)
    return SeedUsable(entry, queries)
end

-- Re-derives every effect of one entry from its flags and its bar.
function Effects.Update(entry, queries)
    local icon = entry.icon
    if not icon then return end
    local view = C.views[entry.slot]
    if not view then return end
    if icon.fxEntry ~= entry or icon.fxOv ~= entry.ov or icon.fxGen ~= view.behaviorGen or icon.fxSpell ~= entry.spell then
        Bind(entry, icon, view, queries)
    elseif entry.usablePending and (not entry.hidden or C.state.preview) then
        SeedUsable(entry, queries)
    end
    if icon.simFx then
        C.Preview.Glows(entry)
    else
        Effects.SetGlow(icon, "proc", ProcWanted(entry, view))
        Effects.SetGlow(icon, "ready", ReadyWanted(entry, view))
    end
    Effects.Ants(icon, entry.assistOn == true and view.assist == true)
    Restyle(icon, entry, view)
    Tint(entry)
end

------------------------------------------------------------------ assisted combat
local function AssistEntry(entry, spell)
    local on = spell ~= nil and (entry.spell == spell or entry.base == spell or entry.override == spell)
    on = on and true or false
    if (entry.assistOn or false) == on then return end
    entry.assistOn = on
    local icon = entry.icon
    if not icon then return end
    local view = C.views[entry.slot]
    Effects.Ants(icon, on and view ~= nil and view.assist == true)
end

local function Walk(list, fn, arg)
    if list then
        for i = 1, #list do fn(list[i], arg) end
        return
    end
    for _, plan in pairs(C.plans) do
        if plan.kind == KIND.COOLDOWN then
            local entries = plan.entries
            for i = 1, #entries do fn(entries[i], arg) end
        end
    end
end

-- Paints only on a suggestion change.
function Effects.Assist(spell)
    if spell ~= nil and not (Public(spell) and type(spell) == "number") then spell = nil end
    if spell == assistSpell then return end
    assistSpell = spell
    Effects.Recommendation()
    Walk(C.Index.assist, AssistEntry, spell)
end

------------------------------------------------------------------ combat and release
local function ReadyEntry(entry)
    local icon = entry.icon
    local view = icon and C.views[entry.slot]
    if view and not icon.simFx then Effects.SetGlow(icon, "ready", ReadyWanted(entry, view)) end
end
Effects.RefreshReady = ReadyEntry

-- Ready glows gated to combat flip here; everything else is untouched.
-- Only entries that want a ready glow (Index.ready) are walked; on a combat
-- edge (edge set) only while those glows wait for combat.
function Effects.CombatChanged(edge)
    local allowed = GlowsAllowed() == true
    for icon in pairs(fxIcons) do
        local gate = icon.effectGate
        if gate and icon.effectsAllowed ~= allowed then
            icon.effectsAllowed = allowed
            gate:SetShown(allowed)
        end
    end
    -- Missing buffs' glows (AuraPlaceholders.lua) follow the same gate.
    local missing = C.MissingGlowGate
    if missing then missing() end
    if edge and not C.state.readyGlowCombat then return end
    Walk(C.Index.ready, ReadyEntry)
end

-- Size changes from the icon style pass.
function Effects.Refit(icon)
    local entry = icon.entry
    local view = entry and C.views[entry.slot] or EMPTY
    Restyle(icon, entry, view)
    if view.kickMark and icon.kickGlow then C.KickMark.Style(entry, view) end
    if icon.antsOn then SizeAnts(icon) end
end

-- A glow only a shape made (the icon never showed one: icon.gW, which
-- ShowGlow sets) is parked when the shape goes, with its gate unless assist
-- ants share it, so no glow path or combat edge visits it, as on Suite main;
-- a new shape takes it back.
local function ParkGlow(icon, glow)
    glow:Hide()
    icon.glow, icon.parkedGlow = nil, glow
    if icon.ants then return end
    fxIcons[icon] = nil
    icon.effectGate, icon.parkedGate, icon.effectsAllowed = nil, icon.effectGate, nil
end
local function UnparkGlow(icon)
    local glow, gate = icon.parkedGlow, icon.effectGate
    icon.parkedGlow = nil
    if gate then
        glow:SetParent(gate)
    else
        gate = icon.parkedGate
        icon.effectGate = gate
        gate:SetShown(GlowsAllowed() == true)
    end
    icon.parkedGate = nil
    glow:SetFrameLevel(icon:GetFrameLevel() + K.LEVEL.glow)
    icon.glow, fxIcons[icon] = glow, true
end

-- Independent owned layers leave the shared combat walk while parked.
function Effects.ParkOwnedGlow(icon)
    if not icon.glow then return end
    HideGlow(icon)
    ParkGlow(icon, icon.glow)
end
function Effects.ResumeOwnedGlow(icon)
    if icon.parkedGlow then UnparkGlow(icon) end
end

-- A shaped icon's new decoration (a new shape, pixel grid or look: Icons.lua's
-- StyleDecorated, out of combat) or one that lost its shape: the glow's paint
-- memos, which leave the shape out of the plain one and the size out of the
-- shaped one, are dropped; a running glow shows again, a hidden one is
-- painted now (also once the shape went: its plain memo) and a shaped icon's
-- missing one made, so its first show (also in combat) paints and makes
-- nothing.
function Effects.Reshaped(icon, view)
    local glow = icon.glow
    if glow then
        glow.pStyle, glow.rStyle = nil, nil
        if glow.ringsOn and not icon.shape then
            glow.ringsOn = false
            K.PlaceRings(glow.rings, glow, icon.tex, nil, 0)
        end
        if not icon.shape and icon.gW == nil and icon.gStyle == nil then return ParkGlow(icon, glow) end
    elseif icon.shape and icon.parkedGlow then
        UnparkGlow(icon)
    end
    local style, r, g, b = GlowSpec(icon.entry, view)
    if icon.gStyle ~= nil then
        HideGlow(icon)
        ShowGlow(icon, style, r, g, b)
    elseif icon.shape or icon.glow then
        Paint(EnsureGlow(icon), icon, K.GLOW[style], style, r, g, b, icon.w, icon.h)
    end
    -- Every edge glow style's rings exist now (also while the alert style is
    -- chosen), so a glow setting edited later and shown first in combat
    -- places its rings without making any.
    if icon.shape then
        glow = icon.glow
        glow.rings = glow.rings or {}
        K.EnsureRings(glow.rings, glow, MAX_RINGS)
    end
end

-- Stops every visual on a recycled icon; the next Update re-seeds.
function Effects.ResetIcon(icon)
    if icon.kickGlow then C.KickMark.Recycled(icon) end
    if icon.pressPulse then icon.pressPulse:Stop() end
    icon.gProc, icon.gReady, icon.gAura, icon.simFx = nil, nil, nil, nil
    HideGlow(icon)
    Effects.Ants(icon, false)
    icon.fxEntry = nil
end

-- The entry left every bar: drop its range reference and assist state.
function Effects.Detach(entry)
    Effects.EnableRange(entry, false)
    entry.assistOn = nil
end

local function ClearAssist(entry) entry.assistOn = nil end

function Effects.ReleaseAll()
    for entry in pairs(ranged) do
        local spell = entry.rangeSpell
        entry.rangeSpell, entry.outOfRange, ranged[entry] = nil, nil, nil
        if spell then Drop(spell) end
    end
    for icon in pairs(fxIcons) do Effects.ResetIcon(icon) end
    Walk(nil, ClearAssist)
    assistSpell = nil
    Effects.ReleaseRecommendation()
end

-- Diagnostics: range references currently held.
function C.Diagnostics.RangeReferences()
    local total = 0
    for _, count in pairs(rangeRefs) do total = total + count end
    return total
end
