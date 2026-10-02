local _, Private = ...
local NS, S = Private.NS, Private.Suite
local Dispatch = NS.Dispatch

-- Deferred work of a module, owned by its context (Runtime.lua). Release
-- cancels all of it, so a stopped module never runs a late callback.
--   ctx:After(delay, fn)          fn(module) once, delay seconds from now and
--                                 never earlier: GetTime() has reached the
--                                 deadline when fn runs. A new call moves the
--                                 deadline (a restart).
--   ctx:Coalesce(delay, fn, keys) a job: job:Request() asks for one run of
--                                 fn(module, keys) delay seconds after the
--                                 first request; later requests ride along.
--                                 job:Add(key) also marks keys[key] = true;
--                                 fn consumes the keys.
--   ctx:Ticker(interval, fn)      fn(module) every interval seconds.
--   ctx:Cancel(fn)                drops fn's pending run or stops its ticker.
-- Each returns a handle, one per fn and context, reused by every call: fn must
-- be a function made once, never a closure made per call. handle:Cancel()
-- drops the pending run; handle:Pending() (job, deadline) and
-- handle:Running() (ticker) tell whether one is due. A module keeps a handle
-- only to ask it something (a job's Request, Add or Pending, a ticker's
-- Running) and cancels it through that handle; every other wait is cancelled
-- through its function (ctx:Cancel(fn)). A job is also an event
-- callback: ctx:Event(event, job) requests it on every event at the cost of
-- a pending check. A per-event path with work of its own may read
-- job.pending and skip the Request call while a run is due already.
-- Callbacks run isolated (Dispatch) and only while the module is active. They
-- run in combat too: work that needs the lockdown over checks it itself.
--
-- C_Timer.After cannot be cancelled. Every wait therefore hands C_Timer a
-- tick of its own; a tick that was replaced finds itself stale and does
-- nothing. Steady use allocates nothing, and so does a cancel followed by a
-- restart: a cancelled deadline keeps its tick in flight for the next start,
-- and a cancelled job serves its next request with its second tick. A tick
-- is made again only when a restart moves a deadline before its tick or a
-- cancel finds both of a job's ticks in flight.
local Context = Private.Context

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

-- The module a context belongs to stays the same for the context's lifetime
-- (S.Install), so each handle keeps it.
local function OwnerOf(ctx)
    return assert(S.instances[ctx.id], "context timers need an installed module")
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
    if self.armed and self.firesAt <= due then return end
    Abandon(self)
    self.firesAt = due
    Arm(self, delay)
end

function Deadline:Fire()
    local due = self.due
    if not due then return end
    -- A tick ahead of the deadline (a restart moved it, or C_Timer's clock
    -- ran a hair ahead of GetTime) waits for the rest.
    local left = due - GetTime()
    if left > 0 then
        self.firesAt = due
        Arm(self, left)
        return
    end
    self.due = nil
    self:Run()
end

-- A tick in flight stays armed: it finds no deadline and does nothing,
-- unless a later Start reuses it.
function Deadline:Cancel()
    self.due = nil
end

function Deadline:Pending()
    return self.due ~= nil
end

local After = setmetatable({}, { __index = Deadline })
After.__index = After

function After:Run()
    local module = self.module
    if module.active then Dispatch(self.fn, module) end
end

------------------------------------------------------------------ coalesced jobs
local Job = {}
Job.__index = Job

-- A job's tick runs the job itself: the per-window path stays one call. A
-- stale tick that was the job's second one frees it (Job:Cancel).
local function NewJobTick(job)
    local tick
    tick = function()
        local self = job
        if self.tick ~= tick then
            if self.spare == tick then self.spareBusy = false end
            return
        end
        self.armed = false
        if not self.pending then return end
        self.pending = false
        local module = self.module
        if module.active then Dispatch(self.fn, module, self.keys) end
    end
    job.tick = tick
    return tick
end

-- Per-event code calls this: the wait is armed inline.
function Job:Request()
    if self.pending then return end
    self.pending = true
    if self.armed then return end
    self.armed = true
    C_Timer.After(self.delay, self.tick or NewJobTick(self))
end

function Job:Add(key)
    self.keys[key] = true
    self:Request()
end

-- Forgets the request; a wait in flight finds nothing to do, and a request
-- made before it fires rides on it.
function Job:Clear()
    self.pending = false
end

-- Forgets the request and makes a wait in flight stale: the next request
-- waits the full delay. The stale tick becomes the job's second one; the
-- earlier second tick, once its own wait is over, serves the next request.
function Job:Cancel()
    self.pending = false
    if not self.armed then return end
    self.armed = false
    local stale = self.tick
    self.tick = not self.spareBusy and self.spare or nil
    self.spare, self.spareBusy = stale, true
end

function Job:Pending()
    return self.pending == true
end

-- As an event callback (ctx:Event(event, job)) a job takes the request.
-- Dispatch is securecallfunction, which takes a function, not a callable
-- table: Context:Event registers this one, made once per job.
function Job:EventFunction()
    local fn = self.eventFunction
    if not fn then
        local job = self
        fn = function()
            if job.pending then return end
            job:Request()
        end
        self.eventFunction = fn
    end
    return fn
end

------------------------------------------------------------------ tickers
local Ticker = {}
Ticker.__index = Ticker

function Ticker:Start()
    if self.ticker then return end
    if not self.tick then
        self.tick = function()
            local module = self.module
            if module.active then Dispatch(self.fn, module) end
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
        handle = setmetatable({ ctx = ctx, fn = fn, kind = class, module = OwnerOf(ctx) }, class)
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
