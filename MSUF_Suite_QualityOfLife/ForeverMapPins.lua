local _, P = ...
local NS, S = P.NS, P.Suite
MSUFSuiteForeverMapPinMixin = {}
if not NS.Client.isForever then return end

-- Own the markers and their pool. The native canvas provides coordinates and
-- clipping, while its provider and pin tables remain under Blizzard's control.
local Pin = MSUFSuiteForeverMapPinMixin
local Pins = { frames = {}, count = 0 }
P.ForeverMapPins = Pins
local ATLASES = { "FlightPath", "flightmasterferry", "vehicle-air-horde", "vehicle-air-alliance",
    [6] = "poi-traveldirections", [7] = "Dungeon", [8] = "Dungeon" }
local icons = {}

function Pin:OnLoad()
    self.icon = S.CreateTexture(self, nil, "ARTWORK")
    self.icon:SetAllPoints()
    self.highlight = S.CreateTexture(self, nil, "BACKGROUND")
    self.highlight:SetPoint("TOPLEFT", -2, 2)
    self.highlight:SetPoint("BOTTOMRIGHT", 2, -2)
    self.highlight:SetColorTexture(.2, .8, 1, .7)
    self.highlight:Hide()
end

function Pin:SetHighlightLocked(locked)
    self.highlight:SetShown(locked == true)
end

function Pin:OnAcquired(owner, record, x, y, title, kind)
    self.owner, self.record, self.title, self.kind = owner, record, title, kind
    self.x, self.y = x, y
    local atlas = icons[kind]
    if atlas == nil then
        atlas = C_Texture.GetAtlasInfo(ATLASES[kind]) and ATLASES[kind] or false
        icons[kind] = atlas
    end
    if atlas then self.icon:SetAtlas(atlas) else self.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01") end
    self:SetSize(owner.config.pinSize, owner.config.pinSize)
end

function Pin:OnMouseEnter()
    if not self.owner or not self.owner.active or NS.Safety.IsForbidden(GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.title)
    if self.record.tooltipLines then
        for i = 1, #self.record.tooltipLines do GameTooltip:AddLine(self.record.tooltipLines[i], 1, 1, 1) end
    end
    GameTooltip:AddLine(S.Text("Click to place a map pin"), .7, .85, 1)
    GameTooltip:Show()
end

function Pin:OnMouseLeave()
    if not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

function Pin:OnMouseClickAction(button)
    if button ~= "LeftButton" or not self.owner or not self.owner.active or NS.InCombat() then return end
    -- Only the marker whose tooltip the player sees may place a waypoint
    -- from a gamepad click.
    if S.GamepadUI() and (NS.Safety.IsForbidden(GameTooltip)
        or not GameTooltip:IsShown() or not GameTooltip:IsOwned(self)) then return end
    local record = self.record
    local allowed = C_Map.CanSetUserWaypointOnMap(record[1])
    if not S.Public(allowed) or not allowed then return end
    local placed = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(record[1], record[2], record[3]))
    if S.Public(placed) and placed then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
end

function Pin:OnReleased()
    self:OnMouseLeave()
    self.highlight:Hide()
    self:Hide()
    self.owner, self.record, self.title, self.kind = nil, nil, nil, nil
end

local function Enter(pin)
    pin:SetHighlightLocked(true)
    pin:OnMouseEnter()
end

local function Leave(pin)
    pin:SetHighlightLocked(false)
    pin:OnMouseLeave()
end

local function MouseUp(pin, button, inside)
    if inside then pin:OnMouseClickAction(button) end
end

function Pins.Add(owner, record, x, y, title, kind)
    local index = Pins.count + 1
    local pin = Pins.frames[index]
    if not pin then
        pin = S.CreateFrame("Frame", nil, nil, "MSUFSuiteForeverMapPinTemplate")
        pin:OnLoad()
        pin:SetScript("OnEnter", Enter)
        pin:SetScript("OnLeave", Leave)
        pin:SetScript("OnMouseUp", MouseUp)
        Pins.frames[index] = pin
    end
    Pins.count = index
    pin:OnAcquired(owner, record, x, y, title, kind)
end

local hovered, lastX, lastY, lastLeft, lastTop
local function SetHovered(pin)
    if hovered == pin then return end
    if hovered then Leave(hovered) end
    hovered = pin
    if hovered then Enter(hovered) end
end

function Pins.Release()
    SetHovered(nil)
    for index = 1, Pins.count do Pins.frames[index]:OnReleased() end
    Pins.count = 0
    lastX = nil
end

function Pins.Layout(map)
    if Pins.count == 0 then return end
    local canvas = map:GetCanvas()
    local width, height = canvas:GetSize()
    local zoom, canvasScale, globalScale = map:GetCanvasZoomPercent(), map:GetCanvasScale(), map:GetGlobalPinScale()
    if not S.Finite(width) or not S.Finite(height) or not S.Finite(zoom) or not S.Finite(canvasScale)
        or not S.Finite(globalScale) or width <= 0 or height <= 0 or canvasScale <= 0 or globalScale <= 0 then return end
    local scale = (.5 + .5 * math.max(0, math.min(1, zoom))) * globalScale / canvasScale
    local level = map:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_FLIGHT_POINT")
    for index = 1, Pins.count do
        local pin = Pins.frames[index]
        if pin:GetParent() ~= canvas then pin:SetParent(canvas) end
        if pin:GetFrameLevel() ~= level then pin:SetFrameLevel(level) end
        pin:SetScale(scale)
        pin:SetPoint("CENTER", canvas, "TOPLEFT", width * pin.x / scale, -height * pin.y / scale)
        if not pin:IsShown() then pin:Show() end
    end
    lastX = nil
end

function Pins.UpdateGamepadCursor(map)
    if Pins.count == 0 then return end
    if map:GetHoveredPin() then
        lastX = nil
        SetHovered(nil)
        return
    end
    local x, y = map.ScrollContainer:GetGamepadCursorPosition()
    local canvas = map:GetCanvas()
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not S.Finite(x) or not S.Finite(y) or not S.Public(left) or not S.Public(top) then return end
    if x == lastX and y == lastY and left == lastLeft and top == lastTop then return end
    lastX, lastY, lastLeft, lastTop = x, y, left, top
    local nearest, best = nil, 12 * 12
    for index = 1, Pins.count do
        local pin = Pins.frames[index]
        local pinX, pinY
        if pin:IsShown() then pinX, pinY = pin:GetCenter() end
        if S.Finite(pinX) and S.Finite(pinY) then
            local dx, dy = x - pinX, y - pinY
            local distance = dx * dx + dy * dy
            if distance <= best then nearest, best = pin, distance end
        end
    end
    SetHovered(nearest)
end

function Pins.ClickHovered()
    if hovered then hovered:OnMouseClickAction("LeftButton") end
end
