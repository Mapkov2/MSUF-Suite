local root = assert(arg[1], "repository root required")
local function noop() end
local Widget = {}
Widget.__index = Widget
local function New(parent) return setmetatable({ parent = parent, shown = true, scripts = {} }, Widget) end
for _, name in ipairs({ "SetPoint", "SetSize", "SetScale", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetText", "SetColorTexture", "SetJustifyH", "SetWordWrap", "ClearAllPoints",
    "RegisterUnitEvent", "RegisterEvent", "UnregisterAllEvents", "SetFormattedText", "SetAllPoints" }) do
    Widget[name] = noop
end
function Widget:CreateTexture() return New(self) end
function Widget:Hide() self.shown = false end
function Widget:SetShown(shown) self.shown = shown end
function Widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Widget:GetStringWidth() return 80 end
function Widget:GetStringHeight() return 16 end
function Widget:SetScript(event, callback) self.scripts[event] = callback end
CreateFrame = function(_, _, parent) return New(parent) end
wipe = function(values) for key in pairs(values) do values[key] = nil end end

local activeTimer
C_Timer = { NewTimer = function(duration, callback)
    assert(not activeTimer and duration == .9, "only one timed wave may be active")
    local timer = {}
    function timer:Cancel() if activeTimer == self then activeTimer = nil end end
    function timer:Fire()
        assert(activeTimer == self)
        activeTimer = nil
        callback()
    end
    activeTimer = timer
    return timer
end }

local keys = {
    crit = "hit", dodge = "avoid", parry = "avoid", xp = "xp", level = "gain", reputation = "gain",
    honor = "gain", power = "power", enter = "combat", leave = "combat",
}
local samples, shown, buttons, flags = {}, {}, {}, {}
for key, route in pairs(keys) do
    samples[#samples + 1] = { key = key, label = key, route = route, value = key }
end
local placements, routes = {}, {}
for _, route in pairs(keys) do routes[route] = 2 end
for lane = 1, 3 do placements[lane] = { rows = 3, step = 60, dy = 30, dx = 0 } end
local scene = {
    height = 32, placements = placements, routes = routes, enabled = {},
    Configure = function(self)
        shown = {}
        wipe(self.enabled)
        for key, value in pairs(flags) do self.enabled[key] = value end
    end,
    Clear = function() shown = {} end,
    Show = function(_, _, _, _, example, _, stationary)
        shown[#shown + 1] = { example, stationary }
    end,
}
local config = { fontSize = 28, critScale = 140, screenY = 0, sideOffset = 124, offset = 5, duration = .9 }
local S = {
    Config = function() return config end, ResolveFont = function() return "font" end, Finite = function() return true end,
    SetFont = noop, CreateFontString = New, FloatingTextSamples = samples,
    FloatingTextDisplay = { New = function() return scene end },
}
local refresh
local function Changed(settings)
    local changed = false
    for key, value in pairs(flags) do
        if value ~= settings[key] then settings[key], changed = value, true end
    end
    return changed
end
local menu = {
    Combat = function() return true end, -- exercises the sample scene without loading the player model
    Text = function(parent) return New(parent) end, HM = { SkipHistoryCheckpoint = noop },
    catalog = { floatingCombatText = { rules = {} } }, PreviewCanvas = { Changed = Changed },
    M = { TrackRefresh = function(_, callback) refresh = callback end },
    T = { colors = {}, Font = function(parent) return New(parent) end, Button = function(parent, label)
        local button = New(parent)
        buttons[label] = button
        return button
    end },
}
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/FloatingCombatTextPreview.lua"))("MSUF_Suite_QualityOfLife", { Suite = S })
local parent = New()
local _, preview = S.BuildFloatingCombatTextPreview(menu, {}, parent, 640, 0, true)
preview.BuildSamples(parent, "hits", -500)
local function Click(label) buttons[label].scripts.OnClick() end

Click("crit")
assert(#shown == 1 and shown[1][1] == "crit", "manual samples should work even while their setting is off")
Click("Play sample burst")
assert(#shown == 0 and not activeTimer, "disabled events must not appear in a burst")

flags.honor, flags.combat = true, true
Click("Play sample burst")
assert(#shown == 2 and shown[1][1] == "honor" and shown[2][1] == "enter" and not activeTimer,
    "the burst must read changed switches before a queued menu refresh, using only the matching samples")

for _, flag in ipairs({ "hit", "avoid", "xp", "level", "reputation", "honor", "power", "combat" }) do flags[flag] = true end
routes.combat = 3
refresh()
assert(#shown == 4 and shown[1][2] and shown[4][1] == "enter" and not activeTimer,
    "resting preview must fill available lanes without scheduling waves")
routes.combat = 2
Click("Play sample burst")
local seen, count = {}, 0
while true do
    assert(#shown <= 3, "one lane must retain all three lines in a wave")
    for _, sample in ipairs(shown) do
        assert(not seen[sample[1]] and not sample[2])
        seen[sample[1]], count = true, count + 1
    end
    if not activeTimer then break end
    activeTimer:Fire()
end
assert(count == 8 and not seen.leave, "the burst must represent every enabled category even on one lane")

Click("Play sample burst")
assert(activeTimer)
flags.xp = false
activeTimer:Fire()
assert(not activeTimer and #shown == 3 and shown[1][2], "a queued wave must retire after a settings change")
Click("Play sample burst")
assert(activeTimer)
preview.stage.scripts.OnHide()
assert(not activeTimer and #shown == 0, "closing the preview must stop pending waves")
print("Floating combat text burst filters saved events, fits lanes, and cancels pending waves")
