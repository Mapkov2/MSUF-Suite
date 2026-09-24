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
    IsEditModePreviewEnabled=true,GetAuraSlotFrame=true,AddAuraShownAnimation=true}
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
    if s.button then
        m=ButtonMethods[key]
        if m and V125_ONLY[key] and not R[s.parent].v125 then m=nil end
    end
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

-- A parent keeps its children (and animation groups their animations), as
-- in the client: R is weak-keyed, so a child only the addon's locals held
-- (an animation group, a flipbook) would otherwise vanish in a GC cycle.
local function New(kind,parent,mt)
    local obj=setmetatable({},mt or RegionMT)
    local ps=parent and R[parent]
    R[obj]={kind=kind,parent=parent,shown=true,points={},level=ps and ps.level+1 or 0,calls={},args={}}
    if ps then
        local kids=ps.kids
        if not kids then kids={};ps.kids=kids end
        kids[#kids+1]=obj
    end
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
    "SetShadowColor","SetAtlas","SetClipsChildren","SetLooping","SetFromAlpha","SetToAlpha","SetDuration",
    "SetFlipBookRows","SetFlipBookColumns","SetFlipBookFrames","SetFlipBookFrameWidth","SetFlipBookFrameHeight"}) do
    Methods[name]=Record(name)
end
local play,stop=Record("Play"),Record("Stop")
function Methods:Play() play(self);R[self].playing=true end
function Methods:Stop() stop(self);R[self].playing=false end
function Methods:CreateAnimationGroup() return New("AnimationGroup",self) end
function Methods:CreateAnimation(kind)
    assert(R[self].kind=="AnimationGroup","animations live in groups")
    assert(kind=="Alpha" or kind=="FlipBook","animation type "..tostring(kind))
    return New(kind,self)
