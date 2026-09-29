local root = assert(arg[1], "repository root required")
local secret, callbacks, timers, installed = {}, {}, {}, {}
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
GetTime = function() return now end
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
C_Timer = { NewTimer = function(delay, callback)
    assert(delay > 0)
    local timer = { delay = delay, callback = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end }
local function Fire(timer)
    assert(not timer.cancelled)
    now = now + timer.delay
    timer.callback()
end

local groupFrame = Widget()
groupFrame.MSUFUnitKey = "party1"
local observer
_G.MSUF_NS = { GF = {
    FrameForUnit = function(unit) if unit == "party1" then return groupFrame end end,
    RegisterFrameRegistryObserver = function(_, fn) observer = fn; return true end,
    UnregisterFrameRegistryObserver = function() observer = nil end,
} }
local locked = false
local S = { editMode = false }
S.Public = function(x) return x ~= secret end
S.PublicText = function(x) return S.Public(x) and type(x) == "string" and x ~= "" and x or nil end
S.Finite = function(x) return S.Public(x) and type(x) == "number" and x == x end
S.Text = function(x) return x end
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
    IsCombatLocked = function() return locked end,
}
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/InnervateCue.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })

local M = assert(installed.module)
M.active = true
M.config = { width = 280, height = 54, scale = 100, point = 5, x = 0, y = 180,
    openWorld = true, party = true, raid = true, sound = true, highlightTarget = true,
    targetName = "Healer-Realm", duration = 4 }
M.context = { Event = function(_, event, callback, allowCombat, unit)
    assert(allowCombat == true)
    callbacks[event] = callback
    if event == "UNIT_SPELLCAST_SUCCEEDED" then assert(unit == "player") end
end }
local function Event(name, ...)
    assert(callbacks[name], name .. " missing")
    callbacks[name](M, name, ...)
end

M:Enable()
assert(installed.mover and installed.mover.getFrame() == M.host
    and installed.mover.xKey == "x" and #installed.mover.extraControls == 3)
assert(not M.host.shown and M.glowAnchor == groupFrame and observer)
assert(M.host.mouse == false and M.glow.mouse == false)
Event("CHAT_MSG_WHISPER", secret, secret)
assert(M.host.shown and M.glow.shown and M.subtitle.text == "Incoming whisper" and sounds == 1,
    "secret whisper did not produce a generic cue on the cached target")
assert(M.host.width == 280 and M.host.point[4] == 0)
Fire(timers[#timers])
assert(not M.host.shown and not M.glow.shown, "cue was not hidden after one timer")

now = now + 6
cooldown = { startTime = now - 174, duration = 180, isEnabled = true }
Event("CHAT_MSG_WHISPER", "message", "Healer-Realm")
assert(not M.host.shown and not M.pending and not M.readyTimer,
    "cooldown longer than freshness window should not defer")

now = now + 6
cooldown.startTime = now - 177
Event("CHAT_MSG_WHISPER", "message", "Healer-Realm")
assert(M.pending and M.readyTimer and not M.host.shown, "near-ready whisper was not deferred")
Fire(M.readyTimer)
assert(M.host.shown and M.subtitle.text == "Healer-Realm whispered", "fresh pending cue did not appear")

Event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 29166)
assert(not M.host.shown and not M.glow.shown and M.fallbackReady == now + 180,
    "observed Innervate did not dismiss cue")
cooldown = secret
now = now + 6
Event("CHAT_MSG_WHISPER", secret, secret)
assert(not M.host.shown and not M.pending, "secret cooldown bypassed observed-cast fallback")

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
M:Disable()
M.active = false
assert(observer == nil and not M.host.shown and not M.glow.shown,
    "disable did not release observer and visuals")
assert(castReads > 0)
print("Innervate cue: secret whisper, cooldown, roster, mover and teardown passed")
