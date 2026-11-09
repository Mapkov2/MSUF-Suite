local _, P = ...
local S, Data = P.Suite, P.GatheringRouteData
local Arrow = {}
P.GatheringArrow = Arrow

local ROUND_DEGREE = 180 / math.pi

local function Create()
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(72, 57)
    host:SetPoint("CENTER", UIParent, "CENTER", 0, 188)
    host:SetFrameStrata("MEDIUM")
    host:EnableMouse(false)
    host:Hide()
    local arrow = S.CreateTexture(host, nil, "ARTWORK")
    arrow:SetAtlas("Navigation-Tracked-Arrow")
    arrow:SetSize(38, 38)
    arrow:SetPoint("TOP", host, "TOP", 0, -2)
    local distance = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    distance:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
    distance:SetShadowOffset(1, -1)
    host.arrow, host.distance = arrow, distance
    return host
end

function Arrow.Hide(self)
    local view = self.arrow
    if view and view.visible then
        view:Hide()
        view.visible = false
    end
end

local function PaintArrow(view, dx, dy, facing)
    -- Player facing is counterclockwise from north, as is texture rotation.
    local degrees = math.floor((math.atan2(-dx, dy) - facing) * ROUND_DEGREE + .5) % 360
    if view.degrees ~= degrees then
        view.arrow:SetRotation(degrees / ROUND_DEGREE)
        view.degrees = degrees
    end
end

function Arrow.Paint(self, x, y)
    local goal = self.goal
    if not goal or goal.arrived or goal.map ~= self.map or not self.width or x == nil then return Arrow.Hide(self) end
    local dx, dy = (goal.x - x) * self.width, (y - goal.y) * self.height
    local distanceSquared = dx * dx + dy * dy
    if distanceSquared <= Data.arrivalDistanceSquared then
        goal.arrived = true
        return Arrow.Hide(self)
    end
    local facing = GetPlayerFacing()
    if not S.Finite(facing) then return Arrow.Hide(self) end
    local view = self.arrow
    if not view then view = Create() self.arrow = view end
    local meters = math.floor(math.sqrt(distanceSquared) * Data.yardsToMeters + .5)
    if view.kind ~= goal.kind then
        local color = Data.types[goal.kind].color
        view.arrow:SetVertexColor(color[1], color[2], color[3])
        view.kind = goal.kind
    end
    if view.meters ~= meters then
        view.distance:SetText(("%d m"):format(meters))
        view.meters = meters
    end
    PaintArrow(view, dx, dy, facing)
    if not view.visible then
        view:Show()
        view.visible = true
    end
end
