local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Sample state for MSUF Edit Mode ("edit") and the options page
-- ("options"): every bar visible, rules suspended, unlearned spells shown
-- and three sample icons on empty bars. The options page also gets a
-- standalone drawing of one bar (never a live bar) and an optional
-- simulation: an 8 s cooldown on the first icon of each bar, a proc glow on
-- the second and a buff glow on the third, from duration objects built out
-- of plain numbers. The simulation runs only while the page is open and out
-- of combat; its one ticker exists only while it runs. This file keeps its
-- own small constants: the options contract loads it on its own.
local Pv={mode=nil,sim=false}
C.Preview=Pv
local EMPTY=C.EMPTY
local pairs,type,max,min=pairs,type,math.max,math.min
local wipe=table.wipe or wipe or function(t) for k in pairs(t) do t[k]=nil end return t end
local QUESTION=134400
local SIM_LENGTH,SIM_LOOP=8,10
local BAR_TEXTURE="Interface\\TargetingFrame\\UI-StatusBar"

------------------------------------------------------------------ sample icons
-- The first class spells of each family in Blizzard's order, unlearned ones
-- included; the question mark when the catalog has none.
local samples={{},{}}
local function Samples()
    local catalog=C.Catalog
    local order,records=catalog.order,catalog.records
    local a,b=samples[1],samples[2]
    wipe(a);wipe(b)
    for i=1,#order do
        local rec=records[order[i]]
        local list=rec and samples[rec.family]
        if list and #list<3 then
            local tex=catalog.RecordTexture(rec)
            if tex then list[#list+1]=tex end
        end
        if #a>=3 and #b>=3 then break end
    end
end
local function Sample(family,n)
    local list=samples[family]
    return list and list[n] or QUESTION
end

-- Resolve rebuilds placeholders with the question mark; this runs after
-- every resolve while a preview is on.
function Pv.Decorate()
    if not Pv.mode then return end
    local filled=false
    for _,plan in pairs(C.plans) do
        local entries=plan.entries
        for i=1,#entries do
            local e=entries[i]
            if e.src=="p" then
                if not filled then Samples();filled=true end
                e.texture=Sample(e.family,e.id)
            end
        end
    end
end

------------------------------------------------------------------ mode
-- Returns true when the preview turned on or off (the controller then marks
-- resolve, cooldowns, effects, layout and visibility).
function Pv.SetMode(mode)
    if mode~="edit" and mode~="options" then mode=nil end
    if Pv.mode==mode then return false end
    local was=Pv.mode~=nil
    Pv.mode=mode
    local on=mode~=nil
    if mode~="options" then Pv.Simulate(false) end
    C.state.preview=on
    if was==on then return false end
    local auras=C.Auras
    if auras and auras.SetPreview then auras.SetPreview(on) end
    return true
end

------------------------------------------------------------------ simulation
local durations=setmetatable({},{__mode="k"})
local touched={}   -- entry -> "cd"|"proc"|"aura" while simulated
local canvases={}  -- canvas holders by parent
local ticker

local function Duration(icon)
    local d=durations[icon]
    if d==nil then
        local util=_G.C_DurationUtil
        d=util and util.CreateDuration and util.CreateDuration() or false
        durations[icon]=d
    end
    return d or nil
end

local function Sim(entry,role)
    local icon=entry.icon
    if not icon then return end
    touched[entry]=role
    if role=="cd" then
        local d=Duration(icon)
        if d then
            d:SetTimeFromStart(GetTime(),SIM_LENGTH)
            C.Time.Simulate(entry,d)
        end
    else
        C.Effects.SetGlow(icon,role,true)
    end
end

-- Live icons return to their real state (a real proc glow comes back
-- through Update); canvas icons to rest.
local function Unsim(entry,role)
    local icon=entry.icon
    if not icon then return end
    if role=="cd" then
        if icon.sim then C.Time.Simulate(entry,nil) end
    else
        C.Effects.SetGlow(icon,role,false)
        if entry.src~="p" then C.Effects.Update(entry) end
    end
end

-- Sample icons that already run their role keep running (a repaint on a
-- slider tick restarts nothing); the ticker restarts every sample.
local ROLES={"cd","proc","aura"}
local function Canvas(holder)
    local fakes=holder.fakes
    for i=1,3 do
        local fake,role=fakes[i],ROLES[i]
        if fake and i<=holder.count and holder.kind~=3 and touched[fake]~=role then Sim(fake,role) end
    end
end

local function StopAll()
    for entry,role in pairs(touched) do
        touched[entry]=nil
        Unsim(entry,role)
    end
end

local function Restart()
    StopAll()
    if not Pv.sim then return end
    for _,plan in pairs(C.plans) do
        if plan.kind==1 then
            local entries,n=plan.entries,0
            for i=1,#entries do
                local e=entries[i]
                if e.icon and n<3 then n=n+1;Sim(e,ROLES[n]) end
            end
        end
    end
    for _,holder in pairs(canvases) do
        if holder.shown then Canvas(holder) end
    end
end
Pv.Restart=Restart

function Pv.Simulate(on)
    on=on==true
    if on and (Pv.mode~="options" or NS.IsCombatLocked() or not C.M.active) then on=false end
    if on==Pv.sim then return on end
    Pv.sim=on
    if ticker then ticker:Cancel();ticker=nil end
    if on then
        local timer=_G.C_Timer
        if timer and timer.NewTicker then ticker=timer.NewTicker(SIM_LOOP,Restart) end
        Restart()
    else
        StopAll()
    end
    return on
end

------------------------------------------------------------------ options canvas
-- One holder per parent frame, reused: standalone icons (kinds 1 and 2) or
-- simple rows (kind 3), in bar order with the cooldown layout math
-- (Layout.Offsets; aura bars without their player and target parts).
-- The options page lays its own mouse buttons over the drawing and reads,
-- after each Render: holder.count (items drawn), holder.kind, holder.items[i]
-- (the icon or row region), holder.keys[i] (the entry key, false for a
-- sample icon of an empty bar) and holder.dim[i] (unlearned or sample).
-- Plain table fields written in place: no widget call, nothing allocated.
local keyScratch,describe={},{}

local function Holder(parent)
    local holder=canvases[parent]
    if not holder then
        holder=S.CreateFrame("Frame",nil,parent)
        holder.icons,holder.rows,holder.fakes,holder.out,holder.look={},{},{},{},{gen=0}
        holder.keys,holder.dim,holder.textures,holder.names={},{},{},{}
        holder.items=holder.icons
        holder.count,holder.shown=0,false
        canvases[parent]=holder
    end
    return holder
end

-- What a bar's content depends on besides its own slot and kind: which bars
-- are on and their kinds (claims), by slot index.
local WEIGHT={}
for i=1,16 do WEIGHT[i]=8^(i-1) end
local function Bars()
    local sig=0
    for _,view in pairs(C.views) do
        local weight=view.index and WEIGHT[view.index]
        if weight then sig=sig+((view.on and 4 or 0)+(view.kind or 0))*weight end
    end
    return sig
end
-- Resolving a bar's keys is the costly part of a repaint: it runs again only
-- when the catalog, the entries, the spec, the lists, the spell choices,
-- the preview mode or the bars moved (every settings tick repaints).
local function SameContent(holder,slot,kind)
    local catalog,state=C.Catalog,C.state
    local gen,entries=catalog and catalog.generation or 0,state.entryGen or 0
    local spec,bars,preview=state.specID or 0,Bars(),state.preview==true
    local same=holder.cSlot==slot and holder.cKind==kind and holder.cGen==gen and holder.cEntries==entries
        and holder.cSpec==spec and holder.cBars==bars and holder.cPreview==preview and holder.cLists==C.lists
        and holder.cSpells==C.spells
    holder.cSlot,holder.cKind,holder.cGen,holder.cEntries=slot,kind,gen,entries
    holder.cSpec,holder.cBars,holder.cPreview,holder.cLists,holder.cSpells=spec,bars,preview,C.lists,C.spells
    return same
end

-- Textures and names of what the bar holds now (or would hold when off);
-- unlearned spells included, sample icons for an empty bar.
local function Content(slot,kind,holder)
    local keys=C.Resolve.Keys(slot,keyScratch)
    local spells=type(C.spells)=="table" and type(C.spells.e)=="table" and C.spells.e or EMPTY
    local itemKeys,dim,textures,names=holder.keys,holder.dim,holder.textures,holder.names
    local n=0
    for i=1,#keys do
        local key=keys[i]
        local e=C.entries[key]
        local tex,name,known
        if e and e.src~="p" then tex,name,known=e.texture,e.name,e.known
        else
            local d=C.Resolve.Describe(key,describe)
            if d then tex,name,known=d.texture,d.name,d.known end
        end
        local ov=spells[key]
        if type(ov)=="table" and ov.icon then tex=ov.icon end
        n=n+1
        textures[n],names[n]=tex or QUESTION,name or ""
        itemKeys[n],dim[n]=key,known==false
    end
    if n==0 then
        Samples()
        local family=kind==1 and 1 or 2
        for i=1,3 do textures[i],names[i],itemKeys[i],dim[i]=Sample(family,i),"",false,true end
        n=3
    end
    for i=#textures,n+1,-1 do textures[i],names[i]=nil,nil end
    for i=#itemKeys,n+1,-1 do itemKeys[i],dim[i]=nil,nil end
    return n
end

-- Canvas writes are memoized like the live bars: a repaint of an unchanged
-- bar (every settings tick repaints the page) makes no widget calls.
local function Place(region,parent,x,y)
    if region.pvX==x and region.pvY==y then return end
    region.pvX,region.pvY=x,y
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y)
end
local function Shown(region,shown)
    if region.pvShown==shown then return end
    region.pvShown=shown
    if shown then region:Show() else region:Hide() end
