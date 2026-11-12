local _, NS = ...
local Art = { WIDTH = 660, HEIGHT = 130 }
NS.AnnouncementArt = Art

-- Indices match the announcement artStyle choices. Each part specifies its
-- top-left offset and size. Blizzard's tutorial and event toast atlases are
-- available on Retail and Forever.
local ARROWS = 2
local PANEL_INSET, PANEL_TOP, PANEL_BOTTOM = 65, 8, 11
local PANEL_WIDTH, PANEL_HEIGHT = Art.WIDTH - 2 * PANEL_INSET, Art.HEIGHT - PANEL_TOP - PANEL_BOTTOM
-- The panel the background fills and the frame outlines; the menu preview
-- places its click targets on it.
Art.PANEL = { x = PANEL_INSET, y = -PANEL_TOP, width = PANEL_WIDTH, height = PANEL_HEIGHT }
local DIVIDER = { 200, -75, 260, 1, alpha = .62 }
local STYLES = {
    { { 312.5, -12, 35, 2, alpha = .95 }, DIVIDER },
    {
        { 16, -38, 44, 44, alpha = .95, atlas = "NPE_ArrowRight" },
        { 600, -38, 44, 44, alpha = .95, atlas = "NPE_ArrowLeft" },
    },
    {
        { 97, -6, 466, 10, alpha = .90, atlas = "levelup-bar-gold" },
        { 97, -108, 466, 10, alpha = .90, atlas = "levelup-bar-gold" },
    },
    { { 120, -9, 420, 79, alpha = .45, atlas = "levelup-glow-gold" }, DIVIDER },
}

-- frameStyle: Full box, Top and bottom lines, Corner brackets;
-- frameColorSource: Classic gold, Headline color, Custom color
-- (MSUF_Suite/Core/Catalog/HUD.lua).
local FRAME_LINES, FRAME_CORNERS = 2, 3
local FRAME_HEADLINE, FRAME_CUSTOM = 2, 3
local GOLD_R, GOLD_G, GOLD_B = .96, .81, .44
local CORNER_LENGTH = 24
-- Layout without settings (the menu preview of another HUD) draws nothing.
local HIDDEN = { showBoxArt = false, showFrame = false }
-- colorStyle: Suite skin + default accents, Custom colors.
local CUSTOM_COLORS = 2
-- The headline color of each banner kind, and its setting under Custom colors.
local KIND_COLORS = {
    zone = { .96, .88, .67 }, quest = { .98, .79, .39 },
    achievement = { .88, .69, .41 }, level = { .47, .81, .98 },
    scenario = { .69, .58, .96 }, notice = { .66, .84, .98 },
}
local COLOR_KEYS = {
    zone = "zoneColor", quest = "questColor", achievement = "achievementColor",
    level = "levelColor", scenario = "scenarioColor", notice = "noticeColor",
}
-- The top of the headline and subtitle rows; the subtitle sits a little
-- further in than the headline.
local TITLE_TOP, SUBTITLE_TOP, SUBTITLE_PAD = -23, -84, 4

local function Text(parent, createFontString)
    local text = createFontString(parent, nil, "OVERLAY")
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)
    return text
end

