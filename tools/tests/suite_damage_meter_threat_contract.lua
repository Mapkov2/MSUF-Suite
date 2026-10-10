local root=assert(arg[1],"repository root required")
-- Threat mode of the damage meter (MSUF_Suite_DamageMeter/Threat.lua) on WoW
-- Forever: the type picker's sixth damage tile, Omen-style rows from the
-- client's own threat data (sorted, share of the tank, the pull row), a
-- restricted (secret) enemy painted through sinks only, the C-side event
-- filter, coalesced repaints and dormancy without a threat window.
-- Retail has no threat type: suite_damage_meter_contract.lua pins eleven tiles.
securecallfunction=function(callback,...) return callback(...) end

------------------------------------------------------------------ secrets
local SecretMT={}
local function Raise(what) return function() error("secret value used: "..what,2) end end
for _,key in ipairs({"__add","__sub","__mul","__div","__mod","__pow","__unm","__concat","__lt","__le","__eq","__call"}) do
    SecretMT[key]=Raise(key)
end
SecretMT.__index=Raise("index");SecretMT.__newindex=Raise("assignment");SecretMT.__tostring=Raise("tostring")
local function Secret() return setmetatable({},SecretMT) end
local function IsSecret(value) return getmetatable(value)==SecretMT end
issecretvalue=IsSecret

------------------------------------------------------------------ frames
local Region={}
Region.__index=Region
local function NewRegion(kind,parent)
    return setmetatable({kind=kind,parent=parent,shown=true,points={},scripts={},events={},unitEvents={},alpha=1,level=1,
        width=0,height=0},Region)
end
for _,name in ipairs({"SetClampedToScreen","SetMovable","SetResizable","SetDontSavePosition","SetResizeBounds","EnableMouse",
    "EnableMouseWheel","RegisterForClicks","RegisterForDrag","SetFrameStrata","SetScale","SetNormalTexture","SetHighlightTexture",
    "SetPushedTexture","SetTexCoord","SetVertexColor","SetJustifyH","SetWordWrap","SetShadowColor","SetShadowOffset",
    "SetBlendMode","SetGradient","SetDrawLayer","SetAtlas","SetTexture","StartMoving","StopMovingOrSizing"}) do
    Region[name]=function() end
