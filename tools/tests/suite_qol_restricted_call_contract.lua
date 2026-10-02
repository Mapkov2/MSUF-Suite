-- S.QoLRestrictedCall (MSUF_Suite_QualityOfLife/Bootstrap.lua): the client
-- refuses a restricted action with ADDON_ACTION_BLOCKED or
-- ADDON_ACTION_FORBIDDEN, delivered to every registered frame while the call
-- runs. Single, raising and nested calls.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

local frames = Support.EventFrames()
local reported = {}
local suite = { CreateFrame = frames.Create, Dispatch = Support.Dispatcher(reported) }
Support.QoLStyleFixture(root, suite)
local Call = assert(suite.QoLRestrictedCall, "Bootstrap.lua defines S.QoLRestrictedCall")

local function Allowed() end
local function Blocked() frames.Fire("ADDON_ACTION_BLOCKED", "MSUF_Suite_QualityOfLife", "UseContainerItem") end
local function Forbidden() frames.Fire("ADDON_ACTION_FORBIDDEN", "MSUF_Suite_QualityOfLife", "CancelAura") end
local function Raises() error("the restricted action raised") end
local function Watching()
    for _, frame in ipairs(frames.list) do
        if frame.events.ADDON_ACTION_BLOCKED or frame.events.ADDON_ACTION_FORBIDDEN then return true end
    end
    return false
end

assert(Call(Allowed) == true, "an allowed action counted as refused")
assert(Call(Blocked) == false and Call(Forbidden) == false, "a refused action counted as done")
assert(Call(Raises) == false and #reported == 1, "a raising action was not reported and refused")
assert(Call(Allowed) == true, "an earlier refusal leaked into a later call")
assert(not Watching(), "the refusal watch stayed registered between calls")
-- A refusal outside any call belongs to someone else.
Blocked()
assert(Call(Allowed) == true, "a foreign refusal before the call was counted")

-- Nested calls: the outer call sees refusals made after an inner call
-- returned, and an inner refusal refuses the outer action too.
local inner, watching
local function OuterAfterInner()
    inner = Call(Allowed)
    watching = Watching()
    Blocked()
end
assert(Call(OuterAfterInner) == false and inner == true and watching and #reported == 1,
    "a refusal after a nested call returned was missed")
local function OuterAroundRefusal()
    inner = Call(Forbidden)
end
assert(Call(OuterAroundRefusal) == false and inner == false, "an inner refusal did not refuse the outer action")
local function OuterBeforeInner()
    Blocked()
    inner = Call(Allowed)
end
assert(Call(OuterBeforeInner) == false and inner == true,
    "an outer refusal before a nested call was lost or charged to the inner call")
assert(not Watching() and Call(Allowed) == true, "nested calls left the watch or a refusal behind")
print("suite_qol_restricted_call_contract: OK")
