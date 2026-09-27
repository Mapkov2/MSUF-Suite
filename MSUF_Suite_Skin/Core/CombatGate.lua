local _, NS = ...

-- Runs visual work now, or once after combat. A job is keyed, so a newer
-- request for the same target replaces the older one.
local CombatGate = {
    pending = {},
    count = 0,
}
NS.CombatGate = CombatGate

local eventFrame = CreateFrame("Frame")

-- Each deferred job is its own boundary: a job that raises is reported and
-- the remaining jobs still run in the same drain.
local function DrainPending()
    if NS.IsCombatLocked() then
        return
    end
    local pending = CombatGate.pending
    local dispatch = NS.Safety.Dispatch
    local key, callback = next(pending)
    while key ~= nil do
        pending[key] = nil
        CombatGate.count = CombatGate.count - 1
        dispatch(callback)
        key, callback = next(pending)
    end
    CombatGate.count = 0
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

eventFrame:SetScript("OnEvent", DrainPending)

function CombatGate.RunOrDefer(key, callback)
    if type(callback) ~= "function" then
        return false, "invalid callback"
    end
    if not NS.IsCombatLocked() then
        callback()
        return true
    end

    key = tostring(key or callback)
    if CombatGate.pending[key] == nil then
        if CombatGate.count == 0 then eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
        CombatGate.count = CombatGate.count + 1
    end
    CombatGate.pending[key] = callback
    return false, "combat"
end

function CombatGate.Cancel(key)
    key = tostring(key)
    if CombatGate.pending[key] ~= nil then
        CombatGate.pending[key] = nil
        CombatGate.count = math.max(0, CombatGate.count - 1)
        if CombatGate.count == 0 then eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    end
end

function CombatGate.GetPendingCount()
    return CombatGate.count
end
