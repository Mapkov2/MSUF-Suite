local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local module, notices, combat = nil, {}, false
local suite = {
    Install = function(_, value) module = value end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value) return type(value) == "string" and value ~= "secret" and value or nil end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Text = function(value) return value end,
    Print = function(value) notices[#notices + 1] = value end,
    -- MSUF_Suite_Modules/MicroMenu.lua: out of combat lockdown (Retail only).
    CanOpenNativeWindow = function() return not combat end,
}
local slash = Support.SlashRegistry()
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
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SlashCommands.lua"))("MSUF_Suite_QualityOfLife", { Suite = suite })
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/Waypoints.lua"))("MSUF_Suite_QualityOfLife", { Suite = suite })
local events = {}
module.context = {
    Event = function(_, event, callback) events[event] = callback end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
module.config = { superTrack = true, openMap = true }

-- A waypoint addon owns /way and the player already typed in chat, so the
-- client moved its command out of SlashCmdList into the hash and proxy.
local tomtomRuns = 0
local function TomTom() tomtomRuns = tomtomRuns + 1 end
SLASH_TOMTOM_WAY1 = "/way"
SlashCmdList.TOMTOM_WAY = TomTom
slash.Import()
module.active = true
module:Enable()
assert(slash.Type("/way 40 40") and tomtomRuns == 1 and placed == nil,
    "the helper took an imported /way from another addon")
assert(slash.Type("/msufway 30 30") and placed and placed.x == .3, "/msufway did not work beside another /way")
module:Refresh()
assert(slash.Type("/way 41 41") and tomtomRuns == 2, "a settings refresh reclaimed another addon's /way")

-- Disabling releases the typed command, not only the pending list entry.
module.active = false
module:Disable()
assert(not slash.Type("/msufway 10 10") and SLASH_MSUFSUITEWAY1 == nil
    and slash.proxy.MSUFSUITEWAY == nil and rawget(SlashCmdList, "MSUFSUITEWAY") == nil,
    "the disabled helper kept /msufway bound")
assert(slash.Type("/way 42 42") and tomtomRuns == 3, "disabling the helper removed another addon's /way")

-- Without another owner the helper claims /way.
SLASH_TOMTOM_WAY1, slash.proxy.TOMTOM_WAY, hash_SlashCmdList["/WAY"] = nil, nil, nil
module.active = true
module:Enable()
assert(slash.Type("/way 12.5 34,5") and placed.mapID == 11 and placed.x == 0.125 and placed.y == 0.345
    and tracked and not mapOpened, "a free /way did not place a waypoint on the visible map")
-- A comma beside a space separates the numbers; one inside a number is a decimal comma.
for _, case in ipairs({
    { "/way 12.3, 45.6", 11, .123, .456 }, { "/way 12.3 ,45.6", 11, .123, .456 },
    { "/way 12.3,45.6", 11, .123, .456 }, { "/way 12,3 45,6", 11, .123, .456 },
    { "/way 12,3, 45,6", 11, .123, .456 }, { "/way 22 12.3, 45.6", 22, .123, .456 },
}) do
    placed = nil
    slash.Type(case[1])
    assert(placed and placed.mapID == case[2] and math.abs(placed.x - case[3]) < 1e-9
        and math.abs(placed.y - case[4]) < 1e-9, case[1] .. " did not place the waypoint")
end
WorldMapFrame.shown = false
tracked = false
assert(slash.Type("/msufway 22 75 20") and placed.mapID == 22 and placed.x == .75 and placed.y == .2
    and tracked and mapOpened, "explicit map waypoint was not tracked")
-- In combat Blizzard's panel manager refuses the Suite's ToggleWorldMap:
-- the waypoint is placed and the map is left alone.
mapOpened, combat = false, true
assert(slash.Type("/msufway 22 50 50") and placed.x == .5 and not mapOpened,
    "the waypoint command opened the world map from the Suite's code in combat")
combat = false
local oldPoint = placed
slash.Type("/way 101 20")
assert(placed == oldPoint and #notices == 1, "out of range coordinates were accepted")
slash.Type("/way secret")
assert(placed == oldPoint and #notices == 2, "unreadable command text was parsed")

-- Blizzard loads dozens of addons on demand without a /way: the helper
-- neither reads the imported commands again nor registers again.
for i = 1, 200 do
    _G["SLASH_BLIZZARD" .. i .. "1"] = "/blizzard" .. i
    SlashCmdList["BLIZZARD" .. i] = function() end
end
slash.Import()
local slashReads, registers, register = 0, 0, suite.RegisterSlash
suite.RegisterSlash = function(...) registers = registers + 1; return register(...) end
setmetatable(_G, { __index = function(_, key)
    if type(key) == "string" and key:find("^SLASH_") then slashReads = slashReads + 1 end
end })
for _ = 1, 10 do events.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_Collections") end
setmetatable(_G, nil)
suite.RegisterSlash = register
assert(slashReads == 0 and registers == 0,
    "an unrelated addon load read " .. slashReads .. " slash aliases and registered " .. registers .. " times")
assert(slash.Type("/way 45 45") and placed.x == .45, "the helper lost a free /way")
oldPoint = placed
-- An addon loaded later registers /way: it gets the alias at once.
SLASH_TOMTOM_WAY1 = "/way"
SlashCmdList.TOMTOM_WAY = TomTom
events.ADDON_LOADED(module, "ADDON_LOADED", "TomTom")
assert(SLASH_MSUFSUITEWAY1 == "/msufway" and SLASH_MSUFSUITEWAY2 == nil,
    "the helper still lists /way beside the addon that just took it")
assert(slash.Type("/way 43 43") and tomtomRuns == 4 and placed == oldPoint,
    "a later waypoint addon lost /way to the helper")
module.active = false
module:Disable()
assert(slash.Type("/way 44 44") and tomtomRuns == 5 and not slash.Type("/msufway 5 5"),
    "disable did not leave exactly the other addon's /way")

local points, opened, editor, changes = {}, nil, nil, 0
local character = { points = points }
suite.CharacterData = function() return character end
suite.ToolListWindow = {
    Open = function(_, spec) opened = spec end,
    Edit = function(_, spec) editor = spec end,
    Refresh = function() end,
}
C_Map.GetMapInfo = function(id) return { name = "Zone " .. id } end
EventRegistry = { TriggerEvent = function(_, event)
    assert(event == "MSUF_Suite.SavedWaypointsChanged")
    changes = changes + 1
end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/WaypointLists.lua"))("MSUF_Suite_QualityOfLife",
    { NS = { InCombat = function() return combat end }, Suite = suite })
module.active = true
module:Open()
opened.actions[3].run()
assert(editor.multiline)
assert(editor.onSave(module, "/way #11 12.3 45.6\r\n/way 1000 5 5\n/way 11 12,3 45,6\n/way 20 30"))
local preview = opened.rows()
assert(opened.help == "2 new waypoints, 1 invalid lines, 1 duplicates." and #preview == 2
    and preview[2].label:find("^4%.") and #points == 0 and placed == oldPoint,
    "the preview did not preserve source lines or allowed an early save")
opened.actions[1].run()
assert(#points == 2 and points[1].map == 11 and points[2].map == 22
    and points[1].list == "Imported waypoints" and opened.title == "Saved waypoint lists" and changes == 1,
    "the preview did not save exactly the accepted waypoints")
print("Suite waypoint command lifecycle passed")
