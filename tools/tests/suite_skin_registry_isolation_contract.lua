local root=assert(arg[1],"repository root required")
local run=assert(loadfile(root.."/tools/tests/skin_registry_cases.lua"))()
for _,mode in ipairs({"full","token"}) do for fault=0,3 do run(root,mode,fault) end end
run(root,"combat",0)

local pending, order, ticks, combat, deferred = nil, {}, 0, false, {}
local NS = {
    Safety = { Dispatch = function(fn, ...) return fn(...) end },
    IsCombatLocked = function() return combat end,
    CombatGate = {
        RunOrDefer = function(key, fn) deferred[key] = fn end,
        Cancel = function(key) deferred[key] = nil end,
    },
}
local function Timer(_, fn)
    assert(not pending, "duplicate registry flush")
    local handle = { callback = fn }
    pending = handle
    function handle:Cancel() assert(pending == self) pending = nil end
    return handle
end
C_Timer = {
    After = function(delay, callback) Timer(delay, function() callback() end) end,
    NewTimer = Timer,
}
local registryFile = os.getenv("SUITE_SKIN_REGISTRY_OVERRIDE") or root .. "/MSUF_Suite_Skin/Core/Registry.lua"
assert(loadfile(registryFile))("MSUF_Suite_Skin", NS)
local registry = NS.Registry
local function B() order[#order + 1] = "B" end
local function C() order[#order + 1] = "C" end
local function D() order[#order + 1] = "D" end
local function A()
    order[#order + 1] = "A"
    registry.CancelJob(C)
    registry.QueueJob(B)
    registry.QueueJob(D)
end
local function Flush()
    if pending then
        local timer = pending
        pending, ticks = nil, ticks + 1
        timer.callback(timer)
    end
    assert(not pending, "a canceled or in-flight job scheduled another flush")
end
registry.QueueJob(A)
registry.QueueJob(B)
registry.QueueJob(C)
registry.CancelJob(B)
Flush()
assert(table.concat(order) == "ABD", "cancel/requeue lost an unrelated job, order, or deduplication")
registry.QueueJob(C)
registry.CancelJob(C)
local before = ticks
Flush()
assert(ticks == before, "last cancel still invoked a next-frame registry callback")
assert(table.concat(order) == "ABD", "canceled last job was dispatched")

local paints = 0
registry.RegisterSurface({}, { refresh = function() paints = paints + 1 end }, { "palette" })
registry.QueueJob(C)
registry.QueueRefresh("palette")
registry.CancelJob(C)
Flush()
assert(ticks == before + 1 and paints == 1, "last canceled job lost an unrelated token")

combat = true
registry.QueueJob(C)
Flush()
assert(deferred["registry:queued"], "combat did not hold the registry burst")
registry.QueueJob(B)
assert(not pending, "combat queued a second native timer")
registry.CancelJob(C)
assert(deferred["registry:queued"], "cancel lost another combat job")
registry.CancelJob(B)
assert(not deferred["registry:queued"] and not pending, "last combat cancel left a regen replay")
registry.QueueJob(D)
Flush()
combat = false
local resume = assert(deferred["registry:queued"])
deferred["registry:queued"] = nil
resume()
assert(table.concat(order) == "ABDD" and not pending, "regen failed to replay new work exactly once")
print("Skin registry: independent isolation, combat and cancellation cases passed")
