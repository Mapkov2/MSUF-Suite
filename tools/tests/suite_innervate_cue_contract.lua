local root = assert(arg[1], "repository root required")
local secret, callbacks, installed = {}, {}, {}
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local reported = {}
local now, combat, inInstance, instanceType = 100, true, false, "none"
local spellKnown, cooldown = true, { startTime = 0, duration = 0, isEnabled = true }
local rosterName, rosterRealm = "Healer", "Realm"
local castReads, sounds = 0, 0

local function Widget()
    local w = { shown = true }
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:SetSize(x, y) self.width, self.height = x, y end
    function w:SetScale(x) self.scale = x end
    function w:SetFrameStrata() end
    function w:EnableMouse(x) self.mouse = x end
    function w:SetAllPoints() end
    function w:SetColorTexture() end
    function w:SetTexture() end
    function w:SetPoint(...) self.point = { ... } end
    function w:ClearAllPoints() end
    function w:SetJustifyH() end
    function w:SetFont() end
    function w:SetTextColor() end
    function w:SetText(x) self.text = x end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsVisible() return self.shown end
    function w:IsForbidden() return false end
    return w
end

UIParent = Widget()
SOUNDKIT = { RAID_WARNING = 1 }
PlaySound = function() sounds = sounds + 1 end
UnitAffectingCombat = function() return combat end
IsInInstance = function() return inInstance, instanceType end
UnitExists = function(unit) return unit == "player" or unit == "party1" end
UnitFullName = function(unit)
    if unit == "party1" then return rosterName, rosterRealm end
    return "Druid", "Realm"
end
IsInRaid = function() return false end
GetNumGroupMembers = function() return 2 end
C_Spell = {
    GetSpellTexture = function() return 123 end,
    GetSpellCooldown = function(id)
        assert(id == 29166)
        castReads = castReads + 1
        return cooldown
    end,
}
C_SpellBook = { IsSpellKnown = function(id) assert(id == 29166); return spellKnown end }
local clock = Support.Clock(now)

local groupFrame = Widget()
groupFrame.MSUFUnitKey = "party1"
local observer
_G.MSUF_NS = { GF = {
    FrameForUnit = function(unit) if unit == "party1" then return groupFrame end end,
    RegisterFrameRegistryObserver = function(_, fn) observer = fn; return true end,
    UnregisterFrameRegistryObserver = function() observer = nil end,
} }
local locked = false
local S = { editMode = false, Dispatch = Support.Dispatcher(reported) }
S.Public = function(x) return x ~= secret end
S.PublicText = function(x) return S.Public(x) and type(x) == "string" and x ~= "" and x or nil end
S.Finite = function(x) return S.Public(x) and type(x) == "number" and x == x end
-- German texts prove that every shown string goes through the translation.
local GERMAN = { ["Innervate whisper cue"] = "Anregen-Flüsterhinweis", ["%s whispered"] = "%s hat geflüstert",
    ["Incoming whisper"] = "Eingehendes Flüstern" }
S.Text = function(x) return GERMAN[x] or x end
S.CreateFrame = function() return Widget() end
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.PlaceEdges = function() end
S.SetFont = function() end
S.Install = function(id, module) assert(id == "innervateCue"); installed.module = module end
S.RegisterOwnedMover = function(id, element, spec)
    assert(id == "innervateCue" and element == "alert")
    installed.mover = spec
end
S.Config = function() return installed.module.config end
S.Set = function(_, key, value)
    installed.module.config[key] = value
    installed.module:Refresh()
    return true
end
local NS = {
    AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER" },
    IsCombatLocked = function() return locked end, Dispatch = S.Dispatch,
}
assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, S)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/InnervateCue.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })

local M = assert(installed.module)
M.active = true
M.config = { width = 280, height = 54, scale = 100, point = 5, x = 0, y = 180,
    openWorld = true, party = true, raid = true, sound = true, highlightTarget = true,
    targetName = "Healer-Realm", duration = 4 }
M.context = Support.ModuleTimers(root, S, NS)("innervateCue", M, { Event = function(_, event, callback, allowCombat, unit)
    assert(allowCombat == true)
    callbacks[event] = callback
    if event == "UNIT_SPELLCAST_SUCCEEDED" then assert(unit == "player") end
end })
local function Event(name, ...)
    assert(callbacks[name], name .. " missing")
    callbacks[name](M, name, ...)
end

M:Enable()
assert(installed.mover and installed.mover.getFrame() == M.host
    and installed.mover.xKey == "x" and not installed.mover.extraControls
    and table.concat(installed.mover.sizeKeys, ",") == "width,height,scale")
