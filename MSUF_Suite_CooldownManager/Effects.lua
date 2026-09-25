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
local E = {}
C.Effects = E
local Public = S.Public
local issecret = type(_G.issecretvalue) == "function" and _G.issecretvalue or nil
local EMPTY = C.EMPTY
local Spell = _G.C_Spell or {}
local IsUsable = Spell.IsSpellUsable
local InRange = Spell.IsSpellInRange
local EnableRangeCheck = Spell.EnableSpellRangeCheck
local Overlay = _G.C_SpellActivationOverlay
local IsOverlayed = Overlay and Overlay.IsSpellOverlayed
local Item = _G.C_Item
local IsUsableItem = Item and Item.IsUsableItem
local rangeRefs = {}
local ranged = {}
local fxIcons = {}
local REASONS = { proc = "gProc", ready = "gReady", aura = "gAura" }
local assistSpell

------------------------------------------------------------------ glow frames
local function EnsureGlow(icon)
    local glow = icon.glow
    if glow then return glow end
    glow = S.CreateFrame("Frame", nil, icon)
    glow:SetAllPoints(icon)
    glow:SetFrameLevel(icon:GetFrameLevel() + K.LEVEL.glow)
    glow:Hide()
    local flip = S.CreateTexture(glow, nil, "OVERLAY")
    flip:SetPoint("CENTER", icon, "CENTER")
    flip:Hide()
    glow.flip, glow.flipOn = flip, false
    glow.flipAnim = K.FlipBook(flip, K.GLOW[1])
    local edges = {}
    for i = 1, 4 do
        edges[i] = S.CreateTexture(glow, nil, "OVERLAY")
        edges[i]:Hide()
    end
    glow.edges, glow.edgesOn = edges, false
    glow.pulse = K.Pulse(glow, K.GLOW[3].pulse)
    icon.glow = glow
    fxIcons[icon] = true
    return glow
end

-- Style and color for an entry: per-spell choices first, then the bar.
local function GlowSpec(entry, view)
    local ov = entry and entry.ov or EMPTY
    local style = ov.glowStyle or view.glowStyle or 1
    if not K.GLOW[style] then style = 1 end
    if ov.glowColor then return style, K.HexRGB(ov.glowColor) end
    if view.glowTint then return style, view.glowR or 1, view.glowG or 1, view.glowB or 1 end
    return style
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
function E.SetGlow(icon, reason, on)
    if not icon then return end
    on = on and true or false
    if reason == "assist" then return E.Ants(icon, on) end
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
    ants = S.CreateFrame("Frame", nil, icon)
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

function E.Ants(icon, on)
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
function E.Tint(entry)
    local icon = entry.icon
    if not icon then return end
    local view = C.views[entry.slot]
    local code = entry.outOfRange and 4 or entry.usableCode or 1
    local gen = view and view.behaviorGen or 0
    if icon.tint == code and icon.tintGen == gen then return end
    icon.tint, icon.tintGen = code, gen
    if code == 4 then
        icon.tex:SetVertexColor(view and view.rangeR or .8, view and view.rangeG or .18, view and view.rangeB or .18)
    else
        local color = K.TINT[code]
        icon.tex:SetVertexColor(color[1], color[2], color[3])
    end
end
local Tint = E.Tint

function E.Usable(entry)
    -- Range tint wins while the action is out of range. Defer the native
    -- usability query until a range/target edge makes its result visible.
    if entry.outOfRange then return end
    local view = C.views[entry.slot]
    local code = 1
    if view and view.usable and entry.src ~= "p" then
        local usable, noPower
        if entry.src == "i" then
            if IsUsableItem then usable, noPower = IsUsableItem(entry.itemID or entry.id) end
        elseif not (entry.equipSlot or entry.src == "e") then
            local spell, category = entry.spell, entry.spellCategory
            if category and category ~= 0 then spell = entry.catSpell end
            if spell and IsUsable then usable, noPower = IsUsable(spell) end
        end
        if not (issecret and issecret(usable)) and usable == false then
            code = (not (issecret and issecret(noPower)) and noPower) and 2 or 3
        end
    end
    entry.usableCode = code
    local icon = entry.icon
    -- Usability broadcasts usually leave the visible tint unchanged. Avoid
    -- another Lua function call on that common path, while still repainting
    -- after a range or behavior change. All compared values are local codes.
    if icon and (icon.tint ~= code
        or icon.tintGen ~= (view and view.behaviorGen or 0)) then Tint(entry) end
end

------------------------------------------------------------------ range
local function Hold(spell)
    local count = rangeRefs[spell] or 0
    rangeRefs[spell] = count + 1
    if count == 0 and EnableRangeCheck then EnableRangeCheck(spell, true) end
end

local function Drop(spell)
    local count = (rangeRefs[spell] or 1) - 1
    if count > 0 then
        rangeRefs[spell] = count
        return
    end
    rangeRefs[spell] = nil
    if EnableRangeCheck then EnableRangeCheck(spell, false) end
end

local function Seed(entry, spell)
    local inRange = InRange and InRange(spell)
    entry.outOfRange = (Public(inRange) and inRange == false) or nil
end

