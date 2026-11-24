local _, P = ...
-- Minimap page preview, the drawing: the element tables, the samples and the
-- mirrored native art, and the painters of texts, icons, artwork edges and
-- map controls. MinimapPreview.lua builds the selectable canvas on top.
local Suite, S, Tr = P.Suite, P.S, P.Tr
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ANCHORS = Suite.AnchorPoints
local ROWS = Suite.MinimapRowGeometry
local OUTLINES = { "", "OUTLINE", "THICKOUTLINE", "MONOCHROME,OUTLINE" }
-- The choice values (Core/Catalog/Minimap.lua) and the catalog defaults that
-- stand in for a setting a partial config lacks.
local TEXT_ANCHOR, WEATHER, BOX = Suite.MinimapTextAnchor, Suite.MinimapWeatherDisplay, Suite.MinimapTextBox
local MinimapStyle = Suite.MinimapStyle
local LANDING, LANDING_ICON, ZOOM = Suite.MinimapLanding, Suite.MinimapLandingIcon, Suite.MinimapZoomButtons
local ROTATE = Suite.MinimapRotate
local RULES = P.catalog.minimap.rules
local Native = Suite.MinimapElements
local Data = {}
P.MinimapPreviewData = Data
local TEXTS, ICONS, ICON_KEYS, LAYERS

-- { name, sample text, key } of every info text.
function Data.Texts()
    if TEXTS then return TEXTS end
    TEXTS = {
        { "Clock", "12:34", "clock" }, { "FPS", "60 FPS", "fps" }, { "Latency", "23 ms", "latency" },
        { "Coordinates", "42.1, 56.7", "coordinates" }, { "Durability", "100%", "durability" },
        { "Location", "Current zone", "location" }, { "Weather", "Clear", "weather" },
        { "Difficulty", "5H", "difficulty" }, { "CalendarDay", "12", "calendarDay" },
    }
    return TEXTS
end
-- { key, label, section, visibility setting (false: native state), layer, atlas, file }
function Data.Icons()
    if ICONS then return ICONS end
    ICONS = {
        { "dungeon", "Group finder", "dungeon", "dungeonButton", "blizzard", "groupfinder-eye-single" },
        { "queueStatus", "Queue status", "elements", "queueStatusEnabled", "blizzard", "groupfinder-eye-single", nil, "QueueStatus" },
        { "tracking", "Tracking", "elements", "showTracking", "blizzard", "ui-hud-minimap-tracking-up", "Interface\\Minimap\\Tracking\\None" },
        { "calendar", "Calendar", "elements", "showCalendar", "blizzard", "ui-hud-minimap-calendar-up", "Interface\\Calendar\\UI-Calendar-Button" },
        { "mail", "Mail", "elements", "showMail", "blizzard", "ui-hud-minimap-mail-up", "Interface\\Minimap\\Tracking\\Mailbox" },
        { "crafting", "Crafting", "elements", "showCrafting", "blizzard", "UI-HUD-Minimap-CraftingOrder-Up", "Interface\\Icons\\INV_Hammer_20" },
        { "compartment", "Compartment", "elements", "showCompartment", "blizzard", "ui-hud-minimap-button", "Interface\\Buttons\\UI-OptionsButton" },
        { "externalEvent", "External event", "elements", false, "blizzard", nil, "Interface\\Icons\\Spell_nature_timestop", "ExternalEvent" },
        { "difficulty", "Difficulty", "elements", "showDifficulty", "blizzard", nil, "Interface\\GroupFrame\\UI-Group-LeaderIcon" },
        { "folio", "Omnium Folio", "landing", "showLanding", "folio", "GarrLanding-MinimapIcon-Alliance-Up", "Interface\\Icons\\INV_Misc_Book_09" },
        { "drawer", "Addon drawer", "addons", "collectButtons", "addons" },
    }
    if not Suite.Client.isForever then
        ICONS[#ICONS + 1] = { "specialization", "Minimap specialization menu", "specialization", "specButton",
            "specialization", nil, "Interface\\Icons\\INV_Misc_QuestionMark" }
    end
    ICON_KEYS = {}
    for _, spec in ipairs(ICONS) do ICON_KEYS[spec[1]] = true end
    return ICONS
