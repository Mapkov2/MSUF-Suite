local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Glows, usable/range tint and the assisted-combat overlay. Glows are C
-- animations (flipbooks, alpha bounce) started and stopped only on edges;
-- nothing is animated from Lua. Glow reasons (proc, ready, aura) share one
-- glow per icon; the assist suggestion has its own ants overlay. Range
-- checks are reference counted per spell so shared spells stay enabled
-- until their last icon lets go.
local K = C.Const
local KIND = K.KIND
local USABLE = S.USABLE
local USABLE_TINT = S.USABLE_TINT
local Effects = {}
C.Effects = Effects
local Public = S.Public
local issecret = _G.issecretvalue
local EMPTY = C.EMPTY
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
local recommendation
function Effects.RecommendationFrame() return recommendation end
function Effects.RecommendationGCD()
    local frame = recommendation
    if not frame or not frame:IsShown() then return end
    if not C.state.assistIconGCD then
        frame.cd:Clear()
        return
    end
    local duration = C_Spell.GetSpellCooldownDuration(K.GCD_SPELL)
    if duration then frame.cd:SetCooldownFromDurationObject(duration, true) else frame.cd:Clear() end
end
local function NewRecommendation()
    local frame = S.CreateFrame("Frame", nil, UIParent)
    frame:EnableMouse(false)
    frame.tex = S.CreateTexture(frame, nil, "ARTWORK")
    frame.tex:SetAllPoints(frame)
    frame.tex:SetTexCoord(.08, .92, .08, .92)
    frame.cd = S.CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cd:SetAllPoints(frame)
    frame.cd:SetHideCountdownNumbers(true)
    frame.cd:SetDrawEdge(false)
    frame.cd:SetDrawBling(false)
    frame.over = S.CreateFrame("Frame", nil, frame)
    frame.over:SetAllPoints(frame)
    frame.over:SetFrameLevel(frame.cd:GetFrameLevel() + 1)
    frame.key = S.CreateFontString(frame.over, nil, "OVERLAY")
    frame.key:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    frame.badge = S.CreateTexture(frame.over, nil, "BACKGROUND")
    frame.badge:SetPoint("TOPLEFT", frame.key, "TOPLEFT", -2, 2)
    frame.badge:SetPoint("BOTTOMRIGHT", frame.key, "BOTTOMRIGHT", 2, -2)
    frame.badge:SetColorTexture(0, 0, 0, .85)
    return frame
end
-- A new suggestion arrives up to five times a second in combat: the frame
-- writes only what changed (shown state, size, place, texture, font and
-- key text, memoized on the frame). MSUF Edit Mode moves the frame itself,
-- so its place is written again on every call while Edit Mode runs.
function Effects.Recommendation()
    local state = C.state
    local spell = assistSpell
    local show = state.assistIcon == true and (spell ~= nil or state.preview == true)
    local frame = recommendation
    if not frame and not show then return end
    if not frame then
        frame = NewRecommendation()
        recommendation = frame
    end
    local edge = frame.layShown ~= show
    if edge then
        frame.layShown = show
        frame:SetShown(show)
    end
    if not show then
        if edge then frame.cd:Clear() end
        return
    end
    local size = state.assistIconSize or 48
    local x, y = state.assistIconX or 0, state.assistIconY or -180
    if frame.laySize ~= size then
        frame.laySize = size
        frame:SetSize(size, size)
    end
    if frame.layX ~= x or frame.layY ~= y or S.editMode then
        frame.layX, frame.layY = x, y
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
    local texture = spell and C_Spell.GetSpellTexture(spell) or K.QUESTION_ICON
    if frame.layTexture ~= texture then
        frame.layTexture = texture
        frame.tex:SetTexture(texture)
    end
    local fontSize = K.TextSize(nil, K.FONT.keybind, size)
    if frame.layFontSize ~= fontSize or frame.layText ~= state.textGen then
        frame.layFontSize, frame.layText = fontSize, state.textGen
        S.SetStyledFont(frame.key, state.font, fontSize, state.fontFlags,
            state.fontRendering, state.fontShadow, state.fontShadowOpacity, state.fontShadowDistance)
    end
    local key = state.assistIconKeybind and spell and C.Keybinds.Text(spell) or ""
    if frame.layKey ~= key then
        frame.layKey = key
        frame.key:SetText(key)
        frame.badge:SetShown(key ~= "")
    end
    -- The GCD swipe follows its own events while shown; it is read here
    -- when the frame appears or the GCD option changed.
    if edge or frame.layGCD ~= state.assistIconGCD then
        frame.layGCD = state.assistIconGCD
        Effects.RecommendationGCD()
    end
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
local function Paint(glow, icon, spec, style, r, g, b, w, h)
    local px = K.Px()
    if glow.pStyle == style and glow.pR == r and glow.pG == g and glow.pB == b and glow.pW == w and glow.pH == h and glow.pPx == px then return end
    glow.pStyle, glow.pR, glow.pG, glow.pB, glow.pW, glow.pH, glow.pPx = style, r, g, b, w, h, px
    local flip, edges = glow.flip, glow.edges
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