end
local function HideFrom(list,first)
    for i=first,#list do Shown(list[i],false) end
end

local function Icons(holder,view,count,slot)
    local icons,fakes,out,textures=holder.icons,holder.fakes,holder.out,holder.textures
    for i=1,count do
        local icon=icons[i]
        if not icon then
            icon=C.Icons.CreateStandalone(holder)
            icons[i]=icon
            -- A plain sample entry lets the glow and time layers find the bar.
            fakes[i]={key="preview",src="p",id=i,family=1,ov=EMPTY,icon=icon}
            icon.entry=fakes[i]
        end
        fakes[i].slot=slot
        if icon.styleGen~=view.styleGen or icon.styleView~=view then C.Icons.StyleIcon(icon,view) end
        C.Icons.SetTexture(icon,textures[i])
        Place(icon,holder,out[2*i-1],out[2*i])
        Shown(icon,true)
    end
    HideFrom(icons,count+1)
    HideFrom(holder.rows,1)
end

local function Row(holder,i)
    local row=holder.rows[i]
    if row then return row end
    row=S.CreateFrame("Frame",nil,holder)
    row.bg=S.CreateTexture(row,nil,"BACKGROUND")
    row.bg:SetAllPoints(row)
    row.fill=S.CreateTexture(row,nil,"ARTWORK")
    row.icon=S.CreateTexture(row,nil,"ARTWORK",nil,1)
    row.name=S.CreateFontString(row,nil,"OVERLAY")
    row.name:SetWordWrap(false)
    row.name:SetJustifyH("LEFT")
    holder.rows[i]=row
    return row
