local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Bar visibility. The effect is bar alpha and mouse: bar frames stay shown,
-- so attached bars keep their place and MSUF's anchor stays usable. A rule
-- binds a bar to one of three sources:
--  * "Always" (without a macro hide condition) follows a few rare events for
--    pet battles, vehicles and override bars. It needs no state driver, so
--    the default setup registers none.
--  * "Hidden" is static.
--  * Every other rule is one macro condition: the bar's hide conditions
--    (vehicles, mounted, resting, not in a group, flying, dead) ahead of its
--    "Show" choice. Bars with the same condition share one plain driver
--    frame whose attribute Blizzard's state driver manager keeps current;
--    combat, target, mount and the other changes run Lua only on transitions.
-- "Hide outside instances" has no macro conditional: a flag read on loading
-- screens (ApplyAll) and zone changes joins the driver's answer at paint.
-- Addon frames cannot join Blizzard's "cooldownViewers" roleset, hence the
-- explicit pet battle rule. Only driver (un)registration touches secure
-- code: combat parks it until PLAYER_REGEN_ENABLED. The driver never shows
-- or hides a frame, it reports; Lua writes the alpha. Alpha writes and the
-- fades' Alpha animations are legal on these plain frames in combat, so a
-- fade runs in combat too and nothing falls back to an instant hide there:
-- only a fade time of 0, the preview and an invisible bar switch at once.
local Visibility = { pending = {}, drivers = {}, state = {}, expr = {} }
C.Visibility = Visibility
local SLOTS = NS.CDM.SLOTS
local Public = S.Public
local tremove, abs, min = table.remove, math.abs, math.min
local ATTR = "msufvis"
-- The "Show" choice: Always, In combat, In combat or with a target, Hidden.
local VIS = C.Const.VIS
local VIS_HIDDEN = VIS.HIDDEN
-- Bindings without a driver.
local EVENTS, HIDDEN = "events", "hide"
Visibility.EVENTS, Visibility.HIDDEN = EVENTS, HIDDEN
-- The paint's tables, and the slot keys a combat edge repaints.
local bars, views, states = C.bars, C.views, Visibility.state
local KEYS = {}
for i = 1, #SLOTS do KEYS[i] = SLOTS[i].key end

-- Driver strings: pet battles, the bar's hide conditions in this order,
-- then its "Show" choice; built once per combination. Without the newer
-- conditions they are the strings of the first release.
local BODY = {
    [VIS.ALWAYS] = "show",
    [VIS.COMBAT] = "[combat] show; hide",
    [VIS.COMBAT_OR_TARGET] = "[combat][@target,exists] show; hide",
}
local HIDES = { { "hideVehicle", "[vehicleui][overridebar] hide; " }, { "hideMounted", "[mounted] hide; " } }
-- The catalog's other macro conditions: resting, not in a group, flying, dead.
local MACROS = NS.CDM.HIDE_MACROS
for i = 1, #MACROS do HIDES[#HIDES + 1] = { MACROS[i].suffix, MACROS[i].macro .. " hide; " } end
local EXPR = { [VIS.ALWAYS] = {}, [VIS.COMBAT] = {}, [VIS.COMBAT_OR_TARGET] = {} }
function Visibility.Expression(view)
    local vis = view.vis
    if vis == VIS_HIDDEN then return "hide" end
    if vis ~= VIS.COMBAT and vis ~= VIS.COMBAT_OR_TARGET then vis = VIS.ALWAYS end
    local mask, bit = 0, 1
    for i = 1, #HIDES do
        if view[HIDES[i][1]] then mask = mask + bit end
        bit = bit + bit
    end
    local known = EXPR[vis]
    local expr = known[mask]
    if not expr then
        expr = "[petbattle] hide; "
        for i = 1, #HIDES do
            if view[HIDES[i][1]] then expr = expr .. HIDES[i][2] end
        end
        expr = expr .. BODY[vis]
        known[mask] = expr
    end
    return expr
end

local function Macro(view)
    for i = 1, #MACROS do
        if view[MACROS[i].suffix] then return true end
    end
    return false
end
-- What a bar's rule binds to: EVENTS, HIDDEN or a driver expression.
function Visibility.Binding(view)
    local vis = view.vis
    if vis == VIS.HIDDEN then return HIDDEN end
    if vis ~= VIS.COMBAT and vis ~= VIS.COMBAT_OR_TARGET and not view.hideMounted and not Macro(view) then
        return EVENTS
    end
    return Visibility.Expression(view)
