local _, P = ...
local NS, S = P.NS, P.Suite
-- The event map: one event frame (the module context) marks work in the
-- dirty mask (Flush.lua); only slot-level payloads (usability, range, proc
-- glows) paint their buttons at once. Visibility edges, page changes from
-- the restricted page handler and the dispatcher's start and stop are here
-- too. No per-event allocation.
local AB = P.ActionBars
local M = AB.M
local Public = S.Public
local PROC_PIXEL, PROC_NONE = AB.ENUM.PROC_GLOW.PIXEL, AB.ENUM.PROC_GLOW.NONE
local MAIN_BAR = AB.ENUM.BAR.MAIN
local Painter, Dirty = AB.Painter, AB.Dirty
local slotMap, Visible, NewChargeEpoch = Painter.slotMap, Painter.Visible, Painter.NewChargeEpoch
local Tint, Usable, Cooldown, ReleaseRange = Painter.Tint, Painter.Usable, Painter.Cooldown, Painter.ReleaseRange
local CacheAction, ActionSpell, SetGlow, GlowCheck = Painter.CacheAction, Painter.ActionSpell, Painter.SetGlow, Painter.GlowCheck
local GLOW_SPELL, GLOW_DYNAMIC, GLOW_FLYOUT = Painter.GLOW_SPELL, Painter.GLOW_DYNAMIC, Painter.GLOW_FLYOUT
local Walk, WalkNative, MapButton, UnmapButton, Remap, AllKeyTexts = Painter.Walk, Painter.WalkNative, Painter.MapButton, Painter.UnmapButton,
    Painter.Remap, Painter.AllKeyTexts
local dirtySlots, gridBars, protected, reported = Dirty.slots, Dirty.grid, Dirty.protected, Dirty.reported
local Schedule, Mark = Dirty.Schedule, Dirty.Mark

------------------------------------------------------------------ events
local function SlotChanged(_, _, slot)
    if not Public(slot) or type(slot) ~= "number" or slot == 0 then
        AB.MarkAll()
        return
    end
    dirtySlots[slot] = true
    -- A filled or emptied slot changes which buttons show; a slot becoming or
    -- ceasing to be a flyout changes key routing. Suite buttons re-read their
    -- action when repainted; Blizzard paints the native ones, so their proc
    -- glow match is re-read here while the pixel glow follows it.
    local list = slotMap[slot]
    if list then
        local flyout = AB.IsFlyoutSlot(slot)
        local nativeGlow = M.config.procGlow == PROC_PIXEL
        for i = 1, #list do
            local rec = list[i]
            gridBars[rec.bar] = true
            if rec.native then
                if nativeGlow then CacheAction(rec) end
            elseif rec.flyout ~= flyout then
                rec.flyout = flyout
                protected.routing = true
            end
        end
    end
    Schedule()
end

local function UsableChanged(_, _, changes)
    if type(changes) ~= "table" then
        Mark("usable")
        return
    end
    for i = 1, #changes do
        local change = changes[i]
        local slot = type(change) == "table" and change.slot
        if Public(slot) and slot then reported[slot] = true end
        local list = Public(slot) and slotMap[slot]
        if list then
            for n = 1, #list do
                local rec = list[n]
                if not rec.native and rec.filled and Visible(rec.bar) then Usable(rec, change.usable, change.noMana) end
            end
        end
    end
end

local function RangeChanged(_, _, slot, inRange, checksRange)
    if not M.config.rangeColoring then return end
    local list = Public(slot) and slotMap[slot]
    if not list then return end
    local out = Public(inRange) and Public(checksRange) and checksRange and not inRange or nil
    for i = 1, #list do
        local rec = list[i]
        if rec.rangeSlot == slot and rec.outOfRange ~= out then
            rec.outOfRange = out
            if not out then
                Usable(rec)
            else
                Tint(rec)
            end
        end
    end
end

