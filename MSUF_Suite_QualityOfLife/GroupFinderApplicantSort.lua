local _, P = ...
local S = P.Suite
local M = {}

-- Blizzard_GroupFinder/Mainline/LFGList.lua (upstream/live) sorts
-- ApplicationViewer.applicants before UpdateResults builds the ScrollBox.
-- Keep its array and its order intact unless every member has a public score.
-- Group Finder loads with the Retail UI at startup; this module is Retail-only.
local function MythicPlusListing()
    local entry = C_LFGList.GetActiveEntryInfo()
    if not S.Public(entry) or type(entry) ~= "table" then return false end
    local activities = entry.activityIDs
    if not S.Public(activities) or type(activities) ~= "table" then return false end
    local activityID = activities[1]
    if not S.Finite(activityID) then return false end
    local questID = entry.questID
    if not S.Public(questID) then return false end
    local activity = C_LFGList.GetActivityInfoTable(activityID, questID)
    if not S.Public(activity) or type(activity) ~= "table" then return false end
    local mythic = activity.isMythicPlusActivity
    return S.Public(mythic) and mythic == true
end

local function ApplicantAverage(applicantID)
    local info = C_LFGList.GetApplicantInfo(applicantID)
    if not S.Public(info) or type(info) ~= "table" then return nil end
    local count = info.numMembers
    if not S.Finite(count) or count < 1 or count > 5 or count ~= math.floor(count) then return nil end
    local total = 0
    for member = 1, count do
        local _name, _class, _localizedClass, _level, _itemLevel, _honorLevel, _tank,
            _healer, _damage, _assignedRole, _relationship, score =
            C_LFGList.GetApplicantMemberInfo(applicantID, member)
        if not S.Finite(score) or score < 0 then return nil end
        total = total + score
    end
    return total / count
end

local function VisibleViewer(viewer)
    if viewer ~= LFGListFrame.ApplicationViewer then return false end
    local forbidden = viewer:IsForbidden()
    if not S.Public(forbidden) or forbidden == true then return false end
    local shown = viewer:IsShown()
    return S.Public(shown) and shown == true
end

local function SortAfterNative(viewer)
    if not M.active or not VisibleViewer(viewer) or not MythicPlusListing() then return end
    local applicants = viewer.applicants
    if not S.Public(applicants) or type(applicants) ~= "table" or #applicants < 2 then return end

    local scores, nativeIndex = {}, {}
    for index = 1, #applicants do
        local id = applicants[index]
        if not S.Finite(id) or nativeIndex[id] then return end
        local score = ApplicantAverage(id)
        if score == nil then return end
        scores[id], nativeIndex[id] = score, index
    end
    table.sort(applicants, function(left, right)
        if scores[left] ~= scores[right] then return scores[left] > scores[right] end
        return nativeIndex[left] < nativeIndex[right]
    end)
end

local function RefreshViewer()
    local viewer = LFGListFrame.ApplicationViewer
    if not VisibleViewer(viewer) then return end
    -- Use the native Refresh button's C request (upstream/live LFGList.xml).
    -- Calling the Lua updates here taints applicants and rendered row fields;
    -- GROUP_ROSTER_UPDATE later reads those before UpdateInfo tests secrets.
    C_LFGList.RefreshApplicants()
end

function M:Enable()
    if not self.hooked then
        hooksecurefunc("LFGListApplicationViewer_UpdateResultList", SortAfterNative)
        self.hooked = true
    end
    RefreshViewer()
end

function M:Refresh()
    RefreshViewer()
end

function M:Disable()
    RefreshViewer()
end

S.Install("groupFinderApplicantSort", M)
