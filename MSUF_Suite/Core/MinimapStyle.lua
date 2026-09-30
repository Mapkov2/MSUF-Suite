local _, NS = ...
-- One renderer is used by the live minimap and its options preview. Ornament
-- textures belong to the Suite; Blizzard's map and buttons remain untouched.
local Style = {}
NS.MinimapStyle = Style
local MEDIA = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\"
Style.paths = { false, MEDIA .. "ArcaneRing.tga", MEDIA .. "EmberRing.tga",
    MEDIA .. "AstralRing.tga", MEDIA .. "SteelFrame.tga", false,
    MEDIA .. "AntiqueScrollFrame.tga" }
local HALO, CIRCLE = MEDIA .. "Halo.tga", MEDIA .. "Circle.tga"
local RGB = NS.RGB

-- Shared by the live weather entry and the options preview. WeatherType and
-- Blizzard's weather aura IDs come from upstream/forever WeatherConstantsDocumentation
-- and Blizzard_PetBattleUI/Shared/Blizzard_PetBattleUI.lua respectively. Use the
-- ability's actual icon, as PetBattleWeatherFrame_Update does, not BackgroundArt.
local WEATHER_TYPES = { [0] = "Clear", [1] = "Rain", [2] = "Snow", [3] = "Sandstorm", [4] = "Other weather" }
local WEATHER_BLIZZARD = { [0] = 403, [1] = 229, [2] = 205, [3] = 454 }
local weatherIcons = {}
local WEATHER_ART = "Interface\\AddOns\\MSUF_Suite\\Media\\Weather\\"

function Style.WeatherHeight(c)
    local textSize = c.infoWeatherSize or 12
    if c.infoWeatherDisplay == 1 then return textSize end
    local iconSize = c.infoWeatherIconSize or 24
    return c.infoWeatherDisplay == 2 and iconSize or math.max(textSize, iconSize)
end

-- Keep the plain localized name for tooltips, including in icon-only mode.
-- Unknown values never borrow the clear-weather artwork.
function Style.WeatherContent(c, kind)
    local name = WEATHER_TYPES[kind]
    if not name then return "--", "--" end
    local label = NS.Text(name)
    if c.infoWeatherDisplay == 1 then return label, label end
    local file = "Interface\\Icons\\INV_Misc_QuestionMark"
    if WEATHER_BLIZZARD[kind] then
        file = WEATHER_ART .. name .. ".tga"
        if c.infoWeatherIconStyle ~= 2 then
            local icon = weatherIcons[kind]
            if icon == nil then
                local _, _, texture = C_PetBattles.GetAbilityInfoByID(WEATHER_BLIZZARD[kind])
                icon = NS.Finite(texture) and texture > 0 and texture or false
                weatherIcons[kind] = icon
            end
            -- Missing client artwork keeps the correct Suite weather symbol.
            if icon then file = icon end
        end
    end
    return c.infoWeatherDisplay == 2 and "" or label, label, file
end

-- Weather artwork is a native Texture, never FontString escape markup: the
-- live icon-only field previously displayed the literal |T texture string.
-- Runtime and preview share the same left/center/right content placement.
function Style.LayoutWeather(entry, c, text, scale)
    scale = scale or 1
    local label, icon, button = entry.label, entry.icon, entry.button
    local iconSize = entry.weatherTexture and math.max(1, math.floor((c.infoWeatherIconSize or 24) * scale + .5)) or 0
    local hasText = text ~= ""
    local gap = iconSize > 0 and hasText and 4 * scale or 0
    local available = button:GetWidth()
    -- Measure the full new name before clipping it to the configured field;
    -- a longer weather name must not inherit the previous label's width.
    local measured = label:GetUnboundedStringWidth()
    if not NS.Finite(measured) or measured <= 0 then measured = #text * (c.infoWeatherSize or 12) * scale * .62 end
    local textWidth = hasText and math.min(math.max(1, available - iconSize - gap), measured) or 0
    local width = iconSize + gap + textWidth
    local x = entry.justify == "LEFT" and 0 or entry.justify == "RIGHT" and available - width or (available - width) / 2
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", button, "LEFT", x, 0)
    icon:SetSize(math.max(1, iconSize), math.max(1, iconSize))
    icon:SetShown(iconSize > 0)
    label:ClearAllPoints()
    label:SetPoint("LEFT", button, "LEFT", x + iconSize + gap, 0)
    label:SetSize(math.max(1, textWidth), button:GetHeight())
    label:SetJustifyH("LEFT")
    label:SetShown(hasText)
    entry.contentWidth = width
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
        -- The scroll is asymmetric. Keep its paper opening aligned as the map resizes.
        local scrollX = tonumber(c.styleTexture) == 7 and width * (11 / 190) or 0
        texture:SetPoint("CENTER", self.parent, "CENTER", scrollX + (tonumber(c.styleX) or 0) * scale,
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
