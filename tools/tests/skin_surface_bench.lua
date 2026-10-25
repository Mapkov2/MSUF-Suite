-- Shared A4 measurement driver. VM/KB and native shim counts use separate
-- passes so debug.getinfo allocations cannot contaminate the stopped-GC pass.
local B = {}
function B.Measure(label, callback, native, prepare, setNativePass)
    setNativePass(false)
    if prepare then prepare() end
    collectgarbage("collect")
    collectgarbage("stop")
    local instructions = 0
    local function Count() instructions = instructions + 1 end
    local before = collectgarbage("count")
    debug.sethook(Count, "", 1)
    callback()
    debug.sethook()
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    setNativePass(true)
    if prepare then prepare() end
    local calls = 0
    local function Calls(event)
        if event == "call" and native[debug.getinfo(2, "f").func] then calls = calls + 1 end
    end
    debug.sethook(Calls, "c")
    callback()
    debug.sethook()
    setNativePass(false)
    print(string.format("BUDGET %s vm=%d kb=%.3f native=%d", label, instructions, kb, calls))
    return instructions, kb, calls
end
function B.Methods(target, out)
    for key, value in pairs(target) do
        if type(value) == "function" and key ~= "Fire" then out[value] = true end
    end
end
function B.Limit(value, maximum, label)
    if not os.getenv("SUITE_A4_MEASURE_ONLY") then assert(value <= maximum, label .. " budget exceeded") end
end
return B
