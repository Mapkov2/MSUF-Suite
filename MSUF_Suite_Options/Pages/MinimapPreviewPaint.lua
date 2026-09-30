local _, P = ...
-- Minimap page preview, the drawing: the element tables, the samples and the
-- mirrored native art, and the painters of texts, icons, artwork edges and
-- map controls. MinimapPreview.lua builds the selectable canvas on top.
local Suite, S, Tr = P.Suite, P.S, P.Tr
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ANCHORS = Suite.AnchorPoints
local ROWS = Suite.MinimapRowGeometry
local OUTLINES = { "", "OUTLINE", "THICKOUTLINE", "MONOCHROME,OUTLINE" }

-- { name, sample text, key } of every info text.
local TEXTS = {
    { "Clock", "12:34", "clock" }, { "FPS", "60 FPS", "fps" }, { "Latency", "23 ms", "latency" },
    { "Coordinates", "42.1, 56.7", "coordinates" }, { "Durability", "100%", "durability" },
    { "Location", "Current zone", "location" }, { "Weather", "Clear", "weather" },
    { "Difficulty", "5H", "difficulty" },
}
-- { key, label, section, visibility setting (false: native state), layer, atlas, file }
local ICONS = {
    { "tracking", "Tracking", "elements", "showTracking", "blizzard", "ui-hud-minimap-tracking-up", "Interface\\Minimap\\Tracking\\None" },
    { "calendar", "Calendar", "elements", "showCalendar", "blizzard", "ui-hud-minimap-calendar-up", "Interface\\Calendar\\UI-Calendar-Button" },
    { "mail", "Mail", "elements", "showMail", "blizzard", "ui-hud-minimap-mail-up", "Interface\\Minimap\\Tracking\\Mailbox" },
    { "crafting", "Crafting", "elements", "showCrafting", "blizzard", "UI-HUD-Minimap-CraftingOrder-Up", "Interface\\Icons\\INV_Hammer_20" },
    { "compartment", "Compartment", "elements", "showCompartment", "blizzard", "ui-hud-minimap-button", "Interface\\Buttons\\UI-OptionsButton" },
    { "difficulty", "Difficulty", "elements", "showDifficulty", "blizzard", nil, "Interface\\GroupFrame\\UI-Group-LeaderIcon" },
    { "folio", "Omnium Folio", "landing", "showLanding", "folio", "GarrLanding-MinimapIcon-Alliance-Up", "Interface\\Icons\\INV_Misc_Book_09" },
    { "drawer", "Addon drawer", "addons", "collectButtons", "addons", nil, "Interface\\Buttons\\UI-OptionsButton" },
}
local ICON_KEYS = {}
if not Suite.Client.isForever then
    ICONS[#ICONS + 1] = { "specialization", "Minimap specialization menu", "specialization", "specButton",
        "specialization", nil, "Interface\\Icons\\INV_Misc_QuestionMark" }
