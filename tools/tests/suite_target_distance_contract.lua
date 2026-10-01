local root = assert(arg[1], "repository root required")
local secret, module, target, enemy = {}, nil, false, true
local subscriptions, values, reads, lookups = {}, {}, 0, 0
local subscriptionCalls = 0
local deferred = {}
wipe = function(t) for key in pairs(t) do t[key] = nil end end
C_Timer = { After = function(delay, callback) assert(delay == 0); deferred[#deferred + 1] = callback end }
local function Flush()
    local callbacks = deferred; deferred = {}
    for _, callback in ipairs(callbacks) do callback() end
end
local spells = {
    { spellID = 1, minRange = 0, maxRange = 10, harmful = true },
    { spellID = 2, minRange = 0, maxRange = 30, harmful = true },
    { spellID = 3, minRange = 0, maxRange = 30, harmful = true },
    { spellID = 4, minRange = 5, maxRange = 40, harmful = true },
    { spellID = 5, minRange = 0, maxRange = 0, harmful = true },
    { spellID = 6, minRange = 0, maxRange = 40, helpful = true },
    { spellID = 7, minRange = 0, maxRange = secret, harmful = true },
}
local function Widget()
    local w = { scale = 1 }
    for _, key in ipairs({ "EnableMouse", "SetAllPoints", "SetWordWrap", "ClearAllPoints", "SetSize", "SetTextColor" }) do
        w[key] = function() end
    end
    function w:SetPoint(...) self.point = { ... } end
    function w:SetText(value) self.text = value end
    function w:SetJustifyH(value) self.align = value end
    function w:SetShown(value) self.shown = value end
    function w:SetScale(value) self.scale = value end
    function w:GetEffectiveScale() return self.scale end
    function w:GetCenter() return self.centerX, self.centerY end
    function w:GetBottom() return self.bottom end
    function w:Hide() self.shown = false end
    function w:SetScript(name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end
    function w:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... }; self.point = { ... } end
    function w:ClearAllPoints() self.points = {} end
    return w
end
UIParent, TargetFrame = Widget(), Widget()
TargetFrame.centerX, TargetFrame.centerY, TargetFrame.bottom = 300, 500, 450
Enum = { SpellBookSpellBank = { Player = 0 } }
UnitExists = function() return target end
UnitCanAttack = function() return enemy end
UnitCanAssist = function() return not enemy end
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #spells } end,
    GetSpellBookItemInfo = function(slot)
        lookups = lookups + 1
        return { spellID = spells[slot].spellID, isPassive = false, isOffSpec = false }
    end,
    IsSpellKnown = function() return true end,
}
C_Spell = {
    GetSpellInfo = function(id) return spells[id] end,
    IsSpellHarmful = function(id) return spells[id].harmful == true end,
    IsSpellHelpful = function(id) return spells[id].helpful == true end,
    IsSpellInRange = function(id) reads = reads + 1; return values[id] end,
}
local S = {
    Install = function(_, m) module = m end,
    Public = function(v) return v ~= secret end,
    Finite = function(v) return type(v) == "number" end,
    Text = function(v) return v end, CreateFrame = Widget, CreateFontString = Widget,
    SetStyledFont = function() end, GlobalFontPath = function() return "font" end,
    RGB = function() return 1, 1, 1 end, RegisterOwnedMover = function() end,
    SetNativeSpellRange = function(owner, id, enabled)
        assert(owner == "targetDistance")
        subscriptionCalls = subscriptionCalls + 1
        subscriptions[id] = enabled or nil
    end,
    ClearNativeSpellRanges = function(owner)
        assert(owner == "targetDistance")
        subscriptionCalls = subscriptionCalls + 1
        subscriptions = {}
    end,
}
local movers = {}
S.RegisterOwnedMover = function(id, element, spec) assert(id == "targetDistance"); movers[element] = spec end
local combat = false
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TargetDistance.lua"))("test",
    { NS = { Client = {}, IsCombatLocked = function() return combat end }, Suite = S })
