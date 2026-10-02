local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- One aura container: its record, groups and slots, and its place on the
-- bar. Auras.lua syncs every bar through these.
--  * Groups and slots cannot be removed, so they are updated in place and
--    surplus ones switched off; structure changes out of combat only.
--  * Containers cannot be freed either: retired ones are disabled, hidden
--    and parked in a per-bar pool for reuse (never dropped from it).
--  * Regions are made at button creation, so a change of region set swaps
--    containers (Ensure); looks and per-spell choices restyle in place
--    (Refit, AuraButtons.lua).
local K = C.Const
local AuraContainers = {}
C.AuraContainers = AuraContainers
local AuraButtons = C.AuraButtons
local TextOpts, Look, Hush, Mutable = AuraButtons.TextOpts, AuraButtons.Look, AuraButtons.Hush, AuraButtons.Mutable
local Style, ApplyEntry, Init = AuraButtons.Style, AuraButtons.ApplyEntry, AuraButtons.Init

-- The containers are created with the client's CreateFrame: they lay out
-- and seal Blizzard's buttons, so MSUF's pixel-layout policy
-- (S.CreateFrame) must not round what Blizzard positions. Frames on our
-- own bars use S.CreateFrame.
local CreateFrame = CreateFrame
local next, type = next, type
local tremove = table.remove
local Public = S.Public
local EMPTY = C.EMPTY

local STRATA = K.STRATA
local HELP_MINE, HELP_ANY, HARM_MINE = "HELPFUL|PLAYER", "HELPFUL", "HARMFUL|PLAYER"
-- No aura passes this (maxDuration also drops permanent auras): 12.1.0
-- slots have no enable flag.
local NONE = { maxDuration = 0 }
-- Container levels above the bar frame: aura bars sit over their host (+1)
-- and cells (+2); overlays sit on the icon (+1) at swipe height, under the
-- icon's glows and text.
local AURA_LEVEL = 4
local OVER_LEVEL = 1 + K.LEVEL.cd

-- Shared with the bar sync (Auras.lua): live containers, overlay icons,
-- hidden bars, the entries being built (list/where), the compact geometry
-- (geo) and the bindings the bar asks for (need).
local live = {}     -- live[slot] = { aura = {player=rec,target=rec}, over = {...} }
local pools = {}    -- retired container records per bar
local overIcon = {} -- cooldown icon -> bar slot, for icons that carry an overlay
local unseen = {}   -- bar slot -> true while Visibility hides the bar
local list, where, cand, lay, geo = {}, {}, {}, {}, {}
local groupOpts, slotOpts = { maxFrameCount = 1 }, {}
local need = {}     -- bindings the bar being synced asks for: glow, stack, kit
local watching = {} -- ancestor watch frame -> its kit container record
local stamp = 0
AuraContainers.live, AuraContainers.overIcon, AuraContainers.unseen = live, overIcon, unseen
AuraContainers.list, AuraContainers.where, AuraContainers.geo, AuraContainers.need = list, where, geo, need

------------------------------------------------------------------ helpers
local SameSet, CopySet = K.SameSet, K.CopySet

-- includeSpellIDs of an entry: Resolve gives every aura entry (and every
-- cooldown with an aura) its auraIDs; callers copy what they keep.
local function Ids(entry)
    local map = entry.auraIDs
    if type(map) == "table" and next(map) ~= nil then return map end
end

-- The unit Resolve gave the entry (harmful IDs: target, else player; a
-- per-spell "Track on" choice wins). "both": the player and the target
-- container.
local function UnitOf(entry) return entry.unit or "player" end
local function OnUnit(entry, unit)
    local u = UnitOf(entry)
    return u == unit or u == "both"
end
-- Own harmful auras on a friendly target bypass spell-ID filters (Blizzard's
-- identity rule), so target containers pause while the target is friendly.
local function FriendlyTarget()
    local assist = UnitCanAssist("player", "target")
    return Public(assist) and assist == true
end
-- Own helpful auras (any caster for custom "a" entries) or own harmful
-- auras on the target.
local function FilterOf(entry, unit)
    if unit == "target" then return HARM_MINE end
    return entry.src == "a" and HELP_ANY or HELP_MINE