end
for _, spec in ipairs(ICONS) do ICON_KEYS[spec[1]] = true end
local LAYERS = {
    { "map", "Map" }, { "border", "Border" }, { "ornament", "Artwork" }, { "glow", "Glow" },
    { "backdrop", "Plate" }, { "shadow", "Shadow" },
    { "text", "Texts" }, { "blizzard", "Blizzard" }, { "folio", "Folio" },
    { "addons", "Addons" }, { "guides", "Guides" }, { "hidden", "Hidden" },
}
local ORNAMENT_EDGES = { "TOP", "BOTTOM", "LEFT", "RIGHT" }
if not Suite.Client.isForever then table.insert(LAYERS, #LAYERS - 1, { "specialization", "Specialization" }) end

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
        if PublicNumber(hour) and PublicNumber(minute) then
            return string.format("%02d:%02d", hour, minute)
        end
        return "12:34"
    end
    if name == "Location" then
        return Suite.PublicText(GetZoneText()) or Tr("Current zone")
    end
    if name == "Durability" then
        return (config.infoDurabilityIcon and "|TInterface\\Durability\\UI-Durability-Icons:12:10|t " or "") .. "100%"
    end
    for _, spec in ipairs(TEXTS) do
        if spec[1] == name then return spec[2] end
    end
    return name
end

-- GetAtlasInfo returns nil for an atlas this client does not have.
local function SetIcon(texture, atlas, path)
    if atlas then
        local info = C_Texture.GetAtlasInfo(atlas)
        if info and Public(info) then
            texture:SetAtlas(atlas)
            return
        end
    end
    texture:SetTexture(path or WHITE)
end

-- Offset of a native region's center from its frame's center, in preview units.
local function CenterOffset(frame, source, scale)
    local fx, fy = frame:GetCenter()
    local sx, sy = source:GetCenter()
    local x = PublicNumber(fx) and PublicNumber(sx) and (sx - fx) * scale or 0
    local y = PublicNumber(fy) and PublicNumber(sy) and (sy - fy) * scale or 0
    return x, y
end

-- Mirror the active Blizzard difficulty banner instead of drawing a crown.
-- Its artwork and text change with instance type, guild group and client.
local function CopyNativeTexture(target, source, frame, scale, nativeScale)
    if not source then
        target:Hide()
        return false
    end
    local shown = source:IsShown()
    if not Public(shown) or not shown then
        target:Hide()
        return false
    end
    local atlas = source:GetAtlas()
    if Public(atlas) and type(atlas) == "string" and atlas ~= "" then
        target:SetAtlas(atlas)
    else
        local file = source:GetTexture()
        if not Public(file) or type(file) ~= "string" and type(file) ~= "number" then
            target:Hide()
            return false
        end
        target:SetTexture(file)
    end
    local left, right, top, bottom = source:GetTexCoord()
    if PublicNumber(left) and PublicNumber(right) and PublicNumber(top) and PublicNumber(bottom) then
        target:SetTexCoord(left, right, top, bottom)
    end
    local r, g, b, a = source:GetVertexColor()
    if PublicNumber(r) and PublicNumber(g) and PublicNumber(b) and Public(a) then
        target:SetVertexColor(r, g, b, type(a) == "number" and a or 1)
    end
    local alpha = source:GetAlpha()
    if PublicNumber(alpha) then target:SetAlpha(alpha) end
    local width, height = source:GetSize()
    if not PublicNumber(width) or not PublicNumber(height) then
        target:Hide()
        return false
    end
    target:SetSize(width * nativeScale * scale, height * nativeScale * scale)
    target:ClearAllPoints()
    target:SetPoint("CENTER", target:GetParent(), "CENTER", CenterOffset(frame, source, scale))
    target:Show()
    return true
end

local function CopyNativeText(target, source, frame, scale, nativeScale)
    if not source then
        target:Hide()
        return
    end
    local shown = source:IsShown()
    if not Public(shown) or not shown then
        target:Hide()
        return
    end
    local font, size, flags = source:GetFont()
    if Public(font) and Public(size) and Public(flags) and type(font) == "string" and type(size) == "number" then
        target:SetFont(font, math.max(6, size * nativeScale * scale), flags)
    end
    target:SetText(source:GetText())
    local r, g, b, a = source:GetTextColor()
    if PublicNumber(r) and PublicNumber(g) and PublicNumber(b) and Public(a) then
        target:SetTextColor(r, g, b, type(a) == "number" and a or 1)
    end
    target:ClearAllPoints()
    target:SetPoint("CENTER", target:GetParent(), "CENTER", CenterOffset(frame, source, scale))
    target:Show()
end

local function RowPosition(button, map, rowIndex, index, config, scale, prefix)
    local row = ROWS[rowIndex] or ROWS[1]
    local distance = ((config.elementDistance or 0) + (config.borderSize or 0)) * scale
    local step = ((config.elementSize or 21) + (config.elementSpacing or 0)) * scale
    button:ClearAllPoints()
    button:SetPoint(row[1], map, row[2],
        row[3] * distance + row[5] * index * step + (config[prefix .. "X"] or 0) * scale,
        row[4] * distance + row[6] * index * step + (config[prefix .. "Y"] or 0) * scale)
end

-- Anchors 10 and 11 sit above and below the map; returns the text justify.
local function TextPosition(button, map, anchor, x, y, scale, border)
    button:ClearAllPoints()
    if anchor == 10 then
        button:SetPoint("BOTTOM", map, "TOP", x * scale, y * scale + border)
        return "CENTER"
    end
    if anchor == 11 then
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
    if not key then return nil end
    if key:find("^info") then return key end
    if key == "folio" then return "landing" end
    if key == "specialization" then return "spec" end
    if key == "difficulty" then return "difficultyButton" end
    if key == "drawer" or key == "zoomIn" or key == "zoomOut" then return key end
    if key == "ornament" or key:find("^ornament_") then return "style" end
    if ICON_KEYS[key] then return "button" .. key:sub(1, 1):upper() .. key:sub(2) end
end

local function OffsetKeys(key)
    if key == "map" then return "x", "y" end
    local prefix = OffsetPrefix(key)
    if prefix then return prefix .. "X", prefix .. "Y" end
end

------------------------------------------------------------------ painting
local function PaintText(ui, config, item)
    local name, prefix = item.spec[1], "info" .. item.spec[1]
    local on = config[prefix] == true
    local shown = ui.LayerOn("text") and (on or ui.LayerOn("hidden"))
    local button = item.button
    button:SetShown(shown)
    if not shown then return end
    local scale = ui.art.scale
    local size = config[prefix .. "Size"] or 12
    local path = Suite.ResolveFont(config[prefix .. "Font"] or "") or STANDARD_TEXT_FONT
    P.StylePreviewFont(item.label, path, math.max(8, size * scale), OUTLINES[config[prefix .. "Outline"]] or "OUTLINE",
        config[prefix .. "Rendering"], config[prefix .. "Shadow"],
        config[prefix .. "ShadowOpacity"], config[prefix .. "ShadowDistance"])
    local sample, _, texture = Sample(name, config)
    item.label:SetText(sample)
    -- The hit area hugs the rendered text, up to the configured field width.
    local contentHeight = name == "Weather" and Suite.MinimapStyle.WeatherHeight(config) or size
    local fieldWidth = config[prefix .. "Width"] or 100
    if name == "Weather" and config.infoWeatherDisplay ~= 1 then
        local iconSize = config.infoWeatherIconSize or 24
        fieldWidth = config.infoWeatherDisplay == 2 and iconSize or math.max(fieldWidth, iconSize + 8)
    end
    local configuredWidth = math.max(24, fieldWidth * scale)
    -- A font that has not loaded yet measures 0: estimate from the text.
    local measured = item.label:GetStringWidth()
    if measured <= 0 then
        measured = #sample * size * scale * 0.62
    end
    if name == "Weather" and texture then
        measured = measured + (config.infoWeatherIconSize or 24) * scale + (sample ~= "" and 4 * scale or 0)
    end
    local hitWidth = math.min(configuredWidth, math.max(24, measured + 8))
    button:SetSize(hitWidth, math.max(18, (contentHeight + 8) * scale))
    item.box:SetWidth(hitWidth)
    if name == "Weather" then item.box:SetHeight((contentHeight + 4) * scale) end
    local justify = TextPosition(button, ui.map, config[prefix .. "Anchor"], config[prefix .. "X"] or 0,
        config[prefix .. "Y"] or 0, scale, (config.borderSize or 0) * scale)
    item.label:SetJustifyH(justify)
    if name == "Weather" then
        if item.weatherTexture ~= texture then item.icon:SetTexture(texture) end
        item.weatherTexture, item.justify = texture, justify
        Suite.MinimapStyle.LayoutWeather(item, config, sample, scale)
        item.box:SetWidth(math.max(contentHeight * scale, item.contentWidth + 8 * scale))
    end
    local r, g, b = P.RGB(config[prefix .. "Color"] or "ffffff")
    if config[prefix .. "ClassColor"] then r, g, b = PlayerClassColor(r, g, b) end
    item.label:SetTextColor(r or 1, g or 1, b or 1)
    local boxMode = config[prefix .. "Box"]
    local boxed = name ~= "Difficulty" and (boxMode == 2 or boxMode == 3)
    local br, bg, bb = P.RGB(config.borderColor)
    if boxMode == 3 then br, bg, bb = P.RGB(config[prefix .. "BoxColor"]) end
    Tint(item.box, br, bg, bb, 0.85)
    item.box:SetShown(boxed or ui.state.selected and ui.state.selected.key == prefix)
    button:SetAlpha(on and 1 or 0.38)
end

-- Whether an icon's element would show in game (the preview may still show
-- it dimmed through the Hidden layer).
-- S.Minimap* come with the minimap addon; before it loads, the settings decide.
local function IconWanted(config, spec)
    local key = spec[1]
    if key == "specialization" then return config.specButton and (config.specShowSpec or config.specShowLoot) end
    if key == "difficulty" then
        local wanted = config.showDifficulty and not config.infoDifficulty
        if S.MinimapElementAvailable then wanted = wanted and S.MinimapElementAvailable("Difficulty") end
        if S.MinimapElementPreviewShown and S.MinimapElementPreviewShown("Difficulty") == false then wanted = false end
        return wanted
    end
    local wanted = key == "folio" and config.showLanding ~= 3 or spec[4] and config[spec[4]] == true
    if key == "drawer" and Suite.Client.IsAddOnLoaded("MinimapButtonButton") then wanted = false end
    if spec[4] == false then
        wanted = S.MinimapElementPreviewShown and S.MinimapElementPreviewShown(spec[2]) == true or false
    end
    if spec[3] == "elements" and S.MinimapElementPreviewShown and S.MinimapElementPreviewShown(spec[2]) == false then
        wanted = false
    end
    return wanted
