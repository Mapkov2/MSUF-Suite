local root = assert(arg[1], "repository root required")
local module, combat, instance = nil, false, false
local suite = {
    Install = function(_, value) module = value end,
    Public = function(value) return value ~= "secret" end,
}
local ns = {
    IsCombatLocked = function() return combat end,
    Safety = { IsForbidden = function() return false end },
}
IsInInstance = function() return instance, instance and "party" or "none" end
local tooltip = { shown = true, protected = false, hides = 0 }
Enum = { TooltipDataType = { Item = 1, Spell = 2, Unit = 3 } }
local typeCallbacks = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback)
    assert(not typeCallbacks[kind], "duplicate tooltip type callback")
    typeCallbacks[kind] = callback
end }
function tooltip:IsShown() return self.shown end
function tooltip:IsProtected() return self.protected end
function tooltip:IsTooltipType(kind)
    if self.tooltipType == "secret" then return "secret" end
    return self.tooltipType == kind
end
function tooltip:Hide() self.shown = false; self.hides = self.hides + 1 end
function tooltip:HookScript(name, callback)
    assert(name == "OnShow" and not self.onShow)
    self.onShow = callback
end
GameTooltip = tooltip
local context = { events = {} }
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipVisibility.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(module)
module.active, module.context = true, context
module.config = { inCombat = true, inInstances = false }
module:Enable()
assert(tooltip.onShow and context.events.PLAYER_REGEN_DISABLED
    and not context.events.PLAYER_ENTERING_WORLD, "combat-only tooltip listener was not selective")
tooltip.onShow()
assert(tooltip.shown, "tooltip was hidden outside combat")
combat = true
context.events.PLAYER_REGEN_DISABLED()
assert(not tooltip.shown and tooltip.hides == 1, "visible tooltip survived combat entry")
tooltip.shown, tooltip.protected = true, true
tooltip.onShow()
assert(tooltip.shown, "protected tooltip was hidden during combat")
combat = false
tooltip.protected = false
module.config.inCombat, module.config.inInstances = false, true
module:Refresh()
assert(not context.events.PLAYER_REGEN_DISABLED and context.events.PLAYER_ENTERING_WORLD,
    "disabled combat listener remained registered")
instance = true
context.events.PLAYER_ENTERING_WORLD()
assert(not tooltip.shown and tooltip.hides == 2, "instance tooltip rule did not apply")
instance = false
module.config.inInstances = false
module.config.hideItems = true
module:Refresh()
assert(typeCallbacks[1] and not typeCallbacks[2] and not typeCallbacks[3],
    "unselected tooltip types installed post-calls")
tooltip.shown, tooltip.tooltipType = true, Enum.TooltipDataType.Item
typeCallbacks[1]({})
assert(tooltip.shown, "another tooltip's data changed the main tooltip")
tooltip.shown, tooltip.tooltipType = true, Enum.TooltipDataType.Spell
typeCallbacks[1](tooltip)
assert(tooltip.shown, "unselected tooltip type was hidden")
tooltip.tooltipType = Enum.TooltipDataType.Item
typeCallbacks[1](tooltip)
assert(not tooltip.shown and tooltip.hides == 3, "item tooltip was not hidden")
tooltip.shown, tooltip.tooltipType = true, "secret"
typeCallbacks[1](tooltip)
assert(tooltip.shown, "secret tooltip type was interpreted")
module.config.hideItems, module.config.hideSpells, module.config.hideUnits = false, true, true
module:Refresh()
assert(typeCallbacks[2] and typeCallbacks[3], "newly selected tooltip types were not installed")
tooltip.shown, tooltip.tooltipType = true, Enum.TooltipDataType.Spell
typeCallbacks[2](tooltip)
assert(not tooltip.shown and tooltip.hides == 4, "spell tooltip was not hidden")
tooltip.shown, tooltip.tooltipType = true, Enum.TooltipDataType.Unit
typeCallbacks[3](tooltip)
assert(not tooltip.shown and tooltip.hides == 5, "unit tooltip was not hidden")
module.active = false
tooltip.shown = true
tooltip.onShow()
assert(tooltip.shown, "disabled module's permanent hook hid the tooltip")
typeCallbacks[3](tooltip)
assert(tooltip.shown, "disabled module's post-call hid the tooltip")
print("Suite tooltip visibility lifecycle passed")
