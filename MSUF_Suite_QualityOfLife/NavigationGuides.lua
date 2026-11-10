local _, Private = ...
local NS, Suite, Navigation = Private.NS, Private.Suite, Private.Navigation
local observed, installed = {}, {}

local function Table(value)
    return Suite.Public(value) and type(value) == "table"
end

local function ClearGuide(source)
    local owner = Navigation.owner
    if not owner or not owner.active then return end
    observed[source] = nil
    if Navigation.selectedSource ~= source then return end
    local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType()
    if Suite.Public(kind) and kind == Enum.SuperTrackingType.UserWaypoint
        and Navigation.IsSelectedPoint(C_Map.GetUserWaypoint()) then
        C_SuperTrack.SetSuperTrackedUserWaypoint(false)
    end
    Navigation.selected, Navigation.selectedSource = nil, nil
end

local function Offer(source, map, x, y, name)
    local owner = Navigation.owner
    if not owner or not owner.active or not Suite.Finite(map) or not Suite.Finite(x) or not Suite.Finite(y)
        or map < 1 or x < 0 or x > 1 or y < 0 or y > 1 then return end
    local previous = observed[source]
    if previous and previous.map == map and previous.x == x and previous.y == y then return end
    local manual = Navigation.selectedSource == "manual" or Navigation.selectedSource == "saved" or Navigation.selectedSource == "route"
    if manual and Navigation.IsSelectedPoint(C_Map.GetUserWaypoint()) and not owner.config.replaceManual then return end
    if Navigation.Select({ map = map, x = x, y = y, name = Suite.PublicText(name) or Suite.Text("Guide destination"),
        list = source }, source) then
        previous = previous or {}
        previous.map, previous.x, previous.y = map, x, y
        observed[source] = previous
    end
end

local function TomTomPoint(_, uid, _, title)
    local owner = Navigation.owner
    if not owner or not owner.config.guideTomTom or not Table(uid) then return end
    local map, x, y = uid[1], uid[2], uid[3]
    if Suite.Finite(uid[4]) then x, y = uid[3], uid[4] end
    Offer("TomTom", map, x, y, title)
end

local function TomTomChanged(_, uid)
    local owner = Navigation.owner
    if not owner or not owner.active or not owner.config.guideTomTom then return end
    if Suite.Public(uid) and uid == nil then ClearGuide("TomTom") return end
    TomTomPoint(nil, uid, nil, Table(uid) and uid.title or nil)
end

local function RXPPoint(owner)
    local arrow = _G.RXPG_ARROW
    if not owner.config.guideRestedXP or not arrow or not arrow:IsShown() then return end
    local element = arrow.element
    if not Table(element) or not Suite.Finite(element.x) or not Suite.Finite(element.y) then return end
    local step = Table(element.step) and element.step or nil
    Offer("RestedXP", element.zone, element.x / 100, element.y / 100, step and (step.arrowtext or step.title))
end

local function MapzerothPoint(owner)
    local addon = _G.MapzerothAddon
    if not owner.config.guideMapzeroth or not Table(addon) or not Table(addon.Navigation) then return end
    local model = addon.Navigation:Model()
    if not Table(model) or model.finished or not Table(model.step) then return end
    local path = model.step.path
    if not Table(path) then return end
    local target = path[#path]
    if Table(target) then Offer("Mapzeroth", target.mapID, target.x, target.y, model.step.text or model.destination) end
end

local function APRPoint(_, active, x, y, displayAction)
    local owner, addon = Navigation.owner, _G.APR
    if not owner or not owner.active or not owner.config.guideAPR then return end
    if not Suite.Public(displayAction) then return end
    if displayAction ~= nil then ClearGuide("Azeroth Pilot Reloaded") return end
    if Suite.Public(active) and active ~= true then ClearGuide("Azeroth Pilot Reloaded") return end
    if active ~= true or not Table(addon)
        or not Suite.Finite(x) or not Suite.Finite(y) then return end
    local map = addon:GetPlayerParentMapID()
    if not Suite.Finite(map) then return end
    local continent = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(.5, .5))
    if not Suite.Finite(continent) then return end
    -- APR's documented Coord axes are swapped relative to the map API.
    local _, position = C_Map.GetMapPosFromWorldPos(continent, CreateVector2D(y, x), map)
    if not Suite.Public(position) or not position then return end
    local px, py = position.x, position.y
    Offer("Azeroth Pilot Reloaded", map, px, py, Suite.Text("Guide destination"))
