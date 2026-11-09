local _, P = ...
local S, Data = P.Suite, P.GatheringRouteData
local Radar = {}
P.GatheringRadar = Radar

local SIZE, MAX_MARKERS = 300, 32
local HALF = SIZE / 2
local floor = math.floor

local function Create()
    local host = S.CreateFrame("Frame", nil, UIParent)
    host:SetSize(SIZE, SIZE)
    host:SetPoint("CENTER")
    host:SetFrameStrata("LOW")
    host:EnableMouse(false)
    host:Hide()
    host.markers = {}
    local center = S.CreateTexture(host, nil, "ARTWORK")
    center:SetPoint("CENTER")
    center:SetSize(4, 4)
    center:SetColorTexture(.9, .95, 1, .75)
    for i = 1, MAX_MARKERS do
        local texture = S.CreateTexture(host, nil, "OVERLAY")
        texture:SetPoint("CENTER", host, "CENTER")
        texture:Hide()
        host.markers[i] = { texture = texture }
    end
    return host
end

function Radar.Hide(self)
    local host = self.radar
    if host and host.visible then
        host:Hide()
        host.visible = false
    end
    self.radarX, self.radarY = nil, nil
end

local function Draw(host, index, node, goal, x, y)
    local marker = host.markers[index]
    local texture = marker.texture
    if marker.kind ~= node.kind or marker.goal ~= goal then
        local color = Data.types[node.kind].color
        local size = goal and 12 or 7
        texture:SetSize(size, size)
        texture:SetColorTexture(color[1], color[2], color[3], goal and 1 or .75)
        marker.kind, marker.goal = node.kind, goal
    end
    x, y = floor(x + .5), floor(y + .5)
    if marker.x ~= x or marker.y ~= y then
        texture:SetPoint("CENTER", host, "CENTER", x, y)
        marker.x, marker.y = x, y
    end
    if not marker.shown then
        marker.shown = true
        texture:Show()
    end
end

local function LowerBound(points, minX)
    local left, right = 1, #points + 1
    while left < right do
        local mid = floor((left + right) / 2)
        if points[mid].x < minX then left = mid + 1 else right = mid end
    end
    return left
end

local function DrawPoint(self, index, node, x, y, scale, range, goal)
    local dx, dy = (node.x - x) * self.width, (y - node.y) * self.height
    if dx * dx + dy * dy > range * range then return index end
    Draw(self.radar, index, node, goal, dx * scale, dy * scale)
    return index + 1
end

function Radar.Paint(self, x, y)
    local points, tab, goal = self.points, self.tab, self.goal
    if not self.width or x == nil or #points == 0 and not goal then
        Radar.Hide(self)
        return
    end
    if x == self.radarX and y == self.radarY then return end
    self.radarX, self.radarY = x, y
    if not self.radar then self.radar = Create() end
    local host, range = self.radar, self.config.radarRange / Data.yardsToMeters
    local scale, index = HALF / range, 1
    if goal and goal.map == self.map and (tab == 0 or tab == goal.kind) then
        index = DrawPoint(self, index, goal, x, y, scale, range, true)
    else
        goal = nil
    end
    local radiusX = range / self.width
    for i = LowerBound(points, x - radiusX), #points do
        local node = points[i]
        if node.x > x + radiusX or index > MAX_MARKERS then break end
        if self.kinds[node.kind] and (tab == 0 or tab == node.kind) and (not goal or node.key ~= goal.key) then
            index = DrawPoint(self, index, node, x, y, scale, range, false)
        end
    end
    for i = index, host.count or 0 do
        local marker = host.markers[i]
        marker.shown = false
        marker.texture:Hide()
    end
    local visible = index > 1
    if host.visible ~= visible then
        host:SetShown(visible)
        host.visible = visible
    end
    host.count = index - 1
end