end
function Data.Layers()
    if LAYERS then return LAYERS end
    LAYERS = {
        { "map", "Map" }, { "border", "Border" }, { "ornament", "Artwork" }, { "glow", "Glow" },
        { "backdrop", "Plate" }, { "shadow", "Shadow" },
        { "text", "Texts" }, { "blizzard", "Blizzard" }, { "folio", "Folio" },
        { "addons", "Addons" }, { "player", "Player arrow" },
        { "clock", "Clock" }, { "fps", "FPS" }, { "latency", "Latency" },
        { "coordinates", "Coordinates" }, { "durability", "Durability" }, { "location", "Location" },
        { "weather", "Weather" }, { "difficultyText", "Difficulty text" },
        { "calendarDay", "Calendar day" }, { "dungeon", "Group finder" },
        { "queueStatus", "Queue status" },
        { "tracking", "Tracking" }, { "calendar", "Calendar" }, { "mail", "Mail" },
        { "crafting", "Crafting" }, { "compartment", "Compartment" }, { "externalEvent", "External event" }, { "difficulty", "Difficulty" },
        { "zoom", "Zoom buttons" }, { "compass", "Compass" },
        { "guides", "Guides" }, { "hidden", "Hidden" },
    }
    local colors = {
        map = { 0.30, 0.66, 1.00 }, border = { 0.85, 0.70, 0.25 }, ornament = { 0.90, 0.42, 1.00 },
        glow = { 0.20, 0.90, 0.85 }, backdrop = { 0.80, 0.55, 0.25 }, shadow = { 0.48, 0.56, 0.72 },
        text = { 0.70, 0.90, 1.00 }, blizzard = { 0.95, 0.72, 0.18 }, folio = { 0.90, 0.42, 1.00 },
        addons = { 0.30, 0.78, 0.55 }, specialization = { 0.30, 0.78, 0.55 },
        player = { 0.95, 0.72, 0.18 }, guides = { 0.42, 0.72, 1.00 }, hidden = { 0.48, 0.56, 0.72 },
    }
    for _, entry in ipairs(LAYERS) do
        local key = entry[1]
        entry[3] = colors[key] or (key == "zoom" or key == "compass") and colors.blizzard or colors.text
    end
    if not Suite.Client.isForever then
        table.insert(LAYERS, #LAYERS - 1, { "specialization", "Specialization", colors.specialization })
    end
    return LAYERS
end
local ORNAMENT_EDGES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }

local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end
-- Secret-safe readers from MSUF_Suite (always loaded, also without the runtime).
local Public, PublicNumber = Suite.Public, Suite.Number
local function Tint(texture, r, g, b, a) texture:SetColorTexture(r, g, b, a) end
local PlayerClassColor = P.MinimapPlayerClassRGB

------------------------------------------------------------------ samples and native art
local function Sample(name, config)
    if name == "Weather" then
        return Suite.MinimapStyle.WeatherContent(config, 0)
    end
    if name == "Clock" then
        local hour, minute = GetGameTime()
        local time = PublicNumber(hour) and PublicNumber(minute) and string.format("%02d:%02d", hour, minute) or "12:34"
        return MinimapStyle.ClockContent(config, time)
    end
    if name == "Location" then
        local text = Suite.MinimapStyle.LocationContent(config, GetZoneText(), GetSubZoneText(), GetMinimapZoneText())
        return text ~= "--" and text or Suite.Text("Current zone")
    end
    if name == "Durability" then
        return (config.infoDurabilityIcon and "|TInterface\\Durability\\UI-Durability-Icons:12:10|t " or "") .. "100%"
    end
    -- The live texts' formats (Minimap/Info.lua), in the reader's language.
    if name == "FPS" then return Tr("%d FPS"):format(60) end
    if name == "Latency" then return Tr("%d ms"):format(23) end
    for _, spec in ipairs(TEXTS) do
        if spec[1] == name then return spec[2] end
    end
    return name
end

-- GetAtlasInfo returns nil for an atlas this client does not have.
local function SetIcon(texture, atlas, path)
    if atlas then
        local info = C_Texture.GetAtlasInfo(atlas)
        if Public(info) and info then
            texture:SetAtlas(atlas)
            return
        end
    end
    texture:SetTexture(path or WHITE)
end

local function EffectiveScale(region)
    local scale = region:GetEffectiveScale()
    return PublicNumber(scale) and scale > 0 and scale or 1
end

-- Centers are reported in each region's own effective coordinate space.
local function PlaceRegion(target, source, frame, scale, ratio)
    local fx, fy = frame:GetCenter()
    local sx, sy = source:GetCenter()
    local x = PublicNumber(fx) and PublicNumber(sx) and (sx * ratio - fx) * scale or 0
    local y = PublicNumber(fy) and PublicNumber(sy) and (sy * ratio - fy) * scale or 0
    target:ClearAllPoints()
    target:SetPoint("CENTER", target:GetParent(), "CENTER", x, y)
end

local function RegionShown(region)
    if not region or Suite.Safety.IsForbidden(region) then return false end
    local shown = region:IsShown()
    return Public(shown) and shown == true
end

local function CopyArtwork(target, source)
    local atlas = source:GetAtlas()
    if Public(atlas) and type(atlas) == "string" and atlas ~= "" then
        target:SetAtlas(atlas)
    else
        local file = source:GetTexture()
        if not Public(file) or type(file) ~= "string" and type(file) ~= "number" then return false end
        target:SetTexture(file)
        target:SetTexCoord(0, 1, 0, 1)
    end
    -- GetTexCoord always returns four (x, y) pairs, even for an uncropped atlas.
    local ulx, uly, llx, lly, urx, ury, lrx, lry = source:GetTexCoord()
    if PublicNumber(ulx) and PublicNumber(uly) and PublicNumber(llx) and PublicNumber(lly)
        and PublicNumber(urx) and PublicNumber(ury) and PublicNumber(lrx) and PublicNumber(lry) then
        target:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
    end
    local r, g, b, a = source:GetVertexColor()
    if PublicNumber(r) and PublicNumber(g) and PublicNumber(b) and Public(a) then
        target:SetVertexColor(r, g, b, type(a) == "number" and a or 1)
    else
        target:SetVertexColor(1, 1, 1, 1)
    end
    local alpha = source:GetAlpha()
    target:SetAlpha(PublicNumber(alpha) and alpha or 1)
    local desaturation = source:GetDesaturation()
    target:SetDesaturation(PublicNumber(desaturation) and desaturation or 0)
    return true
