local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Bar frames and geometry. Every bar is a plain UIParent child, so moving,
-- sizing and reflowing stay legal in combat. Math runs in whole physical
-- pixels and every widget write is diffed against memo fields on our own
-- frames: a repeated pass with unchanged inputs makes no widget calls.
-- Offsets are TOPLEFT offsets inside the bar frame; the bar frame itself is
-- anchored by its growth edge to the screen center (free, x/y from there) or
-- to its parent's edge (attached, x/y an offset from the attach point).
local L={dirty={}}
C.Layout=L
local SLOTS=NS.CDM.SLOTS
local Public=S.Public
local floor,ceil,max=math.floor,math.ceil,math.max
local STRATA={"BACKGROUND","LOW","MEDIUM","HIGH"}
-- Attach sides (Below, Above, Left, Right) x alignment along that edge
-- (Center, Start, End): own point, target point; gap sign per side.
local ATTACH={
    {{"TOP","BOTTOM"},{"TOPLEFT","BOTTOMLEFT"},{"TOPRIGHT","BOTTOMRIGHT"}},
    {{"BOTTOM","TOP"},{"BOTTOMLEFT","TOPLEFT"},{"BOTTOMRIGHT","TOPRIGHT"}},
    {{"RIGHT","LEFT"},{"TOPRIGHT","TOPLEFT"},{"BOTTOMRIGHT","BOTTOMLEFT"}},
    {{"LEFT","RIGHT"},{"TOPLEFT","TOPRIGHT"},{"BOTTOMLEFT","BOTTOMRIGHT"}},
}
local SIDE_X={0,0,-1,1}
local SIDE_Y={-1,1,0,0}
-- Where a point sits on a rectangle: -1 left/bottom, 0 center, 1 right/top.
local POINT_X={TOP=0,BOTTOM=0,LEFT=-1,RIGHT=1,TOPLEFT=-1,TOPRIGHT=1,BOTTOMLEFT=-1,BOTTOMRIGHT=1,CENTER=0}
local POINT_Y={TOP=1,BOTTOM=-1,LEFT=0,RIGHT=0,TOPLEFT=1,TOPRIGHT=1,BOTTOMLEFT=-1,BOTTOMRIGHT=-1,CENTER=0}
local FRAME_ANCHORS=NS.CDM.FRAME_ANCHORS
local UNIT_FRAME={player="MSUF_player",target="MSUF_target",viewer="EssentialCooldownViewer"}
-- Bars MSUF may anchor to (Native.AnchorFrame); they carry an anchor frame.
local ANCHORED={ess=true,uti=true,buf=true}

local function Round(value) return floor(value+.5) end
-- Bumped whenever a watched frame (MSUF's unit frames, Blizzard's Essential
-- bar) may have moved or the pixel scale changed: cached rectangles and bar
-- anchors older than this generation are read and written again.
local frameGen=0

------------------------------------------------------------------ pixel scale
local px
-- UI units per physical pixel for UIParent children. Cached; recomputed only
-- after InvalidateScale (UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED).
function L.PixelScale()
    if px then return px end
    local value,height=1,nil
    if type(GetPhysicalScreenSize)=="function" then height=select(2,GetPhysicalScreenSize()) end
    local scale=UIParent and UIParent:GetEffectiveScale()
    if Public(height) and Public(scale) and type(height)=="number" and type(scale)=="number" and height>0 and scale>0 then
        value=768/height/scale
    end
    px=value
    C.state.px=value
    return value
end
function L.InvalidateScale()
    px=nil
    frameGen=frameGen+1
    return L.PixelScale()
end
function L.Snap(value)
    local unit=px or L.PixelScale()
    return Round(value/unit)*unit
end

------------------------------------------------------------------ grid math
-- Growth direction: 1 Down (vertical: Right), 2 Up (vertical: Left). Aura
-- bars without a grow rule (built-in "Buff bars") stack upward.
local function Grow(view)
    local grow=view.grow
    if grow==nil and view.kind==3 then return 2 end
    return grow==2 and 2 or 1
