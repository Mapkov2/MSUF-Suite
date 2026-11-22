local _, P = ...
local NS, S = P.NS, P.Suite
local X, L, T, E = NS.NameplateExtensions, P.ExtensionLayout, P.ExtensionText, P.ExtensionEffects
local Extensions = { inUse = false }
P.Extensions = Extensions
local M, plan, context, hasFocus, targetState, hideEnemies, opacityCombat
local states, restores = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local castStates = setmetatable({}, { __mode = "k" })
local subscribed = {}
local registeredSpell, RangeEvent
local nativeRange = C_Spell and C_Spell.EnableSpellRangeCheck
local restoreFrame, hooked, metadataJob
local IN_COMBAT, RANGE_OWNER = { inCombat = true }, "MSUF_Suite_NameplateExtensions"
local ExpireInterrupts

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

local function Is(value, expected)
    return not NS.IsSecret(value) and value == expected
end

local function EnemyHidden(load, event)
    local usesCombat = load.enemyHideInCombat or load.enemyHideOutOfCombat or load.enemyHideOutOfCombatNoTarget
    local combat = usesCombat and NS.InCombat(event)
    if load.enemyHideInCombat and combat or load.enemyHideOutOfCombat and not combat then return true end
    if (load.enemyHideNoTarget or load.enemyHideOutOfCombatNoTarget and not combat)
        and Is(UnitExists("target"), false) then return true end
    if load.enemyHideInGroup or load.enemyHideSolo then
        local grouped = IsInGroup()
        if load.enemyHideInGroup and Is(grouped, true) or load.enemyHideSolo and Is(grouped, false) then return true end
    end
    if load.enemyHideInInstance and Is(IsInInstance(), true) then return true end
    if load.enemyHideInVehicle and (Is(UnitHasVehicleUI("player"), true) or Is(UnitInVehicle("player"), true)) then
        return true
    end
    if load.enemyHideMounted and Is(IsMounted(), true) then return true end
    if load.enemyHideResting and Is(IsResting(), true) then return true end
    if load.enemyHideStealthed and Is(IsStealthed(), true) then return true end
    return load.enemyHideInHousing == true and C_Housing and C_Housing.IsInsideHouseOrPlot
        and Is(C_Housing.IsInsideHouseOrPlot(), true) or false
end

local function ReadEnemyLoad(event)
    local hidden = plan.enemyLoad ~= nil and EnemyHidden(plan.enemyLoad, event)
    if hidden == hideEnemies then return false end
    hideEnemies = hidden
    return true
end

local function ReadContext(event)
    context, hasFocus = nil, nil
    if not plan.enabled then return end
    if plan.contextEnabled then local _, instanceType = IsInInstance() context = X.Context(instanceType) end
    if plan.focusReminder then hasFocus = FocusPresent() end
    local combat = plan.opacityCombat and NS.InCombat(event)
    local opacityChanged = combat ~= opacityCombat
    opacityCombat = combat
    return ReadEnemyLoad(event) or opacityChanged
end

local function RangeSubscription()
    local scope = targetState and targetState.interaction
    local spell = nativeRange and plan.range and targetState and targetState.visible and scope and scope.range
        and targetState.rangeSpell or nil
    if spell == registeredSpell then return end
    local previous = registeredSpell
    registeredSpell = spell
    if previous then S.SetNativeSpellRange(RANGE_OWNER, previous, false) end
    if spell then
        if not previous then M.context:Event("SPELL_RANGE_CHECK_UPDATE", RangeEvent, IN_COMBAT) end
        S.SetNativeSpellRange(RANGE_OWNER, spell, true)
    else
        M.context:RemoveEvent("SPELL_RANGE_CHECK_UPDATE")
    end
end