local function ShowGlow(icon, style, r, g, b)
    local glow = EnsureGlow(icon)
    local spec = K.GLOW[style]
    local w, h = icon.w or icon:GetWidth(), icon.h or icon:GetHeight()
    Paint(glow, icon, spec, style, r, g, b, w, h)
    local anim = (spec.atlas and glow.flipAnim) or (spec.pulse and glow.pulse) or nil
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

-- A running glow follows style, color and size changes (cold path).
local function Restyle(icon, entry, view)
    if icon.gStyle == nil then return end
    local style, r, g, b = GlowSpec(entry, view)
    if style == icon.gStyle and r == icon.gR and g == icon.gG and b == icon.gB and icon.gW == icon.w and icon.gH == icon.h then return end
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
    return view ~= nil and K.Pick(entry.ov or EMPTY, view, "readyResources")
end
-- Whether a usability read of the entry can show: its icon is on a shown
-- bar and in range, or the read gates its ready glow. The usable broadcast
-- (Events) and the flush ask this before Effects.Usable.
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
            if queries and Public(id) then
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
    if needResources then Effects.RefreshReady(entry) end
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
local function ProcWanted(entry, view)
    if not entry.procOn then return false end
    return K.Pick(entry.ov or EMPTY, view, "procGlow")
end

local function ReadyWanted(entry, view)
    local ov = entry.ov or EMPTY
    local normal = K.Pick(ov, view, "readyGlow") and not entry.cooling
    local full = K.Pick(ov, view, "fullChargeGlow") and entry.fullyCharged == true
    if not (normal or full) or entry.hidden then return false end
    if K.Pick(ov, view, "readyResources") and entry.resourcesAvailable ~= true then return false end
    local state = C.state
    if state.readyGlowCombat and not state.inCombat and not state.preview then return false end
    return true
end

function Effects.Proc(entry, on)
    entry.procOn = on and true or false
    local icon = entry.icon
    if not icon then return end
    local view = C.views[entry.slot]
    Effects.SetGlow(icon, "proc", view and ProcWanted(entry, view) or false)
end

-- Cold part of an update: runs when the icon, spell, choices or the bar's
-- behavior generation changed; seeds proc, range and usable state.
local function Bind(entry, icon, view)
    icon.fxEntry, icon.fxOv, icon.fxGen, icon.fxSpell = entry, entry.ov, view.behaviorGen, entry.spell
    if entry.src == "p" then return end
    local spell = entry.spell
    if spell then
        local shown = IsOverlayed(spell)
        entry.procOn = (Public(shown) and shown) and true or false
    end
    -- Entries bound after the last suggestion change still match it.
    local assist = assistSpell
    entry.assistOn = assist ~= nil and (spell == assist or entry.base == assist or entry.override == assist)
    Effects.EnableRange(entry, view.range == true)
    Effects.Usable(entry)
end

-- Re-derives every effect of one entry from its flags and its bar.
function Effects.Update(entry)
    local icon = entry.icon
    if not icon then return end
    local view = C.views[entry.slot]
    if not view then return end
    if icon.fxEntry ~= entry or icon.fxOv ~= entry.ov or icon.fxGen ~= view.behaviorGen or icon.fxSpell ~= entry.spell then
        Bind(entry, icon, view)
    end
    Effects.SetGlow(icon, "proc", ProcWanted(entry, view))
    Effects.SetGlow(icon, "ready", ReadyWanted(entry, view))
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
    if view then Effects.SetGlow(icon, "ready", ReadyWanted(entry, view)) end
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
    if edge and not C.state.readyGlowCombat then return end
    Walk(C.Index.ready, ReadyEntry)
end

-- Size changes from the icon style pass.
function Effects.Refit(icon)
    local entry = icon.entry
    local view = entry and C.views[entry.slot] or EMPTY
    Restyle(icon, entry, view)
    if icon.antsOn then SizeAnts(icon) end
end

-- Stops every visual on a recycled icon; the next Update re-seeds.
function Effects.ResetIcon(icon)
    if icon.pressPulse then icon.pressPulse:Stop() end
    icon.gProc, icon.gReady, icon.gAura = nil, nil, nil
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
    if recommendation then
        recommendation.layShown = false
        recommendation:Hide()
        recommendation.cd:Clear()
    end
end

-- Diagnostics: range references currently held.
function C.Diagnostics.RangeReferences()
    local total = 0
    for _, count in pairs(rangeRefs) do total = total + count end
    return total
end
