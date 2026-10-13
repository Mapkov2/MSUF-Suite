return function(root, scenario, mutant)
local combat,empowered,mythic=false,true,true
local invited,declined,confirmations={}, {},{}
local groupCount,invitedCount,raid=1,0,false
local maximum, assistant = 5, false
local scores={[101]=2100,[102]=1900}
local info={
    [101]={numMembers=1,applicationStatus="applied",applicantInfo=false},
    [102]={numMembers=1,applicationStatus="applied",applicantInfo=false},
}
local Object={}
Object.__index=Object
function Object:SetSize(w,h) self.width,self.height=w,h end
function Object:SetHeight(h) self.height=h end
function Object:SetWidth(w) self.width=w end
function Object:SetPoint(...) self.point={...} end
function Object:SetText(text) self.text=text end
function Object:SetJustifyH() end
function Object:SetAllPoints() end
function Object:SetColorTexture() end
function Object:SetClampedToScreen() end
function Object:SetFrameStrata() end
function Object:EnableMouseWheel() end
function Object:SetScript(script,callback) self.scripts[script]=callback end
function Object:HookScript(script,callback) self.hooks[script]=callback end
function Object:IsShown() return self.shown end
function Object:IsForbidden() return false end
function Object:SetShown(shown) self.shown=shown end
function Object:SetEnabled(enabled) self.enabled=enabled end
function Object:Show()
    local changed=not self.shown
    self.shown=true
    if changed and self.hooks.OnShow then self.hooks.OnShow(self) end
