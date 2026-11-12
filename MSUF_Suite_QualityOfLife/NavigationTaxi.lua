local _, Private = ...
local NS, Suite, Navigation = Private.NS, Private.Suite, Private.Navigation
-- The map pin and the focused quest on the old flight map (TaxiFrame), drawn
-- under the flight points so a point at the destination stays clickable.
-- That map has no UI map. Its scale is measured from the flight points: each
-- has a place on the taxi map (TaxiNodePosition) and one on a UI map
-- (C_TaxiMap.GetAllTaxiNodes), and both follow the world linearly.
local SIZE, MAX_ERROR, MAX_NODES = 26, .03, 256
local WHITE, ROUND = "Interface\\Buttons\\WHITE8X8", "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local markers = {}
-- fit: nil until measured for this visit, false when the map cannot be measured.
local open, fit = false, nil

local function Enter(marker)
    if not marker.title or NS.Safety.IsForbidden(GameTooltip) then return end
    GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
    GameTooltip:SetText(marker.title)
    if marker.info then GameTooltip:AddLine(marker.info, .75, .85, 1) end
    GameTooltip:Show()
end
local function Leave(marker)
    if not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:IsOwned(marker) then GameTooltip:Hide() end
end

local function Acquire(key, host)
    local marker = markers[key]
    if marker then return marker end
    marker = Suite.CreateFrame("Frame", nil, host)
    marker:SetSize(SIZE, SIZE)
    -- The flight points are one level above their map.
    marker:SetFrameLevel(host:GetFrameLevel())
    marker.shade = Suite.CreateTexture(marker, nil, "BACKGROUND")
    marker.shade:SetPoint("TOPLEFT", -2, 2)
    marker.shade:SetPoint("BOTTOMRIGHT", 2, -2)
    marker.shade:SetVertexColor(0, 0, 0, .7)
    marker.icon = Suite.CreateTexture(marker, nil, "ARTWORK")
    marker.icon:SetAllPoints()
    marker:EnableMouse(true)
    marker:SetMouseClickEnabled(false)
    marker:SetScript("OnEnter", Enter)
    marker:SetScript("OnLeave", Leave)
    markers[key] = marker
    return marker
end

local function Release(key)
    local marker = markers[key]
    if marker then marker.title = nil marker:Hide() end
end

-- One taxi axis as a line over the same map axis (least squares). A flight
-- point Blizzard moved by hand is left out; a map that does not fit is refused.
local function Line(samples, from, to)
    local left, skipped = #samples, {}
    while left >= 2 do
        local sp, st, spp, spt = 0, 0, 0, 0
        for index, sample in ipairs(samples) do
            if not skipped[index] then
                local p, t = sample[from], sample[to]
                sp, st, spp, spt = sp + p, st + t, spp + p * p, spt + p * t
            end
        end
        local spread = left * spp - sp * sp
        if spread < .0001 then return nil end
        local scale = (left * spt - sp * st) / spread
        local offset = (st - scale * sp) / left
        local worst, worstError = nil, MAX_ERROR
        for index, sample in ipairs(samples) do
            local miss = skipped[index] and 0 or math.abs(scale * sample[from] + offset - sample[to])
            if miss > worstError then worst, worstError = index, miss end
        end
        if not worst then return scale, offset end
        if left <= 3 or (left - 1) * 4 < #samples * 3 then return nil end
        skipped[worst], left = true, left - 1
    end
end

