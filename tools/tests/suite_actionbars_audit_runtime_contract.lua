local root=assert(arg[1],"repository root required")
-- The client's securecallfunction reports an error and returns nothing;
-- this stand-in lets errors raise, so a failing callback fails the test.
securecallfunction=function(callback,...) return callback(...) end
-- Offline contract for the action bar runtime audit fixes: the key audit skips
-- hidden buttons, a reused Blizzard button keeps no stale usability state for
-- the preview, a fading-out bar paints until its fade has ended, and a button
-- that moves to an empty slot loses its checked decoration. The real core, the
-- Suite modules and the action bar runtime load against plain stand-ins.
local now,combat=100,false
GetTime=function() return now end
InCombatLockdown=function() return combat end
UnitAffectingCombat=function() return combat end
C_Timer={After=function() end,NewTicker=function() end}
local Suite={}
MSUFSuite=Suite
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",SupportsEvent=function() return true end}}
SlashCmdList={}
UnitClass=function() return "Warrior","WARRIOR" end
C_ClassColor={GetClassColor=function() return {r=.78,g=.61,b=.43} end}
MSUF_PixelLayoutRegion=function(frame) return frame end
SecureHandlerExecute=function() end
RegisterStateDriver=function() end
GetNumShapeshiftForms=function() return 0 end
CreateFrame=function() return {SetScript=function() end,RegisterEvent=function() end} end
UIParent={GetEffectiveScale=function() return 1 end,GetWidth=function() return 1024 end,GetHeight=function() return 768 end}
GetPhysicalScreenSize=function() return 1024,768 end
SpellFlyout={IsShown=function() return false end}
local tip={owner=nil}
GameTooltip={GetOwner=function() return tip.owner end,SetAction=function() end,Hide=function() tip.owner=nil end}
GameTooltip_SetDefaultAnchor=function(_,owner) tip.owner=owner end
local calls={usable=0}
C_ActionBar=setmetatable({
    IsUsableAction=function() calls.usable=calls.usable+1;return true,false end,
    IsActionInRange=function() return true end,
}, {__index=function() return function() end end})
C_SpellActivationOverlay={IsSpellOverlayed=function() end}
C_Spell={GetOverrideSpell=function() end,GetSpellInfo=function() return {name="Heal"} end}
Enum={LuaCurveType={Step=1}}
C_CurveUtil={CreateCurve=function()
    return {SetType=function() end,AddPoint=function() end,ClearPoints=function() end}
end}
local hooks={}
hooksecurefunc=function(target,method,fn)
    if type(target)=="string" then fn,method=method,target end
    hooks[method]=fn
end
ActionButtonSpellAlertManager={}
GetActionInfo=function() return "spell",7 end
GetBindingKey=function() return nil end

for _,file in ipairs({"Platform","Database","SuiteCatalog","Catalog/ActionBars","Bindings",
    "Catalog/DataTexts","NameplateStyle","SuiteMigrations","Suite","HostBridge"}) do
    assert(loadfile(root.."/MSUF_Suite/Core/"..file..".lua"))("MSUF_Suite",Suite)
