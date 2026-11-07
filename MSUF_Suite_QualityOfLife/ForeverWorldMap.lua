local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end
local Data, Pins, Labels, Locations = P.ForeverMapData, P.ForeverMapPins, P.ForeverMapLabels, P.ForeverMapLocations
local M = { mapNames = {}, areaNames = {}, titles = {}, rects = {} }
local Provider = {}
local FLIGHT, FIRST_TRANSPORT, LAST_TRANSPORT, ROAD, APPROACH, ENTRANCE = 1, 2, 4, 6, 7, 8
local KIND_TEXT = { "Flight point", "Boat", "Zeppelin", "Skycutter", [APPROACH] = "Dungeon approach" }
local IN_COMBAT = { inCombat = true }

local function MapName(mapID)
    local name = M.mapNames[mapID]
    if name == nil then
        local info = C_Map.GetMapInfo(mapID)
        name = S.Public(info) and type(info) == "table" and canaccesstable(info) and S.PublicText(info.name) or false
        M.mapNames[mapID] = name
    end
    return name
end

local function AreaName(areaID)
    local name = M.areaNames[areaID]
    if name == nil then
        name = areaID > 0 and S.PublicText(C_Map.GetAreaInfo(areaID)) or false
        M.areaNames[areaID] = name
    end
    return name
end

