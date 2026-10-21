-- Full graph semantics plus the cost of copying a representative stored profile tree.
-- Frozen pre-optimization algorithm is the cost reference, not a source-text match.
-- Cold trade: a table root adds one helper call; primitive roots stay unchanged.
local root = assert(arg[1])
local provider = arg[2] or root .. "/MSUF_Suite/Core/Database.lua"
local owner = {}
local env = setmetatable({}, { __index = _G })
setfenv(assert(loadfile(provider)), env)("MSUF_Suite", owner)
local copy = assert(owner.CopyValue)
local function Reference(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[Reference(key, seen)] = Reference(item, seen) end
    return result
end
setfenv(Reference, env)
local function Semantics(fn)
    local callback = function() end
    assert(fn(nil) == nil and fn(false) == false and fn(0) == 0 and fn("text") == "text" and fn(callback) == callback)
    assert(next(fn({})) == nil and fn({}, false) ~= nil)
    local key, child = {}, { zero = 0, disabled = false, label = "Größe 中文", callback = callback }
    local graph = { first = child, second = child, key = key, [key] = key }
    graph.self, child.parent = graph, graph
    local result = fn(graph)
    assert(result ~= graph and result.self == result and result.first ~= child)
    assert(result.first == result.second and result.first.parent == result)
    assert(result.first.zero == 0 and result.first.disabled == false and result.first.callback == callback)
    assert(result.key ~= key and result[result.key] == result.key and result[key] == nil)
    result.first.zero = 17
    assert(child.zero == 0)
    local existing, mapped = {}, {}
    assert(fn(graph, { [graph] = existing }) == existing)
    result = fn(graph, { [child] = mapped })
    assert(result.first == mapped and result.second == mapped)
    local hostile = setmetatable({ stored = 1 }, { __index = function() error("metatable read") end })
    result = fn(hostile)
    assert(result.stored == 1 and getmetatable(result) == nil)
end
Semantics(Reference)
Semantics(copy)
local profiles = {}
for profile = 1, 11 do
    local modules = {}
    profiles["Profile" .. profile] = { suite = { schema = 1, modules = modules } }
    for module = 1, 16 do
        local settings = { enabled = false, size = 0, label = "setting" }
        modules["Module" .. module] = settings
        for setting = 1, 24 do settings["Value" .. setting] = setting end
    end
end
local function Cost(fn)
    local instructions, allocated = math.huge, math.huge
    for _ = 1, 2 do
        fn(profiles)
        collectgarbage("collect")
        collectgarbage("stop")
        local before, ticks = collectgarbage("count"), 0
        debug.sethook(function() ticks = ticks + 1 end, "", 100)
        local result = fn(profiles)
        debug.sethook()
        local delta = collectgarbage("count") - before
        collectgarbage("restart")
        assert(result.Profile1 ~= profiles.Profile1 and result.Profile11 ~= profiles.Profile11)
        instructions, allocated = math.min(instructions, ticks * 100), math.min(allocated, delta)
    end
    return instructions, allocated
end
local function Natives(fn)
    local types, pairsCalls = 0, 0
    env.type = function(value) types = types + 1; return type(value) end
    env.pairs = function(value) pairsCalls = pairsCalls + 1; return pairs(value) end
    fn(profiles)
    env.type, env.pairs = nil, nil
    return types, pairsCalls
end
local ri, ra = Cost(Reference)
local ci, ca = Cost(copy)
local rt, rp = Natives(Reference)
local ct, cp = Natives(copy)
assert(rt == ct and rp == cp, "native type/pairs work increased or traversal changed")
assert(ca <= ra * 1.02, "profile-copy allocation regression above 2 percent")
assert(ci <= ri * .95, "profile-copy VM reduction below 5 percent")
print(string.format("Suite copy startup: VM %d -> %d, KB %.3f -> %.3f; type %d/pairs %d unchanged; full graph semantics passed",
    ri, ci, ra, ca, ct, cp))
