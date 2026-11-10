local _, P = ...
local NS, S = P.NS, P.Suite
local X, L, T, E, R = NS.NameplateExtensions, P.ExtensionLayout, P.ExtensionText, P.ExtensionEffects, P.ExtensionResources
local Extensions = { inUse = false }
P.Extensions = Extensions
local M, plan, context, hasFocus, targetState
local states, restores = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local castStates = setmetatable({}, { __mode = "k" })
local subscribed = {}
local rangeCount, registeredSpell = 0, nil
local restoreFrame, hooked, metadataJob
local IN_COMBAT, RANGE_OWNER = { inCombat = true }, "MSUF_Suite_NameplateExtensions"
local RangeTick, ExpireInterrupts

local function Safe(region)
    return not NS.IsSecret(region) and region and not NS.Safety.IsForbidden(region)
end

local function PublicUnit(unit)
    return not NS.IsSecret(unit) and type(unit) == "string"
end

local function Same(unit, other)
    local same = UnitIsUnit(unit, other)
    return not NS.IsSecret(same) and same == true
end

local function FocusPresent()
    local exists = UnitExists("focus")
    if NS.IsSecret(exists) then return nil end
    if exists ~= true then return false end
    local hostile = UnitCanAttack("player", "focus")
    if NS.IsSecret(hostile) then return nil end
    return hostile == true
end

local function ReadContext()
    context, hasFocus = nil, nil
    if not plan.enabled then return end
    if plan.contextEnabled then local _, instanceType = IsInInstance() context = X.Context(instanceType) end
    if plan.focusReminder then hasFocus = FocusPresent() else hasFocus = nil end
end

local function RangeSubscription()
    local spell = rangeCount > 0 and plan and plan.rangeSpell > 0 and plan.rangeSpell or nil
    if spell ~= registeredSpell then
        if registeredSpell then S.SetNativeSpellRange(RANGE_OWNER, registeredSpell, false) end
        registeredSpell = spell
        if spell then S.SetNativeSpellRange(RANGE_OWNER, spell, true) end
    end
    if spell then M.context:Ticker(.25, RangeTick) else M.context:Cancel(RangeTick) end
end

local function RangeActive(state, active)
    active = active == true
    if active == (state.rangeActive == true) then return end
    state.rangeActive = active
    rangeCount = rangeCount + (active and 1 or -1)
    RangeSubscription()
end

local function ReadRange(state)
    if plan.rangeSpell > 0 then
        local value = C_Spell.IsSpellInRange(plan.rangeSpell, state.unit)
        return X.Range(value), value
    end
    return 3
end

local function Relevant(state)
    if not plan.focusReminder or state.kind ~= "enemyNpc" then return false end
    local facts = M.facts and M.facts[state.health]
    local kind = facts and facts.kind
    if not kind then
        local classification = UnitClassification(state.unit)
        if NS.IsSecret(classification) then return false end
        kind = P.Roles.Classify(state.unit, classification)
    end
    return kind == "Caster" or kind == "Miniboss"
end

local function Presentation(state)
    local wasVisible = state.visible
    local visible, opacity, scale = X.Visibility(plan, state.kind, context, state.casting)
    local clickable = L.HitTest(state, not visible)
    if not clickable then visible = state.visible ~= false end
    state.visible = visible
    local range = state.range or 3
    local rangeValue
    if plan.range and state.prefix == "enemy" then rangeValue = state.rangeValue end
    if plan.range and state.prefix == "enemy" and not NS.IsSecret(rangeValue) then
        opacity = opacity * (range == 2 and plan.rangeAlpha or range == 3 and plan.rangeUnknownAlpha or 1)
    end
    if state.focus then scale = scale * plan.focusScale end
    if state.casting then scale = scale * plan.castScale end
    L.Alpha(state, visible and opacity or 0, rangeValue, plan.rangeAlpha)
    L.Scale(state, scale)
    L.Name(state)
    if L.Mutable(state, state.uf) then
        E.Reminder(state, plan.focusReminder and hasFocus == false
            and (state.relevant or state.casting == true and state.kind == "enemyNpc"))
        E.Range(state)
        if wasVisible ~= nil and wasVisible ~= visible then E.Execute(state) end
    end
    RangeActive(state, visible and plan.range and plan.rangeSpell > 0 and state.prefix == "enemy")
end