-- Proc glows match the event's spell against spell and macro actions;
-- flyouts rescan their slots. Spell actions use the ID cached at paint
-- time, so a glow event reads no action info for them.
local glowSpell, glowShow
local function GlowMatch(rec)
    local kind = rec.glowKind
    if kind == GLOW_SPELL then
        if rec.glowID == glowSpell then SetGlow(rec, glowShow and M.config.procGlow ~= PROC_NONE) end
    elseif kind == GLOW_FLYOUT then
        GlowCheck(rec)
    elseif kind == GLOW_DYNAMIC then
        local id, flyout = ActionSpell(rec.slot)
        if id == glowSpell then
            SetGlow(rec, glowShow and M.config.procGlow ~= PROC_NONE)
        elseif flyout then
            GlowCheck(rec)
        end
    end
end
local function Glow(_, event, spell)
    if M.config.procGlow == PROC_NONE then return end
    if not Public(spell) or type(spell) ~= "number" then
        AB.MarkAll()
        return
    end
    glowSpell, glowShow = spell, event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
    Walk(GlowMatch)
    if M.config.procGlow == PROC_PIXEL then WalkNative(GlowMatch) end
end

local function ActiveLossOfControl()
    local count = C_LossOfControl.GetActiveLossOfControlDataCountByUnit("player")
    if Public(count) and type(count) == "number" then return count > 0 end
end

local function LossOfControl(_, _, unit)
    if Public(unit) and unit and unit ~= "player" then return end
    -- The event marks both the start and the end of an effect. Keep checking
    -- individual action slots only while the player has an active effect.
    local active = ActiveLossOfControl()
    AB.locActive = active == nil and true or active
    Mark("cooldown")
end

-- Key texts are cosmetic and update at once, also in combat; routing waits
-- for combat to end (Bindings.lua).
local function Bindings()
    AllKeyTexts()
    AB.UpdateRouting()
end

local function CVarChanged(_, _, name)
    if name == "ActionButtonUseKeyDown" or name == "lockActionBars" or name == "LOCK_ACTIONBAR" then
        if NS.IsCombatLocked() then
            AB.attributesPending = true
        else
            AB.UpdateClickAttributes()
        end
    end
end

local function FormsChanged()
    local bar = AB.bars[11]
    if not bar then return end
    local forms = AB.HasForms()
    local count = AB.Count(bar, M.config)
    if bar.count == count and bar.forms == forms then return end
    -- Layout, adoption and the driver are protected: re-apply after combat.
    if NS.IsCombatLocked() then
        S.Queue("actionbars")
    else
        M:Refresh()
    end
end

-- Combat starts: PLAYER_REGEN_DISABLED comes before the lockdown, the last
-- moment a protected header may stop an animation. Other features animate
-- the headers (QoL party effects through S.VisitPartyActionBars); a header
-- turning in combat would draw its buttons away from their click areas.
local function RegenDisabled()
    for index = 1, 10 do
        local bar = AB.bars[index]
        if bar and bar.owned then bar.header:StopAnimating() end
    end
end

local function RegenEnabled()
    -- A spellbook or macro window closed (or opened) in combat.
    if AB.panelPending then AB.SyncPanelReveal() end
    if AB.routingPending then AB.UpdateRouting() end
    if AB.attributesPending then
        AB.attributesPending = nil
        AB.UpdateClickAttributes()
    end
    if AB.dragPending or AB.dragging then AB.ApplyDrag() end
    if protected.grid or protected.routing or next(gridBars) then Schedule() end
end

-- A new UI scale or resolution moves the pixel grid: one refresh per burst,
-- next frame (after Blizzard applied the scale), re-snaps and restyles every
-- bar (Controller.lua Collect). In combat the refresh waits for combat end.
local scalePending = false
local function ApplyScale()
    scalePending = false
    if M.active then M:Refresh() end
end
local function ScaleChanged()
    if scalePending then return end
    scalePending = true
    C_Timer.After(0, ApplyScale)
end

local function GamepadChanged()
    if not M.active or not NS.Client.isForever then return end
    if NS.IsCombatLocked() then
        AB.gamepadVisibilityPending = true
        S.Queue("actionbars")
    else
        AB.ApplyVisibility()
    end
end