local function SeedRange(state)
    if state ~= targetState then
        state.range, state.rangeValue, state.rangeSeed, state.rangeSpell = nil, nil, nil, nil
        return
    end
    local scope = state.interaction
    local spell = scope and scope.range and scope.rangeSpell or 0
    if spell == state.rangeSeed then return end
    state.rangeSeed = spell
    local value
    if spell > 0 then
        local override = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spell)
        if not NS.IsSecret(override) and type(override) == "number" and override > 0 then spell = override end
        value = C_Spell.IsSpellInRange(spell, state.unit)
    end
    state.range, state.rangeValue, state.rangeSpell = X.Range(value), value, spell > 0 and spell or nil
end

local function ReseedTarget()
    local state = targetState
    if not state or not Safe(state.uf) or not Same(state.unit, "target") then return end
    state.rangeSeed = nil
    SeedRange(state)
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

local function ApplyAlpha(state)
    local opacity = state.visible and state.opacity or 0
    local fade = state.layerFade
    if fade and not opacityCombat then opacity = opacity * fade.ooc end
    local rangeValue
    local scope = state.interaction
    if opacity > 0 and state == targetState and scope and scope.range then
        rangeValue = state.rangeValue
        if not NS.IsSecret(rangeValue) then
            local range = state.range or 3
            opacity = opacity * (range == 2 and scope.rangeAlpha or range == 3 and scope.rangeUnknownAlpha or 1)
        end
    end
    L.Alpha(state, opacity, rangeValue, scope and scope.rangeAlpha or 1, state.injured)
end

local function PlateLayers(state, force)
    if plan.opacity or state.layerFade or state.layers then
        local scope = X.OpacityScope(state.kind)
        L.Layers(state, plan.opacity and plan.opacity[scope], force)
    end
end

local function Presentation(state)
    local wasVisible = state.visible
    local visible, opacity, scale = X.Visibility(plan, state.kind, context, state.casting)
    local enemy = plan.enemyLoad and X.IsEnemy(state.kind)
    local loadHidden = enemy and hideEnemies
    if loadHidden then visible = false end
    local clickable = L.HitTest(state, not visible)
    -- Public load conditions still update alpha when Blizzard holds the click area.
    if not clickable and not (loadHidden or state.loadHidden) then visible = state.visible ~= false end
    state.visible, state.loadHidden = visible, loadHidden
    state.opacity, state.injured = opacity, enemy and plan.enemyLoad.enemyShowWhenInjured
    ApplyAlpha(state)
    if state.focus then scale = scale * plan.focusScale end
    if state.casting then scale = scale * plan.castScale end
    L.Scale(state, scale)
    L.Name(state)
    if L.Mutable(state, state.uf) then
        E.Reminder(state, plan.focusReminder and hasFocus == false
            and (state.relevant or state.casting == true and state.kind == "enemyNpc"))
        E.Range(state, state == targetState)
        if wasVisible ~= nil and wasVisible ~= visible then E.Execute(state) end
    end
    if state == targetState then RangeSubscription() end
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
    state.watchesCast = nil
    state.focus, state.relevant, state.range, state.rangeValue, state.visible = nil, nil, nil, nil, nil
    state.rangeSeed, state.rangeSpell = nil, nil
    state.opacity, state.injured, state.loadHidden = nil, nil, nil
    state.interaction = nil
    if targetState == state then
        targetState = nil
        RangeSubscription()
    end
    return true
end

local function FlushRestores()
    for state in pairs(restores) do if Retire(state) then restores[state] = nil end end
    if restoreFrame and not next(restores) then restoreFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    Extensions.inUse = plan and plan.enabled or next(restores) ~= nil
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
    if targetState == state then
        targetState = nil
        RangeSubscription()
    end
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

-- A roster update can release the group filter while the same cast is
-- running. Resume its opacity without repainting the rest of the plate.
function Extensions.ResumeName(uf)
    local state = states[uf]
    if state and state.unit and M.activeUnits[state.unit] == uf and not restores[state] then L.Name(state) end
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
    if not state or not state.watchesCast or state.cast ~= cast or restores[state]
        or not state.unit or not M.active or not Extensions.usesCasts or not Safe(state.uf) then return end
    state.casting = CastPresent(state.unit)
    Presentation(state)
