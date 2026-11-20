local _, P = ...
local NS, S = P.NS, P.Suite
local M = {}
local function Store()
    local data = S.CharacterData("waypointLists")
    if not data then return end
    if type(data.points) ~= "table" then data.points = {} end
    for i = #data.points, 1, -1 do
        local p = data.points[i]
        if i > 100 or type(p) ~= "table" or not S.PublicText(p.name) or #p.name > 120
            or not S.PublicText(p.list) or #p.list > 80 or not S.Finite(p.map) or p.map < 1
            or not S.Finite(p.x) or p.x < 0 or p.x > 1 or not S.Finite(p.y) or p.y < 0 or p.y > 1 then
            table.remove(data.points, i)
        end
    end
    return data.points
end
local function Rows()
    local rows = {}
    for i, point in ipairs(Store() or {}) do
        local info = C_Map.GetMapInfo(point.map)
        local zone = S.Public(info) and type(info) == "table" and S.PublicText(info.name) or S.Text("Unknown map")
        rows[#rows + 1] = { key = i, point = point, label = point.list .. " - " .. point.name,
            detail = S.Text("%s · %.1f, %.1f", true):format(zone, point.x * 100, point.y * 100) }
    end
    return rows
end

local function PointsChanged()
    S.ToolListWindow.Refresh(M)
    EventRegistry:TriggerEvent("MSUF_Suite.SavedWaypointsChanged")
end

local function SavePoint(point)
    S.ToolListWindow.Edit(M, { title = "Save waypoint", label = "Name this place.", text = point.name or "", maxBytes = 120,
        onSave = function(_, text)
            text = text:match("^%s*(.-)%s*$")
            if text == "" then return false, S.Text("Enter a name.") end
            point.name = text
            S.ToolListWindow.Edit(M, { title = "Waypoint list", label = "Choose a list name, for example Gathering or Weekly route.",
                text = M.lastList or S.Text("My places"), maxBytes = 80, onSave = function(_, list)
                    list = list:match("^%s*(.-)%s*$")
                    if list == "" then return false, S.Text("Enter a name.") end
                    local points = Store()
                    if not points then return false, S.Text("Character data is not available yet.") end
                    if #points >= 100 then return false, S.Text("Keep at most 100 saved waypoints.") end
                    point.list, M.lastList = list, list
                    points[#points + 1] = point
                    PointsChanged()
                    return true
                end })
            return true
        end })
end
local function Here(_, _, window)
    local map = C_Map.GetBestMapForUnit("player")
    if not S.Finite(map) then
        window:SetStatus(S.Text("Your position is not available on this map."))
        return
    end
    local position = C_Map.GetPlayerMapPosition(map, "player")
    if not S.Public(position) or not position then
        window:SetStatus(S.Text("Your position is not available on this map."))
        return
    end
    local x, y = position.x, position.y
    if not S.Finite(x) or not S.Finite(y) then return end
    SavePoint({ map = map, x = x, y = y })
end
local function Current(_, _, window)
    local point = C_Map.GetUserWaypoint()
    if not S.Public(point) or not point or not S.Finite(point.uiMapID) or not S.Public(point.position) or not point.position then
        window:SetStatus(S.Text("Place a waypoint on Blizzard's map first.")) return
    end
    local x, y = point.position.x, point.position.y
    if S.Finite(x) and S.Finite(y) then SavePoint({ map = point.uiMapID, x = x, y = y }) end
end
local function Activate(_, row, window)
    local point = row.point
    local allowed = C_Map.CanSetUserWaypointOnMap(point.map)
    if not S.Public(allowed) or allowed ~= true then
        window:SetStatus(S.Text("This map does not support waypoints."))
        return
    end
    local ok = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(point.map, point.x, point.y))
    if S.Public(ok) and ok == true then
        if M.config.superTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        window:SetStatus(S.Text("Waypoint activated: %s"):format(point.name))
    else
        window:SetStatus(S.Text("The waypoint could not be activated."))
    end
end
local function Remove(_, row)
    local profile, point = NS.DB, row.point
    S.Confirm("suite-waypoint-remove", { text = S.Text("Remove this saved waypoint?"),
        callback = function()
            if NS.DB ~= profile or NS.InCombat() or not M.active then return end
            for i, p in ipairs(Store() or {}) do if p == point then table.remove(Store(), i) break end end
            PointsChanged()
        end })
end

local function PointKey(point)
    return ("%d:%.8f:%.8f"):format(point.map, point.x, point.y)
