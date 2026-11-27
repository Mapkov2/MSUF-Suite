-- Rounded windows: one opt-in shape for every skinned window and menu.
-- Real Defaults, Database, Theme, Registry, Geometry, Surface, the window
-- focus outline painter and the Skinning page kit. Shell and popup surfaces
-- take the window radius while the toggle is on; square window chrome keeps
-- its corners and hides; every radius has its corner assets; the outline
-- follows the rounded shape; the settings keep the active look.
local root = assert(arg[1], "Suite root required")
local forever = arg[2] == "Forever"
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = function() return false end
Enum = { UITextureSliceMode = { Stretched = 1 } }
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
C_Timer = { After = function(_, callback) callback() end }
dofile(root .. "/tools/tests/skin_registry_timer_fixture.lua")(C_Timer)

local function Texture()
    local texture = {}
    texture.shown, texture.points = true, {}
    texture.SetGradient, texture.ClearTextureSlice, texture.SetTextureSliceMode = Noop, Noop, Noop
    texture.SetDrawLayer = Noop
    function texture:SetTexture(asset) self.asset = asset end
    function texture:SetTextureSliceMargins(left) self.margin = left end
    function texture:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    function texture:ClearAllPoints() self.points = {} end
    function texture:SetPoint(point, _, _, x) self.points[point] = x end
    return texture
end
local function Target()
    local target = {}
    function target:IsForbidden() return false end
    function target:IsProtected() return false, false end
    function target:GetObjectType() return "Frame" end
    function target:GetParent() return nil end
    function target:CreateTexture() return Texture() end
    function target:HookScript() end
    return target
end

