local _, NS = ...
-- One renderer is used by the live minimap and its options preview. Ornament
-- textures belong to the Suite; Blizzard's map and buttons remain untouched.
local Style = {}
NS.MinimapStyle = Style
local MEDIA = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\"
local SUITE_MEDIA = "Interface\\AddOns\\MSUF_Suite\\Media\\"
local HALO, CIRCLE = MEDIA .. "Halo.tga", MEDIA .. "Circle.tga"
local RGB = NS.RGB
-- The choice values (Core/Catalog/Minimap.lua) and the catalog defaults that
-- stand in for a setting a partial config lacks.
local WEATHER, ICONS, SHAPE = NS.MinimapWeatherDisplay, NS.MinimapWeatherIcons, NS.MinimapShape
local DATE = NS.MinimapDatePosition
local ART, PLACEMENT, BLEND = NS.MinimapStyleTexture, NS.MinimapStylePlacement, NS.MinimapStyleBlend
local DRAWER = NS.MinimapDrawerStyle
local RULES = NS.SuiteCatalog.minimap.rules
Style.paths = {
    [ART.ARCANE_RING] = MEDIA .. "ArcaneRing.tga",
    [ART.EMBER_RING] = MEDIA .. "EmberRing.tga",
    [ART.ASTRAL_RING] = MEDIA .. "AstralRing.tga",
    [ART.STEEL_FRAME] = MEDIA .. "SteelFrame.tga",
    [ART.PARCHMENT_SCROLL] = MEDIA .. "AntiqueScrollFrame.tga",
    [ART.WAYFARER] = SUITE_MEDIA .. "WayfarerMinimapFrame.tga",
    [ART.ANTIQUE_MAP_FRAME] = MEDIA .. "AntiqueMapFrame.tga",
}
-- The menu thumbnails use the same files as the live minimap and preview.
RULES.styleTexture.choiceIcons = Style.paths
local DRAWER_TEXTURES = {
    [DRAWER.FOREVER] = SUITE_MEDIA .. "SuiteIconForever.tga",
    [DRAWER.MODERN] = SUITE_MEDIA .. "SuiteIconModern.tga",
    [DRAWER.DARK] = SUITE_MEDIA .. "SuiteIconDark.tga",
}
local DRAWER_PRESETS = {
    [7] = DRAWER.FOREVER, [8] = DRAWER.MODERN, [9] = DRAWER.DARK,
    [10] = DRAWER.FOREVER, [11] = DRAWER.MODERN, [12] = DRAWER.MODERN,
}
local GLOBAL_PRESETS = NS.SuiteCatalog.minimap.look.global
local DEFAULT_DRAWER = NS.Client.isForever and DRAWER.FOREVER or DRAWER.MODERN

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

function Style.ClockLines(c)
    return c.infoClockDate and c.infoClockDatePosition ~= DATE.BESIDE and 2 or 1
end

function Style.ClockContent(c, timeText, today)
    if not c.infoClockDate then return timeText or "--" end
    today = today or date("*t")
    local dateText = FormatShortDate(today.day, today.month, today.year)
    if not timeText then return dateText end
    if c.infoClockDatePosition == DATE.ABOVE then return dateText .. "\n" .. timeText end
    return timeText .. (c.infoClockDatePosition == DATE.BELOW and "\n" or "  ") .. dateText
end

local function PlaceClockRow(label, button, justify, width, height, offset)
    label:ClearAllPoints()
    label:SetPoint(justify, button, justify, 0, offset)
    label:SetSize(width, height)
    label:SetJustifyH(justify)
end

function Style.LayoutClock(entry, c, width, justify, scale)
    local size = c.infoClockSize * scale
    local twoRows = Style.ClockLines(c) == 2
    local offset, height = twoRows and size / 2 or 0, size + 8 * scale
    PlaceClockRow(entry.label, entry.button, justify, width, height, offset)
    if twoRows then PlaceClockRow(entry.clockSecond, entry.button, justify, width, height, -offset) end
end

-- Each row is an independent single-line field so clipping cannot remove the other row.
function Style.SetClockText(entry, text)
    local split = text:find("\n", 1, true)
    entry.label:SetText(split and text:sub(1, split - 1) or text)
    if split then entry.clockSecond:SetText(text:sub(split + 1)) end
    entry.clockSecond:SetShown(split ~= nil)
end