end

local function ExistingPoints(points)
    local keys = {}
    for _, point in ipairs(points) do keys[PointKey(point)] = true end
    return keys
end

local function ParseImport(text, points)
    local imports, keys, skipped, duplicates = {}, ExistingPoints(points), 0, 0
    local current = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() or C_Map.GetBestMapForUnit("player")
    local lineNumber = 0
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lineNumber = lineNumber + 1
        if line:find("%S") then
            local input = line:match("^%s*/[Ww][Aa][Yy]%s+(.+)$")
            local map, x, y, named
            if input then map, x, y, named = S.ParseSuiteWaypoint((input:gsub("^%s*#(%d+)%s+", "%1 ")), current) end
            local allowed = S.Finite(map) and map >= 1 and map % 1 == 0 and C_Map.CanSetUserWaypointOnMap(map)
            if not S.Public(allowed) or allowed ~= true or not S.Finite(x) or not S.Finite(y)
                or x < 0 or x > 1 or y < 0 or y > 1 then
                skipped = skipped + 1
            else
                local name = named and not named.unnamed and S.PublicText(named.name)
                local point = { map = map, x = x, y = y, name = name and #name <= 120 and name
                    or ("%.1f, %.1f"):format(x * 100, y * 100) }
                local key = PointKey(point)
                if keys[key] then
                    duplicates = duplicates + 1
                else
                    keys[key] = true
                    imports[#imports + 1] = { point = point, line = lineNumber }
                end
            end
        end
    end
    return imports, skipped, duplicates
end

local function SaveImport(points, imports, window)
    if not M.active or NS.InCombat() or Store() ~= points then return end
    local keys, list = ExistingPoints(points), S.Text("Imported waypoints")
    local added = 0
    for _, entry in ipairs(imports) do
        if not keys[PointKey(entry.point)] then added = added + 1 end
    end
    if #points + added > 100 then
        window:SetStatus(S.Text("Keep at most 100 saved waypoints."))
        return
    end
    for _, entry in ipairs(imports) do
        local point = entry.point
        if not keys[PointKey(point)] then
            point.list = list
            points[#points + 1] = point
        end
    end
    M:Open()
    PointsChanged()
end

local function PreviewImport(points, imports, summary)
    local rows = {}
    for i, entry in ipairs(imports) do
        local point = entry.point
        local info = C_Map.GetMapInfo(point.map)
        local zone = S.Public(info) and type(info) == "table" and S.PublicText(info.name) or S.Text("Unknown map")
        rows[i] = { key = i, label = ("%d. %s"):format(entry.line, point.name),
            detail = S.Text("%s · %.1f, %.1f", true):format(zone, point.x * 100, point.y * 100) }
    end
    S.ToolListWindow.Open(M, { title = "Review waypoint import", help = summary, rows = function() return rows end,
        actions = {
            { label = "Save", run = function(_, _, window) SaveImport(points, imports, window) end },
            { label = "Cancel", run = function() M:Open() end },
        },
    })
end

local function Import()
    S.ToolListWindow.Edit(M, { title = "Import waypoints", label = "Paste one /way command per line.",
        multiline = true, maxBytes = 8000, onSave = function(_, text)
            local points = Store()
            if not points then return false, S.Text("Character data is not available yet.") end
            local imports, skipped, duplicates = ParseImport(text, points)
            local count = #imports
            local summary = S.Text("%d new waypoints, %d invalid lines, %d duplicates."):format(count, skipped, duplicates)
            if count == 0 then return false, summary end
            if #points + count > 100 then return false, S.Text("Keep at most 100 saved waypoints.") end
            PreviewImport(points, imports, summary)
            return true
        end })
end

function M:Open()
    return S.ToolListWindow.Open(self, { title = "Saved waypoint lists", rows = Rows,
        help = "Save your position or a map pin. Search by list or place, then activate one waypoint manually.",
        empty = "Save a place to start your first route.", actions = {
            { label = "Save my position", run = Here }, { label = "Save map pin", run = Current },
            { label = "Import waypoints", run = Import },
            { label = "Activate waypoint", enabled = function(_, row) return row ~= nil end, run = Activate },
            { label = "Remove waypoint", enabled = function(_, row) return row ~= nil end, run = Remove },
        } })
end
function M:Enable() Store() end
function M:Refresh() S.ToolListWindow.Refresh(self) end
function M:Disable() S.ToolListWindow.Close(self) end
function S.WaypointPoints() return Store() end
S.Install("waypointLists", M)