end

local function CopyNativeTexture(target, source, frame, scale)
    if RegionShown(source) then
        local width, height = source:GetSize()
        if PublicNumber(width) and PublicNumber(height) and width > 0 and height > 0 and CopyArtwork(target, source) then
            local ratio = EffectiveScale(source) / EffectiveScale(frame)
            target:SetSize(width * ratio * scale, height * ratio * scale)
            PlaceRegion(target, source, frame, scale, ratio)
            target:Show()
            return true
        end
    end
    target:Hide()
    return false
end

local function CopyNativeText(target, source, frame, scale)
    if not RegionShown(source) then
        target:Hide()
        return
    end
    local text = Suite.PublicText(source:GetText())
    if not text then
        target:Hide()
        return
    end
    local ratio = EffectiveScale(source) / EffectiveScale(frame)
    local font, size, flags = source:GetFont()
    if Public(font) and PublicNumber(size) and Public(flags) and type(font) == "string" then
        target:SetFont(font, math.max(1, size * ratio * scale), flags)
    end
    target:SetText(text)
    local r, g, b, a = source:GetTextColor()
    if PublicNumber(r) and PublicNumber(g) and PublicNumber(b) and Public(a) then
        target:SetTextColor(r, g, b, type(a) == "number" and a or 1)
    end
    PlaceRegion(target, source, frame, scale, ratio)
    target:Show()
end

local function RowPosition(button, map, rowIndex, index, config, scale, prefix)
    local row = ROWS[rowIndex] or ROWS[1]
    local distance = ((config.elementDistance or 0) + (config.borderSize or 0)) * scale
    local step = ((config.elementSize or RULES.elementSize.default) + (config.elementSpacing or 0)) * scale
    local x = prefix and config[prefix .. "X"] or 0
    local y = prefix and config[prefix .. "Y"] or 0
    button:ClearAllPoints()
    button:SetPoint(row[1], map, row[2],
        row[3] * distance + row[5] * index * step + (x or 0) * scale,
        row[4] * distance + row[6] * index * step + (y or 0) * scale)
end

-- The anchors Above and Below sit outside the map; returns the text justify.
local function TextPosition(button, map, anchor, x, y, scale, border)
    button:ClearAllPoints()
    if anchor == TEXT_ANCHOR.ABOVE then
        button:SetPoint("BOTTOM", map, "TOP", x * scale, y * scale + border)
        return "CENTER"
    end
    if anchor == TEXT_ANCHOR.BELOW then
        button:SetPoint("TOP", map, "BOTTOM", x * scale, y * scale - border)
        return "CENTER"
    end
    local point = ANCHORS[anchor] or "CENTER"
    button:SetPoint(point, map, point, x * scale, y * scale)
    return point:find("LEFT", 1, true) and "LEFT" or point:find("RIGHT", 1, true) and "RIGHT" or "CENTER"
end

------------------------------------------------------------------ offsets
-- Setting prefix of a preview element's X/Y offsets (nil: not movable).
local function OffsetPrefix(key)
    if not key or key == "externalEvent" then return nil end
    if key:find("^info") then return key end
    if key == "folio" then return "landing" end
    if key == "dungeon" or key == "queueStatus" then return key end
    if key == "specialization" then return "spec" end
    if key == "difficulty" then return "difficultyButton" end
    if key == "drawer" or key == "zoomIn" or key == "zoomOut" or key == "zoomGroup" then return key end
    if key == "ornament" or key:find("^ornament_") then return "style" end
    if ICON_KEYS[key] then return "button" .. key:sub(1, 1):upper() .. key:sub(2) end
end

local function OffsetKeys(key)
    if key == "map" then return "x", "y" end
    local prefix = OffsetPrefix(key)
    if prefix then return prefix .. "X", prefix .. "Y" end
end

------------------------------------------------------------------ painting
-- The difficulty sample ("5H") is heroic, the second tier of the live text's colours.
local SAMPLE_DIFFICULTY_TIER = 2
local function TextColor(config, name, prefix)
    if name == "Difficulty" and config.infoDifficultyColors then
        return Suite.MinimapDifficultyColors[SAMPLE_DIFFICULTY_TIER]
    end
    return config[prefix .. "Color"] or "ffffff"
end

local function TextContent(config, name, prefix)
    local wanted = config[prefix] == true
    if wanted and S.MinimapInfoPreviewSource then
        local shown, text, color, texture, invite = S.MinimapInfoPreviewSource(name)
        if shown == true and text then return shown, text, color, texture, invite end
        if shown == false then wanted = false end
    end
    return wanted
end

local function TextHeight(config, name, size)
    if name == "Weather" then return Suite.MinimapStyle.WeatherHeight(config) end
    if name == "Location" then return size * Suite.MinimapStyle.LocationLines(config) end
    if name == "Clock" then return size * MinimapStyle.ClockLines(config) end
    return size