module.active, module.config = true, { x = 0, y = -160, attachX = 0, attachY = -8 }
module.context = { events = {}, Event = function(self, event, fn) self.events[event] = fn end,
    RemoveEvent = function(self, event) self.events[event] = nil end }
local function Fire(event, ...) assert(module.context.events[event], event)(module, event, ...) end
module:Enable()
assert(not module.host.shown and not next(subscriptions) and reads == 0)
assert(movers.distance.visible() and not movers.attached.visible(), "free placement mover missing")
values[1], values[2], target = false, true, true
Fire("PLAYER_TARGET_CHANGED")
assert(module.host.shown and module.label.text == "10-30 yd")
assert(subscriptions[1] and subscriptions[2] and not subscriptions[3] and not subscriptions[4] and not subscriptions[5])
assert(not subscriptions[7], "secret range metadata must never become a threshold")
local beforeReads, beforeLookups = reads, lookups
Fire("SPELL_RANGE_CHECK_UPDATE", 1, true, true)
assert(module.label.text == "<=10 yd")
Fire("SPELL_RANGE_CHECK_UPDATE", 2, false, true)
assert(module.label.text == "-- yd", "contradictory native checks must not fabricate a range")
Fire("SPELL_RANGE_CHECK_UPDATE", 1, secret, true)
assert(module.label.text == ">30 yd")
Fire("SPELL_RANGE_CHECK_UPDATE", 2, false, false)
assert(module.label.text == "-- yd")
assert(reads == beforeReads and lookups == beforeLookups, "range updates must not rescan or query ranges")
-- Tab-targeting another enemy keeps the native subscriptions and reads again.
local churn = subscriptionCalls
values[1], values[2] = true, true
Fire("PLAYER_TARGET_CHANGED")
assert(subscriptionCalls == churn and reads == beforeReads + 2 and module.label.text == "<=10 yd",
    "a target of the same kind re-subscribed the range probes")
enemy, values[6] = false, true; Fire("PLAYER_TARGET_CHANGED")
assert(subscriptions[6] and not subscriptions[1] and not subscriptions[2] and module.label.text == "<=40 yd")
assert(module.host.point[2] == UIParent and module.host.point[4] == 0 and module.host.point[5] == -160)
-- Below the target frame: the display copies the frame's position from its
-- own offsets and never anchors to the secure target frame.
module.config.format, module.config.align, module.config.attachTarget = "Range {range} ({unit})", 3, true
MSUF_target = Widget()
MSUF_target.centerX, MSUF_target.centerY, MSUF_target.bottom, MSUF_target.scale = 400, 300, 250, 2
module:Refresh()
assert(module.label.text == "Range <=40 (yd)" and module.label.align == "RIGHT")
local point = module.host.point
assert(point[1] == "TOP" and point[2] == UIParent and point[3] == "BOTTOMLEFT"
    and point[4] == 800 and point[5] == 492, "attached display did not sit 8 px below the copied target rect")
assert(movers.attached.visible() and not movers.distance.visible(), "attached placement mover missing")
module.host.point = nil
target, enemy = true, true; Fire("PLAYER_TARGET_CHANGED")
assert(module.host.point == nil, "a target change re-anchored the display")
-- When the target frame moves, the probe anchored to it reports the move and
-- the display copies the new rect; only the probe anchors to the frame.
local probe = assert(module.probe, "no probe watches the target frame")
assert(probe.points[2][2] == MSUF_target and probe.points[2][3] == "BOTTOM" and point[2] == UIParent,
    "the probe must anchor to the target frame, the display to UIParent")
