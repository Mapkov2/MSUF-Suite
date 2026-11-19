local _, private = ...
local NS, S, Points = private.NS, private.Suite, private.NavigationHUDPoints
local Compass, Heading = NS.Compass, S.CompassHeading
local Markers = {}
private.NavigationHUDMarkers = Markers

local INTERVAL, COMPASS_RANGE = .20, 325
local POSITION_ATTEMPTS = 5
local MAP_LIMIT, COMPASS_LIMIT, MINIMAP_LIMIT = 22, 10, 12
local COMPASS_CANDIDATES, COMPASS_ICON_SIZE = 20, 12
local RAD = math.pi / 180
local abs, atan2, cos, sin, sqrt, floor = math.abs, math.atan2, math.cos, math.sin, math.sqrt, math.floor
local min, max = math.min, math.max
local Finite, Public = S.Finite, S.Public
local DEFAULT_ATLAS = "Waypoint-MapPin-Tracked"
local GATHER_ICON = { "Interface\\Icons\\Trade_Herbalism", "Interface\\Icons\\Trade_Mining" }
local POINT_ATLAS = { quest = "QuestNormal", trackedQuest = "QuestNormal" }
local SAVED_WAYPOINTS_CHANGED = "MSUF_Suite.SavedWaypointsChanged"
local POINT_EVENTS = {
    "AREA_POIS_UPDATED", "QUEST_LOG_UPDATE", "SUPER_TRACKING_CHANGED",
    "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "TAXI_NODE_STATUS_CHANGED",
}
local cachedAtlases = {}
local ownerWithMinimap, minimapHooked
local Tick

local function HidePin(marker)
    if not marker.shown then return end
    marker.shown = nil
    marker.texture:Hide()
end

local function Clear(pool, first)
    for i = first or 1, #pool do HidePin(pool[i]) end
end

local function Paint(pool, index, parent, mask, point, anchor, x, y, size)
    local marker = pool[index]
    if not marker then
        local texture = S.CreateTexture(parent, nil, "OVERLAY")
        if mask then texture:AddMaskTexture(mask) end
        marker = { texture = texture }
        pool[index] = marker
    end
    local texture, kind = marker.texture, point.kind
    local icon, atlas = GATHER_ICON[kind], point.atlas or POINT_ATLAS[kind] or DEFAULT_ATLAS
    if marker.icon ~= icon or marker.atlas ~= atlas then
        marker.icon, marker.atlas = icon, atlas
        if icon then
            texture:SetTexture(icon)
            texture:SetVertexColor(1, 1, 1, .72)
        else
            if cachedAtlases[atlas] == nil then
                local info = C_Texture.GetAtlasInfo(atlas)
                cachedAtlases[atlas] = Public(info) and type(info) == "table"
            end
            texture:SetAtlas(cachedAtlases[atlas] and atlas or DEFAULT_ATLAS)
            texture:SetVertexColor(1, 1, 1, 1)
        end
    end
    if marker.size ~= size then
        marker.size = size
        texture:SetSize(size, size)
    end
    if marker.x ~= x or marker.y ~= y then
        marker.x, marker.y = x, y
        texture:SetPoint("CENTER", parent, anchor, x, y)
    end
    if not marker.shown then
        marker.shown = true
        texture:Show()
    end
end

local function Insert(list, point, limit)
    local i = #list
    if i == limit and point.order >= list[i].order then return end
    local last = i < limit and i + 1 or i
    while last > 1 and point.order < list[last - 1].order do
        list[last] = list[last - 1]
        last = last - 1
    end
    list[last] = point
end