-- Blizzard's buttons on Retail and Forever follow ACTIONBAR_UPDATE_COOLDOWN
-- for swipes, SPELL_UPDATE_CHARGES for counts, and for usability the slot
-- payloads of ACTION_USABLE_CHANGED plus one full re-read on
-- PLAYER_MOUNT_DISPLAY_CHANGED (Blizzard_ActionBar/Shared/ActionButton.lua;
-- ACTIONBAR_UPDATE_USABLE is no longer registered there); so do these.
-- Whether ACTION_USABLE_CHANGED also covers slots without a registered
-- Blizzard button (C_ActionBar.RegisterActionUIButton) is not documented:
-- ACTIONBAR_UPDATE_USABLE re-reads the suite buttons on slots it never named.
local EVENTS = {
    ADDON_LOADED = function() AB.SyncPanelReveal() end,
    ACTIONBAR_SLOT_CHANGED = SlotChanged,
    ACTIONBAR_UPDATE_COOLDOWN = function() Mark("cooldown") end,
    SPELL_UPDATE_CHARGES = function()
        NewChargeEpoch()
        Mark("count")
    end,
    LOSS_OF_CONTROL_ADDED = LossOfControl,
    LOSS_OF_CONTROL_UPDATE = LossOfControl,
    ACTION_USABLE_CHANGED = UsableChanged,
    ACTIONBAR_UPDATE_USABLE = function() Mark("unreported") end,
    PLAYER_MOUNT_DISPLAY_CHANGED = function() Mark("usable") end,
    ACTIONBAR_UPDATE_STATE = function() Mark("state") end,
    CURRENT_SPELL_CAST_CHANGED = function() Mark("state") end,
    START_AUTOREPEAT_SPELL = function() Mark("state") end,
    STOP_AUTOREPEAT_SPELL = function() Mark("state") end,
    TRADE_SKILL_SHOW = function() Mark("state") end,
    TRADE_SKILL_CLOSE = function() Mark("state") end,
    UPDATE_SHAPESHIFT_FORM = function()
        NewChargeEpoch()
        Mark("icon")
    end,
    SPELL_UPDATE_ICON = function()
        NewChargeEpoch()
        Mark("icon")
    end,
    SPELLS_CHANGED = function()
        NewChargeEpoch()
        Mark("icon")
    end,
    UPDATE_SUMMONPETS_ACTION = function()
        NewChargeEpoch()
        Mark("icon")
    end,
    BAG_UPDATE_DELAYED = function() Mark("count") end,
    PLAYER_EQUIPMENT_CHANGED = function()
        NewChargeEpoch()
        AB.MarkAll()
    end,
    PLAYER_ENTERING_WORLD = function()
        NewChargeEpoch()
        AB.MarkAll()
    end,
    PET_STABLE_UPDATE = function() AB.MarkAll() end,
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = Glow,
    SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = Glow,
    ACTION_RANGE_CHECK_UPDATE = RangeChanged,
    UPDATE_BINDINGS = Bindings,
    CVAR_UPDATE = CVarChanged,
    ACTIONBAR_SHOWGRID = function() AB.CursorChanged() end,
    ACTIONBAR_HIDEGRID = function() AB.CursorChanged() end,
    CURSOR_CHANGED = function() AB.CursorChanged() end,
    UPDATE_SHAPESHIFT_FORMS = function()
        NewChargeEpoch()
        FormsChanged()
    end,
    PLAYER_REGEN_DISABLED = RegenDisabled,
    PLAYER_REGEN_ENABLED = RegenEnabled,
    UI_SCALE_CHANGED = ScaleChanged,
    DISPLAY_SIZE_CHANGED = ScaleChanged,
    GAME_PAD_ACTIVE_CHANGED = GamepadChanged,
    GAME_PAD_CONNECTED = GamepadChanged,
    GAME_PAD_DISCONNECTED = GamepadChanged,
    INPUT_DEVICE_INTERFACE_TRANSITION = GamepadChanged,
}

