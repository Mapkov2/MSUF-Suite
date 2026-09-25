-- Code that other addons register through the skin's public API runs through
-- Safety.Dispatch. The client's securecallfunction reports an error to the
-- error handler and returns nothing; this harness models exactly that. A
-- failing adapter or theme listener is reported and the others still run.
local root = assert(arg[1], "repository root required")

local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end

local function Frame()
    return {
        IsForbidden = function() return false end,
        IsProtected = function() return false, false end,
    }
end

local NS = {
    DB = { enabled = true, skins = {} },
    Client = { HasAddOn = function() return false end },
    IsCombatLocked = function() return false end,
    CombatGate = { RunOrDefer = function() error("no combat in this contract") end },
    WindowControls = { DisableOwner = function() end, Attach = function() end },
    Cosmetics = { RestoreOwner = function() end },
    Surface = { Attach = function(frame) return frame end, SetVisible = function() end },
    Checkmarks = { TrackControlTree = function() end },
}
for _, file in ipairs({ "Core/Safety.lua", "Core/Registry.lua", "Adapters/Blizzard.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end

local Adapters = NS.Adapters
local applied = {}
local function Definition(id, apply, resolve)
    return {
        id = id,
        resolve = resolve or function() return Frame() end,
        apply = apply or function() applied[#applied + 1] = id; return true end,
    }
end
assert(Adapters.Register(Definition("before")))
assert(Adapters.Register(Definition("broken-apply", function() error("foreign apply failed") end)))
assert(Adapters.Register(Definition("broken-resolve", nil, function() error("foreign resolve failed") end)))
assert(Adapters.Register(Definition("after")))

assert(Adapters.ApplyAll() == true)
assert(#applied == 2 and applied[1] == "before" and applied[2] == "after",
    "a failing adapter stopped the adapters after it")
assert(#reported == 2 and reported[1]:find("foreign apply failed", 1, true)
    and reported[2]:find("foreign resolve failed", 1, true), "adapter errors were not reported")
assert(Adapters.status["broken-apply"].state == "error", "a failed apply was reported as applied")
assert(Adapters.status["broken-resolve"].state == "missing")
assert(Adapters.status.after.state == "applied")

local heard = {}
NS.Registry.AddListener({}, function() error("foreign listener failed") end)
NS.Registry.AddListener({}, function(_, domain, key) heard[#heard + 1] = domain .. ":" .. key end)
NS.Registry.AddListener({}, function(_, domain, key) heard[#heard + 1] = domain .. ":" .. key end)
assert(NS.Registry.NotifyListeners("theme", "look") == true)
assert(#heard == 2, "a failing theme listener stopped the others")
assert(#reported == 3 and reported[3]:find("foreign listener failed", 1, true))

print("Suite skin dispatch: failing foreign adapters and listeners are reported and isolated")
