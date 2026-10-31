local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- One dirty mask with a prebuilt next-frame flush. The settings
-- reader (Settings.lua), the event map (Events.lua) and the layers mark work
-- here; the flush runs it in dependency order: catalog, resolve, index,
-- structure (icons before aura overlays), style, cooldown state, effects,
-- layout, visibility. A resolve passes on only what changed: bars whose plan
-- moved sync, lay out and repaint; entries that kept their place but changed
-- refresh alone.
-- The data units that need the event wiring (spec and catalog, routing,
-- event registration, keybind and sound watches) live in Events.lua and bind
-- here once at its load (Flush.BindDataUnits), so every call stays an upvalue.
local M = C.M
local SLOTS = NS.CDM.SLOTS
local COOLDOWN = C.Const.KIND.COOLDOWN
local AURA_FAMILY = C.Const.FAMILY.AURA
local pairs, next = pairs, next
local wipe = C.wipe
local Flush = {}
C.Flush = Flush

------------------------------------------------------------------ dirty mask
-- keysLater: keybind texts after a resolve, through the coalesced request.
-- bags: a capped bag cooldown refresh (Events.lua OnBag) for the item and
-- equipment entries. catalog: true starts a catalog pass, "slice" continues
-- a combat pass (CatalogUnit). Pending names every key; the contract checks
-- that.
local dirty = { catalog = false, resolve = false, index = false, events = false, cooldowns = false, usable = false, effects = false,
    keybinds = false, keysLater = false, alerts = false, layout = false, visibility = false, bags = false }
-- Per slot: sync (structure), style, behavior (entry refresh), visible
-- (driver and alpha), laid (layout of that bar only).
local sync, style, behavior, visible, laid, marked = {}, {}, {}, {}, {}, {}
Flush.dirty, Flush.sync, Flush.style, Flush.behavior, Flush.visible = dirty, sync, style, behavior, visible
-- Every unit of flush work runs isolated with one retry (S.NewUnitRunner,
-- Runtime.lua).
local Run, Settle, ResetUnits = S.NewUnitRunner()
-- Layout requests of runtime paths (Layout.Request) and the item entries
-- bag cooldowns refresh: both tables keep their identity (wiped in place).
local layoutRequests, bagEntries = C.Layout.dirty, C.Index.bags
-- The plan (and its generation) each bar was last synced with.
local seenPlan, seenGen = {}, {}
local scheduled = false

local FlushNow
local function Schedule()
    if scheduled or not M.active then return end
    scheduled = true
    C_Timer.After(0, FlushNow)
end
C.Schedule, Flush.Schedule = Schedule, Schedule

-- MSUF follows our Essential bar (MSUF_GetSuiteCooldownAnchor): one
-- notification per frame when that bar appears or goes. MSUF defers its own
-- work in combat.
local anchorNotify = false
local function FireAnchorChanged()
    anchorNotify = false
    EventRegistry:TriggerEvent("MSUFSuite.CooldownManager.AnchorChanged")
end
function C.AnchorChanged()
    if anchorNotify then return end
    anchorNotify = true
    C_Timer.After(0, FireAnchorChanged)
end

-- Marks in one frame merge to the one that refreshes most: "full" (texture,
-- state, effects) over "charges" (state and count) over "recharge" (the
-- recharge swipe and count, SPELL_UPDATE_CHARGES) over "count" (the count
-- alone, SPELL_UPDATE_USES) over "item" (bag contents: potion and
-- healthstone entries keep their cooldown).
local RANK = { item = 1, count = 2, recharge = 3, charges = 4, full = 5 }
local function Mark(entry, reason)
    local pending = marked[entry]
    if pending == nil or RANK[reason] > RANK[pending] then marked[entry] = reason end
    Schedule()
end
Flush.Mark = Mark

local function ResetDirty()
    for key in pairs(dirty) do dirty[key] = false end
    wipe(sync)
    wipe(style)
    wipe(behavior)
    wipe(visible)
    wipe(laid)
    wipe(marked)
    ResetUnits()
