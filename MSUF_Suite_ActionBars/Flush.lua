local _, P = ...
local NS, S = P.NS, P.Suite
-- One dirty mask with a single next-frame flush: the event map (Events.lua)
-- marks work, the flush paints it (Paint.lua, NativeButtons.lua). Same-frame
-- marks merge for free; cooldown and usable storms get a 0.1 s leading-edge
-- cap with one trailing flush; per-bar filled-button lists and a slot map
-- keep targeted events targeted; dormant (hidden) bars are skipped.
local AB = P.ActionBars
local M = AB.M
local Painter, NativeButtons = AB.Painter, AB.NativeButtons
local PROC_PIXEL = AB.ENUM.PROC_GLOW.PIXEL
local slotMap, Visible = Painter.slotMap, Painter.Visible
local Walk, WalkNative, Paint, Icon, Refill, PaintBar = Painter.Walk, Painter.WalkNative, Painter.Paint, Painter.Icon, Painter.Refill, Painter.PaintBar
local Cooldown, Usable, State, Count, GlowCheck, AllKeyTexts = Painter.Cooldown, Painter.Usable, Painter.State, Painter.Count, Painter.GlowCheck,
    Painter.AllKeyTexts
local SpellRouted = Painter.SpellRouted
local NativeFeedback, NativeState, NativeCount = NativeButtons.Feedback, NativeButtons.State, NativeButtons.Count
local NativeColor, Retint = NativeButtons.Color, NativeButtons.Retint
-- tint: re-applies the range color after a color change; keys: binding
-- texts; usable: every suite button's usability; unreported: only those on
-- slots ACTION_USABLE_CHANGED never named. cooldown: every button's
-- cooldown; actionbarCooldown: those SPELL_UPDATE_COOLDOWN does not keep
-- current (ACTIONBAR_UPDATE_COOLDOWN names no action).
local dirty = {
    cooldown = false, actionbarCooldown = false, usable = false, unreported = false, state = false, count = false,
    icon = false, tint = false, keys = false, full = false,
}
local dirtySlots, dirtyBars, refillBars, gridBars = {}, {}, {}, {}
-- The suite buttons SPELL_UPDATE_COOLDOWN named since the last flush.
local spellCooldowns = {}
-- Protected work for the next flush out of combat: every bar's shown-button
-- plan (grid) and the key routing (routing).
local protected = { grid = false, routing = false }
-- scheduled: the next-frame flush is pending. throttled: the trailing flush
-- of the cooldown/usable cap is pending. Separate flags, so next-frame work
-- (a page change, a slot change) never waits for the cap.
local scheduled, throttled = false, false
local last = { cooldown = 0, actionbarCooldown = 0, usable = 0, unreported = 0 }
-- Slots ACTION_USABLE_CHANGED has named: the client tracks their usability.
local reported = {}
local CAP = 0.1

------------------------------------------------------------------ flush
-- Every unit of flush work (a paint kind, one bar, one slot, one bar's
-- shown-button plan, the key routing) clears its mark first and runs
-- isolated with one retry (S.NewUnitRunner, Runtime.lua). A paint kind is
-- one unit for all buttons: the cooldown walk is the hot path.
local Run, Settle, ResetUnits = S.NewUnitRunner()

local Flush
local function Schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, Flush)
end

local function CapDone()
    throttled = false
    -- A pending next-frame flush runs the capped walks as well.
    if not scheduled then Flush() end
end

local function Throttle(wait)
    if throttled then return end
    throttled = true
    C_Timer.After(wait, CapDone)
end

local function CooldownAndCount(rec)
    local charges, queried = Cooldown(rec)
    Count(rec, charges, queried)
end
local function CooldownWalk()
    if dirty.count then
        -- Charge and cooldown events often arrive together. Consume their
        -- count mark only after the combined walk succeeded; a failure leaves
        -- the ordinary count unit intact and cooldown's isolated retry armed.
        Walk(CooldownAndCount)
        if M.config.hideEmptyCharges then WalkNative(NativeCount) end
        dirty.count = false
    else
        Walk(Cooldown)
    end
    if not AB.directDuration then WalkNative(NativeFeedback) end
end

