local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Glows on the suite action bars' buttons for entries with an action-bar
-- glow spell (ov.actionGlowSpell): one native aura slot per button shows
-- the entry's buff (mode 1) or its stacks (mode 2), drawn with the aura
-- layer's primitives (AuraGlows.lua). The action bars, their own
-- load-on-demand module, visit the buttons that hold a spell
-- (S.ForEachActionBarButtonForSpell, out of combat only); nothing here
-- tells them about aura presence or stack counts.
--  * Routes: slot, page, form and binding events come in storms (100+ at
--    login, spec and talent swaps). One trailing pass 0.2 s after the first
--    event follows them all, like the key texts (Keybinds.Request).
--  * In combat (and while auras are secret) a page can change under a
--    binding, and the action bars refuse the visit: the trailing pass only
--    switches each placed record off or back on by whether its button's
--    action slot still holds its spell (plain reads, container-level
--    switches: legal in combat). The full pass runs when combat ends.
--  * Containers cannot be freed. A button keeps its records; one that no
--    entry placed in a pass is switched off and taken by the next entry
--    of the same kind (glow mode and display) on that button.
--  * Display (opt-in, ov.actionAuraDisplay): the same aura button also
--    draws the aura's icon, swipe, duration or stacks over the action icon,
--    with the glow or without it (ov.actionAuraGlow).
local ActionGlows = { wanted = false, pending = false, targetWanted = false, styled = false }
C.ActionGlows = ActionGlows
local AuraButtons, K = C.AuraButtons, C.Const
local ACTION_GLOW = K.ACTION_GLOW
local Public = S.Public
local pairs, next, type = pairs, next, type
local DELAY = 0.2
local records = {} -- action button -> its records
local activeTargets = {}
local stamp = 0
-- The entry a pass visits the buttons for, its kind, whether its glow shows
-- and the stack threshold its glow uses (nil: no stack glow).
local currentEntry, currentView, currentKind, currentGlow, currentStacks
local armed = false

local Draw = C.AuraGlows
local NewGlow, ApplyStack, ApplyGlow = Draw.NewGlow, Draw.ApplyStack, Draw.ApplyGlow
local ApplyCombatGate, Overlay, BridgeStack = Draw.ApplyCombatGate, Draw.Overlay, Draw.BridgeStack

------------------------------------------------------------------ routes
-- The suite action bars own every button a record decorates: without
-- them running there is nothing to visit and no slot event to follow.
local function Visitor()
    local visit, bars = S.ForEachActionBarButtonForSpell, S.states.actionbars
    if type(visit) == "function" and bars and bars.active == true then return visit end
end

local function Wants(entry)
    local ov, ids = entry.ov, entry.auraIDs
    return ov ~= nil and ov.actionGlowSpell ~= nil and ids ~= nil and next(ids) ~= nil
end

-- The action slot a button shows now: the field Blizzard's action buttons
-- keep (native mode), else the secure "action" attribute the suite bars'
-- page handler writes. Plain reads, legal in combat.
local function ButtonSlot(button)
    local slot = button.action
    if not (Public(slot) and type(slot) == "number") then slot = button:GetAttribute("action") end
    if Public(slot) and type(slot) == "number" then return slot end
end