end
assert(loadfile(root.."/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite",Suite)
assert(Suite.Database.Initialize(nil));Suite.Suite.Normalize(Suite.DB)
local private={}
assert(loadfile(root.."/MSUF_Suite/Core/FontBridge.lua"))("MSUF_Suite",MSUFSuite)
for _,file in ipairs({"Surfaces","Runtime","EditMode"}) do
    assert(loadfile(root.."/MSUF_Suite_Modules/"..file..".lua"))("MSUF_Suite_Modules",private)
end
local toc=assert(io.open(root.."/MSUF_Suite_ActionBars/MSUF_Suite_ActionBars_Mainline.toc","rb")):read("*a")
for file in toc:gmatch("([%w_]+)%.lua") do
    assert(loadfile(root.."/MSUF_Suite_ActionBars/"..file..".lua"))("MSUF_Suite_ActionBars",private)
end
local S,AB=Suite.Suite,private.ActionBars
local ENUM,config=AB.ENUM,S.Config("actionbars")
AB.M.config,AB.M.active=config,true
AB.ResolveAPI()
AB.BuildStyle()
local VIS,USABLE=ENUM.VISIBILITY,S.USABLE
local Runtime=private.Suite

local function Frame()
    local frame={scripts={}}
    function frame:HookScript(name,fn) self.scripts[name]=fn end
    return frame
end

------------------------------------------------------------------ key audit
-- A button the player cannot see needs no key: a bar switched off, or the
-- buttons beyond the bar's button count.
local function Owned(bar,index)
    return {bar=bar,index=index,command="BUTTON"..bar.index.."_"..index,
        button={GetAttribute=function() return index end}}
end
local shown={index=1,key=AB.KEYS[1],count=2}
local off={index=9,key=AB.KEYS[9],count=12}
AB.owned={Owned(shown,1),Owned(shown,2),Owned(shown,3),Owned(off,1)}
config.bar1Visibility,config.bar9Visibility=VIS.ALWAYS,VIS.ALWAYS
assert(#Runtime.ActionKeyAuditRows(true)==3,"a button beyond the bar's button count was audited")
config.bar9Visibility=VIS.NEVER
local rows=Runtime.ActionKeyAuditRows(true)
assert(#rows==2 and not rows[1].label:find("Button 3",1,true) and not rows[2].label:find("Button 3",1,true),
    "a bar that is switched off was audited")
assert(#Runtime.ActionKeyAuditRows(false)==2,"the full review lists hidden buttons")
config.bar1Visibility=VIS.NEVER
assert(#Runtime.ActionKeyAuditRows(true)==0,"every bar off must leave nothing to audit")
shown.count=nil
config.bar1Visibility=VIS.ALWAYS
assert(#Runtime.ActionKeyAuditRows(true)==3,"a bar that was never laid out hides its buttons")
AB.owned={}

------------------------------------------------------------------ reused button, stale usability
local function Icon()
    local icon={}
    function icon:SetVertexColor(...) self.vertex={...} end
    function icon:SetTexture() end
    function icon:Hide() end
    return icon
end
local function Bar(index,native)
    local bar={index=index,key=AB.KEYS[index],owned=false,native=native,buttons={},filled={},
        header={IsVisible=function() return true end}}
    AB.bars[index]=bar
    return bar
end
local function Rec(bar,native)
    local button={icon=Icon(),cooldown={Clear=function() end},chargeCooldown={Clear=function() end},
        lossOfControlCooldown={Clear=function() end},
        IsVisible=function() return true end,HookScript=function() end,
        GetChecked=function() return false end,SetChecked=function() end}
    local rec={button=button,bar=bar,index=#bar.buttons+1,slot=61,owned=true,native=native,filled=true}
    bar.buttons[#bar.buttons+1],bar.filled[#bar.filled+1]=rec,rec
    AB.records[button]=rec
    return rec
end
local nativeBar=Bar(2,true)
local native=Rec(nativeBar,true)
AB.UpdateCurves()
AB.RefreshNativeBar(nativeBar)
local hook=assert(hooks.UpdateUsable,"no usable hook on the reused button")
local Tint=Runtime.ActionBarPreviewTint
-- Stock colors: Blizzard paints, so a state the suite read once must not
-- outlive Blizzard's next update.
native.usable=USABLE.NO_POWER
hook(native.button,61,true,false)
assert(Tint(2,1)==nil,"the preview shows a usability state Blizzard has painted over: "..tostring(Tint(2,1)))
-- A dormant (faded) bar drops the update too.
native.usable=USABLE.UNUSABLE
nativeBar.paintDormant=true
hook(native.button,61,true,false)
nativeBar.paintDormant=nil
assert(Tint(2,1)==nil,"a faded bar kept a stale usability state")
-- Custom colors: the payload names the state, fresh at each update.
config.noPowerColor="ff0000"
AB.BuildStyle()
hook(native.button,61,false,true)
assert(Tint(2,1)=="noPowerColor","a custom color lost its state: "..tostring(Tint(2,1)))
hook(native.button,61,true,false)
assert(Tint(2,1)=="usableColor","the preview did not follow the payload")
config.noPowerColor=S.catalog.actionbars.rules.noPowerColor.default
AB.BuildStyle()
native.outOfRange=true
assert(Tint(2,1)=="rangeColor","range lost to the usability cache")
native.outOfRange=nil
AB.bars[2]=nil

------------------------------------------------------------------ fade, paint dormancy
local function Header()
    local h=Frame()
    h.attrs,h.groups={},{}
    function h:GetAttribute(name) return self.attrs[name] end
    function h:SetAttribute(name,value) self.attrs[name]=value end
    function h:EnableMouse() end
    function h:EnableMouseMotion() end
    function h:SetAlpha(alpha) self.alpha=alpha end
    function h:IsMouseOver() return false end
    function h:IsVisible() return true end
    function h:CreateAnimationGroup()
        local group={scripts={}}
        function group:CreateAnimation()
            local animation={}
            function animation:SetDuration() end
            function animation:SetFromAlpha() end
            function animation:SetToAlpha() end
            return animation
        end
        function group:SetScript(name,fn) self.scripts[name]=fn end
        function group:Play() end
        function group:Stop() end
        self.groups[#self.groups+1]=group
        return group
    end
    return h
end
local function HoverBar(index,state)
    local header=Header()
    header.attrs["state-vis"]=state
    local bar={index=index,key=AB.KEYS[index],header=header,owned=false,buttons={},filled={}}
    local button=Frame()
    button.TextOverlayContainer={SetAlpha=function() end}
    local rec={button=button,bar=bar,index=1,slot=1,owned=true,filled=true}
    bar.buttons[1]=rec
    AB.records[button]=rec
    AB.bars[index]=bar
    AB.headers=AB.headers or {}
    AB.headers[header]=bar
    return bar
end
local fading=HoverBar(1,"fade")
local button=fading.buttons[1].button
config.bar1Visibility,config.bar1FadeAlpha,config.bar1Alpha=VIS.MOUSEOVER,0,100
config.bar1FadeDuration=.3
AB.ApplyVisibility({[fading]=true})
assert(fading.paintDormant==true,"a faded bar must not paint")
button.scripts.OnEnter(button)
assert(fading.paintDormant==false,"revealing must resume painting at once")
button.scripts.OnLeave(button)
assert(fading.paintDormant==false,"a bar fading out is still on screen and must keep painting")
local group=assert(fading.header.groups[1],"the fade has no animation group")
group.scripts.OnFinished(group)
assert(fading.paintDormant==true,"the fade ended and the bar still paints")
-- Reversing the fade-out keeps painting; no fade time parks at once.
button.scripts.OnEnter(button)
button.scripts.OnLeave(button)
button.scripts.OnEnter(button)
group.scripts.OnFinished(group)
assert(fading.paintDormant==false,"a revealed bar was parked by the end of an old fade")
config.bar1FadeDuration=0
AB.ApplyVisibility({[fading]=true})
button.scripts.OnLeave(button)
assert(fading.paintDormant==true,"an instant fade must park the bar at once")
AB.bars[1]=nil

------------------------------------------------------------------ checked decoration, empty slot
local plain=Rec(Bar(1))
plain.decorFancy=true
plain.stateArt={shown=true}
function plain.stateArt:SetShown(value) self.shown=value end
plain.decorChecked=true
AB.Painter.Paint(plain)
assert(plain.filled==false and plain.decorChecked==false,"a button on an empty slot kept its checked flag")
assert(plain.stateArt.shown==false,"a button on an empty slot kept its checked frame art")
AB.bars[1]=nil

print("Action bar audit (runtime): key audit, native usability cache, fade dormancy and checked art passed")
