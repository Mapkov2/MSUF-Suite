local root = assert(arg[1], "repository root required")
MSUF_DM_FEATURE_TESTS = true
dofile(root .. "/tools/tests/suite_damage_meter_contract.lua")
local f = assert(MSUF_DM_FIXTURE)
local D, S, api = f.D, f.S, f.api
local forever = arg[2] == "Forever"
f.NS.Client.isForever = forever
local oldRogueSpec = forever and f.Secret("forever native spec") or 236270
local oldDruidSpec = forever and f.Secret("forever native spec") or 136041
local roster = {
    { name = "Rogue", class = "ROGUE", spec = oldRogueSpec, guid = "Player-Rogue", total = 1300, pps = 130 },
    { name = "Other Rogue", class = "ROGUE", spec = oldRogueSpec, guid = "Player-Other", total = 900, pps = 90 },
    { name = "Me", class = "DRUID", spec = 136096, guid = "Player-1", total = 500, pps = 50, isLocal = true },
    { name = "Healer", class = "DRUID", spec = oldDruidSpec, guid = "Player-Healer", total = 300, pps = 30 },
}
local units = { player = "Player-1", party1 = "Player-Rogue", party2 = "Player-Other", raid2 = "Player-Healer" }
local inspected, requests = {}, {}
UnitGUID = function(unit) return units[unit] end
UnitTokenFromGUID = function(guid)
    for unit, current in pairs(units) do if current == guid then return unit end end
