local _, NS = ...

-- Runs visual work now, or once after combat. A job is keyed, so a newer
-- request for the same target replaces the older one. Deferred jobs run in
-- the order of their latest request: when combat deferred an attach and then
-- a hide of the same surface (or the other way round), the later request is
-- also the one that wins after combat.
local CombatGate = {
    pending = {},
    -- Keys in request order; a key asked for again moves to the end, and
    -- its earlier slot stays behind as a stale entry (positions tells).
    order = {},
    positions = {},
    count = 0,
}
NS.CombatGate = CombatGate

local eventFrame = CreateFrame("Frame")

-- Drops stale slots once they outnumber the live jobs, so a key that is
-- asked for on every update during a long fight keeps the list short.
local function Compact()
    local order, positions, pending = CombatGate.order, CombatGate.positions, CombatGate.pending
    local kept = 0
    for index = 1, #order do
        local key = order[index]
        if pending[key] ~= nil and positions[key] == index then
            kept = kept + 1
            order[kept] = key
            positions[key] = kept
        end
    end
    for index = #order, kept + 1, -1 do order[index] = nil end
end

local function Clear()
    local order, positions = CombatGate.order, CombatGate.positions
    for index = #order, 1, -1 do order[index] = nil end
    for key in pairs(positions) do positions[key] = nil end
    CombatGate.count = 0
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

-- A drain runs jobs for about DRAIN_BUDGET_MS per frame (debugprofilestop,
-- milliseconds; at least one job) and goes on with the rest on the next
-- frame, in the same order: a safety net (raid trace 2026-10-11: one
-- combat-end drain took 23.7 ms in one frame). Combat before then holds the
-- rest until it ends. A job leaves the queue before it runs: none runs twice.
local DRAIN_BUDGET_MS = 4
local draining, resumeQueued = false, false
local ResumeDrain

-- Each deferred job is its own boundary: a job that raises is reported and
-- the remaining jobs still run in the same drain. budget nil: no limit.
local function Drain(budget)
    if NS.IsCombatLocked() then
        return
    end
    local pending, order, positions = CombatGate.pending, CombatGate.order, CombatGate.positions
    local dispatch = NS.Safety.Dispatch
    local started = budget and CombatGate.count > 1 and debugprofilestop() or nil
    local index = 1
    draining = true
    while index <= #order do
        local key = order[index]
        local callback = positions[key] == index and pending[key]
        if callback then
            pending[key], positions[key] = nil, nil
            CombatGate.count = CombatGate.count - 1
            dispatch(callback)
            if started and CombatGate.count > 0 and debugprofilestop() - started >= budget then
                draining = false
                if not resumeQueued then
                    resumeQueued = true
                    C_Timer.After(0, ResumeDrain)
                end
                return
            end
        end
        index = index + 1
    end
    draining = false
    Clear()
end

local function DrainPending()
    Drain(DRAIN_BUDGET_MS)
end

ResumeDrain = function()
    resumeQueued = false
    DrainPending()
end

eventFrame:SetScript("OnEvent", DrainPending)

function CombatGate.RunOrDefer(key, callback)
    if type(callback) ~= "function" then
        return false, "invalid callback"
    end
    if not NS.IsCombatLocked() then
        -- Jobs a budgeted drain left for the next frame were asked for
        -- before this request: they run first, without the budget.
        if resumeQueued and not draining and CombatGate.count > 0 then Drain(nil) end
        callback()
        return true
    end

    key = tostring(key or callback)
    local order, positions = CombatGate.order, CombatGate.positions
    if CombatGate.pending[key] == nil then
        if CombatGate.count == 0 then eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
        CombatGate.count = CombatGate.count + 1
    end
    CombatGate.pending[key] = callback
    if positions[key] ~= #order or order[#order] ~= key then
        order[#order + 1] = key
        positions[key] = #order
        if #order > CombatGate.count * 2 + 16 then Compact() end
    end
    return false, "combat"
end

function CombatGate.IsPending(key)
    return CombatGate.pending[tostring(key)] ~= nil
end

function CombatGate.Cancel(key)
    key = tostring(key)
    if CombatGate.pending[key] ~= nil then
        CombatGate.pending[key] = nil
        CombatGate.positions[key] = nil
        CombatGate.count = math.max(0, CombatGate.count - 1)
        if CombatGate.count == 0 then Clear() end
    end
end

function CombatGate.GetPendingCount()
    return CombatGate.count
end