-- The spell an action slot casts: a spell, or a macro that shows one
-- (Blizzard's rule, AssistedCombatManager.lua). Nothing while secret.
local function SlotSpell(slot)
    local kind, id, sub = GetActionInfo(slot)
    if not (Public(kind) and Public(id) and Public(sub)) then return nil end
    if kind == "spell" or (kind == "macro" and sub == "spell") then return id end
end

------------------------------------------------------------------ kinds
-- What a record is besides its entry and route: its glow mode and what it
-- shows of the aura (rec.kind; Take, Unwanted). A pass gives each wanted
-- entry its kind once (kinds); a kind is one table per combination, so a
-- record compares its kind in one step. The glow alone: GLOW_ONLY[mode].
-- Whether the glow shows (ov.actionAuraGlow) is no part of it: the same
-- record lights its glow or leaves it dark (Visit: rec.ov).
local CDM = NS.CDM
local ACTION_AURA, GLOW_HIDDEN = CDM.ACTION_AURA, CDM.ACTION_AURA_GLOW.HIDE
-- The display's regions: its icon, the full aura, or only its duration
-- swipe, duration text or stacks.
local SHOWS = {
    [ACTION_AURA.ICON] = { icon = true },
    [ACTION_AURA.FULL] = { icon = true, swipe = true, time = true, count = true },
    [ACTION_AURA.SWIPE] = { swipe = true },
    [ACTION_AURA.TIME] = { time = true },
    [ACTION_AURA.STACKS] = { count = true },
}
local GLOW_ONLY, DISPLAYS = {}, {}
for _, mode in pairs(ACTION_GLOW) do
    GLOW_ONLY[mode], DISPLAYS[mode] = { mode = mode }, {}
    for display, shows in pairs(SHOWS) do DISPLAYS[mode][display] = { mode = mode, shows = shows } end
end
local kinds = {} -- entry key -> its kind in this pass (wanted entries only)

-- An entry's kind; nil when it would show nothing (no display, glow hidden).
local function Kind(ov)
    local mode, display = ov.actionGlowMode or ACTION_GLOW.PRESENT, ov.actionAuraDisplay
    local displays = SHOWS[display] and DISPLAYS[mode]
    if displays then return displays[display] end
    if ov.actionAuraGlow ~= GLOW_HIDDEN then return GLOW_ONLY[mode] end
end

------------------------------------------------------------------ display
-- The display's regions are the record's own aura button's, bound in
-- initializeFrame: Blizzard draws every aura value in C, no Lua reads one,
-- and nothing runs per aura change. Above the aura button: the swipe, the
-- glow, the texts.
-- The active buff's swipe opacity over a cooldown icon (AuraButtons StyleIcon).
local SWIPE_ALPHA = .55
-- Blizzard's icon border crop, where the action icon's own is unreadable.
local CROP = .08

-- The action button's icon (`icon` on Blizzard's and the suite's buttons):
-- the display covers it and takes its crop and shape. Plain reads, out of
-- combat.
local function IconOf(button) return button.icon end
local function Crop(target)
    if target.GetTexCoord then
        local l, t, _, _, _, _, r, b = target:GetTexCoord()
        if Public(l) and Public(t) and Public(r) and Public(b) and type(l) == "number" and type(t) == "number"
            and type(r) == "number" and type(b) == "number" then return l, r, t, b end
    end
    return CROP, 1 - CROP, CROP, 1 - CROP
end

-- The action icon's shape is the masks its owner put on it (MSUF's shape,
-- the Suite's own circle, Masque's): the display's icon takes the same mask
-- objects, so it has the owner's exact geometry without asking the owner.
-- Only masks of the action button itself (the display lies inside it);
-- GetMaskTexture answers secret for a secret hierarchy. A Cooldown has no
-- getter for its swipe texture: the display's swipe takes the first mask's
-- file as its silhouette, as MSUF's shapes give theirs (an atlas mask
-- leaves it square). lk.masks keeps the masks read, lk.mgen counts their
-- changes, lk.swipe holds the silhouette.
local function Silhouette(mask)
    local atlas = mask:GetAtlas()
    if not Public(atlas) or (atlas ~= nil and atlas ~= "") then return nil end
    local file = mask:GetTexture()
    if Public(file) and (type(file) == "string" or type(file) == "number") then return file end
end
local function ReadMasks(button, target, lk)
    local masks = lk.masks or {}
    local n, changed, swipe = 0, false, nil
    local count = target:GetNumMaskTextures()
    if Public(count) and type(count) == "number" then
        for i = 1, count do
            local mask = target:GetMaskTexture(i)
            local owner = Public(mask) and mask and mask:GetParent()
            if Public(owner) and owner == button then
                n = n + 1
                if masks[n] ~= mask then masks[n], changed = mask, true end
                if n == 1 then swipe = Silhouette(mask) end
            end
        end
    end
    for i = #masks, n + 1, -1 do masks[i], changed = nil, true end
    if changed then lk.mgen = (lk.mgen or 0) + 1 end
    lk.masks, lk.swipe = masks, S.ActionBarButtonSwipe(button) or swipe
end

-- The action bars' looks as this bridge knows them: a new generation with
-- each of their style events and with each new subscription (unheard
-- events). A displaying record reads its action icon's crop and masks once
-- per generation (and when made); other passes read nothing of the icon.
local looks = 0

