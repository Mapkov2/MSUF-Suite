local _, Private = ...
local NS, Suite, Navigation = Private.NS, Private.Suite, Private.Navigation
local MAX_STEPS = 100

local function Append(steps, map, x, y, name)
    if not Suite.Finite(map) or not Suite.Finite(x) or not Suite.Finite(y)
        or map < 1 or x < 0 or x > 1 or y < 0 or y > 1 then return false end
    local previous = steps[#steps]
    if previous and previous.map == map and math.abs(previous.x - x) < .0001 and math.abs(previous.y - y) < .0001 then return true end
    if #steps >= MAX_STEPS then return false end
    steps[#steps + 1] = { map = map, x = x, y = y, name = Suite.PublicText(name) or Suite.Text("Route stop"),
        list = Suite.Text("Planned route") }
    return true
end

local function Farstrider(target, steps)
    local provider = _G.FarstriderLib_API
    if type(provider) ~= "table" or type(provider.FindTrailTo) ~= "function" then return false end
    local _, path = provider.FindTrailTo(target.map, target.x, target.y, 0)
    if not Suite.Public(path) or type(path) ~= "table" then return false end
    if #path > MAX_STEPS then return false end
    for index = 2, #path do
        local node = path[index]
        if Suite.Public(node) and type(node) == "table" and type(node.getLocation) == "function" then
            local location = node.getLocation()
            if Suite.Public(location) and type(location) == "table" and location.isUI == true then
                local position = location.pos
                if Suite.Public(position) and type(position) == "table" then
                    if not Append(steps, location.mapId, position.x, position.y, target.name) then return false end
                end
            end
        end
    end
    return #steps > 0
end

local function Mapzeroth(target, steps)
    local addon = _G.MapzerothAddon
    if type(addon) ~= "table" or type(addon.Journey) ~= "table" or type(addon.Journey.PlanFromHere) ~= "function" then return false end
    local destination = { id = "MSUF_NAV_DESTINATION", mapID = target.map, x = target.x, y = target.y, name = target.name }
    local entry = { id = destination.id, nodeID = destination.id, dest = destination, name = target.name }
    local plan = addon.Journey:PlanFromHere(entry)
    if not Suite.Public(plan) or type(plan) ~= "table" or type(plan.steps) ~= "table" then return false end
    for _, step in ipairs(plan.steps) do
        if type(step.path) == "table" then
            for _, point in ipairs(step.path) do
                if not Append(steps, point.mapID, point.x, point.y, step.text or step.name) then return false end
            end
        end
    end
    return #steps > 0
end

function Navigation.NextStep()
    local route = Navigation.travel
    if not route then return false end
    local nextIndex = route.index + 1
    if not route.steps[nextIndex] then Navigation.travel = nil return false end
    if not Navigation.Select(route.steps[nextIndex], "route") then return false end
    route.index = nextIndex
    return true
end

function Navigation.PlanRoute()
    local owner, target = Navigation.owner, Navigation.selected
    if not owner or not target or owner.config.pathfinding == 1 then return false end
    local steps = {}
    local planner = owner.config.pathfinding == 2 and Farstrider or Mapzeroth
    local ok, planned = Suite.Dispatch(NS.Finish, planner, target, steps)
    if not ok or not planned or not Append(steps, target.map, target.x, target.y, target.name) then
        Suite.Print(Suite.Text("The selected route provider is unavailable or could not find a route."))
        return false
    end
    if not Navigation.Select(steps[1], "route") then return false end
    Navigation.travel = { steps = steps, index = 1 }
    return true
end

-- Turn-in route (the XP bar's ready quests). The nearest ready quest is the
-- current stop: a map pin where the quest's map position is readable, the
-- focused quest otherwise. The next stop follows once that quest is handed
-- in; any other destination chosen through Navigation ends the route.
local function QuestPoint(id)
    local map = GetQuestUiMapID(id, true)
    if not Suite.Finite(map) or map < 1 then return nil end
    local quests = C_QuestLog.GetQuestsOnMap(map)
    if not Suite.Public(quests) or type(quests) ~= "table" then return nil end
    for _, quest in ipairs(quests) do
        if Suite.Public(quest) and type(quest) == "table" and Suite.Finite(quest.questID) and quest.questID == id then
            if not Suite.Finite(quest.x) or not Suite.Finite(quest.y) then return nil end
            return { map = map, x = quest.x, y = quest.y, list = Suite.Text("Ready for turn-in"),
                name = Suite.PublicText(C_QuestLog.GetTitleForQuestID(id)) or Suite.Text("Quest destination") }
        end
    end
end

-- Drops quests that are no longer ready. Quests the client cannot measure
-- from here (another continent) come after every measurable one.
local function NearestQuest(ids)
    local best, bestDistance, unmeasured
    for index = #ids, 1, -1 do
        local id = ids[index]
        local ready = C_QuestLog.IsComplete(id)
        if Suite.Public(ready) and ready ~= true then
            table.remove(ids, index)
        elseif Suite.Public(ready) then
            local distance, reachable = C_QuestLog.GetDistanceSqToQuest(id)
            if not Suite.Finite(distance) or not Suite.Public(reachable) or reachable ~= true then
                unmeasured = id
            elseif not bestDistance or distance <= bestDistance then
                best, bestDistance = id, distance
            end
        end
    end
    return best or unmeasured
end

-- The route's own map pin goes with its stop; a pin the player placed stays.
local function ReleasePin(route)
    if not route.pinned then return end
    local pin = C_Map.GetUserWaypoint()
    if Suite.Public(pin) and pin and Navigation.IsSelectedPoint(pin) then C_Map.ClearUserWaypoint() end
end

local function FollowQuest(route, id)
    local point = QuestPoint(id)
    local pinned = point ~= nil and Navigation.Select(point, "turnin")
    if not pinned then
        ReleasePin(route)
        if not Navigation.FocusQuest(id) then return false end
    end
    route.current, route.pinned = id, pinned
    Navigation.SetQuests(route)
    return true
end

function Navigation.RouteQuests(ids, count)
    if not Navigation.owner then return false end
    local route = { ids = {} }
    for index = 1, count do route.ids[index] = ids[index] end
    local first = NearestQuest(route.ids)
    if not first or not FollowQuest(route, first) then return false end
    return true, #route.ids
end

function Navigation.AdvanceQuests()
    local route = Navigation.quests
    local ready = C_QuestLog.IsComplete(route.current)
    if not Suite.Public(ready) or ready == true then return end
    if route.pinned then
        -- A different map pin is the player's own choice: the route ends.
        local pin = C_Map.GetUserWaypoint()
        if not Suite.Public(pin) then return end
        if pin and not Navigation.IsSelectedPoint(pin) then Navigation.SetQuests(nil) return end
    end
    local nextQuest = NearestQuest(route.ids)
    if nextQuest and FollowQuest(route, nextQuest) then return end
    if not nextQuest then ReleasePin(route) end
    Navigation.SetQuests(nil)
    if not nextQuest then Suite.Print(Suite.Text("Turn-in route complete.")) end
end

function Navigation.StopQuests()
    local route = Navigation.quests
    if not route then return false end
    ReleasePin(route)
    Navigation.Clear()
    return true
end
