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
    function w:SetFrameStrata(value) self.strata = value end
    function w:GetFrameStrata() return self.strata or "MEDIUM" end
    function w:SetParent(value) self.parent = value end
    function w:EnableMouse(value) self.mouse = value end
    function w:SetAllPoints() end
    function w:SetColorTexture() end
    function w:SetTexture(value) self.texture = value end
    function w:SetPoint(...) self.point = { ... } end
    function w:ClearAllPoints() end
    function w:SetDrawEdge() end
    function w:SetHideCountdownNumbers(value) self.hideNumbers = value end
    function w:SetMinimumCountdownDuration(value) self.minimumCountdown = value end
    function w:SetTextColor(...) self.color = { ... } end
    function w:SetFont(path, size, flags)
        assert(type(path) == "string" and path ~= "" and type(size) == "number" and size > 0)
        self.fontPath, self.fontSize, self.fontFlags = path, size, flags
        return true
    end
    function w:SetJustifyH() end
    function w:SetText(value)
        assert(self.fontPath, "FontString:SetText(): Font not set")
        self.text = value
    end
    function w:SetFormattedText(format, ...)
        assert(self.fontPath, "FontString:SetFormattedText(): Font not set")
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
S.SetFont = function(fontString, path, size, flags)
    fontString:SetFont(path or "MSUF.ttf", size, flags)
end
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

