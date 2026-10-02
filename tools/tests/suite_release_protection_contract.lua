local root = assert(arg[1], "repository root required")
-- Offline contract for release protection. Blizzard's DEATH dialog owns its
-- buttons' visibility, enabled state and layout (GameDialogDefs.lua); the
-- lock may only make Release transparent and click-through, so the fixtures
-- raise on any Lua field write to Blizzard's tables and on layout calls.
local hooks, installed, secret = 0, nil, {}
local modifiers, inInstance, zone = {}, true, "raid"
SHIFT_KEY_TEXT, CTRL_KEY_TEXT, ALT_KEY_TEXT = "Shift", "Ctrl", "Alt"
IsShiftKeyDown = function() return modifiers[1] == true end
IsControlKeyDown = function() return modifiers[2] == true end
IsAltKeyDown = function() return modifiers[3] == true end
IsInInstance = function() return inInstance, zone end

local function Hook(owner, method, callback)
    hooks = hooks + 1
    local previous = assert(owner[method], method)
    owner[method] = function(...)
        previous(...)
        callback(...)
    end
end
hooksecurefunc = function(owner, method, callback)
    assert(type(owner) == "string", "only the StaticPopup_Show function may be hooked")
    Hook(_G, owner, method)
end

-- Blizzard tables: methods are read from a class, state lives in a private
-- store, and a write of any Lua field raises.
local function Sealed(methods, state)
    return setmetatable({}, {
        __index = function(_, key) if methods[key] then return methods[key] end; return state[key] end,
        __newindex = function(_, key) error("wrote Blizzard field " .. tostring(key), 2) end,
    }), state
end
local ButtonMethods = {}
function ButtonMethods:Show() self._s.shown = true end
function ButtonMethods:Hide() self._s.shown = false end
function ButtonMethods:SetShown(shown) self._s.shown = shown end
function ButtonMethods:IsShown() return self._s.shown end
function ButtonMethods:SetEnabled(enabled) self._s.enabled = enabled; self._s.enabledWrites = self._s.enabledWrites + 1 end
function ButtonMethods:GetAlpha() return self._s.alpha end
function ButtonMethods:SetAlpha(alpha) self._s.alpha = alpha end
function ButtonMethods:IsMouseEnabled() return self._s.mouse end
function ButtonMethods:EnableMouse(enabled) self._s.mouse = enabled end
function ButtonMethods:Click()
    local s = self._s
    if s.shown and s.enabled and s.mouse then s.clicks = s.clicks + 1 end
end
local function Button()
    local state = { shown = true, enabled = true, clicks = 0, enabledWrites = 0, alpha = 1, mouse = true }
    local button = Sealed(ButtonMethods, state)
    state._s = state
    return button, state
end
local PopupMethods = {}
function PopupMethods:GetButton1() return self._s.buttons[1] end
function PopupMethods:GetWidth() return 360 end
function PopupMethods:HookScript(script, callback)
    assert(script == "OnHide"); self._s.onHide = callback; hooks = hooks + 1
end
function PopupMethods:Hide() self._s.shown = false; if self._s.onHide then self._s.onHide() end end
local function Popup()
    local container = Sealed({ MarkDirty = function() error("dirtied Blizzard's dialog layout") end }, {})
    local state = { buttons = {}, states = {}, ButtonContainer = container }
    for i = 1, 4 do state.buttons[i], state.states[i] = Button() end
    local popup = Sealed(PopupMethods, state)
    state._s = state
    return popup, state
end
local popup, popupState = Popup()
local visible
StaticPopup_FindVisible = function(which)
    if visible and visible._s.shown and visible._s.which == which then return visible end
end
StaticPopup_Show = function(which)
    popupState.which, popupState.shown, visible = which, true, popup
    for _, button in ipairs(popupState.buttons) do button:SetShown(true) end
