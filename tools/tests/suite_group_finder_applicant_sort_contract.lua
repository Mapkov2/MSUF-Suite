local root = assert(arg[1], "repository root required")
local installed = {}
local suite = {
    Install = function(id, module) installed[id] = module end,
    Public = function(value) return value ~= "secret" end,
    PublicText = function(value)
        return value ~= "secret" and type(value) == "string" and value ~= "" and value or nil
    end,
    Finite = function(value)
        return value ~= "secret" and type(value) == "number" and value == value
            and value > -math.huge and value < math.huge
    end,
}
local function context()
    return {
        events = {},
        Event = function(self, event, callback) self.events[event] = callback end,
        RemoveEvent = function(self, event) self.events[event] = nil end,
    }
end

local hook, hookCount, nativeUpdates, renderUpdates = nil, 0, 0, 0
local nativeEvent, refreshPending, refreshRequests = false, false, 0
hooksecurefunc = function(name, callback)
    assert(name == "LFGListApplicationViewer_UpdateResultList")
    hook, hookCount = callback, hookCount + 1
end

local shown = false
local forbidden = false
local viewer = {
    IsShown = function() return shown end,
    IsForbidden = function() return forbidden end,
}
LFGListFrame = { ApplicationViewer = viewer }
local native = { 101, 103, 102, 104 }
local scores = {
    [101] = { 2000, 1000 }, -- average 1500
    [103] = { 1500 },       -- equal average, native order after 101
    [102] = { 1800 },
    [104] = { 1000 },
}
local mythic, entryCalls, memberCalls = true, 0, 0
C_LFGList = {
    RefreshApplicants = function()
        refreshRequests = refreshRequests + 1
        refreshPending = true
    end,
    GetActiveEntryInfo = function()
        entryCalls = entryCalls + 1
        return { activityIDs = { 77 }, questID = 901 }
    end,
    GetActivityInfoTable = function(id, questID)
        assert(id == 77 and questID == 901)
        return { isMythicPlusActivity = mythic }
    end,
    GetApplicantInfo = function(id)
        return { numMembers = #scores[id] }
    end,
    GetApplicantMemberInfo = function(id, member)
        memberCalls = memberCalls + 1
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, scores[id][member]
    end,
}

-- Blizzard_GroupFinder loads with the Retail UI at startup, before any
-- Suite module enables.
LFGListApplicationViewer_UpdateResultList = function(frame)
    assert(nativeEvent, "Suite rebuilt Blizzard applicants outside the native event")
    nativeUpdates = nativeUpdates + 1
    frame.applicants = {}
    for i, id in ipairs(native) do frame.applicants[i] = id end
    if hook then hook(frame) end
end
LFGListApplicationViewer_UpdateResults = function()
    assert(nativeEvent, "Suite rebuilt Blizzard applicant rows outside the native event")
    renderUpdates = renderUpdates + 1
end
local function NativeListUpdate(render)
    nativeEvent = true
    LFGListApplicationViewer_UpdateResultList(viewer)
    if render then LFGListApplicationViewer_UpdateResults(viewer) end
    nativeEvent = false
end
local function DeliverRefresh()
    assert(refreshPending, "visible viewer did not request a native applicant refresh")
    refreshPending = false
    NativeListUpdate(true)
end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupFinderApplicantSort.lua"))(
    "MSUF_Suite_QualityOfLife", { Suite = suite })
local sorter = assert(installed.groupFinderApplicantSort)
sorter.context, sorter.active = context(), true
sorter:Enable()
assert(hookCount == 1 and not sorter.context.events.ADDON_LOADED,
    "the applicant sort waited for an addon that loads with the UI")
assert(entryCalls == 0 and memberCalls == 0 and nativeUpdates == 0 and refreshRequests == 0,
    "closed viewer performed score or result-list work")

local function order(expected)
    assert(#viewer.applicants == #expected)
    for i, id in ipairs(expected) do
        assert(viewer.applicants[i] == id, "unexpected applicant order at " .. i)
    end
end

shown = true
NativeListUpdate()
order({ 102, 101, 103, 104 })
assert(entryCalls == 1 and memberCalls == 5,
    "score sorting did not inspect every group member once")

scores[104][1] = "secret"
NativeListUpdate()
order(native)
scores[104][1] = nil
NativeListUpdate()
order(native)
scores[104][1] = 1000

mythic = false
local beforeMembers = memberCalls
NativeListUpdate()
order(native)
assert(memberCalls == beforeMembers, "non-Mythic listing read applicant scores")
mythic = true

shown = false
local beforeEntry, beforeMember = entryCalls, memberCalls
NativeListUpdate()
order(native)
assert(entryCalls == beforeEntry and memberCalls == beforeMember,
    "closed viewer queried applicant scores")

shown, forbidden = true, true
beforeEntry, beforeMember = entryCalls, memberCalls
NativeListUpdate()
order(native)
assert(entryCalls == beforeEntry and memberCalls == beforeMember,
    "forbidden viewer queried applicant scores")
forbidden = false

shown = true
sorter.active = false -- Suite clears active before calling Disable.
sorter:Disable()
assert(nativeUpdates == 6 and renderUpdates == 0 and refreshRequests == 1,
    "disable must request a native event without writing the native list or rows")
DeliverRefresh()
order(native)
assert(nativeUpdates == 7 and renderUpdates == 1,
    "native refresh did not restore the visible list after disable")

sorter.active = true
sorter:Enable()
assert(nativeUpdates == 7 and renderUpdates == 1 and refreshRequests == 2,
    "reenable rebuilt the native list before its event")
DeliverRefresh()
order({ 102, 101, 103, 104 })
assert(hookCount == 1 and renderUpdates == 2,
    "reenable should reuse its hook and refresh the visible list")

sorter:Refresh()
assert(nativeUpdates == 8 and renderUpdates == 2 and refreshRequests == 3,
    "profile refresh rebuilt the native list before its event")
DeliverRefresh()
order({ 102, 101, 103, 104 })
assert(hookCount == 1 and renderUpdates == 3,
    "active profile refresh should reuse the hook and refresh the visible list")

-- The reported GROUP_ROSTER_UPDATE was for a normal raid after combat.
-- Native Lua refreshes used to write applicants/provider/row fields even
-- though the score-sort hook does no work for this listing.
mythic = false
beforeEntry, beforeMember = entryCalls, memberCalls
local previousApplicants = viewer.applicants
sorter:Refresh()
assert(viewer.applicants == previousApplicants and nativeUpdates == 9 and renderUpdates == 3,
    "post-combat raid refresh changed Blizzard-owned list state")
assert(entryCalls == beforeEntry and memberCalls == beforeMember and refreshRequests == 4,
    "post-combat raid refresh did not stay a native request")
DeliverRefresh()
order(native)
assert(memberCalls == beforeMember and nativeUpdates == 10 and renderUpdates == 4,
    "raid refresh queried scores or failed to render through the native event")

shown = false
sorter:Refresh()
shown, forbidden = true, true
sorter:Refresh()
forbidden, shown = false, "secret"
sorter:Refresh()
shown, forbidden = true, "secret"
sorter:Refresh()
assert(refreshRequests == 4, "hidden, forbidden or unreadable viewer requested a refresh")
print("applicant sort: native lifecycle refresh, raid regression and score ordering passed")