end

local function NativeCastHidden(cast)
    local state = castStates[cast]
    if not state or not state.watchesCast or state.cast ~= cast or restores[state]
        or not state.unit or not M.active or not Extensions.usesCasts or not Safe(state.uf) then return end
    state.casting = false
    Presentation(state)
end

local function ObserveCast(state, changedBar)
    local kind, side = state.kind, plan[state.prefix]
    local rule = plan.kinds[kind]
    local watch = Extensions.usesCasts and (side.nameCast > 1 or plan.interrupt or plan.castScale ~= 1
        or plan.focusReminder and kind == "enemyNpc" or plan.contextEnabled and rule and rule.castVisibility > 1)
    if not watch then
        state.watchesCast, state.casting, state.castID = nil, nil, nil
        return
    end
    if not state.watchesCast or changedBar then state.casting = CastPresent(state.unit) end
    state.watchesCast = true
    local cast = state.cast
    if not cast then return end
    local previous = castStates[cast]
    castStates[cast] = state
    if previous then return end
    cast:HookScript("OnShow", NativeCastShown)
    cast:HookScript("OnHide", NativeCastHidden)
end

local function SetInteraction(state)
    local entry = plan.interaction[X.OpacityScope(state.kind)]
    if entry ~= state.interaction then
        state.interaction = entry
        state.hitPlan = nil
        T.Invalidate(state)
    end
end

function Extensions.Apply(uf, health, cast, prefix, unit)
    if not M.active or not plan or not plan.enabled or not prefix or not M.config[prefix]
        or M.config.look == P.Mode.LOOK_BLIZZARD or not PublicUnit(unit)
        or plan.questTextOnly and not P.FriendlyNames.KeepsQuestText(uf) then
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
        state.unit = unit
    end
    if state.plan ~= plan or state.prefix ~= prefix then T.Invalidate(state) state.layoutPlan = nil end
    local previousCast = state.cast
    state.health, state.cast, state.prefix, state.plan = health, Safe(cast) and cast or nil, prefix, plan
    P.Layout.Observe(uf)
    if state.interruptExpired then E.EndInterrupt(state) state.interruptExpired = nil end
    if plan.neutralContext or plan.enemyLoad or plan.opacity or plan.hostileScoped then
        state.kind = X.PlateKind(uf, unit, P.UnitKinds[uf])
    else
        state.kind = P.UnitKinds[uf] or X.UnitKind(uf, unit)
    end
    ObserveCast(state, state.cast ~= previousCast)
    state.focus = (plan.focusScale ~= 1 or plan.focusReminder) and Same(unit, "focus") or false
    SetInteraction(state)
    if plan.range and Same(unit, "target") then targetState = state end
    state.relevant = Relevant(state)
    if plan.range then SeedRange(state) end
    L.Anchors(state)
    PlateLayers(state, true)
    Presentation(state)
    if mutable then
        if P.FriendlyNames and P.FriendlyNames.nameOnlyEnabled and P.FriendlyNames.IsNameOnly(uf) then
            T.Apply(state)
            E.Hide(state)
        else
            E.Resume(state)
            T.Apply(state)
            E.Execute(state)
            E.Identity(state)
        end
    end
end

function Extensions.RepaintLayers(uf)
    local state = states[uf]
    if not state or not state.unit or restores[state] or not plan.opacity then return end
    if not Safe(uf) or not Safe(state.health) then return end
    PlateLayers(state, true)
    L.Name(state)
end

