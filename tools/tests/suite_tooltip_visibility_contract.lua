local root = assert(arg[1], "repository root required")
local module, combat, instance = nil, false, false
local suite = {
    Install = function(_, value) module = value end,
    Public = function(value) return value ~= "secret" end,
}
-- The client turns InCombatLockdown() on only after PLAYER_REGEN_DISABLED;
-- Suite.InCombat(event) answers for that event (MSUF_Suite/Core/Platform.lua).
local ns = {
    IsCombatLocked = function() return combat end,
    InCombat = function(event)
        if event == "PLAYER_REGEN_DISABLED" then return true end
        if event == "PLAYER_REGEN_ENABLED" then return false end
        return combat
    end,
    Safety = { IsForbidden = function() return false end },
}
IsInInstance = function() return instance, instance and "party" or "none" end
Enum = { TooltipDataType = { Item = 1, Spell = 2, Unit = 3 } }
-- GameTooltip as addon code meets it: Hide() would run GameTooltip_OnHide in
-- the caller's context, so the helper must never call it.
local built
suite.TooltipLines = { Add = function(_, kind, callback)
    assert(kind == "AllTypes")
    built = callback
end }
local tooltip = { shown = false, alpha = 1, scripts = {}, hooks = {} }
function tooltip:IsShown() return self.shown end
function tooltip:GetOwner() return self.owner end
function tooltip:GetAlpha() return self.alpha end
function tooltip:SetAlpha(value) self.alpha = value end
function tooltip:IsTooltipType(kind)
    if self.tooltipType == "secret" then return "secret" end
    return self.tooltipType == kind
end
function tooltip:Show()
    if built then built(self, {}) end
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function tooltip:Hide() error("addon code ran GameTooltip_OnHide") end
function tooltip:NativeHide()
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function tooltip:HookScript(name, callback)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end; callback(...) end
end
hooksecurefunc = function(owner, key, callback)
    assert(owner ~= GameTooltip, "shared tooltip method hook is forbidden")
    local original = owner[key]
    owner[key] = function(...) original(...); callback(...) end
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
assert(context.events.PLAYER_REGEN_DISABLED and context.events.PLAYER_REGEN_ENABLED
    and not context.events.PLAYER_ENTERING_WORLD, "combat-only tooltip listener was not selective")
tooltip:Show()
assert(tooltip.alpha == 1, "tooltip was concealed outside combat")
-- Combat starts while the tooltip is shown; the lockdown flag is still off.
context.events.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
assert(tooltip.shown and tooltip.alpha == 0, "visible tooltip survived combat entry")
combat = true
tooltip:Show()
assert(tooltip.alpha == 0, "a rebuild in combat showed the tooltip")
combat = false
context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(tooltip.alpha == 1, "the tooltip stayed concealed after combat")
tooltip:NativeHide()
module.config.inCombat, module.config.inInstances = false, true
module:Refresh()
assert(not context.events.PLAYER_REGEN_DISABLED and context.events.PLAYER_ENTERING_WORLD,
    "disabled combat listener remained registered")
instance = true
tooltip:Show()
assert(tooltip.alpha == 0, "instance tooltip rule did not apply")
tooltip:NativeHide()
assert(tooltip.alpha == 1, "a concealed tooltip hid without its alpha back")
instance = false
module.config.inInstances = false
module.config.hideItems = true
module:Refresh()
tooltip.tooltipType = Enum.TooltipDataType.Spell
tooltip:Show()
assert(tooltip.alpha == 1, "unselected tooltip type was concealed")
tooltip.tooltipType = Enum.TooltipDataType.Item
tooltip:Show()
assert(tooltip.alpha == 0, "item tooltip was not concealed")
tooltip.tooltipType = Enum.TooltipDataType.Spell
tooltip:Show()
assert(tooltip.alpha == 1, "the next tooltip of an unselected type stayed concealed")
tooltip.tooltipType = "secret"
tooltip:Show()
assert(tooltip.alpha == 1, "secret tooltip type was interpreted")
module.config.hideItems, module.config.hideSpells, module.config.hideUnits = false, true, true
module:Refresh()
tooltip.tooltipType = Enum.TooltipDataType.Spell
tooltip:Show()
assert(tooltip.alpha == 0, "spell tooltip was not concealed")
tooltip.tooltipType = Enum.TooltipDataType.Unit
tooltip:Show()
assert(tooltip.alpha == 0, "unit tooltip was not concealed")
tooltip:NativeHide()
-- The shared GameTooltip also renders MSUF unit/group frame tooltips.
-- Their own Always/OOC/Modifier/Never setting must win over every QoL rule.
tooltip._msufUnitTooltipOwner = {}
module.config.inCombat, module.config.inInstances = true, true
combat, instance = true, true
module:Refresh()
tooltip:Show()
context.events.PLAYER_REGEN_DISABLED(module, "PLAYER_REGEN_DISABLED")
context.events.PLAYER_ENTERING_WORLD(module, "PLAYER_ENTERING_WORLD")
assert(tooltip.alpha == 1, "QoL overrode MSUF unitframe tooltip visibility")
tooltip._msufUnitTooltipOwner = nil
tooltip:Show()
assert(tooltip.alpha == 0, "QoL did not resume after MSUF released the tooltip")
tooltip:NativeHide()
-- Clickable aura reminders use GameTooltip for their configured item/spell,
-- while ordinary native auras use the separate AuraButtonTooltip.
tooltip.owner = { _msufA3CastTooltip = true }
tooltip:Show()
assert(tooltip.alpha == 1, "QoL concealed an MSUF aura reminder with its own tooltip switch")
tooltip.owner = {}
tooltip:Show()
assert(tooltip.alpha == 0, "aura reminder exemption leaked to another owner")
tooltip:NativeHide()
tooltip.owner._msufA3CastTooltip = "secret"
tooltip:Show()
assert(tooltip.alpha == 0, "a restricted owner field exempted a foreign tooltip")
module.active = false
module:Disable()
assert(tooltip.alpha == 1, "disable left the tooltip concealed")
tooltip:NativeHide()
tooltip:Show()
assert(tooltip.alpha == 1, "disabled module's permanent hook concealed the tooltip")
print("Suite tooltip visibility lifecycle passed")
