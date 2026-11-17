local _, private = ...
local NS, S = private.NS, private.Suite
local Text = NS.NameplateText
local IsSecret = NS.IsSecret
local IsCombatLocked = NS.IsCombatLocked
local states = setmetatable({}, { __mode = "k" })
local Names = { states = states, inUse = false }
private.NameText = Names
local M, looks, hooked, threatHooked

function Names.Bind(module) M = module end

-- The plate Button and its FontString can lose access while still tracked.
local function ReadLabel(uf)
    local forbidden = uf:IsForbidden()
    if IsSecret(forbidden) or forbidden then return end
    local label = uf.name
    if not label then return end
    forbidden = label:IsForbidden()
    if IsSecret(forbidden) or forbidden then return end
    return label
end

local function Protected(uf, label)
    local protected = uf:IsProtected()
    if IsSecret(protected) or protected then return true end
    protected = label:IsProtected()
    return IsSecret(protected) or protected
end

local function Safe(uf)
    if not uf then return end
    local label = ReadLabel(uf)
    if not label then return end
    if IsCombatLocked() and Protected(uf, label) then
        M.pendingPlates[uf] = true
        return
    end
    return label
end

local function Clear(state)
    for key in pairs(state) do state[key] = nil end
end

-- Keeps the unit mapping, drops the rest. captured marks a Capture that
-- succeeded since the last Clear (raw alone does not: a label without text
-- captures nil); every field but unit, prefix, look and nativeDirty is
-- written only after one, so a state without the mark has nothing else to
-- drop. Secret names take this way on every native update (2026-11-11 raid
-- trace: 24,911 in 300 s).
local function ForgetPlain(state)
    if not state.captured then
        state.look, state.nativeDirty = nil, nil
        return
    end
    local unit, prefix = state.unit, state.prefix
    Clear(state)
    state.unit, state.prefix = unit, prefix
end

local function Capture(state, label, raw)
    state.raw, state.captured = raw, true
    local r, g, b, a = label:GetTextColor()
    if S.Finite(r) and S.Finite(g) and S.Finite(b) and S.Finite(a) then
        state.r, state.g, state.b, state.a = r, g, b, a
    else
        state.r, state.g, state.b, state.a = nil, nil, nil, nil
    end
    state.formatted, state.tinted, state.nativeDirty = nil, nil, nil
end

local function RestoreColor(state, label)
    if state.tinted and state.r then
        local r, g, b, a = label:GetTextColor()
        if S.Finite(r) and S.Finite(g) and S.Finite(b) and S.Finite(a)
            and r == state.paintR and g == state.paintG and b == state.paintB and a == state.paintA then
            label:SetVertexColor(state.r, state.g, state.b, state.a)
        end
    end
    state.tinted = nil
end

local function Restore(state, label)
    if not state.formatted and not state.tinted then return end
    local current = label:GetText()
    if not S.Public(current) then
        ForgetPlain(state)
        return
    end
    if state.formatted and current == state.output then label:SetText(state.raw) end
    RestoreColor(state, label)
    state.formatted, state.tinted = nil, nil
end

local function Paint(state, label, look)
    if look.enabled then
        local output = Text.Format(state, state.raw, look)
        local changed = output ~= state.raw
        if changed or state.formatted then label:SetText(output) end
        state.output, state.formatted = output, changed
    elseif state.formatted then
        label:SetText(state.raw)
        state.formatted = nil
    end
    if (look.customColor or look.shared) and state.r then
        local applied = Text.PaintColor(label, state, look, state.unit)
        if not applied then RestoreColor(state, label) end
        local r, g, b, a = label:GetTextColor()
        if applied and S.Finite(r) and S.Finite(g) and S.Finite(b) and S.Finite(a) then
            state.paintR, state.paintG, state.paintB, state.paintA = r, g, b, a
            state.tinted = true
        else
            state.tinted = nil
        end
    elseif state.tinted then
        RestoreColor(state, label)
    end
    state.look = look
end

-- A name can become readable before the next native update. Keep the
-- combat-end replay even when the current text would be secret.
local function Defer(uf, state, label)
    M.pendingPlates[uf], state.look = true, nil
    if not uf.UpdateNameOverride then
        local shown = label:IsShown()
        if not IsSecret(shown) and shown then state.nativeDirty = true end
    end
end

