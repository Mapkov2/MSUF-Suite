local _, Private = ...
local Suite, Navigation = Private.Suite, Private.Navigation
local Types = Enum.SuperTrackingType

-- model.incomplete: the client could not give all of the destination (an
-- unreadable value, a name it has not loaded). Navigation.lua then lets the
-- player's movement ask again.
local function Quest(model, config)
    if not config.trackQuests then return false end
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    if not Suite.Finite(id) or id <= 0 then
        model.incomplete = not Suite.Public(id)
        return false
    end
    model.identity, model.source = id, "quest"
    local title = Suite.PublicText(C_QuestLog.GetTitleForQuestID(id))
    model.title = title or Suite.Text("Quest destination")
    local complete = C_QuestLog.IsComplete(id)
    model.incomplete = not title or not Suite.Public(complete)
    model.kind = Suite.Public(complete) and complete == true and "complete" or "quest"
    model.info = model.kind == "complete" and Suite.Text("Ready for turn-in") or Suite.Text("Focused quest")
    local index = C_QuestLog.GetLogIndexForQuestID(id)
    local info = Suite.Finite(index) and index > 0 and C_QuestLog.GetInfo(index) or nil
    if Suite.Public(info) and type(info) == "table" then
        local campaign, frequency = info.campaignID, info.frequency
        if model.kind ~= "complete" and Suite.Finite(campaign) and campaign > 0 then model.kind = "campaign"
        elseif model.kind ~= "complete" and Suite.Finite(frequency) and frequency > 0 then model.kind = "repeatable" end
    end
    return true
end

function Navigation.IsSelectedPoint(point)
    local selected = Navigation.selected
    if not selected or not Suite.Public(point) or type(point) ~= "table" then return false end
    local map, position = point.uiMapID, point.position
    if not Suite.Finite(map) or not Suite.Public(position) or not position then return false end
    local x, y = position.x, position.y
    return Suite.Finite(x) and Suite.Finite(y) and selected.map == map
        and math.abs(selected.x - x) < .00001 and math.abs(selected.y - y) < .00001
end

local function Waypoint(model, config)
    if not config.trackPins then return false end
    local point = C_Map.GetUserWaypoint()
    if not Suite.Public(point) or not point then
        model.incomplete = not Suite.Public(point)
        return false
    end
    -- A pin that is there and cannot be read in full.
    model.incomplete = true
    local map = point.uiMapID
    local position = point.position
    if not Suite.Finite(map) or not Suite.Public(position) or not position then return false end
    local x, y = position.x, position.y
    if not Suite.Finite(x) or not Suite.Finite(y) then return false end
    model.incomplete = false
    model.identity, model.source, model.kind = ("%d:%.5f:%.5f"):format(map, x, y), "pin", "pin"
    local selected = Navigation.IsSelectedPoint(point) and Navigation.selected or nil
    model.title = selected and selected.name or Suite.Text("Map waypoint")
    model.info = selected and selected.list or Suite.Text("Tracked map pin")
    if selected and Navigation.selectedSource then model.source = Navigation.selectedSource end
    return true
end

local function Interest(model, config, kind)
    if not config.trackPOIs then return false end
    model.source, model.kind = "poi", "pin"
    local name, description = C_SuperTrack.GetSuperTrackedItemName()
    name = Suite.PublicText(name)
    model.title = name or Suite.Text("Tracked point of interest")
    model.info = Suite.PublicText(description) or Suite.Text("Point of interest")
    local identity
    if kind == Types.MapPin then _, identity = C_SuperTrack.GetSuperTrackedMapPin()
    elseif kind == Types.Content then _, identity = C_SuperTrack.GetSuperTrackedContent()
    elseif kind == Types.Vignette then identity = C_SuperTrack.GetSuperTrackedVignette() end
    -- The client may give the name later (GetSuperTrackedItemName may return nothing).
    model.incomplete = not name or not Suite.Public(identity)
    if not Suite.Public(identity) then return false end
    model.identity = identity or kind
    return true
end

function Navigation.ReadSource(model, config)
    local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType()
    model.incomplete = not Suite.Public(kind)
    if model.incomplete then return false end
    local previousSource, previousID = model.source, model.identity
    local supported = false
    if kind == Types.Quest then supported = Quest(model, config)
    elseif kind == Types.UserWaypoint then supported = Waypoint(model, config)
    elseif kind == Types.MapPin or kind == Types.Content or kind == Types.Vignette then
        supported = Interest(model, config, kind)
    end
    if not supported then return false end
    model.color = Navigation.Color(config, model.kind)
    if model.source ~= previousSource or model.identity ~= previousID then
        model.rounded, model.near = nil, nil
        if config.soundTarget then Navigation.Play(config) end
    end
    return true
end

-- The one writer of the turn-in route (NavigationRoutes.lua). The XP bar's
-- route button follows it through questsChanged.
function Navigation.SetQuests(route)
    if Navigation.quests == route then return end
    Navigation.quests = route
    if Navigation.questsChanged then Suite.Dispatch(Navigation.questsChanged) end
end

function Navigation.Clear()
    Navigation.generation = (Navigation.generation or 0) + 1
    Navigation.selected, Navigation.selectedSource, Navigation.route, Navigation.travel = nil, nil, nil, nil
    Navigation.SetQuests(nil)
    C_SuperTrack.ClearAllSuperTracked()
end

function Navigation.FocusQuest(questID)
    if not Suite.Finite(questID) or questID <= 0 then return false end
    Navigation.generation = (Navigation.generation or 0) + 1
    Navigation.selected, Navigation.selectedSource, Navigation.route, Navigation.travel = nil, nil, nil, nil
    Navigation.SetQuests(nil)
    C_SuperTrack.SetSuperTrackedQuestID(questID)
    return true
end

function Navigation.Remember(point, source)
    if source ~= "route" then Navigation.travel = nil end
    if source ~= "saved" then Navigation.route = nil end
    Navigation.SetQuests(nil)
    Navigation.generation = (Navigation.generation or 0) + 1
    Navigation.selected, Navigation.selectedSource = point, source or "manual"
end

-- All callers supply normalized map coordinates. Selecting a target is the
-- only path that writes native tracking; repainting never reasserts a pin.
function Navigation.Select(point, source)
    if not Suite.Public(point) or type(point) ~= "table" or not Suite.Finite(point.map)
        or not Suite.Finite(point.x) or not Suite.Finite(point.y)
        or point.map < 1 or point.x < 0 or point.x > 1 or point.y < 0 or point.y > 1 then return false end
    local allowed = C_Map.CanSetUserWaypointOnMap(point.map)
    if not Suite.Public(allowed) or allowed ~= true then return false end
    local placed = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(point.map, point.x, point.y))
    if not Suite.Public(placed) or placed ~= true then return false end
    if not Suite.PublicText(point.name) then point.name = Suite.Text("Map waypoint") end
    if not Suite.PublicText(point.list) then point.list = Suite.Text("My places") end
    Navigation.Remember(point, source or "saved")
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    return true
end
