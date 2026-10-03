-- Native inherited chrome with the real GenericWindows, Cosmetics and Surface.
local root = assert(arg[1], "Suite root required")
local adapterPath = arg[2] or root .. "/MSUF_Suite_Skin/Adapters/ForeverGroupFinder.lua"
local skin = root .. "/MSUF_Suite_Skin/"
local function Noop() end
local function False() return false end
securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = False

local function Texture(name, path, atlas)
    local region = { alpha = 1, shown = true, name = name, path = path, atlas = atlas }
    function region:GetObjectType() return "Texture" end
    function region:GetName() return self.name end
    function region:GetTexture() return self.path end
    function region:GetTextureFilePath()
        if type(self.path) == "string" then return self.path end
    end
    function region:GetAtlas() return self.atlas end
    function region:GetAlpha() return self.alpha end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:IsShown() return self.shown end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetVertexColor(...) self.vertex = { ... } end
    region.ClearAllPoints, region.SetPoint = Noop, Noop
    return region
end

local function Frame(name, parent)
    local frame = { name = name, parent = parent, regions = {}, scripts = {}, events = {} }
    function frame:GetName() return self.name end
    function frame:GetObjectType() return "Frame" end
    function frame:GetParent() return self.parent end
    function frame:GetRegions() return unpack(self.regions) end
    function frame:GetNumChildren() return 0 end
    function frame:CreateTexture(_, layer, _, sublevel)
        local region = Texture()
        region.layer, region.sublevel = layer, sublevel
        self.regions[#self.regions + 1] = region
        return region
    end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    return frame
end
CreateFrame = function() return Frame() end

local surfaces, locked, pending = {}, false, {}
local colors = { background = { .1, .1, .1, .8 }, border = { .4, .4, .4, 1 } }
local geometry = { fill = "fixture-fill", edge = "fixture-edge" }
local material = { from = "background", to = "background", border = "border" }
local NS = {
    Client = { isForever = true, HasAddOn = function() return true end },
    DB = { theme = { gradient = false, materialDepth = 0, gradientStrength = 1 } },
    IsCombatLocked = function() return locked end,
    Theme = {
        GetMaterial = function() return material end,
        GetColorTable = function(key) return assert(colors[key]) end,
        GetColor = function(key) return unpack(assert(colors[key])) end,
        GetMaterialOpacity = function() return 1 end, GetBorderOpacity = function() return 1 end,
    },
    Geometry = { Resolve = function() return geometry end, ConfigureShape = Noop },
    Registry = {
        GetSurface = function(frame) return surfaces[frame] end,
        RegisterSurface = function(frame, state) surfaces[frame] = state end,
        AddListener = Noop,
    },
    CombatGate = {
        RunOrDefer = function(key, callback)
            if locked then pending[key] = callback return false, "combat" end
            return callback()
        end,
        Cancel = function(key) pending[key] = nil end,
    },
    SuiteOwnership = { IsBagShell = False },
    BlizzardYellow = { TrackFrame = Noop, TrackMenuSelection = Noop },
    Checkmarks = { TrackFrame = Noop, TrackDropdown = Noop, UntrackOwner = Noop },
    CharacterDetails = { IsHost = False }, CharacterStats = { IsHost = False }, EQoLCharacter = { IsHost = False },
    WindowControls = { Attach = Noop },
    ControlSkin = { DisableOwner = Noop }, IconSkin = { DisableOwner = Noop },
    ScrollBarSkin = { DisableOwner = Noop },
}
for _, path in ipairs({ "Core/Safety.lua", "Core/Cosmetics.lua", "Adapters/AdapterKit.lua",
    "Rendering/Surface.lua", "Adapters/GenericWindows.lua", "Adapters/GenericWindowsNodes.lua",
    "Adapters/GenericWindowsFrames.lua" }) do
    assert(loadfile(skin .. path))("MSUF_Suite_Skin", NS)
end
NS.GenericWindows.IsCategoryEnabled = function() return true end
NS.GenericWindows.Disable = function(owner)
    if locked then return false, "combat" end
    NS.GenericWindowsShared.DeactivateOwner(owner)
    return true
end
assert(loadfile(adapterPath))("MSUF_Suite_Skin", NS)

UIParent = Frame("UIParent")
LFGParentFrame = Frame("LFGParentFrame", UIParent)
local windows = {}
for _, name in ipairs({ "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame" }) do
    local pane = Frame(name, LFGParentFrame)
    _G[name] = pane
    windows[#windows + 1] = pane
    -- PortraitFrameTexturedBaseTemplate supplies $parentBg at BACKGROUND -6.
    -- Native texture getters may expose only a numeric file ID. Its value
    -- here is fixture data; the exact XML name must identify that region.
    pane.inheritedRock = Texture(name .. "Bg", 101)
    pane.regions[#pane.regions + 1] = pane.inheritedRock
    pane.Bg = pane.inheritedRock
    pane.TopTileStreaks = Texture(nil, nil, "_UI-Frame-TopTileStreaks")
    pane.regions[#pane.regions + 1] = pane.TopTileStreaks
    pane.NineSlice = {}
    for _, key in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
        "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
        pane.NineSlice[key] = Texture()
    end
    pane.TitleContainer = { TitleText = { text = "Looking For Group" } }
    pane.PortraitContainer = { portrait = Texture(nil, "Interface\\Icons\\SemanticPortrait") }
end
-- The browse XML declares $parentBg/Bg again for its small stone header.
-- Model both regions: the displaced inherited texture is no longer in .Bg.
LFGBrowseFrame.Bg = Texture("LFGBrowseFrameBg", nil, "groupfinder-Stat-StoneBG")
LFGBrowseFrame.regions[#LFGBrowseFrame.regions + 1] = LFGBrowseFrame.Bg
-- Unnamed inherited regions are identifiable only by the exact native file.
local unnamedRock = Texture(nil, "interface/framegeneral/ui-background-rock")
LFGBrowseFrame.regions[#LFGBrowseFrame.regions + 1] = unnamedRock
local semantic = Texture(nil, "Interface\\Icons\\SemanticRole", "groupfinder-icon-role-large-tank")
LFGBrowseFrame.regions[#LFGBrowseFrame.regions + 1] = semantic

assert(NS.ForeverGroupFinder.Apply())
assert(surfaces[LFGParentFrame].fill:IsShown(), "group finder shell has no fill")
assert(LFGBrowseFrame.inheritedRock:GetAlpha() == 0 and unnamedRock:GetAlpha() == 0,
    "displaced inherited PortraitFrame rock still covers the group finder shell")
for _, pane in ipairs(windows) do
    assert(pane.Bg:GetAlpha() == 0 and pane.TopTileStreaks:GetAlpha() == 0)
    assert(not surfaces[pane].fill:IsShown(), "pane stacked another fill above the glass shell")
    for _, region in pairs(pane.NineSlice) do assert(region:GetAlpha() == 0) end
    assert(pane.TitleContainer.TitleText.text == "Looking For Group")
    assert(pane.PortraitContainer.portrait:GetAlpha() == 1)
end
assert(semantic:GetAlpha() == 1, "window-chrome pass faded a semantic region")

assert(NS.ForeverGroupFinder.Disable())
assert(LFGBrowseFrame.inheritedRock:GetAlpha() == 1 and unnamedRock:GetAlpha() == 1,
    "disabling the skin did not restore inherited native backgrounds")
assert(not surfaces[LFGParentFrame].fill:IsShown())
assert(NS.ForeverGroupFinder.Apply())
assert(LFGBrowseFrame.inheritedRock:GetAlpha() == 0 and unnamedRock:GetAlpha() == 0)
locked = true
unnamedRock:SetAlpha(.5)
assert(NS.ForeverGroupFinder.Apply() and next(pending))
assert(unnamedRock:GetAlpha() == .5, "inherited chrome was painted during combat")
locked = false
for key, callback in pairs(pending) do pending[key] = nil callback() end
assert(unnamedRock:GetAlpha() == 0, "deferred chrome pass lost inherited background")
assert(NS.ForeverGroupFinder.Disable())
print("Forever inherited background, real shell layering, combat and restore passed")