end
-- The part of an aura bar an entry takes: e.unit=="target" entries the
-- target part; a per-spell "both" counts in the player part. Player and
-- target auras live in two containers that cannot interleave (and Blizzard
-- forbids anchoring one AuraContainer to another); Layout.FixedAuras is the
-- one rule for how the two parts are arranged.
local function TargetRow(entry)
    return entry.unit == "target"
end

-- An ancestor of a kit container shown or hidden (the UI hidden for a
-- cinematic, the bar hidden): a plain frame beside the container on the
-- same host hears it and hushes the container.
local function Woke(watch)
    local rec = watching[watch]
    if rec then Hush(rec) end
end

------------------------------------------------------------------ groups and slots
-- A group or slot shows while the build wants it (on) and, for overlays,
-- while the layout shows its cooldown icon (not shut). Container-level
-- switches only: legal at any time, in combat too; unchanged state makes
-- no call. 12.1.0 lacks SetAuraSlotEnabled and SetAuraGroupEnabled: an off
-- slot carries NONE as its candidate filters and gets its spell list back
-- when it comes on.
local function Apply(rec, k)
    local on = rec.on[k] == true and not rec.shut[k]
    if rec.act[k] == on then return end
    rec.act[k] = on
    local container, key = rec.frame, rec.keys[k]
    if rec.fixed then
        if container.SetAuraSlotEnabled then
            container:SetAuraSlotEnabled(key, on)
        elseif on then
            cand.includeSpellIDs = rec.ids[k]
            container:SetAuraSlotCandidateFilters(key, cand)
            cand.includeSpellIDs = nil
        else
            container:SetAuraSlotCandidateFilters(key, NONE)
        end
    elseif container.SetAuraGroupEnabled then
        container:SetAuraGroupEnabled(key, on)
    else
        -- 12.1.0 groups have no enable flag either: a zero frame count hides them.
        container:SetAuraGroupMaxFrameCount(key, on and 1 or 0)
    end
end

local function Update(rec, k, entry, filter, set)
    local container, key, fixed = rec.frame, rec.keys[k], rec.fixed
    local have = rec.ids[k]
    -- Spell list first, then the filter string: the group never passes
    -- through a state without its spell list. A 12.1.0 slot that is off
    -- keeps NONE until Apply hands it the list.
    if not SameSet(have, set) then
        CopySet(have, set)
        if not fixed or container.SetAuraSlotEnabled or rec.act[k] then
            cand.includeSpellIDs = have
            if fixed then
                container:SetAuraSlotCandidateFilters(key, cand)
            else
                container:SetAuraGroupCandidateFilters(key, cand)
            end
            cand.includeSpellIDs = nil
        end
    end
    if rec.filter[k] ~= filter then
        rec.filter[k] = filter
        if fixed then
            container:SetAuraSlotFilterString(key, filter)
        else
            container:SetAuraGroupFilterString(key, filter)
        end
    end
    rec.on[k], rec.entry[k] = true, entry
    Apply(rec, k)
end

-- One-frame groups: the gap between them is group spacing (only positive
-- values apply), the line gap follows the bar spacing.
local function GroupLayout(rec, index)
    lay.elementWidth, lay.elementHeight = rec.gw, rec.gh
    lay.elementSpacing, lay.lineSpacing = 0, rec.gc
    lay.groupSpacing, lay.groupLineSpacing = rec.gp, rec.gc
    lay.layoutIndex = index
    return lay
end

-- The buttons after a build: restyled when the look changed, per-spell
-- choices applied where they differ. Returns false when sealed buttons
-- would need a write they refuse.
local function Refit(rec, look)
    if not AuraButtons.Finish(rec) then return false end
    local parts = rec.parts
    local restyle = rec.look ~= look
    local dirty = restyle
    if not dirty then
        for i = 1, #parts do
            local part = parts[i]
            local entry = rec.on[part.pos] and rec.entry[part.pos]
            if entry and ApplyEntry(rec, part, entry, true) then
                dirty = true
                break
            end
        end
    end
    if not dirty then return true end
    if not Mutable(rec) then return false end
    for i = 1, #parts do
        local part = parts[i]
        if restyle then Style(rec, part) end
        local entry = rec.on[part.pos] and rec.entry[part.pos]
        if entry then ApplyEntry(rec, part, entry, false) end
    end
    rec.look = look
    return true