local function SelectPoints(state, points)
    local x, y = state.lastX, state.lastY
    local halfX, halfY, radius = state.halfX, state.halfY, state.radius
    local width, height = state.width or 1, state.height or 1
    local compass = state.width and state.wantCompass
    for _, point in ipairs(points) do
        local dx, dy = point.x - x, y - point.y
        local gathered = GATHER_ICON[point.kind] ~= nil
        local onMap = halfX and point.kind ~= "waypoint" and (not gathered or state.mapGather)
            and abs(dx) <= halfX and abs(dy) <= halfY
        dx, dy = dx * width, dy * height
        local onCompass = compass and (not gathered or state.mapGather) and abs(dx) <= COMPASS_RANGE and abs(dy) <= COMPASS_RANGE
        local onMinimap = radius and gathered and abs(dx) <= radius and abs(dy) <= radius
        if onMap or onCompass or onMinimap then
            local distance = dx * dx + dy * dy
            point.dx, point.dy, point.distance = dx, dy, distance
            point.order = point.kind == "waypoint" and -2 or point.kind == "trackedQuest" and -1 or distance
            if onMap then Insert(state.overlay, point, MAP_LIMIT) end
            if onCompass and distance >= 1 and distance <= COMPASS_RANGE * COMPASS_RANGE then
                Insert(state.compass, point, COMPASS_CANDIDATES)
            end
            if onMinimap and distance <= radius * radius * .81 then Insert(state.mini, point, MINIMAP_LIMIT) end
        end
    end
end

local function SelectionBound(points, limit, maximum)
    local last = points[limit]
    return last and min(maximum, last.order) or maximum
end

local function GatheringBound(state, map, compass, mini)
    return max(
        SelectionBound(state.overlay, MAP_LIMIT, map),
        SelectionBound(state.compass, COMPASS_CANDIDATES, compass),
        SelectionBound(state.mini, MINIMAP_LIMIT, mini))
end

local function SelectGathering(state)
    local width, height = state.width or 1, state.height or 1
    local radius = state.radius or 0
    local compass = state.width and state.mapGather and state.wantCompass and COMPASS_RANGE or 0
    local mapX, mapY = state.mapGather and state.halfX or 0, state.mapGather and state.halfY or 0
    local range = max(compass, radius)
    local halfX, halfY = max(range / width, mapX), max(range / height, mapY)
    if halfX == 0 or halfY == 0 then return end
    local mapBound, compassBound, miniBound = (mapX * width) ^ 2 + (mapY * height) ^ 2, compass * compass, radius * radius * .81
    local x, y = state.lastX, state.lastY
    local cells, buckets = Points.gatheringCells, state.gatherBuckets
    local step = 1 / cells
    local firstColumn = Points.GatheringCell(max(0, x - halfX))
    local lastColumn = Points.GatheringCell(min(1, x + halfX))
    local firstRow = Points.GatheringCell(max(0, y - halfY))
    local lastRow = Points.GatheringCell(min(1, y + halfY))
    local center = Points.GatheringCell(y) * cells + Points.GatheringCell(x)
    if buckets[center] then SelectPoints(state, buckets[center]) end
    local bound = GatheringBound(state, mapBound, compassBound, miniBound)
    -- Seed the nearest lists with the current cell. Once a list is full, a
    -- cell farther away than its last candidate cannot contribute to it.
    for row = firstRow, lastRow do
        local dy = row * step - y
        local gapY = (max(dy, -dy - step, 0) * height) ^ 2
        if gapY <= bound then
            local start = row * cells
            for column = firstColumn, lastColumn do
                local index = start + column
                local bucket = buckets[index]
                if bucket and index ~= center then
                    local dx = column * step - x
                    local gapX = max(dx, -dx - step, 0) * width
                    if gapX * gapX + gapY <= bound then
                        SelectPoints(state, bucket)
                        bound = GatheringBound(state, mapBound, compassBound, miniBound)
                    end
                end
            end
        end
    end
end

local function Select(state, map)
    wipe(state.overlay)
    wipe(state.compass)
    wipe(state.mini)
    if state.wantMap then
        state.halfX, state.halfY = map.halfX / map.art.width, map.halfY / map.art.height
    else
        state.halfX, state.halfY = nil, nil
    end
    if state.points then SelectPoints(state, state.points) end
    if state.gatherCount > 0 then SelectGathering(state) end
end

