local root=assert(arg[1],"repository root required")
local checks=0
local function Check(value,message) assert(value,message);checks=checks+1 end
local created={}
local function Widget(name,parent)
    local w={name=name,parent=parent,shown=true,alpha=1,width=320,height=72,points={{"CENTER",nil,"CENTER",0,0}},font={"native",12,""},coords={0,1,0,1},scripts={}}
    created[#created+1]=w
    function w:SetScript(key,callback) self.scripts[key]=callback end
    function w:HookScript(key,callback)
        local old=self.scripts[key];self.scripts[key]=function(...) if old then old(...) end;callback(...) end
    end
    function w:Show() local old=self.shown;self.shown=true;if not old and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function w:Hide() local old=self.shown;self.shown=false;if old and self.scripts.OnHide then self.scripts.OnHide(self) end end
    function w:SetShown(on) if on then self:Show() else self:Hide() end end
    function w:IsShown() return self.shown end
    function w:IsProtected() return false end
    function w:GetName() return self.name end
    function w:GetAlpha() return self.alpha end
    function w:SetAlpha(value) self.alpha=value end
    function w:SetSize(x,y) self.width,self.height=x,y end
    function w:SetHeight(v) self.height=v end
    function w:GetHeight() return self.height end
    function w:SetWidth(v) self.width=v end
    function w:SetPoint(...) self.points[#self.points+1]={...} end
    function w:ClearAllPoints() self.points={} end
    function w:GetNumPoints() return #self.points end
    function w:GetPoint(i) return unpack(self.points[i]) end
    function w:SetText(value) self.text=value end
    function w:SetFont(...) self.font={...} end
    function w:GetFont() return unpack(self.font) end
    function w:SetTexCoord(...) self.coords={...} end
    function w:GetTexCoord() return unpack(self.coords) end
    function w:SetColorTexture(...) self.color={...} end
    function w:SetID(v) self.id=v end
    function w:GetItemLocation() return self.locationObject end
    function w:SetOwner(owner,anchor,x,y) self.owner,self.anchor,self.anchorX,self.anchorY=owner,anchor,x,y end
    function w:GetUnit() return "unit",self.unit end
    function w:AddDoubleLine(a,b,...) self.lines[#self.lines+1]={a,b,...} end
    function w:SetScrollChild(child) self.child=child end
    function w:GetVerticalScroll() return self.offset or 0 end
    function w:GetFrameLevel() return 5 end
    function w:CreateAnimationGroup()
        local group={}
        function group:Play() self.playing=true end
        function group:Stop() self.playing=false end
        function group:SetLooping(v) self.looping=v end
        function group:CreateAnimation() return setmetatable({}, {__index=function() return function() end end}) end
        return group
    end
    for _,key in ipairs({"SetAllPoints","EnableMouse","SetScale","SetJustifyH","SetInventoryItem","SetFrameLevel","SetFrameStrata","SetBackdrop","SetBackdropColor","SetBackdropBorderColor"}) do w[key]=function() end end
    return w
end
local combat=false
local hooks,post,pre={}, {}, {}
hooksecurefunc=function(target,method,callback) hooks[type(target)=="table" and method or target]=callback or method end
TooltipDataProcessor={AddTooltipPostCall=function(kind,callback) post[kind]=callback end,AddLinePreCall=function(kind,callback) pre[kind]=callback end}
Enum={TooltipDataType={Unit=1,Item=2,Spell=4},TooltipDataLineType={UnitName=1}}
UIParent=Widget("UIParent")
GameTooltip=Widget("tooltip");GameTooltip.lines={};GameTooltipStatusBar=Widget("health")
CharacterFrame=Widget("character")
InspectFrame=Widget("inspect");InspectFrame.unit="party1"
CharacterHeadSlot=Widget("head");CharacterHeadSlot.popoutButton=Widget("arrow");CharacterHeadSlot.icon=Widget("icon")
InspectHeadSlot=Widget("inspecthead");InspectHeadSlot.icon=Widget("inspecticon")
local vault,folio,socket=0,0,nil
WeeklyRewards_ShowUI=function() vault=vault+1 end
ToggleExpansionLandingPage=function() folio=folio+1 end
ExpansionLandingPage={IsOverlayApplied=function() return true end}
C_PlayerInfo={IsExpansionLandingPageUnlockedForPlayer=function() return true end};LE_EXPANSION_MIDNIGHT=12
SocketInventoryItem=function(slot) socket=slot end
GetAverageItemLevel=function() return 100,110,120 end
GetInventoryItemDurability=function(slot) if slot==1 then return 25,50 elseif slot==2 then return 100,100 end end
GetInventoryItemLink=function(_,slot) if slot==1 then return "gear1" end end
C_Item={GetItemStats=function() return {EMPTY_SOCKET_PRISMATIC=2} end,
    GetItemGem=function(_,index) if index==1 then return "Gem","gem" end end,
    GetItemInfo=function(link) if link=="gear1" then return "Helmet" end;return "item",link,4,100,nil,nil,nil,200,nil,1234 end,
    GetDetailedItemLevelInfo=function() return 155 end,GetCurrentItemLevel=function() return 144 end}
C_Container={GetContainerItemLink=function() return "gear1" end}
EquipmentManager_GetLocationData=function() return {isBags=true,bag=0,slot=1} end
EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION=999
EquipmentFlyoutFrame={buttons={Widget("flyout")}};EquipmentFlyoutFrame.buttons[1].locationObject={}
EquipmentFlyout_UpdateItems=function() end;EquipmentFlyoutPopoutButton_ShowAll=function() end
C_PaperDollInfo={GetInspectItemLevel=function() return 180 end}
local inspectTime, inspectRequests = 0, 0
UnitIsDeadOrGhost=function() return false end
GetTime=function() return inspectTime end
local inspectTimers={}
C_Timer={NewTimer=function(delay,callback)
    local timer={delay=delay,callback=callback};function timer:Cancel() self.cancelled=true end
    inspectTimers[#inspectTimers+1]=timer;return timer
end}
CanInspect=function() return true end
CheckInteractDistance=function() return true end
NotifyInspect=function(unit) inspectRequests=inspectRequests+1;hooks.NotifyInspect(unit) end
UnitGUID=function(unit) return "GUID-"..unit end
C_Secrets={ShouldUnitIdentityBeSecret=function() return false end}
C_MountJournal={GetMountFromSpell=function(spell) Check(spell==99,"mount marker used a guessed tooltip-data id");return 1 end,GetMountInfoByID=function() return "mount",1,1,false,true,1,false,false,nil,false,true end}
C_Spell={GetSpellTexture=function() return 4321 end}
GetGuildInfo=function() return "guild","Officer" end
UnitIsUnit=function(a,b) return a==b or a=="party1target" and b=="player" end
UnitName=function(unit) return unit=="party1target" and "My player" or "Plain name" end
UnitExists=function() return true end
local S={}
local movers={}
S.RegisterOwnedMover=function(id,element,spec) movers[id]={element=element,spec=spec};return true end
local NS={Client={isForever=arg[2]=="Forever"},Safety={IsForbidden=function(frame) return frame.forbidden == true end},IsCombatLocked=function() return combat end}
NS.Dispatch=function(callback,...) return callback(...) end
local Support=dofile(root.."/tools/tests/suite_test_support.lua")
local TimerContext=Support.ModuleTimers(root,S,NS)
S.Public=function(value) return value~="secret" end
S.PublicText=function(value) return S.Public(value) and type(value)=="string" and value or nil end
S.Finite=function(value) return S.Public(value) and type(value)=="number" and value==value end
S.Text=function(value) return value end
S.SetFont=function(w,...) w:SetFont(...) end
S.GlobalFontPath=function() return "global" end
S.Queue=function(id) S.queued=id end
S.CreateFrame=function(_,name,parent,template)
    local frame=Widget(name,parent)
    if template=="MerchantItemTemplate" then
        frame.Name=Widget(name.."Name",frame);frame.ItemButton=Widget(name.."ItemButton",frame)
        _G[name.."MoneyFrame"]=Widget();_G[name.."AltCurrencyFrame"]=Widget()
    end
    return frame
end
S.CreateFontString=function(parent) return Widget(nil,parent) end;S.CreateTexture=S.CreateFontString
local modules={};S.Install=function(id,m) modules[id]=m end
local function Load(name,id,config)
    assert(loadfile(root.."/MSUF_Suite_QualityOfLife/"..name..".lua"))("test",{NS=NS,Suite=S})
    local m=modules[id];m.active=true;m.config=config;m.events={}
    m.eventUnits={}
    m.context=TimerContext(id,m,{Event=function(_,event,callback,_,unit) m.events[event]=callback;m.eventUnits[event]=unit end,
        RemoveEvent=function(_,event) m.events[event]=nil;m.eventUnits[event]=nil end})
    m:Enable();return m
end
-- The merchant list has its own contract: suite_merchant_list_contract.lua.
local clock=Support.Clock()
local party=Load("PartyEffects","partyEffects",{onLevelUp=true,onAchievement=false,onLust=true,duration=6,fontSize=24,scale=100,x=0,y=0})
local castUnits=party.eventUnits.UNIT_SPELLCAST_SUCCEEDED
Check(castUnits and castUnits[1]=="player" and castUnits[2]=="pet" and #castUnits==2,"Bloodlust trigger listened beyond the player and pet")
party.events.PLAYER_LEVEL_UP(party,"PLAYER_LEVEL_UP",70);Check(party.host.shown and party.animations[1].playing,"level-up did not start native animations")
clock.Advance(6.1)
Check(not party.host.shown,"effect duration did not end native animations")
party.events.PLAYER_LEVEL_UP(party,"PLAYER_LEVEL_UP",71)
party.active=false
party:Disable()
Check(not party.host.shown,"disable left the effect shown")
party.host.shown=true
clock.Advance(7)
Check(party.host.shown,"disable left an effect timer active")
print("Party effects: "..checks.." checks passed")