end
local hints = {}
local S = {
    Install = function(id, module) assert(id == "releaseProtection"); installed = module end,
    Public = function(value) return value ~= secret end,
    Text = function(text) return text == "Hold %s to release spirit" and "Halte %s zum Freilassen" or text end,
    SetFont = function() end,
    CreateFontString = function(parent)
        local hint = { parent = parent }
        function hint:SetPoint() end
        function hint:SetJustifyH() end
        function hint:SetTextColor() end
        function hint:SetWordWrap() end
        function hint:Hide() self.shown = false end
        function hint:SetShown(shown) self.shown = shown end
        function hint:SetWidth(width) self.width = width end
        function hint:SetText(text) self.text = text end
        hints[#hints + 1] = hint
        return hint
    end,
}
assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))().QoLStyleFixture(root, S)
local NS = { Safety = { IsForbidden = function(frame) return frame._s.forbidden == true end } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ReleaseProtection.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local M = assert(installed)
M.active, M.config = true, { modifier = 1, openWorld = true, party = true, raid = true, pvp = true }
M.context = { events = {}, Event = function(self, event, callback, allowCombat)
    assert(dofile(root .. "/tools/tests/suite_test_support.lua").InCombatOption(allowCombat), "death protection must react during combat")
    self.events[event] = callback
end, RemoveEvent = function(self, event) self.events[event] = nil end }
local function Modifier(index, down)
    modifiers[index] = down
    local event = M.context.events.MODIFIER_STATE_CHANGED
    if event then event(M, "MODIFIER_STATE_CHANGED") end
end
local function Locked(state) return state.alpha == 0 and state.mouse == false end

M:Enable()
assert(not M.context.events.MODIFIER_STATE_CHANGED and #hints == 0, "idle protection allocated a dialog or listened for keys")
StaticPopup_Show("DEATH")
local release, releaseState, hint = popupState.buttons[1], popupState.states[1], hints[1]
assert(Locked(releaseState) and releaseState.shown and hint.shown and hint.text == "Halte Shift zum Freilassen",
    "Release must stay laid out but transparent and click-through, with a translated hint")
release:Click()
assert(releaseState.clicks == 0, "locked release remained clickable")
for i = 2, 4 do
    popupState.buttons[i]:Click()
    assert(popupState.states[i].clicks == 1 and popupState.states[i].alpha == 1, "resurrection or recap was blocked")
end
Modifier(2, true)
assert(Locked(releaseState), "wrong modifier unlocked release")
Modifier(2, false)
Modifier(1, true)
assert(releaseState.alpha == 1 and releaseState.mouse == true, "the modifier did not unlock release")
release:Click()
assert(releaseState.clicks == 1)
Modifier(1, false)
assert(Locked(releaseState), "releasing the key left the button unlocked")

-- Blizzard keeps exclusive ownership of the enabled state and visibility.
release:SetEnabled(false)
Modifier(1, true)
release:Click()
assert(releaseState.clicks == 1 and not releaseState.enabled and releaseState.enabledWrites == 1)
release:SetEnabled(true)
Modifier(1, false)
release:Show()
assert(Locked(releaseState), "a native Show bypassed protection")
release:Hide()
Modifier(1, false)
assert(not hint.shown and not releaseState.shown, "the hint stayed over a release button Blizzard hid")
Modifier(1, true)
assert(not releaseState.shown, "unlocking overrode a native Hide")
release:Show()
Modifier(1, false)
assert(hint.shown and Locked(releaseState))

-- Reconfigure a visible death popup, including every modifier.
M.config.modifier = 2
M:Refresh()
assert(Locked(releaseState) and hint.text == "Halte Ctrl zum Freilassen")
Modifier(2, true)
assert(not Locked(releaseState))
Modifier(2, false)
M.config.modifier = 3
M:Refresh()
assert(Locked(releaseState) and hint.text == "Halte Alt zum Freilassen")
Modifier(3, true)
assert(not Locked(releaseState))
Modifier(3, false)

-- Zone switches through S.InstanceKind.
M.config.raid = false
M:Refresh()
assert(not Locked(releaseState) and not hint.shown and not M.context.events.MODIFIER_STATE_CHANGED)
for _, entry in ipairs({ { "party", "party" }, { "scenario", "party" }, { "pvp", "pvp" }, { "arena", "pvp" } }) do
    zone = entry[1]
    M:Refresh()
    assert(Locked(releaseState), zone .. " was not protected")
    M.config[entry[2]] = false
    M:Refresh()
    assert(not Locked(releaseState), zone .. " ignored its opt-out")
    M.config[entry[2]] = true
end
inInstance = false
M:Refresh()
assert(Locked(releaseState))
M.config.openWorld = false
M:Refresh()
assert(not Locked(releaseState))
M.config.openWorld = true
inInstance = secret
M:Refresh()
assert(not Locked(releaseState) and not hint.shown, "secret instance state was inspected")
inInstance = false
M:Refresh()

-- Closing the dialog restores the button before Blizzard reuses it.
local hookCount = hooks
popup:Hide()
assert(not Locked(releaseState) and not hint.shown and not M.context.events.MODIFIER_STATE_CHANGED)
StaticPopup_Show("RECOVER_CORPSE")
assert(not Locked(releaseState) and not hint.shown, "reused corpse-recovery dialog was gated")
StaticPopup_Show("DEATH")
assert(Locked(releaseState) and hooks == hookCount and #hints == 1, "a reused dialog was hooked again")
M.active = false
M:Disable()
assert(not Locked(releaseState) and not hint.shown and not M.context.events.MODIFIER_STATE_CHANGED)
StaticPopup_Show("DEATH")
assert(not Locked(releaseState), "disabled hook continued locking release")
modifiers[3] = true
M.active = true
M:Enable()
assert(not Locked(releaseState) and hint.shown and hooks == hookCount, "enable duplicated hooks or ignored a held key")
Modifier(3, false)
assert(Locked(releaseState))

-- The native alpha and mouse state come back exactly as they were.
M.active = false
M:Disable()
releaseState.alpha, releaseState.mouse = .6, false
M.active = true
Modifier(3, false)
M:Refresh()
assert(Locked(releaseState))
M.active = false
M:Disable()
assert(releaseState.alpha == .6 and releaseState.mouse == false, "disable lost the native alpha or mouse state")

-- A different pooled popup gets its own hint and cleanup; forbidden UI is untouched.
popup:Hide()
popup, popupState = Popup()
popupState.forbidden = true
M.active = true
M:Enable()
StaticPopup_Show("DEATH")
assert(not Locked(popupState.states[1]) and #hints == 1)
popupState.forbidden = false
M:Refresh()
assert(Locked(popupState.states[1]) and #hints == 2)
popup:Hide()
assert(not Locked(popupState.states[1]) and not hints[2].shown)
print("suite_release_protection_contract: ok")
