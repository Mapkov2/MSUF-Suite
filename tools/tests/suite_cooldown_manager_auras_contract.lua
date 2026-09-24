local root=assert(arg[1],"repository root required")
-- Offline contract for the cooldown manager aura layer: Auras.lua (buff icon
-- bars, buff bars and cooldown overlays on AuraContainer) and Alerts.lua
-- (ready sounds, speech, native aura sounds). Blizzard objects are fakes that
-- refuse addon field writes, validate every binding, and refuse any touch of
-- a sealed aura button while auras are secret. Secret values are sentinels
-- that raise on comparison, arithmetic, concatenation, indexing and tostring.

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

------------------------------------------------------------------ clock, combat, timers
local NOW,COMBAT,ACCESS,AURAS_SECRET,V125=100,false,true,false,true
function GetTime() return NOW end
function InCombatLockdown() return COMBAT end
C_Secrets={ShouldAurasBeSecret=function() return AURAS_SECRET end}
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
table.wipe=wipe
local timerFns,timerDelays,timerCount={},{},0
C_Timer={After=function(delay,fn)
    assert(type(fn)=="function","timer callback")
    timerCount=timerCount+1
    timerFns[timerCount],timerDelays[timerCount]=fn,delay
end}
local function RunTimers()
    local i,guard=1,0
    while i<=timerCount do
        guard=guard+1
        assert(guard<100,"timer storm")
        local fn=timerFns[i]
        timerFns[i]=false
        fn()
        i=i+1
    end
    timerCount=0
end

------------------------------------------------------------------ widgets
local R=setmetatable({},{__mode="k"})
local Methods,ContainerMethods,ButtonMethods={},{},{}
local V125_ONLY={SetAuraGroupEnabled=true,SetAuraSlotEnabled=true,SetEditModePreviewEnabled=true,
    IsEditModePreviewEnabled=true,GetAuraSlotFrame=true}
local function Sealed(obj)
    local s=R[obj]
    while s do
        if s.button and s.sealed then return true end
        s=s.parent and R[s.parent]
    end
    return false
end
local function Index(obj,key)
    local s=R[obj]
    local m
    if s.button then m=ButtonMethods[key] end
    if m==nil and s.container then
        m=ContainerMethods[key]
        if m and V125_ONLY[key] and not s.v125 then m=nil end
    end
    if m==nil then m=Methods[key] end
    if m==nil then return nil end
    if key~="CanBeAccessedInContext" and ACCESS~=true and Sealed(obj) then
        return function() error("sealed aura button touched while auras are secret: "..key,2) end
    end
    return m
end
local RegionMT={__index=Index}
local BlizzardMT={__index=Index,__newindex=function(_,key) error("addon wrote field '"..tostring(key).."' on a Blizzard object",2) end}

local function New(kind,parent,mt)
    local obj=setmetatable({},mt or RegionMT)
    local ps=parent and R[parent]
    R[obj]={kind=kind,parent=parent,shown=true,points={},level=ps and ps.level+1 or 0,calls={},args={}}
    return obj
end
local function Calls(obj,name) return R[obj].calls[name] or 0 end
local function Args(obj,name) return R[obj].args[name] end
local function Record(name)
    return function(self,...)
        local s=R[self]
        s.args[name]={...}
        s.calls[name]=(s.calls[name] or 0)+1
    end
end
for _,name in ipairs({"SetSize","SetWidth","SetHeight","SetAlpha","SetFrameStrata","SetTexture","SetTexCoord",
    "SetColorTexture","SetVertexColor","SetDesaturated","SetBlendMode","SetTextColor","SetText","SetJustifyH",
    "SetJustifyV","SetWordWrap","SetClampedToScreen","EnableMouse","EnableMouseMotion","SetMouseMotionEnabled",
    "SetMouseClickEnabled","SetDrawBling","SetHideCountdownNumbers","SetReverse","SetSwipeColor","SetDrawEdge",
    "SetDrawSwipe","SetMinMaxValues","SetValue","SetStatusBarTexture","SetStatusBarColor","SetShadowOffset",
    "SetShadowColor"}) do Methods[name]=Record(name) end
local setShown=Record("SetShown")
function Methods:SetShown(shown)
    assert(type(shown)=="boolean","SetShown needs a plain boolean")
    setShown(self,shown)
    R[self].shown=shown
