local _, private = ...
local NS = private.NS
local Draw = NS.NameplateStyle.Decor
local Decor = {}
private.Decor = Decor
local module, plans, targetState
local states = setmetatable({}, { __mode = "k" })
local byCast = setmetatable({}, { __mode = "k" })

local function Safe(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local function Blocked(uf, health)
    return NS.IsCombatLocked() and (uf:IsProtected() or health:IsProtected())
end

local function CastShown(cast)
    if not Safe(cast) then return false end
    local shown = cast:IsShown()
    return NS.Public(shown) and shown == true
end

local function Identity(unit, other)
    local same = unit and UnitIsUnit(unit, other)
    return NS.Public(same) and same == true
end

local function CastVisibility(cast)
    local state = byCast[cast]
    if not state or not module.active or not state.plan then return end
    local p = state.plan
    if not p.outer then return end
    if Blocked(state.parent, state.health) then
        module.pendingPlates[state.parent] = true
        return
    end
    Draw.Paint(state, p, state.target, state.focus, CastShown(cast))
end

function Decor.Configure(owner)
    module = owner
    local c = owner.config
    plans = { enemy = Draw.Plan(c, "enemy"), friendly = Draw.Plan(c, "friendly") }
    Decor.inUse = plans.enemy.active or plans.friendly.active
    if not Decor.inUse then Decor.Disable() end
end

function Decor.Paint(uf, health, cast, prefix, unit)
    local p = plans and plans[prefix]
    local state = states[health]
    if not p or not p.active then
        Draw.Hide(state)
        if state then state.plan = nil end
        return
    end
    if not Safe(uf) or not Safe(health) then return end
    if Blocked(uf, health) then
        module.pendingPlates[uf] = true
        return
    end
    if not state then
        state = { parent = uf, health = health }
        states[health] = state
    end
    state.cast = Safe(cast) and cast or nil
    if state.cast and p.outer and not byCast[cast] then
        byCast[cast] = state
        cast:HookScript("OnShow", CastVisibility)
        cast:HookScript("OnHide", CastVisibility)
    end
    state.plan = p
    state.target = p.glow == 3 and Identity(unit, "target") or false
    state.focus = (p.focus or p.glow == 4) and Identity(unit, "focus") or false
    state.separate = module.pendingPlates[uf] ~= nil
    state.unit = unit
    if state.target then targetState = state end
    Draw.Paint(state, p, state.target, state.focus, CastShown(state.cast))
end

function Decor.TargetChanged(uf)
    local old = targetState
    local health = Safe(uf) and uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar
    local current = health and states[health]
    targetState = current
    if old and old ~= current and old.plan and Safe(old.health) then
        if Blocked(old.parent, old.health) then
            module.pendingPlates[old.parent] = true
            return
        end
        old.target = false
        Draw.Paint(old, old.plan, false, old.focus, CastShown(old.cast))
    end
end

function Decor.Restore(health)
    local state = states[health]
    Draw.Hide(state)
    if state then state.plan = nil end
    if targetState == state then targetState = nil end
end

function Decor.Disable()
    for _, state in pairs(states) do
        Draw.Hide(state)
        state.plan = nil
    end
    targetState = nil
    Decor.inUse = false
end
