local _, P = ...
local S = P.Suite

local M = {}
local COMMAND, ALIAS = "MSUFSUITEWAY", "/way"

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

local function Refuse()
    S.Print(S.Text("A waypoint cannot be set on this map"))
end

local function Place(message)
    if not M.active then return end
    local mapID, x, y = Coordinates(message)
    if not x or x < 0 or x > 100 or y < 0 or y > 100 then
        S.Print(S.Text("Usage: /way x y or /way mapID x y"))
        return
    end
    local mapShown = WorldMapFrame:IsShown()
    if not mapID then
        mapID = mapShown and WorldMapFrame:GetMapID() or C_Map.GetBestMapForUnit("player")
    end
    if not S.Finite(mapID) then return Refuse() end
    local allowed = C_Map.CanSetUserWaypointOnMap(mapID)
    if not S.Public(allowed) or allowed ~= true then return Refuse() end
    local placed = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
    if not S.Public(placed) or placed ~= true then return Refuse() end
    if M.config.superTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    -- The world map is a panel of Blizzard's panel manager, which refuses the
    -- Suite's ToggleWorldMap in combat lockdown ("Interface action failed
    -- because of an AddOn"): the waypoint is placed and the map stays shut.
    if M.config.openMap and not mapShown and S.CanOpenNativeWindow() then ToggleWorldMap() end
end

-- /way stays with a waypoint addon (TomTom and others) whenever one owns it.
local function Register()
    M.aliased = S.SlashAliasFree(ALIAS, COMMAND, Place)
    if M.aliased then
        S.RegisterSlash(COMMAND, Place, "/msufway", ALIAS)
    else
        S.RegisterSlash(COMMAND, Place, "/msufway")
    end
end

-- An addon loaded later may register /way; it keeps the alias. Blizzard
-- loads many addons on demand: only what a new addon can have added is read.
local function AddonLoaded()
    if M.aliased and S.SlashAliasNewlyClaimed(ALIAS, COMMAND, Place) then Register() end
end

function M:Enable()
    Register()
    self.context:Event("ADDON_LOADED", AddonLoaded)
end

function M:Refresh() Register() end

function M:Disable() S.UnregisterSlash(COMMAND, Place) end

S.Install("waypoints", M)
