local root=assert(arg[1],"repository root required")
-- Offline contract for the cooldown manager render plane (Const, Presets, Icons,
-- Time, Effects). Secret values are sentinels that raise on comparison,
-- arithmetic, concatenation, indexing and tostring, and report their WoW
-- type through type(), so an unguarded type check followed by a compare
-- fails here as it would in game. Widgets record every setter call.

------------------------------------------------------------------ secrets
local SecretMT={}
local function Raise(what) return function() error("secret value used: "..what,2) end end
for _,key in ipairs({"__add","__sub","__mul","__div","__mod","__pow","__unm","__concat","__lt","__le","__eq","__call","__len"}) do
    SecretMT[key]=Raise(key)
end
SecretMT.__index=Raise("index");SecretMT.__newindex=Raise("assignment");SecretMT.__tostring=Raise("tostring")
local secretType=setmetatable({},{__mode="k"})
local function IsSecret(value) return getmetatable(value)==SecretMT end
local function Secret(kind) local value=setmetatable({},SecretMT);secretType[value]=kind;return value end
issecretvalue=IsSecret
local rawtype=type
type=function(value) if IsSecret(value) then return secretType[value] end return rawtype(value) end
local SECRET_NUM,SECRET_BOOL,SECRET_COUNT=Secret("number"),Secret("boolean"),Secret("string")
local SECRET_START,SECRET_LENGTH=Secret("number"),Secret("number")