assert(not M.host.shown and M.glowAnchor == groupFrame and observer)
assert(M.host.mouse == false and M.glow.mouse == false)
Event("CHAT_MSG_WHISPER", secret, secret)
assert(M.host.shown and M.glow.shown and M.subtitle.text == "Eingehendes Flüstern" and sounds == 1
    and M.title.text == "Anregen-Flüsterhinweis",
    "secret whisper did not produce a generic cue on the cached target")
assert(M.host.width == 280 and M.host.point[4] == 0)
clock.Advance(3.9)
assert(M.host.shown, "the cue hid before its duration")
clock.Advance(.2)
assert(not M.host.shown and not M.glow.shown, "cue was not hidden after its duration")

clock.Advance(6)
cooldown = { startTime = GetTime() - 174, duration = 180, isEnabled = true }
Event("CHAT_MSG_WHISPER", "message", "Healer-Realm")
assert(not M.host.shown and not M.pending, "cooldown longer than freshness window should not defer")

clock.Advance(6)
cooldown.startTime = GetTime() - 177
Event("CHAT_MSG_WHISPER", "message", "Healer-Realm")
assert(M.pending and not M.host.shown, "near-ready whisper was not deferred")
clock.Advance(3.05)
assert(M.host.shown and M.subtitle.text == "Healer-Realm hat geflüstert", "fresh pending cue did not appear")

Event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 29166)
assert(not M.host.shown and not M.glow.shown and M.fallbackReady == GetTime() + 180,
    "observed Innervate did not dismiss cue")
clock.Advance(5)
assert(not M.host.shown, "a dismissed cue came back on its old timeout")
cooldown = secret
clock.Advance(6)
Event("CHAT_MSG_WHISPER", secret, secret)
assert(not M.host.shown and not M.pending, "secret cooldown bypassed observed-cast fallback")

-- Zone switches (S.InstanceKind): dungeons, scenarios, battlegrounds and
-- arenas share the group switch; an unreadable instance state shows nothing.
cooldown, M.fallbackReady = { startTime = 0, duration = 0, isEnabled = true }, nil
for _, case in ipairs({ { "arena", "party" }, { "scenario", "party" }, { "raid", "raid" } }) do
    inInstance, instanceType = true, case[1]
    M.config[case[2]] = false
    clock.Advance(6)
    Event("CHAT_MSG_WHISPER", "message", "Healer-Realm")
    assert(not M.host.shown, case[1] .. " ignored its switch")
    M.config[case[2]] = true
    clock.Advance(6)
    Event("CHAT_MSG_WHISPER", "message", "Healer-Realm")
    assert(M.host.shown, case[1] .. " did not show the cue")
    clock.Advance(4.1)
end
inInstance = secret
clock.Advance(6)
Event("CHAT_MSG_WHISPER", "message", "Healer-Realm")
assert(not M.host.shown, "an unreadable instance state showed the cue")
inInstance, instanceType = false, "none"

locked = true
Event("GROUP_ROSTER_UPDATE")
assert(M.glowAnchor == nil, "combat roster change retained stale target frame")
locked = false
Event("PLAYER_REGEN_ENABLED")
assert(M.glowAnchor == groupFrame, "target frame was not resolved after combat")

S.editMode = true
M:Refresh()
assert(M.host.shown, "Edit Mode did not preview the alert")
S.editMode = false
M:Refresh()
assert(not M.host.shown, "Edit Mode preview did not close")
-- MSUF calls the observer inside its registry update: the cue's error is
-- reported there and never raises into MSUF's notification loop.
local frameForUnit = _G.MSUF_NS.GF.FrameForUnit
_G.MSUF_NS.GF.FrameForUnit = function() error("group frame lookup raised") end
observer("add", groupFrame)
assert(#reported == 1, "an observer error raised into MSUF's registry update")
_G.MSUF_NS.GF.FrameForUnit = frameForUnit
M:Disable()
M.active = false
assert(observer == nil and not M.host.shown and not M.glow.shown,
    "disable did not release observer and visuals")
-- An MSUF build without the observer leave call still disables cleanly.
M.active = true
M:Enable()
_G.MSUF_NS.GF.UnregisterFrameRegistryObserver = nil
M:Disable()
M.active = false
assert(not M.observedGF and #reported == 1, "disable raised on an MSUF without the observer leave call")
assert(castReads > 0)
print("Innervate cue: secret whisper, cooldown, roster, mover and teardown passed")