local combat = false
local NS = {
    path = "",
    Client = { isForever = forever },
    IsCombatLocked = function() return combat end,
    BlizzardYellow = { TrackFrame = Noop },
}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", NS)
NS.DB = NS.CopyValue(NS.Defaults)
for _, file in ipairs({ "../MSUF_Suite/Appearance/Safety.lua", "Core/Registry.lua", "Core/Theme.lua",
    "Rendering/Geometry.lua", "Rendering/Surface.lua", "Core/Database.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local Geometry, geometry = NS.Geometry, NS.DB.geometry

local function IsListed(list, value)
    for index = 1, #list do if list[index] == value then return true end end
    return false
end

-- Factory profile: off, with a listed window radius; every offered radius
-- has corner assets.
Check(NS.Defaults.geometry.roundWindows == false, "rounded windows must be opt-in")
Check(IsListed(NS.WindowRadii, NS.Defaults.geometry.windowRadius), "factory window radius is not offered")
for _, list in ipairs({ NS.GeometryRadii, NS.WindowRadii }) do
    for index = 1, #list do Check(IsListed(NS.ShapeRadii, list[index]), "radius without corner assets: " .. list[index]) end
end

-- The factory assets through radius 8 are 20 pixels square. Larger assets
-- grow with their radius. Geometry slices each through its middle.
local function PngSize(path)
    local file = assert(io.open(path, "rb"), "missing corner asset " .. path)
    local header = file:read(24)
    file:close()
    Check(header and header:sub(2, 4) == "PNG", "corner asset is no PNG: " .. path)
    local function Word(offset)
        local a, b, c, d = header:byte(offset, offset + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return Word(17), Word(21)
end
local shapes = root .. "/MSUF_Suite_Skin/Media/Shapes/"
for _, family in ipairs(NS.GeometryFamilies) do
    for _, radius in ipairs(NS.ShapeRadii) do
        local resolved = Geometry.Resolve({ role = "card", shape = family, radius = radius, border = 2 })
        Check(resolved.radius == radius, "radius did not resolve to its own asset: " .. family .. " " .. radius)
        for _, suffix in ipairs({ "fill", "edge1", "edge2" }) do
            local width, height = PngSize(shapes .. family .. "_r" .. radius .. "_" .. suffix .. ".png")
            Check(width == height, "corner asset is not square: " .. family .. " " .. radius)
            Check(resolved.margins[1] == (width - 1) / 2 and resolved.margins[2] == (width - 1) / 2,
                "slice margin does not split the asset: " .. family .. " " .. radius)
        end
        Check(resolved.fill == "Media\\Shapes\\" .. family .. "_r" .. radius .. "_fill.png", "fill asset path changed")
    end
end

local function Radius(spec) return Geometry.Resolve(spec).radius end
local window, popup = { role = "shell", radius = 8 }, { role = "popup", radius = 4 }
local titleBand = { role = "shell", radius = 0, border = 0 }
local card = { role = "card", radius = 6 }

-- Off: Retail keeps each adapter's radius, Forever windows the global radius.
geometry.radius, geometry.windowRadius = 12, 24
Check(Radius(window) == (forever and 12 or 8), "rounded windows off changed a window radius")
Check(Radius(popup) == (forever and 12 or 4), "rounded windows off changed a menu radius")
Check(Radius(card) == 6, "a card followed the window radius")

-- On: every window and menu takes the window radius; square chrome and
-- panels inside windows keep theirs.
geometry.roundWindows = true
Check(Radius(window) == 24 and Radius(popup) == 24, "rounded windows did not reach every window and menu")
Check(Radius({ role = "popup" }) == 24, "a menu without its own radius kept the global radius")
Check(Radius(card) == 6 and Radius({ role = "panel", radius = 8 }) == 8, "rounded windows reached a card or panel")
Check(Radius(titleBand) == (forever and 12 or 4), "square window chrome took the window radius")
local large = Geometry.Resolve(window)
Check(large.fill:find("_r24_fill.png", 1, true) and large.margins[1] == 27.5 and large.roundWindows == true,
    "the largest window radius did not use its own sliced asset")
for _, family in ipairs(NS.GeometryFamilies) do
    for _, radius in ipairs(NS.WindowRadii) do
        geometry.windowRadius = radius
        local cutout = Geometry.Resolve({ role = "shell", shape = family }).outside
        Check(cutout ~= nil, "rounded shell has no inverse mask")
        local expected = radius <= 8 and 20 or 2 * radius + 8
        local width, height = PngSize(shapes .. cutout:match("[^\\]+$"))
        Check(width == expected and height == expected, "inverse mask does not match the visible shell dimensions")
    end
end
Check(Geometry.Resolve(titleBand).outside == nil and Geometry.Resolve(card).outside == nil,
    "square chrome or an interior panel was advertised as a rounded window cutout")
geometry.roundWindows = false
Check(Geometry.Resolve(window).outside == nil, "disabled rounding kept the inverse mask active")

-- Settings: listed values only, refused in combat, and the look stays.
local Theme = NS.Theme
NS.DB.theme.look = "dark"
Check(Theme.SetWindowRounding("roundWindows", true) and geometry.roundWindows == true, "toggle was refused")
Check(Theme.SetWindowRounding("windowRadius", 16) and geometry.windowRadius == 16, "listed radius was refused")
Check(not Theme.SetWindowRounding("windowRadius", 10) and not Theme.SetWindowRounding("windowRadius", "x")
    and geometry.windowRadius == 16, "unlisted window radius was stored")
Check(not Theme.SetWindowRounding("radius", 4) and geometry.radius == 12, "rounding setter wrote another geometry key")
Check(NS.DB.theme.look == "dark", "changing rounded windows detached the active look")
combat = true
Check(not Theme.SetWindowRounding("roundWindows", false) and geometry.roundWindows == true, "combat did not refuse the toggle")
combat = false

-- Imported or older profiles normalize to the factory choice.
NS.FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" }
local imported = NS.CopyValue(NS.Defaults)
imported.geometry.roundWindows, imported.geometry.windowRadius = "yes", 13
NS.Database.Normalize(imported)
Check(imported.geometry.roundWindows == false and imported.geometry.windowRadius == NS.Defaults.geometry.windowRadius,
    "invalid rounding values survived normalization")
local old = NS.CopyValue(NS.Defaults)
old.geometry.roundWindows, old.geometry.windowRadius = nil, nil
NS.Database.Normalize(old)
Check(old.geometry.roundWindows == false and old.geometry.windowRadius == NS.Defaults.geometry.windowRadius,
    "an older profile did not gain the rounding defaults")
imported.geometry.roundWindows, imported.geometry.windowRadius = true, 20
NS.Database.Normalize(imported)
Check(imported.geometry.roundWindows == true and imported.geometry.windowRadius == 20, "saved rounding choice was lost")

-- A title band would cut into rounded corners: it hides while windows are
-- rounded and returns with them off.
local band = Target()
local bandSpec = { role = "shell", radius = 0, border = 0, motion = false, hideWhenRounded = true }
geometry.roundWindows = false
local state = NS.Surface.Attach(band, bandSpec)
Check(state and state.fill.shown, "square window chrome hid without rounded windows")
geometry.roundWindows = true
state.refresh(state)
Check(not state.fill.shown, "square window chrome stayed over rounded corners")
geometry.roundWindows = false
state.refresh(state)
Check(state.fill.shown, "square window chrome did not return with rounded windows off")
geometry.roundWindows = true
local plain = NS.Surface.Attach(Target(), { role = "shell", radius = 8 })
Check(plain.fill.shown and plain.fill.asset:find("_r16_fill.png", 1, true), "a rounded window lost its fill")

-- The window outline: one 1 px ring, or 2 px rings one unit apart, all on
-- the window's rounded shape.
local frames = {}
CreateFrame = function()
    local frame = { shown = false }
    frames[#frames + 1] = frame
    function frame:EnableMouse() end
    function frame:SetAllPoints(target) self.anchor = target end
    function frame:SetParent(target) self.parent = target end
    function frame:CreateTexture() return Texture() end
    function frame:GetEffectiveScale() return (self.scale or 1) * UIParent:GetEffectiveScale() end
    function frame:SetScale(scale) self.scale = scale end
    function frame:GetFrameStrata() return self.strata end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:GetFrameLevel() return self.level end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    return frame
end
UIParent = { GetEffectiveScale = function() return .8 end }
NS.SuiteCore = function() return { WindowCaption = { PixelFactor = function() return .8 end } } end
assert(loadfile(root .. "/MSUF_Suite_Skin/Rendering/WindowFocusVisual.lua"))("MSUF_Suite_Skin", NS)
local Visual = NS.WindowFocusVisual
local function Shown(art)
    local count = 0
    for _, ring in ipairs(art.rings) do if ring.shown then count = count + 1 end end
    return count
end
local owner = { scale = .8, GetEffectiveScale = function(self) return self.scale end }
local art = Visual.PaintRoundOutline(owner, nil, 1, 1, 0, 0, 1, "HIGH", 40)
Check(art.anchor == owner and art.shown and art.strata == "HIGH" and art.level == 40, "outline did not follow its window")
Check(Shown(art) == 1 and art.rings[1].asset:find("_r16_edge1.png", 1, true), "a 1 px outline is not one thin ring")
Visual.PaintRoundOutline(owner, art, 4, 1, 0, 0, 1, "HIGH", 40)
Check(Shown(art) == 3 and art.rings[3].asset:find("_r16_edge2.png", 1, true) and art.rings[3].points.TOPLEFT == 2,
    "a 4 px outline is not three stacked rings")
Visual.PaintRoundOutline(owner, art, 10, 1, 0, 0, 1, "HIGH", 40)
Check(Shown(art) == 9, "the widest outline does not cover its thickness")
Visual.PaintRoundOutline(owner, art, 2, 1, 0, 0, 1, "HIGH", 40)
Check(Shown(art) == 1 and art.rings[1].asset:find("_edge2.png", 1, true) and #frames == 1,
    "a thinner outline kept old rings or built another frame")
local attached = Visual.PaintRoundOutline(owner, nil, 3, 1, 0, 0, 1, nil, nil, true, true)
Check(attached.parent == owner and attached.anchor == owner and attached.strata == nil and attached.level == nil
    and Shown(attached) == 2, "the owned outline did not inherit the window parent, layer or logical width")
owner.scale = .64
Visual.PaintRoundOutline(owner, art, 1, 1, 0, 0, 1, "HIGH", 40)
Check(math.abs(art:GetEffectiveScale() - .64) < .000001, "detached outline used UIParent scale instead of the skinned window scale")
owner.scale = .8
Visual.PaintRoundOutline(owner, art, 1, 1, 0, 0, 1, "HIGH", 40)
Check(art.scale == 1, "the reused detached outline did not reset after restoring the window scale")

-- The Skinning page: a toggle and a radius that waits for it, in the shape section.
local P = setmetatable({
    Tr = function(text) return text end,
    Meta = function() return {} end,
    SummaryPriority = function() return nil end,
}, { __index = function() return Noop end })
assert(loadfile(root .. "/MSUF_Suite_Options/Pages/AppearanceKit.lua"))("MSUF_Suite_Options", P)
local rows = {}
local skin = { DB = NS.DB, Theme = Theme, WindowRadii = NS.WindowRadii }
P.SkinPageKit.AddWindowRoundingRows(rows, skin)
Check(#rows == 2 and rows[1].id == "geometry.roundWindows" and rows[1].kind == "toggle", "rounding toggle row missing")
Check(rows[2].id == "geometry.windowRadius" and rows[2].kind == "dropdown" and #rows[2].values == #NS.WindowRadii,
    "window radius row does not offer every radius")
geometry.roundWindows = false
Check(rows[2].unavailable() ~= nil and rows[1].get() == false, "radius row is available while rounding is off")
geometry.roundWindows = true
Check(rows[2].unavailable() == nil and rows[2].get() == geometry.windowRadius, "radius row did not follow the setting")
local source = assert(io.open(root .. "/MSUF_Suite_Options/Pages/Appearance.lua", "rb")):read("*a")
Check(source:find("Kit.AddWindowRoundingRows(shape, skin)", 1, true), "the shape section does not list the rounding rows")

print(("suite_skin_rounded_windows_contract%s: %d checks passed"):format(forever and " (Forever)" or "", checks))