end
function Region:Show() self.shown=true end
function Region:Hide() self.shown=false end
function Region:IsShown() return self.shown end
function Region:SetShown(shown) self.shown=shown and true or false end
function Region:SetScript(key,value) self.scripts[key]=value end
function Region:GetScript(key) return self.scripts[key] end
function Region:SetPoint(...) self.points[#self.points+1]={...} end
function Region:ClearAllPoints() self.points={} end
function Region:SetAllPoints(target) self.allPoints=target end
function Region:SetSize(width,height) self.width,self.height=width,height end
function Region:SetWidth(width) self.width=width end
function Region:SetHeight(height) self.height=height end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end
function Region:GetParent() return self.parent end
function Region:GetEffectiveScale() return 1 end
function Region:SetAlpha(alpha) self.alpha=alpha end
function Region:GetAlpha() return self.alpha end
function Region:SetFrameLevel(level) self.level=level end
function Region:GetFrameLevel() return self.level end
function Region:IsMouseOver() return false end
function Region:CreateTexture() return NewRegion("Texture",self) end
function Region:CreateFontString() return NewRegion("FontString",self) end
function Region:RegisterEvent(event) self.events[event]=true end
function Region:RegisterUnitEvent(event,...) self.events[event]=true;self.unitEvents[event]={...} end
function Region:UnregisterEvent(event) self.events[event]=nil;self.unitEvents[event]=nil end
function Region:UnregisterAllEvents() self.events={} end
function Region:SetStatusBarColor(r,g,b,a) self.color={r,g,b,a} end
function Region:SetStatusBarTexture() self.statusTexture=NewRegion("Texture",self) end
function Region:GetStatusBarTexture() return self.statusTexture end
function Region:SetMinMaxValues(low,high) self.min,self.max=low,high end
function Region:SetValue(value) self.value=value end
function Region:SetColorTexture(r,g,b,a) self.color={r,g,b,a} end
function Region:SetFont(path,size,flags) self.font={path,size,flags};return true end
function Region:SetTextColor(r,g,b) self.textColor={r,g,b} end
function Region:SetText(text) self.text=text end
function Region:SetFormattedText(format,...)
    local args,secret={...},false
    for i=1,select("#",...) do if IsSecret(args[i]) then secret=true end end
    if secret then self.text={format=format,args=args} else self.text=string.format(format,...) end
end
CreateFrame=function(kind,_,parent) return NewRegion(kind,parent) end
CreateColor=function(r,g,b,a) return {r,g,b,a} end
MSUF_ApplyFontScaleAnimationMode=function() end

------------------------------------------------------------------ client
local combat,now=false,100
InCombatLockdown=function() return combat end
GetTime=function() return now end
SlashCmdList={}
MSUFSuite={}
-- The host's client model: WoW Forever.
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",IsForever=true,SupportsEvent=function() return true end}}
IsInInstance=function() return false,"none" end
IsInGroup=function() return true end
UnitGUID=function(unit) return unit=="player" and "Player-1" or nil end
GetRealmName=function() return "Realm" end
C_AddOns={IsAddOnLoaded=function() return false end}
Ambiguate=function(name) if IsSecret(name) then return Secret() end;return (name:gsub("%-.*$","")) end
AbbreviateNumbers=function(value)
    if IsSecret(value) then return Secret() end
    if value>=1e4 then return tostring(math.floor(value/1e3)).."K" end
    if value>=1e3 then return tostring(math.floor(value/1e2)/10).."K" end
    return tostring(value)
end
RAID_CLASS_COLORS={WARRIOR={r=.78,g=.61,b=.43},MAGE={r=.25,g=.78,b=.92},PRIEST={r=1,g=1,b=1}}
CLASS_ICON_TCOORDS={WARRIOR={0,.25,0,.25},MAGE={.25,.5,0,.25},PRIEST={.5,.75,.25,.5}}
LOCALIZED_CLASS_NAMES_MALE={}
Enum={DamageMeterType={DamageDone=0,Dps=1,HealingDone=2,Hps=3,Absorbs=4,Interrupts=5,Dispels=6,DamageTaken=7,
    AvoidableDamageTaken=8,Deaths=9,EnemyDamageTaken=10},DamageMeterSessionType={Overall=0,Current=1,Expired=2},
    AddOnRestrictionState={Inactive=0,Activating=1,Active=2}}
YES,NO="Yes","No"
local cvars={damageMeterEnabled="1"}
C_CVar={GetCVar=function(key) return cvars[key] end,SetCVar=function(key,value) cvars[key]=tostring(value) end}
C_Texture={GetAtlasInfo=function() return {} end}
C_Spell={GetSpellName=function() return "Spell" end,GetSpellTexture=function() return 1 end}
local afters={}
C_Timer={NewTimer=function() return {Cancel=function() end} end,After=function(delay,callback) afters[#afters+1]={delay=delay,callback=callback} end}
UIParent=NewRegion("Frame");UIParent:SetSize(1920,1080)
GetCursorPosition=function() return 700,500 end
GameTooltip=NewRegion("Frame")
function GameTooltip:SetOwner(owner) self.owner=owner end
function GameTooltip:GetOwner() return self.owner end
dofile(root.."/tools/tests/suite_test_support.lua").StaticPopups()
MenuUtil={CreateContextMenu=function() end}
MSUF_EditModeAPI={RegisterElement=function() return true end,RefreshOwner=function() end,UnregisterOwner=function() end}
MSUF_EM2={ExternalElements={GetRecord=function() return {isEnabled=function() return true end} end}}
local meterFetches=0
C_DamageMeter={
    GetCombatSessionFromType=function() meterFetches=meterFetches+1;return {combatSources={},maxAmount=0,totalAmount=0} end,
    GetCombatSessionFromID=function() meterFetches=meterFetches+1;return {combatSources={},maxAmount=0,totalAmount=0} end,
    GetSessionDurationSeconds=function() return 42 end,
    GetAvailableCombatSessions=function() return {} end,
    IsDamageMeterAvailable=function() return true,"" end,
    ResetAllCombatSessions=function() end,
}

------------------------------------------------------------------ group and threat
-- A party: the player (mage), the tank (party1) and a healer (party2), and a
-- hostile target. Each unit's threat: { isTanking, status, scaled, raw, threat }.
local units={player=true,party1=true,party2=true,target=true}
local names={player="Me",party1="Tank-Realm",party2="Healer"}
local classes={player="MAGE",party1="WARRIOR",party2="PRIEST"}
local hostile,friendlyTarget,targetName={target=true},false,"Hogger"
local threats={player={false,1,80,96,48000},party1={true,3,100,100,50000},party2={false,0,30,40,20000}}
local reads=0
UnitExists=function(unit) return units[unit]==true end
UnitCanAttack=function(_,unit) return hostile[unit]==true end
UnitCanAssist=function(_,unit) return unit=="target" and friendlyTarget end
UnitIsUnit=function(a,b) return a==b or (a=="nameplate3" and b=="targettarget") end
UnitName=function(unit) return unit=="target" and targetName or names[unit] end
GetUnitName=function(unit) return names[unit] end
UnitClass=function(unit) return classes[unit],classes[unit] end
IsInRaid=function() return false end
GetNumGroupMembers=function() return 3 end
UnitDetailedThreatSituation=function(unit,enemy)
    assert(enemy=="target" or enemy=="targettarget","threat read for an unexpected enemy: "..tostring(enemy))
    reads=reads+1
    local entry=threats[unit]
    if not entry then return end
    return entry[1],entry[2],entry[3],entry[4],entry[5]
end
local formatted=0
C_StringUtil={
    TruncateWhenZero=function(value) formatted=formatted+1;return IsSecret(value) and Secret() or tostring(math.floor(value)) end,
    WrapString=function(infix) return infix end,
}

------------------------------------------------------------------ load
local Suite=MSUFSuite
local Support=dofile(root.."/tools/tests/suite_test_support.lua")
Support.Load(root,"MSUF_Suite",Suite,"Core/Suite.lua")
assert(loadfile(root.."/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite",Suite)
assert(loadfile(root.."/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite",Suite)
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
GameFontHighlightSmall={GetFont=function() return "Fonts\\FRIZQT__.TTF",12,"" end}
local private={}
for _,file in ipairs({"Surfaces","Runtime","Timers","EditMode","Dialogs","MicroMenu"}) do
    assert(loadfile(root.."/MSUF_Suite_Modules/"..file..".lua"))("MSUF_Suite_Modules",private)
end
for _,file in ipairs(Support.TocFiles(root,"MSUF_Suite_DamageMeter")) do
    if file~="Bootstrap.lua" then assert(loadfile(root.."/MSUF_Suite_DamageMeter/"..file))("MSUF_Suite_DamageMeter",private) end
end
local S,D=Suite.Suite,private.DamageMeter
local M=S.instances.damageMeter
Suite.Client.AddOnEnabled=function() return true end
assert(Suite.Client.isForever,"the test client is not WoW Forever")
local labels=Suite.DamageMeterTypeLabels
assert(#labels==12 and labels[12]=="Threat" and D.THREAT==11,"WoW Forever lacks the threat meter type after Blizzard's")

local function Frame() return M.context.frame end
local function Registered(name) return Frame() and Frame().events[name]==true end
local function Event(name,...)
    assert(Registered(name),"event not registered: "..name)
    Frame().scripts.OnEvent(Frame(),name,...)
end
local function RunThreatPaint()
    local job,list,ran=D.threatJob,afters,0
    afters={}
    for _,entry in ipairs(list) do
        if entry.callback==job.tick then entry.callback();ran=ran+1 else afters[#afters+1]=entry end
    end
    return ran
end
local function Text(row) return row.valueText.text end

------------------------------------------------------------------ enable: no threat work without a threat window
S.started=true
local c=S.Config("damageMeter")
c.windowCount=1
c.enabled=false
S.Apply("damageMeter")
assert(S.Set("damageMeter","enabled",true))
local win=assert(D.windows[1])
assert(win.shown and win.meterType==0,"the first window does not show damage")
assert(not Registered("UNIT_THREAT_LIST_UPDATE") and not Registered("PLAYER_TARGET_CHANGED") and not Registered("UNIT_PET")
    and reads==0,"threat listens or reads without a threat window")

------------------------------------------------------------------ the picker's sixth damage tile
D.OpenTypeMenu(win,win.header)
local panel=assert(D.typePanel)
local tile=assert(panel.buttons[D.THREAT],"the type picker has no threat tile")
local damageTile=assert(panel.buttons[Enum.DamageMeterType.EnemyDamageTaken])
assert(tile.label.text=="Threat" and tile.points[1][5]==damageTile.points[1][5]
    and tile.points[1][4]~=damageTile.points[1][4],"threat is not the sixth tile beside Enemy damage taken")
local fetches=meterFetches
tile.scripts.OnClick(tile)
assert(win.meterType==D.THREAT and not panel.shown,"picking threat did not switch the window")
assert(c.w1Type==12,"the threat pick was not saved")
assert(meterFetches==fetches,"a threat window fetched a damage meter session")
assert(Registered("UNIT_THREAT_LIST_UPDATE") and Frame().unitEvents.UNIT_THREAT_LIST_UPDATE[1]=="target",
    "the threat list is not filtered to the target in C")
assert(Registered("PLAYER_TARGET_CHANGED") and Frame().unitEvents.UNIT_TARGET[1]=="target" and Registered("UNIT_PET")
    and Registered("GROUP_ROSTER_UPDATE"),"threat window lacks its target, pet or roster events")

------------------------------------------------------------------ Omen rows from plain values
assert(win.title.text=="Threat - Hogger","the title does not name the watched enemy: "..tostring(win.title.text))
local rows={}
for slot=1,4 do rows[slot]=assert(win.rows[slot],"threat row "..slot.." missing") end
-- Pull threshold: the player's 48000 threat is 80% of it, 60000; 120% of the tank's 50000.
assert(rows[1].nameText.text=="Pull aggro" and rows[1].bar.value==60000 and rows[1].bar.color[1]>.8 and rows[1].bar.color[2]<.3,
    "the red pull row is not on top at the player's pull threshold")
assert(rows[2].nameText.text=="Tank" and rows[3].nameText.text=="Me" and rows[4].nameText.text=="Healer",
    "threat rows are not sorted highest first")
assert(rows[2].bar.max==60000 and rows[2].bar.value==50000,"bars do not scale to the highest value")
assert(Text(rows[1])=="120% (60K)" and Text(rows[2])=="100% (50K)" and Text(rows[3])=="96% (48K)" and Text(rows[4])=="40% (20K)",
    "values are not the share of the tank with the threat points: "..tostring(Text(rows[3])))
assert(rows[3].bar.color[1]==RAID_CLASS_COLORS.MAGE.r,"class colors are not kept")
assert(rows[1].rankText.text=="" and rows[2].rankText.text=="1." and rows[3].rankText.text=="2." and rows[4].rankText.text=="3.",
    "rank numbers do not count the members only")
-- A threat-only meter has no damage meter data to hear.
assert(not Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED") and not Registered("ENCOUNTER_START"),
    "a threat-only window keeps the damage meter's data events")

-- Threat changes coalesce into one paint per tick; an unrelated unit is
-- filtered out in C and never reaches the handler.
threats.player={false,1,90,104,52000}
reads=0
Event("UNIT_THREAT_LIST_UPDATE","target")
Event("UNIT_THREAT_LIST_UPDATE","target")
assert(reads==0,"threat was read before the coalesced paint")
assert(RunThreatPaint()==1 and reads==3,"two threat events did not coalesce into one paint of the three members")
assert(rows[2].nameText.text=="Me" and Text(rows[2])=="104% (52K)","the repaint did not re-sort")
local clicked=false
D.OpenBreakdown=function() clicked=true end
rows[2].scripts.OnClick(rows[2],"LeftButton")
assert(not clicked and not win.bd.open,"a threat row opened a breakdown")

-- Tanking: no pull row.
threats.player={true,3,100,100,53000}
Event("UNIT_THREAT_LIST_UPDATE","target")
RunThreatPaint()
assert(rows[1].nameText.text=="Me" and Text(rows[1])=="100% (53K)" and rows[4].shown==false,
    "a tanking player still sees a pull row")

-- A tank outside the group: the pull row's share still follows the player's
-- own numbers (96% of the tank at 80% of the pull threshold is 120%).
threats.player,threats.party1={false,1,80,96,48000},nil
Event("UNIT_THREAT_LIST_UPDATE","target")
RunThreatPaint()
assert(rows[1].nameText.text=="Pull aggro" and Text(rows[1])=="120% (60K)",
    "the pull row's share depends on the tank being listed: "..tostring(Text(rows[1])))
threats.party1={true,3,100,100,50000}

-- Roster changes coalesce: the next paint rebuilds the roster once.
local classReads=0
local unitClass=UnitClass
UnitClass=function(unit) classReads=classReads+1;return unitClass(unit) end
Event("GROUP_ROSTER_UPDATE")
Event("UNIT_PET","party1")
Event("GROUP_ROSTER_UPDATE")
assert(classReads==0,"a roster event rebuilt the roster before the paint")
RunThreatPaint()
assert(classReads==3,"a burst of roster events did not coalesce into one rebuild: "..classReads)
UnitClass=unitClass
threats.player={true,3,100,100,53000}
Event("UNIT_THREAT_LIST_UPDATE","target")
RunThreatPaint()

-- A hostile target's own target never matters.
Event("UNIT_TARGET","target")
assert(RunThreatPaint()==0,"the hostile target's target change repainted the threat list")

-- Two threat windows share one read of the threat list per paint.
assert(S.Set("damageMeter","windowCount",2) and S.Set("damageMeter","w2Type",12))
local second=assert(D.windows[2])
assert(second.shown and second.meterType==D.THREAT and second.title.text=="Threat - Hogger",
    "the second threat window lacks its type or the enemy's name")
RunThreatPaint()
reads=0
Event("UNIT_THREAT_LIST_UPDATE","target")
assert(RunThreatPaint()==1 and reads==3 and rawequal(second.session,win.session),
    "two threat windows read the threat list twice")
-- A damage window beside the threat window hears its data again.
assert(S.Set("damageMeter","w2Type",1))
assert(Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED") and Registered("UNIT_THREAT_LIST_UPDATE"),
    "a damage window beside a threat window lost its data or threat events")
assert(S.Set("damageMeter","windowCount",1))

------------------------------------------------------------------ restricted (secret) enemy: sinks only, roster order
threats.player={Secret(),Secret(),Secret(),Secret(),Secret()}
threats.party1={Secret(),Secret(),Secret(),Secret(),Secret()}
threats.party2={Secret(),Secret(),Secret(),Secret(),Secret()}
formatted=0
Event("UNIT_THREAT_LIST_UPDATE","target")
RunThreatPaint()
assert(rows[1].nameText.text=="Me" and rows[2].nameText.text=="Tank" and rows[3].nameText.text=="Healer" and rows[4].shown==false,
    "restricted threat was sorted or got a pull row")
assert(rows[1].bar.max==100 and IsSecret(rows[1].bar.value),"restricted bars do not take the share of the tank as is")
assert(type(Text(rows[1]))=="table" and Text(rows[1]).format=="%s (%s)" and formatted==3,
    "restricted values did not go through the C formatters")
assert(rows[1].rankText.text=="" and rows[2].rankText.text=="","an unsorted restricted list got rank numbers")

------------------------------------------------------------------ a friendly target's enemy
threats={player={false,1,50,50,10000},party1={true,3,100,100,20000}}
units.targettarget,friendlyTarget,hostile=true,true,{targettarget=true}
Event("PLAYER_TARGET_CHANGED")
assert(Registered("UNIT_THREAT_LIST_UPDATE") and Frame().unitEvents.UNIT_THREAT_LIST_UPDATE==nil,
    "the threat list stayed filtered to a friendly target")
assert(win.title.text=="Threat","a friendly target's enemy name was guessed")
RunThreatPaint()
reads=0
Event("UNIT_THREAT_LIST_UPDATE","nameplate7")
assert(RunThreatPaint()==0,"another enemy's threat list repainted")
Event("UNIT_THREAT_LIST_UPDATE","nameplate3")
assert(RunThreatPaint()==1 and reads>0,"the watched enemy's threat list did not repaint")
local originalIsUnit=UnitIsUnit
for _, unreadable in ipairs({false,true}) do
    UnitIsUnit=function() if unreadable then return Secret() end end
    reads=0
    Event("UNIT_THREAT_LIST_UPDATE","nameplate3")
    Event("UNIT_THREAT_LIST_UPDATE","nameplate7")
    assert(RunThreatPaint()==1 and reads>0,"unknown compound identity lost or duplicated a coalesced repaint")
end
UnitIsUnit=originalIsUnit

------------------------------------------------------------------ leaving threat releases everything
D.SetWindowType(win,0)
assert(not Registered("UNIT_THREAT_LIST_UPDATE") and not Registered("PLAYER_TARGET_CHANGED") and not Registered("UNIT_TARGET")
    and not Registered("UNIT_PET"),"threat events stayed registered without a threat window")
print("suite_damage_meter_threat_contract: OK (picker tile, Omen rows, pull row, restricted sinks, C filter, coalesced paints)")