end
local function Driven(bind) return bind ~= nil and bind ~= EVENTS and bind ~= HIDDEN end

------------------------------------------------------------------ paint
-- A hidden or fully transparent bar gives the mouse back to whatever lies
-- below it; the icon and aura layers apply it to their frames.
local function Mouse(slot, on)
    C.Icons.SetBarMouse(slot, on)
    C.Auras.SetBarMouse(slot, on)
end

-- bar.hidden: nothing of the bar can be seen (its rule hides it or its
-- opacity is 0); the icon layer reads it for tooltips and mouse. A bar seen
-- again samples the usability it skipped while invisible.
local function Flip(slot, bar, hidden)
    local wasHidden = bar.hidden
    bar.hidden = hidden
    Mouse(slot, not hidden)
    if C.M.active and wasHidden == true and not hidden then
        local list = C.Index.usable
        for i = 1, #list do
            local entry = list[i]
            if entry.slot == slot and entry.icon then C.Effects.Usable(entry) end
        end
    end
end

-- Bars with more than a plain alpha (opacity while hidden, mouseover, a fade
-- time or the instance rule) paint through PaintFx below; every other bar
-- pays this one lookup for them.
local fx = {}
local PaintFx

-- Preview (Edit Mode, options page) suspends the rules: plain bar opacity.
-- Out of combat the bar uses its out-of-combat opacity. Until its source
-- has reported, only "Hidden" hides.
local function Paint(slot)
    local bar, view = bars[slot], views[slot]
    if not bar or not view then return end
    if fx[slot] then return PaintFx(slot, bar, view) end
    local state = C.state
    local hidden, percent
    if state.preview then
        hidden, percent = false, view.alpha
    else
        local value = states[slot]
        if value == nil then
            hidden = view.vis == VIS_HIDDEN
        else
            hidden = value == "hide"
        end
        if state.inCombat then
            percent = view.alpha
        else
            percent = view.oocAlpha
        end
    end
    local alpha = 0
    if not hidden then
        alpha = type(percent) == "number" and percent / 100 or 1
        if alpha < 0 then
            alpha = 0
        elseif alpha > 1 then
            alpha = 1
        end
    end
    hidden = alpha <= 0
    if bar.hidden ~= hidden then Flip(slot, bar, hidden) end
    if bar.alpha ~= alpha then
        bar.alpha = alpha
        bar.frame:SetAlpha(alpha)
    end
end
Visibility.Paint = Paint

------------------------------------------------------------------ hidden, faded, pointed at
-- PaintFx composes the opacity:
--  * shown: "Opacity" in combat, "Opacity out of combat" outside it;
--  * hidden by its rule (the "Show" choice, a hide condition, outside an
--    instance): "Opacity while hidden", never above the shown opacity, so
--    hiding never brightens a bar (0, the default, hides as before);
--  * pointed at while that leaves it below "Opacity" (hidden, faded, or
--    out of combat): "Opacity", the bar's full opacity;
--  * preview: "Opacity", at once, without the mouseover.
local inside = true -- in a dungeon, raid, delve or scenario, battleground or arena
local function Percent(value, fallback)
    if type(value) ~= "number" then return fallback end
    value = value / 100
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

-- Mouseover: a motion-only probe over the bar (clicks pass to the world and
-- the frames below), one per bar, made on first use and kept. It lies above
-- the bar's icons and aura containers, whose sealed aura buttons take no
-- hooks, so the probe alone sees the cursor come and go; it ignores the
-- bar's alpha, as a fully transparent frame does not reliably take hover on
-- Forever. It listens only while pointing would change the bar; meanwhile
-- it covers the bar's own tooltips.
local PROBE_LEVEL = 20
local function Hover(slot, on)
    local bar = bars[slot]
    if not bar or bar.hover == on then return end
    bar.hover = on
    Paint(slot)
end
local function ProbeEnter(probe) Hover(probe.slot, true) end
local function ProbeLeave(probe) Hover(probe.slot, nil) end
local function Probe(slot, bar, on)
    local probe = bar.probe
    if not on then
        bar.hover = nil
        if probe and probe.on then
            probe.on = false
            probe:EnableMouseMotion(false)
        end
        return
    end
    if not probe then
        probe = S.CreateFrame("Frame", nil, bar.frame)
        probe:SetAllPoints(bar.frame)
        probe:SetIgnoreParentAlpha(true)
        probe:EnableMouse(false)
        probe:SetScript("OnEnter", ProbeEnter)
        probe:SetScript("OnLeave", ProbeLeave)
        probe.slot, probe.on = slot, false
        bar.probe = probe
    end
    if not probe.on then
        probe.on = true
        probe:SetFrameLevel(bar.frame:GetFrameLevel() + PROBE_LEVEL)
        probe:EnableMouseMotion(true)
    end