end

-- Cell size and spacing in whole pixels, stride, flow and alignment.
local function Grid(view,unit)
    if view.kind==3 then
        return max(1,Round((view.barWidth or 200)/unit)),max(1,Round((view.barHeight or 18)/unit)),
            Round((view.spacing or 2)/unit),1,false,Grow(view),1
    end
    local size=view.size or 36
    local per=floor(view.perRow or 1)
    if per<1 then per=1 end
    local align=view.align
    if align~=2 and align~=3 then align=1 end
    return max(1,Round(size/unit)),max(1,Round(size*(view.height or 100)/100/unit)),Round((view.spacing or 0)/unit),
        per,view.vertical==true,Grow(view),align
end

-- Lays out group 1 (n1 cells) and then group 2 (n2 cells) starting on a new
-- line, lines of `per`, in growth order. Every line is aligned on its own.
-- Integer pixel math; the centering origin is floored once per line.
-- Writes out[2i-1], out[2i] and returns the content size in UI units. An
-- empty layout keeps the footprint of one cell.
local function Fill(w,h,sp,per,vertical,grow,align,n1,n2,out,unit)
    local lines1=ceil(n1/per)
    local lines=lines1+ceil(n2/per)
    if lines==0 then return w*unit,h*unit end
    local along,across=w,h
    if vertical then along,across=h,w end
    local full=n1>n2 and n1 or n2
    if full>per then full=per end
    local extent=full*along+(full-1)*sp
    local depth=lines*across+(lines-1)*sp
    local index=0
    for group=1,2 do
        local n,base=n1,0
        if group==2 then n,base=n2,lines1 end
        for i=0,n-1 do
            local line=floor(i/per)
            local count=n-line*per
            if count>per then count=per end
            local free=extent-(count*along+(count-1)*sp)
            local a=(align==2 and 0 or align==3 and free or floor(free/2))+(i-line*per)*(along+sp)
            local g=base+line
            if grow==2 then g=lines-1-g end
            local b=g*(across+sp)
            index=index+1
            if vertical then out[2*index-1],out[2*index]=b*unit,-a*unit
            else out[2*index-1],out[2*index]=a*unit,-b*unit end
        end
    end
    if vertical then return depth*unit,extent*unit end
    return extent*unit,depth*unit
end

-- Pure: offsets of the first `count` cells (capped by maxIcons) relative to
-- the bar's TOPLEFT. Returns width, height and the laid-out count.
function L.Offsets(view,count,out)
    local unit=px or L.PixelScale()
    local w,h,sp,per,vertical,grow,align=Grid(view,unit)
    local n=type(count)=="number" and count or 0
    local cap=view.maxIcons
    if type(cap)=="number" and cap>0 and n>cap then n=cap end
    if n<0 then n=0 end
    local width,height=Fill(w,h,sp,per,vertical,grow,align,n,0,out,unit)
    return width,height,n
end

-- Cell width, height and spacing in UI units (pixel exact), stride, vertical,
-- grow and align: what the aura layer needs for its flow layout.
function L.Metrics(view)
    local unit=px or L.PixelScale()
    local w,h,sp,per,vertical,grow,align=Grid(view,unit)
    return w*unit,h*unit,sp*unit,per,vertical,grow,align
end

-- Growth-edge point of a bar; free bars anchor it to UIParent's center.
function L.Point(view)
    if view.kind~=3 and view.vertical then return Grow(view)==2 and "RIGHT" or "LEFT" end
    return Grow(view)==2 and "BOTTOM" or "TOP"
end
local Point=L.Point

------------------------------------------------------------------ frames
local function Host(bar)
    local host=bar.auraHost
    if not host then
        host=S.CreateFrame("Frame",nil,bar.frame)
        host:SetAllPoints(bar.frame)
        bar.auraHost=host
    end
    return host