end

local function PlaceTextDecorations(item, justify, size, width, scale, invite)
    local box = item.box
    local x = justify == "LEFT" and -4 or justify == "RIGHT" and 4 or 0
    box:ClearAllPoints()
    box:SetPoint(justify, item.button, justify, x * scale, 0)
    box:SetWidth(math.max(size * scale, width + 8 * scale))
    local mark = item.invite
    if not mark then return end
    mark:SetShown(invite == true)
    if not invite then return end
    mark:SetSize(size * scale, size * scale)
    mark:ClearAllPoints()
    if justify == "RIGHT" then
        mark:SetPoint("RIGHT", item.button, "RIGHT", -width - 2 * scale, 0)
    elseif justify == "LEFT" then
        mark:SetPoint("LEFT", item.button, "LEFT", width + 2 * scale, 0)
    else
        mark:SetPoint("LEFT", item.button, "CENTER", width / 2 + 2 * scale, 0)
    end
end

local function StylePreviewText(label, config, prefix, size, scale)
    local path = Suite.ResolveFont(config[prefix .. "Font"] or "")
    P.StylePreviewFont(label, path, math.max(1, size * scale), OUTLINES[config[prefix .. "Outline"]] or "OUTLINE",
        config[prefix .. "Rendering"], config[prefix .. "Shadow"],
        config[prefix .. "ShadowOpacity"], (config[prefix .. "ShadowDistance"] or 1) * scale)
end

local function LayoutTextLabels(item, config, prefix, text, justify, width, size, height, scale)
    local label = item.label
    StylePreviewText(label, config, prefix, size, scale)
    if item.clockSecond then
        StylePreviewText(item.clockSecond, config, prefix, size, scale)
        MinimapStyle.LayoutClock(item, config, width, justify, scale)
        MinimapStyle.SetClockText(item, text)
        return
    end
    label:ClearAllPoints()
    label:SetPoint(justify, item.button, justify)
    label:SetSize(width, (height + 8) * scale)
    label:SetJustifyH(justify)
    label:SetText(text)
end

local function PaintText(ui, config, item)
    local name, prefix = item.spec[1], "info" .. item.spec[1]
    local on, sample, liveColor, texture, invite = TextContent(config, name, prefix)
    local layer = name == "Difficulty" and "difficultyText" or item.spec[3]
    local shown = ui.ShowLayer(layer, on, "text")
    local button = item.button
    button:SetShown(shown)
    if not shown then return end
    if sample == nil then
        local _, sampleTexture
        sample, _, sampleTexture = Sample(name, config)
        texture = sampleTexture
    end
    local scale = ui.art.scale
    local size = config[prefix .. "Size"] or 12
    local contentHeight = TextHeight(config, name, size)
    local fieldWidth = config[prefix .. "Width"] or 100
    if name == "Weather" and config.infoWeatherDisplay ~= WEATHER.TEXT then
        local iconSize = config.infoWeatherIconSize or RULES.infoWeatherIconSize.default
        fieldWidth = config.infoWeatherDisplay == WEATHER.ICON and iconSize or math.max(fieldWidth, iconSize + 8)
    end
    local configuredWidth = fieldWidth * scale
    local justify = TextPosition(button, ui.map, config[prefix .. "Anchor"], config[prefix .. "X"] or 0,
        config[prefix .. "Y"] or 0, scale, (config.borderSize or 0) * scale)
    LayoutTextLabels(item, config, prefix, sample, justify, configuredWidth, size, contentHeight, scale)
    -- A font that has not loaded yet measures 0: estimate from the text.
    local measured = MinimapStyle.InfoTextWidth(item)
    if measured <= 0 then
        measured = #sample * size * scale * 0.62
    end
    if name == "Weather" and texture then
        measured = measured + (config.infoWeatherIconSize or RULES.infoWeatherIconSize.default) * scale + (sample ~= "" and 4 * scale or 0)
    end
    local hitWidth = math.min(configuredWidth, math.max(24, measured + 8 * scale))
    button:SetSize(name == "Weather" and configuredWidth or hitWidth, math.max(18, (contentHeight + 8) * scale))
    item.box:SetHeight((contentHeight + 4) * scale)
    if name == "Weather" then
        if item.weatherTexture ~= texture then item.icon:SetTexture(texture) end
        item.weatherTexture, item.justify = texture, justify
        Suite.MinimapStyle.LayoutWeather(item, config, sample, scale)
        measured = item.contentWidth
        local free = math.max(0, configuredWidth - measured - 8 * scale)
        local left = justify == "LEFT" and 0 or justify == "RIGHT" and free or free / 2
        button:SetHitRectInsets(left, free - left, 0, 0)
    end
    PlaceTextDecorations(item, justify, name == "Weather" and contentHeight or size, math.min(configuredWidth, measured), scale, invite)
    local r, g, b = P.RGB(liveColor or TextColor(config, name, prefix))
    if not liveColor and config[prefix .. "ClassColor"] then r, g, b = PlayerClassColor(r, g, b) end
    item.label:SetTextColor(r or 1, g or 1, b or 1)
    if item.clockSecond then item.clockSecond:SetTextColor(r or 1, g or 1, b or 1) end
    local boxMode = config[prefix .. "Box"]
    local boxed = boxMode == BOX.BORDER or boxMode == BOX.CUSTOM
    local br, bg, bb = P.RGB(config.borderColor)
    if config.borderClassColor then br, bg, bb = PlayerClassColor(br, bg, bb) end
    if boxMode == BOX.CUSTOM then br, bg, bb = P.RGB(config[prefix .. "BoxColor"]) end
    Tint(item.box, br, bg, bb, boxed and 1 or 0.85)
    item.box:SetShown(boxed or ui.body._selectedHandle == button)
    button:SetAlpha(on and 1 or 0.38)
