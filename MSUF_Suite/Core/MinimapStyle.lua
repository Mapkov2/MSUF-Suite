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
-- The choice values (Core/Catalog/Minimap.lua) and the catalog defaults that
-- stand in for a setting a partial config lacks.
local WEATHER, ICONS, SHAPE = NS.MinimapWeatherDisplay, NS.MinimapWeatherIcons, NS.MinimapShape
local ART, PLACEMENT, BLEND = NS.MinimapStyleTexture, NS.MinimapStylePlacement, NS.MinimapStyleBlend
local RULES = NS.SuiteCatalog.minimap.rules

-- Native location values are public text only; Custom retains older profiles.
function Style.LocationContent(c, zone, subzone, minimap)
    zone, subzone, minimap = NS.PublicText(zone) or "", NS.PublicText(subzone) or "", NS.PublicText(minimap) or ""
    local source = c.infoLocationSource or 1
    if source == 2 then return zone ~= "" and zone or "--" end
    if source == 3 then return subzone ~= "" and subzone or zone ~= "" and zone or "--" end
    if source == 4 then
        return minimap ~= "" and minimap or subzone ~= "" and subzone or zone ~= "" and zone or "--"
    end
    zone = (source == 5 or c.infoLocationZone) and zone or ""
    subzone = (source == 5 or c.infoLocationSubzone) and subzone or ""
    if subzone == zone then subzone = "" end
    return zone ~= "" and subzone ~= "" and zone .. (c.infoLocationBelow and "\n" or " - ") .. subzone
        or zone ~= "" and zone or subzone ~= "" and subzone or "--"
end

function Style.LocationLines(c)
    local source = c.infoLocationSource or 1
    return c.infoLocationBelow and (source == 5 or source == 1 and c.infoLocationZone and c.infoLocationSubzone) and 2 or 1
end

-- The native queue-eye atlas is a subrectangle, not a whole texture file.
-- Crop inside that rectangle so runtime and preview show the same iris.
function Style.PaintDungeonButton(button, icon, style, scale)
    local modern = style == 2
    local band, inner = rawget(button, "dungeonBand"), rawget(button, "dungeonInner")
    if modern and not band then
        band = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        inner = button:CreateTexture(nil, "BACKGROUND", nil, 2)
        button.dungeonBand, button.dungeonInner = band, inner
        band:SetColorTexture(22 / 255, 25 / 255, 27 / 255, 1)
        inner:SetColorTexture(0, 0, 0, 1)
    end
    if band then
        band:ClearAllPoints()
        band:SetPoint("TOPLEFT", button, "TOPLEFT", 2 * scale, -2 * scale)
        band:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2 * scale, 2 * scale)
        inner:ClearAllPoints()
        inner:SetPoint("TOPLEFT", button, "TOPLEFT", 4 * scale, -4 * scale)
        inner:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4 * scale, 4 * scale)
        band:SetShown(modern)
        inner:SetShown(modern)
    end
    local inset = (modern and 5 or 2) * scale
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    icon:SetAtlas("groupfinder-eye-single")
    local info = C_Texture.GetAtlasInfo("groupfinder-eye-single")
    if not NS.Public(info) or type(info) ~= "table" then return end
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    if not (NS.Finite(l) and NS.Finite(r) and NS.Finite(t) and NS.Finite(b)) then return end
    local x, y = modern and .30 or .16, modern and .36 or .30
    icon:SetTexCoord(l + (r - l) * x, r - (r - l) * x, t + (b - t) * y, b - (b - t) * y)
end

-- Shared by the live weather entry and the options preview. WeatherType and
-- Blizzard's weather auras come from upstream/forever WeatherConstantsDocumentation
-- and Blizzard_PetBattleUI/Shared/Blizzard_PetBattleUI.lua respectively.
local WEATHER_TYPES = { [0] = "Clear", [1] = "Rain", [2] = "Snow", [3] = "Sandstorm", [4] = "Other weather" }
-- BattlePetAbility.IconFileDataID for auras 403, 229, 205 and 454. Use the
-- actual icon assets directly: Forever's GetAbilityInfoByID returns nil for
-- these records. Falling back to Suite art made both styles look identical.
local WEATHER_BLIZZARD = { [0] = 535593, [1] = 132852, [2] = 135857, [3] = 463521 }
local WEATHER_ART = "Interface\\AddOns\\MSUF_Suite\\Media\\Weather\\"

function Style.WeatherHeight(c)
    local textSize = c.infoWeatherSize or RULES.infoWeatherSize.default
    if c.infoWeatherDisplay == WEATHER.TEXT then return textSize end
    local iconSize = c.infoWeatherIconSize or RULES.infoWeatherIconSize.default
    return c.infoWeatherDisplay == WEATHER.ICON and iconSize or math.max(textSize, iconSize)
end

-- Keep the plain localized name for tooltips, including in icon-only mode.
-- Unknown values never borrow the clear-weather artwork.
function Style.WeatherContent(c, kind)
    local name = WEATHER_TYPES[kind]
    if not name then return "--", "--" end
    local label = NS.Text(name)
    if c.infoWeatherDisplay == WEATHER.TEXT then return label, label end
    local file = "Interface\\Icons\\INV_Misc_QuestionMark"
    if WEATHER_BLIZZARD[kind] then
        file = c.infoWeatherIconStyle == ICONS.FOREVER and WEATHER_ART .. name .. ".tga" or WEATHER_BLIZZARD[kind]
    end
    return c.infoWeatherDisplay == WEATHER.ICON and "" or label, label, file
end

