local root = assert(arg[1], "repository root required")
local Secrets = dofile(root .. "/../MidnightSimpleUnitFrames/tools/tests/classpower_secrets.lua")
Secrets.Install()
Secrets.GUARD_NAMES.falsy.Public = true
local secretNumber, secretText = Secrets.New("number"), Secrets.New("string")
local checks = 0
local function Check(ok, message)
    assert(ok, message)
    checks = checks + 1
end

local world, combat, map, px, py, facing = true, false, 10, .5, .5, 0
local reads, writes, pins, providerReads = 0, 0, 0, 0
local tracking = { { spellID = 2383, active = true }, { spellID = 2580, active = false },
    { spellID = 43308, active = secretNumber }, Secrets.New("table") }
local function WorldRead()
    assert(world, "a gathering API was read inside an instance")
    reads = reads + 1
end
canaccesstable = function(value) return not issecretvalue(value) end
wipe = function(value) for key in pairs(value) do value[key] = nil end return value end
Enum = { UIMapType = { Micro = 5 } }
UIParent = {}
GetPlayerFacing = function() WorldRead() return facing end
local vector = { GetXY = function() return px, py end }
C_Map = {
    GetBestMapForUnit = function() WorldRead() return map end,
    GetPlayerMapPosition = function() WorldRead() return vector end,
    GetMapInfo = function() WorldRead() return { mapType = 3 } end,
    GetMapWorldSize = function() WorldRead() return 1000, 2000 end,
    CanSetUserWaypointOnMap = function() WorldRead() return true end,
    SetUserWaypoint = function() WorldRead() pins = pins + 1 return true end,
}
UiMapPoint = { CreateFromCoordinates = function(...) return { ... } end }
C_Minimap = {
    GetNumTrackingTypes = function() WorldRead() return #tracking end,
    GetTrackingInfo = function(i) WorldRead() return tracking[i] end,
}
C_Spell = { GetSpellName = function(id)
    WorldRead()
    if id == 2366 or id == 2367 then return "Herb Gathering" end
    if id == 2575 or id == 2576 then return "Mining" end
end }

local data, events, after, timers, widget = {}, {}, {}, {}, {}
local function Written() writes = writes + 1 end
widget.__index = widget
function widget:SetPoint() Written() end
function widget:SetSize() Written() end
function widget:SetFrameStrata() end
function widget:EnableMouse(value) self.mouse = value end
function widget:SetShadowOffset() end
function widget:SetWordWrap() end
function widget:SetAtlas(value) self.atlas = value end
function widget:SetText(value) Written() self.text = value end
function widget:SetShown(value) Written() self.shown = value end
function widget:Hide() self:SetShown(false) end
function widget:Show() self:SetShown(true) end
function widget:SetColorTexture() Written() end
function widget:SetVertexColor() Written() end
function widget:SetRotation(value) Written() self.rotation = value end
local function Widget() return setmetatable({}, widget) end
widget.CreateFontString = Widget

local config = { record = true, radar = true, radarRange = 150, herbs = true, ore = true,
    fish = true, timber = true, skinning = true }