-- The banner on parent: the runtime banner and the menu's sample draw the
-- same parts through the same functions, so the sample cannot drift.
function Art.Create(parent, createTexture, createFontString)
    createTexture = createTexture or parent.CreateTexture
    createFontString = createFontString or parent.CreateFontString
    local background = createTexture(parent, nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", PANEL_INSET, -PANEL_TOP)
    background:SetPoint("BOTTOMRIGHT", -PANEL_INSET, PANEL_BOTTOM)
    return { parent = parent, createTexture = createTexture, background = background, accents = {}, inset = 14,
        border = {}, frameCount = 0, revision = 0,
        title = Text(parent, createFontString), subtitle = Text(parent, createFontString) }
end

function Art.PaintBackground(art, r, g, b, opacity)
    art.backgroundOpacity = opacity
    art.background:SetColorTexture(r, g, b, opacity)
    art.background:SetShown(opacity > 0)
end

-- The frame's edges as top-left offset and size: the whole box, only its top
-- and bottom lines, or a bracket at each corner. Thicker lines grow inwards,
-- so a one pixel box is the frame the banner always had.
local function FrameParts(shape, thickness)
    local left, top = PANEL_INSET, -PANEL_TOP
    local right, bottom = left + PANEL_WIDTH - thickness, top - PANEL_HEIGHT + thickness
    if shape == FRAME_CORNERS then
        local arm, across = CORNER_LENGTH - thickness, right + thickness - CORNER_LENGTH
        return {
            { left, top, CORNER_LENGTH, thickness }, { left, top - thickness, thickness, arm },
            { across, top, CORNER_LENGTH, thickness }, { right, top - thickness, thickness, arm },
            { left, bottom, CORNER_LENGTH, thickness }, { left, bottom + arm, thickness, arm },
            { across, bottom, CORNER_LENGTH, thickness }, { right, bottom + arm, thickness, arm },
        }
    end
    local parts = { { left, top, PANEL_WIDTH, thickness }, { left, bottom, PANEL_WIDTH, thickness } }
    if shape ~= FRAME_LINES then
        parts[3] = { left, top - thickness, thickness, PANEL_HEIGHT - 2 * thickness }
        parts[4] = { right, top - thickness, thickness, PANEL_HEIGHT - 2 * thickness }
    end
    return parts
end

-- Headline color follows the last Art.Tint; until then the frame is gold.
local function FrameColor(art)
    if art.frameSource == FRAME_HEADLINE and art.tintR then return art.tintR, art.tintG, art.tintB end
    if art.frameSource == FRAME_CUSTOM and art.frameCustom then return NS.RGB(art.frameCustom) end
    return GOLD_R, GOLD_G, GOLD_B
end

local function PaintFrame(art)
    if art.frameCount == 0 then return end
    local r, g, b = FrameColor(art)
    for index = 1, art.frameCount do art.border[index]:SetColorTexture(r, g, b, art.frameAlpha) end
end

local function PlaceFrame(art, shape, thickness)
    local parts = shape == 0 and {} or FrameParts(shape, thickness)
    for index, part in ipairs(parts) do
        local edge = art.border[index]
        if not edge then
            edge = art.createTexture(art.parent, nil, "BORDER")
            art.border[index] = edge
        end
        local x, y, width, height = unpack(part)
        edge:ClearAllPoints()
        edge:SetPoint("TOPLEFT", x, y)
        edge:SetSize(width, height)
        edge:Show()
    end
    for index = #parts + 1, #art.border do art.border[index]:Hide() end
    art.frameCount = #parts
end

-- A config saved before the frame had its own switch hid the frame with the
-- artwork. Normalized profiles carry that over (the catalog's prepareConfig);
-- a config without the setting follows the artwork switch the same way.
local function LayoutFrame(art, config)
    local shown = config.showFrame
    if shown == nil then shown = config.showBoxArt ~= false end
    local shape = shown and (config.frameStyle or 1) or 0
    local thickness, alpha = config.frameThickness or 1, (config.frameOpacity or 48) / 100
    local source = config.frameColorSource or 1
    local custom = source == FRAME_CUSTOM and config.frameColor or nil
    if art.frameShape ~= shape or art.frameThickness ~= thickness then
        art.frameShape, art.frameThickness = shape, thickness
        PlaceFrame(art, shape, thickness)
        art.revision = art.revision + 1
    end
    if art.frameAlpha ~= alpha or art.frameSource ~= source or art.frameCustom ~= custom then
        art.frameAlpha, art.frameSource, art.frameCustom = alpha, source, custom
        art.revision = art.revision + 1
    end
    PaintFrame(art)
end

local function Available(index)
    local style = STYLES[index]
    if not style then return 1 end
    for _, part in ipairs(style) do
        if part.atlas and not C_Texture.GetAtlasInfo(part.atlas) then return 1 end
    end
    return index
end

-- art.revision changes with every visible change of the artwork or frame.
function Art.Layout(art, config)
    config = config or HIDDEN
    LayoutFrame(art, config)
    local requested = config.showBoxArt ~= false and (config.artStyle or 1) or 0
    local opacity = (config.artOpacity or 100) / 100
    if art.requested == requested and art.artOpacity == opacity then return end
    art.requested, art.artOpacity = requested, opacity
    art.revision = art.revision + 1
    local show = requested ~= 0
    local style = show and Available(requested) or 0
    art.style, art.inset = style, style == ARROWS and 65 or 14
    if not show then
        for _, texture in ipairs(art.accents) do texture:Hide() end
        return
    end
    for index, part in ipairs(STYLES[style]) do
        local texture = art.accents[index]
        if not texture then
            texture = art.createTexture(art.parent, nil, "ARTWORK")
            art.accents[index] = texture
        end
        local x, y, width, height = unpack(part)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", x, y)
        texture:SetSize(width, height)
        if part.atlas then texture:SetAtlas(part.atlas) end
        texture:SetAlpha(part.atlas and part.alpha * opacity or 1)
        texture:Show()
    end
end

-- The headline color of the banner on show: it tints the plain accents and,
-- with Headline color, the frame.
function Art.Tint(art, r, g, b)
    art.tintR, art.tintG, art.tintB = r, g, b
    PaintFrame(art)
    local style = STYLES[art.style]
    if not style then return end
    for index, part in ipairs(style) do
        if not part.atlas then art.accents[index]:SetColorTexture(r, g, b, part.alpha * art.artOpacity) end
    end
end

------------------------------------------------------------------ text
-- The offset settings of each text row: x moves right, y moves up.
local OFFSET_KEYS = { title = { "titleOffsetX", "titleOffsetY" }, subtitle = { "subtitleOffsetX", "subtitleOffsetY" } }
Art.OFFSET_KEYS = OFFSET_KEYS

function Art.TextOffset(config, key)
    local keys = OFFSET_KEYS[key]
    return config[keys[1]] or 0, config[keys[2]] or 0
end

-- A text row ("title" or "subtitle") inside the artwork's insets, moved by
-- x and y. The menu preview draws a dragged row here before it is saved.
function Art.PlaceText(art, key, x, y)
    local text, pad = art[key], art.inset + (key == "subtitle" and SUBTITLE_PAD or 0)
    local top = (key == "subtitle" and SUBTITLE_TOP or TITLE_TOP) + y
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", pad + x, top)
    text:SetPoint("TOPRIGHT", x - pad, top)
end

local function PlaceTexts(art, config)
    local tx, ty = Art.TextOffset(config, "title")
    local sx, sy = Art.TextOffset(config, "subtitle")
    local placed = art.placed
    if placed and placed[1] == art.inset and placed[2] == tx and placed[3] == ty and placed[4] == sx
        and placed[5] == sy then return end
    art.placed = { art.inset, tx, ty, sx, sy }
    Art.PlaceText(art, "title", tx, ty)
    Art.PlaceText(art, "subtitle", sx, sy)
    art.revision = art.revision + 1
end

-- Fonts, colors, background, artwork and text rows from the settings.
-- skin: the Suite skin's palette (GetColor, GetLook), nil while it is off.
function Art.Theme(art, config, skin)
    local font, setFont = NS.ResolveFont(config.font) or NS.GlobalFontPath(), NS.Suite.SetStyledFont
    setFont(art.title, font, config.titleSize or 31, NS.HUDTextArgs(config, "banner"))
    setFont(art.subtitle, font, config.subtitleSize or 16, NS.HUDTextArgs(config, "subtitle"))
    Art.Layout(art, config)
    local dark = not skin or not skin.GetLook or skin:GetLook() == "midnightDark"
    local opacity = (config.backgroundOpacity or (dark and 57 or 50)) / 100
    if config.colorStyle == CUSTOM_COLORS then
        local r, g, b = NS.RGB(config.backgroundColor)
        Art.PaintBackground(art, r, g, b, opacity)
        art.subtitle:SetTextColor(NS.RGB(config.subtitleColor))
    elseif skin then
        local r, g, b = skin:GetColor("surface")
        Art.PaintBackground(art, r, g, b, opacity)
        art.subtitle:SetTextColor(skin:GetColor("text"))
    else
        Art.PaintBackground(art, .02, .025, .035, opacity)
        art.subtitle:SetTextColor(.91, .93, .96)
    end
    PlaceTexts(art, config)
end

-- The headline color of a banner kind; an unknown kind takes the zone's.
function Art.KindColor(config, kind)
    if config.colorStyle == CUSTOM_COLORS then return NS.RGB(config[COLOR_KEYS[kind] or COLOR_KEYS.zone]) end
    local color = KIND_COLORS[kind] or KIND_COLORS.zone
    return color[1], color[2], color[3]
end

-- One banner: its texts, the headline in its kind's color, which also tints
-- the plain accents and a headline-colored frame.
function Art.Show(art, config, kind, title, subtitle)
    local r, g, b = Art.KindColor(config, kind)
    art.title:SetText(title)
    art.title:SetTextColor(r, g, b)
    art.subtitle:SetText(subtitle or "")
    art.title:Show()
    art.subtitle:Show()
    Art.Tint(art, r, g, b)
end

-- Nothing of the banner shows (the menu preview of another HUD).
function Art.Clear(art)
    Art.Layout(art)
    art.background:Hide()
    art.title:Hide()
    art.subtitle:Hide()
end
