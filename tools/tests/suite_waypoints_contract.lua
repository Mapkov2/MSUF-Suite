local root = assert(arg[1], "repository root required")
local module, notices = nil, {}
local suite = {
    Install = function(_, value) module = value end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Text = function(value) return value end,
    Print = function(value) notices[#notices + 1] = value end,
}
SlashCmdList = { OTHER = function() end }
SLASH_OTHER1 = "/other"
local placed, tracked, mapOpened = nil, false, false
WorldMapFrame = { shown = true,
    IsShown = function(self) return self.shown end,
    GetMapID = function() return 11 end,
}
C_Map = {
    GetBestMapForUnit = function() return 22 end,
    CanSetUserWaypointOnMap = function(mapID) return mapID == 11 or mapID == 22 end,
    SetUserWaypoint = function(point) placed = point; return true end,
}
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y)
    return { mapID = mapID, x = x, y = y }
end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(value) tracked = value end }
ToggleWorldMap = function() mapOpened = true end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Waypoints.lua"))(
    "MSUF_Suite_QualityOfLife", { Suite = suite })
module.active, module.config = true, { superTrack = true, openMap = true }
module:Enable()
assert(SlashCmdList.MSUFSUITEWAY and SLASH_MSUFSUITEWAY1 == "/msufway"
    and SLASH_MSUFSUITEWAY2 == "/way", "slash aliases were not registered")
SlashCmdList.MSUFSUITEWAY("12.5 34,5")
assert(placed.mapID == 11 and placed.x == 0.125 and placed.y == 0.345
    and tracked and not mapOpened, "map coordinates did not use the visible map")
WorldMapFrame.shown = false
tracked = false
SlashCmdList.MSUFSUITEWAY("22 75 20")
assert(placed.mapID == 22 and placed.x == .75 and placed.y == .2
    and tracked and mapOpened, "explicit map waypoint was not tracked")
local oldPoint = placed
SlashCmdList.MSUFSUITEWAY("101 20")
assert(placed == oldPoint and #notices == 1, "out of range coordinates were accepted")
SlashCmdList.MSUFSUITEWAY("secret")
assert(placed == oldPoint and #notices == 2, "unreadable command text was parsed")
SLASH_OTHER2 = "/way"
module:Refresh()
assert(SLASH_MSUFSUITEWAY2 == nil, "existing /way owner was not respected")
module.active = false
module:Disable()
assert(SlashCmdList.MSUFSUITEWAY == nil and SLASH_MSUFSUITEWAY1 == nil,
    "disabling the waypoint helper left a slash alias")
print("Suite waypoint command lifecycle passed")