end
-- Every flush asks this at its end (2026-10-11 raid trace: 1,097 flushes,
-- 2.1 us each as a pairs() walk of the mask): the flags are named, no walk.
local function Pending()
    return dirty.catalog or dirty.resolve or dirty.index or dirty.events or dirty.cooldowns or dirty.usable
        or dirty.effects or dirty.keybinds or dirty.keysLater or dirty.alerts or dirty.layout or dirty.visibility
        or dirty.bags or next(sync) ~= nil or next(style) ~= nil or next(behavior) ~= nil or next(visible) ~= nil
        or next(laid) ~= nil or next(marked) ~= nil
end
Flush.Reset, Flush.Pending = ResetDirty, Pending

-- Disable: the next activation syncs every bar again.
function Flush.Forget()
    wipe(seenPlan)
    wipe(seenGen)
end

------------------------------------------------------------------ resolve results
-- After a resolve: bars whose plan appeared, went or changed its list
-- sync, lay out and repaint; entries that kept their place but changed on
-- refill refresh alone (their aura containers sync when their aura IDs
-- moved). Routing, sounds and keybind texts follow only a real change.
local function Resolved(any)
    local plans = C.plans
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        local plan = plans[slot]
        local gen = plan and plan.gen
        if seenPlan[slot] ~= plan or seenGen[slot] ~= gen then
            seenPlan[slot], seenGen[slot] = plan, gen
            sync[slot], visible[slot], laid[slot] = true, true, true
            any = true
        end
    end
    local R = C.Resolve
    local touched, auraTouched = R.touched, R.auraTouched
    for i = 1, #touched do
        local entry = touched[i]
        if entry.icon then Mark(entry, "full") end
        local slot = entry.slot
        if slot and (entry.family == AURA_FAMILY or auraTouched[entry]) then sync[slot] = true end
    end
    if any or touched[1] ~= nil then dirty.index, dirty.alerts, dirty.keysLater = true, true, true end
end

local function MarkPlans(only)
    for slot, plan in pairs(C.plans) do
        if plan.kind == COOLDOWN and (not only or only[slot]) then
            local list = plan.entries
            for i = 1, #list do marked[list[i]] = "full" end
        end
    end
end

------------------------------------------------------------------ isolated units
-- Units of flush work: a dirty flag, one bar's structure, layout or
-- visibility, one marked entry, one layout request (Run, above).
local CatalogUnit, IndexUnit, EventsUnit, KeysLaterUnit, AlertsUnit
function Flush.BindDataUnits(catalog, index, events, keysLater, alerts)
    CatalogUnit, IndexUnit, EventsUnit, KeysLaterUnit, AlertsUnit = catalog, index, events, keysLater, alerts
end
-- In combat a resolve stages its entries over frames (ResolveStages.lua):
-- nil until it lands; dirty.resolve "stage" continues it, true restarts it.
local function ResolveUnit(locked, fresh)
    local plans, any = C.Resolve.Build(locked, fresh)
    if plans == nil then
        if not dirty.resolve then dirty.resolve = "stage" end
        return
    end
    C.Preview.Decorate()
    Resolved(any)
    C.ActionGlows.Refresh()
end
local function SyncUnit(slot)
    C.Icons.Sync(slot)
    C.Auras.Sync(slot)
end
local function StyleUnit(slot)
    C.Icons.Style(slot)
    C.Auras.Restyle(slot)
end
-- Exact spell/item answers are shared by rebinds, show edges and the
-- usability broadcast in one synchronous entry pass. Never retain answers across
-- passes; range, target and show edges outside this pass still read fresh.
local usableSpells = { seen = {}, usable = {}, noPower = {} }
local usableItems = { seen = {}, usable = {}, noPower = {} }
local usableQueries = { spells = usableSpells, items = usableItems }
local function EntryUnit(entry, reason)
    if reason ~= "full" then
        if C.Time.Refresh(entry, reason, usableQueries) then C.Layout.Request(entry.slot) end
        return
    end
    C.Icons.Texture(entry)
    if C.Time.Refresh(entry, reason, usableQueries) then C.Layout.Request(entry.slot) end
    C.Effects.Update(entry, usableQueries)
