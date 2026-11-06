-- Native WowStyle2DropdownMixin repaints normal gold on every button-state
-- edge (Blizzard_Menu/MenuTemplates.lua, Retail and Forever). Exercise that
-- lifecycle through the real color owner and dropdown registration.
local root = assert(arg[1], "Suite root required")
local checks, hooks, reported = 0, 0, 0
local combat, secret = false, {}
local desired = { 0.2, 0.7, 0.9, 1 }
local function Check(value, why) assert(value, why) checks = checks + 1 end
local function Noop() end
issecretvalue = function(value) return value == secret end
InCombatLockdown = function() return combat end
securecallfunction = function(callback, ...)
    local ok, value = pcall(callback, ...)
    if not ok then reported = reported + 1 return end
    return value
end
hooksecurefunc = function(target, method, callback)
    hooks = hooks + 1
    local original = assert(target[method])
    target[method] = function(...)
        local value = original(...)
        callback(...)
        return value
    end
end
DropdownButtonMixin = { Event = { OnMenuOpen = "open", OnMenuClose = "close" } }
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
local NS = {
    DB = { enabled = true }, IsCombatLocked = InCombatLockdown,
    Theme = { GetColor = function() return unpack(desired) end },
    Registry = { AddListener = Noop }, BlizzardFontNames = {},
    GenericWindows = { Disable = Noop }, WindowActionSkin = { DisableOwner = Noop },
}
for _, path in ipairs({ "Safety", "BlizzardYellow", "Checkmarks", "CheckmarksMenus" }) do
    local override = path == "CheckmarksMenus" and os.getenv("SUITE_DROPDOWN_STATE_OVERRIDE")
    assert(loadfile(override or root .. "/MSUF_Suite_Skin/Core/" .. path .. ".lua"))("MSUF_Suite_Skin", NS)
end
local function Label()
    local text = { color = { 1, 0.82, 0, 1 }, writes = 0 }
    function text:GetObjectType() return "FontString" end
    function text:IsForbidden() return self.forbidden == true end
    function text:IsProtected() return false, false end
    function text:GetTextColor() return unpack(self.color) end
    function text:SetTextColor(r, g, b, a)
        self.writes = self.writes + 1
        self.color[1], self.color[2], self.color[3], self.color[4] = r, g, b, a or 1
    end
    return text
end
local function Dropdown()
    local button = { Text = Label(), enabled = true, callbacks = {} }
    function button:IsForbidden() return self.forbidden == true end
    function button:IsProtected() return self.protected == true, self.explicit == true end
    function button:IsEnabled() return self.enabled end
    function button:RegisterCallback(event, callback, owner) self.callbacks[event] = { callback, owner } end
    function button:UnregisterCallback(event) self.callbacks[event] = nil end
    function button:IsMenuOpen() return false end
    function button:GetMenuDescription() return {} end
    function button:GetRegions() return self.Text end
    function button:OnButtonStateChanged()
        if self.nativeColor then self.Text:SetTextColor(unpack(self.nativeColor))
        elseif self.enabled then self.Text:SetTextColor(1, 0.82, 0)
        else self.Text:SetTextColor(0.5, 0.5, 0.5) end
        return "native state"
    end
    return button
end
local function Matches(button, color)
    local actual = button.Text.color
    return actual[1] == color[1] and actual[2] == color[2] and actual[3] == color[3]
end
local function State(button)
    Check(button:OnButtonStateChanged() == "native state", "native state return changed")
end
local button = Dropdown()
Check(NS.Checkmarks.TrackDropdown(button, "settings"), "dropdown was not adopted")
Check(Matches(button, desired), "initial color missing")
for _, edge in ipairs({ "enter", "leave", "mouse down", "mouse up", "menu open", "menu close" }) do
    State(button)
    Check(Matches(button, desired), edge .. " restored Blizzard gold")
end
for _ = 1, 20 do NS.Checkmarks.TrackDropdown(button, "settings") end
Check(hooks == 1, "repeated discovery installed duplicate state hooks")
button.enabled = false
State(button)
Check(Matches(button, { 0.5, 0.5, 0.5 }), "disabled text was recolored")
button.enabled = true
State(button)
Check(Matches(button, desired), "re-enabled text kept native gold")
desired[1], desired[2], desired[3] = 0.8, 0.3, 0.6
State(button)
Check(Matches(button, desired), "state hook cached the old theme color")
button.nativeColor = { 1, 0, 0, 1 }
State(button)
Check(Matches(button, button.nativeColor), "semantic warning color was overwritten")
button.nativeColor = { secret, 0, 0, 1 }
State(button)
Check(button.Text.color[1] == secret, "secret text color was recolored")
button.nativeColor = nil
button.Text = Label()
State(button)
Check(Matches(button, desired), "recycled dropdown retained its old label")
combat, button.protected = true, true
State(button)
Check(Matches(button, { 1, 0.82, 0 }), "protected dropdown repainted in combat")
combat, button.protected = false, false
button.Text.forbidden = true
State(button)
Check(Matches(button, { 1, 0.82, 0 }), "forbidden label was recolored")
button.Text.forbidden = false
State(button)
Check(Matches(button, desired), "safe dropdown did not resume repainting")
NS.DB.enabled = false
State(button)
Check(Matches(button, { 1, 0.82, 0 }), "disabled skin retained state color ownership")
NS.DB.enabled = true
Check(NS.Checkmarks.UntrackDropdown(button), "dropdown release failed")
State(button)
Check(Matches(button, { 1, 0.82, 0 }), "released dropdown was recolored")
Check(NS.Checkmarks.TrackDropdown(button, "new-owner"), "pooled dropdown could not be readopted")
State(button)
Check(Matches(button, desired) and hooks == 1, "readoption lost color or doubled the hook")
local other = Dropdown()
State(other)
Check(Matches(other, { 1, 0.82, 0 }), "unowned dropdown was recolored")
other.OnButtonStateChanged = nil
Check(NS.Checkmarks.TrackDropdown(other, "legacy"), "dropdown without state method was rejected")
Check(hooks == 1, "missing state method was hooked")
local repaint = NS.BlizzardYellow.TrackDropdown
NS.BlizzardYellow.TrackDropdown = function() error("state callback failure") end
State(button)
Check(reported == 1, "state callback escaped its native boundary")
NS.BlizzardYellow.TrackDropdown = repaint
NS.Checkmarks.UntrackDropdown(button)
NS.Checkmarks.UntrackDropdown(other)
NS.BlizzardYellow.Restore()
Check(NORMAL_FONT_COLOR.r == 1 and NORMAL_FONT_COLOR.g == 0.82 and NORMAL_FONT_COLOR.b == 0,
    "native color constant changed")
print("Suite dropdown text state: " .. checks .. " checks passed")