-- ACTIONBAR_UPDATE_COOLDOWN: the buttons SPELL_UPDATE_COOLDOWN does not
-- keep current, Blizzard's reused buttons' feedback, and the count mark the
-- same way as the full walk. A button this walk paints is done for the
-- flush: a spell event that also named it (a charge action) reads nothing
-- again.
local function OtherCooldown(rec)
    if SpellRouted(rec) then return end
    spellCooldowns[rec] = nil
    Cooldown(rec)
end
local function OtherCooldownAndCount(rec)
    if SpellRouted(rec) then
        Count(rec)
        return
    end
    spellCooldowns[rec] = nil
    CooldownAndCount(rec)
end
local function ActionbarCooldownWalk()
    if dirty.count then
        Walk(OtherCooldownAndCount)
        if M.config.hideEmptyCharges then WalkNative(NativeCount) end
        dirty.count = false
    else
        Walk(OtherCooldown)
    end
    if not AB.directDuration then WalkNative(NativeFeedback) end
end

-- The buttons SPELL_UPDATE_COOLDOWN named, once each per flush.
local function SpellCooldownWalk()
    for rec in pairs(spellCooldowns) do
        spellCooldowns[rec] = nil
        if rec.filled and Visible(rec.bar) then Run(spellCooldowns, rec, true, Cooldown, rec) end
    end
end
local function UsableWalk() Walk(Usable) end
-- ACTION_USABLE_CHANGED names the slots it tracks; a suite button on a slot
-- it never named (bars 9/10 have no Blizzard button) follows
-- ACTIONBAR_UPDATE_USABLE instead.
local function UsableIfUnreported(rec)
    if not reported[rec.slot] then Usable(rec) end
end
local function UnreportedWalk() Walk(UsableIfUnreported) end

-- Leading edge next frame, then at most one walk per CAP seconds. True
-- when the walk ran.
local function Capped(kind, now, fn)
    if not dirty[kind] then return false end
    local wait = last[kind] + CAP - now
    if wait > 0 then
        Throttle(wait)
        return false
    end
    dirty[kind] = false
    last[kind] = now
    Run(dirty, kind, true, fn)
    return true
end

-- A full refresh repaints every bar and absorbs the same-frame marks.
local function ExpandFull()
    dirty.full = false
    for kind in pairs(dirty) do dirty[kind] = false end
    for slot in pairs(dirtySlots) do dirtySlots[slot] = nil end
    for rec in pairs(spellCooldowns) do spellCooldowns[rec] = nil end
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar then dirtyBars[bar] = true end
    end
    dirty.keys = true
    -- Suite paint skips native buttons, so their optional effects still
    -- need one pass when a global refresh absorbs same-frame events.
    if M.config.hideEmptyCharges then dirty.count = true end
    if not M.config.castHighlight then dirty.state = true end
    if not AB.directDuration then dirty.cooldown = true end
end

local function PaintVisibleBar(bar)
    if Visible(bar) then PaintBar(bar) end
end

local function PaintSlot(slot)
    local list = slotMap[slot]
    if not list then return end
    for i = 1, #list do
        local rec = list[i]
        if not rec.native and Visible(rec.bar) then
            Paint(rec)
            refillBars[rec.bar] = true
        end
    end
end

local function PaintDirty()
    for bar in pairs(dirtyBars) do
        dirtyBars[bar] = nil
        Run(dirtyBars, bar, true, PaintVisibleBar, bar)
    end
    for slot in pairs(dirtySlots) do
        dirtySlots[slot] = nil
        Run(dirtySlots, slot, true, PaintSlot, slot)
    end
    for bar in pairs(refillBars) do
        refillBars[bar] = nil
        Run(refillBars, bar, true, Refill, bar)
    end
end

local function StateWalk()
    Walk(State)
    if not M.config.castHighlight then WalkNative(NativeState) end
end
local function CountWalk()
    Walk(Count)
    if M.config.hideEmptyCharges then WalkNative(NativeCount) end
end
local function IconWalk()
    Walk(Icon)
    for index = 1, 10 do
        local bar = AB.bars[index]
        if bar and not bar.native and Visible(bar) then Refill(bar) end
    end
end
local function TintWalk()
    Walk(Retint)
    WalkNative(Retint)
