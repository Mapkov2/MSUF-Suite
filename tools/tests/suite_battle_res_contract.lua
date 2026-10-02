local root = assert(arg[1], "repository root required")
local callbacks, timers, installed = {}, {}, {}
local instanceType, challenge, encounter, charges = "none", false, false, nil
local chargeReads, displayReads, durationReads = 0, 0, 0

local function Widget()
    local w = { shown = true }
    function w:CreateTexture() return Widget() end
    function w:CreateFontString() return Widget() end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetScale(value) self.scale = value end
    function w:SetFrameStrata() end
    function w:EnableMouse(value) self.mouse = value end
    function w:SetAllPoints() end
    function w:SetColorTexture() end
    function w:SetTexture(value) self.texture = value end
    function w:SetPoint(...) self.point = { ... } end
    function w:ClearAllPoints() end
    function w:SetDrawEdge() end
    function w:SetHideCountdownNumbers(value) self.hideNumbers = value end
    function w:SetMinimumCountdownDuration(value) self.minimumCountdown = value end
    function w:SetTextColor() end
    function w:SetFont() end
    function w:SetText(value) self.text = value end
    function w:SetFormattedText(format, ...)
        self.text, self.formatted = format:format(...), (self.formatted or 0) + 1
    end
    function w:SetCooldown(start, duration) self.preview = { start, duration } end
    function w:SetCooldownFromDurationObject(value) self.duration = value; self.preview = nil end
    function w:Clear() self.duration, self.preview = nil, nil end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
end

UIParent = Widget()
GetTime = function() return 25 end
GetInstanceInfo = function() return "Test", instanceType end
-- The deprecated global exists only while loadDeprecationFallbacks is on;
-- the module must use the namespaced API.
IsEncounterInProgress = nil
C_InstanceEncounter = { IsEncounterInProgress = function() return encounter end }
C_ChallengeMode = { IsChallengeModeActive = function() return challenge end }
C_Spell = {
    GetSpellTexture = function(id) assert(id == 20484); return 123 end,
    GetSpellCharges = function(id) assert(id == 20484); chargeReads = chargeReads + 1; return charges end,
    GetSpellDisplayCount = function(id)
        assert(id == 20484)
        displayReads = displayReads + 1
        return charges.display
    end,
    GetSpellChargeDuration = function(id)
        assert(id == 20484)
        durationReads = durationReads + 1
        return charges.duration
    end,
}
C_Timer = { After = function(delay, callback)
    assert(delay == .2)
    timers[#timers + 1] = callback
end }
local function Drain()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
end

local secret = {}
local S = { editMode = false }
S.Text = function(value) return value end
S.Public = function(value) return value ~= secret end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.CreateFrame = function() return Widget() end
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.CreateFontString = function(parent) return parent:CreateFontString() end
S.PlaceEdges = function() end
S.SetFont = function(fontString) fontString:SetFont() end
S.Install = function(id, module) assert(id == "battleRes"); installed.module = module end
S.RegisterOwnedMover = function(id, element, spec)
    assert(id == "battleRes" and element == "charges")
    installed.mover = spec
end
S.Config = function(id) assert(id == "battleRes"); return installed.module.config end
S.Set = function(id, key, value)
    S.Config(id)[key] = value
    installed.module:Refresh()
    return true
end
local NS = {
    AnchorPoints = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
    MSUFMedia = { font = "MSUF.ttf" },
    IsCombatLocked = function() return false end,
    Dispatch = function(callback, ...) return callback(...) end,
}
NS.Suite = S
assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, S)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/BattleRes.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })

local M = assert(installed.module)
M.active = true
M.config = { width = 146, height = 44, scale = 100, point = 5, x = 10, y = 120 }
M.context = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().ModuleTimers(root, S, NS)("battleRes", M, {
    Event = function(_, event, callback, allowCombat)
        assert(dofile(root .. "/tools/tests/suite_test_support.lua").InCombatOption(allowCombat))
        callbacks[event] = callback
    end,
    RemoveEvent = function(_, event) callbacks[event] = nil end,
})
local function Event(name)
    assert(callbacks[name], name .. " is not registered")
    callbacks[name](M, name)
end

charges = { currentCharges = 1, maxCharges = 1, isActive = false, display = "1" }
M:Enable()
assert(not M.host.shown and not callbacks.SPELL_UPDATE_CHARGES and chargeReads == 0,
    "idle tracker read personal charges or listened to charge changes")
assert(M.host.mouse == false and M.cooldown.hideNumbers == false and M.cooldown.minimumCountdown == 0,
    "tracker captures input or hides the native countdown")
assert(installed.mover and installed.mover.getFrame() == M.host
    and installed.mover.xKey == "x" and installed.mover.yKey == "y"
    and installed.mover.pointKey == "point" and installed.mover.quickPosition
    and installed.mover.sizeKeys and table.concat(installed.mover.sizeKeys, ",") == "width,height,scale"
    and not installed.mover.extraControls, "Edit Mode mover or size controls are missing")
