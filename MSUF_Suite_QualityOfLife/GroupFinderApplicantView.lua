local _, P = ...
local NS, S = P.NS, P.Suite
local View = { rows = {}, offset = 0 }
P.ApplicantView = View
local PAGE_SIZE, ROW_HEIGHT = 10, 30

-- Only our rows are reordered. Blizzard retains its applicants, ScrollBox,
-- selection and row fields. Actions use the same native C requests as its
-- buttons (Blizzard_GroupFinder/Mainline/LFGList.xml), with fresh validation.
local function Empowered()
    local leader = UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
    if not S.Public(leader) then return false end
    if leader == true then return true end
    local assistant = UnitIsGroupAssistant("player", LE_PARTY_CATEGORY_HOME)
    return S.Public(assistant) and assistant == true
end

local function ActionInfo(id, checkListing)
    if not View.owner.active or NS.InCombat() or not View.frame:IsShown() then return nil end
    if (checkListing and not View.owner:CanAct()) or not Empowered() then return nil end
    local info = C_LFGList.GetApplicantInfo(id)
    if not S.Public(info) or type(info) ~= "table" then return nil end
    local status, pending, informational = info.applicationStatus, info.pendingApplicationStatus, info.applicantInfo
    if not S.Public(status) or not S.Public(pending) or not S.Public(informational) then return nil end
    if status ~= "applied" or pending or informational then return nil end
    local count = info.numMembers
    if not S.Finite(count) or count < 1 or count > 5 or count ~= math.floor(count) then return nil end
    return count
end

-- Native UpdateInviteState counts current AND already invited members against
-- the listing limit. Unknown/restricted inputs leave our Invite disabled.
local function InviteCapacity()
    local entry = C_LFGList.GetActiveEntryInfo()
    if not S.Public(entry) or type(entry) ~= "table" then return nil end
    local ids, quest = entry.activityIDs, entry.questID
    if not S.Public(ids) or type(ids) ~= "table" or not S.Public(quest) then return nil end
    local id = ids[1]
    if not S.Finite(id) then return nil end
    local activity = C_LFGList.GetActivityInfoTable(id, quest)
    if not S.Public(activity) or type(activity) ~= "table" then return nil end
    local limit = activity.maxNumPlayers
    if not S.Finite(limit) or limit < 0 then return nil end
    if limit == 0 then limit = MAX_RAID_MEMBERS end
    -- This view handles Mythic+ parties only; it never converts to a raid.
    -- A native activity with no size limit must still respect party capacity.
    limit = math.min(limit, MAX_PARTY_MEMBERS + 1)
    local current = GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)
    local invited = C_LFGList.GetNumInvitedApplicantMembers()
    if not S.Finite(current) or current < 0 or not S.Finite(invited) or invited < 0 then return nil end
    return limit - current - invited
end

local function Invite(self)
    local id = self.row.applicantID
    local count = id and ActionInfo(id, true)
    if not count then return end
    local capacity = InviteCapacity()
    if capacity and count <= capacity then C_LFGList.InviteApplicant(id) end
end

local function Decline(self)
    local id = self.row.applicantID
    if id and ActionInfo(id, true) then C_LFGList.DeclineApplicant(id) end
end

local function Button(row, text, width, x, callback)
    local button = S.CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetPoint("RIGHT", row, "RIGHT", x, 0)
    button:SetText(text)
    button.row = row
    button:SetScript("OnClick", callback)
    return button
end

local function Row(index)
    local row = View.rows[index]
    if row then return row end
    row = S.CreateFrame("Frame", nil, View.frame)
    row:SetSize(352, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", View.frame, "TOPLEFT", 8, -34 - (index - 1) * ROW_HEIGHT)
    local name = S.CreateFontString(row, nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", row, "LEFT", 0, 0)
    name:SetWidth(130)
    name:SetJustifyH("LEFT")
    local score = S.CreateFontString(row, nil, "OVERLAY", "GameFontHighlightSmall")
    score:SetPoint("LEFT", name, "RIGHT", 4, 0)
    score:SetWidth(44)
    row.name, row.score = name, score
    row.invite = Button(row, INVITE, 76, -54, Invite)
    row.decline = Button(row, DECLINE, 52, 0, Decline)
    View.rows[index] = row
    return row
end

local function Paint()
    local entries = View.entries
    local count = #entries
    View.offset = math.min(math.max(View.offset, 0), math.max(0, count - PAGE_SIZE))
    local shown = math.min(PAGE_SIZE, count)
    local capacity = InviteCapacity()
    View.frame:SetHeight(42 + shown * ROW_HEIGHT)
    for index = 1, PAGE_SIZE do
        local entry = entries[View.offset + index]
        local row = entry and Row(index) or View.rows[index]
        if row then
            row.applicantID = entry and entry.id or nil
            row:SetShown(entry ~= nil)
            if entry then
                row.name:SetText(entry.name)
                row.score:SetText(math.floor(entry.score + .5))
                local members = ActionInfo(entry.id)
                row.invite:SetEnabled(members ~= nil and capacity ~= nil and members <= capacity)
                row.decline:SetEnabled(members ~= nil)
            end
        end
    end
end

local function Scroll(_, delta)
    View.offset = View.offset - delta
    Paint()
end

local function Ensure()
    if View.frame then return end
    local frame = S.CreateFrame("Frame", nil, UIParent)
    View.frame = frame
    frame:SetSize(368, 42)
    frame:SetPoint("TOPLEFT", LFGListFrame, "TOPRIGHT", 8, 0)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", Scroll)
    local background = S.CreateTexture(frame, nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(.04, .04, .04, .96)
    local title = S.CreateFontString(frame, nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -10)
    title:SetWidth(352)
    title:SetJustifyH("LEFT")
    title:SetText(S.Text("Mythic+ applicant score sorting"))
end

function View.Hide()
    if View.frame then View.frame:Hide() end
    View.entries, View.offset = nil, 0
end

function View.Show(owner, entries)
    View.owner, View.entries = owner, entries
    Ensure()
    View.frame:Show()
    Paint()
end
