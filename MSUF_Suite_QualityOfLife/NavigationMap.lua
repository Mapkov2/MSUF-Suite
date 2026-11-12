local _, Private = ...
local NS, Suite, Navigation = Private.NS, Private.Suite, Private.Navigation
local Pins = { world = {}, mini = {} }
local hookedMap, hookedMinimap

local function Enter(pin)
    if not pin.point or NS.Safety.IsForbidden(GameTooltip) then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(pin.point.name)
    GameTooltip:AddLine(Suite.Text("Click to track. Ctrl-click to remove."), .75, .85, 1)
    GameTooltip:Show()
end
local function Leave(pin)
    if not NS.Safety.IsForbidden(GameTooltip) and GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
end
local function Click(pin, button)
    if button ~= "LeftButton" or NS.InCombat() or not Navigation.owner then return end
    if IsControlKeyDown() then Navigation.Remove(pin.point)
    else Navigation.route = pin.point Navigation.Select(pin.point, "saved") end
end
local function Acquire(pool, index, parent)
    local pin = pool[index]
    if not pin then
        pin = Suite.CreateFrame("Button", nil, parent)
        pin.icon = Suite.CreateTexture(pin, nil, "ARTWORK")
        pin.icon:SetAtlas("Waypoint-MapPin-Tracked")
        pin.icon:SetAllPoints()
        pin:RegisterForClicks("LeftButtonUp")
        pin:SetScript("OnClick", Click)
        pin:SetScript("OnEnter", Enter)
        pin:SetScript("OnLeave", Leave)
        pool[index] = pin
    end
    return pin
end
local function Release(pool, first)
    for index = first or 1, #pool do pool[index].point = nil pool[index]:Hide() end
end

local function WorldRefresh()
    local owner, map = Navigation.owner, hookedMap
    if not owner or not owner.config.mapPins or not map or not map:IsShown() then Release(Pins.world) return end
    local mapID, canvas = map:GetMapID(), map:GetCanvas()
    local width, height = canvas:GetSize()
    if not Suite.Finite(mapID) or not Suite.Finite(width) or not Suite.Finite(height) or width <= 0 or height <= 0 then
        Release(Pins.world)
        return
    end
    local scale = map:GetCanvasScale()
    if not Suite.Finite(scale) or scale <= 0 then return end
    local count = 0
    for _, point in ipairs(Suite.WaypointPoints() or {}) do
        if point.map == mapID then
            count = count + 1
            local pin = Acquire(Pins.world, count, canvas)
            pin.point = point
            pin:SetSize(owner.config.pinSize, owner.config.pinSize)
            pin:SetScale(1 / scale)
            pin:SetPoint("CENTER", canvas, "TOPLEFT", width * point.x * scale, -height * point.y * scale)
            pin:Show()
        end
    end
    Release(Pins.world, count + 1)
end

local function WorldQueue()
    local owner = Navigation.owner
    if owner and owner.mapRefresh then owner.mapRefresh:Request() end
end

local function MinimapRefresh(owner)
    if not owner.config.minimapPins or not Minimap:IsVisible() then Release(Pins.mini) return end
    local map = C_Map.GetBestMapForUnit("player")
    if not Suite.Finite(map) then Release(Pins.mini) return end
    local position = C_Map.GetPlayerMapPosition(map, "player")
    if not Suite.Public(position) or not position then Release(Pins.mini) return end
    local x, y = position.x, position.y
    local width, height = C_Map.GetMapWorldSize(map)
    local radius = C_Minimap.GetViewRadius()
    if not Suite.Finite(x) or not Suite.Finite(y) or not Suite.Finite(width) or not Suite.Finite(height)
        or not Suite.Finite(radius) or radius <= 0 then Release(Pins.mini) return end
    local rotating = C_CVar.GetCVarBool("rotateMinimap")
    if not Suite.Public(rotating) then Release(Pins.mini) return end
    local angle = rotating and GetPlayerFacing() or 0
    if not Suite.Finite(angle) then Release(Pins.mini) return end
    local minimapWidth, minimapHeight = Minimap:GetSize()
    if not Suite.Finite(minimapWidth) or minimapWidth <= 0 or not Suite.Finite(minimapHeight) or minimapHeight <= 0 then
        Release(Pins.mini)
        return
    end
    local cosine, sine = math.cos(angle), math.sin(angle)
    local pixelsX, pixelsY = minimapWidth / (radius * 2), minimapHeight / (radius * 2)
    local count = 0
    for _, point in ipairs(owner.mapPoints) do
        if point.map == map then
            local dx, dy = (point.x - x) * width, (y - point.y) * height
            if dx * dx + dy * dy < radius * radius * .81 then
                count = count + 1
                local pin = Acquire(Pins.mini, count, Minimap)
                local px, py = (dx * cosine + dy * sine) * pixelsX, (dy * cosine - dx * sine) * pixelsY
                pin.point = point
                pin:SetSize(owner.config.pinSize, owner.config.pinSize)
                if pin.x ~= px or pin.y ~= py then pin:SetPoint("CENTER", Minimap, "CENTER", px, py) pin.x, pin.y = px, py end
                pin:Show()
            end
        end
    end
    Release(Pins.mini, count + 1)
end