end
function Methods:Show() R[self].shown=true end
function Methods:Hide() R[self].shown=false end
function Methods:IsShown() return R[self].shown end
function Methods:SetPoint(...) local s=R[self];s.points[#s.points+1]={...};s.calls.SetPoint=(s.calls.SetPoint or 0)+1 end
function Methods:ClearAllPoints() R[self].points={} end
function Methods:SetAllPoints(target) local s=R[self];s.allPoints=target or s.parent end
function Methods:SetFrameLevel(level) assert(type(level)=="number");R[self].level=level;local c=R[self].calls;c.SetFrameLevel=(c.SetFrameLevel or 0)+1 end
function Methods:GetFrameLevel() return R[self].level end
function Methods:GetEffectiveScale() return 1 end
function Methods:CreateTexture() return New("Texture",self) end
function Methods:CreateFontString() return New("FontString",self) end
function Methods:SetFont(path,size,flags)
    assert(type(path)=="string" and type(size)=="number" and size>0,"font")
    R[self].font={path,size,flags}
    return true
end
function Methods:GetFont() return "Fonts\\FRIZQT__.TTF",12,"" end
function Methods:SetScript() error("no scripts on aura layer regions",2) end
function Methods:HookScript() error("no hooks on aura layer regions",2) end

local containers={}
local function NewButton(container)
    local b=New("AuraButton",container,BlizzardMT)
    local s=R[b]
    s.button,s.bind=true,{}
    return b
end
local TOKENS={HELPFUL=true,HARMFUL=true,PLAYER=true,RAID=true,CANCELABLE=true}
local function ValidFilter(filter)
    assert(type(filter)=="string" and filter~="","filter string")
    for token in filter:gmatch("[^|%s]+") do
        assert(TOKENS[(token:gsub("^!",""))],"bad filter token "..token)
    end
end
local function SecureCopy(value)
    if type(value)~="table" then return value end
    local copy={}
    for k,v in pairs(value) do copy[k]=SecureCopy(v) end
    return copy
end
local function ValidCandidates(cand)
    if cand==nil then return end
    assert(type(cand)=="table","candidateFilters")
    if cand.includeSpellIDs~=nil then assert(type(cand.includeSpellIDs)=="table","includeSpellIDs") end
    if cand.maxDuration~=nil then assert(type(cand.maxDuration)=="number" and cand.maxDuration>=0,"maxDuration") end
end
local function Log(self,name,key,value)
    local log=R[self].log
    log[#log+1]={name,key,value}
end

function ContainerMethods:SetUnit(unit)
    assert(type(unit)=="string","unit")
    local s=R[self]
    if s.unit~=unit then s.unit=unit;s.unitSets=s.unitSets+1 end
end
function ContainerMethods:GetUnit() return R[self].unit end
function ContainerMethods:SetEnabled(on)
    assert(type(on)=="boolean","enabled")
    R[self].enabled=on
    Log(self,"SetEnabled",nil,on)
end
function ContainerMethods:IsEnabled() return R[self].enabled end
function ContainerMethods:UpdateAllAuras() local s=R[self];s.updates=s.updates+1 end
function ContainerMethods:SetEditModePreviewEnabled(on) R[self].editPreview=on end
local function Display(self,key,filter,opts,count,slot)
    local s=R[self]
    assert(type(key)=="string" and key~="","key")
    assert(not s.groups[key] and not s.slots[key],"key reused: "..key)
    ValidFilter(filter)
    assert(type(opts)=="table" and type(opts.initializeFrame)=="function","initializeFrame")
    ValidCandidates(opts.candidateFilters)
    local g={filter=filter,cand=SecureCopy(opts.candidateFilters),layout=SecureCopy(opts.layout),max=opts.maxFrameCount,buttons={},enabled=true}
    if slot then s.slots[key]=g else s.groups[key]=g end
    s.order[#s.order+1]=key
    s.adds=s.adds+1
    Log(self,slot and "AddAuraSlot" or "AddAuraGroup",key,filter)
    for i=1,count do
        local b=NewButton(self)
        g.buttons[i]=b
        opts.initializeFrame(b)
        R[b].sealed=true
    end
    return g
end
function ContainerMethods:AddAuraGroup(key,filter,opts)
    assert(type(opts.layout)=="table" and type(opts.layout.layoutIndex)=="number","group layout")
    assert(opts.maxFrameCount==1,"one frame per entry group")
    Display(self,key,filter,opts,10,false)
end
function ContainerMethods:AddAuraSlot(key,filter,opts)
    local g=Display(self,key,filter,opts,1,true)
    if not R[self].v125 then return g.buttons[1] end
end
local function Group(self,key,slot)
    local s=R[self]
    local g=(slot and s.slots or s.groups)[key]
    assert(g,"unknown "..(slot and "slot " or "group ")..tostring(key))
    return g
end
function ContainerMethods:SetAuraGroupFilterString(key,filter) ValidFilter(filter);Group(self,key).filter=filter;Log(self,"GroupFilter",key,filter) end
function ContainerMethods:SetAuraGroupCandidateFilters(key,cand) ValidCandidates(cand);Group(self,key).cand=SecureCopy(cand);Log(self,"GroupCandidates",key,cand) end
function ContainerMethods:SetAuraGroupMaxFrameCount(key,n) assert(n==0 or n==1);Group(self,key).max=n;Log(self,"GroupMax",key,n) end
function ContainerMethods:SetAuraGroupLayout(key,layout) Group(self,key).layout=SecureCopy(layout);Log(self,"GroupLayout",key,layout) end
function ContainerMethods:SetAuraGroupEnabled(key,on) Group(self,key).enabled=on;Log(self,"GroupEnabled",key,on) end
function ContainerMethods:SetAuraSlotFilterString(key,filter) ValidFilter(filter);Group(self,key,true).filter=filter;Log(self,"SlotFilter",key,filter) end
function ContainerMethods:SetAuraSlotCandidateFilters(key,cand) ValidCandidates(cand);Group(self,key,true).cand=SecureCopy(cand);Log(self,"SlotCandidates",key,cand) end
function ContainerMethods:SetAuraSlotEnabled(key,on) Group(self,key,true).enabled=on;Log(self,"SlotEnabled",key,on) end
function ContainerMethods:SetFlowLayoutAxis(axis) R[self].flow.axis=axis end
function ContainerMethods:SetFlowLayoutAnchorPoint(point) R[self].flow.anchor=point end
function ContainerMethods:SetFlowLayoutGrowthDirection(h,v) R[self].flow.h,R[self].flow.v=h,v end
function ContainerMethods:SetFlowLayoutMaximumLineSize(n) R[self].flow.line=n end
function ContainerMethods:SetFlowLayoutPadding(a,b,c,d) R[self].flow.padding={a,b,c,d} end

local function Descendant(region,button,kind)
    local s=R[region]
    assert(s,"bound object is not a widget")
    if kind then assert(s.kind==kind,"expected "..kind..", got "..s.kind) end
    local parent=s.parent
    while parent do
        if parent==button then return end
        parent=R[parent].parent
    end
    error("bound region is not a descendant of its aura button",3)
end
function ButtonMethods:SetIcon(t) Descendant(t,self,"Texture");R[self].bind.icon=t end
function ButtonMethods:SetDurationCooldown(cd) Descendant(cd,self,"Cooldown");R[self].bind.cooldown=cd end
function ButtonMethods:SetDurationText(fs,opts)
    Descendant(fs,self,"FontString")
    assert(type(opts)=="table","duration text options")
    local b=R[self].bind
    b.text,b.textOpts,b.textBinds=fs,opts,(b.textBinds or 0)+1
end
function ButtonMethods:SetApplicationCount(fs,opts)
    Descendant(fs,self,"FontString")
    assert(opts==nil,"no custom count formatter")
    R[self].bind.count=fs
end
function ButtonMethods:SetDurationBar(bar,opts) Descendant(bar,self,"StatusBar");R[self].bind.bar,R[self].bind.barOpts=bar,SecureCopy(opts) end
function ButtonMethods:SetSpellName(fs) Descendant(fs,self,"FontString");R[self].bind.name=fs end
function ButtonMethods:AddPandemicRegion(region)
    Descendant(region,self)
    local b=R[self].bind
    b.pandemic=(b.pandemic or 0)+1
    if not R[R[self].parent].v125 then return b.pandemic end
end
local ANCHORS={ANCHOR_LEFT=true,ANCHOR_RIGHT=true,ANCHOR_BOTTOMLEFT=true,ANCHOR_BOTTOM=true,ANCHOR_BOTTOMRIGHT=true,
    ANCHOR_TOPLEFT=true,ANCHOR_TOP=true,ANCHOR_TOPRIGHT=true,ANCHOR_CURSOR=true,ANCHOR_NONE=true}
function ButtonMethods:SetTooltipAnchorPoint(point) assert(ANCHORS[point],"tooltip anchor") end
function ButtonMethods:CanBeAccessedInContext() return ACCESS end
function ButtonMethods:SetAuraBorder() error("SetAuraBorder must never be called",2) end
function ButtonMethods:SetAuraSymbol() error("SetAuraSymbol must never be called",2) end

function CreateFrame(kind,name,parent,template)
    if kind=="AuraContainer" then
        assert(template=="CustomAuraContainerTemplate","container template")
        local c=New("AuraContainer",parent,BlizzardMT)
        local s=R[c]
        s.container,s.v125,s.unit,s.enabled=true,V125,"none",true
        s.updates,s.unitSets,s.adds=0,0,0
        s.groups,s.slots,s.order,s.log,s.flow={},{},{},{},{}
        containers[#containers+1]=c
        return c
    end
    assert(kind=="Frame" or kind=="Cooldown" or kind=="StatusBar","frame type "..tostring(kind))
    return New(kind,parent)
end
UIParent=New("Frame",nil)

------------------------------------------------------------------ WoW API
AuraContainerInbound={}
Enum={StatusBarTimerDirection={ElapsedTime=0,RemainingTime=1},StatusBarInterpolation={Immediate=0,ExponentialEaseOut=1},
    NumericRuleFormatRounding={Nearest=0,Up=1,Down=2},UnitAuraSoundTrigger={Added=0,ApplicationsIncreased=1,Removed=2},
    TtsVoiceType={Standard=0,Alternate=1}}
RAID_CLASS_COLORS={MAGE={r=.25,g=.78,b=.92}}
function UnitClass() return "Mage","MAGE",8 end
local FRIENDLY,assistCalls=false,0
function UnitCanAssist(a,b)
    assert(a=="player" and b=="target","assist check on the target only")
    assistCalls=assistCalls+1
    return FRIENDLY
end
local bindings={}
C_DurationUtil={CreateDurationTextBinding=function()
    local binding={calls={}}
    local function Set(name) return function(self,value) self.calls[name]=value==nil and true or value end end
    for _,name in ipairs({"SetFormatter","SetZeroDurationText","SetExpiredText","SetUpdateInterval","SetEnabled"}) do binding[name]=Set(name) end
    bindings[#bindings+1]=binding
    return binding
end}
C_StringUtil={CreateNumericRuleFormatter=function()
    return {SetBreakpoints=function(self,points) self.points=SecureCopy(points) end}
end}
local played={kits=0,files=0,speech=0}
function PlaySound(kit,channel) played.kits=played.kits+1;played.kit,played.kitChannel=kit,channel;return true,1 end
function PlaySoundFile(file,channel) played.files=played.files+1;played.file,played.fileChannel=file,channel;return true,2 end
C_VoiceChat={SpeakText=function(voice,text,rate,volume,overlap)
    assert(type(voice)=="number" and type(rate)=="number" and type(volume)=="number" and type(overlap)=="boolean","speech args")
    played.speech=played.speech+1;played.text=text
end}
C_TTSSettings={GetVoiceOptionID=function() return 3 end,GetSpeechRate=function() return 0 end,GetSpeechVolume=function() return 80 end}
local LSM={Fetch=function(_,kind,name) if kind=="sound" and name=="Boom" then return "Sound\\Boom.ogg" end
    if kind=="sound" and name=="None" then return 1 end end}
LibStub=setmetatable({GetLibrary=function(_,name) if name=="LibSharedMedia-3.0" then return LSM end end},
    {__call=function(self,name) return self:GetLibrary(name) end})
local auraSounds,nextSound={},0
C_UnitAuras={
    AddAuraSound=function(trigger,info)
        assert(type(trigger)=="number" and type(info)=="table","AddAuraSound args")
        assert((info.unitToken=="player" or info.unitToken=="target") and type(info.spellID)=="number","sound info")
        assert((info.soundFileName~=nil)~=(info.soundFileID~=nil),"one sound source")
        nextSound=nextSound+1
        auraSounds[nextSound]={trigger=trigger,unit=info.unitToken,spell=info.spellID,name=info.soundFileName,
            file=info.soundFileID,channel=info.outputChannel}
        return nextSound
    end,
    RemoveAuraSound=function(id) assert(auraSounds[id],"unknown aura sound "..tostring(id));auraSounds[id]=nil end,
}
local function SoundCount() local n=0 for _ in pairs(auraSounds) do n=n+1 end return n end

------------------------------------------------------------------ suite core + catalog
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",IsRetail=true,SupportsEvent=function() return true end}}
WOW_PROJECT_ID,WOW_PROJECT_MAINLINE=1,1
C_CooldownViewer={GetCooldownViewerCategorySet=function() return {} end,GetCooldownViewerCooldownInfo=function() end}
C_Spell={GetSpellCooldownDuration=function() end}
local store={}
MSUF_EncodeCompactTable=function(t,prefix) store[#store+1]=t;return prefix..":"..#store end
MSUF_TryDecodeCompactString=function(s) local n=tonumber(s:match("^MSUF3:(%d+)$"));return n and store[n] or nil end
local NS={}
for _,file in ipairs({"Core/Platform.lua","Core/Database.lua","Core/SuiteCatalog.lua"}) do
    assert(loadfile(root.."/MSUF_Suite/"..file))("MSUF_Suite",NS)
end
-- moduleAddons gains the module only at integration: register it locally.
local B=NS.CatalogBuild
local module=B.Module
B.Module=function(id,spec)
    if id=="cooldownManager" and not NS.SuiteCatalog[id] then
        spec.id,spec.addon,spec.controls,spec.rules,spec.conflicts=id,"MSUF_Suite_CooldownManager",{},{},spec.conflicts or {}
        NS.SuiteCatalog[id]=spec
        NS.SuiteOrder[#NS.SuiteOrder+1]=id
        B.Add(id,B.Bool("enabled","Enable module",false))
        return spec
    end
    return module(id,spec)
end
assert(loadfile(root.."/MSUF_Suite/Core/Catalog/CooldownManager.lua"))("MSUF_Suite",NS)
local CDM=NS.CDM
local S=NS.Suite or {}
NS.Suite=S
function S.Public(value) return not issecretvalue(value) end
function S.Text(value) return value end
MSUFSuite=NS
assert(loadfile(root.."/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules",{})

------------------------------------------------------------------ CDM private table
local C={M={},EMPTY={},views={},plans={},bars={},entries={},spells={v=1,e={}},lists=CDM.CleanLists(nil)}
C.state={config={},px=1,fontFlags="OUTLINE",cdR=1,cdG=1,cdB=1,stackR=1,stackG=1,stackB=1,threshold=0,
    thR=1,thG=.35,thB=.24,muteSounds=false,soundChannel="Master",soundQuietUntil=0,inCombat=false,preview=false}
local P={NS=NS,Suite=S,CDM=C}
local function LoadRuntime(file,private)
    local chunk=assert(loadfile(root.."/MSUF_Suite_CooldownManager/"..file))
    chunk("MSUF_Suite_CooldownManager",private or P)
end
LoadRuntime("Const.lua")

-- Layout stand-in with the contract the aura layer uses (EnsureBar, Cell,
-- Metrics); the real Layout.lua is checked against it further down.
local L={}
C.Layout=L
function L.PixelScale() return 1 end
function L.EnsureBar(slot)
    local bar=C.bars[slot]
    if bar then return bar end
    local frame=CreateFrame("Frame",nil,UIParent)
    frame:SetFrameLevel(10)
    bar={key=slot,frame=frame,cells={}}
    bar.auraHost=CreateFrame("Frame",nil,frame)
    C.bars[slot]=bar
    return bar
end
function L.Cell(slot,i)
    local bar=L.EnsureBar(slot)
    for n=#bar.cells+1,i do bar.cells[n]=CreateFrame("Frame",nil,bar.auraHost) end
    return bar.cells[i]
end
function L.Metrics(view)
    if view.kind==3 then
        return view.barWidth or 200,view.barHeight or 18,view.spacing or 2,1,false,view.grow==1 and 1 or 2,1
    end
    local size=view.size or 36
    return size,size*(view.height or 100)/100,view.spacing or 0,view.perRow or 1,view.vertical==true,
        view.grow==2 and 2 or 1,(view.align==2 or view.align==3) and view.align or 1
end

-- Strict globals from here on: the runtime files may not create any.
setmetatable(_G,{__newindex=function(_,key) error("global write: "..tostring(key),2) end})
LoadRuntime("Auras.lua")
LoadRuntime("Alerts.lua")
local A,Alerts=C.Auras,C.Alerts
assert(A and Alerts,"exports")
for _,name in ipairs({"Sync","SyncOverlays","Restyle","TargetChanged","TargetReaction","OverlayShown","SetBarMouse","FlushPending",
    "Release","ReleaseAll","SetPreview"}) do
    assert(type(A[name])=="function","C.Auras."..name)
end
assert(type(A.pending)=="table","C.Auras.pending")
for _,name in ipairs({"Ready","SyncAuraSounds","ReleaseAll","Play"}) do assert(type(Alerts[name])=="function","C.Alerts."..name) end

-- Static rules on the source text.
for _,file in ipairs({"Auras.lua","Alerts.lua"}) do
    local handle=assert(io.open(root.."/MSUF_Suite_CooldownManager/"..file,"rb"))
    local text=handle:read("*a")
    handle:close()
    local header=text:gsub("\r",""):match("^([^\n]*\n[^\n]*\n[^\n]*)\n")
    assert(header=="local _,P=...\nlocal NS,S=P.NS,P.Suite\nlocal C=P.CDM",file.." header")
    -- No event registration of its own: no Lua runs per UNIT_AURA.
    for _,word in ipairs({"pcall","loadstring","setfenv","hooksecurefunc","HookScript","SetScript","OnUpdate",
        "RegisterEvent","RegisterUnitEvent","NewTicker","SetAuraBorder","SetAuraSymbol","Claude","Anthropic"}) do
        assert(not text:find(word,1,true),file.." must not contain "..word)
    end
end

------------------------------------------------------------------ views and entries
local rules=NS.SuiteCatalog.cooldownManager.rules
-- Slots the aura layer serves: four cooldown bars (overlays), Buffs (icons),
-- Buff bars, then six custom bars of any kind.
local ORDER={"ess","uti","def","ext","buf","bar","c1","c2","c3","c4","c5","c6"}
assert(#CDM.SLOTS==#ORDER,"twelve slots")
for i,key in ipairs(ORDER) do assert(CDM.SLOTS[i].key==key and CDM.SLOT_INDEX[key]==i,"slot order at "..key) end
for i=1,4 do assert(CDM.SLOTS[i].kind==1 and CDM.SLOTS[i].builtin,"built-in cooldown bar "..ORDER[i]) end
assert(CDM.SLOTS[5].kind==2 and CDM.SLOTS[6].kind==3,"Buffs are icons, Buff bars are bars")
assert(CDM.KEYS.def.showAura and CDM.KEYS.ext.showAura and not CDM.KEYS.def.keepSlots,"new cooldown bars carry the overlay switch only")
assert(CDM.KEYS.bar.grow and rules[CDM.KEYS.bar.grow].default==1,"Buff bars carry a grow rule, Down by default")
local function View(slot,kind)
    local view={key=slot,index=CDM.SLOT_INDEX[slot],kind=kind,builtin=slot:sub(1,1)~="c",title=slot,
        styleGen=1,layoutGen=1,behaviorGen=1}
    for suffix,key in pairs(CDM.KEYS[slot]) do view[suffix]=rules[key].default end
    view.on,view.kind=true,kind
    view.borderR,view.borderG,view.borderB=S.RGB(view.borderColor or "000000")
    if view.barColor then view.barR,view.barG,view.barB=S.RGB(view.barColor) end
    return view
end
local function Set(...) local set={} for i=1,select("#",...) do set[select(i,...)]=true end return set end
local function Aura(slot,key,src,unit,ids,extra)
    local e={key=key,src=src,id=tonumber(key:sub(2)),family=2,unit=unit,slot=slot,ov=C.EMPTY,auraIDs=ids,
        texture=500000+tonumber(key:sub(2)),name="Aura "..key,selfAura=unit=="player",hasAura=true,linked=C.EMPTY}
    if extra then for k,v in pairs(extra) do e[k]=v end end
    return e
end
local function Plan(slot,kind,entries)
    for i,e in ipairs(entries) do e.index=i end
    C.plans[slot]={slot=slot,kind=kind,entries=entries,gen=1}
    return C.plans[slot]
end
local function Count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
local function Live(slot,unit,over)
    -- the newest container of a bar/unit that is enabled, found through the fakes
    local bar=C.bars[slot]
    local parent=over and bar.frame or bar.auraHost
    local found
    for _,c in ipairs(containers) do
        local s=R[c]
        if s.parent==parent and s.enabled and s.unit==unit and s.shown~=false then found=c end
    end
    return found
end
local function LogCount(c,name,key)
    local n=0
    for _,row in ipairs(R[c].log) do if row[1]==name and (key==nil or row[2]==key) then n=n+1 end end
    return n
end
local function Buttons(c,key)
    local s=R[c]
    local g=s.groups[key] or s.slots[key]
    return g and g.buttons or {}
end

------------------------------------------------------------------ compact aura icon bar
C.views.buf=View("buf",2)
local buf=C.views.buf
assert(buf.grow==1 and buf.perRow==10 and buf.size==30 and buf.height==90 and buf.spacing==2
    and buf.pandemic==true and buf.cdText==true,"Buffs defaults: 30 px at 10:9, ten per row, growing down")
local e1=Aura("buf","b11","b","player",Set(1001,1002,1003,1004))
local e2=Aura("buf","a2001","a","player",Set(2001))
local e3=Aura("buf","b12","b","target",Set(3001,3002))
local e4=Aura("buf","d4001","d","target",Set(4001))
Plan("buf",2,{e1,e2,e3,e4})
A.Sync("buf")
assert(#containers==2,"one container per unit")
local pc,tc=Live("buf","player"),Live("buf","target")
assert(pc and tc and pc~=tc,"player and target containers")
local ps,ts=R[pc],R[tc]
assert(ps.editPreview==false and ts.editPreview==false,"12.1.5: Edit Mode preview switched off")
assert(ps.order[1]=="g1" and ps.order[2]=="g2" and #ps.order==2,"player groups per entry")
assert(ps.groups.g1.filter=="HELPFUL|PLAYER" and ps.groups.g2.filter=="HELPFUL","player filters by entry type")
assert(ts.groups.g1.filter=="HARMFUL|PLAYER" and ts.groups.g2.filter=="HARMFUL|PLAYER","target filters")
local inc=ps.groups.g1.cand.includeSpellIDs
assert(Count(inc)==4 and inc[1001] and inc[1004],"Blizzard entry includes all its IDs")
assert(ps.groups.g2.cand.includeSpellIDs[2001] and Count(ps.groups.g2.cand.includeSpellIDs)==1)
assert(ts.groups.g1.cand.includeSpellIDs[3002] and ts.groups.g2.cand.includeSpellIDs[4001])
assert(ps.groups.g1.layout.layoutIndex==1 and ps.groups.g2.layout.layoutIndex==2,"layoutIndex = entry index")
assert(ts.groups.g1.layout.layoutIndex==3 and ts.groups.g2.layout.layoutIndex==4)
local layout=ps.groups.g1.layout
assert(layout.elementWidth==30 and layout.elementHeight==27 and layout.elementSpacing==0 and layout.groupSpacing==2
    and layout.groupLineSpacing==2,"one-frame groups spaced by groupSpacing, 10:9 elements")
assert(ps.groups.g1.max==1)
-- growth Down, centered: flow from the top-left, container anchored by its top center
assert(ps.flow.axis==0 and ps.flow.anchor=="TOPLEFT" and ps.flow.h==1 and ps.flow.v==-1,"flow down/right")
assert(math.abs(ps.flow.line-(10*30+9*2))<.1,"ten icons per line")
local host=C.bars.buf.auraHost
local pp,tp=ps.points[1],ts.points[1]
assert(pp[1]=="TOP" and pp[2]==host and pp[3]=="TOP" and pp[4]==0 and pp[5]==0,"player row at the growth point")
assert(tp[1]=="TOP" and tp[2]==host and tp[5]==-29,"target row one 27 px line plus spacing further down")
assert(#ps.points==1 and #ts.points==1,"one anchor per container")
assert(ps.level==C.bars.buf.frame:GetFrameLevel()+4,"above host and cells")
-- growth Up flips flow and host point on the same containers; Down restores
local layoutCalls=LogCount(pc,"GroupLayout")
buf.grow=2;buf.layoutGen=2
A.Sync("buf")
assert(Live("buf","player")==pc and Live("buf","target")==tc and #containers==2,"growth is a container write, not a rebuild")
assert(ps.flow.anchor=="BOTTOMLEFT" and ps.flow.v==1 and ps.flow.h==1,"flow up/right")
assert(ps.points[1][1]=="BOTTOM" and ps.points[1][5]==0 and #ps.points==1,"player row on the bottom edge")
assert(ts.points[1][1]=="BOTTOM" and ts.points[1][5]==29 and #ts.points==1,"target row one line further up")
assert(LogCount(pc,"GroupLayout")==layoutCalls,"same element size: no group layout writes")
buf.grow=1;buf.layoutGen=3
A.Sync("buf")
assert(ps.flow.anchor=="TOPLEFT" and ps.flow.v==-1 and ps.points[1][1]=="TOP" and ts.points[1][5]==-29,"back to growing down")
assert(ps.unit=="player" and ts.unit=="target" and ps.enabled and ts.enabled)
-- buttons: ten per group, styled and bound
local buttons=Buttons(pc,"g1")
assert(#buttons==10,"a group creates ten buttons")
local b1=R[buttons[1]]
assert(b1.sealed and b1.bind.icon and b1.bind.cooldown and b1.bind.text and b1.bind.count and b1.bind.pandemic==1,"bindings")
assert(b1.bind.textOpts.binding,"duration text through a binding template")
local binding=b1.bind.textOpts.binding
assert(binding.calls.SetFormatter and binding.calls.SetZeroDurationText=="" and binding.calls.SetExpiredText==""
    and binding.calls.SetUpdateInterval==.1 and binding.calls.SetEnabled==true,"binding fallbacks")
assert(Args(buttons[1],"SetSize")[1]==30 and Args(buttons[1],"SetSize")[2]==27 and Args(buttons[1],"SetMouseClickEnabled")[1]==false
    and Args(buttons[1],"SetMouseMotionEnabled")[1]==false,"compact button size and mouse")
local cd=b1.bind.cooldown
assert(Args(cd,"SetReverse")[1]==true and math.abs(Args(cd,"SetSwipeColor")[4]-.6)<1e-9,"reverse swipe at swipeAlpha")
assert(Args(cd,"SetHideCountdownNumbers")[1]==true,"text comes from the binding")
local shared=R[Buttons(pc,"g2")[1]].bind.textOpts
assert(shared==b1.bind.textOpts,"one template per threshold, shared")

-- retarget: once per frame, target containers only
local before=ts.updates
A.TargetChanged();A.TargetChanged();A.TargetChanged()
assert(timerCount==1,"one next-frame refresh")
RunTimers()
assert(ts.updates==before+1 and ps.updates==0,"UpdateAllAuras on target containers once")

------------------------------------------------------------------ in-place content changes
local adds=ps.adds+ts.adds
local e2b=Aura("buf","a2002","a","player",Set(2002))
Plan("buf",2,{e1,e2b,e3,e4})
A.Sync("buf")
assert(#containers==2 and ps.adds+ts.adds==adds,"new spell reuses the group")
assert(ps.groups.g2.cand.includeSpellIDs[2002] and not ps.groups.g2.cand.includeSpellIDs[2001],"candidate filters updated")
-- both filter and spell list change: spell list first
local e2c=Aura("buf","b13","b","player",Set(1301))
Plan("buf",2,{e1,e2c,e3,e4})
local mark=#ps.log
A.Sync("buf")
local candAt,filterAt
for i=mark+1,#ps.log do
    local row=ps.log[i]
    if row[2]=="g2" and row[1]=="GroupCandidates" then candAt=i end
    if row[2]=="g2" and row[1]=="GroupFilter" then filterAt=i end
end
assert(candAt and filterAt and candAt<filterAt,"spell list before filter string")
assert(ps.groups.g2.filter=="HELPFUL|PLAYER")
-- an entry leaves: its group is switched off, then back on
Plan("buf",2,{e1,e2c,e3})
A.Sync("buf")
assert(ts.groups.g2.enabled==false and LogCount(tc,"GroupEnabled","g2")==1,"12.1.5: surplus group disabled")
Plan("buf",2,{e1,e2c,e3,e4})
A.Sync("buf")
assert(ts.groups.g2.enabled==true and ts.adds==2,"re-enabled, never re-added")

------------------------------------------------------------------ combat
COMBAT=true
local e5=Aura("buf","a2003","a","player",Set(2003))
Plan("buf",2,{e1,e2c,e5,e3,e4})
local addsBefore=ps.adds
A.Sync("buf")
A.Restyle("buf")
assert(ps.adds==addsBefore and A.pending.buf==true,"no structural work in combat")
A.FlushPending()
assert(A.pending.buf==true,"flush waits for combat to end")
COMBAT=false
A.FlushPending()
assert(A.pending.buf==nil and ps.adds==addsBefore+1 and ps.groups.g3,"pending sync after combat")
assert(ps.groups.g3.cand.includeSpellIDs[2003])
-- the target row stays one line down (3 players still fit one line)
assert(ts.points[#ts.points][5]==-29)

------------------------------------------------------------------ restyle in place
local icon1=b1.bind.icon
local coordCalls=Calls(icon1,"SetTexCoord")
buf.zoom=20;buf.styleGen=2
A.Restyle("buf")
assert(#containers==2,"restyle keeps containers")
assert(Calls(icon1,"SetTexCoord")==coordCalls+1,"sealed button restyled while accessible")
local coords=Args(icon1,"SetTexCoord")
assert(math.abs(coords[1]-.1)<1e-9 and math.abs(coords[2]-.9)<1e-9,"zoom crop")
-- 10:9 icons (28x25 inside the 1 px border): the shorter axis is cropped further
local v=.8*25/28
assert(math.abs(coords[3]-(.5-v/2))<1e-9 and math.abs(coords[4]-(.5+v/2))<1e-9,"flat icons keep the art's aspect")
-- per-spell choices on a live button: swipe mode and warning threshold
e1.ov={swipe=3,threshold=4}
A.Sync("buf")
assert(Args(cd,"SetDrawSwipe")[1]==false,"per-spell hidden swipe")
assert(b1.bind.textBinds==2 and b1.bind.textOpts~=shared,"per-spell threshold rebinds the text")
local points=b1.bind.textOpts.binding.calls.SetFormatter.points
assert(points[1].format:find("|cff",1,true) and points[2].threshold==4,"threshold breakpoints")
-- sealed buttons (auras secret): no touch, replaced after the debounce
ACCESS=Secret()
buf.zoom=24;buf.styleGen=3
local count=#containers
A.Restyle("buf")
assert(#containers==count and A.pending.buf==true and timerCount==1,"secret context: debounced rebuild")
RunTimers()
assert(#containers==count+2,"rebuilt with the new look")
assert(R[pc].enabled==false and R[tc].enabled==false,"old containers retired")
pc,tc=Live("buf","player"),Live("buf","target")
ps,ts=R[pc],R[tc]
local nb=R[Buttons(pc,"g1")[1]]
local ncoords=Args(nb.bind.icon,"SetTexCoord")
assert(math.abs(ncoords[1]-.12)<1e-9,"new container carries the new look")
ACCESS=true
-- auras secret (M+ key, PvP match; a secret predicate counts as secret):
-- the structure stays current, the look waits for the auras to open, and
-- no container is created or timer armed (a container is never freed)
AURAS_SECRET=Secret()
buf.zoom=8;buf.styleGen=4
count=#containers
local armed=timerCount
local liveP=pc
A.Restyle("buf")
assert(A.pending.buf==true and #containers==count and timerCount==armed,"secret: deferred, no replacement, no timer")
A.FlushPending()
assert(A.pending.buf==true and #containers==count and Live("buf","player")==liveP,"still secret after combat: still waiting")
AURAS_SECRET=true
buf.zoom=10;buf.styleGen=5
A.Restyle("buf")
assert(A.pending.buf==true and #containers==count and timerCount==armed,"plain secret flag: same")
-- a binding change while secret takes pooled containers: toggling never
-- creates more than one new set, and the pool never drops one
buf.pandemic=false
A.Sync("buf")
assert(#containers==count+2 and Live("buf","player")~=liveP,"new binding set: one new pair")
for _=1,6 do
    buf.pandemic=not buf.pandemic
    A.Sync("buf")
end
assert(#containers==count+2 and buf.pandemic==false,"toggling reuses the pool")
buf.pandemic=true
A.Sync("buf")
assert(Live("buf","player")==liveP and #containers==count+2,"the pooled pair comes back")
AURAS_SECRET=false
A.FlushPending()
assert(A.pending.buf==nil and #containers==count+2,"auras open: restyled in place")
ncoords=Args(nb.bind.icon,"SetTexCoord")
assert(math.abs(ncoords[1]-.05)<1e-9,"the waiting look applied to the live buttons")

------------------------------------------------------------------ fixed places, missing buffs, pool reuse
count=#containers
local compactP,compactT=pc,tc
buf.keepSlots=true
A.Sync("buf")
assert(#containers==count+2,"fixed mode uses slot containers")
assert(R[compactP].enabled==false and R[compactP].shown==false,"compact containers retired: disabled and hidden")
local fp=Live("buf","player")
local fs=R[fp]
assert(fs.order[1]=="s1" and fs.slots.s1 and Count(fs.groups)==0,"one slot per entry")
local slotButton=R[Buttons(fp,"s1")[1]]
assert(slotButton.allPoints==C.bars.buf.cells[1],"slot follows the entry's cell")
assert(not slotButton.args.SetSize,"slot size comes from the cell")
assert(R[Buttons(fp,"s3")[1]].allPoints==C.bars.buf.cells[3],"third entry (a2003) on cell 3")
local ft=Live("buf","target")
assert(R[Buttons(ft,"s1")[1]].allPoints==C.bars.buf.cells[4],"target entries keep their plan cells")
assert(R[ft].slots.s1.filter=="HARMFUL|PLAYER")
-- no placeholders without showMissing
local function Holder(cell)
    local found
    for obj,s in pairs(R) do if s.parent==cell and s.kind=="Texture" and s.shown then found=obj end end
    return found
end
assert(not Holder(C.bars.buf.cells[1]),"no placeholder unless missing buffs are shown")
buf.showMissing=true
A.Sync("buf")
local ph=Holder(C.bars.buf.cells[2])
assert(ph and Args(ph,"SetDesaturated")[1]==true and Args(ph,"SetTexture")[1]==e2c.texture,"dimmed placeholder")
-- entry leaves a fixed bar: 12.1.5 switches its slot off
Plan("buf",2,{e1,e2c,e3,e4})
A.Sync("buf")
assert(fs.slots.s3.enabled==false,"slot switched off")
-- back to compact: the pooled compact containers come back
buf.keepSlots,buf.showMissing=false,false
count=#containers
A.Sync("buf")
assert(#containers==count,"compact containers reused from the pool")
assert(R[compactP].enabled and R[compactP].shown and R[compactT].enabled,"reused containers enabled and shown")
assert(R[fp].enabled==false,"fixed containers retired")
assert(not Holder(C.bars.buf.cells[2]),"placeholders hidden again")

------------------------------------------------------------------ preview
A.SetPreview(true)
assert(R[compactP].shown==false,"compact containers step aside in the preview")
local sample=Holder(C.bars.buf.cells[1])
assert(sample and Args(sample,"SetDesaturated")[1]==false,"preview sample icon per entry")
A.SetPreview(false)
assert(R[compactP].shown==true and not Holder(C.bars.buf.cells[1]),"preview off restores")

------------------------------------------------------------------ buff bars (kind 3)
C.views.bar=View("bar",3)
local barView=C.views.bar
local k1=Aura("bar","b21","b","player",Set(2101))
local k2=Aura("bar","b22","b","player",Set(2201))
Plan("bar",3,{k1,k2})
count=#containers
A.Sync("bar")
assert(#containers==count+1,"player container only")
local bc=Live("bar","player")
local bs=R[bc]
local bb=R[Buttons(bc,"g1")[1]]
assert(bb.bind.bar and bb.bind.barOpts.direction==1,"drain bar via RemainingTime")
assert(bb.bind.name and bb.bind.text and bb.bind.icon and bb.bind.count,"name, time, icon and stacks bound")
assert(not bb.bind.cooldown,"no swipe on bars")
assert(Args(Buttons(bc,"g1")[1],"SetSize")[1]==220 and Args(Buttons(bc,"g1")[1],"SetSize")[2]==20,"bar size")
assert(barView.grow==1,"Buff bars grow down by default")
assert(bs.flow.anchor=="TOPLEFT" and bs.flow.v==-1 and math.abs(bs.flow.line-220)<.1,"one bar per line, growing down")
assert(bs.points[1][1]=="TOP" and bs.points[1][2]==C.bars.bar.auraHost,"bars hang from the top edge")
barView.grow=2
A.Sync("bar")
assert(Live("bar","player")==bc and bs.flow.anchor=="BOTTOMLEFT" and bs.flow.v==1 and bs.points[1][1]=="BOTTOM","growing up in place")
barView.grow=1
A.Sync("bar")
assert(bs.flow.anchor=="TOPLEFT" and bs.points[1][1]=="TOP")
barView.barFill=2
A.Sync("bar")
local bc2=Live("bar","player")
assert(bc2~=bc and R[Buttons(bc2,"g1")[1]].bind.barOpts.direction==0,"fill direction is a new binding set")

------------------------------------------------------------------ cooldown overlays (kind 1)
C.views.ess=View("ess",1)
local ess=C.views.ess
local bar=L.EnsureBar("ess")
-- A cooldown icon the layout shows (Layout's shown memo on our own frame).
local function Icon() local icon=CreateFrame("Frame",nil,bar.frame);icon.layShown=true;return icon end
local o1={key="b31",src="b",family=1,hasAura=true,selfAura=true,unit="player",auraIDs=Set(3101,3102),ov=C.EMPTY,icon=Icon(),slot="ess",linked=C.EMPTY}
local o2={key="b32",src="b",family=1,hasAura=true,unit="target",auraIDs=Set(3201),ov=C.EMPTY,icon=Icon(),slot="ess",linked=C.EMPTY}
local o3={key="b33",src="b",family=1,hasAura=false,ov=C.EMPTY,icon=Icon(),slot="ess",linked=C.EMPTY}
local o4={key="b34",src="b",family=1,hasAura=true,unit="player",auraIDs=Set(3401),ov={showAura=false},icon=Icon(),slot="ess",linked=C.EMPTY}
Plan("ess",1,{o1,o2,o3,o4})
count=#containers
A.Sync("ess")
assert(#containers==count+2,"overlay container per unit")
local oc,ot=Live("ess","player",true),Live("ess","target",true)
local os=R[oc]
assert(#os.order==1 and os.slots.s1.filter=="HELPFUL|PLAYER" and os.slots.s1.cand.includeSpellIDs[3102],"one slot per aura entry")
assert(#R[ot].order==1 and R[ot].slots.s1.filter=="HARMFUL|PLAYER","target overlay")
local ob=R[Buttons(oc,"s1")[1]]
assert(ob.allPoints==o1.icon,"overlay covers its cooldown icon")
local ocd=ob.bind.cooldown
local swipe=Args(ocd,"SetSwipeColor")
assert(swipe[1]==1 and math.abs(swipe[2]-.82)<1e-9 and swipe[4]==.55 and Args(ocd,"SetReverse")[1]==true,"gold reverse swipe")
assert(ob.bind.text and ob.bind.icon and not ob.bind.pandemic,"full-cover icon and duration text")
assert(os.level==bar.frame:GetFrameLevel()+2,"above the icon")
-- icon frame changed: new slot on the new icon, old slot off
o1.icon=Icon()
A.SyncOverlays("ess")
assert(os.slots.s2 and R[Buttons(oc,"s2")[1]].allPoints==o1.icon and os.slots.s1.enabled==false,"rebuilt on the new icon")
-- retarget reaches overlay target containers too
local tu=R[ot].updates
A.TargetChanged()
RunTimers()
assert(R[ot].updates==tu+1)
ess.showAura=false
A.Sync("ess")
assert(R[oc].enabled==false and R[ot].enabled==false,"overlays off with the bar setting")
-- the new Defensives bar (class preset list) is a cooldown bar like Essential:
-- overlays on icons whose spell has an aura; a preset-only spell has none
do
    C.views.def=View("def",1)
    assert(C.views.def.showAura==true,"Defensives show active buff durations by default")
    local host=L.EnsureBar("def").frame
    local d1={key="b51",src="b",family=1,hasAura=true,selfAura=true,unit="player",auraIDs=Set(5101),ov=C.EMPTY,
        icon=CreateFrame("Frame",nil,host),slot="def",linked=C.EMPTY}
    local d2={key="s48707",src="s",family=1,hasAura=false,presetSpell=true,ov=C.EMPTY,
        icon=CreateFrame("Frame",nil,host),slot="def",linked=C.EMPTY}
    Plan("def",1,{d1,d2})
    count=#containers
    A.Sync("def")
    assert(#containers==count+1,"one player overlay container on Defensives")
    local dc=Live("def","player",true)
    assert(dc and #R[dc].order==1 and R[Buttons(dc,"s1")[1]].allPoints==d1.icon,"overlay on the aura spell only")
    assert(not Live("def","player"),"no aura containers on a cooldown bar")
    A.Release("def")
    assert(R[dc].enabled==false and R[dc].shown==false,"released with the bar")
    C.plans.def=nil
end

------------------------------------------------------------------ 12.1.0 shape
V125=false
C.views.c1=View("c1",2)
local c1=C.views.c1
c1.keepSlots=true
local x1=Aura("c1","a61","a","player",Set(61))
local x2=Aura("c1","a62","a","player",Set(62))
Plan("c1",2,{x1,x2})
A.Sync("c1")
local xc=Live("c1","player")
local xs=R[xc]
assert(xs.editPreview==nil,"no Edit Mode opt-out on 12.1.0")
Plan("c1",2,{x1})
A.Sync("c1")
local neutral=xs.slots.s2.cand
assert(neutral.maxDuration==0 and not neutral.includeSpellIDs,"12.1.0 slot neutralized by maxDuration=0")
Plan("c1",2,{x1,x2})
A.Sync("c1")
assert(xs.slots.s2.cand.includeSpellIDs[62] and xs.adds==2,"slot restored in place")
c1.keepSlots=false
A.Sync("c1")
local gc=Live("c1","player")
Plan("c1",2,{x1})
A.Sync("c1")
assert(R[gc].groups.g2.max==0,"12.1.0 group neutralized by max count 0")
Plan("c1",2,{x1,x2})
A.Sync("c1")
assert(R[gc].groups.g2.max==1)
V125=true

------------------------------------------------------------------ release
A.Release("c1")
assert(R[gc].enabled==false and R[gc].shown==false)
A.ReleaseAll()
for _,c in ipairs(containers) do assert(R[c].enabled==false,"every container disabled") end
before=timerCount
A.TargetChanged()
assert(timerCount==before,"no target containers, no refresh")
A.Sync("buf")
assert(Live("buf","player")==compactP,"re-enable reuses the pool")

------------------------------------------------------------------ real Layout interface
do
    local chunk=loadfile(root.."/MSUF_Suite_CooldownManager/Layout.lua")
    if chunk then
        local C2={EMPTY={},views={},plans={},bars={},entries={},state={px=1}}
        chunk("MSUF_Suite_CooldownManager",{NS=NS,Suite=S,CDM=C2})
        local L2=C2.Layout
        assert(type(L2.EnsureBar)=="function" and type(L2.Cell)=="function" and type(L2.Metrics)=="function","Layout interface")
        C2.views.buf=View("buf",2)
        C2.plans.buf={slot="buf",kind=2,entries={e1,e3},gen=1}
        local w,h,sp,per,vertical,grow,align=L2.Metrics(C2.views.buf)
        assert(w==30 and h==27 and sp==2 and per==10 and vertical==false and grow==1 and align==1,"Layout metrics")
        -- the stand-in above agrees with the real Layout for both aura kinds
        local a={L.Metrics(C2.views.buf)}
        local b={L2.Metrics(C2.views.buf)}
        for i=1,7 do assert(a[i]==b[i],"icon metrics stand-in at "..i) end
        C2.views.bar=View("bar",3)
        a,b={L.Metrics(C2.views.bar)},{L2.Metrics(C2.views.bar)}
        for i=1,7 do assert(a[i]==b[i],"bar metrics stand-in at "..i) end
        assert(b[1]==220 and b[2]==20 and b[4]==1 and b[6]==1,"Buff bars: 220x20, one per line, growing down")
        C2.views.bar.grow=2
        assert(select(6,L2.Metrics(C2.views.bar))==2,"Buff bars grow up on request")
        local bar2=L2.EnsureBar("buf")
        assert(bar2.frame and bar2.auraHost and type(bar2.cells)=="table","bar record")
        assert(L2.Cell("buf",2)==bar2.cells[2],"cell per plan position")
    else
        print("note: Layout.lua not loadable, interface check skipped")
    end
end

------------------------------------------------------------------ alerts: ready sounds and speech
local r1={key="b41",family=1,name="Fireball",ov={sound="kit:1234"}}
Alerts.Ready(r1)
assert(played.kits==1 and played.kit==1234 and played.kitChannel=="Master","ready kit sound")
Alerts.Ready(r1)
assert(played.kits==1,"1 s throttle per entry")
NOW=NOW+1.1
Alerts.Ready(r1)
assert(played.kits==2)
C.state.muteSounds=true
NOW=NOW+2
Alerts.Ready(r1)
assert(played.kits==2,"muted")
C.state.muteSounds=false
C.state.soundQuietUntil=NOW+2
Alerts.Ready(r1)
assert(played.kits==2,"quiet after a loading screen")
NOW=NOW+2.5
Alerts.Ready(r1)
assert(played.kits==3)
C.state.soundChannel="SFX"
local r2={key="b42",family=1,name="Frost Nova",ov={sound="lsm:Boom",tts=true}}
Alerts.Ready(r2)
assert(played.files==1 and played.file=="Sound\\Boom.ogg" and played.fileChannel=="SFX","LSM sound on the chosen channel")
assert(played.speech==1 and played.text=="Frost Nova","speaks the name")
local r3={key="b43",family=1,name=Secret(),ov={tts=true}}
Alerts.Ready(r3)
assert(played.speech==1,"secret names are never spoken")
Alerts.Ready({key="a9",family=2,ov={sound="kit:1"}})
assert(played.kits==3,"aura entries sound natively")
C.state.muteSounds=true
assert(Alerts.Play("file:555")==false and played.files==1,"preview respects mute unless forced")
assert(Alerts.Play("file:555",true)==true and played.files==2 and played.file==555,"forced preview")
assert(Alerts.Play("lsm:None",true)==false and Alerts.Play("bogus",true)==false,"silent values")
C.state.muteSounds=false
C.state.soundChannel="Master"
-- allocation-free ready path
collectgarbage("collect")
collectgarbage("stop")
local mem=collectgarbage("count")
for _=1,2000 do NOW=NOW+1.5;Alerts.Ready(r1) end
local grew=collectgarbage("count")-mem
collectgarbage("restart")
assert(grew<1,"ready alerts allocate nothing ("..grew.." KB)")

------------------------------------------------------------------ alerts: native aura sounds
local s1=Aura("buf","a71","a","player",Set(71),{ov={sound="file:777",lossSound="lsm:Boom"}})
local s2=Aura("buf","a72","a","player",Set(71),{ov={sound="file:777"}})
local s3=Aura("buf","d73","d","target",Set(73),{ov={sound="kit:5"}})
Plan("buf",2,{s1,s2,s3})
C.plans.ess,C.plans.bar,C.plans.c1=nil,nil,nil
Alerts.SyncAuraSounds()
assert(SoundCount()==2,"shared registration counted once; kits cannot be registered")
local added,removed
for _,row in pairs(auraSounds) do
    if row.trigger==0 then added=row else removed=row end
end
assert(added.unit=="player" and added.spell==71 and added.file==777 and added.channel=="Master","gain sound")
assert(removed.trigger==2 and removed.name=="Sound\\Boom.ogg","loss sound")
local n,have=Alerts.Registrations()
local refs=0
for _,reg in pairs(have) do refs=math.max(refs,reg.refs) end
assert(n==2 and refs==2,"reference counted")
s2.ov={}
Alerts.SyncAuraSounds()
assert(SoundCount()==2,"still wanted by one entry")
s1.ov={}
Alerts.SyncAuraSounds()
assert(SoundCount()==0,"released when unused")
s1.ov={sound="file:777"}
COMBAT=true
Alerts.SyncAuraSounds()
assert(SoundCount()==0 and Alerts.pending==true,"out of combat only")
COMBAT=false
A.FlushPending()
assert(SoundCount()==1 and Alerts.pending==false,"registered after combat")
C.state.soundQuietUntil=NOW+2
Alerts.SyncAuraSounds()
assert(SoundCount()==0 and timerCount==1,"quiet window drops registrations and waits")
NOW=NOW+2.2
RunTimers()
assert(SoundCount()==1,"back after the quiet window")
C.state.muteSounds=true
Alerts.SyncAuraSounds()
assert(SoundCount()==0,"mute drops registrations")
C.state.muteSounds=false
Alerts.SyncAuraSounds()
assert(SoundCount()==1)
C.state.soundQuietUntil=NOW+2
Alerts.SyncAuraSounds()
Alerts.ReleaseAll()
NOW=NOW+3
RunTimers()
assert(SoundCount()==0,"release wins over a pending quiet timer")

------------------------------------------------------------------ allocation-free retarget
A.Sync("buf")
collectgarbage("collect")
collectgarbage("stop")
mem=collectgarbage("count")
for _=1,500 do A.TargetChanged();RunTimers() end
grew=collectgarbage("count")-mem
collectgarbage("restart")
assert(grew<1,"retarget refresh allocates nothing ("..grew.." KB)")

do
------------------------------------------------------------------ Blizzard entries watch both units
-- Blizzard's viewer looks for a tracked aura on the player and on the
-- target, so a "both" entry has a group in each container; player places
-- come first, the target row starts after the lines the layout reserves.
C.views.c2=View("c2",2)
local both=C.views.c2
both.perRow,both.size,both.height,both.spacing,both.grow=2,30,100,2,1
local w1=Aura("c2","b81","b","both",Set(8101),{selfAura=true})
local w2=Aura("c2","b82","b","both",Set(8201),{selfAura=false})
local w3=Aura("c2","a83","a","player",Set(8301))
local w4=Aura("c2","d84","d","target",Set(8401))
Plan("c2",2,{w1,w2,w3,w4})
count=#containers
A.Sync("c2")
assert(#containers==count+2,"one container per unit")
local bothP,bothT=Live("c2","player"),Live("c2","target")
local bp,bt=R[bothP],R[bothT]
assert(#bp.order==3 and #bt.order==3,"each unit: its own entries plus the both entries")
assert(bp.groups.g1.cand.includeSpellIDs[8101] and bp.groups.g2.cand.includeSpellIDs[8201] and bp.groups.g3.cand.includeSpellIDs[8301])
assert(bt.groups.g1.cand.includeSpellIDs[8101] and bt.groups.g2.cand.includeSpellIDs[8201] and bt.groups.g3.cand.includeSpellIDs[8401])
assert(bp.groups.g1.filter=="HELPFUL|PLAYER" and bp.groups.g3.filter=="HELPFUL","player side: own buffs, any caster for custom")
assert(bt.groups.g1.filter=="HARMFUL|PLAYER" and bt.groups.g3.filter=="HARMFUL|PLAYER","target side: own debuffs only")
assert(bp.groups.g2.layout.layoutIndex==2 and bt.groups.g2.layout.layoutIndex==2 and bt.groups.g3.layout.layoutIndex==4,
    "a both entry keeps its plan place in both rows")
-- rows: a both entry takes the row the catalog's selfAura hint names, so
-- a tracked debuff (a DoT) holds its place in the target row, where it
-- shows. Player row b81 + a83 (one line at two per row), target row b82 +
-- d84 one 30 px line plus spacing further down.
assert(A.TargetRow(w2) and A.TargetRow(w4) and not A.TargetRow(w1) and not A.TargetRow(w3),"row rule")
assert(bp.points[1][5]==0 and bt.points[1][5]==-32,"target row after the player places")
Plan("c2",2,{w2,w4})
A.Sync("c2")
assert(bt.points[#bt.points][5]==0,"a bar of tracked debuffs starts at the growth point")
Plan("c2",2,{w1,w2,w3,w4})
A.Sync("c2")
assert(bt.points[#bt.points][5]==-32)
do
    local chunk=loadfile(root.."/MSUF_Suite_CooldownManager/Layout.lua")
    if chunk then
        local C3={EMPTY={},views={c2=both},plans={c2=C.plans.c2},bars={},entries={},state={px=1},Auras={TargetRow=A.TargetRow}}
        chunk("MSUF_Suite_CooldownManager",{NS=NS,Suite=S,CDM=C3})
        C3.Layout.Apply("c2")
        local lb=C3.bars.c2
        -- the target row (one line) starts inside the layout's footprint
        assert(lb.lines1>=1 and lb.lines1+lb.lines2>=2,"the real layout reserves the player line and the target line")
    end
end
-- fixed places: both units of an entry share its cell (only one of them
-- can match: own buffs on you, own debuffs on a hostile target)
both.keepSlots=true
A.Sync("c2")
local fixedP,fixedT=Live("c2","player"),Live("c2","target")
local cells=C.bars.c2.cells
assert(R[Buttons(fixedP,"s1")[1]].allPoints==cells[1] and R[Buttons(fixedT,"s1")[1]].allPoints==cells[1],"one cell for both units")
assert(R[Buttons(fixedP,"s2")[1]].allPoints==cells[2] and R[Buttons(fixedT,"s2")[1]].allPoints==cells[2])
assert(R[Buttons(fixedP,"s3")[1]].allPoints==cells[3] and R[Buttons(fixedT,"s3")[1]].allPoints==cells[4],"single-unit entries on their own cells")
both.keepSlots=false
A.Sync("c2")
assert(Live("c2","player")==bothP and Live("c2","target")==bothT,"compact pair back from the pool")

------------------------------------------------------------------ friendly target pause
-- Own debuffs on a friendly unit bypass spell-ID filters (12.1.0 shows all
-- of them), so every target container pauses while the target is friendly.
-- Container-level switches only, legal in combat, nothing while it holds.
local function TargetStates(state)
    for _,c in ipairs(containers) do
        local s=R[c]
        if s.unit=="target" and s.shown~=false and s.adds>0 and s.pausable then
            if s.enabled~=state then return false end
        end
    end
    return true
end
for _,c in ipairs(containers) do
    local s=R[c]
    if s.unit=="target" and s.enabled and s.shown~=false then s.pausable=true end
end
local upd=bt.updates
FRIENDLY=true
A.TargetChanged()
assert(bt.enabled==false and TargetStates(false),"friendly target: every target container paused at once")
assert(bp.enabled==true,"player containers keep running")
RunTimers()
assert(bt.updates==upd,"a paused container is not refreshed")
local sets=LogCount(bothT,"SetEnabled")
A.TargetChanged();A.TargetChanged()
RunTimers()
assert(LogCount(bothT,"SetEnabled")==sets and bt.updates==upd,"still friendly: no container call")
-- a sync while friendly builds new target containers paused
both.pandemic=false
A.Sync("c2")
local fresh=Live("c2","player")
local freshT
for _,c in ipairs(containers) do if R[c].parent==C.bars.c2.auraHost and R[c].unit=="target" and R[c].shown then freshT=c end end
assert(fresh~=bothP and freshT and R[freshT].enabled==false,"new target container starts paused")
both.pandemic=true
A.Sync("c2")
assert(Live("c2","player")==bothP and bt.enabled==false,"pooled target container comes back paused")
-- in combat: a duel starts (UNIT_FACTION) and the disposition flips
COMBAT=true
local addsNow=bp.adds+bt.adds
FRIENDLY=false
A.TargetReaction()
assert(bt.enabled==true and TargetStates(true) and bp.adds+bt.adds==addsNow,"hostile again: resumed in combat, no structure")
sets=LogCount(bothT,"SetEnabled")
local asks=assistCalls
A.TargetReaction()
assert(LogCount(bothT,"SetEnabled")==sets and assistCalls==asks+1,"unchanged disposition: one check, no call")
FRIENDLY=Secret()
A.TargetReaction()
assert(bt.enabled==true,"an unreadable disposition never pauses")
FRIENDLY=true
A.TargetReaction()
assert(bt.enabled==false,"friendly again in combat: paused")
FRIENDLY=false
upd=bt.updates
A.TargetChanged()
RunTimers()
assert(bt.enabled==true and bt.updates==upd+1 and TargetStates(true),"hostile retarget: resumed and refreshed once")
COMBAT=false
FRIENDLY=false
-- Visibility hides the bar (its rule, or opacity 0): the containers hide
-- with it, so invisible buttons take no mouse or tooltip and no aura work
-- runs. Container writes only, in combat too; not a retirement.
COMBAT=true
A.SetBarMouse("c2",false)
assert(bp.shown==false and bt.shown==false and bp.enabled and bt.enabled,"hidden with the bar, in combat")
local shownCalls=Calls(bothP,"SetShown")+Calls(bothT,"SetShown")
A.SetBarMouse("c2",false)
assert(Calls(bothP,"SetShown")+Calls(bothT,"SetShown")==shownCalls,"unchanged: no call")
COMBAT=false
both.pandemic=false
A.Sync("c2")
local hiddenNew=Live("c2","player")
assert(hiddenNew==nil,"a container built while the bar is hidden starts hidden")
A.SetPreview(true)
A.SetPreview(false)
both.pandemic=true
A.Sync("c2")
assert(bp.shown==false,"a pooled container comes back hidden")
A.SetBarMouse("c2",true)
assert(bp.shown==true and bt.shown==true and Live("c2","player")==bothP,"shown again with the bar")
A.SetPreview(true)
assert(bp.shown==false,"the preview still draws compact entries on their cells")
A.SetBarMouse("c2",false)
A.SetBarMouse("c2",true)
assert(bp.shown==false,"showing the bar keeps the preview rule")
A.SetPreview(false)
assert(bp.shown==true)
C.plans.c2=nil
A.Release("c2")

end

do
------------------------------------------------------------------ overlays follow their icons
-- An overlay slot sits on its icon (SetAllPoints) but is the container's
-- child: the layout switches it with the icon's shown state, in combat too.
C.views.uti=View("uti",1)
local uti=C.views.uti
uti.showAura,uti.hideReady,uti.maxIcons=true,true,0
local utiHost=L.EnsureBar("uti").frame
local function UtiIcon(shown) local icon=CreateFrame("Frame",nil,utiHost);icon.layShown=shown;return icon end
local function Over(key,icon,extra)
    local e={key=key,src="b",id=tonumber(key:sub(2)),family=1,hasAura=true,unit="both",auraIDs=Set(tonumber(key:sub(2))*100+1),
        ov=C.EMPTY,icon=icon,slot="uti",linked=C.EMPTY}
    if extra then for k,v in pairs(extra) do e[k]=v end end
    return e
end
local q1,q2,q3=Over("b91",UtiIcon(true)),Over("b92",UtiIcon(false)),Over("b93",UtiIcon(nil))
Plan("uti",1,{q1,q2,q3})
count=#containers
A.Sync("uti")
assert(#containers==count+2,"overlay container per unit")
local qc,qt=Live("uti","player",true),Live("uti","target",true)
local qp,qs=R[qc],R[qt]
assert(#qp.order==3 and #qs.order==3,"a both entry has a slot in each container")
assert(R[Buttons(qc,"s1")[1]].allPoints==q1.icon and R[Buttons(qt,"s1")[1]].allPoints==q1.icon,"both slots on the icon")
assert(qp.slots.s1.enabled==true and qp.slots.s2.enabled==false and qp.slots.s3.enabled==false,"slots start with their icon")
assert(qs.slots.s1.enabled==true and qs.slots.s2.enabled==false and qs.slots.s3.enabled==false)
-- hideReady edges in combat: container switches only
COMBAT=true
local structure=qp.adds+qs.adds
q2.icon.layShown=true
A.OverlayShown(q2,true)
assert(qp.slots.s2.enabled==true and qs.slots.s2.enabled==true,"icon shown: its overlay shows")
q1.icon.layShown=false
A.OverlayShown(q1,false)
assert(qp.slots.s1.enabled==false and qs.slots.s1.enabled==false,"icon hidden: its overlay goes with it")
assert(qp.adds+qs.adds==structure and A.pending.uti==nil,"no structural work")
local switches=LogCount(qc,"SlotEnabled")+LogCount(qt,"SlotEnabled")
A.OverlayShown(q1,false);A.OverlayShown(q2,true);A.OverlayShown(q2,true)
assert(LogCount(qc,"SlotEnabled")+LogCount(qt,"SlotEnabled")==switches,"unchanged state: no call")
-- an in-combat resolve pools q2's icon and binds it to another entry: the
-- old slot never shows the old spell's aura on the new spell's icon
local reused=q2.icon
A.OverlayShown(q2,false,reused)
q2.icon=nil
local q4=Over("b94",reused)
A.OverlayShown(q4,true)
assert(qp.slots.s2.enabled==false and qs.slots.s2.enabled==false,"a rebound icon keeps the old slot off")
A.OverlayShown(nil,false,reused)
A.OverlayShown({icon=UtiIcon(true)},true)
A.OverlayShown(nil,true)
COMBAT=false
-- out of combat the rebuild keys the slot to the entry on the icon
Plan("uti",1,{q1,q4,q3})
A.Sync("uti")
assert(qp.slots.s2.enabled==true and qp.slots.s2.cand.includeSpellIDs[9401] and not qp.slots.s2.cand.includeSpellIDs[9201],
    "slot follows the new entry")
assert(qp.slots.s1.enabled==false,"a rebuild keeps a hidden icon's overlay off")
-- maxIcons: an icon behind maxIcons icons that never hide gets no slot
uti.hideReady,uti.maxIcons=false,1
q1.icon.layShown=true
A.Sync("uti")
assert(qp.slots.s1.enabled==true and qp.slots.s2.enabled==false and qp.slots.s3.enabled==false,"only the first icon can show")
uti.hideReady=true
A.Sync("uti")
assert(qp.slots.s2.enabled==true,"with hideReady any icon may move up")
q1.ov={hideReady=false}
A.Sync("uti")
assert(qp.slots.s2.enabled==false,"per-spell rule: the first icon always holds the one place")
q1.ov=C.EMPTY
local ph=Over("p1",UtiIcon(true),{src="p",hasAura=false})
Plan("uti",1,{ph,q1,q4,q3})
A.Sync("uti")
assert(qp.enabled==false and qs.enabled==false,"a placeholder never hides and holds the one place: nothing to overlay")
uti.maxIcons=0
Plan("uti",1,{q1,q4,q3})
A.Sync("uti")
assert(Live("uti","player",true)==qc and qp.slots.s1.enabled==true and qp.slots.s2.enabled==true and qp.adds==3,"all back from the pool, no new slots")
-- the switch costs nothing for icons without an overlay and allocates nothing
local plain={icon=UtiIcon(true)}
collectgarbage("collect")
collectgarbage("stop")
mem=collectgarbage("count")
for _=1,2000 do A.OverlayShown(plain,true);A.OverlayShown(q1,true);A.OverlayShown(nil,false) end
grew=collectgarbage("count")-mem
collectgarbage("restart")
assert(grew<1,"overlay switch allocates nothing ("..grew.." KB)")
-- 12.1.0: no slot enable flag; a hidden icon's slot carries NONE and gets
-- the current spell list back when it shows
V125=false
C.views.c3=View("c3",1)
local legacy=C.views.c3
legacy.showAura,legacy.hideReady,legacy.maxIcons=true,true,0
local c3Host=L.EnsureBar("c3").frame
local r1={key="b96",src="b",family=1,hasAura=true,unit="player",auraIDs=Set(9601),ov=C.EMPTY,slot="c3",linked=C.EMPTY,
    icon=CreateFrame("Frame",nil,c3Host)}
r1.icon.layShown=true
Plan("c3",1,{r1})
A.Sync("c3")
local lc=Live("c3","player",true)
local ls=R[lc]
assert(ls.slots.s1.cand.includeSpellIDs[9601],"12.1.0 overlay live")
COMBAT=true
r1.icon.layShown=false
A.OverlayShown(r1,false)
assert(ls.slots.s1.cand.maxDuration==0 and not ls.slots.s1.cand.includeSpellIDs,"12.1.0: NONE while the icon is hidden")
COMBAT=false
r1.auraIDs=Set(9602)
local candWrites=LogCount(lc,"SlotCandidates")
A.Sync("c3")
assert(ls.slots.s1.cand.maxDuration==0 and LogCount(lc,"SlotCandidates")==candWrites,"a resync while hidden keeps NONE")
COMBAT=true
r1.icon.layShown=true
A.OverlayShown(r1,true)
assert(ls.slots.s1.cand.includeSpellIDs[9602] and not ls.slots.s1.cand.includeSpellIDs[9601],"back with the current list")
COMBAT=false
V125=true
-- overlays hide with their cooldown bar
COMBAT=true
A.SetBarMouse("uti",false)
assert(qp.shown==false and qs.shown==false and qp.enabled,"overlay containers hidden with the bar")
A.SetBarMouse("uti",true)
assert(qp.shown==true and qs.shown==true)
COMBAT=false
C.plans.uti,C.plans.c3=nil,nil
A.Release("uti");A.Release("c3")

end

do
------------------------------------------------------------------ sounds for both units
-- "both" is no unit token: Blizzard entries register for the player, and
-- for the target too unless the catalog calls the aura a self aura.
for id in pairs(auraSounds) do auraSounds[id]=nil end
local y1=Aura("buf","b87","b","both",Set(87),{selfAura=true,ov={sound="file:887"}})
local y2=Aura("buf","b88","b","both",Set(88),{selfAura=false,ov={sound="file:888",lossSound="file:889"}})
Plan("buf",2,{y1,y2})
Alerts.SyncAuraSounds()
local units={}
for _,row in pairs(auraSounds) do units[row.spell..row.unit..row.trigger]=true end
assert(SoundCount()==5,"one self aura, two both-unit sounds")
assert(units["87player0"] and not units["87target0"],"a self aura sounds for the player only")
assert(units["88player0"] and units["88target0"] and units["88player2"] and units["88target2"],"gain and loss on both units")
Alerts.ReleaseAll()
assert(SoundCount()==0)

end

print("suite_cooldown_manager_auras_contract: ok")
