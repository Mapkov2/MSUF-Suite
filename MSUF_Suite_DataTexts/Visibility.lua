local _, P = ...
local NS, S = P.NS, P.Suite
local Finite = S.Finite
local VISIBILITY = NS.DataTextVisibility
-- When a DataTexts bar shows (DataTexts.lua owns the bars). The visibility
-- mode, the load conditions and the Edit Mode reveal run as state drivers, so
-- combat itself needs no handler; zone and housing events re-evaluate the
-- conditions the client cannot (instance, housing). An injured-only bar fades
-- through a health curve and lets the pointer through at full health.
local Visibility = {}
P.DataTextBarVisibility = Visibility
local ID = "dataTexts"
local healthCurve

local function Clear(t)
    for key in pairs(t) do t[key] = nil end
end

local function InInstance()
    local inside = IsInInstance()
    return inside == true or inside == 1
end

local function InHousing()
    return C_Housing.IsInsideHouseOrPlot() == true
end

------------------------------------------------------------------ health gate
-- Full health maps to 0 (hidden), anything less to 1 (shown). Retail and
-- WoW Forever both have UnitHealthPercent with curve support.
local function HealthCurve()
    if not healthCurve then
        healthCurve = C_CurveUtil.CreateCurve()
        healthCurve:SetType(Enum.LuaCurveType.Step)
        healthCurve:AddPoint(0, 1)
        healthCurve:AddPoint(1, 0)
    end
    return healthCurve
end

-- Whether a bar and its places take the pointer. An invisible bar must not
-- catch clicks, tooltips or the wheel; only audio places take the wheel.
local function SetBarMouse(bar, enabled)
    if bar.mouseEnabled == enabled then return end
    bar.mouseEnabled = enabled
    bar.frame:EnableMouse(enabled)
    bar.badge:EnableMouse(enabled)
    for i = 1, #bar.slots do
        local button = bar.slots[i]
        button:EnableMouse(enabled)
        button:EnableMouseWheel(enabled and button.extra ~= nil and button.extra.kind == "audio")
    end
end

-- The bars shown only below full health, listed by Visibility.Apply (none
-- in Edit Mode): player health events repaint these alone.
local healthBars = {}

local function GateHealth(bar)
    -- Health can be secret. The curve result goes straight into SetAlpha
    -- without Lua comparison, arithmetic or string conversion.
    local alpha = UnitHealthPercent("player", false, HealthCurve())
    bar.visual:SetAlpha(alpha)
    -- At full health (alpha 0) the bar lets the pointer through. A secret
    -- reading cannot be compared: the bar keeps taking the pointer then.
    SetBarMouse(bar, not Finite(alpha) or alpha > 0)
end

local function RefreshHealthAlpha(config, bar)
    if not bar or not bar.visual then return end
    if S.editMode or not config[bar.injuredKey] then
        bar.visual:SetAlpha(1)
        SetBarMouse(bar, true)
        return
    end
    healthBars[#healthBars + 1] = bar
    GateHealth(bar)
end

-- The player's health events repaint these bars (DataTexts.lua's event path
-- walks the list itself, so a health event costs no extra call).
Visibility.healthBars, Visibility.GateHealthBar = healthBars, GateHealth

function Visibility.Release()
    Clear(healthBars)
end

------------------------------------------------------------------ state drivers
-- "Out of combat" and "In combat" are state drivers as well: the client
-- decides combat, and PLAYER_REGEN_DISABLED fires before lockdown starts.
local function MacroVisibility(c, bar)
    local rules, n = {}, 0
    local injured = c[bar.injuredKey] == true
    for _, condition in ipairs(NS.DataTextLoadConditions) do
        local suffix, macro = condition[1], condition[3]
        if macro and c[bar.prefix .. "LoadCond" .. suffix] == true
            and not (injured and (suffix == "HideNoTarget" or suffix == "HideOutOfCombat"
                or suffix == "HideOutOfCombatNoTarget")) then
            n = n + 1
            rules[n] = macro
        end
    end
    local mode = c[bar.visibilityKey]
    if n == 0 and mode ~= VISIBILITY.OUT_OF_COMBAT and mode ~= VISIBILITY.IN_COMBAT then return nil end
    if mode == VISIBILITY.OUT_OF_COMBAT then
        table.insert(rules, 1, "[combat] hide")
    elseif mode == VISIBILITY.IN_COMBAT then
        table.insert(rules, 1, "[nocombat] hide")
    end
    rules[#rules + 1] = "show"
    return table.concat(rules, "; ")
end

-- Visibility macros depend on settings only: they are built when a bar is
-- refreshed, and Visibility.Apply (zone and housing events) reads the cached
-- strings. Edit Mode reveals bars out of combat.
local EDIT_PREFIX = "[nocombat] show; "
local BLOCKED, BLOCKED_EDIT = "hide", EDIT_PREFIX .. "hide"
function Visibility.Cache(c, bar)
    local expression = MacroVisibility(c, bar)
    bar.visibilityMacro = expression
    bar.visibilityEditMacro = expression and EDIT_PREFIX .. expression
end

-- Returns false when combat keeps the driver for after combat (queued).
local function SetDriver(bar, expression)
    if bar.visibilityDriver == expression then return true end
    if NS.IsCombatLocked() then
        S.Queue(ID)
        return false
    end
    if bar.visibilityDriver then UnregisterStateDriver(bar.frame, "visibility") end
    bar.visibilityDriver = nil
    if expression then
        RegisterStateDriver(bar.frame, "visibility", expression)
        bar.visibilityDriver = expression
    end
    return true
end
Visibility.SetDriver = SetDriver

-- Shows, hides and fades every bar of the module for its settings, the
-- current zone and Edit Mode; the caller rebinds the sources afterwards.
function Visibility.Apply(module)
    local c = module.config
    module.styling = true
    Clear(healthBars)
    for i, bar in pairs(module.bars) do
        local mode = c[bar.visibilityKey]
        if mode ~= VISIBILITY.MOUSEOVER then bar.hover = false end
        local enabled = module.presentIDs[i] and c[bar.enabledKey] == true
        local blocked = enabled and (c[bar.instanceKey] and InInstance()
            or c[bar.housingKey] and InHousing())
        local expression
        if enabled then
            expression = S.editMode and bar.visibilityEditMacro or bar.visibilityMacro
            if expression and blocked then expression = S.editMode and BLOCKED_EDIT or BLOCKED end
        end
        if SetDriver(bar, expression) and not expression then
            bar.frame:SetShown(enabled and (S.editMode or not blocked))
        end
        bar.frame:SetAlpha((S.editMode or mode ~= VISIBILITY.MOUSEOVER or bar.hover) and 1 or 0)
        RefreshHealthAlpha(c, bar)
    end
    module.styling = false
end
