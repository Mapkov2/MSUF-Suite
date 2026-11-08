local root = assert(arg[1], "Suite root required")
local hooks, walks, reads = 0, 0, 0
local combat = false
local gold, gray = { 1, 0.82, 0, 1 }, { 0.5, 0.5, 0.5, 1 }
local desired = { 0.2, 0.7, 0.9, 1 }
local function Noop() end
InCombatLockdown = function() return combat end
securecallfunction = function(callback, ...) return callback(...) end
hooksecurefunc = function(target, method, callback)
    hooks = hooks + 1
    local original = assert(target[method])
    target[method] = function(...)
        local result = original(...)
        callback(...)
        return result
    end
end
EventRegistry = { RegisterCallback = Noop, UnregisterCallback = Noop }
ScrollBoxListMixin = { Event = { OnInitializedFrame = "init" } }
ButtonGroupBaseMixin = { Event = { Selected = "selected" } }

local NS = {
    DB = { enabled = true }, IsCombatLocked = InCombatLockdown,
    Theme = { GetColor = function() return unpack(desired) end },
    Registry = { AddListener = Noop }, BlizzardFontNames = {},
    WindowActionSkin = { HasOwnedStates = Noop, IsApplied = Noop, DisableOwner = Noop },
}
for _, path in ipairs({ "Safety", "BlizzardYellow", "Checkmarks", "CheckmarksMenus" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/" .. path .. ".lua"))("MSUF_Suite_Skin", NS)
end

local function Label()
    local label = { color = { unpack(gold) } }
    function label:GetObjectType() return "FontString" end
    function label:GetTextColor() return unpack(self.color) end
    function label:SetTextColor(r, g, b, a)
        self.color[1], self.color[2], self.color[3], self.color[4] = r, g, b, a or 1
    end
    label.SetVertexColor = label.SetTextColor
    return label
end

local function Control(hasSlider)
    local row = { Text = Label() }
    function row:IsProtected() return self.protected == true, false end
    function row:GetRegions() reads = reads + 1 return self.Text end
    function row:DisplayEnabled(enabled) self.Text:SetTextColor(unpack(enabled and gold or gray)) end
    if hasSlider then
        local slider = { RightText = Label(), LeftText = Label(), IsProtected = row.IsProtected }
        function slider:GetRegions() reads = reads + 1 return self.LeftText, self.RightText end
        function slider:SetEnabled(enabled)
            local color = enabled and gold or gray
            self.LeftText:SetVertexColor(unpack(color))
            self.RightText:SetVertexColor(unpack(color))
        end
        row.SliderWithSteppers = slider
    end
    function row:EvaluateState(enabled)
        if self.SliderWithSteppers then self.SliderWithSteppers:SetEnabled(enabled) end
        self:DisplayEnabled(enabled)
    end
    return row
end

local function Matches(label, color)
    return label.color[1] == color[1] and label.color[2] == color[2]
        and label.color[3] == color[3] and label.color[4] == color[4]
end

local music, checkbox, independent = Control(true), Control(false), Control(true)
local slider = music.SliderWithSteppers
local scroll = {
    RegisterCallback = function(self, _, callback, state) self.init, self.state = callback, state end,
    UnregisterCallback = function(self) self.init, self.state = nil, nil end,
    ForEachFrame = function(_, visit) walks = walks + 1 visit(music) end,
}
local categories = { ScrollBox = { RegisterCallback = Noop, UnregisterCallback = Noop, ForEachFrame = Noop } }
local panel = { GetSettingsList = function() return { ScrollBox = scroll } end }
local marks, yellow = NS.Checkmarks, NS.BlizzardYellow
assert(marks.TrackSettingsCategories(categories, "settings", panel))
scroll.init(scroll.state, checkbox)

-- Initial paint comes from GenericWindows. Master-volume changes re-evaluate
-- its dependent sliders and can also re-evaluate checkbox rows.
yellow.TrackFrame(music)
yellow.TrackFrame(slider)
yellow.TrackFrame(checkbox)
local initialWalks, initialReads = walks, reads
for _ = 1, 20 do
    music:EvaluateState(true)
    checkbox:EvaluateState(true)
    assert(Matches(music.Text, desired), "dependent slider name returned to Blizzard gold")
    assert(Matches(slider.LeftText, desired) and Matches(slider.RightText, desired),
        "dependent slider values returned to Blizzard gold")
    assert(Matches(checkbox.Text, desired), "dependent checkbox name returned to Blizzard gold")
end
assert(walks == initialWalks and hooks == 3, "slider updates walked the list or installed more hooks")
assert(reads - initialReads == 20 * 3, "an enabled-state update visited more than its own regions")

local before = reads
music:EvaluateState(false)
assert(Matches(music.Text, gray) and Matches(slider.RightText, gray) and reads == before,
    "disabled state should stay gray without visiting regions")
desired = { 0.8, 0.4, 0.6, 1 }
music:EvaluateState(true)
assert(Matches(music.Text, desired) and Matches(slider.RightText, desired), "stale theme color after re-enable")
slider:SetEnabled(false)
assert(Matches(music.Text, desired) and Matches(slider.RightText, gray),
    "disabling just the slider should retain the enabled row color")

combat, music.protected, slider.protected = true, true, true
music:EvaluateState(true)
assert(Matches(music.Text, gold) and Matches(slider.RightText, gold), "protected control repainted in combat")
combat, music.protected, slider.protected = false, false, false
independent:EvaluateState(true)
assert(Matches(independent.Text, gold), "untracked row was recolored")

assert(marks.UntrackSettingsCategories(categories))
music:EvaluateState(true)
assert(Matches(music.Text, gold) and Matches(slider.RightText, gold), "released row was recolored")
assert(marks.TrackSettingsCategories(categories, "settings", panel))
scroll.init(scroll.state, music)
music:EvaluateState(true)
assert(Matches(music.Text, desired) and Matches(slider.RightText, desired) and hooks == 3,
    "recycled control lost its tint or was hooked twice")
NS.DB.enabled = false
music:EvaluateState(true)
assert(Matches(music.Text, gold) and Matches(slider.RightText, gold), "disabled skin repainted")
NS.DB.enabled = true
music:EvaluateState(true)
assert(yellow.Restore())
assert(Matches(music.Text, gold) and Matches(slider.RightText, gold), "global restore lost the native colors")
print("Suite Settings text state passed")