function Style.InfoTextWidth(entry)
    local width = entry.label:GetStringWidth()
    if not NS.Finite(width) then width = 0 end
    if entry.clockSecond and entry.clockSecond:IsShown() then
        local second = entry.clockSecond:GetStringWidth()
        if NS.Finite(second) then width = math.max(width, second) end
    end
    return width
end

-- A readable minus even when Blizzard's current zoom atlas is desaturated.
function Style.CreateZoomOutGlyph(parent)
    local backing = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    backing:SetPoint("CENTER", parent, "CENTER")
    backing:SetColorTexture(0.035, 0.05, 0.065, 0.94)
    local line = parent:CreateTexture(nil, "OVERLAY", nil, 2)
    line:SetPoint("CENTER", parent, "CENTER")
    return { backing = backing, line = line }
end

function Style.PaintZoomOutGlyph(glyph, scale, enabled)
    glyph.backing:SetSize(math.max(6, 13 * scale), math.max(3, 6 * scale))
    glyph.line:SetSize(math.max(4, 9 * scale), math.max(1, 2 * scale))
    if enabled then
        glyph.line:SetColorTexture(1.0, 0.81, 0.41, 1)
    else
        glyph.line:SetColorTexture(0.73, 0.76, 0.80, 1)
    end
end

-- The group finder symbol stands square in the button's middle: a white Suite
-- glyph tinted by the caller (tools/build_group_finder_symbols.py), or
-- Blizzard's eye. Its static "groupfinder-eye-single" atlas has no art on WoW
-- Forever (a green square), so the eye is the first frame of the searching
-- flipbook both clients animate (Blizzard_LFGUtil LFGEye.xml: 8 rows, 11 columns).
local SYMBOL = NS.MinimapGroupFinderSymbol
local GLYPHS = {
    [SYMBOL.EYE] = SUITE_MEDIA .. "GroupFinder\\Eye", [SYMBOL.SEARCH] = SUITE_MEDIA .. "GroupFinder\\Search",
    [SYMBOL.GROUP] = SUITE_MEDIA .. "GroupFinder\\Group", [SYMBOL.DUNGEON] = SUITE_MEDIA .. "GroupFinder\\Dungeon",
}
-- After SetAtlas the client reads texture coordinates inside the atlas, not
-- the file (seen on WoW Forever), so the frame is cut from the atlas' own file
-- in file coordinates; without that file, the cut is relative to the atlas.
local EYE_FLIPBOOK, EYE_COLUMNS, EYE_ROWS = "groupfinder-eye-flipbook-searching", 11, 8
local function PaintBlizzardEye(icon)
    local info = C_Texture.GetAtlasInfo(EYE_FLIPBOOK)
    info = NS.Public(info) and type(info) == "table" and info or nil
    local file = info and (info.file or info.filename)
    local l, r, t, b
    if info then l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord end
    if (type(file) == "number" or type(file) == "string") and NS.Finite(l) and NS.Finite(r) and NS.Finite(t)
        and NS.Finite(b) then
        icon:SetTexture(file)
        icon:SetTexCoord(l, l + (r - l) / EYE_COLUMNS, t, t + (b - t) / EYE_ROWS)
        return
    end
    icon:SetAtlas(EYE_FLIPBOOK)
    icon:SetTexCoord(0, 1 / EYE_COLUMNS, 0, 1 / EYE_ROWS)
end

-- The symbol's colour: Automatic takes the accent of the map's look preset,
-- else of the profile's Suite look, and keeps Blizzard's eye in its own
-- colours (nil). "class" asks the caller for the player's class colour.
local ACCENT, TINT = NS.MinimapLookAccent, NS.MinimapGroupFinderTint
function Style.GroupFinderTint(config)
    local mode = config.dungeonIconTint
    if mode == TINT.CLASS then return "class" end
    if mode == TINT.CUSTOM then return config.dungeonIconColor end
    if config.dungeonIcon == SYMBOL.BLIZZARD then return nil end
    local db = NS.DB and NS.DB.suite
    local look = db and NS.SuiteLooks.indexes[db.globalLook]
    return ACCENT[config.stylePreset] or ACCENT[GLOBAL_PRESETS[look]] or ACCENT[11]
end

