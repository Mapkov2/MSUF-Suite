-- Load the complete chosen module; measure only its actual query closure.
-- Lifecycle/restriction coverage remains in group_mplus_qol/hot_event_native.
local options = { iterations = 1000 }
local at = 1
if arg[1] and arg[1]:sub(1, 2) ~= "--" then
    options.root, at = arg[1]:gsub("[/\\]+$", ""), 2
end
while at <= #arg do
    local key = arg[at]
    if key == "--measure" then options.measure = true
    elseif key == "--strict" then options.strict = true
    elseif key == "--source" or key == "--baseline" or key == "--candidate"
        or key == "--budgets" or key == "--iterations" then
        at = at + 1
        options[key:sub(3)] = assert(arg[at], "missing value for " .. key)
    else error("unknown argument: " .. tostring(key)) end
    at = at + 1
end
if options.root then
    if not (options.source or options.baseline or options.candidate) then
        options.source = options.root .. "/MSUF_Suite_QualityOfLife/GroupBloodlust.lua"
    end
    options.budgets = options.budgets or options.root .. "/tools/tests/helperbloodlust_query_budgets.lua"
    if not options.measure then options.strict = true end
end
options.iterations = assert(tonumber(options.iterations), "numeric iterations required")
assert(options.iterations >= 1 and options.iterations % 1 == 0, "positive integer iterations required")
assert(options.measure ~= options.strict, "choose --measure or --strict")
local limits
if options.strict then
    limits = assert(loadfile(assert(options.budgets, "strict mode needs measured --budgets")))()
    assert(limits.measured == true, "Bloodlust budgets await actual serial measurement")
    assert(limits.iterations == options.iterations, "another measured iteration count")
end
local sources = {}
for _, name in ipairs({ "baseline", "candidate", "source" }) do
    if options[name] then sources[#sources + 1] = { name = name, path = options[name] } end
end
assert(#sources > 0, "provide --source or --baseline/--candidate paths")

local SPELLS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435 }
local function Upvalue(fn, wanted)
    for index = 1, 60 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
    end
    error("real product upvalue missing: " .. wanted)
end

local function New(path)
    local world = { present = {}, native = {}, order = {}, orderCount = 0, calls = 0, recording = false }
    local positions = {}
    for i, id in ipairs(SPELLS) do positions[id], world.native[i] = i, 0 end
    local function Query(id)
        local index = assert(positions[id], "unknown or removed lockout spell")
        world.calls = world.calls + 1
        world.native[index] = world.native[index] + 1
        if world.recording then
            world.orderCount = world.orderCount + 1
            world.order[world.orderCount] = id
        end
        local aura = world.present[id]
        if aura ~= nil then return aura end
        if world.falseMissing then return false end
    end
    world.api = Query
    local installed
    -- Query must not inspect aura fields or call a secret/render helper.
    local function Unexpected() error("query called an unrelated helper") end
    local suite = { Install = function(id, module)
        assert(id == "groupBloodlust"); installed = module
    end, Public = Unexpected, Finite = Unexpected }
    world.env = setmetatable({ C_UnitAuras = { GetPlayerAuraBySpellID = Query } }, { __index = _G })
    local chunk = assert(loadfile(path))
    setfenv(chunk, world.env)
    chunk("MSUF_Suite_QualityOfLife", { NS = { AnchorPoints = {}, IsSecret = Unexpected }, Suite = suite })
    local paint = Upvalue(Upvalue(assert(installed).Enable, "OnGroup"), "Paint")
    world.query = Upvalue(paint, "LockoutAura")
    world.source = debug.getinfo(world.query, "S").source
    assert(world.source == "@" .. path, "query source filter does not match actual product file")
    return world
end

local function Reset(world)
    world.calls, world.orderCount = 0, 0
    for i = 1, #SPELLS do world.native[i] = 0 end
end

local function Prepare(world, mask, falseMissing)
    world.falseMissing = falseMissing
    for i, id in ipairs(SPELLS) do
        world.present[id] = math.floor(mask / 2 ^ (i - 1)) % 2 == 1 and world.auras[i] or nil
    end
end

local function Expected(world)
    for i, id in ipairs(SPELLS) do
        local aura = world.present[id]
        if aura then return aura, i end
    end
    return nil, #SPELLS
end

local function Behavior(world)
    world.auras = {}
    local unreadable = { __index = function() error("query inspected secret-capable aura data") end }
    for i = 1, #SPELLS do world.auras[i] = setmetatable({}, unreadable) end
    world.recording = true
    local checks = 0
    for _, falseMissing in ipairs({ false, true }) do
        for mask = 0, 127 do
            Prepare(world, mask, falseMissing)
            Reset(world)
            local expected, count = Expected(world)
            assert(world.query() == expected, "changed first-present aura priority or miss result")
            assert(world.calls == count and world.orderCount == count, "changed native query count")
            for i = 1, count do assert(world.order[i] == SPELLS[i], "changed native spell query order") end
            checks = checks + 1
        end
    end
    -- Distinct objects prove priority, not merely equal Locked presentation.
    for i = 1, #SPELLS do world.auras[i] = { duration = i, expirationTime = i * 100, auraInstanceID = i } end
    Prepare(world, 127, false)
    for i, id in ipairs(SPELLS) do
        assert(world.query() == world.auras[i], "multiple simultaneous lockouts changed priority")
        world.present[id] = nil
    end
    Prepare(world, 4, false)
    local newer = { duration = 599, expirationTime = 900, auraInstanceID = 3 }
    world.present[SPELLS[3]] = newer
    assert(world.query() == newer, "query reused an old same-instance aura object")
    -- Keep dynamic namespace AND method replacement visible after chunk load.
    local replacement = {}
    world.env.C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
        if id == SPELLS[2] then return replacement end
    end }
    assert(world.query() == replacement, "query cached the API namespace")
    world.env.C_UnitAuras.GetPlayerAuraBySpellID = function(id)
        if id == SPELLS[1] then return world.auras[1] end
    end
    assert(world.query() == world.auras[1], "query cached the API method")
    world.env.C_UnitAuras.GetPlayerAuraBySpellID = world.api
    world.recording = false
    return checks
