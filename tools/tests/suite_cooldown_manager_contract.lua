local root=assert(arg[1],"repository root required")
-- Full offline contract for the cooldown manager runtime. Boots the core
-- suite (with the cooldown manager catalog), the shared runtime and every
-- runtime file in TOC order, then drives the installed module through its
-- lifecycle and the event map with stubbed WoW APIs. Secret values are
-- sentinels that raise on any Lua use and report their game type through
-- type(); widgets count every setter call; timers run only when the test
-- advances the clock.
local Support=dofile(root.."/tools/tests/suite_test_support.lua")
local ADDON,ID="MSUF_Suite_CooldownManager","cooldownManager"

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
local SECRET_NUM,SECRET_BOOL,SECRET_TEXT=Secret("number"),Secret("boolean"),Secret("string")
-- getmetatable() on a string interns "__metatable" again after every full
-- collect; this constant keeps it alive so the stub above never shows up
-- in the allocation budgets (the client's issecretvalue is a C function).
local PINNED_METAFIELD="__metatable"
local function Plain(value,what) if IsSecret(value) then error("secret value reached "..what,3) end end

------------------------------------------------------------------ static checks
local function Read(path)
    local handle=assert(io.open(path,"rb"),"missing "..path)
    local text=handle:read("*a"):gsub("\r","")
    handle:close()
    return text
end
local ORDER={"Bootstrap.lua","Const.lua","Presets.lua","GuideProfiles.lua","Catalog.lua","Resolve.lua","Index.lua","Icons.lua","Time.lua",
    "Effects.lua","Auras.lua","Alerts.lua","Layout.lua","Visibility.lua","Native.lua","Keybinds.lua","Preview.lua",
    "Controller.lua"}
local tocFiles=Support.TocFiles(root,ADDON)
assert(#tocFiles==#ORDER,"runtime TOC must list the 18 cooldown manager files")
for i=1,#ORDER do assert(tocFiles[i]==ORDER[i],"TOC order: expected "..ORDER[i].." at "..i) end
local toc=Read(root.."/"..ADDON.."/"..ADDON.."_Mainline.toc")
local chat=Read(root.."/MSUF_Suite_Chat/MSUF_Suite_Chat_Mainline.toc")
for _,field in ipairs({"## Interface:[^\n]*","## Version:[^\n]*","## Author:[^\n]*"}) do
    local line=assert(chat:match(field))
    assert(toc:find(line,1,true),"TOC header differs from the Chat addon: "..line)
end
assert(toc:find("## Title: MSUF Suite - Cooldown manager\n",1,true),"TOC title")
assert(toc:find("## Dependencies: MSUF_Suite, MSUF_Suite_Modules\n",1,true),"TOC dependencies")
assert(toc:find("## LoadOnDemand: 1\n",1,true),"runtime must load on demand")
local HEADER="local _, P = ...\nlocal NS, S = P.NS, P.Suite\nlocal C = P.CDM\n"
-- Presets.lua is plain data plus one class lookup: it needs only the CDM table.
local DATA_HEADER="local _, P = ...\nlocal C = P.CDM\n"
for _,file in ipairs(ORDER) do
    local text=Read(root.."/"..ADDON.."/"..file)
    if file=="Presets.lua" or file=="GuideProfiles.lua" then assert(text:sub(1,#DATA_HEADER)==DATA_HEADER,file.." header")
    elseif file~="Bootstrap.lua" then assert(text:sub(1,#HEADER)==HEADER,file.." header") end
    for _,word in ipairs({"pcall","loadstring","setfenv","getfenv","OnUpdate","Claude","Anthropic"}) do
        assert(not text:find(word,1,true),file.." uses "..word)
    end
    if file~="Native.lua" then assert(not text:find("hooksecurefunc",1,true),file.." hooks Blizzard code") end
    assert(loadfile(root.."/"..ADDON.."/"..file),file.." does not compile")
end

------------------------------------------------------------------ widgets
local writes=0
local Widget={}
Widget.__index=Widget
local all={}
local created={}
local function New(kind,parent,name)
    local widget=setmetatable({kind=kind,parent=parent,name=name,calls={},scripts={},events={},children={},
        shown=true,alpha=1,level=(parent and parent.level or 0)+1,w=0,h=0,points=0},Widget)
    if parent and parent.children then parent.children[#parent.children+1]=widget end
    all[#all+1]=widget
    created[kind]=(created[kind] or 0)+1
    return widget
end
local function Setter(name,apply,plain)
    Widget[name]=function(self,a,b,c,d,e)
        writes=writes+1
        self.calls[name]=(self.calls[name] or 0)+1
        if plain then Plain(a,name);Plain(b,name);Plain(c,name) end
        if apply then return apply(self,a,b,c,d,e) end
    end
end
Setter("SetPoint",function(self,a,b,c,d,e) self.points=self.points+1;self.point={a,b,c,d,e} end,true)
Setter("ClearAllPoints",function(self) self.points=0 end)
Setter("SetAllPoints",function(self,rel) self.points=2;self.point={"ALL",rel} end)
Setter("SetSize",function(self,w,h) self.w,self.h=w,h end,true)
Setter("SetWidth",function(self,w) self.w=w end,true)
Setter("SetHeight",function(self,h) self.h=h end,true)
Setter("Show",function(self) self.shown=true end)
Setter("Hide",function(self) self.shown=false end)
Setter("SetShown",function(self,shown) self.shown=shown and true or false end,true)
Setter("SetAlpha",function(self,alpha) self.alpha=alpha end)
Setter("SetScale",function(self,scale) self.scale=scale end,true)
Setter("SetFrameLevel",function(self,level) self.level=level end,true)
Setter("SetFrameStrata",function(self,strata) self.strata=strata end,true)
Setter("SetScript",function(self,key,fn) self.scripts[key]=fn end)
Setter("SetAttribute",function(self,key,value) self.attributes=self.attributes or {};self.attributes[key]=value end)
Setter("HookScript")
Setter("RegisterEvent",function(self,event) self.events[event]=true end)
Setter("UnregisterEvent",function(self,event) self.events[event]=nil end)
Setter("UnregisterAllEvents",function(self) self.events={} end)
Setter("SetTexture",function(self,tex) self.tex=tex end,true)
Setter("SetVertexColor",function(self,r,g,b) self.vc={r,g,b} end,true)
Setter("SetText",function(self,text) self.text=text end)
Setter("SetFont",function(self,path,size,flags) Plain(size,"SetFont");self.font=path;self.size=size;self.fontFlags=flags end)
Setter("SetShadowColor",function(self,r,g,b,a) self.shadowColor={r,g,b,a} end)
Setter("SetShadowOffset",function(self,x,y) self.shadowOffset={x,y} end)
Setter("SetCooldownFromDurationObject",function(self,duration)
    assert(getmetatable(duration)==_G.DurationMT,"not a duration object");self.running=duration
end)
Setter("Clear",function(self) self.running=nil end)
Setter("Play",function(self) self.playing=true end)
Setter("Stop",function(self) self.playing=false end)
Setter("SetUnit",function(self,unit) self.unit=unit end,true)
Setter("SetEnabled",function(self,on) self.enabled=on end,true)
Setter("UpdateAllAuras",function(self) self.updates=(self.updates or 0)+1 end)
for _,name in ipairs({"EnableMouse","EnableMouseMotion","SetDesaturated","SetAtlas","SetDrawSwipe","SetDrawEdge","SetDrawBling",
    "SetHideCountdownNumbers","SetReverse","SetCountdownFormatter","SetClampedToScreen","SetMouseClickEnabled",
    "SetMouseMotionEnabled","SetJustifyH","SetWordWrap","SetFlowLayoutAxis","SetFlowLayoutAnchorPoint",
    "SetFlowLayoutGrowthDirection","SetFlowLayoutMaximumLineSize","SetFlowLayoutPadding","SetAuraGroupFilterString",
    "SetAuraSlotFilterString","SetAuraGroupMaxFrameCount","SetEditModePreviewEnabled"}) do
    Setter(name,nil,true)
end
for _,name in ipairs({"SetTexCoord","SetColorTexture","SetDesaturation","SetTextColor","SetSwipeColor","SetLooping",
    "SetDuration","SetFromAlpha","SetToAlpha","SetFlipBookRows","SetFlipBookColumns","SetFlipBookFrames",
    "SetFlipBookFrameWidth","SetFlipBookFrameHeight","SetStatusBarTexture","SetStatusBarColor","SetMinMaxValues","SetValue",
    "SetAuraGroupLayout",
    "SetOwner","SetSpellByID","SetItemByID","SetInventoryItem","SetTooltipAnchorPoint"}) do
    Setter(name)
end
-- Compact aura containers remember each group's spell IDs and on state, so
-- the test reads which container (unit) tracks an entry.
function Widget:Group(key)
    local groups=self.groups or {}
    self.groups=groups
    local group=groups[key] or {on=true}
    groups[key]=group
    return group
end
function Widget:Tracks(id)
    for _,group in pairs(self.groups or {}) do if group.on and group.ids and group.ids[id] then return true end end
    return false
end
Setter("AddAuraGroup",function(self,key,_,opts)
    local group=self:Group(key)
    group.on,group.ids=true,{}
    for id in pairs(opts.candidateFilters.includeSpellIDs or {}) do group.ids[id]=true end
end)
Setter("SetAuraGroupCandidateFilters",function(self,key,filters)
    local group=self:Group(key)
    group.ids={}
    for id in pairs(filters.includeSpellIDs or {}) do group.ids[id]=true end
end)
Setter("SetAuraGroupEnabled",function(self,key,on) self:Group(key).on=on==true end,true)
-- Fixed-place slots (AuraSlots) record their spell IDs and on state like
-- groups, so Tracks reads both. While Widget.InitSlots(true) holds, a new
-- slot also gets its one button through initializeFrame, as the client
-- does, so the test reads the cell each slot follows.
do
    local initSlots=false
    function Widget.InitSlots(on) initSlots=on==true end
    local BUTTON={"SetIcon","SetDurationCooldown","SetDurationText","SetDurationBar","SetSpellName","SetApplicationCount",
        "SetApplicationBar"}
    local function Ignore() end
    Setter("AddAuraSlot",function(self,key,_,opts)
        local group=self:Group(key)
        group.on,group.slot,group.ids=true,true,{}
        for id in pairs(opts.candidateFilters.includeSpellIDs or {}) do group.ids[id]=true end
        if initSlots then
            local button=New("AuraButton",self)
            for i=1,#BUTTON do button[BUTTON[i]]=Ignore end
            group.button=button
            opts.initializeFrame(button)
        end
    end)
    Setter("SetAuraSlotCandidateFilters",function(self,key,filters)
        local group=self:Group(key)
        group.ids={}
        for id in pairs(filters.includeSpellIDs or {}) do group.ids[id]=true end
    end)
    Setter("SetAuraSlotEnabled",function(self,key,on) self:Group(key).on=on==true end,true)
end
function Widget:GetWidth() return self.w end
function Widget:GetHeight() return self.h end
function Widget:GetFrameLevel() return self.level end
function Widget:IsShown() return self.shown end
function Widget:GetAlpha() return self.alpha end
function Widget:GetScale() return self.scale or 1 end
function Widget:GetEffectiveScale() return self.escale or 1 end
function Widget:GetCenter() return self.cx,self.cy end
function Widget:GetRect() local r=self.rect or {0,0,self.w,self.h};return r[1],r[2],r[3],r[4] end
function Widget:GetScript(key) return self.scripts[key] end
function Widget:GetChildren() return unpack(self.children) end
function Widget:GetNumPoints() return self.points end
function Widget:GetAttribute(key) return self.attributes and self.attributes[key] end
function Widget:IsForbidden() return false end
function Widget:IsMouseOver() return false end
function Widget:IsOwned() return false end
function Widget:CreateTexture() return New("Texture",self) end
function Widget:CreateFontString() return New("FontString",self) end
function Widget:CreateAnimationGroup() return New("AnimationGroup",self) end
function Widget:CreateAnimation(kind) return New(kind,self) end
function Widget:GetCountdownFontString()
    if not self.countdown then self.countdown=New("FontString",self) end
    return self.countdown
end
local frameKinds={}
CreateFrame=function(kind,name,parent,template)
    frameKinds[kind]=(frameKinds[kind] or 0)+1
    local frame=New(kind,parent,name)
    frame.template=template
    return frame
end
UIParent=New("Frame",nil,"UIParent")
UIParent.w,UIParent.h=1024,768
local physical={1024,768}
GetPhysicalScreenSize=function() return physical[1],physical[2] end
GameTooltip=New("GameTooltip")
MSUF_PixelLayoutRegion=function(frame) return frame end

------------------------------------------------------------------ clock and timers
local now=1000
GetTime=function() return now end
local timers,tickers={},{}
C_Timer={
    After=function(delay,fn) timers[#timers+1]={due=now+delay,fn=fn} end,
    NewTimer=function(delay,fn)
        local timer={due=now+delay,fn=fn}
        function timer:Cancel() self.cancelled=true end
        timers[#timers+1]=timer
        return timer
    end,
    NewTicker=function(interval,fn)
        local ticker={interval=interval,fn=fn}
        function ticker:Cancel() self.cancelled=true end
        tickers[#tickers+1]=ticker
        return ticker
    end,
}
local function Run(advance)
    now=now+(advance or 0)
    for _=1,1000 do
        local index
        for i=1,#timers do
            if timers[i].cancelled then index=i;break end
            if timers[i].due<=now then index=i;break end
        end
        if not index then return end
        local timer=table.remove(timers,index)
        if not timer.cancelled then timer.fn() end
    end
    error("timers did not settle")
end
local function PendingTimers()
    local n=0
    for i=1,#timers do if not timers[i].cancelled then n=n+1 end end
    return n
end
local function LiveTickers()
    local n,last=0,nil
    for i=1,#tickers do if not tickers[i].cancelled then n=n+1;last=tickers[i] end end
    return n,last
end
wipe=function(t) for k in pairs(t) do t[k]=nil end return t end
table.wipe=wipe

------------------------------------------------------------------ client state
local combat,targetExists=false,false
InCombatLockdown=function() return combat end
UnitName=function() return "Tester" end
GetRealmName=function() return "Realm" end
UnitClass=function() return "Mage","MAGE",8 end
RAID_CLASS_COLORS={MAGE={r=.25,g=.78,b=.92}}
SlashCmdList={}
local cvars={cooldownViewerEnabled="1",assistedCombatHighlight="0"}
C_CVar={GetCVar=function(key) return cvars[key] end,SetCVar=function(key,value) cvars[key]=tostring(value) end}
local specIndex=2
local SPEC_IDS={62,63,64}
C_SpecializationInfo={
    GetSpecialization=function() return specIndex end,
    GetSpecializationInfo=function(index) return SPEC_IDS[index],"Spec"..index,"",6000+index end,
}
Constants={SpellCooldownConsts={GLOBAL_RECOVERY_CATEGORY=133}}
Enum={LuaCurveType={Linear=0,Step=1},NumericRuleFormatRounding={Nearest=0,Up=1,Down=2},
    UnitAuraSoundTrigger={Added=0,Removed=2},StatusBarTimerDirection={ElapsedTime=0,RemainingTime=1},
    StatusBarInterpolation={Immediate=0},SpellBookSpellBank={Player=0,Pet=1},CompressionMethod={Deflate=0}}
local hooks={}
hooksecurefunc=function(object,method,fn) hooks[#hooks+1]={object,method,fn} end
local drivers={}
-- The state driver manager resolves macro conditions at once.
local function Evaluate(expression)
    for clause in (expression..";"):gmatch("%s*([^;]*);") do
        local conditions,action=clause:match("^(.-)%s*(%a+)$")
        if conditions=="" then return action end
        for group in conditions:gmatch("%[(.-)%]") do
            local on=(group=="combat" and combat) or (group=="@target,exists" and targetExists)
            if on then return action end
        end
    end
    return "show"
end
-- Like the client: the attribute is set (OnAttributeChanged fires only
-- when the value changes) and stays readable through GetAttribute.
RegisterAttributeDriver=function(frame,attribute,expression)
    drivers[frame]=expression
    frame.attributes=frame.attributes or {}
    local value=Evaluate(expression)
    if frame.attributes[attribute]==value then return end
    frame.attributes[attribute]=value
    local handler=frame.scripts.OnAttributeChanged
    if handler then handler(frame,attribute,value) end
end
UnregisterAttributeDriver=function(frame) drivers[frame]=nil end
local function DriverCount() local n=0;for _ in pairs(drivers) do n=n+1 end;return n end
local registry,triggered={},{}
EventRegistry={
    RegisterCallback=function(_,event,fn,owner) registry[event]={fn=fn,owner=owner} end,
    UnregisterCallback=function(_,event,owner) if registry[event] and registry[event].owner==owner then registry[event]=nil end end,
    TriggerEvent=function(_,event,...) assert(select("#",...)==0,"no payload");triggered[#triggered+1]=event end,
}
local ANCHOR_EVENT="MSUFSuite.CooldownManager.AnchorChanged"
local function AnchorEvents()
    local n=0
    for i=1,#triggered do if triggered[i]==ANCHOR_EVENT then n=n+1 end end
    assert(n==#triggered,"only the anchor event is triggered")
    return n
end
local elements={}
MSUF_EditModeAPI={
    RegisterElement=function(_,element) elements[element.id]=element;return true end,
    RefreshOwner=function() end,
    UnregisterOwner=function() wipe(elements) end,
    IsActive=function() return false end,
    RegisterSessionListener=function() end,
    UnregisterSessionListener=function() end,
}
local store={}
MSUF_EncodeCompactTable=function(value,prefix) store[#store+1]=value;return prefix..":"..#store end
MSUF_TryDecodeCompactString=function(text) local n=tonumber(text:match("^MSUF3:(%d+)$"));return n and store[n] or nil end
AuraContainerInbound={}

------------------------------------------------------------------ durations, curves, formatters
DurationMT={}
DurationMT.__index=DurationMT
local function NewDuration(secret,start,length) return setmetatable({secret=secret,start=start or 0,length=length or 0},DurationMT) end
function DurationMT:HasSecretValues() return self.secret end
function DurationMT:IsActive() if self.secret then return SECRET_BOOL end return self.start+self.length>now end
function DurationMT:EvaluateRemainingDuration(curve)
    assert(curve and curve.points,"curve missing")
    if self.secret then return SECRET_NUM end
    return (self.start+self.length>now) and curve.points[2][2] or curve.points[1][2]
end
function DurationMT:SetTimeFromStart(start,length)
    Plain(start,"SetTimeFromStart");Plain(length,"SetTimeFromStart")
    self.start,self.length,self.secret=start,length,false
end
C_DurationUtil={CreateDuration=function() return NewDuration(false) end}
local CurveMT={}
CurveMT.__index=CurveMT
function CurveMT:SetType(kind) self.type=kind end
function CurveMT:AddPoint(x,y) self.points[#self.points+1]={x,y} end
C_CurveUtil={CreateCurve=function() return setmetatable({points={}},CurveMT) end}
local FormatterMT={}
FormatterMT.__index=FormatterMT
function FormatterMT:SetBreakpoints(points) self.points=points end
C_StringUtil={CreateNumericRuleFormatter=function() return setmetatable({},FormatterMT) end}

------------------------------------------------------------------ spells, items and Blizzard's catalog
local names={[101]="Fire Blast",[102]="Combustion",[103]="Meteor",[104]="Shifting Power",[1040]="Shifting Power II",
    [201]="Blink",[202]="Counterspell",[301]="Hot Streak",[302]="Ignite",[303]="Pyroclasm",[401]="Combustion Buff",
    [501]="Arcane Torrent",[9001]="Custom Spell",[9102]="Use Item",[431932]="Potion",[431933]="Potion II"}
local known={[101]=true,[102]=true,[104]=true,[201]=true,[202]=true,[301]=true,[302]=true,[303]=true,[401]=true,
    [501]=true,[9001]=true}
local ranged={[101]=true,[202]=true}
local cdState,chargeState,usable,inRange,overlayed={},{[101]={isActive=false}},{},{},{}
usable.calls={}
local bagCounts={}
local cdCalls,cdSpells,invCalls,rangeLog=0,{},0,{}
local function CooldownInfo(spell)
    local state=cdState[spell]
    local active=state and state.start+state.length>now or false
    return {isActive=active,isOnGCD=state and state.gcd or false,isEnabled=true,
        startTime=combat and SECRET_NUM or (state and state.start or 0),duration=combat and SECRET_NUM or (state and state.length or 0)}
end
C_Spell={
    GetSpellName=function(spell) Plain(spell,"GetSpellName");return names[spell] end,
    GetSpellTexture=function(spell) Plain(spell,"GetSpellTexture");if names[spell] then return 1000+spell,1000+spell,nil end end,
    GetBaseSpell=function(spell) return spell end,
    SpellHasRange=function(spell) return ranged[spell]==true end,
    GetSpellCooldown=function(spell)
        Plain(spell,"GetSpellCooldown")
        cdCalls=cdCalls+1;cdSpells[spell]=(cdSpells[spell] or 0)+1
        return CooldownInfo(spell)
    end,
    GetSpellCooldownDuration=function(spell)
        Plain(spell,"GetSpellCooldownDuration")
        local state=cdState[spell]
        return NewDuration(combat,state and state.start,state and state.length)
    end,
    GetSpellCharges=function(spell)
        local state=chargeState[spell]
        if not state then return nil end
        return {maxCharges=2,isActive=state.isActive,currentCharges=combat and SECRET_NUM or 1}
    end,
    GetSpellChargeDuration=function() return NewDuration(combat,now,8) end,
    GetSpellDisplayCount=function() return SECRET_TEXT end,
    IsSpellUsable=function(spell)
        usable.calls[spell]=(usable.calls[spell] or 0)+1
        if usable[spell]~=nil then return usable[spell],false end
        return true,false
    end,
    IsSpellInRange=function(spell) return inRange[spell] end,
    EnableSpellRangeCheck=function(spell,on) Plain(spell,"range");Plain(on,"range");rangeLog[#rangeLog+1]={spell,on} end,
    GetLastCategoryCooldownSource=function(category)
        if category==4 and not combat then return 431932,212265 end
    end,
    -- Harmful spells (a DoT like Ignite, Deathstalker's Mark): a Blizzard
    -- aura entry with any harmful aura ID is tracked on the target, the
    -- rest on the player. Calls are counted per ID (Resolve caches them).
    harmful={[302]=true,[3011]=true},
    harmChecks={},
    IsSpellHarmful=function(spell)
        Plain(spell,"IsSpellHarmful")
        C_Spell.harmChecks[spell]=(C_Spell.harmChecks[spell] or 0)+1
        return C_Spell.harmful[spell]==true
    end,
}
C_SpellBook={
    IsSpellKnownOrInSpellBook=function(spell) return known[spell]==true end,
    FindSpellOverrideByID=function() return nil end,
}
C_SpellActivationOverlay={IsSpellOverlayed=function(spell) return overlayed[spell]==true end}
C_Item={
    GetItemIconByID=function(item) if item==9002 or item==7777 then return 5000+item end end,
    GetItemNameByID=function(item) if item==9002 then return "Healthstone" end if item==7777 then return "Trinket" end end,
    GetItemSpell=function(item) if item==9002 then return "Use Item",9102 end end,
    -- Item cooldowns by item ID ({start,length,enable}); none by default.
    cooldowns={},
    GetItemCooldown=function(item) local cd=C_Item.cooldowns[item];if cd then return cd[1],cd[2],cd[3] end return 0,0,true end,
    GetItemCount=function(item) return bagCounts[item] or 2 end,
    IsUsableItem=function() return true,false end,
}
GetInventoryItemID=function(_,slot) if slot==13 then return 7777 end end
GetInventoryItemTexture=function(_,slot) if slot==13 then return 4444 end end
GetInventoryItemCooldown=function(unit,slot) assert(unit=="player" and slot==13);invCalls=invCalls+1;return 0,0,1 end
local actionSlots={[102]={2},[101]={62}}
local bindings={ACTIONBUTTON2="SHIFT-2",MULTIACTIONBAR1BUTTON2="NUMPAD4"}
C_ActionBar={FindSpellActionButtons=function(spell) local list=actionSlots[spell];return list and {unpack(list)} or {} end}
GetBindingKey=function(command) return bindings[command] end
local nextCast
C_AssistedCombat={IsAvailable=function() return true end,GetNextCastSpell=function() return nextCast end}
AssistedCombatManager={}
local auraSounds={}
C_UnitAuras={AddAuraSound=function() auraSounds[#auraSounds+1]=true;return #auraSounds end,RemoveAuraSound=function() end}
PlaySoundFile=function() return true end
PlaySound=function() return true end

local infos,sets={},{[0]={11,12,13,14},[1]={21,22},[2]={31,32},[3]={41},[5]={51,52},[6]={},[7]={71},[8]={}}
local function Info(id,spell,category,fields)
    local info={cooldownID=id,spellID=spell,category=category,isKnown=true,flags=0,linkedSpellIDs={},
        selfAura=false,hasAura=false,charges=false}
    for key,value in pairs(fields or {}) do info[key]=value end
    infos[id]=info
end
Info(11,101,0,{charges=true,linkedSpellIDs={1011}})
Info(12,102,0,{hasAura=true,selfAura=true})
Info(13,103,0,{isKnown=false})
Info(14,104,0)
Info(21,201,1)
Info(22,202,1)
Info(31,301,2,{selfAura=true,hasAura=true})
Info(32,302,2,{hasAura=true})
Info(41,401,3,{selfAura=true,hasAura=true})
Info(51,501,5)
Info(52,nil,5,{spellCategoryID=4})
Info(71,nil,7,{equipSlot=13})
C_CooldownViewer={
    GetCooldownViewerCategorySet=function(category) local list=sets[category];return list and {unpack(list)} or {} end,
    GetCooldownViewerCooldownInfo=function(id) return infos[id] end,
    GetLayoutData=function() return "" end,
}

-- Blizzard's viewers: read for the first-run capture, alpha-zeroed in mode 2.
local function Viewer(name,cx,cy,w,h,fields)
    local viewer=New("Frame",UIParent,name)
    viewer.cx,viewer.cy,viewer.w,viewer.h=cx,cy,w,h
    for key,value in pairs(fields) do viewer[key]=value end
    viewer.OnAcquireItemFrame=function() end
    _G[name]=viewer
    return viewer
end
local essViewer=Viewer("EssentialCooldownViewer",512,500,300,50,{iconLimit=7,iconPadding=6,iconScale=1,isHorizontal=true})
Viewer("UtilityCooldownViewer",512,420,200,30,{iconLimit=9,iconPadding=4,iconScale=1,isHorizontal=true})
Viewer("BuffIconCooldownViewer",512,600,200,40,{iconPadding=4,iconScale=1,isHorizontal=true})
Viewer("BuffBarCooldownViewer",512,650,220,20,{})
local item=New("Frame",essViewer)
item.layoutIndex=1

------------------------------------------------------------------ boot: core, shared runtime, cooldown manager
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",IsRetail=true,SupportsEvent=function() return true end}}
WOW_PROJECT_ID,WOW_PROJECT_MAINLINE=1,1
local Suite={}
MSUFSuite=Suite
-- Until the integrator lists the catalog in the core TOC (and adds its
-- moduleAddons entry), load it before Suite.lua with a local entry.
local coreFiles=Support.TocFiles(root,"MSUF_Suite")
local listed=false
for _,file in ipairs(coreFiles) do if file=="Core/Catalog/CooldownManager.lua" then listed=true end end
for _,file in ipairs(coreFiles) do
    if file:match("%.lua$") then
        if file=="Core/Suite.lua" and not listed then
            assert(loadfile(root.."/MSUF_Suite/Core/Catalog/CooldownManager.lua"))("MSUF_Suite",Suite)
        end
        assert(loadfile(root.."/MSUF_Suite/"..file))("MSUF_Suite",Suite)
        if file=="Core/SuiteCatalog.lua" and not listed then
            local B=Suite.CatalogBuild
            local original=B.Module
            B.Module=function(id,spec)
                if id~=ID then return original(id,spec) end
                spec.id,spec.addon,spec.controls,spec.rules,spec.conflicts=id,ADDON,{},{},spec.conflicts or {}
                Suite.SuiteCatalog[id],Suite.SuiteOrder[#Suite.SuiteOrder+1]=spec,id
                B.Add(id,B.Bool("enabled","Enable module",true))
                return spec
            end
        end
        if file=="Core/Suite.lua" then break end
    end
end
assert(loadfile(root.."/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite",Suite)
assert(Suite.Database.Initialize(nil))
local S=Suite.Suite
S.Normalize(Suite.DB)
-- The legacy runtime assertions below exercise Blizzard's uncurated list.
-- Raid-presets and their default-on gate have a focused data-plane contract.
S.Config(ID).raidEssentials=false
Support.Load(root,"MSUF_Suite_Modules",{})

-- The runtime may add no globals.
local globalsBefore={}
for key in pairs(_G) do globalsBefore[key]=true end
local private={}
Support.Load(root,ADDON,private)
for key in pairs(_G) do assert(globalsBefore[key],"runtime created the global "..tostring(key)) end
local C=assert(private.CDM,"Bootstrap must publish P.CDM")
for _,field in ipairs({"M","EMPTY","state","views","plans","bars","entries","lists","spells"}) do
    assert(C[field]~=nil,"P.CDM."..field.." missing")
end
local module=assert(S.instances[ID],"Controller must install the module")
assert(module==C.M and module.id==ID and not module.geometry,"module object and combat-safe events")
assert(type(Suite.CooldownManager)=="table" and type(Suite.CooldownManager.GetAnchorFrame)=="function","MSUF anchor export")
for _,name in ipairs({"BarEntries","CatalogEntries","RenderPreview","ReleasePreview","Simulate","SetPreview","Spec",
    "Status","PlaySound","ConvertGrow","ConvertVertical","Generation"}) do
    assert(type(S["CooldownManager"..name])=="function","S.CooldownManager"..name.." missing")
end
C.EMPTY.probe=true
assert(C.EMPTY.probe==nil and next(C.EMPTY)==nil,"EMPTY must stay empty")

local function Fire(event,...)
    local frame=module.context.frame
    if not (frame and frame.events[event]) then return false end
    frame.scripts.OnEvent(frame,event,...)
    return true
end
local function Registered(event)
    local frame=module.context.frame
    return frame~=nil and frame.events[event]==true
end
local function NoOnUpdate()
    for i=1,#all do assert(not all[i].scripts.OnUpdate,"an OnUpdate script is set") end
end
local Codec=Suite.CDM.Codec

-- Work counters: the controller reaches every layer through C at call time.
local calls={}
local function Count(owner,name,label)
    local original=assert(owner[name],name)
    owner[name]=function(...) calls[label]=(calls[label] or 0)+1;return original(...) end
end
Count(C.Icons,"Sync","iconSync");Count(C.Auras,"Sync","auraSync");Count(C.Index,"Rebuild","index")
Count(C.Layout,"ApplyAll","layoutAll");Count(C.Layout,"Apply","layout")
Count(C.Visibility,"ApplyAll","visAll");Count(C.Visibility,"Apply","vis")
Count(C.Keybinds,"Rebuild","keysRebuild");Count(C.Keybinds,"Refresh","keysRefresh");Count(C.Keybinds,"Request","keysRequest")
Count(C.Catalog,"Rebuild","catalog");Count(C.Resolve,"Build","resolve")
local function ResetCalls() wipe(calls) end
local function Calls(label) return calls[label] or 0 end
local seeds=0
do
    local get=C_Spell.GetLastCategoryCooldownSource
    C_Spell.GetLastCategoryCooldownSource=function(...) seeds=seeds+1;return get(...) end
end
-- Every setting suffix of the catalog says what its change dirties.
for suffix in pairs(Suite.CDM.SUFFIXES) do
    assert(C.SettingWork[suffix],"the controller has no work mapping for the setting suffix "..suffix)
end

------------------------------------------------------------------ loaded, never enabled: cold snapshot
assert(S.CooldownManagerStatus()==nil and not S.CooldownManagerSetPreview(true),"no status and no running preview while off")
-- The page's request is kept for the next activation; closing the page takes it back.
assert(S.CooldownManagerSetPreview(false),"turning the preview off always succeeds")
local coldRows=S.CooldownManagerBarEntries("ess")
assert(#coldRows==5 and coldRows[3].key=="b13" and coldRows[3].known==false and coldRows[1].known==true
    and coldRows[5].key=="b71","the options page lists a bar before the module ever ran (trinket last)")
-- Rows say which cooldowns track a buff (the popover's stack rows follow it).
assert(coldRows[2].key=="b12" and coldRows[2].hasAura==true and coldRows[1].hasAura==false
    and coldRows[5].hasAura==false,"bar rows carry hasAura")
coldRows=assert(S.CooldownManagerBlizzardSnapshot())
assert(coldRows.ess[1]=="b11" and coldRows.ess[2]=="b12" and coldRows.ess[#coldRows.ess]=="b71"
    and type(coldRows.uti)=="table" and type(coldRows.buf)=="table"
    and type(coldRows.bar)=="table" and type(coldRows.ext)=="table",
    "Blizzard snapshot follows the current native order and includes every built-in category")
assert(#S.CooldownManagerBarEntries("nope")==0)
local barStage=New("Frame",UIParent)
local rowsCanvas=assert(S.CooldownManagerRenderPreview(barStage,"bar",400,200),"buff bar canvas")
assert(rowsCanvas.rows[1] and rowsCanvas.rows[1].shown and rowsCanvas.rows[1].name.text=="Combustion Buff"
    and not rowsCanvas.icons[1],"buff bars draw as rows")
local iconCanvas=assert(S.CooldownManagerRenderPreview(barStage,"buf",400,200))
assert(iconCanvas==rowsCanvas and iconCanvas.icons[1].shown and not iconCanvas.rows[1].shown,"one reused canvas per parent")
S.CooldownManagerReleasePreview(barStage)
assert(PendingTimers()==0 and not module.context,"nothing runs before activation")

------------------------------------------------------------------ enable: capture, takeover, first build
local config=S.Config(ID)
module.config=config
module.context=S.NewContext(ID)
module.active=true
assert(config.captured==false)
-- The capture takes only the Essential bar's position; sizes stay ours.
local function KeyList(t)
    local list={}
    for key in pairs(t) do list[#list+1]=key end
    table.sort(list)
    return table.concat(list,",")
end
-- x/y place the growth edge relative to UIParent's center: Blizzard's bar is
-- centered at (512, 500) on a 1024 x 768 screen, 50 high, so its top edge
-- sits 500+25-384 = 141 units above the center.
local capture=assert(C.Native.Capture(),"capture values")
assert(KeyList(capture)=="captured,ess_x,ess_y" and capture.captured==true and capture.ess_x==0 and capture.ess_y==141,
    "the capture writes the Essential position from Blizzard's shown bar and nothing else ("..KeyList(capture)..")")
-- Without Blizzard's bar (hidden, or unreadable): the top edge sits just
-- below the screen center, exactly where the catalog default puts it.
local FALLBACK_Y=S.catalog[ID].rules.ess_y.default
assert(S.catalog[ID].rules.ess_x.default==0 and type(FALLBACK_Y)=="number" and FALLBACK_Y<-150 and FALLBACK_Y>-300,
    "the Essential default is centered, a little below the screen center ("..tostring(FALLBACK_Y)..")")
essViewer.shown=false
capture=assert(C.Native.Capture(),"fallback capture")
assert(KeyList(capture)=="captured,ess_x,ess_y" and capture.captured==true and capture.ess_x==0 and capture.ess_y==FALLBACK_Y,
    "a hidden Blizzard bar falls back to the catalog default ("..tostring(capture.ess_y)..")")
essViewer.shown=true
essViewer.cx=SECRET_NUM
capture=assert(C.Native.Capture())
assert(capture.ess_x==0 and capture.ess_y==FALLBACK_Y and capture.captured==true,"a secret viewer center falls back")
essViewer.cx=512
-- Grow Up anchors by the bottom edge: the same rectangle, the other edge.
config.ess_grow=2
capture=assert(C.Native.Capture())
assert(capture.ess_x==0 and capture.ess_y==500-25-384,"grow Up captures the bottom edge")
essViewer.shown=false
capture=assert(C.Native.Capture())
assert(capture.ess_y==FALLBACK_Y-36,"grow Up fallback keeps the top edge where the default puts it")
essViewer.shown=true
config.ess_grow=1
combat=true
assert(C.Native.Capture()==nil,"no capture in combat")
combat=false
UIParent.w=SECRET_NUM
assert(C.Native.Capture()==nil,"no capture without readable UIParent metrics")
UIParent.w=1024
module:Enable()
assert(cvars.cooldownViewerEnabled=="0","mode 1 turns Blizzard's bars off through the CVar")
assert(#hooks==0,"mode 1 installs no hooks")
assert(PendingTimers()>=1,"the first build waits for the next frame")
Run()
S.states[ID].active=true
assert(config.captured==true,"the capture is written once")
assert(config.ess_x==0 and config.ess_y==141,"Essential bar position captured from Blizzard's viewer")
assert(config.defaultsVersion==Suite.CDM.DEFAULTS_VERSION and Suite.CDM.DEFAULTS_VERSION==3,
    "the first run stamps the current defaults version")
assert(config.ess_perRow==9 and config.ess_size==40 and config.ess_spacing==2 and config.ess_height==90,
    "sizes, spacing and icons per row keep the suite defaults (Blizzard's viewer has 7 per row, padding 6)")
assert(config.uti_x==0 and config.uti_y==0 and config.uti_perRow==12,"only the Essential bar is captured; attached bars keep a zero offset")
module:Refresh()
Run()
local bars=C.bars
for _,slot in ipairs({"ess","uti","def","ext","buf","bar"}) do
    assert(bars[slot] and bars[slot].shown and bars[slot].frame.shown,slot.." bar not shown")
end
assert(not (bars.c1 and bars.c1.shown),"custom bars start off")
assert(C.Icons.Count("ess")==4 and C.Icons.Count("uti")==2 and C.Icons.Count("ext")==2,"cooldown icons per bar")
-- The trinket slot joins the end of Essential; Potions and racials keeps the
-- racial and the potion category.
local trinket=assert(C.entries.b71,"trinket entry")
assert(trinket.slot=="ess" and trinket.index==4 and trinket.icon and trinket.equipSlot==13 and trinket.itemID==7777,
    "the trinket ends the Essential bar")
for i=1,#C.Index.usable do
    assert(C.Index.usable[i]~=trinket,"equipment slots must not enter usable broadcasts")
end
assert(trinket.icon.template=="PingReceiverAttributeTemplate" and trinket.icon:GetIsPingable()
    and trinket.icon:GetTargetInfo().itemID==7777 and not trinket.icon:GetAllowRadialWheel(),
    "the live trinket is a contextual item ping target")
assert(C.entries.b51.slot=="ext" and C.entries.b52.slot=="ext","potions and racials stay")
assert(not C.entries.b13,"unlearned spells stay out of live bars")
local e11,e12,e14,e21,e22=C.entries.b11,C.entries.b12,C.entries.b14,C.entries.b21,C.entries.b22
assert(e11.icon and e12.icon and e14.icon and e21.icon and e22.icon)
assert(e11.icon:GetTargetInfo().spellID==e11.spell and e11.icon.attributes["ping-receiver"]==true,
    "live spell icons expose their spell ping target even with tooltips off")
assert(C.entries.b52.catSpell==431932,"category entries are seeded from the last category source")
-- Every Blizzard aura entry gets one unit: the target when an aura ID is
-- harmful (Ignite, a DoT), else the player. Blizzard's selfAura flag plays
-- no part: Ignite is no self aura and was tracked on both units before.
assert(C.entries.b32.unit=="target" and C.entries.b31.unit=="player" and e12.unit=="player" and C.entries.b41.unit=="player",
    "harmful Blizzard auras track on the target, the rest on the player")
assert(e11.unit==nil and e21.unit==nil,"cooldowns without an aura track no unit")
assert(C_Spell.harmChecks[302]==1 and C_Spell.harmChecks[301]==1 and C_Spell.harmChecks[102]==1,
    "the harmful check runs once per spell ID")
assert(config.ess_keybind==false and (e12.icon.lastKey or "")=="","keybind text starts off on the Essential bar")
assert(C.state.specID==63 and C.state.specTag==82,"spec detection")
assert(bars.ess.frame.point[1]=="TOP" and bars.ess.frame.point[2]==UIParent and bars.ess.frame.point[3]=="CENTER"
    and bars.ess.frame.point[4]==0 and bars.ess.frame.point[5]==141,"free bars anchor their growth edge to the screen center")
assert(bars.uti.parent=="ess","Utility attaches to Essential")
assert(C.Effects.RangeReferences()==2,"range checks held for range spells")
assert(frameKinds.AuraContainer and frameKinds.AuraContainer>=4,"aura containers for buffs, buff bars and overlays")
assert(DriverCount()==0 and C.Visibility.DriverCount()==0,"bars shown always need no state driver")
for _,event in ipairs({"SPELL_UPDATE_COOLDOWN","SPELL_UPDATE_CHARGES","SPELL_UPDATE_USABLE","SPELL_RANGE_CHECK_UPDATE",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW","SPELL_ACTIVATION_OVERLAY_GLOW_HIDE","BAG_UPDATE_COOLDOWN","BAG_UPDATE_DELAYED",
    "PLAYER_TARGET_CHANGED","COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED","SPELLS_CHANGED",
    "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","UI_SCALE_CHANGED","PLAYER_ENTERING_WORLD"}) do
    assert(Registered(event),event.." not registered")
end
assert(not Registered("UPDATE_BINDINGS") and not Registered("ACTIONBAR_SLOT_CHANGED"),"no binding events while keybinds are off")
assert(not Registered("UNIT_AURA"),"no Lua per UNIT_AURA: aura containers match auras on the client side")
assert(Registered("UNIT_FACTION"),"target aura containers follow the target's disposition")
assert(registry["CooldownViewerSettings.OnPendingChanges"] and registry["CooldownViewerSettings.OnHide"],
    "Blizzard layout saves rebuild the catalog")
assert(S.CooldownManagerStatus():find("off",1,true),"status names the takeover mode")
assert(Suite.CooldownManager.GetAnchorFrame("EssentialCooldownViewer")==bars.ess.anchorFrame,"MSUF anchor frame")
assert(Suite.CooldownManager.GetAnchorFrame("BuffBarCooldownViewer")==nil)
assert(AnchorEvents()==1,"MSUF hears once that the Essential bar appeared")

------------------------------------------------------------------ MSUF anchor notifications
-- MSUF follows our Essential bar: one EventRegistry event, a frame after
-- that bar shows or hides; everything else stays silent.
local anchorCount=AnchorEvents()
C.Layout.Hide("uti")
C.Layout.Apply("uti")
Run()
assert(AnchorEvents()==anchorCount and PendingTimers()==0,"other bars showing or hiding notify nothing")
C.Layout.Hide("ess")
assert(AnchorEvents()==anchorCount and PendingTimers()==1,"the notification waits for the next frame")
C.Layout.Apply("ess")
C.AnchorChanged()
assert(PendingTimers()==1,"hide, show and a direct request in one frame share one timer")
Run()
assert(AnchorEvents()==anchorCount+1 and bars.ess.shown,"one notification per frame")
Run(1)
assert(AnchorEvents()==anchorCount+1 and PendingTimers()==0,"the notification does not repeat")
config.ess_perRow=8
module:Refresh()
Run()
assert(AnchorEvents()==anchorCount+1,"a layout change of a shown bar notifies nothing")
config.ess_perRow=9
module:Refresh()
Run()

------------------------------------------------------------------ idle budget
NoOnUpdate()
Run(5)
assert(PendingTimers()==0 and LiveTickers()==0,"an idle module keeps no timers")

------------------------------------------------------------------ cooldown events
cdState[101]={start=now,length=12}
local cd11=e11.icon.cd
assert(Fire("SPELL_UPDATE_COOLDOWN",101))
assert(cd11.running and e11.cooling==true,"a matched cooldown starts the swipe")
-- Hot events that match nothing: no allocation, no widget call, no work
-- scheduled, and at most two reads of the routing maps (misses counted).
local ROUTES={C.Index.bySpell,C.Index.byBase,C.Index.byCategory,C.Index.byItem,C.Index.byEquip,C.Catalog.byBase}
local lookups=0
local counting={__index=function() lookups=lookups+1 end}
local before=writes
local function Budget(label,event,...)
    assert(Registered(event),event.." not registered")
    for i=1,#ROUTES do setmetatable(ROUTES[i],counting) end
    lookups=0
    Fire(event,...)
    local reads=lookups
    for i=1,#ROUTES do setmetatable(ROUTES[i],nil) end
    assert(reads<=2,label.." read the routing maps "..reads.." times")
    before=writes
    collectgarbage("collect")
    collectgarbage("stop")
    local kb=collectgarbage("count")
    for _=1,1000 do Fire(event,...) end
    local used=collectgarbage("count")-kb
    collectgarbage("restart")
    assert(used==0,label.." allocated "..used.." KB")
    assert(writes==before,label.." wrote widgets")
    assert(PendingTimers()==0,label.." scheduled work")
end
Budget("a cooldown event without a match","SPELL_UPDATE_COOLDOWN",999999,nil,nil,nil,nil)
Budget("a GCD start without a match","SPELL_UPDATE_COOLDOWN",999999,999998,nil,133,nil)
Budget("a use count without a match","SPELL_UPDATE_USES",999999,999998)
Budget("an icon change without a match","SPELL_UPDATE_ICON",999999)
Budget("a spell alert without a match","SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",999999)
Budget("a spell alert end without a match","SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",999999)
Budget("a range update without a match","SPELL_RANGE_CHECK_UPDATE",999999,false,true)
Budget("an override nothing tracks","COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",999999,999998)
Budget("a gear change outside the tracked slots","PLAYER_EQUIPMENT_CHANGED",5,true)
Budget("a faction change of another unit","UNIT_FACTION","party1")
-- Restrictions (M+ key, PvP match): with aura containers live the end of one
-- flushes held-back aura restyles a frame later; nothing pending, no work.
Budget("a restriction ending with nothing pending","ADDON_RESTRICTION_STATE_CHANGED",1,0)
Budget("a restriction starting","ADDON_RESTRICTION_STATE_CHANGED",1,1)
do
    local flushes,realFlush=0,C.Auras.FlushPending
    C.Auras.FlushPending=function() flushes=flushes+1 end
    C.Auras.pending.buf=true
    Fire("ADDON_RESTRICTION_STATE_CHANGED",1,2)
    assert(PendingTimers()==0,"an active restriction flushes nothing")
    Fire("ADDON_RESTRICTION_STATE_CHANGED",1,0)
    assert(PendingTimers()==1 and flushes==0,"the flush waits for the next frame")
    Run()
    assert(flushes==1,"a restriction ending flushes pending aura restyles once")
    C.Auras.FlushPending=realFlush
    C.Auras.pending.buf=nil
end
-- A GCD for one spell refreshes that spell's icons only: the others do not
-- show the GCD and are not touched.
cdCalls=0
before=writes
Fire("SPELL_UPDATE_COOLDOWN",201,nil,nil,133)
assert(cdCalls==1 and cdSpells[201]~=nil,"a GCD start refreshed icons that ignore the GCD ("..cdCalls..")")
-- Nil payload: every cooldown icon, once.
cdCalls,invCalls=0,0
Fire("SPELL_UPDATE_COOLDOWN",nil)
assert(cdCalls==7 and invCalls==1,"nil payload refreshes each cooldown icon once ("..cdCalls..")")
-- The trinket on Essential reads its cooldown by equipment slot on bag
-- cooldown events, as it did on Potions and racials.
invCalls=0
assert(Fire("BAG_UPDATE_COOLDOWN"))
Run()
assert(invCalls==1 and C.entries.b71.slot=="ess","item cooldowns reach the trinket on Essential ("..invCalls..")")
-- A GCD start that matches nothing touches nothing while icons ignore the GCD.
cdCalls=0
Fire("SPELL_UPDATE_COOLDOWN",55555,nil,nil,133)
assert(cdCalls==0,"GCD start refreshed icons that ignore the GCD")
config.showGCD=true
module:Refresh()
Run()
cdCalls=0
Fire("SPELL_UPDATE_COOLDOWN",55555,nil,nil,133)
assert(cdCalls==7,"GCD start refreshes every icon that shows the GCD")
config.showGCD=false
module:Refresh()
Run()
-- Potions and healthstones follow the spell that started their category.
cdSpells[431933]=nil
Fire("SPELL_UPDATE_COOLDOWN",431933,nil,4,nil,212266)
assert(C.entries.b52.catSpell==431933 and cdSpells[431933]==1,"category source tracking")
-- Secret payload values are never used as keys.
Fire("SPELL_UPDATE_COOLDOWN",SECRET_NUM,SECRET_NUM,SECRET_NUM,SECRET_NUM,SECRET_NUM)
Fire("SPELL_UPDATE_COOLDOWN",101,SECRET_NUM,SECRET_NUM,SECRET_NUM,SECRET_NUM)

------------------------------------------------------------------ charges, usable, range, procs, target
-- Spending a charge arrives with the spell's own cooldown event, which arms
-- the recharge swipe; SPELL_UPDATE_CHARGES (no payload, never registered by
-- Blizzard's viewer) refreshes only recharge swipes that already run.
chargeState[101].isActive=true
cdCalls=0
assert(Fire("SPELL_UPDATE_CHARGES"))
Run()
assert(e11.icon.chargeCd and not e11.icon.chargeCd.running and cdCalls==0,"a charge event refreshed an entry with every charge")
Fire("SPELL_UPDATE_COOLDOWN",101)
assert(e11.icon.chargeCd.running and e11.icon.chargeSet==true,"charge recharge edge")
usable[201]=false
assert(Fire("SPELL_UPDATE_USABLE"))
Run()
assert(e21.icon.tex.vc and e21.icon.tex.vc[1]==.4,"unusable tint")
usable.stormReads=usable.calls[201] or 0
usable[201]=nil
for _=1,30 do Fire("SPELL_UPDATE_USABLE") end
Run()
assert(e21.icon.tex.vc[1]==.4 and (usable.calls[201] or 0)==usable.stormReads,
    "usable event storm repainted before the trailing deadline")
Run(.1)
assert(e21.icon.tex.vc[1]==1 and (usable.calls[201] or 0)==usable.stormReads+1,
    "usable event storm did not coalesce to one final refresh")
usable[201]=SECRET_BOOL
C.Effects.Usable(e21)
assert(e21.icon.tint==1,"a secret usability answer changed the visible tint")
usable[201]=nil
-- All range-tinted entries are inert for this broadcast. A range edge still
-- refreshes the actual usable state when the action becomes visible again.
do
    local rangeSnapshot={}
    for i=1,#C.Index.usable do
        local entry=C.Index.usable[i]
        rangeSnapshot[i]=entry.outOfRange
        entry.outOfRange=true
    end
    local pendingBefore=PendingTimers()
    Fire("SPELL_UPDATE_USABLE")
    assert(PendingTimers()==pendingBefore,"all out-of-range entries still scheduled a usable sweep")
    for i=1,#C.Index.usable do C.Index.usable[i].outOfRange=rangeSnapshot[i] end
end
config.ess_vis=4
module:Refresh();Run()
assert(bars.ess.hidden==true,"hidden Essential bar still appeared visible")
usable.hiddenCallCount=usable.calls[101] or 0
usable[101]=false
Fire("SPELL_UPDATE_USABLE");Run()
assert((usable.calls[101] or 0)==usable.hiddenCallCount,
    "a hidden cooldown bar still queried spell usability")
config.ess_vis=1
module:Refresh();Run()
assert(bars.ess.hidden==false and (usable.calls[101] or 0)>usable.hiddenCallCount
    and e11.icon.tint==3,"a shown cooldown bar did not restore its current usability tint")
usable[101]=nil
Fire("SPELL_UPDATE_USABLE");Run(.1)
assert(e11.icon.tint==1,"visible usability tint did not recover")
Fire("SPELL_RANGE_CHECK_UPDATE",202,false,true)
assert(e22.outOfRange==true and e22.icon.tint==4,"out-of-range tint is immediate")
Fire("SPELL_RANGE_CHECK_UPDATE",202,SECRET_BOOL,true)
assert(not e22.outOfRange,"a secret range answer is treated as in range")
Fire("SPELL_RANGE_CHECK_UPDATE",202,false,false)
-- A linked ID routes to Fire Blast, but only the spell holding the check tints it.
Fire("SPELL_RANGE_CHECK_UPDATE",1011,false,true)
assert(not e11.outOfRange,"a range update for another spell tinted the icon")
Fire("SPELL_RANGE_CHECK_UPDATE",101,false,true)
assert(e11.outOfRange==true)
Fire("SPELL_RANGE_CHECK_UPDATE",101,true,true)
assert(not e22.outOfRange,"no range check means no tint")
-- An out-of-range icon shows the range tint regardless of usability. Defer
-- native usability reads, then recover the current tint on the range edge.
Fire("SPELL_RANGE_CHECK_UPDATE",101,false,true)
usable.outOfRangeReads=usable.calls[101] or 0
usable[101]=false
Fire("SPELL_UPDATE_USABLE");Run(.1)
assert((usable.calls[101] or 0)==usable.outOfRangeReads and e11.icon.tint==4,
    "out-of-range icon still queried hidden usability state")
Fire("SPELL_RANGE_CHECK_UPDATE",101,true,true)
assert((usable.calls[101] or 0)==usable.outOfRangeReads+1 and e11.icon.tint==3,
    "returning to range did not immediately recover unusable tint")
usable[101]=nil
Fire("SPELL_UPDATE_USABLE");Run(.1)
assert(e11.icon.tint==1,"usable tint did not recover after range-edge refresh")
assert(Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",102))
assert(e12.icon.glow and e12.icon.glow.shown and e12.icon.glow.flipAnim.playing,"proc glow")
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",102)
assert(not e12.icon.glow.shown and not e12.icon.glow.flipAnim.playing)
inRange[202]=false
targetExists=true
assert(Fire("PLAYER_TARGET_CHANGED"))
assert(e22.outOfRange==true,"target change re-reads range")
usable.targetRangeReads=usable.calls[202] or 0
usable[202]=false
Fire("SPELL_UPDATE_USABLE");Run(.1)
assert((usable.calls[202] or 0)==usable.targetRangeReads and e22.icon.tint==4,
    "target range tint still spent usability reads")
inRange[202]=true
Fire("PLAYER_TARGET_CHANGED")
assert((usable.calls[202] or 0)==usable.targetRangeReads+1 and e22.icon.tint==3,
    "target change back into range did not recover usability tint")
usable[202]=nil
Fire("SPELL_UPDATE_USABLE");Run(.1)
assert(e22.icon.tint==1,"target range usability tint did not recover")
Run()
local targetContainers=0
for i=1,#all do
    local w=all[i]
    if w.kind=="AuraContainer" and w.unit=="target" and (w.updates or 0)>0 then targetContainers=targetContainers+1 end
end
assert(targetContainers>=1,"target containers refresh on retarget")
inRange[202]=nil

------------------------------------------------------------------ bag counts
-- Potion and healthstone entries show the bag count of every rank behind
-- their category; bag contents arrive with BAG_UPDATE_DELAYED, which shares
-- the item handler with BAG_UPDATE_COOLDOWN.
local potions=assert(C.Presets.CATEGORY_ITEMS[4],"combat potion ranks")
local potion=C.entries.b52.icon
assert(potion.lastCount==2*#potions,"category entries sum every rank")
for i=1,#potions do bagCounts[potions[i]]=0 end
bagCounts[potions[#potions]]=3
assert(Fire("BAG_UPDATE_DELAYED"))
assert(potion.lastCount==2*#potions and PendingTimers()==1,"bag updates share the next-frame flush")
Run()
assert(potion.lastCount==3 and potion.count.text==3,"BAG_UPDATE_DELAYED recounts category entries")
-- BAG_UPDATE_COOLDOWN refreshes item entries but never recounts the bags:
-- totals are counted once per BAG_UPDATE_DELAYED.
bagCounts[potions[#potions]]=0
assert(Fire("BAG_UPDATE_COOLDOWN"))
Run()
assert(potion.lastCount==3 and potion.count.text==3,"a bag cooldown event recounted the bags")
assert(Fire("BAG_UPDATE_DELAYED"))
Run()
assert(potion.lastCount==nil and potion.countOff==true and potion.count.text=="","an empty category clears its count")
wipe(bagCounts)
Fire("BAG_UPDATE_DELAYED")
Run()
assert(potion.lastCount==2*#potions and potion.count.text==2*#potions,"the count returns with the potions")
-- A cooldown event of the category with unchanged bags keeps the bag count:
-- the spell's display count never replaces it.
Fire("SPELL_UPDATE_COOLDOWN",431933,nil,4,nil,212266)
assert(potion.count.text==2*#potions,"a category cooldown refresh replaced the bag count with the spell display count")
-- Marks in one frame merge to the one that refreshes most: a bag mark keeps
-- the entry's cooldown, so it never replaces a pending recharge mark; a
-- recharge mark replaces a pending bag mark and never a use-count mark.
do
    local entry=C.entries.b52
    local charged=C.Index.charged
    charged[#charged+1]=entry
    local reasons,realRefresh={},C.Time.Refresh
    C.Time.Refresh=function(e,reason)
        if e==entry then reasons[#reasons+1]=reason end
        return realRefresh(e,reason)
    end
    local function Marks(first,second)
        for i=#reasons,1,-1 do reasons[i]=nil end
        Fire(first);Fire(second)
        Run()
        return table.concat(reasons,",")
    end
    assert(Registered("SPELL_UPDATE_CHARGES") and Registered("BAG_UPDATE_DELAYED"))
    -- A running recharge swipe (the potion stands in for a charge spell).
    local armed=entry.icon.chargeSet
    entry.icon.chargeSet=true
    local got=Marks("SPELL_UPDATE_CHARGES","BAG_UPDATE_DELAYED")
    assert(got=="recharge","a bag mark replaced a pending recharge mark ("..got..")")
    got=Marks("BAG_UPDATE_DELAYED","SPELL_UPDATE_CHARGES")
    assert(got=="recharge","a recharge mark did not replace a pending bag mark ("..got..")")
    got=Marks("BAG_UPDATE_DELAYED","BAG_UPDATE_DELAYED")
    assert(got=="item","bag contents refresh the entry once ("..got..")")
    C.Time.Refresh=realRefresh
    charged[#charged]=nil
    entry.icon.chargeSet=armed
end
-- SPELL_UPDATE_CHARGES names no spell. While a charge is available (the
-- main swipe is clear) it reads only the recharge swipe and the count, no
-- main cooldown; a pending use-count mark keeps its full refresh.
do
    cdState[101]=nil
    Fire("SPELL_UPDATE_COOLDOWN",101)
    assert(not e11.icon.cdSet,"a charge is available: the main swipe is clear")
    chargeState[101].isActive=true
    local reasons,realRefresh={},C.Time.Refresh
    C.Time.Refresh=function(e,reason)
        if e==e11 then reasons[#reasons+1]=reason end
        return realRefresh(e,reason)
    end
    cdCalls=0
    Fire("SPELL_UPDATE_CHARGES")
    Run()
    assert(table.concat(reasons,",")=="recharge" and cdCalls==0,"a charge event queried the main cooldown ("..cdCalls..")")
    assert(e11.icon.chargeCd.running,"the recharge swipe follows the charge event")
    assert(Registered("SPELL_UPDATE_USES"))
    -- SPELL_UPDATE_USES: the count alone, as Blizzard's viewer does: no
    -- cooldown, charge or duration query, one count write.
    for i=#reasons,1,-1 do reasons[i]=nil end
    cdCalls=0
    local countWrites=e11.icon.count.calls.SetText or 0
    local swipes=e11.icon.cd.calls.SetCooldownFromDurationObject or 0
    Fire("SPELL_UPDATE_USES",101)
    Run()
    assert(table.concat(reasons,",")=="count" and cdCalls==0 and (e11.icon.count.calls.SetText or 0)==countWrites+1
        and (e11.icon.cd.calls.SetCooldownFromDurationObject or 0)==swipes,"a use count refreshed more than the count")
    -- A pending count mark is covered by a recharge refresh in the same frame.
    for i=#reasons,1,-1 do reasons[i]=nil end
    Fire("SPELL_UPDATE_USES",101)
    Fire("SPELL_UPDATE_CHARGES")
    Run()
    assert(table.concat(reasons,",")=="recharge","a count mark replaced a pending recharge mark")
    C.Time.Refresh=realRefresh
end

------------------------------------------------------------------ overrides
assert(Fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",104,1040))
assert(e14.override==1040 and e14.spell==1040)
Run()
cdSpells[1040]=nil
Fire("SPELL_UPDATE_COOLDOWN",1040)
assert(cdSpells[1040]==1,"override IDs route cooldown events")

------------------------------------------------------------------ settings: incremental refresh
local ess=C.views.ess
local styleGen,layoutGen,behaviorGen=ess.styleGen,ess.layoutGen,ess.behaviorGen
config.ess_zoom=12
module:Refresh()
assert(ess.styleGen==styleGen+1 and ess.layoutGen==layoutGen and ess.behaviorGen==behaviorGen,"zoom is style only")
local texCoords=e11.icon.tex.calls.SetTexCoord or 0
Run()
assert((e11.icon.tex.calls.SetTexCoord or 0)==texCoords+1,"style change restyles the icons")
config.ess_size=44
module:Refresh()
assert(ess.styleGen==styleGen+2 and ess.layoutGen==layoutGen+1,"size is layout and style")
Run()
assert(e11.icon.w==44,"icons resized")
config.ess_desat=false
module:Refresh()
assert(ess.behaviorGen==behaviorGen+1)
Run()
-- Unchanged settings: no work at all; a repeated layout pass writes nothing.
before=writes
local queued=#timers
module:Refresh()
assert(writes==before and #timers==queued,"an unchanged refresh did work")
C.Layout.ApplyAll()
assert(writes==before,"a repeated unchanged layout pass made widget calls")

------------------------------------------------------------------ settings: work per setting
-- Each setting marks only its own work (R17): opacity and visibility rules
-- repaint, a position relayouts, aura flow syncs its own containers, a
-- behavior tick re-routes only when routing membership can change.
local function Step(key,value)
    config[key]=value
    ResetCalls()
    module:Refresh()
    Run()
end
local function Structural() return Calls("iconSync")+Calls("auraSync")+Calls("index") end
Step("ess_alpha",60)
assert(Structural()+Calls("layoutAll")+Calls("layout")+Calls("visAll")==0,"an opacity tick did more than repaint")
assert(Calls("vis")==1 and bars.ess.frame.alpha==1,"an opacity tick repaints its own bar (out of combat: its out-of-combat opacity)")
Step("ess_oocAlpha",40)
assert(Structural()+Calls("layoutAll")==0 and Calls("vis")==1 and bars.ess.frame.alpha==.4,"out-of-combat opacity")
Step("ess_oocAlpha",100)
Step("ess_alpha",100)
Step("ess_hideMounted",true)
assert(Structural()+Calls("layoutAll")==0 and Calls("vis")==1,"a visibility rule repaints only")
Step("ess_hideMounted",false)
Step("uti_x",6)
assert(Calls("layoutAll")==1 and Structural()+Calls("vis")==0,"a position change relayouts only")
assert(bars.uti.frame.point[2]==bars.ess.frame and bars.uti.frame.point[4]==6,"an attached bar's x is an offset from its anchor")
Step("uti_x",0)
Step("uti_perRow",6)
assert(Calls("layoutAll")==1 and Structural()==0,"cooldown icons reflow in the layout pass, no structural sync")
Step("uti_perRow",12)
Step("buf_perRow",6)
assert(Calls("auraSync")==1 and Calls("iconSync")==1 and Calls("layoutAll")==1 and Calls("index")==0,
    "aura flow syncs its own bar and nothing else")
Step("buf_perRow",10)
Step("ess_cdAlpha",50)
assert(Structural()+Calls("layoutAll")==0,"a behavior tick outside routing rebuilt structure or routing")
Step("ess_cdAlpha",100)
Step("ess_procGlow",false)
assert(Calls("index")==1 and Calls("iconSync")+Calls("auraSync")==0,"spell alert glows change routing membership")
Step("ess_procGlow",true)
-- The glow look styles aura glows too: the bar's overlays and an aura bar's
-- buttons restyle through their diffed sync, no icon sync or re-route.
for _,key in ipairs({"ess_glowStyle","ess_glowTint","ess_glowColor"}) do
    local was=config[key]
    Step(key,key=="ess_glowStyle" and 3 or key=="ess_glowTint" and not was or "3399ff")
    assert(Calls("auraSync")==1 and Calls("iconSync")+Calls("index")+Calls("layoutAll")==0,
        key.." restyles the bar's aura glows only")
    Step(key,was)
end
local tipGen=C.views.ess.styleGen
Step("ess_tooltips",true)
-- Restyle: icons and the bar's aura overlays (Auras.Restyle is their diffed sync), no icon sync.
assert(C.views.ess.styleGen==tipGen and e11.icon.mouse==true and Calls("iconSync")+Calls("index")==0,
    "tooltips restyle without a generation")
Step("ess_tooltips",false)
assert(e11.icon.mouse==false)
Step("ess_showAura",false)
assert(Calls("iconSync")==1 and Calls("auraSync")==1 and Calls("index")==1,"aura overlays follow showAura")
Step("ess_showAura",true)
Step("ess_strata",4)
assert(bars.ess.frame.strata=="HIGH" and Calls("iconSync")+Calls("index")+Calls("layoutAll")==0 and Calls("vis")==1,
    "the frame layer restyles and repaints")
Step("ess_strata",3)

------------------------------------------------------------------ list and spell data
local lists62={v=1,specs={[62]={ess={"b14","b11"},c1={"s9001","i9002"}},[63]={c1={"s9001","i9002"}}}}
config.listsData=assert(Codec.EncodeLists(lists62))
config.c1_on=true
module:Refresh()
Run()
local c1=assert(C.plans.c1,"custom bar plan")
assert(#c1.entries==2 and c1.entries[1].key=="s9001" and c1.entries[2].key=="i9002","custom list")
assert(C.entries.s9001.icon and C.entries.i9002.icon and bars.c1.shown)
local decoded=C.lists
module:Refresh()
assert(C.lists==decoded,"an unchanged data string is not decoded again")
config.spellsData=assert(Codec.EncodeSpells({v=1,e={b11={readyGlow=true,glowStyle=2}}}))
module:Refresh()
Run()
assert(C.entries.b11.ov.readyGlow==true,"per-spell choices reach entries")

------------------------------------------------------------------ spec change
specIndex=1
assert(Fire("ACTIVE_PLAYER_SPECIALIZATION_CHANGED"))
Run()
assert(C.state.specID==62 and C.state.specTag==81,"spec change")
local order=C.plans.ess.entries
assert(order[1].key=="b14" and order[2].key=="b11" and order[3].key=="b12","per-spec explicit order")
assert(S.CooldownManagerSpec()==62)

------------------------------------------------------------------ MSUF Edit Mode preview
config.c2_on=true
module:Refresh()
Run()
assert(C.plans.c2 and #C.plans.c2.entries==0,"an empty custom bar is empty in live play")
S.editMode=true
module:Refresh()
Run()
assert(C.state.preview and C.Preview.mode=="edit","Edit Mode preview")
assert(C.entries.b13 and C.entries.b13.slot=="ess" and C.entries.b13.icon,"unlearned spells show in the preview")
local sample=C.plans.c2.entries
assert(#sample==3 and sample[1].src=="p" and sample[1].texture==1101,"sample icons on empty bars")
-- A cancelled drag re-applies the saved position.
module:RegisterMovers()
local element=assert(elements.ess,"Essential mover")
assert(element.movePosition({state=element.captureState(),deltaX=40,deltaY=0,phase="drag"}))
assert(bars.ess.frame.point[4]==40,"drag preview moves the bar")
element.restoreState(element.captureState())
module:Refresh()
Run()
assert(bars.ess.frame.point[4]==0,"the saved position returns after a cancelled drag")
S.editMode=false
module:Refresh()
Run()
assert(not C.state.preview and not C.entries.b13 and #C.plans.c2.entries==0,"preview off restores live content")

------------------------------------------------------------------ movers
assert(elements.ess.isEnabled() and elements.uti.isEnabled(),"free bars move, attached bars shift from their anchor")
local utiPoint=bars.uti.frame.point
assert(elements.uti.movePosition({state=elements.uti.captureState(),deltaX=5,deltaY=-3,phase="drag"}),
    "attached bars preview their drag through the place hook")
assert(bars.uti.frame.point[2]==bars.ess.frame and bars.uti.frame.point[4]==(utiPoint and utiPoint[4] or 0)+5,
    "the drag preview keeps the attachment and shifts the offset")
elements.uti.restoreState(elements.uti.captureState())
local controls={}
for _,control in ipairs(elements.ess.extraControls) do controls[control.id]=control end
assert(controls.size and controls.spacing and controls.perRow and controls.size.get()==44,"size, spacing and icons per row")
local barControls={}
for _,control in ipairs(elements.bar.extraControls) do barControls[control.id]=true end
assert(barControls.barWidth and barControls.barHeight,"buff bars size their bars")
-- Every shown bar moves: free bars by their screen position, bars on another
-- bar or on MSUF's frames by their offset. The preview goes through the
-- place hook and writes nothing; the commit writes x/y. Outside MSUF Edit
-- Mode nothing re-applies a preview, so each bar is put back by hand.
C.Layout.ApplyAll()
for _,def in ipairs(Suite.CDM.SLOTS) do
    local slot=def.key
    local mover=assert(elements[slot],slot.." has a mover")
    local bar=bars[slot]
    if C.plans[slot] and bar and bar.shown then
        local k=Suite.CDM.KEYS[slot]
        local x,y=config[k.x],config[k.y]
        assert(mover.isEnabled(),slot.." bar can be moved")
        local x0,y0=bar.frame.point[4],bar.frame.point[5]
        assert(mover.movePosition({state=mover.captureState(),deltaX=6,deltaY=-4,phase="drag"}),slot.." drag preview")
        local p=bar.frame.point
        assert(p[4]==x0+6 and p[5]==y0-4,slot.." preview moves by the drag ("..tostring(p[4]).."/"..tostring(p[5])..")")
        assert(config[k.x]==x and config[k.y]==y,slot.." preview writes nothing")
        assert(mover.movePosition({state=mover.captureState(),deltaX=6,deltaY=-4,phase="commit"}),slot.." commit")
        assert(config[k.x]==x+6 and config[k.y]==y-4,slot.." commit writes x/y")
        config[k.x],config[k.y]=x,y
        C.Layout.ApplyAll()
        assert(bar.frame.point[4]==x0 and bar.frame.point[5]==y0,slot.." goes back to its saved place")
    else
        assert(not mover.isEnabled(),slot.." without a shown bar cannot be moved")
    end
end
module:Refresh()
Run()
-- A bar standing in for its switched-off parent takes that bar's place and
-- has no mover of its own.
config.c2_anchor=Suite.CDM.SLOT_INDEX.c1+1
config.c1_on=false
module:Refresh()
Run()
assert(bars.c2.shown and bars.c2.frame.point[2]==UIParent and not elements.c2.isEnabled(),"a stand-in bar has no mover")
config.c1_on=true
module:Refresh()
Run()
assert(elements.c2.isEnabled() and bars.c2.frame.point[2]==bars.c1.frame,"attached again")
config.c2_anchor=1
module:Refresh()
Run()

------------------------------------------------------------------ options page exports
assert(S.CooldownManagerSetPreview(true))
Run()
assert(C.Preview.mode=="options")
local rows=S.CooldownManagerBarEntries("ess")
assert(rows[1].key=="b14" and rows[2].key=="b11","bar entries in display order")
local meteor
for _,row in ipairs(rows) do if row.key=="b13" then meteor=row end end
assert(meteor and meteor.known==false and meteor.family==1,"unlearned entries are listed")
local catalog=S.CooldownManagerCatalogEntries(1)
local where={}
for _,row in ipairs(catalog) do where[row.key]=row.slot end
assert(where.b21=="uti" and where.b11=="ess","picker rows know their bar")
local rowSpell={}
for _,row in ipairs(catalog) do rowSpell[row.key]=row.spell end
assert(rowSpell.b11==101 and rowSpell.b21==201 and rowSpell.b52==nil,"picker rows carry their spell ID for the ID search")
assert(where.e13==nil and where.e14==nil,"trinket slots are the page's own rows, never listed twice")
local stage=New("Frame",UIParent)
local canvas=assert(S.CooldownManagerRenderPreview(stage,"ess",60,100),"preview canvas")
assert(canvas.parent==stage and canvas.scale and canvas.scale<1,"the canvas shrinks to fit")
local canvasIcon=canvas.icons[1]
local liveCount=C.Icons.Count("ess")
assert(S.CooldownManagerSimulate(true))
local live,ticker=LiveTickers()
assert(live==1 and ticker.interval==10,"one simulation ticker")
assert(C.plans.ess.entries[1].icon.sim and canvasIcon.cd.running,"simulated cooldown on live and canvas icons")
assert(C.Icons.Count("ess")==liveCount,"the canvas never touches live bars")
combat=true
Fire("PLAYER_REGEN_DISABLED")
assert(LiveTickers()==0 and not C.plans.ess.entries[1].icon.sim,"combat stops the simulation")
assert(not S.CooldownManagerSimulate(true),"no simulation in combat")
combat=false
Fire("PLAYER_REGEN_ENABLED")
S.CooldownManagerReleasePreview(stage)
assert(not canvas.shown)
assert(S.CooldownManagerSetPreview(false))
Run()
assert(not C.state.preview)
assert(S.CooldownManagerPlaySound("kit:12345")==true,"sound preview plays")

------------------------------------------------------------------ grow conversion keeps the bar in place
bars.ess.frame.rect={362,500,300,50}
local _,height=C.Layout.Offsets(C.views.ess,3,{})
-- The bar's center sits at (512, 525): 0/141 from the screen center.
local values=assert(S.CooldownManagerConvertGrow("ess",2))
assert(values.ess_grow==2 and values.ess_x==0 and values.ess_y==math.floor(525-384-height/2+.5),
    "grow keeps the center and counts the bottom edge from the screen center")
local probe={}
for key,value in pairs(C.views.ess) do probe[key]=value end
probe.vertical=true
local columnWidth=C.Layout.Offsets(probe,3,{})
values=assert(S.CooldownManagerConvertVertical("ess",true))
assert(values.ess_vertical==true and values.ess_x==math.floor(512-512-columnWidth/2+.5) and values.ess_y==525-384,
    "a vertical bar keeps the center and anchors by its left edge")
assert(C.views.ess.vertical==false and C.views.ess.grow==1,"conversion leaves the live view alone")
bars.ess.frame.rect=nil
assert(S.CooldownManagerConvertGrow("ess",3)==nil,"invalid grow")
-- Attach changes keep the bar on screen: to Free, the x/y of the place it
-- has now; to a bar or unit frame, a zero offset from that anchor.
bars.uti.frame.rect={412,420,200,30}
local utiShown=0
for _,e in ipairs(C.plans.uti.entries) do if e.icon and not e.hidden then utiShown=utiShown+1 end end
local _,utiHeight=C.Layout.Offsets(C.views.uti,utiShown,{})
values=assert(S.CooldownManagerConvertAnchor("uti",1))
assert(values.uti_anchor==1 and values.uti_x==0 and values.uti_y==math.floor(435-384+utiHeight/2+.5),
    "attached to free keeps the bar where it is (center 512/435, top edge from the screen center)")
bars.uti.frame.rect=nil
values=assert(S.CooldownManagerConvertAnchor("c1",2))
assert(KeyList(values)=="c1_anchor,c1_x,c1_y" and values.c1_anchor==2 and values.c1_x==0 and values.c1_y==0,
    "free to attached starts at a zero offset")
values=assert(S.CooldownManagerConvertAnchor("ext",1))
assert(values.ext_anchor==1 and type(values.ext_x)=="number","a bar on the player frame converts to free too")
assert(S.CooldownManagerConvertAnchor("nope",1)==nil and S.CooldownManagerConvertAnchor("ess","1")==nil,"invalid attach")
-- Compact aura bars reserve player entries first and target entries from a
-- new line, so a conversion sizes them as two groups. A centered row that
-- mixes both and fits one line splits at its center (Layout.FixedAuras) and
-- lays out as one line: 2+1 at three per line is one line.
local auraLists=config.listsData
config.listsData=assert(Codec.EncodeLists({v=1,specs={[62]={ess={"b14","b11"},c1={"s9001","i9002"},
    c2={"a401","a301","d302"}},[63]={c1={"s9001","i9002"}}}}))
config.c2_kind,config.c2_perRow=2,3
module:Refresh()
Run()
assert(C.plans.c2.kind==2 and #C.plans.c2.entries==3 and C.entries.d302.unit=="target" and C.entries.a401.unit=="player")
assert(select(3,C.Layout.FixedAuras(C.views.c2,C.plans.c2.entries))==true
    and not C.Layout.FixedAuras(C.views.c2,C.plans.c2.entries),"a centered mixed row on one line splits, compact")
-- 36 px icons, 2 px apart: one line of three cells.
assert(bars.c2.lines1==1 and bars.c2.lines2==1 and bars.c2.frame.w==112 and bars.c2.frame.h==36,
    "three entries at three per line lay out as one line ("..tostring(bars.c2.frame.w).."x"..tostring(bars.c2.frame.h)..")")
bars.c2.frame.rect={400,300,74,74}
values=assert(S.CooldownManagerConvertGrow("c2",2))
assert(values.c2_x==437-512 and values.c2_y==300+37-384-18,"one line holds both groups when they fit ("..tostring(values.c2_y)..")")
-- 2+1 at two per line: the player line, then the target line.
config.c2_perRow=2
module:Refresh()
Run()
assert(select("#",C.Layout.FixedAuras(C.views.c2,C.plans.c2.entries))==3
    and not C.Layout.FixedAuras(C.views.c2,C.plans.c2.entries)
    and not select(3,C.Layout.FixedAuras(C.views.c2,C.plans.c2.entries)),"over two lines the row stays compact, unsplit")
assert(bars.c2.lines1==1 and bars.c2.lines2==1 and bars.c2.frame.w==74 and bars.c2.frame.h==74,"a player line, then a target line")
values=assert(S.CooldownManagerConvertGrow("c2",2))
assert(values.c2_x==437-512 and values.c2_y==300+37-384-37,"aura bars convert with both groups' lines ("..tostring(values.c2_y)..")")
-- Per-spell "Track on" (auraUnit) travels through spellsData: 1 automatic
-- (harmful aura IDs on the target, the rest on the player), 2 the player,
-- 3 the target, 4 both ("both" counts in the player part). A change resolves
-- the entry's unit again, marks it aura-touched and resyncs its bar: the
-- entry moves between the player and the target container, the target part
-- moves by the player lines, and the layout and conversion follow.
do (function()
    local keptSpells=config.spellsData
    config.listsData=assert(Codec.EncodeLists({v=1,specs={[62]={ess={"b14","b11"},c1={"s9001","i9002"},
        c2={"a401","a301","b32","d303"}},[63]={c1={"s9001","i9002"}}}}))
    module:Refresh()
    Run()
    local b32=C.entries.b32
    assert(#C.plans.c2.entries==4 and b32.slot=="c2" and b32.unit=="target" and C.Auras.TargetRow(b32)
        and b32.ov.auraUnit==nil,"automatic: Ignite (harmful) tracks on the target")
    -- Automatic: any harmful aura ID decides (base, override, tooltip or
    -- linked); Blizzard's selfAura flag does not. Cooldowns without an aura
    -- track nothing. Probed through Describe on records of our own.
    local records=C.Catalog.records
    local probes={
        {spell=301,linked={3011},selfAura=true,unit="target"},{spell=301,tooltip=302,unit="target"},
        {spell=301,override=302,unit="target"},{spell=301,unit="player"},{spell=302,family=1,unit="target"},
        {spell=302,family=1,hasAura=false},
    }
    for i=1,#probes do
        local probe,id=probes[i],9900+i
        records[id]={id=id,key="b"..id,spell=probe.spell,override=probe.override,tooltip=probe.tooltip,
            linked=probe.linked or C.EMPTY,family=probe.family or 2,hasAura=probe.hasAura~=false,
            selfAura=probe.selfAura==true,known=true,charges=false}
        local d=assert(C.Resolve.Describe("b"..id,{}),"probe "..i)
        records[id]=nil
        assert(d.unit==probe.unit,"automatic unit of probe "..i..": "..tostring(d.unit))
    end
    assert(C_Spell.harmChecks[3011]==1 and C_Spell.harmChecks[302]==1 and C_Spell.harmChecks[301]==1,
        "probes reuse the cached answers")
    local _,h,sp=C.Layout.Metrics(C.views.c2)
    -- Compact containers flow from the bar's aura host (its frame without one).
    local frame=bars.c2.frame
    local host=bars.c2.auraHost or frame
    -- The live (shown, enabled) containers of c2 by unit.
    local function Live()
        local found={}
        for i=1,#all do
            local w=all[i]
            if w.kind=="AuraContainer" and (w.parent==host or w.parent==frame) and w.shown and w.enabled and w.unit then
                assert(not found[w.unit],"two live "..w.unit.." containers on one bar")
                found[w.unit]=w
            end
        end
        return found.player,found.target
    end
    local function Track(value)
        local e={b11={readyGlow=true,glowStyle=2}}
        if value~=nil then e.b32={auraUnit=value} end
        config.spellsData=assert(Codec.EncodeSpells({v=1,e=e}))
        ResetCalls()
        module:Refresh()
        Run()
    end
    -- value, unit, player lines before the target part (2 per line: a401,
    -- a301 and b32 unless b32 sits in the target part, which d303 holds
    -- anyway), changed from the step before.
    local steps={
        {4,"both",2,true},{2,"player",2,true},{3,"target",1,true},{1,"target",1,false},{nil,"target",1,false},
        {2,"player",2,true},{nil,"target",1,true},
    }
    for i=1,#steps do
        local value,unit,lines,changed=steps[i][1],steps[i][2],steps[i][3],steps[i][4]
        local label="Track on "..tostring(value)
        local _,oldTarget=Live()
        local placed=oldTarget and oldTarget.calls.SetPoint or 0
        Track(value)
        assert(Codec.DecodeSpells(config.spellsData).e.b32==nil and value==nil
            or Codec.DecodeSpells(config.spellsData).e.b32.auraUnit==value,label..": the choice survives the data string")
        assert(C.spells.e.b32==nil and value==nil or C.spells.e.b32.auraUnit==value,label..": decoded on Refresh")
        assert(C.entries.b32==b32 and b32.ov.auraUnit==value and b32.unit==unit,
            label..": the entry tracks on "..unit.." ("..tostring(b32.unit)..")")
        assert(C.Auras.TargetRow(b32)==(unit=="target"),label..": only target entries sit in the target part")
        assert((C.Resolve.auraTouched[b32]==true)==changed,label..": aura-touched exactly when the unit changed")
        assert(Calls("resolve")==1 and Calls("auraSync")>=1,label..": resolved once, aura bars synced")
        local player,target=Live()
        assert(player and target,label..": c2 keeps its player and target containers (d303)")
        assert(player:Tracks(302)==(unit~="target") and target:Tracks(302)==(unit~="player"),
            label..": Ignite in the "..unit.." container(s)")
        assert(player:Tracks(401) and player:Tracks(301) and target:Tracks(303) and not player:Tracks(303)
            and not target:Tracks(401),label..": the other entries stay where they were")
        local p=target.point
        assert(p[2]==host and p[1]==p[3] and p[4]==0 and math.abs(p[5]+lines*(h+sp))<1e-6,
            label..": the target part starts after "..lines.." player line(s) ("..tostring(p[5])..")")
        if not changed then
            assert(target==oldTarget and target.calls.SetPoint==placed,label..": an unchanged unit places nothing again")
        end
        assert(bars.c2.lines1==lines and bars.c2.lines2==1 and math.abs(bars.c2.frame.h-((lines+1)*h+lines*sp))<1e-6,
            label..": the layout follows ("..tostring(bars.c2.frame.h)..")")
        local conv=assert(S.CooldownManagerConvertGrow("c2",2))
        local depth=(lines+1)*h+lines*sp
        assert(conv.c2_y==math.floor(300+37-384-depth/2+.5),
            label..": the conversion sizes "..(lines+1).." lines ("..tostring(conv.c2_y)..")")
    end
    -- Values outside 1..4 never reach the data string: automatic.
    for _,bad in ipairs({0,5,2.5,"4",true}) do
        Track(bad)
        assert(Codec.DecodeSpells(config.spellsData).e.b32==nil and b32.ov.auraUnit==nil and b32.unit=="target",
            "an invalid Track on value is dropped ("..tostring(bad)..")")
    end
    -- One rule places aura bars (Layout.FixedAuras, shared by the aura
    -- layer, the layout and the conversions). Player and target auras live
    -- in two containers that cannot interleave, so a column that mixes both
    -- (a vertical bar whose entries fit one line, or one icon per line)
    -- keeps every entry in its own cell in the bar's order. A mixed row that
    -- fits one line is fixed and ordered when start or end aligned; centered
    -- it splits at its center: player auras end there, target auras start
    -- there, both compact and growing from the middle. Every other compact
    -- bar keeps the target part the reserved player lines further, from the
    -- alignment point. Containers anchor only to our own frames, never to
    -- one another. Ignite (b32, the target) sits between two player buffs.
    Widget.InitSlots(true)
    config.listsData=assert(Codec.EncodeLists({v=1,specs={[62]={ess={"b14","b11"},c1={"s9001","i9002"},
        c2={"a401","b32","a301","d303"}},[63]={c1={"s9001","i9002"}}}}))
    local K2=Suite.CDM.KEYS.c2
    local cw=C.Layout.Metrics(C.views.c2)
    local dx,dy=cw+sp,h+sp
    local cells=bars.c2.cells
    -- Settings (all of them each time), Track on for Ignite; the shared rule's answer.
    local function Bar(values,auraUnit)
        for suffix,value in pairs(values) do config[assert(K2[suffix],suffix)]=value end
        Track(auraUnit)
        return C.Layout.FixedAuras(C.views.c2,C.plans.c2.entries)
    end
    local function Slots(container)
        for _,group in pairs(container.groups or {}) do if group.slot then return true end end
        return false
    end
    -- The cell the on slot for `id` follows (its button's SetAllPoints).
    local function SlotCell(container,id)
        for _,group in pairs(container.groups or {}) do
            if group.slot and group.on and group.ids and group.ids[id] then
                local p=group.button and group.button.point
                return p and p[1]=="ALL" and p[2] or nil
            end
        end
    end
    -- Cells by plan position, in columns/lines of cw+sp and h+sp.
    local function CellsAt(label,spots)
        for i=1,#spots do
            local cell=cells[i]
            local p=cell and cell.point
            assert(p and cell.shown and p[1]=="TOPLEFT" and p[2]==host and p[3]=="TOPLEFT"
                and math.abs(p[4]-spots[i][1]*dx)<1e-6 and math.abs(p[5]+spots[i][2]*dy)<1e-6,
                label..": cell "..i.." sits at "..tostring(p and p[4]).."/"..tostring(p and p[5]))
        end
    end
    local function Size(label,width,height)
        local f=bars.c2.frame
        assert(math.abs(f.w-width)<1e-6 and math.abs(f.h-height)<1e-6,
            label..": the layout draws "..width.."x"..height.." ("..tostring(f.w).."x"..tostring(f.h)..")")
    end
    -- Fixed containers cover the bar from its top left (the aura host, or
    -- the bar frame of the same rectangle when the first sync after a kind
    -- change ran before the layout made the host); their slots follow cells.
    local function Fixed(label,container)
        local p=container and container.point
        assert(p and Slots(container) and p[1]=="TOPLEFT" and (p[2]==host or p[2]==frame) and p[3]=="TOPLEFT"
            and p[4]==0 and p[5]==0,label..": a fixed container covers the bar")
    end
    local function Compact(label,container,point,rel,x,y)
        local p=container and container.point
        assert(p and not Slots(container) and p[1]==point and p[2]==host and p[3]==rel
            and math.abs(p[4]-x)<1e-6 and math.abs(p[5]-y)<1e-6,
            label..": a compact container at "..point.." of the host's "..rel.." "..x.."/"..y.." ("
            ..tostring(p and p[1]).." "..tostring(p and p[3]).." "..tostring(p and p[4]).."/"..tostring(p and p[5])..")")
    end
    -- Every aura container (every bar) on our own bar frames or aura hosts.
    local function OwnAnchors(label)
        local own={}
        for _,bar in pairs(C.bars) do
            own[bar.frame]=true
            if bar.auraHost then own[bar.auraHost]=true end
        end
        for i=1,#all do
            local w=all[i]
            if w.kind=="AuraContainer" and w.point then
                assert(own[w.point[2]] and w.point[2].kind~="AuraContainer",
                    label..": an aura container is anchored to a frame that is not ours")
            end
        end
    end
    -- The controller's extent (Convert) sizes the bar as the layout drew it:
    -- a conversion to the current grow keeps the frame's growth edge.
    local function Extent(label)
        local f=bars.c2.frame
        local conv=assert(S.CooldownManagerConvertGrow("c2",C.views.c2.grow==2 and 2 or 1))
        local point=C.Layout.Point(C.views.c2)
        local x,y=437-512,337-384
        if point=="TOP" then y=y+f.h/2 elseif point=="BOTTOM" then y=y-f.h/2
        elseif point=="LEFT" then x=x-f.w/2 else x=x+f.w/2 end
        assert(conv.c2_x==math.floor(x+.5) and conv.c2_y==math.floor(y+.5),
            label..": the conversion sizes the bar as laid out ("..tostring(conv.c2_x).."/"..tostring(conv.c2_y)..")")
    end
    local function Check(label)
        OwnAnchors(label)
        Extent(label)
    end
    local line4=4*cw+3*sp
    -- A vertical bar whose entries fit one column: fixed places in the bar's order.
    local fixed,ordered,split=Bar({vertical=true,align=1,grow=1,perRow=4,keepSlots=false})
    assert(fixed==true and ordered==true and split==false,"a mixed column is fixed and ordered")
    local player,target=Live()
    Fixed("column",player);Fixed("column",target)
    CellsAt("column",{{0,0},{0,1},{0,2},{0,3}})
    Size("column",cw,4*h+3*sp)
    assert(SlotCell(player,401)==cells[1] and SlotCell(target,302)==cells[2] and SlotCell(player,301)==cells[3]
        and SlotCell(target,303)==cells[4] and not SlotCell(player,302) and not SlotCell(target,401),
        "column: each slot follows the cell of its entry, Ignite between the player buffs")
    Check("column")
    -- Both: Ignite's player and target slots share its cell.
    fixed,ordered,split=Bar({vertical=true,align=1,grow=1,perRow=4,keepSlots=false},4)
    player,target=Live()
    assert(fixed==true and ordered==true and split==false and b32.unit=="both" and not C.Auras.TargetRow(b32),
        "a column with a both entry stays fixed and ordered")
    assert(SlotCell(player,302)==cells[2] and SlotCell(target,302)==cells[2] and SlotCell(player,301)==cells[3],
        "both: the player and the target slot share Ignite's cell")
    CellsAt("both",{{0,0},{0,1},{0,2},{0,3}})
    Check("both")
    -- A vertical bar that needs two columns stays compact: the target part
    -- starts the reserved player columns further, from the left edge.
    fixed,ordered,split=Bar({vertical=true,align=1,grow=1,perRow=2,keepSlots=false})
    assert(not fixed and not ordered and not split,"a mixed column that needs two columns is compact")
    player,target=Live()
    Compact("two columns",player,"LEFT","LEFT",0,0)
    Compact("two columns",target,"LEFT","LEFT",dx,0)
    assert(player:Tracks(401) and player:Tracks(301) and target:Tracks(302) and target:Tracks(303),"two columns: tracking")
    Size("two columns",2*cw+sp,2*h+sp)
    Check("two columns")
    -- One icon per line on a horizontal bar is a column too.
    fixed,ordered,split=Bar({vertical=false,align=1,grow=1,perRow=1,keepSlots=false})
    assert(fixed==true and ordered==true and split==false,"one icon per line is fixed and ordered")
    player,target=Live()
    Fixed("one per line",player);Fixed("one per line",target)
    CellsAt("one per line",{{0,0},{0,1},{0,2},{0,3}})
    Size("one per line",cw,4*h+3*sp)
    assert(SlotCell(player,401)==cells[1] and SlotCell(target,302)==cells[2] and SlotCell(player,301)==cells[3]
        and SlotCell(target,303)==cells[4],"one per line: slots follow their cells")
    Check("one per line")
    -- A centered horizontal row over two lines stays compact from the top
    -- center, the target part one player line further.
    fixed,ordered,split=Bar({vertical=false,align=1,grow=1,perRow=2,keepSlots=false})
    assert(not fixed and not ordered and not split,"a centered mixed row over two lines is compact")
    player,target=Live()
    Compact("two lines",player,"TOP","TOP",0,0)
    Compact("two lines",target,"TOP","TOP",0,-dy)
    Size("two lines",2*cw+sp,2*h+sp)
    Check("two lines")
    -- Keep buffs in fixed places: fixed; ordered only on one line.
    fixed,ordered,split=Bar({vertical=false,align=1,grow=1,perRow=2,keepSlots=true})
    assert(fixed==true and ordered==false and split==false,"keepSlots over two lines: fixed, not ordered")
    player,target=Live()
    Fixed("keepSlots, two lines",player);Fixed("keepSlots, two lines",target)
    CellsAt("keepSlots, two lines",{{0,0},{0,1},{1,0},{1,1}})
    Size("keepSlots, two lines",2*cw+sp,2*h+sp)
    assert(SlotCell(player,401)==cells[1] and SlotCell(target,302)==cells[2] and SlotCell(player,301)==cells[3]
        and SlotCell(target,303)==cells[4],"keepSlots, two lines: player cells first, target cells from the next line")
    Check("keepSlots, two lines")
    fixed,ordered,split=Bar({vertical=false,align=1,grow=1,perRow=4,keepSlots=true})
    assert(fixed==true and ordered==true and split==false,"keepSlots on one line: fixed and ordered")
    Fixed("keepSlots, one line",(Live()))
    CellsAt("keepSlots, one line",{{0,0},{1,0},{2,0},{3,0}})
    Size("keepSlots, one line",line4,h)
    Check("keepSlots, one line")
    -- A start or end aligned mixed row on one line: fixed and ordered.
    for align=2,3 do
        local label="aligned "..align
        fixed,ordered,split=Bar({vertical=false,align=align,grow=1,perRow=4,keepSlots=false})
        assert(fixed==true and ordered==true and split==false,label..": a mixed row on one line is fixed and ordered")
        player,target=Live()
        Fixed(label,player);Fixed(label,target)
        CellsAt(label,{{0,0},{1,0},{2,0},{3,0}})
        assert(SlotCell(player,401)==cells[1] and SlotCell(target,302)==cells[2] and SlotCell(player,301)==cells[3]
            and SlotCell(target,303)==cells[4],label..": slots in the bar's order")
        Size(label,line4,h)
        Check(label)
    end
    -- Centered on one line: split at the center, compact on both sides. The
    -- player container ends there by its top right corner, the target
    -- container starts there by its top left corner, one spacing apart:
    -- no reserved gap. The footprint is one line; cells sit in plan order.
    fixed,ordered,split=Bar({vertical=false,align=1,grow=1,perRow=4,keepSlots=false})
    assert(fixed==false and ordered==false and split==true,"a centered mixed row on one line splits at its center")
    player,target=Live()
    Compact("split",player,"TOPRIGHT","TOP",-sp/2,0)
    Compact("split",target,"TOPLEFT","TOP",sp/2,0)
    assert(math.abs(target.point[4]-player.point[4]-sp)<1e-6,"split: the two halves are one spacing apart")
    assert(player:Tracks(401) and player:Tracks(301) and target:Tracks(302) and target:Tracks(303)
        and not player:Tracks(302),"split: buffs on the player side, Ignite on the target side")
    CellsAt("split",{{0,0},{1,0},{2,0},{3,0}})
    Size("split",line4,h)
    Check("split")
    -- A vertical conversion of the split row sizes one column (fixed there).
    local values=assert(S.CooldownManagerConvertVertical("c2",true))
    assert(values.c2_vertical==true and values.c2_x==math.floor(437-512-cw/2+.5) and values.c2_y==337-384,
        "a split row converted to vertical sizes one column ("..tostring(values.c2_x)..")")
    assert(C.views.c2.vertical==false,"the conversion leaves the view alone")
    -- Growing up: the halves hang from the bottom center.
    fixed,ordered,split=Bar({vertical=false,align=1,grow=2,perRow=4,keepSlots=false})
    assert(split==true and not fixed,"a centered mixed row growing up splits too")
    player,target=Live()
    Compact("split up",player,"BOTTOMRIGHT","BOTTOM",-sp/2,0)
    Compact("split up",target,"BOTTOMLEFT","BOTTOM",sp/2,0)
    Size("split up",line4,h)
    Check("split up")
    -- Both: Ignite on both sides of the split.
    fixed,ordered,split=Bar({vertical=false,align=1,grow=1,perRow=4,keepSlots=false},4)
    assert(split==true and not fixed,"a split row with a both entry stays split")
    player,target=Live()
    Compact("split, both",player,"TOPRIGHT","TOP",-sp/2,0)
    Compact("split, both",target,"TOPLEFT","TOP",sp/2,0)
    assert(player:Tracks(302) and target:Tracks(302),"split, both: Ignite on both sides")
    Check("split, both")
    -- Without target entries nothing mixes: one compact player container
    -- from the top center. Me takes Ignite off the target container.
    config.listsData=assert(Codec.EncodeLists({v=1,specs={[62]={ess={"b14","b11"},c1={"s9001","i9002"},
        c2={"a401","b32"}},[63]={c1={"s9001","i9002"}}}}))
    fixed,ordered,split=Bar({vertical=false,align=1,grow=1,perRow=4,keepSlots=false},2)
    assert(not fixed and not ordered and not split,"a row of player entries is compact")
    player,target=Live()
    assert(#C.plans.c2.entries==2 and player and player:Tracks(302) and player:Tracks(401) and not target,
        "Me: one player container, no target container")
    Compact("player row",player,"TOP","TOP",0,0)
    Size("player row",2*cw+sp,h)
    Check("player row")
    fixed,ordered,split=Bar({vertical=false,align=1,grow=1,perRow=4,keepSlots=false},3)
    player,target=Live()
    assert(split==true and player and target and target:Tracks(302) and not player:Tracks(302)
        and C.Resolve.auraTouched[b32],"Target: Ignite moves to the target side of the split")
    Compact("buff and target aura",player,"TOPRIGHT","TOP",-sp/2,0)
    Compact("buff and target aura",target,"TOPLEFT","TOP",sp/2,0)
    Size("buff and target aura",2*cw+sp,h)
    Check("buff and target aura")
    -- Vertical: one column, the target aura in the cell after the buff
    -- (never in a column beside it, Deathstalker's Mark).
    fixed,ordered,split=Bar({vertical=true,align=1,grow=1,perRow=4,keepSlots=false},3)
    assert(fixed==true and ordered==true and split==false,"a buff over a target aura is one fixed column")
    player,target=Live()
    Fixed("buff over target aura",player);Fixed("buff over target aura",target)
    CellsAt("buff over target aura",{{0,0},{0,1}})
    assert(SlotCell(player,401)==cells[1] and SlotCell(target,302)==cells[2],"the target aura follows the second cell")
    Size("buff over target aura",cw,2*h+sp)
    Check("buff over target aura")
    Widget.InitSlots(false)
    for suffix,value in pairs({vertical=false,align=1,grow=1,keepSlots=false}) do config[K2[suffix]]=value end
    config.spellsData=keptSpells
    module:Refresh()
    Run()
    assert(C.entries.b32.unit=="target" and C.entries.b32.ov.auraUnit==nil,"back to automatic")
end)() end
bars.c2.frame.rect=nil
config.listsData,config.c2_kind,config.c2_perRow=auraLists,1,10
module:Refresh()
Run()
assert(C.plans.c2.kind==1 and #C.plans.c2.entries==0)

------------------------------------------------------------------ combat deferrals
local function Size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
combat=true
Fire("PLAYER_REGEN_DISABLED")
-- A catalog event that changes nothing passes nothing on: no bar syncs,
-- relayouts or repaints, nothing is routed again or parked for combat end.
ResetCalls()
Fire("SPELLS_CHANGED")
Run()
assert(Calls("catalog")==1 and Calls("resolve")==1,"the catalog event rebuilds and resolves")
assert(Structural()+Calls("layoutAll")+Calls("layout")+Calls("visAll")+Calls("vis")==0,
    "an unchanged resolve synced, routed, laid out or repainted bars")
assert(Calls("keysRebuild")+Calls("keysRefresh")+Calls("keysRequest")==0 and next(C.Auras.pending)==nil,
    "an unchanged resolve touched keybinds or parked aura work")
-- One bar's content changes: that bar alone syncs and lays out; its aura
-- containers wait for combat to end. Category sources are not read in combat.
C.entries.b52.catSpell=nil
seeds=0
sets[2]={31,32,33}
Info(33,303,2,{selfAura=true,hasAura=true})
ResetCalls()
Fire("SPELLS_CHANGED")
Run()
assert(C.entries.b33 and C.entries.b33.slot=="buf","catalog changes resolve in combat")
assert(C.Auras.pending.buf and Size(C.Auras.pending)==1,"only the changed bar's aura structure waits for combat to end")
assert(Calls("iconSync")==1 and Calls("auraSync")==1 and Calls("index")==1 and Calls("layoutAll")==0 and Calls("vis")==1,
    "the changed bar alone syncs, lays out and repaints")
assert(seeds==0 and C.entries.b52.catSpell==nil,"no category source is read in combat")
-- An override in combat refreshes its entry and routes the new ID at once;
-- the routing index is rebuilt once combat ends.
ResetCalls()
assert(Fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",101,1012))
Run()
assert(e11.override==1012 and e11.spell==1012 and Calls("index")==0,"no routing rebuild in combat")
cdSpells[1012]=nil
Fire("SPELL_UPDATE_COOLDOWN",1012)
assert(cdSpells[1012]==1,"the new override routes cooldown events at once")
combat=false
Fire("PLAYER_REGEN_ENABLED")
Run()
assert(not C.Auras.pending.buf,"combat end flushes aura structure")
assert(Calls("index")==1,"combat end rebuilds the routing index once")
assert(seeds>=1 and C.entries.b52.catSpell==431932,"category entries are seeded after combat")
Fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",101,nil)
Run()
assert(e11.spell==101 and e11.override==nil)
-- Blizzard's layout callbacks rebuild only when the saved layout string moved.
local pendingChanges=registry["CooldownViewerSettings.OnPendingChanges"].fn
ResetCalls()
pendingChanges()
assert(PendingTimers()==0,"an unchanged Blizzard layout rebuilds nothing")
local layoutData=""
C_CooldownViewer.GetLayoutData=function() return layoutData end
layoutData="1|saved"
pendingChanges()
Run()
assert(Calls("catalog")==1,"a saved Blizzard layout rebuilds the catalog")
registry["CooldownViewerSettings.OnHide"].fn()
assert(PendingTimers()==0,"the same layout string is read once")
layoutData=""
pendingChanges()
Run()
assert(Calls("catalog")==2)

------------------------------------------------------------------ pixel scale
physical[2]=864
assert(Fire("UI_SCALE_CHANGED"))
Run()
local px=768/864
assert(math.abs(C.state.px-px)<1e-9,"pixel scale recomputed")
assert(math.abs(e11.icon.w-math.floor(44/px+.5)*px)<1e-9,"icons snap to the new pixel grid")

------------------------------------------------------------------ keybinds
config.ess_keybind=true
module:Refresh()
Run()
assert(Registered("UPDATE_BINDINGS") and Registered("ACTIONBAR_SLOT_CHANGED"),"keybinds on register the binding events")
assert(e12.icon.lastKey=="S2","keybind text on the Essential bar")
assert(PendingTimers()==0,"turning keybinds on leaves no timer behind")
bindings.ACTIONBUTTON2="CTRL-F"
assert(Fire("UPDATE_BINDINGS"))
Fire("ACTIONBAR_SLOT_CHANGED",2)
assert(PendingTimers()==1,"binding events coalesce")
Run(.1)
assert(e12.icon.lastKey=="S2")
Run(.2)
assert(e12.icon.lastKey=="CF","keybind text follows binding changes")
-- A resolve that brings a new spell pushes key texts through the coalesced
-- request (cached texts, the new spell looked up once), never a rebuild.
actionSlots[9001]={3}
bindings.ACTIONBUTTON3="Q"
local keyedLists=config.listsData
config.listsData=assert(Codec.EncodeLists({v=1,specs={[62]={ess={"b14","b11","s9001"},c1={"i9002"}},
    [63]={c1={"s9001","i9002"}}}}))
ResetCalls()
module:Refresh()
Run()
local keyed=assert(C.entries.s9001)
assert(keyed.slot=="ess" and keyed.icon and (keyed.icon.lastKey or "")=="","the new icon waits for its key text")
assert(Calls("keysRebuild")+Calls("keysRefresh")==0 and Calls("keysRequest")==1 and PendingTimers()==1,
    "a resolve requests key texts once, coalesced")
Run(.2)
assert(keyed.icon.lastKey=="Q" and e12.icon.lastKey=="CF","key texts arrive 0.2 s later")
assert(Calls("keysRefresh")==1 and Calls("keysRebuild")==0,"a resolve keeps the key cache")
config.listsData=keyedLists
module:Refresh()
Run()
Run(.2)
assert(C.entries.s9001.slot=="c1" and PendingTimers()==0)
-- The trinket on Essential sits on the bars as an item action, which
-- FindSpellActionButtons never matches: its key comes from a scan of the
-- action slots by item ID, in the same key preference, cached per item.
local actionItems,infoCalls={[5]=7777,[64]=7777},0
GetActionInfo=function(slot)
    infoCalls=infoCalls+1
    local item=actionItems[slot]
    if item then return "item",item end
end
bindings.ACTIONBUTTON5,bindings.MULTIACTIONBAR1BUTTON4="E","ALT-4"
assert(Fire("ACTIONBAR_SLOT_CHANGED",5))
Run(.2)
local trinketIcon=assert(C.entries.b71.icon)
assert(trinketIcon.lastKey=="E" and e12.icon.lastKey=="CF","the trinket takes the key of its item action (main bar first)")
local scans=infoCalls
assert(scans>0)
C.Keybinds.Request(false)
Run(.2)
assert(infoCalls==scans and trinketIcon.lastKey=="E","a content refresh reuses the item's cached key")
actionItems[5]=nil
assert(Fire("ACTIONBAR_SLOT_CHANGED",5))
Run(.2)
assert(infoCalls>scans and trinketIcon.lastKey=="A4","moving the item action rescans")
actionItems[64]=nil
assert(Fire("UPDATE_BINDINGS"))
Run(.2)
assert(trinketIcon.lastKey=="","no key without an item action")
GetActionInfo=nil
bindings.ACTIONBUTTON5,bindings.MULTIACTIONBAR1BUTTON4=nil,nil

------------------------------------------------------------------ assisted combat
config.ess_assist=true
cvars.assistedCombatHighlight="1"
module:Refresh()
Run()
local highlight=assert(registry["AssistedCombatManager.OnAssistedHighlightSpellChange"],"Blizzard's highlight callback")
AssistedCombatManager.lastNextCastSpellID=101
highlight.fn()
assert(e11.icon.antsOn,"assisted suggestion highlighted")
cvars.assistedCombatHighlight="0"
nextCast=102
combat=true
Fire("PLAYER_REGEN_DISABLED")
live,ticker=LiveTickers()
assert(live==1 and ticker.interval==.2,"poll only in combat without Blizzard's highlight")
assert(e12.icon.antsOn and not e11.icon.antsOn)
combat=false
Fire("PLAYER_REGEN_ENABLED")
assert(LiveTickers()==0 and not e12.icon.antsOn,"poll stops after combat")

------------------------------------------------------------------ invisible mode and MSUF promotion
config.blizzard=2
module:Refresh()
Run()
assert(cvars.cooldownViewerEnabled=="1" and essViewer.alpha==0 and #hooks>=2,"mode 2 keeps Blizzard's bars running invisibly")
assert(S.CooldownManagerStatus():find("invisibly",1,true))
config.blizzard=1
module:Refresh()
assert(cvars.cooldownViewerEnabled=="0" and essViewer.alpha==1,"back to mode 1")
MSUF_DB={general={anchorToCooldown=true}}
module:Refresh()
assert(cvars.cooldownViewerEnabled=="1" and essViewer.alpha==0,"MSUF anchored to the viewers promotes mode 1")
assert(S.CooldownManagerStatus():find("MSUF",1,true),"status explains the promotion")
-- An MSUF that knows our bars follows the Essential bar itself: no promotion.
MSUF_GetSuiteCooldownAnchor=function() return bars.ess.anchorFrame end
module:Refresh()
assert(C.Native.Mode()==1 and select(2,C.Native.Mode())==nil,"MSUF following our bars keeps mode 1")
assert(cvars.cooldownViewerEnabled=="0" and essViewer.alpha==1,"Blizzard's bars go off again")
assert(S.CooldownManagerStatus():find("off",1,true) and not S.CooldownManagerStatus():find("MSUF",1,true),
    "status names no promotion")
config.blizzard=2
module:Refresh()
assert(C.Native.Mode()==2 and cvars.cooldownViewerEnabled=="1" and essViewer.alpha==0,"an explicit mode 2 still applies")
config.blizzard=1
module:Refresh()
assert(cvars.cooldownViewerEnabled=="0" and essViewer.alpha==1)
MSUF_GetSuiteCooldownAnchor=nil
module:Refresh()
assert(C.Native.Mode()==2 and cvars.cooldownViewerEnabled=="1","an older MSUF is promoted again")
MSUF_DB=nil
module:Refresh()
Run()
assert(C.Native.Mode()==1 and cvars.cooldownViewerEnabled=="0" and essViewer.alpha==1,"back to mode 1 without MSUF")

------------------------------------------------------------------ riding Blizzard's Essential bar
-- MSUF without the suite provider follows Blizzard's invisible Essential
-- bar, so ours sits on it: x/y turn into an offset from it at once (this
-- flush already places the bar) and are saved a frame later. Switching back
-- turns them into the screen position the bar has then; switching back
-- before the save keeps the saved values.
local savedX,savedY=config.ess_x,config.ess_y
essViewer.rect={362,478,300,50}
config.blizzard=2
MSUF_DB={general={anchorToCooldown=true}}
module:Refresh()
assert(C.Native.FollowViewer() and C.views.ess.x==0 and C.views.ess.y==0 and config.essOnViewer==false,
    "the view takes the offset at once")
Run()
assert(config.essOnViewer==true and config.ess_x==0 and config.ess_y==0,"the offset is saved a frame later")
local ride=bars.ess.frame.point
assert(ride[1]=="TOP" and ride[2]==UIParent and ride[3]=="BOTTOMLEFT" and math.abs(ride[4]-512)<1e-6
    and math.abs(ride[5]-528)<1e-6,"the growth edge sits on the viewer's top edge")
module:Refresh()
Run()
assert(PendingTimers()==0,"the switch is written once")
bars.ess.frame.rect={362,489,300,36}
local shownIcons=0
for _,e in ipairs(C.plans.ess.entries) do if e.icon and not e.hidden then shownIcons=shownIcons+1 end end
local _,essHeight=C.Layout.Offsets(C.views.ess,shownIcons,{})
local wantY=math.floor(489+18-384+essHeight/2+.5)
MSUF_DB=nil
module:Refresh()
assert(not C.Native.FollowViewer() and C.views.ess.x==0 and C.views.ess.y==wantY,"the view takes the screen position at once")
Run()
assert(config.essOnViewer==false and config.ess_x==0 and config.ess_y==wantY,"the screen position is saved")
assert(bars.ess.frame.point[2]==UIParent and bars.ess.frame.point[3]=="CENTER","free again")
bars.ess.frame.rect=nil
MSUF_DB={general={anchorToCooldown=true}}
module:Refresh()
assert(C.views.ess.y==0)
MSUF_DB=nil
module:Refresh()
assert(C.views.ess.x==0 and C.views.ess.y==wantY,"switching back before the save restores the saved position")
Run()
assert(config.essOnViewer==false and config.ess_y==wantY and PendingTimers()==0,"nothing was written")
-- Only the layout's reading counts (Layout.RidesViewer). Attached, x/y are
-- an attach offset: MSUF following Blizzard's bar or letting go of it
-- leaves them alone.
local PLAYER=#Suite.CDM.SLOTS+2
local function Apply(values)
    for key,value in pairs(values) do config[key]=value end
    module:Refresh()
    Run()
end
Apply({ess_anchor=PLAYER,ess_x=0,ess_y=10})
MSUF_DB={general={anchorToCooldown=true}}
module:Refresh()
Run()
assert(C.Native.FollowViewer() and not C.Layout.RidesViewer("ess"),"attached: following Blizzard's bar, not riding it")
assert(config.ess_x==0 and config.ess_y==10 and config.essOnViewer==false and PendingTimers()==0,
    "an attach offset survives MSUF following Blizzard's bar")
-- Turning free while MSUF follows Blizzard's bar: the bar keeps its place
-- as an offset from Blizzard's bar (top edge 528, ours at 525), and the
-- flag travels with the values, so nothing is converted afterwards.
bars.ess.frame.rect={362,489,300,36}
local toFree=assert(S.CooldownManagerConvertAnchor("ess",1))
assert(toFree.ess_anchor==1 and toFree.ess_x==0 and toFree.ess_y==-3 and toFree.essOnViewer==true,
    "turning free while riding gives an offset from Blizzard's bar ("..tostring(toFree.ess_y)..")")
Apply(toFree)
assert(C.Layout.RidesViewer("ess") and config.ess_y==-3 and config.essOnViewer==true and PendingTimers()==0,
    "the converted values stay as they are")
-- Blizzard's top edge and the offset both snap to the pixel grid.
local unit=C.Layout.PixelScale()
local function Snap(value) return math.floor(value/unit+.5)*unit end
local ride2=bars.ess.frame.point
assert(ride2[1]=="TOP" and ride2[3]=="BOTTOMLEFT" and math.abs(ride2[5]-(Snap(528)+Snap(-3)))<1e-6,
    "the bar kept its place")
local toFrame=assert(S.CooldownManagerConvertAnchor("ess",PLAYER))
assert(toFrame.ess_x==0 and toFrame.ess_y==0 and toFrame.essOnViewer==false,"attaching while riding: a zero attach offset")
Apply(toFrame)
config.ess_y=10
module:Refresh()
Run()
MSUF_DB=nil
module:Refresh()
Run()
assert(config.ess_x==0 and config.ess_y==10 and config.essOnViewer==false and PendingTimers()==0,
    "an attach offset survives MSUF letting go of Blizzard's bar")
bars.ess.frame.rect=nil
-- Our Essential bar off while it rides: Utility stands in with the same
-- offset. Letting go takes the screen position from Blizzard's bar plus
-- that offset (528-3-384 = 141 above the center), so nothing jumps.
Apply({ess_anchor=1,ess_x=0,ess_y=141})
MSUF_DB={general={anchorToCooldown=true}}
module:Refresh()
Run()
assert(config.essOnViewer==true and config.ess_y==0)
Apply({ess_on=false,ess_y=-3})
assert(not bars.ess.shown and bars.uti.shown)
MSUF_DB=nil
module:Refresh()
assert(C.views.ess.y==141,"the view takes the position from Blizzard's bar at once")
Run()
assert(config.essOnViewer==false and config.ess_x==0 and config.ess_y==141,"the screen position is saved")
local stand=bars.uti.frame.point
assert(stand[1]=="TOP" and stand[2]==UIParent and stand[3]=="CENTER" and math.abs(stand[5]-Snap(141))<1e-6
    and math.abs(384+stand[5]-(Snap(528)+Snap(-3)))<unit,"the stand-in stays in place")
-- Nothing readable (our bar off, Blizzard's bar without a rectangle):
-- nothing is written, the flag holds and the next Refresh tries again.
MSUF_DB={general={anchorToCooldown=true}}
module:Refresh()
Run()
assert(config.essOnViewer==true and config.ess_y==0)
essViewer.rect={}
C.Layout.InvalidateScale()
MSUF_DB=nil
module:Refresh()
Run()
assert(config.essOnViewer==true and config.ess_x==0 and config.ess_y==0 and PendingTimers()==0,"nothing readable: nothing written")
essViewer.rect={362,478,300,50}
C.Layout.InvalidateScale()
module:Refresh()
Run()
assert(config.essOnViewer==false and config.ess_y==144,"the next Refresh converts ("..tostring(config.ess_y)..")")
Apply({ess_on=true})
config.ess_x,config.ess_y,config.blizzard=savedX,savedY,1
essViewer.rect=nil
module:Refresh()
Run()
assert(C.Native.Mode()==1 and cvars.cooldownViewerEnabled=="0")

------------------------------------------------------------------ disabled features register no events
for _,slot in ipairs({"ess","uti","ext","c1","c2","c3","c4","c5","c6"}) do
    local k=Suite.CDM.KEYS[slot]
    for _,suffix in ipairs({"usable","range","procGlow","keybind","assist","charges"}) do
        if k[suffix] then config[k[suffix]]=false end
    end
end
module:Refresh()
Run()
for _,event in ipairs({"SPELL_UPDATE_USABLE","SPELL_RANGE_CHECK_UPDATE","SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE","UPDATE_BINDINGS","ACTIONBAR_SLOT_CHANGED","SPELL_UPDATE_USES"}) do
    assert(not Registered(event),event.." registered for a disabled feature")
end
assert(Registered("SPELL_UPDATE_CHARGES"),"recharge swipes do not depend on shown counts")
assert(Registered("SPELL_UPDATE_COOLDOWN"))
assert(C.Effects.RangeReferences()==0,"range checks released")
local released=0
for _,call in ipairs(rangeLog) do if call[2]==false then released=released+1 end end
assert(released>=2)
assert(LiveTickers()==0)
NoOnUpdate()
Run(5)
assert(PendingTimers()==0 and LiveTickers()==0,"idle again")
-- Both bag events live exactly while item entries exist. The trinket on
-- Essential is one: bag events stay while it alone is left, and go once it
-- is removed as well.
config.ext_on,config.c1_on=false,false
module:Refresh()
Run()
assert(#C.Index.items==1 and C.Index.items[1]==C.entries.b71 and Registered("BAG_UPDATE_COOLDOWN")
    and Registered("BAG_UPDATE_DELAYED") and Registered("PLAYER_EQUIPMENT_CHANGED"),"the trinket on Essential keeps its item events")
local bagLists=config.listsData
config.listsData=assert(Codec.EncodeLists({v=1,specs={[62]={ess={"b14","b11"},c1={"s9001","i9002"}},
    [63]={c1={"s9001","i9002"}}},hidden={[62]={b71=true}}}))
module:Refresh()
Run()
assert(not C.entries.b71 and #C.Index.items==0 and not Registered("BAG_UPDATE_COOLDOWN") and not Registered("BAG_UPDATE_DELAYED"),
    "bag events without item entries")
config.listsData=bagLists
config.ext_on,config.c1_on=true,true
module:Refresh()
Run()
assert(#C.Index.items>0 and Registered("BAG_UPDATE_COOLDOWN") and Registered("BAG_UPDATE_DELAYED") and C.entries.b71.slot=="ess",
    "bag events return with item entries")
-- The gear watch follows the bars that hold an equipment slot record,
-- learned or not: with Buffs, Potions and racials and the custom bar off and
-- the trinket not usable yet, equipping an on-use trinket must still rebuild.
config.ext_on,config.c1_on,config.buf_on=false,false,false
infos[71].isKnown=false
Fire("SPELLS_CHANGED")
module:Refresh()
Run()
assert(not C.entries.b71 and #C.Index.items==0 and C.Catalog.equipBars.ess and Registered("PLAYER_EQUIPMENT_CHANGED"),
    "an unlearned trinket on Essential keeps the gear watch")
config.ess_on=false
module:Refresh()
Run()
assert(not Registered("PLAYER_EQUIPMENT_CHANGED"),"no gear watch without a shown bar holding equipment")
config.ess_on=true
module:Refresh()
Run()
assert(Registered("PLAYER_EQUIPMENT_CHANGED"),"the gear watch returns with the Essential bar")
infos[71].isKnown=true
config.ext_on,config.c1_on,config.buf_on=true,true,true
Fire("SPELLS_CHANGED")
module:Refresh()
Run()
assert(C.entries.b71 and C.entries.b71.slot=="ess" and Registered("PLAYER_EQUIPMENT_CHANGED"))
-- Only trinket slots and slots an entry tracks rebuild the catalog.
ResetCalls()
assert(Fire("PLAYER_EQUIPMENT_CHANGED",13,true) and PendingTimers()==1,"a trinket change rebuilds")
Run()
assert(Calls("catalog")==1 and Calls("resolve")==1)
-- Target events live while target containers or range checks exist.
config.buf_on,config.bar_on,config.ess_showAura=false,false,false
module:Refresh()
Run()
assert(not Registered("UNIT_FACTION") and not Registered("PLAYER_TARGET_CHANGED"),"no target watch without target auras")
assert(#C.Index.aura+#C.Index.overlay==0 and not Registered("ADDON_RESTRICTION_STATE_CHANGED"),
    "no restriction watch without aura containers or overlays")
config.buf_on,config.bar_on,config.ess_showAura=true,true,true
module:Refresh()
Run()
assert(Registered("UNIT_FACTION") and Registered("PLAYER_TARGET_CHANGED"),"target auras watch the target again")
assert(Registered("ADDON_RESTRICTION_STATE_CHANGED"),"the restriction watch returns with aura containers")
-- Turning the Essential bar off and on tells MSUF each time.
anchorCount=AnchorEvents()
config.ess_on=false
module:Refresh()
Run()
assert(not bars.ess.shown and AnchorEvents()==anchorCount+1,"hiding the Essential bar notifies")
assert(Suite.CooldownManager.GetAnchorFrame("EssentialCooldownViewer")==nil,"no anchor while the Essential bar is off")
config.ess_on=true
module:Refresh()
Run()
assert(bars.ess.shown and AnchorEvents()==anchorCount+2,"showing it again notifies")
assert(Suite.CooldownManager.GetAnchorFrame("EssentialCooldownViewer")==bars.ess.anchorFrame)
anchorCount=AnchorEvents()

------------------------------------------------------------------ healthstones
-- Potions and racials offers the Healthstone and the Demonic Healthstone
-- after Blizzard's entries. They hide while the bags hold none, keep both
-- bag events alive (alone too), relayout their bar once per flip, and a
-- cooldown held until combat ends shows no swipe until BAG_UPDATE_COOLDOWN
-- starts it. A function of its own: the main chunk is at Lua's 200-local limit.
do (function()
    local keptLists,getIcon,getName=config.listsData,C_Item.GetItemIconByID,C_Item.GetItemNameByID
    -- Counts were switched off above; the bar shows them again here.
    local chargesKey=Suite.CDM.KEYS.ext.charges
    local keptCharges=config[chargesKey]
    config[chargesKey]=true
    C_Item.GetItemIconByID=function(item) if item==5512 or item==224464 then return 538745 end return getIcon(item) end
    C_Item.GetItemNameByID=function(item)
        if item==5512 then return "Healthstone" elseif item==224464 then return "Demonic Healthstone" end
        return getName(item)
    end
    bagCounts[5512],bagCounts[224464]=0,0
    -- Only the healthstones follow the bags: the potion and the trinket are
    -- removed for this spec and the custom bar (a bag item) is off.
    config.listsData=assert(Codec.EncodeLists({v=1,specs={[62]={ess={"b14","b11"},c1={"s9001","i9002"}}},
        hidden={[62]={b52=true,b71=true}}}))
    config.c1_on=false
    module:Refresh()
    Run()
    local ext=C.plans.ext.entries
    assert(#ext==3 and ext[1].key=="b51" and ext[2].key=="i5512" and ext[3].key=="i224464",
        "Blizzard's entries, then the Healthstone and the Demonic Healthstone")
    local stone,demonic=C.entries.i5512,C.entries.i224464
    assert(stone.icon and demonic.icon and stone.hidden==true and demonic.hidden==true and not stone.icon.shown
        and not demonic.icon.shown,"empty healthstones hide")
    assert(#C.Index.items==2 and #C.Index.bags==2 and Registered("BAG_UPDATE_DELAYED") and Registered("BAG_UPDATE_COOLDOWN"),
        "bag events stay while only hidden healthstones follow the bags")
    local rows=S.CooldownManagerBarEntries("ext")
    assert(rows[2].key=="i5512" and rows[2].hidden==true and rows[1].hidden==false,"the page marks an empty healthstone hidden")
    -- Count 0 -> 1 -> 0: one relayout of the bar per flip, none in between.
    ResetCalls()
    bagCounts[5512]=1
    assert(Fire("BAG_UPDATE_DELAYED"))
    Run()
    assert(stone.hidden==false and stone.icon.shown and demonic.hidden==true and Calls("layout")==1 and Calls("layoutAll")==0,
        "a stone in the bags shows it with one relayout ("..Calls("layout")..")")
    ResetCalls()
    bagCounts[5512]=3
    Fire("BAG_UPDATE_DELAYED")
    Run()
    assert(stone.icon.count.text==3 and Calls("layout")==0,"a count change without a flip lays nothing out")
    ResetCalls()
    bagCounts[5512]=0
    Fire("BAG_UPDATE_DELAYED")
    Run()
    assert(stone.hidden==true and not stone.icon.shown and Calls("layout")==1,"the last stone used hides it again")
    -- Bag events that change nothing: no allocation, no widget call, no
    -- layout (the next-frame flush runs through an allocation-free timer).
    bagCounts[5512]=2
    Fire("BAG_UPDATE_DELAYED")
    Run()
    do
        local after,queued=C_Timer.After,nil
        C_Timer.After=function(_,fn) queued=fn end
        local function Pass(event)
            Fire(event)
            local fn=queued
            queued=nil
            if fn then fn() end
        end
        ResetCalls()
        collectgarbage("collect")
        collectgarbage("stop")
        for _=1,20 do Pass("BAG_UPDATE_COOLDOWN");Pass("BAG_UPDATE_DELAYED") end
        local quiet=writes
        local kb=collectgarbage("count")
        for _=1,300 do Pass("BAG_UPDATE_COOLDOWN");Pass("BAG_UPDATE_DELAYED") end
        local used=collectgarbage("count")-kb
        collectgarbage("restart")
        C_Timer.After=after
        assert(used==0,"bag events that change nothing allocated "..used.." KB")
        assert(writes==quiet and Calls("layout")==0,"bag events that change nothing wrote "..(writes-quiet).." widgets")
    end
    -- Used in combat: the cooldown is held until combat ends (enable false),
    -- no swipe, still cooling (no ready alert). The BAG_UPDATE_COOLDOWN that
    -- starts it arms the swipe; its end is the one ready edge.
    local alerts,realReady=0,C.Alerts.Ready
    C.Alerts.Ready=function(e,...) if e==stone then alerts=alerts+1 end return realReady(e,...) end
    combat=true
    Fire("PLAYER_REGEN_DISABLED")
    Run()
    C_Item.cooldowns[5512]={now,60,false}
    bagCounts[5512]=1
    Fire("BAG_UPDATE_COOLDOWN")
    Fire("BAG_UPDATE_DELAYED")
    Run()
    assert(stone.cooling==true and not stone.icon.cd.running and stone.hidden==false and alerts==0,
        "a held cooldown: no swipe, cooling, still shown")
    combat=false
    Fire("PLAYER_REGEN_ENABLED")
    Run()
    assert(stone.cooling==true and not stone.icon.cd.running,"held until the cooldown starts")
    C_Item.cooldowns[5512]={now,60,true}
    Fire("BAG_UPDATE_COOLDOWN")
    Run()
    assert(stone.cooling==true and stone.icon.cd.running and alerts==0,"the cooldown's start arms the swipe")
    Run(61)
    stone.icon.cd.scripts.OnCooldownDone(stone.icon.cd)
    Run()
    assert(stone.cooling==false and not stone.icon.cd.running and alerts==1,"its end is one ready edge")
    C.Alerts.Ready=realReady
    -- Removed from the bar (hidden set) the bag events go with the last one.
    config.listsData=assert(Codec.EncodeLists({v=1,specs={[62]={ess={"b14","b11"},c1={"s9001","i9002"}}},
        hidden={[62]={b52=true,b71=true,i5512=true,i224464=true}}}))
    module:Refresh()
    Run()
    assert(not C.entries.i5512 and #C.Index.items==0 and not Registered("BAG_UPDATE_DELAYED") and not Registered("BAG_UPDATE_COOLDOWN"),
        "no bag events without bag entries")
    C_Item.cooldowns[5512],bagCounts[5512],bagCounts[224464]=nil,nil,nil
    C_Item.GetItemIconByID,C_Item.GetItemNameByID=getIcon,getName
    config.listsData,config.c1_on,config[chargesKey]=keptLists,true,keptCharges
    module:Refresh()
    Run()
    assert(#C.plans.ext.entries==2 and not C.entries.i5512 and C.entries.b52.slot=="ext" and C.entries.b71.slot=="ess"
        and Registered("BAG_UPDATE_DELAYED"),"back to the potion, the racial and the trinket")
end)() end

------------------------------------------------------------------ loading screens silence sounds
Fire("PLAYER_ENTERING_WORLD",false,true)
assert(C.state.soundQuietUntil==now+2,"two quiet seconds after a loading screen")
Run()

------------------------------------------------------------------ disable and release
module.active=false
S.states[ID].active=false
module:Disable()
module.context:Release()
assert(cvars.cooldownViewerEnabled=="1","the CVar is restored")
for _,slot in ipairs({"ess","uti","def","ext","buf","bar","c1","c2"}) do
    assert(not bars[slot].frame.shown,slot.." still shown after disable")
end
assert(not next(module.context.frame.events),"events left registered")
assert(DriverCount()==0,"visibility drivers left registered")
assert(not registry["CooldownViewerSettings.OnPendingChanges"] and not registry["AssistedCombatManager.OnAssistedHighlightSpellChange"],
    "registry callbacks left registered")
assert(C.Effects.RangeReferences()==0 and LiveTickers()==0)
assert(Suite.CooldownManager.GetAnchorFrame("EssentialCooldownViewer")==nil,"no anchor while off")
assert(S.CooldownManagerStatus()==nil)
Run(5)
assert(PendingTimers()==0)
assert(AnchorEvents()==anchorCount+1,"disabling the module tells MSUF the Essential bar went away")
-- The loaded but inactive runtime still answers the options page.
assert(#S.CooldownManagerBarEntries("uti")==2,"cold snapshot for the options page")
-- No catalog events run while the module is off: a specialization change
-- rebuilds Blizzard's snapshot on the next page call, and only then.
local generation=C.Catalog.generation
sets[1]={21}
specIndex=3
assert(#S.CooldownManagerBarEntries("uti")==1 and C.Catalog.generation==generation+1 and C.Catalog.specTag==83,
    "a spec change while off rebuilds the snapshot")
assert(#S.CooldownManagerBarEntries("uti")==1 and C.Catalog.generation==generation+1,"the same spec reuses the snapshot")
sets[1]={21,22}
specIndex=1
assert(#S.CooldownManagerBarEntries("uti")==2 and C.Catalog.generation==generation+2)

-- A second activation starts clean; releasing mode 2 leaves the hooks inert.
-- The options page's preview request made while the module was off applies
-- once it is enabled.
assert(not S.CooldownManagerSetPreview(true),"no preview runs while off")
config.blizzard=2
module.active=true
module:Enable()
Run()
assert(C.Preview.mode=="options" and C.state.preview and C.Icons.Count("ess")==5,"the stored preview request applies on enable")
assert(S.CooldownManagerSetPreview(false))
Run()
assert(not C.state.preview,"the page takes its request back")
assert(bars.ess.shown and C.Icons.Count("ess")==4 and Registered("SPELL_UPDATE_COOLDOWN"),"re-enable")
assert(essViewer.alpha==0 and cvars.cooldownViewerEnabled=="1")
assert(AnchorEvents()==anchorCount+2,"a second activation notifies once")
local alphaHook,acquireHook
for _,hook in ipairs(hooks) do
    if hook[1]==essViewer and hook[2]=="SetAlpha" then alphaHook=hook[3] end
    if hook[1]==essViewer and hook[2]=="OnAcquireItemFrame" then acquireHook=hook[3] end
end
assert(alphaHook and acquireHook,"mode 2 hooks the viewer")
essViewer:SetAlpha(1)
alphaHook(essViewer,1)
assert(essViewer.alpha==0,"mode 2 keeps the viewer invisible")
local acquired=New("Frame",essViewer)
acquireHook(essViewer,acquired)
assert((acquired.calls.EnableMouse or 0)==1,"acquired items lose the mouse")
module.active=false
module:Disable()
module.context:Release()
assert(not next(module.context.frame.events) and cvars.cooldownViewerEnabled=="1")
assert(essViewer.alpha==1,"viewer alpha restored")
alphaHook(essViewer,1)
local later=New("Frame",essViewer)
acquireHook(essViewer,later)
assert(essViewer.alpha==1 and not later.calls.EnableMouse,"hooks are inert after release")
Run(5)
assert(AnchorEvents()==anchorCount+3 and PendingTimers()==0,"the final release notifies once")

------------------------------------------------------------------ defaults migrations
-- Saved settings older than CDM.DEFAULTS_VERSION migrate once on activation,
-- written a frame later through SetMany. 1: attached bars' x/y become
-- offsets from their anchor (zero). 2: free bars keep their place, counted
-- from the screen center instead of the same point of UIParent; unused
-- custom bars start in the middle. Bar contents always stay.
local function Activate() module.active=true;module:Enable();Run() end
local function Deactivate() module.active=false;module:Disable();module.context:Release();Run(5) end
config.blizzard=1
assert(not S.CooldownManagerSetPreview(true))
config.defaultsVersion=1
config.ess_x,config.ess_y=10,-50
config.uti_x,config.uti_y=5,5
config.c3_on,config.c3_x,config.c3_y=false,100,100
config.c4_on,config.c4_grow,config.c4_x,config.c4_y=true,2,20,30
local keptLists=config.listsData
Activate()
assert(config.defaultsVersion==3,"the migration stamps the current version")
assert(config.ess_x==10 and config.ess_y==-50+384,"a free bar keeps its place, now counted from the screen center")
assert(config.uti_x==0 and config.uti_y==0,"attached offsets start at zero")
assert(config.c3_x==0 and config.c3_y==0,"an unused custom bar starts in the middle")
assert(config.c4_x==20 and config.c4_y==30-384,"a bar growing up keeps its bottom edge")
assert(config.listsData==keptLists and config.captured==true,"bar contents and the capture stay")
assert(C.Preview.mode=="options","the stored preview request applies on enable")
Deactivate()
config.defaultsVersion=2
config.uti_x,config.uti_y,config.ess_y=7,-3,-50
Activate()
assert(config.defaultsVersion==3 and config.uti_x==7 and config.uti_y==-3 and config.ess_y==334,
    "2 to 3 converts free bars and keeps attached offsets")
assert(C.Preview.mode=="options","the preview request outlives a disable")
Deactivate()
-- 0: every bar setting returns to its default once; Blizzard's bar is read again.
config.defaultsVersion=0
config.ess_size,config.ess_perRow,config.uti_x=50,5,7
Activate()
local rules=S.catalog[ID].rules
assert(config.defaultsVersion==3 and config.ess_size==rules.ess_size.default and config.ess_perRow==rules.ess_perRow.default
    and config.uti_x==0 and config.listsData==keptLists and config.ess_y==141,"version 0 resets bar settings and keeps contents")
Deactivate()
config.ess_size=50
Activate()
assert(config.ess_size==50 and config.defaultsVersion==3,"current settings are never migrated")
assert(S.CooldownManagerSetPreview(false))
Run()
assert(not C.state.preview)
config.fontOutline,config.fontRendering,config.fontShadow=2,2,true
config.fontShadowOpacity,config.fontShadowDistance=70,2
module:Refresh();Run()
local effectCanvas=assert(S.CooldownManagerRenderPreview(barStage,"bar",400,200))
assert(effectCanvas.rows[1].name.fontFlags=="THICKOUTLINE,MONOCHROME"
    and effectCanvas.rows[1].name.shadowColor[4]==0.7
    and effectCanvas.rows[1].name.shadowOffset[1]==2,
    "Cooldown Manager preview text effects did not apply")
config.fontRendering=3
module:Refresh();Run()
effectCanvas=assert(S.CooldownManagerRenderPreview(barStage,"bar",400,200))
assert(effectCanvas.rows[1].name.fontFlags=="OUTLINE,SLUG"
    and effectCanvas.rows[1].name.shadowColor[4]==0,
    "Cooldown Manager Slug retained a shadow")
S.CooldownManagerReleasePreview(barStage)
Deactivate()
for key in pairs(_G) do assert(globalsBefore[key] or key=="MSUF_DB","runtime created the global "..tostring(key)) end

print("Cooldown manager contract: TOC, boot, capture, takeover, anchor notifications, event map, hot-event budgets (allocations, writes, lookups), charges, usable, range, procs, target, bag counts, overrides, incremental refresh, work per setting, data strings, spec change, previews, movers for every bar, exports, attach and grow conversion, resolve diffs, combat deferrals, layout callbacks, pixel scale, keybinds, assist, invisible mode, MSUF promotion, viewer offsets, feature-gated events, release, cold snapshot, stored preview and defaults migrations passed")