local function UpdateKind(uf, unit)
    local state = states[uf]
    if not state or restores[state] or state.unit ~= unit then return end
    local kind = X.PlateKind(uf, unit, P.UnitKinds[uf])
    if kind == state.kind then return end
    state.kind = kind
    ObserveCast(state)
    SetInteraction(state)
    if state == targetState then SeedRange(state) end
    PlateLayers(state)
    Presentation(state)
    if L.Mutable(state, uf) then T.Apply(state) end
end

local function NeutralEvent(module, event, unit)
    module.unitEvents(module, event, unit)
    if not PublicUnit(unit) then return end
    local uf = module.activeUnits[unit]
    if not Safe(uf) or P.IsSkinSuppressed and P.IsSkinSuppressed(uf) then return end
    local features = P.EasyFeatures
    if features and features.splitEnemyPatterns then features.UpdatePatternScope(uf, unit) end
    if P.PlatePrefix(uf) ~= "enemy" then return end
    if module.config.neutralNpcSizeOverride then P.Layout.Apply(uf, "enemy", module.config) end
    if plan.neutralContext or plan.enemyLoad or plan.opacity or plan.hostileScoped then UpdateKind(uf, unit) end
end

function Extensions.NeutralHandler(config)
    local features = P.EasyFeatures
    if config.neutralNpcSizeOverride == true or plan.neutralContext or plan.enemyLoad or plan.opacity or plan.hostileScoped
        or features and features.splitEnemyPatterns then
        return NeutralEvent
    end
end

local function DataEvent(_, event, unit)
    if not M.active or not plan.enabled or not PublicUnit(unit) then return end
    local uf = M.activeUnits[unit]
    local state = uf and states[uf]
    if not state or restores[state] or state.unit ~= unit or not Safe(uf) then return end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if state.injured and state.visible then ApplyAlpha(state) end
        if plan.execute and event == "UNIT_HEALTH" and L.Mutable(state, uf) then E.Execute(state) end
        return
    end
    if not L.Mutable(state, uf) then return end
    if event == "UNIT_NAME_UPDATE" then state.metadataReady = nil E.Identity(state) end
    T.Apply(state, event)
end

local function TargetEvent(module, event, unit)
    module:OnAggroTargetChanged(unit)
    DataEvent(module, event, unit)
end

local needsNameData, nameEventUnits
local function NameEvent(module, event, unit)
    if P.FriendlyNames.managedNames and PublicUnit(unit) then
        local token, uf = unit, module.activeUnits[unit]
        if unit == "target" then
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            uf = Safe(plate) and Is(plate:CanBeAccessedInContext(), true) and plate.UnitFrame
            token = Safe(uf) and Is(uf:CanBeAccessedInContext(), true) and uf.unit
            if not PublicUnit(token) or module.activeUnits[token] ~= uf then uf = nil end
        end
        if uf then P.FriendlyNames.RepairMissing(uf, token) end
    end
    if needsNameData then DataEvent(module, event, unit) end
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

RangeEvent = function(_, _, spell, inRange, checksRange)
    local state = targetState
    if NS.IsSecret(spell) or spell ~= registeredSpell or not state or not state.unit then return end
    if not Safe(state.uf) or not Same(state.unit, "target") then return end
    local checked = not NS.IsSecret(checksRange) and checksRange == true
    local range = checked and X.Range(inRange) or 3
    if state.range ~= range or checked and NS.IsSecret(inRange) or NS.IsSecret(state.rangeValue) then
        state.range, state.rangeValue = range, nil
        if checked then state.rangeValue = inRange end
        ApplyAlpha(state)
        if state.interaction.rangeText and L.Mutable(state, state.uf) then E.Range(state, true) end
    end
end

local START = { UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true }
local STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true, UNIT_SPELLCAST_EMPOWER_STOP = true }

