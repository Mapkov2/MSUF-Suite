local _, P = ...
local Suite, S = P.Suite, P.S
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\Circle.tga"
local MASKS = { "Interface\\ChatFrame\\ChatFrameBackground", CIRCLE }
local STRENGTH = { 0.45, 0.25, 0.12 }

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

local function PaintEdges(edges, map, width, height, inner, outer, r, g, b, alpha, shown)
    local band = outer - inner
    local top, bottom, left, right = unpack(edges)
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
    for i = 1, 4 do
        edges[i]:SetColorTexture(r, g, b, alpha)
        edges[i]:SetShown(shown and band > 0 and alpha > 0)
    end
end

-- Blizzard's world-map tile closest to the player gives the static canvas real
-- zone artwork. No second Minimap widget, reparenting or continuous map query.
local function ReadTerrain()
    local api = _G.C_Map
    if type(api) ~= "table" or type(api.GetBestMapForUnit) ~= "function"
        or type(api.GetMapArtLayers) ~= "function" or type(api.GetMapArtLayerTextures) ~= "function"
        or type(api.GetPlayerMapPosition) ~= "function" then return nil end
    local ok, mapID = pcall(api.GetBestMapForUnit, "player")
    if not ok or not Public(mapID) or type(mapID) ~= "number" then return nil end
    local good, layers = pcall(api.GetMapArtLayers, mapID)
    if not good or not Public(layers) or type(layers) ~= "table" then return nil end
    local layer = layers[1]
    if not Public(layer) or type(layer) ~= "table" then return nil end
    local layerWidth, layerHeight = layer.layerWidth, layer.layerHeight
    local tileWidth, tileHeight = layer.tileWidth, layer.tileHeight
    if not Public(layerWidth) or not Public(layerHeight) or not Public(tileWidth) or not Public(tileHeight)
        or type(layerWidth) ~= "number" or type(layerHeight) ~= "number"
        or type(tileWidth) ~= "number" or type(tileHeight) ~= "number"
        or layerWidth <= 0 or layerHeight <= 0 or tileWidth <= 0 or tileHeight <= 0 then return nil end
    local got, files = pcall(api.GetMapArtLayerTextures, mapID, 1)
    if not got or not Public(files) or type(files) ~= "table" then return nil end
    local found, position = pcall(api.GetPlayerMapPosition, mapID, "player")
    if not found or not Public(position) or not position or type(position.GetXY) ~= "function" then return nil end
    local read, u, v = pcall(position.GetXY, position)
    if not read or not Public(u) or not Public(v) or type(u) ~= "number" or type(v) ~= "number"
        or u < 0 or u > 1 or v < 0 or v > 1 then return nil end
    return { files = files, width = layerWidth, height = layerHeight,
        tileWidth = tileWidth, tileHeight = tileHeight, x = u * layerWidth, y = v * layerHeight }
end

function P.CreateMinimapPreviewArt(canvas)
    local art = {}
    local map = CreateFrame("Button", nil, canvas)
    local canvasLevel = tonumber((canvas:GetFrameLevel())) or 0
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
    local fallback = Texture(clip, "BACKGROUND", -8)
    fallback:SetAllPoints(clip)
    fallback:SetTexture("Interface\\AddOns\\MidnightSimpleUnitFrames_Options\\Media\\PreviewBackgrounds\\silvermoon.png")
    art.fallback = fallback
    local tiles = {}
    for i = 1, 9 do tiles[i] = Texture(clip, "BACKGROUND", -7) end
    art.tiles = tiles
    local mask
    if type(clip.CreateMaskTexture) == "function" then
        mask = clip:CreateMaskTexture()
        if mask and type(mask.SetTexture) == "function" then
            mask:SetAllPoints(clip)
            for i = 1, #tiles do if tiles[i].AddMaskTexture then tiles[i]:AddMaskTexture(mask) end end
            if fallback.AddMaskTexture then fallback:AddMaskTexture(mask) end
        else mask = nil end
    end
    art.mask = mask

    local arrow = Texture(clip, "OVERLAY", 2)
    arrow:SetPoint("CENTER", clip, "CENTER")
    arrow:SetSize(19, 19)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    art.arrow = arrow

    local edges = EdgeSet(canvas, "BORDER", 0)
    local disc = Texture(canvas, "BACKGROUND", -2)
    disc:SetTexture(CIRCLE)
    disc:SetPoint("CENTER", map, "CENTER")
    local shadows = {}
    for step = 1, 3 do
        local ring = { edges = EdgeSet(canvas, "BACKGROUND", -8 + step) }
        ring.disc = Texture(canvas, "BACKGROUND", -8 + step)
        ring.disc:SetTexture(CIRCLE)
        ring.disc:SetPoint("CENTER", map, "CENTER")
        shadows[step] = ring
    end
    local terrain = ReadTerrain()
    art.terrainAvailable = terrain ~= nil
    if Suite.MinimapStyle then art.style = Suite.MinimapStyle.Create(canvas, canvasLevel + 1, canvasLevel + 4) end

    function art:Paint(config, scale, layerOn)
        local size = math.max(100, tonumber(config.size) or 190)
        local shape = tonumber(config.shape) or 1
        local width = math.floor(size * scale + 0.5)
        local height = shape == 3 and math.floor(width * 2 / 3 + 0.5) or width
        map:SetSize(width, height)
        self.width, self.height, self.scale = width, height, scale
        local showMap = layerOn("map")
        clip:SetShown(showMap)
        if mask then mask:SetTexture(shape == 2 and MASKS[2] or MASKS[1]) end

        if terrain and showMap then
            local pixelScale = width / 384
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
                    else tile:Hide() end
                end
            end
            fallback:Hide()
        else
            for i = 1, #tiles do tiles[i]:Hide() end
            fallback:SetShown(showMap)
        end
        arrow:SetShown(showMap)

        local r, g, b = P.RGB(config.borderColor)
        if config.borderClassColor and type(_G.UnitClass) == "function" and S.ClassRGB then
            local _, token = _G.UnitClass("player")
            if Public(token) then
                local cr, cg, cb = S.ClassRGB(token)
                if cr then r, g, b = cr, cg, cb end
            end
        end
        local border = (tonumber(config.borderSize) or 0) * scale
        local borderAlpha = (tonumber(config.borderAlpha) or 0) / 100
        PaintEdges(edges, map, width, height, 0, border, r, g, b, borderAlpha,
            layerOn("border") and shape ~= 2)
        disc:SetSize(width + border * 2, height + border * 2)
        disc:SetVertexColor(r, g, b, borderAlpha)
        disc:SetShown(layerOn("border") and shape == 2 and border > 0 and borderAlpha > 0)

        local sr, sg, sb = P.RGB(config.shadowColor)
        local shadow = (tonumber(config.shadowSize) or 0) * scale
        for step = 1, 3 do
            local ring = shadows[step]
            local inner = border + shadow * (step - 1) / 3
            local outer = border + shadow * step / 3
            local alpha = (tonumber(config.shadowAlpha) or 0) / 100 * STRENGTH[step]
            local shown = layerOn("shadow") and shadow > 0 and alpha > 0
            PaintEdges(ring.edges, map, width, height, inner, outer, sr, sg, sb, alpha,
                shown and shape ~= 2)
            ring.disc:SetSize(width + outer * 2, height + outer * 2)
            ring.disc:SetVertexColor(sr, sg, sb, alpha)
            ring.disc:SetShown(shown and shape == 2)
        end
        if self.style then self.style:Paint(config, scale, layerOn, false) end
    end
    return art
end
