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
-- Blizzard_GroupFinder loads with the Retail UI before any Suite module.
LFGListFrame = { HookScript = function(self, script, fn)
    assert(script == "OnHide" and not self.onHide, "the listing frame was hooked twice")
    self.onHide = fn
end }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupFinderExitReminder.lua"))(
    "MSUF_Suite_QualityOfLife", { Suite = suite })
local finder = assert(installed.groupFinderExitReminder)
finder.active, finder.context = true, context()
finder:Enable()
assert(LFGListFrame.onHide and not finder.context.events.ADDON_LOADED,
    "the reminder waited for an addon that loads with the UI")
LFGListFrame.onHide()
assert(#notices == 0)
activeApps = 2
LFGListFrame.onHide()
assert(#notices == 1 and notices[1] == "2 group applications are still active")
activeApps = "secret"
LFGListFrame.onHide()
assert(#notices == 1, "secret application count was formatted")
finder.active = false
finder:Disable()
activeApps = 1
LFGListFrame.onHide()
assert(#notices == 1, "disabled module still warned")
finder.active = true
finder:Enable()

local grouped, leader, assistant, raid = true, true, false, false
local combat = false
-- The real client: a restricted action called by an addon raises
-- ADDON_ACTION_BLOCKED (counted here) and does nothing; Lua sees no error.
Enum = { AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 } }
local restriction = nil
C_RestrictedActions = { IsAddOnRestrictionActive = function(kind) return kind == restriction end }
local function Restricted() return combat or restriction ~= nil end
local blockedCalls = 0
local support = assert(loadfile(root .. "/tools/tests/suite_test_support.lua"))()
local ns = support.Platform(root, { InCombatLockdown = function() return combat end,
    C_RestrictedActions = C_RestrictedActions, Enum = Enum })
ns.IsCombatLocked = function() return combat end
ns.Finish = function(callback, ...) return true, callback(...) end
-- securecallfunction: an error is reported and the call returns nothing.
suite.Dispatch = function(fn, ...)
    local results = { pcall(fn, ...) }
    if results[1] then return unpack(results, 2) end
end
local blockedText = ns.RestrictedNotice()
-- S.QoLRestrictedCall (Bootstrap.lua): true when the call returned without an
-- ADDON_ACTION_BLOCKED refusal; refuseNext makes the client refuse once.
local refuseNext, restrictedCalls = false, 0
suite.QoLRestrictedCall = function(action, ...)
    restrictedCalls = restrictedCalls + 1
    if refuseNext then refuseNext = false; return false end
    action(...)
    return true
end
local expanded, countdown, marked, readyChecks = 0, nil, nil, 0
local managerBroken = false
local marks = {}
-- The client's slash registry (hash and proxy); SlashCommands.lua follows it.
local slash = support.SlashRegistry()
CompactRaidFrameManager = { IsShown = function() return true end }
CompactRaidFrameManager_Expand = function()
    if managerBroken then error("Blizzard raid manager failed") end
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
    if Restricted() then blockedCalls = blockedCalls + 1; return end
    marked = { unit, icon }
    marks[unit] = icon
end
C_PartyInfo = {
    DoCountdown = function(seconds)
        if Restricted() then blockedCalls = blockedCalls + 1; return false end
        countdown = seconds
        return true
    end,
    DoReadyCheck = function()
        if Restricted() then blockedCalls = blockedCalls + 1; return end
        readyChecks = readyChecks + 1
    end,
}
DoReadyCheck = function() error("deprecated DoReadyCheck shim used") end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SlashCommands.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupRaidShortcuts.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = ns, Suite = suite })
local raidTools = assert(installed.groupRaidShortcuts)
raidTools.active, raidTools.config = true, { tankMarker = 4, healerMarker = 6 }
raidTools.context = context()
raidTools:Enable()
assert(SLASH_MSUFSUITERAID1 == "/msufraid" and SLASH_MSUFSUITEPULL1 == "/msufpull"
    and SLASH_MSUFSUITEMARK1 == "/msufmark")
local raidCommand, markCommand = SlashCmdList.MSUFSUITERAID, SlashCmdList.MSUFSUITEMARK
assert(slash.Type("/msufraid") and expanded == 1, "the typed raid command did not run")
managerBroken = true
local noticesBeforeManager = #notices
SlashCmdList.MSUFSUITERAID("")
assert(expanded == 1 and #notices == noticesBeforeManager + 1
    and notices[#notices] == "Raid Manager could not be opened by the client.",
    "a failing Blizzard raid manager stopped the command without a notice")
managerBroken = false
combat = true
SlashCmdList.MSUFSUITERAID("")
assert(expanded == 1 and notices[#notices] == blockedText, "Raid Manager was moved from addon code in combat")
combat = false
SlashCmdList.MSUFSUITEPULL("")
assert(countdown == 10, "default pull countdown was not started")
-- A keystone keeps its restriction between pulls, outside combat.
restriction = Enum.AddOnRestrictionType.ChallengeMode
SlashCmdList.MSUFSUITEPULL("5")
assert(blockedCalls == 0 and countdown == 10 and notices[#notices] == blockedText,
    "pull countdown was called under an addon restriction")
restriction = nil
SlashCmdList.MSUFSUITEMARK("healer")
assert(marked and marked[1] == "party1" and marked[2] == 6)
marks.party1, marked = nil, nil
restriction = Enum.AddOnRestrictionType.Encounter
SlashCmdList.MSUFSUITEMARK("healer")
assert(blockedCalls == 0 and not marked and notices[#notices] == blockedText,
    "manual raid marker was called under an addon restriction")
restriction = nil
SlashCmdList.MSUFSUITEMARK("dps")
assert(notices[#notices] == "Usage: /msufmark tank or /msufmark healer",
    "usage text lost its role names")
marked = nil
leader = false
SlashCmdList.MSUFSUITEMARK("healer")
assert(not marked, "non-leader marked a role")
leader = true
UnitGroupRolesAssigned = function(unit) return unit == "party1" and "secret" or "DAMAGER" end
SlashCmdList.MSUFSUITEMARK("healer")
assert(not marked, "secret role was used to select a unit")
UnitGroupRolesAssigned = function(unit) return unit == "party1" and "HEALER" or "DAMAGER" end
-- A refusal the restriction check could not foresee is reported.
refuseNext = true
SlashCmdList.MSUFSUITEMARK("healer")
assert(not marked and notices[#notices] == "Raid marker could not be set by the client.",
    "a refused raid marker gave no feedback")
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
assert(not marked and blockedCalls == 0, "automatic marker changed a protected target in combat")
combat = false
raidTools.context.events.PLAYER_REGEN_ENABLED(raidTools, "PLAYER_REGEN_ENABLED")
assert(marked and marked[1] == "party1", "automatic marker did not resume after combat")
-- A keystone restriction between pulls: automation stays silent and waits.
guidVersion, marks.party1, marked = 3, nil, nil
restriction = Enum.AddOnRestrictionType.ChallengeMode
local noticesBefore = #notices
raidTools.context.events.GROUP_ROSTER_UPDATE(raidTools)
raidTools.context.events.ROLE_CHANGED_INFORM(raidTools)
assert(blockedCalls == 0 and not marked and #notices == noticesBefore,
    "automatic marking called a restricted marker or announced it")
restriction = nil
raidTools.context.events.PLAYER_REGEN_ENABLED(raidTools, "PLAYER_REGEN_ENABLED")
assert(marked and marked[2] == 6, "automatic marking did not resume after the restriction")
raidTools.config.healerMarker = 5
marks.party1, marked = nil, nil
raidTools:Refresh()
assert(marked and marked[2] == 5, "setting change did not apply the new automatic marker")
-- A refused automatic marker stops automation until the settings change.
raidTools.config.healerMarker = 7
marks.party1, marked = nil, nil
refuseNext = true
raidTools:Refresh()
assert(not marked and raidTools.autoBlocked and notices[#notices] == "Automatic raid markers were blocked by the client.",
    "a refused automatic marker gave no feedback")
local callsBefore = restrictedCalls
-- A new member (new GUID) would be a new attempt; the stop still holds.
guidVersion = guidVersion + 1
raidTools.context.events.GROUP_ROSTER_UPDATE(raidTools)
assert(restrictedCalls == callsBefore and not marked, "automation kept trying after a refusal")
guidVersion = guidVersion - 1
raidTools.config.healerMarker = 5
raidTools:Refresh()
assert(marked and marked[2] == 5 and not raidTools.autoBlocked, "a settings change did not lift the refusal stop")
-- Raid roster storms and members without lead cost no restriction reads:
-- the cheap raid and permission checks come first.
local restrictionReads, isRestricted = 0, C_RestrictedActions.IsAddOnRestrictionActive
C_RestrictedActions.IsAddOnRestrictionActive = function(kind)
    restrictionReads = restrictionReads + 1
    return isRestricted(kind)
end
marks.party1, marked = nil, nil
raid = true
for _ = 1, 20 do raidTools.context.events.GROUP_ROSTER_UPDATE(raidTools) end
raid, leader = false, false
for _ = 1, 20 do raidTools.context.events.GROUP_ROSTER_UPDATE(raidTools) end
leader, guidVersion = true, 4
assert(restrictionReads == 0 and not marked, "a raid or member without lead read the addon restrictions")
raidTools.context.events.GROUP_ROSTER_UPDATE(raidTools)
assert(restrictionReads > 0 and marked and marked[2] == 5, "a party leader marked without the restriction check")
C_RestrictedActions.IsAddOnRestrictionActive = isRestricted
raidTools:Disable()
assert(not SlashCmdList.MSUFSUITERAID and not SlashCmdList.MSUFSUITEPULL
    and not SlashCmdList.MSUFSUITEMARK and not SLASH_MSUFSUITERAID1
    and not raidTools.context.events.GROUP_ROSTER_UPDATE)
assert(not slash.Type("/msufraid") and not slash.Type("/msufmark healer"),
    "the client still ran a command of the disabled module")
-- A handler another addon kept a reference to still explains itself.
raidTools.active = false
noticesBefore = #notices
raidCommand(""); markCommand("healer")
assert(#notices == noticesBefore + 2 and notices[#notices] == "Raid shortcuts are switched off in the MSUF Suite options."
    and expanded == 1, "a cached command of the disabled module was a silent no-op")
raidTools.active = true
print("Suite group finder exit, raid shortcuts and optional role markers passed")

-- Exercise authored secure snippets independently; this is not a live secure-handler test.
local function PanelWidget()
    local w = { attributes = {}, shown = true }
    for _, name in ipairs({ "SetSize", "SetPoint", "ClearAllPoints", "SetScale", "SetAllPoints", "SetColorTexture",
        "SetText", "RegisterForClicks", "SetFrameRef" }) do w[name] = function() end end
    function w:SetScript(name, fn) self[name] = fn end
    function w:SetAttribute(key, value) self.attributes[key] = value end
    function w:GetAttribute(key) return self.attributes[key] end
    function w:Hide() self.shown = false end
    return w
end
suite.CreateFrame, suite.CreateFontString, suite.CreateTexture = PanelWidget, PanelWidget, PanelWidget
suite.SetStyledFont, suite.RegisterOwnedMover = function() end, function() end
suite.GlobalFontPath = function() return "font" end
UIParent = PanelWidget()
RegisterStateDriver = function(frame, _, condition) frame.driver = condition end
UnregisterStateDriver = function(frame) frame.driver = nil end
SecureHandlerWrapScript = function(button, _, control, snippet)
    button.run = function(click)
        local env = { self = button, control = control, math = math, down = false, button = click or "LeftButton" }
        setfenv(assert(loadstring(snippet)), env)()
    end
end
raidTools.config.showPanel, raidTools.config.panelColumns = true, 2
raidTools:Refresh()
assert(#raidTools.panelButtons == 6 and raidTools.panel.driver == "[group] show; hide")
local nextMark, undoMark, clearMarks = raidTools.panelButtons[4], raidTools.panelButtons[5], raidTools.panelButtons[6]
assert(nextMark.attributes.type == "worldmarker" and nextMark.attributes.action == "set")
nextMark.run(); assert(nextMark.attributes.marker == 1)
nextMark.run(); assert(nextMark.attributes.marker == 2)
undoMark.run(); assert(undoMark.attributes.marker == 2 and undoMark.attributes.action == "clear")
nextMark.run(); assert(nextMark.attributes.marker == 2)
for i = 1, 8 do nextMark.run() end
assert(nextMark.attributes.marker == 2 and raidTools.panel.attributes.count == 8)
clearMarks.run(); assert(clearMarks.attributes.marker == nil and raidTools.panel.attributes.count == 0)
undoMark.run(); assert(undoMark.attributes.type == nil, "empty undo must not clear arbitrary marks")
nextMark.run(); assert(nextMark.attributes.marker == 1 and raidTools.panel.attributes.next == 2)
nextMark.run("RightButton")
assert(nextMark.attributes.type == nil and raidTools.panel.attributes.next == 1 and raidTools.panel.attributes.count == 0,
    "rewinding a canceled request must not perform a native set or clear action")
undoMark.run(); assert(undoMark.attributes.type == nil, "rewound canceled step must not clear another marker")
nextMark.run("RightButton"); assert(raidTools.panel.attributes.next == 1, "empty rewind is inert")
nextMark.run(); assert(nextMark.attributes.marker == 1 and nextMark.attributes.type == "worldmarker",
    "next left click must retry the rewound marker")
local readyButton = raidTools.panelButtons[3]
readyButton.OnClick()
assert(readyChecks == 1, "ready check button did not use C_PartyInfo.DoReadyCheck")
restriction = Enum.AddOnRestrictionType.Encounter
readyButton.OnClick()
assert(readyChecks == 1 and blockedCalls == 0 and notices[#notices] == blockedText,
    "ready check was started under an addon restriction")
restriction = nil
raidTools.config.showPanel = false; raidTools:Refresh()
assert(not raidTools.panel.driver and not raidTools.panel.shown)
-- The controller registers the mover after Enable and Refresh
-- (S.RefreshEditMover); the registration stays, so the mover follows the
-- panel option.
local toolMovers = {}
suite.RegisterOwnedMover = function(id, element, spec)
    assert(id == "groupRaidShortcuts")
    toolMovers[element] = spec
end
raidTools:Refresh()
assert(not next(toolMovers), "Refresh registered the mover; the controller does it through RegisterMovers")
raidTools:RegisterMovers()
local tools = assert(toolMovers.tools, "the raid tools mover is missing")
assert(tools.getFrame() == raidTools.panel and not tools.isEnabled(), "a hidden raid tools panel offered its mover")
raidTools.config.showPanel = true; raidTools:Refresh()
assert(tools.isEnabled(), "the shown raid tools panel lost its mover")
raidTools.config.showPanel = false; raidTools:Refresh()
assert(not tools.isEnabled(), "turning the panel off kept its mover")
print("Raid tools panel and authored worldmark sequence/undo/clear snippets passed")