end

-- The bar look of a holder's rows; a change bumps gen and every row
-- restyles once.
local function Look(holder,w,h,tex,r,g,b,bgA,left,lead,size,st)
    local look=holder.look
    if look.w~=w or look.h~=h or look.tex~=tex or look.r~=r or look.g~=g or look.b~=b or look.bgA~=bgA
        or look.left~=left or look.lead~=lead or look.size~=size or look.font~=st.font
        or look.flags~=st.fontFlags or look.rendering~=st.fontRendering or look.shadow~=st.fontShadow
        or look.shadowOpacity~=st.fontShadowOpacity or look.shadowDistance~=st.fontShadowDistance then
        look.w,look.h,look.tex,look.r,look.g,look.b,look.bgA=w,h,tex,r,g,b,bgA
        look.left,look.lead,look.size,look.font,look.flags=left,lead,size,st.font,st.fontFlags
        look.rendering,look.shadow,look.shadowOpacity,look.shadowDistance=
            st.fontRendering,st.fontShadow,st.fontShadowOpacity,st.fontShadowDistance
        look.gen=look.gen+1
    end
    return look.gen
end

local function StyleRow(row,w,h,tex,r,g,b,bgA,left,lead,size,st)
    local side=left and "LEFT" or "RIGHT"
    row:SetSize(w,h)
    row.bg:SetTexture(tex)
    row.bg:SetVertexColor(r*.25,g*.25,b*.25,bgA)
    local icon=row.icon
    icon:ClearAllPoints()
    icon:SetPoint(side,row,side,0,0)
    icon:SetSize(h,h)
    icon:SetShown(lead>0)
    local fill=row.fill
    fill:ClearAllPoints()
    fill:SetPoint(side,row,side,left and lead or -lead,0)
    fill:SetSize(max(1,(w-lead)*.6),h)
    fill:SetTexture(tex)
    fill:SetVertexColor(r,g,b,1)
    local name=row.name
    S.SetStyledFont(name,st.font,size,st.fontFlags,st.fontRendering,
        st.fontShadow,st.fontShadowOpacity,st.fontShadowDistance)
    name:ClearAllPoints()
    name:SetPoint("LEFT",row,"LEFT",(left and lead or 0)+4,0)
    name:SetPoint("RIGHT",row,"RIGHT",-(left and 0 or lead)-4,0)
