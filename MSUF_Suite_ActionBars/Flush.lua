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
local Virtual = AB.VirtualPaint
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
-- What a shown-button plan read per mapped slot: filled, and for a plain
-- spell that spell (Events.lua GridChanged).
local gridFill, gridHold = {}, {}
-- The suite buttons SPELL_UPDATE_COOLDOWN named since the last flush.
local spellCooldowns = {}
-- Protected work for the next flush out of combat: every bar's shown-button
-- plan (grid) and the key routing (routing).
local protected = { grid = false, routing = false }
-- scheduled: the next-frame flush is pending. throttled: the trailing flush
-- of the cooldown/usable cap is pending. Separate flags, so next-frame work
-- (a page change, a slot change) never waits for the cap.
local scheduled, throttled = false, false
local sharedDue
local last = { cooldown = 0, actionbarCooldown = 0, usable = 0, unreported = 0 }
-- Only a capped pass can prove that this kind awaits the trailing timer.
local waiting = {}
-- Slots ACTION_USABLE_CHANGED has named: the client tracks their usability.
local reported = {}
local CAP = 0.1
-- The number of the running flush. A slot paint that completed leaves it on
-- its button (rec.paintedPass): Paint has just read that button's cooldown,
-- charges and count, and nothing in the client changes inside one flush, so
-- the action bar cooldown walk of the same flush passes it by (the full
-- cooldown walk still reads it). A walk in any later flush (the cap's trailing one too) reads it
-- again. 2026-11-16 Ironforge idle trace (Forever, 29.5 s): every pointer move
-- over a unit sent ACTIONBAR_SLOT_CHANGED for the macro slots together with
-- ACTIONBAR_UPDATE_COOLDOWN; 216 slot paints, then 186 cooldown reads of
-- buttons off the spell routes, six a flush on both sides. paintedIn is the
-- last flush that painted a slot: a walk without one keeps its plain
-- per-button function and its instruction budget.
local pass, paintedIn = 0, 0

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

local function WakeRetry()
    -- An otherwise idle slot event still wakes a failed paint or grid plan.
    if next(dirtyBars) or next(dirtySlots) or next(spellCooldowns)
        or (protected.grid or protected.routing or next(gridBars)) and not NS.IsCombatLocked() then
        Schedule()
        return
    end
    for kind, marked in pairs(dirty) do
        if marked and not waiting[kind] then
            Schedule()
            return
        end
    end
end

local function CapDone()
    throttled, sharedDue = false, nil
    -- A pending next-frame flush runs the capped walks as well.
    if not scheduled then Flush() end
end

local function Throttle(wait, due)
    if throttled then return end
    throttled, sharedDue = true, due
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
local function VirtualActionbarCooldown(rec)
    spellCooldowns[rec] = nil
    Virtual.Cooldown(rec)
end
local function VirtualActionbarCooldownAndCount(rec)
    spellCooldowns[rec] = nil
    Virtual.CooldownAndCount(rec)
end
-- The same two walks in a flush that painted slots: a button painted in it
-- is current (pass, above) and done for the flush like one the walk paints.
local function UnpaintedCooldown(rec)
    if rec.paintedPass == pass then
        spellCooldowns[rec] = nil
        return
    end
    OtherCooldown(rec)
end
local function UnpaintedCooldownAndCount(rec)
    if rec.paintedPass == pass then
        spellCooldowns[rec] = nil
        return
    end
    OtherCooldownAndCount(rec)
end
local function ActionbarCooldownWalk()
    -- A native call during paint can queue newer data for the next flush.
    local painted = paintedIn == pass and not scheduled
    if dirty.count then
        Walk(painted and UnpaintedCooldownAndCount or OtherCooldownAndCount)
        if M.config.hideEmptyCharges then WalkNative(NativeCount) end
        dirty.count = false
    else
        Walk(painted and UnpaintedCooldown or OtherCooldown)
    end
    if not AB.directDuration then WalkNative(NativeFeedback) end
end

local function TypedCooldown(rec)
    if rec.virtual then return Virtual.Cooldown(rec) end
    return Cooldown(rec)
end
local NamedCooldown = Virtual and TypedCooldown or Cooldown

-- The buttons SPELL_UPDATE_COOLDOWN named, once each per flush.
local function SpellCooldownWalk()
    for rec in pairs(spellCooldowns) do
        spellCooldowns[rec] = nil
        if rec.filled and Visible(rec.bar) then Run(spellCooldowns, rec, true, NamedCooldown, rec) end
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
    local due = last[kind] + CAP
    local wait = due - now
    if wait > 0 then
        waiting[kind] = due
        Throttle(wait, due)
        return false
    end
    waiting[kind] = nil
    dirty[kind] = false
    last[kind] = now
    Run(dirty, kind, true, fn)
    return true
end

-- A full refresh repaints every bar and absorbs the same-frame marks.
local function ExpandFull()
    dirty.full = false
    for kind in pairs(dirty) do dirty[kind], waiting[kind] = false, nil end
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
    if not Visible(bar) then return end
    if bar.native then
        if bar.index == AB.ENUM.BAR.MAIN then AB.RefreshNativeBar(bar) end
        return
    end
    PaintBar(bar)
    -- A completed owned-bar paint already refilled it. A new mark schedules
    -- another pass and prevents reuse, including marks raised during paint.
    if bar.owned and not scheduled and next(dirtySlots) and refillBars[bar] == nil then
        refillBars[bar] = false
    end
end

local function PaintSlot(slot)
    local list = slotMap[slot]
    if not list then return end
    for i = 1, #list do
        local rec = list[i]
        if rec.native then
            if AB.nativeSlotEffects and Visible(rec.bar) then
                if M.config.hideEmptyCharges then NativeCount(rec) end
                if M.config.procGlow == PROC_PIXEL then GlowCheck(rec) end
            end
        elseif (refillBars[rec.bar] ~= false or scheduled) and Visible(rec.bar) then
            Paint(rec, true)
            -- Only a paint that returned: a raising one leaves the walks on it.
            rec.paintedPass, paintedIn = pass, pass
            if rec.refillFilled ~= rec.filled then refillBars[rec.bar] = true end
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
    for bar, needed in pairs(refillBars) do
        refillBars[bar] = nil
        if needed then Run(refillBars, bar, true, Refill, bar) end
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
    if AB.procRoutesStale then
        if M.config.procGlow == PROC_PIXEL then WalkNative(GlowCheck) end
        AB.procRoutesStale = nil
    end
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

-- Shown/empty state and key routing are protected: out of combat only. A
-- bar's shown-button plan is one SecureHandlerExecute of the restricted GRID
-- snippet. The 2026-10-11 raid trace ran five plans (374 us each) in the
-- first flush after every combat end, because Blizzard's in-combat plan
-- (Blizzard.lua) and slot changes (Events.lua) mark the bars, and five
-- again after a stealth swap just after combat. A flush runs at most
-- GRID_PER_FLUSH plans, in bar order, and schedules the next flush for the
-- rest. In combat the flush returns before any plan; PLAYER_REGEN_ENABLED
-- resumes the parked ones (Events.lua).
local GRID_PER_FLUSH = 2
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
    if next(gridBars) then
        local budget = GRID_PER_FLUSH
        for index = 1, 10 do
            local bar = AB.bars[index]
            if bar and gridBars[bar] then
                if budget == 0 then
                    Schedule()
                    break
                end
                budget = budget - 1
                gridBars[bar] = nil
                Run(gridBars, bar, true, GridUnit, bar)
            end
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
    pass = pass + 1
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
    local due = waiting[kind]
    -- Only an equally early shared wake can replace this kind's next frame.
    if due and dirty[kind] and throttled and sharedDue <= due and not scheduled and GetTime() < due then return end
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
-- burst (spec, talent or loadout swap) marks the bar and one of the next
-- flushes runs the plan once (FlushProtected: two bars per flush); in combat
-- it waits for combat to end. The reused buttons' OnHide wrap keeps them
-- shown until then.
function AB.Regrid(bar)
    gridBars[bar] = true
    Schedule()
end

-- StopDispatcher: every mark and every parked unit is dropped.
local function Reset()
    for kind in pairs(dirty) do dirty[kind], waiting[kind] = false, nil end
    for slot in pairs(dirtySlots) do dirtySlots[slot] = nil end
    for rec in pairs(spellCooldowns) do spellCooldowns[rec] = nil end
    for bar in pairs(dirtyBars) do dirtyBars[bar] = nil end
    for bar in pairs(gridBars) do gridBars[bar] = nil end
    for slot in pairs(gridFill) do gridFill[slot] = nil end
    for slot in pairs(gridHold) do gridHold[slot] = nil end
    protected.routing, protected.grid = false, false
    ResetUnits()
end

-- The existing dirty passes keep the native callbacks. The independent bar
-- chooses its typed counterpart only when walking its own filled buttons.
if Virtual then
    Virtual.walk = {
        [Cooldown] = Virtual.Cooldown, [CooldownAndCount] = Virtual.CooldownAndCount,
        [OtherCooldown] = VirtualActionbarCooldown, [OtherCooldownAndCount] = VirtualActionbarCooldownAndCount,
        [UnpaintedCooldown] = VirtualActionbarCooldown, [UnpaintedCooldownAndCount] = VirtualActionbarCooldownAndCount,
        [Usable] = Virtual.Usable, [UsableIfUnreported] = Virtual.Usable,
        [Count] = Virtual.Count, [State] = Virtual.State, [Icon] = Virtual.Paint,
    }
end

-- What the event map (Events.lua) marks directly.
AB.Dirty = {
    slots = dirtySlots, grid = gridBars, gridFill = gridFill, gridHold = gridHold, protected = protected, reported = reported,
    spellCooldowns = spellCooldowns, Schedule = Schedule, WakeRetry = WakeRetry, Mark = Mark, Reset = Reset,
}
