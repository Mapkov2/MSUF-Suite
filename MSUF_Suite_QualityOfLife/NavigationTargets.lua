local _, Private = ...
local NS, Suite, Navigation = Private.NS, Private.Suite, Private.Navigation
local MAX_POINTS = 100
local linkHooked

local function FollowLink(link)
    local owner = Navigation.owner
    if not owner or not owner.config.autoTrackLinks or not Suite.PublicText(link) then return end
    local map, x, y = link:match("^worldmap:(%d+):(%d+):(%d+)")
    if not map then return end
    map, x, y = tonumber(map), tonumber(x) / 10000, tonumber(y) / 10000
    local point = C_Map.GetUserWaypoint()
    if not Suite.Public(point) or not point or not Suite.Finite(point.uiMapID) or point.uiMapID ~= map
        or not Suite.Public(point.position) or not point.position then return end
    local px, py = point.position.x, point.position.y
    if Suite.Finite(px) and Suite.Finite(py) and math.abs(px - x) < .0001 and math.abs(py - y) < .0001 then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
end

function Navigation.EnableLinks()
    if linkHooked then return end
    linkHooked = true
    hooksecurefunc("SetItemRef", FollowLink)
end

function Navigation.Changed()
    local owner = Navigation.owner
    if owner then
        Suite.ToolListWindow.Refresh(owner)
        Navigation.RefreshMap(owner)
        owner.refresh:Request()
    end
end

function Navigation.ObservePin(owner)
    local point = C_Map.GetUserWaypoint()
    if not Suite.Public(point) then return end
    if not point then owner.pinMap, owner.pinX, owner.pinY = nil, nil, nil return end
    if not Suite.Finite(point.uiMapID)
        or not Suite.Public(point.position) or not point.position then return end
    local x, y = point.position.x, point.position.y
    if not Suite.Finite(x) or not Suite.Finite(y) then return end
    if owner.pinMap == point.uiMapID and owner.pinX == x and owner.pinY == y then return end
    owner.pinMap, owner.pinX, owner.pinY = point.uiMapID, x, y
    if owner.config.autoTrackPins then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
end

