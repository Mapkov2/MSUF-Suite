local root = assert(arg[1], "repository root required")
local module
local frame = { enabled = { [101] = true, [102] = false, [103] = true, [104] = true, [105] = true }, writes = {} }
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
    and frame.enabled[103] == false,
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
print("Suite native UI error filter lifecycle passed")
