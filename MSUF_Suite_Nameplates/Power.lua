local _, private = ...
local NS = private.NS
local LOOK_BLIZZARD = private.Mode.LOOK_BLIZZARD
local Style = NS.NameplateStyle
local Power = {}
private.Power = Power

local owner
local visuals = setmetatable({}, { __mode = "k" })
local hooked, hookedDisplay

local function Requested()
    local config = owner and owner.config
    return owner and owner.active and config.look ~= LOOK_BLIZZARD
        and (config.personalPowerSkin or (config.personalPowerOffsetX or 0) ~= 0
            or (config.personalPowerOffsetY or 0) ~= 0)
end

local function Accessible(bar)
    return bar and not NS.Safety.IsForbidden(bar)
end

local function Paint(bar, force, x, y, size, color)
    if not Accessible(bar) then return end
    local visual = visuals[bar]
    if not visual and x == 0 and y == 0 and size == 0 then return end
    local oldX, oldY = visual and visual.offsetX or 0, visual and visual.offsetY or 0
    local move = oldX ~= x or oldY ~= y or force and (x ~= 0 or y ~= 0)
    local resize = (visual and visual.borderSize or 0) ~= size
        or size > 0 and visual.borderColor ~= color
    if not move and not resize then return end
    if NS.IsCombatLocked() then
        owner.needsRefresh = true
        return
    end
    if not visual then
        visual = {}
        visuals[bar] = visual
    end
    if resize then
        if not visual.edges then visual.edges = Style.CreateBorder(bar).edges end
        Style.PaintBorder(visual, bar, size, color)
    end
    if move then
        bar:SetPointsOffset(x, y)
        visual.offsetX, visual.offsetY = x, y
    end
end

local function PaintPower(bar, force, inheritOffset)
    local config = owner.config
    local x = not inheritOffset and config.personalPowerOffsetX or 0
    local y = not inheritOffset and config.personalPowerOffsetY or 0
    local size = config.personalPowerSkin and config.personalPowerBorderSize or 0
    Paint(bar, force, x, y, size, config.personalPowerBorderColor)
end

local function PaintDisplayAlternate(display, force)
    local hidden = display.hidePower
    if not NS.Public(hidden) then return end
    -- Both native clients attach the alternate bar to PowerBar when enabled.
    PaintPower(display.AlternatePowerBar, force, not hidden)
end

local function OnDisplayPowerAnchor(display)
    if Requested() and Accessible(display) then PaintPower(display.PowerBar, true) end
end

local function OnDisplayAlternateAnchor(display)
    if Requested() and Accessible(display) then PaintDisplayAlternate(display, true) end
end

local function RefreshDisplay(force)
    local display = PersonalResourceDisplayFrame
    if not Accessible(display) then return end
    if not hookedDisplay then
        hooksecurefunc(display, "UpdatePowerBarAnchor", OnDisplayPowerAnchor)
        hooksecurefunc(display, "UpdateAdditionalBarAnchors", OnDisplayAlternateAnchor)
        hookedDisplay = true
    end
    PaintPower(display.PowerBar, force)
    PaintDisplayAlternate(display, force)
end

-- Paints the personal power bars; force writes their offsets again.
local function Refresh(force)
    if not owner then return end
    if not Requested() then
        for bar in pairs(visuals) do Paint(bar, false, 0, 0, 0) end
        return
    end
    RefreshDisplay(force)
    local driver = NamePlateDriverFrame
    if not Accessible(driver) then return end
    if not hooked then
        hooksecurefunc(driver, "SetupClassNameplateBars", function()
            if Requested() then Power.Reapply() end
        end)
        hooked = true
    end
    local mana = driver:GetClassNameplateManaBar()
    local alternate = driver:GetClassNameplateAlternatePowerBar()
    PaintPower(mana, force)
    -- Blizzard anchors alternate power to mana when mana is shown. Moving
    -- both would apply the displacement twice to the alternate bar.
    local manaShown = Accessible(mana) and mana:IsShown()
    local altRoot = not mana or (NS.Public(manaShown) and manaShown == false)
    PaintPower(alternate, force, not altRoot)
end
Power.Refresh = Refresh

-- After Blizzard set the bars up again (SetupClassNameplateBars), or after
-- combat held back a paint: every offset is written again.
function Power.Reapply()
    Refresh(true)
end

function Power.Enable(module)
    owner = module
    Power.Refresh()
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

local function StopEnemyUpdates(bar)
    if not bar.enemyPowerListening then return end
    bar:UnregisterEvent(POWER_EVENT)
    bar.enemyPowerListening = nil
