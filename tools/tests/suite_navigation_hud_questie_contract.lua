local root = assert(arg[1], "fixture root required")
local function Forbidden() error("foreign frame or unsafe value inspected") end
local secret = setmetatable({}, { __index = Forbidden, __lt = Forbidden })
local inaccessible = setmetatable({}, { __index = Forbidden })
local function Public(value) return not rawequal(value, secret) end
local function Finite(value) return Public(value) and type(value) == "number" and value - value == 0 end
local function Text(value) if Public(value) and type(value) == "string" and value ~= "" then return value end end
canaccesstable = function(value) return not rawequal(value, inaccessible) end
local callbackCount, hookCount = 0, 0
function hooksecurefunc(owner, key, callback)
    local original = assert(owner[key])
    owner[key] = function(...) original(...); callback(...) end
    hookCount = hookCount + 1
end
local P = { NS = { Client = { isForever = false } }, Suite = { Public = Public, Finite = Finite, PublicText = Text,
    Dispatch = function(callback) callback() end } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/NavigationHUDQuestie.lua"))("Suite", P)
local Q = P.NavigationHUDQuestie
local function Changed() callbackCount = callbackCount + 1 end
local function Read(map)
    local result = {}
    Q.Read(result, map or 1429, function(output, x, y, label, _, kind, texture, left, right, top, bottom, native)
        assert(output == result and x >= 0 and x <= 1 and y >= 0 and y <= 1 and kind == "questie")
        assert(not left and not right and not top and not bottom)
        assert(not result[label], "one map+minimap twin produced two rows")
        result[label] = { x = x, y = y, texture = texture, native = native }
    end)
    return result
end
Q.Watch(Changed)
assert(not next(Read()) and hookCount == 0 and callbackCount == 0)
P.NS.Client.isForever = true

Minimap = {}
local profile = { enabled = true, enableMapIcons = true, enableMiniMapIcons = true }
local ready
Questie = {
    API = { RegisterOnReady = function(callback) assert(not ready); ready = callback end },
    db = { profile = profile }, usedIcons = { [2] = "Questie\Available", objective = 70012 },
    RefreshConfig = function() end,
}
local foreign = {}
local pins = {
    Minimap = Minimap,
    minimapPinRegistry = { [Questie] = {}, [foreign] = {} },
    minimapPins = {},
    worldmapPinRegistry = { [Questie] = {}, [foreign] = {} },
    worldmapPins = {},
}
function pins:AddWorldMapIconMap(owner, frame, map)
    self.worldmapPinRegistry[owner][frame] = true
    self.worldmapPins[frame] = { uiMapID = map, x = 8000, y = 9000 }
end
function pins:AddMinimapIconMap(owner, frame, map)
    self.minimapPinRegistry[owner][frame] = true
    self.minimapPins[frame] = { uiMapID = map, x = 5000, y = 6000 }
end
function pins:RemoveWorldMapIcon(owner, frame)
    self.worldmapPinRegistry[owner][frame], self.worldmapPins[frame] = nil, nil
end
function pins:RemoveMinimapIcon(owner, frame)
    self.minimapPinRegistry[owner][frame], self.minimapPins[frame] = nil, nil
end
function pins:RemoveAllWorldMapIcons(owner)
    for frame in pairs(self.worldmapPinRegistry[owner]) do self.worldmapPins[frame] = nil end
    self.worldmapPinRegistry[owner] = {}
end
function pins:SetMinimapObject(frame) self.Minimap = frame or Minimap end
local waypoints = { OwnerChanged = function() end }
QuestieLoader = { _modules = { HBDPins = pins, QuestieWaypoints = waypoints }, ImportModule = Forbidden }
Q.Watch(Changed)
Q.Watch(Changed)
assert(ready and not next(Read()) and hookCount == 0, "read before Questie initialized")
Questie.API.isReady = true
ready()
assert(callbackCount == 1 and hookCount == 8, "late provider readiness did not arm scoped hooks")
Q.Watch(Changed)
assert(hookCount == 8 and callbackCount == 1, "duplicate watch registration")

local function Frame(label, opts)
    local frame = { UiMapID = 1429, x = 45, y = 55, _loaded = true,
        data = { Name = label, Icon = 2 }, GetTexture = Forbidden, GetPoint = Forbidden, IsVisible = Forbidden, IsForbidden = Forbidden }
    for key, value in pairs(opts or {}) do frame[key] = value end
    return frame
end
local mini = Frame("Available quest")
local world = Frame("Available quest", { minimapTwin = mini })
local manual = Frame("Bank", { isManualIcon = true, data = { Name = "Bank", Icon = "Questie\Gold" }, x = 0, y = 100 })
local objective = Frame("Kill", { data = { QuestData = { Name = "Kill" }, Icon = "objective" } })
local anotherZone = Frame("Other zone", { UiMapID = 99 })
local unknownMap = Frame("Disagreement")
local hidden = Frame("Hidden", { hidden = true })
local secretHidden = Frame("Secret visibility", { hidden = secret })
local noCoordinates = Frame("Secret position", { x = secret })
local negative = Frame("Invalid position", { x = -1 })
local pooled = Frame("Unloaded", { _loaded = false })
pins:AddMinimapIconMap(Questie, mini, 1429)
pins:AddWorldMapIconMap(Questie, world, 1429)
pins:AddWorldMapIconMap(Questie, manual, 1429)
pins:AddWorldMapIconMap(Questie, objective, 1429)
pins:AddWorldMapIconMap(foreign, Frame("Foreign"), 1429)
for _, frame in ipairs({ hidden, secretHidden, noCoordinates, negative, pooled, inaccessible, secret }) do
    pins:AddWorldMapIconMap(Questie, frame, 1429)
end
pins:AddWorldMapIconMap(Questie, anotherZone, 99)
pins:AddWorldMapIconMap(Questie, unknownMap, 99)
assert(callbackCount == 1, "the pending change wasn't coalesced")
local visible = Read()
assert(visible["Available quest"].native == true and visible["Available quest"].texture == "Questie\Available")
assert(visible["Available quest"].x == .45 and visible["Available quest"].y == .55, "raw HBD world values leaked")
assert(visible.Bank.texture == "Questie\Gold" and visible.Bank.x == 0 and visible.Bank.y == 1 and visible.Bank.native == nil)
assert(visible.Kill.texture == 70012)
visible["Available quest"], visible.Bank, visible.Kill = nil, nil, nil
assert(not next(visible), "ineligible or unowned icon reached the Suite")

pins:AddWorldMapIconMap(Questie, Frame("Far", { UiMapID = 60 }), 60)
pins:AddWorldMapIconMap(foreign, Frame("Another foreign"), 1429)
assert(callbackCount == 1, "unrelated provider changes woke the active map")
mini.hidden = true
waypoints.OwnerChanged(mini)
assert(callbackCount == 2 and Read()["Available quest"].native == nil, "hiding the mini twin left a stale native flag")
mini.hidden = nil
waypoints.OwnerChanged(mini)
assert(callbackCount == 3 and Read()["Available quest"].native == true)
pins:SetMinimapObject({})
assert(callbackCount == 4 and Read()["Available quest"].native == nil, "replacement minimap was treated as Blizzard's")
pins:SetMinimapObject(nil)
assert(callbackCount == 5 and Read()["Available quest"].native == true)

profile.enableMiniMapIcons = false
Questie:RefreshConfig()
assert(callbackCount == 6 and Read()["Available quest"].native == false,
    "mappable world pin did not report the readably disabled built-in minimap route")
profile.enableMiniMapIcons = secret
assert(Read()["Available quest"].native == nil, "a restricted toggle was treated as disabled")
profile.enableMiniMapIcons = nil
assert(Read()["Available quest"].native == nil, "a missing toggle was treated as disabled")
profile.enableMapIcons, profile.enableMiniMapIcons = false, true
Questie:RefreshConfig()
visible = Read()
assert(visible["Available quest"].native == true and not visible.Bank, "map-only provider bypassed its toggle")
profile.enabled = false
Questie:RefreshConfig()
assert(not next(Read()))

profile.enabled, profile.enableMapIcons = true, true
Questie.enabledState = false
assert(not next(Read()))
Questie.enabledState = true
pins:RemoveMinimapIcon(Questie, mini)
assert(Read()["Available quest"].native == nil)
pins:RemoveWorldMapIcon(Questie, world)
assert(not Read()["Available quest"])
pins:RemoveAllWorldMapIcons(Questie)
assert(not next(Read()))
Q.Watch(nil)
local count = callbackCount
pins:AddWorldMapIconMap(Questie, manual, 1429)
waypoints.OwnerChanged(manual)
Questie:RefreshConfig()
assert(callbackCount == count, "stopped source still woke the HUD")
Q.Watch(Changed)
assert(callbackCount == count + 1 and hookCount == 8 and Read().Bank)
P.NS.Client.isForever = false
assert(not next(Read()))
print("Questie HUD source ownership, visibility, coordinates and late-load lifecycle passed")