assert(M.host.width == 146 and M.host.height == 44 and M.host.scale == 1)
-- MSUF Edit Mode's size controls write these keys through S.Set.
S.Set("battleRes", "width", 200)
S.Set("battleRes", "height", 60)
S.Set("battleRes", "scale", 125)
assert(M.host.width == 200 and M.host.height == 60 and M.host.scale == 1.25
    and M.cooldown.duration == nil,
    "battle resurrection popup size did not reach its frame safely")
assert(M.host.point[1] == "CENTER" and M.host.point[4] == 10 and M.host.point[5] == 120)

instanceType, challenge = "party", true
charges = { currentCharges = 2, maxCharges = 3, isActive = true,
    display = "2", duration = {} }
Event("CHALLENGE_MODE_START")
assert(M.host.shown and M.count.text == "2" and M.maximum.text == "/3"
    and M.cooldown.duration == charges.duration and callbacks.SPELL_UPDATE_CHARGES,
    "active Mythic+ charges or native countdown did not appear")
local readBefore = chargeReads
charges = { currentCharges = 1, maxCharges = 3, isActive = true,
    display = "1", duration = {} }
local formatted = M.maximum.formatted or 0
Event("SPELL_UPDATE_CHARGES")
assert(chargeReads == readBefore + 1 and M.count.text == "1" and M.cooldown.duration == charges.duration,
    "charge event did not refresh count and next recharge")
-- The pool size goes to the native formatter: no Lua string per charge event.
assert(M.maximum.formatted == formatted + 1 and M.maximum.text == "/3",
    "the pool size was built as a Lua string on a charge event")

-- Current charge and time are allowed to be secret in combat. The display
-- string and duration object must flow directly to native UI setters.
charges = { currentCharges = secret, cooldownStartTime = secret,
    cooldownDuration = secret, maxCharges = 3, isActive = true,
    display = secret, duration = secret }
Event("SPELL_UPDATE_CHARGES")
assert(M.host.shown and M.count.text == secret and M.cooldown.duration == secret,
    "secret charge data was compared, formatted or discarded")

charges = { currentCharges = 3, maxCharges = 3, isActive = false,
    display = "3", duration = {} }
Event("SPELL_UPDATE_CHARGES")
assert(M.count.text == "3" and M.cooldown.duration == nil and M.host.shown,
    "full pool retained a stale recharge timer")
charges = nil
Event("SPELL_UPDATE_CHARGES")
assert(not M.host.shown and M.cooldown.duration == nil,
    "unavailable shared pool showed a made-up count")

Event("CHALLENGE_MODE_COMPLETED")
assert(not callbacks.SPELL_UPDATE_CHARGES and not M.host.shown,
    "completed key kept the charge listener or UI")

instanceType, challenge, encounter = "raid", false, true
charges = { currentCharges = 1, maxCharges = 2, isActive = true,
    display = "1", duration = {} }
Event("ENCOUNTER_START")
assert(M.host.shown and callbacks.SPELL_UPDATE_CHARGES and M.maximum.text == "/2",
    "raid boss encounter did not use the shared pool")
Event("ENCOUNTER_END")
assert(not M.host.shown and not callbacks.SPELL_UPDATE_CHARGES,
    "raid boss ending did not release the charge listener")

S.editMode = true
M.config.point, M.config.x, M.config.y = 2, -20, -80
M:Refresh()
assert(M.host.shown and M.count.text == "2" and M.maximum.text == "/3"
    and M.cooldown.preview[2] == 90 and not callbacks.SPELL_UPDATE_CHARGES
    and M.host.point[1] == "TOP" and M.host.point[4] == -20,
    "Edit Mode preview or profile position is broken")
S.editMode = false
M:Refresh()
assert(not M.host.shown and not M.cooldown.preview,
    "Edit Mode left a fake pool or timer visible")

instanceType, challenge = "party", false
Event("CHALLENGE_MODE_START")
assert(#timers == 1 and not callbacks.SPELL_UPDATE_CHARGES,
    "early key start should schedule only one bounded recheck")
challenge = true
Drain()
assert(M.host.shown and callbacks.SPELL_UPDATE_CHARGES,
    "delayed key activation missed the shared pool")
challenge = false
Event("CHALLENGE_MODE_RESET")
Event("CHALLENGE_MODE_START")
readBefore = chargeReads
M:Disable()
M.active = false
Drain()
assert(not M.host.shown and not callbacks.SPELL_UPDATE_CHARGES and chargeReads == readBefore,
    "disabled tracker retained events or ran a deferred read")
assert(displayReads > 0 and durationReads > 0)

print("Battle resurrection: contextual charges, native timer, secrets, mover and teardown passed")
