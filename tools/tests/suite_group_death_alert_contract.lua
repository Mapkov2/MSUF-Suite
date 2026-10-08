local root = assert(arg[1], "repository root required")
local module, lines = nil, {}
local combat, grouped, raid = false, false, false
local members = {}
local nativeWrites, created = 0, 0
local screen
RaidWarningFrame = { messageCounter = 0 }
RaidWarningUtil = { AddMessage = function()
    -- Blizzard's shared pool is also read by DebuffFrame's deadly-debuff path.
    nativeWrites = nativeWrites + 1
    RaidWarningFrame.messageCounter = RaidWarningFrame.messageCounter + 1
end }
GameFontNormalHuge = {}
ChatTypeInfo = { RAID_WARNING = { r = 1, g = .28, b = 0 } }
UIParent = {}
IsInGroup = function() return grouped end
IsInRaid = function() return raid end
UnitExists = function(unit) return members[unit] ~= nil end
UnitIsDeadOrGhost = function(unit) return members[unit] end
local names, feigned = { party1 = "Alice", party3 = "Cleo" }, {}
UnitName = function(unit) return names[unit] or "Player" end
UnitGUID = function(unit) return members[unit] ~= nil and "GUID-" .. unit or nil end
UnitIsFeignDeath = function(unit) return feigned[unit] == true end
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
    CreateFrame = function(kind, name, parent, template)
        created = created + 1
        assert(kind == "MessageFrame" and parent == UIParent and not template,
            "death alerts need an owned native message frame without Blizzard Lua scripts")
        screen = { messages = {} }
        function screen:SetSize(width, height) self.width, self.height = width, height end
        function screen:SetPoint(...) self.point = { ... } end
        function screen:SetFrameStrata(value) self.strata = value end
        function screen:EnableMouse(value) self.mouse = value end
        function screen:SetFontObject(value) self.font = value end
        function screen:SetJustifyH(value) self.justify = value end
        function screen:SetInsertMode(value) self.insert = value end
        function screen:SetTimeVisible(value) self.visibleFor = value end
        function screen:SetFadeDuration(value) self.fadeFor = value end
        function screen:SetFading(value) self.fading = value end
        function screen:Show() self.shown = true end
        function screen:Hide() self.shown = false end
        function screen:Clear() self.messages = {} end
        function screen:AddMessage(...) self.messages[#self.messages + 1] = { ... } end
        return screen
    end,
}
-- Platform.lua's IsSecret is the client's issecretvalue; "secret" stands in
-- for a secret value.
local ns = { IsCombatLocked = function() return combat end,
    IsSecret = function(value) return value == "secret" end }
ns.InCombat = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().InCombat(root,
    function() return combat end)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupDeathAlert.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(module)
module.active, module.context, module.config = true, context, { includePlayer = false, screen = true }
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
assert(nativeWrites == 0 and RaidWarningFrame.messageCounter == 0,
    "death alerts mutated Blizzard's shared raid-warning state used by deadly debuffs")
assert(created == 1 and screen.shown and #screen.messages == 1,
    "one death was not displayed exactly once on the owned screen frame")
local message = screen.messages[1]
assert(message[1] == "Alice died" and message[2] == 1 and message[3] == .28 and message[4] == 0,
    "the screen death text or warning color changed")
assert(screen.visibleFor == 10 and screen.fadeFor == 3 and screen.fading and screen.mouse == false,
    "screen messages must fade natively and leave input alone")
assert(screen.point[2] == RaidWarningFrame and screen.point[3] == "TOP",
    "owned death messages must stay above the native raid-warning/debuff stack")
-- In an instance the dying member stays in combat: the health and flag
-- events of that moment still read them alive, and UNIT_DIED tells the death.
members.party3 = false
context.events.GROUP_ROSTER_UPDATE.callback(module, "GROUP_ROSTER_UPDATE")
assert(context.events.UNIT_DIED and module.guids["GUID-party3"] == "party3",
    "the death event or the member GUID index was not set up in combat")