end

-- Mirrors Blizzard's difficulty banner, or falls back to the plain icon.
local function PaintDifficulty(ui, config, item, size)
    local button, parts, scale = item.button, item.button.previewNative, ui.art.scale
    local native, mode
    if S.MinimapDifficultyPreviewSource then native, mode = S.MinimapDifficultyPreviewSource() end
    local nativeScale = (config.elementSize or 21) / 21
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
        local background = CopyNativeTexture(parts.background, mode.Background, native, scale, nativeScale)
        local border = CopyNativeTexture(parts.border, mode.Border, native, scale, nativeScale)
        mirrored = background or border
        CopyNativeTexture(parts.emblem, mode.Emblem, native, scale, nativeScale)
        CopyNativeTexture(parts.glyph, glyph, native, scale, nativeScale)
        CopyNativeText(parts.text, content.Text, native, scale, nativeScale)
    end
    if not mirrored then
        for _, part in pairs(parts) do part:Hide() end
        button:SetSize(size, size)
    end
    button.previewIcon:SetShown(not mirrored)
    item.backdrop:SetShown(not mirrored)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", ui.map, "TOPRIGHT", (-2 + (config.difficultyButtonX or 0)) * scale,
        (-2 + (config.difficultyButtonY or 0)) * scale)
end

