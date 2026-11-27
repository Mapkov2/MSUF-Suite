local root = assert(arg[1], "repository root required")
local SECRET = {}
local function IsSecret(value) return rawequal(value, SECRET) end
local function Noop() end
local reads, tints, usable, plans = 0, 0, 0, 0
local rec = { rangeSlot = 61, native = true, bar = {} }
local events, options, context = {}, {}, {}
function context:Event(event, handler, option) events[event], options[event] = handler, option end
function context:RemoveEvent(event) events[event], options[event] = nil, nil end
local module = { active = true, config = { rangeColoring = true, procGlow = 0 }, context = context }
local suite = { Public = function(value) return not IsSecret(value) end }
local actionBars = {
    M = module,
    ENUM = { PROC_GLOW = { NONE = 0, PIXEL = 2 }, BAR = { MAIN = 1, LAST_ACTION = 0 } },
    bars = {}, owned = {}, BAR_COUNT = 0,
    MarkAll = Noop, InvalidateProc = Noop,
    Painter = {
        slotMap = { [61] = { rec } }, Remap = Noop, api = { HasAction = function() return true end },
        Visible = function() reads = reads + 1 return true end,
        Tint = function() tints = tints + 1 end,
        Usable = function() usable = usable + 1 end,
    },
    Dirty = {
        slots = {}, grid = {}, protected = {}, reported = {}, gridFill = {}, gridHold = {}, spellCooldowns = {},
        Schedule = function() plans = plans + 1 end, WakeRetry = Noop, Mark = Noop, Reset = Noop,
    },
}
Constants = { SpellCooldownConsts = { GLOBAL_RECOVERY_CATEGORY = 133 } }
C_LossOfControl = { GetActiveLossOfControlDataCountByUnit = function() return 0 end }
local action = 2052
GetActionInfo = function() return "spell", action end
assert(loadfile(root .. "/MSUF_Suite_ActionBars/Events.lua"))("MSUF_Suite_ActionBars", {
    NS = { IsSecret = IsSecret, Client = { isForever = false } }, Suite = suite, ActionBars = actionBars,
})
actionBars.StartDispatcher()

local function Fire(event, ...) events[event](module, event, ...) end
local range, slot = "ACTION_RANGE_CHECK_UPDATE", "ACTIONBAR_SLOT_CHANGED"
Fire(range, 61, false, true)
assert(reads == 1 and tints == 1 and rec.outOfRange == true)
for _ = 1, 114 do Fire(range, 61, false, true) end
assert(reads == 1 and tints == 1, "unchanged range events rechecked bar visibility or painted")
Fire(range, 61, true, true)
assert(reads == 2 and usable == 1 and rec.outOfRange == nil, "a real range change failed to repaint")
Fire(range, SECRET, false, true)
assert(reads == 2 and tints == 1, "a secret slot reached a bar")

Fire(slot, 61)
for _ = 1, 114 do Fire(slot, 61) end
assert(plans == 1, "unchanged native slots queued grid work")
action = 2053
Fire(slot, 61)
assert(plans == 2, "a different slotted spell did not update its grid")
for _, event in ipairs({ range, slot }) do
    assert(options[event].direct and options[event].inCombat, "idle slot/range work entered the generic router")
end
module.config.rangeColoring = false
actionBars.SyncOptionalEvents()
assert(not events[range] and events[slot], "disabling range removed the wrong listener")
print("ActionBars idle events: 114 stable range updates skipped visibility reads; 114 stable slot events queued no grid work")
