local _, P = ...
local Suite, S = P.Suite, P.S
local CIRCLE = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\Circle.tga"
local SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"
local FALLBACK_ART = "Interface\\AddOns\\MidnightSimpleUnitFrames_Options\\Media\\PreviewBackgrounds\\silvermoon.png"
-- Alpha share of the three shadow rings, inner to outer.
local SHADOW_STRENGTH = { 0.45, 0.25, 0.12 }
-- Pixel width of one world-map tile row at minimap zoom.
local TERRAIN_SPAN = 384

local function Public(value)
    return not S.Public or S.Public(value)
end

local function Texture(parent, layer, sub)
    return parent:CreateTexture(nil, layer, nil, sub)
end

local function EdgeSet(parent, layer, sub)
    local out = {}
    for i = 1, 4 do out[i] = Texture(parent, layer, sub) end
    return out
end

-- Four bars framing `map` from `inner` to `outer` pixels outside its edge.
local function PaintEdges(edges, map, inner, outer, r, g, b, alpha, shown)
    local band = outer - inner
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    top:ClearAllPoints()
    top:SetPoint("BOTTOMLEFT", map, "TOPLEFT", -outer, inner)
    top:SetPoint("BOTTOMRIGHT", map, "TOPRIGHT", outer, inner)
    top:SetHeight(band)
    bottom:ClearAllPoints()
    bottom:SetPoint("TOPLEFT", map, "BOTTOMLEFT", -outer, -inner)
    bottom:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", outer, -inner)
    bottom:SetHeight(band)
    left:ClearAllPoints()
    left:SetPoint("TOPRIGHT", map, "TOPLEFT", -inner, inner)
    left:SetPoint("BOTTOMRIGHT", map, "BOTTOMLEFT", -inner, -inner)
    left:SetWidth(band)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", map, "TOPRIGHT", inner, inner)
    right:SetPoint("BOTTOMLEFT", map, "BOTTOMRIGHT", inner, -inner)
    right:SetWidth(band)
    local visible = shown and band > 0 and alpha > 0
    for i = 1, 4 do
        edges[i]:SetColorTexture(r, g, b, alpha)
        edges[i]:SetShown(visible)
    end
end

local function PositiveNumber(value)
    return Public(value) and type(value) == "number" and value > 0
end

local function UnitInterval(value)
    return Public(value) and type(value) == "number" and value >= 0 and value <= 1
end

-- Blizzard's world-map tile closest to the player gives the static canvas real
-- zone artwork. No second Minimap widget, reparenting or continuous map query.
-- The C_Map calls take plain arguments ("player" and a validated map ID) and
-- report missing data through nil or empty returns, which are checked below.
local function ReadTerrain()
    local api = _G.C_Map
    if type(api) ~= "table" or type(api.GetBestMapForUnit) ~= "function"
        or type(api.GetMapArtLayers) ~= "function" or type(api.GetMapArtLayerTextures) ~= "function"
        or type(api.GetPlayerMapPosition) ~= "function" then
        return nil
    end
    local mapID = api.GetBestMapForUnit("player")
    if not PositiveNumber(mapID) then return nil end
    local layers = api.GetMapArtLayers(mapID)
    if not Public(layers) or type(layers) ~= "table" then return nil end
    local layer = layers[1]
    if not Public(layer) or type(layer) ~= "table" then return nil end
    local layerWidth, layerHeight = layer.layerWidth, layer.layerHeight
    local tileWidth, tileHeight = layer.tileWidth, layer.tileHeight
    if not (PositiveNumber(layerWidth) and PositiveNumber(layerHeight)
        and PositiveNumber(tileWidth) and PositiveNumber(tileHeight)) then
        return nil
    end
    local files = api.GetMapArtLayerTextures(mapID, 1)
    if not Public(files) or type(files) ~= "table" then return nil end
    local position = api.GetPlayerMapPosition(mapID, "player")
    if not Public(position) or type(position) ~= "table" or type(position.GetXY) ~= "function" then return nil end
    local u, v = position:GetXY()
    if not (UnitInterval(u) and UnitInterval(v)) then return nil end
    return {
        files = files,
        width = layerWidth,
        height = layerHeight,
        tileWidth = tileWidth,
        tileHeight = tileHeight,
        x = u * layerWidth,
        y = v * layerHeight,
    }