RangeTick = function()
    if not M.active or not plan.range then return end
    for _, state in pairs(states) do
        if state.rangeActive and state.unit and state ~= targetState and Safe(state.uf) then
            local range, value = ReadRange(state)
            if range ~= state.range or NS.IsSecret(value) or NS.IsSecret(state.rangeValue) then
                state.range, state.rangeValue = range, value
                Presentation(state)
            end
        end
    end
end

local function ArmInterrupts()
    local earliest
    for _, state in pairs(states) do
        local at = state.interruptUntil
        if at and (not earliest or at < earliest) then earliest = at end
    end
    if earliest then
        M.context:After(math.max(0, earliest - GetTime()), ExpireInterrupts)
    else
        M.context:Cancel(ExpireInterrupts)
    end
end

ExpireInterrupts = function()
    local now = GetTime()
    for _, state in pairs(states) do
        if state.interruptUntil and state.interruptUntil <= now then
            if L.Mutable(state, state.uf) then
                E.EndInterrupt(state)
            else
                state.interruptUntil, state.interruptExpired = nil, true
            end
        end
    end
    ArmInterrupts()
end

local function Retire(state)
    if not L.Restore(state) then return false end
    T.Hide(state)
    T.Invalidate(state)
    E.Hide(state)
    state.unit, state.plan, state.casting, state.castID, state.interruptExpired = nil, nil, nil, nil, nil
    state.focus, state.relevant, state.range, state.rangeValue, state.visible = nil, nil, nil, nil, nil
    if targetState == state then targetState = nil end
    return true
end

local function FlushRestores()
    for state in pairs(restores) do if Retire(state) then restores[state] = nil end end
    if R.pending then R.Refresh() end
    if restoreFrame and not next(restores) and not R.pending then restoreFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    Extensions.inUse = plan and plan.enabled or next(restores) ~= nil or R.pending == true
end

local function RestoreEvent()
    NS.Dispatch(FlushRestores)
end

local function ArmRestores()
    if not restoreFrame then
        restoreFrame = S.CreateFrame("Frame")
        restoreFrame:SetScript("OnEvent", RestoreEvent)
    end
    restoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    Extensions.inUse = true
end

function Extensions.Restore(uf)
    local state = states[uf]
    if not state or not state.unit then return end
    RangeActive(state, false)
    if Retire(state) then
        restores[state] = nil
    else
        if Safe(uf) then E.Suspend(state) end
        restores[state] = true
        ArmRestores()
    end
end

function Extensions.BeforeNameFilter(uf)
    local state = states[uf]
    if state then L.RestoreName(state) end
end

local function CastPresent(unit)
    local duration = UnitCastingDuration(unit)
    if NS.IsSecret(duration) then return nil end
    if duration ~= nil then return true end
    duration = UnitChannelDuration(unit)
    if NS.IsSecret(duration) then return nil end
    return duration ~= nil
end

local function NativeCastShown(cast)
    local state = castStates[cast]
    if not state or restores[state] or not state.unit or not M.active or not plan.enabled or not Safe(state.uf) then return end
    state.casting = CastPresent(state.unit)
    Presentation(state)
end

local function NativeCastHidden(cast)
    local state = castStates[cast]
    if not state or restores[state] or not state.unit or not M.active or not plan.enabled or not Safe(state.uf) then return end
    state.casting = false
    Presentation(state)
end

local function ObserveCast(state)
    local cast = state.cast
    if not cast or castStates[cast] then return end
    castStates[cast] = state
    cast:HookScript("OnShow", NativeCastShown)
    cast:HookScript("OnHide", NativeCastHidden)
end

function Extensions.Apply(uf, health, cast, prefix, unit)
    if not M.active or not plan or not plan.enabled or not prefix or not M.config[prefix]
        or M.config.look == P.Mode.LOOK_BLIZZARD or not PublicUnit(unit) then
        Extensions.Restore(uf)
        return
    end
    if not Safe(uf) or not Safe(health) then return end
    local state = states[uf]
    if state and state.unit and state.unit ~= unit then
        Extensions.Restore(uf)
        if restores[state] then return end
    end
    if not state then
        state = { uf = uf, health = health, owner = M }
        states[uf] = state
    end
    local mutable = L.Mutable(state, uf)
    local fresh = state.unit == nil
    if fresh then
        state.plate = C_NamePlate.GetNamePlateForUnit(unit)
        state.casting = CastPresent(unit)
        state.unit = unit
    end
    if state.plan ~= plan or state.prefix ~= prefix then T.Invalidate(state) state.layoutPlan = nil end
    state.health, state.cast, state.prefix, state.plan = health, Safe(cast) and cast or nil, prefix, plan
    P.Layout.Observe(uf)
    ObserveCast(state)
    if state.interruptExpired then E.EndInterrupt(state) state.interruptExpired = nil end
    state.kind = X.Kind(uf.isFriend, uf.isPlayer)
    state.focus = (plan.focusScale ~= 1 or plan.focusReminder) and Same(unit, "focus") or false
    if plan.range and Same(unit, "target") then targetState = state end
    state.relevant = Relevant(state)
    if plan.range and prefix == "enemy" then state.range, state.rangeValue = ReadRange(state) end
    L.Anchors(state)
    Presentation(state)
    if mutable then
        E.Resume(state)
        T.Apply(state)
        E.Execute(state)
        E.Identity(state)
    end