function Extensions.OnCast(_, event, unit, _, _, fourth, fifth, sixth)
    if not Extensions.usesCasts or not (START[event] or STOP[event]) or not PublicUnit(unit) then return end
    local uf = M.activeUnits[unit]
    local state = uf and states[uf]
    if not state or not state.watchesCast or restores[state] or state.unit ~= unit or not Safe(uf) then return end
    if START[event] then
        state.casting = true
        state.castID = not NS.IsSecret(fourth) and fourth or nil
        if plan.interrupt then E.EndInterrupt(state) end
    else
        local castID, interrupter = fourth, nil
        if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            castID, interrupter = fifth, fourth
        elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            castID, interrupter = sixth, fifth
        end
        if not NS.IsSecret(castID) and castID ~= nil and state.castID ~= nil and castID ~= state.castID then return end
        state.casting = false
        local interrupted = plan.interrupt and (event == "UNIT_SPELLCAST_INTERRUPTED"
            or not NS.IsSecret(interrupter) and type(interrupter) == "string" and interrupter ~= ""
            or event == "UNIT_SPELLCAST_EMPOWER_STOP" and not NS.IsSecret(fourth) and fourth == false)
        if interrupted and L.Mutable(state, uf) then E.Interrupt(state, interrupter) ArmInterrupts() end
    end
    Presentation(state)
end

function Extensions.OnSelection()
    if not plan or not plan.enabled or not M.active then return end
    if plan.enemyLoad then ReadEnemyLoad() end
    if plan.focusReminder then hasFocus = FocusPresent() else hasFocus = nil end
    local previous = targetState
    targetState = nil
    for _, state in pairs(states) do
        if state.unit and not restores[state] and Safe(state.uf) then
            state.focus = (plan.focusScale ~= 1 or plan.focusReminder) and Same(state.unit, "focus") or false
            if plan.range and Same(state.unit, "target") then
                targetState = state
                SeedRange(state)
            elseif state == previous then
                SeedRange(state)
            end
            Presentation(state)
        end
    end
    if plan.range then RangeSubscription() end
end

function Extensions.OnContext(changed, event)
    if not plan or not plan.enabled or not M.active then return end
    local oldContext, oldFocus = context, hasFocus
    local loadChanged = ReadContext(event)
    if event == "PLAYER_ENTERING_WORLD" then ReseedTarget() end
    if changed == false and not loadChanged and oldContext == context and oldFocus == hasFocus then return end
    for _, state in pairs(states) do
        if state.unit and not restores[state] and Safe(state.uf) then
            state.metadataReady = nil
            state.relevant = Relevant(state)
            Presentation(state)
            if L.Mutable(state, state.uf) then T.Apply(state) end
        end
    end
end

function Extensions.RangeSpellChanged()
    local bridge = NS.HostBridge
    if bridge and bridge.NameplateRangeSpell then
        for _, entry in pairs(plan.interaction) do
            if entry.rangeAuto then entry.rangeSpell = bridge.NameplateRangeSpell(entry.friendly) end
        end
    end
    if not targetState then return end
    ReseedTarget()
    if targetState and Safe(targetState.uf) then Presentation(targetState) end
end

function Extensions.OnCombatEnded()
    FlushRestores()
    if plan and plan.enabled then
        Extensions.OnContext(nil, "PLAYER_REGEN_ENABLED")
        if plan.neutralQuestText then Extensions.OnMetadata() end
    end
end

local function NativeAnchors(uf)
    local state = states[uf]
    if not state or restores[state] or not state.unit or not M.active or not plan.enabled then return end
    state.raidMoved, state.iconMoved, state.layoutPlan = nil, nil, nil
    L.Anchors(state, true)
end
Extensions.OnAnchors = NativeAnchors

local function NativeHitTest(uf)
    if P.SkinScopes and P.SkinScopes.OnHitTest(uf) then return end
    local state = states[uf]
    if not state or not state.unit then return end
    L.NativeHitTest(state)
    if not restores[state] and M.active and plan.enabled and L.Mutable(state, uf) then Presentation(state) end
end