end

local function PlayerClassRGB(r, g, b)
    if type(_G.UnitClass) ~= "function" or not S.ClassRGB then return r, g, b end
    local _, token = _G.UnitClass("player")
    if not Public(token) then return r, g, b end
    local cr, cg, cb = S.ClassRGB(token)
    if cr then return cr, cg, cb end
    return r, g, b
end

-- The map clip: fallback artwork, 3x3 terrain tiles, shape mask and arrow.
local function BuildMap(art, canvas, canvasLevel)
    local map = CreateFrame("Button", nil, canvas)
    map:SetFrameLevel(canvasLevel + 2)
    map:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    map:RegisterForClicks("LeftButtonUp")
    map:SetSize(190, 190)
    art.map = map

    local clip = CreateFrame("Frame", nil, map)
    clip:SetFrameLevel(canvasLevel + 3)
    clip:EnableMouse(false)
    clip:SetAllPoints(map)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    art.clip = clip

    local fallback = Texture(clip, "BACKGROUND", -8)
    fallback:SetAllPoints(clip)
    fallback:SetTexture(FALLBACK_ART)
    art.fallback = fallback
    local tiles = {}
    for i = 1, 9 do tiles[i] = Texture(clip, "BACKGROUND", -7) end
    art.tiles = tiles

    if type(clip.CreateMaskTexture) == "function" then
        local mask = clip:CreateMaskTexture()
        if mask and type(mask.SetTexture) == "function" then
            mask:SetAllPoints(clip)
            for i = 1, #tiles do
                if tiles[i].AddMaskTexture then tiles[i]:AddMaskTexture(mask) end
            end
            if fallback.AddMaskTexture then fallback:AddMaskTexture(mask) end
            art.mask = mask
        end
    end

    local arrow = Texture(clip, "OVERLAY", 2)
    arrow:SetPoint("CENTER", clip, "CENTER")
    arrow:SetSize(19, 19)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    art.arrow = arrow
end

-- Square border edges or a round disc, plus three shadow rings of each.
local function BuildFrame(art, canvas)
    art.edges = EdgeSet(canvas, "BORDER", 0)
    art.disc = Texture(canvas, "BACKGROUND", -2)
    art.disc:SetTexture(CIRCLE)
    art.disc:SetPoint("CENTER", art.map, "CENTER")
    art.shadows = {}
    for step = 1, 3 do
        local ring = { edges = EdgeSet(canvas, "BACKGROUND", -8 + step) }
        ring.disc = Texture(canvas, "BACKGROUND", -8 + step)
        ring.disc:SetTexture(CIRCLE)
        ring.disc:SetPoint("CENTER", art.map, "CENTER")
        art.shadows[step] = ring
    end
end

local function PaintTerrain(art, width, showMap)
    local terrain, tiles, clip = art.terrain, art.tiles, art.clip
    if not (terrain and showMap) then
        for i = 1, #tiles do tiles[i]:Hide() end
        art.fallback:SetShown(showMap)
        return
    end
    local pixelScale = width / TERRAIN_SPAN
    local columns = math.ceil(terrain.width / terrain.tileWidth)
    local rows = math.ceil(terrain.height / terrain.tileHeight)
    local baseCol = math.floor(terrain.x / terrain.tileWidth) + 1
    local baseRow = math.floor(terrain.y / terrain.tileHeight) + 1
    local index = 0
    for row = baseRow - 1, baseRow + 1 do
        for col = baseCol - 1, baseCol + 1 do
            index = index + 1
            local tile = tiles[index]
            local file = col >= 1 and col <= columns and row >= 1 and row <= rows
                and terrain.files[(row - 1) * columns + col]
            if Public(file) and (type(file) == "number" or type(file) == "string") then
                tile:SetTexture(file)
                tile:ClearAllPoints()
                tile:SetPoint("TOPLEFT", clip, "CENTER",
                    ((col - 1) * terrain.tileWidth - terrain.x) * pixelScale,
                    (terrain.y - (row - 1) * terrain.tileHeight) * pixelScale)
                tile:SetSize(terrain.tileWidth * pixelScale, terrain.tileHeight * pixelScale)
                tile:Show()
            else
                tile:Hide()
            end
        end
    end
    art.fallback:Hide()
