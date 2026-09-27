local root = assert(arg[1], "Suite root required")

-- The client's securecallfunction reports an error to the error handler and
-- returns nothing; the caller goes on.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end

local faded = {}
local textureReads = 0
local function Region(path)
    local region = { path = path, alpha = 1, shown = false }
    function region:GetTexture()
        textureReads = textureReads + 1
        return self.path
    end
    function region:GetAlpha() return self.alpha end
    function region:SetAlpha(alpha)
        self.alpha = alpha
        if alpha == 0 then faded[self] = true end
    end
    function region:IsShown() return self.shown end
    function region:GetDrawLayer() return self.layer or "BACKGROUND" end
    return region
end

local visible, active, specs, surfaces = {}, {}, {}, {}
local attaches = {}
local eventFrame = {}
function eventFrame:RegisterEvent(event) self.event = event end
function eventFrame:UnregisterEvent(event)
    if self.event == event then self.event = nil end
end
function eventFrame:SetScript(script, callback)
    if script == "OnEvent" then self.onEvent = callback end
end
CreateFrame = function() return eventFrame end
hooksecurefunc = function(target, method, callback)
    local native = target[method]
    target[method] = function(self, ...)
        native(self, ...)
        callback(self, ...)
    end
end
local NS = {
    IsCombatLocked = function() return false end,
    Cosmetics = {
        Fade = function(region) if region then faded[region] = true; region:SetAlpha(0) end end,
        FadeNineSlice = function(region) if region then faded[region] = true end end,
    },
    Surface = {
        -- One surface record per target, like Registry's.
        Attach = function(button, spec)
            attaches[button] = (attaches[button] or 0) + 1
            visible[button] = true
            specs[button] = spec
            local surface = surfaces[button]
            if not surface then
                surface = { edge = { SetDrawLayer = function(self, layer, sublevel)
                    self.layer, self.sublevel = layer, sublevel
                end } }
                surfaces[button] = surface
            end
            surface.spec, surface.visible = spec, true
            return surface
        end,
        SetActive = function(button, selected) active[button] = selected end,
        SetVisible = function(button, shown)
            visible[button] = shown
            if surfaces[button] then surfaces[button].visible = shown end
        end,
    },
    Client = { HasAddOn = function() return true end },
    Registry = { GetSurface = function(target) return surfaces[target] end },
}
-- The real guards and ScrollBox row helpers.
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/AdapterKit.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/SharedChrome.lua"))("MSUF_Suite_Skin", NS)
local MacroWindow = assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/MacroWindow.lua"))("MSUF_Suite_Skin", NS)

local function Button(selected)
    local button = {
        Icon = Region(), SelectedTexture = Region(), Highlight = Region(),
        backdrop = Region("Interface\\Buttons\\UI-EmptySlot-Disabled"),
        ownFill = Region(), hooks = {},
    }
    button.SelectedTexture.shown = selected
    function button:GetRegions() return self.backdrop, self.ownFill end
    function button:HookScript(name, callback) self.hooks[name] = callback end
    return button
end

local one, two = Button(true), Button(false)
two.backdrop.path = nil
function two.backdrop:GetTexCoord()
    return 0.140625, 0.84375, 0.140625, 0.84375
end
local rows = { one, two }
local scrollBox = {}
scrollBox.viewReady = false
function scrollBox:HasView() return self.viewReady end
function scrollBox:ForEachFrame(callback)
    assert(self.viewReady, "ForEachFrame reached an uninitialized Blizzard view")
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
MacroHorizontalBarLeft = Region()
MacroFrameTextBackground = { NineSlice = Region() }
local frame = {
    Bg = Region(), NineSlice = Region(),
    MacroSelector = nil,
    SelectedMacroButton = Button(false),
    divider = Region("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar"),
    dividerRight = Region(),
    PortraitContainer = Region(),
    Inset = { Bg = Region(), NineSlice = Region() },
    shown = false,
    hooks = {},
}
frame.PortraitContainer.portrait = Region()
function frame.dividerRight:GetPoint()
    return "LEFT", MacroHorizontalBarLeft, "RIGHT"
