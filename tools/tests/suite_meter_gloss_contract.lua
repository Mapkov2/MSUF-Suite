-- Real meter configuration, runtime rows and the menu's own runtime preview.
local root, flavor, sourceOverride = assert(arg[1]), arg[2] or "Mainline", arg[3]
local originalLoad, private, secretTest = loadfile
loadfile = function(path)
    if sourceOverride and path:find("MSUF_Suite_DamageMeter/Rows.lua", 1, true) then path = sourceOverride end
    local chunk = assert(originalLoad(path))
    return function(addon, namespace)
        if path:find("MSUF_Suite_DamageMeter/Data.lua", 1, true) then private, secretTest = namespace, issecretvalue end
        return chunk(addon, namespace)
    end
end
local fixture = flavor == "Forever" and "suite_damage_meter_threat_contract.lua" or "suite_damage_meter_contract.lua"
assert(originalLoad(root .. "/tools/tests/" .. fixture))()
loadfile, issecretvalue = originalLoad, secretTest
local S, D, NS = private.Suite, private.DamageMeter, private.NS
local M = D.M
local rules = S.catalog.damageMeter.rules
assert(rules.glossEnabled and rules.glossEnabled.default == false, "meter Gloss must be optional for existing profiles")
assert(rules.glossStrength and rules.glossStrength.default == 50, "meter Gloss strength default missing")
assert(rules.glossStrength.enableKey == "glossEnabled", "meter Gloss strength gate missing")
M:Disable()
M.active = false
assert(originalLoad(root .. "/MSUF_Suite_DamageMeter/Preview.lua"))("MSUF_Suite_DamageMeter", private)
local c = S.Config("damageMeter")
c.glossEnabled, c.glossStrength, c.barAlpha = false, 50, 35
local stage = CreateFrame("Frame", nil, UIParent)
local Region, textures = getmetatable(stage), {}
local createTexture, setAlpha, setTexture = Region.CreateTexture, Region.SetAlpha, Region.SetTexture
Region.CreateTexture = function(self, ...)
    local texture = createTexture(self, ...)
    textures[#textures + 1] = texture
    return texture
end
-- Native region alpha may be shared by SetAlpha and SetVertexColor. This
-- stricter model ensures opacity cannot overwrite the material's intensity.
Region.SetVertexColor = function(self, r, g, b, alpha)
    self.vertex = { r, g, b }
    self.alpha = alpha == nil and 1 or alpha
end
Region.GetVertexColor = function(self)
    local color = self.vertex or { 1, 1, 1 }
    return color[1], color[2], color[3], self.alpha
end
Region.SetTexCoord = function(self, ...) self.coords = { ... } end
Region.GetTexCoord = function(self) return unpack(self.coords or { 0, 1, 0, 1 }) end
Region.SetAlpha = function(self, alpha) return setAlpha(self, alpha) end
Region.SetTexture = function(self, path, ...) self.texture = path return setTexture(self, path, ...) end
Region.SetBlendMode = function(self, mode) self.blendMode = mode end
MSUF_HostAPI = { version = 1, GetIconSkins = function()
    return { version = 1, Subscribe = function() return true end, Compile = function() return nil end,
        Paint = function() return false end,
        GlossTexture = function() return "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Skins\\msuf_skin_gloss_top.tga" end }
end }
assert(originalLoad(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", NS)
assert(originalLoad(root .. "/MSUF_Suite/Core/GlossMaterial.lua"))("MSUF_Suite", NS)
local calls, paint = 0, NS.GlossMaterial.Bar
NS.GlossMaterial.Bar = function(...) calls = calls + 1 return paint(...) end
local function Draw() return S.DamageMeterDrawMenuPreview(stage, 1) end
local function Layers(bar)
    local result = {}
    for _, texture in ipairs(textures) do
        if texture:GetParent() == bar and type(texture.texture) == "string"
            and texture.texture:find("msuf_skin_gloss_top.tga", 1, true) then result[#result + 1] = texture end
    end
    return result
end
local function Material(row, strength, opacity, visible)
    local list = Layers(row.bar)
    assert(#list == 2, "Gloss must retain exactly two reflected-light regions")
    local upper, lower
    for _, texture in ipairs(list) do
        local _, _, top, bottom = texture:GetTexCoord()
        if top == 0 and bottom == 2 then upper = texture else lower = texture end
        assert(texture:IsShown() == visible, "Gloss visibility differs from its setting")
        local anchored = texture.allPoints == row.bar:GetStatusBarTexture()
        for _, point in ipairs(texture.points) do
            anchored = anchored or point[2] == row.bar:GetStatusBarTexture()
        end
        assert(not visible or anchored, "Gloss does not follow the native meter fill")
    end
    if visible then
        assert(upper and lower and upper.blendMode == "ADD" and lower.blendMode == "ADD", "reflections lost their neutral additive light")
        assert(math.abs(upper:GetVertexColor() * upper:GetAlpha() - .65 * strength / 100 * opacity) < .000001,
            "meter opacity overwrote the upper Gloss intensity")
        assert(math.abs(lower:GetVertexColor() * lower:GetAlpha() - .08 * strength / 100 * opacity) < .000001,
            "meter opacity overwrote the lower Gloss intensity")
    end
    return list
end
local win = Draw()
local row = win.rows[1]
assert(#Layers(row.bar) == 0 and calls == 0, "disabled Gloss allocated textures or called the material helper")
c.glossEnabled = true
Draw()
assert(M.style.glossEnabled and M.style.glossStrength == 50, "catalog setting did not compile into the meter style")
local retained = Material(row, 50, .35, true)
local beforeCalls, beforeTextures = calls, #textures
for pass = 1, 20 do Draw() end
assert(calls == beforeCalls and #textures == beforeTextures, "unchanged menu preview repainted Gloss")
local source = { name = "Player", classFilename = "WARRIOR", specIconID = 132355, totalAmount = 50, amountPerSecond = 5 }
local session = { maxAmount = 100, totalAmount = 100 }
for pass = 1, 1000 do
    source.totalAmount = pass
    D.PaintSource(row, source, 1, session, win)
end
assert(calls == beforeCalls and #textures == beforeTextures, "meter data updates touched Gloss material")
for _, kind in ipairs({ "spell", "tip" }) do
    local detail = D.CreateRow(win.body, win, kind)
    D.StyleRow(detail)
    Material(detail, 50, .35, true)
end
c.glossStrength, c.barAlpha = 80, 65
Draw()
local nextLayers = Material(row, 80, .65, true)
assert(nextLayers[1] == retained[1] and nextLayers[2] == retained[2], "strength edits replaced Gloss regions")
c.glossStrength = 0
Draw()
assert(M.style.glossStrength == 0, "explicit zero strength was replaced")
Material(row, 0, .65, false)
c.glossStrength, c.barAlpha = 50, 0
Draw()
Material(row, 50, 0, true)
c.glossEnabled = false
Draw()
Material(row, 50, 0, false)
assert(not M.active and not M.preview, "menu preview activated the live meter")
print("meter Gloss: " .. flavor .. " PASS; optional defaults, real style/preview, rows/details/tips, opacity/zero, 1000 updates without material work")