end
UnitInAnyGroup = function(unit) return units[unit] ~= nil end
CanInspect = function(unit) return units[unit] ~= nil end
NotifyInspect = function(unit) requests[#requests + 1] = units[unit] end
ClearInspectPlayer = function() end
hooksecurefunc = function(name, hook)
    local original = _G[name]
    _G[name] = function(...) original(...); hook(...) end
end
C_SpecializationInfo = { GetInspectSpecialization = function(unit) return inspected[UnitGUID(unit)] or 0 end }
GetSpecializationInfoByID = function(id)
    return id, "Spec", "", ({ [261] = 132320, [104] = 132276 })[id]
end
CLASS_ICON_TCOORDS.ROGUE = { 0, .25, 0, .25 }
CLASS_ICON_TCOORDS.DRUID = { .25, .5, 0, .25 }
f.SetRoster(roster)
f.SetCombat(false)
f.SetZone("none")
f.SetGroup(true)
f.SetTime(1000)
api.secret, api.empty = false, false
assert(S.SetMany("damageMeter", { enabled = true, windowCount = 2, visibility = D.VISIBILITY.ALWAYS,
    inspectRemoteSpecs = true, iconStyle = D.ICON.SPEC, w1Type = 1, w2Type = 1, w1Session = D.SESSION.CURRENT,
    w2Session = D.SESSION.OVERALL, w1Height = 180, w2Height = 180, w1HideWorld = false, w2HideWorld = false }))
local current, overall = D.windows[1], D.windows[2]
local function Icon(win, index) return win.rows[index].icon.texture end
local recordedIcon = Icon(current, 1)
local recordedHealer = Icon(current, 4)
assert((forever and type(recordedIcon) == "string" or recordedIcon == 236270) and Icon(overall, 1) == recordedIcon,
    "test must start with the recorded Assassination or class icon")
assert(f.Registered("PLAYER_SPECIALIZATION_CHANGED"), "live spec icons must watch remote changes with all role meters set to Keep")
f.Event("PLAYER_SPECIALIZATION_CHANGED", "player")
f.Event("PLAYER_SPECIALIZATION_CHANGED", f.Secret("unit token"))
f.Event("PLAYER_SPECIALIZATION_CHANGED", "party1")
f.RunAfters(.1)
assert(#requests == 1 and requests[1] == "Player-Rogue", "only the changed remote player should be inspected")
assert(type(Icon(current, 1)) == "string", "the invalidated icon should use the class while the new spec is pending")
f.Event("INSPECT_READY", "Player-Other")
assert(Icon(current, 1) ~= 132320, "an unrelated inspect response must not update this row")
inspected["Player-Rogue"] = 261
f.Event("INSPECT_READY", "Player-Rogue")
f.RunPaint()
assert(Icon(current, 1) == 132320 and Icon(overall, 1) == 132320, "both live sessions should update to Subtlety")
assert(Icon(current, 2) == recordedIcon and Icon(current, 3) == 136096, "same-class and local player rows must keep their own icons")
assert(rawequal(current.session.combatSources[1].specIconID, oldRogueSpec) and current.rows[1].bar.value == 1300,
    "the display correction must preserve native records and amounts")

D.SelectSession(overall, D.SESSION.CURRENT, 7, 65)
assert(Icon(overall, 1) == recordedIcon, "a pinned fight keeps its recorded specialization")
f.SetTime(1010)
f.Event("PLAYER_SPECIALIZATION_CHANGED", "raid2")
f.RunAfters(.1)
inspected["Player-Healer"] = 104
f.Event("INSPECT_READY", "Player-Healer")
f.RunPaint()
assert(Icon(current, 4) == 132276, "a raid member changing from Restoration to Guardian should update too")
units.raid2 = "Player-Replacement"
f.Event("GROUP_ROSTER_UPDATE")
f.RunPaint()
assert(Icon(current, 4) == recordedHealer, "a departed group member should return to the recorded specialization")

-- An intervening native Inspect request cancels our association and gets priority.
f.SetTime(1020)
f.Event("PLAYER_SPECIALIZATION_CHANGED", "party1")
f.RunAfters(.1)
assert(#requests == 3 and requests[3] == "Player-Rogue", "second switch should request a fresh inspection")
NotifyInspect("raid2")
f.Event("INSPECT_READY", "Player-Rogue")
f.RunPaint()
assert(type(Icon(current, 1)) == "string" and #requests == 4, "an interrupted reply must not restore the old spec")
f.SetTime(1025)
f.RunAfters(5)
assert(#requests == 5 and requests[5] == "Player-Rogue", "the quiet period must resume the pending inspection")

-- The match is a public GUID lookup only, including when combat hides identities.
f.SetCombat(true)
api.secret = true
f.Event("PLAYER_REGEN_DISABLED")
f.Event("INSPECT_READY", "Player-Rogue")
assert(Icon(current, 1) == recordedIcon and #requests == 5, "restricted rows must use the native icon and defer inspection")
f.SetCombat(false)
api.secret = false
f.Event("PLAYER_REGEN_ENABLED")
f.SetTime(1026)
f.RunAfters(.5)
f.SetTime(1030)
f.RunAfters(4)
assert(#requests == 6 and requests[6] == "Player-Rogue", "combat exit must resume the changed player's inspect")

-- Wait for the native Inspect window to release its buffer, then resume once.
NotifyInspect("raid2")
InspectFrame = { unit = "raid2", IsShown = function() return true end }
f.SetTime(1035)
f.RunAfters(5)
assert(#requests == 7, "a visible native Inspect must keep priority")
InspectFrame = nil
ClearInspectPlayer()
f.SetTime(1040)
f.RunAfters(5)
assert(#requests == 8 and requests[8] == "Player-Rogue", "closing the native Inspect must resume the queued player")
assert(S.Set("damageMeter", "iconStyle", D.ICON.CLASS))
assert(not f.Registered("INSPECT_READY") and not f.Registered("PLAYER_SPECIALIZATION_CHANGED"),
    "class icon mode must release remote spec listeners")
assert(S.Set("damageMeter", "iconStyle", D.ICON.SPEC))
assert(S.Set("damageMeter", "enabled", false))
assert(not f.Registered("INSPECT_READY") and not f.Registered("PLAYER_SPECIALIZATION_CHANGED"), "disabled meter kept its spec listeners")
print("Damage meter remote specialization: changed party and raid GUID, stale snapshot, pinned history, and roster cleanup passed")