local function PaintMap(state, map)
    local pool = state.mapPins
    if not state.wantMap then
        Clear(pool)
        return
    end
    local selected, slots = state.mapSelected, state.mapSlots
    for _, point in ipairs(state.overlay) do selected[point] = true end
    for _, marker in ipairs(pool) do
        local point = marker.point
        if point and not selected[point] then
            slots[point], marker.point = nil, nil
        end
    end
    local scaleX, scaleY = map.art.width * map.scale, -map.art.height * map.scale
    local free = 1
    for _, point in ipairs(state.overlay) do
        local slot = slots[point]
        if not slot then
            while pool[free] and pool[free].point do free = free + 1 end
            slot = free
            slots[point] = slot
        end
        Paint(pool, slot, map.plane, map.mask, point, "TOPLEFT", point.x * scaleX, point.y * scaleY, GATHER_ICON[point.kind] and 11 or 14)
        pool[slot].point = point
    end
    for _, marker in ipairs(pool) do
        if not marker.point then HidePin(marker) end
    end
    wipe(selected)
end

local function PaintCompass(state, view)
    local count, accepted = 0, 0
    if state.wantCompass then
        local candidates = state.compass
        local spacing = (COMPASS_ICON_SIZE + 2) / view.step
        for _, point in ipairs(candidates) do
            local bearing = (atan2(point.dx, point.dy) / RAD) % 360
            local overlap
            for i = 1, accepted do
                local delta = abs(bearing - candidates[i].bearing)
                if delta < spacing or 360 - delta < spacing then
                    overlap = true
                    break
                end
            end
            if not overlap then
                point.bearing = bearing
                accepted = accepted + 1
                candidates[accepted] = point
                local a, b = Compass.MarkerOffsets(view, bearing)
                count = count + 1
                Paint(state.compassPins, count, view.rail, nil, point, "BOTTOMLEFT", a, view.baseline, COMPASS_ICON_SIZE)
                if b then
                    count = count + 1
                    Paint(state.compassPins, count, view.rail, nil, point, "BOTTOMLEFT", b, view.baseline, COMPASS_ICON_SIZE)
                end
                if accepted == COMPASS_LIMIT then break end
            end
        end
        for i = #candidates, accepted + 1, -1 do candidates[i] = nil end
    end
    Clear(state.compassPins, count + 1)
end

local function Focus(state, view, driver, bearing)
    local target, score
    if state.wantCompass and bearing then
        for _, point in ipairs(state.compass) do
            local delta = abs((point.bearing - bearing + 180) % 360 - 180)
            if point.label and delta <= 16 and (not score or delta < score) then target, score = point, delta end
        end
    end
    if target then
        if not state.focus then
            local text = driver:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("TOP", view.frame, "BOTTOM", 0, -3)
            text:SetWordWrap(false)
            state.focus = text
        end
        if state.focusFont ~= view.font then
            state.focusFont = view.font
            S.SetFont(state.focus, view.font, 12, "OUTLINE")
        end
        local meters = floor(sqrt(target.distance) * .9144 + .5)
        if state.focusName ~= target.label or state.focusMeters ~= meters then
            state.focusName, state.focusMeters = target.label, meters
            state.focus:SetText(("%s  |cffe0cb83%d m|r"):format(target.label, meters))
        end
        if state.focusWidth ~= view.width then
            state.focusWidth = view.width
            state.focus:SetWidth(view.width)
        end
        if not state.focusShown then
            state.focusShown = true
            state.focus:Show()
        end
    elseif state.focusShown then
        state.focusShown = nil
        state.focus:Hide()
    end
end

local function MinimapProjection(bearing)
    local rotate = C_CVar.GetCVarBool("rotateMinimap")
    if not Public(rotate) then return end
    local angle = 0
    if rotate then
        local ignored = C_Minimap.IsRotateMinimapIgnored()
        if not Public(ignored) then return end
        if not ignored then
            bearing = bearing or Heading.Read()
            if not bearing then return end
            angle = -bearing * RAD
        end
    end
    local w, h = Minimap:GetSize()
    if Finite(w) and Finite(h) and w > 0 and h > 0 then return angle, w, h end
end

local function PaintMinimap(state, radius, angle, w, h)
    local count = 0
    if radius and angle and w and h and #state.mini > 0 then
        if not state.minimapFrame then
            local frame = S.CreateFrame("Frame", nil, Minimap)
            frame:SetAllPoints(Minimap)
            frame:EnableMouse(false)
            state.minimapFrame = frame
        end
        local c, s = cos(angle), sin(angle)
        local scaleX, scaleY = w / (2 * radius), h / (2 * radius)
        for i, point in ipairs(state.mini) do
            local x, y = (point.dx * c + point.dy * s) * scaleX, (point.dy * c - point.dx * s) * scaleY
            Paint(state.miniPins, i, state.minimapFrame, nil, point, "CENTER", x, y, 9)
            count = i
        end
    end
    Clear(state.miniPins, count + 1)
