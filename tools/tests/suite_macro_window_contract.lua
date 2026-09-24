local root = assert(arg[1], "Suite root required")

local function Region(path)
    local region = { path = path, alpha = 1, shown = false }
    function region:GetTexture() return self.path end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:IsShown() return self.shown end
    return region
end

local faded, visible, active = {}, {}, {}
local NS = {
    IsCombatLocked = function() return false end,
    Safety = { CanCreateRegions = function() return true end },
    Cosmetics = {
        Fade = function(region) if region then faded[region] = true; region:SetAlpha(0) end end,
        FadeNineSlice = function(region) if region then faded[region] = true end end,
    },
    Surface = {
        Attach = function(button)
            visible[button] = true
            return { edge = { SetDrawLayer = function(self, layer, sublevel)
                self.layer, self.sublevel = layer, sublevel
            end } }
        end,
        SetActive = function(button, selected) active[button] = selected end,
        SetVisible = function(button, shown) visible[button] = shown end,
    },
}
local MacroWindow = assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/MacroWindow.lua"))("MSUF_Suite_Skin", NS)

local function Button(selected)
    local button = {
        Icon = Region(), SelectedTexture = Region(), Highlight = Region(),
        backdrop = Region("Interface\\Buttons\\UI-EmptySlot-Disabled"), hooks = {},
    }
    button.SelectedTexture.shown = selected
    function button:GetRegions() return self.backdrop end
    function button:HookScript(name, callback) self.hooks[name] = callback end
    return button
end

local one, two = Button(true), Button(false)
local rows = { one, two }
local scrollBox = {}
function scrollBox:ForEachFrame(callback)
    for _, button in ipairs(rows) do callback(button) end
end
function scrollBox:RegisterCallback(event, callback, owner)
    self.event, self.callback, self.owner = event, callback, owner
end
function scrollBox:UnregisterCallback(event, owner)
    assert(event == self.event and owner == self.owner)
    self.callback, self.owner = nil, nil
end
ScrollBoxListMixin = { Event = { OnInitializedFrame = "initialized" } }
MacroFramePortrait = Region()
MacroFrameSelectedMacroBackground = Region()
MacroFrameTextBackground = { NineSlice = {} }
local frame = {
    MacroSelector = { ScrollBox = scrollBox },
    SelectedMacroButton = Button(false),
    divider = Region("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar"),
}
function frame:GetRegions() return self.divider end
assert(MacroWindow.Apply(frame, "blizzardWindows"))
assert(faded[MacroFramePortrait] and faded[MacroFrameSelectedMacroBackground]
    and faded[frame.divider] and faded[one.backdrop]
    and faded[MacroFrameTextBackground.NineSlice],
    "Macro window kept its native portrait, divider, slot or editor chrome")
assert(active[one] == true and active[two] == false and scrollBox.callback,
    "Macro selection or pooled-row styling was not initialized")

one.SelectedTexture.shown, two.SelectedTexture.shown = false, true
two.hooks.OnClick(two)
assert(active[one] == false and active[two] == true,
    "Macro selection did not follow Blizzard's click result")
local three = Button(false)
rows[#rows + 1] = three
scrollBox.callback(scrollBox.owner, three)
assert(faded[three.backdrop] and visible[three] and active[three] == false,
    "a newly recycled Macro button kept Blizzard slot art")
assert(MacroWindow.Disable("blizzardWindows") and not scrollBox.callback
    and visible[one] == false and visible[three] == false
    and visible[MacroFrameTextBackground] == false,
    "Macro window did not release its visual ownership")

print("Macro window: native actions preserved, pooled slots, selection and disable passed")
