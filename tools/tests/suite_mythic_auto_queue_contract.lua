local root = assert(arg[1], "repository root required")
local runtime = arg[2] or root .. "/MSUF_Suite_QualityOfLife/MPlusAutoQueue.lua"
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local SECRET = {}
local function Public(value) return value ~= SECRET end
local function Finite(value)
    return Public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local reported, installed, notices = {}, {}, {}
local calls, apiReads, state = { role = 0 }, 0, {}
local S = {
    Install = function(id, module) installed[id] = module end,
    Public = Public, Finite = Finite,
    PublicText = function(value) return Public(value) and type(value) == "string" and value ~= "" and value or nil end,
    Text = function(value) return value end,
    Print = function(value) notices[#notices + 1] = value end,
}
local NS = {
    Client = { isMainline = true, isForever = false },
    IsSecret = function(value) return value == SECRET end,
    InCombat = function() return state.combat == true or state.lockdown == true end,
    IsCombatLocked = function() return state.lockdown == true end,
    Finish = function(callback, ...) return true, callback(...) end,
    Dispatch = Support.Dispatcher(reported),
}
S.Dispatch = NS.Dispatch
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
InCombatLockdown = function() return state.lockdown == true end
IsInGroup = function(category)
    assert(category == nil or category == LE_PARTY_CATEGORY_HOME, "instance party used for invite ownership")
    return state.grouped
end
UnitIsGroupLeader = function(unit, category)
    assert(unit == "player" and category == LE_PARTY_CATEGORY_HOME, "invite ownership did not use the home party")
    return state.leader
end
GetLFGRoleUpdate = function()
    apiReads = apiReads + 1
    return state.inProgress, 1, 2, 0, state.activityID, false
end
GetLFGRoles = function()
    apiReads = apiReads + 1
    return false, state.tank, state.healer, state.damage
end
LFDPopupCheckRoleSelectionValid = function(tank, healer, damage)
    assert(Public(tank) and Public(healer) and Public(damage), "secret selected role reached native Lua validation")
    return state.rolesValid
end
CompleteLFGRoleCheck = function(accepted)
    assert(accepted == true and not NS.InCombat() and not InCombatLockdown(), "unsafe role acceptance")
    calls.role = calls.role + 1
end
C_LFGList = {
    GetRoleCheckInfo = function()
        apiReads = apiReads + 1
        return state.isLFGList, state.activityID
    end,
    GetActivityInfoTable = function(activityID)
        apiReads = apiReads + 1
        assert(Finite(activityID), "unreadable activity ID reached the native API")
        return state.activities[activityID]
    end,
    GetSearchResultInfo = function(resultID)
        apiReads = apiReads + 1
        assert(Finite(resultID), "unreadable result ID reached the native API")
        return state.results[resultID]
    end,
    GetApplicationInfo = function(resultID)
        apiReads = apiReads + 1
        assert(Finite(resultID), "unreadable result ID reached the native API")
        local app = state.applications[resultID]
        if app then return app.id, app.status, app.pending end
    end,
    -- The reported Retail client blocks this even outside combat. Like a
    -- blocked native action, this records the attempt without raising Lua.
    AcceptInvite = function(resultID)
        calls.blocked = (calls.blocked or 0) + 1
    end,
}
-- Native role selection stays untouched; the helper confirms saved roles.
SetLFGRoles = function() error("automatic queue helper changed saved roles") end
local clock = Support.Clock()
local function Load(client)
    local previous = NS.Client
    NS.Client = client
    installed.mythicAutoQueue = nil
    assert(loadfile(runtime))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
    NS.Client = previous
    return installed.mythicAutoQueue
end
local beforeRead = apiReads
assert(not Load({ isMainline = true, isForever = true }), "Forever installed an M+ queue helper")
assert(apiReads == beforeRead, "Forever queried unavailable M+ queue APIs")
local M = assert(Load(NS.Client), "Retail did not install mythicAutoQueue")
assert(apiReads == beforeRead, "disabled queue helper queried native state")
local context = { events = {} }
function context:Event(event, callback, options)
    self.events[event] = { callback = Support.EventCallback(callback), options = options }
end
function context:RemoveEvent(event) self.events[event] = nil end
M.context = Support.ModuleTimers(root, S, NS)("mythicAutoQueue", M, context)
local function Fire(event, ...)
    local entry = context.events[event]
    if entry then entry.callback(M, event, ...) end
end
local function Frame() clock.Frame() end
local function Reset()
    if M.active then M.active = false; M:Disable(); Frame() end
    state = {
        inProgress = true, isLFGList = true, activityID = 101,
        tank = false, healer = false, damage = true, rolesValid = true,
        grouped = true, leader = false, combat = false, lockdown = false,
        activities = { [101] = { isMythicPlusActivity = true }, [202] = { isMythicPlusActivity = false } },
        results = { [17] = { searchResultID = 17, activityIDs = { 101 } },
            [18] = { searchResultID = 18, activityIDs = { 202 } } },
        applications = { [17] = { id = 17, status = "invited" }, [18] = { id = 18, status = "invited" } },
    }
    M.active, M.config = true, { roleCheck = true, invites = true }
    local before = apiReads
    M:Enable()
    assert(apiReads == before, "Enable accepted or inspected an old queue dialog")
end
local function Role()
    Fire("LFG_ROLE_CHECK_SHOW")
end
local function Invite(id, status)
    Fire("LFG_LIST_APPLICATION_STATUS_UPDATED", id or 17, status or "invited", "applied", "Dungeon group")
end
local function NoRole(why, change)
    Reset(); change()
    local before = calls.role
    Role(); Frame()
    assert(calls.role == before, why)
end
local function NoInvite(why, change, id, status)
    Reset(); state.leader = true; change()
    local before = #notices
    Invite(id, status); Frame()
    assert(#notices == before, why)
end

-- Exact report route: application event -> next-frame timer -> native call.
-- No combat state is involved, and Dispatch cannot make the call permitted.
Reset(); state.grouped = false
Invite(); Frame()
assert((calls.blocked or 0) == 0, "ADDON_ACTION_BLOCKED: timer called C_LFGList.AcceptInvite outside combat")
assert(#notices == 1, "a protected invitation needs a manual-acceptance reminder")

Reset()
assert(context.events.LFG_ROLE_CHECK_SHOW and context.events.LFG_ROLE_CHECK_HIDE
    and context.events.LFG_LIST_APPLICATION_STATUS_UPDATED, "queue events were not registered")
local roleBefore = calls.role
Role(); Role()
assert(calls.role == roleBefore, "role confirmation ran before Blizzard displayed its popup")
Frame()
assert(calls.role == roleBefore + 1, "a group member's M+ role check was not accepted once")
Role(); Frame()
assert(calls.role == roleBefore + 1, "duplicate role events answered the same check twice")
Fire("LFG_ROLE_CHECK_HIDE"); Role(); Frame()
assert(calls.role == roleBefore + 2, "a later role check could not be accepted")

NoRole("ordinary dungeon role check was accepted", function() state.activityID = 202 end)
NoRole("non-premade role check was accepted", function() state.isLFGList = false end)
NoRole("finished role check was accepted", function() state.inProgress = false end)
NoRole("empty selected roles were accepted", function() state.damage = false end)
NoRole("restricted selected roles were accepted", function() state.rolesValid = false end)
NoRole("role confirmation ignored its setting", function() M.config.roleCheck = false end)
NoRole("role confirmation ran at the combat-start edge", function() state.combat = true end)
NoRole("role confirmation ran during lockdown", function() state.lockdown = true end)
for _, key in ipairs({ "inProgress", "isLFGList", "activityID", "tank", "healer", "damage", "rolesValid" }) do
    NoRole("unreadable " .. key .. " accepted a role check", function() state[key] = SECRET end)
end
NoRole("unreadable activity classification accepted a role check", function()
    state.activities[101].isMythicPlusActivity = SECRET
end)
NoRole("unreadable activity table accepted a role check", function() state.activities[101] = SECRET end)
for _, selected in ipairs({ "tank", "healer" }) do
    Reset(); state.damage, state[selected] = false, true; roleBefore = calls.role
    Role(); Frame()
    assert(calls.role == roleBefore + 1, "a valid saved " .. selected .. " role was ignored")
end
Reset(); roleBefore = calls.role; Role(); state.activityID = 202; Frame()
assert(calls.role == roleBefore, "deferred role confirmation did not recheck its activity")
Reset(); roleBefore = calls.role; Role(); state.inProgress = false; Frame()
assert(calls.role == roleBefore, "a role check that finished before the next frame was answered")
Reset(); roleBefore = calls.role; Role(); state.damage = false; Frame()
assert(calls.role == roleBefore, "deferred role confirmation used stale selected roles")
Reset(); roleBefore = calls.role; Role(); Fire("LFG_ROLE_CHECK_HIDE"); Frame()
assert(calls.role == roleBefore, "a closed role check was answered later")

for _, grouped in ipairs({ false, true }) do
    Reset(); state.grouped, state.leader = grouped, true
    local before = #notices
    Invite(); Invite()
    assert(#notices == before, "invite acceptance ran before Blizzard handled its event")
    Frame()
    assert(#notices == before + 1, "solo or home-party leader M+ invite did not produce one reminder")
    Invite(); Frame()
    assert(#notices == before + 1, "duplicate application events accepted the same invitation twice")
end
NoInvite("party member accepted the leader's invitation", function() state.leader = false end)
NoInvite("ordinary dungeon invitation was accepted", function() end, 18)
NoInvite("unrelated application status was accepted", function() end, 17, "applied")
NoInvite("stale invited event accepted a cancelled application", function() state.applications[17].status = "cancelled" end)
NoInvite("already responding application was accepted", function() state.applications[17].pending = "inviteaccepted" end)
NoInvite("mismatched application ID was accepted", function() state.applications[17].id = 999 end)
NoInvite("missing result was accepted", function() state.results[17] = nil end)
NoInvite("missing result activities were accepted", function() state.results[17].activityIDs = nil end)
NoInvite("invitation ignored its setting", function() M.config.invites = false end)
NoInvite("invitation ran at the combat-start edge", function() state.combat = true end)
NoInvite("invitation ran during lockdown", function() state.lockdown = true end)
NoInvite("secret event ID was accepted", function() end, SECRET)
NoInvite("secret event status was accepted", function() end, 17, SECRET)
for _, key in ipairs({ "id", "status", "pending" }) do
    NoInvite("unreadable application " .. key .. " was accepted", function() state.applications[17][key] = SECRET end)
end
for _, key in ipairs({ "grouped", "leader" }) do
    NoInvite("unreadable party " .. key .. " was accepted", function() state[key] = SECRET end)
end
NoInvite("unreadable search result was accepted", function() state.results[17] = SECRET end)
NoInvite("unreadable activity list was accepted", function() state.results[17].activityIDs = SECRET end)
NoInvite("unreadable first activity was accepted", function() state.results[17].activityIDs[1] = SECRET end)
NoInvite("unreadable M+ activity flag was accepted", function() state.activities[101].isMythicPlusActivity = SECRET end)

Reset(); state.leader = true
local inviteBefore = #notices
Invite(); Invite(17, "cancelled"); Frame()
assert(#notices == inviteBefore, "cancelled application event retained a pending acceptance")
Reset(); state.leader = true; inviteBefore = #notices
Invite(); state.applications[17].status = "cancelled"; Frame()
assert(#notices == inviteBefore, "deferred acceptance ignored a cancelled application")
Reset(); state.leader = true; inviteBefore = #notices
Invite(); state.applications[17].pending = "inviteaccepted"; Frame()
assert(#notices == inviteBefore, "deferred acceptance ignored a response already in flight")
Reset(); state.leader = true; inviteBefore = #notices
Invite(); state.results[17].activityIDs[1] = 202; Frame()
assert(#notices == inviteBefore, "deferred acceptance ignored changed result activity")
Reset(); state.leader = true; inviteBefore = #notices
Invite(); state.leader = false; Frame()
assert(#notices == inviteBefore, "deferred acceptance ignored loss of party leadership")
Reset(); state.leader = true; inviteBefore = #notices
Invite(); state.combat = true; Frame(); state.combat = false; Frame()
assert(#notices == inviteBefore, "combat-start deferred invite was accepted or replayed")

Reset(); state.leader = true; inviteBefore = #notices
Invite(18); Invite(17); Frame()
assert(#notices == inviteBefore + 1,
    "a simultaneous non-M+ invitation hid the eligible M+ application")
Reset(); state.leader = true; inviteBefore = #notices
state.results[19] = { searchResultID = 19, activityIDs = { 101 } }
state.applications[19] = { id = 19, status = "invited" }
Invite(17); Invite(19); Frame()
assert(#notices == inviteBefore + 1, "one event burst accepted competing applications")
Invite(17); Invite(19); Frame()
assert(#notices == inviteBefore + 1, "duplicate competing invitations repeated the reminder")

-- A later invitation is not suppressed as if the reminder had joined a group.
Reset(); state.leader = true; inviteBefore = #notices
Invite(17); Frame()
state.results[19] = { searchResultID = 19, activityIDs = { 101 } }
state.applications[19] = { id = 19, status = "invited" }
Invite(19); Frame()
assert(#notices == inviteBefore + 2, "a reminder falsely left a join in progress")
Invite(17, "cancelled"); Invite(17); Frame()
assert(#notices == inviteBefore + 3, "a new invitation after cancellation was suppressed")
assert(notices[#notices] == "Mythic+ invitation received. Accept it in Blizzard's dialog.",
    "invitation reminder did not explain the required manual acceptance")

-- The two switches operate independently.
Reset(); M.config.invites = false; roleBefore = calls.role
Role(); Frame()
assert(calls.role == roleBefore + 1, "disabling invitations also disabled role checks")
Reset(); M.config.roleCheck, state.leader = false, true; inviteBefore = #notices
Invite(); Frame()
assert(#notices == inviteBefore + 1, "disabling role checks also disabled invitations")
for _, stop in ipairs({ "Refresh", "Disable" }) do
    Reset(); state.leader = true
    roleBefore, inviteBefore = calls.role, #notices
    Role(); Invite()
    if stop == "Disable" then M.active = false end
    M[stop](M); Frame()
    assert(calls.role == roleBefore and #notices == inviteBefore, stop .. " retained deferred queue actions")
end
assert(next(context.events) == nil, "disabled helper retained queue listeners")
assert((calls.blocked or 0) == 0, "queue helper attempted protected invitation acceptance")
assert(#reported == 0, "queue callback raised: " .. tostring(reported[1]))
print("suite_mythic_auto_queue_contract: PASS")
