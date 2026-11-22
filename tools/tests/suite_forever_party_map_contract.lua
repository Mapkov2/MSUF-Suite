local root = assert(arg[1], "repository root required")
local source = root .. "/MSUF_Suite_QualityOfLife/ForeverPartyMap.lua"
local secret = setmetatable({}, { __index = function() error("restricted map data read") end })
local sealed = setmetatable({}, getmetatable(secret))
local function Public(value) return value ~= secret end
local function Finite(value) return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge end
local function PublicText(value) return Public(value) and type(value) == "string" and value ~= "" and value or nil end
function canaccesstable(value) return value ~= sealed end

local function Widget(parent)
    return {
        parent = parent,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown == true end,
        SetPoint = function(self, ...) self.point = { ... } end,
        SetText = function(self, text) self.text = text end,
        SetSize = function(self, w, h) self.width, self.height = w, h end,
        SetWidth = function(self, width) self.width = width end,
        SetHeight = function(self, height) self.height = height end,
        SetFrameLevel = function(self, level) self.level = level end,
        EnableMouse = function(self, enabled) assert(enabled == false, "overlay must pass map input through") end,
        SetVertexColor = function() end, SetColorTexture = function() end, SetAllPoints = function() end,
        SetAtlas = function() end, SetJustifyH = function() end, SetWordWrap = function() end, SetTextColor = function() end,
    }
end
local map, canvas, viewport = Widget(), Widget(), Widget()
WorldMapFrame = map
local scripts, hooks = {}, {}
map.id, map.scale = 101, 1
function map:GetMapID() return self.id end
function map:GetCanvas() return canvas end
function map:GetCanvasContainer() return viewport end
function map:GetCanvasScale() return self.scale end
function map:GetPinFrameLevelsManager() return self end
function map:GetValidFrameLevel(key) assert(key == "PIN_FRAME_LEVEL_GROUP_MEMBER"); return 20 end
function map:HookScript(event, callback) assert(not scripts[event]); scripts[event] = callback end
function canvas:GetSize() return 1000, 500 end
function hooksecurefunc(frame, name, callback)
    assert(frame == map and not hooks[name], "unrelated or duplicate map hook")
    hooks[name] = callback
end

local count, raid, loaded, calls = 2, false, false, 0
local zones = { party1 = 101, party2 = 102 }
local names = { party1 = "Aria", party2 = "Borin" }
local connections = { party1 = true, party2 = true }
local infos = {
    [101] = { name = "Elwynn", parentMapID = 201 },
    [102] = { name = "Dun Morogh", parentMapID = 201 },
    [201] = { name = "Eastern Kingdoms", parentMapID = 301 },
    [301] = { name = "Azeroth" },
    [405] = sealed,
}
local position = { x = .2, y = .5 }
local unitPosition = { party1 = position, party2 = position }
local worldPosition = { x = .32, y = .64 }
GetNumSubgroupMembers = function() calls = calls + 1; return count end
IsInRaid = function() return raid end
UnitName = function(unit) return names[unit] end
UnitIsConnected = function(unit) return connections[unit] end
UnitClass = function() return nil, "MAGE" end
GetClassColor = function(class) assert(class == "MAGE"); return .25, .78, .92 end
UNKNOWN, UNKNOWNOBJECT, PLAYER_OFFLINE = "Unknown location", "Unknown member", "Offline"
C_Map = {
    GetMapInfo = function(id) assert(Finite(id)); return infos[id] end,
    GetMapDisplayInfo = function(id) return id == 201 or id == 301 or id == 406 end,
    GetBestMapForUnit = function(unit) return zones[unit] end,
    GetPlayerMapPosition = function(id, unit)
        assert(Finite(id))
        if id == 301 and unit == "party1" then return worldPosition end
        if id == 406 then return position end
        if id == zones[unit] then return unitPosition[unit] end
    end,
    GetMapRectOnMap = function(id, shown)
        assert(infos[id].parentMapID == shown or shown == 301, "attempted projection onto unrelated map")
        if id == 101 then return .1, .6, .2, .6 end
        return .5, .9, .4, .6
    end,
}

local module, events, after, tick = nil, {}, {}, {}
local context = {
    Event = function(_, event, fn) events[event] = fn end,
    RemoveEvent = function(_, event) events[event] = nil end,
    After = function(_, delay, fn) assert(delay == 0); after[fn] = true end,
    Ticker = function(_, interval, fn) assert(interval > 0); tick[fn] = true end,
    Cancel = function(_, fn) after[fn], tick[fn] = nil, nil end,
}
local suite = {
    Public = Public, Finite = Finite, PublicText = PublicText,
    CreateFrame = function(_, _, parent) return Widget(parent) end,
    CreateFontString = Widget, CreateTexture = Widget,
    Install = function(id, candidate) assert(id == "foreverPartyMap"); module = candidate end,
}
local private = {
    NS = {
        Client = { isForever = false, IsAddOnLoaded = function() return loaded end },
        Safety = {},
    },
    Suite = suite,
}
local function MapID(id)
    map.id = id
    hooks.OnMapChanged(map)
