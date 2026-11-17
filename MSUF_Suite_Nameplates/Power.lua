local _, private = ...
local NS = private.NS
local LOOK_BLIZZARD = private.Mode.LOOK_BLIZZARD
local Style = NS.NameplateStyle
local Power = {}
private.Power = Power

local owner
local function Accessible(bar)
    return bar and not NS.Safety.IsForbidden(bar)
end

function Power.Enable(module)
    owner = module
end

-- Enemy power is a separate, owned row. It shares the native health bar's
-- visibility and anchors to the space Blizzard already reserves for casts.
local Enemy = Style.EnemyPower
local enemyBars = setmetatable({}, { __mode = "k" })
local enemyPlan
local MAX_POWER_EVENT = "UNIT_MAXPOWER"
local POWER_EVENT = "UNIT_POWER_UPDATE"
local ENEMY_POWER_EVENTS = { inCombat = true }
local extraTextEvents
local enemyTextRevision = 0

local function WritePowerText(bar, unit, value)
    local label = bar.enemyPowerText
    local max, percent, format = Enemy.TextValue(bar.enemyPowerTextMode)
    if percent then
        label:SetFormattedText(format, UnitPowerPercent(unit, bar.enemyPowerType, false, CurveConstants.ScaleTo100))
    elseif max then
        local maximum = bar.enemyPowerMaximum
        if maximum == nil then maximum = UnitPowerMax(unit, bar.enemyPowerType) end
        label:SetFormattedText(format, value, maximum)
    else
        label:SetFormattedText(format, value)
    end
end

local function WriteEnemyPower(bar, unit, interpolation)
    local value = UnitPower(unit, bar.enemyPowerType)
    if bar.enemyPowerChunked then
        if interpolation then Enemy.SnapshotLoss(bar, value) else Enemy.StopLoss(bar) end
        interpolation = nil
    end
    Enemy.SetValue(bar, value, interpolation)
    if bar.enemyPowerTextMode then WritePowerText(bar, unit, value) end
end

local function StopEnemyUpdates(bar)
    if not bar.enemyPowerListening then return end
    bar:UnregisterEvent(POWER_EVENT)
    bar.enemyPowerListening = nil
end

local function StartEnemyUpdates(bar)
    local unit = bar.enemyPowerUnit
    if not unit or bar.enemyPowerListening then return end
    bar.enemyPowerValue = nil
    WriteEnemyPower(bar, unit)
    bar:RegisterUnitEvent(POWER_EVENT, unit)
    bar.enemyPowerListening = true
end

local function OnEnemyPowerShown(bar)
    bar.enemyPowerVisible = true
    StartEnemyUpdates(bar)
end

local function OnEnemyPowerHidden(bar)
    bar.enemyPowerVisible = nil
    StopEnemyUpdates(bar)
    if bar.enemyPowerLoss then Enemy.StopLoss(bar) end
end

local function OnEnemyPowerChanged(bar, _, unit, token)
    if not bar.enemyPowerListening or not NS.Public(unit) or unit ~= bar.enemyPowerUnit then return end
    local displayed = bar.enemyPowerToken
    if displayed and NS.Public(token) and token ~= displayed then return end
    WriteEnemyPower(bar, unit, bar.enemyPowerSmooth or bar.enemyPowerChunked)
end

local function ReleaseEnemyBar(bar)
    if not bar or not bar.enemyPowerUnit then return end
    StopEnemyUpdates(bar)
    bar.enemyPowerUnit, bar.enemyPowerMaximum = nil, nil
    bar.enemyPowerValue = nil
    if bar.enemyPowerLoss then Enemy.StopLoss(bar) end
    if bar.powerGradient then Style.Gradient.SetAlpha(bar.powerGradient, 1) end
    -- An alpha write can retire the owned row even if the anchor later
    -- becomes protected. The next occupant seeds a fresh, immediate value.
    bar:SetAlpha(0)
end

function Power.RestoreEnemy(uf)
    local state = enemyBars[uf]
    if not state then return end
    ReleaseEnemyBar(state.bar)
    state.unit, state.plan = nil, nil
end

