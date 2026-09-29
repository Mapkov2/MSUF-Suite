local _, P = ...
local S = P.Suite

local M = {}
local COMMAND = "MSUFSUITEWAY"

local function AliasInUse(alias)
    if type(SlashCmdList) ~= "table" then return true end
    for key, callback in pairs(SlashCmdList) do
        if key ~= COMMAND and type(callback) == "function" then
            for index = 1, 12 do
                local value = _G["SLASH_" .. key .. index]
                if type(value) == "string" and value:lower() == alias then return true end
            end
        end
    end
    return false
end

local function Coordinates(message)
    if not S.PublicText(message) then return nil end
    local words = {}
    for word in message:gmatch("%S+") do
        local value = tonumber((word:gsub(",", ".")))
        if not S.Finite(value) then return nil end
        words[#words + 1] = value
        if #words > 3 then return nil end
    end
    if #words == 2 then return nil, words[1], words[2] end
    if #words == 3 and words[1] % 1 == 0 then return words[1], words[2], words[3] end
    return nil
end

local function Place(message)
    if not M.active then return end
    local mapID, x, y = Coordinates(message)
    if not x or x < 0 or x > 100 or y < 0 or y > 100 then
        S.Print(S.Text("Usage: /way x y or /way mapID x y"))
        return
    end
    local map = _G.WorldMapFrame
    local mapShown = map and map:IsShown()
    if not S.Public(mapShown) then mapShown = false end
    if not mapID then
        mapID = mapShown and map:GetMapID()
            or C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    end
    if not S.Finite(mapID) or not C_Map or not C_Map.CanSetUserWaypointOnMap
        or not UiMapPoint or not UiMapPoint.CreateFromCoordinates then
        S.Print(S.Text("A waypoint cannot be set on this map"))
        return
    end
    local allowed = C_Map.CanSetUserWaypointOnMap(mapID)
    if not S.Public(allowed) or allowed ~= true then
        S.Print(S.Text("A waypoint cannot be set on this map"))
        return
    end
    local point = UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100)
    local placed = S.Public(point) and point and C_Map.SetUserWaypoint(point)
    if not S.Public(placed) or placed ~= true then
        S.Print(S.Text("A waypoint cannot be set on this map"))
        return
    end
    if M.config.superTrack and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    if M.config.openMap and ToggleWorldMap then
        if not mapShown then ToggleWorldMap() end
    end
end

function M:Enable()
    _G["SLASH_" .. COMMAND .. "1"] = "/msufway"
    _G["SLASH_" .. COMMAND .. "2"] = not AliasInUse("/way") and "/way" or nil
    SlashCmdList[COMMAND] = Place
end

function M:Refresh()
    if AliasInUse("/way") then
        _G["SLASH_" .. COMMAND .. "2"] = nil
    elseif not _G["SLASH_" .. COMMAND .. "2"] then
        _G["SLASH_" .. COMMAND .. "2"] = "/way"
    end
end

function M:Disable()
    SlashCmdList[COMMAND] = nil
    _G["SLASH_" .. COMMAND .. "1"] = nil
    _G["SLASH_" .. COMMAND .. "2"] = nil
end

S.Install("waypoints", M)