MSUF_target.centerX, MSUF_target.bottom = 450, 260
combat = true
probe.scripts.OnSizeChanged()
assert(module.host.point[4] == 900 and module.host.point[5] == 512, "a moved target frame left the display behind")
combat = false
MSUF_target.centerX, MSUF_target.bottom = 400, 250
probe.scripts.OnSizeChanged()
module.host.scale = 2
movers.attached.place(10, -20)
assert(module.host.point[4] == 410 and module.host.point[5] == 230, "Edit Mode drag ignored the display's own scale")
module.host.scale = 1
-- A target frame that was never laid out has no rect yet: the display waits
-- at its free position and copies the rect on the next target.
MSUF_target = Widget()
module:Refresh()
assert(module.host.point[3] == "CENTER" and module.placePending, "missing target rect was not deferred")
MSUF_target.centerX, MSUF_target.centerY, MSUF_target.bottom = 100, 200, 150
Fire("PLAYER_TARGET_CHANGED")
assert(module.host.point[4] == 100 and module.host.point[5] == 142 and not module.placePending,
    "the deferred target rect was never copied")
MSUF_target = nil; module:Refresh(); assert(module.host.point[4] == 300 and module.host.point[5] == 442,
    "the native target frame was not used without MSUF's frame")
assert(module.watched == TargetFrame and probe.points[2][2] == TargetFrame, "the probe kept watching a gone frame")
combat = true
MSUF_target = Widget()
MSUF_target.centerX, MSUF_target.centerY, MSUF_target.bottom = 100, 200, 150
module:Refresh()
assert(module.watched == TargetFrame, "the probe re-anchored in combat")
combat = false
MSUF_target = nil
module.config.attachTarget = false; module:Refresh()
assert(module.watched == nil and #probe.points == 0, "a free display kept the probe on the target frame")
module.config.attachTarget = true; module:Refresh()
assert(lookups == beforeLookups, "format and attachment edits must reuse discovery")
Fire("SPELLS_CHANGED"); Fire("SPELLS_CHANGED"); Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
assert(#deferred == 1 and lookups == beforeLookups, "spellbook bursts must coalesce until the next frame")
Flush(); assert(lookups == beforeLookups + #spells and subscriptions[1], "rediscovery dropped the probes")
-- SPELLS_CHANGED also fires for spell overrides and procs: an unchanged
-- spellbook layout keeps the probes; a changed one, a talent commit or a
-- learned spell finds them again.
beforeLookups = lookups
for _ = 1, 5 do Fire("SPELLS_CHANGED") end
assert(#deferred == 0 and lookups == beforeLookups, "an unchanged spellbook was scanned again")
spells[8] = { spellID = 8, minRange = 0, maxRange = 25, harmful = true }
Fire("SPELLS_CHANGED")
assert(#deferred == 1, "a changed spellbook layout was not scanned again")
Flush(); assert(lookups == beforeLookups + #spells, "the changed spellbook was not scanned")
spells[8] = nil
Fire("SPELLS_CHANGED"); Flush()
for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "LEARNED_SPELL_IN_SKILL_LINE" }) do
    beforeLookups = lookups
    Fire(event, 12345)
    assert(#deferred == 1, event .. " did not find the probes again")
    Flush(); assert(lookups == beforeLookups + #spells, event .. " did not scan the spellbook")
end
target = false; Fire("PLAYER_TARGET_CHANGED")
assert(not module.host.shown and not next(subscriptions) and not module.context.events.SPELL_RANGE_CHECK_UPDATE)
S.editMode = true; module:Refresh()
assert(module.host.shown and module.label.text == "Range 10-30 (yd)" and not next(subscriptions))
S.editMode, target, enemy = false, true, true
Fire("PLAYER_ENTERING_WORLD", true, false)
Flush()
assert(subscriptions[1], "world-entry boolean payload must not be mistaken for a unit token")
Fire("TRAIT_CONFIG_UPDATED", 12345); beforeLookups = lookups
module:Disable(); Flush()
assert(not module.host.shown and not next(subscriptions))
assert(lookups == beforeLookups, "disabled owners must cancel pending discovery")
print("Target range estimate: bounded discovery, kind-scoped subscriptions, copied target rect, secrets, formatting and cleanup passed")