end

-- Brings a container to list[1..n]: compact mode keys groups by position,
-- fixed mode keys slots by their anchor (cell or cooldown icon). Returns
-- false when sealed buttons would need a write they refuse (Refit).
local function Build(rec, view, n)
    local container, fixed, over, slot = rec.frame, rec.fixed, rec.fam == "over", rec.slot
    local look = Look(rec, view)
    local parts = rec.parts
    if parts[1] == nil then rec.look = look end
    -- Bar-level glow and text choices behind the per-spell ones.
    rec.glowAll = view.auraGlow == true
    rec.gStyle, rec.gTint = view.glowStyle, view.glowTint == true
    rec.gR, rec.gG, rec.gB = view.glowR or 1, view.glowG or 1, view.glowB or 1
    rec.timeBar, rec.stackBar, rec.topBar = K.BarTime(view), K.BarStacks(view, false), K.BarStacksTop(view)
    rec.colorAt, rec.colorHex = view.barStackColorAt or 0, view.barStackColor or "ff6633"
    local threshold = C.state.threshold
    local keys = rec.keys
    stamp = stamp + 1
    for i = 1, n do
        local entry = list[i]
        local set, filter = Ids(entry), FilterOf(entry, rec.unit)
        local k
        if fixed then
            local anchor = over and entry.icon or C.Layout.Cell(slot, where[i])
            k = rec.byAnchor[anchor]
            if not k then
                k = #keys + 1
                keys[k] = rec.prefix .. k
                rec.byAnchor[anchor], rec.anchors[k] = k, anchor
            end
            -- An overlay starts from the layout's shown state of its icon
            -- (layShown); the layout reports every change (Auras.OverlayShown).
            if over then
                overIcon[anchor] = slot
                rec.shut[k] = anchor.layShown ~= true
            end
        else
            k = i
            if not keys[k] then keys[k] = rec.prefix .. k end
        end
        rec.mark[k] = stamp
        if rec.text then rec.topts[k] = TextOpts((entry.ov or EMPTY).threshold or threshold) end
        if rec.ids[k] then
            Update(rec, k, entry, filter, set)
            if not fixed and (rec.li[k] ~= entry.index or rec.lg[k] ~= rec.geo) then
                rec.li[k], rec.lg[k] = entry.index, rec.geo
                container:SetAuraGroupLayout(keys[k], GroupLayout(rec, entry.index))
            end
        else
            rec.entry[k], rec.filter[k], rec.ids[k], rec.on[k], rec.act[k] = entry, filter, CopySet({}, set), true, true
            cand.includeSpellIDs = set
            local function init(button) Init(rec, button, k) end
            if fixed then
                slotOpts.candidateFilters, slotOpts.initializeFrame = cand, init
                container:AddAuraSlot(keys[k], filter, slotOpts)
            else
                rec.li[k], rec.lg[k] = entry.index, rec.geo
                groupOpts.candidateFilters, groupOpts.initializeFrame, groupOpts.layout = cand, init, GroupLayout(rec, entry.index)
                -- Of the ten buttons Blizzard pre-builds, only the one it
                -- shows gets regions (AuraButtons.BeginBatch).
                local collected = AuraButtons.BeginBatch(rec)
                container:AddAuraGroup(keys[k], filter, groupOpts)
                if collected then AuraButtons.EndBatch(rec, k) end
            end
            cand.includeSpellIDs = nil
            slotOpts.initializeFrame, groupOpts.initializeFrame = nil, nil
            -- An overlay on a hidden icon starts off.
            Apply(rec, k)
        end
    end
    for k = 1, #keys do
        if rec.on[k] and rec.mark[k] ~= stamp then
            rec.on[k] = false
            Apply(rec, k)
        end
    end
    return Refit(rec, look)
end

------------------------------------------------------------------ containers
-- A container shows unless its bar is hidden (SetBarMouse) or, in the
-- preview, it is a compact aura container (the preview draws every entry
-- on its cell instead). Container widget writes: legal in combat.
local function Show(rec)
    local shown = not (unseen[rec.slot] or (AuraContainers.preview and rec.fam == "aura" and not rec.fixed))
    if rec.shown ~= shown then
        rec.shown = shown
        Hush(rec)
        rec.frame:SetShown(shown)
    end
