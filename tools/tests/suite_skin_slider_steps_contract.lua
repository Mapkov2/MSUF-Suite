-- Exercise the standalone Skin options slider through its value-change callback.
local refreshers = {}
local function Frame()
    local frame = { scripts = {} }
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:SetValue(value)
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    function frame:GetValue() return self.value end
    function frame:SetValueStep(value) self.step = value end
    function frame:CreateTexture() return Frame() end
    return setmetatable(frame, { __index = function() return function() end end })
end
CreateFrame = function() return Frame() end

local NS = {
    path = "",
    IsCombatLocked = function() return false end,
    Theme = { GetColor = function() return 1, 1, 1 end },
}
local O = {
    CreatePanel = function() return Frame() end,
    CreateText = function() return Frame() end,
    TrackRefresh = function(callback) refreshers[#refreshers + 1] = callback end,
    BeginUserChange = function() return true end,
    CommitUserChange = function() end,
    RefreshAll = function() for _, callback in ipairs(refreshers) do callback() end end,
}
assert(loadfile("MSUF_Suite_Skin_Options/Shell/Widgets.lua"))("MSUF_Suite_Skin_Options", {
    NS = NS, Options = O,
})

local function Slider(minimum, maximum, step, initial)
    local value = initial
    local row = O.CreateSlider(Frame(), "test", minimum, maximum, step,
        function() return value end, function(nextValue) value = nextValue end)
    return row._mskinControl, function() return value end
end
local function Near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001,
        ("expected %s, got %s"):format(expected, actual))
end

local whole, wholeValue = Slider(0, 100, 5, 50)
assert(whole.step == 1, "whole-number slider did not use single steps")
whole:SetValue(51)
Near(wholeValue(), 51)
IsShiftKeyDown = function() return true end
whole:SetValue(63)
Near(wholeValue(), 65)
IsShiftKeyDown = nil
IsControlKeyDown = function() return true end
whole:SetValue(79)
Near(wholeValue(), 80)
IsControlKeyDown = nil

local fraction, fractionValue = Slider(0.35, 1, 0.05, 0.95)
Near(fraction.step, 0.01)
fraction:SetValue(0.96)
Near(fractionValue(), 0.96)
IsShiftKeyDown = function() return true end
fraction:SetValue(0.87)
Near(fractionValue(), 0.85)
IsShiftKeyDown = nil
IsControlKeyDown = function() return true end
fraction:SetValue(0.91)
Near(fractionValue(), 0.95)
IsControlKeyDown = nil

print("Suite Skinning sliders: single, Shift 5x and Ctrl 10x steps passed")