end
function frame:IsShown() return self.shown end
function frame:Update() self.nativeUpdated = true end
function frame:GetRegions() return self.divider, self.dividerRight end
function frame:HookScript(script, callback) self.hooks[script] = callback end
assert(MacroWindow.Start("blizzardWindows") and eventFrame.event == "ADDON_LOADED",
    "Macro window did not wait for Blizzard_MacroUI")
MacroFrame = frame
eventFrame.onEvent(eventFrame, "ADDON_LOADED", "Other_Addon")
assert(not faded[MacroFramePortrait] and eventFrame.event == "ADDON_LOADED",
    "Unrelated addon load styled the Macro window")
eventFrame.onEvent(eventFrame, "ADDON_LOADED", "Blizzard_MacroUI")
assert(not faded[MacroFramePortrait] and frame.hooks.OnShow and not eventFrame.event,
    "Macro window touched Blizzard's hidden, unfinished selector")
frame.MacroSelector = { ScrollBox = scrollBox }
frame.shown = true
frame.hooks.OnShow(frame)
assert(faded[MacroFramePortrait] and scrollBox.callback and not faded[one.backdrop],
    "Macro window did not wait for the selector view")
scrollBox.viewReady = true
local frameAttaches = attaches[frame]
frame:Update()
assert(frame.nativeUpdated and faded[one.backdrop] and faded[two.backdrop],
    "Macro skin did not follow Blizzard's native Update")
-- Opening runs OnShow and Update twice: the window chrome takes one pass.
frame.hooks.OnShow(frame)
frame:Update()
assert(attaches[frame] == frameAttaches and MacroFramePortrait.alpha == 0,
    "Blizzard's Update and OnShow repeated the Macro window chrome pass")
-- Recycled slots only follow the selection once styled.
local slotAttaches, reads = attaches[one], textureReads
active[one] = nil
scrollBox.callback(scrollBox.owner, one)
scrollBox.callback(scrollBox.owner, two)
assert(faded[one.backdrop] and faded[two.backdrop],
    "Initialized macro rows kept the native slot background")
assert(attaches[one] == slotAttaches and textureReads == reads and active[one] == true,
    "a recycled Macro slot was styled again instead of following its selection")
-- A slot whose surface another skin replaced takes the slot surface again.
NS.Surface.Attach(one, { role = "card" })
scrollBox.callback(scrollBox.owner, one)
assert(specs[one] and specs[one].role == "button",
    "a Macro slot kept a surface another skin attached")
-- Update runs inside Blizzard's call: a raising slot is reported and
-- Blizzard's Update goes on.
local raising = Button(false)
function raising:GetRegions() error("contract: macro slot raised") end
rows[#rows + 1] = raising
local before = #reported
local updated = pcall(frame.Update, frame)
table.remove(rows)
assert(updated and #reported == before + 1,
    "a raising Macro slot escaped into Blizzard's Update")
assert(MacroWindow.Apply(frame, "blizzardWindows"))
assert(not faded[one.ownFill], "A second pass faded the Suite slot surface")
assert(faded[MacroFramePortrait] and faded[MacroFrameSelectedMacroBackground]
    and faded[frame.PortraitContainer] and faded[frame.PortraitContainer.portrait]
    and faded[frame.Inset.Bg] and faded[frame.Inset.NineSlice]
    and faded[MacroHorizontalBarLeft]
    and faded[frame.divider] and faded[frame.dividerRight] and faded[one.backdrop]
    and faded[MacroFrameTextBackground.NineSlice],
    "Macro window kept its native portrait, divider, slot or editor chrome")
assert(specs[frame] and specs[frame].role == "popup"
    and specs[frame].fillAlphaScale > 1,
    "Macro adapter did not own a dense dark window shell")
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
    and visible[frame] == false
    and visible[frame.Inset] == false and visible[MacroFrameTextBackground] == false,
    "Macro window did not release its visual ownership")
assert(MacroFramePortrait.alpha == 1 and frame.Bg.alpha == 1
    and frame.NineSlice.alpha == 1 and one.backdrop.alpha == 1
    and frame.Inset.NineSlice.alpha == 1,
    "Macro window did not restore exact native alpha values")

print("Macro window: native actions preserved, pooled slots, selection and disable passed")