local function PaintFolio(ui, config, button, size)
    local simpleBook = config.landingIcon == 2
    button.previewIcon:SetShown(not simpleBook)
    for _, part in ipairs(button.previewBook) do part:SetShown(simpleBook) end
    local scale = ui.art.scale
    button:SetSize(size * 0.8, size * 0.8)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", ui.map, "BOTTOMLEFT", (2 + (config.landingX or 0)) * scale,
        (2 + (config.landingY or 0)) * scale)
end

local function PaintIcons(ui, config)
    local rowCount = 0
    local scale = ui.art.scale
    local size = Clamp((config.elementSize or 21) * scale, 12, 60)
    local selectedKey = ui.state.selected and ui.state.selected.key
    for _, item in ipairs(ui.iconItems) do
        local spec, button = item.spec, item.button
        local key = spec[1]
        local wanted = IconWanted(config, spec)
        button:SetShown(ui.LayerOn(spec[5]) and (wanted or ui.LayerOn("hidden")))
        button:SetAlpha(wanted and 1 or 0.38)
        button:SetSize(size, size)
        if key == "specialization" then
            local corner = Suite.MinimapSpecCorners[config.specCorner] or Suite.MinimapSpecCorners[1]
            local buttonSize = (config.specSize or 24) * scale
            button:SetSize(buttonSize, buttonSize)
            button:ClearAllPoints()
            button:SetPoint(corner[1], ui.map, corner[2], (corner[3] + (config.specX or 0)) * scale,
                (corner[4] + (config.specY or 0)) * scale)
            local index = C_SpecializationInfo.GetSpecialization()
            local icon
            if PublicNumber(index) and index > 0 then
                local _, _, _, texture = C_SpecializationInfo.GetSpecializationInfo(index)
                if PublicNumber(texture) then icon = texture end
            end
            button.previewIcon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        elseif key == "folio" then
            PaintFolio(ui, config, button, size)
        elseif key == "difficulty" then
            PaintDifficulty(ui, config, item, size)
        elseif key == "drawer" then
            local index = config.drawerRow == config.elementRow and rowCount or 0
            RowPosition(button, ui.map, config.drawerRow, index, config, scale, "drawer")
        else
            RowPosition(button, ui.map, config.elementRow, rowCount, config, scale, OffsetPrefix(key))
            if wanted then rowCount = rowCount + 1 end
        end
        local chosen = selectedKey == key
        if key == "difficulty" then item.edge:SetShown(chosen) end
        if chosen then
            Tint(item.edge, 0.28, 0.74, 1, 1)
            Tint(item.backdrop, 0.11, 0.3, 0.43, 0.9)
        else
            Tint(item.edge, 0.6, 0.74, 0.83, 0.65)
            Tint(item.backdrop, 0.025, 0.035, 0.045, 0.9)
        end
    end
