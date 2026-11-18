local _, private = ...
local S = private.Suite
local Map = {}
Map.__index = Map
private.NavigationHUDMap = Map

local MASK = "Interface\\AddOns\\MSUF_Suite\\Media\\MapOverlayMask.tga"
local MAP_ASPECT = 2 / 3
local RANGES = { .52, .73, 1 }
local RAD = math.pi / 180
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local Finite, Public = S.Finite, S.Public

local function Positive(value)
    return Finite(value) and value > 0
end

local function Fraction(value)
    return Finite(value) and value >= 0 and value <= 1
end

local function Coordinates(vector)
    if not Public(vector) or type(vector) ~= "table" then return end
    local x, y = vector.x, vector.y
    if Fraction(x) and Fraction(y) then return x, y end
end

function Map.New(parent)
    local frame = S.CreateFrame("Frame", nil, parent)
    frame:SetClipsChildren(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:Hide()
    local plane = S.CreateFrame("Frame", nil, frame)
    plane:EnableMouse(false)
    local mask = frame:CreateMaskTexture()
    mask:SetAllPoints(frame)
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    local pin = S.CreateTexture(plane, nil, "OVERLAY")
    pin:SetSize(15, 15)
    pin:SetAtlas("Waypoint-MapPin-Untracked")
    pin:SetDesaturated(true)
    pin:Hide()

    local indicator = S.CreateFrame("Frame", nil, frame)
    indicator:SetAllPoints(frame)
    indicator:SetFrameLevel(plane:GetFrameLevel() + 1)
    indicator:EnableMouse(false)
    local arrow = S.CreateTexture(indicator, nil, "OVERLAY")
    arrow:SetPoint("CENTER", indicator, "CENTER")
    arrow:SetSize(19, 19)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetDesaturated(true)
    local dot = S.CreateTexture(indicator, nil, "OVERLAY")
    dot:SetPoint("CENTER", indicator, "CENTER")
    dot:SetSize(5, 5)
    dot:SetColorTexture(.95, .97, 1, 1)
    arrow:Hide()
    dot:Hide()

    local backdrop = S.CreateTexture(frame, nil, "BACKGROUND")
    backdrop:SetAllPoints(frame)
    backdrop:SetColorTexture(.04, .07, .11, .8)
    backdrop:AddMaskTexture(mask)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("CENTER", frame, "CENTER")
    title:SetText(S.Text("Map overlay"))
    title:SetTextColor(.95, .97, 1)
    backdrop:Hide()
    title:Hide()
    return setmetatable({ frame = frame, plane = plane, mask = mask, pin = pin, arrow = arrow,
        dot = dot, backdrop = backdrop, title = title, tiles = {}, heading = false }, Map)
end

local function ReadArt(mapID, artID)
    local layers = C_Map.GetMapArtLayers(mapID)
    if not Public(layers) or type(layers) ~= "table" then return end
    local layer = layers[1]
    if not Public(layer) or type(layer) ~= "table" then return end
    local width, height, tileWidth, tileHeight = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
    if not (Positive(width) and Positive(height) and Positive(tileWidth) and Positive(tileHeight)) then return end
    local textures = C_Map.GetMapArtLayerTextures(mapID, 1)
    if not Public(textures) or type(textures) ~= "table" then return end
    return {
        mapID = mapID, artID = artID, textures = textures, width = width, height = height, tileWidth = tileWidth,
        tileHeight = tileHeight, columns = ceil(width / tileWidth), rows = ceil(height / tileHeight),
    }
end

function Map:Project()
    local art = self.art
    -- A window narrower than two tiles on either axis intersects at most
    -- three columns and three rows, including partially filled edge tiles.
    local span = min(art.width, art.height / MAP_ASPECT, art.tileWidth * 1.9, art.tileHeight * 1.9 / MAP_ASPECT)
    local scale = self.width / (span * RANGES[self.zoom])
    self.scale, self.halfX, self.halfY = scale, self.width / (2 * scale), self.height / (2 * scale)
    self.plane:SetSize(art.width * scale, art.height * scale)
    self.projection = (self.projection or 0) + 1
    self.firstCol, self.offsetX, self.offsetY = nil, nil, nil
    self.pinX, self.pinY = nil, nil
end

function Map:Layout(config, pixelScale)
    local width, zoom = config.mapWidth, config.mapZoom
    if self.width ~= width or self.zoom ~= zoom then
        self.width, self.height, self.zoom = width, width * MAP_ASPECT, zoom
        self.frame:SetSize(width, self.height)
        if self.art then self:Project() end
    end
    self.pixelScale = pixelScale
    self.frame:SetPoint("CENTER", UIParent, "CENTER", config.mapX, config.mapY)
    local opacity = config.mapOpacity / 100
    if self.opacity ~= opacity then
        self.opacity = opacity
        for _, slot in pairs(self.tiles) do slot.texture:SetAlpha(opacity) end
    end
    self.pin:SetVertexColor(S.RGB(config.accentColor))
    S.SetFont(self.title, S.GlobalFontPath(), 14, "OUTLINE")
end

function Map:SelectArt()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not Positive(mapID) then return false end
    local artID = C_Map.GetMapArtID(mapID)
    if not Finite(artID) then artID = nil end
    local art = self.art
    if art and art.mapID == mapID and art.artID == artID then return true end
    self.art = ReadArt(mapID, artID)
    if not self.art then return false end
    self:Project()
    return true, true
end

function Map:UpdateWaypoint(enabled)
    local art = self.art
    local point = art and enabled and C_Map.GetUserWaypoint()
    if Public(point) and type(point) == "table" and Finite(point.uiMapID) and point.uiMapID == art.mapID then
        local x, y = Coordinates(point.position)
        if x then
            if self.pinX ~= x or self.pinY ~= y then
                self.pinX, self.pinY = x, y
                self.pin:SetPoint("CENTER", self.plane, "TOPLEFT", x * art.width * self.scale, -y * art.height * self.scale)
            end
            self.pin:Show()
            return
        end
    end
    self.pin:Hide()
end

local function TileSlot(self, index)
    local slot = self.tiles[index]
    if slot then return slot end
    local texture = S.CreateTexture(self.plane, nil, "ARTWORK")
    texture:SetDesaturated(true)
    texture:SetVertexColor(.83, .88, .93)
    texture:SetAlpha(self.opacity)
    texture:AddMaskTexture(self.mask)
    texture:Hide()
    slot = { texture = texture }
    self.tiles[index] = slot
    return slot
end

local function PaintTile(self, column, row, art, file)
    -- Keep existing tiles in the same slots across a row/column crossing.
    local slot = TileSlot(self, ((row - 1) % 3) * 3 + (column - 1) % 3 + 1)
    local texture = slot.texture
    if slot.file ~= file then
        texture:SetTexture(file, nil, nil, "TRILINEAR")
        slot.file = file
    end
    if slot.projection ~= self.projection or slot.column ~= column or slot.row ~= row then
        local left, top = (column - 1) * art.tileWidth, (row - 1) * art.tileHeight
        local width = min(art.tileWidth, art.width - left)
        local height = min(art.tileHeight, art.height - top)
        texture:SetPoint("TOPLEFT", self.plane, "TOPLEFT", left * self.scale, -top * self.scale)
        texture:SetSize(width * self.scale, height * self.scale)
        texture:SetTexCoord(0, width / art.tileWidth, 0, height / art.tileHeight)
        slot.projection, slot.column, slot.row = self.projection, column, row
    end
    if not slot.visible then texture:Show() end
    slot.visible, slot.generation = true, self.generation
end

function Map:PaintTiles(x, y)
    local art = self.art
    local firstCol = max(1, floor((x - self.halfX) / art.tileWidth) + 1)
    local lastCol = min(art.columns, ceil((x + self.halfX) / art.tileWidth))
    local firstRow = max(1, floor((y - self.halfY) / art.tileHeight) + 1)
    local lastRow = min(art.rows, ceil((y + self.halfY) / art.tileHeight))
    if self.firstCol == firstCol and self.lastCol == lastCol and self.firstRow == firstRow and self.lastRow == lastRow then
        return self.covered
    end
    self.firstCol, self.lastCol, self.firstRow, self.lastRow = firstCol, lastCol, firstRow, lastRow
    self.generation = (self.generation or 0) + 1
    local covered = false
    for row = firstRow, lastRow do
        for column = firstCol, lastCol do
            local file = art.textures[(row - 1) * art.columns + column]
            if Positive(file) then
                PaintTile(self, column, row, art, file)
                covered = true
            end
        end
    end
    for _, slot in pairs(self.tiles) do
        if slot.visible and slot.generation ~= self.generation then
            slot.texture:Hide()
            slot.visible = false
        end
    end
    self.covered = covered
    return covered
end

function Map:Sample()
    local art = self.art
    local x, y = Coordinates(C_Map.GetPlayerMapPosition(art.mapID, "player"))
    if not x then return false end
    x, y = x * art.width, y * art.height
    local scale, pixels = self.scale, self.pixelScale
    local offsetX = floor(-x * scale * pixels + .5) / pixels
    local offsetY = floor(y * scale * pixels + .5) / pixels
    if self.offsetX == offsetX and self.offsetY == offsetY then return self.covered end
    if not self:PaintTiles(-offsetX / scale, offsetY / scale) then return false end
    self.offsetX, self.offsetY = offsetX, offsetY
    self.plane:SetPoint("TOPLEFT", self.frame, "CENTER", offsetX, offsetY)
    return true
end

function Map:SetHeading(bearing)
    if self.heading == bearing then return end
    self.heading = bearing
    if bearing == nil then
        self.arrow:Hide()
        self.dot:Show()
    else
        self.arrow:SetRotation(-bearing * RAD)
        self.dot:Hide()
        self.arrow:Show()
    end
end

function Map:Show(preview)
    self.plane:SetShown(not preview)
    self.backdrop:SetShown(preview)
    self.title:SetShown(preview)
    self.arrow:SetShown(not preview and self.heading ~= nil)
    self.dot:SetShown(not preview and self.heading == nil)
    self.frame:Show()
end

function Map:Release()
    self.frame:Hide()
    self.art, self.firstCol, self.offsetX, self.offsetY = nil, nil, nil, nil
    for _, slot in pairs(self.tiles) do
        slot.texture:SetTexture(nil)
        slot.texture:Hide()
        slot.file, slot.visible = nil, false
    end
end
