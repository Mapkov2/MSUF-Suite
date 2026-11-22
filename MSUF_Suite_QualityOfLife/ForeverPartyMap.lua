local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end

local PartyMap = { rows = {}, pins = {} }
local UNITS = { "party1", "party2", "party3", "party4" }
local ROW_HEIGHT, WIDTH, PIN_SIZE = 17, 226, 12
local UPDATE_INTERVAL = .5
local PIN_LEVEL = "PIN_FRAME_LEVEL_GROUP_MEMBER"

local function PartySize()
    local raid = IsInRaid()
    local count = GetNumSubgroupMembers()
    if S.Public(raid) and raid == false and S.Finite(count) and count > 0 then
        return math.min(count, #UNITS)
    end
    return 0
end

local function MapInfo(mapID)
    if not S.Finite(mapID) or mapID <= 0 then return end
    local info = C_Map.GetMapInfo(mapID)
    if S.Public(info) and type(info) == "table" and canaccesstable(info) then return info end
end

local function OnMap(x, y)
    return S.Finite(x) and S.Finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local function UnitCoordinates(mapID, unit)
    local position = C_Map.GetPlayerMapPosition(mapID, unit)
    if not S.Public(position) or type(position) ~= "table" or not canaccesstable(position) then return end
    local x, y = position.x, position.y
    if OnMap(x, y) and (x ~= 0 or y ~= 0) then return x, y end
end

local function ContainsMap(shownMap, unitMap, info)
    if not info then return false end
    if unitMap == shownMap then return true end
    -- Floors and unrelated zones can share world coordinates.
    local parent = info.parentMapID
    for _ = 1, 8 do
        if not S.Finite(parent) or parent <= 0 then return false end
        if parent == shownMap then return true end
        local parentInfo = MapInfo(parent)
        parent = parentInfo and parentInfo.parentMapID
    end
    return false
end

local function Project(unit, unitMap, shownMap)
    local left, right, top, bottom = C_Map.GetMapRectOnMap(unitMap, shownMap)
    if not S.Finite(left) or not S.Finite(right) or not S.Finite(top) or not S.Finite(bottom)
        or left >= right or top >= bottom then return end
    local x, y = UnitCoordinates(unitMap, unit)
    if not x then return end
    x, y = left + x * (right - left), top + y * (bottom - top)
    if OnMap(x, y) then return x, y end
end

local function CreateList(self)
    local viewport = self.map:GetCanvasContainer()
    local list = S.CreateFrame("Frame", nil, viewport)
    list:SetFrameLevel(self.map:GetPinFrameLevelsManager():GetValidFrameLevel(PIN_LEVEL) + 1)
    list:SetPoint("BOTTOMLEFT", viewport, "BOTTOMLEFT", 12, 50)
    list:SetWidth(WIDTH)
    list:EnableMouse(false)
    local fill = S.CreateTexture(list, nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(.035, .045, .06, .9)
    for index = 1, #UNITS do
        local row = {
            name = S.CreateFontString(list, nil, "OVERLAY", "GameFontHighlightSmall"),
            location = S.CreateFontString(list, nil, "OVERLAY", "GameFontHighlightSmall"),
        }
        local y = -6 - (index - 1) * ROW_HEIGHT
        row.name:SetPoint("TOPLEFT", list, "TOPLEFT", 8, y)
        row.name:SetWidth(88)
        row.location:SetPoint("TOPLEFT", list, "TOPLEFT", 104, y)
        row.location:SetWidth(WIDTH - 112)
        for _, text in ipairs({ row.name, row.location }) do
            text:SetJustifyH("LEFT")
            text:SetWordWrap(false)
        end
        row.location:SetTextColor(.8, .83, .88)
        self.rows[index] = row
    end
    self.list = list
end

local function LayoutPins(map)
    local self = PartyMap
    if map ~= self.map or not self.hasPins then return end
    local canvas = map:GetCanvas()
    local width, height = canvas:GetSize()
    local scale = map:GetCanvasScale()
    local valid = S.Finite(width) and width > 0 and S.Finite(height) and height > 0 and S.Finite(scale) and scale > 0
    for _, pin in pairs(self.pins) do
        if valid and pin.x then
            pin.frame:SetSize(PIN_SIZE / scale, PIN_SIZE / scale)
            pin.frame:SetPoint("CENTER", canvas, "TOPLEFT", width * pin.x, -height * pin.y)
            pin.frame:Show()
        else
            pin.frame:Hide()
        end
    end
end

local function SetPin(self, index, x, y, r, g, b)
    local pin = self.pins[index]
    if x and not pin then
        local frame = S.CreateFrame("Frame", nil, self.map:GetCanvas())
        frame:SetFrameLevel(self.map:GetPinFrameLevelsManager():GetValidFrameLevel(PIN_LEVEL))
        frame:EnableMouse(false)
        local icon = S.CreateTexture(frame, nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetAtlas("WhiteCircle-RaidBlips")
        pin = { frame = frame, icon = icon }
        self.pins[index] = pin
    end
    if not pin then return end
    pin.x, pin.y = x, y
    if x then
        self.hasPins = true
        pin.icon:SetVertexColor(r, g, b)
    else
        pin.frame:Hide()
    end
end

local function PartyColor(unit)
    local _, class = UnitClass(unit)
    class = S.PublicText(class)
    if class then
        local r, g, b = GetClassColor(class)
        if S.Finite(r) and S.Finite(g) and S.Finite(b) then return r, g, b end
    end
    return .7, .87, 1
end

local function SetRowText(text, value)
    if text.partyMapValue == value then return end
    text.partyMapValue = value
    text:SetText(value)
end

local function PaintMember(self, index, shownMap, nativeHidden)
    local unit, row = UNITS[index], self.rows[index]
    local name = S.PublicText(UnitName(unit)) or UNKNOWNOBJECT
    local connected = UnitIsConnected(unit)
    if not S.Public(connected) then connected = nil end
    local unitMap = connected == true and C_Map.GetBestMapForUnit(unit)
    local info = MapInfo(unitMap)
    local location = info and S.PublicText(info.name)
    local r, g, b = PartyColor(unit)
    SetRowText(row.name, name)
    row.name:SetTextColor(r, g, b)
    local offline = connected == false and name ~= UNKNOWNOBJECT
    SetRowText(row.location, location or (offline and PLAYER_OFFLINE or UNKNOWN))
    row.name:Show()
    row.location:Show()

    local x, y
    -- The native frame does not expose its rendered positions. Add our own
    -- markers only on maps where Blizzard has hidden the whole native layer.
    if nativeHidden and ContainsMap(shownMap, unitMap, info) then
        x, y = UnitCoordinates(shownMap, unit)
        if not x and unitMap ~= shownMap then x, y = Project(unit, unitMap, shownMap) end
    end
    SetPin(self, index, x, y, r, g, b)
end

local function ClearPins(self)
    self.hasPins = nil
    for _, pin in pairs(self.pins) do
        pin.x, pin.y = nil, nil
        pin.frame:Hide()
    end
end

local function Clear(self)
    if self.list then self.list:Hide() end
    ClearPins(self)
end

local function Paint(self)
    local map = self.map
    if not self.active or not map or not map:IsShown() then return end
    local count = PartySize()
    if count == 0 then return Clear(self) end
    if not self.list then CreateList(self) end
    local shownMap = map:GetMapID()
    shownMap = S.Finite(shownMap) and shownMap > 0 and shownMap or nil
    local hideIcons = shownMap and C_Map.GetMapDisplayInfo(shownMap)
    local nativeHidden = S.Public(hideIcons) and hideIcons == true
    self.hasPins = nil
    for index = 1, count do PaintMember(self, index, shownMap, nativeHidden) end
    for index = count + 1, #UNITS do
        self.rows[index].name:Hide()
        self.rows[index].location:Hide()
        SetPin(self, index)
    end
    self.list:SetHeight(count * ROW_HEIGHT + 12)
    self.list:Show()
    LayoutPins(map)
end

local function Tick(self)
    Paint(self)
end

local function RosterChanged(self)
    if PartySize() > 0 then
        self.context:Ticker(UPDATE_INTERVAL, Tick)
    else
        self.context:Cancel(Tick)
    end
    self.context:After(0, Paint)
end

local function MapChanged(map)
    if PartyMap.active and map == PartyMap.map and map:IsShown() then
        if PartyMap.hasPins then ClearPins(PartyMap) end
        -- Read party data and create new markers outside the native callback.
        PartyMap.context:After(0, Paint)
    end
end

local function MapShown(map)
    local self = PartyMap
    if not self.active or map ~= self.map then return end
    self.context:Event("GROUP_ROSTER_UPDATE", RosterChanged)
    RosterChanged(self)
end

local function MapHidden(map)
    local self = PartyMap
    if map ~= self.map then return end
    self.context:RemoveEvent("GROUP_ROSTER_UPDATE")
    self.context:Cancel(Paint)
    self.context:Cancel(Tick)
    Clear(self)
end

local function Attach(self)
    local map = WorldMapFrame
    if not map then return end
    self.map = map
    self.context:RemoveEvent("ADDON_LOADED")
    if not self.hooked then
        self.hooked = true
        map:HookScript("OnShow", MapShown)
        map:HookScript("OnHide", MapHidden)
        hooksecurefunc(map, "OnMapChanged", MapChanged)
        hooksecurefunc(map, "OnCanvasSizeChanged", LayoutPins)
        hooksecurefunc(map, "OnCanvasScaleChanged", LayoutPins)
    end
    if map:IsShown() then MapShown(map) end
end

local function MapLoaded(self, _, addon)
    if addon == "Blizzard_WorldMap" then Attach(self) end
end

function PartyMap:Enable()
    if NS.Client.IsAddOnLoaded("Blizzard_WorldMap") then Attach(self) end
    if not self.map then self.context:Event("ADDON_LOADED", MapLoaded) end
end

function PartyMap:Disable()
    if self.map then MapHidden(self.map) end
    self.map = nil
end

S.Install("foreverPartyMap", PartyMap)