end

local function RXPVisibility()
    local owner = Navigation.owner
    if not owner or not owner.active then return end
    owner.context:Cancel(RXPPoint)
    if owner.config.guideRestedXP and _G.RXPG_ARROW:IsShown() then
        RXPPoint(owner)
        owner.context:Ticker(.5, RXPPoint)
    else
        ClearGuide("RestedXP")
    end
end

local function MapzerothVisibility()
    local owner, addon = Navigation.owner, _G.MapzerothAddon
    if not owner or not owner.active or not Table(addon) or not Table(addon.Navigation) then return end
    owner.context:Cancel(MapzerothPoint)
    if owner.config.guideMapzeroth and addon.Navigation:IsActive() then
        MapzerothPoint(owner)
        owner.context:Ticker(.5, MapzerothPoint)
    else
        ClearGuide("Mapzeroth")
    end
end

function Navigation.RefreshGuides(owner)
    local tomtom, rxp, apr, mapzeroth = _G.TomTom, _G.RXPG_ARROW, _G.APR, _G.MapzerothAddon
    local signature = tostring(owner.config.guideTomTom) .. tostring(owner.config.guideRestedXP)
        .. tostring(owner.config.guideAPR) .. tostring(owner.config.guideMapzeroth) .. tostring(owner.config.replaceManual)
    if owner.guideSignature ~= signature then
        owner.guideSignature = signature
        for key in pairs(observed) do observed[key] = nil end
    end
    if not owner.config.guideTomTom and owner.tomtom then
        owner.tomtom.UnregisterCallback(owner, "ArrowTargetChanged")
        owner.tomtom = nil
    end
    if owner.config.guideTomTom and Table(tomtom) and type(tomtom.RegisterCallback) == "function" then
        if owner.tomtom ~= tomtom then
            tomtom.RegisterCallback(owner, "ArrowTargetChanged", TomTomChanged)
            owner.tomtom = tomtom
        end
        -- TomTom 4.4.1 exposes this optional seed internally. Ongoing updates
        -- use its public callback; a missing seed never changes foreign state.
        local internal = tomtom.private
        if owner.config.guideTomTom and Table(internal) and type(internal.GetCrazyArrowTarget) == "function" then
            local uid, title = internal.GetCrazyArrowTarget()
            TomTomPoint(nil, uid, nil, title)
        end
    elseif owner.config.guideTomTom and Table(tomtom) and type(tomtom.SetCrazyArrow) == "function" and not installed[tomtom] then
        installed[tomtom] = true
        hooksecurefunc(tomtom, "SetCrazyArrow", TomTomPoint)
    end
    if owner.config.guideRestedXP and rxp and not installed[rxp] then
        installed[rxp] = true
        rxp:HookScript("OnShow", RXPVisibility)
        rxp:HookScript("OnHide", RXPVisibility)
    end
    if owner.config.guideAPR and Table(apr) and Table(apr.Arrow)
        and type(apr.Arrow.SetArrowActive) == "function" and not installed[apr.Arrow] then
        installed[apr.Arrow] = true
        hooksecurefunc(apr.Arrow, "SetArrowActive", APRPoint)
    end
    if Table(apr) and Table(apr.Arrow) then
        APRPoint(apr.Arrow, apr.Arrow.Active, apr.Arrow.x, apr.Arrow.y, apr.Arrow.displayAction)
    end
    if owner.config.guideMapzeroth and Table(mapzeroth) and Table(mapzeroth.Navigation) and not installed[mapzeroth.Navigation] then
        local guide = mapzeroth.Navigation
        if type(guide.Start) == "function" and type(guide.Stop) == "function" then
            installed[guide] = true
            hooksecurefunc(guide, "Start", MapzerothVisibility)
            hooksecurefunc(guide, "Stop", MapzerothVisibility)
        end
    end
    if rxp then RXPVisibility() else owner.context:Cancel(RXPPoint) end
    MapzerothVisibility()
end

function Navigation.DisableGuides(owner)
    owner.context:Cancel(RXPPoint)
    owner.context:Cancel(MapzerothPoint)
    if owner.tomtom then owner.tomtom.UnregisterCallback(owner, "ArrowTargetChanged") owner.tomtom = nil end
    for key in pairs(observed) do observed[key] = nil end
end