end

function L.EnsureBar(slot)
    local bar=C.bars[slot]
    if bar then return bar end
    local frame=S.CreateFrame("Frame",nil,UIParent)
    frame:SetClampedToScreen(true)
    frame:Hide()
    -- out: offsets scratch; laid/spare: icons of the last two passes.
    bar={key=slot,frame=frame,cells={},out={},laid={},spare={},pass=0,shown=false}
    if ANCHORED[slot] then
        -- MSUF's anchor: same rectangle as the bar, never a restricted frame.
        local anchor=S.CreateFrame("Frame",nil,frame)
        anchor:SetAllPoints(frame)
        bar.anchorFrame=anchor
    end
    C.bars[slot]=bar
    local view=C.views[slot]
    if view and (view.kind==2 or view.kind==3) then Host(bar) end
    -- A driver may have reported before the bar existed.
    local visibility=C.Visibility
    if visibility and visibility.Paint then visibility.Paint(slot) end
    return bar
end

local function Size(region,w,h)
    if region.layW~=w or region.layH~=h then
        region.layW,region.layH=w,h
        region:SetSize(w,h)
    end
end

local function Shown(region,shown)
    if region.layShown~=shown then
        region.layShown=shown
        if shown then region:Show() else region:Hide() end
    end
end

-- One TOPLEFT point per region; the first write after a memo reset also
-- clears foreign points.
local function Place(region,rel,x,y)
    if region.layX~=x or region.layY~=y then
        if region.layX==nil then region:ClearAllPoints() end
        region.layX,region.layY=x,y
        region:SetPoint("TOPLEFT",rel,"TOPLEFT",x,y)
    end
    Shown(region,true)
end

-- Drops an icon's placement memo: the next pass writes it again and
-- reports its overlay edge. The icon pool calls it when it hides an icon
-- behind the layout's back.
local function Forget(icon)
    icon.layX,icon.layY,icon.layShown,icon.layEntry=nil,nil,nil,nil
end
L.Forget=Forget

function L.Strata(slot)
    local bar,view=C.bars[slot],C.views[slot]
    if not bar or not view then return end
    local strata=STRATA[view.strata] or "MEDIUM"
    if bar.strata~=strata then
        bar.strata=strata
        bar.frame:SetFrameStrata(strata)
    end
end

------------------------------------------------------------------ anchoring
-- Parent candidate: the first shown bar up the attach chain. A bar that is
-- off passes the attachment on to its own target, so switching a bar off
-- never strands the bars attached to it. With no shown bar up the chain the
-- second value names the off bar whose place the bar takes over.
local function Direct(slot)
    local cursor,standIn=slot,nil
    for _=1,#SLOTS do
        local view=C.views[cursor]
        local anchor=view and view.anchor
        if type(anchor)~="number" or anchor<2 then return nil,standIn end
        local target=SLOTS[anchor-1]
        local key=target and target.key
        if not key or key==slot then return nil,standIn end
        local parent=C.views[key]
        if not parent then return nil,standIn end
        if parent.on then return key end
        standIn,cursor=key,key
    end
    return nil,standIn
end
-- Resolved parent, or nil for a free bar. A bar inside an anchor cycle is
-- free; a bar leading into a cycle attaches to its (then free) parent.
function L.Parent(slot)
    local parent=Direct(slot)
    if not parent then return nil end
    local cursor=parent
    for _=1,#SLOTS do
        cursor=Direct(cursor)
        if not cursor then return parent end
        if cursor==slot then return nil end
    end
    return parent
end

local function SetAnchor(bar,point,rel,relPoint,x,y)
    local frame=bar.frame
    if bar.aPoint==point and bar.aRel==rel and bar.aRelPoint==relPoint then
        if bar.aX==x and bar.aY==y then return end
    else
        frame:ClearAllPoints()
        bar.aPoint,bar.aRel,bar.aRelPoint=point,rel,relPoint
    end
    bar.aX,bar.aY=x,y
    frame:SetPoint(point,rel,relPoint,x,y)