end

-- Fades: the bar frame's own Alpha animation (no per-frame script), made on
-- first use, from the alpha on screen to the new one. The fade time is the
-- length of a full fade; a smaller change takes its share. The bar counts as
-- hidden (mouse, aura containers, usability reads) only once nothing of it
-- shows: a fade-out flips it when it ends, a fade-in when it starts.
local function Settled(group)
    local slot = group.slot
    local bar = bars[slot]
    if not bar or not bar.fading then return end
    bar.fading = nil
    bar.frame:SetAlpha(bar.alpha)
    local hidden = bar.alpha <= 0
    if bar.hidden ~= hidden then Flip(slot, bar, hidden) end
end
local function Fader(bar, slot)
    local group = bar.fader
    if group then return group end
    group = bar.frame:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    group.anim, group.slot = group:CreateAnimation("Alpha"), slot
    -- A stop from outside (not Commit's) settles the bar at its target.
    group:SetScript("OnFinished", Settled)
    group:SetScript("OnStop", Settled)
    bar.fader = group
    return group
end
-- Writes a bar's alpha: at once, or as a fade of `seconds` per full fade.
local function Commit(slot, bar, alpha, seconds)
    local from = bar.alpha
    if from == alpha then
        if not bar.fading then
            local hidden = alpha <= 0
            if bar.hidden ~= hidden then Flip(slot, bar, hidden) end
        end
        return
    end
    bar.alpha = alpha
    local frame, group = bar.frame, bar.fader
    if bar.fading then
        -- A new target mid-fade continues from where the fade is now.
        local progress = group:GetProgress()
        if Public(progress) and type(progress) == "number" then
            from = group.from + (group.to - group.from) * progress
        end
        bar.fading = nil
        group:Stop()
    end
    if from and type(seconds) == "number" and seconds > 0 and frame:IsVisible() then
        local duration = seconds * abs(alpha - from)
        if duration >= .02 then
            group = Fader(bar, slot)
            group.from, group.to = from, alpha
            local anim = group.anim
            anim:SetFromAlpha(from)
            anim:SetToAlpha(alpha)
            anim:SetDuration(duration)
            if alpha > 0 and bar.hidden ~= false then Flip(slot, bar, false) end
            bar.fading = true
            group:Play()
            return
        end
    end
    frame:SetAlpha(alpha)
    local hidden = alpha <= 0
    if bar.hidden ~= hidden then Flip(slot, bar, hidden) end
end

PaintFx = function(slot, bar, view)
    local state = C.state
    local full = Percent(view.alpha, 1)
    if state.preview then
        Probe(slot, bar, false)
        return Commit(slot, bar, full, nil)
    end
    local value, hidden = states[slot], nil
    if value == nil then
        hidden = view.vis == VIS_HIDDEN
    else
        hidden = value == "hide"
    end
    if view.hideWorld and not inside then hidden = true end
    local alpha = full
    if not state.inCombat then alpha = Percent(view.oocAlpha, 1) end
    if hidden then alpha = min(alpha, Percent(view.hiddenAlpha, 0)) end
    local concealed = view.hoverShow == true and alpha < full
    Probe(slot, bar, concealed)
    if concealed and bar.hover then alpha = full end
    Commit(slot, bar, alpha, view.fadeTime)
end

-- A bar leaving PaintFx: no probe, and a running fade ends at its target,
-- so the plain paint takes over a settled frame.
local function Calm(slot)
    local bar = bars[slot]
    if not bar then return end
    Probe(slot, bar, false)
    if bar.fading then
        bar.fading = nil
        bar.fader:Stop()
        bar.frame:SetAlpha(bar.alpha)
    end
end
-- fx and world (the bars on the instance rule) follow the settings.
local world = {}
Visibility.fx, Visibility.world = fx, world
local function Configure(slot)
    local view = views[slot]
    local on = C.M.active and view and view.on or false
    local far = on and view.hideWorld == true or nil
    local effect = far or on and (type(view.hiddenAlpha) == "number" and view.hiddenAlpha > 0
        or view.hoverShow == true or type(view.fadeTime) == "number" and view.fadeTime > 0) or nil
    world[slot] = far
    if fx[slot] and not effect then Calm(slot) end
    fx[slot] = effect
end

------------------------------------------------------------------ "Always": events
local petBattle, vehicle = false, false
local listener, listening, listeningVehicle, listeningWorld = nil, false, false, false
local PET_EVENTS = { "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE" }
local VEHICLE_EVENTS = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR" }
local WORLD_EVENTS = { "ZONE_CHANGED_NEW_AREA" }
local UNIT_EVENT = { UNIT_ENTERED_VEHICLE = true, UNIT_EXITED_VEHICLE = true }

local function InPetBattle()
    local value = C_PetBattles.IsInBattle()
    return Public(value) and value == true
end
-- [vehicleui][overridebar]: vehicle interface or an override bar. The
-- global HasOverrideActionBar exists only with Blizzard's deprecation
-- fallbacks loaded; C_ActionBar has it on both clients.
local function InVehicle()
    local value = UnitHasVehicleUI("player")
    if Public(value) and value then return true end
    value = C_ActionBar.HasOverrideActionBar()
    return Public(value) and value and true or false
end
-- "Hide outside instances": dungeons, raids, delves and scenarios,
-- battlegrounds and arenas (catalog CDM.INSTANCES, by IsInInstance's type).
local INSTANCES = NS.CDM.INSTANCES
local function InInstance()
    local _, kind = IsInInstance()
    return Public(kind) and INSTANCES[kind] == true
end

local function EventState(slot)
    local view = C.views[slot]
    Visibility.state[slot] = (petBattle or (vehicle and view and view.hideVehicle)) and "hide" or "show"
end

-- Instances change behind a loading screen, where the module's
-- PLAYER_ENTERING_WORLD applies every bar again; a zone change reads it too.
local function WorldChanged()
    local now = InInstance()
    if now == inside then return end
    inside = now
    for i = 1, #KEYS do
        local slot = KEYS[i]
        if world[slot] then Paint(slot) end
    end
end

local function OnEvent(_, event, unit)
    if event == "ZONE_CHANGED_NEW_AREA" then return WorldChanged() end
    local pet, veh = petBattle, vehicle
    if event == "PET_BATTLE_OPENING_START" then
        pet = true
    elseif event == "PET_BATTLE_CLOSE" then
        pet = false -- fires twice, the first time still in battle
    else
        if UNIT_EVENT[event] and not (Public(unit) and unit == "player") then return end
        veh = InVehicle()
    end
    if pet == petBattle and veh == vehicle then return end
    petBattle, vehicle = pet, veh
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if Visibility.expr[slot] == EVENTS then
            EventState(slot)
            Paint(slot)
        end
    end
end

local function Listen(list, on)
    for i = 1, #list do
        local event = list[i]
        if NS.Client.SupportsEvent(event) then
            if not on then
                listener:UnregisterEvent(event)
            elseif UNIT_EVENT[event] then
                listener:RegisterUnitEvent(event, "player")
            else
                listener:RegisterEvent(event)
            end
        end
    end
end
-- The events exist only while an "Always" bar needs them (vehicle events
-- only while one of them hides in vehicles, the zone event only while a bar
-- hides outside instances). refresh re-reads the flags.
local function Watch(refresh)
    local any, veh, far = false, false, false
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if Visibility.expr[slot] == EVENTS then
            any = true
            local view = C.views[slot]
            if view and view.hideVehicle then veh = true end
        end
        if world[slot] then far = true end
    end
    if (any or far) and not listener then
        listener = S.CreateFrame("Frame")
        listener:SetScript("OnEvent", OnEvent)
    end
    if any ~= listening then
        listening = any
        Listen(PET_EVENTS, any)
        refresh = true
    end
    if veh ~= listeningVehicle then
        listeningVehicle = veh
        Listen(VEHICLE_EVENTS, veh)
        refresh = true
    end
    if far ~= listeningWorld then
        listeningWorld = far
        Listen(WORLD_EVENTS, far)
        refresh = true
    end
    if refresh then
        petBattle = listening and InPetBattle()
        vehicle = listeningVehicle and InVehicle()
        inside = not listeningWorld or InInstance()
    end
end

------------------------------------------------------------------ shared drivers
-- One driver frame per distinct condition, kept for reuse (there are at
-- most ten). Its attribute reports for every bar on it.
local function Changed(self, name, value)
    if name ~= ATTR then return end
    self.value = value
    local slots = self.slots
    for i = 1, #slots do
        local slot = slots[i]
        Visibility.state[slot] = value
        Paint(slot)
    end
end

local function Leave(slot)
    local bind = Visibility.expr[slot]
    Visibility.expr[slot] = nil
    local driver = Driven(bind) and Visibility.drivers[bind]
    if not driver then return end
    local slots = driver.slots
    for i = #slots, 1, -1 do
        if slots[i] == slot then
            tremove(slots, i)
        end
    end
    if slots[1] == nil then
        driver.value = nil
        UnregisterAttributeDriver(driver, ATTR)
    end
end

local function Join(slot, bind)
    Visibility.expr[slot] = bind
    if not Driven(bind) then return end
    local driver = Visibility.drivers[bind]
    if not driver then
        driver = S.CreateFrame("Frame")
        driver:Hide()
        driver.slots, driver.expr = {}, bind
        driver:SetScript("OnAttributeChanged", Changed)
        Visibility.drivers[bind] = driver
    end
    local slots = driver.slots
    slots[#slots + 1] = slot
    if slots[2] == nil then
        -- First bar on this condition: the manager resolves it at once. An
        -- attribute left from an earlier registration may not change, so
        -- the current value is read back.
        RegisterAttributeDriver(driver, ATTR, bind)
        local value = driver:GetAttribute(ATTR)
        driver.value = Public(value) and value or nil
    end
end

------------------------------------------------------------------ apply
-- Moves a bar to the source its rule names. Changes that register or
-- unregister a driver wait for combat to end; the bar keeps its old rule.
local function Bind(slot)
    local view = C.views[slot]
    local want = C.M.active and view and view.on and Visibility.Binding(view) or nil
    local have = Visibility.expr[slot]
    if have == want then
        Visibility.pending[slot] = nil
        return
    end
    if (Driven(have) or Driven(want)) and NS.IsCombatLocked() then
        Visibility.pending[slot] = true
        return
    end
    Visibility.pending[slot] = nil
    Leave(slot)
    if want then Join(slot, want) end
end

local function Settle(slot)
    local bind = Visibility.expr[slot]
    if bind == EVENTS then
        EventState(slot)
    elseif bind == HIDDEN then
        Visibility.state[slot] = "hide"
    elseif bind == nil then
        Visibility.state[slot] = nil
    else
        local driver = Visibility.drivers[bind]
        Visibility.state[slot] = driver and driver.value
    end
    C.Layout.Strata(slot)
    Paint(slot)
end

function Visibility.Apply(slot)
    Bind(slot)
    Configure(slot)
    Watch(false)
    Settle(slot)
end

-- Activation, preview switches and loading screens: the event flags are read
-- again, so a transition missed while nothing listened cannot stick.
function Visibility.ApplyAll()
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        Bind(slot)
        Configure(slot)
    end
    Watch(true)
    for i = 1, #SLOTS do Settle(SLOTS[i].key) end
end

-- Combat edges switch between the two opacities; drivers flip their own
-- [combat] state a frame later and repaint through the handler.
function Visibility.CombatChanged()
    for i = 1, #KEYS do Paint(KEYS[i]) end
end

-- PLAYER_REGEN_ENABLED: apply parked (un)registrations.
function Visibility.FlushPending()
    if NS.IsCombatLocked() or next(Visibility.pending) == nil then return end
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if Visibility.pending[slot] then Visibility.Apply(slot) end
    end
end

function Visibility.HasPending() return next(Visibility.pending) ~= nil end

-- Module off: every bar leaves its source; drivers registered in combat
-- wait for FlushPending (the module is inactive by then). Probes stop
-- listening and fades end at their target.
function Visibility.ReleaseAll()
    local locked = NS.IsCombatLocked()
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if locked and Driven(Visibility.expr[slot]) then
            Visibility.pending[slot] = true
        else
            Visibility.pending[slot] = nil
            Leave(slot)
            Visibility.state[slot] = nil
        end
        Calm(slot)
        fx[slot], world[slot] = nil, nil
        local bar = C.bars[slot]
        if bar then bar.hidden = nil end
    end
    Watch(false)
end

-- Diagnostics: registered driver entries.
function C.Diagnostics.DriverCount()
    local count = 0
    for _, driver in pairs(Visibility.drivers) do
        if driver.slots[1] ~= nil then count = count + 1 end
    end
    return count
end