-- Hidden and override calls can return without a native write. Only a shown
-- ordinary update can replace the saved baseline with fresh native values.
-- ReadLabel and Protected are repeated inline, same queries in the same
-- order: a secret name in a raid ends here without painting, so the hook
-- runs as one Lua frame (2026-11-15 raid trace: 10,213 of 24,848 hook runs
-- passed the mapping test, 10,153 read a secret name).
local function OnNativeName(uf)
    local state = states[uf]
    if not state or not M.active then return end
    local unit, prefix = state.unit, state.prefix
    if not unit or M.activeUnits[unit] ~= uf or not M.config[prefix] then return end
    -- looks holds owning sides only; this test stands in for Names.inUse.
    -- Read once here and reused after the label read.
    local look = looks[prefix]
    if not look then return end
    local flag = uf:IsForbidden()
    if IsSecret(flag) or flag then
        state.look = nil
        return
    end
    local label = uf.name
    if label then flag = label:IsForbidden() end
    if not label or IsSecret(flag) or flag then
        state.look = nil
        return
    end
    if IsCombatLocked() then
        flag = uf:IsProtected()
        if IsSecret(flag) or flag then return Defer(uf, state, label) end
        flag = label:IsProtected()
        if IsSecret(flag) or flag then return Defer(uf, state, label) end
    end
    if uf.UpdateNameOverride then return end
    flag = label:IsShown()
    if IsSecret(flag) or not flag then return end
    local raw = label:GetText()
    if IsSecret(raw) then
        if state.captured then ForgetPlain(state) end
        state.look, state.nativeDirty = look, nil
        return
    end
    Capture(state, label, raw)
    Paint(state, label, look)
end

local function RestoreInactive()
    Names.pendingRestore = false
    for uf, state in pairs(states) do
        if state.formatted or state.tinted then
            if Safe(uf) then
                Restore(state, uf.name)
            else
                Names.pendingRestore = true
            end
        end
    end
end

function Names.FlushRestores()
    if Names.pendingRestore then RestoreInactive() end
end

-- A side owns the native name only when its look formats or colors it.
local function Owning(look)
    if look.enabled or look.customColor or look.shared ~= nil then return look end
end

-- A side that stopped owning gives back what it wrote and loses its unit
-- mapping, so the native hook leaves at the mapping test. A restore blocked
-- by protection keeps the owned values and the unit for the pending-plate
-- replay (Apply restores and unmaps it then); the hook's side test keeps
-- that state untouched meanwhile.
local function ReleaseDormant()
    for uf, state in pairs(states) do
        local prefix = state.prefix
        if prefix and not looks[prefix] then
            if (state.formatted or state.tinted) and Safe(uf) then Restore(state, uf.name) end
            state.look = nil
            if not state.formatted and not state.tinted then state.unit, state.prefix = nil, nil end
        end
    end
end

function Names.Configure(config)
    Names.threatNames = private.EasyFeatures and config.look ~= 2 and config.threatNameColor == true
    local enemy, friendly = Text.Compile(config, "enemy"), Text.Compile(config, "friendly")
    looks = { enemy = Owning(enemy), friendly = Owning(friendly) }
    Names.inUse = looks.enemy ~= nil or looks.friendly ~= nil
    if not Names.inUse then
        RestoreInactive()
    elseif not looks.enemy or not looks.friendly then
        ReleaseDormant()
    end
    if (Names.inUse or Names.threatNames) and not hooked then
        hooked = true
        hooksecurefunc("CompactUnitFrame_UpdateName", OnNativeName)
    end
    if Names.threatNames and not threatHooked then
        threatHooked = true
        hooksecurefunc("CompactUnitFrame_UpdateName", private.EasyFeatures.NativeName)
    end
end

function Names.Apply(uf, prefix, unit)
    local state = states[uf]
    local look = prefix and looks and looks[prefix]
    local enabled = Names.inUse and look and unit and M.config[prefix]
    -- Other skin events do no native text/color work on an unchanged look.
    if enabled and state and state.unit == unit and state.look == look then return end
    if not enabled and (not state or not state.formatted and not state.tinted) then return end
    local label = Safe(uf)
    if not label then return end
    if not enabled then
        Restore(state, label)
        state.look = nil
        -- A dormant side's replayed restore ends its unit mapping.
        if Names.inUse and prefix and not look then state.unit, state.prefix = nil, nil end
        return
    end
    if uf.UpdateNameOverride then return end
    local shown = label:IsShown()
    if IsSecret(shown) or not shown then return end
    if not state then state = {} states[uf] = state end
    if state.unit ~= unit then Clear(state) end
    state.unit, state.prefix = unit, prefix
    local current = label:GetText()
    if IsSecret(current) then
        ForgetPlain(state)
        state.look = look
        return
    end
    if state.nativeDirty or state.raw == nil or current ~= state.output and current ~= state.raw then
        Capture(state, label, current)
    end
    Paint(state, label, look)
end

function Names.Begin(uf)
    local state = states[uf]
    if state then Clear(state) end
end

function Names.Invalidate(uf)
    local state = states[uf]
    if state then state.look = nil end
end

function Names.Suspend(uf)
    local state = states[uf]
    if not state then return end
    state.unit = nil
    if not state.formatted and not state.tinted then return end
    if Safe(uf) then Restore(state, uf.name) else Names.pendingRestore = true end
end

function Names.Release(uf)
    local state = states[uf]
    if not state then return end
    if (state.formatted or state.tinted) and Safe(uf) then Restore(state, uf.name) end
    -- Removal retires identity even when combat/forbidden state blocks restore.
    -- Reusing the same unit token must capture the next native occupant.
    Clear(state)
end
