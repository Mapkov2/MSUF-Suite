local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- One dirty mask with a prebuilt next-frame flush (spec 8.2). The settings
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
local pairs, next = pairs, next
local wipe = C.wipe
local Flush = {}
C.Flush = Flush

------------------------------------------------------------------ dirty mask
-- keysLater: keybind texts after a resolve, through the coalesced request.
local dirty = { catalog = false, resolve = false, index = false, events = false, cooldowns = false, usable = false, effects = false,
    keybinds = false, keysLater = false, alerts = false, layout = false, visibility = false }
-- Per slot: sync (structure), style, behavior (entry refresh), visible
-- (driver and alpha), laid (layout of that bar only).
local sync, style, behavior, visible, laid, marked = {}, {}, {}, {}, {}, {}
Flush.dirty, Flush.sync, Flush.style, Flush.behavior, Flush.visible = dirty, sync, style, behavior, visible
-- Every unit of flush work runs isolated with one retry (S.NewUnitRunner,
-- Runtime.lua).
local Run, Settle, ResetUnits = S.NewUnitRunner()
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
local function Pending()
    for _, on in pairs(dirty) do
        if on then
            return true
        end
    end
    return next(sync) ~= nil or next(style) ~= nil or next(behavior) ~= nil or next(visible) ~= nil or next(laid) ~= nil
        or next(marked) ~= nil
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
        if slot and (entry.family == 2 or auraTouched[entry]) then sync[slot] = true end
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
local function ResolveUnit()
    local _, any = C.Resolve.Build()
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
local function EntryUnit(entry, reason)
    if reason == "full" then C.Icons.Texture(entry) end
    if C.Time.Refresh(entry, reason) then C.Layout.Request(entry.slot) end
    if reason == "full" then C.Effects.Update(entry) end
end
-- Reuse native usability answers only during one synchronous broadcast.
-- The maps retain capacity, but no answers (including secrets) across passes.
local usableSpells = { seen = {}, usable = {}, noPower = {} }
local usableItems = { seen = {}, usable = {}, noPower = {} }
local function UsableUnit()
    local list = C.Index.usable
    local fx = C.Effects
    for i = 1, #list do
        local entry = list[i]
        if fx.UsableShown(entry) then fx.Usable(entry, entry.src == "i" and usableItems or usableSpells) end
    end
end
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
-- Catalog, resolve, routing index and event registration.
local function FlushData(locked)
    if dirty.catalog then
        dirty.catalog = false
        Run(dirty, "catalog", true, CatalogUnit, locked)
    end
    if dirty.resolve then
        dirty.resolve = false
        Run(dirty, "resolve", true, ResolveUnit)
    end
    if dirty.index then
        dirty.index, dirty.events = false, true
        Run(dirty, "index", true, IndexUnit, locked)
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
    if changed and C.ActionGlows.wanted then C.ActionGlows.Refresh() end
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
    local timeQueries = next(marked) and C.Index.hasSharedTimeSpells and C.Time.BeginQueries()
    for entry, reason in pairs(marked) do
        marked[entry] = nil
        if entry.icon and entry.slot then Run(marked, entry, reason, EntryUnit, entry, reason) end
    end
    if timeQueries then C.Time.EndQueries() end
    if dirty.usable then
        dirty.usable = false
        Run(dirty, "usable", true, UsableUnit)
        -- Run isolates a raising entry; cleanup also runs after that failure.
        for _, map in pairs(usableSpells) do wipe(map) end
        for _, map in pairs(usableItems) do wipe(map) end
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
end

-- The flush flag clears whatever raised, so the bars never freeze until a
-- reload. Raising units get their marks back at the end (Settle); after an
-- error only the next mark schedules a flush, so a unit that keeps raising
-- never repeats every frame.
FlushNow = function()
    if not M.active then
        scheduled = false
        ResetDirty()
        return
    end
    local locked = NS.IsCombatLocked()
    FlushData(locked)
    FlushStructure()
    FlushEntries()
    FlushTextsAndSounds()
    FlushPlacement()
    scheduled = false
    if Settle() then return end
    if Pending() or next(C.Layout.dirty) then Schedule() end
end
