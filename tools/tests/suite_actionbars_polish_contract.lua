local root=assert(arg[1],"repository root required")
-- The client's securecallfunction reports an error and returns nothing;
-- this stand-in lets errors raise, so a failing callback fails the test.
securecallfunction=function(callback,...) return callback(...) end
-- Offline contract for the action bar polish options: the usability colors,
-- the per-bar tooltip rule, the mouseover fade time and the spell flyout
-- direction. The real core, the Suite modules and the action bar runtime
-- load against plain stand-ins; every case runs the shipped code.
local now,combat=100,false
GetTime=function() return now end
InCombatLockdown=function() return combat end
UnitAffectingCombat=function() return combat end
local timers=0
C_Timer={After=function() timers=timers+1 end,NewTicker=function() timers=timers+1 end}
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
-- Tooltip: who owns it, what it was asked to show, and every Hide.
local tip={actions={},hides=0}
GameTooltip={GetOwner=function() return tip.owner end,
    SetAction=function(_,slot) tip.actions[#tip.actions+1]=slot end,
    Hide=function() tip.hides=tip.hides+1;tip.owner=nil end}
GameTooltip_SetDefaultAnchor=function(_,owner) tip.owner=owner end
-- The action API, counting the usability reads (the one call a tint could add).
local calls={usable=0}
C_ActionBar=setmetatable({
    IsUsableAction=function() calls.usable=calls.usable+1;return true,false end,
    IsActionInRange=function() return true end,
}, {__index=function() return function() end end})
C_SpellActivationOverlay={IsSpellOverlayed=function() end}
C_Spell={GetOverrideSpell=function() end}
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
local rules=S.catalog.actionbars.rules
local USABLE=S.USABLE

------------------------------------------------------------------ catalog
for i=1,12 do
    local p="bar"..i
    assert(rules[p.."Tooltip"].default==ENUM.TOOLTIP.ALWAYS and #rules[p.."Tooltip"].choices==3,"tooltip choice "..i)
    assert(rules[p.."FadeDuration"].default==0 and rules[p.."FadeDuration"].min==0,"fade duration "..i)
    assert(rules[p.."FadeDuration"].requiresChoice.key==p.."Visibility","fade duration is a mouseover option")
    assert(rules[p.."FlyoutDirection"].default==ENUM.FLYOUT.AUTOMATIC and #rules[p.."FlyoutDirection"].choices==5,
        "flyout choice "..i)
    assert((rules[p.."FlyoutDirection"].hidden==true)==(i>10),"only the stance and pet bars lack flyouts: "..i)
end
for _,key in ipairs({"usableColor","noPowerColor","unusableColor"}) do
    assert(rules[key] and rules[key].color,key.." is not a color setting")
end

------------------------------------------------------------------ usability colors
-- Defaults paint Blizzard's own tints, float for float.
AB.BuildStyle()
for state,stock in pairs(S.USABLE_TINT) do
    for i=1,3 do assert(AB.style.tints[state][i]==stock[i],"default usability color differs from the stock tint") end
end
assert(AB.style.customTints==false,"default colors count as custom")
config.noPowerColor="ff8000"
AB.BuildStyle()
local r,g,b=S.RGB("ff8000")
assert(AB.style.customTints and AB.style.tints[USABLE.NO_POWER][1]==r and AB.style.tints[USABLE.NO_POWER][2]==g
    and AB.style.tints[USABLE.NO_POWER][3]==b,"custom color missing from the style")
assert(AB.style.tints[USABLE.UNUSABLE][1]==S.USABLE_TINT[USABLE.UNUSABLE][1],"an untouched color changed")
config.noPowerColor=rules.noPowerColor.default
-- The setting names reach the style and the tint walk.
for _,key in ipairs({"rangeColor","usableColor","noPowerColor","unusableColor"}) do
    assert(AB.GLOBAL_WORK[key].style and AB.GLOBAL_WORK[key].tint,key.." repaints no tint")
end

local function Icon()
    local icon={writes=0}
    function icon:SetVertexColor(...) self.vertex={...};self.writes=self.writes+1 end
    return icon
end
local function Bar(index,native)
    local bar={index=index,key=AB.KEYS[index],owned=false,native=native,buttons={},filled={},
        header={IsVisible=function() return true end}}
    AB.bars[index]=bar
    return bar
end
local function Rec(bar,native)
    local button={icon=Icon(),cooldown={},chargeCooldown={},lossOfControlCooldown={},
        IsVisible=function() return true end,HookScript=function() end,
        GetChecked=function() return false end,SetChecked=function() end}
    local rec={button=button,bar=bar,slot=61,owned=true,native=native,filled=true}
    bar.buttons[#bar.buttons+1],bar.filled[#bar.filled+1]=rec,rec
    AB.records[button]=rec
    return rec
end
local function Same(vertex,...) return vertex and vertex[1]==select(1,...) and vertex[2]==select(2,...) and vertex[3]==select(3,...) end
local Painter,Retint=AB.Painter,AB.NativeButtons.Retint

-- A suite button: the payload picks the color, the tint cache skips repeats,
-- a color change repaints from the cache without reading usability again.
local owned=Rec(Bar(1))
config.noPowerColor,config.unusableColor,config.usableColor="ff0000","00ff00","0000ff"
AB.BuildStyle()
calls.usable=0
Painter.Usable(owned,false,true)
assert(owned.tint==USABLE.NO_POWER and Same(owned.button.icon.vertex,S.RGB("ff0000")),"not enough resources color")
Painter.Usable(owned,false,false)
assert(owned.tint==USABLE.UNUSABLE and Same(owned.button.icon.vertex,S.RGB("00ff00")),"unusable color")
Painter.Usable(owned,true,false)
assert(owned.tint==USABLE.USABLE and Same(owned.button.icon.vertex,S.RGB("0000ff")),"usable color")
local writes=owned.button.icon.writes
Painter.Usable(owned,true,false)
assert(owned.button.icon.writes==writes,"the tint cache repainted an unchanged state")
config.usableColor="ffff00"
AB.BuildStyle()
Painter.Walk(Retint)
assert(Same(owned.button.icon.vertex,S.RGB("ffff00")) and owned.tint==USABLE.USABLE,"a color change did not reach the button")
assert(calls.usable==0,"a payload or a repaint read usability")
owned.outOfRange=true
Retint(owned)
assert(Same(owned.button.icon.vertex,AB.style.rr,AB.style.rg,AB.style.rb),"out of range lost to a usability color")
owned.outOfRange=nil
Retint(owned)
assert(Same(owned.button.icon.vertex,S.RGB("ffff00")),"back in range kept the range color")

-- A reused Blizzard button: Blizzard paints it; the suite adds a tint only
-- for custom colors or an out-of-range button, from Blizzard's own payload.
local nativeBar=Bar(2,true)
local native=Rec(nativeBar,true)
config.noPowerColor,config.unusableColor,config.usableColor=rules.noPowerColor.default,rules.unusableColor.default,rules.usableColor.default
AB.BuildStyle()
AB.UpdateCurves()
AB.RefreshNativeBar(nativeBar)
local hook=assert(hooks.UpdateUsable,"no usable hook on the reused button")
calls.usable,writes=0,native.button.icon.writes
hook(native.button,61,false,true)
assert(native.button.icon.writes==writes and calls.usable==0,"stock colors touched a Blizzard button")
config.noPowerColor="ff0000"
AB.BuildStyle()
hook(native.button,61,false,true)
assert(Same(native.button.icon.vertex,S.RGB("ff0000")) and calls.usable==0,"payload did not pick the custom color")
hook(native.button,61,true,false)
assert(Same(native.button.icon.vertex,1,1,1) and calls.usable==0,"a usable payload kept the old tint")
hook(native.button)
assert(calls.usable==1,"an update without payload must read usability exactly once")
native.outOfRange=true
calls.usable=0
hook(native.button,61,false,true)
assert(Same(native.button.icon.vertex,AB.style.rr,AB.style.rg,AB.style.rb) and calls.usable==0,"range color lost on a native")
native.outOfRange=nil
-- A color change walks the reused buttons; stock colors on an untinted one do nothing.
config.noPowerColor=rules.noPowerColor.default
AB.BuildStyle()
calls.usable,writes=0,native.button.icon.writes
Painter.WalkNative(Retint)
assert(calls.usable==1 and native.tint~=nil,"a tinted native button did not return to the stock tint")
native.tint=nil
calls.usable,writes=0,native.button.icon.writes
Painter.WalkNative(Retint)
assert(calls.usable==0 and native.button.icon.writes==writes,"an untinted native button was repainted")
AB.bars[1],AB.bars[2]=nil,nil

------------------------------------------------------------------ tooltips
local function Frame()
    local frame={scripts={}}
    function frame:HookScript(name,fn) self.scripts[name]=fn end
    return frame
end
local function Header()
    local h=Frame()
    h.attrs,h.groups,h.sets,h.protected={},{},0,0
    function h:GetAttribute(name) return self.attrs[name] end
    function h:SetAttribute(name,value) self.protected=self.protected+1;self.attrs[name]=value end
    function h:EnableMouse() self.protected=self.protected+1 end
    function h:EnableMouseMotion() self.protected=self.protected+1 end
    function h:SetAlpha(alpha) self.alpha=alpha;self.sets=self.sets+1 end
    function h:IsMouseOver() return false end
    function h:IsVisible() return true end
    function h:CreateAnimationGroup()
        local group={plays=0,stops=0,scripts={}}
        function group:CreateAnimation(kind)
            assert(kind=="Alpha","the fade is an Alpha animation")
            local animation={}
            function animation:SetDuration(v) self.duration=v end
            function animation:SetFromAlpha(v) self.from=v end
            function animation:SetToAlpha(v) self.to=v end
            self.animation=animation
            return animation
        end
        function group:SetScript(name,fn)
            assert(name=="OnFinished","a fade registered the script "..name)
            self.scripts[name]=fn
        end
        function group:Play() self.plays=self.plays+1 end
        function group:Stop() self.stops=self.stops+1 end
        self.groups[#self.groups+1]=group
        return group
    end
    return h
end
-- A bar of two buttons with its hover hooks, in the given driver state.
local function HoverBar(index,native,state)
    local header=Header()
    header.attrs["state-vis"]=state
    local bar={index=index,key=AB.KEYS[index],header=header,owned=false,native=native,buttons={},filled={}}
    for i=1,2 do
        local button=Frame()
        button.TextOverlayContainer={SetAlpha=function(self,a) self.alpha=a end}
        local rec={button=button,bar=bar,index=i,slot=i,owned=true,native=native,filled=true}
        bar.buttons[i]=rec
        AB.records[button]=rec
    end
    AB.bars[index]=bar
    AB.headers=AB.headers or {}
    AB.headers[header]=bar
    return bar
end
local function Enter(bar,i) local button=bar.buttons[i or 1].button;button.scripts.OnEnter(button) end
local function Leave(bar,i) local button=bar.buttons[i or 1].button;button.scripts.OnLeave(button) end

local suite=HoverBar(1,nil,"show")
AB.ApplyVisibility({[suite]=true})
local function Shown(count) assert(#tip.actions==count,"tooltip shown "..#tip.actions.." times, expected "..count) end
config.bar1Tooltip=ENUM.TOOLTIP.ALWAYS
Enter(suite);Shown(1)
assert(tip.owner==suite.buttons[1].button)
Leave(suite)
assert(tip.hides==1,"leaving a suite button must hide its tooltip")
config.bar1Tooltip=ENUM.TOOLTIP.NEVER
Enter(suite);Shown(1)
config.bar1Tooltip=ENUM.TOOLTIP.OUT_OF_COMBAT
Enter(suite);Shown(2)
combat=true
Enter(suite);Shown(2)
config.bar1Tooltip=ENUM.TOOLTIP.ALWAYS
Enter(suite);Shown(3)
combat=false

-- Blizzard's reused buttons show their own tooltip in their own OnEnter; the
-- post-hook takes it away where the setting says so, and only then.
local reused=HoverBar(2,true,"show")
AB.ApplyVisibility({[reused]=true})
local button=reused.buttons[1].button
local function BlizzardEnter(owner)
    tip.owner=owner or button
    button.scripts.OnEnter(button)
end
local hides=tip.hides
BlizzardEnter()
assert(tip.hides==hides and tip.owner==button,"Always hid Blizzard's tooltip")
config.bar2Tooltip=ENUM.TOOLTIP.NEVER
BlizzardEnter()
assert(tip.hides==hides+1 and tip.owner==nil,"Never left Blizzard's tooltip")
BlizzardEnter(suite.buttons[1].button)
assert(tip.hides==hides+1,"Never hid a tooltip another button owns")
config.bar2Tooltip=ENUM.TOOLTIP.OUT_OF_COMBAT
BlizzardEnter()
assert(tip.hides==hides+1 and tip.owner==button,"Out of combat hid the tooltip out of combat")
combat=true
BlizzardEnter()
assert(tip.hides==hides+2 and tip.owner==nil,"Out of combat kept the tooltip in combat")
combat=false
-- Quick Keybind mode shows Blizzard's binding tooltip on the reused buttons.
config.bar2Tooltip=ENUM.TOOLTIP.NEVER
QuickKeybindFrame={IsShown=function() return true end}
BlizzardEnter()
assert(tip.hides==hides+2 and tip.owner==button,"Never hid the Quick Keybind tooltip")
QuickKeybindFrame=nil
AB.bars[1],AB.bars[2]=nil,nil

------------------------------------------------------------------ mouseover fade
local bar=HoverBar(1,nil,"fade")
local header,overlay=bar.header,bar.buttons[1].button.TextOverlayContainer
config.bar1Visibility,config.bar1FadeAlpha,config.bar1Alpha,config.bar1FadeDuration=ENUM.VISIBILITY.MOUSEOVER,0,100,0
AB.ApplyVisibility({[bar]=true})
assert(header.alpha==.01 and overlay.alpha==0,"a mouseover bar starts faded")
Enter(bar)
assert(header.alpha==1 and overlay.alpha==1,"hover reveals at once without a fade time")
Leave(bar)
assert(header.alpha==.01 and overlay.alpha==0 and #header.groups==0 and timers==0,
    "no fade time must stay instant and create no animation")

config.bar1FadeDuration=.3
AB.ApplyVisibility({[bar]=true})
local group=assert(header.groups[1],"a fade time creates the header's animation group")
local animation=group.animation
assert(#header.groups==1 and animation.duration==.3 and group.scripts.OnFinished,"fade group setup")
assert(header.alpha==.01 and group.plays==0,"setting the fade time moved the bar")
Enter(bar)
assert(group.plays==1 and animation.from==.01 and animation.to==1 and header.alpha==1,"fade in")
assert(overlay.alpha==1,"the text of a revealed bar appears with the first frame")
-- Reversing a third of the way in starts from where the fade stands.
now=now+.1
Leave(bar)
assert(group.plays==2 and math.abs(animation.from-.34)<1e-9 and animation.to==.01 and header.alpha==.01,
    "a reversed fade must start from the current opacity")
assert(overlay.alpha==1,"the text of a fading-out bar hid before the fade ended")
group.scripts.OnFinished(group)
assert(overlay.alpha==0 and bar.fade.startedAt==nil,"the text did not follow the end of the fade")
-- Every other opacity change is instant (a slider tick), and stops a running fade.
Enter(bar)
local plays=group.plays
config.bar1Alpha=50
AB.UpdateAlpha(bar)
assert(header.alpha==.5 and group.plays==plays and group.stops>0,"a slider tick animated or left the fade running")
config.bar1Alpha=100
AB.UpdateAlpha(bar)
Leave(bar)
group.scripts.OnFinished(group)

-- In combat the fade still runs, and touches nothing protected or new.
combat=true
local created,protected,sets,tickers=#header.groups,header.protected,header.sets,timers
plays=group.plays
Enter(bar)
Leave(bar)
assert(group.plays==plays+2 and header.sets==sets+2,"fade does not run in combat")
assert(#header.groups==created and header.protected==protected and timers==tickers,
    "a fade in combat created a frame, wrote a protected value or started a timer")
AB.ApplyVisibility({[bar]=true})
assert(header.protected==protected,"the visibility pass ran in combat")
combat=false
-- Disabling the fade stops a running one; the bar goes back to instant changes.
config.bar1FadeDuration=0
AB.ApplyVisibility({[bar]=true})
group.scripts.OnFinished(group)
local stops=group.stops
plays=group.plays
Enter(bar)
assert(group.plays==plays and header.alpha==1,"a zero fade time still animated")
assert(group.stops==stops,"stopping a fade that was not running")
AB.bars[1]=nil
-- No steady-state Lua: the fade registers no per-frame script and no timer.
local source=assert(io.open(root.."/MSUF_Suite_ActionBars/Visibility.lua","rb")):read("*a"):gsub("%-%-[^\n]*","")
assert(not source:find("OnUpdate",1,true) and not source:find("NewTicker",1,true),"the fade polls")

------------------------------------------------------------------ flyout direction
local function Region()
    local region={points={},attributes={},sets=0}
    function region:SetSize(w,h) self.width,self.height=w,h end
    function region:ClearAllPoints() self.points={} end
    function region:SetPoint(...) self.points[#self.points+1]={...} end
    function region:GetCenter() return 512,100 end
    function region:SetAttribute(key,value) self.sets=self.sets+1;self.attributes[key]=value end
    function region:GetAttribute(key) return self.attributes[key] end
    function region:EnableMouse() end
    function region:Hide() end
    function region:Show() end
    function region:SetColorTexture() end
    return region
end
local layout={index=3,key=AB.KEYS[3],header=Region(),buttons={},owned=true,background=Region()}
for i=1,12 do layout.buttons[i]={button=Region(),index=i} end
local function Directions()
    local seen
    for i=1,12 do
        local value=layout.buttons[i].button.attributes.flyoutDirection
        assert(seen==nil or seen==value,"the buttons of one bar disagree on the flyout direction")
        seen=value
    end
    return seen
end
config.bar3Buttons,config.bar3Rows,config.bar3Vertical=12,1,false
AB.LayoutBar(layout)
assert(Directions()=="UP","Automatic must open toward the middle of the screen")
config.bar3Rows,config.bar3Vertical=12,true
AB.LayoutBar(layout)
assert(Directions()=="RIGHT","Automatic on a column")
for choice,word in pairs({[ENUM.FLYOUT.UP]="UP",[ENUM.FLYOUT.DOWN]="DOWN",[ENUM.FLYOUT.LEFT]="LEFT",[ENUM.FLYOUT.RIGHT]="RIGHT"}) do
    config.bar3FlyoutDirection=choice
    AB.LayoutBar(layout)
    assert(Directions()==word,"explicit flyout direction "..word)
end
local attributeWrites=layout.buttons[1].button.sets
AB.LayoutBar(layout)
assert(layout.buttons[1].button.sets==attributeWrites,"an unchanged flyout direction was written again")
config.bar3FlyoutDirection=ENUM.FLYOUT.AUTOMATIC
AB.LayoutBar(layout)
assert(Directions()=="RIGHT","back to Automatic")
assert(AB.BAR_WORK.FlyoutDirection.layout and AB.BAR_WORK.FadeDuration.visible and AB.BAR_WORK.Tooltip,
    "the per-bar options lost their settings work")

------------------------------------------------------------------ options page wiring
-- Every per-bar setting belongs to one group of the page: that group's section
-- builds, resets and copies it (and the search finds it there).
local page=assert(io.open(root.."/MSUF_Suite_Options/Pages/ActionBars.lua","rb")):read("*a")
local stop=assert(page:find("local function Preset",1,true))
local values={}
local P={Suite=Suite,S={},M={},W={},T={},Tr=function(text) return text end,
    catalog={actionbars={rules=rules}},Help=function(text) return text end,
    Get=function(_,key) return values[key] end,Combat=function() return false end}
local api=assert(loadstring(page:sub(1,stop-1).."return { groups = GROUPS, copy = CopyValues }"))("Options",P)
local owner={}
for _,section in ipairs(api.groups) do
    for _,suffix in ipairs(section.suffixes) do
        assert(not owner[suffix],suffix.." is in two groups")
        owner[suffix]=section.id
    end
end
for key,rule in pairs(rules) do
    local suffix=rule.bar and key:match("^bar%d+(.+)$")
    assert(not suffix or suffix=="ResumeVisibility" or owner[suffix],key.." belongs to no group of the page")
end
assert(owner.Tooltip=="visibility" and owner.FadeDuration=="visibility" and owner.FlyoutDirection=="layout")
values.bar1Tooltip,values.bar1FadeDuration,values.bar1FlyoutDirection=ENUM.TOOLTIP.NEVER,.4,ENUM.FLYOUT.LEFT
local copied={}
api.copy(copied,1,2,{visibility=true,layout=true})
assert(copied.bar2Tooltip==ENUM.TOOLTIP.NEVER and copied.bar2FadeDuration==.4 and copied.bar2FlyoutDirection==ENUM.FLYOUT.LEFT,
    "Copy To dropped a new per-bar setting")
copied={}
api.copy(copied,1,2,{text=true})
assert(copied.bar2Tooltip==nil and copied.bar2FlyoutDirection==nil,"a text copy carried a visibility or layout setting")
copied={}
api.copy(copied,1,11,{visibility=true,layout=true})
assert(copied.bar11Tooltip==ENUM.TOOLTIP.NEVER and copied.bar11FlyoutDirection==nil,
    "the stance bar has no flyouts to copy a direction to")

print("Action bar polish: usability colors, tooltip modes, fade timing, flyout direction and page wiring passed")