end

local function DataEvent(_, event, unit)
    if not M.active or not plan.enabled or not PublicUnit(unit) then return end
    local uf = M.activeUnits[unit]
    local state = uf and states[uf]
    if not state or restores[state] or state.unit ~= unit or not L.Mutable(state, uf) then return end
    if event == "UNIT_HEALTH" then
        E.Execute(state)
        return
    end
    if event == "UNIT_NAME_UPDATE" then state.metadataReady = nil E.Identity(state) end
    T.Apply(state, event)
end

function Extensions.OnUnit(_, event, unit)
    DataEvent(M, event, unit)
end

local function MetadataPass()
    if not M.active then return end
    for _, state in pairs(states) do
        if state.unit and not restores[state] and L.Mutable(state, state.uf) then state.metadataReady = nil T.Apply(state) end
    end
end

function Extensions.OnMetadata()
    if metadataJob then metadataJob:Request() end
end

local function RangeEvent(_, _, spell, inRange, checksRange)
    if NS.IsSecret(spell) or spell ~= registeredSpell or not targetState or not targetState.unit then return end
    if not Safe(targetState.uf) then return end
    local checked = not NS.IsSecret(checksRange) and checksRange == true
    local range = checked and X.Range(inRange) or 3
    if targetState.range ~= range or checked and NS.IsSecret(inRange) or NS.IsSecret(targetState.rangeValue) then
        targetState.range, targetState.rangeValue = range, nil
        if checked then targetState.rangeValue = inRange end
        Presentation(targetState)
    end
end

local START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true }
local STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_EMPOWER_STOP = true }

function Extensions.OnCast(_, event, unit, _, _, fourth, fifth, sixth)
    if not plan or not plan.enabled or not PublicUnit(unit) then return end
    local uf = M.activeUnits[unit]
    local state = uf and states[uf]
    if not state or restores[state] or state.unit ~= unit or not Safe(uf) then return end
    if START[event] then
        state.casting = true
        state.castID = not NS.IsSecret(fourth) and fourth or nil
        E.EndInterrupt(state)
    elseif STOP[event] then
        local castID, interrupter = fourth, nil
        if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            castID, interrupter = fifth, fourth
        elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            castID, interrupter = sixth, fifth
        end
        if not NS.IsSecret(castID) and castID ~= nil and state.castID ~= nil and castID ~= state.castID then return end
        state.casting = false
        local interrupted = event == "UNIT_SPELLCAST_INTERRUPTED"
            or not NS.IsSecret(interrupter) and type(interrupter) == "string" and interrupter ~= ""
            or event == "UNIT_SPELLCAST_EMPOWER_STOP" and not NS.IsSecret(fourth) and fourth == false
        if interrupted and L.Mutable(state, uf) then E.Interrupt(state, interrupter) ArmInterrupts() end
    end
    Presentation(state)
end

function Extensions.OnSelection()
    if not plan or not plan.enabled or not M.active then return end
    if plan.focusReminder then hasFocus = FocusPresent() else hasFocus = nil end
    targetState = nil
    for _, state in pairs(states) do
        if state.unit and not restores[state] and Safe(state.uf) then
            state.focus = (plan.focusScale ~= 1 or plan.focusReminder) and Same(state.unit, "focus") or false
            if plan.range and Same(state.unit, "target") then targetState = state end
            if plan.range and state.prefix == "enemy" then state.range, state.rangeValue = ReadRange(state) end
            Presentation(state)
        end
    end
    if not R.Refresh() then ArmRestores() end
end

function Extensions.OnContext(changed)
    if not plan or not plan.enabled or not M.active then return end
    local oldContext, oldFocus = context, hasFocus
    ReadContext()
    if changed == false and oldContext == context and oldFocus == hasFocus then return end
    for _, state in pairs(states) do
        if state.unit and not restores[state] and Safe(state.uf) then
            state.metadataReady = nil
            state.relevant = Relevant(state)
            Presentation(state)
            if L.Mutable(state, state.uf) then T.Apply(state) end
        end
    end