-- What a pass hands a displaying record: its bar, the countdown binding of
-- the warning threshold (the entry's, else the Text section's) and, with a
-- new generation of looks, the action icon's crop, masks and silhouette.
local function DisplayLook(rec, view, ov)
    local shows, lk = rec.shows, rec.lk
    rec.view = view
    rec.textOpts = shows.time and K.DurationText(ov.threshold, ov.tenthsSeconds, ov.thresholdColor) or nil
    if lk.looks == looks then return end
    lk.looks = looks
    local target = IconOf(rec.button)
    if shows.icon then lk.l, lk.r, lk.t, lk.b = Crop(target) end
    if shows.icon or shows.swipe then ReadMasks(rec.button, target, lk) end
end

-- The display's regions in a new aura button (initializeFrame); BindDisplay
-- binds them last. Returns the glow's level: above the swipe.
local function NewDisplay(rec, part, level)
    local shows, button = rec.shows, part.button
    local target = IconOf(rec.button)
    local d = { target = target }
    part.display = d
    if shows.icon then
        d.icon = button:CreateTexture(nil, "ARTWORK")
        d.icon:SetAllPoints(target)
        d.masks = {}
    end
    if shows.swipe then
        local swipe = K.Child("Cooldown", button, "CooldownFrameTemplate")
        swipe:SetAllPoints(target)
        swipe:SetFrameLevel(level)
        swipe:SetDrawBling(false)
        swipe:SetDrawEdge(false)
        swipe:SetHideCountdownNumbers(true)
        -- Aura swipes run reversed, as on the buff icons.
        swipe:SetReverse(true)
        d.cd, level = swipe, level + 1
    end
    if shows.time or shows.count then
        local texts = K.Child("Frame", button)
        texts:SetAllPoints(button)
        texts:SetFrameLevel(level + 1)
        if shows.time then d.time = texts:CreateFontString(nil, "OVERLAY") end
        if shows.count then d.count = texts:CreateFontString(nil, "OVERLAY") end
    end
    return level
end

local function Font(fs, size, r, g, b)
    local state = C.state
    S.SetStyledFont(fs, state.font, size, state.fontFlags, state.fontRendering, state.fontShadow, state.fontShadowOpacity,
        state.fontShadowDistance)
    fs:SetTextColor(r or 1, g or 1, b or 1)
end

-- The aura icon's masks: the action icon's (lk.masks), swapped when they
-- changed (lk.mgen).
local function Mask(d, lk)
    local have, want, icon = d.masks, lk.masks, d.icon
    for i = #have, 1, -1 do
        icon:RemoveMaskTexture(have[i])
        have[i] = nil
    end
    for i = 1, #want do
        icon:AddMaskTexture(want[i])
        have[i] = want[i]
    end
end

-- Fonts, colors, places, crop and shape from the bar's look (its style
-- generation also moves with the Text section), the button's size and the
-- action icon; the same look makes no call. A square swipe keeps its
-- template's texture.
local function Styled(d, rec)
    local lk, view = rec.lk, rec.view
    return d.view == view and d.gen == view.styleGen and d.relook == view.relook and d.w == lk.w and d.h == lk.h
        and d.px == lk.px and d.l == lk.l and d.r == lk.r and d.t == lk.t and d.b == lk.b and d.swipe == lk.swipe
        and d.mgen == lk.mgen
end
local function StyleDisplay(rec, part)
    local d, lk, view = part.display, rec.lk, rec.view
    if Styled(d, rec) then return end
    d.view, d.gen, d.relook, d.w, d.h, d.px = view, view.styleGen, view.relook, lk.w, lk.h, lk.px
    d.l, d.r, d.t, d.b = lk.l, lk.r, lk.t, lk.b
    if d.icon then
        d.icon:SetTexCoord(lk.l, lk.r, lk.t, lk.b)
        if d.mgen ~= lk.mgen then Mask(d, lk) end
    end
    if d.cd then
        local r, g, b = K.AuraSwipeRGB(view)
        d.cd:SetSwipeColor(r, g, b, SWIPE_ALPHA)
        if d.swipe ~= lk.swipe then d.cd:SetSwipeTexture(lk.swipe or K.WHITE) end
    end
    d.swipe, d.mgen = lk.swipe, lk.mgen
    local state, font, time, count = C.state, K.FONT, d.time, d.count
    if time then
        Font(time, K.TextSize(view.cdSize, font.countdown, lk.h), state.cdR, state.cdG, state.cdB)
        time:ClearAllPoints()
        time:SetPoint("CENTER", d.target, "CENTER", 0, 0)
    end
    if count then
        local pos = K.POINTS[view.stackPos] and view.stackPos or 9
        local point, inset = K.POINTS[pos], 2 * lk.px
        Font(count, K.TextSize(view.stackSize, font.stacks, lk.h), state.stackR, state.stackG, state.stackB)
        count:ClearAllPoints()
        count:SetPoint(point, d.target, point, K.POINT_X[pos] * inset, K.POINT_Y[pos] * inset)
        count:SetJustifyH(K.JUSTIFY[pos])
    end
