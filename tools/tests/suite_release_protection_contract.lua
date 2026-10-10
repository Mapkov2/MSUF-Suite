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
function PopupMethods:GetFrameStrata() return "DIALOG" end
function PopupMethods:IsShown() return self._s.shown == true end
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
UIParent = { name = "UIParent" }
-- WoW Forever's Gamepad UI and the client's pad modifier CVars.
local gamepadUI, padModifiers = false, { GamePadEmulateShift = "PADLTRIGGER", GamePadEmulateCtrl = "none" }
C_CVar = { GetCVar = function(name) return padModifiers[name] end }
-- S.GamepadUI (MSUF_Suite_Modules/Dialogs.lua, loaded by the QoL fixture) reads InputUtil.
InputUtil = { IsGamepadUIEnabled = function() return gamepadUI end }
-- The client's display text for a key; a pad button's is its icon markup.
GetBindingText = function(key, abbreviate)
    assert(abbreviate == true)
    return "|A:Gamepad_" .. key .. "_32:14:14|a"
end
local S = {
    CreateFrame = function(kind, name, parent)
        assert(kind == "Frame" and name == nil)
        local frame = { parent = parent }
        function frame:SetFrameStrata(strata) self.strata = strata end
        return frame
    end,
    Install = function(id, module) assert(id == "releaseProtection"); installed = module end,
    Public = function(value) return value ~= secret end,
    Text = function(text)
        if text == "Hold %s to release spirit" then return "Halte %s zum Freilassen" end
        if text == "Press %s, then %s to release spirit" then return "Drücke %s, dann %s zum Freilassen" end
        return text
    end,
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
local NS = { Safety = { IsForbidden = function(frame) return frame._s.forbidden == true end },
    Client = { isForever = true } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ReleaseProtection.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local M = assert(installed)
M.active, M.config = true, { modifier = 1, openWorld = true, party = true, raid = true, pvp = true }
-- Context timers (MSUF_Suite_Modules/Timers.lua): After runs fn(module) once
-- delay has passed (Elapse here), Cancel drops it.
M.context = { events = {}, timers = {}, Event = function(self, event, callback, allowCombat)
    assert(dofile(root .. "/tools/tests/suite_test_support.lua").InCombatOption(allowCombat), "death protection must react during combat")
    self.events[event] = callback
end, RemoveEvent = function(self, event) self.events[event] = nil end,
After = function(self, delay, fn) self.timers[fn] = delay end,
Cancel = function(self, fn) self.timers[fn] = nil end }
local function Elapse(seconds)
    local due = {}
    for fn, left in pairs(M.context.timers) do
        if left <= seconds then due[#due + 1] = fn else M.context.timers[fn] = left - seconds end
    end
    for _, fn in ipairs(due) do
        M.context.timers[fn] = nil
        fn(M)
    end
end
local function Transition(toGamepad)
    gamepadUI = toGamepad
    M.context.events.INPUT_DEVICE_INTERFACE_TRANSITION(M, "INPUT_DEVICE_INTERFACE_TRANSITION",
        toGamepad and 1 or 0, toGamepad and 0 or 1)
end
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
-- StaticPopupTemplate is a ResizeLayoutFrame (GameDialog.xml): its Layout
-- counts every shown child and region (LayoutFrame.lua GetLayoutChildren)
-- and DEATH lays out every frame of its countdown, so the hint above the
-- dialog lives on an owned frame of UIParent in the dialog's strata.
assert(hint.parent ~= popup and hint.parent.parent == UIParent and hint.parent.strata == "DIALOG",
    "the release hint is part of Blizzard's dialog layout and makes the dialog taller")
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

-- WoW Forever's Gamepad UI. GamepadPopupHandler binds only the bare PAD1
-- to the dialog's first button (StaticPopupGamepad.lua InitializeBindings,
-- ClickPopupButton: IsShown and IsEnabled, then Click), after its binding
-- group's BlockEverything bound SHIFT-PAD1, CTRL-PAD1 and CTRL-SHIFT-PAD1 to
-- nothing (BindingSetFactory.lua BlockKeysWithModifiers); the Gamepad UI's
-- triggers are those modifiers (GamepadConstants.lua: LT Shift, RT Ctrl).
-- So an A pressed while a modifier is held never reaches Release.
local function PadPress(button)
    if modifiers[1] or modifiers[2] or modifiers[3] then return "blocked" end
    if button:IsShown() and button._s.enabled then
        button._s.clicks = button._s.clicks + 1
        return "clicked"
    end
    return "hidden"
end
local PAD_HINT = "Drücke |A:Gamepad_PADLTRIGGER_32:14:14|a, dann |A:Gamepad_PAD1_32:14:14|a zum Freilassen"
M.active = true
M.config.modifier = 1
M:Enable()
StaticPopup_Show("DEATH")
releaseState = popupState.states[1]
local padClicks = releaseState.clicks
assert(PadPress(release) == "clicked" and releaseState.clicks == padClicks + 1,
    "fixture: outside the Gamepad UI the pad press still releases")
-- Under the Gamepad UI the lock hides Release and the hint says how to
-- release with the pad alone.
gamepadUI = true
M:Refresh()
assert(PadPress(release) == "hidden" and releaseState.clicks == padClicks + 1 and hint.shown and hint.text == PAD_HINT,
    "the pad's A released without the modifier under the Gamepad UI, or the hint does not name the pad's buttons")
-- Pressing the modifier arms Release; while it is held the A is a modified
-- chord that Blizzard blocks, so the window lasts past the release.
Modifier(1, true)
assert(releaseState.shown and not Locked(releaseState), "the pad modifier did not bring Release back")
assert(PadPress(release) == "blocked" and releaseState.clicks == padClicks + 1, "fixture: a modified A reached Release")
Modifier(1, false)
assert(releaseState.shown and not Locked(releaseState), "letting go of the modifier took Release away at once")
Elapse(2)
assert(PadPress(release) == "clicked" and releaseState.clicks == padClicks + 2,
    "the bare A right after the modifier did not release (the pad-only player is stuck)")
Elapse(1)
assert(not releaseState.shown and Locked(releaseState), "Release stayed pressable after the armed window")
assert(PadPress(release) == "hidden" and releaseState.clicks == padClicks + 2, "the A released after the window")
-- A second press restarts the window; holding keeps Release up.
Modifier(1, true)
Elapse(10)
assert(releaseState.shown, "holding the modifier lost Release")
Modifier(1, false)
Elapse(2)
Modifier(1, true)
Modifier(1, false)
Elapse(2)
assert(releaseState.shown and PadPress(release) == "clicked", "a second press did not restart the window")
Elapse(1)
assert(not releaseState.shown, "the restarted window did not end")
-- Without a pad button for the modifier a pad-only player could never arm
-- it: Release keeps Blizzard's A press then.
M.config.modifier = 2
M:Refresh()
assert(releaseState.shown and Locked(releaseState) and hint.text == "Halte Ctrl zum Freilassen",
    "a modifier the pad cannot press hid Release")
M.config.modifier = 1
M:Refresh()
assert(not releaseState.shown, "the pad lock did not return")
popup:Hide()
assert(not releaseState.shown, "closing the dialog showed a button of a hidden dialog")
StaticPopup_Show("DEATH")
assert(not releaseState.shown and Locked(releaseState), "a shown DEATH dialog lost the pad lock")
gamepadUI = false
M:Refresh()
assert(releaseState.shown and Locked(releaseState), "leaving the Gamepad UI kept Release hidden")
-- The input device switch alone re-syncs: the mouse UI shows Release while
-- dead at once, the Gamepad UI hides it at once (Forever's
-- INPUT_DEVICE_INTERFACE_TRANSITION).
gamepadUI = true
M:Refresh()
assert(not releaseState.shown, "fixture: the Gamepad UI did not hide Release")
Transition(false)
assert(releaseState.shown and Locked(releaseState) and hint.text == "Halte Shift zum Freilassen",
    "switching to the mouse UI while dead kept Release hidden")
Transition(true)
assert(not releaseState.shown and hint.text == PAD_HINT,
    "switching into the Gamepad UI while dead left Release pressable or the mouse hint")
M.active = false
M:Disable()

-- Rescue: whatever the pad does, the pad lock ends 30 seconds after it began
-- on a dialog, also after the modifier was used, and the A releases as on
-- Blizzard's own dialog. A new dialog starts locked again.
popup:Hide()
M.active = true
M:Enable()
StaticPopup_Show("DEATH")
releaseState = popupState.states[1]
padClicks = releaseState.clicks
assert(not releaseState.shown, "fixture: the Gamepad UI hid Release")
Modifier(1, true)
Modifier(1, false)
Elapse(3)
Elapse(26)
assert(PadPress(release) == "hidden" and releaseState.clicks == padClicks, "the rescue freed Release too early")
Elapse(1)
assert(releaseState.shown and not Locked(releaseState) and not hint.shown,
    "the rescue left the pad-only player without a visible Release")
assert(PadPress(release) == "clicked" and releaseState.clicks == padClicks + 1, "the rescued Release did not take the A")
Modifier(1, true)
Modifier(1, false)
Elapse(3)
assert(releaseState.shown, "the modifier took the rescued Release away")
Transition(false)
assert(releaseState.shown and Locked(releaseState) and hint.shown, "the mouse UI lost its lock after a pad rescue")
Transition(true)
popup:Hide()
assert(next(M.context.timers) == nil, "a closed dialog kept a timer")
StaticPopup_Show("DEATH")
assert(not releaseState.shown and hint.text == PAD_HINT, "a new death started without the pad lock")
Elapse(30)
assert(releaseState.shown, "the rescue did not come on the next death")
M.active = false
M:Disable()

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
