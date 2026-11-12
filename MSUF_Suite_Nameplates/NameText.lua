local _, private = ...
local NS, S = private.NS, private.Suite
local Text = NS.NameplateText
local Names = { states = setmetatable({}, { __mode = "k" }), inUse = false }
private.NameText = Names
local M, looks, hooked

function Names.Bind(module) M = module end

local function Safe(uf)
    if not uf or NS.Safety.IsForbidden(uf) then return false, "forbidden" end
    local label = uf.name
    if not label or NS.Safety.IsForbidden(label) then return false, "forbidden" end
    if NS.IsCombatLocked() and (uf:IsProtected() or label:IsProtected()) then
        M.pendingPlates[uf] = true
        return false, "protected"
    end
    return true
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

local function Capture(state, label)
    local raw = label:GetText()
    if not S.Public(raw) then
        ForgetPlain(state)
        return false
    end
    state.raw, state.captured = raw, true
    local r, g, b, a = label:GetTextColor()
    if S.Finite(r) and S.Finite(g) and S.Finite(b) and S.Finite(a) then
        state.r, state.g, state.b, state.a = r, g, b, a
    else
        state.r, state.g, state.b, state.a = nil, nil, nil, nil
    end
    state.formatted, state.tinted, state.nativeDirty = nil, nil, nil
    return true
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

-- Hidden and override calls can return without a native write. Only a shown
-- ordinary update can replace the saved baseline with fresh native values.
local function OnNativeName(uf)
    if not M.active or not Names.inUse then return end
    local state = Names.states[uf]
    if not state or not state.unit then return end
    local prefix, unit = state.prefix, state.unit
    if not M.config[prefix] or M.activeUnits[unit] ~= uf then return end
    local safe, reason = Safe(uf)
    if not safe then
        state.look = nil
        if reason == "protected" and not uf.UpdateNameOverride and uf.name:IsShown() then state.nativeDirty = true end
        return
    end
    if uf.UpdateNameOverride or not uf.name:IsShown() then return end
    if Capture(state, uf.name) then
        Paint(state, uf.name, looks[prefix])
    else
        state.look = looks[prefix]
    end
end

local function RestoreInactive()
    Names.pendingRestore = false
    for uf, state in pairs(Names.states) do
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

function Names.Configure(config)
    looks = { enemy = Text.Compile(config, "enemy"), friendly = Text.Compile(config, "friendly") }
    Names.inUse = looks.enemy.enabled or looks.friendly.enabled or looks.enemy.customColor or looks.friendly.customColor
        or looks.enemy.shared ~= nil or looks.friendly.shared ~= nil
    if not Names.inUse then RestoreInactive() end
    if Names.inUse and not hooked then
        hooked = true
        hooksecurefunc("CompactUnitFrame_UpdateName", OnNativeName)
    end
end

function Names.Apply(uf, prefix, unit)
    local state = Names.states[uf]
    local look = prefix and looks and looks[prefix]
    local enabled = Names.inUse and look and unit and M.config[prefix]
    -- Other skin events do no native text/color work on an unchanged look.
    if enabled and state and state.unit == unit and state.look == look then return end
    if not enabled and (not state or not state.formatted and not state.tinted) then return end
    if not Safe(uf) then return end
    if not enabled then
        Restore(state, uf.name)
        state.look = nil
        return
    end
    if uf.UpdateNameOverride or not uf.name:IsShown() then return end
    if not state then state = {} Names.states[uf] = state end
    if state.unit ~= unit then Clear(state) end
    state.unit, state.prefix = unit, prefix
    local current = uf.name:GetText()
    if not S.Public(current) then
        ForgetPlain(state)
        state.look = look
        return
    end
    if (state.nativeDirty or state.raw == nil or current ~= state.output and current ~= state.raw) and not Capture(state, uf.name) then
        state.look = look
        return
    end
    Paint(state, uf.name, look)
end

function Names.Begin(uf)
    local state = Names.states[uf]
    if state then Clear(state) end
end

function Names.Invalidate(uf)
    local state = Names.states[uf]
    if state then state.look = nil end
end

function Names.Release(uf)
    local state = Names.states[uf]
    if not state then return end
    if (state.formatted or state.tinted) and Safe(uf) then Restore(state, uf.name) end
    -- Removal retires identity even when combat/forbidden state blocks restore.
    -- Reusing the same unit token must capture the next native occupant.
    Clear(state)
end