end
-- The fill texture a StatusBar sizes from its value (Blizzard's side).
function Methods:GetStatusBarTexture()
    local s=R[self]
    assert(s.kind=="StatusBar","status bar texture")
    if not s.fill then s.fill=New("Texture",self) end
    return s.fill
end
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
-- The one script use: kit sound sensors. A plain frame inside an aura
-- button hears the button show and hide; a plain frame on the bar host
-- beside a kit container hears the host (or the UI) show and hide. Only
-- OnShow and OnHide, never on a Blizzard object.
local function InButton(obj)
    local s=R[obj]
    local parent=s and s.parent
    while parent do
        if R[parent].button then return true end
        parent=R[parent].parent
    end
    return false
end
local scripted={}
function Methods:SetScript(key,fn)
    local s=R[self]
    assert(s.kind=="Frame","scripts only on plain frames")
    assert((key=="OnShow" or key=="OnHide") and type(fn)=="function","sensor scripts: OnShow and OnHide")
    s.scripts=s.scripts or {}
    s.scripts[key]=fn
    s.sensor=InButton(self)
    scripted[self]=true
end
function Methods:HookScript() error("no hooks on aura layer regions",2) end
-- Blizzard's side of a bound value: kept for secret checks, never readable
-- by the addon without raising when it is a secret.
function Methods:GetValue() return R[self].value end
function Methods:GetText() return R[self].text end

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
-- Options are securecopied by Blizzard; the formatter object inside is
-- shared (the identity is what the test checks).
function ButtonMethods:SetApplicationCount(fs,opts)
    Descendant(fs,self,"FontString")
    local b=R[self].bind
    if opts~=nil then
        assert(type(opts)=="table" and opts.formatter and type(opts.formatter.FormatNumber)=="function",
            "count options carry a numeric rule formatter")
    end
    b.count,b.countFormatter,b.countBinds=fs,opts and opts.formatter,(b.countBinds or 0)+1
end
function ButtonMethods:SetApplicationBar(bar,opts)
    Descendant(bar,self,"StatusBar")
    assert(type(opts)=="table" and type(opts.maxApplications)=="number" and opts.maxApplications>=1,
        "application bar needs maxApplications")
    local b=R[self].bind
    b.appBar,b.appOpts,b.appBinds=bar,SecureCopy(opts),(b.appBinds or 0)+1
end
function ButtonMethods:AddAuraShownAnimation(group)
    Descendant(group,self,"AnimationGroup")
    local b=R[self].bind
    b.shownAnims=(b.shownAnims or 0)+1
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
-- FormatNumber stands in for Blizzard's C side: the last breakpoint at or
-- below the value picks the format (components ignored).
local formatters={}
C_StringUtil={CreateNumericRuleFormatter=function()
    local formatter={SetBreakpoints=function(self,points) self.points=SecureCopy(points) end}
    function formatter:FormatNumber(value)
        local pick
        for _,point in ipairs(self.points) do if value>=point.threshold then pick=point end end
        if not pick or pick.format=="" then return "" end
        return (pick.format:gsub("%%%.0f","%%d")):format(value)
    end
    formatters[#formatters+1]=formatter
    return formatter
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
-- Metrics, FixedAuras); the real Layout.lua is checked against it further
-- down.
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
-- The one fixed-places rule (containers, layout and controller share it).
-- Within maxIcons, n1 counts the player part ("both" included), n2 the
-- target entries. Fixed: keepSlots, showMissing (bar or any spell), or a
-- column that mixes both parts (vertical on one line, or one icon per
-- line). Ordered: fixed on one line (or one icon per line). A horizontal
-- mixed row on one line is fixed and ordered when start or end aligned and
-- split (third value, compact) when centered.
function L.FixedAuras(view,entries)
    local cap=view.maxIcons
    if type(cap)~="number" or cap<=0 or cap>#entries then cap=#entries end
    local n1,n2=0,0
    for i=1,cap do if entries[i].unit=="target" then n2=n2+1 else n1=n1+1 end end
    local _,_,_,per,vertical,_,align=L.Metrics(view)
    local n=n1+n2
    local fixed=view.keepSlots==true or view.showMissing==true
    for i=1,#entries do
        local ov=entries[i].ov
        if ov and ov.showMissing==true then fixed=true end
    end
    local line,split=n<=per,false
    if not fixed and n1>0 and n2>0 then
        if vertical then fixed=line
        elseif per==1 then fixed=true
        elseif line then split=align==1;fixed=not split end
    end
    return fixed,fixed and (line or per==1),split
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
    for _,word in ipairs({"pcall","loadstring","setfenv","hooksecurefunc","HookScript","OnUpdate",
        "RegisterEvent","RegisterUnitEvent","NewTicker","SetAuraBorder","SetAuraSymbol","Claude","Anthropic"}) do
        assert(not text:find(word,1,true),file.." must not contain "..word)
    end
    -- Stack counts, bar values and shown states stay in C: nothing reads
    -- them back (no Lua comparison of a secret count can exist).
    for _,word in ipairs({":GetValue(",":GetText(",":IsShown(",":IsVisible(",".applications",":GetApplication",
        ":GetMinMaxValues("}) do
        assert(not text:find(word,1,true),file.." must not read "..word)
    end
    -- Scripts: kit sensors only (OnShow/OnHide on our own frames, Auras.lua).
    local scripts=0
    for key in text:gmatch(":SetScript%(\"(%a+)\"") do
        assert(file=="Auras.lua" and (key=="OnShow" or key=="OnHide"),file..": script "..key)
        scripts=scripts+1
    end
    assert(scripts==(file=="Auras.lua" and 4 or 0) and select(2,text:gsub(":SetScript%(",""))==scripts,
        file..": only the sensor and watcher scripts")
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
-- Every point of every container ever made names its own bar's frame (the
-- aura host, or the bar frame for overlays): never another container (Blizzard
-- forbids anchoring one AuraContainer to another) or any Blizzard object.
local function OwnAnchors(label)
    local own={}
    for _,bar in pairs(C.bars) do
        own[bar.frame]=true
        if bar.auraHost then own[bar.auraHost]=true end
    end
    for _,c in ipairs(containers) do
        local s=R[c]
        for _,p in ipairs(s.points) do
            local rel=p[2]
            assert(own[rel] and rel==s.parent and not R[rel].container and not R[rel].button,
                label..": a container anchors to its own bar only")
        end
    end
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
-- growth Down, centered: flow from the top-left
assert(ps.flow.axis==0 and ps.flow.anchor=="TOPLEFT" and ps.flow.h==1 and ps.flow.v==-1,"flow down/right")
assert(math.abs(ps.flow.line-(10*30+9*2))<.1,"ten icons per line")
local host=C.bars.buf.auraHost
local pp,tp=ps.points[1],ts.points[1]
-- Two buffs and two target debuffs fit one centered line of ten: a mixed
-- row stays compact and splits at the host's top center. The player
-- container ends there by its top right corner, the target container
-- starts there by its top left corner, one 2 px group gap apart (the gap
-- between two icons of one row); Blizzard sizes each container to its
-- shown auras, so both grow from the middle.
assert(Count(ps.slots)==0 and Count(ts.slots)==0,"a centered mixed row stays compact")
assert(pp[1]=="TOPRIGHT" and pp[2]==host and pp[3]=="TOP" and pp[4]==-1 and pp[5]==0,"player part ends at the center")
assert(tp[1]=="TOPLEFT" and tp[2]==host and tp[3]=="TOP" and tp[4]==1 and tp[5]==0,"target part starts at the center")
assert(tp[4]-pp[4]==layout.groupSpacing,"the two parts one group gap apart: no hole in the row")
assert(ts.flow.axis==0 and ts.flow.anchor=="TOPLEFT" and ts.flow.h==1 and ts.flow.v==-1 and ts.flow.line==ps.flow.line,
    "the target container flows like the player container")
assert(#ps.points==1 and #ts.points==1,"one anchor per container")
assert(ps.level==C.bars.buf.frame:GetFrameLevel()+4,"above host and cells")
-- growth Up flips flow and host point on the same containers; Down restores
local layoutCalls=LogCount(pc,"GroupLayout")
buf.grow=2;buf.layoutGen=2
A.Sync("buf")
assert(Live("buf","player")==pc and Live("buf","target")==tc and #containers==2,"growth is a container write, not a rebuild")
assert(ps.flow.anchor=="BOTTOMLEFT" and ps.flow.v==1 and ps.flow.h==1,"flow up/right")
assert(ps.points[1][1]=="BOTTOMRIGHT" and ps.points[1][2]==host and ps.points[1][3]=="BOTTOM" and ps.points[1][4]==-1
    and ps.points[1][5]==0 and #ps.points==1,"player part ends at the bottom center")
assert(ts.points[1][1]=="BOTTOMLEFT" and ts.points[1][2]==host and ts.points[1][3]=="BOTTOM" and ts.points[1][4]==1
    and ts.points[1][5]==0 and #ts.points==1 and ts.flow.anchor=="BOTTOMLEFT","target part starts at the bottom center")
assert(LogCount(pc,"GroupLayout")==layoutCalls,"same element size: no group layout writes")
buf.grow=1;buf.layoutGen=3
A.Sync("buf")
assert(ps.flow.anchor=="TOPLEFT" and ps.flow.v==-1 and ps.points[1][1]=="TOPRIGHT" and ps.points[1][3]=="TOP"
    and ps.points[1][4]==-1 and ts.points[1][1]=="TOPLEFT" and ts.points[1][2]==host and ts.points[1][3]=="TOP"
    and ts.points[1][4]==1 and #ps.points==1 and #ts.points==1,"back to growing down")
assert(ps.unit=="player" and ts.unit=="target" and ps.enabled and ts.enabled)
OwnAnchors("compact centered row")
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

-- retarget: at once, target containers only, no timer. UpdateAllAuras only
-- marks the container dirty, so repeats within a frame still parse once.
local before=ts.updates
local sets=LogCount(tc,"SetEnabled")
A.TargetChanged()
assert(timerCount==0,"no next-frame refresh")
assert(ts.updates==before+1 and ps.updates==0,"one UpdateAllAuras per target container per call")
A.TargetChanged();A.TargetChanged()
assert(timerCount==0 and ts.updates==before+3 and ps.updates==0 and LogCount(tc,"SetEnabled")==sets,
    "every retarget tells each running target container once, no enable call")

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
-- five entries still fit one centered line: still split at the center
assert(#ts.points==1 and ts.points[1][1]=="TOPLEFT" and ts.points[1][2]==host and ts.points[1][3]=="TOP"
    and ts.points[1][4]==1 and ts.points[1][5]==0 and #ps.points==1 and ps.points[1][1]=="TOPRIGHT"
    and ps.points[1][2]==host and ps.points[1][4]==-1,"five entries: still split at the center")

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
assert(#ts.points==1 and ts.points[1][1]=="TOPLEFT" and ts.points[1][2]==host and ts.points[1][4]==1
    and #ps.points==1 and ps.points[1][1]=="TOPRIGHT" and ps.points[1][2]==host and ps.points[1][4]==-1,
    "a rebuilt pair splits at the center again")
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

------------------------------------------------------------------ one fixed-places rule: layout cells and controller extent
-- Layout.FixedAuras is the one rule: the aura layer takes fixed and split
-- from it, Layout.PlaceAuras places the cells and the footprint by it and
-- the controller's Extent (grow/orientation conversion) sizes the bar by
-- it. Ordered or split: one sequence of n1+n2 cells, each entry on its plan
-- position. Otherwise the player part first and the target part from a new
-- line. Checked on the real Layout.lua, against the stand-in's statement of
-- the rule and against the real Extent from Controller.lua.
do
    local chunk=assert(loadfile(root.."/MSUF_Suite_CooldownManager/Layout.lua"))
    local Cx={EMPTY={},views={},plans={},bars={},entries={},state={px=1},Auras={TargetRow=A.TargetRow}}
    chunk("MSUF_Suite_CooldownManager",{NS=NS,Suite=S,CDM=Cx})
    local L2=Cx.Layout
    assert(type(L2.FixedAuras)=="function","Layout.FixedAuras")
    local handle=assert(io.open(root.."/MSUF_Suite_CooldownManager/Controller.lua","rb"))
    local text=(handle:read("*a"):gsub("\r",""))
    handle:close()
    local body=text:match("\n(local function Extent%(view,plan%)\n.-\nend)\n")
    assert(body and body:find("FixedAuras(",1,true),"Controller.lua: Extent sizes aura bars by Layout.FixedAuras")
    local Extent=assert(loadstring("local C,probe,ceil=...\n"..body.."\nreturn Extent","=Controller.Extent"))(Cx,{},math.ceil)
    local UNIT={p="player",t="target",b="both",m="player"}
    -- p player, t target, b both (player part), m player with a per-spell showMissing
    local function Entries(units)
        local list={}
        for i=1,#units do
            local u=units:sub(i,i)
            list[i]={key="x"..i,unit=UNIT[u],ov=u=="m" and {showMissing=true} or C.EMPTY}
        end
        return list
    end
    -- 30x30 cells, 2 px spacing, ten per line, horizontal, centered, down.
    local function Case(name,set,units,rule,size,at)
        local view=View("c3",2)
        view.size,view.height,view.spacing,view.perRow,view.vertical,view.align,view.grow,view.maxIcons=30,100,2,10,false,1,1,0
        view.keepSlots,view.showMissing=false,false
        for k,v in pairs(set) do view[k]=v end
        local list=Entries(units)
        Cx.views.c3,Cx.plans.c3=view,{slot="c3",kind=2,entries=list,gen=1}
        local fixed,ordered,split=L2.FixedAuras(view,list)
        assert(fixed==rule[1] and ordered==rule[2] and split==rule[3],
            name..": fixed/ordered/split "..tostring(fixed).."/"..tostring(ordered).."/"..tostring(split))
        local f2,o2,s2=L.FixedAuras(view,list)
        assert(f2==fixed and o2==ordered and s2==split,name..": the stand-in states the same rule")
        L2.Cell("c3",#list)
        L2.Apply("c3")
        local bar=Cx.bars.c3
        assert(bar.frame.layW==size[1] and bar.frame.layH==size[2],
            name..": footprint "..tostring(bar.frame.layW).."x"..tostring(bar.frame.layH))
        local ew,eh=Extent(view,Cx.plans.c3)
        assert(ew==size[1] and eh==size[2],name..": controller extent "..tostring(ew).."x"..tostring(eh))
        for i=1,#bar.cells do
            local cell,want=bar.cells[i],at[i]
            if want then
                local points=R[cell].points
                local p=points[#points]
                assert(cell.layShown==true and p and p[1]=="TOPLEFT" and p[2]==bar.auraHost and p[3]=="TOPLEFT"
                    and p[4]==want[1] and p[5]==want[2],
                    name..": cell "..i.." at "..tostring(p and p[4])..","..tostring(p and p[5]))
            else
                assert(cell.layShown==false,name..": cell "..i.." hidden")
            end
        end
    end
    local ROW4,COL4={{0,0},{32,0},{64,0},{96,0}},{{0,0},{0,-32},{0,-64},{0,-96}}
    -- A column that mixes both parts: fixed, every entry on its plan cell.
    Case("vertical mixed column",{vertical=true},"ptpt",{true,true,false},{30,126},COL4)
    Case("vertical mixed column growing left",{vertical=true,grow=2},"ptpt",{true,true,false},{30,126},COL4)
    Case("one icon per line",{perRow=1},"ptp",{true,true,false},{30,94},{{0,0},{0,-32},{0,-64}})
    Case("one icon per line growing up",{perRow=1,grow=2},"ptp",{true,true,false},{30,94},{{0,-64},{0,-32},{0,0}})
    Case("both beside a target in a column",{vertical=true},"bt",{true,true,false},{30,62},{{0,0},{0,-32}})
    -- A horizontal mixed row on one line: centered splits (compact, one
    -- line in plan order, no gap), start or end aligned is fixed.
    Case("centered mixed row",{},"ptpt",{false,false,true},{126,30},ROW4)
    Case("centered uneven mixed row",{},"pbpt",{false,false,true},{126,30},ROW4)
    Case("both beside a target in a centered row",{},"bt",{false,false,true},{62,30},{{0,0},{32,0}})
    Case("start-aligned mixed row",{align=2},"ptpt",{true,true,false},{126,30},ROW4)
    Case("end-aligned mixed row",{align=3},"ptpt",{true,true,false},{126,30},ROW4)
    -- Mixed but longer than a line: compact, the target part from a new line.
    Case("mixed row over two lines",{perRow=2},"ptpt",{false,false,false},{62,62},{{0,0},{0,-32},{32,0},{32,-32}})
    Case("mixed row over two lines growing up",{perRow=2,grow=2},"ptpt",{false,false,false},{62,62},
        {{0,-32},{0,0},{32,-32},{32,0}})
    Case("vertical mixed bar over two columns",{vertical=true,perRow=2},"ptpt",{false,false,false},{62,62},
        {{0,0},{32,0},{0,-32},{32,-32}})
    Case("vertical, one icon per column",{vertical=true,perRow=1},"ptp",{false,false,false},{94,30},{{0,0},{64,0},{32,0}})
    -- One part only: compact, never split.
    Case("player-only column",{vertical=true},"ppp",{false,false,false},{30,94},{{0,0},{0,-32},{0,-64}})
    Case("target-only centered row",{},"ttt",{false,false,false},{94,30},{{0,0},{32,0},{64,0}})
    Case("both entries only",{vertical=true},"bb",{false,false,false},{30,62},{{0,0},{0,-32}})
    -- keepSlots and showMissing: fixed, ordered only on one line.
    Case("keepSlots row on one line",{keepSlots=true},"ptp",{true,true,false},{94,30},{{0,0},{32,0},{64,0}})
    Case("keepSlots row over two lines",{keepSlots=true,perRow=2},"ptp",{true,false,false},{62,62},
        {{0,0},{16,-32},{32,0}})
    Case("keepSlots, one icon per line",{keepSlots=true,perRow=1},"ppp",{true,true,false},{30,94},
        {{0,0},{0,-32},{0,-64}})
    Case("showMissing over two lines",{showMissing=true,perRow=2},"ppp",{true,false,false},{62,62},
        {{0,0},{32,0},{16,-32}})
    Case("per-spell showMissing",{},"mp",{true,true,false},{62,30},{{0,0},{32,0}})
    Case("keepSlots on a centered mixed row",{keepSlots=true},"ptpt",{true,true,false},{126,30},ROW4)
    -- maxIcons: only the entries the bar can show count.
    Case("maxIcons hides the mix",{vertical=true,maxIcons=2},"ppt",{false,false,false},{30,62},{{0,0},{0,-32}})
    Case("maxIcons keeps a mixed column",{vertical=true,perRow=2,maxIcons=2},"tpppp",{true,true,false},{30,62},
        {{0,0},{0,-32}})
    Case("maxIcons row stays compact",{maxIcons=3},"ppptt",{false,false,false},{94,30},{{0,0},{32,0},{64,0}})
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
------------------------------------------------------------------ "both" entries watch both units
-- Resolve gives every entry one unit; "both" comes only from the per-spell
-- "Track on" choice. A both entry has a group in each container and counts
-- in the player part; player places come first, and on a bar longer than
-- one line the target part starts after the lines the layout reserves.
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
-- rows: only target entries take the target part; a both entry counts in
-- the player part whatever Blizzard's selfAura hint says. Player part b81
-- + b82 + a83 (two lines at two per row), target part d84 two 30 px lines
-- plus spacing further down: four entries never fit one line of two, so
-- the row is neither fixed nor split and both containers sit at the
-- bar's growth point (centered: TOP), the target one two lines on.
assert(A.TargetRow(w4) and not A.TargetRow(w1) and not A.TargetRow(w2) and not A.TargetRow(w3),"row rule: target entries only")
assert(A.TargetRow({unit="target",selfAura=true}) and not A.TargetRow({unit="player",selfAura=false})
    and not A.TargetRow({unit="both",selfAura=false}),"the row is the unit alone: selfAura plays no part")
local c2Host=C.bars.c2.auraHost
assert(#bp.points==1 and bp.points[1][1]=="TOP" and bp.points[1][2]==c2Host and bp.points[1][3]=="TOP" and bp.points[1][4]==0
    and bp.points[1][5]==0,"player part at the growth point")
assert(#bt.points==1 and bt.points[1][1]=="TOP" and bt.points[1][2]==c2Host
    and bt.points[1][3]=="TOP" and bt.points[1][4]==0 and bt.points[1][5]==-64,"target part after the two reserved player lines")
-- no player entry: the target part starts at the growth point
Plan("c2",2,{w4})
A.Sync("c2")
assert(#bt.points==1 and bt.points[1][1]=="TOP" and bt.points[1][2]==c2Host and bt.points[1][4]==0 and bt.points[1][5]==0
    and not Live("c2","player"),"a bar of tracked debuffs starts at the growth point")
-- a both entry and a debuff fit one centered line of two: the both entry
-- is the player part, and the row splits at the center after it
Plan("c2",2,{w2,w4})
A.Sync("c2")
assert(Live("c2","player")==bothP,"the player container back from the pool")
assert(bp.groups.g1.cand.includeSpellIDs[8201] and bt.groups.g1.cand.includeSpellIDs[8201]
    and bt.groups.g2.cand.includeSpellIDs[8401],"the both entry in both containers")
assert(#bp.order==3 and bp.groups.g1.enabled and bp.groups.g2.enabled==false and bp.groups.g3.enabled==false
    and bt.groups.g1.enabled and bt.groups.g2.enabled and bt.groups.g3.enabled==false,
    "the pooled containers keep their groups: the surplus ones switched off")
assert(#bp.points==1 and bp.points[1][1]=="TOPRIGHT" and bp.points[1][2]==c2Host and bp.points[1][3]=="TOP"
    and bp.points[1][4]==-1 and bp.points[1][5]==0,"the both entry ends at the center")
assert(#bt.points==1 and bt.points[1][1]=="TOPLEFT" and bt.points[1][2]==c2Host and bt.points[1][3]=="TOP"
    and bt.points[1][4]==1 and bt.points[1][5]==0,"the target part starts at the center")
Plan("c2",2,{w1,w2,w3,w4})
A.Sync("c2")
assert(#bt.points==1 and bt.points[1][1]=="TOP" and bt.points[1][2]==c2Host and bt.points[1][4]==0 and bt.points[1][5]==-64
    and #bp.points==1 and bp.points[1][1]=="TOP" and bp.points[1][4]==0,"back to the reserved lines")
do
    local chunk=loadfile(root.."/MSUF_Suite_CooldownManager/Layout.lua")
    if chunk then
        local C3={EMPTY={},views={c2=both},plans={c2=C.plans.c2},bars={},entries={},state={px=1},Auras={TargetRow=A.TargetRow}}
        chunk("MSUF_Suite_CooldownManager",{NS=NS,Suite=S,CDM=C3})
        C3.Layout.Apply("c2")
        local lb=C3.bars.c2
        -- the layout reserves the lines the aura layer offsets by: three
        -- player-part entries (two lines of two), then the target line
        assert(lb.lines1==2 and lb.lines2==1,"the real layout reserves two player lines and the target line")
        assert(Args(lb.frame,"SetSize")[1]==62 and Args(lb.frame,"SetSize")[2]==94,"footprint: two per line, three lines")
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
OwnAnchors("both entries")

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
sets=LogCount(bothT,"SetEnabled")
A.TargetChanged()
-- Blizzard's SetEnabled reparses a container that turns on: no second
-- UpdateAllAuras for it, and nothing waits for the next frame.
assert(bt.enabled==true and LogCount(bothT,"SetEnabled")==sets+1 and bt.updates==upd and TargetStates(true)
    and timerCount==0,"hostile retarget: resumed at once, SetEnabled reparses it")
A.TargetChanged()
assert(LogCount(bothT,"SetEnabled")==sets+1 and bt.updates==upd+1,"the next retarget refreshes the running container once")
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
------------------------------------------------------------------ mixed rows and columns on the containers
-- The aura layer takes fixed and split from Layout.FixedAuras. A mixed
-- column (vertical on one line, or one icon per line) and a start or end
-- aligned mixed row on one line: slots on the entries' plan cells. A
-- centered mixed row on one line: compact, split at the center. Longer
-- mixed bars: compact, the target container the reserved player lines on.
C.views.c3=View("c3",2)
local mv=C.views.c3
mv.size,mv.height,mv.spacing,mv.perRow,mv.vertical,mv.align,mv.grow,mv.maxIcons=30,100,2,10,true,1,1,0
local m1=Aura("c3","a3101","a","player",Set(3101))
local m2=Aura("c3","d3102","d","target",Set(3102))
local m3=Aura("c3","b3103","b","player",Set(3103))
local m4=Aura("c3","b3104","b","target",Set(3104))
Plan("c3",2,{m1,m2,m3,m4})
local mHost=L.EnsureBar("c3").auraHost
-- A live slot on cell i (watching spell id, when given).
local function OnCell(c,i,id)
    local cell=C.bars.c3.cells[i]
    for _,g in pairs(R[c].slots) do
        local inc=g.cand and g.cand.includeSpellIDs
        if R[g.buttons[1]].allPoints==cell and g.enabled and inc and (id==nil or inc[id]) then return true end
    end
    return false
end
local function Fixed(label)
    local p,t=Live("c3","player"),Live("c3","target")
    assert(p and t and Count(R[p].groups)==0 and Count(R[t].groups)==0,label..": slot containers")
    assert(OnCell(p,1,3101) and OnCell(t,2,3102) and OnCell(p,3,3103) and OnCell(t,4,3104),
        label..": every entry on its plan cell, in the bar's order")
    assert(not OnCell(p,2) and not OnCell(p,4) and not OnCell(t,1) and not OnCell(t,3),
        label..": each unit only on its own entries' cells")
    for _,c in ipairs({p,t}) do
        local pt=R[c].points
        assert(#pt==1 and pt[1][1]=="TOPLEFT" and pt[1][2]==mHost and pt[1][3]=="TOPLEFT","slot containers sit on the host")
    end
end
local function Split(label,edge,gap)
    local p,t=Live("c3","player"),Live("c3","target")
    local ps,ts=R[p],R[t]
    assert(Count(ps.slots)==0 and Count(ts.slots)==0 and ps.groups.g2 and ts.groups.g2,label..": compact containers")
    local pp,tp=ps.points,ts.points
    assert(#pp==1 and pp[1][1]==edge.."RIGHT" and pp[1][2]==mHost and pp[1][3]==edge and pp[1][4]==-gap/2 and pp[1][5]==0,
        label..": the player part ends at the center")
    assert(#tp==1 and tp[1][1]==edge.."LEFT" and tp[1][2]==mHost and tp[1][3]==edge and tp[1][4]==gap/2 and tp[1][5]==0,
        label..": the target part starts at the center")
    assert(ps.groups.g1.layout.groupSpacing==gap and ts.groups.g1.layout.groupSpacing==gap,
        label..": the parts one group gap apart, like two icons of the row")
    assert(ps.flow.axis==0 and ts.flow.axis==0 and ps.flow.anchor==ts.flow.anchor and ps.flow.h==1 and ts.flow.h==1
        and ps.flow.line==ts.flow.line,label..": both parts flow the same way")
end
local function Compact(label,point,dx,dy)
    local p,t=Live("c3","player"),Live("c3","target")
    local pp,tp=R[p].points,R[t].points
    assert(Count(R[p].slots)==0 and Count(R[t].slots)==0,label..": compact containers")
    assert(#pp==1 and pp[1][1]==point and pp[1][2]==mHost and pp[1][3]==point and pp[1][4]==0 and pp[1][5]==0,
        label..": the player part at the growth point")
    assert(#tp==1 and tp[1][1]==point and tp[1][2]==mHost and tp[1][3]==point and tp[1][4]==dx and tp[1][5]==dy,
        label..": the target part after the reserved player lines")
end
-- a vertical bar on one line: a mixed column, fixed in the bar's order
A.Sync("c3")
Fixed("vertical mixed column")
assert(not Holder(C.bars.c3.cells[1]),"a mixed column shows no placeholders without showMissing")
-- horizontal and centered on one line: compact, split at the center
mv.vertical=false
A.Sync("c3")
Split("centered mixed row","TOP",2)
mv.spacing=4
A.Sync("c3")
Split("wider spacing","TOP",4)
mv.spacing,mv.grow=2,2
A.Sync("c3")
Split("growing up","BOTTOM",2)
assert(R[Live("c3","player")].flow.anchor=="BOTTOMLEFT","growing up: flow from the bottom")
mv.grow=1
-- start or end aligned on one line: fixed in the bar's order
mv.align=2
A.Sync("c3")
Fixed("start-aligned mixed row")
mv.align=3
A.Sync("c3")
Fixed("end-aligned mixed row")
mv.align=1
-- one icon per line: a mixed column
mv.perRow=1
A.Sync("c3")
Fixed("one icon per line")
-- longer than a line: compact, the target part a line on (two per line:
-- one player line, 30 px icon plus 2 px spacing)
mv.perRow=2
A.Sync("c3")
Compact("mixed row over two lines","TOP",0,-32)
mv.align=2
A.Sync("c3")
Compact("start-aligned row over two lines","TOPLEFT",0,-32)
mv.align,mv.vertical=1,true
A.Sync("c3")
Compact("vertical bar over two columns","LEFT",32,0)
assert(R[Live("c3","player")].flow.axis==1,"vertical flow")
mv.vertical,mv.perRow=false,10
-- one part only: never split, the part at the growth point
Plan("c3",2,{m1,m3})
A.Sync("c3")
local lone=R[Live("c3","player")].points
assert(#lone==1 and lone[1][1]=="TOP" and lone[1][2]==mHost and lone[1][4]==0 and not Live("c3","target"),
    "buffs only: the row at the growth point")
Plan("c3",2,{m2,m4})
A.Sync("c3")
lone=R[Live("c3","target")].points
assert(#lone==1 and lone[1][1]=="TOP" and lone[1][2]==mHost and lone[1][4]==0 and lone[1][5]==0 and not Live("c3","player"),
    "target debuffs only: the row at the growth point")
Plan("c3",2,{m1,m2,m3,m4})
A.Sync("c3")
Split("both parts again","TOP",2)
-- the layout's rule decides, and nothing else: forced answers are obeyed
-- (keepSlots and showMissing are the layout's to read)
local rule,asked=L.FixedAuras,0
L.FixedAuras=function(view,entries)
    asked=asked+1
    assert(view==mv and entries==C.plans.c3.entries,"the rule sees the bar's view and entries")
    return true,true,false
end
A.Sync("c3")
Fixed("the layout says fixed")
assert(asked==1,"one rule call per sync")
L.FixedAuras=function() return false,false,true end
mv.align=2
A.Sync("c3")
Split("the layout says split","TOP",2)
L.FixedAuras=function() return false,false,false end
mv.keepSlots,mv.showMissing=true,true
A.Sync("c3")
Compact("the layout says compact","TOPLEFT",0,-32)
assert(not Holder(C.bars.c3.cells[2]),"compact: no placeholders")
L.FixedAuras=rule
mv.keepSlots,mv.showMissing,mv.align=false,false,1
A.Sync("c3")
Split("the real rule again","TOP",2)
OwnAnchors("mixed rows and columns")
C.plans.c3=nil
A.Release("c3")

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

-- Stack choices, glow styles and kit sounds: a function of its own (the
-- main chunk is near Lua's 200-local limit).
local function Features()
------------------------------------------------------------------ helpers over the fakes
local function Under(obj,root)
    local s=R[obj]
    local parent=s and s.parent
    while parent do
        if parent==root then return true end
        parent=R[parent].parent
    end
    return false
end
local function Find(root,pred)
    local out={}
    for obj,s in pairs(R) do if Under(obj,root) and pred(obj,s) then out[#out+1]=obj end end
    return out
end
local function Child(parent,kind)
    for obj,s in pairs(R) do if s.parent==parent and s.kind==kind then return obj end end
end
-- A texture carrying a flipbook loop (the glow's flipbook), and whether a
-- clipping gate lies between it and the button (the stack glow's).
local function IsFlip(obj,s)
    if s.kind~="Texture" then return false end
    local group=Child(obj,"AnimationGroup")
    return group~=nil and Child(group,"FlipBook")~=nil
end
local function Gated(obj,root)
    local parent=R[obj].parent
    while parent and parent~=root do
        if R[parent].calls.SetClipsChildren then return true end
        parent=R[parent].parent
    end
    return false
end
-- The "glow while active" parts of one aura button.
local function AuraGlow(button)
    local flips=Find(button,function(obj,s) return IsFlip(obj,s) and not Gated(obj,button) end)
    assert(#flips==1,"one aura glow per button")
    local flip=flips[1]
    local frame=R[flip].parent
    local ring=Child(frame,"Frame")
    local pulse=Child(ring,"AnimationGroup")
    local edges=Find(ring,function(_,s) return s.kind=="Texture" end)
    return {frame=frame,flip=flip,ring=ring,pulse=pulse,fade=Child(pulse,"Alpha"),edges=edges,
        loop=Child(flip,"AnimationGroup")}
end
local function Near(a,b) return math.abs(a-b)<1e-6 end
local function CountFormatters()
    local n=0
    for _,f in ipairs(formatters) do if f.points and f.points[1].format=="" then n=n+1 end end
    return n
end
local function Fire(frame,key) R[frame].scripts[key](frame) end

do
------------------------------------------------------------------ stack text color: shared count formatters
-- stackColorAt N: one numeric rule formatter per (N, color), shared by
-- every button of every container. Nothing below two applications, plain
-- from two, colored from N (N = 1 colors a single application too).
C.views.c4=View("c4",2)
local sv=C.views.c4
local made=CountFormatters()
local t1=Aura("c4","a4101","a","player",Set(4101),{ov={stackColorAt=3,stackColor="00ff00"}})
local t2=Aura("c4","a4102","a","player",Set(4102),{ov={stackColorAt=3,stackColor="00ff00"}})
local t3=Aura("c4","a4103","a","player",Set(4103),{ov={stackColorAt=1}})
local t4=Aura("c4","a4104","a","player",Set(4104),{ov={stackColorAt=2,stackColor="3366ff"}})
local t5=Aura("c4","a4105","a","player",Set(4105))
local t6=Aura("c4","d4106","d","target",Set(4106),{ov={stackColorAt=3,stackColor="00ff00"}})
Plan("c4",2,{t1,t2,t3,t4,t5,t6})
A.Sync("c4")
local sc,st=Live("c4","player"),Live("c4","target")
assert(#R[sc].order==5 and #R[st].order==1)
local f1=R[Buttons(sc,"g1")[1]].bind.countFormatter
assert(f1,"stack color binds a count formatter")
for _,key in ipairs({"g1","g2"}) do
    for _,b in ipairs(Buttons(sc,key)) do assert(R[b].bind.countFormatter==f1,"one formatter per (N, color): every button") end
end
assert(R[Buttons(st,"g1")[1]].bind.countFormatter==f1,"shared across containers")
local f3,f4=R[Buttons(sc,"g3")[1]].bind.countFormatter,R[Buttons(sc,"g4")[1]].bind.countFormatter
assert(f3 and f4 and f3~=f1 and f4~=f1 and f3~=f4,"a new signature, a new formatter")
for _,b in ipairs(Buttons(sc,"g5")) do
    assert(R[b].bind.count and R[b].bind.countFormatter==nil,"no stack color: Blizzard's plain count")
end
assert(CountFormatters()==made+3,"three signatures, three formatters")
local p=f1.points
assert(#p==3 and p[1].threshold==0 and p[1].format=="" and p[2].threshold==2 and p[2].format=="%d"
    and p[3].threshold==3 and p[3].format=="|cff00ff00%d|r","breakpoints: hidden, plain, colored")
assert(f1:FormatNumber(0)=="" and f1:FormatNumber(1)=="" and f1:FormatNumber(2)=="2"
    and f1:FormatNumber(3)=="|cff00ff003|r" and f1:FormatNumber(12)=="|cff00ff0012|r","colored from N")
assert(#f3.points==2 and f3.points[2].threshold==1 and f3:FormatNumber(0)=="" and f3:FormatNumber(1)=="|cffff5a3c1|r",
    "N = 1 colors one application, default color ff5a3c")
assert(#f4.points==2 and f4:FormatNumber(1)=="" and f4:FormatNumber(2)=="|cff3366ff2|r","N = 2: no plain step")
-- live changes rebind in place while buttons are accessible; an equal
-- signature is no change
local b1=R[Buttons(sc,"g1")[1]]
local binds=b1.bind.countBinds
t1.ov={stackColorAt=3,stackColor="00ff00"}
A.Sync("c4")
assert(b1.bind.countBinds==binds,"same signature: no rebind")
t1.ov={stackColorAt=4,stackColor="00ff00"}
A.Sync("c4")
assert(Live("c4","player")==sc and b1.bind.countBinds==binds+1 and b1.bind.countFormatter.points[3].threshold==4,
    "new N: a new formatter, rebound in place")
assert(R[Buttons(sc,"g2")[1]].bind.countFormatter==f1,"other entries keep theirs")
t1.ov=C.EMPTY
A.Sync("c4")
assert(b1.bind.countFormatter==nil and b1.bind.countBinds==binds+2,"off: the plain binding again")
-- combat: sealed buttons are not touched, the change waits for combat to end
COMBAT=true
t1.ov={stackColorAt=3,stackColor="00ff00"}
A.Sync("c4")
assert(b1.bind.countFormatter==nil and A.pending.c4==true,"combat: deferred")
COMBAT=false
A.FlushPending()
assert(b1.bind.countFormatter==f1 and A.pending.c4==nil,"after combat: the shared formatter")
-- without the formatter API the plain binding stays
local strings=C_StringUtil
C_StringUtil=nil
t2.ov={stackColorAt=5,stackColor="123456"}
A.Sync("c4")
rawset(_G,"C_StringUtil",strings)
assert(R[Buttons(sc,"g2")[1]].bind.countFormatter==nil,"no formatter API: plain binding")

------------------------------------------------------------------ stack glow: clip gate and application bar
-- stackGlow N: a gate that clips its children, an invisible StatusBar
-- Blizzard fills with the applications (maximum N) and the glow host
-- centered on the fill's right edge. Below N the glow lies wholly outside
-- the gate; from N on it sits on the icon. No Lua reads the count.
local sg=Aura("c4","a4201","a","player",Set(4201),{ov={stackGlow=3,glowStyle=2,glowColor="3399ff"}})
Plan("c4",2,{t1,t2,t3,t4,t5,t6,sg})
A.Sync("c4")
local sc2=Live("c4","player")
assert(sc2~=sc and R[sc].enabled==false,"a stack glow is a new binding set")
local gb=Buttons(sc2,"g6")[1]
local bind=R[gb].bind
assert(bind.appBar and bind.appOpts.maxApplications==3 and bind.appBinds==1,"application bar bound with maximum N")
local plain=R[Buttons(sc2,"g1")[1]].bind
assert(plain.appBar and plain.appOpts.maxApplications==1,"entries without a stack glow: bound at 1, gate hidden")
local gates=Find(gb,function(_,s) return s.calls.SetClipsChildren~=nil end)
assert(#gates==1 and Args(gates[1],"SetClipsChildren")[1]==true,"one clipping gate")
local gate=gates[1]
assert(R[gate].parent==gb and R[gate].shown==true,"gate shown for N > 0")
local plainGate=Find(Buttons(sc2,"g1")[1],function(_,s) return s.calls.SetClipsChildren~=nil end)[1]
assert(R[plainGate].shown==false)
local gp=R[gate].points[1]
assert(#R[gate].points==1 and gp[1]=="CENTER" and gp[2]==gb and gp[3]=="CENTER" and gp[4]==0 and gp[5]==0,"gate on the icon")
local sbar=bind.appBar
assert(R[sbar].parent==gb and Args(sbar,"SetAlpha")[1]==0,"invisible application bar")
local fill=R[sbar].fill
local hosts=Find(gate,function(_,s) return s.kind=="Frame" and s.points[1]~=nil and s.points[1][2]==fill end)
assert(#hosts==1 and R[hosts[1]].parent==gate,"glow host inside the gate")
local host=hosts[1]
local hp=R[host].points[1]
assert(hp[1]=="CENTER" and hp[3]=="RIGHT" and hp[4]==0 and hp[5]==0,"host centered on the fill's right edge")
local w,h=Args(gb,"SetSize")[1],Args(gb,"SetSize")[2]
local gw,gh=Args(gate,"SetSize")[1],Args(gate,"SetSize")[2]
assert(Args(host,"SetSize")[1]==w and Args(host,"SetSize")[2]==h,"host is the icon's size")
local function Geometry(n)
    local bw=Args(sbar,"SetSize")[1]
    local bp=R[sbar].points
    assert(#bp==1 and bp[1][1]=="LEFT" and bp[1][2]==gate and bp[1][3]=="CENTER" and bp[1][5]==0,"bar left of the gate center")
    assert(Near(bp[1][4],-bw),"the bar ends at the gate's center")
    local travel=bw/n
    assert(travel>gw and travel>gh,"one application moves the glow further than the gate is wide")
    return bp[1][4],bw
end
local left,bw=Geometry(3)
local flip=Find(host,function(obj,s) return IsFlip(obj,s) end)[1]
assert(Args(flip,"SetAtlas")[1]=="rotationhelper_ants_flipbook","per-spell glow style 2")
assert(Args(flip,"SetDesaturated")[1]==true and Near(Args(flip,"SetVertexColor")[1],.2) and Near(Args(flip,"SetVertexColor")[2],.6)
    and Near(Args(flip,"SetVertexColor")[3],1),"per-spell glow color")
local fw,fh=Args(flip,"SetSize")[1],Args(flip,"SetSize")[2]
assert(fw<=gw and fh<=gh and fw>w,"the gate holds the whole glow")
-- Blizzard's fill: value / max of the bar's width; the host follows its
-- right edge. Applications above the maximum fill the bar.
local function HostX(apps,n) return left+bw*math.min(apps,n)/n end
for apps=0,2 do assert(HostX(apps,3)+fw/2<-gw/2,"below N the glow is clipped ("..apps..")") end
for _,apps in ipairs({3,4,99}) do assert(Near(HostX(apps,3),0),"from N on the glow is on the icon") end
assert(bind.shownAnims==2,"12.1.5: the glow loops play with the button")
-- N changes on a live button: placed again and rebound (the setter
-- replaces the element); unchanged choices make no call
local sizes=Calls(gate,"SetSize")
A.Sync("c4")
assert(Calls(gate,"SetSize")==sizes and bind.appBinds==1,"unchanged: no call")
sg.ov={stackGlow=5,glowStyle=2,glowColor="3399ff"}
A.Sync("c4")
assert(Live("c4","player")==sc2 and bind.appBinds==2 and bind.appOpts.maxApplications==5,"new N rebinds the same bar")
left,bw=Geometry(5)
for apps=0,4 do assert(HostX(apps,5)+fw/2<-gw/2,"below the new N: clipped") end
assert(Near(HostX(5,5),0))
-- another stack glow on the bar keeps the binding set
t5.ov={stackGlow=9}
sg.ov={stackGlow=0,glowStyle=2}
A.Sync("c4")
assert(Live("c4","player")==sc2 and R[gate].shown==false and bind.appBinds==2,"off: gate hidden, nothing rebound")
assert(R[Buttons(sc2,"g5")[1]].bind.appOpts.maxApplications==9,"the other entry's gate")
sg.ov={stackGlow=3,glowStyle=4}
A.Sync("c4")
assert(R[gate].shown==true and bind.appOpts.maxApplications==3)
local ring=Child(R[flip].parent,"Frame")
assert(R[ring].shown==true and R[flip].shown==false,"per-spell style 4 on the stack glow: edges")
-- Blizzard writes secret counts into every bound region; restyles and
-- threshold changes never read them
for _,c in ipairs({sc2,Live("c4","target")}) do
    for _,key in ipairs(R[c].order) do
        for _,b in ipairs(Buttons(c,key)) do
            local bb=R[b].bind
            R[bb.count].text=Secret()
            if bb.appBar then R[bb.appBar].value=Secret() end
        end
    end
end
sv.zoom=16;sv.styleGen=2
A.Restyle("c4")
sg.ov={stackGlow=2,glowStyle=1}
A.Sync("c4")
assert(bind.appOpts.maxApplications==2 and Live("c4","player")==sc2,"secret counts: restyled and rebound without a read")
assert(#Find(C.bars.c4.auraHost,function(_,s) return s.scripts~=nil end)==0,"no kit value: no sensor, no watcher")
-- the bar's last stack glow gone: the pooled pair without gates returns
t5.ov,sg.ov=C.EMPTY,C.EMPTY
A.Sync("c4")
assert(Live("c4","player")==sc and R[sc2].enabled==false,"no stack glow: the gate-less pair from the pool")

------------------------------------------------------------------ aura glow styles
-- "Glow while active": one builder, styled by widget writes only. 1 Blizzard
-- alert and 2 marching ants are 6x5 flipbooks (30 frames, 1 s loop), 3
-- pulses four edges, 4 holds them still. Per-spell style and color first,
-- then the bar's.
C.views.c5=View("c5",2)
local gv=C.views.c5
gv.glowStyle,gv.glowTint,gv.glowR,gv.glowG,gv.glowB=3,false,.1,.2,.3
local g1=Aura("c5","a5101","a","player",Set(5101),{ov={auraGlow=true,glowStyle=1}})
local g2=Aura("c5","a5102","a","player",Set(5102),{ov={auraGlow=true,glowStyle=2,glowColor="ff0000"}})
local g3=Aura("c5","a5103","a","player",Set(5103),{ov={auraGlow=true,glowStyle=3}})
local g4=Aura("c5","a5104","a","player",Set(5104),{ov={auraGlow=true,glowStyle=4}})
local g5=Aura("c5","a5105","a","player",Set(5105),{ov={auraGlow=true}})
local g6=Aura("c5","a5106","a","player",Set(5106))
Plan("c5",2,{g1,g2,g3,g4,g5,g6})
A.Sync("c5")
local gc=Live("c5","player")
local function GlowOf(key) return AuraGlow(Buttons(gc,key)[1]) end
local gw1=GlowOf("g1")
assert(R[gw1.frame].shown and R[gw1.flip].shown and not R[gw1.ring].shown,"style 1: flipbook")
assert(Args(gw1.flip,"SetAtlas")[1]=="UI-HUD-ActionBar-Proc-Loop-Flipbook" and Args(gw1.flip,"SetDesaturated")[1]==false
    and Args(gw1.flip,"SetVertexColor")[1]==1,"Blizzard alert art in its own gold")
local gbw,gbh=Args(Buttons(gc,"g1")[1],"SetSize")[1],Args(Buttons(gc,"g1")[1],"SetSize")[2]
local grow=.4*math.min(gbw,gbh)
assert(Near(Args(gw1.flip,"SetSize")[1],gbw+grow) and Near(Args(gw1.flip,"SetSize")[2],gbh+grow),"same margin on every side")
assert(Args(gw1.flip,"SetAlpha")[1]==0,"the sheet rests hidden; only the loop lifts it")
local loop=gw1.loop
local book=Child(loop,"FlipBook")
local lift=Child(loop,"Alpha")
assert(Args(loop,"SetLooping")[1]=="REPEAT" and R[loop].playing,"looping in C")
assert(Args(book,"SetFlipBookRows")[1]==6 and Args(book,"SetFlipBookColumns")[1]==5 and Args(book,"SetFlipBookFrames")[1]==30
    and Args(book,"SetDuration")[1]==1,"6x5 flipbook, 30 frames, 1 s")
assert(Args(lift,"SetFromAlpha")[1]==1 and Args(lift,"SetToAlpha")[1]==1)
assert(Args(gw1.pulse,"SetLooping")[1]=="BOUNCE" and R[gw1.pulse].playing)
assert(R[Buttons(gc,"g1")[1]].bind.shownAnims==2,"both loops play with the button")
local gw2=GlowOf("g2")
assert(Args(gw2.flip,"SetAtlas")[1]=="rotationhelper_ants_flipbook" and Args(gw2.flip,"SetDesaturated")[1]==true
    and Args(gw2.flip,"SetVertexColor")[1]==1 and Args(gw2.flip,"SetVertexColor")[2]==0,"style 2 tinted by the spell's color")
local gw3=GlowOf("g3")
assert(R[gw3.ring].shown and not R[gw3.flip].shown and #gw3.edges==4,"style 3: four edges")
local edge=Args(gw3.edges[1],"SetColorTexture")
assert(edge[1]==1 and Near(edge[2],.82) and edge[3]==0,"untinted edges in the alert's gold")
assert(Near(Args(gw3.fade,"SetToAlpha")[1],.25),"style 3 pulses")
local gw4=GlowOf("g4")
assert(R[gw4.ring].shown and Args(gw4.fade,"SetToAlpha")[1]==1,"style 4 holds still")
local gw5=GlowOf("g5")
assert(R[gw5.ring].shown and Near(Args(gw5.fade,"SetToAlpha")[1],.25),"no per-spell style: the bar's (3)")
assert(not R[GlowOf("g6").frame].shown,"no glow while active: hidden")
-- the bar's tint colors every glow without a per-spell color
gv.glowTint=true
A.Sync("c5")
edge=Args(gw5.edges[1],"SetColorTexture")
assert(Near(edge[1],.1) and Near(edge[2],.2) and Near(edge[3],.3),"bar tint on the edges")
assert(Args(gw1.flip,"SetDesaturated")[1]==true and Near(Args(gw1.flip,"SetVertexColor")[3],.3),"bar tint on the flipbook")
assert(Args(gw2.flip,"SetVertexColor")[1]==1 and Args(gw2.flip,"SetVertexColor")[2]==0,"a per-spell color wins")
local atlases=Calls(gw1.flip,"SetAtlas")+Calls(gw2.flip,"SetAtlas")
A.Sync("c5")
assert(Calls(gw1.flip,"SetAtlas")+Calls(gw2.flip,"SetAtlas")==atlases,"unchanged look: no call")
-- a style change in combat waits for the next out-of-combat sync
COMBAT=true
g3.ov={auraGlow=true,glowStyle=1}
A.Sync("c5")
assert(R[gw3.ring].shown and not R[gw3.flip].shown and A.pending.c5==true,"combat: no restyle")
COMBAT=false
A.FlushPending()
assert(R[gw3.flip].shown and not R[gw3.ring].shown and Args(gw3.flip,"SetAtlas")[1]=="UI-HUD-ActionBar-Proc-Loop-Flipbook",
    "restyled after combat")
-- the bar's "glow while active" lights every entry; a per-spell false wins
gv.auraGlow=true
g5.ov={auraGlow=false}
A.Sync("c5")
assert(R[GlowOf("g6").frame].shown and not R[gw5.frame].shown,"bar switch and per-spell exception")

------------------------------------------------------------------ overlays: stack glow and color
-- Aura overlays on cooldown icons carry the same per-spell stack choices;
-- kit sounds stay with aura entries (cooldowns sound when ready).
C.views.c6=View("c6",1)
local ov6=C.views.c6
ov6.showAura=true
local host6=L.EnsureBar("c6").frame
local oe={key="b61",src="b",family=1,hasAura=true,selfAura=true,unit="player",auraIDs=Set(6101),slot="c6",
    ov={stackGlow=2,stackColorAt=2,sound="kit:6000"},icon=CreateFrame("Frame",nil,host6),linked=C.EMPTY}
oe.icon.layShown=true
Plan("c6",1,{oe})
A.Sync("c6")
local oc6=Live("c6","player",true)
local ob6=Buttons(oc6,"s1")[1]
local ob=R[ob6].bind
assert(ob.appBar and ob.appOpts.maxApplications==2,"overlay stack glow")
assert(ob.countFormatter and ob.countFormatter.points[2].threshold==2,"overlay stack color")
assert(R[Find(ob6,function(_,s) return s.calls.SetClipsChildren~=nil end)[1]].shown,"overlay gate shown")
assert(#Find(host6,function(_,s) return s.scripts~=nil end)==0,"no kit sensor on overlays")
C.plans.c4,C.plans.c5,C.plans.c6=nil,nil,nil
A.Release("c4");A.Release("c5");A.Release("c6")
end

do
------------------------------------------------------------------ kit sounds on aura entries
-- C_UnitAuras.AddAuraSound takes files only: kit values play from a sensor
-- in each aura button (OnShow gain, OnHide loss), decided one frame later.
-- Mute, channel, the quiet window, the container's hush and a 1 s throttle
-- per entry and direction apply; a loss and a gain of one entry in the
-- same frame are a button reset and play nothing.
C.views.c1.keepSlots=false
C.state.soundQuietUntil,C.state.muteSounds,C.state.soundChannel=0,false,"Master"
local k1=Aura("c1","a7101","a","player",Set(7101),{ov={sound="kit:5001",lossSound="kit:5002"}})
local k2=Aura("c1","a7102","a","player",Set(7102),{ov={sound="file:777"}})
local k3=Aura("c1","d7103","d","target",Set(7103),{ov={sound="kit:5003"}})
for _,e in ipairs({k1,k2,k3}) do C.entries[e.key]=e end
Plan("c1",2,{k1,k2,k3})
A.Sync("c1")
local kp,kt=Live("c1","player"),Live("c1","target")
local function SensorOf(button)
    local list=Find(button,function(_,s) return s.scripts~=nil end)
    assert(#list==1 and R[list[1]].sensor and R[list[1]].kind=="Frame","one sensor per button")
    return list[1]
end
for _,c in ipairs({kp,kt}) do
    for _,key in ipairs(R[c].order) do for _,b in ipairs(Buttons(c,key)) do SensorOf(b) end end
end
local watch={}
for obj,s in pairs(R) do
    if s.scripts and not s.sensor and s.parent==C.bars.c1.auraHost then watch[#watch+1]=obj end
end
assert(#watch==2,"one watcher per kit container, on the bar host")
local hostOf={}
for _,bar in pairs(C.bars) do hostOf[bar.auraHost]=true end
for obj in pairs(scripted) do
    local s=R[obj]
    assert(s.sensor or hostOf[s.parent],"scripts: sensors in aura buttons and watchers on bar hosts only")
end
local s1,s1b=SensorOf(Buttons(kp,"g1")[1]),SensorOf(Buttons(kp,"g1")[2])
local s2=SensorOf(Buttons(kp,"g2")[1])
local s3=SensorOf(Buttons(kt,"g1")[1])
NOW=NOW+5
local kits,timers=played.kits,timerCount
Fire(s1,"OnShow")
assert(played.kits==kits and timerCount==timers+1,"an edge waits one frame")
RunTimers()
assert(played.kits==kits+1 and played.kit==5001 and played.kitChannel=="Master","gain kit")
NOW=NOW+.4
Fire(s1,"OnHide")
RunTimers()
assert(played.kits==kits+2 and played.kit==5002,"loss kit")
NOW=NOW+.3
Fire(s1,"OnShow")
RunTimers()
assert(played.kits==kits+2,"1 s throttle per entry and direction")
NOW=NOW+1
Fire(s1,"OnShow")
RunTimers()
assert(played.kits==kits+3 and played.kit==5001)
-- a full rebuild releases and re-acquires buttons in one pass: the loss on
-- one button and the gain on another are no change
NOW=NOW+2
Fire(s1,"OnHide");Fire(s1b,"OnShow")
assert(timerCount==1,"one flush per frame")
RunTimers()
assert(played.kits==kits+3,"a button reset plays nothing")
-- file sounds are native registrations: the sensor passes them by
NOW=NOW+2
Fire(s2,"OnShow")
assert(timerCount==0 and Alerts.PlayAura(k2.key,"gain")==false,"no kit value: nothing taken")
-- a retarget hushes the target containers, even later in the same frame
Fire(s3,"OnShow")
A.TargetChanged()
RunTimers()
assert(played.kits==kits+3,"retarget: target sensors silent")
NOW=NOW+.1
Fire(s3,"OnShow")
RunTimers()
assert(played.kits==kits+3,"still inside the hush")
NOW=NOW+.5
Fire(s3,"OnShow")
RunTimers()
assert(played.kits==kits+4 and played.kit==5003,"target debuff gain")
-- ... but never the player's buffs
NOW=NOW+2
A.TargetChanged()
Fire(s1,"OnShow")
RunTimers()
assert(played.kits==kits+5 and played.kit==5001,"a retarget leaves player sensors alone")
-- an ancestor hidden and shown again (the UI hidden for a cinematic): the
-- watchers hush their containers, in any order within the frame
NOW=NOW+2
Fire(s1,"OnHide")
for i=1,#watch do Fire(watch[i],"OnHide") end
RunTimers()
NOW=NOW+30
for i=1,#watch do Fire(watch[i],"OnShow") end
Fire(s1,"OnShow")
RunTimers()
assert(played.kits==kits+5,"UI hidden and shown: silent")
-- quiet window after a loading screen, mute, channel
NOW=NOW+5
C.state.soundQuietUntil=NOW+2
Fire(s1,"OnHide")
RunTimers()
assert(played.kits==kits+5,"quiet after a loading screen")
C.state.soundQuietUntil=0
C.state.muteSounds=true
NOW=NOW+2
Fire(s1,"OnShow")
RunTimers()
assert(played.kits==kits+5,"muted")
C.state.muteSounds=false
C.state.soundChannel="SFX"
NOW=NOW+2
Fire(s1,"OnHide")
RunTimers()
assert(played.kits==kits+6 and played.kit==5002 and played.kitChannel=="SFX","chosen channel")
C.state.soundChannel="Master"
-- kits are never registered natively; files still are
Alerts.ReleaseAll()
Alerts.SyncAuraSounds()
local regs={}
for _,row in pairs(auraSounds) do if row.spell>=7101 and row.spell<=7103 then regs[#regs+1]=row end end
assert(#regs==1 and regs[1].spell==7102 and regs[1].file==777 and regs[1].trigger==0,"file sounds keep AddAuraSound")
Alerts.ReleaseAll()
-- sensor edges allocate nothing
collectgarbage("collect")
collectgarbage("stop")
local mem=collectgarbage("count")
for _=1,300 do
    NOW=NOW+1.5;Fire(s1,"OnShow");RunTimers()
    NOW=NOW+1.5;Fire(s1,"OnHide");RunTimers()
end
local grew=collectgarbage("count")-mem
collectgarbage("restart")
assert(grew<1,"kit sensor edges allocate nothing ("..grew.." KB)")
-- no Lua per UNIT_AURA: a stacking aura changes bound regions only (the
-- button stays shown), which runs none of our scripts
local before=played.kits
for _,b in ipairs(Buttons(kp,"g1")) do R[R[b].bind.count].text=Secret() end
assert(timerCount==0 and played.kits==before,"stack changes run nothing")
-- the kit containers go when the bar's last kit value goes
k1.ov={sound="file:778"}
A.Sync("c1")
assert(Live("c1","player")==kp,"a kit value left on the bar: same containers")
k3.ov={sound="file:779"}
A.Sync("c1")
local np=Live("c1","player")
assert(np~=kp and #Find(np,function(_,s) return s.scripts~=nil end)==0,"no kit value left: containers without sensors")
C.plans.c1=nil
A.Release("c1")
end

end
Features()
OwnAnchors("every container")

print("suite_cooldown_manager_auras_contract: ok")