local function Samples(map)
    local entries = C_TaxiMap.GetAllTaxiNodes(map)
    if not Suite.Public(entries) or type(entries) ~= "table" then return nil end
    local samples = {}
    for index = 1, math.min(#entries, MAX_NODES) do
        local entry = entries[index]
        if Suite.Public(entry) and type(entry) == "table" then
            local slot, position, transition = entry.slotIndex, entry.position, entry.isMapLayerTransition
            if Suite.Finite(slot) and slot > 0 and Suite.Public(position) and position
                and Suite.Public(transition) and not transition then
                local x, y = position.x, position.y
                local taxiX, taxiY = TaxiNodePosition(slot)
                if Suite.Finite(x) and Suite.Finite(y) and Suite.Finite(taxiX) and Suite.Finite(taxiY) then
                    samples[#samples + 1] = { x, y, taxiX, taxiY }
                end
            end
        end
    end
    return samples
end

local function Measure(map)
    local samples = Samples(map)
    if not samples then return nil end
    local scaleX, offsetX = Line(samples, 1, 3)
    local scaleY, offsetY = Line(samples, 2, 4)
    if not scaleX or not scaleY then return nil end
    -- The world this map shows: a destination elsewhere has no place here.
    local instance = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(.5, .5))
    if not Suite.Finite(instance) then return nil end
    return { map = map, instance = instance, scaleX = scaleX, offsetX = offsetX, scaleY = scaleY, offsetY = offsetY }
end

local function Continent(map)
    for _ = 1, 8 do
        local info = C_Map.GetMapInfo(map)
        if not Suite.Public(info) or type(info) ~= "table" then return nil end
        local kind, parent = info.mapType, info.parentMapID
        if not Suite.Finite(kind) then return nil end
        if kind <= Enum.UIMapType.Continent then return kind == Enum.UIMapType.Continent and map or nil end
        if not Suite.Finite(parent) or parent < 1 then return nil end
        map = parent
    end
end

-- The continent holds every flight point of the taxi map; the player's own
-- map is the fallback where the client measures only that one.
local function MeasureHere()
    local map = C_Map.GetBestMapForUnit("player")
    if not Suite.Finite(map) or map < 1 then return false end
    local continent = Continent(map)
    return continent and Measure(continent) or Measure(map) or false
end

-- A map position as a taxi map position (0-1, top left origin).
local function OnTaxiMap(map, x, y)
    if map ~= fit.map then
        local instance, world = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
        if not Suite.Finite(instance) or instance ~= fit.instance or not Suite.Public(world) or not world then return nil end
        local _, position = C_Map.GetMapPosFromWorldPos(instance, world, fit.map)
        if not Suite.Public(position) or not position then return nil end
        x, y = position.x, position.y
        if not Suite.Finite(x) or not Suite.Finite(y) then return nil end
    end
    x, y = fit.scaleX * x + fit.offsetX, fit.scaleY * y + fit.offsetY
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function Place(key, host, config, map, x, y, title, info, color)
    local width, height = TAXI_MAP_WIDTH, TAXI_MAP_HEIGHT
    if Suite.Finite(width) and Suite.Finite(height) then x, y = OnTaxiMap(map, x, y) else x = nil end
    if not x then
        Release(key)
        return
    end
    local marker = Acquire(key, host)
    local round = config.shape == 2
    marker.shade:SetTexture(round and ROUND or WHITE)
    marker.shade:SetRotation(round and 0 or math.pi / 4)
    marker.icon:SetTexture(round and ROUND or WHITE)
    marker.icon:SetRotation(round and 0 or math.pi / 4)
    marker.icon:SetVertexColor(Suite.RGB(color))
    marker.title, marker.info = title, info
    marker:ClearAllPoints()
    -- TaxiFrame_OnShow places its flight points the same way.
    marker:SetPoint("CENTER", host, "BOTTOMLEFT", x * width, (1 - y) * height)
    marker:Show()
end

local function PinPoint()
    local point = C_Map.GetUserWaypoint()
    if not Suite.Public(point) or not point then return nil end
    local map, position = point.uiMapID, point.position
    if not Suite.Finite(map) or not Suite.Public(position) or not position then return nil end
    local x, y = position.x, position.y
    if not Suite.Finite(x) or not Suite.Finite(y) then return nil end
    local selected = Navigation.IsSelectedPoint(point) and Navigation.selected or nil
    return map, x, y, selected and selected.name or Suite.Text("Map waypoint")
end

local function PlacePin(host, config)
    local map, x, y, title = PinPoint()
    if not map then
        Release("pin")
        return
    end
    Place("pin", host, config, map, x, y, title, nil, config.pinColor)
end

local function PlaceQuest(owner, host, config)
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    local point = Suite.Finite(id) and id > 0 and Navigation.QuestPoint(id) or nil
    if not point then
        Release("quest")
        return
    end
    -- The colour of the world marker while it follows this quest.
    local model = owner.model
    local color = model.source == "quest" and model.identity == id and model.color or config.questColor
    Place("quest", host, config, point.map, point.x, point.y, point.name, Suite.Text("Focused quest"), color)
end

function Navigation.RefreshTaxi(owner)
    local config, host = owner.config, _G.TaxiRouteMap
    local shown = open and config.flightMapPins and host and not NS.Safety.IsForbidden(host) and host:IsVisible()
    if shown and fit == nil then fit = MeasureHere() end
    if not shown or not fit then
        Release("pin")
        Release("quest")
        return
    end
    PlacePin(host, config)
    PlaceQuest(owner, host, config)
end

-- The taxi frame is laid out in the same event: draw one frame later.
local function Opened(owner)
    open, fit = true, nil
    owner.taxiRefresh:Request()
end

local function Closed(owner)
    open, fit = false, nil
    Navigation.RefreshTaxi(owner)
end

function Navigation.EnableTaxi(owner)
    owner.taxiRefresh = owner.context:Coalesce(0, Navigation.RefreshTaxi)
    owner.context:Event("TAXIMAP_OPENED", Opened, true)
    owner.context:Event("TAXIMAP_CLOSED", Closed, true)
end

function Navigation.DisableTaxi(owner)
    Closed(owner)
end
