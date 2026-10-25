-- Measure real code in the existing contract worlds. Native calls are counted
-- in a separate pass: debug.getinfo allocates and must not pollute the KB pass.
local B = {}
function B.Measure(label, callback, native, prepare)
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
    local calls = 0
    local function Calls(event)
        if event == "call" and native[debug.getinfo(2, "f").func] then calls = calls + 1 end
    end
    if prepare then prepare() end
    debug.sethook(Calls, "c")
    callback()
    debug.sethook()
    print(string.format("BUDGET %s vm=%d kb=%.3f native=%d", label, instructions, kb, calls))
    return instructions, kb, calls
end
function B.Methods(target, out)
    out = out or {}
    for _, value in pairs(target) do if type(value) == "function" then out[value] = true end end
    local meta = getmetatable(target)
    if meta and type(meta.__index) == "table" then B.Methods(meta.__index, out) end
    return out
end
function B.Limit(value, maximum, label)
    if not os.getenv("SUITE_A1_MEASURE_ONLY") then assert(value <= maximum, label .. " budget exceeded") end
end
return B