end
function Object:Hide() self.shown=false;if self.hooks.OnHide then self.hooks.OnHide(self) end end
local function New() return setmetatable({shown=true,scripts={},hooks={}},Object) end
UIParent=New()
LFGListFrame=New()
LFGListFrame.ApplicationViewer=New()
LFGListFrame.ApplicationViewer.applicants={101,102}
LE_PARTY_CATEGORY_HOME,MAX_PARTY_MEMBERS,MAX_RAID_MEMBERS=1,4,40
UNKNOWN,INVITE,DECLINE,LFG_LIST_CONVERT_TO_RAID_WARNING="Unknown","Invite","Decline","Convert?"
UnitIsGroupLeader=function() return empowered end
UnitIsGroupAssistant=function() return assistant end
LFGListUtil_IsEntryEmpowered=function() return empowered or assistant end
IsInRaid=function() return raid end
GetNumGroupMembers=function() return groupCount end
C_PartyInfo={ConfirmConvertToRaid=function() raid=true end}
C_LFGList={
    GetActiveEntryInfo=function() return {activityIDs={10}} end,
    GetActivityInfoTable=function() return {isMythicPlusActivity=mythic,maxNumPlayers=maximum} end,
    GetApplicantInfo=function(id) return info[id] end,
    GetApplicantMemberInfo=function(id) return "Player"..id,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,scores[id] end,
    GetNumInvitedApplicantMembers=function() return invitedCount end,
    RefreshApplicants=function() end,
    InviteApplicant=function(id) invited[#invited+1]=id end,
    DeclineApplicant=function(id) declined[#declined+1]=id end,
}
local hooks={}
hooksecurefunc=function(name,callback) hooks[name]=callback end
local P={NS={InCombat=function() return combat end},Suite={}}
local S=P.Suite
S.Public=function(v) return v~="secret" end
S.Finite=function(v) return type(v)=="number" and v==v and v<math.huge and v>-math.huge end
S.PublicText=function(v) return S.Public(v) and type(v)=="string" and v or nil end
S.Text=function(v) return v end
S.CreateFrame=New;S.CreateFontString=New;S.CreateTexture=New
S.Confirm=function(key,data) confirmations[#confirmations+1]=data end
S.Install=function(_,module) P.module=module end
assert(loadfile(root.."/MSUF_Suite_QualityOfLife/GroupFinderApplicantView.lua"))("MSUF_Suite_QualityOfLife",P)
local sorter=assert(io.open(root.."/MSUF_Suite_QualityOfLife/GroupFinderApplicantSort.lua","rb"))
local sorterText=sorter:read("*a");sorter:close()
if mutant=="without_view_events" then
    for _,event in ipairs({"LFG_LIST_APPLICANT_UPDATED","LFG_LIST_ACTIVE_ENTRY_UPDATE","GROUP_ROSTER_UPDATE"}) do
        sorterText=sorterText:gsub('self.context:Event%("'..event..'", update%)','')
    end
end
assert(loadstring(sorterText,"@GroupFinderApplicantSort.lua"))("MSUF_Suite_QualityOfLife",P)
local M,View=P.module,P.ApplicantView
M.active=true;M.context={events={}}
function M.context:Event(event,callback) self.events[event]=callback end
function M.context:Coalesce(_,callback)
    local pending=false
    local function Request()
        if pending then return end
        pending=true;P.queued=P.queued or {}
        P.queued[#P.queued+1]=function() pending=false;callback() end
    end
    return setmetatable({Request=Request},{__call=Request})
end
if scenario=="paging" then
    for id=103,114 do
        LFGListFrame.ApplicationViewer.applicants[#LFGListFrame.ApplicationViewer.applicants+1]=id
        info[id]={numMembers=1,applicationStatus="applied",applicantInfo=false}
        scores[id]=1000+id
    end
end
M:Enable()
local function Event(event,...)
    local callback=M.context.events[event]
    if callback then callback(M.context,event,...) end
    -- Drain an event-coalesced owned refresh if the candidate queues one.
    for _,callback in ipairs(P.queued or {}) do callback() end
    P.queued={}
end
local function Click(button) button.scripts.OnClick(button) end
local function NativeRefresh() hooks.LFGListApplicationViewer_UpdateResultList(LFGListFrame.ApplicationViewer) end
local original=LFGListFrame.ApplicationViewer.applicants
assert(View.frame:IsShown() and View.rows[1].applicantID==101,"owned sorted view failed initial display")
if scenario=="individual_status" then
    info[101].applicationStatus="invited"
    Event("LFG_LIST_APPLICANT_UPDATED",101)
    assert(View.rows[1].invite.enabled==false,"individual native update left owned Invite enabled")
elseif scenario=="individual_score" then
    scores[102]=2500
    Event("LFG_LIST_APPLICANT_UPDATED",102)
    assert(View.rows[1].applicantID==102,"individual score update did not resort owned view")
elseif scenario=="listing_change" then
    mythic=false
    Event("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    assert(not View.frame:IsShown(),"non-Mythic listing retained previous Mythic view")
elseif scenario=="group_authority" then
    empowered=false
    Event("GROUP_ROSTER_UPDATE")
    assert(not View.rows[1].invite.enabled,"roster authority change left own Invite enabled")
elseif scenario=="fresh_click_guard" then
    info[101].pendingApplicationStatus="invited"
    Click(View.rows[1].invite)
    assert(#invited==0 and #confirmations==0,"stale pending applicant still invited")
elseif scenario=="full_group" or scenario=="pending_fills_group" then
    groupCount=4
    if scenario=="full_group" then info[101].numMembers=2 else invitedCount=1 end
    Event("GROUP_ROSTER_UPDATE")
    assert(not View.rows[1].invite.enabled,"full Mythic+ group left Invite enabled")
    Click(View.rows[1].invite)
    assert(#invited==0 and #confirmations==0 and not raid,"full Mythic+ group invited or converted to raid")
elseif scenario=="secret_leader" or scenario=="secret_assistant" then
    empowered=scenario=="secret_leader" and "secret" or false
    assistant=scenario=="secret_assistant" and "secret" or false
    Event("GROUP_ROSTER_UPDATE")
    Click(View.rows[1].invite)
    assert(not View.rows[1].invite.enabled and #invited==0,"secret authority permitted invitation")
elseif scenario=="secret_capacity" then
    groupCount="secret"
    Event("GROUP_ROSTER_UPDATE")
    Click(View.rows[1].invite)
    assert(not View.rows[1].invite.enabled and #invited==0,"secret group size permitted invitation")
elseif scenario=="zero_limit" then
    maximum=0;groupCount=5
    Event("GROUP_ROSTER_UPDATE")
    Click(View.rows[1].invite)
    assert(not View.rows[1].invite.enabled and #invited==0,"unspecified Mythic+ limit bypassed party capacity")
elseif scenario=="missing_limit" then
    maximum=nil
    Event("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    Click(View.rows[1].invite)
    assert(not View.rows[1].invite.enabled and #invited==0,"unknown activity limit permitted invitation")
elseif scenario=="fresh_listing_guard" then
    mythic=false
    Click(View.rows[1].invite)
    assert(#invited==0,"stale panel invited into a different listing")
elseif scenario=="combat_return" then
    combat=true
    Event("PLAYER_REGEN_DISABLED")
    Click(View.rows[1].invite)
    assert(not View.frame:IsShown() and #invited==0,"combat edge retained active applicant actions")
    combat=false
    Event("PLAYER_REGEN_ENABLED")
    assert(View.frame:IsShown(),"combat end required an unproven native refresh event")
elseif scenario=="reopen" or scenario=="reenable_reopen" then
    local viewer=LFGListFrame.ApplicationViewer
    if scenario=="reenable_reopen" then
        M.active=false;M:Disable()
        M.context=setmetatable({events={}},{__index=M.context})
        M.active=true;M:Enable()
    end
    viewer:Hide()
    assert(not View.frame:IsShown(),"closed native viewer retained own panel")
    viewer:Show()
    Event("drain_only")
    assert(View.frame:IsShown(),"reopened viewer depended on a native data-change event")
elseif scenario=="paging" then
    local first=View.rows[1]
    View.frame.scripts.OnMouseWheel(View.frame,-3)
    assert(View.rows[1]==first and first.applicantID==M.entries[4].id and #View.rows==10,"paging did not reuse ten owned rows")
    View.frame.scripts.OnMouseWheel(View.frame,-100)
    assert(View.offset==4 and first.applicantID==M.entries[5].id,"paging overshot the last page")
    View.frame.scripts.OnMouseWheel(View.frame,100)
    assert(View.offset==0 and first.applicantID==M.entries[1].id,"paging overshot the first page")
elseif scenario=="invite_decline" then
    Click(View.rows[1].invite)
    Click(View.rows[2].decline)
    assert(#invited==1 and invited[1]==101 and #declined==1 and declined[1]==102,"valid native actions lost applicant IDs")
else error("unknown scenario "..scenario) end
assert(LFGListFrame.ApplicationViewer.applicants==original and original[1]==101 and original[2]==102,
    "owned view mutated native applicant array")
print("independent applicant "..scenario.." passed")

end