function Navigation.Save(point)
    if not Suite.Public(point) or type(point) ~= "table" or not Suite.Finite(point.map)
        or not Suite.Finite(point.x) or not Suite.Finite(point.y) or not Suite.PublicText(point.name)
        or not Suite.PublicText(point.list) or point.map <= 0 or point.x < 0 or point.x > 1 or point.y < 0 or point.y > 1 then return false end
    local points = Suite.WaypointPoints()
    if not points or #points >= MAX_POINTS then return false end
    points[#points + 1] = point
    Navigation.Changed()
    return true
end

function Navigation.Remove(point)
    local points = Suite.WaypointPoints()
    for index, existing in ipairs(points or {}) do
        if existing == point then table.remove(points, index) Navigation.Changed() return true end
    end
    return false
end

-- Decimal commas and punctuation between coordinates match the existing
-- /way helper. Text after the coordinates is a place name, never executable.
function Navigation.Parse(line, fallbackMap)
    if not Suite.PublicText(line) then return nil end
    line = line:gsub("^%s*/[%a]+%s+", ""):gsub("^%s+", "")
    local values, name = {}, nil
    for token in line:gmatch("%S+") do
        token = token:gsub("^,+", ""):gsub(",+$", "")
        local number = tonumber((token:gsub(",", ".")))
        if not name and token:find(".", 1, true) and token:find(",", 1, true) then
            for piece in token:gmatch("[^,]+") do
                local part = tonumber(piece)
                if not Suite.Finite(part) then return nil end
                values[#values + 1] = part
            end
        elseif number and not name then
            values[#values + 1] = number
        elseif token ~= "" then
            name = name and (name .. " " .. token) or token
        end
    end
    local map, x, y
    if #values == 2 then map, x, y = fallbackMap, values[1], values[2]
    elseif #values == 3 then map, x, y = values[1], values[2], values[3] end
    if not Suite.Finite(map) or map <= 0 or map % 1 ~= 0 or not Suite.Finite(x) or not Suite.Finite(y)
        or x < 0 or x > 100 or y < 0 or y > 100 then return nil end
    return { map = map, x = x / 100, y = y / 100,
        name = name and name:sub(1, 120) or Suite.Text("Map waypoint"), list = Suite.Text("My places") }
end

function Navigation.Import(text)
    if not Suite.PublicText(text) or #text > 6500 then return false, Suite.Text("Invalid waypoint list.") end
    local points, incoming = Suite.WaypointPoints(), {}
    local map = C_Map.GetBestMapForUnit("player")
    local lineNumber = 0
    for line in text:gmatch("[^\r\n]+") do
        lineNumber = lineNumber + 1
        local point = Navigation.Parse(line, map)
        if not point then return false, Suite.Text("Invalid waypoint on line %d."):format(lineNumber) end
        incoming[#incoming + 1] = point
    end
    if not points or #incoming == 0 or #points + #incoming > MAX_POINTS then
        return false, Suite.Text("Keep at most 100 saved waypoints.")
    end
    for _, point in ipairs(incoming) do points[#points + 1] = point end
    Navigation.Changed()
    return true, Suite.Text("Imported %d waypoints."):format(#incoming)
end

local function Rows()
    local rows = {}
    for index, point in ipairs(Suite.WaypointPoints() or {}) do
        rows[#rows + 1] = { key = index, point = point, label = point.name,
            detail = Suite.Text("%s · %.1f, %.1f"):format(point.list, point.x * 100, point.y * 100) }
    end
    return rows
end

-- Chat reminder after a destination the player started by hand: how to stop.
function Navigation.PrintStop()
    local owner = Navigation.owner
    if not owner then return end
    Suite.Print(owner.config.rightClickClear and Suite.Text("Stop navigation with /msufnav stop or right-click the marker.")
        or Suite.Text("Stop navigation with /msufnav stop."))
end

local function Activate(_, row)
    Navigation.route = row.point
    if Navigation.Select(row.point, "saved") then Navigation.PrintStop() end
end

local function Delete(_, row)
    local data, point = NS.DB, row.point
    Suite.Confirm("suite-navigation-remove", { text = Suite.Text("Remove this saved waypoint?"), callback = function()
        if NS.DB == data and not NS.InCombat() then Navigation.Remove(point) end
    end })
end

function Navigation.SaveHere()
    local map = C_Map.GetBestMapForUnit("player")
    if not Suite.Finite(map) then return end
    local position = C_Map.GetPlayerMapPosition(map, "player")
    if not Suite.Public(position) or not position then return end
    local x, y = position.x, position.y
    if not Suite.Finite(x) or not Suite.Finite(y) then return end
    local profile = NS.DB
    local owner = Navigation.owner
    if not owner then return end
    Suite.ToolListWindow.Edit(owner, { title = "Save waypoint", label = "Name this place.", text = "", maxBytes = 120,
        onSave = function(_, name)
            if NS.DB ~= profile or NS.InCombat() or Navigation.owner ~= owner or name == "" then return false end
            return Navigation.Save({ map = map, x = x, y = y, name = name:sub(1, 120), list = Suite.Text("My places") })
        end })
end

function Navigation.OpenPlaces()
    local owner = Navigation.owner
    if not owner then return end
    return Suite.ToolListWindow.Open(owner, { title = "Saved waypoint lists", rows = Rows,
        help = "Choose a saved destination or save your position. Route stops follow the order of their list.",
        empty = "Save a place to start your first route.", actions = {
            { label = "Save my position", run = Navigation.SaveHere },
            { label = "Activate waypoint", enabled = function(_, row) return row ~= nil end, run = Activate },
            { label = "Remove waypoint", enabled = function(_, row) return row ~= nil end, run = Delete },
        } })
end

function Navigation.QueueNext(owner)
    if Navigation.travel then
        owner.nextTravelGeneration = Navigation.generation
        owner.context:After(0, Navigation.AdvanceTravel)
        return
    end
    local current, points = Navigation.route, Suite.WaypointPoints()
    if not current or not Navigation.IsSelectedPoint(C_Map.GetUserWaypoint()) then return end
    local nextPoint
    for index, point in ipairs(points or {}) do
        if point == current then
            for nextIndex = index + 1, #points do
                if points[nextIndex].list == current.list then nextPoint = points[nextIndex] break end
            end
            break
        end
    end
    if not nextPoint then Navigation.route = nil return end
    owner.nextPoint, owner.nextGeneration = nextPoint, Navigation.generation
    owner.context:After(0, Navigation.Advance)
end

function Navigation.AdvanceTravel(owner)
    if not owner.active or owner.nextTravelGeneration ~= Navigation.generation then return end
    local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType()
    if not Suite.Public(kind) or kind ~= nil and kind ~= Enum.SuperTrackingType.UserWaypoint then return end
    if kind ~= nil and not Navigation.IsSelectedPoint(C_Map.GetUserWaypoint()) then return end
    Navigation.NextStep()
end

function Navigation.Advance(owner)
    local point = owner.nextPoint
    owner.nextPoint = nil
    if point and owner.active and owner.config.autoNext and owner.nextGeneration == Navigation.generation then
        local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType()
        if not Suite.Public(kind) then return end
        if kind ~= nil and kind ~= Enum.SuperTrackingType.UserWaypoint then return end
        if kind == Enum.SuperTrackingType.UserWaypoint and not Navigation.IsSelectedPoint(C_Map.GetUserWaypoint()) then return end
        Navigation.route = point
        Navigation.Select(point, "saved")
    end
end

local function Command(text)
    if not Navigation.owner then return end
    if text == "stop" then Navigation.Clear()
    elseif text == "save" then Navigation.SaveHere()
    elseif text == "next" then Navigation.NextStep()
    elseif text == "" or text == "list" then Navigation.OpenPlaces()
    else
        local point = Navigation.Parse(text, C_Map.GetBestMapForUnit("player"))
        if not point or not Navigation.Select(point, "manual") then
            Suite.Print(Suite.Text("Use /msufnav x y Name, /msufnav list, /msufnav save or /msufnav stop."))
        else
            Navigation.PrintStop()
        end
    end
end
Navigation.RegisterCommand = function() Suite.RegisterSlash("MSUFSUITENAV", Command, "/msufnav") end
Navigation.UnregisterCommand = function() Suite.UnregisterSlash("MSUFSUITENAV", Command) end