end

------------------------------------------------------------------ MSUF unit frames
-- A bar attached to MSUF's player or target frame never anchors to it: that
-- frame is protected, and a bar in its anchor family could not reflow in
-- combat. The bar reads the frame's rectangle and sits against UIParent at
-- that spot instead. MSUF frames do not move in combat, so this is exact.
-- Two probes stretched from UIParent's corner to the frame's corners report
-- every move or resize through OnSizeChanged: no polling, no hooks. Between
-- two reports the rectangle is read once and kept, so relayouts of bars on
-- these frames make no geometry reads.
local watched,probesPending,rects={},false,{}
local function Num(v) return Public(v) and type(v)=="number" and v==v end
local function FollowsViewer(slot)
    return slot=="ess" and C.Native~=nil and C.Native.FollowViewer()
end
local function FrameMoved()
    frameGen=frameGen+1
    for i=1,#SLOTS do
        local slot=SLOTS[i].key
        local view=C.views[slot]
        if view and view.on then
            local parent,off=Direct(slot)
            local src=(not parent and off) and C.views[off] or view
            if FRAME_ANCHORS[src.anchor] or FollowsViewer(src.key) then L.Request(slot) end
        end
    end
end
local function Probe(frame,relPoint)
    local probe=S.CreateFrame("Frame",nil,UIParent)
    probe:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",0,0)
    probe:SetPoint("TOPRIGHT",frame,relPoint,0,0)
    probe:SetScript("OnSizeChanged",FrameMoved)
    return probe
end
-- Rectangle of MSUF's frame for `unit` (or Blizzard's Essential bar for
-- "viewer") in UIParent units: left, bottom, right, top; nil when the frame
-- is missing or unreadable. A watched frame's readable rectangle is kept
-- until its probes (or a scale change) bump frameGen; a frame without
-- probes yet (it appeared in combat) is read on every call.
local function Rect(unit)
    local frame=_G[UNIT_FRAME[unit]]
    local kept=rects[unit]
    if kept and kept.frame==frame and kept.gen==frameGen then return kept[1],kept[2],kept[3],kept[4] end
    if type(frame)~="table" or NS.Safety.IsForbidden(frame) then return nil end
    if watched[unit]~=frame then
        if NS.IsCombatLocked() then probesPending=true
        else
            watched[unit]=frame
            Probe(frame,"BOTTOMLEFT"); Probe(frame,"TOPRIGHT")
        end
    end
    local left,bottom,width,height=frame:GetRect()
    local scale,ui=frame:GetEffectiveScale(),UIParent:GetEffectiveScale()
    if not (Num(left) and Num(bottom) and Num(width) and Num(height) and Num(scale) and Num(ui)) or ui<=0 then
        return nil
    end
    local k=scale/ui
    local right,top=(left+width)*k,(bottom+height)*k
    left,bottom=left*k,bottom*k
    if watched[unit]==frame then
        if not kept then kept={};rects[unit]=kept end
        kept.frame,kept.gen=frame,frameGen
        kept[1],kept[2],kept[3],kept[4]=left,bottom,right,top
    end
    return left,bottom,right,top
end
L.Rect=Rect

-- MSUF places its unit frames by our Essential bar when it follows the
-- cooldown bars; then the Essential bar and every bar it attaches to stay
-- off MSUF's frames, or the two would chase each other.
local function MSUFFollows()
    local db=_G.MSUF_DB
    local general=type(db)=="table" and db.general or nil
    return type(general)=="table" and general.anchorToCooldown==true
        and type(_G.MSUF_GetSuiteCooldownAnchor)=="function"
