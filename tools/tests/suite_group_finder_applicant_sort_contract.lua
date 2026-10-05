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
    nativeUpdates = nativeUpdates + 1
    frame.applicants = {}
    for i, id in ipairs(native) do frame.applicants[i] = id end
    if hook then hook(frame) end
end
LFGListApplicationViewer_UpdateResults = function()
    renderUpdates = renderUpdates + 1
end
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/GroupFinderApplicantSort.lua"))(
    "MSUF_Suite_QualityOfLife", { Suite = suite })
local sorter = assert(installed.groupFinderApplicantSort)
sorter.context, sorter.active = context(), true
sorter:Enable()
assert(hookCount == 1 and not sorter.context.events.ADDON_LOADED,
    "the applicant sort waited for an addon that loads with the UI")
assert(entryCalls == 0 and memberCalls == 0 and nativeUpdates == 0,
    "closed viewer performed score or result-list work")

local function order(expected)
    assert(#viewer.applicants == #expected)
    for i, id in ipairs(expected) do
        assert(viewer.applicants[i] == id, "unexpected applicant order at " .. i)
    end
end

shown = true
LFGListApplicationViewer_UpdateResultList(viewer)
order({ 102, 101, 103, 104 })
assert(entryCalls == 1 and memberCalls == 5,
    "score sorting did not inspect every group member once")

scores[104][1] = "secret"
LFGListApplicationViewer_UpdateResultList(viewer)
order(native)
scores[104][1] = nil
LFGListApplicationViewer_UpdateResultList(viewer)
order(native)
scores[104][1] = 1000

mythic = false
local beforeMembers = memberCalls
LFGListApplicationViewer_UpdateResultList(viewer)
order(native)
assert(memberCalls == beforeMembers, "non-Mythic listing read applicant scores")
mythic = true

shown = false
local beforeEntry, beforeMember = entryCalls, memberCalls
LFGListApplicationViewer_UpdateResultList(viewer)
order(native)
assert(entryCalls == beforeEntry and memberCalls == beforeMember,
    "closed viewer queried applicant scores")

shown, forbidden = true, true
beforeEntry, beforeMember = entryCalls, memberCalls
LFGListApplicationViewer_UpdateResultList(viewer)
order(native)
assert(entryCalls == beforeEntry and memberCalls == beforeMember,
    "forbidden viewer queried applicant scores")
forbidden = false

shown = true
sorter.active = false -- Suite clears active before calling Disable.
sorter:Disable()
order(native)
assert(nativeUpdates == 7 and renderUpdates == 1,
    "disable did not immediately restore the native visible list")

sorter.active = true
sorter:Enable()
order({ 102, 101, 103, 104 })
assert(hookCount == 1 and renderUpdates == 2,
    "reenable should reuse its hook and refresh the visible list")

-- An active refresh (profile switch, spec variant) changes nothing the hook
-- does not already apply on every native update: Blizzard's viewer rebuild
-- is not run from addon code for it.
sorter:Refresh()
order({ 102, 101, 103, 104 })
assert(hookCount == 1 and renderUpdates == 2 and nativeUpdates == 8,
    "active profile refresh rebuilt Blizzard's applicant viewer from addon code")