end

local function Bar(slot)
    local bar = C.bars[slot]
    if not bar then bar = C.Layout.EnsureBar(slot) end
    return bar and bar.frame and bar or nil
end

local function Retire(slot, fam, unit)
    local fams = live[slot]
    local byUnit = fams and fams[fam]
    local rec = byUnit and byUnit[unit]
    if not rec then return end
    byUnit[unit] = nil
    rec.enabled, rec.shown = false, false
    Hush(rec)
    rec.frame:SetEnabled(false)
    rec.frame:Hide()
    C.AuraGlows.ReleaseGlows(rec)
    -- Every retired container stays reusable: it cannot be freed, so one
    -- dropped from the pool would only be replaced by a new one.
    local pool = pools[slot]
    if not pool then
        pool = {}
        pools[slot] = pool
    end
    pool[#pool + 1] = rec
end

-- Same unit first: a unit switch costs the container a full rebuild. Taken
-- even while buttons are sealed: the structure applies at once and the
-- look follows when they open.
local function Acquire(slot, fam, bind, unit)
    local pool = pools[slot]
    if not pool then return nil end
    for pass = 1, 2 do
        for i = #pool, 1, -1 do
            local rec = pool[i]
            if rec.fam == fam and rec.bind == bind and (pass == 2 or rec.unit == unit) then
                tremove(pool, i)
                return rec
            end
        end
    end
end

-- The live container of one bar, family and unit. Regions are made at
-- button creation, so a change of region set (mode, countdown text, name,
-- pandemic, glow, stack glow, kit sensor, bar direction) swaps containers;
-- `need` says which the bar's entries ask for. fresh: a new container for
-- buttons that refused a restyle (a pooled one would refuse it too).
local function Ensure(slot, fam, unit, role, fixed, view, fresh)
    local bar = Bar(slot)
    if not bar then return nil end
    local fams = live[slot]
    if not fams then
        fams = { aura = {}, over = {} }
        live[slot] = fams
    end
    local byUnit = fams[fam]
    local text, name, fill = need.text == true, false, K.BAR_FILL.DRAIN
    if role == "bar" then
        name, fill = view.barName ~= false, view.barFill == K.BAR_FILL.FILL and K.BAR_FILL.FILL or K.BAR_FILL.DRAIN
    end
    local pan = fam == "aura" and view.pandemic == true
    local glow = fam == "aura" and (view.auraGlow == true or need.glow == true)
    local stack, kit = need.stack == true, fam == "aura" and need.kit == true
    local stackFill = role == "bar" and view.barStacks == true
    local stackExtra = stackFill and stack
    if stackFill then stack = false end -- The native button has one application-bar binding.
    local color = stackFill and (view.barStackColorAt or 0) > 0
    -- Region sets only: the stack maximum and markers are looks (Look),
    -- applied in place, so a slider drag never builds another container.
    local bind = (fixed and "s" or "g") .. role .. (text and 1 or 0) .. (name and 1 or 0) .. (pan and 1 or 0) .. (glow and 1 or 0)
        .. (stack and 1 or 0) .. (kit and 1 or 0) .. fill .. (stackFill and 1 or 0) .. (color and 1 or 0) .. (stackExtra and 1 or 0)
    local rec = byUnit[unit]
    if rec and rec.bind ~= bind then
        Retire(slot, fam, unit)
        rec = nil
    end
    if not rec then
        if not fresh then rec = Acquire(slot, fam, bind, unit) end
        if not rec then
            local parent = fam == "over" and bar.frame or bar.auraHost or bar.frame
            local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
            if not container then return nil end
            -- No fake Edit Mode auras in our bars (12.1.0 lacks
            -- SetEditModePreviewEnabled and shows none).
            if container.SetEditModePreviewEnabled then container:SetEditModePreviewEnabled(false) end
            if fixed then container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0) end
            -- eager: buttons refused a restyle while auras are plain, so this
            -- container builds every button of a batch (AuraButtons.BeginBatch).
            rec = { frame = container, slot = slot, fam = fam, role = role, fixed = fixed, bind = bind, prefix = fixed and "s" or "g",
                eager = fresh == true,
                text = text, name = name, pandemic = pan, glow = glow, stack = stack, kit = kit, fill = fill, geo = 0,
                stackFill = stackFill, stackExtra = stackExtra, color = color,
                keys = {}, on = {}, act = {}, shut = {}, filter = {}, ids = {}, entry = {}, anchors = {}, byAnchor = {}, topts = {}, li = {}, lg = {},
                mark = {}, parts = {}, lk = {} }
            if kit then
                local watch = S.CreateFrame("Frame", nil, parent)
                watch:SetAllPoints(parent)
                watching[watch] = rec
                watch:SetScript("OnShow", Woke)
                watch:SetScript("OnHide", Woke)
            end
        end
        byUnit[unit] = rec
    end
    local container = rec.frame
    local level = bar.frame:GetFrameLevel() + (fam == "over" and OVER_LEVEL or AURA_LEVEL)
    if rec.level ~= level then
        rec.level = level
        container:SetFrameLevel(level)
    end
    local strata = STRATA[view.strata] or "MEDIUM"
    if rec.strata ~= strata then
        rec.strata = strata
        container:SetFrameStrata(strata)
    end
    if rec.unit ~= unit then
        rec.unit = unit
        container:SetUnit(unit)
    end
    local enabled = not (unit == "target" and FriendlyTarget())
    if rec.enabled ~= enabled then
        rec.enabled = enabled
        container:SetEnabled(enabled)
    end
    Show(rec)
    return rec
