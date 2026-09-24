local root=assert(arg[1],"repository root required")
-- Offline contract for the cooldown manager's layout plane (Layout.lua,
-- Visibility.lua, Native.lua, Preview.lua): pixel math, diffed writes,
-- anchoring chains, MSUF unit frame anchors with cached rectangles, riding
-- Blizzard's invisible Essential bar, Edit Mode drag previews, aura overlay
-- edges, visibility sources (events for "Always", shared drivers for the
-- rest) with mouse gating, Blizzard viewer takeover and restore, first-run
-- capture and the options canvas. Free bars place their growth edge
-- relative to UIParent's center; x/y of an attached bar are an offset from
-- its attach point. Budgets: repeated passes make no widget calls, no
-- geometry reads and no garbage.
local floor=math.floor

------------------------------------------------------------------ secrets
local SecretMT={}
local function Raise(what) return function() error("secret value used: "..what,2) end end
for _,key in ipairs({"__add","__sub","__mul","__div","__mod","__pow","__unm","__concat","__lt","__le","__eq","__call","__len"}) do
    SecretMT[key]=Raise(key)
end
SecretMT.__index=Raise("index");SecretMT.__newindex=Raise("assignment");SecretMT.__tostring=Raise("tostring")
local function Secret() return setmetatable({},SecretMT) end
issecretvalue=function(value) return getmetatable(value)==SecretMT end

------------------------------------------------------------------ frames
local calls={}
local function Count(name) calls[name]=(calls[name] or 0)+1 end
local function ResetCalls() for key in pairs(calls) do calls[key]=nil end end
local WRITES={"SetPoint","ClearAllPoints","SetSize","SetAlpha","Show","Hide","SetFrameStrata","SetAllPoints","EnableMouse",
    "SetScale","SetTexture","SetVertexColor","SetShown","SetText","SetFont","SetMouseClickEnabled","SetMouseMotionEnabled",
    "RegisterEvent","RegisterUnitEvent","UnregisterEvent"}