end
local function UsableUnit()
    usableQueries.used = true
    local list = C.Index.usable
    local fx = C.Effects
    for i = 1, #list do
        local entry = list[i]
        if entry.hidden and not C.state.preview then
            entry.usablePending = true
        elseif fx.UsableShown(entry) then
            fx.Usable(entry, entry.src == "i" and usableItems or usableSpells)
        end
    end
end
-- "Show only when usable" (Index.gated): the same sweep, then the gate list,
-- asked from the same answers also while hidden. Bound in place of the
-- plain sweep only while the list holds entries (Flush.Gated, the event
-- registration), so the plain sweep costs what it did.
local function GatedUsableUnit()
    UsableUnit()
    local list, fx = C.Index.gated, C.Effects
    for i = 1, #list do fx.GateUsable(list[i], usableQueries) end
end
local usableUnit = UsableUnit
function Flush.Gated(on) usableUnit = on and GatedUsableUnit or UsableUnit end
local function EffectsUnit()
    C.Effects.CombatChanged()
    C.ActionGlows.Refresh()
end
local function KeybindsUnit() C.Keybinds.Refresh() end
local function LayoutAllUnit() C.Layout.ApplyAll() end
local function LayoutUnit(slot) C.Layout.Apply(slot) end
local function VisibilityAllUnit() C.Visibility.ApplyAll() end
local function VisibilityUnit(slot) C.Visibility.Apply(slot) end

------------------------------------------------------------------ flush steps, in dependency order
-- Catalog, resolve, routing index and event registration. Only the catalog
-- and index units read the lockdown, so only they ask for it (the combat
-- state cannot change inside one flush). In combat the catalog reads in
-- slices over consecutive frames, and such a frame runs nothing else of
-- this step: the resolve a pass asks for comes a frame later, so no frame
-- holds both. True when the rest waits. After DEFER such frames while the
-- rest has work, the catalog waits one frame instead: catalog events every
-- few frames cannot starve the resolve (it stages as usual).
local DEFER, deferred = 3, 0
local function CatalogStep()
    local fresh, locked = dirty.catalog == true, NS.IsCombatLocked()
    local waiting = locked and (dirty.resolve or dirty.index or dirty.events)
    if not waiting then
        deferred = 0
    elseif deferred >= DEFER then
        deferred = 0
        return false
    end
    dirty.catalog = false
    -- A catalog event stages a combat resolve again (its inputs may move).
    local stage = C.Resolve.stage
    if fresh then stage.stale = stage.on end
    Run(dirty, "catalog", true, CatalogUnit, locked, fresh)
    if waiting then deferred = deferred + 1 end
    return locked
end
Flush.DEFER = DEFER
local function FlushData()
    if dirty.catalog and CatalogStep() then return end
    if dirty.resolve then
        local fresh = dirty.resolve == true
        dirty.resolve = false
        Run(dirty, "resolve", true, ResolveUnit, NS.IsCombatLocked(), fresh)
    end
    if dirty.index then
        dirty.index, dirty.events = false, true
        Run(dirty, "index", true, IndexUnit, NS.IsCombatLocked())
    end
    if dirty.events then
        dirty.events = false
        Run(dirty, "events", true, EventsUnit)
    end
end

-- Structure (icons before aura overlays) or, without it, the look.
local function FlushStructure()
    local changed = false
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if sync[slot] then
            changed = true
            sync[slot], style[slot], laid[slot] = nil, nil, true
            Run(sync, slot, true, SyncUnit, slot)
        elseif style[slot] then
            changed = true
            style[slot] = nil
            Run(style, slot, true, StyleUnit, slot)
        end
    end
    if changed and (C.ActionGlows.wanted or C.ActionUsableGlows.wanted) then C.ActionGlows.Refresh() end
    -- Plans and timer routes exist only after structure sync. Reconcile
    -- native summon sources here, including first enable and removing one.
    if changed then S.Dispatch(C.Native.Apply) end
end