end

local function StartEnemyUpdates(bar)
    local unit = bar.enemyPowerUnit
    if not unit or bar.enemyPowerListening then return end
    bar.enemyPowerValue = nil
    Enemy.SetValue(bar, UnitPower(unit))
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
end

local function OnEnemyPowerChanged(bar, _, unit, token)
    if not bar.enemyPowerListening or not NS.Public(unit) or unit ~= bar.enemyPowerUnit then return end
    local displayed = bar.enemyPowerToken
    if displayed and NS.Public(token) and token ~= displayed then return end
    Enemy.SetValue(bar, UnitPower(unit), bar.enemyPowerSmooth)
end

local function ReleaseEnemyBar(bar)
    if not bar or not bar.enemyPowerUnit then return end
    StopEnemyUpdates(bar)
    bar.enemyPowerUnit, bar.enemyPowerMaximum = nil, nil
    bar.enemyPowerValue = nil
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

local function PublicAnchor(frame)
    if not Accessible(frame) then return false end
    local protected = frame:IsProtected()
    if not NS.Public(protected) or protected ~= false then return false end
    local restricted = frame:IsAnchoringRestricted()
    return NS.Public(restricted) and restricted == false
end

local function CanAttach(uf, health, bottom, bar)
    return PublicAnchor(uf) and PublicAnchor(health) and PublicAnchor(bottom) and (not bar or PublicAnchor(bar))
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

local function ReadEnemyToken(unit)
    local _, token = UnitPowerType(unit)
    if NS.Public(token) and type(token) == "string" then return token end
end

local function SetEnemyMaximum(bar, maxPower)
    if not NS.Public(maxPower) then
        bar.enemyPowerMaximum = nil
        bar:SetMinMaxValues(0, maxPower)
    elseif bar.enemyPowerMaximum ~= maxPower then
        bar.enemyPowerMaximum = maxPower
        bar:SetMinMaxValues(0, maxPower)
    end
end

local function RefreshEnemyResource(state, health, unit)
    if state.unit ~= unit then ReleaseEnemyBar(state.bar) end
    local maxPower = UnitPowerMax(unit)
    state.unit = unit
    if NS.Public(maxPower) and (type(maxPower) ~= "number" or maxPower <= 0) then
        ReleaseEnemyBar(state.bar)
        return
    end
    local bar = state.bar
    if not bar then
        bar = CreateEnemyBar(health)
        state.bar = bar
    end
    bar.enemyPowerToken = ReadEnemyToken(unit)
    SetEnemyMaximum(bar, maxPower)
    return bar
end

function Power.ApplyEnemy(uf, health, prefix, unit, refreshResource)
    local state = enemyBars[uf]
    if prefix ~= "enemy" or not unit then
        if state and state.unit then Power.RestoreEnemy(uf) end
        return
    end
    local plan = enemyPlan
    if state and state.unit == unit and state.plan == plan and not refreshResource then return end
    local bottom = uf.CastBarsContainer
    local bar = state and state.bar
    if not CanAttach(uf, health, bottom, bar) then
        Power.RestoreEnemy(uf)
        if NS.InCombat() then owner.pendingPlates[uf] = true end
        return
    end
    if not state then
        state = {}
        enemyBars[uf] = state
    end
    local refresh = refreshResource or state.unit ~= unit
    if refresh then bar = RefreshEnemyResource(state, health, unit) end
    state.plan = plan
    if not bar or not refresh and not bar.enemyPowerUnit then return end
    local previous = bar.enemyPowerPlan
    if not previous or previous.width ~= plan.width or previous.x ~= plan.x or previous.y ~= plan.y then
        Enemy.Place(bar, health, bottom, plan)
    end
    local wasSmooth = bar.enemyPowerSmooth
    PaintEnemyBar(bar, plan)
    if not bar.enemyPowerUnit then
        bar.enemyPowerUnit = unit
        if bar.enemyPowerVisible then StartEnemyUpdates(bar) end
        bar:SetAlpha(1)
    elseif bar.enemyPowerListening and (refresh or wasSmooth and not bar.enemyPowerSmooth) then
        Enemy.SetValue(bar, UnitPower(unit))
    end
end

function Power.EnemyResourceChanged(uf, unit)
    local container = uf.HealthBarsContainer
    Power.ApplyEnemy(uf, container and container.healthBar, private.PlatePrefix(uf), unit, true)
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
    local plan = Enemy.Plan(owner.config, enemyPlan)
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
    for bar in pairs(visuals) do Paint(bar, false, 0, 0, 0) end
    owner = nil
end
