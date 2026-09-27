local _, NS = ...
-- One renderer is used by the live minimap and its options preview. Ornament
-- textures belong to the Suite; Blizzard's map and buttons remain untouched.
local Style = {}
NS.MinimapStyle = Style
local MEDIA = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\"
Style.paths = { false, MEDIA .. "ArcaneRing.tga", MEDIA .. "EmberRing.tga",
    MEDIA .. "AstralRing.tga", MEDIA .. "SteelFrame.tga" }
local HALO, CIRCLE = MEDIA .. "Halo.tga", MEDIA .. "Circle.tga"
local RGB = NS.RGB

local function Texture(parent, layer, sub)
    return parent:CreateTexture(nil, layer, nil, sub)
end
local function Surface(parent, level)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(level)
    frame:EnableMouse(false)
    return frame
end
-- The renderer's own fields on a texture, read past the widget metatable.
local function Stored(widget, key)
    if type(widget) == "table" then return rawget(widget, key) end
    return widget[key]
end
local function Rotate(texture, speed, animate)
    local group = Stored(texture, "_msufStyleRotation")
    if not animate or speed == 0 then
        if group then group:Stop() end
        texture:SetRotation(0)
        return
    end
    if not group then
        group = texture:CreateAnimationGroup()
        local animation = group:CreateAnimation("Rotation")
        animation:SetOrigin("CENTER", 0, 0)
        group:SetLooping("REPEAT")
        texture._msufStyleRotation = group
        texture._msufStyleRotationAnimation = animation
    end
    local rotation = Stored(texture, "_msufStyleRotationAnimation")
    if Stored(texture, "_msufStyleRotationSpeed") ~= speed then
        group:Stop()
        rotation:SetDegrees(speed > 0 and -360 or 360)
        rotation:SetDuration(360 / math.abs(speed))
        texture._msufStyleRotationSpeed = speed
    end
    if not group:IsPlaying() then group:Play() end
end
local function Assign(texture, path)
    if Stored(texture, "_msufStyleTexture") == path then return end
    texture._msufStyleTexture = path
    texture:SetTexture(path)
end
local function Visible(layerOn, key)
    return not layerOn or layerOn(key)
end

------------------------------------------------------------------ paint steps
local function PaintBackdrop(self, c, scale, width, height, layerOn)
    local alpha = (tonumber(c.styleBackdropAlpha) or 0) / 100
    local plate = c.styleBackdrop == true and alpha > 0 and Visible(layerOn, "backdrop")
    if plate then
        local pad = (tonumber(c.styleBackdropPadding) or 0) * scale
        local r, g, b = RGB(c.styleBackdropColor)
        if c.shape == 2 then
            Assign(self.backdrop, CIRCLE)
            self.backdrop:SetVertexColor(r, g, b, alpha)
        else
            self.backdrop._msufStyleTexture = nil
            self.backdrop:SetColorTexture(r, g, b, alpha)
        end
        self.backdrop:SetSize(width + pad * 2, height + pad * 2)
    end
    self.backdrop:SetShown(plate)
end

local function PaintGlow(self, c, width, height, layerOn)
    local alpha = (tonumber(c.styleGlowAlpha) or 0) / 100
    local glow = c.styleGlow == true and alpha > 0 and Visible(layerOn, "glow")
    if glow then
        local r, g, b = RGB(c.styleGlowColor)
        local factor = (tonumber(c.styleGlowScale) or 145) / 100
        self.glow:SetSize(width * factor, height * factor)
        self.glow:SetVertexColor(r, g, b, alpha)
    end
    self.glow:SetShown(glow)
end

-- The ornament path of the chosen artwork (6 is a custom file or ID).
local function ArtPath(c)
    local choice = tonumber(c.styleTexture) or 1
    if choice == 6 and type(c.styleTexturePath) == "string" and c.styleTexturePath ~= "" then
        return tonumber(c.styleTexturePath) or c.styleTexturePath
    end
    return Style.paths[choice]
end

-- One of the two ornament layers: under or over the map, never both.
local function PaintArt(self, texture, shown, path, c, scale, width, height, animate)
    texture:SetShown(shown)
    if shown then
        Assign(texture, path)
        local factor = (tonumber(c.styleScale) or 100) / 100
        texture:SetSize(width * factor, height * factor)
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", self.parent, "CENTER", (tonumber(c.styleX) or 0) * scale,
            (tonumber(c.styleY) or 0) * scale)
        local r, g, b = RGB(c.styleColor)
        texture:SetVertexColor(r, g, b, (tonumber(c.styleAlpha) or 0) / 100)
        texture:SetBlendMode(c.styleBlend == 2 and "ADD" or "BLEND")
    end
    Rotate(texture, shown and (tonumber(c.styleRotation) or 0) or 0, animate == true)
end

------------------------------------------------------------------ renderer
local Renderer = {}
Renderer.__index = Renderer

-- c: minimap settings; layerOn(key) filters preview layers (nil: all shown).
function Renderer:Paint(c, scale, layerOn, animate, widthOverride, heightOverride)
    scale = tonumber(scale) or 1
    local width = widthOverride or (tonumber(c.size) or 190) * scale
    local height = heightOverride or (c.shape == 3 and width * 2 / 3 or width)
    PaintBackdrop(self, c, scale, width, height, layerOn)
    PaintGlow(self, c, width, height, layerOn)
    local path = ArtPath(c)
    local art = path and (tonumber(c.styleAlpha) or 0) > 0 and Visible(layerOn, "ornament")
    local over = c.stylePlacement ~= 2
    PaintArt(self, self.artUnder, art and not over, path, c, scale, width, height, animate)
    PaintArt(self, self.artOver, art and over, path, c, scale, width, height, animate)
end

function Renderer:Hide()
    self.backdrop:Hide()
    self.glow:Hide()
    self.artUnder:Hide()
    self.artOver:Hide()
    Rotate(self.artUnder, 0, false)
    Rotate(self.artOver, 0, false)
end

function Style.Create(parent, underLevel, overLevel)
    local self = setmetatable({ parent = parent }, Renderer)
    self.under = Surface(parent, underLevel)
    self.over = Surface(parent, overLevel)
    self.backdrop = Texture(self.under, "BACKGROUND", -8)
    self.backdrop:SetPoint("CENTER", parent, "CENTER")
    self.glow = Texture(self.under, "BACKGROUND", -7)
    self.glow:SetTexture(HALO)
    self.glow:SetPoint("CENTER", parent, "CENTER")
    self.glow:SetBlendMode("ADD")
    self.artUnder = Texture(self.under, "ARTWORK", 0)
    self.artUnder:SetPoint("CENTER", parent, "CENTER")
    self.artOver = Texture(self.over, "ARTWORK", 0)
    self.artOver:SetPoint("CENTER", parent, "CENTER")
    return self
end
