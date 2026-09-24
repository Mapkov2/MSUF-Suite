local _, NS = ...

local CombatGate = {
    pending = {},
    count = 0,
}
NS.CombatGate = CombatGate

local eventFrame = CreateFrame("Frame")

local function DrainPending()
    if NS.IsCombatLocked() then
        return
    end

    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local pending = CombatGate.pending
    CombatGate.pending = {}
    CombatGate.count = 0

    for key, callback in pairs(pending) do
        local ok, message = pcall(callback)
        if not ok then
            NS.ReportError("deferred job " .. tostring(key), message)
        end
    end
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
