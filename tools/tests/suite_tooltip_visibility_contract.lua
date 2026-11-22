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
local built, buildHooks, ownerReads = nil, 0, 0
suite.TooltipLines = { Add = function(_, kind, callback)
    assert(kind == "AllTypes")
    built = callback
    buildHooks = buildHooks + 1
end }
local tooltip = { shown = false, alpha = 1, scripts = {}, hooks = {} }
function tooltip:IsShown() return self.shown end
function tooltip:GetOwner() ownerReads = ownerReads + 1; return self.owner end
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
-- SetOwner and ClearLines clear the lines and run OnTooltipCleared; the tooltip
-- stays shown (GameTooltip.xml, SharedTooltipTemplates.xml).
function tooltip:Clear()
    self.tooltipType = nil
    if self.scripts.OnTooltipCleared then self.scripts.OnTooltipCleared(self) end
end
-- Plain SetText/AddLine content: no Blizzard data, so no TooltipData post-call;
-- Show() on a shown tooltip does not run OnShow again.
function tooltip:ShowPlain()
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
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
-- The tooltip's scale belongs to the Suite core's owner (TooltipScale.lua).
ApproximatelyEqual = function(a, b) return math.abs(a - b) < .000001 end
ns.Finite = function(value) return type(value) == "number" and value == value end
assert(loadfile(root .. "/MSUF_Suite/Core/TooltipScale.lua"))("MSUF_Suite", ns)
local context = { events = {} }
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end
assert(loadfile(root .. "/MSUF_Suite_Tooltips/TooltipVisibility.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(module)
module.active, module.context = true, context
module.config = { inCombat = false, inInstances = false, scale = 100 }
module:Enable()
for _ = 1, 20 do tooltip:Show() end
assert(buildHooks == 0 and ownerReads == 0, "scale-only tooltip registered visibility work")
tooltip:NativeHide()
-- A saved profile can still carry these legacy settings. Rebuilding in any
-- combination of world/instance and combat/normal uses the same rules.
module.config.inCombat, module.config.inInstances = true, true
module:Refresh()
assert(buildHooks == 0 and not next(context.events), "old profile installed combat or zone visibility work")
for _, inCombat in ipairs({ false, true }) do
    for _, inInstance in ipairs({ false, true }) do
        combat, instance = inCombat, inInstance
        tooltip.tooltipType = Enum.TooltipDataType.Item
        tooltip:Show()
        assert(tooltip.alpha == 1, "old visibility setting concealed a tooltip")
        tooltip:NativeHide()
    end
end
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
-- DA-2: a concealed tooltip that the client reuses for plain text without a
-- Hide in between (SetOwner/ClearLines run OnTooltipCleared) must come back; a
-- rebuild from Blizzard data is judged again by the post-call.
module.config.hideItems, module.config.hideSpells, module.config.hideUnits = true, false, false
module:Refresh()
tooltip.tooltipType = Enum.TooltipDataType.Item
tooltip:Show()
assert(tooltip.alpha == 0, "item tooltip was not concealed before the reuse")
tooltip:Clear()
tooltip:ShowPlain()
assert(tooltip.alpha == 1, "a concealed tooltip stayed invisible when reused for plain text")
tooltip.tooltipType = Enum.TooltipDataType.Item
tooltip:Show()
assert(tooltip.alpha == 0, "the rebuilt item tooltip was not concealed again")
tooltip:Clear()
tooltip.tooltipType = Enum.TooltipDataType.Spell
tooltip:Show()
assert(tooltip.alpha == 1, "a concealed tooltip stayed invisible when reused for an unselected type")
tooltip:Clear()
assert(tooltip.alpha == 1, "clearing an unconcealed tooltip changed its alpha")
tooltip:NativeHide()
for _, inCombat in ipairs({ false, true }) do
    for _, inInstance in ipairs({ false, true }) do
        combat, instance = inCombat, inInstance
        tooltip.tooltipType = Enum.TooltipDataType.Item
        tooltip:Show()
        assert(tooltip.alpha == 0, "filtered item visibility differed by combat or location")
        tooltip:Clear()
        tooltip.tooltipType = Enum.TooltipDataType.Spell
        tooltip:Show()
        assert(tooltip.alpha == 1, "unfiltered spell visibility differed by combat or location")
        tooltip:NativeHide()
    end
end
module.config.hideSpells, module.config.hideUnits = true, true
module:Refresh()
-- The shared GameTooltip also renders MSUF unit/group frame tooltips.
-- Their own Always/OOC/Modifier/Never setting must win over every QoL rule.
tooltip._msufUnitTooltipOwner = {}
module.config.inCombat, module.config.inInstances = true, true
combat, instance = true, true
module:Refresh()
tooltip:Show()
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
-- Turning off the last rule restores a tooltip already concealed by it.
tooltip.owner = nil
tooltip:Show()
assert(tooltip.alpha == 0)
for _, option in ipairs({ "inCombat", "inInstances", "hideItems", "hideSpells", "hideUnits" }) do
    module.config[option] = false
end
module:Refresh()
assert(tooltip.alpha == 1 and next(context.events) == nil, "last rule left a tooltip or listener hidden")
local reads = ownerReads
for _ = 1, 20 do tooltip:Show() end
assert(ownerReads == reads and tooltip.alpha == 1, "registered callback repeated inactive visibility work")
module.config.hideSpells = true
module:Refresh()
assert(buildHooks == 1 and tooltip.alpha == 0, "reenabling a rule lost or duplicated its rebuild handling")
module.active = false
module:Disable()
assert(tooltip.alpha == 1, "disable left the tooltip concealed")
tooltip:NativeHide()
tooltip:Show()
assert(tooltip.alpha == 1, "disabled module's permanent hook concealed the tooltip")
print("Suite tooltip visibility lifecycle passed")
