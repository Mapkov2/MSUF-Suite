local _, owner = ...
local NS = owner.AppearancePrimitives or owner

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

local eventFrame
local combatStarted = false

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
    combatStarted = false
    eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

-- A drain runs jobs for about DRAIN_BUDGET_MS per frame (debugprofilestop,
-- milliseconds; at least one job) and goes on with the rest on the next
-- frame, in the same order: a safety net (raid trace 2026-10-11: one
-- combat-end drain took 23.7 ms in one frame). Combat before then holds the
-- rest until it ends. A job leaves the queue before it runs: none runs twice.
local DRAIN_BUDGET_MS = 4
local FIRST_SETTLE_DELAY, MAX_SETTLE_DELAY = 0.05, 0.25
local draining, resumeQueued, settleDelay = false, false, 0
local ResumeDrain

local function ScheduleDrain(delay)
    if resumeQueued then return end
    resumeQueued = true
    C_Timer.After(delay or 0, ResumeDrain)
end

-- Each deferred job is its own boundary: a job that raises is reported and
-- the remaining jobs still run in the same drain. budget nil: no limit.
local function Drain(budget)
    if combatStarted or NS.IsCombatLocked() then return false end
    settleDelay = 0
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
                ScheduleDrain()
                return true
            end
        end
        index = index + 1
    end
    draining = false
    Clear()
    return true
end

ResumeDrain = function()
    resumeQueued = false
    if CombatGate.count == 0 or Drain(DRAIN_BUDGET_MS) then return end
    if combatStarted or InCombatLockdown() then return end
    -- The unit flag can outlast the regen event and the next frame.
    -- Probe only while work remains, backing off until the flag settles.
    settleDelay = math.min(MAX_SETTLE_DELAY, math.max(FIRST_SETTLE_DELAY, settleDelay * 2))
    ScheduleDrain(settleDelay)
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        combatStarted = true
        return
    end
    combatStarted, settleDelay = false, 0
    if not Drain(DRAIN_BUDGET_MS) then ScheduleDrain() end
end

-- The shared addon does not need an event frame before a cosmetic consumer loads.
function CombatGate.Initialize()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    end
    return CombatGate
end

if not owner.AppearancePrimitives then CombatGate.Initialize() end

function CombatGate.RunOrDefer(key, callback)
    if type(callback) ~= "function" then
        return false, "invalid callback"
    end
    if not combatStarted and not NS.IsCombatLocked() then
        if CombatGate.count > 0 then
            -- Preserve the scheduled drain's order. If there is no such
            -- drain, do not let a queued callback replay after this request.
            if resumeQueued and not draining then
                Drain(nil)
            else
                CombatGate.Cancel(key or callback)
                if not draining and CombatGate.count > 0 then ScheduleDrain() end
            end
        end
        callback()
        return true
    end

    key = tostring(key or callback)
    local order, positions = CombatGate.order, CombatGate.positions
    if CombatGate.pending[key] == nil then
        if CombatGate.count == 0 then
            settleDelay = 0
            eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            -- A job can arrive after the regen dispatch already passed us.
            if not InCombatLockdown() then ScheduleDrain() end
        end
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
