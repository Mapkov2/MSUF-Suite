local _, P = ...
local S = P.Suite
local M = {}

-- Blizzard_GroupFinder/Mainline/LFGList.lua (upstream/live) sorts
-- ApplicationViewer.applicants before UpdateResults builds the ScrollBox.
-- Keep its array and its order intact unless every member has a public score.
local function MythicPlusListing()
    local api = _G.C_LFGList
    if not api or type(api.GetActiveEntryInfo) ~= "function"
        or type(api.GetActivityInfoTable) ~= "function" then return false end
    local ok, entry = pcall(api.GetActiveEntryInfo)
    if not ok or not S.Public(entry) or type(entry) ~= "table" then return false end
    local activities = entry.activityIDs
    if not S.Public(activities) or type(activities) ~= "table" then return false end
    local activityID = activities[1]
    if not S.Finite(activityID) then return false end
    local questID = entry.questID
    if not S.Public(questID) then return false end
    local activityOK, activity = pcall(api.GetActivityInfoTable, activityID, questID)
    if not activityOK or not S.Public(activity) or type(activity) ~= "table" then return false end
    local mythic = activity.isMythicPlusActivity
    return S.Public(mythic) and mythic == true
end

local function ApplicantAverage(applicantID)
    local api = _G.C_LFGList
    if not api or type(api.GetApplicantInfo) ~= "function"
        or type(api.GetApplicantMemberInfo) ~= "function" then return nil end
    local ok, info = pcall(api.GetApplicantInfo, applicantID)
    if not ok or not S.Public(info) or type(info) ~= "table" then return nil end
    local count = info.numMembers
    if not S.Finite(count) or count < 1 or count > 5 or count ~= math.floor(count) then return nil end
    local total = 0
    for member = 1, count do
        local memberOK, _name, _class, _localizedClass, _level, _itemLevel,
            _honorLevel, _tank, _healer, _damage, _assignedRole, _relationship, score =
            pcall(api.GetApplicantMemberInfo, applicantID, member)
        if not memberOK or not S.Finite(score) or score < 0 then return nil end
        total = total + score
    end
    return total / count
end

local function VisibleViewer(viewer)
    local frame = _G.LFGListFrame
    if not viewer or not S.Public(viewer) or not frame or not S.Public(frame)
        or not S.Public(frame.ApplicationViewer) or viewer ~= frame.ApplicationViewer
        or type(viewer.IsShown) ~= "function" then return false end
    if type(viewer.IsForbidden) == "function" then
        local forbidden = viewer:IsForbidden()
        if not S.Public(forbidden) or forbidden == true then return false end
    end
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
    local viewer = _G.LFGListFrame and _G.LFGListFrame.ApplicationViewer
    if not VisibleViewer(viewer) or type(_G.LFGListApplicationViewer_UpdateResultList) ~= "function"
        or type(_G.LFGListApplicationViewer_UpdateResults) ~= "function" then return end
    LFGListApplicationViewer_UpdateResultList(viewer)
    LFGListApplicationViewer_UpdateResults(viewer)
end

local function TryHook(self)
    if self.hooked or type(_G.LFGListApplicationViewer_UpdateResultList) ~= "function" then return end
    hooksecurefunc("LFGListApplicationViewer_UpdateResultList", SortAfterNative)
    self.hooked = true
    self.context:RemoveEvent("ADDON_LOADED")
    RefreshViewer()
end

local function OnAddon(self, _, name)
    if S.PublicText(name) == "Blizzard_GroupFinder" then TryHook(self) end
end

function M:Enable()
    if not self.hooked then
        self.context:Event("ADDON_LOADED", OnAddon, true)
        TryHook(self)
    else
        RefreshViewer()
    end
end

function M:Refresh()
    RefreshViewer()
end

function M:Disable()
    self.context:RemoveEvent("ADDON_LOADED")
    RefreshViewer()
end

S.Install("groupFinderApplicantSort", M)
