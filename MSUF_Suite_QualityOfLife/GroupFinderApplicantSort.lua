local _, P = ...
local NS, S = P.NS, P.Suite
local View = P.ApplicantView
local M = { entries = {}, pool = {} }

-- Blizzard_GroupFinder/Mainline/LFGList.lua (upstream/live) sorts
-- ApplicationViewer.applicants before UpdateResults builds the ScrollBox.
-- Read its array without changing it; only the Suite's companion view sorts.
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
    local total, name = 0, nil
    for member = 1, count do
        local _name, _class, _localizedClass, _level, _itemLevel, _honorLevel, _tank,
            _healer, _damage, _assignedRole, _relationship, score =
            C_LFGList.GetApplicantMemberInfo(applicantID, member)
        if not S.Finite(score) or score < 0 then return nil end
        total = total + score
        if member == 1 then name = S.PublicText(_name) end
    end
    return total / count, name or UNKNOWN, count
end

local function VisibleViewer(viewer)
    if viewer ~= LFGListFrame.ApplicationViewer then return false end
    local forbidden = viewer:IsForbidden()
    if not S.Public(forbidden) or forbidden == true then return false end
    local shown = viewer:IsShown()
    return S.Public(shown) and shown == true
end

function M:CanAct()
    return VisibleViewer(LFGListFrame.ApplicationViewer) and MythicPlusListing()
end

local function HigherScore(left, right)
    if left.score ~= right.score then return left.score > right.score end
    return left.nativeIndex < right.nativeIndex
end

local function SortAfterNative(viewer)
    if not M.active or NS.InCombat() or not VisibleViewer(viewer) or not MythicPlusListing() then
        View.Hide()
        return
    end
    local applicants = viewer.applicants
    if not S.Public(applicants) or type(applicants) ~= "table" or #applicants < 2 then
        View.Hide()
        return
    end
    local entries, seen = M.entries, {}
    for index = 1, #applicants do
        local id = applicants[index]
        if not S.Finite(id) or seen[id] then
            View.Hide()
            return
        end
        local score, name, count = ApplicantAverage(id)
        if score == nil then
            View.Hide()
            return
        end
        local entry = M.pool[index]
        if not entry then
            entry = {}
            M.pool[index] = entry
        end
        entry.id, entry.score, entry.name, entry.nativeIndex = id, score, string.format("%s (%d)", name, count), index
        entries[index], seen[id] = entry, true
    end
    for index = #entries, #applicants + 1, -1 do entries[index] = nil end
    table.sort(entries, HigherScore)
    View.Show(M, entries)
end

local function RefreshViewer()
    local viewer = LFGListFrame.ApplicationViewer
    if not VisibleViewer(viewer) then return end
    -- Use the native Refresh button's C request (upstream/live LFGList.xml).
    -- Calling the Lua updates here taints applicants and rendered row fields;
    -- GROUP_ROSTER_UPDATE later reads those before UpdateInfo tests secrets.
    C_LFGList.RefreshApplicants()
end

local function UpdateView()
    SortAfterNative(LFGListFrame.ApplicationViewer)
end

local function QueueView()
    if M.active then M.refreshJob:Request() end
end

function M:Enable()
    local update = self.context:Coalesce(0, UpdateView)
    self.refreshJob = update
    if not self.hooked then
        hooksecurefunc("LFGListApplicationViewer_UpdateResultList", SortAfterNative)
        LFGListFrame.ApplicationViewer:HookScript("OnHide", View.Hide)
        LFGListFrame.ApplicationViewer:HookScript("OnShow", QueueView)
        self.hooked = true
    end
    self.context:Event("LFG_LIST_APPLICANT_UPDATED", update)
    self.context:Event("LFG_LIST_ACTIVE_ENTRY_UPDATE", update)
    self.context:Event("GROUP_ROSTER_UPDATE", update)
    self.context:Event("PLAYER_REGEN_DISABLED", View.Hide)
    self.context:Event("PLAYER_REGEN_ENABLED", update)
    RefreshViewer()
    SortAfterNative(LFGListFrame.ApplicationViewer)
end

function M:Refresh()
    RefreshViewer()
    SortAfterNative(LFGListFrame.ApplicationViewer)
end

function M:Disable()
    View.Hide()
end

S.Install("groupFinderApplicantSort", M)