local function Writes() local n=0; for _,name in ipairs(WRITES) do n=n+(calls[name] or 0) end; return n end
local created=0
local frames={}
local Frame={}
Frame.__index=Frame
function CreateFrame(kind,_,parent)
    created=created+1
    local frame=setmetatable({kind=kind,parent=parent,shown=true,points={},scripts={},attrs={},alpha=1,mouse=true,
        events={}},Frame)
    frames[#frames+1]=frame
    return frame
end
-- Plain recorded setters: the value lands in frame[field].
local function Setter(name,field)
    Frame[name]=function(self,value) Count(name); self[field]=value end
end
Setter("SetScale","scale"); Setter("SetTexture","texture"); Setter("SetText","text"); Setter("SetFont","font")
Setter("SetMouseClickEnabled","click"); Setter("SetMouseMotionEnabled","motion")
function Frame:SetVertexColor(r,g,b,a) Count("SetVertexColor"); self.color={r,g,b,a} end
function Frame:SetShown(shown) Count("SetShown"); self.shown=shown and true or false end
function Frame:SetWordWrap() end
function Frame:SetJustifyH() end
function Frame:RegisterEvent(event) Count("RegisterEvent"); self.events[event]=true end
function Frame:RegisterUnitEvent(event,unit) Count("RegisterUnitEvent"); self.events[event]=unit end
function Frame:UnregisterEvent(event) Count("UnregisterEvent"); self.events[event]=nil end
function Frame:SetPoint(point,rel,relPoint,x,y)
    Count("SetPoint")
    for i,p in ipairs(self.points) do
        if p[1]==point then self.points[i]={point,rel,relPoint,x,y}; return end
    end
    self.points[#self.points+1]={point,rel,relPoint,x,y}
end
function Frame:ClearAllPoints() Count("ClearAllPoints"); self.points={} end
function Frame:SetAllPoints(target) Count("SetAllPoints"); self.allPoints=target end
function Frame:SetSize(w,h) Count("SetSize"); self.w,self.h=w,h end
function Frame:SetAlpha(alpha) Count("SetAlpha"); self.alpha=alpha end
function Frame:GetAlpha() return self.alpha end
function Frame:Show() Count("Show"); self.shown=true end
function Frame:Hide() Count("Hide"); self.shown=false end
function Frame:IsShown() return self.shown end
function Frame:SetFrameStrata(strata) Count("SetFrameStrata"); self.strata=strata end
function Frame:SetClampedToScreen(value) self.clamped=value end
function Frame:SetScript(key,fn) self.scripts[key]=fn end
function Frame:SetAttribute(key,value)
    self.attrs[key]=value
    local handler=self.scripts.OnAttributeChanged
    if handler then handler(self,key,value) end
end
function Frame:GetAttribute(key) return self.attrs[key] end
function Frame:EnableMouse(value) Count("EnableMouse"); self.mouse=value end
function Frame:IsForbidden() return false end
function Frame:GetEffectiveScale() return self.scale or 1 end
function Frame:GetCenter() return self.cx,self.cy end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:GetRect() Count("GetRect"); local r=self.rect; if r then return r[1],r[2],r[3],r[4] end end
function Frame:GetChildren() return unpack(self.children or {}) end

------------------------------------------------------------------ client
local combat=false
InCombatLockdown=function() return combat end
local physicalHeight=768
GetPhysicalScreenSize=function() return 1024,physicalHeight end
UIParent=CreateFrame("Frame")
UIParent.width,UIParent.height=1920,1080
UIParent.scale=1
-- Pet battle, vehicle interface and override bar state for "Always" bars.
local inPetBattle,vehicleUI,overrideBar=false,false,false
C_PetBattles={IsInBattle=function() return inPetBattle end}
UnitHasVehicleUI=function(unit) assert(unit=="player","vehicle state is read for the player"); return vehicleUI end
HasOverrideActionBar=function() return overrideBar end
local hooks={}
hooksecurefunc=function(target,name,hook)
    hooks[#hooks+1]=name
    local original=target[name]
    target[name]=function(...) original(...); hook(...) end
end

-- Secure state driver manager: resolves at registration and on Tick().
local cond={}
local drivers,registered,unregistered={},0,0
local function Evaluate(expr)
    for clause in (expr..";"):gmatch("%s*([^;]-)%s*;") do
        local head,action=clause:match("^(.*%])%s*(%S+)$")
        if not head then return clause end
        for group in head:gmatch("%[(.-)%]") do
            local ok=true
            for token in group:gmatch("[^,]+") do
                if token=="exists" then ok=ok and cond.target==true
                elseif token~="@target" then ok=ok and cond[token]==true end
            end
            if ok then return action end
        end
    end
end
local function Resolve(frame,attr,values)
    local value=Evaluate(values)
    if frame:GetAttribute(attr)~=value then frame:SetAttribute(attr,value) end
end
RegisterAttributeDriver=function(frame,attr,values)
    assert(not combat,"driver registered in combat")
    registered=registered+1
    drivers[frame]=drivers[frame] or {}
    drivers[frame][attr]=values
    Resolve(frame,attr,values)
end
UnregisterAttributeDriver=function(frame,attr)
    assert(not combat,"driver unregistered in combat")
    unregistered=unregistered+1
    if drivers[frame] then drivers[frame][attr]=nil end
end
local function Tick()
    for frame,set in pairs(drivers) do for attr,values in pairs(set) do Resolve(frame,attr,values) end end
end

------------------------------------------------------------------ suite core + catalog
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",IsRetail=true,SupportsEvent=function() return true end}}
WOW_PROJECT_ID,WOW_PROJECT_MAINLINE=1,1
C_CooldownViewer={GetCooldownViewerCategorySet=function() return {} end,GetCooldownViewerCooldownInfo=function() end}
C_Spell={GetSpellCooldownDuration=function() end}
MSUF_EncodeCompactTable=function() return "" end
MSUF_TryDecodeCompactString=function() return nil end
local NS={}
for _,file in ipairs({"Core/Platform.lua","Core/Database.lua","Core/SuiteCatalog.lua"}) do
    assert(loadfile(root.."/MSUF_Suite/"..file))("MSUF_Suite",NS)
end
-- moduleAddons lacks the module until integration; register it locally.
local B=NS.CatalogBuild
local original=B.Module
B.Module=function(mid,spec)
    if mid=="cooldownManager" then
        spec.id,spec.addon,spec.controls,spec.rules,spec.conflicts=mid,"MSUF_Suite_CooldownManager",{},{},spec.conflicts or {}
        NS.SuiteCatalog[mid]=spec
        NS.SuiteOrder[#NS.SuiteOrder+1]=mid
        B.Add(mid,B.Bool("enabled","Enable module",false))
        return spec
    end
    return original(mid,spec)
end
assert(loadfile(root.."/MSUF_Suite/Core/Catalog/CooldownManager.lua"))("MSUF_Suite",NS)
local CDM=NS.CDM
local rules=NS.SuiteCatalog.cooldownManager.rules

------------------------------------------------------------------ minimal bootstrap
local restoredCVars={}
local queued={}
local S={
    Public=function(value) return not issecretvalue(value) end,
    Text=function(text) return text end,
    CreateFrame=function(...) return CreateFrame(...) end,
    Queue=function(id) queued[#queued+1]=id end,
    RestoreCVar=function(id,key) restoredCVars[#restoredCVars+1]=id..":"..key end,
}
NS.Suite=S
local config={}
for key,rule in pairs(rules) do config[key]=rule.default end
local M={active=true,config=config,id="cooldownManager"}
local C={M=M,EMPTY={},state={inCombat=false,preview=false},views={},plans={},bars={},entries={}}
local P={NS=NS,Suite=S,CDM=C}

local FILES={"Layout","Visibility","Native","Preview"}
local createdBefore=created
for _,name in ipairs(FILES) do
    local path=root.."/MSUF_Suite_CooldownManager/"..name..".lua"
    local chunk,err=loadfile(path)
    assert(chunk,err)
    chunk("MSUF_Suite_CooldownManager",P)
end
assert(created==createdBefore,"loading the layout plane created frames")
local L,V,N,Pv=C.Layout,C.Visibility,C.Native,C.Preview
assert(L and V and N and Pv,"exports missing")
for _,name in ipairs({"PixelScale","InvalidateScale","EnsureBar","Apply","ApplyAll","Offsets","Cell","Hide","HideAll",
    "Metrics","Point","Parent","FrameTarget","Free","Movable","DragPlace","ForgetAnchors","CombatEnded","Request","Flush"}) do
    assert(type(L[name])=="function","Layout."..name.." missing")
end
for _,name in ipairs({"Apply","ApplyAll","CombatChanged","ReleaseAll","FlushPending","HasPending","Paint","Binding","DriverCount"}) do
    assert(type(V[name])=="function","Visibility."..name.." missing")
end
for _,name in ipairs({"Apply","Release","Capture","Mode","AnchorFrame","FollowViewer","Applied"}) do
    assert(type(N[name])=="function","Native."..name.." missing")
end
for _,name in ipairs({"SetMode","Simulate","Decorate","Render","Release","ReleaseAll"}) do
    assert(type(Pv[name])=="function","Preview."..name.." missing")
end
assert(M.cvars and M.cvars.cooldownViewerEnabled==true,"cooldownViewerEnabled not declared as a module CVar")

------------------------------------------------------------------ source rules
for _,name in ipairs(FILES) do
    local file=assert(io.open(root.."/MSUF_Suite_CooldownManager/"..name..".lua","rb"))
    local text=file:read("*a"):gsub("\r","")
    file:close()
    assert(text:find("^local _,P=%.%.%.\nlocal NS,S=P%.NS,P%.Suite\nlocal C=P%.CDM\n"),"header of "..name)
    local code=text:gsub("%-%-[^\n]*","")
    -- The options simulation owns the only timer of the plane (while it runs).
    for _,token in ipairs({"pcall","loadstring","setfenv","OnUpdate","C_Timer","CooldownViewerSettings"}) do
        assert(not code:find(token,1,true) or (name=="Preview" and token=="C_Timer"),name..".lua uses "..token)
    end
    assert(not text:find("Claude",1,true) and not text:find("Anthropic",1,true),name..".lua attribution")
    local count=0
    for hooked in code:gmatch('hooksecurefunc%(%s*[%w_]+%s*,%s*"([%w_]+)"') do
        count=count+1
        assert(name=="Native" and (hooked=="SetAlpha" or hooked=="OnAcquireItemFrame"),"hook not allowed: "..hooked)
    end
    assert(count==(name=="Native" and 2 or 0),"unexpected hook count in "..name)
end

------------------------------------------------------------------ views and plans
local function BuildView(i)
    local slot=CDM.SLOTS[i]
    local view={key=slot.key,index=i,builtin=slot.builtin==true,title=slot.title,layoutGen=1}
    for suffix,key in pairs(CDM.KEYS[slot.key]) do view[suffix]=rules[key].default end
    view.kind=view.kind or slot.kind or 1
    return view
end
for i=1,#CDM.SLOTS do C.views[CDM.SLOTS[i].key]=BuildView(i) end
local function Touch(slot) C.views[slot].layoutGen=C.views[slot].layoutGen+1 end
local function Entry(unit) return {icon=nil,unit=unit} end
local function IconEntries(slot,n)
    local list={}
    for i=1,n do list[i]={key="b"..i,icon=CreateFrame("Frame",nil,nil),slot=slot,index=i} end
    return list
end
local function Plan(slot,entries) C.plans[slot]={slot=slot,kind=C.views[slot].kind,entries=entries} end

local function Near(a,b) return math.abs(a-b)<1e-9 end
local function Point(frame,i) return frame.points[i or 1] end
local function CheckPoint(frame,point,rel,relPoint,x,y,label)
    local p=Point(frame)
    assert(#frame.points==1,label..": expected one point, got "..#frame.points)
    assert(p[1]==point and p[2]==rel and p[3]==relPoint,label..": anchor "..tostring(p[1]).." "..tostring(p[3]))
    assert(Near(p[4],x) and Near(p[5],y),label..": offset "..tostring(p[4])..","..tostring(p[5]).." ~= "..x..","..y)
end

------------------------------------------------------------------ pixel scale
assert(L.PixelScale()==1 and C.state.px==1,"px at 768 physical lines and scale 1")
physicalHeight=1080
assert(L.PixelScale()==1,"px must stay cached until invalidated")
assert(Near(L.InvalidateScale(),768/1080) and Near(C.state.px,768/1080),"px recompute after invalidate")
UIParent.scale=Secret()
assert(L.InvalidateScale()==1,"secret scale falls back to 1")
UIParent.scale=1
physicalHeight=768
assert(L.InvalidateScale()==1)

------------------------------------------------------------------ offsets (pure)
local out={}
local grid={kind=1,size=10,height=100,spacing=2,perRow=4,maxIcons=0,vertical=false,align=1,grow=1}
ResetCalls()
local w,h,n=L.Offsets(grid,6,out)
assert(Writes()==0,"Offsets must not touch widgets")
assert(w==46 and h==22 and n==6,"footprint 4x2 rows: "..w.."x"..h)
local expect={0,0,12,0,24,0,36,0,12,-12,24,-12}
for i=1,12 do assert(Near(out[i],expect[i]),"centered partial row at "..i..": "..tostring(out[i])) end
grid.grow=2
L.Offsets(grid,6,out)
expect={0,-12,12,-12,24,-12,36,-12,12,0,24,0}
for i=1,12 do assert(Near(out[i],expect[i]),"grow up at "..i) end
grid.grow,grid.align=1,2
L.Offsets(grid,6,out)
assert(out[9]==0 and out[11]==12,"start aligned partial row")
grid.align=3
L.Offsets(grid,6,out)
assert(out[9]==24 and out[11]==36,"end aligned partial row")
grid.align=1
-- odd free space: the centering origin is floored once
grid.spacing=1
L.Offsets(grid,5,out)
assert(out[9]==16 and out[10]==-11,"floored centering origin")
grid.spacing=2
-- vertical: columns of perRow, grow right, then left
grid.vertical=true
w,h=L.Offsets(grid,6,out)
assert(w==22 and h==46,"vertical footprint")
expect={0,0,0,-12,0,-24,0,-36,12,-12,12,-24}
for i=1,12 do assert(Near(out[i],expect[i]),"vertical at "..i) end
grid.grow=2
L.Offsets(grid,6,out)
assert(out[1]==12 and out[9]==0,"vertical grow left mirrors columns")
grid.vertical,grid.grow=false,1
-- empty bar keeps one cell; maxIcons caps
w,h,n=L.Offsets(grid,0,out)
assert(w==10 and h==10 and n==0,"empty footprint is one icon")
grid.maxIcons=3
w,h,n=L.Offsets(grid,6,out)
assert(n==3 and w==34 and h==10,"maxIcons caps the layout")
grid.maxIcons=0
grid.height=50
w,h=L.Offsets(grid,1,out)
assert(w==10 and h==5,"icon height percent")
grid.height=100
-- negative spacing overlaps borders
grid.spacing=-2
w=L.Offsets(grid,4,out)
assert(w==34 and out[3]==8,"negative spacing")
grid.spacing=2
-- pixel snapping at a fractional scale: every value is a whole pixel
physicalHeight=1080
local px=L.InvalidateScale()
grid.size,grid.spacing=42.3,3
w,h=L.Offsets(grid,7,out)
local function Whole(value) local p=value/px; return math.abs(p-floor(p+.5))<1e-6 end
assert(Whole(w) and Whole(h),"snapped footprint")
for i=1,14 do assert(Whole(out[i]),"snapped offset "..i) end
assert(Near(w,(4*59+3*4)*px),"42.3 units = 59 px, 3 units = 4 px")
local mw,mh,msp,mper=L.Metrics(grid)
assert(Near(mw,59*px) and Near(mh,59*px) and Near(msp,4*px) and mper==4,"metrics are pixel exact")
assert(Near(L.Snap(10),14*px),"Snap rounds to whole pixels")
grid.size,grid.spacing=10,2
physicalHeight=768
L.InvalidateScale()

------------------------------------------------------------------ bars: layout and zero-call repeat
local ess,uti,buf,ext=C.views.ess,C.views.uti,C.views.buf,C.views.ext
-- slot order: anchor index = slot index + 1, then MSUF's player and target frames
local ORDER={"ess","uti","def","ext","buf","bar","c1","c2","c3","c4","c5","c6"}
for i,key in ipairs(ORDER) do assert(CDM.SLOTS[i].key==key and CDM.SLOT_INDEX[key]==i,"slot "..i.." is "..key) end
local function AnchorOf(slot) return CDM.SLOT_INDEX[slot]+1 end
local PLAYER,TARGET=#CDM.SLOTS+2,#CDM.SLOTS+3
-- defaults: the free Essential bar's top edge ESS_Y units below the screen
-- center (under MSUF's default player castbar); every other bar is attached
-- with a zero offset (unused custom bars start in the middle once freed)
local ESS_Y=-222
assert(ess.anchor==1 and ess.x==0 and ess.y==ESS_Y,"Essential default position "..tostring(ess.x)..","..tostring(ess.y))
for i=2,#CDM.SLOTS do
    local view=C.views[CDM.SLOTS[i].key]
    assert(view.x==0 and view.y==0,CDM.SLOTS[i].key.." default offset is zero")
end
assert(CDM.FRAME_ANCHORS[PLAYER]=="player" and CDM.FRAME_ANCHORS[TARGET]=="target","frame anchors after the bar entries")
assert(CDM.ANCHOR_LABELS[PLAYER]=="Player frame" and CDM.ANCHOR_LABELS[TARGET]=="Target frame" and #CDM.ANCHOR_LABELS==TARGET,"anchor labels")
-- MSUF follows the Essential bar: every show/hide of that bar notifies it
local anchorChanges=0
C.AnchorChanged=function() anchorChanges=anchorChanges+1 end
-- Icon and aura layer entry points the layout plane calls (guarded there):
-- overlay edges from PlaceIcons, mouse edges from the visibility paint.
local overlayLog,mouseLog,auraMouseLog={},{},{}
C.Auras={
    OverlayShown=function(entry,on) overlayLog[#overlayLog+1]={entry,on} end,
    SetBarMouse=function(slot,on) auraMouseLog[#auraMouseLog+1]=slot..(on and "+" or "-") end,
    -- the aura layer's row rule (Auras.lua A.TargetRow)
    TargetRow=function(e) return e.unit=="target" or (e.unit=="both" and e.selfAura~=true) end,
}
C.Icons={SetBarMouse=function(slot,on) mouseLog[#mouseLog+1]=slot..(on and "+" or "-") end}
local function Clear(list) for i=#list,1,-1 do list[i]=nil end end
local function Logged(list,value) for i=1,#list do if list[i]==value then return true end end return false end
local essEntries=IconEntries("ess",5)
Plan("ess",essEntries)
Plan("uti",IconEntries("uti",3))
local bufEntries={Entry("player"),Entry("target"),Entry("player"),Entry("target"),Entry("player")}
Plan("buf",bufEntries)
Plan("bar",{Entry("player"),Entry("player"),Entry("player")})
Plan("ext",{})
L.ApplyAll()
local essBar=C.bars.ess
assert(essBar and essBar.frame and essBar.frame.parent==UIParent and essBar.frame.clamped,"bar frame is a clamped UIParent child")
assert(essBar.frame.shown and essBar.shown,"applied bar is shown")
assert(anchorChanges==1,"showing the Essential bar notifies MSUF once, got "..anchorChanges)
-- 40 units at 90 percent height: 36 units tall, 2 units apart
assert(essBar.frame.w==208 and essBar.frame.h==36,"ess content size "..tostring(essBar.frame.w).."x"..tostring(essBar.frame.h))
CheckPoint(essBar.frame,"TOP",UIParent,"CENTER",0,ESS_Y,"free ess bar: top edge from the screen center")
for i=1,5 do
    local icon=essEntries[i].icon
    CheckPoint(icon,"TOPLEFT",essBar.frame,"TOPLEFT",(i-1)*42,0,"ess icon "..i)
    assert(icon.shown,"ess icon shown")
end
-- every icon's first placement switches its aura overlay on, once
local seenOn=0
for _,call in ipairs(overlayLog) do
    for i=1,5 do if call[1]==essEntries[i] then assert(call[2]==true,"first placement shows the overlay");seenOn=seenOn+1 end end
end
assert(seenOn==5,"one overlay edge per placed ess icon, got "..seenOn)
assert(essBar.frame.strata=="MEDIUM","default strata")
-- anchor frames: ess/uti/buf only, same rectangle as the bar
for _,slot in ipairs({"ess","uti","buf"}) do
    local record=C.bars[slot]
    assert(record.anchorFrame and record.anchorFrame.parent==record.frame and record.anchorFrame.allPoints==record.frame,"anchor frame for "..slot)
end
assert(C.bars.bar.anchorFrame==nil and C.bars.ext.anchorFrame==nil,"no anchor frame for bar/ext")
assert(C.bars.def==nil,"a bar without a plan creates no frame")
-- one centered stack: uti below ess, buf below uti, bar below buf
CheckPoint(C.bars.uti.frame,"TOP",essBar.frame,"BOTTOM",0,-2,"uti below ess")
assert(C.bars.uti.frame.w==100 and C.bars.uti.frame.h==29,"uti size "..tostring(C.bars.uti.frame.w).."x"..tostring(C.bars.uti.frame.h))
CheckPoint(C.bars.buf.frame,"TOP",C.bars.uti.frame,"BOTTOM",0,-4,"buf below uti")
CheckPoint(C.bars.bar.frame,"TOP",C.bars.buf.frame,"BOTTOM",0,-4,"bar below buf")
-- ext sits on MSUF's player frame; without that frame it keeps its own position
assert(L.FrameTarget("ext")=="player" and L.FrameTarget("def")=="player","potions and defensives follow the player frame")
assert(L.FrameTarget("ess")==nil and L.FrameTarget("uti")==nil,"bar anchors are not frame anchors")
CheckPoint(C.bars.ext.frame,"TOP",UIParent,"CENTER",0,0,"ext free at the screen center without MSUF's player frame")
assert(C.bars.ext.frame.w==28 and C.bars.ext.frame.h==25,"empty ext keeps one icon footprint")
-- aura icon bar: player line first in growth order (down), target line below
local bufBar=C.bars.buf
assert(bufBar.auraHost and bufBar.auraHost.parent==bufBar.frame and bufBar.auraHost.allPoints==bufBar.frame,"aura host")
assert(bufBar.frame.w==94 and bufBar.frame.h==56,"buf grouped footprint "..tostring(bufBar.frame.w).."x"..tostring(bufBar.frame.h))
assert(bufBar.lines1==1 and bufBar.lines2==1,"line split recorded")
local cellAt={{0,0},{16,-29},{32,0},{48,-29},{64,0}}
for i=1,5 do
    local cell=L.Cell("buf",i)
    assert(cell.parent==bufBar.auraHost,"cell parent")
    CheckPoint(cell,"TOPLEFT",bufBar.auraHost,"TOPLEFT",cellAt[i][1],cellAt[i][2],"buf cell "..i)
    assert(cell.w==30 and cell.h==27 and cell.shown,"cell size")
end
assert(L.Cell("buf",3)==bufBar.cells[3],"cells are stable")
assert(#bufBar.cells==5,"the first cell request makes a cell for every entry at once")
-- an existing cell is a lookup: no layout pass, no widget call (the flush's
-- layout pass keeps cells placed), even while the plan moved on
Plan("buf",{Entry("target"),Entry("target"),Entry("player"),Entry("player"),Entry("player")})
ResetCalls()
for i=1,5 do assert(L.Cell("buf",i)==bufBar.cells[i]) end
assert(Writes()==0,"existing cells wrote "..Writes().." times")
CheckPoint(bufBar.cells[1],"TOPLEFT",bufBar.auraHost,"TOPLEFT",0,0,"cells keep their place until the layout pass")
Plan("buf",bufEntries)
-- missing cells: made up to the laid-out entries (maxIcons caps), placed once
do
    local c6=C.views.c6
    c6.kind,c6.maxIcons=2,4
    Plan("c6",{Entry("player"),Entry("player"),Entry("player"),Entry("player"),Entry("player"),Entry("player")})
    local cell=L.Cell("c6",2)
    local cells=C.bars.c6.cells
    assert(cell==cells[2] and #cells==4,"cells up to maxIcons at once, got "..#cells)
    for i=1,4 do assert(#cells[i].points==1 and cells[i].shown,"new cell "..i.." placed") end
    -- custom bars: 36 units, spacing 2
    CheckPoint(cells[4],"TOPLEFT",C.bars.c6.auraHost,"TOPLEFT",114,0,"fourth cell in line")
    ResetCalls()
    L.Cell("c6",4)
    assert(Writes()==0,"a later request for a made cell writes nothing")
    assert(L.Cell("c6",5)==cells[5] and #cells==5 and #cells[5].points==0,"a cell past the cap is made on request, never placed")
    c6.kind,c6.maxIcons=1,0
    C.plans.c6=nil
end
-- Blizzard aura entries track both units ("both"); the aura layer's rule
-- names their row (own buffs: the player row, tracked debuffs: the target
-- row), so its containers and these cells agree. One fixed cell serves the
-- player's and the target's slot of an entry.
local function Both(self) return {unit="both",selfAura=self} end
Plan("buf",{Both(true),Entry("target"),Both(false),Entry("player")})
L.Apply("buf")
assert(bufBar.lines1==1 and bufBar.lines2==1,"one player line, one target line")
assert(bufBar.frame.w==62 and bufBar.frame.h==56,"footprint with both entries "..tostring(bufBar.frame.w).."x"..tostring(bufBar.frame.h))
local bothAt={{0,0},{0,-29},{32,-29},{32,0}}
for i=1,4 do CheckPoint(bufBar.cells[i],"TOPLEFT",bufBar.auraHost,"TOPLEFT",bothAt[i][1],bothAt[i][2],"both-unit cell "..i) end
assert(not bufBar.cells[5].shown,"cell beyond the entries hides")
Plan("buf",{Both(true),Both(true)})
L.Apply("buf")
assert(bufBar.lines1==1 and bufBar.lines2==0 and bufBar.frame.w==62 and bufBar.frame.h==27,"own buffs fill one player line")
CheckPoint(bufBar.cells[2],"TOPLEFT",bufBar.auraHost,"TOPLEFT",32,0,"second own buff on the player line")
Plan("buf",{Both(false),Both(nil)})
L.Apply("buf")
assert(bufBar.lines1==0 and bufBar.lines2==1 and bufBar.frame.w==62 and bufBar.frame.h==27,"tracked debuffs only: one target line")
CheckPoint(bufBar.cells[1],"TOPLEFT",bufBar.auraHost,"TOPLEFT",0,0,"a bar of tracked debuffs starts at the growth point")
-- without the aura layer's rule only target entries take the target row
local rowRule=C.Auras.TargetRow
C.Auras.TargetRow=nil
Plan("buf",{Both(false),Entry("target")})
L.Apply("buf")
assert(bufBar.lines1==1 and bufBar.lines2==1,"fallback: both entries in the player row")
C.Auras.TargetRow=rowRule
Plan("buf",bufEntries)
L.Apply("buf")
for i=1,5 do CheckPoint(bufBar.cells[i],"TOPLEFT",bufBar.auraHost,"TOPLEFT",cellAt[i][1],cellAt[i][2],"buf cell "..i.." restored") end
-- aura bar bar: the built-in bar has a grow rule, default Down; 220x(3*20+2*2)
local barBar=C.bars.bar
assert(C.views.bar.grow==1 and CDM.KEYS.bar.grow,"built-in buff bars carry a grow rule")
assert(barBar.frame.w==220 and barBar.frame.h==64,"buff bar footprint")
for i=1,3 do
    local cell=L.Cell("bar",i)
    CheckPoint(cell,"TOPLEFT",barBar.auraHost,"TOPLEFT",0,-(i-1)*22,"bar cell "..i)
    assert(cell.w==220 and cell.h==20,"bar cell size")
end
C.views.bar.grow=2; Touch("bar"); L.Apply("bar")
for i=1,3 do CheckPoint(barBar.cells[i],"TOPLEFT",barBar.auraHost,"TOPLEFT",0,-(3-i)*22,"bar cell grows up "..i) end
CheckPoint(barBar.frame,"TOP",bufBar.frame,"BOTTOM",0,-4,"attached bar keeps its attach point when growing up")
C.views.bar.grow=1; Touch("bar"); L.Apply("bar")
ResetCalls()
L.ApplyAll()
assert(Writes()==0,"repeat ApplyAll wrote "..Writes().." times")
L.Apply("ess"); L.Apply("buf"); L.Apply("bar")
assert(Writes()==0,"repeat Apply wrote")
assert(anchorChanges==1,"repeat passes do not notify MSUF")
-- no allocation, no widget call and no overlay edge on unchanged passes
Clear(overlayLog)
collectgarbage("collect"); collectgarbage("stop")
local before=collectgarbage("count")
for _=1,200 do L.Apply("ess"); L.Apply("buf"); L.ApplyAll(); L.Flush() end
local grown=collectgarbage("count")-before
collectgarbage("restart")
assert(grown<1,"unchanged layout passes allocated "..grown.." KB")
assert(Writes()==0 and #overlayLog==0,"unchanged layout passes wrote "..Writes().." times")

-- empty aura bars keep one cell
Plan("bar",{})
L.Apply("bar")
assert(barBar.frame.w==220 and barBar.frame.h==20,"empty buff bar keeps one bar")
assert(not barBar.cells[1].shown,"cells beyond the entries hide")
Plan("buf",{})
L.Apply("buf")
assert(bufBar.frame.w==30 and bufBar.frame.h==27,"empty buff icons keep one icon")
Plan("buf",bufEntries)
L.Apply("buf")

-- hideReady: hidden entries drop out and the row re-centers; the aura
-- overlay of a hidden icon switches off with it (it is no child of the icon)
essEntries[2].hidden=true
ResetCalls()
L.Apply("ess")
assert(not essEntries[2].icon.shown,"hidden entry's icon hides")
assert(#overlayLog==1 and overlayLog[1][1]==essEntries[2] and overlayLog[1][2]==false,"hiding an icon hides its overlay")
assert(essBar.frame.w==4*40+3*2,"bar shrinks to visible icons")
CheckPoint(essEntries[3].icon,"TOPLEFT",essBar.frame,"TOPLEFT",42,0,"next icon moves up")
assert((calls.ClearAllPoints or 0)==0,"moving a placed icon keeps its single point")
-- the dependent chain follows without writes of its own
assert(Point(C.bars.uti.frame)[2]==essBar.frame,"uti still attached")
L.Apply("ess")
assert(#overlayLog==1,"a steady hidden icon repeats no overlay edge")
C.state.preview=true
L.Apply("ess")
assert(essEntries[2].icon.shown and essBar.frame.w==208,"preview shows hidden entries")
assert(#overlayLog==2 and overlayLog[2][1]==essEntries[2] and overlayLog[2][2]==true,"a shown icon shows its overlay")
C.state.preview=false
essEntries[2].hidden=nil
L.Apply("ess")
assert(#overlayLog==2,"no edge while the icon stays shown")
Clear(overlayLog)
-- pooled icon released by the icon layer and back for another entry
local moved=essEntries[5].icon
table.remove(essEntries,5)
L.Apply("ess")
moved:ClearAllPoints(); moved:Hide()
local newcomer={key="s99",icon=moved}
essEntries[5]=newcomer
L.Apply("ess")
CheckPoint(moved,"TOPLEFT",essBar.frame,"TOPLEFT",168,0,"returning pooled icon is re-placed")
assert(moved.shown,"returning pooled icon shown")
local swapped=essEntries[1].icon
essEntries[1].icon,essEntries[4].icon=essEntries[4].icon,swapped
swapped:ClearAllPoints()
L.Apply("ess")
CheckPoint(swapped,"TOPLEFT",essBar.frame,"TOPLEFT",126,0,"icon handed to another entry is re-placed")
-- same slot, new entry, same pooled icon, no pass in between
local last=essEntries[5]
last.icon:ClearAllPoints(); last.icon:Hide()
essEntries[5]={key="s77",icon=last.icon}
L.Apply("ess")
CheckPoint(last.icon,"TOPLEFT",essBar.frame,"TOPLEFT",168,0,"icon reused in place is re-placed")
assert(last.icon.shown,"icon reused in place is shown")
-- the same entry leaves and comes back with its pooled icon
local back=essEntries[5]
essEntries[5]=nil
L.Apply("ess")
back.icon:ClearAllPoints(); back.icon:Hide()
essEntries[5]=back
L.Apply("ess")
CheckPoint(back.icon,"TOPLEFT",essBar.frame,"TOPLEFT",168,0,"returning entry is re-placed")
assert(back.icon.shown,"returning entry is shown")
-- icons handed over or back always show their (new) entry's overlay
local handed={}
for _,call in ipairs(overlayLog) do if call[2]==true then handed[call[1]]=true end end
assert(handed[newcomer] and handed[essEntries[1]] and handed[essEntries[4]] and handed[back],"re-placed icons show their overlay")
-- maxIcons on a cooldown bar hides the rest, overlays included
Clear(overlayLog)
ess.maxIcons=3
L.Apply("ess")
assert(not essEntries[4].icon.shown and not essEntries[5].icon.shown and essBar.frame.w==3*40+2*2,"maxIcons hides extra icons")
assert(#overlayLog==2 and overlayLog[1][2]==false and overlayLog[2][2]==false
    and overlayLog[1][1]==essEntries[4] and overlayLog[2][1]==essEntries[5],"capped icons hide their overlays")
ess.maxIcons=0
L.Apply("ess")
assert(essEntries[5].icon.shown,"icons return when the cap lifts")
assert(#overlayLog==4 and overlayLog[3][2]==true and overlayLog[4][2]==true,"and so do their overlays")
-- the icon pool hides an icon behind the layout's back (release and bind
-- in one flush): Forget makes the next pass place and show it again,
-- overlay included
local pooled=essEntries[1].icon
pooled:ClearAllPoints(); pooled:Hide()
L.Forget(pooled)
Clear(overlayLog)
L.Apply("ess")
assert(pooled.shown and #pooled.points==1 and #overlayLog==1 and overlayLog[1][1]==essEntries[1] and overlayLog[1][2]==true,
    "a forgotten icon is placed and shown again")
Clear(overlayLog)

-- a scale change re-snaps every anchor, even through a single bar's pass
physicalHeight=1080
px=L.InvalidateScale()
L.Apply("ess")
CheckPoint(C.bars.uti.frame,"TOP",essBar.frame,"BOTTOM",0,-3*px,"gap re-snapped to 3 px")
local snappedY=floor(ESS_Y/px+.5)*px
assert(not Near(snappedY,ESS_Y) and Whole(snappedY),"the default offset is off-grid at this scale")
CheckPoint(essBar.frame,"TOP",UIParent,"CENTER",0,snappedY,"position re-snapped to whole pixels")
physicalHeight=768
L.InvalidateScale()
L.ApplyAll()
CheckPoint(C.bars.uti.frame,"TOP",essBar.frame,"BOTTOM",0,-2,"gap back at 1 px units")
CheckPoint(essBar.frame,"TOP",UIParent,"CENTER",0,ESS_Y,"position back at 1 px units")

-- strata diff
ess.strata=4
ResetCalls()
L.Apply("ess")
assert(essBar.frame.strata=="HIGH" and calls.SetFrameStrata==1,"strata write")
L.Apply("ess")
assert(calls.SetFrameStrata==1,"strata diffed")

------------------------------------------------------------------ attach sides, cycles, parents off
local c1,c2,c3,c4=C.views.c1,C.views.c2,C.views.c3,C.views.c4
for _,slot in ipairs({"c1","c2","c3","c4"}) do C.views[slot].on=true; Plan(slot,IconEntries(slot,1)) end
c1.anchor,c1.side,c1.gap=AnchorOf("ess"),4,3
assert(c1.anchor==2,"Essential is anchor entry 2")
Touch("c1")
L.ApplyAll()
CheckPoint(C.bars.c1.frame,"LEFT",essBar.frame,"RIGHT",3,0,"right of ess")
c1.side=3; Touch("c1")
L.Apply("c1")
CheckPoint(C.bars.c1.frame,"RIGHT",essBar.frame,"LEFT",-3,0,"left of ess")
-- c1 <-> c2 cycle: both free; c3 -> c1 attaches; c4 -> itself is free
assert(AnchorOf("c1")==8 and AnchorOf("c4")==11,"custom bars are anchor entries 8..13")
c1.anchor,c2.anchor,c3.anchor,c4.anchor=AnchorOf("c2"),AnchorOf("c1"),AnchorOf("c1"),AnchorOf("c4")
c2.x,c2.y=50,-40
for _,slot in ipairs({"c1","c2","c3","c4"}) do Touch(slot) end
local order={}
local apply=L.Apply
L.Apply=function(slot) order[#order+1]=slot; return apply(slot) end
L.ApplyAll()
L.Apply=apply
local position={}
for i,slot in ipairs(order) do position[slot]=i end
assert(position.ess<position.uti and position.uti<position.buf and position.buf<position.bar,"roots before children")
assert(position.c1<position.c3,"cycle member before its dependent")
assert(L.Parent("c1")==nil and L.Parent("c2")==nil,"cycle members are free")
CheckPoint(C.bars.c1.frame,"TOP",UIParent,"CENTER",0,0,"cycle member c1 free")
CheckPoint(C.bars.c2.frame,"TOP",UIParent,"CENTER",50,-40,"cycle member c2 free")
assert(L.Free("c1") and L.Free("c2") and L.Movable("c1"),"cycle members are placed by their own x/y")
assert(L.Parent("c3")=="c1","dependent of a cycle attaches")
CheckPoint(C.bars.c3.frame,"TOP",C.bars.c1.frame,"BOTTOM",0,-4,"c3 below c1")
CheckPoint(C.bars.c4.frame,"TOP",UIParent,"CENTER",0,0,"self anchor is free")
assert(not L.Free("c3") and L.Movable("c3"),"an attached bar moves by an offset, not by a position")
-- longer cycle through three bars
c1.anchor,c2.anchor,c3.anchor=AnchorOf("c2"),AnchorOf("c3"),AnchorOf("c1")
assert(L.Parent("c1")==nil and L.Parent("c2")==nil and L.Parent("c3")==nil,"three-bar cycle is free")
c1.anchor,c2.anchor,c3.anchor=AnchorOf("c2"),AnchorOf("c1"),AnchorOf("c1")
-- frame anchors are not bar parents
c4.anchor=PLAYER
assert(L.Parent("c4")==nil and L.FrameTarget("c4")=="player","player frame entry")
c4.anchor=TARGET
assert(L.Parent("c4")==nil and L.FrameTarget("c4")=="target","target frame entry")
c4.anchor=TARGET+1
assert(L.Parent("c4")==nil and L.FrameTarget("c4")==nil,"out-of-range anchor is free")
c4.anchor=AnchorOf("c4")
-- free bar growth edges
c4.grow=2; Touch("c4"); L.Apply("c4")
CheckPoint(C.bars.c4.frame,"BOTTOM",UIParent,"CENTER",0,0,"grow up anchors BOTTOM")
c4.vertical=true; Touch("c4"); L.Apply("c4")
CheckPoint(C.bars.c4.frame,"RIGHT",UIParent,"CENTER",0,0,"vertical grow left anchors RIGHT")
c4.grow=1; Touch("c4"); L.Apply("c4")
CheckPoint(C.bars.c4.frame,"LEFT",UIParent,"CENTER",0,0,"vertical grow right anchors LEFT")
-- Edit Mode drag preview: the bar moves as if x/y were the dragged values,
-- settings stay; the next pass writes the saved place again
assert(L.DragPlace("c4",25,-60),"free bars drag")
CheckPoint(C.bars.c4.frame,"LEFT",UIParent,"CENTER",25,-60,"drag preview of a free bar")
assert(c4.x==0 and c4.y==0,"a drag preview writes no setting")
L.Apply("c4")
CheckPoint(C.bars.c4.frame,"LEFT",UIParent,"CENTER",0,0,"the saved place comes back")
assert(L.DragPlace("c3",6,-7),"attached bars drag by an offset")
CheckPoint(C.bars.c3.frame,"TOP",C.bars.c1.frame,"BOTTOM",6,-11,"drag preview of an attached bar")
L.Apply("c3")
CheckPoint(C.bars.c3.frame,"TOP",C.bars.c1.frame,"BOTTOM",0,-4,"attached bar back at its offset")
assert(not L.DragPlace("c5",0,0),"a bar without a frame does not drag")
-- parent turned off: the child takes the off bar's place (an off root's
-- free spot); applying only the parent re-anchors the dependents
ess.on=false; Touch("ess")
C.plans.ess=nil
L.Apply("ess")
assert(not essBar.frame.shown and not essBar.shown,"off bar hides")
assert(anchorChanges==2,"hiding the Essential bar notifies MSUF")
CheckPoint(C.bars.uti.frame,"TOP",UIParent,"CENTER",ess.x,ess.y,"orphaned uti takes the Essential bar's place")
-- a stand-in is placed by the off bar's x/y: neither free nor draggable
assert(not L.Free("uti") and not L.Movable("uti") and not L.DragPlace("uti",1,1),"stand-in placement")
CheckPoint(C.bars.uti.frame,"TOP",UIParent,"CENTER",ess.x,ess.y,"a refused drag leaves the stand-in")
CheckPoint(C.bars.buf.frame,"TOP",C.bars.uti.frame,"BOTTOM",0,-4,"buf stays below uti")
uti.on=false; Touch("uti")
L.Apply("uti")
assert(anchorChanges==2,"other bars do not notify MSUF")
CheckPoint(C.bars.buf.frame,"TOP",UIParent,"CENTER",ess.x,ess.y,"with uti off too, buf skips it and takes the Essential bar's place")
CheckPoint(C.bars.bar.frame,"TOP",C.bars.buf.frame,"BOTTOM",0,-4,"bar stays below the free buf")
uti.on=true; Touch("uti")
L.Apply("uti")
ess.on=true; Touch("ess")
Plan("ess",essEntries)
L.Apply("ess")
assert(anchorChanges==3,"showing the Essential bar again notifies MSUF")
CheckPoint(C.bars.uti.frame,"TOP",essBar.frame,"BOTTOM",0,-2,"uti re-attached")
CheckPoint(C.bars.buf.frame,"TOP",C.bars.uti.frame,"BOTTOM",0,-4,"buf re-attached")
for _,slot in ipairs({"c1","c2","c3","c4"}) do C.views[slot].on=false; Touch(slot) end
L.ApplyAll()
assert(not C.bars.c1.frame.shown and not C.bars.c4.frame.shown,"custom bars off")
ResetCalls()
L.ApplyAll()
assert(Writes()==0,"repeat after chain edits wrote")
assert(anchorChanges==3,"no notification without an Essential show or hide")
-- kind switch hides cooldown-only content: cells of a custom bar that turned into a cooldown bar hide
c1.on,c1.kind,c1.anchor=true,2,1; Touch("c1")
Plan("c1",{Entry("player"),Entry("player")})
L.Apply("c1")
local cell=L.Cell("c1",1)
assert(cell.shown,"custom aura cell shown")
c1.kind=1; Touch("c1")
Plan("c1",IconEntries("c1",2))
L.Apply("c1")
assert(not cell.shown,"cells hide when the bar holds cooldowns")
c1.on=false; Touch("c1"); L.Apply("c1")

------------------------------------------------------------------ MSUF unit frame anchors
-- A bar on MSUF's player or target frame reads that frame's rectangle and
-- sits against UIParent's corner: the protected unit frame is never its
-- anchor. Probes stretched to the frame report moves; no polling.
local function UnitFrame(name,left,bottom,width,height,scale)
    local frame=CreateFrame("Frame",nil,UIParent)
    frame.rect={left,bottom,width,height}
    frame.scale=scale
    _G[name]=frame
    return frame
end
local function Probes(target)
    local list={}
    for _,frame in ipairs(frames) do
        if frame.scripts.OnSizeChanged then
            for _,p in ipairs(frame.points) do
                if p[2]==target then list[#list+1]=frame; break end
            end
        end
    end
    return list
end
-- Per side (Below, Above, Left, Right) and alignment (Center, Start, End):
-- the bar's own point, then the target's x edge and y edge it sits on.
-- A probe event, as the client sends one when the frame moved or resized.
local function Moved(frame) local p=Probes(frame)[1]; if p then p.scripts.OnSizeChanged(p,1,1) end end
local EDGES={
    {{"TOP","cx","bottom"},{"TOPLEFT","left","bottom"},{"TOPRIGHT","right","bottom"}},
    {{"BOTTOM","cx","top"},{"BOTTOMLEFT","left","top"},{"BOTTOMRIGHT","right","top"}},
    {{"RIGHT","left","cy"},{"TOPRIGHT","left","top"},{"BOTTOMRIGHT","left","bottom"}},
    {{"LEFT","right","cy"},{"TOPLEFT","right","top"},{"BOTTOMLEFT","right","bottom"}},
}
local GAP_SIGN={{0,-1},{0,1},{-1,0},{1,0}}
local EDGE_NAME={left="LEFT",right="RIGHT",cx="",top="TOP",bottom="BOTTOM",cy=""}
local function RelPoint(e) return EDGE_NAME[e[3]]..EDGE_NAME[e[2]] end

-- defaults: Defensives above the player frame flush right, Potions and
-- racials below it flush left
local def=C.views.def
assert(def.on and def.anchor==PLAYER and def.side==2 and def.align==3 and def.gap==44,"defensives default placement")
assert(ext.on and ext.anchor==PLAYER and ext.side==1 and ext.align==2 and ext.gap==22,"potions default placement")
-- in combat the bar follows the rectangle but no probe is created
combat=true
-- 80,160 200x40 at effective scale 1.5: UIParent units 120..420 x 240..300
local player=UnitFrame("MSUF_player",80,160,200,40,1.5)
Plan("def",IconEntries("def",2))
L.Apply("def")
local defBar=C.bars.def
assert(defBar.frame.w==66 and defBar.frame.h==29,"def size "..tostring(defBar.frame.w).."x"..tostring(defBar.frame.h))
assert(defBar.anchorFrame==nil,"no MSUF anchor frame for def")
CheckPoint(defBar.frame,"BOTTOMRIGHT",UIParent,"BOTTOMLEFT",420,344,"def above the player frame, right edges aligned")
assert(#Probes(player)==0,"no probe created in combat")
combat=false
L.Apply("def")
local probes=Probes(player)
assert(#probes==2,"two probes per watched frame, got "..#probes)
local seen={}
for _,probe in ipairs(probes) do
    assert(probe.parent==UIParent and #probe.points==2,"probe is a UIParent child with two points")
    local a,b=probe.points[1],probe.points[2]
    assert(a[1]=="BOTTOMLEFT" and a[2]==UIParent and a[3]=="BOTTOMLEFT" and a[4]==0 and a[5]==0,"probe starts at UIParent's corner")
    assert(b[1]=="TOPRIGHT" and b[2]==player and b[4]==0 and b[5]==0,"probe ends on the frame")
    seen[b[3]]=true
end
assert(seen.BOTTOMLEFT and seen.TOPRIGHT,"probes reach both frame corners")
L.Apply("ext")
CheckPoint(C.bars.ext.frame,"TOPLEFT",UIParent,"BOTTOMLEFT",120,218,"ext below the player frame, left edges aligned")
L.Apply("def")
assert(#Probes(player)==2,"a watched frame gets no more probes")
-- repeated passes: no widget calls, no frames, no garbage
L.ApplyAll()
local createdNow=created
ResetCalls()
L.ApplyAll()
L.Apply("def"); L.Apply("ext")
assert(Writes()==0 and created==createdNow,"repeat pass with frame anchors wrote "..Writes().." times")
collectgarbage("collect"); collectgarbage("stop")
before=collectgarbage("count")
for _=1,200 do L.Apply("def"); L.Apply("ext") end
grown=collectgarbage("count")-before
collectgarbage("restart")
assert(grown<1,"frame-anchored passes allocated "..grown.." KB")
-- the rectangle is read once per reported move, never per pass
ResetCalls()
for _=1,50 do L.Apply("def"); L.Apply("ext"); L.ApplyAll() end
assert((calls.GetRect or 0)==0,"a kept rectangle was read "..tostring(calls.GetRect).." times")
-- a move reaches the bars through the probes only
player.rect[1]=100
L.Apply("uti")
CheckPoint(defBar.frame,"BOTTOMRIGHT",UIParent,"BOTTOMLEFT",420,344,"no re-anchor without a probe event")
ResetCalls()
probes[1].scripts.OnSizeChanged(probes[1],1,1)
assert(L.dirty.def and L.dirty.ext,"FrameMoved requests the frame-anchored bars")
assert(not L.dirty.ess and not L.dirty.uti and not L.dirty.buf and not L.dirty.bar,"bars off the frames stay clean")
L.Flush()
assert(next(L.dirty)==nil,"flush clears the requests")
CheckPoint(defBar.frame,"BOTTOMRIGHT",UIParent,"BOTTOMLEFT",450,344,"def follows the moved frame")
CheckPoint(C.bars.ext.frame,"TOPLEFT",UIParent,"BOTTOMLEFT",150,218,"ext follows the moved frame")
assert(calls.GetRect==1,"one read per reported move, got "..tostring(calls.GetRect))
-- a resize through the other probe: any later pass re-anchors every bar
player.rect[1],player.rect[4]=80,60
probes[2].scripts.OnSizeChanged(probes[2],1,1)
L.Apply("ess")
CheckPoint(defBar.frame,"BOTTOMRIGHT",UIParent,"BOTTOMLEFT",420,374,"a frame move re-anchors on any pass")
L.Flush()
player.rect[4]=40
probes[1].scripts.OnSizeChanged(probes[1],1,1)
L.Flush()
CheckPoint(defBar.frame,"BOTTOMRIGHT",UIParent,"BOTTOMLEFT",420,344,"def back in place")

-- every side and alignment on the target frame: UIParent at scale .8 (1.25
-- UI units per pixel), frame at 1.2, so 1.5 UI units per frame unit
UIParent.scale=.8
px=L.InvalidateScale()
assert(Near(px,1.25),"px at UI scale .8")
local target=UnitFrame("MSUF_target",400,100,120,60,1.2)
local edge={left=600,right=780,cx=690,bottom=150,top=240,cy=195}
c1.on,c1.kind,c1.anchor,c1.gap,c1.x,c1.y=true,1,TARGET,5,30,-50
Plan("c1",IconEntries("c1",1))
for side=1,4 do
    for align=1,3 do
        c1.side,c1.align=side,align; Touch("c1")
        L.Apply("c1")
        local e=EDGES[side][align]
        -- x/y (30,-50) are the offset from the attach point.
        CheckPoint(C.bars.c1.frame,e[1],UIParent,"BOTTOMLEFT",edge[e[2]]+GAP_SIGN[side][1]*5+30,edge[e[3]]+GAP_SIGN[side][2]*5-50,
            "target frame side "..side.." align "..align)
    end
end
assert(#Probes(target)==2,"target frame watched")
c1.x,c1.y=0,0
-- off-grid rectangles snap to whole pixels before the gap is added
target.rect[1]=401; Moved(target)
c1.side,c1.align=1,1; Touch("c1"); L.Apply("c1")
CheckPoint(C.bars.c1.frame,"TOP",UIParent,"BOTTOMLEFT",691.25,145,"center 691.5 snaps to 553 px")
c1.side,c1.align=4,2; Touch("c1"); L.Apply("c1")
CheckPoint(C.bars.c1.frame,"TOPLEFT",UIParent,"BOTTOMLEFT",786.25,240,"right edge 781.5 snaps to 625 px")
target.rect[1]=400; Moved(target)
UIParent.scale=1
px=L.InvalidateScale()

-- bar to bar: the same sides and edge alignments against another bar
-- x/y of an attached bar are its offset from the attach point: zero here.
c2.on,c2.anchor,c2.gap,c2.x,c2.y=true,AnchorOf("ess"),5,0,0
Plan("c2",IconEntries("c2",1))
for side=1,4 do
    for align=1,3 do
        c2.side,c2.align=side,align; Touch("c2")
        L.Apply("c2")
        local e=EDGES[side][align]
        CheckPoint(C.bars.c2.frame,e[1],essBar.frame,RelPoint(e),GAP_SIGN[side][1]*5,GAP_SIGN[side][2]*5,
            "bar attach side "..side.." align "..align)
    end
end

-- missing, unreadable or forbidden frames: the bar keeps its own position
c1.side,c1.align=1,1; Touch("c1"); L.Apply("c1")
CheckPoint(C.bars.c1.frame,"TOP",UIParent,"BOTTOMLEFT",552,115,"target frame at UI scale 1")
c1.x,c1.y=30,-50
-- (each change is reported through the probes, as the client does)
local function Free(label) L.Apply("c1"); CheckPoint(C.bars.c1.frame,"TOP",UIParent,"CENTER",30,-50,label) end
for i=1,4 do
    local keep=target.rect[i]
    target.rect[i]=Secret(); Moved(target); Free("secret rectangle value "..i)
    target.rect[i]=keep
end
target.rect[3]=nil; Moved(target); Free("incomplete rectangle")
target.rect[3]=120; target.scale=Secret(); Moved(target); Free("secret frame scale")
target.scale=1.2; UIParent.scale=Secret(); Moved(target); Free("secret UIParent scale")
UIParent.scale=1; _G.MSUF_target=nil; Free("missing frame")
_G.MSUF_target="MSUF_target"; Free("frame global of the wrong type")
local forbidden=UnitFrame("MSUF_target",400,100,120,60,1.2)
forbidden.IsForbidden=function() return true end
Free("forbidden frame")
assert(#Probes(forbidden)==0,"a forbidden frame is never probed")
-- a frame that appears in combat is followed at once and probed after combat
c1.x,c1.y=0,0; Touch("c1")
combat=true
target=UnitFrame("MSUF_target",400,100,120,60,1.2)
L.Apply("c1")
CheckPoint(C.bars.c1.frame,"TOP",UIParent,"BOTTOMLEFT",552,115,"new frame followed in combat")
assert(#Probes(target)==0,"no probes for a new frame in combat")
combat=false
L.Apply("c1")
assert(#Probes(target)==2,"probes once combat ends")

-- MSUF follows the Essential bar: ess and every bar it hangs from stay off
-- MSUF's frames, or the unit frames and the bars would chase each other
local function Follows(flag,getter)
    MSUF_DB={general={anchorToCooldown=flag}}
    MSUF_GetSuiteCooldownAnchor=getter and function() end or nil
end
ess.anchor=PLAYER; Touch("ess")
Follows(true,true)
assert(L.FrameTarget("ess")==nil,"a followed Essential bar never sits on MSUF's frames")
assert(L.FrameTarget("def")=="player" and L.FrameTarget("ext")=="player","bars off the chain keep the player frame")
L.Apply("ess")
CheckPoint(essBar.frame,"TOP",UIParent,"CENTER",0,ESS_Y,"followed Essential bar stays free")
Follows(true,false)
assert(L.FrameTarget("ess")=="player","an MSUF without the getter does not follow our bars")
L.Apply("ess")
CheckPoint(essBar.frame,"TOP",UIParent,"BOTTOMLEFT",270+ess.x,238+ess.y,"Essential bar below the player frame, shifted by its x/y offset")
Follows(false,true)
assert(L.FrameTarget("ess")=="player","anchorToCooldown off: no follow")
Follows("yes",true)
assert(L.FrameTarget("ess")=="player","only a true flag follows")
MSUF_DB={general="broken"}
assert(L.FrameTarget("ess")=="player","malformed MSUF_DB ignored")
MSUF_DB=nil
assert(L.FrameTarget("ess")=="player","no MSUF_DB")
-- chain: ess below c1 below c2, c2 on the player frame
Follows(true,true)
ess.anchor,c1.anchor,c2.anchor=AnchorOf("c1"),AnchorOf("c2"),PLAYER
ess.x,ess.y,c2.x,c2.y=0,0,50,-40
c1.side,c1.align,c2.side,c2.align=1,1,1,1
for _,slot in ipairs({"ess","c1","c2"}) do Touch(slot) end
assert(L.Parent("ess")=="c1" and L.Parent("c1")=="c2" and L.Parent("c2")==nil,"chain parents")
assert(L.FrameTarget("c2")==nil,"a bar the Essential bar hangs from stays off MSUF's frames")
-- the walk starts at the Essential bar, not at a bar hanging below it
uti.anchor=1
assert(L.FrameTarget("c2")==nil and L.FrameTarget("def")=="player","chain walk starts at ess")
uti.anchor=AnchorOf("ess")
-- a bar hanging below the Essential bar breaks nothing; a switched-off link ends the chain
c3.on,c3.anchor=true,AnchorOf("ess")
assert(L.FrameTarget("c2")==nil,"a dependent of ess does not change the chain")
c3.on,c3.anchor=false,AnchorOf("c1")
c1.on=false
assert(L.Parent("ess")=="c2" and L.FrameTarget("c2")==nil,"a switched-off link passes the chain on to its own target")
c1.on=true
L.ApplyAll()
CheckPoint(C.bars.c2.frame,"TOP",UIParent,"CENTER",50,-40,"chain root free while MSUF follows")
CheckPoint(C.bars.c1.frame,"TOP",C.bars.c2.frame,"BOTTOM",0,-5,"c1 below c2")
CheckPoint(essBar.frame,"TOP",C.bars.c1.frame,"BOTTOM",0,-2,"ess below c1")
Follows(true,false)
assert(L.FrameTarget("c2")=="player","without the getter the chain root sits on the player frame")
L.Apply("c2")
-- its x/y (50,-40) now count from the frame's bottom center, 5 units below
CheckPoint(C.bars.c2.frame,"TOP",UIParent,"BOTTOMLEFT",320,195,"chain root below the player frame")
MSUF_DB,MSUF_GetSuiteCooldownAnchor=nil,nil
ess.anchor,ess.x,ess.y,c1.on,c2.on=1,0,ESS_Y,false,false
for _,slot in ipairs({"ess","c1","c2"}) do Touch(slot) end
L.ApplyAll()
CheckPoint(essBar.frame,"TOP",UIParent,"CENTER",0,ESS_Y,"ess free again")
CheckPoint(C.bars.uti.frame,"TOP",essBar.frame,"BOTTOM",0,-2,"stack intact")
assert(anchorChanges==3,"frame anchors never hid or showed the Essential bar")
ResetCalls()
L.ApplyAll()
assert(Writes()==0,"repeat after frame anchors wrote "..Writes().." times")

-- request/flush
L.Request("ess")
assert(L.dirty.ess,"request marks dirty")
L.Flush()
assert(not L.dirty.ess,"flush clears dirty")
L.HideAll()
for _,slot in ipairs({"ess","uti","def","ext","buf","bar"}) do assert(not C.bars[slot].frame.shown,"HideAll "..slot) end
assert(anchorChanges==4,"HideAll notifies MSUF once")
L.ApplyAll()
assert(anchorChanges==5,"ApplyAll after HideAll notifies MSUF once")

------------------------------------------------------------------ visibility
-- Sources: "Always" follows a few rare events and costs no state driver,
-- "Hidden" is static, every other rule is a macro condition on a driver
-- shared by all bars with that condition. The effect is alpha and mouse.
local function Expr(vis,mounted,vehicle) return V.Expression({vis=vis,hideMounted=mounted,hideVehicle=vehicle}) end
assert(Expr(1,false,true)=="[petbattle] hide; [vehicleui][overridebar] hide; show","always + vehicle")
assert(Expr(1,false,false)=="[petbattle] hide; show","always")
assert(Expr(2,true,true)=="[petbattle] hide; [vehicleui][overridebar] hide; [mounted] hide; [combat] show; hide","combat + mounted + vehicle")
assert(Expr(3,false,false)=="[petbattle] hide; [combat][@target,exists] show; hide","combat or target")
assert(Expr(4,true,true)=="hide","hidden")
assert(Expr(9,false,false)=="[petbattle] hide; show","unknown vis falls back to always")
assert(V.Binding({vis=1,hideVehicle=true})==V.EVENTS and V.Binding({vis=1})==V.EVENTS and V.Binding({vis=9})==V.EVENTS,
    "always without the mount rule follows events")
assert(V.Binding({vis=1,hideMounted=true,hideVehicle=true})==Expr(1,true,true),"the mount rule needs a driver")
assert(V.Binding({vis=4,hideMounted=true})==V.HIDDEN,"hidden is static")
assert(V.Binding({vis=2})==Expr(2,false,false) and V.Binding({vis=3,hideVehicle=true})==Expr(3,false,true),"combat and target rules")
do
    local ON={"ess","uti","def","ext","buf","bar"}
    local function Listener()
        for _,frame in ipairs(frames) do if frame.scripts.OnEvent then return frame end end
    end
    local function Fire(event,unit) local frame=Listener(); frame.scripts.OnEvent(frame,event,unit) end
    local function AllHidden(hidden,label)
        for _,slot in ipairs(ON) do
            local bar=C.bars[slot]
            assert(bar.hidden==hidden and bar.frame.alpha==(hidden and 0 or 1),label..": "..slot)
        end
    end

    -- the default setup: six "Always" bars, no state driver, a few rare events
    assert(Listener()==nil,"no event frame before the first rule")
    local registeredBefore=registered
    Clear(mouseLog)
    V.ApplyAll()
    assert(registered==registeredBefore and V.DriverCount()==0 and next(V.drivers)==nil,"the default setup registers no state driver")
    local listener=Listener()
    assert(listener and listener.parent==nil,"one plain event frame")
    local ev=listener.events
    assert(ev.PET_BATTLE_OPENING_START and ev.PET_BATTLE_CLOSE,"pet battle events")
    assert(ev.UNIT_ENTERED_VEHICLE=="player" and ev.UNIT_EXITED_VEHICLE=="player","vehicle events for the player only")
    assert(ev.UPDATE_OVERRIDE_ACTIONBAR and ev.UPDATE_VEHICLE_ACTIONBAR,"override and vehicle bar events")
    AllHidden(false,"always shown")
    assert(#mouseLog==0,"no mouse edge while nothing hides")
    -- pet battle: every "Always" bar hides and gives the mouse back; the same
    -- edge twice does nothing
    Fire("PET_BATTLE_OPENING_START")
    AllHidden(true,"pet battle")
    for _,slot in ipairs(ON) do
        assert(Logged(mouseLog,slot.."-") and Logged(auraMouseLog,slot.."-"),"icons and auras lose the mouse: "..slot)
    end
    local edges=#mouseLog
    Fire("PET_BATTLE_OPENING_START")
    assert(#mouseLog==edges,"no repeated mouse edge")
    Fire("PET_BATTLE_CLOSE")
    AllHidden(false,"after the pet battle")
    assert(Logged(mouseLog,"ess+") and #mouseLog==edges+6,"the mouse comes back once per bar")
    -- vehicles and override bars, the player's only
    vehicleUI=true
    Fire("UNIT_ENTERED_VEHICLE","party1")
    AllHidden(false,"another unit's vehicle changes nothing")
    Fire("UNIT_ENTERED_VEHICLE","player")
    AllHidden(true,"a vehicle interface hides")
    vehicleUI=false
    Fire("UNIT_EXITED_VEHICLE","player")
    AllHidden(false,"vehicle left")
    overrideBar=true; Fire("UPDATE_OVERRIDE_ACTIONBAR")
    AllHidden(true,"an override bar hides")
    overrideBar=false; Fire("UPDATE_OVERRIDE_ACTIONBAR")
    AllHidden(false,"override bar gone")
    -- a bar kept in vehicles
    uti.hideVehicle=false; V.Apply("uti")
    vehicleUI=true; Fire("UNIT_ENTERED_VEHICLE","player")
    assert(essBar.hidden and not C.bars.uti.hidden,"only bars with the vehicle rule hide")
    vehicleUI=false; Fire("UNIT_EXITED_VEHICLE","player")
    uti.hideVehicle=true; V.Apply("uti")
    -- unchanged events, paints and passes: no widget call, no garbage
    ResetCalls(); Clear(mouseLog)
    collectgarbage("collect"); collectgarbage("stop")
    before=collectgarbage("count")
    for _=1,200 do
        Fire("UPDATE_OVERRIDE_ACTIONBAR"); Fire("UNIT_EXITED_VEHICLE","player"); Fire("PET_BATTLE_CLOSE")
        V.CombatChanged(); V.ApplyAll()
    end
    grown=collectgarbage("count")-before
    collectgarbage("restart")
    assert(grown<1,"steady visibility allocated "..grown.." KB")
    assert(Writes()==0 and #mouseLog==0,"steady visibility wrote "..Writes().." times")
    -- vehicle events exist only while a bar hides in vehicles; a vehicle
    -- entered while nobody listened is read when listening starts
    for _,slot in ipairs(ON) do C.views[slot].hideVehicle=false end
    V.ApplyAll()
    assert(ev.PET_BATTLE_CLOSE and not ev.UNIT_ENTERED_VEHICLE and not ev.UPDATE_OVERRIDE_ACTIONBAR,"vehicle events follow the vehicle rule")
    vehicleUI=true
    V.ApplyAll()
    AllHidden(false,"no vehicle rule, no vehicle hiding")
    for _,slot in ipairs(ON) do C.views[slot].hideVehicle=true end
    V.ApplyAll()
    assert(ev.UNIT_ENTERED_VEHICLE=="player","vehicle events back")
    AllHidden(true,"the vehicle is read when listening starts")
    vehicleUI=false; Fire("UNIT_EXITED_VEHICLE","player")
    AllHidden(false,"out of the vehicle")

    -- shared drivers: bars with the same condition share one driver frame
    Clear(mouseLog)
    ess.vis,ess.alpha,ess.oocAlpha=2,80,50
    uti.vis=2
    registeredBefore=registered
    V.ApplyAll()
    assert(V.DriverCount()==1 and registered==registeredBefore+1,"two combat bars, one driver")
    local combatDriver=V.drivers[V.Expression(ess)]
    assert(combatDriver and combatDriver.parent==nil and combatDriver~=essBar.frame and #combatDriver.slots==2,"shared plain driver frame")
    assert(drivers[combatDriver].msufvis==V.Expression(ess),"driver registered with the bars' condition")
    assert(essBar.hidden==true and essBar.frame.alpha==0 and C.bars.uti.hidden==true,"out of combat hidden by the combat rule")
    assert(Logged(mouseLog,"ess-") and Logged(mouseLog,"uti-"),"hidden bars give the mouse back")
    assert(C.bars.def.hidden==false and C.bars.def.frame.alpha==1,"always-shown bar at full opacity")
    assert(ev.PET_BATTLE_CLOSE,"the other bars still follow events")
    registeredBefore=registered
    ResetCalls()
    V.ApplyAll()
    assert(registered==registeredBefore and Writes()==0,"unchanged visibility re-registers or writes")
    -- combat start: opacity switches first, the driver flips a frame later
    C.state.inCombat=true
    cond.combat=true
    V.CombatChanged()
    assert(essBar.frame.alpha==0,"driver has not flipped yet")
    Tick()
    assert(essBar.hidden==false and Near(essBar.frame.alpha,.8) and C.bars.uti.hidden==false,"combat shows every bar on the driver")
    C.state.inCombat=false
    cond.combat=false
    V.CombatChanged(); Tick()
    assert(essBar.hidden==true and essBar.frame.alpha==0 and C.bars.uti.hidden==true,"combat end hides again")
    -- opacity 0 counts as hidden for tooltips and the mouse
    def.oocAlpha=0; Clear(mouseLog)
    V.Apply("def")
    assert(C.bars.def.hidden==true and C.bars.def.frame.alpha==0 and Logged(mouseLog,"def-"),"a transparent bar takes no mouse")
    def.oocAlpha=100; V.Apply("def")
    assert(C.bars.def.hidden==false and Logged(mouseLog,"def+"),"mouse back with opacity")
    -- another condition gets its own driver; the mount rule turns "Always"
    -- into a driver too
    buf.vis,buf.hideMounted=3,true
    def.hideMounted=true
    V.ApplyAll()
    assert(V.DriverCount()==3,"three conditions, three drivers, got "..V.DriverCount())
    assert(C.bars.buf.hidden,"no combat, no target: hidden")
    assert(not C.bars.def.hidden,"always with the mount rule: shown")
    cond.target=true; Tick()
    assert(not C.bars.buf.hidden,"target shows")
    cond.mounted=true; Tick()
    assert(C.bars.buf.hidden and C.bars.def.hidden,"mounted hides before the target rule")
    cond.mounted=false; cond.vehicleui=true; Tick()
    assert(C.bars.buf.hidden and C.bars.def.hidden,"vehicle hides")
    cond.vehicleui=false; cond.petbattle=true; Tick()
    assert(C.bars.buf.hidden and C.bars.def.hidden and C.bars.uti.hidden,"pet battle hides every driven bar")
    cond.petbattle=false; cond.target=false; Tick()
    -- leaving a shared driver keeps it; the last bar out unregisters it
    local unregisteredBefore=unregistered
    uti.vis=1
    V.Apply("uti")
    assert(unregistered==unregisteredBefore and #combatDriver.slots==1 and drivers[combatDriver].msufvis,"a shared driver stays while a bar uses it")
    assert(C.bars.uti.hidden==false and V.expr.uti==V.EVENTS,"back on events: shown")
    ess.vis=1
    V.Apply("ess")
    assert(unregistered==unregisteredBefore+1 and drivers[combatDriver].msufvis==nil and V.DriverCount()==2,"the last bar out unregisters")
    -- hidden is static: no driver
    local count=V.DriverCount()
    registeredBefore=registered
    uti.vis,uti.alpha=4,70
    V.Apply("uti")
    assert(C.bars.uti.hidden and C.bars.uti.frame.alpha==0 and registered==registeredBefore and V.DriverCount()==count,"hidden bar, no driver")
    -- preview suspends every rule at plain bar opacity
    C.state.preview=true
    V.ApplyAll()
    assert(not C.bars.uti.hidden and Near(C.bars.uti.frame.alpha,.7),"preview shows hidden bars at bar opacity")
    assert(not C.bars.buf.hidden and Near(essBar.frame.alpha,.8),"preview ignores rules and the out-of-combat opacity")
    C.state.preview=false
    V.ApplyAll()
    assert(C.bars.uti.hidden and C.bars.uti.frame.alpha==0,"leaving preview restores the rules")
    -- combat parks driver (un)registration; event and static sources switch at once
    combat=true
    C.state.inCombat=true
    ess.vis=2
    V.Apply("ess")
    assert(V.pending.ess and V.HasPending(),"combat parks the registration")
    assert(V.expr.ess==V.EVENTS and not essBar.hidden,"the bar keeps its old source meanwhile")
    uti.vis=1
    V.Apply("uti")
    assert(not V.pending.uti and not C.bars.uti.hidden,"hidden to always needs no driver: at once")
    V.FlushPending()
    assert(V.pending.ess,"FlushPending waits for combat to end")
    combat=false
    C.state.inCombat=false
    V.FlushPending()
    assert(not V.pending.ess and not V.HasPending(),"regen applies the parked source")
    assert(drivers[combatDriver].msufvis==V.Expression(ess) and essBar.hidden,"re-registered driver reports at once")
    ess.vis=1; V.Apply("ess")
    -- a driver that reported before its bar existed still paints the new bar
    local c5=C.views.c5
    c5.on,c5.vis=true,2
    assert(C.bars.c5==nil,"c5 has no bar yet")
    V.Apply("c5")
    Plan("c5",IconEntries("c5",1))
    L.Apply("c5")
    assert(C.bars.c5.hidden==true and C.bars.c5.frame.alpha==0,"new bar painted from the driver state")
    c5.on=false
    unregisteredBefore=unregistered
    L.Apply("c5"); V.Apply("c5")
    assert(V.expr.c5==nil and unregistered==unregisteredBefore+1,"c5 released its driver")
    -- a bar turned off leaves its source
    ext.on=false
    V.Apply("ext")
    assert(V.expr.ext==nil,"off bar has no source")
    ext.on=true
    V.Apply("ext")
    assert(V.expr.ext==V.EVENTS and C.bars.ext.hidden==false,"back on events")
    -- release: drivers unregistered, events gone, paint forgotten
    V.ReleaseAll()
    assert(V.DriverCount()==0,"release unregisters drivers")
    for _,set in pairs(drivers) do assert(next(set)==nil,"driver left registered") end
    assert(next(ev)==nil,"release removes the events")
    for _,slot in ipairs(ON) do assert(C.bars[slot].hidden==nil,"release forgets the paint of "..slot) end
    M.active=false
    V.FlushPending()
    V.ApplyAll()
    assert(V.DriverCount()==0 and next(ev)==nil,"inactive module registers nothing")
    M.active=true
    for _,slot in ipairs(ON) do
        local view=C.views[slot]
        view.vis,view.hideMounted,view.alpha,view.oocAlpha=1,false,100,100
    end
    V.ApplyAll()
    AllHidden(false,"defaults again")
    assert(V.DriverCount()==0 and ev.PET_BATTLE_CLOSE,"defaults: events, no driver")
end

------------------------------------------------------------------ native: mode and takeover
local ctxLog={}
local ctx={properties={},cvars={}}
function ctx:Alpha(frame,value)
    ctxLog[#ctxLog+1]="alpha"
    if not self.properties[frame] then self.properties[frame]={before=frame:GetAlpha()} end
    frame:SetAlpha(value)
    self.properties[frame].applied=frame:GetAlpha()
end
function ctx:RestoreProperty(frame,setter)
    assert(setter=="SetAlpha")
    ctxLog[#ctxLog+1]="restore"
    local record=self.properties[frame]
    if record then
        if frame:GetAlpha()==record.applied then frame:SetAlpha(record.before) end
        self.properties[frame]=nil
    end
end
function ctx:CVar(key,value) ctxLog[#ctxLog+1]="cvar:"..key.."="..value; self.cvars[key]=value; return true end
M.context=ctx

local function Viewer(name,cx,cy,width,height,scale)
    local viewer=CreateFrame("Frame",nil,UIParent)
    viewer.cx,viewer.cy,viewer.width,viewer.height,viewer.scale=cx,cy,width,height,scale
    viewer.iconLimit,viewer.iconPadding,viewer.iconScale,viewer.isHorizontal=8,5,1,true
    viewer.OnAcquireItemFrame=function(_,_) end
    local item=CreateFrame("Frame",nil,viewer); item.layoutIndex=1
    local placeholder=CreateFrame("Frame",nil,viewer); placeholder.layoutIndex=2; placeholder:Hide()
    local released=CreateFrame("Frame",nil,viewer)
    local selection=CreateFrame("Frame",nil,viewer)
    viewer.children={item,placeholder,released,selection}
    viewer.item,viewer.selection,viewer.released=item,selection,released
    _G[name]=viewer
    return viewer
end
local essential=Viewer("EssentialCooldownViewer",640,240,400,100,1.5)
local utility=Viewer("UtilityCooldownViewer",960,300,300,30,1)
local buffIcon=Viewer("BuffIconCooldownViewer",960,500,200,40,1)
local buffBar=Viewer("BuffBarCooldownViewer",1400,600,220,90,1)
utility:Hide()
buffIcon.isHorizontal=false
buffIcon.iconScale=2.5

-- mode and promotion
config.blizzard=1
assert(N.Mode()==1,"mode 1 by default")
MSUF_DB={general={anchorToCooldown=true}}
local mode,reason=N.Mode()
assert(mode==2 and type(reason)=="string" and reason~="","MSUF anchoring promotes mode 1")
MSUF_DB={general="broken"}
assert(N.Mode()==1,"malformed MSUF_DB ignored")
MSUF_DB={general={anchorToCooldown="yes"}}
assert(N.Mode()==1,"only a true flag promotes")
-- an MSUF that follows our Essential bar needs no Blizzard bars
MSUF_DB={general={anchorToCooldown=true}}
MSUF_GetSuiteCooldownAnchor=function() end
mode,reason=N.Mode()
assert(mode==1 and reason==nil,"MSUF following our bars keeps mode 1")
MSUF_GetSuiteCooldownAnchor=nil
MSUF_DB=nil
config.blizzard=2
mode,reason=N.Mode()
assert(mode==2 and reason==nil,"chosen mode 2 has no promotion reason")

-- capture (before the CVar is touched)
config.blizzard=1
local captured=N.Capture()
assert(captured and captured.captured==true,"capture returns values")
local K=CDM.KEYS
-- only the Essential position, counted from the screen center (960,540):
-- center (640,240) and 400x100 at scale 1.5 put the top edge at
-- (240+50)*1.5 = 435, 105 below the center
local function OnlyEssential(values,label)
    local count=0
    for key in pairs(values) do
        count=count+1
        assert(key=="captured" or key==K.ess.x or key==K.ess.y,label..": capture wrote "..key)
    end
    assert(count==3,label..": expected ess x/y plus captured")
end
OnlyEssential(captured,"shown viewer")
assert(captured[K.ess.x]==0 and captured[K.ess.y]==-105,"essential top edge "..tostring(captured[K.ess.x])..","..tostring(captured[K.ess.y]))
-- the bar's growth edge picks the captured point
config[K.ess.grow]=2
captured=N.Capture()
assert(captured[K.ess.x]==0 and captured[K.ess.y]==-255,"bottom edge when growing up: "..tostring(captured[K.ess.y]))
config[K.ess.grow]=1
config[K.ess.vertical]=true
captured=N.Capture()
assert(captured[K.ess.x]==-300 and captured[K.ess.y]==-180,"left edge of a vertical bar: "..tostring(captured[K.ess.x]))
config[K.ess.vertical]=false
-- unreadable, hidden or missing viewer: top edge where the default puts it
-- (222 units below the screen center, under MSUF's player castbar)
essential.cx=Secret()
captured=N.Capture()
OnlyEssential(captured,"secret viewer")
assert(captured.captured==true and captured[K.ess.x]==0 and captured[K.ess.y]==ESS_Y,"secret geometry falls back: "..tostring(captured[K.ess.y]))
essential.cx=640
essential.shown=false
captured=N.Capture()
assert(captured and captured[K.ess.x]==0 and captured[K.ess.y]==ESS_Y,"hidden viewer falls back")
essential.shown=true
_G.EssentialCooldownViewer=nil
captured=N.Capture()
assert(captured and captured[K.ess.y]==ESS_Y,"missing viewer falls back")
_G.EssentialCooldownViewer=essential
-- unreadable UIParent metrics or combat: nothing
UIParent.height=Secret()
assert(N.Capture()==nil,"secret UIParent metrics -> nil")
UIParent.height=1080
combat=true
assert(N.Capture()==nil,"no capture in combat")
combat=false

-- mode 1: CVar only
ctxLog={}
N.Apply()
assert(#ctxLog==1 and ctxLog[1]=="cvar:cooldownViewerEnabled=0" and N.Applied()==1,"mode 1 turns the CVar off")
assert(#hooks==0,"mode 1 installs no hooks")
N.Apply()
assert(#ctxLog==1,"unchanged mode does nothing")
-- mode 2: alpha 0 through the context, hooks, CVar restored, item mouse off
config.blizzard=2
ResetCalls()
N.Apply()
assert(N.Applied()==2 and restoredCVars[#restoredCVars]=="cooldownManager:cooldownViewerEnabled","leaving mode 1 restores the CVar")
for _,viewer in ipairs({essential,utility,buffIcon,buffBar}) do
    assert(viewer.alpha==0,"viewer alpha 0")
    assert(not viewer.item.mouse and not viewer.children[2].mouse,"acquired items lose the mouse")
    assert(viewer.selection.mouse and viewer.released.mouse,"selection and released frames untouched")
end
assert(#hooks==8,"two hooks per viewer")
ResetCalls()
essential:SetAlpha(1)
assert(essential.alpha==0 and calls.SetAlpha==2,"alpha hook re-zeroes once (recursion guard)")
essential:SetAlpha(Secret())
assert(essential.alpha==0,"secret alpha re-zeroed")
local fresh=CreateFrame("Frame",nil,essential)
essential:OnAcquireItemFrame(fresh)
assert(fresh.mouse==false,"newly acquired item loses the mouse")
N.Apply()
assert(#hooks==8,"hooks installed once")
-- release restores alpha and leaves the hooks inert; the silenced items
-- get Blizzard's own state back: clicks off, motion as the viewer's
-- tooltip setting says (off when it cannot be read)
essential.tooltipsShown,utility.tooltipsShown,buffIcon.tooltipsShown=true,false,Secret()
N.Release()
assert(essential.item.click==false and essential.item.motion==true and fresh.click==false and fresh.motion==true,
    "Blizzard's tooltips work again on its items")
assert(essential.children[2].click==false and essential.children[2].motion==true,"hidden acquired items too")
assert(utility.item.motion==false and buffIcon.item.motion==false and buffBar.item.motion==false,
    "no motion where the viewer shows no tooltips or its setting is unreadable")
assert(essential.selection.click==nil and essential.released.click==nil,"frames never silenced stay untouched")
ResetCalls()
N.Release()
assert((calls.SetMouseMotionEnabled or 0)==0 and (calls.SetMouseClickEnabled or 0)==0,"items are restored once")
assert(essential.alpha==1 and buffBar.alpha==1,"release restores viewer alpha")
essential:SetAlpha(.7)
assert(essential.alpha==.7,"inert alpha hook")
local late=CreateFrame("Frame",nil,essential)
essential:OnAcquireItemFrame(late)
assert(late.mouse==true,"inert acquire hook")
assert(N.Applied()==nil,"nothing applied after release")
-- mode 1 release goes through the recorded CVar
config.blizzard=1
N.Apply()
local restores=#restoredCVars
N.Release()
assert(#restoredCVars==restores+1,"mode 1 release restores the CVar")
-- promotion: mode 1 setting behaves like mode 2
MSUF_DB={general={anchorToCooldown=true}}
ctxLog={}
N.Apply()
assert(N.Applied()==2 and essential.alpha==0,"promoted takeover keeps viewers running invisibly")
for _,entry in ipairs(ctxLog) do assert(entry:sub(1,4)~="cvar","promoted mode never touches the CVar") end
-- switching to mode 1 while applied restores alpha before the CVar write
assert(essential.item.mouse==false,"promoted takeover silences the items again")
essential.item.motion=nil
MSUF_DB=nil
ctxLog={}
N.Apply()
assert(essential.item.motion==true,"2 -> 1 restores the items")
assert(essential.alpha==.7 and ctxLog[#ctxLog]=="cvar:cooldownViewerEnabled=0","2 -> 1 restores alpha, then CVar")
N.Release()
combat=true
local queuedBefore=#queued
N.Apply()
assert(#queued==queuedBefore+1 and N.Applied()==nil,"combat queues the takeover")
combat=false

-- MSUF anchor export
assert(N.AnchorFrame("EssentialCooldownViewer")==essBar.anchorFrame,"essential anchor")
assert(N.AnchorFrame("UtilityCooldownViewer")==C.bars.uti.anchorFrame,"utility anchor")
assert(N.AnchorFrame("BuffIconCooldownViewer")==C.bars.buf.anchorFrame,"buff icon anchor")
assert(N.AnchorFrame("BuffBarCooldownViewer")==nil and N.AnchorFrame(nil)==nil and N.AnchorFrame(Secret())==nil,"only three names")
ess.on=false; Touch("ess"); C.plans.ess=nil; L.Apply("ess")
assert(N.AnchorFrame("EssentialCooldownViewer")==nil,"hidden bar exports nothing")
ess.on=true; Touch("ess"); Plan("ess",essEntries); L.Apply("ess")
M.active=false
assert(N.AnchorFrame("EssentialCooldownViewer")==nil,"inactive module exports nothing")
M.active=true

------------------------------------------------------------------ riding Blizzard's invisible Essential bar
-- MSUF without the suite getter sits on Blizzard's Essential bar, which
-- keeps running invisibly (promoted mode 2): our Essential bar rides it,
-- growth edge on growth edge, x/y an offset from it.
do
    MSUF_DB={general={anchorToCooldown=true}}
    MSUF_GetSuiteCooldownAnchor=nil
    N.Apply()
    assert(N.Applied()==2 and N.FollowViewer() and L.FollowsViewer("ess") and not L.FollowsViewer("uti"),"riding mode")
    -- 400,190 400x100 at scale 1.5: UIParent units 600..1200 x 285..435
    essential.rect={400,190,400,100}
    ess.x,ess.y=10,-5; Touch("ess")
    L.Apply("ess")
    CheckPoint(essBar.frame,"TOP",UIParent,"BOTTOMLEFT",910,430,"top edge centered on Blizzard's bar, shifted by x/y")
    assert(#Probes(essential)==2,"Blizzard's bar is watched by two probes")
    assert(not L.Free("ess") and L.Movable("ess"),"a riding bar moves by an offset")
    assert(L.DragPlace("ess",0,0))
    CheckPoint(essBar.frame,"TOP",UIParent,"BOTTOMLEFT",900,435,"drag preview relative to Blizzard's bar")
    L.Apply("ess")
    CheckPoint(essBar.frame,"TOP",UIParent,"BOTTOMLEFT",910,430,"saved offset back")
    CheckPoint(C.bars.uti.frame,"TOP",essBar.frame,"BOTTOM",0,-2,"the stack hangs below as usual")
    -- Blizzard's bar moves: the riding bar is requested, its dependents follow by anchor
    essential.rect[1]=420
    Moved(essential)
    assert(L.dirty.ess and not L.dirty.uti,"a move of Blizzard's bar requests the riding bar")
    L.Flush()
    CheckPoint(essBar.frame,"TOP",UIParent,"BOTTOMLEFT",940,430,"the riding bar follows")
    -- Essential off: Utility takes its placement, riding included
    ess.on=false; Touch("ess"); C.plans.ess=nil
    L.Apply("ess")
    CheckPoint(C.bars.uti.frame,"TOP",UIParent,"BOTTOMLEFT",940,430,"the stand-in rides Blizzard's bar with the Essential offset")
    essential.rect[1]=400
    Moved(essential)
    assert(L.dirty.uti,"a move of Blizzard's bar requests the stand-in")
    L.Flush()
    CheckPoint(C.bars.uti.frame,"TOP",UIParent,"BOTTOMLEFT",910,430,"the stand-in follows")
    ess.on=true; Touch("ess"); Plan("ess",essEntries)
    L.Apply("ess")
    CheckPoint(essBar.frame,"TOP",UIParent,"BOTTOMLEFT",910,430,"Essential back on Blizzard's bar")
    CheckPoint(C.bars.uti.frame,"TOP",essBar.frame,"BOTTOM",0,-2,"Utility back below it")
    -- unchanged passes read nothing and write nothing
    ResetCalls()
    for _=1,20 do L.ApplyAll(); L.Apply("ess") end
    assert(Writes()==0 and (calls.GetRect or 0)==0,"steady riding passes wrote "..Writes().." times")
    -- the ride ends (Blizzard's bars off): any pass re-anchors, even without
    -- a change to the Essential bar
    MSUF_DB=nil
    N.Apply()
    assert(not N.FollowViewer(),"riding over")
    L.Apply("bar")
    CheckPoint(essBar.frame,"TOP",UIParent,"CENTER",10,-5,"free again without an Essential change")
    N.Release()
    ess.x,ess.y=0,ESS_Y; Touch("ess"); L.Apply("ess")
    CheckPoint(essBar.frame,"TOP",UIParent,"CENTER",0,ESS_Y,"default place")
end

------------------------------------------------------------------ options canvas (Preview.lua)
-- One reused holder per parent, laid out with the live math; a repaint of
-- an unchanged bar (every settings tick repaints the page) writes nothing.
do
    S.ResolveTexture=function(value,fallback) return value or fallback end
    S.ClassRGB=function() return .2,.4,.6 end
    S.SetFont=function(fontString,font) fontString:SetFont(font) end
    S.CreateTexture=function(parent) return CreateFrame("Texture",nil,parent) end
    S.CreateFontString=function(parent) return CreateFrame("FontString",nil,parent) end
    UnitClass=function() return "Mage","MAGE" end
    C.spells={e={}}
    C.Catalog={order={},records={},RecordTexture=function() end}
    local keys={bar={"a1","a2"},ess={"s1","s2","s3"}}
    C.Resolve={
        Keys=function(slot,out)
            for i=#out,1,-1 do out[i]=nil end
            local list=keys[slot] or {}
            for i=1,#list do out[i]=list[i] end
            return out
        end,
        Describe=function(key,d) d.texture,d.name=key=="a2" and 502 or 501,key;return d end,
    }
    C.Icons.CreateStandalone=function(parent) return CreateFrame("Frame",nil,parent) end
    C.Icons.StyleIcon=function(icon,view) icon.styleGen,icon.styleView=view.styleGen,view;icon:SetSize(1,1) end
    C.Icons.SetTexture=function(icon,texture) if icon.lastTex~=texture then icon.lastTex=texture;icon:SetTexture(texture) end end
    local stage=CreateFrame("Frame",nil,UIParent)
    local canvas=Pv.Render(stage,"bar",400,200)
    assert(canvas and canvas.parent==stage and #canvas.rows==2,"buff bars draw as rows")
    local row=canvas.rows[2]
    assert(row.shown and row.name.text=="a2" and row.icon.texture==502 and row.w==220 and row.h==20,"row look")
    CheckPoint(row,"TOPLEFT",canvas,"TOPLEFT",0,-22,"second row below the first")
    assert(canvas.w==220 and canvas.h==42 and canvas.scale==1,"canvas footprint")
    ResetCalls()
    Pv.Render(stage,"bar",400,200)
    assert(Writes()==0,"an unchanged repaint of rows wrote "..Writes().." times")
    -- a look change restyles every row once
    C.views.bar.barTexture="Interface\\Other"
    ResetCalls()
    Pv.Render(stage,"bar",400,200)
    assert(row.bg.texture=="Interface\\Other" and row.fill.texture=="Interface\\Other" and calls.SetVertexColor==4,"one restyle per row")
    ResetCalls()
    Pv.Render(stage,"bar",400,200)
    assert(Writes()==0,"restyled rows repaint without writes")
    C.views.bar.barTexture=nil
    -- icons on the same holder: rows hide, icons show; a repaint writes nothing
    local same=Pv.Render(stage,"ess",60,100)
    assert(same==canvas and #canvas.icons==3 and canvas.icons[1].shown and not canvas.rows[1].shown,"one reused canvas per parent")
    assert(canvas.scale<1,"the canvas shrinks to fit")
    ResetCalls()
    Pv.Render(stage,"ess",60,100)
    assert(Writes()==0,"an unchanged repaint of icons wrote "..Writes().." times")
    Pv.Release(stage)
    assert(not canvas.shown,"release hides the canvas")
    Pv.Render(stage,"ess",60,100)
    assert(canvas.shown,"a later render shows it again")
    Pv.ReleaseAll()
    assert(not canvas.shown,"release all")
end

print("suite cooldown manager layout contract: ok")
