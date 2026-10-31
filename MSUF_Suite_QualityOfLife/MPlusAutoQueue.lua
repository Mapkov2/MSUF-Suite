local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local M = { invited = {}, attempted = {} }

-- Blizzard_GroupFinder loads at startup on Retail. Use its activity facts
-- without changing the native dialogs or their state.
local function MythicActivity(activityID)
    if not S.Finite(activityID) then return false end
    local info = C_LFGList.GetActivityInfoTable(activityID)
    if not S.Public(info) or type(info) ~= "table" then return false end
    local mythic = info.isMythicPlusActivity
    return S.Public(mythic) and mythic == true
end

local function RoleActivity()
    local inProgress, slots = GetLFGRoleUpdate()
    if not S.Public(inProgress) or inProgress ~= true
        or not S.Finite(slots) or slots < 0 then return end
    local isList, activityID = C_LFGList.GetRoleCheckInfo()
    if S.Public(isList) and isList == true and MythicActivity(activityID) then return activityID end
end

local function AcceptRole(self)
    local activityID = self.roleActivity
    self.roleActivity = nil
    if not self.active or not self.config.roleCheck or NS.InCombat()
        or not activityID or self.roleAttempted or RoleActivity() ~= activityID then return end
    local _, tank, healer, damage = GetLFGRoles()
    if not S.Public(tank) or type(tank) ~= "boolean"
        or not S.Public(healer) or type(healer) ~= "boolean"
        or not S.Public(damage) or type(damage) ~= "boolean"
        or not (tank or healer or damage) then return end
    -- The same restriction check enables Blizzard's rolecheck Accept button.
    local ok, valid = S.Dispatch(NS.Finish, LFDPopupCheckRoleSelectionValid, tank, healer, damage)
    if ok ~= true or not S.Public(valid) or valid ~= true then return end
    self.roleAttempted = true
    S.Dispatch(NS.Finish, CompleteLFGRoleCheck, true)
end

local function ClearRole(self)
    self.context:Cancel(AcceptRole)
    self.roleActivity, self.roleAttempted = nil, nil
end

local function OnRoleCheck(self)
    self.context:Cancel(AcceptRole)
    self.roleActivity = nil
    if not self.active or not self.config.roleCheck or self.roleAttempted or NS.InCombat() then return end
    self.roleActivity = RoleActivity()
    if self.roleActivity then
        -- Native SHOW seeds the selected roles and shows the popup. Let that
        -- handler finish before accepting, regardless of event delivery order.
        self.context:After(0, AcceptRole)
    end
end

local function CanJoin()
    local grouped = IsInGroup(LE_PARTY_CATEGORY_HOME)
    if not S.Public(grouped) then return false end
    if grouped == false then return true end
    if grouped ~= true then return false end
    local leader = UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
    return S.Public(leader) and leader == true
end

local function MythicInvite(resultID)
    local id, status, pending = C_LFGList.GetApplicationInfo(resultID)
    if not S.Finite(id) or id ~= resultID or S.PublicText(status) ~= "invited"
        or not S.Public(pending) or pending then return false end
    local result = C_LFGList.GetSearchResultInfo(resultID)
    if not S.Public(result) or type(result) ~= "table" then return false end
    local activities = result.activityIDs
    return S.Public(activities) and type(activities) == "table" and MythicActivity(activities[1])
end

local function NotifyInvitations(self)
    local notify
    if self.active and self.config.invites and not NS.InCombat() and CanJoin() then
        for resultID in pairs(self.invited) do
            if not self.attempted[resultID] and MythicInvite(resultID) then
                self.attempted[resultID], notify = true, true
            end
        end
    end
    for resultID in pairs(self.invited) do self.invited[resultID] = nil end
    -- Retail blocks AcceptInvite from addon callbacks even outside combat.
    -- Keep Blizzard's dialog and its user-click acceptance path untouched.
    if notify then S.Print(S.Text("Mythic+ invitation received. Accept it in Blizzard's dialog.")) end
end

local function OnApplication(self, _, resultID, status)
    if not S.Finite(resultID) or not S.PublicText(status) then return end
    if status ~= "invited" then
        self.invited[resultID], self.attempted[resultID] = nil, nil
        return
    end
    if not self.active or not self.config.invites or self.attempted[resultID] or NS.InCombat() then return end
    self.invited[resultID] = true
    self.context:After(0, NotifyInvitations)
end

function M:Refresh()
    ClearRole(self)
    self.context:Cancel(NotifyInvitations)
    for resultID in pairs(self.invited) do self.invited[resultID] = nil end
    for resultID in pairs(self.attempted) do self.attempted[resultID] = nil end
end

function M:Enable()
    self:Refresh()
    self.context:Event("LFG_ROLE_CHECK_SHOW", OnRoleCheck)
    self.context:Event("LFG_ROLE_CHECK_HIDE", ClearRole)
    self.context:Event("LFG_LIST_APPLICATION_STATUS_UPDATED", OnApplication)
end

function M:Disable()
    self:Refresh()
    self.context:RemoveEvent("LFG_ROLE_CHECK_SHOW")
    self.context:RemoveEvent("LFG_ROLE_CHECK_HIDE")
    self.context:RemoveEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
end

S.Install("mythicAutoQueue", M)