end

function Extensions.OnCombatEnded()
    FlushRestores()
    if plan and plan.enabled then Extensions.OnContext() end
end

local function NativeAnchors(uf)
    local state = states[uf]
    if not state or restores[state] or not state.unit or not M.active or not plan.enabled then return end
    state.raidMoved, state.iconMoved, state.layoutPlan = nil, nil, nil
    L.Anchors(state, true)
end
Extensions.OnAnchors = NativeAnchors

local function NativeHitTest(uf)
    local state = states[uf]
    if not state or not state.unit then return end
    L.NativeHitTest(state)
    if M.active and plan.enabled and L.Mutable(state, uf) then Presentation(state) end
end

local function Subscribe(event, callback, wanted)
    if wanted then
        local units = event:sub(1, 5) == "UNIT_" and S.NameplateUnits or nil
        M.context:Event(event, callback, IN_COMBAT, units)
        subscribed[event] = true
    elseif subscribed[event] then
        M.context:RemoveEvent(event)
        subscribed[event] = nil
    end
end

local function Subscriptions()
    local sources, enabled = plan.sources, plan.enabled and M.active
    Subscribe("UNIT_HEALTH", DataEvent, enabled and plan.execute)
    Subscribe("UNIT_TARGET", DataEvent, enabled and (sources[2] or sources[7]))
    local identity = plan.enemy.identity > 1 or plan.friendly.identity > 1
    Subscribe("UNIT_NAME_UPDATE", DataEvent, enabled and (sources[2] or sources[4] or sources[5] or identity))
    Subscribe("UNIT_POWER_UPDATE", DataEvent, enabled and sources[8])
    P.Power.SetExtraTextEvents(enabled and sources[8])
    Subscribe("UNIT_ABSORB_AMOUNT_CHANGED", DataEvent, enabled and sources[9])
    Subscribe("SPELL_RANGE_CHECK_UPDATE", RangeEvent, enabled and plan.range)
    local metadata = enabled and (sources[3] or sources[4] or sources[5] or sources[10])
    Subscribe("CHALLENGE_MODE_START", Extensions.OnMetadata, metadata and sources[10])
    Subscribe("CHALLENGE_MODE_COMPLETED", Extensions.OnMetadata, metadata and sources[10])
    Subscribe("PLAYER_GUILD_UPDATE", Extensions.OnMetadata, metadata and sources[4])
    if metadata then
        metadataJob = M.context:Coalesce(.5, MetadataPass)
    elseif metadataJob then
        metadataJob:Cancel()
        metadataJob = nil
    end
end

function Extensions.Configure(module)
    M = module
    plan = X.Plan(module.config)
    plan.enabled = plan.enabled and module.config.look ~= P.Mode.LOOK_BLIZZARD
    if plan.enabled and plan.range and plan.rangeSpell > 0 then
        local exists = C_Spell.DoesSpellExist(plan.rangeSpell)
        if NS.IsSecret(exists) or exists ~= true then plan.rangeSpell = 0 end
    end
    ReadContext()
    E.Configure(plan)
    Extensions.inUse = plan.enabled or next(restores) ~= nil
    if plan.enabled and not hooked then
        hooked = true
        P.HookPlates("UpdateHitTestArea", NativeHitTest)
    end
    Subscriptions()
    if not R.Configure(module, plan) then ArmRestores() end
    if not plan.enabled then
        for uf in pairs(states) do Extensions.Restore(uf) end
        Extensions.inUse = next(restores) ~= nil or R.pending == true
    end
    if not plan.range then
        for _, state in pairs(states) do RangeActive(state, false) end
    end
    RangeSubscription()
end

function Extensions.Disable()
    if not M then return end
    plan.enabled, plan.range = false, false
    Subscriptions()
    for uf in pairs(states) do Extensions.Restore(uf) end
    if registeredSpell then S.SetNativeSpellRange(RANGE_OWNER, registeredSpell, false) registeredSpell = nil end
    M.context:Cancel(RangeTick)
    M.context:Cancel(ExpireInterrupts)
    if metadataJob then metadataJob:Cancel() metadataJob = nil end
    if not R.Disable() then ArmRestores() end
    Extensions.inUse = next(restores) ~= nil or R.pending == true
end

function Extensions.Bind(module) M = module end
