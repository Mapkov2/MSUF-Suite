local root = assert(arg[1], "repository root required")
local module, lines = nil, {}
local combat, grouped, raid = false, false, false
local members = {}
IsInGroup = function() return grouped end
IsInRaid = function() return raid end
UnitExists = function(unit) return members[unit] ~= nil end
UnitIsDeadOrGhost = function(unit) return members[unit] end
UnitName = function(unit) return unit == "party1" and "Alice" or "Player" end
local context = { events = {} }
function context:Event(event, callback, _, units)
    self.events[event] = { callback = callback, units = units }
end
function context:RemoveEvent(event) self.events[event] = nil end
local suite = {
    Install = function(_, value) module = value end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Text = function(value) return value end,
    Print = function(value) lines[#lines + 1] = value end,
}
local ns = { IsCombatLocked = function() return combat end }
ns.InCombat = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().InCombat(root,
    function() return combat end)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupDeathAlert.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(module)
module.active, module.context, module.config = true, context, { includePlayer = false }
module:Enable()
assert(not context.events.UNIT_HEALTH and context.events.GROUP_ROSTER_UPDATE,
    "group health must not be observed while idle")
grouped, members.party1 = true, false
-- PLAYER_REGEN_DISABLED arrives before InCombatLockdown() turns true.
context.events.PLAYER_REGEN_DISABLED.callback(module, "PLAYER_REGEN_DISABLED")
combat = true
assert(context.events.UNIT_HEALTH and context.events.UNIT_FLAGS,
    "group health events were not registered on combat entry")
members.party1 = true
context.events.UNIT_HEALTH.callback(module, "UNIT_HEALTH", "party1")
context.events.UNIT_FLAGS.callback(module, "UNIT_FLAGS", "party1")
assert(#lines == 1 and lines[1] == "Alice died", "one death was not reported exactly once")
combat = false
context.events.PLAYER_REGEN_ENABLED.callback(module, "PLAYER_REGEN_ENABLED")
assert(not context.events.UNIT_HEALTH and not context.events.UNIT_FLAGS,
    "group health events remained registered after combat")
-- A wipe: the player's own death ends their combat (PLAYER_REGEN_ENABLED),
-- the other deaths are still told until the player is alive again.
members.party1, members.party2, members.player = false, false, false
context.events.PLAYER_REGEN_DISABLED.callback(module, "PLAYER_REGEN_DISABLED")
combat = true
local watched, baseline = context.events.UNIT_HEALTH.units, module.dead
context.events.GROUP_ROSTER_UPDATE.callback(module, "GROUP_ROSTER_UPDATE")
assert(context.events.UNIT_HEALTH.units == watched and module.dead == baseline,
    "a roster change in combat built new unit and baseline tables")
members.player, combat = true, false
context.events.PLAYER_REGEN_ENABLED.callback(module, "PLAYER_REGEN_ENABLED")
assert(context.events.UNIT_HEALTH and context.events.PLAYER_UNGHOST,
    "the player's death stopped the alerts for the rest of the wipe")
members.party2 = true
context.events.UNIT_HEALTH.callback(module, "UNIT_HEALTH", "party2")
assert(#lines == 2 and lines[2] == "Player died", "a death after the player's own was not reported")
context.events.PLAYER_ALIVE.callback(module, "PLAYER_ALIVE")
assert(context.events.UNIT_HEALTH, "releasing the spirit ended the watch while the group still fights")
members.player = false
context.events.PLAYER_UNGHOST.callback(module, "PLAYER_UNGHOST")
assert(not context.events.UNIT_HEALTH and not context.events.PLAYER_ALIVE,
    "the watch outlived the player's resurrection")
module:Disable()
print("Suite group death alert lifecycle passed")
