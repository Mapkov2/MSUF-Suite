-- The embedded skin consumes the Suite's host boundary. Optional host
-- exports stay live: a font or menu published later is not cached absent.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, label) assert(value, label); checks = checks + 1 end
local secret = setmetatable({}, { __eq = function() error("secret comparison") end })
local Suite = { Public = function(value) return not rawequal(value, secret) end }
CreateFrame = function() error("host service lookup created a frame") end
C_AddOns = { LoadAddOn = function() error("host service lookup loaded Options") end }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", Suite)
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeMenu.lua"))("MSUF_Suite", Suite)
local bridge = Suite.HostBridge
Check(type(bridge.HostFontPath) == "function" and type(bridge.WithMenuHistory) == "function",
    "skin host services are missing from their boundary")

MSUF_GetFontPath = nil
Check(bridge.HostFontPath() == nil and select("#", bridge.HostFontPath()) == 1,
    "an absent host font needs one nil result, without a bundled fallback")
local path, calls = "Host.ttf", 0
MSUF_GetFontPath = function() calls = calls + 1; return path end
Check(bridge.HostFontPath() == "Host.ttf" and calls == 1, "late host font was cached absent")
path = "Second.ttf"
Check(bridge.HostFontPath() == path and calls == 2, "host font changes were cached")
for _, value in ipairs({ "", false, 10, secret }) do
    path = value
    Check(bridge.HostFontPath() == nil, "invalid or secret font path escaped the boundary")
end
path = nil
Check(bridge.HostFontPath() == nil, "a disappearing host selection retained its previous font")
MSUF_GetFontPath = "not callable"
Check(bridge.HostFontPath() == nil, "non-callable legacy font export was used")

local function Results(...) return { n = select("#", ...), ... } end
local commits, history = 0, 0
local function Commit() commits = commits + 1; return nil, "kept" end
MSUF2 = nil
local result = Results(bridge.WithMenuHistory("Move", "skin:move", Commit))
Check(commits == 1 and result.n == 2 and result[1] == nil and result[2] == "kept",
    "cold history fallback changed callback count or return values")
MSUF2 = { RunWithHistory = function(label, source, callback)
    Check(label == "Move" and source == "skin:move", "history metadata changed")
    history = history + 1
    return callback()
end }
result = Results(bridge.WithMenuHistory("Move", "skin:move", Commit))
Check(commits == 2 and history == 1 and result.n == 2 and result[2] == "kept",
    "late history provider was ignored or callback ran twice")
MSUF2.RunWithHistory = function() history = history + 1; return nil end
result = Results(bridge.WithMenuHistory("Move", "skin:move", Commit))
Check(commits == 2 and history == 2 and result.n == 1 and result[1] == nil,
    "a nil history result retried the commit")
MSUF2.RunWithHistory = nil
bridge.WithMenuHistory("Move", "skin:move", Commit)
Check(commits == 3, "a menu without history prevented the single direct commit")
MSUF2 = nil
bridge.WithMenuHistory("Move", "skin:move", Commit)
Check(commits == 4, "a closed history provider was cached")
print("Suite skin host services: " .. checks .. " checks passed")