end

-- Compact containers: flow layout and host anchor from geo. A centered
-- horizontal row with both units uses opposite sides of the midpoint.
local function Place(rec, offset, split)
    local container, g = rec.frame, geo
    if rec.gw ~= g.w or rec.gh ~= g.h or rec.gp ~= g.gp or rec.gc ~= g.gc then
        rec.gw, rec.gh, rec.gp, rec.gc = g.w, g.h, g.gp, g.gc
        rec.geo = rec.geo + 1
    end
    if rec.axis ~= g.axis then
        rec.axis = g.axis
        container:SetFlowLayoutAxis(g.axis)
    end
    local flow = g.flow
    if rec.flowPoint ~= flow[1] then
        rec.flowPoint = flow[1]
        container:SetFlowLayoutAnchorPoint(flow[1])
    end
    if rec.hd ~= flow[2] or rec.vd ~= flow[3] then
        rec.hd, rec.vd = flow[2], flow[3]
        container:SetFlowLayoutGrowthDirection(flow[2], flow[3])
    end
    if rec.line ~= g.line then
        rec.line = g.line
        container:SetFlowLayoutMaximumLineSize(g.line)
    end
    if not rec.padded then
        rec.padded = true
        container:SetFlowLayoutPadding(0, 0, 0, 0)
    end
    local dx, dy = 0, 0
    local point, host = g.point, g.host
    local rel = point
    if split then
        -- Blizzard sizes each container to its visible auras. Anchoring
        -- opposite edges to the host midpoint keeps both on one row.
        rel = flow[1]:find("BOTTOM") and "BOTTOM" or "TOP"
        if split == "lead" then
            point, dx = rel .. "RIGHT", -g.gp / 2
        else
            point, dx = rel .. "LEFT", g.gp / 2
        end
    elseif g.vertical then
        dx = offset * g.step
    else
        dy = offset * g.step
    end
    if rec.pt ~= point or rec.host ~= host or rec.rel ~= rel or rec.dx ~= dx or rec.dy ~= dy then
        rec.pt, rec.host, rec.rel, rec.dx, rec.dy = point, host, rel, dx, dy
        container:ClearAllPoints()
        container:SetPoint(point, host, rel, dx, dy)
    end
end

AuraContainers.Ids, AuraContainers.UnitOf, AuraContainers.OnUnit, AuraContainers.TargetRow = Ids, UnitOf, OnUnit, TargetRow
AuraContainers.FriendlyTarget = FriendlyTarget
AuraContainers.Apply, AuraContainers.Build, AuraContainers.Show, AuraContainers.Bar = Apply, Build, Show, Bar
AuraContainers.Retire, AuraContainers.Ensure, AuraContainers.Place = Retire, Ensure, Place
