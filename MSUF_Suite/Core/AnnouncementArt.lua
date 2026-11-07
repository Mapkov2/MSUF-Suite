local _, NS = ...
local Art = { WIDTH = 660, HEIGHT = 130 }
NS.AnnouncementArt = Art

-- Indices match the announcement artStyle choices. Each part specifies its
-- top-left offset and size. Blizzard's tutorial and event toast atlases are
-- available on Retail and Forever.
local ARROWS = 2
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

function Art.Create(parent, createTexture)
    createTexture = createTexture or parent.CreateTexture
    local background = createTexture(parent, nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", 65, -8)
    background:SetPoint("BOTTOMRIGHT", -65, 11)
    return { parent = parent, createTexture = createTexture, background = background, accents = {}, inset = 14 }
end

local function Available(index)
    local style = STYLES[index]
    if not style then return 1 end
    local getAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
    for _, part in ipairs(style) do
        if part.atlas and (not getAtlasInfo or not getAtlasInfo(part.atlas)) then return 1 end
    end
    return index
end

function Art.Layout(art, config)
    local requested = config and config.showBoxArt ~= false and (config.artStyle or 1) or 0
    if art.requested == requested then return end
    art.requested = requested
    local show = requested ~= 0
    local style = show and Available(requested) or 0
    art.style, art.inset = style, style == ARROWS and 65 or 14
    art.background:SetShown(show)
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
        texture:SetAlpha(part.atlas and part.alpha or 1)
        texture:Show()
    end
end

function Art.Tint(art, r, g, b)
    local style = STYLES[art.style]
    if not style then return end
    for index, part in ipairs(style) do
        if not part.atlas then art.accents[index]:SetColorTexture(r, g, b, part.alpha) end
    end
end