local eventOptions = {}
local context = {
    Event = function(_, event, fn, options) events[event], eventOptions[event] = fn, options end,
    RemoveEvent = function(_, event) events[event], eventOptions[event] = nil, nil end,
    Ticker = function(_, _, fn) timers[fn] = true end,
    After = function(_, _, fn) after[fn] = true end,
    Cancel = function(_, fn) timers[fn], after[fn] = nil, nil end,
}
local NS = {
    Client = { isForever = false }, DB = {},
    InCombat = function(event) return combat or event == "PLAYER_REGEN_DISABLED" end,
}
local module, spec, slash
local window = { Hide = function(self) self.shown = false end, SetStatus = function(self, text) self.status = text end }
local S = {
    Public = function(value) return not issecretvalue(value) end,
    Finite = function(value)
        return not issecretvalue(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
    end,
    PublicText = function(value) return not issecretvalue(value) and type(value) == "string" and value ~= "" and value or nil end,
    Text = function(value) return value end,
    InstanceKind = function() return world and "world" or "party" end,
    CharacterData = function() return data end,
    CreateFrame = Widget, CreateTexture = Widget,
    Install = function(_, value) module = value end,
    RegisterSlash = function(_, fn) slash = fn end,
    UnregisterSlash = function() slash = nil end,
    Set = function(_, key, value) config[key] = value module:Refresh() end,
    ToolListWindow = {
        Open = function(_, value) spec = value window.shown = true return window end,
        Refresh = function() end,
        Close = function() window:Hide() end,
    },
}
function S.ReadText(fn, ...) return S.PublicText((fn(...))) end
local P, paths = { NS = NS, Suite = S }, {}
for _, name in ipairs({ "GatheringRouteData", "GatheringRadar", "GatheringArrow", "GatheringRoutes" }) do
    local path = root .. "/MSUF_Suite_QualityOfLife/" .. name .. ".lua"
    assert(loadfile(path))("MSUF_Suite_QualityOfLife", P)
    paths[#paths + 1] = path
end
local stop = Secrets.Watch(paths, { strict = true })
local function Fire(event, ...)
    local fn = assert(events[event], event .. " is not subscribed")
    fn(module, event, ...)
end
local function Tick() local fn = assert(next(timers), "no active ticker") fn(module) end

GatherMate2 = {
    gmdbs = { ["Herb Gathering"] = true, Mining = true, Fishing = true, Logging = true },
    GetNodesForZone = function(_, zone, kind, ignoreFilter)
        WorldRead()
        assert(zone == map and ignoreFilter)
        providerReads = providerReads + 1
        return pairs(kind == "Herb Gathering" and { [1] = 1 } or kind == "Mining" and { [2] = 2 }
            or kind == "Fishing" and { [3] = 3 } or {})
    end,
    DecodeLoc = function(_, value) return .5 + value * .05, .5 end,
    reverseNodeIDs = { ["Herb Gathering"] = {}, Mining = {} },
    GetNameForNode = function(_, _, value) return value == 1 and "Silverleaf" or "Copper Vein" end,
}
module.config, module.context, module.active = config, context, true
world = false
module:Enable()
Check(reads == 0 and not next(timers) and not events.UNIT_SPELLCAST_SENT, "instance login started the feature")
Check(not module:Open() and not window.shown and reads == 0, "instance opened the route tool")
slash("hud")
Check(config.radar and reads == 0, "instance slash changed the feature")

world = true
Fire("PLAYER_ENTERING_WORLD")
Check(events.UNIT_SPELLCAST_SUCCEEDED and module.radar.shown and not module.radar.mouse, "world radar did not start")
Check(module.arrow and module.arrow.shown and module.goal and module.goal.automatic and module.arrow.distance.text == "46 m",
    "the nearest route did not start automatically")
Check(not module.arrow.open and not module.arrow.title and not module.arrow.mouse and not module.radar.label,
    "the arrow showed extra controls or text")
Check(module:Open() == window and #spec.tabs == 6, "Retail professions are missing")
local rows = spec.rows(module)
Check(#rows == 3 and rows[1].label == "Silverleaf · 46 m" and rows[2].label == "Copper Vein · 91 m",
    "distance did not use world width and meters")
Check(spec.status(module):find("Herbalism tracking: active", 1, true)
    and spec.status(module):find("Mining tracking: off", 1, true)
    and spec.status(module):find("Fishing tracking: unavailable", 1, true), "incorrect tracking status")
spec.actions[1].run(module, rows[1], window)
Check(module.arrow.shown and module.arrow.distance.text == "46 m" and pins == 0, "guide did not own its target")
Check(module.arrow.arrow.rotation > math.pi and module.goal.kind == 1, "arrow did not face east")
facing = math.pi
Tick()
Check(module.arrow.arrow.rotation < math.pi, "turning the character did not rotate the arrow")
local beforeWrites, beforeProvider, beforeReads = writes, providerReads, reads
for _ = 1, 200 do Tick() end
Check(writes == beforeWrites and providerReads == beforeProvider, "steady navigation wrote or reloaded source data")
Check(reads == beforeReads + 200 * 3, "arrow and radar did not share one position sample")
facing = secretNumber
Tick()
Check(not module.arrow.shown, "secret facing should hide the arrow")
px = secretNumber
Tick()
Check(not module.arrow.shown and not module.radar.shown, "secret position showed stale navigation")
px, facing = .55, 0
Tick()
Check(module.goal.kind == 2 and module.arrow.distance.text == "46 m", "arrival did not show the next node")
module:Open()
rows = spec.rows(module)
Check(spec.actions[2].enabled(module), "next stop did not advance from the current target")
px = secretNumber
Check(not spec.rows(module) and not spec.actions[2].enabled(module), "private position kept a stale recommendation")
px = .55
rows = spec.rows(module)
Check(spec.actions[2].enabled(module), "next recommendation did not recover at the same position")
px = .6
Tick()
Check(module.goal.kind == 3 and module.arrow.distance.text == "46 m", "next repeated a visited spot before the circuit ended")
module:Open()
rows = spec.rows(module)
spec.actions[3].run(module, rows[1], window)
Check(pins == 1, "explicit map pin failed")
spec.selectTab(module, 2)
Check(#spec.rows(module) == 1 and not spec.status(module):find("Herbalism", 1, true), "profession filter leaked")

Fire("UNIT_SPELLCAST_SENT", "player", secretText, "cast-a", 2576)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-a", 2576)
Check(not data.nodes, "secret target was saved")
Fire("UNIT_SPELLCAST_SENT", "player", "Tin Vein", "cast-b", 2576)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "wrong", 2576)
Check(not data.nodes, "unmatched cast was saved")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-b", 2576)
Check(data.nodes[10][1].name == "Tin Vein", "successful ranked gathering cast was not saved")

module:Open()
spec.selectTab(module, 0)
for _, row in ipairs(spec.rows(module)) do
    if row.node.kind == 3 then spec.actions[1].run(module, row, window) break end
end
combat = true
px = .61
Tick()
Check(module.arrow.shown and module.radar.shown and module.arrow.distance.text == "37 m" and not module:Open(),
    "world combat did not update the owned navigation")
Check(eventOptions.UNIT_SPELLCAST_SENT.inCombat and eventOptions.UNIT_SPELLCAST_SUCCEEDED.inCombat,
    "gathering events are filtered during world combat")
Fire("UNIT_SPELLCAST_SENT", "player", "Iron Deposit", "cast-c", 2576)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-c", 2576)
Check(data.nodes[10][2].name == "Iron Deposit", "public gathering cast was not recorded during combat")
slash("stop")
Check(not module.arrow.shown and module.radar.shown and not module.goal, "stop left the arrow or stopped the radar")
Tick()
Check(not module.goal and not module.arrow.shown, "auto-selection ignored the stop command")
combat = false
Fire("PLAYER_LEAVING_WORLD")
world = false
Fire("PLAYER_ENTERING_WORLD")
Check(not next(timers) and not events.MINIMAP_UPDATE_TRACKING and not events.UNIT_SPELLCAST_SENT
    and not module.goal and not module.arrow.shown and not module.radar.shown and not window.shown, "instance teardown incomplete")
world = true
NS.Client.isForever = true
Fire("PLAYER_ENTERING_WORLD")
module:Refresh()
module:Open()
Check(#spec.tabs == 5 and spec.tabs[5].label == "Skinning profession", "Forever offered Retail timber")
config.herbs, config.ore, config.fish = false, false, false
module:Refresh()
Check(not events.UNIT_SPELLCAST_SENT and #spec.rows(module) == 0, "disabled professions kept working")
module:Disable()
Check(not next(timers) and slash == nil and not window.shown and not module.radar.shown, "disable did not release the feature")
module:Enable()
Check(not module.arrow.shown and not next(timers), "empty zone left a placeholder or timer")
module:Disable()
local provider = GatherMate2
GatherMate2, data.nodes, config.ore, combat = nil, nil, true, true
module:Enable()
Check(not module.goal and not next(timers) and not module.arrow.shown, "empty combat login started a scan or display")
GatherMate2 = provider
Fire("ADDON_LOADED", "GatherMate2")
Check(module.goal and module.goal.automatic and module.arrow.shown,
    "new source data did not start the arrow in open-world combat")
Fire("ZONE_CHANGED")
Check(next(after), "no pending zone update for the instance teardown test")
Fire("PLAYER_LEAVING_WORLD")
world = false
Fire("PLAYER_ENTERING_WORLD")
Check(not next(after) and not next(timers) and not module.arrow.shown and not events.ADDON_LOADED,
    "instance transition did not cancel the automatic route")
module:Disable()
local violations = stop()
Check(#violations == 0, table.concat(violations, "\n"))
print(("Suite gathering guide: %d assertions passed"):format(checks))
