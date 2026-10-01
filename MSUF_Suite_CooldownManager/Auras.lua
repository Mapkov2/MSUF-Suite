local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Aura layer on Blizzard's AuraContainer: buff icon bars (kind 2), buff bar
-- bars (kind 3) and aura overlays on cooldown icons (kind 1). Blizzard
-- matches the auras and writes every secret value (icon, swipe, text,
-- stacks, bar) from its secure side, so no Lua runs per UNIT_AURA. This
-- file syncs each bar's containers (one container's record, groups, slots
-- and placement are AuraContainers.lua's):
--  * structure (groups, slots, filters) changes out of combat only;
--  * sealed buttons are restyled only while CanBeAccessedInContext() is
--    plainly true. While auras are secret the new look waits for them to
--    open; buttons that refuse while auras are plain get a new container;
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
local Auras = { pending = {} }
C.Auras = Auras
local AuraButtons = C.AuraButtons
local Look, Hush, Quiet = AuraButtons.Look, AuraButtons.Hush, AuraButtons.Quiet
local Unholds, Placeholders = AuraButtons.Unholds, AuraButtons.Placeholders
-- One container's record, groups, slots and placement (AuraContainers.lua
-- loads first); the tables it shares with the bar sync come along.
local Containers = C.AuraContainers
local Ids, UnitOf, OnUnit, TargetRow = Containers.Ids, Containers.UnitOf, Containers.OnUnit, Containers.TargetRow
local FriendlyTarget = Containers.FriendlyTarget
local Apply, Build, Show, Bar = Containers.Apply, Containers.Build, Containers.Show, Containers.Bar
local Retire, Ensure, Place = Containers.Retire, Containers.Ensure, Containers.Place
local live, overIcon, unseen = Containers.live, Containers.overIcon, Containers.unseen
local list, where, geo, need = Containers.list, Containers.where, Containers.geo, Containers.need

local IsCombatLocked = NS.IsCombatLocked
local ceil, max = math.ceil, math.max
local pairs, next, type = pairs, next, type
local wipe = C.wipe
local EMPTY = C.EMPTY

local UNITS = { "player", "target" }
-- Flow per [vertical][grow]: flow anchor, horizontal and vertical direction
-- (AnchorUtil.FlowDirection), host point per align (center, start, end).
-- Lines always run in entry order; the block is aligned by its host point.
local FLOW = {
    [false] = { { "TOPLEFT", 1, -1, { "TOP", "TOPLEFT", "TOPRIGHT" } }, { "BOTTOMLEFT", 1, 1, { "BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT" } } },
    [true] = { { "TOPLEFT", 1, -1, { "LEFT", "TOPLEFT", "BOTTOMLEFT" } }, { "TOPRIGHT", -1, -1, { "RIGHT", "TOPRIGHT", "BOTTOMRIGHT" } } },
}

local meta = {}    -- per aura bar: role, fixed mode and look (placeholders)
local targets = {} -- live target containers, refreshed on retarget
local flushing = {}
local debounced = false
Auras.UnitOf, Auras.Ids, Auras.TargetRow = UnitOf, Ids, TargetRow


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
-- every other overlay switches with its icon (Auras.OverlayShown).
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
    Auras.FlushPending()
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
        Auras.pending[slot] = true
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
    Placeholders(slot, view, plan, barMeta, Containers.preview == true)
end

-- Structure changes only out of combat: in combat the bar is marked
-- pending for FlushPending and the sync stops.
local function Deferred(slot)
    if IsCombatLocked() then
        Auras.pending[slot] = true
        return true
    end
    Auras.pending[slot] = nil
    return false
end

-- Structural sync of one bar (aura bars and cooldown overlays alike). Out
-- of combat only; in combat the bar is marked pending for FlushPending.
function Auras.Sync(slot, force)
    local view, plan = C.views[slot], C.plans[slot]
    if not (view and plan and view.on) then
        Auras.Release(slot)
        return
    end
    if plan.kind == 1 then
        if live[slot] then ReleaseFam(slot, "aura") end
        Unholds(slot)
        return Auras.SyncOverlays(slot, force)
    end
    if Deferred(slot) then return end
    if live[slot] then ReleaseFam(slot, "over") end
    SyncAura(slot, view, plan, force)
    RefreshTargets()
end

-- Aura overlays on a cooldown bar: one slot per icon whose spell has an
-- aura, anchored to that icon. Needs the bar's icons (C.Icons.Sync) first.
function Auras.SyncOverlays(slot, force)
    local view, plan = C.views[slot], C.plans[slot]
    if not (view and plan and view.on and plan.kind == 1 and not view.cooldownDuration) then
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
function Auras.Restyle(slot) return Auras.Sync(slot) end

function Auras.Release(slot)
    if live[slot] then
        ReleaseFam(slot, "aura")
        ReleaseFam(slot, "over")
    end
    Unholds(slot)
    Auras.pending[slot] = nil
    RefreshTargets()
end

-- Module off. Gates parked by an earlier release in combat go too: the
-- module may be switched off after combat but before its own
-- PLAYER_REGEN_ENABLED ran (a profile change queued in combat).
function Auras.ReleaseAll()
    for slot in pairs(live) do Auras.Release(slot) end
    for slot in pairs(meta) do Unholds(slot) end
    for slot in pairs(Auras.pending) do Auras.pending[slot] = nil end
    C.AuraGlows.FlushGates()
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
function Auras.TargetChanged()
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
            -- Fixed slot buttons stay shown across a retarget (aura groups
            -- release and show theirs again), so the stack colour and stack
            -- glow containers inside them are told as well.
            if rec.fixed and (rec.color or rec.stackExtra) then C.StackColors.Retarget(rec) end
        end
    end
end
-- UNIT_FACTION for the target (a duel starts, a charm ends): work only when
-- its disposition changed.
function Auras.TargetReaction()
    if targets[1] ~= nil then React() end
end

-- An overlay slot follows its cooldown icon's position (SetAllPoints) but
-- is the container's child, so not its visibility. The layout calls this
-- on every change of an icon's shown state, the icon pool before it pools
-- an icon (icon given; its entry may be gone). The slot shows only while
-- its icon shows and still carries the entry the slot was built for.
-- Container-level calls only, legal in combat; unchanged state makes none;
-- an icon without an overlay costs two lookups.
function Auras.OverlayShown(entry, on, icon)
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
function Auras.SetBarMouse(slot, on)
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
function Auras.FlushPending()
    C.AuraGlows.FlushGates()
    if IsCombatLocked() then return end
    local n = 0
    for slot in pairs(Auras.pending) do
        n = n + 1
        flushing[n] = slot
    end
    for i = 1, n do
        local slot = flushing[i]
        flushing[i] = nil
        Auras.pending[slot] = nil
        Auras.Sync(slot, true)
    end
    local alerts = C.Alerts
    if alerts.pending then alerts.SyncAuraSounds() end
end

-- Edit Mode / options preview: every aura-bar entry shows its sample icon
-- on its cell; compact containers step aside so nothing is drawn twice.
function Auras.SetPreview(on)
    on = on == true
    if Containers.preview == on then return end
    Containers.preview = on
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
