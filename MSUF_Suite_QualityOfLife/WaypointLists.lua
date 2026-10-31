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
        rows[#rows + 1] = { key = i, point = point, label = point.list .. " · " .. point.name,
            detail = S.Text("%s · %.1f, %.1f"):format(zone, point.x * 100, point.y * 100) }
    end
    return rows
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
                    S.ToolListWindow.Refresh(M)
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
    local x, y = position:GetXY()
    if not S.Finite(x) or not S.Finite(y) then return end
    SavePoint({ map = map, x = x, y = y })
end
local function Current(_, _, window)
    local point = C_Map.GetUserWaypoint()
    if not S.Public(point) or not point or not S.Finite(point.uiMapID) or not S.Public(point.position) or not point.position then
        window:SetStatus(S.Text("Place a waypoint on Blizzard's map first.")) return
    end
    local x, y = point.position:GetXY()
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
            S.ToolListWindow.Refresh(M)
        end })
end
function M:Open()
    return S.ToolListWindow.Open(self, { title = "Saved waypoint lists", rows = Rows,
        help = "Save your position or a map pin. Search by list or place, then activate one waypoint manually.",
        empty = "Save a place to start your first route.", actions = {
            { label = "Save my position", run = Here }, { label = "Save map pin", run = Current },
            { label = "Activate waypoint", enabled = function(_, row) return row ~= nil end, run = Activate },
            { label = "Remove waypoint", enabled = function(_, row) return row ~= nil end, run = Remove },
        } })
end
function M:Enable() Store() end
function M:Refresh() S.ToolListWindow.Refresh(self) end
function M:Disable() S.ToolListWindow.Close(self) end
S.Install("waypointLists", M)