-- Holds one reference on the entry's base spell (the ID Blizzard's viewer
-- checks) while wanted; there is no initial range event, so it seeds once.
function E.EnableRange(entry, on)
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
function E.Range(entry, inRange)
    if not entry.rangeSpell then return end
    local out = (Public(inRange) and inRange == false) or nil
    if entry.outOfRange == out then return end
    local wasOut = entry.outOfRange
    entry.outOfRange = out
    if wasOut and not out then
        E.Usable(entry)
    else
        Tint(entry)
    end
end

-- Target changes: re-read the held check without touching references.
function E.ReadRange(entry)
    local spell = entry.rangeSpell
    if not spell then return end
    local before = entry.outOfRange
    Seed(entry, spell)
    if before ~= entry.outOfRange then
        if before and not entry.outOfRange then
            E.Usable(entry)
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
    if not K.Pick(entry.ov or EMPTY, view, "readyGlow") or entry.cooling or entry.hidden then return false end
    local state = C.state
    if state.readyGlowCombat and not state.inCombat and not state.preview then return false end
    return true
end

function E.Proc(entry, on)
    entry.procOn = on and true or false
    local icon = entry.icon
    if not icon then return end
    local view = C.views[entry.slot]
    E.SetGlow(icon, "proc", view and ProcWanted(entry, view) or false)
end

-- Cold part of an update: runs when the icon, spell, choices or the bar's
-- behavior generation changed; seeds proc, range and usable state.
local function Bind(entry, icon, view)
    icon.fxEntry, icon.fxOv, icon.fxGen, icon.fxSpell = entry, entry.ov, view.behaviorGen, entry.spell
    if entry.src == "p" then return end
    local spell = entry.spell
    if spell and IsOverlayed then
        local shown = IsOverlayed(spell)
        entry.procOn = (Public(shown) and shown) and true or false
    end
    -- Entries bound after the last suggestion change still match it.
    local assist = assistSpell
    entry.assistOn = assist ~= nil and (spell == assist or entry.base == assist or entry.override == assist)
    E.EnableRange(entry, view.range == true)
    E.Usable(entry)
end

-- Re-derives every effect of one entry from its flags and its bar.
function E.Update(entry)
    local icon = entry.icon
    if not icon then return end
    local view = C.views[entry.slot]
    if not view then return end
    if icon.fxEntry ~= entry or icon.fxOv ~= entry.ov or icon.fxGen ~= view.behaviorGen or icon.fxSpell ~= entry.spell then
        Bind(entry, icon, view)
    end
    E.SetGlow(icon, "proc", ProcWanted(entry, view))
    E.SetGlow(icon, "ready", ReadyWanted(entry, view))
    E.Ants(icon, entry.assistOn == true and view.assist == true)
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
    E.Ants(icon, on and view ~= nil and view.assist == true)
end

local function Walk(list, fn, arg)
    if list then
        for i = 1, #list do fn(list[i], arg) end
        return
    end
    for _, plan in pairs(C.plans) do
        if plan.kind == 1 then
            local entries = plan.entries
            for i = 1, #entries do fn(entries[i], arg) end
        end
    end
end

-- Paints only on a suggestion change.
function E.Assist(spell)
    if spell ~= nil and not (Public(spell) and type(spell) == "number") then spell = nil end
    if spell == assistSpell then return end
    assistSpell = spell
    Walk(C.Index and C.Index.assist, AssistEntry, spell)
end

------------------------------------------------------------------ combat and release
local function ReadyEntry(entry)
    local icon = entry.icon
    local view = icon and C.views[entry.slot]
    if view then E.SetGlow(icon, "ready", ReadyWanted(entry, view)) end
end

-- Ready glows gated to combat flip here; everything else is untouched.
-- Only entries that want a ready glow (Index.ready) are walked; on a combat
-- edge (edge set) only while those glows wait for combat.
function E.CombatChanged(edge)
    if edge and not C.state.readyGlowCombat then return end
    Walk(C.Index and C.Index.ready, ReadyEntry)
end

-- Size changes from the icon style pass.
function E.Refit(icon)
    local entry = icon.entry
    local view = entry and C.views[entry.slot] or EMPTY
    Restyle(icon, entry, view)
    if icon.antsOn then SizeAnts(icon) end
end

-- Stops every visual on a recycled icon; the next Update re-seeds.
function E.ResetIcon(icon)
    icon.gProc, icon.gReady, icon.gAura = nil, nil, nil
    HideGlow(icon)
    E.Ants(icon, false)
    icon.fxEntry = nil
end

-- The entry left every bar: drop its range reference and assist state.
function E.Detach(entry)
    E.EnableRange(entry, false)
    entry.assistOn = nil
end

local function ClearAssist(entry) entry.assistOn = nil end

function E.ReleaseAll()
    for entry in pairs(ranged) do
        local spell = entry.rangeSpell
        entry.rangeSpell, entry.outOfRange, ranged[entry] = nil, nil, nil
        if spell then Drop(spell) end
    end
    for icon in pairs(fxIcons) do E.ResetIcon(icon) end
    Walk(nil, ClearAssist)
    assistSpell = nil
end

-- Test and diagnostics hook: range references currently held.
function E.RangeReferences()
    local total = 0
    for _, count in pairs(rangeRefs) do total = total + count end
    return total
end
