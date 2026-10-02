local _, Private = ...
local NS, S = Private.NS, Private.Suite
local Dispatch = NS.Dispatch

-- Deferred work of a module, owned by its context (Runtime.lua). Release
-- cancels all of it, so a stopped module never runs a late callback.
--   ctx:After(delay, fn)          fn(module) once, delay seconds from now. A
--                                 new call moves the deadline (a restart).
--   ctx:Coalesce(delay, fn, keys) a job: job:Request(key) asks for one run of
--                                 fn(module, keys) delay seconds after the
--                                 first request; later requests ride along
--                                 (keys[key] = true) and fn consumes the keys.
--   ctx:Ticker(interval, fn)      fn(module) every interval seconds.
--   ctx:Cancel(fn)                drops fn's pending run or stops its ticker.
-- Each returns a handle, one per fn and context, reused by every call: fn must
-- be a function made once, never a closure made per call. handle:Cancel()
-- drops the pending run; handle:Pending() (job, deadline) and
-- handle:Running() (ticker) tell whether one is due. A per-event path may
-- read job.pending and skip the Request call while a run is due already.
-- Callbacks run isolated (Dispatch) and only while the module is active. They
-- run in combat too: work that needs the lockdown over checks it itself.
--
-- C_Timer.After cannot be cancelled. Every wait therefore hands C_Timer a
-- tick of its own; a tick that Cancel replaced finds itself stale and does
-- nothing. Steady use allocates nothing: a tick is made once and again only
-- after a cancel caught one in flight.
local Context = Private.Context

-- Deadlines closer than this run at once instead of waiting another frame.
local EPSILON = .001

------------------------------------------------------------------ ticks
local function NewTick(wait)
    local tick
    tick = function()
        if wait.tick ~= tick then return end
        wait.armed = false
        wait:Fire()
    end
    wait.tick = tick
    return tick
end

local function Arm(wait, delay)
    wait.armed = true
    C_Timer.After(delay, wait.tick or NewTick(wait))
end

-- An armed wait becomes stale: its tick still fires and does nothing.
local function Abandon(wait)
    if not wait.armed then return end
    wait.armed = false
    wait.tick = nil
end

local function Owner(wait)
    local module = S.instances[wait.ctx.id]
    return module and module.active and module or nil
end

------------------------------------------------------------------ deadlines
-- A deadline (After, S.Debounce): a restart moves `due`. While the armed
-- tick fires no later than the new deadline it stays and arms again for the
-- rest, so restarts that extend the wait allocate nothing.
local Deadline = {}
Deadline.__index = Deadline

function Deadline:Start(delay)
    local due = GetTime() + delay
    self.due = due
    if self.armed and self.firesAt <= due + EPSILON then return end
    Abandon(self)
    self.firesAt = due
    Arm(self, delay)
end

function Deadline:Fire()
    local due = self.due
    if not due then return end
    local left = due - GetTime()
    if left > EPSILON then
        self.firesAt = due
        Arm(self, left)
        return
    end
    self.due = nil
    self:Run()
end

function Deadline:Cancel()
    self.due = nil
    Abandon(self)
end

function Deadline:Pending()
    return self.due ~= nil
end

local After = setmetatable({}, { __index = Deadline })
After.__index = After

function After:Run()
    local module = Owner(self)
    if module then Dispatch(self.fn, module) end
end

------------------------------------------------------------------ coalesced jobs
local Job = {}
Job.__index = Job

function Job:Request(key)
    if key ~= nil then self.keys[key] = true end
    if self.pending then return end
    self.pending = true
    if not self.armed then Arm(self, self.delay) end
end

function Job:Fire()
    if not self.pending then return end
    self.pending = false
    local module = Owner(self)
    if module then Dispatch(self.fn, module, self.keys) end
end

-- Forgets the request; a wait in flight finds nothing to do, and a request
-- made before it fires rides on it.
function Job:Clear()
    self.pending = false
end

-- Forgets the request and makes a wait in flight stale: the next request
-- waits the full delay.
function Job:Cancel()
    self.pending = false
    Abandon(self)
end

function Job:Pending()
    return self.pending == true
end

------------------------------------------------------------------ tickers
local Ticker = {}
Ticker.__index = Ticker

function Ticker:Start()
    if self.ticker then return end
    if not self.tick then
        self.tick = function()
            local module = Owner(self)
            if module then Dispatch(self.fn, module) end
        end
    end
    self.ticker = C_Timer.NewTicker(self.interval, self.tick)
end

function Ticker:Cancel()
    if not self.ticker then return end
    self.ticker:Cancel()
    self.ticker = nil
end

function Ticker:Running()
    return self.ticker ~= nil
end

------------------------------------------------------------------ context methods
local function Handle(ctx, fn, class)
    local timers = ctx.timers
    if not timers then
        timers = {}
        ctx.timers = timers
    end
    local handle = timers[fn]
    if not handle then
        handle = setmetatable({ ctx = ctx, fn = fn, kind = class }, class)
        timers[fn] = handle
    end
    assert(handle.kind == class, "a callback serves one kind of context timer")
    return handle
end

function Context:After(delay, fn)
    local handle = Handle(self, fn, After)
    handle:Start(delay)
    return handle
end

function Context:Coalesce(delay, fn, keys)
    local handle = Handle(self, fn, Job)
    handle.delay = delay
    handle.keys = keys or handle.keys or {}
    handle.pending = handle.pending == true
    return handle
end

function Context:Ticker(interval, fn)
    local handle = Handle(self, fn, Ticker)
    if handle.ticker and handle.interval ~= interval then handle:Cancel() end
    handle.interval = interval
    handle:Start()
    return handle
end

function Context:Cancel(fn)
    local handle = self.timers and self.timers[fn]
    if handle then handle:Cancel() end
end

-- Release (Runtime.lua) drops every pending run and stops every ticker.
function Context:CancelTimers()
    if not self.timers then return end
    for _, handle in pairs(self.timers) do handle:Cancel() end
end

------------------------------------------------------------------ debounce
-- A deadline without a context, for code that has none: debounce:Request()
-- (re)starts the wait and fn() runs once, isolated, delay seconds after the
-- last request; debounce:Cancel() drops it.
local Debounce = setmetatable({}, { __index = Deadline })
Debounce.__index = Debounce

function Debounce:Run()
    Dispatch(self.fn)
end

function Debounce:Request()
    self:Start(self.delay)
end

function S.Debounce(delay, fn)
    return setmetatable({ delay = delay, fn = fn }, Debounce)
end