end
-- from: the switched-off bar whose placement `slot` takes over, if any.
function L.FrameTarget(slot,from)
    local view=C.views[from or slot]
    local target=view and FRAME_ANCHORS[view.anchor]
    if not target then return nil end
    if MSUFFollows() then
        local cursor="ess"
        for _=1,#SLOTS do
            if cursor==slot or cursor==from then return nil end
            cursor=Direct(cursor)
            if not cursor then break end
        end
    end
    return target
end

-- Placed by its own absolute x/y: not attached to a bar or an MSUF frame,
-- not standing in for a switched-off bar and not riding Blizzard's
-- Essential bar. Position conversion needs this.
function L.Free(slot)
    if L.Parent(slot)~=nil or L.FrameTarget(slot)~=nil then return false end
    local _,standIn=Direct(slot)
    if standIn~=nil then return false end
    return not FollowsViewer(slot)
end
-- Draggable in Edit Mode and the preview: free bars move, attached bars and
-- the Essential bar riding Blizzard's bar shift by an offset from it.
function L.Movable(slot)
    if C.views[slot]==nil then return false end
    local parent,off=Direct(slot)
    return not (parent==nil and off~=nil)
end
L.FollowsViewer=FollowsViewer
-- The bar's own x/y count from Blizzard's Essential bar: it follows that
-- bar (FollowsViewer) and has no parent bar, MSUF frame or switched-off bar
-- whose placement it takes, the condition Anchor rides it under. A bar
-- standing in for it reads the same x/y the same way.
function L.RidesViewer(slot)
    if not FollowsViewer(slot) or L.Parent(slot)~=nil or L.FrameTarget(slot)~=nil then return false end
    local _,standIn=Direct(slot)
    return standIn==nil
end
-- Growth-edge point of a bar with this view laid on Blizzard's Essential
-- bar (UIParent units from its bottom left); nil when that bar's rectangle
-- is unreadable.
local function ViewerPoint(view)
    local left,bottom,right,top=Rect("viewer")
    if not left then return nil end
    local point=Point(view)
    return point=="LEFT" and left or point=="RIGHT" and right or (left+right)/2,
        point=="TOP" and top or point=="BOTTOM" and bottom or (bottom+top)/2
end
L.ViewerPoint=ViewerPoint

