local root = assert(arg[1], "repository root required")
local logOn, instanceType, difficulty = false, "none", 0
local timers, events, messages, calls = {}, {}, {}, {}

LoggingCombat = function(value)
    if value == nil then return logOn end
    logOn = value
    calls[#calls + 1] = value
    return logOn
end
C_ChatInfo = { IsLoggingCombat = function() return logOn end }
GetInstanceInfo = function() return "test", instanceType, difficulty end
local inDelve = false
C_DelvesUI = { HasActiveDelve = function() return inDelve end }
C_Timer = { NewTimer = function(seconds, callback)
    assert(seconds == 30)
    local timer = { callback = callback, canceled = false }
    function timer:Cancel() self.canceled = true end
    timers[#timers + 1] = timer
    return timer
end }
local secret = {}
issecretvalue = function(value) return value == secret end

local suite = { instances = {} }
suite.Public = function(value) return not issecretvalue(value) end
suite.Text = function(value) return value end
function suite.Install(id, module)
    assert(id == "combatLog" and not suite.instances[id])
    suite.instances[id] = module
end
local owner = { Print = function(message) messages[#messages + 1] = message end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/CombatLog.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = owner, Suite = suite })
local module = assert(suite.instances.combatLog)
module.active = true
module.config = {
    dungeonMythicPlus = true, raidNormal = true, raidHeroic = true,
    raidMythic = true, stopPolicy = 2, chatNotice = true,
}
module.context = {
    Event = function(_, name, callback, allowCombat)
        assert(allowCombat == true and not events[name], "duplicate event")
        events[name] = callback
    end,
}
local function Fire(name)
    assert(events[name], "missing event " .. name)(module, name)
end
local function Place(kind, id)
    instanceType, difficulty = kind, id or 0
    Fire("ZONE_CHANGED_NEW_AREA")
end

-- Enabling outside selected content does not touch Blizzard's logging state.
module:Enable()
assert(not logOn and #calls == 0 and events.CHALLENGE_MODE_START)

-- A Keystone starts the log. Leaving schedules one stop; returning cancels it.
Place("party", 23)
assert(not logOn, "ordinary Mythic was selected as Mythic+")
instanceType, difficulty = "party", 8
Fire("CHALLENGE_MODE_START")
assert(logOn and module.startedBySuite and #calls == 1)
Place("none")
assert(#timers == 1 and logOn)
Place("party", 8)
assert(timers[1].canceled and logOn)
timers[1].callback()
assert(logOn, "canceled timer stopped logging after re-entry")
Place("none")
assert(#timers == 2)
timers[2].callback()
assert(not logOn and not module.startedBySuite and #calls == 2)

-- A log already running before MSUF enters is always owned by the player.
logOn = true
Place("raid", 14)
assert(not module.startedBySuite)
Place("none")
assert(logOn and #timers == 2 and #calls == 2)

-- Selected difficulties are separate, and unclassified content is untouched.
logOn = false
Place("raid", 17)
assert(not logOn)
Place("raid", 15)
assert(logOn and module.startedBySuite)
Place("raid", 999)
assert(logOn and #timers == 2, "unknown difficulty stopped an owned log")
Place("none")
module.config.stopPolicy = 1
module:Refresh()
assert(not logOn and #calls == 4, "immediate stop ignored")

-- A user turning logging off in a selected instance is not overruled by
-- later zone or difficulty events inside that same selected category.
Place("party", 8)
assert(logOn)
logOn = false
Fire("UPDATE_INSTANCE_INFO")
assert(not logOn and module.manualStop)
Fire("PLAYER_DIFFICULTY_CHANGED")
assert(not logOn)
Place("none")
Place("party", 8)
assert(logOn and not module.manualStop)

-- Leave-on policy transfers ownership; disabling does not stop that log.
module.config.stopPolicy = 3
Place("none")
assert(logOn and not module.startedBySuite)
module.active = false
module:Disable()
assert(logOn and #calls == 6)
module.active = true
events = {}
module:Enable()

-- Delves report the scenario instance type; the Delves switch decides them.
module.config.stopPolicy, module.config.delve, module.config.scenario = 1, true, false
logOn, module.startedBySuite, module.manualStop = false, false, nil
inDelve = true
Place("scenario", 208)
assert(logOn and module.startedBySuite, "a delve followed the Scenarios switch")
Place("none")
assert(not logOn)
inDelve = false
Place("scenario", 208)
assert(logOn, "difficulty 208 alone did not identify the delve")
Place("none")
Place("scenario", 12)
assert(not logOn, "an ordinary scenario followed the Delves switch")
module.config.delve, module.config.scenario = false, true
inDelve = true
Place("scenario", 208)
assert(not logOn, "a delve followed the Scenarios switch")
inDelve = false
Place("scenario", 12)
assert(logOn, "the Scenarios switch did not start the log")
Place("none")
inDelve, difficulty = secret, secret
Place("scenario", secret)
assert(logOn, "an unreadable delve state must fall back to the Scenarios switch")
Place("none")
inDelve = false
local delveCalls = #calls

-- No secret or unknown instance result may be indexed or compared.
logOn = false
module.active = true
events = {}
module:Enable()
instanceType = secret
Fire("ZONE_CHANGED_NEW_AREA")
assert(not logOn and #calls == delveCalls)
module.active = false
module:Disable()
assert(#messages == delveCalls and #calls == delveCalls)
-- Retail and WoW Forever always have the APIs combat logging calls.
for _, name in ipairs({ "CombatLog" }) do
    local file = assert(io.open(root .. "/MSUF_Suite_QualityOfLife/" .. name .. ".lua", "rb"))
    local source = file:read("*a")
    file:close()
    local guarded = source:match("type%(([^)]*)%)%s*[~=]=%s*\"function\"") or source:match("(C_%w+) and C_%w+%.")
    assert(not guarded, name .. ".lua guards " .. tostring(guarded) .. " as if a client lacked it")
end
print("Combat logging: event routing, difficulty choices, ownership, timer and manual override passed")