end

local function Instructions(world, run)
    local count = 0
    debug.sethook(function()
        if debug.getinfo(2, "S").source == world.source then count = count + 1 end
    end, "", 1)
    run()
    debug.sethook()
    assert(count > 0, "product instruction filter counted zero")
    return count
end

local function Allocation(run)
    run()
    local minimum = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        run()
        minimum = math.min(minimum, collectgarbage("count") - before)
        collectgarbage("restart")
    end
    return minimum
end

for _, source in ipairs(sources) do
    local world = New(source.path)
    local checks = Behavior(world)
    for _, falseMissing in ipairs({ false, true }) do
        for position = 1, 8 do
            local name = (falseMissing and "false-" or "nil-") .. (position == 8 and "absent" or "hit" .. position)
            local mask = position == 8 and 0 or 2 ^ (position - 1)
            Prepare(world, mask, falseMissing)
            local expected, perCall = Expected(world)
            local last
            local function Run()
                for _ = 1, options.iterations do last = world.query() end
            end
            Run()
            assert(last == expected, name .. ": query did not return current object")
            local instructions = Instructions(world, Run)
            local kb = Allocation(Run)
            Reset(world)
            Run()
            assert(world.calls == perCall * options.iterations, name .. ": native total changed")
            for i = 1, #SPELLS do
                local wanted = i <= perCall and options.iterations or 0
                assert(world.native[i] == wanted, name .. ": native per-spell vector changed")
            end
            if limits and source.name ~= "baseline" then
                local limit = assert(limits.cases[name], "missing measured query budget " .. name)
                assert(instructions <= limit.instructions, name .. ": product VM budget regressed")
                assert(kb <= limits.allocationKB, name .. ": warm Lua allocation budget regressed")
            end
            print(string.format("BloodlustQuery\t%s\t%s\t%d\t%d\t%.6f\t%d\t%s", source.name, name,
                options.iterations, instructions, kb, world.calls, table.concat(world.native, ",")))
        end
    end
    print(string.format("Bloodlust behavior: %s %d presence/miss cases + priority/fresh-object/API replacement PASS",
        source.name, checks))
end
print("Bloodlust query budgets: product Lua VM only; exact native vectors; warm Lua allocation minimum of two")
print("Restriction/lifecycle behavior is covered by existing group_mplus_qol and hot_event_native contracts")