-- Modern Dark sets the symbol on a round dark badge whose ring takes the
-- symbol's colour; Default shows it bare. A tinted Blizzard eye is
-- desaturated first. A glyph the client has not loaded yet (a new file needs
-- a game restart) falls back to Blizzard's eye. Never a box: returns false,
-- so callers hide their rectangular plates.
function Style.PaintDungeonButton(button, icon, style, scale, symbol, width, height, r, g, b)
    local side = math.max(1, math.min(width or 26, height or 26))
    local badge = style == 2
    local ring, disc = rawget(button, "dungeonRing"), rawget(button, "dungeonDisc")
    if badge and not ring then
        ring = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        disc = button:CreateTexture(nil, "BACKGROUND", nil, 2)
        ring:SetTexture(MEDIA .. "Circle.tga")
        disc:SetTexture(MEDIA .. "Circle.tga")
        disc:SetVertexColor(0.05, 0.06, 0.08, 0.92)
        ring:SetPoint("CENTER", button, "CENTER")
        disc:SetPoint("CENTER", button, "CENTER")
        button.dungeonRing, button.dungeonDisc = ring, disc
    end
    if ring then
        if r then ring:SetVertexColor(r, g, b, 0.75) else ring:SetVertexColor(0.30, 0.34, 0.39, 0.95) end
        ring:SetSize(side, side)
        disc:SetSize(math.max(1, side - 2 * scale), math.max(1, side - 2 * scale))
        ring:SetShown(badge)
        disc:SetShown(badge)
    end
    local size = badge and side * .62 or side
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", button, "CENTER")
    icon:SetSize(size, size)
    local glyph = symbol ~= SYMBOL.BLIZZARD and (GLYPHS[symbol] or GLYPHS[SYMBOL.EYE])
    if glyph and icon:SetTexture(glyph) ~= false then
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetDesaturation(0)
    else
        PaintBlizzardEye(icon)
        icon:SetDesaturation(r and 1 or 0)
    end
    icon:SetVertexColor(r or 1, g or 1, b or 1, 1)
    return false
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
    texture:SetTexCoord(0, 1, 0, 1)
end

-- Automatic uses a matching minimap preset, then the profile's Suite look.
local function AutomaticDrawer(config)
    local db = NS.DB and NS.DB.suite
    local look = db and NS.SuiteLooks.indexes[db.globalLook]
    return DRAWER_PRESETS[config.stylePreset] or DRAWER_PRESETS[GLOBAL_PRESETS[look]] or DEFAULT_DRAWER
end
function Style.PaintDrawerToggle(icon, config, highlight)
    local path = DRAWER_TEXTURES[config.drawerStyle] or DRAWER_TEXTURES[AutomaticDrawer(config)]
    Assign(icon, path)
    if highlight then Assign(highlight, path) end
end
-- The group finder button's Automatic style follows the same look: the dark
-- band for the modern and dark palettes, the plain button for Forever's gold.
local FINDER = NS.MinimapGroupFinderStyle
function Style.GroupFinderStyle(config)
    local style = config.dungeonStyle
    if style ~= FINDER.AUTO then return style end
    return AutomaticDrawer(config) == DRAWER.FOREVER and FINDER.DEFAULT or FINDER.MODERN_DARK
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
    if choice == ART.BLIZZARD then return "ui-hud-minimap-frame" end
    if choice == ART.CUSTOM and type(c.styleTexturePath) == "string" and c.styleTexturePath ~= "" then
        return tonumber(c.styleTexturePath) or c.styleTexturePath
    end
    return Style.paths[choice]
end

-- One of the two ornament layers: under or over the map, never both.
local function PaintArt(self, texture, shown, path, c, scale, width, height, animate)
    texture:SetShown(shown)
    if shown then
        local native = tonumber(c.styleTexture) == ART.BLIZZARD
        if native then
            -- Blizzard_Minimap/Mainline/Minimap.xml: the 215 x 226 compass
            -- frame surrounds a 198 x 198 terrain disc. Paint on our texture.
            texture:SetAtlas(path)
            texture._msufStyleTexture = nil
        else
            Assign(texture, path)
        end
        local factor = (tonumber(c.styleScale) or RULES.styleScale.default) / 100
        texture:SetSize(width * factor * (native and 215 / 198 or 1),
            height * factor * (native and 226 / 198 or 1))
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
    local round = c.shape == SHAPE.CIRCLE
    return NS.HostBridge.IconSkinLook(c.iconSkin, round and "CIRCLE" or "RECTANGLE", nil, round)
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