local function PlaceOnMinimap(_, button)
    local owner = Navigation.owner
    if button ~= "LeftButton" or not owner or not owner.config.minimapPlacement or NS.InCombat() then return end
    local map = C_Map.GetBestMapForUnit("player")
    if not Suite.Finite(map) then return end
    local position = C_Map.GetPlayerMapPosition(map, "player")
    if not Suite.Public(position) or not position then return end
    local x, y = position.x, position.y
    local mouseX, mouseY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local minimapWidth, minimapHeight = Minimap:GetSize()
    local radius, width, height = C_Minimap.GetViewRadius(), C_Map.GetMapWorldSize(map)
    if not Suite.Finite(x) or not Suite.Finite(y) or not Suite.Finite(radius) or not Suite.Finite(width)
        or not Suite.Finite(height) or width <= 0 or height <= 0 then return end
    if not Suite.Finite(mouseX) or not Suite.Finite(mouseY) or not Suite.Finite(centerX) or not Suite.Finite(centerY)
        or not Suite.Finite(scale) or scale <= 0 or not Suite.Finite(minimapWidth) or minimapWidth <= 0
        or not Suite.Finite(minimapHeight) or minimapHeight <= 0 then return end
    local dx, dy = mouseX / scale - centerX, mouseY / scale - centerY
    local nx, ny = dx * 2 / minimapWidth, dy * 2 / minimapHeight
    if nx * nx + ny * ny > 1 then return end
    dx, dy = nx * radius, ny * radius
    local rotating = C_CVar.GetCVarBool("rotateMinimap")
    if not Suite.Public(rotating) then return end
    local angle = rotating and GetPlayerFacing() or 0
    if not Suite.Finite(angle) then return end
    local cosine, sine = math.cos(angle), math.sin(angle)
    x, y = x + (dx * cosine - dy * sine) / width, y - (dy * cosine + dx * sine) / height
    if x < 0 or y < 0 or x > 1 or y > 1 then return end
    local point = { map = map, x = x, y = y, name = Suite.Text("Map waypoint"), list = Suite.Text("My places") }
    if Navigation.Save(point) and owner.config.autoTrackPins then Navigation.Select(point, "manual") end
end

local function Modifier(owner)
    if owner.placement then owner.placement:EnableMouse(owner.config.minimapPlacement and IsControlKeyDown() and not NS.InCombat()) end
end
Navigation.RefreshMapInput = Modifier

function Navigation.RefreshMap(owner)
    owner.mapPoints = owner.mapPoints or {}
    for index = #owner.mapPoints, 1, -1 do owner.mapPoints[index] = nil end
    local map = C_Map.GetBestMapForUnit("player")
    if Suite.Finite(map) then
        for _, point in ipairs(Suite.WaypointPoints() or {}) do
            if point.map == map then owner.mapPoints[#owner.mapPoints + 1] = point end
        end
    end
    WorldQueue()
    owner.context:Cancel(MinimapRefresh)
    if owner.config.minimapPins and not owner.paused and #owner.mapPoints > 0 and Minimap:IsVisible() then
        owner.context:Ticker(.2, MinimapRefresh)
    else Release(Pins.mini) end
    Modifier(owner)
end

-- Navigation is paused (Navigation.lua, combat inside an instance): no minimap
-- ticker and no modifier event. The world map pins stay, they only refresh
-- when the player opens or moves the map.
function Navigation.PauseMap(owner)
    owner.context:Cancel(MinimapRefresh)
    owner.context:RemoveEvent("MODIFIER_STATE_CHANGED")
    Release(Pins.mini)
    if owner.placement then owner.placement:EnableMouse(false) end
end

function Navigation.ResumeMap(owner)
    owner.context:Event("MODIFIER_STATE_CHANGED", Modifier, true)
    Navigation.RefreshMap(owner)
end

function Navigation.EnableMap(owner)
    owner.mapRefresh = owner.context:Coalesce(0, WorldRefresh)
    C_AddOns.LoadAddOn("Blizzard_WorldMap")
    if not hookedMap and WorldMapFrame then
        hookedMap = WorldMapFrame
        hookedMap:HookScript("OnShow", WorldQueue)
        hookedMap:HookScript("OnHide", function() Release(Pins.world) end)
        hooksecurefunc(hookedMap, "OnMapChanged", WorldQueue)
        hooksecurefunc(hookedMap, "OnCanvasScaleChanged", WorldQueue)
        hooksecurefunc(hookedMap, "OnCanvasSizeChanged", WorldQueue)
    end
    if not owner.placement then
        owner.placement = Suite.CreateFrame("Button", nil, Minimap)
        owner.placement:SetAllPoints(Minimap)
        owner.placement:SetFrameLevel(Minimap:GetFrameLevel() + 20)
        owner.placement:RegisterForClicks("LeftButtonUp")
        owner.placement:SetScript("OnClick", PlaceOnMinimap)
        owner.placement:EnableMouse(false)
    end
    if not hookedMinimap then
        hookedMinimap = true
        Minimap:HookScript("OnHide", function()
            local current = Navigation.owner
            if current then current.context:Cancel(MinimapRefresh) end
            Release(Pins.mini)
        end)
        Minimap:HookScript("OnShow", function()
            local current = Navigation.owner
            if current then Navigation.RefreshMap(current) end
        end)
    end
    owner.context:Event("MODIFIER_STATE_CHANGED", Modifier, true)
end

function Navigation.DisableMap(owner)
    Release(Pins.world)
    Release(Pins.mini)
    if owner.placement then owner.placement:EnableMouse(false) end
end