-- Weather artwork is a native Texture, never FontString escape markup: the
-- live icon-only field previously displayed the literal |T texture string.
-- Runtime and preview share the same left/center/right content placement.
function Style.LayoutWeather(entry, c, text, scale)
    scale = scale or 1
    local label, icon, button = entry.label, entry.icon, entry.button
    local iconSize = entry.weatherTexture and math.max(1, math.floor((c.infoWeatherIconSize or RULES.infoWeatherIconSize.default) * scale + .5)) or 0
    local hasText = text ~= ""
    local gap = iconSize > 0 and hasText and 4 * scale or 0
    local available = button:GetWidth()
    -- Measure the full new name before clipping it to the configured field;
    -- a longer weather name must not inherit the previous label's width.
    local measured = label:GetUnboundedStringWidth()
    if not NS.Finite(measured) or measured <= 0 then measured = #text * (c.infoWeatherSize or RULES.infoWeatherSize.default) * scale * .62 end
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
        if c.shape == SHAPE.CIRCLE then
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
        local factor = (tonumber(c.styleGlowScale) or RULES.styleGlowScale.default) / 100
        self.glow:SetSize(width * factor, height * factor)
        self.glow:SetVertexColor(r, g, b, alpha)
    end
    self.glow:SetShown(glow)
end

-- The ornament path of the chosen artwork (Custom is a file or ID).
local function ArtPath(c)
    local choice = tonumber(c.styleTexture) or ART.NONE
    if choice == ART.CUSTOM and type(c.styleTexturePath) == "string" and c.styleTexturePath ~= "" then
        return tonumber(c.styleTexturePath) or c.styleTexturePath
    end
    return Style.paths[choice]
end

-- One of the two ornament layers: under or over the map, never both.
local function PaintArt(self, texture, shown, path, c, scale, width, height, animate)
    texture:SetShown(shown)
    if shown then
        Assign(texture, path)
        local factor = (tonumber(c.styleScale) or RULES.styleScale.default) / 100
        texture:SetSize(width * factor, height * factor)
        texture:ClearAllPoints()
        -- The scroll is asymmetric. Keep its paper opening aligned as the map resizes.
        local scrollX = tonumber(c.styleTexture) == ART.PARCHMENT_SCROLL and width * (11 / 190) or 0
        texture:SetPoint("CENTER", self.parent, "CENTER", scrollX + (tonumber(c.styleX) or 0) * scale,
            (tonumber(c.styleY) or 0) * scale)
        local r, g, b = RGB(c.styleColor)
        texture:SetVertexColor(r, g, b, (tonumber(c.styleAlpha) or 0) / 100)
        texture:SetBlendMode(c.styleBlend == BLEND.ADDITIVE and "ADD" or "BLEND")
    end
    Rotate(texture, shown and (tonumber(c.styleRotation) or 0) or 0, animate == true)
end

------------------------------------------------------------------ renderer
local Renderer = {}
Renderer.__index = Renderer

local function IconLook(c)
    if not c.iconSkin or c.iconSkin == "CUSTOM" then return nil end
    return NS.HostBridge.IconSkinLook(c.iconSkin, c.shape == SHAPE.CIRCLE and "CIRCLE" or "RECTANGLE")
end

function Renderer:IconSkinChanged(c)
    return self.iconLook ~= IconLook(c)
end

-- Only the cold style/geometry path paints the shared host material. The map
-- keeps its native terrain, mask, player arrow and interactive children.
function Renderer:PaintIconSkin(c, width, height, anchor, shown)
    local look = IconLook(c)
    self.iconLook = look
    local paint = shown and look or nil
    if paint and not self.iconSurface then
        self.iconSurface = Surface(self.parent, self.over:GetFrameLevel() - 1)
    end
    if not self.iconSurface then return look ~= nil, 0 end
    if self.iconPaintLook ~= paint or self.iconWidth ~= width or self.iconHeight ~= height
        or self.iconAnchor ~= anchor then
        if self.iconAnchor ~= anchor then self.iconSurface:SetAllPoints(anchor) end
        NS.HostBridge.PaintIconSkin(self.iconSurface, paint, width, height, anchor)
        self.iconPaintLook, self.iconWidth, self.iconHeight, self.iconAnchor = paint, width, height, anchor
    end
    if self.iconShown ~= (paint ~= nil) then
        self.iconShown = paint ~= nil
        self.iconSurface:SetShown(self.iconShown)
    end
    local x, y = NS.HostBridge.IconSkinOutset(look, width, height)
    return look ~= nil, math.max(x or 0, y or 0)
end

-- c: minimap settings; layerOn(key) filters preview layers (nil: all shown).
function Renderer:Paint(c, scale, layerOn, animate, widthOverride, heightOverride)
    scale = tonumber(scale) or 1
    local width = widthOverride or (tonumber(c.size) or RULES.size.default) * scale
    local height = heightOverride or (c.shape == SHAPE.WIDE and width * 2 / 3 or width)
    PaintBackdrop(self, c, scale, width, height, layerOn)
    PaintGlow(self, c, width, height, layerOn)
    local path = ArtPath(c)
    local art = path and (tonumber(c.styleAlpha) or 0) > 0 and Visible(layerOn, "ornament")
    local over = c.stylePlacement ~= PLACEMENT.BEHIND
    PaintArt(self, self.artUnder, art and not over, path, c, scale, width, height, animate)
    PaintArt(self, self.artOver, art and over, path, c, scale, width, height, animate)
end

function Renderer:Hide()
    if self.iconSurface then
        if self.iconPaintLook then NS.HostBridge.PaintIconSkin(self.iconSurface, nil) end
        self.iconSurface:Hide()
        self.iconLook, self.iconPaintLook, self.iconShown = nil, nil, false
        self.iconWidth, self.iconHeight, self.iconAnchor = nil, nil, nil
    end
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
