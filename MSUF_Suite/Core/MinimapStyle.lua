local _, NS = ...
-- One renderer is used by the live minimap and its options preview. Ornament
-- textures belong to the Suite; Blizzard's map and buttons remain untouched.
local Style = {}
NS.MinimapStyle = Style
local MEDIA = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\"
Style.paths = { false, MEDIA .. "ArcaneRing.tga", MEDIA .. "EmberRing.tga",
    MEDIA .. "AstralRing.tga", MEDIA .. "SteelFrame.tga" }
local HALO, CIRCLE = MEDIA .. "Halo.tga", MEDIA .. "Circle.tga"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function RGB(hex)
    if type(hex) ~= "string" or #hex ~= 6 then return 1, 1, 1 end
    return (tonumber(hex:sub(1, 2), 16) or 255) / 255,
        (tonumber(hex:sub(3, 4), 16) or 255) / 255,
        (tonumber(hex:sub(5, 6), 16) or 255) / 255
end
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
local function Stored(widget, key)
    if type(widget) == "table" then return rawget(widget, key) end
    return widget[key]
end
local function Rotate(texture, speed, animate)
    local group = Stored(texture, "_msufStyleRotation")
    if not animate or speed == 0 then
        if group then group:Stop() end
        if texture.SetRotation then texture:SetRotation(0) end
        return
    end
    if not group and type(texture.CreateAnimationGroup) == "function" then
        group = texture:CreateAnimationGroup()
        if group and type(group.CreateAnimation) == "function" then
            local animation = group:CreateAnimation("Rotation")
            if animation then
                animation:SetOrigin("CENTER", 0, 0)
                group:SetLooping("REPEAT")
                texture._msufStyleRotation = group
                texture._msufStyleRotationAnimation = animation
            end
        end
    end
    local rotation = Stored(texture, "_msufStyleRotationAnimation")
    if not group or not rotation then return end
    local direction = speed > 0 and -360 or 360
    local duration = 360 / math.abs(speed)
    if Stored(texture, "_msufStyleRotationSpeed") ~= speed then
        group:Stop()
        rotation:SetDegrees(direction)
        rotation:SetDuration(duration)
        texture._msufStyleRotationSpeed = speed
    end
    if not group:IsPlaying() then group:Play() end
end
local function Assign(texture, path)
    if Stored(texture, "_msufStyleTexture") == path then return end
    texture._msufStyleTexture = path
    texture:SetTexture(path)
end

function Style.Create(parent, underLevel, overLevel)
    local self = {}
    self.parent = parent
    self.under = Surface(parent, underLevel)
    self.over = Surface(parent, overLevel)
    self.backdrop = Texture(self.under, "BACKGROUND", -8)
    self.backdrop:SetPoint("CENTER", parent, "CENTER")
    self.glow = Texture(self.under, "BACKGROUND", -7)
    self.glow:SetTexture(HALO)
    self.glow:SetPoint("CENTER", parent, "CENTER")
    if self.glow.SetBlendMode then self.glow:SetBlendMode("ADD") end
    self.artUnder = Texture(self.under, "ARTWORK", 0)
    self.artUnder:SetPoint("CENTER", parent, "CENTER")
    self.artOver = Texture(self.over, "ARTWORK", 0)
    self.artOver:SetPoint("CENTER", parent, "CENTER")

    function self:Paint(c, scale, layerOn, animate, widthOverride, heightOverride)
        scale = tonumber(scale) or 1
        local width = widthOverride or (tonumber(c.size) or 190) * scale
        local height = heightOverride or (c.shape == 3 and width * 2 / 3 or width)
        local function Visible(key) return not layerOn or layerOn(key) end

        local plate = c.styleBackdrop == true and (tonumber(c.styleBackdropAlpha) or 0) > 0 and Visible("backdrop")
        if plate then
            local pad = (tonumber(c.styleBackdropPadding) or 0) * scale
            local r, g, b = RGB(c.styleBackdropColor)
            if c.shape == 2 then
                Assign(self.backdrop, CIRCLE)
                self.backdrop:SetVertexColor(r, g, b, (tonumber(c.styleBackdropAlpha) or 0) / 100)
            else
                self.backdrop._msufStyleTexture = nil
                self.backdrop:SetColorTexture(r, g, b, (tonumber(c.styleBackdropAlpha) or 0) / 100)
            end
            self.backdrop:SetSize(width + pad * 2, height + pad * 2)
        end
        self.backdrop:SetShown(plate)

        local glow = c.styleGlow == true and (tonumber(c.styleGlowAlpha) or 0) > 0 and Visible("glow")
        if glow then
            local r, g, b = RGB(c.styleGlowColor)
            local factor = (tonumber(c.styleGlowScale) or 145) / 100
            self.glow:SetSize(width * factor, height * factor)
            self.glow:SetVertexColor(r, g, b, (tonumber(c.styleGlowAlpha) or 0) / 100)
        end
        self.glow:SetShown(glow)

        local choice = tonumber(c.styleTexture) or 1
        local path = Style.paths[choice]
        if choice == 6 and type(c.styleTexturePath) == "string" and c.styleTexturePath ~= "" then
            path = tonumber(c.styleTexturePath) or c.styleTexturePath
        end
        local art = path and (tonumber(c.styleAlpha) or 0) > 0 and Visible("ornament")
        local over = c.stylePlacement ~= 2
        for _, texture in ipairs({ self.artUnder, self.artOver }) do
            local shown = art and (texture == self.artOver) == over
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
                if texture.SetBlendMode then texture:SetBlendMode(c.styleBlend == 2 and "ADD" or "BLEND") end
            end
            Rotate(texture, shown and (tonumber(c.styleRotation) or 0) or 0, animate == true)
        end
    end

    function self:Hide()
        self.backdrop:Hide()
        self.glow:Hide()
        self.artUnder:Hide()
        self.artOver:Hide()
        Rotate(self.artUnder, 0, false)
        Rotate(self.artOver, 0, false)
    end
    return self
end
