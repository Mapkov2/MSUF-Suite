-- Raid shortcuts with the Retail raid-target index: GetRaidTargetIndex has
-- SecretReturns = true and Nilable = true (upstream/live and upstream/forever
-- RaidMarkersDocumentation.lua), so every marked unit answers a secret and an
-- unmarked one nil. Automatic role markers and /msufmark must still work.
local root = assert(arg[1], "repository root required")

-- A secret: any read other than issecretvalue raises, like the client.
local secrets = setmetatable({}, { __mode = "k" })
local function Raise() error("secret value used", 2) end
local function Secret(value)
    local box = newproxy(true)
    local meta = getmetatable(box)
    for _, key in ipairs({ "__index", "__newindex", "__call", "__concat", "__len", "__lt", "__le",
        "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do meta[key] = Raise end
    meta.__tostring = Raise
    secrets[box] = value
    return box
end
issecretvalue = function(value) return secrets[value] ~= nil end

-- The readers of MSUF_Suite/Core/Platform.lua.
local function Public(value) return not issecretvalue(value) end
local installed, notices = {}, {}
local suite = {
    Install = function(id, module) installed[id] = module end,
    Public = Public,
    PublicText = function(value)
        return Public(value) and type(value) == "string" and value ~= "" and value or nil
    end,
    Finite = function(value)
        return Public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
    end,
    Text = function(value) return value end,
    Print = function(value) notices[#notices + 1] = value end,
    RegisterSlash = function(key, fn) _G["SLASH_" .. key] = fn end,
    UnregisterSlash = function() end,
    QoLRestrictedCall = function(action, ...) action(...); return true end,
}
local ns = {
    GroupActionsRestricted = function() return false end,
    IsCombatLocked = function() return false end,
    RestrictedNotice = function() return "restricted" end,
}

local roles = { player = "DAMAGER", party1 = "TANK" }
local marks, calls = {}, {}
IsInGroup = function() return true end
IsInRaid = function() return false end
UnitIsGroupLeader = function() return true end
UnitIsGroupAssistant = function() return false end
UnitExists = function(unit) return roles[unit] ~= nil end
UnitGroupRolesAssigned = function(unit) return roles[unit] or "NONE" end
UnitGUID = function(unit) return roles[unit] and "Player-1-" .. unit or nil end
GetRaidTargetIndex = function(unit)
    local index = marks[unit]
    if index == nil then return nil end
    return Secret(index)
end
-- Markers are unique in a group: setting one moves it from its old holder.
SetRaidTarget = function(unit, index)
    calls[#calls + 1] = unit .. "=" .. index
    for other, held in pairs(marks) do
        if held == index then marks[other] = nil end
    end
    marks[unit] = index ~= 0 and index or nil
end

assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupRaidShortcuts.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local tools = assert(installed.groupRaidShortcuts)
local events = {}
tools.context = {
    Event = function(_, event, fn) events[event] = fn end,
    RemoveEvent = function(_, event) events[event] = nil end,
}
tools.active = true
tools.config = { showPanel = false, autoMarkTank = true, autoMarkHealer = true, tankMarker = 2, healerMarker = 5 }
tools:Enable()
assert(table.concat(calls, ",") == "party1=2", "the unique tank was not marked")

-- The healer joins after the tank wears its (now unreadable) marker.
roles.party2 = "HEALER"
calls = {}
events.GROUP_ROSTER_UPDATE(tools, "GROUP_ROSTER_UPDATE")
assert(table.concat(calls, ",") == "party2=5",
    "a marker on another member blocked the healer marker: " .. table.concat(calls, ","))

-- A marker someone else placed is unreadable too and does not block automation.
roles.party2, roles.party3 = nil, "HEALER"
marks, calls = { party1 = 2, player = 8 }, {}
events.GROUP_ROSTER_UPDATE(tools, "GROUP_ROSTER_UPDATE")
assert(table.concat(calls, ",") == "party3=5",
    "an unreadable marker on the player blocked automatic markers: " .. table.concat(calls, ","))

-- The marker this module put on the tank stays there when both roles share it.
tools.config.healerMarker = 2
marks, calls = { party1 = 2 }, {}
tools:Refresh()
assert(#calls == 0, "the healer took the marker this module put on the tank: " .. table.concat(calls, ","))

-- /msufmark tank while the tank wears Skull: the configured marker is set.
tools.config.autoMarkTank, tools.config.autoMarkHealer, tools.config.healerMarker = false, false, 5
tools:Refresh()
marks, calls, notices = { party1 = 8 }, {}, {}
SLASH_MSUFSUITEMARK("tank")
assert(table.concat(calls, ",") == "party1=2" and #notices == 0,
    "/msufmark did nothing while the tank wore another marker")

-- The marker /msufmark put on the tank is kept from the other role too.
tools.config.autoMarkHealer, tools.config.healerMarker = true, 2
calls = {}
tools:Refresh()
assert(#calls == 0, "the healer took the marker /msufmark put on the tank: " .. table.concat(calls, ","))

-- The former healer turns DPS and someone puts Skull on it (unreadable): the
-- healer marker this module once set there no longer blocks the new healer.
roles.party3, roles.party2 = "DAMAGER", "HEALER"
tools.config.autoMarkTank, tools.config.healerMarker = true, 5
marks, calls = { party1 = 2, party3 = 8 }, {}
tools:Refresh()
assert(table.concat(calls, ",") == "party2=5",
    "the marker once set on the former healer blocked the new healer: " .. table.concat(calls, ","))

print("suite_group_raid_marker_secret_contract: ok")