end

-- The countdown binding of a new warning threshold (out of combat, open).
local function BindText(rec, part)
    local d = part.display
    if not d.time or d.opts == rec.textOpts then return end
    d.opts = rec.textOpts
    part.button:SetDurationText(d.time, d.opts)
end
-- The display's regions handed to the aura button; bound regions seal.
-- Without a formatter Blizzard shows stacks from two, as on its buttons.
local function BindDisplay(rec, part)
    local d, button = part.display, part.button
    if d.icon then button:SetIcon(d.icon) end
    if d.cd then button:SetDurationCooldown(d.cd) end
    BindText(rec, part)
    if d.count then button:SetApplicationCount(d.count) end
end

------------------------------------------------------------------ records
-- Action-bar bridges bind their own native aura slot, without exporting
-- aura presence or stack counts to the action-bar controller.
local function InitPrimary(rec, button)
    Overlay(button, rec.button)
    local level = button:GetFrameLevel() + 1
    local part = { button = button, pos = 1, rec = rec }
    rec.parts[1] = part
    if rec.shows then
        level = NewDisplay(rec, part, level)
        StyleDisplay(rec, part)
    end
    if rec.mode == ACTION_GLOW.STACKS then
        BridgeStack(rec, part, rec.ov, level)
    else
        part.glow = NewGlow(button, button, level)
        ApplyGlow(rec, part, rec.ov, false)
        ApplyCombatGate(part.glow, part.gOn, false)
        part.bound = true
    end
    if rec.shows then BindDisplay(rec, part) end
end

-- B is the outer native visibility gate; the original A/stack presentation
-- stays inside it. Hidden containers unregister their native aura listeners
-- and refresh on show. Construct both levels during initializeFrame, before
-- Blizzard seals the outer button (AuraContainerFrameProviders.lua).
local function InitBridge(rec, button)
    if not rec.conditional then return InitPrimary(rec, button) end
    Overlay(button, rec.button)
    rec.conditionButton = button
    local inner = CreateFrame("AuraContainer", nil, button, "CustomAuraContainerTemplate")
    NS.Client.RealAurasOnly(inner)
    inner:SetAllPoints(button)
    inner:SetUnit(rec.unit)
    rec.primary = inner
    inner:AddAuraSlot("glow", rec.filter, { candidateFilters = { includeSpellIDs = rec.ids },
        initializeFrame = function(auraButton) InitPrimary(rec, auraButton) end })
    inner:SetEnabled(true)
    inner:Show()
end

local function StyleBridge(rec)
    if not AuraButtons.Mutable(rec) then return false end
    if rec.conditionButton then
        local open = rec.conditionButton:CanBeAccessedInContext()
        if not Public(open) or open ~= true then return false end
    end
    local part = rec.parts[1]
    if not part then return true end
    if part.display then
        StyleDisplay(rec, part)
        BindText(rec, part)
    end
    if part.glow then
        ApplyGlow(rec, part, rec.ov, false)
        ApplyCombatGate(part.glow, part.gOn, false)
    end
    if part.stack then
        ApplyStack(rec, part, rec.ov, false)
        ApplyCombatGate(part.stack.glow, part.stack.on, false)
    end
    return true
end

-- The record of this entry on the button: its own from the last pass,
-- else one that no entry placed last pass, of the same kind.
local function Take(list, key, kind, conditional, unit)
    for i = 1, #list do
        local rec = list[i]
        if rec.key == key and rec.kind == kind and rec.conditional == conditional and rec.unit == unit then return rec end
    end
    for i = 1, #list do
        local rec = list[i]
        if rec.free and rec.kind == kind and rec.conditional == conditional and rec.unit == unit then return rec end
    end
end