------------------------------------------------------------------ widgets
local writes=0
local Widget={}
Widget.__index=Widget
local all={}
local function New(kind,parent)
    local widget=setmetatable({kind=kind,parent=parent,calls={},last={},scripts={},shown=true,level=(parent and parent.level or 0)+1,w=0,h=0},Widget)
    all[#all+1]=widget
    return widget
end
local function Record(name,apply)
    Widget[name]=function(self,...)
        local a,b,c,d,e=...
        local calls=self.calls
        calls[name]=(calls[name] or 0)+1
        self.last[name]=a
        writes=writes+1
        if apply then apply(self,a,b,c,d,e) end
    end
end
-- The message is built only on failure so the stubs stay allocation-free.
local function Plain(value,what) if IsSecret(value) then error("secret value reached "..what,2) end end
for _,name in ipairs({"SetAllPoints","ClearAllPoints","SetPoint","SetColorTexture","SetHeight","SetWidth",
    "SetJustifyH","SetWordWrap","SetSwipeColor","SetFlipBookRows","SetFlipBookColumns","SetFlipBookFrames",
    "SetFlipBookFrameWidth","SetFlipBookFrameHeight","SetDuration","SetFromAlpha","SetToAlpha","SetLooping","SetOwner",
    "SetItemByID","SetInventoryItem","SetSpellByID","SetDesaturation","SetAlpha"}) do Record(name) end
-- In game a FontString without a font raises on SetText.
Record("SetText",function(self) if self.kind=="FontString" and not self.font then error("SetText before SetFont",3) end end)
-- Sinks documented AllowedWhenUntainted must never see a secret.
for _,name in ipairs({"SetDrawSwipe","SetDrawEdge","SetDrawBling","SetHideCountdownNumbers","SetReverse","SetAtlas",
    "SetDesaturated","SetVertexColor","SetTexture","EnableMouse","EnableMouseMotion"}) do
    Record(name,function(_,a,b,c) Plain(a,name);Plain(b,name);Plain(c,name) end)
end
Record("SetSize",function(self,w,h) Plain(w,"SetSize");self.w,self.h=w,h end)
Record("SetTexCoord",function(self,l,r,t,b) self.tcL,self.tcR,self.tcT,self.tcB=l,r,t,b end)
Record("SetFrameLevel",function(self,level) self.level=level end)
Record("Show",function(self) self.shown=true end)
Record("Hide",function(self) self.shown=false end)
Record("SetShown",function(self,shown) Plain(shown,"SetShown");self.shown=shown and true or false end)
Record("SetScript",function(self,key,fn) self.scripts[key]=fn end)
Record("SetFont",function(self,path,size,flags) Plain(size,"SetFont");self.font=path;self.size=size;self.flags=flags end)
Record("SetShadowColor",function(self,r,g,b,a) self.shadowColor={r,g,b,a} end)
Record("SetShadowOffset",function(self,x,y) self.shadowOffset={x,y} end)
Record("SetTextColor",function(self,r,g,b) self.textColor=r end)
Record("SetCooldownFromDurationObject",function(self,duration) assert(getmetatable(duration)==_G.DurationMT,"not a duration object");self.running=true end)
Record("Clear",function(self) self.running=false end)
Record("SetCountdownFormatter",function(self,formatter) Plain(formatter,"SetCountdownFormatter");self.formatter=formatter end)
Record("Play",function(self) self.playing=true end)
Record("Stop",function(self) self.playing=false end)
function Widget:GetFrameLevel() return self.level end
function Widget:GetWidth() return self.w end
function Widget:GetHeight() return self.h end
function Widget:IsShown() return self.shown end
function Widget:CreateTexture() return New("Texture",self) end
function Widget:CreateFontString() return New("FontString",self) end
function Widget:CreateAnimationGroup() return New("AnimationGroup",self) end
function Widget:CreateAnimation(kind) return New(kind,self) end
function Widget:GetCountdownFontString()
    if not self.countdown then self.countdown=New("FontString",self) end
    return self.countdown
end
local function Calls(widget,name) return widget and widget.calls[name] or 0 end
local frameKinds={}
CreateFrame=function(kind,_,parent,template)
    frameKinds[#frameKinds+1]={kind,template}
    local frame=New(kind,parent)
    frame.template=template
    return frame
end
GameTooltip=New("GameTooltip")
function GameTooltip:IsOwned(frame) return self.last.SetOwner==frame end

------------------------------------------------------------------ durations and curves
DurationMT={}
DurationMT.__index=DurationMT
local now=100
GetTime=function() return now end
local function NewDuration(secret)
    return setmetatable({secret=secret,active=true,start=0,length=0},DurationMT)
end
function DurationMT:HasSecretValues() return self.secret end
function DurationMT:IsActive() if self.secret then return SECRET_BOOL end return self.start+self.length>now end
function DurationMT:EvaluateRemainingDuration(curve)
    assert(curve and curve.points and #curve.points==2,"curve missing")
    if self.secret then return SECRET_NUM end
    return (self.start+self.length>now) and curve.points[2][2] or curve.points[1][2]
end
function DurationMT:SetTimeFromStart(start,length)
    Plain(start,"SetTimeFromStart");Plain(length,"SetTimeFromStart")
    self.start,self.length,self.secret=start,length,false
    self.sets=(self.sets or 0)+1
end
local durations,durationIndex,durationCalls={},0,0
for i=1,64 do durations[i]=NewDuration(true) end
local function NextDuration()
    durationIndex=durationIndex%64+1
    durationCalls=durationCalls+1
    return durations[durationIndex]
end
local createdDurations=0
C_DurationUtil={CreateDuration=function() createdDurations=createdDurations+1;return NewDuration(false) end}
local CurveMT={}
CurveMT.__index=CurveMT
function CurveMT:SetType(kind) self.type=kind end
function CurveMT:AddPoint(x,y) self.points[#self.points+1]={x,y} end
local createdCurves=0
C_CurveUtil={CreateCurve=function() createdCurves=createdCurves+1;return setmetatable({points={}},CurveMT) end}
local FormatterMT={}
FormatterMT.__index=FormatterMT
function FormatterMT:SetBreakpoints(points) self.points=points end
local createdFormatters=0
C_StringUtil={CreateNumericRuleFormatter=function() createdFormatters=createdFormatters+1;return setmetatable({},FormatterMT) end}
Enum={LuaCurveType={Linear=0,Step=1},NumericRuleFormatRounding={Nearest=0,Up=1,Down=2}}

------------------------------------------------------------------ spell and item APIs
local info,charges,usable,noPower,inRange={}, {}, {}, {}, {}
local overlayed={}
local rangeLog={}
local cooldownQueries,countQueries=0,0
local function Info(spell,active,gcd) info[spell]={isActive=active,isOnGCD=gcd,isEnabled=true,startTime=SECRET_START,duration=SECRET_LENGTH,modRate=SECRET_NUM} end
C_Spell={
    GetSpellCooldown=function(spell) Plain(spell,"GetSpellCooldown");cooldownQueries=cooldownQueries+1;return info[spell] end,
    GetSpellCooldownDuration=function(spell,ignoreGCD) Plain(spell,"duration");Plain(ignoreGCD,"duration");return NextDuration() end,
    GetSpellCharges=function(spell) Plain(spell,"charges");return charges[spell] end,
    GetSpellChargeDuration=function(spell) Plain(spell,"charge duration");return NextDuration() end,
    GetSpellDisplayCount=function(spell) Plain(spell,"display count");return SECRET_COUNT end,
    IsSpellUsable=function(spell) Plain(spell,"usable");return usable[spell]~=false,noPower[spell]==true end,
    IsSpellInRange=function(spell) Plain(spell,"range");return inRange[spell] end,
    EnableSpellRangeCheck=function(spell,on) Plain(spell,"range check");Plain(on,"range check");rangeLog[#rangeLog+1]={spell,on} end,
    GetSpellCooldownDurationUnused=nil,
}
C_SpellActivationOverlay={IsSpellOverlayed=function(spell) Plain(spell,"overlay");return overlayed[spell]==true end}
local equip={start=0,length=0,enable=1}
GetInventoryItemCooldown=function(unit,slot) assert(unit=="player" and slot==13);return equip.start,equip.length,equip.enable end
-- Bag contents by item ID; the last GetItemCount flags are kept for the count contract.
local bag,countArgs,itemCd={},{},{}
C_Item={
    GetItemCooldown=function(item)
        Plain(item,"item cooldown")
        local cd=itemCd[item]
        if cd then return cd[1],cd[2],cd[3] end
        return 0,0,true
    end,
    GetItemCount=function(item,bank,uses)
        Plain(item,"item count");countQueries=countQueries+1
        countArgs.bank,countArgs.uses=bank,uses
        return bag[item] or 0
    end,
    IsUsableItem=function(item) return true,false end,
}
RAID_CLASS_COLORS={MAGE={r=.25,g=.78,b=.92}}
UnitClass=function() return "Mage","MAGE" end

------------------------------------------------------------------ core catalog (moduleAddons patched locally)
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",IsRetail=true,SupportsEvent=function() return true end}}
WOW_PROJECT_ID,WOW_PROJECT_MAINLINE=1,1
C_CooldownViewer={GetCooldownViewerCategorySet=function() return {} end,GetCooldownViewerCooldownInfo=function() end}
MSUF_EncodeCompactTable=function() return "" end
MSUF_TryDecodeCompactString=function() return nil end
local NS={}
for _,file in ipairs({"Core/Platform.lua","Core/Database.lua","Core/SuiteCatalog.lua"}) do
    assert(loadfile(root.."/MSUF_Suite/"..file))("MSUF_Suite",NS)
end
do
    local B=NS.CatalogBuild
    local original=B.Module
    B.Module=function(id,spec)
        if id~="cooldownManager" then return original(id,spec) end
        spec.id,spec.addon,spec.controls,spec.rules,spec.conflicts=id,"MSUF_Suite_CooldownManager",{},{},spec.conflicts or {}
        NS.SuiteCatalog[id],NS.SuiteOrder[#NS.SuiteOrder+1]=spec,id
        B.Add(id,B.Bool("enabled","Enable module",false))
        return spec
    end
end
assert(loadfile(root.."/MSUF_Suite/Core/Catalog/CooldownManager.lua"))("MSUF_Suite",NS)
local S={}
NS.Suite=S
MSUFSuite=NS
assert(loadfile(root.."/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules",{})
S.Public=function(value) return not IsSecret(value) end

------------------------------------------------------------------ bootstrap stub and render files
local C={M={},EMPTY={},views={},plans={},bars={},entries={},state={
    px=1,font="Fonts\\TEST.TTF",fontFlags="OUTLINE",cdR=1,cdG=1,cdB=1,stackR=1,stackG=1,stackB=1,keyR=1,keyG=1,keyB=1,
    threshold=0,thR=1,thG=90/255,thB=60/255,showGCD=false,readyGlowCombat=true,inCombat=false,preview=false}}
local P={NS=NS,Suite=S,CDM=C}
local FILES={"Const.lua","Presets.lua","Icons.lua","Time.lua","Effects.lua"}
-- Presets.lua is plain data plus one class lookup: it needs only the CDM table.
local HEADERS={["Presets.lua"]="^local _,P=%.%.%.\nlocal C=P%.CDM\n"}
for _,file in ipairs(FILES) do
    local path=root.."/MSUF_Suite_CooldownManager/"..file
    local handle=assert(io.open(path,"rb"))
    local text=handle:read("*a"):gsub("\r","")
    handle:close()
    assert(text:find(HEADERS[file] or "^local _,P=%.%.%.\nlocal NS,S=P%.NS,P%.Suite\nlocal C=P%.CDM\n"),file.." must start with the runtime header")
    for _,banned in ipairs({"pcall","loadstring","setfenv","OnUpdate","hooksecurefunc","NewTicker","Claude","Anthropic"}) do
        assert(not text:find(banned,1,true),file.." uses banned "..banned)
    end
    assert(loadfile(path))("MSUF_Suite_CooldownManager",P)
end
local K,I,T,E,Presets=C.Const,C.Icons,C.Time,C.Effects,C.Presets
assert(K and I and T and E and Presets,"render tables missing")
local requests,ready={},{}
C.Layout={Request=function(slot) requests[slot]=(requests[slot] or 0)+1 end,PixelScale=function() return 1 end}
C.Alerts={Ready=function(entry) ready[entry.key]=(ready[entry.key] or 0)+1 end}

------------------------------------------------------------------ Const
assert(K.GCD_CATEGORY==133 and #K.POINTS==9 and K.POINTS[9]=="BOTTOMRIGHT")
assert(K.CATEGORY_ICONS[4] and K.CATEGORY_ICONS[30] and K.CATEGORY_ICONS[1711] and K.CATEGORY_ICONS[2566])
-- Every hardcoded category icon has the bag items its count sums.
for category in pairs(K.CATEGORY_ICONS) do
    local items=Presets.CATEGORY_ITEMS[category]
    assert(type(items)=="table" and #items>0,"category "..category.." needs its bag items")
    for i=1,#items do assert(type(items[i])=="number" and items[i]>0 and math.floor(items[i])==items[i]) end
end
do
    local desat=K.DesatCurve()
    assert(desat.type==1 and desat.points[1][1]==0 and desat.points[1][2]==0 and desat.points[2][1]==.001 and desat.points[2][2]==1)
    assert(K.DesatCurve()==desat,"desat curve must be shared")
    local alpha=K.StepCurve(100,40)
    assert(alpha.points[1][2]==1 and alpha.points[2][2]==.4 and K.StepCurve(100,40)==alpha and K.StepCurve(100,50)~=alpha)
    local texture=New("Texture")
    local group=K.FlipBook(texture,K.GLOW[1])
    local flip=group.flip
    assert(group.last.SetLooping=="REPEAT" and flip.last.SetFlipBookRows==6 and flip.last.SetFlipBookColumns==5
        and flip.last.SetFlipBookFrames==30 and flip.last.SetDuration==1,"flipbook parameters")
    assert(K.GLOW[1].atlas=="UI-HUD-ActionBar-Proc-Loop-Flipbook" and K.GLOW[1].scale==1.4)
    assert(K.GLOW[2].atlas=="rotationhelper_ants_flipbook" and K.GLOW[2].scale==1.2 and K.GLOW[3].pulse==.6)
    C.state.px=768/1440
    local snapped=K.Snap(10)
    assert(math.abs(snapped/C.state.px-math.floor(snapped/C.state.px+.5))<1e-9,"snap must land on whole pixels")
    assert(math.abs(K.Pixels(2)-2*C.state.px)<1e-12)
    C.state.px=1
end

------------------------------------------------------------------ fixtures
local rules=NS.SuiteCatalog.cooldownManager.rules
local function View(slot,index)
    local view={key=slot,index=index,kind=1,builtin=true,title=slot,styleGen=1,layoutGen=1,behaviorGen=1}
    for suffix,key in pairs(NS.CDM.KEYS[slot]) do view[suffix]=rules[key].default end
    view.borderR,view.borderG,view.borderB=S.RGB(view.borderColor)
    view.glowR,view.glowG,view.glowB=S.RGB(view.glowColor)
    view.rangeR,view.rangeG,view.rangeB=S.RGB(view.rangeColor)
    return view
end
local ess,uti=View("ess",1),View("uti",2)
C.views.ess,C.views.uti=ess,uti
assert(ess.size==40 and ess.height==90 and ess.perRow==9 and ess.gap==2 and ess.anchor==1 and ess.keybind==false
    and ess.cdText==true and ess.range==true and ess.charges==true and ess.stackPos==9,"catalog defaults changed")
assert(uti.size==32 and uti.height==90 and uti.perRow==12 and uti.gap==2 and uti.anchor==2 and uti.side==1,"utility defaults changed")
-- Built-in cooldown icons are 10:9, snapped to whole pixels.
do
    local function Footprint(slot) return K.IconSize(View(slot,NS.CDM.SLOT_INDEX[slot])) end
    local w,h=Footprint("ess");assert(w==40 and h==36)
    w,h=Footprint("uti");assert(w==32 and h==29)
    w,h=Footprint("def");assert(w==32 and h==29)
    w,h=Footprint("ext");assert(w==28 and h==25)
end
C.bars.ess={frame=CreateFrame("Frame",nil,nil)}
C.bars.uti={frame=CreateFrame("Frame",nil,nil)}
local function Entry(key,slot,fields)
    local entry={key=key,src=key:sub(1,1),id=tonumber(key:sub(2)),family=1,linked=C.EMPTY,ov=C.EMPTY,slot=slot,known=true}
    for field,value in pairs(fields) do entry[field]=value end
    C.entries[key]=entry
    return entry
end
local b1=Entry("b1","ess",{spell=100,base=100,hasRange=true,texture=1001,charges=false})
local b2=Entry("b2","ess",{spell=200,base=200,texture=1002,charges=true})
local b3=Entry("b3","ess",{spell=300,base=300,hasRange=true,texture=1003})
local b4=Entry("b4","ess",{spellCategory=4,texture=K.CATEGORY_ICONS[4]})
local e13=Entry("e13","ess",{equipSlot=13,texture=1013})
local s300=Entry("s300","uti",{spell=300,base=300,hasRange=true,texture=1003})
local b6=Entry("b6","uti",{spell=600,base=600,texture=1006,charges=false})
Info(100,false,false);Info(200,false,false);Info(300,false,false);Info(600,false,false);Info(400,false,false)
C.plans.ess={slot="ess",kind=1,entries={b1,b2,b3,b4,e13}}
C.plans.uti={slot="uti",kind=1,entries={s300,b6}}

------------------------------------------------------------------ Icons: pools, styling, memoization
I.Sync("ess");I.Sync("uti")
assert(I.Count("ess")==5 and I.Count("uti")==2)
for _,entry in ipairs(C.plans.ess.entries) do
    local icon=entry.icon
    assert(icon and icon.entry==entry and icon.parent==C.bars.ess.frame,"icon must be pooled under its bar frame")
    assert(icon.cd.template=="CooldownFrameTemplate" and icon.cd.scripts.OnCooldownDone,"swipe needs OnCooldownDone")
    assert(icon.tex.last.SetTexture==entry.texture,"texture")
    assert(icon.w==40 and icon.h==36 and Calls(icon,"SetSize")==1)
    -- Wider than tall: the art is cropped top and bottom to keep its aspect.
    local tex=icon.tex
    assert(math.abs(tex.tcL-.04)<1e-9 and math.abs(tex.tcR-.96)<1e-9 and tex.tcT>.04 and tex.tcB<.96,"10:9 crop")
    assert(math.abs((tex.tcB-tex.tcT)/(tex.tcR-tex.tcL)-34/38)<1e-9,"texture aspect must match the inner rect")
    local countdown=icon.cd.countdown
    assert(countdown.font=="Fonts\\TEST.TTF" and countdown.size==math.max(10,math.floor(36*.38)) and countdown.flags=="OUTLINE",
        "countdown size follows the icon height")
    assert(icon.cd.last.SetHideCountdownNumbers==false,"countdown shown when cdText is on")
    assert(Calls(icon,"EnableMouseMotion")==0 and not icon.mouse,"no mouse without tooltips")
    assert(icon.count.last.SetPoint=="BOTTOMRIGHT")
end
assert(b2.icon.chargeCd and not b1.icon.chargeCd,"recharge edge only for charge entries")
assert(b2.icon.chargeCd.last.SetDrawSwipe==false and b2.icon.chargeCd.last.SetDrawEdge==true)
do
    local before=writes
    I.Sync("ess");I.Sync("uti");I.Style("ess")
    assert(writes==before,"unchanged sync must not write: "..(writes-before))
    ess.styleGen=2
    I.Sync("ess")
    assert(Calls(b1.icon,"SetSize")==2 and Calls(s300.icon,"SetSize")==1,"style only on the bar whose generation moved")
    before=writes
    I.Style("ess")
    assert(writes==before,"style pass without generation change must not write")
end
-- Tooltips: mouse motion only while enabled; hidden bars show none.
do
    ess.tooltips=true
    I.Style("ess")
    assert(Calls(b1.icon,"EnableMouseMotion")==1 and b1.icon.last.EnableMouseMotion==true)
    I.Style("ess")
    assert(Calls(b1.icon,"EnableMouseMotion")==1,"mouse state memoized")
    b1.icon.scripts.OnEnter(b1.icon)
    assert(GameTooltip.last.SetSpellByID==100 and Calls(GameTooltip,"SetSpellByID")==1)
    e13.icon.scripts.OnEnter(e13.icon)
    assert(GameTooltip.last.SetInventoryItem=="player")
    C.bars.ess.hidden=true
    local before=Calls(GameTooltip,"SetOwner")
    b1.icon.scripts.OnEnter(b1.icon)
    assert(Calls(GameTooltip,"SetOwner")==before,"hidden bar must not show tooltips")
    -- A hidden bar is only transparent: its icons give up mouse motion, and
    -- syncs and restyles while it stays hidden keep them off without writes.
    I.SetBarMouse("ess",false)
    for _,entry in ipairs(C.plans.ess.entries) do
        assert(entry.icon.mouse==false and entry.icon.last.EnableMouseMotion==false,"hidden bar icons must drop the mouse")
    end
    local quiet=writes
    I.SetBarMouse("ess",false);I.Style("ess");I.Sync("ess")
    assert(writes==quiet,"a hidden bar keeps its icons mouse-free without writes")
    C.bars.ess.hidden=nil
    I.SetBarMouse("ess",true)
    assert(b1.icon.mouse==true and b1.icon.last.EnableMouseMotion==true and s300.icon.mouse==false,"shown again: tooltips take the mouse back")
    quiet=writes
    I.SetBarMouse("ess",true);I.Style("ess")
    assert(writes==quiet,"bar mouse memoized")
    I.SetBarMouse("nope",true)
    ess.tooltips=false
    I.Style("ess")
    assert(b1.icon.last.EnableMouseMotion==false)
    b1.icon.scripts.OnEnter(b1.icon)
    assert(Calls(GameTooltip,"SetOwner")==before,"tooltips off")
end
-- Threshold formatter: shared per signature, nil when off.
do
    C.state.threshold=3
    ess.styleGen=3;uti.styleGen=2
    I.Sync("ess");I.Sync("uti")
    local formatter=b1.icon.cd.formatter
    assert(formatter and b2.icon.cd.formatter==formatter and s300.icon.cd.formatter==formatter and createdFormatters==1)
    local points=formatter.points
    assert(points[1].threshold==0 and points[1].format=="|cffff5a3c%.0f|r" and points[1].rounding==1)
    assert(points[2].threshold==3 and points[2].format=="%.0f" and points[2].rounding==1)
    assert(points[3].threshold==60 and points[3].format=="%d:%02d" and points[3].components[1].div==60 and points[3].components[2].mod==60)
    assert(points[4].threshold==3600 and points[4].format=="%dh" and points[4].components[1].div==3600)
    local calls=Calls(b1.icon.cd,"SetCountdownFormatter")
    I.Sync("ess")
    assert(Calls(b1.icon.cd,"SetCountdownFormatter")==calls,"formatter memoized")
    C.state.threshold=0
    ess.styleGen=4;uti.styleGen=3
    I.Sync("ess");I.Sync("uti")
    assert(b1.icon.cd.formatter==nil and Calls(b1.icon.cd,"SetCountdownFormatter")==calls+1)
end
-- Keybind text is lazy and follows the entry to a new icon; keybinds are off by default.
do
    assert(not b1.icon.keyText)
    I.SetKeybind(b1,"S1")
    local key=b1.icon.keyText
    assert(key and key.last.SetText=="S1" and key.font and key.last.SetPoint=="TOPRIGHT" and key.shown==false)
    I.SetKeybind(b1,"S1")
    assert(Calls(key,"SetText")==1,"keybind text memoized")
    ess.keybind=true;ess.styleGen=5
    I.Sync("ess")
    assert(key.shown==true and Calls(key,"SetText")==1,"turning keybinds on shows the text")
    ess.keybind=false;ess.styleGen=6
    I.Sync("ess")
    assert(key.shown==false)
end
-- A released icon takes its aura overlay (at once, combat too) and its
-- layout memo with it: a rebound icon never shows the old aura and is
-- placed and reported again.
do
    local overlays,forgot={},{}
    C.Auras={OverlayShown=function(entry,on,icon) overlays[#overlays+1]={entry,on,icon} end}
    C.Layout.Forget=function(icon) forgot[#forgot+1]=icon end
    local icon=b6.icon
    C.plans.uti.entries={s300}
    I.Sync("uti")
    assert(#overlays==1 and overlays[1][1]==b6 and overlays[1][2]==false and overlays[1][3]==icon,
        "a released icon must switch its aura overlay off")
    assert(#forgot==1 and forgot[1]==icon and b6.icon==nil,"a released icon must drop its layout memo")
    C.plans.uti.entries={s300,b6}
    I.Sync("uti")
    assert(b6.icon and #overlays==1 and #forgot==1,"binding does not release")
    C.Auras,C.Layout.Forget=nil,nil
end

------------------------------------------------------------------ Time: secret sinks and isolation
T.RefreshAll()
assert(b1.cooling==false and b1.hidden==false and not b1.icon.cd.running)
local function Snapshot(entry) local icon=entry.icon;return Calls(icon.cd,"SetCooldownFromDurationObject")+Calls(icon.cd,"Clear")+Calls(icon.tex,"SetDesaturation")+Calls(icon,"SetAlpha")+Calls(icon.count,"SetText") end
do
    local other=Snapshot(b2)+Snapshot(b3)+Snapshot(s300)
    Info(100,true,false)
    local changed=T.Refresh(b1,"cooldown")
    assert(changed==false and b1.cooling==true and b1.coolStart==100)
    assert(b1.icon.cd.running and b1.icon.tex.last.SetDesaturation==SECRET_NUM,"desaturation must come from the C-side curve")
    assert(b1.icon.count.last.SetText==SECRET_COUNT,"display count goes straight to SetText")
    assert(Snapshot(b2)+Snapshot(b3)+Snapshot(s300)==other,"other entries must not be written")
end
-- Opacity curve per spell choice; the secret result feeds SetAlpha.
do
    b6.ov={cdAlpha=40,readyAlpha=100}
    Info(600,true,false)
    T.Refresh(b6,"cooldown")
    assert(b6.icon.last.SetAlpha==SECRET_NUM,"cooldown opacity must come from the curve")
    Info(600,false,false)
    T.Refresh(b6,"cooldown")
    assert(b6.icon.last.SetAlpha==1 and b6.icon.tex.last.SetDesaturation==0)
    local calls=Calls(b6.icon,"SetAlpha")
    T.Refresh(b6,"cooldown")
    assert(Calls(b6.icon,"SetAlpha")==calls,"ready opacity memoized")
end
-- GCD on display: the swipe runs but no ready alert or cooling follows.
do
    Info(200,true,true)
    charges[200]={maxCharges=2,isActive=false,currentCharges=Secret("number"),cooldownStartTime=SECRET_START}
    T.Refresh(b2,"cooldown")
    assert(b2.cooling==false)
    Info(200,false,false)
    b2.icon.cd.scripts.OnCooldownDone(b2.icon.cd)
    assert(not ready.b2,"a GCD must not raise a ready alert")
end
-- Real cooldown: one ready alert on the OnCooldownDone edge.
do
    now=110
    Info(100,false,false)
    b1.icon.cd.scripts.OnCooldownDone(b1.icon.cd)
    assert(ready.b1==1 and b1.cooling==false and b1.coolStart==nil)
    b1.icon.cd.scripts.OnCooldownDone(b1.icon.cd)
    assert(ready.b1==1,"ready alert exactly once")
    -- Under two seconds: no alert.
    Info(100,true,false)
    T.Refresh(b1,"cooldown")
    now=111.5
    Info(100,false,false)
    b1.icon.cd.scripts.OnCooldownDone(b1.icon.cd)
    assert(ready.b1==1 and b1.cooling==false,"short cooldowns stay silent")
end
-- A real cooldown that ends inside another spell's GCD (showGCD off): the
-- GCD-free swipe ran out, so the entry is ready although isActive still
-- reports the GCD and the GCD-free duration is secret. Nothing is queried
-- for the main cooldown.
do
    Info(100,true,false)
    T.Refresh(b1,"cooldown")
    assert(b1.cooling==true and b1.icon.cdReal==true,"the swipe holds the GCD-free duration")
    now=120
    Info(100,true,true)
    local queries,alerts=cooldownQueries,ready.b1
    b1.icon.cd.scripts.OnCooldownDone(b1.icon.cd)
    assert(b1.cooling==false and ready.b1==alerts+1,"a cooldown ending inside a GCD must be ready")
    assert(cooldownQueries==queries,"an expired swipe must not query the main cooldown")
    assert(not b1.icon.cd.running and b1.icon.tex.last.SetDesaturation==0 and b1.icon.cdReal==nil)
    -- Showing the GCD: the swipe's end can be a GCD end, so the state is read.
    C.state.showGCD=true
    Info(100,true,false)
    T.Refresh(b1,"cooldown")
    assert(b1.cooling==true and b1.icon.cdReal==false)
    now=130
    Info(100,false,false)
    queries=cooldownQueries
    b1.icon.cd.scripts.OnCooldownDone(b1.icon.cd)
    assert(b1.cooling==false and cooldownQueries==queries+1)
    C.state.showGCD=false
end
-- Charge spells: cooling holds until every charge is back.
do
    Info(200,true,false)
    charges[200].isActive=true
    T.Refresh(b2,"cooldown")
    assert(b2.cooling and b2.icon.chargeCd.running,"recharge edge runs while recharging")
    now=145
    Info(200,false,false)
    T.Refresh(b2,"charges")
    assert(b2.cooling==true and not ready.b2,"one charge back is not ready yet")
    charges[200].isActive=false
    b2.icon.cd.scripts.OnCooldownDone(b2.icon.cd)
    assert(b2.cooling==false and ready.b2==1 and not b2.icon.chargeCd.running)
    -- The last charge returns inside a GCD: the recharge edge ends, the main
    -- cooldown only shows the GCD (secret GCD-free duration), and the plain
    -- charge isActive=false settles it.
    Info(200,true,false)
    charges[200].isActive=true
    T.Refresh(b2,"cooldown")
    assert(b2.cooling==true)
    Info(200,true,true)
    T.Refresh(b2,"charges")
    assert(b2.cooling==true,"a recharging spell stays cooling")
    now=150
    charges[200].isActive=false
    b2.icon.chargeCd.scripts.OnCooldownDone(b2.icon.chargeCd)
    assert(b2.cooling==false and ready.b2==2,"every charge back inside a GCD must be ready")
    Info(200,false,false)
end
-- SPELL_UPDATE_CHARGES ("recharge", no payload): while a charge is
-- available the main swipe is clear, so only the recharge swipe and the
-- count are read and the main state holds; a main swipe that shows (no
-- charge left) is read in full.
do
    charges[200].isActive=false
    T.Refresh(b2,"cooldown")
    assert(b2.cooling==false and not b2.icon.cdSet,"a charge available: the main swipe is clear")
    charges[200].isActive=true
    local queries,durationsBefore,counts=cooldownQueries,durationCalls,Calls(b2.icon.count,"SetText")
    local mainWrites=Calls(b2.icon.cd,"SetCooldownFromDurationObject")+Calls(b2.icon.cd,"Clear")
    T.Refresh(b2,"recharge")
    assert(cooldownQueries==queries and durationCalls==durationsBefore+1,"recharge read the main cooldown")
    assert(b2.icon.chargeCd.running and Calls(b2.icon.count,"SetText")==counts+1,"recharge swipe and count follow")
    assert(Calls(b2.icon.cd,"SetCooldownFromDurationObject")+Calls(b2.icon.cd,"Clear")==mainWrites,"the main swipe is untouched")
    assert(b2.cooling==false,"a spent charge with one left is not cooling")
    -- No charge left: the main swipe shows and is read in full.
    Info(200,true,false)
    T.Refresh(b2,"cooldown")
    assert(b2.cooling==true and b2.icon.cdSet==true)
    queries=cooldownQueries
    T.Refresh(b2,"recharge")
    assert(cooldownQueries==queries+1 and b2.cooling==true,"a showing main swipe is read in full")
    -- The main swipe ran out (a charge is back): cooling holds while
    -- recharging, and the last charge back settles it without a main query.
    Info(200,false,false)
    b2.icon.cd.scripts.OnCooldownDone(b2.icon.cd)
    assert(b2.cooling==true and not b2.icon.cdSet,"one charge back is not ready yet")
    local alerts=ready.b2 or 0
    charges[200].isActive=false
    queries=cooldownQueries
    now=now+10
    T.Refresh(b2,"recharge")
    assert(cooldownQueries==queries and b2.cooling==false and ready.b2==alerts+1,"every charge back is ready")
    assert(not b2.icon.chargeCd.running,"the recharge swipe clears")
end
-- Outside SPELL_UPDATE_COOLDOWN, isOnGCD is ignored when a plain probe exists or state is known.
do
    Info(300,true,true)
    T.Refresh(b3,"full")
    assert(b3.cooling==false,"unknown state falls back to isOnGCD")
    Info(300,true,false)
    T.Refresh(b3,"charges")
    assert(b3.cooling==false,"secret duration keeps the last known state")
    Info(300,false,false)
    T.Refresh(b3,"cooldown")
end
-- hideReady: the ready edge hides the entry and requests one relayout; never in preview.
do
    b3.ov={hideReady=true}
    Info(300,true,false)
    assert(T.Refresh(b3,"cooldown")==false and b3.hidden==false)
    now=160
    Info(300,false,false)
    requests.ess=nil
    b3.icon.cd.scripts.OnCooldownDone(b3.icon.cd)
    assert(b3.hidden==true and requests.ess==1,"ready edge with hideReady relayouts its bar once")
    C.state.preview=true
    assert(T.Refresh(b3,"full")==true and b3.hidden==false,"preview never hides")
    C.state.preview=false
    assert(T.Refresh(b3,"full")==true and b3.hidden==true)
    b3.ov=C.EMPTY
    T.Refresh(b3,"full")
end
-- Category entries: nothing known clears; a known source spell is a spell entry.
do
    T.Refresh(b4,"cooldown")
    assert(not b4.icon.cd.running and b4.cooling==false)
    b4.catSpell=400
    Info(400,true,false)
    T.Refresh(b4,"cooldown")
    assert(b4.icon.cd.running and b4.cooling==true)
    Info(400,false,false)
    T.Refresh(b4,"cooldown")
end
-- Category counts: the bag count of every rank behind the category
-- (Presets.CATEGORY_ITEMS) summed, uses included; secret counts are skipped;
-- cleared at zero and while charges are off.
do
    local items=Presets.CATEGORY_ITEMS[4]
    local count=b4.icon.count
    assert(#items>=3 and count.last.SetText=="" and b4.icon.countOff==true,"an empty bag shows no count")
    b4.catSpell=nil
    bag[items[1]],bag[items[2]],bag[items[3]]=2,1,Secret("number")
    bag[Presets.CATEGORY_ITEMS[30][1]]=7
    T.Refresh(b4,"item")
    assert(count.last.SetText=="","bag totals are cached until the bags change")
    T.BagsChanged()
    local queries=countQueries
    T.Refresh(b4,"item")
    assert(count.last.SetText==3 and b4.icon.countOff==false,"summed ranks; secret counts and other categories stay out")
    assert(countQueries==queries+#items,"one count per rank after a bag change")
    assert(countArgs.bank==false and countArgs.uses==true,"bag counts include uses, not the bank")
    local quiet=writes
    T.Refresh(b4,"item");T.Refresh(b4,"cooldown");T.Refresh(b4,"full")
    assert(count.last.SetText==3 and b4.icon.lastCount==3,"an unchanged count stays")
    assert(writes==quiet and countQueries==queries+#items,"unchanged bags: no recount and no writes")
    bag[items[1]]=4
    T.BagsChanged()
    T.Refresh(b4,"item")
    assert(count.last.SetText==5)
    ess.charges=false
    T.Refresh(b4,"item")
    assert(count.last.SetText=="" and b4.icon.countOff==true,"charges off clears the count")
    ess.charges=true
    T.Refresh(b4,"item")
    assert(count.last.SetText==5,"charges on shows it again")
    bag[items[1]],bag[items[2]],bag[items[3]]=0,nil,nil
    T.BagsChanged()
    T.Refresh(b4,"item")
    assert(count.last.SetText=="" and b4.icon.countOff==true,"zero clears the count")
    -- With a known source spell the bag total still owns the count text:
    -- the spell's display count must not replace it on a later refresh.
    bag[items[1]]=2
    T.BagsChanged()
    b4.catSpell=400
    Info(400,true,false)
    T.Refresh(b4,"cooldown")
    assert(b4.icon.cd.running and count.last.SetText==2)
    T.Refresh(b4,"cooldown")
    assert(count.last.SetText==2,"the source spell's display count replaced the bag count")
    -- Bag events never re-read the category's cooldown (it arrives with
    -- SPELL_UPDATE_COOLDOWN): no query, no write, the state holds.
    queries,quiet=cooldownQueries,writes
    T.Refresh(b4,"item");T.Refresh(b4,"item")
    assert(cooldownQueries==queries and writes==quiet and b4.cooling==true and b4.icon.cd.running,
        "a bag event re-read a category cooldown")
    Info(400,false,false)
    T.Refresh(b4,"cooldown")
    assert(count.last.SetText==2 and b4.cooling==false)
    bag[items[1]],bag[Presets.CATEGORY_ITEMS[30][1]]=nil,nil
    T.BagsChanged()
    T.Refresh(b4,"item")
    assert(count.last.SetText=="")
end
-- Equipment: plain numbers feed one reused duration object; secrets clear.
do
    local created=createdDurations
    equip.start,equip.length,equip.enable=150,120,1
    T.Refresh(e13,"item")
    assert(createdDurations==created+1 and e13.icon.itemDur.sets==1 and e13.icon.cd.running and e13.cooling==true)
    -- A repeated BAG_UPDATE_COOLDOWN with the same cooldown writes nothing.
    local quiet=writes
    T.Refresh(e13,"item");T.Refresh(e13,"item");T.Refresh(e13,"full")
    assert(e13.icon.itemDur.sets==1 and writes==quiet,"an unchanged item cooldown was written again: "..(writes-quiet))
    -- A new cooldown reuses the duration object.
    equip.start=160
    T.Refresh(e13,"item")
    assert(createdDurations==created+1 and e13.icon.itemDur.sets==2 and e13.icon.itemDur.start==160,"item duration must be reused")
    -- The swipe's end retires the cooldown even while the API still reports
    -- it; later bag events with the same values stay quiet.
    now=280
    local alerts=ready.e13 or 0
    e13.icon.cd.scripts.OnCooldownDone(e13.icon.cd)
    assert(e13.cooling==false and not e13.icon.cd.running and ready.e13==alerts+1,"an item swipe's end is its ready edge")
    quiet=writes
    T.Refresh(e13,"item");T.Refresh(e13,"full")
    assert(writes==quiet and e13.cooling==false and e13.icon.itemDur.sets==2,"a finished item cooldown stays finished")
    -- A cooldown already over when first read never arms.
    equip.start=10
    T.Refresh(e13,"item")
    assert(e13.cooling==false and not e13.icon.cd.running and e13.icon.itemDur.sets==2)
    equip.start=Secret("number")
    T.Refresh(e13,"item")
    assert(not e13.icon.cd.running,"secret item values clear the swipe")
    equip.start,equip.length=0,0
    T.Refresh(e13,"item")
    assert(e13.cooling==false)
end
-- Bag items: the count waits for the bag change; a new cooldown (the item
-- was used) reads the item's own count again.
do
    local entry=Entry("i9002","uti",{itemID=9002,texture=1902})
    table.insert(C.plans.uti.entries,entry)
    bag[9002]=3
    I.Sync("uti")
    local icon=entry.icon
    assert(icon.count.last.SetText==3 and entry.cooling==false and not icon.cd.running)
    bag[9002]=2
    local queries=countQueries
    T.Refresh(entry,"item")
    assert(icon.count.last.SetText==3 and countQueries==queries,"item counts wait for the bag change")
    itemCd[9002]={now,30,1}
    T.Refresh(entry,"item")
    assert(entry.cooling==true and icon.cd.running and icon.count.last.SetText==2 and countQueries==queries+1,
        "a use reads the item's count again")
    local quiet=writes
    T.Refresh(entry,"item")
    assert(writes==quiet and countQueries==queries+1,"a repeated bag event on a cooling item wrote or counted")
    itemCd[9002],bag[9002]=nil,nil
    table.remove(C.plans.uti.entries)
    I.Sync("uti")
    assert(not entry.icon)
end
-- Several count icons bound in one pass recount the bags once.
do
    local p1=Entry("b8","uti",{spellCategory=4,texture=K.CATEGORY_ICONS[4]})
    local p2=Entry("b9","uti",{spellCategory=4,texture=K.CATEGORY_ICONS[4]})
    table.insert(C.plans.uti.entries,p1)
    table.insert(C.plans.uti.entries,p2)
    local queries=countQueries
    I.Sync("uti")
    assert(countQueries==queries+#Presets.CATEGORY_ITEMS[4],"one recount per pass, not per icon: "..(countQueries-queries))
    table.remove(C.plans.uti.entries)
    table.remove(C.plans.uti.entries)
    I.Sync("uti")
    assert(not p1.icon and not p2.icon)
end
-- Healthstones (hideEmpty, from Resolve): the Healthstone item and
-- Blizzard's healthstone category leave their bar while the bags hold none,
-- counts on or off; the refresh reports the flip so the caller relayouts
-- once. Previews show them; potion categories (no hideEmpty) never hide.
local stone,stoneCat
do
    stone=Entry("i5512","uti",{itemID=5512,texture=538745,hideEmpty=true})
    stoneCat=Entry("b10","uti",{spellCategory=1711,texture=K.CATEGORY_ICONS[1711],hideEmpty=true})
    table.insert(C.plans.uti.entries,stone)
    table.insert(C.plans.uti.entries,stoneCat)
    bag[5512]=nil
    I.Sync("uti")
    assert(stone.hidden==true and stone.empty==true and stoneCat.hidden==true and stoneCat.empty==true,"empty healthstones hide")
    assert(stone.icon.countOff==true and stoneCat.icon.countOff==true,"no count while empty")
    bag[5512]=2
    T.BagsChanged()
    assert(T.Refresh(stone,"item")==true and stone.hidden==false and stone.empty==false,"a stone in the bags shows the item")
    assert(T.Refresh(stoneCat,"item")==true and stoneCat.hidden==false and stoneCat.icon.count.last.SetText==2,
        "and the category, with its count")
    assert(stone.icon.count.last.SetText==2)
    assert(T.Refresh(stone,"item")==false and T.Refresh(stoneCat,"full")==false,"no flip, no relayout")
    bag[5512]=1
    T.BagsChanged()
    assert(T.Refresh(stone,"item")==false and stone.hidden==false and stone.icon.countOff==true,"one stone shows without a count")
    -- Counts off: the bags are still read for the hide rule, no count shows.
    uti.charges=false
    bag[5512]=nil
    T.BagsChanged()
    assert(T.Refresh(stone,"item")==true and stone.hidden==true,"counts off still hide an empty stone")
    assert(T.Refresh(stoneCat,"item")==true and stoneCat.hidden==true and stoneCat.icon.countOff==true)
    bag[5512]=2
    T.BagsChanged()
    assert(T.Refresh(stoneCat,"item")==true and stoneCat.hidden==false and stoneCat.icon.countOff==true,"shown, no count")
    uti.charges=true
    T.Refresh(stoneCat,"item")
    bag[5512]=nil
    T.BagsChanged()
    C.state.preview=true
    assert(T.Refresh(stone,"full")==true and stone.hidden==false and stone.empty==true,"previews show empty stones")
    C.state.preview=false
    assert(T.Refresh(stone,"full")==true and stone.hidden==true)
    -- A flip without a cooling edge re-evaluates the ready glow as well.
    stone.ov={readyGlow=true}
    C.state.inCombat=true
    T.Refresh(stone,"full")
    assert(stone.hidden==true and not stone.icon.gReady,"no ready glow while empty")
    bag[5512]=2
    T.BagsChanged()
    assert(T.Refresh(stone,"item")==true and stone.icon.gReady==true,"a stone back in the bags glows ready")
    bag[5512]=nil
    T.BagsChanged()
    assert(T.Refresh(stone,"item")==true and not stone.icon.gReady,"the glow goes with the last stone")
    C.state.inCombat=false
    stone.ov=C.EMPTY
    T.Refresh(stone,"full")
    T.Refresh(stoneCat,"item")
    T.Refresh(b4,"item")
    assert(b4.icon.countOff==true and b4.hidden==false and b4.empty==false,"an empty potion category stays")
end
-- An item cooldown on hold (Blizzard starts it when combat ends: false from
-- C_Item, 0 from C_Container and the inventory API) shows no swipe, looks
-- held (desaturated even with desaturation off, at the cooling opacity) and
-- counts as cooling, so no ready alert fires; the use is counted at once.
-- The enabled cooldown then arms the swipe, and its end is one ready edge.
do
    local icon=stone.icon
    bag[5512]=3
    T.BagsChanged()
    stone.ov={desat=2,cdAlpha=40}
    T.Refresh(stone,"full")
    assert(stone.hidden==false and stone.cooling==false and icon.count.last.SetText==3)
    local alerts=ready.i5512 or 0
    itemCd[5512]={now,60,false}
    bag[5512]=2
    T.Refresh(stone,"item")
    assert(stone.cooling==true and not icon.cd.running and icon.tex.last.SetDesaturation==1 and icon.last.SetAlpha==.4,
        "a held cooldown: no swipe, desaturated, cooling opacity")
    assert(icon.count.last.SetText==2 and (ready.i5512 or 0)==alerts,"the use is counted; no ready alert")
    local quiet,queries=writes,countQueries
    T.Refresh(stone,"item");T.Refresh(stone,"cooldown");T.Refresh(stone,"full")
    itemCd[5512]={now,60,0}
    T.Refresh(stone,"item")
    assert(writes==quiet and countQueries==queries and stone.cooling==true,"a held cooldown writes and counts once")
    -- Zero allocation while held.
    collectgarbage("collect")
    collectgarbage("stop")
    for _=1,20 do T.Refresh(stone,"item");T.Refresh(stoneCat,"item") end
    local before=collectgarbage("count")
    for _=1,300 do T.Refresh(stone,"item");T.Refresh(stoneCat,"item") end
    local after=collectgarbage("count")
    collectgarbage("restart")
    assert(after==before,("a held item cooldown allocated %.3f KB"):format(after-before))
    -- Combat ended: the cooldown starts (BAG_UPDATE_COOLDOWN).
    itemCd[5512]={now,60,true}
    T.Refresh(stone,"item")
    assert(stone.cooling==true and icon.cd.running and icon.itemDur.start==now and icon.tex.last.SetDesaturation==0
        and icon.last.SetAlpha==.4,"the released cooldown arms the swipe")
    assert((ready.i5512 or 0)==alerts,"no ready alert on release")
    now=now+61
    icon.cd.scripts.OnCooldownDone(icon.cd)
    assert(stone.cooling==false and not icon.cd.running and ready.i5512==alerts+1 and icon.last.SetAlpha==1,
        "its end is one ready edge")
    -- A secret flag is never compared: the icon clears.
    itemCd[5512]={now,60,SECRET_BOOL}
    T.Refresh(stone,"item")
    assert(stone.cooling==false and not icon.cd.running and ready.i5512==alerts+1)
    -- Equipment slots hold the same way.
    equip.start,equip.length,equip.enable=now,120,0
    T.Refresh(e13,"item")
    assert(e13.cooling==true and not e13.icon.cd.running and e13.icon.tex.last.SetDesaturation==1,"a held trinket")
    equip.enable=1
    T.Refresh(e13,"item")
    assert(e13.cooling==true and e13.icon.cd.running,"the trinket's released cooldown")
    equip.start,equip.length=0,0
    T.Refresh(e13,"item")
    itemCd[5512],bag[5512]=nil,nil
    table.remove(C.plans.uti.entries)
    table.remove(C.plans.uti.entries)
    I.Sync("uti")
    assert(not stone.icon and not stoneCat.icon)
end
-- Category 0 is no category; OnCooldownDone never re-enters its own refresh.
do
    local entry=Entry("b7","uti",{spell=600,base=600,spellCategory=0,texture=1007,charges=false})
    table.insert(C.plans.uti.entries,entry)
    I.Sync("uti")
    Info(600,true,false)
    T.Refresh(entry,"cooldown")
    assert(entry.icon.cd.running and entry.cooling==true,"category 0 entries are spell entries")
    Info(600,false,false)
    local cd=entry.icon.cd
    local nested=0
    local original=Widget.Clear
    Widget.Clear=function(self,...)
        original(self,...)
        if self==cd then nested=nested+1;cd.scripts.OnCooldownDone(cd) end
    end
    cd.scripts.OnCooldownDone(cd)
    Widget.Clear=original
    assert(nested==1 and entry.cooling==false,"Done must not re-enter")
    table.remove(C.plans.uti.entries)
    I.Sync("uti")
    assert(not entry.icon)
end
-- Simulation owns the icon; live refreshes stay out.
do
    local fake=NewDuration(false)
    fake.start,fake.length=now,8
    T.Simulate(b6,fake)
    local calls=Calls(b6.icon.cd,"SetCooldownFromDurationObject")
    Info(600,true,false)
    T.Refresh(b6,"cooldown")
    assert(Calls(b6.icon.cd,"SetCooldownFromDurationObject")==calls,"simulated icon must ignore live events")
    T.Simulate(b6,nil)
    assert(b6.icon.cd.running and not b6.icon.sim)
    Info(600,false,false)
    T.Refresh(b6,"cooldown")
end

------------------------------------------------------------------ Time: zero allocation for spell entries
do
    Info(100,true,false)
    -- A full collect shrinks the Lua stack; warm up afterwards so the
    -- measurement does not count the stack growing back.
    collectgarbage("collect")
    collectgarbage("stop")
    local cd=b1.icon.cd
    for _=1,20 do T.Refresh(b1,"cooldown");T.Refresh(b1,"charges");T.Refresh(b1,"done");T.Refresh(b2,"charges");T.Refresh(b2,"recharge");T.Done(b1.icon,cd) end
    local before=collectgarbage("count")
    for _=1,300 do T.Refresh(b1,"cooldown");T.Refresh(b1,"charges");T.Refresh(b1,"done");T.Refresh(b2,"charges");T.Refresh(b2,"recharge");T.Done(b1.icon,cd) end
    local after=collectgarbage("count")
    collectgarbage("restart")
    assert(after==before,("Time.Refresh allocated %.3f KB"):format(after-before))
    Info(100,false,false)
    T.Refresh(b1,"cooldown")
end

------------------------------------------------------------------ budgets per hot path
-- GCD start that matches an icon while icons ignore the GCD: one cooldown
-- query, one GCD-free duration, the swipe, the curve and the count; no
-- second duration, no cooling. (Icons that do not match the payload are
-- never called: the controller routes by spell.)
do
    Info(100,true,true)
    local queries,durationsBefore,quiet=cooldownQueries,durationCalls,writes
    T.Refresh(b1,"cooldown")
    assert(cooldownQueries==queries+1 and durationCalls==durationsBefore+1,"a GCD refresh queried more than once")
    assert(writes-quiet<=3 and b1.cooling==false,"a GCD refresh wrote "..(writes-quiet).." widgets")
    Info(100,false,false)
    T.Refresh(b1,"cooldown")
end
-- Repeated bag events, unchanged effects and bar mouse: zero allocation
-- and zero widget calls.
do
    equip.start,equip.length,equip.enable=now,60,1
    T.Refresh(e13,"item")
    assert(e13.cooling==true and e13.icon.cd.running)
    b4.catSpell=400
    Info(400,true,false)
    T.Refresh(b4,"cooldown")
    E.Update(b1)
    local function Pass()
        T.Refresh(e13,"item")
        T.Refresh(b4,"item")
        E.Update(b1);E.Usable(b1);E.Range(b1,nil);E.ReadRange(b1);E.CombatChanged()
        I.SetBarMouse("ess",true);I.Style("ess");I.Sync("ess")
    end
    collectgarbage("collect")
    collectgarbage("stop")
    for _=1,20 do Pass() end
    local quiet,queries,counted=writes,cooldownQueries,countQueries
    local before=collectgarbage("count")
    for _=1,300 do Pass() end
    local after=collectgarbage("count")
    collectgarbage("restart")
    assert(after==before,("repeated bag, effect and mouse passes allocated %.3f KB"):format(after-before))
    assert(writes==quiet,"repeated bag, effect and mouse passes wrote "..(writes-quiet).." widgets")
    assert(cooldownQueries==queries and countQueries==counted,"repeated bag events queried cooldowns or counts")
    Info(400,false,false)
    T.Refresh(b4,"cooldown")
    equip.start,equip.length=0,0
    T.Refresh(e13,"item")
    b4.catSpell=nil
    T.Refresh(b4,"full")
end

------------------------------------------------------------------ Effects: usable and range tint
do
    E.Update(b1)
    usable[100],noPower[100]=false,true
    E.Usable(b1)
    local tex=b1.icon.tex
    assert(tex.last.SetVertexColor==.5 and b1.usableCode==2)
    local calls=Calls(tex,"SetVertexColor")
    E.Usable(b1)
    assert(Calls(tex,"SetVertexColor")==calls,"tint memoized")
    usable[100],noPower[100]=nil,nil
    E.Usable(b1)
    assert(tex.last.SetVertexColor==1 and b1.usableCode==1)
    assert(b1.rangeSpell==100)
    E.Range(b1,false)
    assert(math.abs(tex.last.SetVertexColor-ess.rangeR)<1e-9 and b1.outOfRange)
    calls=Calls(tex,"SetVertexColor")
    E.Range(b1,false)
    assert(Calls(tex,"SetVertexColor")==calls)
    E.Range(b1,nil)
    assert(tex.last.SetVertexColor==1 and not b1.outOfRange)
    E.Range(b1,Secret("boolean"))
    assert(not b1.outOfRange,"a secret range answer never tints")
end
-- Range references: one enable per spell, one disable after the last holder.
do
    local function Count(spell,on)
        local count=0
        for _,call in ipairs(rangeLog) do if call[1]==spell and call[2]==on then count=count+1 end end
        return count
    end
    -- Binding already took one reference per ranged entry: b1 (100), b3 and s300 (300).
    assert(b1.rangeSpell==100 and b3.rangeSpell==300 and s300.rangeSpell==300 and E.RangeReferences()==3)
    assert(Count(300,true)==1 and Count(100,true)==1,"a shared spell is enabled once")
    E.Update(b3);E.Update(s300)
    assert(E.RangeReferences()==3 and Count(300,true)==1,"updates keep their single reference")
    local pooled=b3.icon
    C.plans.ess.entries={b1,b2,b4,e13}
    I.Sync("ess")
    assert(not b3.icon and not b3.rangeSpell and E.RangeReferences()==2 and not pooled.shown)
    assert(Count(300,false)==0,"range must stay enabled while another icon holds it")
    C.plans.uti.entries={b6}
    I.Sync("uti")
    assert(Count(300,false)==1 and E.RangeReferences()==1,"the last holder disables once")
    C.plans.ess.entries={b1,b2,b3,b4,e13}
    I.Sync("ess")
    assert(b3.icon==pooled and pooled.shown and b3.rangeSpell==300 and Count(300,true)==2,"pooled icon reused")
end

------------------------------------------------------------------ Effects: glows
do
    local icon=b1.icon
    overlayed[100]=true;E.Proc(b1,true)
    local glow=icon.glow
    assert(glow and glow.shown and glow.flipAnim.playing and Calls(glow.flipAnim,"Play")==1)
    assert(glow.flip.last.SetAtlas=="UI-HUD-ActionBar-Proc-Loop-Flipbook" and glow.flip.w==40*1.4 and glow.flip.h==36*1.4)
    E.Proc(b1,true)
    assert(Calls(glow.flipAnim,"Play")==1,"no restart without an edge")
    ess.readyGlow=true;ess.behaviorGen=2
    C.state.inCombat=false
    E.Update(b1)
    assert(not icon.gReady,"ready glow waits for combat")
    C.state.inCombat=true
    E.CombatChanged()
    assert(icon.gReady and Calls(glow.flipAnim,"Play")==1,"a second reason shares the running glow")
    overlayed[100]=nil;E.Proc(b1,false)
    assert(Calls(glow.flipAnim,"Stop")==0 and glow.shown,"ready keeps the glow")
    C.state.inCombat=false
    E.CombatChanged()
    assert(Calls(glow.flipAnim,"Stop")==1 and not glow.shown)
    -- Style change while glowing restarts once with the new look.
    C.state.inCombat=true
    E.CombatChanged()
    ess.glowStyle=3;ess.behaviorGen=3
    E.Update(b1)
    assert(glow.pulse.playing and glow.edges[1].shown and not glow.flip.shown)
    -- A pixel-scale change repaints the edge width of a glow shown again.
    local edge=glow.edges[1]
    local height=edge.last.SetHeight
    ess.readyGlow=false;ess.behaviorGen=4
    E.Update(b1)
    C.state.px=.5
    ess.readyGlow=true;ess.behaviorGen=5
    E.Update(b1)
    assert(glow.shown and edge.last.SetHeight==height*.5,"edge glow keeps the old pixel width")
    C.state.px=1
    ess.glowStyle=1;ess.readyGlow=false;ess.behaviorGen=6
    E.Update(b1)
    assert(not glow.shown and not glow.pulse.playing and not glow.flipAnim.playing)
    C.state.inCombat=false
    -- Per-spell tint desaturates the atlas before coloring.
    b1.ov={glowColor="00ff00"}
    overlayed[100]=true;E.Proc(b1,true)
    assert(glow.flip.last.SetDesaturated==true and glow.flip.last.SetVertexColor==0)
    overlayed[100]=nil;E.Proc(b1,false)
    b1.ov=C.EMPTY
    -- Same look again: shown and played, not repainted; hiding stops only
    -- the animation that runs.
    overlayed[100]=true;E.Proc(b1,true)
    local atlas,size,tint,plays=Calls(glow.flip,"SetAtlas"),Calls(glow.flip,"SetSize"),Calls(glow.flip,"SetVertexColor"),Calls(glow.flipAnim,"Play")
    local pulses=Calls(glow.pulse,"Stop")
    overlayed[100]=nil;E.Proc(b1,false)
    assert(Calls(glow.pulse,"Stop")==pulses,"hiding an atlas glow stopped the idle pulse")
    overlayed[100]=true;E.Proc(b1,true)
    assert(glow.shown and glow.flip.shown and Calls(glow.flipAnim,"Play")==plays+1)
    assert(Calls(glow.flip,"SetAtlas")==atlas and Calls(glow.flip,"SetSize")==size and Calls(glow.flip,"SetVertexColor")==tint,
        "a glow shown again with the same look was repainted")
    local quiet=writes
    E.Update(b1);E.Proc(b1,true)
    assert(writes==quiet,"an unchanged effect update wrote "..(writes-quiet))
    overlayed[100]=nil;E.Proc(b1,false)
end
-- Assisted combat: ants only on the suggestion, painted on change only.
do
    ess.assist=true
    E.Assist(100)
    local ants=b1.icon.ants
    assert(ants and ants.shown and Calls(ants.anim,"Play")==1 and b1.assistOn and not b2.assistOn)
    local before=writes
    E.Assist(100)
    assert(writes==before,"same suggestion paints nothing")
    local late=Entry("s100","ess",{spell=100,base=100,texture=1001,charges=false})
    table.insert(C.plans.ess.entries,late)
    I.Sync("ess")
    assert(late.assistOn and late.icon.ants and late.icon.ants.shown,"an entry bound later matches the current suggestion")
    table.remove(C.plans.ess.entries)
    I.Sync("ess")
    assert(not late.icon)
    E.Assist(nil)
    assert(not ants.shown and Calls(ants.anim,"Stop")==1 and not b1.assistOn)
    local sized=Calls(ants.tex,"SetSize")
    E.Assist(100)
    assert(ants.shown and Calls(ants.tex,"SetSize")==sized,"ants shown again keep their size")
    E.Assist(nil)
    ess.assist=false
end

------------------------------------------------------------------ preview and release
do
    local parent=CreateFrame("Frame",nil,nil)
    local icon=I.CreateStandalone(parent)
    I.StyleIcon(icon,uti)
    assert(icon.w==32 and icon.h==29 and icon.parent==parent and I.Count("ess")==5)
    local placeholder=Entry("p1","ess",{texture=134400})
    table.insert(C.plans.ess.entries,placeholder)
    I.Sync("ess")
    assert(placeholder.icon and T.Refresh(placeholder,"full")==false and not placeholder.rangeSpell)
    -- A bar that stops being a cooldown bar releases its icons.
    C.plans.uti.kind=2
    I.Sync("uti")
    assert(I.Count("uti")==0 and not b6.icon)
    C.plans.uti.kind=1
    I.Sync("uti")
    assert(b6.icon and b6.icon.shown)
    overlayed[100]=true
    E.Proc(b1,true)
    ess.assist=true
    E.Assist(100)
    E.ReleaseAll()
    assert(E.RangeReferences()==0 and not b1.icon.glow.shown and not b1.icon.gProc and not b1.icon.ants.shown and not b1.assistOn)
    E.Assist(100)
    assert(b1.icon.ants.shown,"assist paints again after a release")
    ess.assist=false
    I.ReleaseAll()
    assert(I.Count("ess")==0 and I.Count("uti")==0 and not b1.icon and not b2.icon)
    for _,widget in ipairs(all) do
        if widget.kind=="AnimationGroup" and widget.playing then
            assert(false,"an animation kept running after release")
        end
    end
end
print("Cooldown manager render: constants, 10:9 defaults, pooled icons, memoized styling, tooltips, hidden-bar mouse, threshold formatter, keybinds, secret sinks, isolation, ready edges, ready inside a GCD, charges, hideReady, category counts, cached bag totals, memoized items, empty healthstones, held item cooldowns, simulation, zero allocation, hot-path budgets, tint, range references, glow union and repaint memo, assist and release passed")