-- x/y of an attached bar are an offset from its attach point. A drag
-- preview passes its values in without writing settings.
local dragSlot,dragX,dragY
local function Anchor(slot)
    local bar,view=C.bars[slot],C.views[slot]
    if not bar or not view or not view.on then return end
    local unit=px or L.PixelScale()
    local parent,standIn=L.Parent(slot),nil
    if not parent then local _,off=Direct(slot); standIn=off end
    -- Standing in for an off bar: take its whole placement.
    local pv=standIn and C.views[standIn] or view
    local vx,vy=pv.x or 0,pv.y or 0
    if dragSlot==slot and not standIn then vx,vy=dragX,dragY end
    local side,align=pv.side,pv.align
    if side~=2 and side~=3 and side~=4 then side=1 end
    if align~=2 and align~=3 then align=1 end
    local attach=ATTACH[side][align]
    local gap=Round((pv.gap or 0)/unit)*unit
    local ox,oy=Round(vx/unit)*unit,Round(vy/unit)*unit
    bar.parent=parent
    if parent then
        SetAnchor(bar,attach[1],L.EnsureBar(parent).frame,attach[2],SIDE_X[side]*gap+ox,SIDE_Y[side]*gap+oy)
        return
    end
    local target=L.FrameTarget(slot,standIn)
    local left,bottom,right,top
    if target then left,bottom,right,top=Rect(target) end
    -- Blizzard's invisible Essential bar carries MSUF's frames: sit on it,
    -- growth edge on growth edge, centered (also for a bar standing in for
    -- a switched-off Essential bar: its x/y count from Blizzard's bar too).
    if not left and FollowsViewer(standIn or slot) then
        local x,y=ViewerPoint(pv)
        if x then
            SetAnchor(bar,Point(pv),UIParent,"BOTTOMLEFT",Round(x/unit)*unit+ox,Round(y/unit)*unit+oy)
            return
        end
    end
    if left then
        local rel=attach[2]
        local rx,ry=POINT_X[rel],POINT_Y[rel]
        local x=rx<0 and left or rx>0 and right or (left+right)/2
        local y=ry<0 and bottom or ry>0 and top or (bottom+top)/2
        SetAnchor(bar,attach[1],UIParent,"BOTTOMLEFT",Round(x/unit)*unit+SIDE_X[side]*gap+ox,
            Round(y/unit)*unit+SIDE_Y[side]*gap+oy)
    else
        local point=Point(pv)
        SetAnchor(bar,point,UIParent,"CENTER",ox,oy)
    end
end

-- Combat end: watch the MSUF frames that appeared during combat.
function L.CombatEnded()
    if not probesPending then return end
    probesPending=false
    FrameMoved()
end

-- Edit Mode drag preview: place the bar as if x/y were these values.
function L.DragPlace(slot,x,y)
    if not C.bars[slot] or not L.Movable(slot) then return false end
    dragSlot,dragX,dragY=slot,x,y
    Anchor(slot)
    dragSlot,dragX,dragY=nil,nil,nil
    return true
end

-- Anchors of other bars change only when some bar's layout rules, the pixel
-- scale, a watched frame or who follows whom (MSUF and Blizzard's bar)
-- changed; one generation check per slot decides that.
local seenGen,seenPx,seenFrames,seenFollow={},nil,nil,nil

-- MSUF Edit Mode drags move bar frames directly: forget the anchor memo so
-- the next pass writes the saved position again (a cancelled drag included).
function L.ForgetAnchors()
    for _,bar in pairs(C.bars) do bar.aPoint,bar.aRel,bar.aRelPoint,bar.aX,bar.aY=nil,nil,nil,nil,nil end
    seenPx=nil
end

local function Reanchor()
    local follow=(FollowsViewer("ess") and 1 or 0)+(MSUFFollows() and 2 or 0)
    local stale=seenPx~=px or seenFrames~=frameGen or seenFollow~=follow
    seenFrames,seenFollow=frameGen,follow
    for i=1,#SLOTS do
        local view=C.views[SLOTS[i].key]
        local gen=false
        if view then gen=view.layoutGen; if gen==nil then stale=true end end
        if seenGen[i]~=gen then seenGen[i]=gen; stale=true end
    end
    if not stale then return end
    seenPx=px
    for i=1,#SLOTS do Anchor(SLOTS[i].key) end
end

------------------------------------------------------------------ content
-- An aura overlay sits on its cooldown icon without being its child: it
-- switches with the icon on every shown/hidden edge (hideReady, maxIcons,
-- an icon handed to another entry). Edges only, so a steady pass calls
-- nothing.
local function Overlay(entry,on)
    local auras=C.Auras
    local shown=auras and auras.OverlayShown
    if type(shown)=="function" then shown(entry,on) end
end

-- Cooldown icons: visible entries (hideReady hides; preview shows all) up
-- to maxIcons. Icons that left the bar since the last pass lose their memo,
-- so a pooled icon coming back is always written again.
local function PlaceIcons(bar,view,plan)
    local entries=plan.entries
    local showAll=C.state.preview==true
    local n=0
    for i=1,#entries do
        local entry=entries[i]
        if entry.icon and (showAll or not entry.hidden) then n=n+1 end
    end
    local width,height
    width,height,n=L.Offsets(view,n,bar.out)
    local out,frame=bar.out,bar.frame
    local pass=bar.pass+1
    bar.pass=pass
    local current,last=bar.spare,bar.laid
    local count,index=0,0
    for i=1,#entries do
        local entry=entries[i]
        local icon=entry.icon
        if icon then
            count=count+1
            current[count]=icon
            icon.layPass=pass
            if icon.layEntry~=entry then Forget(icon); icon.layEntry=entry end
            local was=icon.layShown
            if index<n and (showAll or not entry.hidden) then
                index=index+1
                Place(icon,frame,out[2*index-1],out[2*index])
                if was~=true then Overlay(entry,true) end
            else
                Shown(icon,false)
                if was~=false then Overlay(entry,false) end
            end
        end
    end
    for i=#current,count+1,-1 do current[i]=nil end
    for i=1,#last do
        local icon=last[i]
        if icon.layPass~=pass then Forget(icon) end
    end
    bar.laid,bar.spare=current,last
    return width,height
end

local function HideCells(bar)
    local cells=bar.cells
    for i=1,#cells do Shown(cells[i],false) end
end

-- The row an aura entry takes: the aura layer's rule (a "both" entry takes
-- the row its selfAura hint names), so containers and cells agree; plain
-- target entries without the aura layer.
local function TargetRow(entry)
    local auras=C.Auras
    local rule=auras and auras.TargetRow
    if rule then return rule(entry) end
    return entry.unit=="target"
end

-- Aura bars in fixed places: keepSlots or showMissing on the bar or a
-- spell, or a column (a vertical one-line bar, or one icon per line) that
-- mixes player and target entries. Player and target auras sit in two
-- containers that cannot interleave, so in a column every entry keeps its
-- own cell in the bar's order. Horizontal rows stay compact and grow from
-- their alignment point like Blizzard's. Second value: the cells follow the
-- bar's order on that single line or column. Third value: a centered
-- horizontal row that mixes both fits on one line split at its center
-- (player auras end there, target auras start there), compact and growing
-- from the middle. Shared by Auras, the layout and the controller.
function L.FixedAuras(view,entries)
    local cap=view.maxIcons
    if type(cap)~="number" or cap<=0 or cap>#entries then cap=#entries end
    local n1,n2=0,0
    for i=1,cap do if TargetRow(entries[i]) then n2=n2+1 else n1=n1+1 end end
    local _,_,_,per,vertical,_,align=Grid(view,px or L.PixelScale())
    local n=n1+n2
    local single=n<=per or per==1
    local fixed=view.keepSlots==true or view.showMissing==true
    if not fixed then
        for i=1,#entries do
            local ov=entries[i].ov
            if ov and ov.showMissing==true then fixed=true;break end
        end
    end
    local split=false
    if not fixed and n1>0 and n2>0 then
        if (vertical and n<=per) or (not vertical and per==1) then fixed=true
        elseif not vertical and n<=per then
            if align==1 then split=true else fixed=true end
        end
    end
    return fixed,fixed and single,split
end

-- Aura bars: footprint of every entry (the container shows the active ones);
-- player-row entries first, target-row entries from a new line in growth
-- order. Fixed cells follow entry positions in the plan.
local function PlaceAuras(bar,view,plan)
    local entries=plan.entries
    local cap=view.maxIcons
    if type(cap)~="number" or cap<=0 then cap=#entries end
    local n1,n2=0,0
    for i=1,#entries do
        if n1+n2>=cap then break end
        if TargetRow(entries[i]) then n2=n2+1 else n1=n1+1 end
    end
    local unit=px or L.PixelScale()
    local w,h,sp,per,vertical,grow,align=Grid(view,unit)
    local out=bar.out
    -- Fixed places on one line: every entry in the bar's order. Otherwise
    -- the target part starts on a new line after the player part.
    local _,ordered,split=L.FixedAuras(view,entries)
    ordered=ordered or split
    local width,height
    if ordered then width,height=Fill(w,h,sp,per,vertical,grow,align,n1+n2,0,out,unit)
    else width,height=Fill(w,h,sp,per,vertical,grow,align,n1,n2,out,unit) end
    bar.lines1,bar.lines2=ceil(n1/per),ceil(n2/per)
    local cells=bar.cells
    if #cells>0 then
        local host=Host(bar)
        local cw,ch=w*unit,h*unit
        local r1,r2=0,0
        for i=1,#cells do
            local cell,entry=cells[i],entries[i]
            local at
            if entry and r1+r2<n1+n2 then
                if TargetRow(entry) then r2=r2+1; at=n1+r2 else r1=r1+1; at=r1 end
                if ordered then at=r1+r2 end
            end
            if at then
                Size(cell,cw,ch)
                Place(cell,host,out[2*at-1],out[2*at])
            else
                Shown(cell,false)
            end
        end
    end
    return width,height
end

-- Fixed-place frame for entry i of an aura bar (AuraSlot anchor target).
-- An existing cell costs one lookup: the layout passes keep it placed.
-- Missing cells are made for every entry the bar can lay out at once and
-- placed in one pass, so a container build stays linear.
function L.Cell(slot,i)
    local bar=L.EnsureBar(slot)
    local cells=bar.cells
    local cell=cells[i]
    if cell then return cell end
    local host=Host(bar)
    local view,plan=C.views[slot],C.plans[slot]
    local want=plan and #plan.entries or 0
    local cap=view and view.maxIcons
    if type(cap)=="number" and cap>0 and want>cap then want=cap end
    if want<i then want=i end
    for index=#cells+1,want do
        cell=S.CreateFrame("Frame",nil,host)
        cell:Hide()
        cell.layShown=false
        cells[index]=cell
    end
    if view and plan and (view.kind==2 or view.kind==3) then PlaceAuras(bar,view,plan) end
    return cells[i]
end

------------------------------------------------------------------ passes
-- MSUF follows the Essential bar: tell it when that bar appears or goes.
local function Notify(slot)
    if slot=="ess" and type(C.AnchorChanged)=="function" then C.AnchorChanged() end
end
function L.Hide(slot)
    local bar=C.bars[slot]
    if bar and bar.shown then
        bar.shown=false
        bar.frame:Hide()
        Notify(slot)
    end
end
function L.HideAll()
    for i=1,#SLOTS do L.Hide(SLOTS[i].key) end
end

function L.Apply(slot)
    L.dirty[slot]=nil
    local view,plan=C.views[slot],C.plans[slot]
    if not view or not view.on or not plan then
        L.Hide(slot)
    else
        local bar=L.EnsureBar(slot)
        L.Strata(slot)
        local width,height
        if view.kind==2 or view.kind==3 then
            Host(bar)
            width,height=PlaceAuras(bar,view,plan)
        else
            width,height=PlaceIcons(bar,view,plan)
            HideCells(bar)
        end
        Size(bar.frame,width,height)
        Anchor(slot)
        if not bar.shown then
            bar.shown=true
            bar.frame:Show()
            Notify(slot)
        end
    end
    Reanchor()
end

-- Roots before attached children, so parents exist and carry their size.
local depths={}
function L.ApplyAll()
    local deepest=0
    for i=1,#SLOTS do
        local depth,cursor=0,L.Parent(SLOTS[i].key)
        while cursor and depth<#SLOTS do depth=depth+1; cursor=L.Parent(cursor) end
        depths[i]=depth
        if depth>deepest then deepest=depth end
    end
    for depth=0,deepest do
        for i=1,#SLOTS do
            if depths[i]==depth then L.Apply(SLOTS[i].key) end
        end
    end
end

-- Relayout request from runtime paths (hideReady edges); the controller's
-- flush calls Flush once per frame.
function L.Request(slot)
    L.dirty[slot]=true
    if type(C.Schedule)=="function" then C.Schedule() end
end
function L.Flush()
    if next(L.dirty)==nil then return end
    for i=1,#SLOTS do
        local slot=SLOTS[i].key
        if L.dirty[slot] then L.Apply(slot) end
    end
end
