local root = assert(arg[1], "repository root required")
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
    if type(owner) == "string" then Hook(_G, owner, method) else Hook(owner, method, callback) end
end

local function Button()
    local button = { shown = true, enabled = true, clicks = 0, enabledWrites = 0 }
    function button:Show() self.shown = true end
    function button:Hide() self.shown = false end
    function button:SetShown(shown) self.shown = shown end
    function button:IsShown() return self.shown end
    function button:SetEnabled(enabled) self.enabled = enabled; self.enabledWrites = self.enabledWrites + 1 end
    function button:Click()
        if self.shown and self.enabled then self.clicks = self.clicks + 1 end
    end
    return button
end
local function Popup()
    local popup = { buttons = { Button(), Button(), Button(), Button() } }
    function popup:GetButton1() return self.buttons[1] end
    function popup:GetWidth() return 360 end
    function popup:HookScript(script, callback) assert(script == "OnHide"); self.onHide = callback end
    function popup:Hide() self.shown = false; if self.onHide then self.onHide() end end
    return popup
end
local popup, visible = Popup(), nil
StaticPopup_FindVisible = function(which)
    if visible and visible.shown and visible.which == which then return visible end
end
StaticPopup_Show = function(which)
    popup.which, popup.shown, visible = which, true, popup
    for _, button in ipairs(popup.buttons) do button:SetShown(true) end
end
local hints = {}
local S = {
    Install = function(id, module) assert(id == "releaseProtection"); installed = module end,
    Public = function(value) return value ~= secret end,
    Text = function(text) return text end,
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
local NS = { Safety = { IsForbidden = function(frame) return frame.forbidden == true end } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/ReleaseProtection.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local M = assert(installed)
M.active, M.config = true, { modifier = 1, openWorld = true, party = true, raid = true, pvp = true }
M.context = { events = {}, Event = function(self, event, callback, allowCombat)
    assert(allowCombat == true, "death protection must react during combat")
    self.events[event] = callback
end, RemoveEvent = function(self, event) self.events[event] = nil end }
local function Modifier(index, down)
    modifiers[index] = down
    local event = M.context.events.MODIFIER_STATE_CHANGED
    if event then event(M, "MODIFIER_STATE_CHANGED") end
end

M:Enable()
assert(not M.context.events.MODIFIER_STATE_CHANGED and #hints == 0, "idle protection allocated a dialog or listened for keys")
StaticPopup_Show("DEATH")
local release, hint = popup.buttons[1], hints[1]
assert(not release.shown and hint.shown and hint.text == "Hold Shift to release spirit")
release:Click()
assert(release.clicks == 0, "locked release remained clickable")
for i = 2, 4 do
    popup.buttons[i]:Click()
    assert(popup.buttons[i].clicks == 1 and popup.buttons[i].shown, "resurrection/recap was blocked")
end
Modifier(2, true)
assert(not release.shown, "wrong modifier unlocked release")
Modifier(1, true)
assert(release.shown)
release:Click()
assert(release.clicks == 1)
Modifier(1, false)
assert(not release.shown, "releasing the key left the button unlocked")

-- Blizzard's per-frame release restrictions retain exclusive enabled-state ownership.
release:SetEnabled(false)
Modifier(1, true)
release:Click()
assert(release.clicks == 1 and not release.enabled and release.enabledWrites == 1)
release:SetEnabled(true)
Modifier(1, false)
release:Show()
assert(not release.shown, "a native Show bypassed protection")
release:SetShown(true)
assert(not release.shown, "a native SetShown bypassed protection")
assert(release.enabledWrites == 2, "protection fought Blizzard's enabled state")
release:Hide()
Modifier(1, true)
assert(not release.shown, "unlocking overrode a later native Hide")
release:Show()
assert(release.shown)

-- Reconfigure a visible death popup, including both left/right key release semantics.
M.config.modifier = 2
Modifier(1, false)
M:Refresh()
assert(release.shown and hint.text == "Hold Ctrl to release spirit")
Modifier(2, false)
assert(not release.shown)
M.config.modifier = 3
M:Refresh()
assert(not release.shown and hint.text == "Hold Alt to release spirit")
Modifier(3, true)
assert(release.shown)
Modifier(3, false)

M.config.raid = false
M:Refresh()
assert(release.shown and not hint.shown and not M.context.events.MODIFIER_STATE_CHANGED)
for _, entry in ipairs({ { "party", "party" }, { "scenario", "party" }, { "pvp", "pvp" }, { "arena", "pvp" } }) do
    zone = entry[1]
    M:Refresh()
    assert(not release.shown, zone .. " was not protected")
    M.config[entry[2]] = false
    M:Refresh()
    assert(release.shown, zone .. " ignored its opt-out")
    M.config[entry[2]] = true
end
inInstance = false
M:Refresh()
assert(not release.shown)
M.config.openWorld = false
M:Refresh()
assert(release.shown)
M.config.openWorld = true
inInstance = secret
M:Refresh()
assert(release.shown and not hint.shown, "secret instance state was inspected")
inInstance = false
M:Refresh()
local hookCount = hooks
popup:Hide()
assert(release.shown and not hint.shown and not M.context.events.MODIFIER_STATE_CHANGED)
StaticPopup_Show("RECOVER_CORPSE")
assert(release.shown and not hint.shown, "reused corpse-recovery dialog was gated")
StaticPopup_Show("DEATH")
assert(not release.shown and hooks == hookCount and #hints == 1)
M.active = false
M:Disable()
assert(release.shown and not hint.shown and not M.context.events.MODIFIER_STATE_CHANGED)
StaticPopup_Show("DEATH")
assert(release.shown, "disabled hook continued hiding release")
modifiers[3] = true
M.active = true
M:Enable()
assert(release.shown and hint.shown and hooks == hookCount, "enable duplicated hooks or ignored an already held key")
Modifier(3, false)
assert(not release.shown)
release:Hide()
M.active = false
M:Disable()
assert(not release.shown, "disable overwrote a later native visibility request")

-- A different pooled popup gets its own hint and cleanup, but forbidden UI is untouched.
popup:Hide()
popup = Popup()
popup.forbidden = true
M.active = true
M:Enable()
StaticPopup_Show("DEATH")
assert(popup.buttons[1].shown and #hints == 1)
popup.forbidden = false
M:Refresh()
assert(not popup.buttons[1].shown and #hints == 2)
popup:Hide()
assert(popup.buttons[1].shown and not hints[2].shown)
print("suite_release_protection_contract: ok")