end

-- Kind 3: icon, a partly filled bar and the name, in the bar's own look.
local function Rows(holder,view,count)
    local w,h=C.Layout.Metrics(view)
    local st=C.state
    local tex=S.ResolveTexture(view.barTexture,BAR_TEXTURE)
    local r,g,b
    if view.barClass~=false and type(UnitClass)=="function" then
        local _,file=UnitClass("player")
        if S.Public(file) then r,g,b=S.ClassRGB(file) end
    end
    if not r then r,g,b=view.barR or .91,view.barG or .72,view.barB or .33 end
    local bgA=(view.barBgAlpha or 55)/100
    local left=view.barIconSide~=2
    local lead=view.barIcon~=false and h or 0
    local size=max(8,math.floor(h*.55))
    local gen=Look(holder,w,h,tex,r,g,b,bgA,left,lead,size,st)
    local out,named,textures,names=holder.out,view.barName~=false,holder.textures,holder.names
    for i=1,count do
        local row=Row(holder,i)
        if row.pvLook~=gen then
            row.pvLook=gen
            StyleRow(row,w,h,tex,r,g,b,bgA,left,lead,size,st)
        end
        Place(row,holder,out[2*i-1],out[2*i])
        local texture,text=textures[i],named and names[i] or ""
        if row.pvTex~=texture then row.pvTex=texture;row.icon:SetTexture(texture) end
        if row.pvText~=text then row.pvText=text;row.name:SetText(text) end
        Shown(row,true)
    end
    HideFrom(holder.rows,count+1)
    HideFrom(holder.icons,1)
end

-- Samples past the first keep ones stop (all of them for rows).
local function Rest(holder,keep)
    local fakes=holder.fakes
    for i=keep+1,#fakes do
        local role=touched[fakes[i]]
        if role then touched[fakes[i]]=nil;Unsim(fakes[i],role) end
    end
end

-- Draws one bar into parent, scaled down only when it exceeds the space.
function Pv.Render(parent,slot,maxWidth,maxHeight)
    local view=parent and C.views[slot]
    if not view then return nil end
    local holder=Holder(parent)
    local kind=view.kind or 1
    local n=holder.n
    if not SameContent(holder,slot,kind) or not n then
        n=Content(slot,kind,holder)
        holder.n=n
    end
    local width,height,count=C.Layout.Offsets(view,n,holder.out)
    Rest(holder,kind~=3 and count or 0)
    if kind==3 then Rows(holder,view,count) else Icons(holder,view,count,slot) end
    holder.kind,holder.count,holder.slot=kind,count,slot
    holder.items=kind==3 and holder.rows or holder.icons
    if holder.pvW~=width or holder.pvH~=height then
        holder.pvW,holder.pvH=width,height
        holder:SetSize(width,height)
    end
    local scale=1
    if type(maxWidth)=="number" and maxWidth>0 and width>maxWidth then scale=maxWidth/width end
    if type(maxHeight)=="number" and maxHeight>0 and height*scale>maxHeight then scale=maxHeight/height end
    scale=max(.1,min(1,scale))
    if holder.pvScale~=scale then holder.pvScale=scale;holder:SetScale(scale) end
    if not holder.shown then holder.shown=true;holder:Show() end
    if Pv.sim then Canvas(holder) end
    return holder
end

function Pv.Release(parent)
    local holder=canvases[parent]
    if not holder then return end
    Rest(holder,0)
    holder.shown,holder.cSlot=false,nil
    holder:Hide()
end

function Pv.ReleaseAll()
    for parent in pairs(canvases) do Pv.Release(parent) end
end