-- Range checks and spell overlays can fire frequently in combat. Keep their
-- listeners absent when the matching paint feature is off; Refresh re-syncs
-- them after settings change without touching the stable event dispatcher.
local optionalEvents = {
    GAME_PAD_ACTIVE_CHANGED = true,
    GAME_PAD_CONNECTED = true,
    GAME_PAD_DISCONNECTED = true,
    INPUT_DEVICE_INTERFACE_TRANSITION = true,
    ACTION_RANGE_CHECK_UPDATE = true,
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true,
    SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true,
}
-- Context:Event's third argument: the handler also runs in combat.
local ALLOW_COMBAT = true
function AB.SyncOptionalEvents()
    local context = M.context
    for event in pairs(optionalEvents) do
        local gamepadEvent = event == "GAME_PAD_ACTIVE_CHANGED" or event == "GAME_PAD_CONNECTED"
            or event == "GAME_PAD_DISCONNECTED" or event == "INPUT_DEVICE_INTERFACE_TRANSITION"
        local wanted = event == "ACTION_RANGE_CHECK_UPDATE" and M.config.rangeColoring
            or event ~= "ACTION_RANGE_CHECK_UPDATE" and M.config.procGlow ~= PROC_NONE
        if gamepadEvent then wanted = NS.Client.isForever and AB.AnyGamepadHidden() end
        if wanted then
            context:Event(event, EVENTS[event], ALLOW_COMBAT)
        else
            context:RemoveEvent(event)
        end
    end
end

-- Visibility edges: a shown bar repaints from live state; a hidden bar
-- releases its range checks and is skipped by every walk.
local function Shown(header)
    local bar = M.active and AB.headers[header]
    if bar then
        AB.MarkBar(bar)
        if bar.native then AB.RefreshNativeBar(bar) end
    end
end
local function Hidden(header)
    local bar = AB.headers[header]
    if not bar or not bar.owned then return end
    for i = 1, #bar.buttons do ReleaseRange(bar.buttons[i]) end
end

-- Page changes arrive from the restricted page handler, also in combat.
-- Only bar 1's twelve buttons move in the slot map. The bars' own paging
-- (target, modifier, opt-outs) fires no ACTIONBAR_PAGE_CHANGED, so the
-- cooldown manager's glows on bar 1 learn of it from ActionsChanged.
local ACTIONS_CHANGED = "MSUFSuite.ActionBars.ActionsChanged"
function AB.OnHeaderAttribute(bar, name, value)
    if not M.active then return end
    if name == "actionpage" and bar.index == MAIN_BAR then
        local buttons = bar.buttons
        for i = 1, #buttons do UnmapButton(buttons[i]) end
        AB.PageSlots(bar, value)
        for i = 1, #buttons do MapButton(buttons[i]) end
        protected.routing = true
        AB.MarkBar(bar)
        EventRegistry:TriggerEvent(ACTIONS_CHANGED)
    elseif name == "state-vis" then
        AB.UpdateAlpha(bar)
    end
end
-- Hooked only on cooldowns StartDispatcher recorded in AB.cooldownOwner.
local function CooldownDone(frame)
    local rec = AB.cooldownOwner[frame]
    if rec and M.active and rec.filled then Cooldown(rec) end
end

function AB.StartDispatcher()
    local context = M.context
    AB.locActive = ActiveLossOfControl()
    for event, handler in pairs(EVENTS) do
        if not optionalEvents[event] then context:Event(event, handler, ALLOW_COMBAT) end
    end
    AB.SyncOptionalEvents()
    AB.cooldownOwner = AB.cooldownOwner or {}
    for index = 1, AB.BAR_COUNT do
        local bar = AB.bars[index]
        if bar and not bar.visHooked then
            bar.visHooked = true
            bar.header:HookScript("OnShow", Shown)
            bar.header:HookScript("OnHide", Hidden)
        end
    end
    for i = 1, #AB.owned do
        local rec = AB.owned[i]
        local cooldown = rec.button.cooldown
        if not rec.native and cooldown and not AB.cooldownOwner[cooldown] then
            AB.cooldownOwner[cooldown] = rec
            cooldown:HookScript("OnCooldownDone", CooldownDone)
        end
    end
    local bar = AB.bars[1]
    if bar then AB.PageSlots(bar, bar.header:GetAttribute("actionpage")) end
    Remap()
    AB.MarkAll()
end

function AB.StopDispatcher()
    for event in pairs(EVENTS) do M.context:RemoveEvent(event) end
    for i = 1, #AB.owned do
        local rec = AB.owned[i]
        if not rec.native then
            ReleaseRange(rec)
            SetGlow(rec, false)
        end
    end
    Dirty.Reset()
    AB.locActive = nil
end