end

-- Owner visibility remains separate from the preview layer filters, since
-- hidden samples must not move the live row's buttons.
local function IconWanted(config, spec, drawer, drawerShown)
    local key, nativeKey = spec[1], spec[8] or spec[2]
    if key == "drawer" then
        return config.collectButtons and drawer ~= false and drawerShown ~= false and not Suite.MinimapButtonCollector()
    end
    if key == "specialization" then return config.specButton and (config.specShowSpec or config.specShowLoot) end
    if key == "dungeon" then return config.dungeonButton end
    -- Only an eye at its own offsets is drawn: hidden, or standing in for the group finder button, it has none.
    if key == "queueStatus" and Native.QueuePlacement(config) ~= "minimap" then return false end
    if key == "folio" then
        if config.showLanding == LANDING.NEVER then return false end
        nativeKey = "Landing"
    elseif key == "difficulty" then
        if not config.showDifficulty or config.infoDifficulty then return false end
    elseif key == "calendar" and config.infoCalendarDay then
        return false -- The calendar day text replaces the button.
    elseif key == "compartment" and Suite.MinimapCompartmentInDrawer(config) then
        return false -- The addon drawer holds it.
    elseif spec[4] and not config[spec[4]] then
        return false
    end
    if S.MinimapElementAvailable and not S.MinimapElementAvailable(nativeKey) then return false end
    local frame = Native.Frame(nativeKey)
    if S.MinimapElementPreviewShown then
        local shown, packed = S.MinimapElementPreviewShown(nativeKey)
        if shown ~= nil then return shown, packed end
    end
    if frame then return RegionShown(frame) end
    return spec[4] ~= false and not Native.Ready()
end

local function FallbackIcon(icon, atlas, file, inset)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", icon:GetParent(), "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", icon:GetParent(), "BOTTOMRIGHT", -inset, inset)
    icon:SetVertexColor(1, 1, 1, 1)
    icon:SetAlpha(1)
    icon:SetDesaturation(0)
    icon:SetTexCoord(0, 1, 0, 1)
    SetIcon(icon, atlas, file)
    icon:Show()
end

local function IconInset(button)
    return math.min(2, button:GetWidth() / 4, button:GetHeight() / 4)
end

-- Mirrors Blizzard's difficulty banner, or falls back to the plain icon.
local function PaintDifficulty(ui, config, item, size)
    local button, parts, scale = item.button, item.button.previewNative, ui.art.scale
    local native, mode
    if S.MinimapDifficultyPreviewSource then native, mode = S.MinimapDifficultyPreviewSource() end
    local nativeScale = (config.elementSize or RULES.elementSize.default) / 21
    local mirrored = false
    if native and mode and mode.Background and mode.Border then
        local width, height = native:GetSize()
        if PublicNumber(width) and PublicNumber(height) and width > 0 and height > 0 then
            button:SetSize(width * nativeScale * scale, height * nativeScale * scale)
        end
        local content = mode.Instance or mode
        local glyph = mode.ChallengeModeTexture
        if not glyph and type(content.DifficultyTextures) == "table" then
            for i = 1, #content.DifficultyTextures do
                local candidate = content.DifficultyTextures[i]
                local shown = candidate:IsShown()
                if Public(shown) and shown then
                    glyph = candidate
                    break
                end
            end
        end
        local background = CopyNativeTexture(parts.background, mode.Background, native, scale * nativeScale)
        local border = CopyNativeTexture(parts.border, mode.Border, native, scale * nativeScale)
        mirrored = background or border
        CopyNativeTexture(parts.emblem, mode.Emblem, native, scale * nativeScale)
        CopyNativeTexture(parts.glyph, glyph, native, scale * nativeScale)
        CopyNativeText(parts.text, content.Text, native, scale * nativeScale)
    end
    if not mirrored then
        for _, part in pairs(parts) do part:Hide() end
        button:SetSize(size, size)
        FallbackIcon(button.previewIcon, nil, item.spec[7], IconInset(button))
    end
    button.previewIcon:SetShown(not mirrored)
    item.backdrop:SetShown(not mirrored)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", ui.map, "TOPRIGHT", (-2 + (config.difficultyButtonX or 0)) * scale,
        (-2 + (config.difficultyButtonY or 0)) * scale)
end

local function NativeSize(frame)
    if not frame then return end
    local width, height = frame:GetWidth(), frame:GetHeight()
    if PublicNumber(width) and PublicNumber(height) and width > 0 and height > 0 then return width, height end
