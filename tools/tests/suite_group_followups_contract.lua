local root = assert(arg[1], "repository root required")
local installed, notices = {}, {}
local suite = {
    Install = function(id, module) installed[id] = module end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value)
        return value ~= "secret" and type(value) == "string" and value ~= "" and value or nil
    end,
    Finite = function(value)
        return value ~= "secret" and type(value) == "number" and value == value
    end,
    Text = function(value) return value end,
    Print = function(value) notices[#notices + 1] = value end,
}
local function context()
    return { events = {},
        Event = function(self, event, fn) self.events[event] = fn end,
        RemoveEvent = function(self, event) self.events[event] = nil end,
    }
end

local activeApps = 0
C_LFGList = { GetNumApplications = function() return 4, activeApps end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupFinderExitReminder.lua"))(
    "MSUF_Suite_QualityOfLife", { Suite = suite })
local finder = assert(installed.groupFinderExitReminder)
finder.active, finder.context = true, context()
finder:Enable()
assert(finder.context.events.ADDON_LOADED)
LFGListFrame = { HookScript = function(self, script, fn)
    assert(script == "OnHide")
    self.onHide = fn
end }
finder.context.events.ADDON_LOADED(finder, "ADDON_LOADED", "Blizzard_GroupFinder")
assert(LFGListFrame.onHide and not finder.context.events.ADDON_LOADED)
LFGListFrame.onHide()
assert(#notices == 0)
activeApps = 2
LFGListFrame.onHide()
assert(#notices == 1 and notices[1] == "2 group applications are still active")
activeApps = "secret"
LFGListFrame.onHide()
assert(#notices == 1, "secret application count was formatted")
finder:Disable()
finder.active = false
activeApps = 1
LFGListFrame.onHide()
assert(#notices == 1, "disabled module still warned")

local grouped, leader, assistant, raid = true, true, false, false
local combat = false
local ns = { IsCombatLocked = function() return combat end }
local expanded, countdown, marked = 0, nil, nil
local managerBlocked = false
local marks = {}
local markBlocked = false
local countdownBlocked = false
SlashCmdList = {}
CompactRaidFrameManager = { IsShown = function() return true end }
CompactRaidFrameManager_Expand = function()
    if managerBlocked then error("restricted manager") end
    expanded = expanded + 1
end
IsInGroup = function() return grouped end
IsInRaid = function() return raid end
UnitIsGroupLeader = function() return leader end
UnitIsGroupAssistant = function() return assistant end
UnitExists = function(unit) return unit == "player" or unit == "party1" end
UnitGroupRolesAssigned = function(unit) return unit == "party1" and "HEALER" or "DAMAGER" end
local guidVersion = 1
UnitGUID = function(unit) return unit .. "-guid" .. guidVersion end
GetRaidTargetIndex = function(unit) return marks[unit] end
SetRaidTarget = function(unit, icon)
    if markBlocked then error("restricted marker") end
    marked = { unit, icon }
    marks[unit] = icon
end
C_PartyInfo = { DoCountdown = function(seconds)
    if countdownBlocked then error("restricted countdown") end
    countdown = seconds
    return true
end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupRaidShortcuts.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local raidTools = assert(installed.groupRaidShortcuts)
raidTools.active, raidTools.config = true, { tankMarker = 4, healerMarker = 6 }
raidTools.context = context()
raidTools:Enable()
assert(SLASH_MSUFSUITERAID1 == "/msufraid" and SLASH_MSUFSUITEPULL1 == "/msufpull"
    and SLASH_MSUFSUITEMARK1 == "/msufmark")
SlashCmdList.MSUFSUITERAID("")
assert(expanded == 1)
managerBlocked = true
local noticesBeforeManager = #notices
SlashCmdList.MSUFSUITERAID("")
assert(expanded == 1 and #notices == noticesBeforeManager + 1,
    "restricted Raid Manager expansion raised an error")
managerBlocked = false
SlashCmdList.MSUFSUITEPULL("")
assert(countdown == 10, "default pull countdown was not started")
countdownBlocked = true
local noticesBeforeCountdown = #notices
SlashCmdList.MSUFSUITEPULL("5")
assert(#notices == noticesBeforeCountdown + 1
    and notices[#notices] == "Countdown could not be started",
    "restricted pull countdown raised an error")
countdownBlocked = false
SlashCmdList.MSUFSUITEMARK("healer")
assert(marked and marked[1] == "party1" and marked[2] == 6)
markBlocked, marks.party1, marked = true, nil, nil
local noticesBeforeMark = #notices
SlashCmdList.MSUFSUITEMARK("healer")
assert(#notices == noticesBeforeMark + 1
    and notices[#notices] == "Raid marker could not be set by the client.",
    "restricted manual raid marker raised an error")
markBlocked = false
marked = nil
leader = false
SlashCmdList.MSUFSUITEMARK("healer")
assert(not marked, "non-leader marked a role")
leader = true
UnitGroupRolesAssigned = function(unit) return unit == "party1" and "secret" or "DAMAGER" end
SlashCmdList.MSUFSUITEMARK("healer")
assert(not marked, "secret role was used to select a unit")
UnitGroupRolesAssigned = function(unit) return unit == "party1" and "HEALER" or "DAMAGER" end
marks, marked = {}, nil
raidTools.config.autoMarkHealer = true
raidTools:Refresh()
assert(marked and marked[1] == "party1" and marked[2] == 6
    and raidTools.context.events.GROUP_ROSTER_UPDATE,
    "opt-in role marker did not mark the unique party healer")
marked, marks.party1 = nil, nil
raidTools.context.events.GROUP_ROSTER_UPDATE(raidTools)
assert(not marked, "automatic marker overrode a manually removed mark")
marks.player = 6
raidTools:Refresh()
assert(not marked, "automatic marker reused a marker occupied by another player")
marks.player = nil
guidVersion = 2
combat = true
raidTools:Refresh()
assert(not marked, "automatic marker changed a protected target in combat")
combat = false
raidTools.context.events.PLAYER_REGEN_ENABLED(raidTools)
assert(marked and marked[1] == "party1", "automatic marker did not resume after combat")
guidVersion, marks.party1, marked, markBlocked = 3, nil, nil, true
local noticesBefore = #notices
raidTools.context.events.GROUP_ROSTER_UPDATE(raidTools)
assert(raidTools.autoBlocked and #notices == noticesBefore + 1,
    "restricted automatic marking did not stop once")
raidTools:Refresh()
raidTools.context.events.GROUP_ROSTER_UPDATE(raidTools)
assert(#notices == noticesBefore + 1, "routine refresh retried a rejected marker")
markBlocked = false
raidTools.config.healerMarker = 5
raidTools:Refresh()
assert(marked and marked[2] == 5, "setting change did not re-enable automatic marking")
raidTools:Disable()
assert(not SlashCmdList.MSUFSUITERAID and not SlashCmdList.MSUFSUITEPULL
    and not SlashCmdList.MSUFSUITEMARK and not SLASH_MSUFSUITERAID1
    and not raidTools.context.events.GROUP_ROSTER_UPDATE)
print("Suite group finder exit, raid shortcuts and optional role markers passed")
