local root = assert(arg[1], "repository root required")
local Suite, frames, skinReleases = {}, {}, 0
MSUF_NS = { Client = {
    Family = "Classic", Flavor = "Vanilla", SupportsEvent = function() return true end,
} }
MSUFSuite = Suite
MapkoSkin = setmetatable({}, { __index = function() error("runtime touched the skin provider") end })
SlashCmdList = {}
local pixelVisits = 0
MSUF_PixelLayoutRegion = function(region) pixelVisits = pixelVisits + 1;return region end
CreateFrame = function()
    local frame = { events = {}, registrations = 0, unregistrations = 0 }
    function frame:SetScript(_, callback) self.callback = callback end
    function frame:RegisterEvent(event) self.events[event] = true; self.registrations = self.registrations + 1 end
    function frame:RegisterUnitEvent(event, unit) self.events[event] = unit; self.registrations = self.registrations + 1 end
    function frame:UnregisterEvent(event) self.events[event] = nil; self.unregistrations = self.unregistrations + 1 end
    function frame:UnregisterAllEvents() self.events = {} end
    frames[#frames + 1] = frame
    return frame
end
local cvarValues = { rotateMinimap = "0", combinedBags = "0", autoLootDefault = "0" }
GetCVar = function(key) return cvarValues[key] end
SetCVar = function(key, value) cvarValues[key] = tostring(value) end
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
Support.Load(root, "MSUF_Suite", Suite, "Core/Suite.lua", nil, "Vanilla")
assert(loadfile(root .. "/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite", Suite)
assert(Suite.Database.Initialize(nil))
local private = {}
Support.Load(root, "MSUF_Suite_Modules", private, nil, nil, "Vanilla")
assert(private.NS == Suite and #frames == 0 and pixelVisits == 0)
assert(Suite.Suite.instances.afkScreen and next(Suite.Suite.instances, "afkScreen") == nil,
    "shared runtime registered modules beyond its AFK screen")
Support.Load(root, "MSUF_Suite_QualityOfLife", {}, nil, nil, "Vanilla")
local count = 0
for id in pairs(Suite.Suite.instances) do
    assert(Suite.Suite.catalog[id], "unknown module registration")
    count = count + 1
end
assert(count == 6, "AFK screen and Quality of Life helpers did not register together")
local context = Suite.Suite.NewContext("qol")
assert(context:Skin() == nil, "disabled skin should require no provider")
local module, events = Suite.Suite.instances.qol, 0
module.active = true
context:Event("TEST_EVENT", function(self, event, value)
    assert(self == module and event == "TEST_EVENT" and value == 42)
    events = events + 1
end)
context.frame:callback("TEST_EVENT", 42)
assert(events == 1 and pixelVisits == 1)
context:Event("TEST_EVENT", function(self, event, value)
    assert(self == module and event == "TEST_EVENT" and value == 42)
    events = events + 1
end, true)
context.frame:callback("TEST_EVENT", 42)
assert(events == 2 and context.frame.registrations == 1 and context.combatEvents.TEST_EVENT,
    "refresh re-registered an unchanged event or lost its updated callback")
context:RemoveEvent("TEST_EVENT")
context:RemoveEvent("TEST_EVENT")
context:Event("UNIT_FLAGS", function() end, true, "player")
assert(context.frame.events.UNIT_FLAGS == "player", "a unit event was registered for every unit")
context:RemoveEvent("UNIT_FLAGS")
assert(context.frame.unregistrations == 2, "removing an absent event repeated a native call")
local native = { scale = 1 }
function native:GetScale() return self.scale end
function native:SetScale(value) self.scale = value end
context:Scale(native, 1.3)
assert(native.scale == 1.3 and pixelVisits == 1, "native parent was claimed by suite layout")
context:Release()
assert(native.scale == 1 and not next(context.frame.events) and not next(context.callbacks))
context:Scale(native, 1.2)
native.scale = 1.5
context:Release()
assert(native.scale == 1.5, "release overwrote a later external change")
local paints, released = 0, 0
local owned = {}
context:OwnSkin("SkinFrame", owned, { role = "popup" })
assert(paints == 0)
MapkoSkin = { GetAPI = function()
    return { RegisterAddon = function()
        return { SkinFrame = function(_, target) assert(target == owned);paints = paints + 1 end,
            ReleaseAll = function() released = released + 1 end }
    end }
end }
Suite.Skin.SetEnabled(true)
context:RefreshOwnedSkins()
assert(paints == 1)
Suite.Skin.SetEnabled(false)
assert(released == 1)
Suite.Skin.SetEnabled(true)
context:RefreshOwnedSkins()
assert(paints == 2, "previously created popup lost its skin after toggling")
context:Release()
context:RefreshOwnedSkins()
assert(paints == 3 and released == 2, "module reactivation lost owned popup styling")

-- CVar ownership: a context sets only CVars its module declares, and a saved
-- record is dropped only once it is resolved.
local S = Suite.Suite
local function Saved(id, key)
    local recovery = Suite.RootDB.suiteRecovery and Suite.RootDB.suiteRecovery["Realm/Tester"]
    return recovery and recovery[id] and recovery[id][key]
end
local minimap = S.NewContext("minimap")
assert(S.instances.minimap == nil and not minimap:CVar("autoLootDefault", 1)
    and cvarValues.autoLootDefault == "0" and not Saved("minimap", "autoLootDefault"),
    "a context set a CVar its module never declared")
assert(minimap:CVar("rotateMinimap", 1) and cvarValues.rotateMinimap == "1" and Saved("minimap", "rotateMinimap"))
-- The module addon is not loaded: its catalog entry still hands the CVar back.
S.RestoreSaved("minimap")
assert(cvarValues.rotateMinimap == "0" and not Saved("minimap", "rotateMinimap"),
    "a saved CVar was dropped without being restored while its addon was not loaded")
-- An unreadable value keeps the record for a later attempt.
assert(minimap:CVar("rotateMinimap", 1))
cvarValues.rotateMinimap = nil
S.RestoreCVar("minimap", "rotateMinimap")
assert(Saved("minimap", "rotateMinimap"), "an unrestored CVar record was dropped")
cvarValues.rotateMinimap = "1"
S.RestoreCVar("minimap", "rotateMinimap")
assert(cvarValues.rotateMinimap == "0" and not Saved("minimap", "rotateMinimap"))
-- A later change by the player resolves the record without overwriting it.
assert(minimap:CVar("rotateMinimap", 1))
cvarValues.rotateMinimap = "0"
minimap:Release()
assert(cvarValues.rotateMinimap == "0" and not Saved("minimap", "rotateMinimap"))
-- Records of CVars no loaded code declares are kept for their owner.
Suite.RootDB.suiteRecovery = { ["Realm/Tester"] = { bags = {
    combinedBags = { before = "0", applied = "1" }, unknownCVar = { before = "0", applied = "1" },
} } }
cvarValues.combinedBags = "1"
S.RestoreSaved("bags")
assert(cvarValues.combinedBags == "0" and not Saved("bags", "combinedBags") and Saved("bags", "unknownCVar"),
    "the Bags catalog did not own combinedBags or an unknown record was dropped")
local bagsModule = { cvars = { unknownCVar = true } }
S.instances.bags = bagsModule
cvarValues.unknownCVar = "1"
S.RestoreSaved("bags")
S.instances.bags = nil
assert(cvarValues.unknownCVar == "0" and Suite.RootDB.suiteRecovery["Realm/Tester"] == nil,
    "a module-level cvars declaration did not restore its record")
print("Standalone runtime: AFK screen and " .. (count - 1)
    .. " Quality of Life helpers register without skin or frames; event and property cleanup passed")