end

-- Returns the scaled border width the shadow rings start from.
local function PaintBorder(art, config, scale, width, height, round, shown)
    local r, g, b = P.RGB(config.borderColor)
    if config.borderClassColor then r, g, b = PlayerClassRGB(r, g, b) end
    local border = (tonumber(config.borderSize) or 0) * scale
    local alpha = (tonumber(config.borderAlpha) or 0) / 100
    PaintEdges(art.edges, art.map, 0, border, r, g, b, alpha, shown and not round)
    art.disc:SetSize(width + border * 2, height + border * 2)
    art.disc:SetVertexColor(r, g, b, alpha)
    art.disc:SetShown(shown and round and border > 0 and alpha > 0)
    return border
end

local function PaintShadow(art, config, scale, width, height, round, border, shown)
    local r, g, b = P.RGB(config.shadowColor)
    local shadow = (tonumber(config.shadowSize) or 0) * scale
    local baseAlpha = (tonumber(config.shadowAlpha) or 0) / 100
    for step = 1, 3 do
        local ring = art.shadows[step]
        local inner = border + shadow * (step - 1) / 3
        local outer = border + shadow * step / 3
        local alpha = baseAlpha * SHADOW_STRENGTH[step]
        local visible = shown and shadow > 0 and alpha > 0
        PaintEdges(ring.edges, art.map, inner, outer, r, g, b, alpha, visible and not round)
        ring.disc:SetSize(width + outer * 2, height + outer * 2)
        ring.disc:SetVertexColor(r, g, b, alpha)
        ring.disc:SetShown(visible and round)
    end
end

local Art = {}
Art.__index = Art

-- layerOn(key): whether a preview layer (map, border, shadow, ...) is shown.
function Art:Paint(config, scale, layerOn)
    local size = math.max(100, tonumber(config.size) or 190)
    local shape = tonumber(config.shape) or 1
    local round = shape == 2
    local width = math.floor(size * scale + 0.5)
    local height = shape == 3 and math.floor(width * 2 / 3 + 0.5) or width
    self.map:SetSize(width, height)
    self.width, self.height, self.scale = width, height, scale

    local showMap = layerOn("map")
    self.clip:SetShown(showMap)
    if self.mask then self.mask:SetTexture(round and CIRCLE or SQUARE_MASK) end
    PaintTerrain(self, width, showMap)
    self.arrow:SetShown(showMap)

    local border = PaintBorder(self, config, scale, width, height, round, layerOn("border"))
    PaintShadow(self, config, scale, width, height, round, border, layerOn("shadow"))
    if self.style then self.style:Paint(config, scale, layerOn, false) end
end

function P.CreateMinimapPreviewArt(canvas)
    local art = setmetatable({}, Art)
    local canvasLevel = tonumber((canvas:GetFrameLevel())) or 0
    BuildMap(art, canvas, canvasLevel)
    BuildFrame(art, canvas)
    art.terrain = ReadTerrain()
    art.terrainAvailable = art.terrain ~= nil
    if Suite.MinimapStyle then
        art.style = Suite.MinimapStyle.Create(canvas, canvasLevel + 1, canvasLevel + 4)
    end
    return art
end