end

-- Use the same native sizing as the runtime's row and corner placements.
local function PaintNativeIcon(item, frame, source, add, border, text, width, height, scale)
    local spec, button = item.spec, item.button
    local parts, icon, mask = button.previewNative, button.previewIcon, rawget(button, "previewIconMask")
    local copied = width and CopyNativeTexture(icon, source, frame, scale)
    if copied then
        if mask then mask:SetSize(width * scale, height * scale) end
        CopyNativeTexture(parts.add, add, frame, scale)
        CopyNativeTexture(parts.border, border, frame, scale)
    else
        parts.add:Hide()
        parts.border:Hide()
        local inset = IconInset(button)
        FallbackIcon(icon, spec[6], spec[7], inset)
        if mask then mask:SetSize(button:GetWidth() - 2 * inset, button:GetHeight() - 2 * inset) end
    end
    if parts.text then
        if width then CopyNativeText(parts.text, text, frame, scale) else parts.text:Hide() end
    end
    item.backdrop:SetShown(not copied)
end

local function PaintFolio(ui, config, item, size)
    local button = item.button
    local frame, source, add = Native.Source("Landing")
    local width, height = NativeSize(frame)
    local scale = ui.art.scale
    local fit = size / 21 * 0.8
    button:SetSize(width and width * fit or size * 0.8, height and height * fit or size * 0.8)
    local book = config.landingIcon == LANDING_ICON.BOOK
    if book then
        button.previewIcon:Hide()
        button.previewNative.add:Hide()
        button.previewNative.border:Hide()
        Tint(item.backdrop, 0.08, 0.1, 0.14, 1)
        item.backdrop:Show()
    else
        PaintNativeIcon(item, frame, source, add, nil, nil, width, height, fit)
    end
    local glyphScale = fit
    local parts = button.previewBook
    parts[1]:SetSize(7 * glyphScale, 13 * glyphScale)
    parts[2]:SetSize(7 * glyphScale, 13 * glyphScale)
    parts[3]:SetSize(2 * glyphScale, 15 * glyphScale)
    parts[1]:SetPoint("RIGHT", button, "CENTER", -glyphScale, 0)
    parts[2]:SetPoint("LEFT", button, "CENTER", glyphScale, 0)
    for _, part in ipairs(parts) do part:SetShown(book) end
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", ui.map, "BOTTOMLEFT", (2 + (config.landingX or 0)) * scale,
        (2 + (config.landingY or 0)) * scale)
end

local function PaintSpec(ui, config, item)
    local button, scale = item.button, ui.art.scale
    local corner = Suite.MinimapSpecCorners[config.specCorner] or Suite.MinimapSpecCorners[1]
    local size = (config.specSize or RULES.specSize.default) * scale
    button:SetSize(size, size)
    button:ClearAllPoints()
    button:SetPoint(corner[1], ui.map, corner[2], (corner[3] + (config.specX or 0)) * scale,
        (corner[4] + (config.specY or 0)) * scale)
    local index = C_SpecializationInfo.GetSpecialization()
    local icon
    if PublicNumber(index) and index > 0 then
        local _, _, _, texture = C_SpecializationInfo.GetSpecializationInfo(index)
        if PublicNumber(texture) then icon = texture end
    end
    FallbackIcon(button.previewIcon, nil, icon or "Interface\\Icons\\INV_Misc_QuestionMark", 2 * scale)
    local r, g, b = P.RGB(config.borderColor)
    if config.borderClassColor then r, g, b = PlayerClassColor(r, g, b) end
    Tint(item.backdrop, r, g, b, 0.88)
end