local function AnchorAllowed(frame, combat)
    if not Accessible(frame) then return false end
    local protected = frame:IsProtected()
    if not NS.Public(protected) or combat and protected then return false end
    local restricted = frame:IsAnchoringRestricted()
    return NS.Public(restricted) and type(restricted) == "boolean"
end

-- The bar is a child of health. Both reference regions are under the same
-- native unit frame, so their anchor-family restriction does not prohibit
-- an anchor within that family. A bound row can refresh its resource in
-- combat without changing any protected geometry.
local function CanAttach(uf, health, bottom, bar, combat)
    return AnchorAllowed(uf, combat) and AnchorAllowed(health, combat) and AnchorAllowed(bottom, combat)
        and (not bar or AnchorAllowed(bar, combat))
end

local function CreateEnemyBar(health)
    local bar = Enemy.Create(health)
    bar:SetAlpha(0)
    bar:SetScript("OnShow", OnEnemyPowerShown)
    bar:SetScript("OnHide", OnEnemyPowerHidden)
    bar:SetScript("OnEvent", OnEnemyPowerChanged)
    bar:Show()
    return bar
end

local function PaintEnemyBar(bar, plan)
    local color = plan.byType and PowerBarColor[bar.enemyPowerToken]
    if color then
        Enemy.Paint(bar, plan, color.r, color.g, color.b)
    else
        Enemy.Paint(bar, plan)
    end
    bar.enemyPowerSmooth = plan.interpolation
end

local function SetEnemyMaximum(bar, maxPower)
    if not NS.Public(maxPower) then
        bar.enemyPowerMaximum = nil
        bar:SetMinMaxValues(0, maxPower)
        if bar.enemyPowerLoss then Enemy.LossRange(bar, maxPower) end
    elseif bar.enemyPowerMaximum ~= maxPower then
        bar.enemyPowerMaximum = maxPower
        bar:SetMinMaxValues(0, maxPower)
        if bar.enemyPowerLoss then Enemy.LossRange(bar, maxPower) end
    end
end

local function RefreshEnemyResource(state, health, unit, source)
    if state.unit ~= unit or state.source ~= source then ReleaseEnemyBar(state.bar) end
    local powerType, token = Enemy.Resource(source)
    local maxPower = UnitPowerMax(unit, powerType)
    state.unit, state.source = unit, source
    if NS.Public(maxPower) and (type(maxPower) ~= "number" or maxPower <= 0) then
        ReleaseEnemyBar(state.bar)
        return
    end
    local displayedType = powerType
    if displayedType == nil then
        displayedType, token = UnitPowerType(unit)
        if not NS.Public(token) or type(token) ~= "string" then token = nil end
    end
    if UnitHasPowerType and NS.Public(displayedType) and type(displayedType) == "number" then
        local hasPower = UnitHasPowerType(unit, displayedType)
        if NS.Public(hasPower) and hasPower == false then
            ReleaseEnemyBar(state.bar)
            return
        end
    end
    local bar = state.bar
    if not bar then
        bar = CreateEnemyBar(health)
        state.bar = bar
    end
    bar.enemyPowerType = powerType
    bar.enemyPowerToken = token
    SetEnemyMaximum(bar, maxPower)
    return bar, maxPower
end

