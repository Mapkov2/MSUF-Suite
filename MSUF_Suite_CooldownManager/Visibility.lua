local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- Bar visibility. The effect is bar alpha and mouse: bar frames stay shown,
-- so attached bars keep their place and MSUF's anchor stays usable. A rule
-- binds a bar to one of three sources:
--  * "Always" (without the mount rule) follows a few rare events for pet
--    battles, vehicles and override bars. It needs no state driver, so the
--    default setup registers none.
--  * "Hidden" is static.
--  * Every other rule is one macro condition. Bars with the same condition
--    share one plain driver frame whose attribute Blizzard's state driver
--    manager keeps current; combat, target and mount changes run Lua only
--    on transitions.
-- Addon frames cannot join Blizzard's "cooldownViewers" roleset, hence the
-- explicit pet battle rule. Only driver (un)registration touches secure
-- code: combat parks it until PLAYER_REGEN_ENABLED.
local Visibility = { pending = {}, drivers = {}, state = {}, expr = {} }
C.Visibility = Visibility
local SLOTS = NS.CDM.SLOTS
local Public = S.Public
local tremove = table.remove
local ATTR = "msufvis"
-- The "Show" choice: Always, In combat, In combat or with a target, Hidden.
local VIS = C.Const.VIS
local VIS_HIDDEN = VIS.HIDDEN
-- Bindings without a driver.
local EVENTS, HIDDEN = "events", "hide"
Visibility.EVENTS, Visibility.HIDDEN = EVENTS, HIDDEN

-- Driver strings per (vis, hideMounted, hideVehicle), built once.
local BODY = {
    [VIS.ALWAYS] = "show",
    [VIS.COMBAT] = "[combat] show; hide",
    [VIS.COMBAT_OR_TARGET] = "[combat][@target,exists] show; hide",
}
local EXPR = {}
for _, vis in ipairs({ VIS.ALWAYS, VIS.COMBAT, VIS.COMBAT_OR_TARGET, VIS.HIDDEN }) do
    EXPR[vis] = {}
    for mounted = 0, 1 do
        EXPR[vis][mounted] = {}
        for vehicle = 0, 1 do
            EXPR[vis][mounted][vehicle] = vis == VIS.HIDDEN and "hide" or "[petbattle] hide; "
                .. (vehicle == 1 and "[vehicleui][overridebar] hide; " or "")
                .. (mounted == 1 and "[mounted] hide; " or "") .. BODY[vis]
        end
    end
end
function Visibility.Expression(view)
    local vis = view.vis
    if vis ~= VIS.COMBAT and vis ~= VIS.COMBAT_OR_TARGET and vis ~= VIS.HIDDEN then vis = VIS.ALWAYS end
    return EXPR[vis][view.hideMounted and 1 or 0][view.hideVehicle and 1 or 0]
end

-- What a bar's rule binds to: EVENTS, HIDDEN or a driver expression.
function Visibility.Binding(view)
    local vis = view.vis
    if vis == VIS.HIDDEN then return HIDDEN end
    if vis ~= VIS.COMBAT and vis ~= VIS.COMBAT_OR_TARGET and not view.hideMounted then return EVENTS end
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

-- Preview (Edit Mode, options page) suspends the rules: plain bar opacity.
-- Out of combat the bar uses its out-of-combat opacity. Until its source
-- has reported, only "Hidden" hides. bar.hidden: nothing of the bar can be
-- seen (its rule hides it or its opacity is 0); the icon layer reads it
-- for tooltips and mouse.
local function Paint(slot)
    local bar, view = C.bars[slot], C.views[slot]
    if not bar or not view then return end
    local state = C.state
    local hidden, percent
    if state.preview then
        hidden, percent = false, view.alpha
    else
        local value = Visibility.state[slot]
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
    local wasHidden = bar.hidden
    if wasHidden ~= hidden then
        bar.hidden = hidden
        Mouse(slot, not hidden)
        if C.M.active and wasHidden == true and not hidden then
            -- Usability was not sampled while this bar was invisible.
            local list = C.Index.usable
            for i = 1, #list do
                local entry = list[i]
                if entry.slot == slot and entry.icon then C.Effects.Usable(entry) end
            end
        end
    end
    if bar.alpha ~= alpha then
        bar.alpha = alpha
        bar.frame:SetAlpha(alpha)
    end
end
Visibility.Paint = Paint

------------------------------------------------------------------ "Always": events
local petBattle, vehicle = false, false
local listener, listening, listeningVehicle = nil, false, false
local PET_EVENTS = { "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE" }
local VEHICLE_EVENTS = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR" }
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

local function EventState(slot)
    local view = C.views[slot]
    Visibility.state[slot] = (petBattle or (vehicle and view and view.hideVehicle)) and "hide" or "show"
end

local function OnEvent(_, event, unit)
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
-- only while one of them hides in vehicles). refresh re-reads the flags.
local function Watch(refresh)
    local any, veh = false, false
    for i = 1, #SLOTS do
        local slot = SLOTS[i].key
        if Visibility.expr[slot] == EVENTS then
            any = true
            local view = C.views[slot]
            if view and view.hideVehicle then veh = true end
        end
    end
    if any and not listener then
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
    if refresh then
        petBattle = listening and InPetBattle()
        vehicle = listeningVehicle and InVehicle()
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
    Watch(false)
    Settle(slot)
end

-- Activation, preview switches and loading screens: the event flags are read
-- again, so a transition missed while nothing listened cannot stick.
function Visibility.ApplyAll()
    for i = 1, #SLOTS do Bind(SLOTS[i].key) end
    Watch(true)
    for i = 1, #SLOTS do Settle(SLOTS[i].key) end
end

-- Combat edges switch between the two opacities; drivers flip their own
-- [combat] state a frame later and repaint through the handler.
function Visibility.CombatChanged()
    for i = 1, #SLOTS do Paint(SLOTS[i].key) end
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
-- wait for FlushPending (the module is inactive by then).
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
        local bar = C.bars[slot]
        if bar then bar.hidden = nil end
    end
    Watch(false)
end

-- Test and diagnostics hook: registered driver entries.
function Visibility.DriverCount()
    local count = 0
    for _, driver in pairs(Visibility.drivers) do
        if driver.slots[1] ~= nil then count = count + 1 end
    end
    return count
end
