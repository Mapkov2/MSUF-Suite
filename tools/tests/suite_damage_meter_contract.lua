local root=assert(arg[1],"repository root required")
-- The client's securecallfunction reports an error and returns nothing;
-- this stand-in lets errors raise, so a failing callback fails the test.
securecallfunction = function(callback, ...) return callback(...) end
-- Offline contract for the damage meter runtime (MSUF_Suite_DamageMeter).
-- Secret values are sentinel tables that raise on comparison, arithmetic,
-- concatenation, indexing and tostring; the runtime may only hand them to sinks.

------------------------------------------------------------------ secrets
local SecretMT={}
local function Raise(what) return function() error("secret value used: "..what,2) end end
for _,key in ipairs({"__add","__sub","__mul","__div","__mod","__pow","__unm","__concat","__lt","__le","__eq","__call"}) do
    SecretMT[key]=Raise(key)
end
SecretMT.__index=Raise("index");SecretMT.__newindex=Raise("assignment");SecretMT.__tostring=Raise("tostring")
local secretLabel=setmetatable({},{__mode="k"})
local function Secret(label) local value=setmetatable({},SecretMT);secretLabel[value]=label;return value end
local function IsSecret(value) return getmetatable(value)==SecretMT end
local function Label(value) return IsSecret(value) and secretLabel[value] or nil end
issecretvalue=IsSecret

