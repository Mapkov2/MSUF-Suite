local root = assert(arg[1], "repository root required")
local module
local frame = { enabled = { [101] = true, [102] = false, [103] = true, [104] = true, [105] = true }, writes = {} }
frame.enabled[106], frame.enabled[107], frame.enabled[108] = true, true, false
frame.enabled[109], frame.enabled[110], frame.enabled[111] = true, true, true
function frame:ShouldDisplayMessageType(id)
    return self.enabled[id]
end
function frame:SetMessageTypeEnabled(id, enabled)
    self.enabled[id] = enabled
    self.writes[#self.writes + 1] = { id, enabled }
end
UIErrorsFrame = frame
LE_GAME_ERR_SPELL_OUT_OF_RANGE = 101
LE_GAME_ERR_GENERIC_NO_VALID_TARGETS = 102
LE_GAME_ERR_OUT_OF_MANA = 103
LE_GAME_ERR_ITEM_COOLDOWN = 104
LE_GAME_ERR_CANT_USE_ITEM = 105
LE_GAME_ERR_OUT_OF_ENERGY = 106
LE_GAME_ERR_OUT_OF_RAGE = 107
LE_GAME_ERR_OUT_OF_FOCUS = 108
LE_GAME_ERR_OUT_OF_RUNES = 109
LE_GAME_ERR_OUT_OF_POWER_DISPLAY = 110
LE_GAME_ERR_OUT_OF_HEALTH = 111

local context = { events = {} }
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end
local suite = {
    Install = function(_, value) module = value end,
    Public = function(value) return value ~= nil end,
    Finite = function(value) return type(value) == "number" end,
}
local ns = { Safety = { IsForbidden = function() return false end } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/UIErrorFilter.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(module)
module.context, module.config = context, { range = true, target = true }
module:Enable()
assert(frame.enabled[101] == false and frame.enabled[102] == false
    and #frame.writes == 1 and not context.events.ADDON_LOADED,
    "selected error filter changed a type already disabled by another owner")
module:Refresh()
assert(#frame.writes == 1, "refresh rewrote unchanged Blizzard error settings")

module.config.range, module.config.target, module.config.mana = false, false, true
module:Refresh()
assert(frame.enabled[101] == true and frame.enabled[102] == false
    and frame.enabled[103] == false and frame.enabled[106] and frame.enabled[107],
    "switching choices did not restore their individual previous states")
module:Disable()
assert(frame.enabled[103] == true and #frame.writes == 4,
    "disabling the module did not restore its final setting")

UIErrorsFrame = nil
module.config.mana = true
module:Enable()
assert(context.events.ADDON_LOADED, "late Blizzard error frame has no load retry")
UIErrorsFrame = frame
context.events.ADDON_LOADED(module)
assert(frame.enabled[103] == false and not context.events.ADDON_LOADED,
    "late Blizzard error frame did not receive the selected filter")
module:Disable()
assert(frame.enabled[103] == true, "late frame did not restore its state")

module.config.mana, module.config.resources = false, true
module:Enable()
assert(frame.enabled[106] == false and frame.enabled[107] == false and frame.enabled[108] == false
    and frame.enabled[109] == false and frame.enabled[110] == false,
    "the resource filter did not suppress non-mana power errors")
assert(frame.enabled[103] and frame.enabled[111], "the resource filter also hid mana or health errors")

module.config.mana = true
module:Refresh()
assert(frame.enabled[103] == false and frame.enabled[106] == false, "the two resource filters did not compose")
module.config.resources = false
module:Refresh()
assert(frame.enabled[103] == false and frame.enabled[106] and frame.enabled[107] and frame.enabled[109]
    and frame.enabled[110] and frame.enabled[108] == false,
    "turning off the resource filter did not restore the prior Blizzard settings")
module:Disable()
assert(frame.enabled[103], "the mana filter did not restore its state after the resource filter was disabled")
print("Suite native UI error filter lifecycle passed")