end
local function Flush()
    local pending = after
    after = {}
    for fn in pairs(pending) do fn(module) end
end
local function Tick()
    for fn in pairs(tick) do fn(module) end
end

assert(loadfile(source))("QualityOfLife", private)
assert(not module, "Retail must not install the Forever feature")
private.NS.Client.isForever = true
assert(loadfile(source))("QualityOfLife", private)
module.active, module.context = true, context
module:Enable()
assert(events.ADDON_LOADED and not module.list and not next(tick), "cold start waits for the native map")
loaded = true
events.ADDON_LOADED(module, "ADDON_LOADED", "Blizzard_WorldMap")
assert(not events.ADDON_LOADED and not next(tick), "closed map remains idle")

map:Show()
scripts.OnShow(map)
assert(not module.list and next(tick), "initial painting must run outside Blizzard's OnShow")
Flush()
assert(module.list:IsShown() and module.list.parent == viewport, "party stays attached to the viewport")
assert(module.rows[1].location.text == "Elwynn" and module.rows[2].location.text == "Dun Morogh")
assert(not next(module.pins), "never duplicate same-map native pins or pin an off-map member")

MapID(201)
Flush()
local first, second = module.pins[1].frame, module.pins[2].frame
assert(first:IsShown() and second:IsShown(), "valid missing positions are projected onto the continent")
assert(math.abs(first.point[4] - 200) < .001 and math.abs(first.point[5] + 200) < .001)
map.scale = 2
hooks.OnCanvasScaleChanged(map)
assert(first.width == 6 and first.point[4] == 200, "canvas zoom keeps the coordinates and the visible icon size")

MapID(301)
assert(not first:IsShown() and not second:IsShown(), "old marker positions must clear during the map transition")
Flush()
assert(first:IsShown() and second:IsShown(), "a world map with native icons suppressed retains verified positions")
assert(first.point[4] == 320 and first.point[5] == -320, "prefer the current map's direct coordinates")
worldPosition = { x = 0, y = 0 }
unitPosition.party1 = sealed
Tick()
assert(not first:IsShown() and second:IsShown(), "missing or restricted positions clear old markers without affecting other members")
MapID(406)
Flush()
assert(module.list:IsShown() and not first:IsShown() and not second:IsShown(),
    "in-bounds world coordinates must not put players on a different floor")
MapID(404)
Flush()
assert(module.list:IsShown() and not first:IsShown() and not second:IsShown(), "unrelated maps still show names and zones")
zones.party1, unitPosition.party2 = secret, secret
names.party1, connections.party1 = secret, secret
zones.party2 = 405
Tick()
assert(module.rows[1].name.text == UNKNOWNOBJECT and module.rows[2].location.text == UNKNOWN,
    "restricted and inaccessible locations cannot leak or break the list")
connections.party1 = false
Tick()
assert(module.rows[1].location.text == UNKNOWN, "an unpopulated unit token is not an offline player")
names.party1 = "Aria"
Tick()
assert(module.rows[1].location.text == PLAYER_OFFLINE, "offline members are listed without stale coordinates")

count = 1
events.GROUP_ROSTER_UPDATE(module)
Flush()
assert(not module.rows[2].name:IsShown() and not second:IsShown(), "leaving members are removed immediately")
raid = true
events.GROUP_ROSTER_UPDATE(module)
Flush()
assert(not module.list:IsShown() and not next(tick), "raid mode leaves the native raid map alone")
raid = false
events.GROUP_ROSTER_UPDATE(module)
assert(next(after) and next(tick))
map:Hide()
scripts.OnHide(map)
assert(not next(after) and not next(tick) and not events.GROUP_ROSTER_UPDATE, "closing the map stops all party queries")
local oldCalls = calls
Flush()
Tick()
assert(calls == oldCalls)

map:Show()
scripts.OnShow(map)
Flush()
module.active = false
module:Disable()
assert(not module.list:IsShown() and not next(tick))
module.active = true
module:Enable()
Flush()
assert(module.list:IsShown(), "re-enable reuses the current map and the overlay without duplicate hooks")
print("PASS: Forever party map lifecycle, projection, secrets and visible roster")