local function Title(record)
    local title = M.titles[record]
    if title then return title end
    local kind = record[4]
    local targets = record.destinations
    local destination = targets and MapName(targets[1])
    local transport = kind >= FIRST_TRANSPORT and kind <= LAST_TRANSPORT
    local place = transport and MapName(record[1]) or AreaName(record[5]) or MapName(record[1])
    place = place or S.Text("Travel marker")
    if kind == ROAD then
        title = S.Text("Road to %s"):format(destination or place)
    elseif destination then
        title = S.Text("%s to %s"):format(S.Text(KIND_TEXT[kind]), destination)
    else
        title = S.Text("%s: %s"):format(S.Text(KIND_TEXT[kind]), place)
    end
    if targets and #targets > 1 then
        record.tooltipLines = {}
        for i = 2, #targets do
            local target = MapName(targets[i])
            if target then
                local line = kind == ROAD and S.Text("Road to %s"):format(target)
                    or S.Text("%s to %s"):format(S.Text(KIND_TEXT[kind]), target)
                record.tooltipLines[#record.tooltipLines + 1] = line
            end
        end
    end
    M.titles[record] = title
    return title
end

local function Project(record, shownMap, mapType)
    if record[1] == shownMap then return record[2], record[3] end
    if mapType == Enum.UIMapType.Zone and (shownMap < 1453 or shownMap > 1458) then return end
    local rect = M.rects[record[1]]
    if rect == nil then
        local left, right, top, bottom = C_Map.GetMapRectOnMap(record[1], shownMap)
        if S.Finite(left) and S.Finite(right) and S.Finite(top) and S.Finite(bottom) then
            rect = { left, right - left, top, bottom - top }
        else
            rect = false
        end
        M.rects[record[1]] = rect
    end
    if not rect then return end
    local x, y = rect[1] + record[2] * rect[2], rect[3] + record[3] * rect[4]
    if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

local function Wanted(record, mapType, faction)
    local kind, config = record[4], M.config
    if config.onlyOwnFaction and record[6] ~= 3 and record[6] ~= faction then return false end
    if kind == FLIGHT then return config.flightPoints and mapType == Enum.UIMapType.Zone end
    if kind == ROAD then return config.zoneRoutes and mapType == Enum.UIMapType.Zone end
    if kind == APPROACH then return config.dungeonEntrances end
    return config.transports
end

local function NativeEntrances(map, mapID)
    if not M.config.dungeonEntrances then return false end
    local entries = C_EncounterJournal.GetDungeonEntrancesForMap(mapID)
    if not S.Public(entries) or type(entries) ~= "table" or #entries == 0 then return false end
    -- Blizzard already paints these exact records when its map filter is on.
    if GetCVarBool("showDungeonEntrancesOnMap") then return true end
    for i = 1, #entries do
        local entry = entries[i]
        if S.Public(entry) and type(entry) == "table" and canaccesstable(entry) then
            local position = entry.position
            local name = S.PublicText(entry.name)
            if S.Public(position) and position and name then
                local x, y = position:GetXY()
                if S.Finite(x) and S.Finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    local record = { mapID, x, y }
                    map:AcquirePin(Pins.template, M, record, x, y, name, ENTRANCE)
                end
            end
        end
    end
    return true
end

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(Pins.template)
end

function Provider:RefreshAllData()
    local map = self:GetMap()
    if not M.active or not map:IsShown() then return end
    self:RemoveAllData()
    local mapID = map:GetMapID()
    local info = S.Finite(mapID) and C_Map.GetMapInfo(mapID)
    if not S.Public(info) or type(info) ~= "table" or not canaccesstable(info) then return end
    local mapType = info.mapType
    if not S.Finite(mapType) then return end
    if M.projectedMap ~= mapID then
        M.projectedMap = mapID
        wipe(M.rects)
    end
    local factionName = S.PublicText(UnitFactionGroup("player"))
    local faction = factionName == "Alliance" and 1 or factionName == "Horde" and 2 or 3
    local entrances = NativeEntrances(map, mapID)
    local nativeFlights = C_TaxiMap.ShouldMapShowTaxiNodes(mapID)
    nativeFlights = S.Public(nativeFlights) and nativeFlights == true
    M.records = M.records or Locations.Build(Data.pins)
    for i = 1, #M.records do
        local record = M.records[i]
        local nativeFlight = record[4] == FLIGHT and nativeFlights and (record[6] == 3 or record[6] == faction)
        if Wanted(record, mapType, faction) and not (record[4] == APPROACH and entrances)
            and not nativeFlight then
            local x, y = Project(record, mapID, mapType)
            if x then map:AcquirePin(Pins.template, M, record, x, y, Title(record), record[4]) end
        end
    end
    Labels.Attach(M)
end

function Provider:OnShow()
    self:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
    self:RegisterEvent("PLAYER_LEVEL_UP")
    self:RegisterEvent("CVAR_UPDATE")
    Labels.Attach(M)
end

function Provider:OnHide()
    self:UnregisterEvent("TAXI_NODE_STATUS_CHANGED")
    self:UnregisterEvent("PLAYER_LEVEL_UP")
    self:UnregisterEvent("CVAR_UPDATE")
    if M.label then M.label:Hide() end
end

function Provider:OnEvent(event, name)
    if event == "CVAR_UPDATE" and (not S.Public(name)
        or name ~= "showDungeonEntrancesOnMap" and name ~= "showdungeonentrancesonmap") then return end
    if event == "PLAYER_LEVEL_UP" then Labels.Refresh(M) else self:RefreshAllData() end
end

function Provider:OnRemoved(map)
    self:OnHide()
    MapCanvasDataProviderMixin.OnRemoved(self, map)
end

local function Attach(self)
    -- Blizzard_WorldMap's Mainline TOC loads the frame and requires
    -- Blizzard_MapCanvas on Forever, including its provider and pin mixins.
    if self.map or not NS.Client.IsAddOnLoaded("Blizzard_WorldMap") then return end
    Pins.Prepare()
    self.provider = self.provider or CreateFromMixins(MapCanvasDataProviderMixin, Provider)
    self.map = WorldMapFrame
    self.map:AddDataProvider(self.provider)
    self.context:RemoveEvent("ADDON_LOADED")
    -- AddDataProvider only calls OnAdded, including when the map is already open.
    if self.map:IsShown() then
        self.provider:RefreshAllData()
        self.provider:OnShow()
    end
end

local function MapLoaded(self, _, addon)
    if addon == "Blizzard_WorldMap" then Attach(self) end
end

function M:Enable()
    Attach(self)
    if not self.map then self.context:Event("ADDON_LOADED", MapLoaded, IN_COMBAT) end
end

function M:Refresh()
    if not self.map then return Attach(self) end
    self.labelRaw = nil
    self.provider:RefreshAllData()
    if not self.config.zoneLevels and self.label then self.label:Hide() end
end

function M:Disable()
    if self.map then self.map:RemoveDataProvider(self.provider) end
    if self.label then self.label:Hide() end
    self.map, self.labelRaw = nil, nil
end

S.Install("foreverWorldMap", M)