end

local function PaintOrnament(ui, config)
    local art = ui.art
    local rim = math.max(12, ((config.styleScale or 100) / 100 - 1) * art.width)
    local shown = ui.LayerOn("ornament") and (config.styleTexture ~= 1 or ui.LayerOn("hidden"))
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

local function PaintMapControls(ui, config)
    local scale = ui.art.scale
    local mode = config.zoomButtons or 1
    for index, button in ipairs(ui.zoomItems) do
        button:SetShown(ui.LayerOn("blizzard") and (mode ~= 3 or ui.LayerOn("hidden")))
        button:SetAlpha(mode == 2 and 1 or mode == 1 and 0.62 or 0.38)
        local prefix = index == 1 and "zoomIn" or "zoomOut"
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", ui.map, "BOTTOMRIGHT",
            (-2 + (config[prefix .. "X"] or 0)) * scale,
            ((index == 1 and 27 or 3) + (config[prefix .. "Y"] or 0)) * scale)
    end
    local rotating = config.rotate == 2
    if config.rotate == 1 then
        local value = GetCVarBool("rotateMinimap")
        rotating = Public(value) and value == true
    end
    ui.compass:SetShown(ui.LayerOn("blizzard") and (rotating or ui.LayerOn("hidden")))
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

P.MinimapPreviewData = {
    TEXTS = TEXTS, ICONS = ICONS, ICON_KEYS = ICON_KEYS, LAYERS = LAYERS, ORNAMENT_EDGES = ORNAMENT_EDGES,
    Clamp = Clamp, Tint = Tint, SetIcon = SetIcon, OffsetPrefix = OffsetPrefix, OffsetKeys = OffsetKeys,
    PaintElements = PaintElements,
}