local function Subscribe(event, callback, wanted, unit)
    if wanted then
        local units = unit or event:sub(1, 5) == "UNIT_" and S.NameplateUnits or nil
        M.context:Event(event, callback, IN_COMBAT, units)
        subscribed[event] = true
    elseif subscribed[event] then
        M.context:RemoveEvent(event)
        subscribed[event] = nil
    end
end

local function EnemyLoadEvent(_, event, unit)
    if not M.active then return end
    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        if not PublicUnit(unit) or unit ~= "player" then return end
    end
    local changed = ReadEnemyLoad(event)
    local combatChanged = event == "PLAYER_REGEN_DISABLED" and plan.opacityCombat and not opacityCombat
    if combatChanged then opacityCombat = true end
    if not changed and not combatChanged then return end
    for _, state in pairs(states) do
        if state.unit and not restores[state] and Safe(state.uf) then
            if changed and X.IsEnemy(state.kind) then
                Presentation(state)
            elseif combatChanged and state.layerFade then
                ApplyAlpha(state)
            end
        end
    end
end

local LOAD_EVENTS = {
    { "PLAYER_REGEN_DISABLED", "enemyHideInCombat", "enemyHideOutOfCombat", "enemyHideOutOfCombatNoTarget" },
    { "UNIT_ENTERED_VEHICLE", "enemyHideInVehicle" },
    { "UNIT_EXITED_VEHICLE", "enemyHideInVehicle" },
    { "UPDATE_VEHICLE_ACTIONBAR", "enemyHideInVehicle" },
    { "PLAYER_MOUNT_DISPLAY_CHANGED", "enemyHideMounted" },
    { "PLAYER_UPDATE_RESTING", "enemyHideResting" },
    { "UPDATE_STEALTH", "enemyHideStealthed" },
    { "HOUSE_PLOT_ENTERED", "enemyHideInHousing" },
    { "HOUSE_PLOT_EXITED", "enemyHideInHousing" },
}

local function SubscribeEnemyLoad(load, fadeCombat)
    for _, entry in ipairs(LOAD_EVENTS) do
        local event, first, second, third = unpack(entry)
        local needed = event == "PLAYER_REGEN_DISABLED" and fadeCombat or load and (load[first] or load[second] or load[third])
        local unit = first == "enemyHideInVehicle" and event:sub(1, 5) == "UNIT_" and "player" or nil
        Subscribe(event, EnemyLoadEvent, needed, unit)
    end
end