-- Third-party single buttons can have several art layers (for example
-- LibDBIcon's icon, rim and background). Retain only a bounded set of textures.
local function CopyDrawerRegions(button, frame, scale, ...)
    local parts, count = button.previewDrawerArt, 0
    for index = 1, select("#", ...) do
        local source = select(index, ...)
        if not Suite.Safety.IsForbidden(source) and source:GetObjectType() == "Texture" then
            local target = parts[count + 1]
            if not target then
                target = button:CreateTexture(nil, "ARTWORK")
                parts[count + 1] = target
            end
            if CopyNativeTexture(target, source, frame, scale) then
                local layer, sublevel = source:GetDrawLayer()
                if Public(layer) and PublicNumber(sublevel) then target:SetDrawLayer(layer, sublevel) end
                local blend = source:GetBlendMode()
                if Public(blend) then target:SetBlendMode(blend) end
                count = count + 1
                if count == 8 then break end
            end
        end
    end
    for index = count + 1, #parts do parts[index]:Hide() end
    return count > 0
end

local function PaintDrawer(ui, config, item, size, source, index)
    local button = item.button
    local width, height = NativeSize(source)
    local copied
    if width then
        copied = CopyDrawerRegions(button, source, size / math.max(width, height), source:GetRegions())
    else
        for _, part in ipairs(button.previewDrawerArt) do part:Hide() end
    end
    if not copied then
        Suite.MinimapStyle.PaintDrawerToggle(button.previewIcon, config)
    end
    button.previewIcon:SetShown(not copied)
    RowPosition(button, ui.map, config.drawerRow, index, config, ui.art.scale, "drawer")
end

local function PaintIcon(ui, config, item, size, index, single)
    local spec, button = item.spec, item.button
    local key, scale = spec[1], ui.art.scale
    button:SetSize(size, size)
    if key == "specialization" then
        PaintSpec(ui, config, item)
    elseif key == "dungeon" then
        local width, height = config.dungeonWidth * scale, config.dungeonHeight * scale
        local tint, r, g, b = Suite.MinimapStyle.GroupFinderTint(config)
        if tint == "class" then r, g, b = PlayerClassColor(P.RGB("e6ecf2")) elseif tint then r, g, b = P.RGB(tint) end
        local plate = Suite.MinimapStyle.PaintDungeonButton(button, button.previewIcon,
            Suite.MinimapStyle.GroupFinderStyle(config), scale, config.dungeonIcon, width, height, r, g, b)
        button:SetSize(width, height)
        local anchor = Suite.MinimapDungeonAnchors[config.dungeonAnchor]
        button:ClearAllPoints()
        button:SetPoint(anchor[1], ui.map, anchor[2], config.dungeonX * scale, config.dungeonY * scale)
        Tint(item.backdrop, 0, 0, 0, 1)
        item.backdrop:SetShown(plate ~= false)
    elseif key == "folio" then
        PaintFolio(ui, config, item, size)
    elseif key == "difficulty" then
        PaintDifficulty(ui, config, item, size)
    elseif key == "drawer" then
        PaintDrawer(ui, config, item, size, single, config.drawerRow == config.elementRow and index or 0)
    else
        local frame, source, add, border, text = Native.Source(spec[8] or spec[2])
        local width, height = NativeSize(frame)
        if key == "queueStatus" then
            local eyeSize, x, y = Native.QueueLayout(config)
            size = eyeSize * scale
            button:SetSize(size, size)
            button:ClearAllPoints()
            button:SetPoint("CENTER", ui.map, "TOPLEFT", x * scale, y * scale)
        else
            RowPosition(button, ui.map, config.elementRow, index, config, scale, OffsetPrefix(key))
        end
        PaintNativeIcon(item, frame, source, add, border, text, width, height, width and size / math.max(width, height))
    end
    item.edge:SetShown(ui.body._selectedHandle == button)
end

local function RowIcon(spec)
    return spec[3] == "elements" and spec[1] ~= "difficulty" and spec[1] ~= "queueStatus"
end

local function PaintIcons(ui, config)
    local size = (config.elementSize or RULES.elementSize.default) * ui.art.scale
    local drawer, single, drawerShown
    if S.MinimapDrawerPreviewSource then drawer, single, drawerShown = S.MinimapDrawerPreviewSource() end
    local count, drawerItem = 0, nil
    for _, item in ipairs(ui.iconItems) do
        local key, spec = item.spec[1], item.spec
        local wanted, packed = IconWanted(config, spec, drawer, drawerShown)
        local occupiesRow = (wanted or packed) and RowIcon(spec)
        local layer = key == "drawer" and "addons" or key
        local group = spec[5] ~= layer and spec[5] or nil
        local shown = ui.ShowLayer(layer, wanted, group)
        item.button:SetShown(shown)
        item.button:SetAlpha(wanted and 1 or 0.38)
        item.sampleRow = shown and not occupiesRow and RowIcon(spec)
        if key == "drawer" then
            if shown then drawerItem = item end
        elseif not item.sampleRow then
            if shown then PaintIcon(ui, config, item, size, count) end
            if occupiesRow then count = count + 1 end
        end
    end
    if drawerItem then
        PaintIcon(ui, config, drawerItem, size, count, single)
    end
    if config.drawerRow == config.elementRow and (drawerItem or drawer and config.collectButtons) then count = count + 1 end
    for _, item in ipairs(ui.iconItems) do
        if item.sampleRow then
            PaintIcon(ui, config, item, size, count)
            count = count + 1
        end
    end
end

local function PaintOrnament(ui, config)
    local art = ui.art
    local rim = math.max(12, ((config.styleScale or RULES.styleScale.default) / 100 - 1) * art.width)
    local shown = ui.ChipOn("ornament") or ui.LayerOn("ornament") and ui.LayerOn("hidden")
    local edges = ui.ornamentEdges
    edges[1]:SetWidth(art.width + rim)
    edges[2]:SetWidth(art.width + rim)
    edges[3]:SetHeight(art.height + rim)
    edges[4]:SetHeight(art.height + rim)
    for index, point in ipairs(ORNAMENT_EDGES) do
        local edge = edges[index]
        edge:ClearAllPoints()
        edge:SetPoint("CENTER", ui.map, point, (config.styleX or 0) * art.scale, (config.styleY or 0) * art.scale)
        edge:SetShown(shown)
    end
end

local function PaintZoom(ui, button, frame, x, y, width, height)
    local scale = ui.art.scale
    local rawWidth = frame and frame:GetWidth()
    local artScale = PublicNumber(rawWidth) and rawWidth > 0 and scale * width / rawWidth or scale
    button:SetSize(width * scale, height * scale)
    local copied = frame and CopyNativeTexture(button.previewIcon, Native.ButtonTexture(frame), frame, artScale)
    button.previewIcon:SetShown(copied == true)
    local glyph = rawget(button, "previewZoomOutGlyph")
    if not glyph then
        button.previewBackdrop:SetShown(not copied)
        button.previewSign:SetShown(not copied)
    else
        local enabled = not frame or frame:IsEnabled()
        MinimapStyle.PaintZoomOutGlyph(glyph, artScale, Public(enabled) and enabled == true)
    end
    button.zoomAnchorX, button.zoomAnchorY = x * scale, y * scale
end

local function PaintZoomGroup(ui, ix, iy, ox, oy, iw, ih, ow, oh)
    local scale = ui.art.scale
    local cx, cy = (ix + ox) / 2 - (iw + ow) / 4, (iy + oy) / 2 + (ih + oh) / 4
    local horizontal = math.abs(ix - iw / 2 - ox + ow / 2) > math.abs(iy + ih / 2 - oy - oh / 2)
    local x = horizontal and cx * scale or math.min(ix - iw, ox - ow) * scale - 10
    local y = horizontal and math.max(iy + ih, oy + oh) * scale + 10 or cy * scale
    ui.zoomGroup.zoomAnchorX, ui.zoomGroup.zoomAnchorY = x, y
end

local function PlaceZoomTarget(button, map, anchor, x, y)
    button:ClearAllPoints()
    button:SetPoint(anchor, map, "BOTTOMRIGHT", button.zoomAnchorX + x, button.zoomAnchorY + y)
end

function Data.MoveZoomGroup(ui, dx, dy)
    local x, y = dx * ui.art.scale, dy * ui.art.scale
    PlaceZoomTarget(ui.zoomItems[1], ui.map, "BOTTOMRIGHT", x, y)
    PlaceZoomTarget(ui.zoomItems[2], ui.map, "BOTTOMRIGHT", x, y)
    PlaceZoomTarget(ui.zoomGroup, ui.map, "CENTER", x, y)
end

function Data.StyleZoomGroupGrip(button)
    local backdrop = button:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints(button)
    Tint(backdrop, 0.035, 0.05, 0.065, 0.95)
    for i = 1, 6 do
        local dot = button:CreateTexture(nil, "ARTWORK")
        dot:SetSize(2, 2)
        dot:SetPoint("CENTER", button, "CENTER", i <= 3 and -2 or 2, ((i - 1) % 3 - 1) * 4)
        Tint(dot, 0.75, 0.84, 0.94, 1)
    end
end

local function PaintMapControls(ui, config)
    local mode = config.zoomButtons or RULES.zoomButtons.default
    local zoomIn, zoomOut = Native.ZoomButtons()
    local zoom
    if S.MinimapZoomPreviewShown then zoom = S.MinimapZoomPreviewShown() end
    if zoom == nil then zoom = mode == ZOOM.ALWAYS and (zoomIn and zoomOut or not Native.Ready()) and true or false end
    local shown = ui.ShowLayer("zoom", zoom, "blizzard")
    for _, button in ipairs(ui.zoomItems) do
        button:SetShown(shown)
        button:SetAlpha(zoom and 1 or 0.38)
    end
    ui.zoomGroup:SetShown(shown)
    if shown then
        local ix, iy, ox, oy, iw, ih, ow, oh = Native.ZoomOffsets(config, zoomIn, zoomOut)
        ix, iy = Native.ZoomPosition(config, true, ix, iy)
        ox, oy = Native.ZoomPosition(config, false, ox, oy)
        PaintZoom(ui, ui.zoomItems[1], zoomIn, ix, iy, iw, ih)
        PaintZoom(ui, ui.zoomItems[2], zoomOut, ox, oy, ow, oh)
        PaintZoomGroup(ui, ix, iy, ox, oy, iw, ih, ow, oh)
        Data.MoveZoomGroup(ui, 0, 0)
    end
    local rotating = config.rotate == ROTATE.ROTATE
    if config.rotate == ROTATE.BLIZZARD then
        local value = GetCVarBool("rotateMinimap")
        rotating = Public(value) and value == true
    end
    ui.compass:SetShown(ui.ShowLayer("compass", rotating, "blizzard"))
    ui.compass:SetAlpha(rotating and 1 or 0.38)
end

-- Everything above the map and its artwork, in drawing order.
local function PaintElements(ui, config)
    PaintOrnament(ui, config)
    ui.guides[1]:SetShown(ui.LayerOn("guides"))
    ui.guides[2]:SetShown(ui.LayerOn("guides"))
    for _, item in ipairs(ui.textItems) do PaintText(ui, config, item) end
    PaintIcons(ui, config)
    PaintMapControls(ui, config)
end

Data.ORNAMENT_EDGES = ORNAMENT_EDGES
Data.Clamp, Data.Tint, Data.SetIcon = Clamp, Tint, SetIcon
Data.OffsetPrefix, Data.OffsetKeys = OffsetPrefix, OffsetKeys
Data.PaintElements, Data.PaintText = PaintElements, PaintText