------------------------------------------------------------------ frames
local created,frames={},{}
local Region={}
Region.__index=Region
local function NewRegion(kind,parent)
    local region=setmetatable({kind=kind,parent=parent,shown=true,points={},scripts={},events={},alpha=1,level=1,width=0,height=0},Region)
    created[kind]=(created[kind] or 0)+1
    if kind~="Texture" and kind~="FontString" then frames[#frames+1]=region end
    return region
end
local function Created(kind) return created[kind] or 0 end
local noop={"SetClampedToScreen","SetMovable","SetResizable","SetDontSavePosition","SetResizeBounds","EnableMouse",
    "EnableMouseWheel","RegisterForClicks","RegisterForDrag","SetFrameStrata","SetScale","SetNormalTexture","SetHighlightTexture",
    "SetPushedTexture","SetTexCoord","SetVertexColor","SetJustifyH","SetWordWrap"}
for _,name in ipairs(noop) do Region[name]=function() end end
function Region:SetShadowColor(r,g,b,a) self.shadowColor={r,g,b,a} end
function Region:SetShadowOffset(x,y) self.shadowOffset={x,y} end
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
function Region:GetRight() return self.right end
function Region:GetBottom() return self.bottom end
function Region:SetAlpha(alpha) self.alpha=alpha end
function Region:GetAlpha() return self.alpha end
function Region:SetFrameLevel(level) self.level=level end
function Region:GetFrameLevel() return self.level end
function Region:IsMouseOver() return self.mouseOver==true end
function Region:IsForbidden() return false end
function Region:StartMoving() self.moving=true end
function Region:StartSizing(point) self.sizing=point end
function Region:StopMovingOrSizing() self.moving,self.sizing=nil,nil end
function Region:CreateTexture() return NewRegion("Texture",self) end
function Region:AttachTexture()
    local texture=NewRegion("Texture",self)
    self.attachments=self.attachments or {}
    self.attachments[#self.attachments+1]=texture
    return texture
end
function Region:CreateFontString() return NewRegion("FontString",self) end
function Region:RegisterEvent(event) self.events[event]=true end
function Region:UnregisterEvent(event) self.events[event]=nil end
function Region:UnregisterAllEvents() self.events={} end
function Region:SetStatusBarColor(r,g,b,a) self.color={r,g,b,a} end
function Region:SetStatusBarTexture(path)
    self.statusTexture=NewRegion("Texture",self)
    self.statusTexture:SetTexture(path)
end
function Region:GetStatusBarTexture() return self.statusTexture end
function Region:SetBlendMode(mode) self.blendMode=mode end
function Region:SetGradient(orientation,first,second) self.gradient={orientation,first,second} end
function Region:SetGradientAlpha(...) self.gradientAlpha={...} end
function Region:SetMinMaxValues(low,high) self.min,self.max=low,high;self.rangeWrites=(self.rangeWrites or 0)+1 end
function Region:SetValue(value) self.value=value;self.valueWrites=(self.valueWrites or 0)+1 end
function Region:SetTexture(texture) self.texture=texture end
function Region:SetColorTexture(r,g,b,a) self.color={r,g,b,a} end
function Region:SetDrawLayer(layer,level) self.drawLayer={layer,level} end
function Region:SetAtlas(atlas) self.atlas=atlas end
function Region:SetFont(path,size,flags) self.font={path,size,flags};return true end
MSUF_ApplyFontScaleAnimationMode=function(region,flags) region.scaleModeFlags=flags end
function Region:SetTextColor(r,g,b) self.textColor={r,g,b} end
local strictFontText=false
function Region:SetText(text)
    if strictFontText and self.kind=="FontString" then assert(self.font,"FontString:SetText before SetFont") end
    self.text=text;self.writes=(self.writes or 0)+1
end
function Region:SetFormattedText(format,...)
    local args,n,secret={...},select("#",...),false
    for i=1,n do if IsSecret(args[i]) then secret=true end end
    self.writes=(self.writes or 0)+1
    if secret then self.text={format=format,args=args} else self.text=string.format(format,...) end
end
CreateFrame=function(kind,_,parent) return NewRegion(kind,parent) end
CreateColor=function(r,g,b,a) return {r,g,b,a} end

------------------------------------------------------------------ client
local combat,now,inside,instanceType,grouped=false,100,false,"none",false
InCombatLockdown=function() return combat end
GetTime=function() return now end
SlashCmdList={}
MSUFSuite={}
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",SupportsEvent=function() return true end}}
IsInInstance=function() return inside,instanceType end
IsInGroup=function() return grouped end
UnitGUID=function(unit) return unit=="player" and "Player-1" or nil end
UnitName=function() return "Tester" end
GetRealmName=function() return "Realm" end
-- No other AddOn is loaded, so no conflict claims the meter.
C_AddOns={IsAddOnLoaded=function() return false end}
Ambiguate=function(name,context)
    assert(context=="short")
    if IsSecret(name) then return Secret("short:"..Label(name)) end
    return (name:gsub("%-.*$",""))
end
AbbreviateNumbers=function(value)
    if IsSecret(value) then return Secret("abbr:"..secretLabel[value]) end
    return "ab"..tostring(value)
end
RAID_CLASS_COLORS={WARRIOR={r=.78,g=.61,b=.43},MAGE={r=.25,g=.78,b=.92},PRIEST={r=1,g=1,b=1}}
CLASS_ICON_TCOORDS={WARRIOR={0,.25,0,.25},MAGE={.25,.5,0,.25},PRIEST={.5,.75,.25,.5}}
-- FrameXML's localized class names exist on both clients; empty here, so
-- sample rows fall back to the class token.
LOCALIZED_CLASS_NAMES_MALE={}
Enum={DamageMeterType={DamageDone=0,Dps=1,HealingDone=2,Hps=3,Absorbs=4,Interrupts=5,Dispels=6,DamageTaken=7,
    AvoidableDamageTaken=8,Deaths=9,EnemyDamageTaken=10},DamageMeterSessionType={Overall=0,Current=1,Expired=2},
    AddOnRestrictionState={Inactive=0,Activating=1,Active=2}}
DAMAGE_METER_TYPE_DAMAGE_DONE="Damage Done"
DAMAGE_METER_OVERALL_SESSION="Overall"
DAMAGE_METER_LABEL="Damage Meter"
YES,NO="Yes","No"
local cvars={damageMeterEnabled="1"}
C_CVar={GetCVar=function(key) return cvars[key] end,SetCVar=function(key,value) cvars[key]=tostring(value) end}
C_Texture={GetAtlasInfo=function() return {} end}
local spellTextureCalls=0
C_Spell={
    GetSpellName=function(id) if IsSecret(id) then return Secret("spellname") end;return "Spell"..id end,
    GetSpellTexture=function(id) assert(not IsSecret(id),"secret spell ID reached a texture lookup");spellTextureCalls=spellTextureCalls+1;return 1000+id end,
}
local timers,afters={},{}
C_Timer={
    NewTimer=function(delay,callback)
        local timer={delay=delay,callback=callback}
        function timer:Cancel() self.cancelled=true end
        timers[#timers+1]=timer
        return timer
    end,
    After=function(delay,callback) afters[#afters+1]={delay=delay,callback=callback} end,
}
-- Runs (and removes) the queued C_Timer.After calls made with callback.
local function RunCalls(callback)
    local list,ran=afters,0
    afters={}
    for _,entry in ipairs(list) do
        if entry.callback==callback then entry.callback();ran=ran+1 else afters[#afters+1]=entry end
    end
    return ran
end
local function RunAfters(delay)
    local list,ran=afters,0
    afters={}
    for _,entry in ipairs(list) do
        if not delay or entry.delay==delay then entry.callback();ran=ran+1 else afters[#afters+1]=entry end
    end
    return ran
end
UIParent=NewRegion("Frame");UIParent.right,UIParent.bottom=1920,0
UIParent:SetSize(1920,1080)
GetCursorPosition=function() return 700,500 end
GameTooltip=NewRegion("Frame")
function GameTooltip:SetOwner(owner) self.owner=owner end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:SetSpellByID(id) self.spell=id end
StaticPopupDialogs={}
local dialogTable,shownPopup=StaticPopupDialogs,nil
StaticPopup_Show=function(which) shownPopup=which end
local recapOpened
OpenDeathRecapUI=function(id) recapOpened=id end

-- Blizzard menu stub: records descriptions so the test can pick entries.
local lastMenu
local function Description()
    local node={items={}}
    local function Add(entry) node.items[#node.items+1]=entry;return entry end
    function node:CreateButton(text,callback,data) local item=Description();item.text,item.callback,item.data=text,callback,data;return Add(item) end
    function node:CreateTitle(text) return Add({text=text,title=true}) end
    function node:CreateRadio(text,selected,callback,data) local item=Description();item.text,item.selected,item.callback,item.data,item.radio=text,selected,callback,data,true;return Add(item) end
    function node:CreateCheckbox(text,selected,callback,data) local item=Description();item.text,item.selected,item.callback,item.data,item.checkbox=text,selected,callback,data,true;return Add(item) end
    function node:CreateDivider() Add({divider=true}) end
    function node:AddInitializer(initializer) self.initializers=self.initializers or {};self.initializers[#self.initializers+1]=initializer end
    function node:SetIsSelected(selected) self.selected=selected end
    function node:IsSelected() return self.selected and self.selected(self.data) or false end
    function node:SetEnabled(enabled) self.enabled=enabled end
    return node
end
MenuUtil={CreateContextMenu=function(owner,generator,...) local rootNode=Description();rootNode.owner=owner;generator(owner,rootNode,...);lastMenu=rootNode;return rootNode end}
local function Find(node,text)
    for _,item in ipairs(node.items) do
        if item.text==text then return item end
        if item.items then local found=Find(item,text);if found then return found end end
    end
end
local function Pick(node,text) local item=assert(Find(node,text),"menu entry missing: "..text);item.callback(item.data);return item end

-- MSUF Edit Mode API and one host adapter record for the suppression claim.
local elements={}
MSUF_EditModeAPI={RegisterElement=function(_,element) elements[element.id]=element;return true end,RefreshOwner=function() end,UnregisterOwner=function() end}
local hostRecord={isEnabled=function() return true end}
MSUF_EM2={ExternalElements={GetRecord=function(key) return key=="external:msuf.blizzard:damagemeter" and hostRecord or nil end}}

------------------------------------------------------------------ meter data
local api={secret=false,available=true,reason="",duration=42,resets=0,fetch=0,fetchID=0,source=0}
local function V(value,label) if api.secret then return Secret(label) end;return value end
local roster={
    {name="Tank-Realm",class="WARRIOR",guid="Player-Tank",total=1500000,pps=15000,death=17},
    {name="Me",class="MAGE",guid="Player-1",total=900000,pps=9000,death=34,isLocal=true,spec=135932},
    {name="Healer-Realm",class="PRIEST",guid="Player-Heal",total=300000,pps=3000,death=51},
}
api.roster=roster
local function Session(meterType)
    if api.empty then return {combatSources={},maxAmount=0,totalAmount=0} end
    if meterType==10 then
        local enemies={{name=V("Boss","bossname"),classFilename="",specIconID=0,sourceGUID=V("Creature-0-99","bossguid"),
            sourceCreatureID=V(99,"bossid"),totalAmount=V(2300,"bosstotal"),amountPerSecond=V(23,"bosspps"),isLocalPlayer=false,
            deathRecapID=0,deathTimeSeconds=V(0,"bossdeath")}}
        if api.targetMode then enemies[2]={name="Add",classFilename="",sourceGUID="Creature-0-100",
            sourceCreatureID=100,totalAmount=700,amountPerSecond=7,isLocalPlayer=false} end
        return {combatSources=enemies,maxAmount=V(2300,"bossmax"),totalAmount=V(2300,"bosssum"),durationSeconds=V(100,"duration")}
    end
    local list,sum={},0
    for i,unit in ipairs(api.roster) do
        list[i]={name=V(unit.name,"name"..i),classFilename=unit.class,specIconID=unit.spec or 0,sourceGUID=V(unit.guid,"guid"..i),
            totalAmount=V(unit.total,"total"..i),amountPerSecond=V(unit.pps,"pps"..i),isLocalPlayer=unit.isLocal==true,
            deathRecapID=unit.recap or 0,deathTimeSeconds=V(unit.death,"death"..i)}
        sum=sum+unit.total
    end
    return {combatSources=list,maxAmount=V(api.roster[1].total,"max"),totalAmount=V(sum,"sum"),durationSeconds=V(100,"duration")}
end
local function Detail(meterType, creature)
    if (meterType==2 or meterType==3) and api.healTargetMode then
        local function Heal(id,amount,unit,class)
            return {spellID=V(id,"healspell"),totalAmount=V(amount,"healtotal"),amountPerSecond=V(amount/100,"healpps"),
                creatureName="",combatSpellDetails={unitName=V(unit,"healunit"),unitClassFilename=class,
                    amount=V(amount,"healamount"),specIconID=0}}
        end
        return {combatSpells={Heal(2061,600,"Me","MAGE"),Heal(2061,400,"Me","MAGE"),
            Heal(2060,300,"Healer-Realm","PRIEST")},maxAmount=600,totalAmount=1300}
    end
    if meterType==10 then
        local function Hit(id,amount,unit,class,detailAmount) return {spellID=V(id,"spell"),totalAmount=V(amount,"hit"),amountPerSecond=V(amount/100,"hitpps"),
            creatureName="",combatSpellDetails={unitName=V(unit,"unit"),unitClassFilename=class,
                amount=V(detailAmount or amount,"detail"),specIconID=0}} end
        if api.targetMode and creature==100 then
            return {combatSpells={Hit(133,400,"Tank","WARRIOR"),Hit(116,300,"Me","MAGE")},maxAmount=400,totalAmount=700}
        end
        return {combatSpells={Hit(133,1000,"Tank","WARRIOR",100),Hit(116,700,"Me","MAGE"),Hit(6343,600,"Tank","WARRIOR")},maxAmount=V(1000,"smax"),totalAmount=V(2300,"ssum")}
    end
    return {combatSpells={
        {spellID=V(133,"spell1"),totalAmount=V(600000,"spelltotal1"),amountPerSecond=V(6000,"spellpps1"),creatureName="",combatSpellDetails={}},
        {spellID=V(2136,"spell2"),totalAmount=V(300000,"spelltotal2"),amountPerSecond=V(3000,"spellpps2"),creatureName=V("Pet","pet"),combatSpellDetails={}},
    },maxAmount=V(600000,"spellmax"),totalAmount=V(900000,"spellsum")}
end
local function Plain(...) for i=1,select("#",...) do assert(not IsSecret((select(i,...))),"secret argument passed back into a getter") end end
C_DamageMeter={
    GetCombatSessionFromType=function(sessionType,meterType) Plain(sessionType,meterType);api.fetch=api.fetch+1;api.lastSession=sessionType;return Session(meterType) end,
    GetCombatSessionFromID=function(id,meterType) Plain(id,meterType);api.fetchID=api.fetchID+1;api.lastID=id;return Session(meterType) end,
    GetCombatSessionSourceFromType=function(sessionType,meterType,guid,creature)
        Plain(sessionType,meterType,guid,creature);api.source=api.source+1;api.lastGUID,api.lastCreature=guid,creature;return Detail(meterType,creature)
    end,
    GetCombatSessionSourceFromID=function(id,meterType,guid,creature)
        Plain(id,meterType,guid,creature);api.source=api.source+1;api.lastGUID,api.lastCreature=guid,creature;return Detail(meterType,creature)
    end,
    GetSessionDurationSeconds=function() api.durationReads=(api.durationReads or 0)+1;return api.duration end,
    GetAvailableCombatSessions=function() return {{sessionID=6,name="Trash",durationSeconds=20},{sessionID=7,name="Boss",durationSeconds=65}} end,
    IsDamageMeterAvailable=function() return api.available,api.reason end,
    ResetAllCombatSessions=function() api.resets=api.resets+1 end,
}

------------------------------------------------------------------ load
local Suite=MSUFSuite
local Support=dofile(root.."/tools/tests/suite_test_support.lua")
Support.Load(root,"MSUF_Suite",Suite,"Core/Suite.lua")
assert(loadfile(root.."/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite",Suite)
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
local files={"Data","Rows","Window","Breakdown","Menus","Timer","Controller"}
local private={}
-- Blizzard builds its shared font objects at startup on every client.
GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
for _,file in ipairs({"Surfaces","Runtime","EditMode"}) do
    assert(loadfile(root.."/MSUF_Suite_Modules/"..file..".lua"))("MSUF_Suite_Modules",private)
end
local baseFrames=#frames
for _,file in ipairs(files) do
    assert(loadfile(root.."/MSUF_Suite_DamageMeter/"..file..".lua"))("MSUF_Suite_DamageMeter",private)
end
local S,D=Suite.Suite,private.DamageMeter
local M=S.instances.damageMeter
Suite.Client.AddOnEnabled=function() return true end -- the test loaded this optional addon directly
-- Paints and clock ticks are C_Timer.After calls with one shared callback
-- each (D.DeferredPaint, D.ClockTick); a request is pending while its flag is
-- set and returns the call in flight that will serve it.
local function Request(pending,callback)
    if not pending then return nil end
    for _,entry in ipairs(afters) do if entry.callback==callback then return entry end end
    return {delay="no call in flight"}
end
local function PaintRequest() return Request(M.pendingPaint,D.DeferredPaint) end
local function ClockRequest() return Request(M.clockRunning,D.ClockTick) end
local function LiveTimers() return (M.pendingPaint and 1 or 0)+(M.clockRunning and 1 or 0) end
local function OtherCalls()
    local count=0
    for _,entry in ipairs(afters) do
        if entry.callback~=D.DeferredPaint and entry.callback~=D.ClockTick then count=count+1 end
    end
    return count
end
local function RunPaint()
    local pending=M.pendingPaint
    RunCalls(D.DeferredPaint)
    return pending and 1 or 0
end
local function RunClock()
    local running=M.clockRunning
    RunCalls(D.ClockTick)
    return running and 1 or 0
end
assert(M and D and S.catalog.damageMeter.cvars.damageMeterEnabled,"module did not install")
assert(#frames==baseFrames and Created("Texture")==0 and #timers==0 and #afters==0,"loading allocated frames or timers")

-- The controller drives the lifecycle; a disabled module stays dormant.
S.started=true
local c=S.Config("damageMeter")
assert(c.windowCount==2 and c.w1Type==1 and c.w2Type==3 and c.w1Session==1 and c.w2Session==1
    and c.w1X==-20 and c.w2X==-20 and c.w1Y==20 and c.w2Y==210
    and c.refreshRate==1 and c.showPlayer and c.trackAlpha==42
    and c.bgAlpha==82 and c.borderSize==1 and c.look==5
    and c.bgColor=="101010" and c.borderColor=="333333", "damage meter defaults")
c.enabled = false
S.Apply("damageMeter")
assert(not M.context and #frames==baseFrames and #timers==0 and #afters==0,"disabled module allocated work")

local function Frame() return M.context.frame end
local function Event(name,...)
    assert(Frame().events[name],"event not registered: "..name)
    Frame().scripts.OnEvent(Frame(),name,...)
end
local function Registered(name) return M.context.frame and M.context.frame.events[name]==true end
local function Row(win,slot) return win.rows[slot] end

------------------------------------------------------------------ enable
assert(S.Set("damageMeter","enabled",true))
assert(S.states.damageMeter.active and M.active,"module not active")
assert(cvars.damageMeterEnabled=="0","Blizzard meter UI not hidden")
assert(hostRecord.isEnabled()==false,"MSUF damage meter mover not claimed")
local win=assert(D.windows[1])
local heal=assert(D.windows[2],"default healing window was not created")
assert(heal.shown and heal.frame.shown and heal.meterType==2 and heal.sessionType==D.CURRENT
    and heal.frame.points[1][1]=="BOTTOMRIGHT" and heal.frame.points[1][4]==-20
    and heal.frame.points[1][5]==210,"healing window must show Current above damage at bottom right")
-- The outline frames a box one border width outside the window.
do
    local box, edges = heal.borderBox, heal.edges
    assert(box.points[1][1]=="TOPLEFT" and box.points[1][2]==heal.border and box.points[1][4]==-1
        and box.points[1][5]==1 and box.points[2][1]=="BOTTOMRIGHT" and box.points[2][4]==1
        and box.points[2][5]==-1 and not box.shown, "window outline box is not one border width outside")
    for i=1,4 do assert(edges[i].shown and edges[i].points[1][2]==box,"window outline strip "..i.." left the box") end
end
assert(win.shown and win.frame.shown and win.capacity>0)
assert(api.fetch==2,"two default windows should each fetch one session")
local sharedFetches=api.fetch
assert(S.Set("damageMeter","w2Type",c.w1Type))
assert(api.fetch==sharedFetches+1 and rawequal(heal.session,win.session),
    "same meter and fight should fetch one snapshot for both windows")
sharedFetches=api.fetch
D.MarkAll(); D.PaintDirty()
assert(api.fetch==sharedFetches+1,"shared snapshot must be fresh on the next paint batch")
assert(S.Set("damageMeter","w2Session",2))
sharedFetches=api.fetch
D.MarkAll(); D.PaintDirty()
assert(api.fetch==sharedFetches+2,"different fights must keep separate session fetches")
assert(S.SetMany("damageMeter",{w2Type=3,w2Session=1}))
assert(#win.rows==3 and not win.rows[4],"rows are not pooled to the visible data")
assert(Row(win,1).nameText.text=="Tank" and Row(win,1).rankText.text=="1.","plain name or rank missing")
assert(c.showRealm==false and D.Short("Tank-Realm")=="Tank","server names should be hidden by default")
assert(S.Set("damageMeter","showRealm",true) and Row(win,1).nameText.text=="Tank-Realm"
    and D.Short("Älvaro-Realm")=="Älvaro-Realm","server-name toggle did not show full names")
assert(S.Set("damageMeter","showRealm",false) and Row(win,1).nameText.text=="Tank",
    "server-name toggle did not restore short names")
local protectedName=Secret("crossRealmName")
assert(Label(D.Short(protectedName))=="short:crossRealmName","protected server name was not passed to Ambiguate")
c.showRealm=true
assert(rawequal(D.Short(protectedName),protectedName),"show-server setting must preserve protected full names")
c.showRealm=false
assert(Row(win,1).valueText.text=="1.50M (15.0K)","value format 3 wrong: "..tostring(Row(win,1).valueText.text))
assert(Row(win,1).bar.max==1500000 and Row(win,1).bar.value==1500000 and Row(win,3).bar.value==300000)
assert(Row(win,2).icon.texture==135932,"spec icon missing")
assert(Row(win,1).icon.texture:find("CharacterCreate%-Classes"),"class sprite fallback missing")
local bar=Row(win,1).bar
assert(c.gradientEnabled==false and not bar.gradientOverlays,"gradient should be dormant by default")
assert(S.SetMany("damageMeter",{gradientEnabled=true,gradientStrength=60,gradientColor="123456",
    gradientDirLeft=true,gradientDirRight=false,gradientDirUp=true,gradientDirDown=false,barAlpha=70}))
local overlays=assert(bar.gradientOverlays)
local left,up=assert(overlays.gradientLeft),assert(overlays.gradientUp)
assert(not overlays.gradientRight and not overlays.gradientDown,"disabled directions allocated textures")
assert(left.allPoints==bar.statusTexture and up.allPoints==bar.statusTexture,
    "gradient must follow the filled bar texture")
assert(left.gradient[1]=="HORIZONTAL" and up.gradient[1]=="VERTICAL"
    and left.gradient[2][4]==.6 and left.gradient[3][4]==0
    and up.gradient[2][4]==0 and up.gradient[3][4]==.6,
    "direction gradient orientation or alpha is wrong")
assert(math.abs(left.gradient[2][1]-0x12/255)<.001 and left.alpha==.7,
    "gradient color or bar opacity was not applied")
local gradientTextureCount=Created("Texture")
D.MarkAll(); D.PaintDirty()
assert(Created("Texture")==gradientTextureCount,"painting reallocated gradient textures")
assert(S.SetMany("damageMeter",{gradientDirLeft=false,gradientDirRight=true,gradientDirUp=false,
    gradientDirDown=true}))
assert(not left.shown and not up.shown and overlays.gradientRight.shown and overlays.gradientDown.shown,
    "direction toggle did not hide and show the correct overlays")
assert(overlays.gradientRight.allPoints==bar.statusTexture
    and overlays.gradientDown.gradient[2][4]==.6 and overlays.gradientDown.gradient[3][4]==0,
    "direction toggle did not retarget the current fill")
assert(S.SetMany("damageMeter",{gradientEnabled=false,barAlpha=100}))
assert(not overlays.gradientRight.shown and not overlays.gradientDown.shown,
    "turning gradient off left an overlay visible")
assert(win.title.text=="Damage Done","title should use Blizzard's localized type name")
assert(win.timer.text=="(0:42)","header timer should show the Current duration")
strictFontText=true
D.OpenTypeMenu(win,win.header)
strictFontText=false
local typePanel=assert(D.typePanel)
assert(typePanel.shown and typePanel.win==win and typePanel.events.GLOBAL_MOUSE_DOWN,"type picker did not open")
assert(typePanel.headings[1].text=="Damage" and typePanel.headings[2].text=="Healing"
    and typePanel.headings[3].text=="Actions","type picker headings missing")
for _,heading in ipairs(typePanel.headings) do assert(heading.font,"type heading has no font") end
local tileCount=0
for meterType=0,10 do
    local button=assert(typePanel.buttons[meterType])
    assert(button.label.text==D.TypeName(meterType) and button.label.font and button.arrow.font,"type choice has no font")
    tileCount=tileCount+1
end
assert(tileCount==11 and typePanel.buttons[0].points[1][4]~=typePanel.buttons[1].points[1][4],"type picker needs eleven choices in two columns")
assert(typePanel.buttons[0].bg.color[2]>typePanel.buttons[1].bg.color[2],"selected type lacks visible highlight")
assert(math.abs(typePanel.palette.accent[1]-0xe6/255)<.001 and math.abs(typePanel.palette.accent[2]-0xec/255)<.001,
    "Clean Modern picker should use the meter color instead of a fixed teal accent")
assert(typePanel.buttons[0].parent==typePanel and typePanel.buttons[0].label.parent==typePanel.buttons[0],"type choices must be addon-owned frames")
local countAfterFirstOpen=Created("Button")
D.HideTypeMenu()
assert(not typePanel.shown and not typePanel.events.GLOBAL_MOUSE_DOWN,"closed picker must release its dismissal event")
D.OpenTypeMenu(win,win.header)
assert(D.typePanel==typePanel and Created("Button")==countAfterFirstOpen,"type picker must reuse its frames")
typePanel.mouseOver=true
typePanel.scripts.OnEvent(typePanel,"GLOBAL_MOUSE_DOWN","LeftButton")
assert(typePanel.shown,"inside click closed type picker")
typePanel.mouseOver=false
typePanel.scripts.OnEvent(typePanel,"GLOBAL_MOUSE_DOWN","LeftButton")
assert(not typePanel.shown,"outside click failed to close type picker")
local client=MSUFSuite.Client
local wasForever=client.isForever
client.isForever=true
D.OpenTypeMenu(win,win.header)
assert(math.abs(typePanel.palette.accent[1]-0xe6/255)<.001
    and math.abs(typePanel.palette.accent[2]-0xec/255)<.001,
    "picker should follow the selected Clean Modern meter style even on Forever")
D.HideTypeMenu()
client.isForever=wasForever
D.HeaderButtonClick(win.buttons.type)
assert(typePanel.shown and typePanel.owner==win.buttons.type,"header type button must open the tile picker")
D.HideTypeMenu()
assert(S.SetMany("damageMeter",{bgColor="14181b",headerColor="20272a",borderColor="9f8960",
    barColor="d8b66a",titleColor="f1e3c4"}))
D.OpenTypeMenu(win,win.header)
assert(math.abs(typePanel.palette.accent[1]-0x9f/255)<.001
    and math.abs(typePanel.bg.color[1]-0x14/255)<.001
    and math.abs(typePanel.edges[1].color[2]-0x89/255)<.001
    and math.abs(typePanel.buttons[0].label.textColor[1]-0xf1/255)<.001,
    "picker did not adopt the meter background, border, and text colors")
D.HideTypeMenu()
assert(S.SetMany("damageMeter",{bgColor="000000",headerColor="1b1b1b",borderColor="000000",
    barColor="598ccc",titleColor="ffffff"}))
assert(c.combatTime and c.headerTimer and not c.timer and c.rendering==3
    and c.outline==2 and c.nameMaxChars==0,"text and time defaults")
assert(S.Set("damageMeter","headerTimer",false) and win.timer.text=="" and heal.timer.text=="","header timer switch did not clear both windows")
assert(S.Set("damageMeter","headerTimer",true) and win.timer.text=="(0:42)","header timer did not restore")
assert(S.Set("damageMeter","combatTime",false) and win.timer.text=="" and heal.timer.text=="","master combat time switch did not clear headers")
assert(S.Set("damageMeter","combatTime",true) and win.timer.text=="(0:42)","master combat time switch did not restore headers")
assert(S.SetMany("damageMeter",{rendering=3,outline=3,textOpacity=70,baseline=2,nameMaxChars=2,shadowOpacity=55,shadowDistance=2}))
assert(Row(win,1).nameText.font[3]=="OUTLINE,SLUG" and Row(win,1).nameText.shadowOffset[1]==0,
    "Slug must use normal outline without a text shadow")
assert(Row(win,1).nameText.scaleModeFlags=="OUTLINE,SLUG","Slug font scale mode not applied")
assert(Row(win,1).nameText.alpha==.7 and Row(win,1).rankText.points[1][5]==2,"text opacity or baseline did not apply")
assert(Row(win,1).nameText.text=="Ta..." and D.Short("Älvaro-Realm")=="Äl...","UTF-8 name shortening failed")
assert(S.Set("damageMeter","nameEllipsis",false) and Row(win,1).nameText.text=="Ta","shortening without ellipsis failed")
assert(S.SetMany("damageMeter",{rendering=2,outline=1,textOpacity=100,baseline=0,nameMaxChars=0,nameEllipsis=true,shadowOpacity=55,shadowDistance=2}))
assert(Row(win,1).nameText.font[3]=="MONOCHROME" and Row(win,1).nameText.shadowOffset[1]==2
    and Row(win,1).nameText.shadowColor[4]==.55 and Row(win,1).nameText.text=="Tank","sharp font or shadow styling failed")
assert(S.Set("damageMeter","outline",5) and Row(win,1).nameText.font[3]=="OUTLINE,MONOCHROME"
    and Row(win,1).nameText.shadowOffset[1]==2,"outline plus shadow style failed")
assert(S.SetMany("damageMeter",{rendering=1,outline=1,shadowOpacity=100,shadowDistance=1}))
local rejected={calls={}}
function rejected:SetFont(path,size,flags)
    self.calls[#self.calls+1]=flags
    return flags==""
end
assert(S.SetFont(rejected,"missing.ttf",11,"SLUG")=="" and #rejected.calls==3,
    "unsupported rendering flag did not fall back to a visible native font")
-- The remaining lifecycle scenarios start with one window and add more explicitly.
assert(S.Set("damageMeter","windowCount",1))
assert(not heal.frame.shown,"reducing the count did not hide the healing window")
for _,name in ipairs({"DAMAGE_METER_COMBAT_SESSION_UPDATED","DAMAGE_METER_CURRENT_SESSION_UPDATED","DAMAGE_METER_RESET",
    "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","ENCOUNTER_START","ENCOUNTER_END","PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA","CHALLENGE_MODE_START","ADDON_RESTRICTION_STATE_CHANGED"}) do
    assert(Registered(name),"missing event "..name)
end
assert(not Registered("GROUP_ROSTER_UPDATE"),"roster event without group visibility")
assert(#timers==0 and #afters==0,"out-of-combat enable started timers")

-- Unchanged plain values are memoized.
local writes=Row(win,1).valueText.writes
local nameWrites=Row(win,1).nameText.writes
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0);RunPaint()
assert(Row(win,1).valueText.writes==writes and Row(win,1).nameText.writes==nameWrites,"plain memo rewrote unchanged text")

------------------------------------------------------------------ dedupe and coalescing
local fetches=api.fetch
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,7)
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",2,0)
assert(not PaintRequest() and not win.dirty,"current-session copy or other meter type repainted a Current window")
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0)
-- Every shown window is dirty behind a pending paint: the rest of the burst
-- cannot change what that paint draws, so the event is muted until it runs.
assert(not Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"),
    "session updates kept firing behind a pending paint that already covers them")
Event("DAMAGE_METER_CURRENT_SESSION_UPDATED")
assert(PaintRequest() and PaintRequest().delay==.1 and LiveTimers()==1,
    "event burst was not coalesced into one deferred paint")
RunPaint()
assert(api.fetch==fetches+1,"coalesced repaint should fetch once")
assert(Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"),"session updates stayed muted after the paint")
assert(RunPaint()==0)

-- Fight menu: pin a historic session; it reacts to its own sessionID only.
D.HeaderButtonClick(win.buttons.session)
assert(Find(lastMenu,"Boss [1:05]") and Find(lastMenu,"Current fight") and Find(lastMenu,"Overall"),"fight menu incomplete")
Pick(lastMenu,"Boss [1:05]")
assert(win.sessionID==7 and api.lastID==7 and win.buttons.session.label.text=="#","pinned session not shown")
assert(win.timer.text=="(1:05)","pinned fight should show its stored duration")
assert(c.w1Session==1,"a pinned fight keeps Current as the saved fallback")
fetches=api.fetchID
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0);assert(not PaintRequest(),"pinned window reacted to the overall copy")
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,7);RunPaint()
assert(api.fetchID==fetches+1,"pinned window missed its own session update")

------------------------------------------------------------------ combat, secrets, one-shot paints
api.secret,combat=true,true
now=200
Event("PLAYER_REGEN_DISABLED")
assert(not win.sessionID,"autoCurrent did not return to the current fight")
assert(LiveTimers()==1 and ClockRequest() and not PaintRequest(),
    "combat start must schedule only the visible clock")
local name1=Row(win,1).nameText.text
assert(Label(name1)=="short:name1","secret name was not shortened by native Ambiguate")
assert(Label(Row(win,1).bar.value)=="total1" and Label(Row(win,1).bar.max)=="max","secret totals did not reach the StatusBar")
local value=Row(win,1).valueText.text
assert(type(value)=="table" and value.format=="%s (%s)" and Label(value.args[1])=="abbr:total1" and Label(value.args[2])=="abbr:pps1",
    "secret values must go through AbbreviateNumbers and SetFormattedText")
M.style.numberFormat,M.style.valueOrder,M.style.valueSeparator=5,5,3
D.SetValueText(Row(win,1),0,Secret("customtotal"),Secret("customrate"),Secret("customdenominator"),true)
value=Row(win,1).valueText.text
assert(type(value)=="table" and value.format=="%s [%s]" and Label(value.args[1])=="abbr:customtotal"
    and Label(value.args[2])=="abbr:customrate","custom layout must omit unavailable percent and keep secrets in C sinks")
D.SetValueText(Row(win,1),0,1000,Secret("mixedrate"),2000,true)
value=Row(win,1).valueText.text
assert(type(value)=="table" and value.format=="%s [%s] [%s]" and value.args[1]=="50%"
    and value.args[2]=="1.00K" and Label(value.args[3])=="abbr:mixedrate",
    "custom layout must place a plain share before a secret rate")
M.style.valueSeparator=6
D.SetValueText(Row(win,1),0,Secret("hyphentotal"),Secret("hyphenrate"),Secret("hyphendenominator"),true)
value=Row(win,1).valueText.text
assert(type(value)=="table" and value.format=="%s - %s" and Label(value.args[1])=="abbr:hyphentotal"
    and Label(value.args[2])=="abbr:hyphenrate","hyphen layout must keep secrets in C sinks")
M.style.numberFormat,M.style.valueOrder,M.style.valueSeparator=3,1,2
assert(OtherCalls()==0 and not PaintRequest(),"combat start left a deferred paint")
-- Mixed readability: plain row values with a secret total never compute a share.
D.SetValueText(Row(win,1),0,1000,10,Secret("sessiontotal"),true)
assert(Row(win,1).valueText.text=="1.00K (10)","secret denominator produced a share")
fetches=api.fetch
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0)
assert(PaintRequest() and PaintRequest().delay==1 and api.fetch==fetches,
    "combat event must schedule one paint at refreshRate")
now=201;RunPaint()
assert(api.fetch==fetches+1,"one-shot did not paint the dirty window")
now=202;RunClock()
assert(api.fetch==fetches+1 and not PaintRequest(),"clock repainted a clean window")
assert(win.timer.text=="(0:02)","live header timer should follow the combat clock: "..tostring(win.timer.text))

-- Breakdown: another player's secret row is blocked; the own row maps to UnitGUID("player").
local sources=api.source
strictFontText=true
Row(win,1).scripts.OnClick(Row(win,1),"LeftButton")
strictFontText=false
assert(win.bd.open and win.bd.blocked and win.panel.shown,"blocked breakdown did not open")
assert(win.panel.message.text=="Details are available after combat." and api.source==sources,"secret identity queried the API")
win.panel.scripts.OnClick(win.panel,"RightButton")
assert(not win.bd.open and Row(win,1).shown,"back action did not restore the list")
Row(win,2).scripts.OnClick(Row(win,2),"LeftButton")
assert(win.bd.open and not win.bd.blocked and api.source==sources+1 and api.lastGUID=="Player-1","own row breakdown not allowed in combat")
local spell=win.bdRows[1]
assert(Label(spell.nameText.text)=="spellname" and not spell.icon.shown,"secret spell must use GetSpellName and skip the icon")
assert(Label(spell.bar.value)=="spelltotal1","secret spell totals did not reach the bar")
spell.scripts.OnEnter(spell)
assert(GameTooltip.owner~=spell,"spell tooltip shown for a secret spell ID")
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0)
fetches=api.fetch
now=203;RunPaint()
assert(api.source==sources+2 and api.fetch==fetches,"open breakdown should refresh with one source fetch")
spell.scripts.OnClick(spell,"LeftButton")
assert(not win.bd.open)

-- Hover tooltip: built once per hover with the same rules.
sources=api.source
strictFontText=true
Row(win,1).scripts.OnEnter(Row(win,1))
strictFontText=false
assert(M.tip.shown and M.tip.message.text=="Details are available after combat." and api.source==sources)
Row(win,1).scripts.OnLeave(Row(win,1))
assert(not M.tip.shown)
Row(win,2).scripts.OnEnter(Row(win,2))
assert(M.tip.shown and api.source==sources+1 and M.tip.rows[1].shown and M.tip.rows[2].shown,"own hover breakdown missing")
Row(win,2).scripts.OnLeave(Row(win,2))

-- A meter pick in combat applies now and is saved after combat.
D.OpenTypeMenu(win,win.header)
typePanel.buttons[2].scripts.OnClick(typePanel.buttons[2])
assert(win.meterType==2 and c.w1Type==1,"combat pick must apply at once and wait with the save")
assert(M.pendingWrites and M.pendingWrites.w1Type==3)
D.HeaderButtonClick(win.buttons.settings)
assert(Find(lastMenu,"Lock window").enabled==false,"window settings must be disabled in combat")

-- Combat end: final paint, clock stops, a delayed repaint follows.
Row(win,1).scripts.OnClick(Row(win,1),"LeftButton")
assert(win.bd.open and win.bd.blocked)
combat,api.secret=false,false
fetches=api.fetch
Event("PLAYER_REGEN_ENABLED")
assert(not win.bd.open and Row(win,1).shown,"blocked panel must close once data is readable")
assert(LiveTimers()==0 and not ClockRequest() and not PaintRequest(),"timers survived combat")
assert(c.w1Type==3 and not M.pendingWrites,"combat pick was not saved after combat")
assert(api.fetch>fetches and Row(win,1).nameText.text=="Tank","no final paint after combat")
assert(RunAfters(.5)==1,"no declassification repaint scheduled")
Event("ADDON_RESTRICTION_STATE_CHANGED",0,0)
assert(PaintRequest(),"declassification edge did not request a repaint");RunPaint()
S.Set("damageMeter","w1Type",1)

------------------------------------------------------------------ geometry, visibility, movers
local frame=win.frame
frame.right,frame.bottom,frame.width,frame.height=1800,60,300,220
win.grip.scripts.OnMouseDown(win.grip,"LeftButton")
assert(frame.sizing=="BOTTOMRIGHT","resize grip did not start sizing")
win.grip.scripts.OnMouseUp(win.grip,"LeftButton")
assert(c.w1Width==300 and c.w1Height==220 and c.w1X==-120 and c.w1Y==60,"resize was not saved as BOTTOMRIGHT geometry")
assert(frame.points[1][1]=="BOTTOMRIGHT" and frame.points[1][4]==-120,"window not re-anchored from settings")
S.Set("damageMeter","w1Locked",true)
win.header.scripts.OnDragStart(win.header)
assert(not frame.moving,"locked window moved")
S.Set("damageMeter","w1Locked",false)
combat=true;win.header.scripts.OnDragStart(win.header);assert(not frame.moving,"window moved in combat");combat=false
win.header.scripts.OnDragStart(win.header);assert(frame.moving)
frame.right,frame.bottom=1900,80
win.header.scripts.OnDragStop(win.header)
assert(c.w1X==-20 and c.w1Y==80,"header drag not saved")

for i=1,5 do
    local element=assert(elements["window"..i],"mover missing for window "..i)
    local state=element.captureState()
    assert(state.values["w"..i.."X"]~=nil and state.values["w"..i.."Y"]~=nil,"mover keys wrong for window "..i)
    assert(state.values["w"..i.."Width"]~=nil and state.values["w"..i.."Height"]~=nil
        and #element.extraControls==4,"meter popup omitted position or window size from Edit Mode history")
end
local windowState=elements.window1.captureState()
assert(elements.window1.extraControls[1].id=="w1X" and elements.window1.extraControls[2].id=="w1Y"
    and elements.window1.extraControls[3].set(340) and c.w1Width==340
    and elements.window1.extraControls[4].set(240) and c.w1Height==240
    and elements.window1.restoreState(windowState)
    and c.w1Width==windowState.values.w1Width and c.w1Height==windowState.values.w1Height,
    "meter popup dimensions did not apply and restore")
assert(elements.window1.label=="Damage Meter 1" and elements.window1.isEnabled() and not elements.window2.isEnabled())
assert(elements.timer and not elements.timer.isEnabled(),"timer mover must follow the timer setting")
assert(S.Set("damageMeter","timer",true))
assert(M.timerFrame and elements.timer.isEnabled() and elements.timer.captureState().values.timerX==0)
local timerState=elements.timer.captureState()
assert(timerState.values.timerSize==c.timerSize and elements.timer.extraControls[3].set(30)
    and c.timerSize==30 and elements.timer.restoreState(timerState)
    and c.timerSize==timerState.values.timerSize,
    "timer popup text size did not apply and restore")
assert(not M.timerFrame.shown,"standalone timer shown out of combat without timerKeep")

assert(S.Set("damageMeter","timer",false))
c.visibility=4;S.Apply("damageMeter")
assert(frame.alpha==0 and win.faded,"mouseover window should fade out")
fetches=api.fetch
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0);RunPaint()
assert(api.fetch==fetches and win.dirty,"faded windows should skip painting")
frame.mouseOver=true;frame.scripts.OnEnter(frame)
assert(frame.alpha==1 and api.fetch==fetches+1,"hover did not reveal and repaint")
frame.mouseOver=false;Row(win,1).scripts.OnLeave(Row(win,1))
assert(frame.alpha==0)
combat=true;Event("PLAYER_REGEN_DISABLED")
assert(LiveTimers()==0,"fully faded mouseover meters kept a timer")
fetches=api.fetch
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0)
assert(not PaintRequest() and api.fetch==fetches and win.dirty,
    "hidden combat updates scheduled a needless repaint")
frame.mouseOver=true;frame.scripts.OnEnter(frame)
assert(LiveTimers()==1 and ClockRequest() and api.fetch==fetches+1,
    "revealing a meter did not paint and resume its visible clock")
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0)
assert(PaintRequest(),"visible dirty meter did not schedule a paint")
frame.mouseOver=false;Row(win,1).scripts.OnLeave(Row(win,1))
assert(LiveTimers()==0 and not PaintRequest(),
    "fading the last meter did not cancel clock and pending paint")
frame.mouseOver=true;frame.scripts.OnEnter(frame)
assert(api.fetch==fetches+2 and not win.dirty,"revealed meter did not catch up after a canceled paint")
frame.mouseOver=false;Row(win,1).scripts.OnLeave(Row(win,1))
combat=false;Event("PLAYER_REGEN_ENABLED");RunAfters(.5)
assert(S.Set("damageMeter","timer",true))
c.visibility=1;S.Apply("damageMeter")
S.Set("damageMeter","w1HideWorld",true)
assert(not frame.shown and not Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"),"hidden windows must drop data events")
assert(Registered("PLAYER_ENTERING_WORLD") and Registered("PLAYER_REGEN_DISABLED"),"visibility events lost")
inside,instanceType=true,"party";Event("ZONE_CHANGED_NEW_AREA")
assert(frame.shown and Registered("DAMAGE_METER_RESET"),"window not shown again inside an instance")
inside,instanceType=false,"none"
S.Set("damageMeter","w1HideWorld",false)
S.Set("damageMeter","visibility",3)
assert(not frame.shown and Registered("GROUP_ROSTER_UPDATE"))
grouped=true;Event("GROUP_ROSTER_UPDATE");assert(frame.shown,"group visibility")
grouped=false;S.Set("damageMeter","visibility",1)

------------------------------------------------------------------ edit mode and preview
S.Set("damageMeter","w1Locked",true)
api.empty=true
S.SetEditMode(true)
assert(M.forced and frame.shown and D.CanMove(win),"Edit Mode must force visible, unlocked windows")
assert(Row(win,1).nameText.text=="WARRIOR" and Row(win,1).shown,"Edit Mode should show sample rows without data")
S.SetEditMode(false)
assert(not M.forced and not D.CanMove(win) and #win.rows>0 and not Row(win,1).shown,"Edit Mode state leaked")
api.empty=false
S.Set("damageMeter","w1Locked",false)
assert(S.DamageMeterPreview(true) and win.session.isSample and win.timer.text=="(1:35)","preview did not show sample data")
fetches=api.fetch
assert(S.DamageMeterPreview(false) and api.fetch==fetches+1 and not win.session.isSample,"preview off did not restore live data")
combat=true;assert(S.DamageMeterPreview(true)==false,"preview must refuse combat");combat=false

------------------------------------------------------------------ windows: new, close and shift
D.HeaderButtonClick(win.buttons.settings)
Pick(lastMenu,"New window")
assert(c.windowCount==2 and D.windows[2] and D.windows[2].shown,"new window not created")
assert(S.SetMany("damageMeter",{windowCount=3,w2Type=6,w3Type=11,w3Width=333,w3Locked=true,w3X=-400}))
local second,third=D.windows[2],D.windows[3]
assert(third and third.meterType==10)
D.HeaderButtonClick(second.buttons.settings)
Pick(lastMenu,"Close window")
assert(c.windowCount==2 and c.w2Type==11 and c.w2Width==333 and c.w2Locked==true and c.w2X==-400,"later window settings not shifted down")
assert(c.w3Type==S.catalog.damageMeter.rules.w3Type.default and c.w3Width==260 and c.w3Locked==false,"freed slot not reset")
assert(D.windows[2]==third and third.index==2 and third.meterType==10 and D.windows[3]==second and not second.frame.shown,"window objects did not follow their settings")
D.HeaderButtonClick(D.windows[2].buttons.settings)
assert(Find(lastMenu,"Close window").enabled==false,"locked windows must not close")
assert(S.SetMany("damageMeter",{windowCount=1}))
assert(not D.windows[2].frame.shown and not elements.window2.isEnabled())

------------------------------------------------------------------ deaths, enemies, reset
S.Set("damageMeter","w1Type",10)
assert(Row(win,1).valueText.text=="0:17" and Row(win,1).bar.value==1 and Row(win,1).bar.max==1,"death rows need a time and a full bar")
Row(win,1).scripts.OnClick(Row(win,1),"LeftButton")
assert(recapOpened==nil,"row without a recap ID opened the recap")
roster[1].recap=55
Event("DAMAGE_METER_RESET")
Row(win,1).scripts.OnClick(Row(win,1),"LeftButton")
assert(recapOpened==55,"death recap not opened")
roster[1].recap=nil
S.Set("damageMeter","w1Session",2)
assert(Row(win,1).valueText.text=="" and win.title.text=="Deaths (Overall)","overall deaths must have no time: "..tostring(win.title.text))
S.SetMany("damageMeter",{w1Session=1,w1Type=11})
Row(win,1).scripts.OnClick(Row(win,1),"LeftButton")
assert(win.bd.open and api.lastCreature==99 and api.lastGUID=="Creature-0-99")
assert(win.bdRows[1].nameText.text=="Tank" and win.bdRows[2].nameText.text=="Me" and not win.bdRows[3],"enemy damage not grouped per attacker")
assert(win.bdRows[1].valueText.text=="1.60K (16) 70%","grouped value wrong: "..tostring(win.bdRows[1].valueText.text))
win.panel.scripts.OnClick(win.panel,"LeftButton")
S.Set("damageMeter","w1Type",1)

local resets=api.resets
assert(S.DamageMeterReset(false) and shownPopup=="MSUF_SUITE_DAMAGE_METER_RESET" and api.resets==resets,"reset must confirm first")
assert(StaticPopupDialogs==dialogTable and StaticPopupDialogs.MSUF_SUITE_DAMAGE_METER_RESET.text=="Reset all sessions?")
StaticPopupDialogs.MSUF_SUITE_DAMAGE_METER_RESET.OnAccept();assert(api.resets==resets+1)
assert(S.DamageMeterReset(true) and api.resets==resets+2,"skipConfirm must reset directly")
S.Set("damageMeter","confirmReset",false);shownPopup=nil
S.DamageMeterReset(false);assert(api.resets==resets+3 and shownPopup==nil)
Event("CHALLENGE_MODE_START");assert(api.resets==resets+4,"M+ start did not reset")

------------------------------------------------------------------ scrolling and the pinned own row
roster={}
for i=1,30 do roster[i]={name="Unit"..i,class="WARRIOR",guid="Player-"..(i+10),total=100000-i*1000,pps=1000,death=i} end
roster[25].isLocal=true
api.roster=roster
 S.Set("damageMeter","showPlayer",false)
 S.Set("damageMeter","showPlayer",true)
local capacity=win.capacity
assert(capacity>1 and capacity<25)
assert(Row(win,capacity).rankText.text=="25." and Row(win,capacity).separator.shown,"own row not pinned into the last slot")
fetches=api.fetch
win.body.scripts.OnMouseWheel(win.body,-1)
assert(win.offset==2 and Row(win,1).rankText.text=="3." and api.fetch==fetches,"wheel must scroll two rows without a fetch")
for _=1,20 do win.body.scripts.OnMouseWheel(win.body,-1) end
assert(win.offset==D.MaxOffset(win,30) and win.offset==31-capacity,"scroll clamp")
for slot=1,capacity do
    local row=Row(win,slot)
    assert(not (row.shown and row.separator and row.separator.shown),"visible own row must not be pinned")
end
roster[25].isLocal,roster[5].isLocal=nil,true
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0);RunPaint()
assert(Row(win,1).rankText.text=="5." and Row(win,1).separator.shown,"own row not pinned into the first slot")
assert(Row(win,2).rankText.text==tostring(win.offset+1)..".","list below a top pin starts at the offset")
S.Set("damageMeter","showPlayer",false)

------------------------------------------------------------------ availability
api.available,api.reason=false,"Not available here"
local ok,reason=S.DamageMeterAvailability()
assert(ok==false and reason=="Not available here")
Event("PLAYER_ENTERING_WORLD");RunPaint()
assert(win.status.text=="Not available here" and not Row(win,1).shown,"failure reason not shown in the body")
api.available=true
Event("PLAYER_ENTERING_WORLD");RunPaint()
assert(win.status.text=="" and Row(win,1).shown)

------------------------------------------------------------------ standalone timer and paint pacing
assert(S.SetMany("damageMeter",{timer=true,refreshRate=2}))
assert(S.Set("damageMeter","combatTime",false))
now,combat=300,true
Event("PLAYER_REGEN_DISABLED")
assert(LiveTimers()==0 and not M.timerFrame.shown and win.timer.text==""
    and not elements.timer.isEnabled(),"disabled combat time kept a visible timer or polling")
combat=false
Event("PLAYER_REGEN_ENABLED")
assert(S.Set("damageMeter","combatTime",true))
now,combat=300,true
Event("PLAYER_REGEN_DISABLED")
assert(LiveTimers()==1 and ClockRequest(),"a shown timer needs a visible clock timer")
assert(M.timerFrame.shown and M.timerFrame.text.text=="0:00","standalone timer not live in combat")
fetches=api.fetch
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0)
assert(PaintRequest() and PaintRequest().delay==2,"data paint was not capped by refreshRate")
local durationReads=api.durationReads or 0
now=301;RunClock()
assert(api.fetch==fetches and M.timerFrame.text.text=="0:01",
    "clock must not fetch meter data")
assert(api.durationReads==durationReads+1,"header and separate clock queried duration twice")
assert(not Registered("DAMAGE_METER_COMBAT_SESSION_UPDATED"),
    "session updates kept firing although the pending paint already covers them")
now=302;RunPaint();RunClock()
assert(api.fetch==fetches+1 and M.timerFrame.text.text=="0:02",
    "refreshRate must pace event paints independently of the clock")
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0)
now=303;RunClock()
assert(api.fetch==fetches+1,"clock repainted unchanged data")
now=304;RunPaint()
assert(api.fetch==fetches+2,"new data missed its next paint window")
combat=false
Event("PLAYER_REGEN_ENABLED")
assert(not M.timerFrame.shown,"timer must hide after combat without timerKeep")
assert(S.Set("damageMeter","timerKeep",true))
assert(M.timerFrame.shown and M.timerFrame.text.text=="0:42","timerKeep must show the last duration")
assert(S.SetMany("damageMeter",{timerKeep=false,refreshRate=1}))
RunAfters()

------------------------------------------------------------------ disable and reuse
S.Set("damageMeter","timer",false)
combat=true;Event("PLAYER_REGEN_DISABLED");combat=false
assert(LiveTimers()==1 and ClockRequest() and not PaintRequest())
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",0,0)
assert(PaintRequest(),"combat event did not schedule a paint before disable")
local framesBefore=#frames
assert(S.Set("damageMeter","enabled",false))
assert(not M.active and LiveTimers()==0 and not PaintRequest()
    and not next(Frame().events) and not next(M.context.callbacks),"disable leaked events or timers")
for i=1,5 do if D.windows[i] then assert(not D.windows[i].frame.shown,"window left visible") end end
assert(cvars.damageMeterEnabled=="1","CVar not restored")
assert(hostRecord.isEnabled()==true,"host mover claim not released")
RunAfters();assert(RunAfters()==0,"inactive module scheduled work")
assert(S.Set("damageMeter","enabled",true))
assert(#frames==framesBefore+0 and D.windows[1]==win and win.frame.shown,"re-enable must reuse frames")

------------------------------------------------------------------ plain path: readable values, percent
issecretvalue=nil
roster={
    {name="Tank-Realm",class="WARRIOR",guid="Player-Tank",total=1500000,pps=15000,death=17},
    {name="Me",class="MAGE",guid="Player-1",total=900000,pps=9000,death=34,isLocal=true},
    {name="Healer-Realm",class="PRIEST",guid="Player-Heal",total=300000,pps=3000,death=51},
}
api.roster=roster
assert(S.Set("damageMeter","percent",true))
assert(Row(win,1).valueText.text=="1.50M (15.0K) 56%","plain-value percent missing: "..tostring(Row(win,1).valueText.text))
S.Set("damageMeter","numberFormat",4)
assert(Row(win,1).valueText.text=="1.50M | 15.0K 56%")
S.Set("damageMeter","numberFormat",1)
assert(Row(win,1).valueText.text=="15.0K 56%")
S.SetMany("damageMeter",{numberFormat=3,w1Type=2})
assert(Row(win,1).valueText.text=="15.0K (1.50M) 56%","rate types lead with the rate")
S.SetMany("damageMeter",{w1Type=6})
assert(Row(win,1).valueText.text=="1.50M 56%","interrupts are counts only")
S.SetMany("damageMeter",{numberFormat=5,w1Type=2,valueOrder=1,valueSeparator=2})
local ordered={
    "1.50M (15.0K) (56%)", "1.50M (56%) (15.0K)",
    "15.0K (1.50M) (56%)", "15.0K (56%) (1.50M)",
    "56% (1.50M) (15.0K)", "56% (15.0K) (1.50M)",
}
for order,expected in ipairs(ordered) do
    S.Set("damageMeter","valueOrder",order)
    assert(Row(win,1).valueText.text==expected,"custom value order "..order)
end
for separator,expected in ipairs({
    "56% 15.0K 1.50M", "56% (15.0K) (1.50M)", "56% [15.0K] [1.50M]",
    "56% | 15.0K | 1.50M", "56% / 15.0K / 1.50M", "56% - 15.0K - 1.50M",
}) do
    S.Set("damageMeter","valueSeparator",separator)
    assert(Row(win,1).valueText.text==expected,"custom value separator "..separator)
end
S.SetMany("damageMeter",{valueOrder=5,valueSeparator=3,percent=false})
assert(Row(win,1).valueText.text=="1.50M [15.0K]","disabled percent must collapse the custom layout")
S.SetMany("damageMeter",{w1Type=6,percent=true})
assert(Row(win,1).valueText.text=="56% [1.50M]","count-only meter must omit the rate")
S.SetMany("damageMeter",{w1Type=2,valueSeparator=6,percent=false})
assert(Row(win,1).valueText.text=="1.50M - 15.0K","hyphen layout must collapse an unavailable share")
S.SetMany("damageMeter",{w1Type=6,percent=true})
assert(Row(win,1).valueText.text=="56% - 1.50M","hyphen layout must collapse a count-only rate")
S.SetMany("damageMeter",{numberFormat=3,w1Type=2})
S.Set("damageMeter","w1Type",1)
-- Hovering a damage row shows damage by enemy, aggregated from Blizzard's
-- EnemyDamageTaken view. The inverse session is read once and shared by later
-- hovers; a meter data event invalidates that snapshot.
api.targetMode=true
D.InvalidateTargets()
local targetSources,targetFetches=api.source,api.fetch
Row(win,1).scripts.OnEnter(Row(win,1))
assert(M.tip.title.text=="Tank - Damage Done" and M.tip.rows[1].nameText.text=="Spell133"
    and M.tip.rows[2].nameText.text=="Spell2136 (Pet)" and M.tip.section.shown
    and M.tip.rows[3].nameText.text=="Boss" and M.tip.rows[3].valueText.text:find("1.60K",1,true)
    and M.tip.rows[4].nameText.text=="Add" and M.tip.rows[4].valueText.text:find("400",1,true),
    "hover did not keep abilities above the target breakdown")
assert(api.source==targetSources+3 and api.fetch==targetFetches+1,
    "target hover did not fetch one ability source and one source per enemy")
Row(win,1).scripts.OnLeave(Row(win,1))
-- Abilities remain the default; the visible Targets tab opens the percentages.
Row(win,1).scripts.OnClick(Row(win,1),"LeftButton")
assert(win.bd.open and win.bdRows[1].nameText.text=="Spell133"
    and win.panel.targetsTab.shown and win.panel.spellsTab.shown,
    "clicked damage breakdown hid abilities or its target tab")
win.panel.targetsTab.scripts.OnClick(win.panel.targetsTab)
assert(win.bd.open and win.panel.title.text=="Tank"
    and win.bdRows[1].nameText.text=="Boss" and win.bdRows[1].valueText.text=="1.60K 80%"
    and win.bdRows[2].nameText.text=="Add" and win.bdRows[2].valueText.text=="400 20%",
    "target tab did not show target percentages")
win.panel.spellsTab.scripts.OnClick(win.panel.spellsTab)
assert(win.bd.open and win.bdRows[1].nameText.text=="Spell133",
    "abilities tab did not restore the spell breakdown")
win.panel.scripts.OnClick(win.panel,"LeftButton")
assert(not win.bd.open,"left click did not close the breakdown")
targetSources,targetFetches=api.source,api.fetch
Row(win,2).scripts.OnEnter(Row(win,2))
assert(M.tip.title.text=="Me - Damage Done" and M.tip.rows[1].nameText.text=="Spell133"
    and M.tip.rows[3].nameText.text=="Boss" and M.tip.rows[4].nameText.text=="Add"
    and api.source==targetSources+1 and api.fetch==targetFetches,
    "another player's hover rebuilt the unchanged target cache")
Row(win,2).scripts.OnLeave(Row(win,2))
Event("DAMAGE_METER_COMBAT_SESSION_UPDATED",10,0)
Row(win,1).scripts.OnEnter(Row(win,1))
assert(api.source==targetSources+4 and api.fetch==targetFetches+1,
    "enemy damage update did not invalidate the hover cache")
Row(win,1).scripts.OnLeave(Row(win,1))
S.Set("damageMeter","numberFormat",1)
Row(win,1).scripts.OnEnter(Row(win,1))
assert(M.tip.rows[3].valueText.text:find("1.60K",1,true),
    "DPS-only number format hid the target damage amount")
Row(win,1).scripts.OnLeave(Row(win,1))
S.Set("damageMeter","numberFormat",3)
local className=win.session.combatSources[1].classFilename
win.session.combatSources[1].classFilename=""
D.InvalidateTargets()
assert(D.TargetGroups(win,win.session.combatSources[1])~=nil,
    "a source without a class lost its native enemy target data")
win.session.combatSources[1].classFilename=className
api.secret=true
D.InvalidateTargets()
targetSources=api.source
assert(D.TargetGroups(win,win.session.combatSources[1])==nil and api.source==targetSources,
    "restricted enemy data was inspected or returned as a target breakdown")
api.secret=false
api.targetMode=false
D.InvalidateTargets()
api.empty=true
Row(win,1).scripts.OnClick(Row(win,1),"LeftButton")
assert(win.bdRows[1].nameText.text=="Spell133","missing target data hid abilities")
win.panel.targetsTab.scripts.OnClick(win.panel.targetsTab)
assert(win.panel.title.text=="Tank" and win.panel.message.text=="Target data unavailable"
    and not win.bdRows[1].shown,"missing target data silently fell back to abilities")
win.panel.spellsTab.scripts.OnClick(win.panel.spellsTab)
assert(win.bdRows[1].nameText.text=="Spell133","abilities were not available after switching views")
api.empty=false
now=now+2
win.panel.targetsTab.scripts.OnClick(win.panel.targetsTab)
assert(win.bdRows[1].nameText.text=="Boss" and win.bdRows[1].valueText.text=="1.60K 100%",
    "a temporarily empty enemy view remained cached after native data arrived")
win.panel.scripts.OnClick(win.panel,"LeftButton")
-- A source panel opened from a restricted snapshot must refresh its session
-- when the player asks for targets after that snapshot becomes readable.
api.targetMode=true
api.secret=true
win.session=Session(0)
D.OpenBreakdown(win,2)
assert(win.bd.open and not win.bd.blocked,"own restricted row did not open")
api.secret=false
D.InvalidateTargets()
win.panel.targetsTab.scripts.OnClick(win.panel.targetsTab)
assert(win.bdRows[1].nameText.text=="Boss" and win.bdRows[2].nameText.text=="Add",
    "targets used a secret-bearing combat snapshot after the restriction lifted")
win.panel.scripts.OnClick(win.panel,"LeftButton")
api.targetMode=false
-- Healing uses recipients supplied by the native source details.
api.healTargetMode=true
S.Set("damageMeter","w1Type",3)
targetSources=api.source
Row(win,1).scripts.OnEnter(Row(win,1))
assert(M.tip.title.text=="Tank - "..D.TypeName(2) and M.tip.rows[1].nameText.text=="Spell2061 - Me"
    and M.tip.rows[4].nameText.text=="Me" and M.tip.rows[4].valueText.text:find("1.00K",1,true)
    and M.tip.rows[5].nameText.text=="Healer" and api.source==targetSources+1,
    "healing recipients were not aggregated from one native source read")
Row(win,1).scripts.OnLeave(Row(win,1))
api.secret=true
assert(D.TargetGroups(win,win.session.combatSources[1],Detail(2))==nil,
    "secret healing recipients were aggregated")
api.secret=false
api.healTargetMode=false
S.Set("damageMeter","w1Type",1)
combat=true;Event("PLAYER_REGEN_DISABLED")
Row(win,1).scripts.OnEnter(Row(win,1))
assert(M.tip.message.text=="Targets after combat", "combat target restriction was not explained")
Row(win,1).scripts.OnLeave(Row(win,1))
Row(win,1).scripts.OnClick(Row(win,1),"LeftButton")
assert(win.bd.open and api.lastGUID=="Player-Tank" and win.bdRows[1].nameText.text=="Spell133" and win.bdRows[1].icon.shown,
    "plain data must allow any breakdown in combat")
assert(win.bdRows[1].valueText.text=="600K (6.00K) 67%","breakdown value wrong: "..tostring(win.bdRows[1].valueText.text))
assert(win.bdRows[2].nameText.text=="Spell2136 (Pet)","pet suffix missing")
win.bdRows[1].scripts.OnEnter(win.bdRows[1])
assert(GameTooltip.owner==win.bdRows[1] and GameTooltip.spell==133,"spell tooltip missing")
win.bdRows[1].scripts.OnLeave(win.bdRows[1])
local enemyDetail=Detail(10,99)
D.PaintSpell(win.bdRows[1],enemyDetail.combatSpells[1],enemyDetail,10,"")
assert(win.bdRows[1].nameText.text=="Spell133 - Tank", "enemy spell omitted the attacking unit")
api.secret=true
local secretEnemy=Detail(10,99)
D.PaintSpell(win.bdRows[1],secretEnemy.combatSpells[1],secretEnemy,10,"")
assert(type(win.bdRows[1].nameText.text)=="table" and IsSecret(win.bdRows[1].nameText.text.args[2]),
    "secret attacker name was not passed directly to the text sink")
api.healTargetMode=true
local secretHealing=Detail(2)
D.PaintSpell(win.bdRows[1],secretHealing.combatSpells[1],secretHealing,2,"")
assert(type(win.bdRows[1].nameText.text)=="table" and IsSecret(win.bdRows[1].nameText.text.args[2]),
    "secret healing recipient was not passed directly to the text sink")
api.secret=false
D.PaintSpell(win.bdRows[1],Detail(0).combatSpells[1],Detail(0),0,"")
assert(win.bdRows[1].nameText.text=="Spell133", "recycled row kept an attacker or recipient suffix")
api.healTargetMode=false
D.RefreshBreakdown(win)
combat=false;Event("PLAYER_REGEN_ENABLED")
-- Visibility "Never" without the standalone timer: a combat that starts in
-- Edit Mode must still end, or the options preview is refused afterwards.
local visibility,combatTime=c.visibility,c.combatTime
assert(S.SetMany("damageMeter",{visibility=5,combatTime=false}))
S.SetEditMode(true)
assert(Registered("PLAYER_REGEN_DISABLED"),"Edit Mode windows did not watch combat")
combat=true;Event("PLAYER_REGEN_DISABLED")
assert(M.inCombat and not M.forced,"combat did not end the Edit Mode preview")
combat=false;Event("PLAYER_REGEN_ENABLED")
assert(not M.inCombat,"combat state stuck after Edit Mode combat")
S.SetEditMode(false)
assert(S.DamageMeterPreview(true) and S.DamageMeterPreview(false),"options preview refused after combat")
assert(S.SetMany("damageMeter",{visibility=visibility,combatTime=combatTime}))
-- Snapshot boundaries, native English secret formatting, fill geometry and
-- fractional standalone timer do not depend on Lua-readable combat values.
do
    local nativeFetch=C_DamageMeter.GetCombatSessionFromType
    C_DamageMeter.GetCombatSessionFromType=function(session,kind)
        assert(session==0)
        return {combatSources={{sourceGUID="Player-test",totalAmount=kind+1}}}
    end
    local totals=S.ReadDamageMeterTotals()
    assert(totals.damage["Player-test"]==1 and totals.damageTaken["Player-test"]==8
        and totals.interrupts["Player-test"]==6 and totals.deaths["Player-test"]==10)
    combat=true;assert(S.ReadDamageMeterTotals()==nil);combat=false
    C_DamageMeter.GetCombatSessionFromType=function() return {combatSources={{sourceGUID=Secret("guid"),totalAmount=1}}} end
    assert(S.ReadDamageMeterTotals()==nil,"secret snapshot GUID escaped public boundary")
    C_DamageMeter.GetCombatSessionFromType=nativeFetch
    local configs=0
    CreateAbbreviateConfig=function(points)
        configs=configs+1
        assert(#points==6 and points[1].breakpoint==1e10 and points[6].abbreviation=="K"
            and points[6].abbreviationIsGlobal==false)
        return points
    end
    local formatter=AbbreviateNumbers
    AbbreviateNumbers=function(value,options)
        assert(IsSecret(value) and options.locale=="enUS" and options.config)
        return Secret("english")
    end
    assert(S.Set("damageMeter","englishNumbers",true))
    assert(IsSecret(D.Abbreviate(Secret("amount"))))
    D.ConfigureAbbreviation();assert(configs==1,"native abbreviation config was rebuilt")
    AbbreviateNumbers=formatter
    assert(S.SetMany("damageMeter",{rowBorderMode=3,rowBorderIcon=true,iconBorder=true}))
    local row=D.CreateRow(win.body,win,"tip")
    D.StyleRow(row)
    assert(row.fillBorder.points[1][2]==row.icon and row.fillBorder.points[2][2]==row.bar:GetStatusBarTexture(),
        "filled border lost native texture anchors")
    assert(row.iconBorder.allPoints==row.icon,"separate icon border lost icon geometry")
    assert(S.SetMany("damageMeter",{timer=true,combatTime=true,timerDecimals=true,timerKeep=true,timerBorderSize=2}))
    M.inCombat=false;M.lastDuration=42.7;D.UpdateTimer()
    assert(M.timerFrame.text.text=="0:42.7" and M.timerFrame.edges[1].shown,"timer decimals or border failed")
    -- In a real fight the session duration counts whole seconds (the meter
    -- shows it through SecondsToClock): the tenths come from the combat clock
    -- that PLAYER_REGEN_DISABLED starts, before the lockdown begins.
    api.duration=12
    Event("PLAYER_REGEN_DISABLED");combat=true
    now=now+12.34;RunAfters(.1)
    assert(M.timerFrame.text.text=="0:12.3","in-combat tenths did not follow the combat clock: "..tostring(M.timerFrame.text.text))
    -- A tick reads no settings colors: they are resolved when the timer is styled.
    local rgb,parsed=S.RGB,0
    S.RGB=function(...) parsed=parsed+1;return rgb(...) end
    now=now+.1;RunAfters(.1)
    S.RGB=rgb
    assert(M.timerFrame.text.text=="0:12.4","the 10 Hz timer did not advance the tenths")
    assert(parsed==0,"a timer tick parsed hex colors")
    combat=false;Event("PLAYER_REGEN_ENABLED");RunAfters()
    assert(M.timerFrame.text.text=="0:12.4","the kept duration dropped the combat clock's tenths")
    local historyHidden,historyPushes
    S.SetActionTrackerSessionHidden=function(hidden) historyHidden=hidden;historyPushes=(historyPushes or 0)+1 end
    assert(S.Set("damageMeter","toggleHistory",true))
    assert(S.ToggleDamageMeterViews() and not M.anyShown and not M.timerFrame.shown and historyHidden)
    assert(S.ToggleDamageMeterViews() and historyHidden==false,"session toggle did not restore current rules")
    assert(S.ToggleDamageMeterViews() and historyHidden)
    assert(S.Set("damageMeter","toggleHistory",false) and historyHidden==false,"disabling shared history toggle left history hidden")
    assert(S.Set("damageMeter","toggleHistory",true) and historyHidden)
    -- The tracker repaints on every push: a meter setting that does not
    -- change the answer pushes nothing.
    local pushes=historyPushes
    assert(S.Set("damageMeter","barHeight",19) and S.Set("damageMeter","barHeight",18) and historyPushes==pushes,
        "a meter setting repainted the action tracker")
    assert(S.Set("damageMeter","enabled",false) and historyHidden==false,"disabling meter left history hidden")
    assert(S.Set("damageMeter","enabled",true) and not M.sessionHidden)
    assert(S.SetMany("damageMeter",{timerDecimals=false,rowBorderMode=1,iconBorder=false,englishNumbers=false}))
end
D.OpenTypeMenu(win,win.header)
assert(typePanel.shown and typePanel.events.GLOBAL_MOUSE_DOWN)
assert(S.Set("damageMeter","enabled",false))
assert(not typePanel.shown and not typePanel.events.GLOBAL_MOUSE_DOWN,"module disable must dismiss the tile picker")
-- Retail and WoW Forever always have the APIs, frame methods, GameTooltip and
-- FrameXML tables the meter calls, and no pre-10.0 gradient remains. Text
-- effects (flags, shadow, MSUF's optional font scale helper) come from the
-- shared S.SetStyledFont, so no meter file builds font flags of its own.
for _,file in ipairs(files) do
    local handle=assert(io.open(root.."/MSUF_Suite_DamageMeter/"..file..".lua","rb"))
    local source=handle:read("*a"):gsub("%-%-[^\n]*","")
    handle:close()
    local guarded=source:match("type%(([^)]*)%)%s*[~=]=%s*\"function\"") or source:match("(_G%.GameTooltip)")
        or source:match("if frame%.(Set%w+) then") or source:match("type%((CLASS_ICON_TCOORDS)%)")
        or source:match("type%((_G%.YES)%)") or source:match("(NS%.Client) and")
    assert(not guarded,file..".lua guards "..tostring(guarded).." as if a client lacked it")
    assert(not source:find("SetGradientAlpha",1,true),file..".lua keeps a pre-10.0 gradient fallback")
    assert(not source:find("MSUF_ApplyFontScaleAnimationMode",1,true) and not source:find("\"MONOCHROME\"",1,true),
        file..".lua applies text effects without S.SetStyledFont")
    -- Readable numbers go through the shared S.Finite under its own name.
    assert(not source:find("[^%w_]Plain =") and not source:find("D.Plain",1,true),file..".lua renames S.Finite")
    -- A row update reads M.style once: the percent helper gets the flag passed in.
    local percentBody=source:match("local function Percent%(.-\nend\n")
    assert(file~="Rows" or (percentBody and not percentBody:find("M.style",1,true)),
        "the per-row percent helper re-reads M.style")
end
-- Paints and clock seconds never create timer objects (C_Timer.NewTimer).
assert(#timers==0,"the meter created "..#timers.." timer objects for paints or clock ticks")
-- Each named mode is the position of its label in the setting's choice list.
do
    local rules=S.catalog.damageMeter.rules
    local NAMES={
        {"visibility",Suite.DamageMeterVisibility,{ALWAYS="Always",COMBAT="In combat",GROUP="In a group",
            MOUSEOVER="Mouseover",NEVER="Never"}},
        {"w1Session",Suite.DamageMeterSession,{CURRENT="Current fight",OVERALL="Overall"}},
        {"iconStyle",Suite.DamageMeterIconStyle,{NONE="None",SPEC="Specialization",CLASS="Class"}},
        {"rowBorderMode",Suite.DamageMeterRowBorder,{NONE="None",FULL="Full row",FILLED="Filled portion"}},
        {"outline",Suite.DamageMeterTextStyle,{SHADOW="Shadow",OUTLINE="Outline",THICK="Thick outline",NONE="None",
            OUTLINE_SHADOW="Outline + shadow",THICK_SHADOW="Thick outline + shadow"}},
        {"numberFormat",Suite.DamageMeterValueFormat,{RATE="Per second only",PRIMARY="Primary value only",
            PARENTHESES="Primary (secondary)",BAR="Primary | secondary",CUSTOM="Custom layout"}},
    }
    for _,entry in ipairs(NAMES) do
        local choices,count=rules[entry[1]].choices,0
        for name,label in pairs(entry[3]) do
            assert(choices[entry[2][name]]==label,entry[1].."."..name.." does not name "..label)
            count=count+1
        end
        assert(count==#choices,entry[1].." has a choice without a name")
    end
end
print("Damage meter: tile picker, dormant load, lifecycle, dedupe, event paints, visible clock, secret sinks, damage and healing targets, combat spell unit labels, breakdown rules, movers, window shifting, visibility, preview and plain-value percent passed")