end

local function Hide(state)
    Clear(state.mapPins)
    Clear(state.compassPins)
    Clear(state.miniPins)
    if state.focusShown then
        state.focusShown = nil
        state.focus:Hide()
    end
    state.lastX = nil
end

local function Allowed(owner, event)
    if not owner.active or not owner.driver:IsVisible() or S.editMode or NS.InCombat(event) then return false end
    local inside = IsInInstance()
    return Public(inside) and inside == false
end

local function WaitForPosition(owner, state)
    Hide(state)
    state.positionMisses = (state.positionMisses or 0) + 1
    if state.positionMisses >= POSITION_ATTEMPTS then owner.context:Cancel(Tick) end
end

Tick = function(owner)
    local state, map = owner.markerState, owner.map
    if not Allowed(owner) then
        Markers.Stop(owner)
        return
    end
    local art = owner.mapLive and map.art
    local mapID = art and art.mapID or Points.PlayerMap()
    if not mapID then
        WaitForPosition(owner, state)
        return
    end
    local mapChanged = state.mapID ~= mapID
    if mapChanged or (not state.width and (state.mapDirty or state.gatherDirty)) then
        state.mapID = mapID
        state.width, state.height = Points.Size(mapID)
    end
    local rebuildMap, rebuildGather = state.mapDirty or mapChanged, state.gatherDirty or mapChanged
    if rebuildMap then
        state.points = (state.general or state.waypoint) and Points.ReadMap(mapID, state.general, state.waypoint) or nil
        state.mapDirty = nil
    end
    if rebuildGather then
        if state.gather then
            state.gatherBuckets, state.gatherCount = Points.ReadGathering(mapID)
        else
            state.gatherBuckets, state.gatherCount = nil, 0
        end
        state.gatherDirty = nil
    end
    if (not state.points or #state.points == 0) and state.gatherCount == 0 then
        Hide(state)
        owner.context:Cancel(Tick)
        return
    end
    local x, y
    if art then x, y = map.playerX, map.playerY else x, y = Points.Position(mapID) end
    if not x or (not state.wantMap and not state.width) then
        WaitForPosition(owner, state)
        return
    end
    state.positionMisses = nil
    local radius = state.wantMini and state.width and state.gatherCount > 0 and C_Minimap.GetViewRadius()
    radius = Finite(radius) and radius > 0 and radius or nil
    local bearing = owner.markerBearing
    local projection = state.wantMap and map.projection
    local railWidth = state.wantCompass and owner.compass.width
    local changed = rebuildMap or rebuildGather or state.lastX ~= x or state.lastY ~= y or state.radius ~= radius
        or state.projection ~= projection or state.railWidth ~= railWidth
    if changed then
        state.lastX, state.lastY, state.radius, state.projection, state.railWidth = x, y, radius, projection, railWidth
        Select(state, map)
        PaintMap(state, map)
        PaintCompass(state, owner.compass)
    end
    local angle, w, h
    if radius and #state.mini > 0 then angle, w, h = MinimapProjection(bearing) end
    if changed or angle ~= state.miniAngle or w ~= state.miniWidth or h ~= state.miniHeight then
        state.miniAngle, state.miniWidth, state.miniHeight = angle, w, h
        PaintMinimap(state, radius, angle, w, h)
    end
    if changed or state.lastBearing ~= bearing or (state.focusShown and state.focusFont ~= owner.compass.font) then
        state.lastBearing = bearing
        Focus(state, owner.compass, owner.driver, bearing)
    end
end

function Markers.Stop(owner)
    local state = owner.markerState
    if not state then return end
    owner.context:Cancel(Tick)
    state.wantMap, state.wantCompass, state.wantMini = nil, nil, nil
    state.positionMisses = nil
    state.mapDirty, state.gatherDirty = true, true
    Hide(state)
end

function Markers.Sync(owner, event)
    local state, c = owner.markerState, owner.config
    if not state then return end
    if not c.showMarkers or not Allowed(owner, event) then
        Markers.Stop(owner)
        return
    end
    local map = owner.mapLive and (c.showMapMarkers or c.showKnownGathering) or false
    local compass = owner.compassLive and (c.showMapMarkers or c.showKnownGathering) or false
    local visible = c.showGatheringMinimap and Minimap:IsVisible()
    local mini = Public(visible) and visible == true
    local general, gather = c.showMapMarkers and (map or compass) or false, (map or compass) and c.showKnownGathering or mini
    local waypoint = general and compass and c.showWaypoint or false
    local mapGather = c.showKnownGathering == true
    if not (map or compass or mini) then
        if state.wantMap or state.wantCompass or state.wantMini then Markers.Stop(owner) end
        return
    end
    local changed = state.wantMap ~= map or state.wantCompass ~= compass or state.wantMini ~= mini or state.mapGather ~= mapGather
    if state.general ~= general or state.waypoint ~= waypoint then state.mapDirty = true end
    if state.gather ~= gather then state.gatherDirty = true end
    state.wantMap, state.wantCompass, state.wantMini = map, compass, mini
    state.general, state.gather, state.waypoint, state.mapGather = general, gather, waypoint, mapGather
    if changed then state.lastX = nil end
    if changed or state.mapDirty or state.gatherDirty then
        state.positionMisses = nil
        owner.context:Ticker(INTERVAL, Tick)
        Tick(owner)
    end
end

function Markers.Invalidate(owner, scope)
    local state = owner.markerState
    if not state then return end
    state.positionMisses = nil
    if scope ~= "gathering" then state.mapDirty = true end
    if scope ~= "map" then state.gatherDirty = true end
    if state.wantMap or state.wantCompass or state.wantMini then owner.context:Ticker(INTERVAL, Tick) end
end

local function PointsChanged(owner)
    if owner.markerState.general then Markers.Invalidate(owner, "map") end
end

local function Harvest(owner, _, unit, _, spell)
    local category = Points.GatherCategory(spell)
    if category and Public(unit) and unit == "player" and Allowed(owner) and Points.Record(category) then
        Markers.Invalidate(owner, "gathering")
    end
end

local function AddOnLoaded(owner, _, name)
    if Public(name) and (name == "GatherMate2" or name == "GatherMate2_Data") then Markers.Invalidate(owner, "gathering") end
end

local function MinimapVisibility()
    if ownerWithMinimap then Markers.Sync(ownerWithMinimap) end
end

function Markers.Bind(owner)
    local c, context = owner.config, owner.context
    local showMini = c.showMarkers and c.showGatheringMinimap
    local general = c.showMarkers and c.showMapMarkers == true
    local gather = (c.showMarkers and c.showKnownGathering == true) or showMini == true
    if (general or gather) and not owner.markerState then
        owner.markerState = {
            overlay = {}, compass = {}, mini = {}, mapPins = {}, compassPins = {}, miniPins = {},
            mapSelected = {}, mapSlots = {},
        }
    end
    if general ~= owner.markerEvents then
        owner.markerEvents = general
        for _, event in ipairs(POINT_EVENTS) do
            if general then context:Event(event, PointsChanged) else context:RemoveEvent(event) end
        end
        if general then
            context:Callback(SAVED_WAYPOINTS_CHANGED, PointsChanged)
        else
            context:RemoveCallback(SAVED_WAYPOINTS_CHANGED)
        end
    end
    if gather ~= owner.gatheringEvents then
        owner.gatheringEvents = gather
        if gather then
            context:Event("UNIT_SPELLCAST_SUCCEEDED", Harvest, false, "player")
            context:Event("ADDON_LOADED", AddOnLoaded)
        else
            context:RemoveEvent("UNIT_SPELLCAST_SUCCEEDED")
            context:RemoveEvent("ADDON_LOADED")
        end
    end
    ownerWithMinimap = showMini and owner or nil
    if ownerWithMinimap and not minimapHooked then
        Minimap:HookScript("OnShow", MinimapVisibility)
        Minimap:HookScript("OnHide", MinimapVisibility)
        minimapHooked = true
    end
end

function Markers.Disable(owner)
    ownerWithMinimap, owner.markerEvents, owner.gatheringEvents = nil, nil, nil
    Markers.Stop(owner)
end
