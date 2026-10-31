local root = assert(arg[1], "repository root required")
-- A saved setup starts with Essential off and no keybind consumers.
-- A native assisted suggestion arrives before its first Essential layout.
-- The existing post-placement event must reconcile its attachment even if
-- that suggestion remains unchanged. The callback disappears while off.
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
do (function()
local config = S.Config(ID)
-- A saved, already-initialized layout survives first-load default capture.
config.captured, config.defaultsVersion = true, Suite.CDM.DEFAULTS_VERSION
config.assistIcon, config.assistIconAnchor = true, 2
config.assistIconX, config.assistIconY = 13, -19
config.assistIconKeybind, config.ess_on = false, false
for _, slot in ipairs(Suite.CDM.SLOTS) do
    local key = Suite.CDM.KEYS[slot.key].keybind
    if key then config[key] = false end
end
cvars.assistedCombatHighlight = "1"
AssistedCombatManager.lastNextCastSpellID = 101
assert(C.bars.ess == nil and C.Effects.RecommendationFrame() == nil,
    "cold fixture already created the Essential bar or recommendation")
-- The mature fixture records callbacks; this case also dispatches the one
-- real placement event as Blizzard's EventRegistry does.
local trigger = EventRegistry.TriggerEvent
EventRegistry.TriggerEvent = function(self, event, ...)
    trigger(self, event, ...)
    local callback = registry[event]
    if callback then callback.fn(callback.owner, ...) end
end
module.config, module.context, module.active = config, S.NewContext(ID), true
module:Enable()
Run()
local icon = assert(C.Effects.RecommendationFrame(), "the initial suggestion did not show")
assert(C.bars.ess == nil and icon.point[2] == UIParent, "an off Essential bar should leave the fallback active")
config.ess_on = true
module:Refresh()
Run()
local essential = assert(C.bars.ess, "the first real placement created no Essential bar")
assert(icon.point[2] == essential.frame and icon.point[4] == 13 and icon.point[5] == -19,
    "cold assisted icon kept the UIParent fallback after Essential placement")
local before = writes
local highlight = assert(registry["AssistedCombatManager.OnAssistedHighlightSpellChange"])
highlight.fn(highlight.owner)
assert(writes == before and icon.point[2] == essential.frame,
    "an unchanged suggestion should need no repaint to finish the attachment")
before = writes
EventRegistry:TriggerEvent(ANCHOR_EVENT)
assert(writes == before, "settled attachment repeated widget writes")
config.assistIconAnchor = 1
module:Refresh(); Run()
assert(registry[ANCHOR_EVENT] == nil and icon.point[2] == UIParent,
    "free recommendation kept its placement subscription")
config.assistIconAnchor = 2
module:Refresh(); Run()
assert(icon.point[2] == essential.frame, "reattaching lost placement ownership")
config.assistIcon = false
module:Refresh(); Run()
assert(registry[ANCHOR_EVENT] == nil, "disabled recommendation kept a placement callback")
local place, calls = C.Effects.RecommendationPlace, 0
C.Effects.RecommendationPlace = function(...) calls = calls + 1; return place(...) end
before = writes
for i = 1, 10 do EventRegistry:TriggerEvent(ANCHOR_EVENT) end
assert(calls == 0 and writes == before, "disabled recommendation did placement work")
C.Effects.RecommendationPlace = place
config.assistIcon = true
module:Refresh(); Run()
assert(icon.point[2] == essential.frame, "re-enable did not restore the attachment")
module.active = false
module:Disable()
assert(registry[ANCHOR_EVENT] == nil, "module release retained its placement callback")
print("PASS assisted icon: cold Essential placement, unchanged suggestion, memoized events, free/off/re-enable/release")
end)() end
]=], "------------------------------------------------------------------ enable: capture")
