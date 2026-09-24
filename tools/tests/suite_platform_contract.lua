local root = assert(arg[1], "repository root required")
local Suite, reads, frames = {}, 0, 0
local denied = { "old_client_event" }
MSUF_NS = { Client = {
    Family = "Mainline", Flavor = "Mainline", IsForever = true, IsRetail = true,
    SupportsEvent = function(event) return event ~= denied[1] end,
}, L = { ["Active"] = "Aktiv" } }
MapkoSkin = setmetatable({}, { __index = function() error("platform read the skin owner") end })
CreateFrame = function() frames = frames + 1;error("platform allocated a runtime frame") end
C_AddOns = {
    DoesAddOnExist = function(name) reads = reads + 1;return name == "Blizzard_CooldownViewer" end,
    IsAddOnLoaded = function(name) return true, name == "Loaded" end,
}
assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", Suite)
assert(Suite.Client.flavor == "Forever" and Suite.Client.isMainline and not Suite.Client.modernEquipment)
assert(Suite.Client.SupportsEvent("UNIT_AURA") and not Suite.Client.SupportsEvent("old_client_event"))
assert(Suite.Client.HasAddOn("Blizzard_CooldownViewer") and not Suite.Client.HasAddOn("Missing"))
assert(Suite.Client.IsAddOnLoaded("Loaded") and not Suite.Client.IsAddOnLoaded("Incomplete"))
assert(Suite.L == MSUF_NS.L and frames == 0 and reads == 2)
local notifications, owner = 0, {}
Suite.Registry.AddListener(owner, function(who, domain, name)
    assert(who == owner and domain == "profile" and name == "Raid")
    notifications = notifications + 1
end)
Suite.OnProfileChanged("Raid")
assert(notifications == 1)
Suite.Registry.RemoveListener(owner)
Suite.OnProfileChanged("Raid")
assert(notifications == 1 and frames == 0)
assert(Suite.Host.build == "Classic")

-- Main MSUF publishes no client model. The suite derives the same facts from
-- the project ID and Blizzard's Forever marker, and caches event validity.
local function Boot(project, forever)
    local suite, checks = {}, 0
    MSUF_NS = { L = {} }
    WOW_PROJECT_ID, WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = project, 1, 2
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 5, 19
    GameEvent = forever and { RegisterCamelotEvents = function() end } or nil
    C_EventUtils = { IsEventValid = function(event) checks = checks + 1;return event ~= "MISSING_EVENT" end }
    assert(loadfile(root .. "/MSUF_Suite/Core/Platform.lua"))("MSUF_Suite", suite)
    return suite, function() return checks end
end
local main, checks = Boot(1, false)
assert(main.Host.build == "Main" and main.Client.flavor == "Mainline" and main.Client.isMainline)
assert(main.Client.modernEquipment and not main.Client.isForever and not main.Client.isClassic)
assert(main.Client.SupportsEvent("UNIT_AURA") and not main.Client.SupportsEvent("MISSING_EVENT"))
assert(main.Client.SupportsEvent("UNIT_AURA") and checks() == 2, "event validity was not cached")
local forever = Boot(1, true)
assert(forever.Client.flavor == "Forever" and forever.Client.isMainline and not forever.Client.modernEquipment)
local era = Boot(2, true)
assert(era.Client.flavor == "Vanilla" and era.Client.isClassic and not era.Client.isForever)
assert(Boot(5).Client.flavor == "TBC" and Boot(19).Client.flavor == "Mists")
assert(Boot(99).Client.flavor == "Unknown" and frames == 0)
print("Standalone suite platform: Classic and Main hosts, Forever detection, optional-addon queries, locale and removable profile listeners passed")