-- Cooldown state of marked entries, usability of visible icons, effects.
local function FlushEntries()
    if dirty.cooldowns then
        dirty.cooldowns = false
        Run(dirty, "cooldowns", true, MarkPlans)
    end
    if next(behavior) then
        MarkPlans(behavior)
        wipe(behavior)
    end
    -- A capped bag cooldown refresh (Events.lua OnBag) marks the item and
    -- equipment entries as Mark would: "item" never replaces a pending mark.
    if dirty.bags then
        dirty.bags = false
        for i = 1, #bagEntries do
            local entry = bagEntries[i]
            if marked[entry] == nil then marked[entry] = "item" end
        end
    end
    local timeQueries = next(marked) and C.Index.hasSharedTimeSpells and C.Time.BeginQueries()
    for entry, reason in pairs(marked) do
        marked[entry] = nil
        if entry.icon and entry.slot then Run(marked, entry, reason, EntryUnit, entry, reason) end
    end
    if timeQueries then C.Time.EndQueries() end
    if dirty.usable then
        dirty.usable = false
        Run(dirty, "usable", true, usableUnit)
    end
    if usableQueries.used then
        usableQueries.used = false
        -- Run isolates raising units; Settle only re-marks them for a later
        -- pass. Cleanup therefore also runs after a failed rebind or sweep.
        wipe(usableSpells.seen)
        wipe(usableSpells.usable)
        wipe(usableSpells.noPower)
        wipe(usableItems.seen)
        wipe(usableItems.usable)
        wipe(usableItems.noPower)
    end
    if dirty.effects then
        dirty.effects = false
        Run(dirty, "effects", true, EffectsUnit)
    end
end

-- Keybind setting changes push cached texts now; resolves wait for the
-- coalesced request. Aura sounds follow their entries.
local function FlushTextsAndSounds()
    if dirty.keybinds then
        dirty.keybinds, dirty.keysLater = false, false
        Run(dirty, "keybinds", true, KeybindsUnit)
    end
    if dirty.keysLater then
        dirty.keysLater = false
        Run(dirty, "keysLater", true, KeysLaterUnit)
    end
    if dirty.alerts then
        dirty.alerts = false
        Run(dirty, "alerts", true, AlertsUnit)
    end
end

-- Layout (all bars or the marked ones, then the layout's own requests),
-- then visibility.
local function FlushPlacement()
    if dirty.layout then
        dirty.layout = false
        wipe(laid)
        Run(dirty, "layout", true, LayoutAllUnit)
    else
        for i = 1, #SLOTS do
            local slot = SLOTS[i].key
            if laid[slot] then
                laid[slot] = nil
                Run(laid, slot, true, LayoutUnit, slot)
            end
        end
        C.Layout.Flush(Run)
    end
    if dirty.visibility then
        dirty.visibility = false
        wipe(visible)
        Run(dirty, "visibility", true, VisibilityAllUnit)
    else
        for slot in pairs(visible) do
            visible[slot] = nil
            Run(visible, slot, true, VisibilityUnit, slot)
        end
    end
    if C.Preview.mode == "options" then S.Dispatch(C.Preview.PaintLabels) end
end

-- The flush flag clears whatever raised, so the bars never freeze until a
-- reload. Raising units get their marks back at the end (Settle); after an
-- error only the next mark schedules a flush, so a unit that keeps raising
-- never repeats every frame.
-- The structure and placement steps run only while one of their own marks
-- is there: an empty table or a clear flag would make them a no-op walk of
-- every bar (2026-10-11 raid trace: 1,097 flushes, 4.0 and 3.3 us each).
-- The tables themselves are asked, so no mark from any writer (the units'
-- retry included) can be missed; the earlier steps run before each check.
FlushNow = function()
    if not M.active then
        scheduled = false
        ResetDirty()
        return
    end
    FlushData()
    if next(sync) ~= nil or next(style) ~= nil then FlushStructure() end
    FlushEntries()
    FlushTextsAndSounds()
    if dirty.layout or dirty.visibility or next(laid) ~= nil or next(visible) ~= nil
        or next(layoutRequests) ~= nil then
        FlushPlacement()
    end
    scheduled = false
    if Settle() then return end
    if Pending() or next(layoutRequests) then Schedule() end
end