function Power.ApplyEnemy(uf, health, prefix, unit, refreshResource)
    local state = enemyBars[uf]
    if prefix ~= "enemy" or not unit then
        if state and state.unit then Power.RestoreEnemy(uf) end
        return
    end
    local plan, c = enemyPlan, owner.config
    if state and state.unit == unit and state.plan == plan and state.textRevision == enemyTextRevision and not refreshResource then return end
    local bottom = uf.CastBarsContainer
    local bar = state and state.bar
    local previous = bar and bar.enemyPowerPlan
    local move = Enemy.GeometryChanged(previous, plan)
    local combat = NS.InCombat()
    local layoutLocked = combat and (move or Enemy.Height(previous) ~= Enemy.Height(plan) or previous.border ~= plan.border)
    if not CanAttach(uf, health, bottom, bar, layoutLocked) then
        Power.RestoreEnemy(uf)
        if combat then owner.pendingPlates[uf] = true end
        return
    end
    if not state then
        state = {}
        enemyBars[uf] = state
    end
    local refresh = refreshResource or state.unit ~= unit or state.source ~= plan.source
    local maximum
    if refresh then bar, maximum = RefreshEnemyResource(state, health, unit, plan.source) end
    state.plan = plan
    if not bar or not refresh and not bar.enemyPowerUnit then return end
    if move then Enemy.Place(bar, health, bottom, plan) end
    local wasSmooth = bar.enemyPowerSmooth
    PaintEnemyBar(bar, plan)
    if plan.chunked or bar.enemyPowerLoss then
        if plan.chunked and not bar.enemyPowerLoss and combat and not AnchorAllowed(bar, true) then
            state.plan = nil
            owner.pendingPlates[uf] = true
        else
            if not refresh and plan.chunked and not bar.enemyPowerLoss then
                maximum = bar.enemyPowerMaximum or UnitPowerMax(unit, bar.enemyPowerType)
            end
            Enemy.PaintLoss(bar, plan, maximum)
            bar.enemyPowerChunked = plan.chunked
        end
    end
    local changedText = state.textRevision ~= enemyTextRevision
    if changedText and combat and c.enemyPowerTextVisible and not AnchorAllowed(bar, true) then
        owner.pendingPlates[uf] = true
        changedText = false
    end
    if changedText then
        state.textRevision = enemyTextRevision
        local font = c.enemyPowerTextVisible and NS.GlobalFontPath()
        local label = Enemy.PaintText(bar, c, font)
        bar.enemyPowerTextMode = label and (c.enemyPowerTextMode or 1) or nil
    end
    if not bar.enemyPowerUnit then
        bar.enemyPowerUnit = unit
        if bar.enemyPowerVisible then StartEnemyUpdates(bar) end
        bar:SetAlpha(1)
    elseif bar.enemyPowerListening and (refresh or changedText or wasSmooth and not bar.enemyPowerSmooth) then
        WriteEnemyPower(bar, unit)
    end
end

function Power.EnemyBar(uf)
    local state = enemyBars[uf]
    local bar = state and state.bar
    if bar and bar.enemyPowerUnit then return bar end
end

function Power.TextRegion(uf)
    local state = enemyBars[uf]
    local bar = state and state.bar
    if bar and bar.enemyPowerUnit and bar.enemyPowerTextMode then return bar.enemyPowerText end
end

function Power.EnemyResourceChanged(uf, unit)
    local container = uf.HealthBarsContainer
    Power.ApplyEnemy(uf, container and container.healthBar, private.PlatePrefix(uf), unit, true)
    if private.Extensions and private.Extensions.inUse then private.Extensions.RepaintLayers(uf) end
end

local function OnEnemyMaximumChanged(module, event, unit)
    if not NS.Public(unit) then return end
    if Power.enemyEnabled then
        local uf = module.activeUnits[unit]
        if Accessible(uf) then NS.Dispatch(Power.EnemyResourceChanged, uf, unit) end
    end
    if extraTextEvents then private.Extensions.OnUnit(module, event, unit) end
end

function Power.SetExtraTextEvents(wanted)
    extraTextEvents = wanted == true
    if not owner then return end
    if extraTextEvents or Power.enemyEnabled then
        owner.context:Event(MAX_POWER_EVENT, OnEnemyMaximumChanged, ENEMY_POWER_EVENTS, private.Suite.NameplateUnits)
    else
        owner.context:RemoveEvent(MAX_POWER_EVENT)
    end
end

local function DisableEnemy()
    if not Power.enemyEnabled then return end
    Power.enemyEnabled = false
    enemyPlan = nil
    Power.SetExtraTextEvents(extraTextEvents)
    for uf in pairs(enemyBars) do Power.RestoreEnemy(uf) end
end

function Power.ConfigureEnemy()
    if not owner then return end
    if owner.config.enemyPowerTextVisible == true or enemyTextRevision ~= 0 then enemyTextRevision = enemyTextRevision + 1 end
    local plan = Enemy.Plan(owner.barSettings or owner.config, enemyPlan)
    if not plan.enabled then
        DisableEnemy()
        return
    end
    enemyPlan = plan
    if not Power.enemyEnabled then
        Power.enemyEnabled = true
        Power.SetExtraTextEvents(extraTextEvents)
    end
end

function Power.Disable()
    if not owner then return end
    DisableEnemy()
    owner = nil
end