context.events.UNIT_HEALTH.callback(module, "UNIT_HEALTH", "party3")
context.events.UNIT_FLAGS.callback(module, "UNIT_FLAGS", "party3")
assert(#lines == 1, "a member read alive was announced")
feigned.party3 = true
context.events.UNIT_DIED.callback(module, "UNIT_DIED", "GUID-party3")
assert(#lines == 1, "Feign Death was announced as a death")
feigned.party3 = nil
-- Units outside the group die with a secret or an unknown GUID.
context.events.UNIT_DIED.callback(module, "UNIT_DIED", "secret")
context.events.UNIT_DIED.callback(module, "UNIT_DIED", "Creature-0-1")
assert(#lines == 1, "a death outside the group was announced")
context.events.UNIT_DIED.callback(module, "UNIT_DIED", "GUID-party3")
assert(#lines == 2 and lines[2] == "Cleo died", "the client's death event was not announced")
members.party3 = true
context.events.UNIT_FLAGS.callback(module, "UNIT_FLAGS", "party3")
context.events.UNIT_DIED.callback(module, "UNIT_DIED", "GUID-party3")
assert(#lines == 2 and #screen.messages == 2, "a death told by UNIT_DIED was told again")
members.party3 = nil
combat = false
context.events.PLAYER_REGEN_ENABLED.callback(module, "PLAYER_REGEN_ENABLED")
assert(not context.events.UNIT_HEALTH and not context.events.UNIT_FLAGS and not context.events.UNIT_DIED,
    "group health or death events remained registered after combat")
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
assert(context.events.UNIT_HEALTH and context.events.UNIT_DIED and context.events.PLAYER_UNGHOST,
    "the player's death stopped the alerts for the rest of the wipe")
members.party2 = true
context.events.UNIT_HEALTH.callback(module, "UNIT_HEALTH", "party2")
assert(#lines == 3 and lines[3] == "Player died", "a death after the player's own was not reported")
context.events.PLAYER_ALIVE.callback(module, "PLAYER_ALIVE")
assert(context.events.UNIT_HEALTH, "releasing the spirit ended the watch while the group still fights")
members.player = false
context.events.PLAYER_UNGHOST.callback(module, "PLAYER_UNGHOST")
assert(not context.events.UNIT_HEALTH and not context.events.PLAYER_ALIVE,
    "the watch outlived the player's resurrection")
-- The player's own death ends their combat, possibly before the client
-- tells it: the combat end keeps the states, so the later UNIT_DIED counts.
module.config.includePlayer = true
members.party2 = false
context.events.PLAYER_REGEN_DISABLED.callback(module, "PLAYER_REGEN_DISABLED")
combat = true
local states = module.dead
members.player, combat = true, false
context.events.PLAYER_REGEN_ENABLED.callback(module, "PLAYER_REGEN_ENABLED")
assert(module.dead == states and states.player == false,
    "the combat end rebuilt the states and took the player's death as known")
context.events.UNIT_DIED.callback(module, "UNIT_DIED", "GUID-player")
assert(#lines == 4 and lines[4] == "Player died", "the player's own death told after combat was lost")
members.player = false
context.events.PLAYER_UNGHOST.callback(module, "PLAYER_UNGHOST")
assert(not context.events.UNIT_DIED, "the death event outlived the player's resurrection")
module.config.includePlayer = false
module.config.screen = false
module:Refresh()
assert(not screen.shown and #screen.messages == 0, "turning screen alerts off left stale messages")
module.config.screen = true
module:Refresh()
assert(created == 1 and screen.shown, "screen alerts rebuilt their frame on a settings refresh")
screen:AddMessage("pending", 1, 1, 1)
module:Disable()
assert(not screen.shown and #screen.messages == 0, "disabling death alerts left screen messages alive")
assert(nativeWrites == 0, "a later death wrote the native raid-warning pool")
print("Suite group death alert lifecycle passed")