end
local function NativeFullWalk()
    WalkNative(NativeColor)
    if M.config.procGlow == PROC_PIXEL then WalkNative(GlowCheck) end
end

-- The uncapped paint kinds, in this order.
local WALK_KINDS = { "state", "count", "icon", "tint", "keys" }
local WALKS = { state = StateWalk, count = CountWalk, icon = IconWalk, tint = TintWalk, keys = AllKeyTexts }

local function WalkDirty(now)
    -- The full cooldown walk (loss of control, a global cooldown, an unnamed
    -- spell, a setting) also covers both targeted cooldown kinds.
    if dirty.cooldown then dirty.actionbarCooldown = false end
    if Capped("cooldown", now, CooldownWalk) then
        for rec in pairs(spellCooldowns) do spellCooldowns[rec] = nil end
    else
        Capped("actionbarCooldown", now, ActionbarCooldownWalk)
        if next(spellCooldowns) then SpellCooldownWalk() end
    end
    -- The full usability walk covers the unreported slots.
    if dirty.usable then dirty.unreported = false end
    Capped("usable", now, UsableWalk)
    Capped("unreported", now, UnreportedWalk)
    for i = 1, #WALK_KINDS do
        local kind = WALK_KINDS[i]
        if dirty[kind] then
            dirty[kind] = false
            Run(dirty, kind, true, WALKS[kind])
        end
    end
end

-- Shown/empty state and key routing are protected: out of combat only.
local function GridUnit(bar)
    AB.Execute(bar.header, AB.SNIPPET.GRID)
end
local function FlushProtected()
    if NS.IsCombatLocked() then return end
    if protected.grid then
        protected.grid = false
        for index = 1, 10 do
            local bar = AB.bars[index]
            if bar then gridBars[bar] = true end
        end
    end
    for index = 1, 10 do
        local bar = AB.bars[index]
        if bar and gridBars[bar] then
            gridBars[bar] = nil
            Run(gridBars, bar, true, GridUnit, bar)
        end
    end
    if protected.routing then
        protected.routing = false
        Run(protected, "routing", true, AB.UpdateRouting)
    end
end

-- Raising units get their marks back at the end (Settle); only the next
-- mark schedules the flush that retries them, so a unit that keeps raising
-- never repeats every frame.
Flush = function()
    scheduled = false
    if not M.active then return end
    local now = GetTime()
    local nativeFull = dirty.full
    if nativeFull then ExpandFull() end
    PaintDirty()
    WalkDirty(now)
    if nativeFull then Run(dirty, "full", true, NativeFullWalk) end
    FlushProtected()
    Settle()
end

local function Mark(kind)
    dirty[kind] = true
    Schedule()
end
AB.Mark = Mark
function AB.MarkAll()
    dirty.full = true
    protected.routing = true
    protected.grid = true
    Schedule()
end
function AB.MarkBar(bar)
    dirtyBars[bar] = true
    Schedule()
end

-- Re-runs the suite's shown-button plan on one bar after Blizzard applied
-- its own (Blizzard.lua). Blizzard plans on every UpdateAction, so a slot
-- burst (spec, talent or loadout swap) marks the bar and the next flush runs
-- the plan once; in combat it waits for combat to end (FlushProtected). The
-- reused buttons' OnHide wrap keeps them shown until then.
function AB.Regrid(bar)
    gridBars[bar] = true
    Schedule()
end

-- StopDispatcher: every mark and every parked unit is dropped.
local function Reset()
    for kind in pairs(dirty) do dirty[kind] = false end
    for slot in pairs(dirtySlots) do dirtySlots[slot] = nil end
    for rec in pairs(spellCooldowns) do spellCooldowns[rec] = nil end
    for bar in pairs(dirtyBars) do dirtyBars[bar] = nil end
    for bar in pairs(gridBars) do gridBars[bar] = nil end
    protected.routing, protected.grid = false, false
    ResetUnits()
end

-- What the event map (Events.lua) marks directly.
AB.Dirty = {
    slots = dirtySlots, grid = gridBars, protected = protected, reported = reported, spellCooldowns = spellCooldowns,
    Schedule = Schedule, Mark = Mark, Reset = Reset,
}
