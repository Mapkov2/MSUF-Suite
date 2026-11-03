local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module, calls, reported, notices = nil, {}, {}, {}
local frames = Support.EventFrames()
local now, combat, lootShown = 0, false, false
local slots, jobs, waits = {}, {}, {}
for bag = 0, 5 do slots[bag] = {} end
GetTime = function() return now end
C_Timer = { After = function(delay, callback)
    if delay == 0 then jobs[#jobs + 1] = callback
    else waits[#waits + 1] = { due = now + delay, callback = callback } end
end }
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
C_Container = {
    GetContainerNumSlots = function() return 5 end,
    GetContainerItemInfo = function(bag, slot) return slots[bag][slot] and slots[bag][slot].info end,
    UseContainerItem = function(bag, slot) calls[#calls + 1] = { bag = bag, slot = slot } end,
}
C_Item = { GetItemGUID = function(location)
    return slots[location.bag][location.slot] and slots[location.bag][location.slot].guid
end }
IsShiftKeyDown = function() return false end
CursorHasItem = function() return false end
LootFrame = { IsShown = function() return lootShown end }
local S = {
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end,
    Text = function(value) return value end,
    Install = function(_, instance) module = instance end,
    CreateFrame = frames.Create, Dispatch = Support.Dispatcher(reported),
}
Support.QoLStyleFixture(root, S)
local NS = {
    Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return combat end,
    Print = function(value) notices[#notices + 1] = value end, Dispatch = S.Dispatch,
}
local context = Support.ModuleTimers(root, S, NS)("lootContainers", nil, { events = {}, options = {} })
function context:Event(event, callback, options) self.events[event], self.options[event] = callback, options end
function context:RemoveEvent(event) self.events[event], self.options[event] = nil, nil end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SharedItems.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/LootContainers.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.context, S.instances.lootContainers = context, module
local function Event(event, ...)
    local handler = context.events[event]
    if handler then handler(module, event, ...) end
end
local function Flush()
    local pending = jobs; jobs = {}
    for _, callback in ipairs(pending) do callback() end
end
local function Advance(seconds)
    now = now + seconds
    local pending = waits; waits = {}
    for _, wait in ipairs(pending) do
        if wait.due <= now then wait.callback() else waits[#waits + 1] = wait end
    end
    Flush()
end
local function Settle(bag)
    Event("BAG_UPDATE", bag); Event("BAG_UPDATE_DELAYED")
end
local function Add(bag, slot, guid)
    slots[bag][slot] = { guid = guid, info = { itemID = 500, hasLoot = true, isLocked = false } }
end
local function Reset()
    if module.active then module.active = false; module:Disable(); context:CancelTimers() end
    calls, jobs, waits, now = {}, {}, {}, 0
    combat, lootShown = false, false
    for bag = 0, 5 do slots[bag] = {} end
    module.config, module.active = { skipWarbound = false }, true
    module:Enable()
end
local function Close()
    Event("LOOT_CLOSED")
    lootShown = false
    Flush()
end

Reset()
Add(0, 1, "first"); Add(0, 2, "second"); Settle(0)
assert(#calls == 1, "initial batch must issue only one use")
Settle(5)
assert(#calls == 1, "another bag update overlapped the still-pending native use")
-- Moving the outstanding GUID is not evidence that the native use ended.
slots[1][3], slots[0][2] = slots[0][2], nil
Event("BAG_UPDATE", 0); Settle(1)
assert(#calls == 1 and module.opening.bag == 1 and module.opening.slot == 3,
    "moving the in-flight GUID released or misplaced its ownership")
Event("ITEM_LOCK_CHANGED", 0, 2); Event("ITEM_LOCK_CHANGED", 1, 3); Flush()
assert(#calls == 1, "item lock changes must not pretend a pending native use completed")
lootShown = true; Event("LOOT_OPENED", true)
Advance(6)
assert(#calls == 1 and #module.pending == 1, "an opened loot window was timed out or bypassed")
Close()
assert(#calls == 2 and calls[2].slot == 1, "native close must resume the next candidate next frame")
lootShown = true; Event("LOOT_OPENED", true); Close(); Settle(0); Settle(1)
assert(#calls == 2, "an attempted GUID was automatically repeated")

Reset()
Add(0, 1, "silent-a"); Add(0, 2, "silent-b"); Settle(0)
Advance(6)
assert(#calls == 1 and #module.pending == 0, "silent refusal deadline must only cancel the batch")
Add(1, 1, "after-timeout"); Settle(1)
assert(#calls == 1, "new acquisition after timeout overlapped an unresolved native use")
lootShown = true; Event("LOOT_OPENED", true); Advance(6); Close()
assert(#calls == 1, "late loot open/close must not retry the cancelled batch")
Add(1, 2, "after-late-close"); Settle(1)
assert(#calls == 2, "native close did not restore eligibility for later acquisitions")

Reset()
Add(0, 1, "error-a"); Add(0, 2, "error-b"); Settle(0)
Event("UI_ERROR_MESSAGE", 42, "native error")
Add(1, 1, "during-error"); Settle(1); Advance(6)
assert(#calls == 1 and #module.pending == 0 and not module.blocked,
    "uncorrelated error must cancel without an unsafe use or permanent blocked flag")
-- Explicit user restart is the recovery when no attributable native close arrives.
module.active = false; module:Disable(); context:CancelTimers()
assert(not context.events.LOOT_OPENED and not context.events.LOOT_CLOSED and not context.events.UI_ERROR_MESSAGE,
    "disable retained native flight callbacks")
module.active = true; module:Enable()
Settle(0); Settle(1)
assert(#calls == 1, "restart must baseline old/manual GUIDs rather than retry them")
Add(1, 2, "after-restart"); Settle(1)
assert(#calls == 2, "explicit restart did not recover new acquisitions")

Reset()
Add(0, 1, "before-combat"); Settle(0)
combat = true
Add(0, 2, "in-combat"); Settle(0)
assert(#calls == 1 and context.events.PLAYER_REGEN_ENABLED, "combat acquisition was lost or used early")
assert(Support.InCombatOption(context.options.LOOT_OPENED)
    and Support.InCombatOption(context.options.LOOT_CLOSED)
    and Support.InCombatOption(context.options.UI_ERROR_MESSAGE), "native flight events must survive combat")
lootShown = true; Event("LOOT_OPENED", true); Close()
assert(#calls == 1 and #module.pending == 1, "native close must retain combat-deferred acquisitions")
combat = false; Event("PLAYER_REGEN_ENABLED")
assert(#calls == 2, "combat-deferred queue did not resume after lockdown")

Reset()
Add(0, 1, "only-flight"); Settle(0)
combat = true
lootShown = true; Event("LOOT_OPENED", true); Close()
assert(not module.opening and not context.events.LOOT_CLOSED, "combat close lost a sole outstanding use")
Add(0, 2, "after-combat-close"); Settle(0)
assert(#calls == 1 and context.events.PLAYER_REGEN_ENABLED, "combat close bypassed acquisition deferral")
combat = false; Event("PLAYER_REGEN_ENABLED")
assert(#calls == 2, "sole-flight combat close prevented later acquisition recovery")

Reset()
local ordinaryUse = C_Container.UseContainerItem
C_Container.UseContainerItem = function(bag, slot)
    ordinaryUse(bag, slot)
    Event("BAG_UPDATE_DELAYED")
end
Add(0, 1, "reentrant-a"); Add(0, 2, "reentrant-b"); Settle(0)
assert(#calls == 1, "use ownership must be established before calling the native API")
C_Container.UseContainerItem = ordinaryUse
module.active = false; module:Disable(); context:CancelTimers()
Advance(10)
assert(#calls == 1 and not module.opening and #reported == 0, "disable retained an asynchronous action")
print("Suite asynchronous loot: native pending, move, late close, cancellation, restart and combat passed")
