local _, NS = ...

local Registry = {
    surfaces = setmetatable({}, { __mode = "k" }),
    surfaceTokens = setmetatable({}, { __mode = "k" }),
    tokenConsumers = {},
    listeners = setmetatable({}, { __mode = "k" }),
}
NS.Registry = Registry

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

function Registry.GetSurface(target)
    return Registry.surfaces[target]
end

function Registry.RegisterSurface(target, state, tokens)
    Registry.surfaces[target] = state

    -- Reuse the target's membership set. A repeated attach refreshes the full
    -- spec, but must not tear down identical token subscriptions or allocate
    -- a new hash table. False marks old memberships until this pass confirms them.
    local bound = Registry.surfaceTokens[target]
    if not bound then
        bound = {}
        Registry.surfaceTokens[target] = bound
    end
    for token in pairs(bound) do
        bound[token] = false
    end
    for index = 1, tokens and #tokens or 0 do
        local token = tokens[index]
        if bound[token] == nil then
            local consumers = Registry.tokenConsumers[token]
            if not consumers then
                consumers = WeakSet()
                Registry.tokenConsumers[token] = consumers
            end
            consumers[target] = true
        end
        bound[token] = true
    end
    for token, retained in pairs(bound) do
        if not retained then
            local consumers = Registry.tokenConsumers[token]
            if consumers then consumers[target] = nil end
            bound[token] = nil
        end
    end
end

local function RefreshTarget(target)
    local state = Registry.surfaces[target]
    if state and type(state.refresh) == "function" then
        state.refresh(state)
    end
end

function Registry.RefreshToken(token)
    if NS.IsCombatLocked() then
        return false
    end
    local consumers = Registry.tokenConsumers[token]
    if not consumers then
        return true
    end
    for target in pairs(consumers) do
        RefreshTarget(target)
    end
    return true
end

function Registry.RefreshAll()
    if NS.IsCombatLocked() then
        return false
    end
    for target in pairs(Registry.surfaces) do
        RefreshTarget(target)
    end
    return true
end

------------------------------------------------------------------ coalescing
-- Settings writes arrive once per slider tick or color-picker move, often
-- several per frame. Their surface refreshes and the full passes listeners
-- queue here run once on the next frame, in the order they were first asked
-- for, and after combat when combat started in between.
local queuedTokens = {}
local queuedAll = false
local queuedJobs = {}
local jobOrder = {}
local jobCount = 0
local flushScheduled = false
local flushing = false

local function HasQueuedWork()
    return queuedAll or next(queuedTokens) ~= nil or jobCount > 0
end

local function RefreshQueuedSurfaces()
    local dispatch = NS.Safety.Dispatch
    if queuedAll then
        queuedAll = false
        for token in pairs(queuedTokens) do queuedTokens[token] = nil end
        dispatch(Registry.RefreshAll)
        return
    end
    for token in pairs(queuedTokens) do
        queuedTokens[token] = nil
        dispatch(Registry.RefreshToken, token)
    end
end

-- Each job is its own boundary; jobs queued while these run join the loop.
local function RunQueuedJobs()
    local dispatch = NS.Safety.Dispatch
    local index = 1
    while index <= jobCount do
        local job = jobOrder[index]
        jobOrder[index] = nil
        queuedJobs[job] = nil
        dispatch(job)
        index = index + 1
    end
    jobCount = 0
end

local function Flush()
    flushScheduled = false
    if flushing then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("registry:queued", Flush)
        return
    end
    flushing = true
    repeat
        RefreshQueuedSurfaces()
        RunQueuedJobs()
    until not HasQueuedWork()
    flushing = false
end

local function ScheduleFlush()
    if flushScheduled or flushing then return end
    flushScheduled = true
    C_Timer.After(0, Flush)
end

-- Refreshes the surfaces that use `token` (every surface when token is nil)
-- once on the next frame.
function Registry.QueueRefresh(token)
    if token == nil then
        queuedAll = true
    else
        queuedTokens[token] = true
    end
    ScheduleFlush()
end

-- Runs job() once on the next frame, however often it is queued before.
function Registry.QueueJob(job)
    if not queuedJobs[job] then
        queuedJobs[job] = true
        jobCount = jobCount + 1
        jobOrder[jobCount] = job
    end
    ScheduleFlush()
end

function Registry.AddListener(owner, callback)
    if type(owner) == "table" and type(callback) == "function" then
        Registry.listeners[owner] = callback
    end
end

function Registry.RemoveListener(owner)
    Registry.listeners[owner] = nil
end

function Registry.NotifyListeners(domain, key)
    if NS.IsCombatLocked() then
        return false
    end
    -- Other addons can listen through the public API; one failing listener
    -- is reported and does not stop the rest (see Safety.Dispatch).
    local dispatch = NS.Safety.Dispatch
    for owner, callback in pairs(Registry.listeners) do
        dispatch(callback, owner, domain, key)
    end
    return true
end

-- Watchers queue a repaint job (once per frame, see QueueJob) after the
-- settings writes it depends on: a key listed in keysByDomain[domain], any
-- theme write except the gradient switch, and a profile switch.
local watchers = {}

local function OnWatchedSetting(watcher, domain, key)
    local keys = watcher.keysByDomain[domain]
    if keys and keys[key]
        or domain == "theme" and key ~= "gradient"
        or domain == "profile" then
        Registry.QueueJob(watcher.job)
    end
end

-- Watching the same job again is a no-op.
function Registry.WatchSettings(job, keysByDomain)
    if watchers[job] then return end
    local watcher = { job = job, keysByDomain = keysByDomain }
    watchers[job] = watcher
    Registry.AddListener(watcher, OnWatchedSetting)
end