local function Subscriptions()
    local sources, enabled = plan.sources, plan.enabled and M.active
    local load = enabled and plan.enemyLoad
    local injured = load and load.enemyShowWhenInjured
    SubscribeEnemyLoad(load, enabled and plan.opacityCombat)
    Subscribe("UNIT_HEALTH", DataEvent, enabled and (plan.execute or injured))
    Subscribe("UNIT_MAXHEALTH", DataEvent, injured)
    local aggro = M.active and P.Selection and P.Selection.aggroEnabled
    Subscribe("UNIT_TARGET", aggro and TargetEvent or DataEvent, aggro or enabled and (sources[2] or sources[7]))
    local identity = plan.enemy.identity > 1 or plan.friendly.identity > 1
    needsNameData = enabled and (sources[2] or sources[4] or sources[5] or identity or plan.neutralQuestText)
    local managed = M.active and P.FriendlyNames and P.FriendlyNames.managedNames
    -- The router retains the first native unit filter until unregistration.
    -- Both consumers share this stable filter when a setting changes.
    if (managed or needsNameData) and not nameEventUnits and S.NameplateUnits then
        nameEventUnits = { unpack(S.NameplateUnits) }
        nameEventUnits[#nameEventUnits + 1] = "target"
    end
    Subscribe("UNIT_NAME_UPDATE", managed and NameEvent or DataEvent, managed or needsNameData, nameEventUnits)
    Subscribe("UNIT_POWER_UPDATE", DataEvent, enabled and sources[8])
    P.Power.SetExtraTextEvents(enabled and sources[8])
    Subscribe("UNIT_ABSORB_AMOUNT_CHANGED", DataEvent, enabled and sources[9])
    Subscribe("UPDATE_SHAPESHIFT_FORM", Extensions.RangeSpellChanged, enabled and plan.range)
    Extensions.usesQuestText = enabled and (sources[3] or plan.neutralQuestText)
    local metadata = enabled and (Extensions.usesQuestText or sources[4] or sources[5] or sources[10])
    Subscribe("CHALLENGE_MODE_START", Extensions.OnMetadata, metadata and sources[10])
    Subscribe("CHALLENGE_MODE_COMPLETED", Extensions.OnMetadata, metadata and sources[10])
    Subscribe("PLAYER_GUILD_UPDATE", Extensions.OnMetadata, metadata and sources[4])
    Extensions.usesMetadata = metadata or false
    if metadata then
        metadataJob = M.context:Coalesce(.5, MetadataPass)
    elseif metadataJob then
        metadataJob:Cancel()
        metadataJob = nil
    end
end

local function NeedsCasts()
    local c = M.config
    if not plan.enabled or not (c.enemy or c.friendly) then return false end
    if plan.interrupt or plan.focusReminder and c.enemy or plan.castScale ~= 1
        or c.enemy and plan.enemy.nameCast > 1 or c.friendly and plan.friendly.nameCast > 1 then return true end
    if plan.contextEnabled then
        for _, kind in pairs(plan.kinds) do if kind.castVisibility > 1 then return true end end
    end
    return false
end

function Extensions.Configure(module)
    M = module
    local hadInterrupt = plan and plan.enabled and plan.interrupt
    plan = X.Plan(module.config)
    plan.enabled = plan.enabled and module.config.look ~= P.Mode.LOOK_BLIZZARD
    if plan.enabled and plan.range then
        for _, scope in pairs(plan.interaction) do
            if scope.range and scope.rangeSpell > 0 then
                local exists = C_Spell.DoesSpellExist(scope.rangeSpell)
                if NS.IsSecret(exists) or exists ~= true then scope.rangeSpell = 0 end
            end
        end
    end
    if plan.enabled then T.Configure(plan.interaction) end
    ReadContext()
    E.Configure(plan)
    if hadInterrupt and not (plan.enabled and plan.interrupt) then
        M.context:Cancel(ExpireInterrupts)
        for _, state in pairs(states) do
            if state.interruptUntil or state.interruptExpired then
                E.EndInterrupt(state)
                state.interruptExpired = nil
            end
        end
    end
    Extensions.inUse = plan.enabled or next(restores) ~= nil
    Extensions.usesRange = plan.enabled and plan.range
    Extensions.usesCasts = NeedsCasts()
    if not hooked and (P.IsSkinSuppressed or plan.enabled and (plan.contextEnabled or plan.enemyLoad or plan.clickbox))
        and type(NamePlateUnitFrameMixin.UpdateHitTestArea) == "function" then
        hooked = true
        P.HookPlates("UpdateHitTestArea", NativeHitTest)
    end
    Subscriptions()
    if not plan.enabled then
        for uf in pairs(states) do Extensions.Restore(uf) end
        Extensions.inUse = next(restores) ~= nil
    end
    if not plan.range then targetState = nil end
    RangeSubscription()
end

function Extensions.Disable()
    if not M then return end
    plan.enabled, plan.range = false, false
    Extensions.usesRange, Extensions.usesCasts = nil, nil
    Subscriptions()
    for uf in pairs(states) do Extensions.Restore(uf) end
    targetState = nil
    RangeSubscription()
    M.context:Cancel(ExpireInterrupts)
    if metadataJob then metadataJob:Cancel() metadataJob = nil end
    Extensions.inUse = next(restores) ~= nil
end

function Extensions.Bind(module) M = module end