-- A new record: its own native aura container on the button. mode and
-- shows (the display's SHOWS row, nil for the glow only) are its kind's.
local function NewRecord(list, button, kind, conditional, unit)
    local frame = CreateFrame("AuraContainer", nil, button, "CustomAuraContainerTemplate")
    -- No Edit Mode samples on the action buttons (MSUF_Suite/Core/Platform.lua).
    NS.Client.RealAurasOnly(frame)
    frame:SetAllPoints(button)
    frame:SetUnit(conditional and "player" or unit)
    local rec = { frame = frame, parts = {}, lk = {}, kind = kind, mode = kind.mode, shows = kind.shows, ov = {}, ids = {},
        button = button, conditional = conditional, secondaryIDs = {}, unit = unit,
        filter = unit == "target" and "HARMFUL|PLAYER" or "HELPFUL" }
    list[#list + 1] = rec
    return rec
end

local function Switch(rec, on)
    if rec.on == on then return end
    rec.on = on
    if rec.unit == "target" then activeTargets[rec] = on and true or nil end
    rec.frame:SetEnabled(on)
end

-- A hidden glow stays dark: the presence glow unlit, the stack glow without
-- a threshold (currentGlow, currentStacks; AuraGlows ApplyGlow, StackRule).
local function Visit(button)
    local entry, view, kind = currentEntry, currentView, currentKind
    local ov = entry.ov
    local width, height = button:GetSize()
    if not Public(width) or not Public(height) or width <= 0 or height <= 0 then return end
    local list = records[button]
    if not list then
        list = {}
        records[button] = list
    end
    local secondary = ov.actionGlowRequireSpell
    local conditional = secondary ~= nil
    local unit = ov.actionGlowUnit == 2 and "target" or "player"
    local rec = Take(list, entry.key, kind, conditional, unit) or NewRecord(list, button, kind, conditional, unit)
    rec.stamp, rec.free, rec.key, rec.spell = stamp, false, entry.key, ov.actionGlowSpell
    rec.lk.w, rec.lk.h, rec.lk.px = width, height, K.Px()
    rec.gStyle, rec.gTint, rec.gR, rec.gG, rec.gB = view.glowStyle, view.glowTint, view.glowR, view.glowG, view.glowB
    rec.ov.auraGlow = currentGlow
    rec.ov.glowStyle, rec.ov.glowColor = ov.glowStyle, ov.glowColor
    rec.ov.stackGlow, rec.ov.stackGlowOp = currentStacks, ov.stackGlowOp
    if kind.shows then DisplayLook(rec, view, ov) end
    if rec.bound and not StyleBridge(rec) then
        ActionGlows.pending = true
        return
    end
    local ids = entry.auraIDs
    local different = not K.SameSet(rec.ids, ids)
    if different then K.CopySet(rec.ids, ids) end
    local secondChanged = rec.secondarySpell ~= secondary
    if secondChanged then
        C.wipe(rec.secondaryIDs)
        rec.secondaryIDs[secondary] = true
        rec.secondarySpell = secondary
    end
    if not rec.bound then
        rec.frame:AddAuraSlot("glow", conditional and "HELPFUL" or rec.filter, {
            candidateFilters = { includeSpellIDs = conditional and rec.secondaryIDs or rec.ids },
            initializeFrame = function(auraButton) InitBridge(rec, auraButton) end })
        rec.bound = true
    else
        if different then (rec.primary or rec.frame):SetAuraSlotCandidateFilters("glow", { includeSpellIDs = rec.ids }) end
        if secondChanged then rec.frame:SetAuraSlotCandidateFilters("glow", { includeSpellIDs = rec.secondaryIDs }) end
    end
    Switch(rec, true)
    rec.frame:Show()
end

local function Free(rec)
    rec.free = true
    Switch(rec, false)
    rec.frame:Hide()
    Draw.ReleaseGlows(rec)
end
-- Before a pass: records whose entry no longer asks for their kind (or
-- nothing at all: kinds holds wanted entries only) are free, so the pass
-- can hand them to another entry at once.
local function Unwanted()
    for _, list in pairs(records) do
        for i = 1, #list do
            local rec = list[i]
            if not rec.free and kinds[rec.key] ~= rec.kind then Free(rec) end
        end
    end
end
-- After a pass: records no entry placed (their spell left the button).
local function Sweep()
    for _, list in pairs(records) do
        for i = 1, #list do
            local rec = list[i]
            if rec.stamp ~= stamp and not rec.free then Free(rec) end
        end
    end
end

-- In combat or while auras are secret: a placed record stays on only while
-- its button still shows its spell.
local function Follow()
    C.ActionUsableGlows.Follow()
    for _, list in pairs(records) do
        for i = 1, #list do
            local rec = list[i]
            if not rec.free then
                local slot = ButtonSlot(rec.button)
                Switch(rec, slot ~= nil and SlotSpell(slot) == rec.spell)
            end
        end
    end
end

-- A same-token retarget need not deliver UNIT_AURA. FullAuraRebuild resets
-- native slot assignments even when B is unchanged; its Hide/Show reseeds
-- the sealed inner target container without any addon call into that child.
function ActionGlows.TargetChanged()
    for rec in pairs(activeTargets) do rec.frame:UpdateAllAuras() end
end

------------------------------------------------------------------ style changes
-- The action bars restyled or laid out their buttons (zoom, shape, size;
-- once per real refresh): the displays take the new crop, masks and text
-- sizes in the trailing pass, in combat when it ends. Subscribed only while
-- an entry asks for a display.
local STYLE_EVENT = "MSUFSuite.ActionBars.StyleChanged"
local function Restyled()
    looks = looks + 1
    ActionGlows.RouteChanged()
end
local function WatchStyle(on)
    if ActionGlows.styled == on then return end
    ActionGlows.styled = on
    if on then
        looks = looks + 1
        EventRegistry:RegisterCallback(STYLE_EVENT, Restyled, ActionGlows)
    else
        EventRegistry:UnregisterCallback(STYLE_EVENT, ActionGlows)
    end
end

------------------------------------------------------------------ passes
function ActionGlows.Refresh()
    C.ActionUsableGlows.Refresh()
    local visit = C.M.active and Visitor() or nil
    local wanted, targetWanted, styled = false, false, false
    C.wipe(kinds)
    if visit then
        for _, entry in pairs(C.entries) do
            local kind = Wants(entry) and Kind(entry.ov)
            if kind then
                kinds[entry.key] = kind
                wanted = true
                if entry.ov.actionGlowUnit == 2 then targetWanted = true end
                if kind.shows then styled = true end
            end
        end
    end
    -- The slot, page and form events follow what is wanted (Events).
    if ActionGlows.wanted ~= wanted or ActionGlows.targetWanted ~= targetWanted then
        ActionGlows.wanted, ActionGlows.targetWanted = wanted, targetWanted
        C.Flush.dirty.events = true
        C.Schedule()
    end
    WatchStyle(styled)
    if NS.IsCombatLocked() or not AuraButtons.Quiet() then
        ActionGlows.pending = true
        return
    end
    -- A new record's slot waits for Forever's gamepad panel to close.
    if AuraButtons.Blocked(ActionGlows, ActionGlows.Refresh) then
        ActionGlows.pending = true
        return
    end
    ActionGlows.pending = false
    stamp = stamp + 1
    Unwanted()
    if wanted then
        for _, entry in pairs(C.entries) do
            local kind = kinds[entry.key]
            if kind then
                local ov = entry.ov
                currentEntry, currentView, currentKind = entry, C.views[entry.slot], kind
                currentGlow = ov.actionAuraGlow ~= GLOW_HIDDEN
                currentStacks = currentGlow and ov.stackGlow or nil
                if currentView then visit(ov.actionGlowSpell, Visit) end
            end
        end
    end
    currentEntry, currentView, currentKind = nil, nil, nil
    Sweep()
end

local function Fire()
    armed = false
    if not C.M.active then return end
    if NS.IsCombatLocked() or not AuraButtons.Quiet() then
        Follow()
        ActionGlows.pending = true
        return
    end
    ActionGlows.Refresh()
end
local FIRE_WAKE = C.NewWake(Fire)

-- A slot, page, form or binding event: one trailing pass for the storm.
-- always: the action bars started or stopped (what is wanted may change).
function ActionGlows.RouteChanged(always)
    if armed or not (ActionGlows.wanted or C.ActionUsableGlows.wanted or always) then return end
    armed = true
    C.Wake(FIRE_WAKE, DELAY)
end

function ActionGlows.Release()
    C.ActionUsableGlows.Release()
    for _, list in pairs(records) do
        for i = 1, #list do Free(list[i]) end
    end
    WatchStyle(false)
    ActionGlows.wanted, ActionGlows.pending, ActionGlows.targetWanted = false, false, false
end

-- Public action routes are shared with the separate usability-glow owner.
ActionGlows.Visitor, ActionGlows.ButtonSlot, ActionGlows.SlotSpell = Visitor, ButtonSlot, SlotSpell