local nativeBindings = {}
Enum = { NumericRuleFormatRounding = { Down = 1 } }
C_StringUtil = { CreateNumericRuleFormatter = function()
    return { SetBreakpoints = function(self, rows) self.rows = rows end }
end }
C_DurationUtil = { CreateDurationTextBinding = function()
    local b = {}
    function b:SetFontString(value)
        assert(value.fontPath, "duration binding attached before font initialization")
        self.label, self.initialFont, self.initialSize = value, value.fontPath, value.fontSize
    end
    function b:SetFormatter(value) self.formatter = value end
    function b:SetUpdateInterval(value) self.interval = value end
    function b:SetZeroDurationText(value) self.zero = value end
    function b:SetExpiredText(value) self.expired = value end
    function b:SetDuration(value) assert(S.Public(value), 'secret object passed to restricted binding'); self.duration = value end
    function b:Enable() self.enabled = true end
    function b:Disable() self.enabled = false end
    nativeBindings[#nativeBindings + 1] = b
    return b
end }

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
M:RegisterMovers() -- the controller registers movers after Enable
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


-- Compact HUD mode uses the shared pool, not personal cooldowns or an aura.
M.active = true
M.config.textOnly, M.config.fontSize = true, 11
M.config.width, M.config.height = 70, 16
instanceType, challenge = 'party', true
charges = { currentCharges = 1, maxCharges = 3, isActive = true, display = '1', duration = {} }
M:Enable()
local binding = assert(M.durationBinding, 'compact battle-res countdown is missing')
assert(M.host.shown and not M.icon.shown and not M.panel.shown and not M.title.shown and not M.maximum.shown,
    'compact text still draws the card, icon, title or pool maximum')
assert(M.count.text == '1' and M.separator.text == '+' and M.separator.shown and M.time.shown,
    'compact charge + countdown layout is missing')
assert(binding.enabled and binding.duration == charges.duration and binding.label == M.time and binding.interval == 1,
    'recharge is not driven by the native duration binding')
local rule = binding.formatter.rows[1]
assert(rule.threshold == 0 and rule.format == '%02d:%02d' and rule.components[1].div == 60
    and rule.components[2].mod == 60 and rule.components[2].rounding == Enum.NumericRuleFormatRounding.Down,
    'compact countdown does not preserve padded minutes and seconds')
charges.display, charges.currentCharges, charges.duration = secret, secret, secret
Event('SPELL_UPDATE_CHARGES')
assert(M.count.text == secret and M.cooldown.duration == secret and not binding.enabled and not M.time.shown,
    'secret object should keep native cooldown support without binding or fabricating a text duration')
charges.display, charges.currentCharges, charges.duration = '0', 0, {}
Event('SPELL_UPDATE_CHARGES')
assert(binding.enabled and M.time.shown and M.count.text == '0', 'public duration did not recover after restriction')
charges.isActive = false
Event('SPELL_UPDATE_CHARGES')
assert(not binding.enabled and not M.time.shown and not M.separator.shown, 'full pool kept a stale recharge text')
S.editMode = true
M:Refresh()
assert(M.time.text == '02:38' and M.time.shown and M.separator.shown and not binding.enabled,
    'compact preview does not use the live text layout')
S.editMode = false
M.config.fontSize = 24
M:Refresh()
assert(M.host.width >= 144 and M.host.height >= 26 and M.time.point[4] > 52
    and M.separator.point[4] > 28, 'large font overlaps the compact charge and countdown')
M.config.textOnly = false
M:Refresh()
assert(M.host.width >= 146 and M.host.height >= 44 and M.config.width == 70 and M.config.height == 16,
    'card mode must fit its content without overwriting stored compact dimensions')
assert(M.icon.shown and M.panel.shown and M.title.shown and M.maximum.shown and not M.time.shown,
    'switching back to card mode retained compact layout')
M:Disable()
assert(not binding.enabled and not M.host.shown, 'disable retained the native text timer')

-- A saved text-only setting must work on the very first live creation.
local cold = { active = true, config = { textOnly = true, font = "Cold.ttf", fontSize = 13,
    width = 70, height = 16, scale = 100, point = 5, x = 0, y = 0 } }
cold.context = dofile(root .. "/tools/tests/suite_test_support.lua").ModuleTimers(root, S, NS)("battleRes", cold, {
    Event = function() end, RemoveEvent = function() end,
})
instanceType, challenge = "party", true
charges = { maxCharges = 3, isActive = true, display = "1", duration = {} }
assert(cold.host == nil and cold.time == nil and cold.separator == nil)
M.Enable(cold)
assert(cold.host.shown and cold.separator.text == "+" and cold.durationBinding.enabled
    and cold.durationBinding.initialFont == "Cold.ttf" and cold.durationBinding.initialSize == 13,
    "cold compact runtime did not initialize its configured font before binding")
local function AssertFont(view, path, size)
    for _, label in ipairs({ view.count, view.time, view.separator }) do
        assert(label.fontPath == path and label.fontSize == size and label.fontFlags == "OUTLINE",
            "compact font choice or size was not applied to every label")
    end
end
AssertFont(cold, "Cold.ttf", 13)
local coldHost, coldTime, coldSeparator, coldBinding = cold.host, cold.time, cold.separator, cold.durationBinding
local bindingCount = #nativeBindings
cold.config.font, cold.config.fontSize = "Warm.ttf", 24
M.Refresh(cold)
AssertFont(cold, "Warm.ttf", 24)
assert(cold.host == coldHost and cold.time == coldTime and cold.separator == coldSeparator
    and cold.durationBinding == coldBinding and #nativeBindings == bindingCount,
    "warm font refresh recreated the compact text or duration binding")
M.Disable(cold)
cold.config.font, cold.config.fontSize = nil, 11
M.Enable(cold)
AssertFont(cold, "MSUF.ttf", 11)
assert(cold.host == coldHost and cold.durationBinding == coldBinding and #nativeBindings == bindingCount
    and cold.durationBinding.enabled, "re-enable did not reuse the initialized runtime")
M.Disable(cold)

-- A separate cold preview follows the same painter, including cached refreshes.
local parent, viewport = Widget(), { width = 200, height = 60, scale = 1 }
local previewConfig = { textOnly = true, font = "Preview.ttf", fontSize = 15,
    width = 90, height = 18, scale = 100, point = 5, x = 0, y = 0 }
local previewHost = S.DrawBattleResPreview(parent, previewConfig, nil, viewport)
local preview = assert(parent.suiteBattleResPreview)
assert(previewHost == preview.host and preview.host.parent == parent and preview.host.shown
    and preview.time.text == "02:38" and preview.separator.text == "+"
    and preview.durationBinding.initialFont == "Preview.ttf" and preview.durationBinding.initialSize == 15,
    "cold compact preview used text or a duration binding before its configured font")
AssertFont(preview, "Preview.ttf", 15)
local previewBinding = preview.durationBinding
bindingCount = #nativeBindings
previewConfig.font, previewConfig.fontSize = "PreviewWarm.ttf", 20
assert(S.DrawBattleResPreview(parent, previewConfig, nil, viewport) == previewHost)
AssertFont(preview, "PreviewWarm.ttf", 20)
assert(preview.durationBinding == previewBinding and #nativeBindings == bindingCount
    and not preview.durationBinding.enabled, "cached preview recreated or enabled its sample timer")

print("Battle resurrection: contextual charges, native timer, secrets, mover, font initialization and teardown passed")
