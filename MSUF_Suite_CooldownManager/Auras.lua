local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Aura layer on Blizzard's AuraContainer: buff icon bars (kind 2), buff bar
-- bars (kind 3) and aura overlays on cooldown icons (kind 1). Blizzard
-- matches the auras and writes every secret value (icon, swipe, text,
-- stacks, bar) from its secure side, so no Lua runs per UNIT_AURA. This
-- file only builds, places and styles containers:
--  * structure (groups, slots, filters) changes out of combat only. Groups
--    and slots cannot be removed, so they are updated in place and surplus
--    ones switched off;
--  * sealed buttons are restyled only while CanBeAccessedInContext() is
--    plainly true. While auras are secret the new look waits for them to
--    open; buttons that refuse while auras are plain get a new container;
--  * containers cannot be freed either: retired ones are disabled, hidden
--    and parked in a per-bar pool for reuse (never dropped from it);
--  * in combat only container-level switches run: target containers pause
--    while the target is friendly, overlay slots follow their icon.
-- Per-spell stack choices ride on the same bindings, so no Lua ever reads
-- an application count: a shared count formatter colors the stack text
-- from N applications, and the stack glow is placed by an application bar
-- Blizzard fills (see NewStack). Countdown and stack text are bound only
-- while the entry shows them (per-spell choice, else the bar's switch);
-- Text on top orders their two frames. Glows are flipbooks, edges and alpha
-- loops styled by widget writes only. The one Lua on the aura side: bars
-- whose entries have unknown sound kits (without a mapped sound file) get a
-- sensor in each button that runs when it shows or hides, never on a stack
-- or duration update. Known CDM kits use native aura sound registrations.
-- Everything inside a button (look, glows, text bindings, sensors) and the
-- placeholders on cells are in AuraButtons.lua.
local K = C.Const
local A = { pending = {} }
C.Auras = A
local AB = C.AuraButtons
local TextOpts, Look, Hush, Quiet, Mutable = AB.TextOpts, AB.Look, AB.Hush, AB.Quiet, AB.Mutable
local Style, ApplyEntry, Init = AB.Style, AB.ApplyEntry, AB.Init
local Unholds, Placeholders = AB.Unholds, AB.Placeholders

-- The containers are created with the client's CreateFrame: they lay out
-- and seal Blizzard's buttons, so MSUF's pixel-layout policy
-- (S.CreateFrame) must not round what Blizzard positions. Frames on our
-- own bars use S.CreateFrame.
local CreateFrame = CreateFrame
local IsCombatLocked = NS.IsCombatLocked
local ceil, max = math.ceil, math.max
local pairs, next, type = pairs, next, type
local tremove = table.remove
local wipe = C.wipe
local Public = S.Public
local EMPTY = C.EMPTY

local UNITS = { "player", "target" }
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
-- Flow per [vertical][grow]: flow anchor, horizontal and vertical direction
-- (AnchorUtil.FlowDirection), host point per align (center, start, end).
-- Lines always run in entry order; the block is aligned by its host point.
local FLOW = {
    [false] = { { "TOPLEFT", 1, -1, { "TOP", "TOPLEFT", "TOPRIGHT" } }, { "BOTTOMLEFT", 1, 1, { "BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT" } } },
    [true] = { { "TOPLEFT", 1, -1, { "LEFT", "TOPLEFT", "BOTTOMLEFT" } }, { "TOPRIGHT", -1, -1, { "RIGHT", "TOPRIGHT", "BOTTOMRIGHT" } } },
}

local live = {}     -- live[slot] = { aura = {player=rec,target=rec}, over = {...} }
local pools = {}    -- retired container records per bar
local meta = {}     -- per aura bar: role, fixed mode and look (placeholders)
local targets = {}  -- live target containers, refreshed on retarget
local overIcon = {} -- cooldown icon -> bar slot, for icons that carry an overlay
local unseen = {}   -- bar slot -> true while Visibility hides the bar
local list, where, cand, lay, geo, flushing = {}, {}, {}, {}, {}, {}
local groupOpts, slotOpts = { maxFrameCount = 1 }, {}
local need = {}      -- bindings the bar being synced asks for: glow, stack, kit
local watching = {}  -- ancestor watch frame -> its kit container record
local stamp = 0
local debounced = false

------------------------------------------------------------------ helpers
local function SameSet(a, b)
    for id in pairs(a) do
        if not b[id] then
            return false
        end
    end
    for id in pairs(b) do
        if not a[id] then
            return false
        end
    end
    return true
end
local function CopySet(into, from)
    wipe(into)
    for id in pairs(from) do into[id] = true end
    return into
end

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
A.UnitOf, A.Ids, A.TargetRow = UnitOf, Ids, TargetRow

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
            -- (layShown); the layout reports every change (A.OverlayShown).
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
                container:AddAuraGroup(keys[k], filter, groupOpts)
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
    local shown = not (unseen[rec.slot] or (A.preview and rec.fam == "aura" and not rec.fixed))
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
    local text, name, fill = need.text == true, false, 1
    if role == "bar" then name, fill = view.barName ~= false, view.barFill == 2 and 2 or 1 end
    local pan = fam == "aura" and view.pandemic == true
    local glow = fam == "aura" and (view.auraGlow == true or need.glow == true)
    local stack, kit = need.stack == true, fam == "aura" and need.kit == true
    local bind = (fixed and "s" or "g") .. role .. (text and 1 or 0) .. (name and 1 or 0) .. (pan and 1 or 0) .. (glow and 1 or 0)
        .. (stack and 1 or 0) .. (kit and 1 or 0) .. fill
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
            rec = { frame = container, slot = slot, fam = fam, role = role, fixed = fixed, bind = bind, prefix = fixed and "s" or "g",
                text = text, name = name, pandemic = pan, glow = glow, stack = stack, kit = kit, fill = fill, geo = 0,
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

local function RefreshTargets()
    wipe(targets)
    for _, fams in pairs(live) do
        local rec = fams.aura.target
        if rec then targets[#targets + 1] = rec end
        rec = fams.over.target
        if rec then targets[#targets + 1] = rec end
    end
end

local function ReleaseFam(slot, fam)
    Retire(slot, fam, "player")
    Retire(slot, fam, "target")
end

-- hideReady of a cooldown entry, as the time layer reads it; placeholders
-- never hide.
local function Hides(entry, view)
    if entry.src == "p" then return false end
    local hide = (entry.ov or EMPTY).hideReady
    if hide == nil then hide = view.hideReady == true end
    return hide == true
end

-- Entries of one unit a container shows, in plan order, into list/where.
-- Aura bars honor maxIcons like the layout does (every entry holds a place).
-- Overlays: the layout shows the first maxIcons visible icons, so an icon
-- behind maxIcons icons that never hide can never show and gets no slot;
-- every other overlay switches with its icon (A.OverlayShown).
local function Collect(plan, unit, over, view)
    local entries, n = plan.entries, 0
    local cap = #entries
    local limit = view.maxIcons
    if type(limit) ~= "number" or limit <= 0 then limit = nil end
    if not over and limit and limit < cap then cap = limit end
    local steady = 0
    for i = 1, cap do
        local entry = entries[i]
        local ok
        if over then
            if entry.icon then
                if limit and steady >= limit then break end
                if not Hides(entry, view) then steady = steady + 1 end
                if entry.family == 1 and entry.hasAura and entry.src ~= "p" and OnUnit(entry, unit) then
                    ok = (entry.ov or EMPTY).showAura
                    if ok == nil then ok = view.showAura == true end
                end
            end
        elseif entry.src ~= "p" and OnUnit(entry, unit) then
            ok = entry.family ~= 1
        end
        if ok and Ids(entry) then
            n = n + 1
            list[n], where[n] = entry, i
        end
    end
    for i = #list, n + 1, -1 do list[i], where[i] = nil, nil end
    return n
end

------------------------------------------------------------------ sync
local function Debounced()
    debounced = false
    A.FlushPending()
end
-- Buttons that refuse a restyle while auras are plain get a new container,
-- batched so slider drags do not leak one per tick.
local function Debounce()
    if debounced then return end
    debounced = true
    C_Timer.After(.5, Debounced)
end

-- What a bar's entries ask of its buttons (need, read by Ensure): countdown
-- regions (the bar shows the countdown or a spell asks for it), a glow while
-- active, a stack glow, a sensor for kit sounds (aura bars only).
local function Needs(entries, aura, view)
    need.glow, need.stack, need.kit = false, false, false
    need.text = K.BarTime(view)
    local isKit = C.Alerts.IsKit
    for i = 1, #entries do
        local entry = entries[i]
        local ov = entry.ov
        if ov and ov ~= EMPTY and entry.src ~= "p" then
            if ov.timeText == 2 then need.text = true end
            local n = ov.stackGlow
            if type(n) == "number" and n >= 1 then need.stack = true end
            if aura then
                if ov.auraGlow == true then need.glow = true end
                if isKit(ov.sound) or isKit(ov.lossSound) then need.kit = true end
            end
        end
    end
end

local function Run(slot, fam, unit, role, fixed, view, n, force, offset, split)
    local rec = Ensure(slot, fam, unit, role, fixed, view, false)
    if not rec then return end
    -- Filters, groups and new buttons change what shows: not aura events.
    Hush(rec)
    if not fixed then Place(rec, offset, split) end
    if Build(rec, view, n) then return end
    -- Sealed buttons refused the restyle; the structure is current. While
    -- auras are secret (M+ key, PvP match) the look waits for them to open
    -- (FlushPending): a new container per change would leak, since none is
    -- ever freed.
    local quiet = Quiet()
    if not (force and quiet) then
        A.pending[slot] = true
        if quiet then Debounce() end
        return
    end
    Retire(slot, fam, unit)
    rec = Ensure(slot, fam, unit, role, fixed, view, true)
    if not rec then return end
    if not fixed then Place(rec, offset, split) end
    Build(rec, view, n)
end

local function SyncAura(slot, view, plan, force)
    local role = plan.kind == 3 and "bar" or "icon"
    local barMeta = meta[slot]
    if not barMeta then
        barMeta = { lk = {} }
        meta[slot] = barMeta
    end
    barMeta.role = role
    barMeta.look = Look(barMeta, view)
    local entries = plan.entries
    Needs(entries, true, view)
    local layout = C.Layout
    -- One rule for the layout and the containers (Layout.FixedAuras).
    local fixed, _, split = layout.FixedAuras(view, entries)
    barMeta.fixed, barMeta.split = fixed == true, split == true
    local bar = Bar(slot)
    if not bar then return end
    local w, h, sp, per, vertical, grow, align = layout.Metrics(view)
    vertical = vertical == true
    local flow = FLOW[vertical][grow == 2 and 2 or 1]
    geo.w, geo.h, geo.gp, geo.gc = w, h, max(0, sp), sp
    geo.axis = vertical and 1 or 0
    geo.flow, geo.point = flow, flow[4][align] or flow[4][1]
    local primary, cross = w, h
    if vertical then primary, cross = h, w end
    geo.line = per * primary + (per - 1) * geo.gp + .01
    geo.vertical = vertical
    local dir
    if vertical then
        dir = grow == 2 and -1 or 1
    else
        dir = grow == 2 and 1 or -1
    end
    geo.step = (cross + sp) * dir
    geo.host = bar.auraHost or bar.frame
    -- Target row starts after the player lines the layout reserves
    -- (every player-row entry within maxIcons, active or not).
    local cap = #entries
    local limit = view.maxIcons
    if type(limit) == "number" and limit > 0 and limit < cap then cap = limit end
    local players = 0
    for i = 1, cap do
        if not TargetRow(entries[i]) then
            players = players + 1
        end
    end
    local lines = ceil(players / per)
    for u = 1, 2 do
        local unit = UNITS[u]
        local n = Collect(plan, unit, false, view)
        if n == 0 then
            Retire(slot, "aura", unit)
        else
            local side = barMeta.split and (u == 1 and "lead" or "tail") or nil
            Run(slot, "aura", unit, role, barMeta.fixed, view, n, force, (u == 2 and not side) and lines or 0, side)
        end
    end
    Placeholders(slot, view, plan, barMeta, A.preview == true)
end

-- Structure changes only out of combat: in combat the bar is marked
-- pending for FlushPending and the sync stops.
local function Deferred(slot)
    if IsCombatLocked() then
        A.pending[slot] = true
        return true
    end
    A.pending[slot] = nil
    return false
end

-- Structural sync of one bar (aura bars and cooldown overlays alike). Out
-- of combat only; in combat the bar is marked pending for FlushPending.
function A.Sync(slot, force)
    local view, plan = C.views[slot], C.plans[slot]
    if not (view and plan and view.on) then
        A.Release(slot)
        return
    end
    if plan.kind == 1 then
        if live[slot] then ReleaseFam(slot, "aura") end
        Unholds(slot)
        return A.SyncOverlays(slot, force)
    end
    if Deferred(slot) then return end
    if live[slot] then ReleaseFam(slot, "over") end
    SyncAura(slot, view, plan, force)
    RefreshTargets()
end

-- Aura overlays on a cooldown bar: one slot per icon whose spell has an
-- aura, anchored to that icon. Needs the bar's icons (C.Icons.Sync) first.
function A.SyncOverlays(slot, force)
    local view, plan = C.views[slot], C.plans[slot]
    if not (view and plan and view.on and plan.kind == 1) then
        if live[slot] then
            ReleaseFam(slot, "over")
            RefreshTargets()
        end
        return
    end
    if Deferred(slot) then return end
    Needs(plan.entries, false, view)
    for u = 1, 2 do
        local unit = UNITS[u]
        local n = Collect(plan, unit, true, view)
        if n == 0 then
            Retire(slot, "over", unit)
        else
            Run(slot, "over", unit, "over", true, view, n, force, 0)
        end
    end
    RefreshTargets()
end

-- Style changes use the same diffing: unchanged structure makes no calls.
function A.Restyle(slot) return A.Sync(slot) end

function A.Release(slot)
    if live[slot] then
        ReleaseFam(slot, "aura")
        ReleaseFam(slot, "over")
    end
    Unholds(slot)
    A.pending[slot] = nil
    RefreshTargets()
end

function A.ReleaseAll()
    for slot in pairs(live) do A.Release(slot) end
    for slot in pairs(meta) do Unholds(slot) end
    for slot in pairs(A.pending) do A.pending[slot] = nil end
end

-- Target containers pause while the target is friendly (FriendlyTarget).
-- SetEnabled is container-level (legal in combat), refreshes the container
-- when it turns on and makes no call while the state holds.
local function React()
    local enabled = not FriendlyTarget()
    for i = 1, #targets do
        local rec = targets[i]
        if rec.enabled ~= enabled then
            rec.enabled = enabled
            Hush(rec)
            rec.frame:SetEnabled(enabled)
        end
    end
end
-- Same-token retarget fires no UNIT_AURA: each target container is told at
-- once. A container turning on reparses inside SetEnabled; a running one
-- is marked dirty by UpdateAllAuras and parses once when it next draws, so
-- several target events in one frame still cost one parse. The pause
-- starts at once, so a friendly target is never parsed. The new target's
-- auras are no gains or losses: kit sensors stay silent.
function A.TargetChanged()
    if targets[1] == nil then return end
    local enabled = not FriendlyTarget()
    for i = 1, #targets do
        local rec = targets[i]
        Hush(rec)
        if rec.enabled ~= enabled then
            rec.enabled = enabled
            rec.frame:SetEnabled(enabled)
        elseif enabled then
            rec.frame:UpdateAllAuras()
        end
    end
end
-- UNIT_FACTION for the target (a duel starts, a charm ends): work only when
-- its disposition changed.
function A.TargetReaction()
    if targets[1] ~= nil then React() end
end

-- An overlay slot follows its cooldown icon's position (SetAllPoints) but
-- is the container's child, so not its visibility. The layout calls this
-- on every change of an icon's shown state, the icon pool before it pools
-- an icon (icon given; its entry may be gone). The slot shows only while
-- its icon shows and still carries the entry the slot was built for.
-- Container-level calls only, legal in combat; unchanged state makes none;
-- an icon without an overlay costs two lookups.
function A.OverlayShown(entry, on, icon)
    icon = icon or (entry and entry.icon)
    local slot = icon and overIcon[icon]
    local fams = slot and live[slot]
    if not fams then return end
    local byUnit = fams.over
    for u = 1, 2 do
        local rec = byUnit[UNITS[u]]
        local k = rec and rec.byAnchor[icon]
        if k then
            local shut = not (on == true and entry ~= nil and rec.entry[k] == entry)
            if rec.shut[k] ~= shut then
                rec.shut[k] = shut
                Apply(rec, k)
            end
        end
    end
end

-- Visibility, on every edge of a bar's hidden state (its rule hides it or
-- its opacity is 0): the bar's containers hide with it, so invisible
-- buttons take no mouse or tooltip and no aura work runs; shown again, a
-- container reparses at once (OnShow). Legal in combat.
function A.SetBarMouse(slot, on)
    local hidden = on ~= true or nil
    if unseen[slot] == hidden then return end
    unseen[slot] = hidden
    local fams = live[slot]
    if not fams then return end
    for _, rec in pairs(fams.aura) do Show(rec) end
    for _, rec in pairs(fams.over) do Show(rec) end
end

-- PLAYER_REGEN_ENABLED, ADDON_RESTRICTION_STATE_CHANGED while something is
-- pending, and the sealed-button debounce: runs every sync that combat or
-- sealed buttons held back, then pending aura sounds.
function A.FlushPending()
    if IsCombatLocked() then return end
    local n = 0
    for slot in pairs(A.pending) do
        n = n + 1
        flushing[n] = slot
    end
    for i = 1, n do
        local slot = flushing[i]
        flushing[i] = nil
        A.pending[slot] = nil
        A.Sync(slot, true)
    end
    local alerts = C.Alerts
    if alerts.pending then alerts.SyncAuraSounds() end
end

-- Edit Mode / options preview: every aura-bar entry shows its sample icon
-- on its cell; compact containers step aside so nothing is drawn twice.
function A.SetPreview(on)
    on = on == true
    if A.preview == on then return end
    A.preview = on
    for _, fams in pairs(live) do
        for _, rec in pairs(fams.aura) do Show(rec) end
    end
    for slot, barMeta in pairs(meta) do
        local view, plan = C.views[slot], C.plans[slot]
        if view and plan and view.on and plan.kind ~= 1 then
            Placeholders(slot, view, plan, barMeta, on)
        else
            Unholds(slot)
        end
    end
end

