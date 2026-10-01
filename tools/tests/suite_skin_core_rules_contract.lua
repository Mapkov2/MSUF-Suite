-- The skin follows the Suite core's rules where both decide the same thing:
-- a secret value is never readable (Platform.lua Public vs. the skin's
-- Safety.Public), also while canaccessvalue answers true for the caller.
local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local secret = setmetatable({}, { __eq = function() error("a secret was compared") end })
issecretvalue = function(value) return value == secret or value == "secret text" end
canaccessvalue = function() return true end
MSUF_NS = {}
local core = {}
assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", core)
local skin = {}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", skin)
for _, value in ipairs({ 1, 0, "text", true, false, {}, secret, "secret text" }) do
    Check(skin.Safety.Public(value) == core.Public(value),
        "the skin and the core disagree whether a value is readable: " .. tostring(value))
end
Check(not skin.Safety.Public(secret) and skin.Safety.Public(7), "a secret counted as readable in the skin")
print("Suite skin core rules: " .. checks .. " checks passed")
