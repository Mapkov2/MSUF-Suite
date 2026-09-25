local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Aura layer on Blizzard's AuraContainer: buff icon bars (kind 2), buff bar
-- bars (kind 3) and aura overlays on cooldown icons (kind 1). Blizzard
-- matches the auras and writes every secret value (icon, swipe, text,
-- stacks, bar) from its secure side, so no Lua runs per UNIT_AURA. This
-- file only builds, places and styles containers:
--  * structure (groups, slots, filters) changes out of combat only. Groups
--    and slots cannot be removed, so they are updated in place and surplus
--    ones switched off;
--  * sealed buttons are restyled only while CanBeAccessedInContext() is
--    plainly true. While auras are secret the new look waits for them to
--    open; buttons that refuse while auras are plain get a new container;
--  * containers cannot be freed either: retired ones are disabled, hidden
--    and parked in a per-bar pool for reuse (never dropped from it);
--  * in combat only container-level switches run: target containers pause
--    while the target is friendly, overlay slots follow their icon.
-- Per-spell stack choices ride on the same bindings, so no Lua ever reads
-- an application count: a shared count formatter colors the stack text
-- from N applications, and the stack glow is placed by an application bar
-- Blizzard fills (see NewStack). Countdown and stack text are bound only
-- while the entry shows them (per-spell choice, else the bar's switch);
-- Text on top orders their two frames. Glows are flipbooks, edges and alpha
-- loops styled by widget writes only. The one Lua on the aura side: bars
-- whose entries have unknown sound kits (without a mapped sound file) get a
-- sensor in each button that runs when it shows or hides, never on a stack
-- or duration update. Known CDM kits use native aura sound registrations.
local K=C.Const
local A={pending={}}
C.Auras=A

local CreateFrame,InCombatLockdown=CreateFrame,InCombatLockdown
local floor,ceil,max,min=math.floor,math.ceil,math.max,math.min
local pairs,next,type,tonumber=pairs,next,type,tonumber
local tremove,tconcat=table.remove,table.concat
local wipe=C.wipe
local Public=S.Public
local EMPTY=C.EMPTY

local UNITS={"player","target"}
local STRATA=K.STRATA
local QUESTION=K.QUESTION_ICON
local BAR_TEXTURE=K.BAR_TEXTURE
local HELP_MINE,HELP_ANY,HARM_MINE="HELPFUL|PLAYER","HELPFUL","HARMFUL|PLAYER"
-- No aura passes this (maxDuration also drops permanent auras): 12.1.0
-- slots have no enable flag.
local NONE={maxDuration=0}
local TEXT_DEFAULT={}
-- Init of a button whose group has no entry yet: the bar's choices.
local NO_ENTRY={}
local E=_G.Enum or EMPTY
local TIMER=E.StatusBarTimerDirection or EMPTY
local IMMEDIATE=E.StatusBarInterpolation and E.StatusBarInterpolation.Immediate or 0
-- barFill 1 drains, 2 fills.
local BAR_OPTS={{direction=TIMER.RemainingTime or 1,interpolation=IMMEDIATE},
    {direction=TIMER.ElapsedTime or 0,interpolation=IMMEDIATE}}
local ROUND=E.NumericRuleFormatRounding or EMPTY
local UP,DOWN=ROUND.Up or 1,ROUND.Down or 2
local GOLD=K.GLOW_GOLD or {1,.82,0}
local PANDEMIC={1,.3,.15}
-- Glow styles (Const): 1 Blizzard alert and 2 marching ants share one
-- flipbook layout, 3 pulses the edges, 4 holds them still.
local GLOW=K.GLOW
local FLIP=GLOW[1]
local PULSE=GLOW[3] and GLOW[3].pulse or .6
local PULSE_LOW=.25
-- The widest glow reaches this far around its button: the stack gate's size.
local REACH=1
for i=1,#GLOW do
    local scale=GLOW[i].scale
    if scale and scale>REACH then REACH=scale end
end
local STACK_TEXTURE="Interface\\Buttons\\WHITE8X8"
local DEFAULTS=NS.CDM and NS.CDM.SPELL_DEFAULTS or EMPTY
local STACK_COLOR=DEFAULTS.stackColor or "ff5a3c"
-- Container levels above the bar frame: aura bars sit over their host (+1)
-- and cells (+2); overlays sit on the icon (+1) at swipe height, under the
-- icon's glows and text.
local AURA_LEVEL=4
local OVER_LEVEL=1+(K.LEVEL and K.LEVEL.cd or 1)
-- Flow per [vertical][grow]: flow anchor, horizontal and vertical direction
-- (AnchorUtil.FlowDirection), host point per align (center, start, end).
-- Lines always run in entry order; the block is aligned by its host point.
local FLOW={
    [false]={{"TOPLEFT",1,-1,{"TOP","TOPLEFT","TOPRIGHT"}},{"BOTTOMLEFT",1,1,{"BOTTOM","BOTTOMLEFT","BOTTOMRIGHT"}}},
    [true]={{"TOPLEFT",1,-1,{"LEFT","TOPLEFT","BOTTOMLEFT"}},{"TOPRIGHT",-1,-1,{"RIGHT","TOPRIGHT","BOTTOMRIGHT"}}},
}
-- Every field Look writes: the signature changes exactly when a button needs restyling.
local LOOK={"w","h","px","bw","er","eg","eb","l","r","t","b","font","flags","rendering","shadow","shadowOpacity",
    "shadowDistance","cs","ss","sp","cr","cg","cb","sr","sg","sb","swipe","edge","tip","tex","fr","fg","fb","bgA","icon","side"}

local live={}     -- live[slot] = { aura = {player=rec,target=rec}, over = {...} }
local pools={}    -- retired container records per bar
local meta={}     -- per aura bar: role, fixed mode and look (placeholders)
local holders={}  -- placeholder regions per cell frame
local targets={}  -- live target containers, refreshed on retarget
local overIcon={} -- cooldown icon -> bar slot, for icons that carry an overlay
local unseen={}   -- bar slot -> true while Visibility hides the bar
local list,where,cand,lay,sig,geo,flushing={},{},{},{},{},{},{}
local groupOpts,slotOpts={maxFrameCount=1},{}
local textOpts={}
local countOpts={} -- stack text options per (N, color); false without the API
local barOpts={}   -- SetApplicationBar options (Blizzard copies them)
local need={}      -- bindings the bar being synced asks for: glow, stack, kit
local sensed={}    -- kit sensor frame -> its button record
local watching={}  -- ancestor watch frame -> its kit container record
local stamp=0
local debounced=false

------------------------------------------------------------------ helpers
local Px=K.Px
local function Snap(value,px) return floor(value/px+.5)*px end

-- Blizzard_AuraContainer is preloaded on Retail and Forever; checked once
-- because CreateFrame with an unknown frame type raises.
local function Available()
    if A.available==nil then
        local addons=_G.C_AddOns
        A.available=type(_G.AuraContainerInbound)=="table"
            or (addons and type(addons.IsAddOnLoaded)=="function" and addons.IsAddOnLoaded("Blizzard_AuraContainer")==true)
            or false
    end
    return A.available
end

local ClassRGB=K.ClassRGB

local function SameSet(a,b)
    for id in pairs(a) do if not b[id] then return false end end
    for id in pairs(b) do if not a[id] then return false end end
    return true
end
local function CopySet(into,from)
    wipe(into)
    for id in pairs(from) do into[id]=true end
    return into
end

-- includeSpellIDs of an entry: Resolve gives every aura entry (and every
-- cooldown with an aura) its auraIDs; callers copy what they keep.
local function Ids(e)
    local map=e.auraIDs
    if type(map)=="table" and next(map)~=nil then return map end
end

-- The unit Resolve gave the entry (harmful IDs: target, else player; a
-- per-spell "Track on" choice wins). "both": the player and the target
-- container.
local function UnitOf(e) return e.unit or "player" end
local function OnUnit(e,unit)
    local u=UnitOf(e)
    return u==unit or u=="both"
end
-- Own harmful auras on a friendly target bypass spell-ID filters (Blizzard's
-- identity rule), so target containers pause while the target is friendly.
local function FriendlyTarget()
    local assist=UnitCanAssist and UnitCanAssist("player","target")
    return Public(assist) and assist==true
end
-- Own helpful auras (any caster for custom "a" entries) or own harmful
-- auras on the target.
local function FilterOf(e,unit)
    if unit=="target" then return HARM_MINE end
    return e.src=="a" and HELP_ANY or HELP_MINE
end
-- The part of an aura bar an entry takes: e.unit=="target" entries the
-- target part; a per-spell "both" counts in the player part. Player and
-- target auras live in two containers that cannot interleave (and Blizzard
-- forbids anchoring one AuraContainer to another); Layout.FixedAuras is the
-- one rule for how the two parts are arranged.
local function TargetRow(e)
    return e.unit=="target"
end
A.UnitOf,A.Ids,A.TargetRow=UnitOf,Ids,TargetRow

-- Duration text options per (threshold, warning color): a binding template
-- that Blizzard copies into each button. The fallbacks must ride on the
-- binding, and without a formatter on it no text renders at all.
local function TextOpts(seconds)
    local st=C.state
    if type(seconds)~="number" or seconds<=0 then seconds=0 else seconds=floor(seconds+.5) end
    local R,G,B=0,0,0
    if seconds>0 then R,G,B=floor((st.thR or 1)*255+.5),floor((st.thG or 1)*255+.5),floor((st.thB or 1)*255+.5) end
    local key=seconds*16777216+R*65536+G*256+B
    local opts=textOpts[key]
    if opts then return opts end
    opts=TEXT_DEFAULT
    local util,strings=_G.C_DurationUtil,_G.C_StringUtil
    if type(util)=="table" and type(util.CreateDurationTextBinding)=="function"
        and type(strings)=="table" and type(strings.CreateNumericRuleFormatter)=="function" then
        local points={{threshold=0,format="%.0f",rounding=UP}}
        if seconds>0 then
            points[1].format=("|cff%02x%02x%02x%%.0f|r"):format(R,G,B)
            points[2]={threshold=seconds,format="%.0f",rounding=UP}
        end
        points[#points+1]={threshold=60,format="%d:%02d",rounding=DOWN,components={{div=60,rounding=DOWN},{mod=60,rounding=DOWN}}}
        points[#points+1]={threshold=3600,format="%dh",rounding=DOWN,components={{div=3600,rounding=DOWN}}}
        local formatter=strings.CreateNumericRuleFormatter()
        if formatter.SetBreakpoints then formatter:SetBreakpoints(points)
        else for i=1,#points do formatter:AddBreakpoint(points[i]) end end
        local binding=util.CreateDurationTextBinding()
        binding:SetFormatter(formatter)
        binding:SetZeroDurationText("")
        binding:SetExpiredText("")
        binding:SetUpdateInterval(.1)
        binding:SetEnabled(true)
        opts={binding=binding}
    end
    textOpts[key]=opts
    return opts
end

-- Stack text options per (stackColorAt, stackColor): one formatter per
-- signature, shared by every button. Nothing below two applications (like
-- Blizzard's default), plain from two, colored from N (N = 1 colors a
-- single application too). nil: the plain binding (off, or no formatter).
local function CountOpts(ov)
    local n=ov.stackColorAt
    if type(n)~="number" or n<1 then return nil end
    n=floor(n)
    local hex=ov.stackColor or STACK_COLOR
    local rgb=type(hex)=="string" and #hex==6 and tonumber(hex,16)
    if not rgb then return nil end
    local key=n*16777216+rgb
    local opts=countOpts[key]
    if opts~=nil then return opts or nil end
    opts=false
    local strings=_G.C_StringUtil
    local make=strings and strings.CreateNumericRuleFormatter
    if type(make)=="function" then
        local formatter=make()
        if formatter and formatter.SetBreakpoints then
            local points={{threshold=0,format=""}}
            if n>2 then points[2]={threshold=2,format="%d"} end
            points[#points+1]={threshold=n,format="|cff"..hex.."%d|r"}
            formatter:SetBreakpoints(points)
            opts={formatter=formatter}
        end
    end
    countOpts[key]=opts
    return opts or nil
end

------------------------------------------------------------------ look
-- Every visual value of a container's buttons in rec.lk; the returned
-- string changes exactly when a button needs restyling.
local function Look(rec,view)
    local st,lk,bar=C.state,rec.lk,rec.role=="bar"
    local px=Px()
    local w,h
    if bar then
        w,h=max(px,Snap(view.barWidth or 200,px)),max(px,Snap(view.barHeight or 18,px))
    else
        local size=view.size or 36
        w,h=max(px,Snap(size,px)),max(px,Snap(size*(view.height or 100)/100,px))
    end
    local bw=floor(view.border or (bar and 1 or 0))*px
    lk.w,lk.h,lk.px,lk.bw=w,h,px,bw
    local r,g,b
    if view.borderClass then r,g,b=ClassRGB() end
    if not r then r,g,b=view.borderR or 0,view.borderG or 0,view.borderB or 0 end
    lk.er,lk.eg,lk.eb=r,g,b
    -- Same crop as the cooldown icons (a bar's icon is square).
    local iw,ih=w-2*bw,h-2*bw
    if bar then iw=ih end
    lk.l,lk.r,lk.t,lk.b=K.Crop(view.zoom,iw,ih)
    lk.font,lk.flags=st.font,st.fontFlags
    lk.rendering,lk.shadow,lk.shadowOpacity,lk.shadowDistance=
        st.fontRendering,st.fontShadow,st.fontShadowOpacity,st.fontShadowDistance
    local cs,ss=view.cdSize or 0,view.stackSize or 0
    if cs<=0 then cs=bar and max(9,floor(h*.55)) or max(10,floor(h*.38)) end
    if ss<=0 then ss=bar and max(8,floor(h*.45)) or max(9,floor(h*.3)) end
    lk.cs,lk.ss=cs,ss
    local pos=view.stackPos
    lk.sp=(pos and K.POINTS[pos]) and pos or 9
    lk.cr,lk.cg,lk.cb=st.cdR or 1,st.cdG or 1,st.cdB or 1
    lk.sr,lk.sg,lk.sb=st.stackR or 1,st.stackG or 1,st.stackB or 1
    lk.swipe=(view.swipeAlpha or 60)/100
    lk.edge=view.edge==true
    lk.tip=view.tooltips==true
    if bar then
        lk.tex=S.ResolveTexture(view.barTexture,BAR_TEXTURE)
        r,g,b=nil,nil,nil
        if view.barClass~=false then r,g,b=ClassRGB() end
        if not r then r,g,b=view.barR or .91,view.barG or .72,view.barB or .33 end
        lk.fr,lk.fg,lk.fb=r,g,b
        lk.bgA=(view.barBgAlpha or 55)/100
        lk.icon=view.barIcon~=false
        lk.side=view.barIconSide==2 and 2 or 1
    end
    for i=1,#LOOK do
        local v=lk[LOOK[i]]
        if v==true then v=1 elseif not v then v=0 end
        sig[i]=v
    end
    return tconcat(sig,"\031",1,#LOOK)
end

------------------------------------------------------------------ buttons
local function Edges(owner)
    local set={}
    for i=1,4 do set[i]=owner:CreateTexture(nil,"OVERLAY") end
    return set
end

------------------------------------------------------------------ glows
-- One glow on an aura button, built in initializeFrame: a flipbook texture
-- for styles 1 and 2 and four edges on their own frame for 3 (pulsing) and
-- 4 (still). Both loops run in C. The flipbook rests at alpha 0 and only
-- its loop lifts it, so a stopped loop never shows the whole sheet. 12.1.5
-- and Forever play the loops each time the button shows and stop them when
-- it hides (AddAuraShownAnimation); 12.1.0 has only the start given here.
local function NewGlow(button,parent,level)
    local frame=CreateFrame("Frame",nil,parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(level)
    frame:Hide()
    local flip=frame:CreateTexture(nil,"OVERLAY")
    flip:SetPoint("CENTER",frame,"CENTER",0,0)
    flip:SetAlpha(0)
    flip:Hide()
    local loop=flip:CreateAnimationGroup()
    loop:SetLooping("REPEAT")
    local lift=loop:CreateAnimation("Alpha")
    lift:SetFromAlpha(1)
    lift:SetToAlpha(1)
    lift:SetDuration(FLIP.duration)
    local book=loop:CreateAnimation("FlipBook")
    book:SetFlipBookRows(FLIP.rows)
    book:SetFlipBookColumns(FLIP.cols)
    book:SetFlipBookFrames(FLIP.frames)
    book:SetFlipBookFrameWidth(0)
    book:SetFlipBookFrameHeight(0)
    book:SetDuration(FLIP.duration)
    local ring=CreateFrame("Frame",nil,frame)
    ring:SetAllPoints(frame)
    ring:Hide()
    local pulse=ring:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade=pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(1)
    fade:SetDuration(PULSE)
    local g={frame=frame,flip=flip,ring=ring,edges=Edges(ring),fade=fade}
    if button.AddAuraShownAnimation then
        button:AddAuraShownAnimation(loop)
        button:AddAuraShownAnimation(pulse)
    end
    loop:Play()
    pulse:Play()
    return g
end

-- Style, color (nil: the art's own gold) and the size of what the glow
-- surrounds. Same input: no call.
local function Painted(g,style,r,gg,b,lk)
    return g.st==style and g.cr==r and g.cg==gg and g.cb==b and g.w==lk.w and g.h==lk.h and g.px==lk.px
end
local function PaintGlow(g,style,r,gg,b,lk)
    if Painted(g,style,r,gg,b,lk) then return end
    local w,h,px=lk.w,lk.h,lk.px
    g.st,g.cr,g.cg,g.cb,g.w,g.h,g.px=style,r,gg,b,w,h,px
    local spec=GLOW[style] or FLIP
    if spec.atlas then
        -- Same margin on every side: bars get a band, not a stretched art.
        local grow=(spec.scale-1)*min(w,h)
        local flip=g.flip
        flip:SetAtlas(spec.atlas)
        flip:SetSize(w+grow,h+grow)
        -- Tinting a golden atlas needs it gray first.
        flip:SetDesaturated(r~=nil)
        if r then flip:SetVertexColor(r,gg,b) else flip:SetVertexColor(1,1,1) end
        flip:Show()
        g.ring:Hide()
    else
        K.PlaceEdges(g.edges,g.ring,(spec.edge or 2)*px,r or GOLD[1],gg or GOLD[2],b or GOLD[3],1)
        g.fade:SetToAlpha(spec.pulse and PULSE_LOW or 1)
        g.ring:Show()
        g.flip:Hide()
    end
end

-- Style and color of an entry's aura glows: per-spell choices first, then
-- the bar's (Build copies them to the record).
local function GlowSpec(rec,ov)
    local style=ov.glowStyle or rec.gStyle
    if not GLOW[style] then style=1 end
    local hex=ov.glowColor
    if hex then return style,K.HexRGB(hex) end
    if rec.gTint then return style,rec.gR,rec.gG,rec.gB end
    return style
end

-- Stack glow, built in initializeFrame. A gate that clips its children,
-- as large as the widest glow around the button; an invisible StatusBar
-- that Blizzard fills with the aura's applications (SetApplicationBar,
-- maximum N); and the glow host centered on the fill's right edge. The bar
-- is N travels long and ends at the gate's center, so from N applications
-- on the fill edge sits on the center and the glow on the button, and each
-- missing application moves it one travel (more than the gate is wide) to
-- the left, out of the gate. The count stays in C: no Lua compares it.
local function NewStack(button,level)
    local gate=CreateFrame("Frame",nil,button)
    gate:SetPoint("CENTER",button,"CENTER",0,0)
    gate:SetFrameLevel(level)
    gate:SetClipsChildren(true)
    gate:Hide()
    local bar=CreateFrame("StatusBar",nil,button)
    bar:SetStatusBarTexture(STACK_TEXTURE)
    bar:SetMinMaxValues(0,1)
    bar:SetValue(0)
    bar:SetAlpha(0)
    local host=CreateFrame("Frame",nil,gate)
    host:SetPoint("CENTER",bar:GetStatusBarTexture(),"RIGHT",0,0)
    local glow=NewGlow(button,host,level)
    glow.frame:Show()
    return {gate=gate,bar=bar,host=host,glow=glow}
end

-- Gate, bar and host for threshold n and the button's size. The bar's
-- range is Blizzard's: every apply sets it to 0..maxApplications.
local function Placed(s,n,lk) return s.n==n and s.w==lk.w and s.h==lk.h and s.px==lk.px end
local function PlaceStack(s,n,lk)
    if Placed(s,n,lk) then return end
    local w,h,px=lk.w,lk.h,lk.px
    s.n,s.w,s.h,s.px=n,w,h,px
    local grow=(REACH-1)*min(w,h)+2*px
    local gw,gh=w+grow,h+grow
    local travel=max(gw,gh)+2*px
    s.gate:SetSize(gw,gh)
    s.host:SetSize(w,h)
    local bar=s.bar
    bar:SetSize(travel*n,px)
    bar:ClearAllPoints()
    bar:SetPoint("LEFT",s.gate,"CENTER",-travel*n,0)
end

-- Unknown kit sounds of aura entries (AddAuraSound takes files only): a
-- sensor in the button hears it show (aura gained) and hide (aura lost).
-- The sound, mute, quiet window, pairing and throttle are the alert
-- layer's; the container record is the hush gate of its sensors.
local function Heard(sensor,which)
    local part=sensed[sensor]
    local rec=part and part.rec
    if not rec then return end
    local k=part.pos
    local e=rec.on[k] and rec.entry[k]
    -- Entries without a sound on the kit bar cost these reads only.
    local ov=e and e.ov
    if not ov or ov==EMPTY or not (ov.sound or ov.lossSound) then return end
    local alerts=C.Alerts
    if alerts and alerts.PlayAura then alerts.PlayAura(e.key,which,rec) end
end
local function Gained(sensor) Heard(sensor,"gain") end
local function Lost(sensor) Heard(sensor,"loss") end

-- Container switches show or hide buttons without an aura changing:
-- that container's sensors stay silent for a moment.
local function Hush(rec)
    if not rec.kit then return end
    local alerts=C.Alerts
    if alerts and alerts.Hush then alerts.Hush(rec) end
end
-- An ancestor of a kit container shown or hidden (the UI hidden for a
-- cinematic, the bar hidden): a plain frame beside the container on the
-- same host hears it and hushes the container.
local function Woke(watch)
    local rec=watching[watch]
    if rec then Hush(rec) end
end

-- Tainted code may touch sealed aura buttons only out of combat, while
-- auras are not secret and each button says so plainly.
local function Quiet()
    if InCombatLockdown() then return false end
    local secrets=_G.C_Secrets
    local should=secrets and secrets.ShouldAurasBeSecret
    if type(should)=="function" then
        local secret=should()
        if not Public(secret) or secret then return false end
    end
    return true
end
local function Open(button)
    local can=button.CanBeAccessedInContext
    if type(can)~="function" then return true end
    local ok=can(button)
    return Public(ok) and ok==true
end
local function Mutable(rec)
    if not Quiet() then return false end
    local parts=rec.parts
    for i=1,#parts do if not Open(parts[i].button) then return false end end
    return true
end

local function Text(fs,size,r,g,b,lk)
    S.SetStyledFont(fs,lk.font,size,lk.flags,lk.rendering,lk.shadow,lk.shadowOpacity,lk.shadowDistance)
    fs:SetTextColor(r,g,b)
end

-- Every region of one button from rec.lk; idempotent (init and restyle).
local function Style(rec,part)
    local lk,b=rec.lk,part.button
    local bw,px=lk.bw,lk.px
    if not rec.fixed then b:SetSize(lk.w,lk.h) end
    K.PlaceEdges(part.edges,b,bw,lk.er,lk.eg,lk.eb,1)
    local icon=part.icon
    icon:ClearAllPoints()
    if rec.role=="bar" then
        local left=lk.side==1
        local inner=lk.h-2*bw
        local point=left and "TOPLEFT" or "TOPRIGHT"
        icon:SetPoint(point,b,point,left and bw or -bw,-bw)
        icon:SetSize(inner,inner)
        icon:SetShown(lk.icon)
        local lead=lk.icon and lk.h or bw
        local bg,bar=part.bg,part.bar
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT",b,"TOPLEFT",bw,-bw)
        bg:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-bw,bw)
        bg:SetTexture(lk.tex)
        bg:SetVertexColor(lk.fr*.25,lk.fg*.25,lk.fb*.25,lk.bgA)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT",b,"TOPLEFT",left and lead or bw,-bw)
        bar:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",left and -bw or -lead,bw)
        bar:SetStatusBarTexture(lk.tex)
        bar:SetStatusBarColor(lk.fr,lk.fg,lk.fb,1)
        local dur,name=part.dur,part.name
        if dur then
            Text(dur,lk.cs,lk.cr,lk.cg,lk.cb,lk)
            dur:ClearAllPoints()
            dur:SetPoint("RIGHT",bar,"RIGHT",-4*px,0)
            dur:SetJustifyH("RIGHT")
        end
        if name then
            Text(name,lk.cs,lk.cr,lk.cg,lk.cb,lk)
            name:ClearAllPoints()
            -- Room for the time text without anchoring to a sealed string.
            name:SetPoint("LEFT",bar,"LEFT",4*px,0)
            name:SetPoint("RIGHT",bar,"RIGHT",dur and -floor(lk.cs*2.6+.5) or -4*px,0)
            name:SetJustifyH("LEFT")
            name:SetWordWrap(false)
        end
    else
        icon:SetPoint("TOPLEFT",b,"TOPLEFT",bw,-bw)
        icon:SetPoint("BOTTOMRIGHT",b,"BOTTOMRIGHT",-bw,bw)
        local cd=part.cd
        if rec.role=="over" then
            cd:SetSwipeColor(GOLD[1],GOLD[2],GOLD[3],.55)
            cd:SetDrawEdge(false)
        else
            cd:SetSwipeColor(0,0,0,lk.swipe)
            cd:SetDrawEdge(lk.edge)
        end
        local dur=part.dur
        if dur then
            Text(dur,lk.cs,lk.cr,lk.cg,lk.cb,lk)
            dur:ClearAllPoints()
            dur:SetPoint("CENTER",icon,"CENTER",0,0)
        end
    end
    icon:SetTexCoord(lk.l,lk.r,lk.t,lk.b)
    local count,pos=part.count,lk.sp
    local point,inset=K.POINTS[pos],px+bw
    Text(count,lk.ss,lk.sr,lk.sg,lk.sb,lk)
    count:ClearAllPoints()
    count:SetPoint(point,icon,point,K.POINT_X[pos]*inset,K.POINT_Y[pos]*inset)
    count:SetJustifyH(K.JUSTIFY[pos])
    if part.pan then K.PlaceEdges(part.panEdges,part.pan,max(2*px,bw),PANDEMIC[1],PANDEMIC[2],PANDEMIC[3],1) end
    if b.SetMouseMotionEnabled then b:SetMouseMotionEnabled(lk.tip) end
end

-- Glow while active: shown and painted per entry.
local function ApplyGlow(rec,part,ov,dry)
    local g=part.glow
    local on=ov.auraGlow
    if on==nil then on=rec.glowAll end
    if on==true then
        local style,r,gg,b=GlowSpec(rec,ov)
        if part.gOn and Painted(g,style,r,gg,b,rec.lk) then return false end
        if dry then return true end
        PaintGlow(g,style,r,gg,b,rec.lk)
        if not part.gOn then part.gOn=true;g.frame:Show() end
    elseif part.gOn then
        if dry then return true end
        part.gOn=false
        g.frame:Hide()
    end
    return false
end

-- Stack glow from N applications: gate shown, bar and glow placed for N.
-- A bound bar is rebound when N changes (a setter replaces its element).
local function ApplyStack(rec,part,ov,dry)
    local s=part.stack
    local n=ov.stackGlow
    if type(n)~="number" or n<1 then n=0 else n=floor(n) end
    if n==0 then
        if not s.on then return false end
        if dry then return true end
        s.on=false
        s.gate:Hide()
        return false
    end
    local lk=rec.lk
    local style,r,gg,b=GlowSpec(rec,ov)
    if s.on and Placed(s,n,lk) and Painted(s.glow,style,r,gg,b,lk) and (s.bound==n or not part.bound) then return false end
    if dry then return true end
    PlaceStack(s,n,lk)
    PaintGlow(s.glow,style,r,gg,b,lk)
    if part.bound and s.bound~=n then
        s.bound=n
        barOpts.maxApplications=n
        part.button:SetApplicationBar(s.bar,barOpts)
    end
    if not s.on then s.on=true;s.gate:Show() end
    return false
end

-- Text on top: the two text frames trade levels (both stay above the glows).
local function Layer(part,top)
    local stacks,texts=part.stackFrame,part.timeFrame
    local a,b=stacks:GetFrameLevel(),texts:GetFrameLevel()
    if a>b then a,b=b,a end
    if top then stacks:SetFrameLevel(b);texts:SetFrameLevel(a) else stacks:SetFrameLevel(a);texts:SetFrameLevel(b) end
end

-- Per-spell choices on one button: swipe mode, glows, stack text (shown,
-- color), countdown (shown, warning threshold) and which is on top. With
-- dry set it only reports whether a write is needed. Unbound
-- (initializeFrame) it prepares what the binding takes. Hidden text is
-- never bound: a bound one is cleared, then hidden by hand.
local function ApplyEntry(rec,part,e,dry)
    local ov=e.ov or EMPTY
    local cd=part.cd
    if cd and rec.role=="icon" then
        local mode=ov.swipe or 1
        if part.swipe~=mode then
            if dry then return true end
            part.swipe=mode
            -- 1 normal (aura swipes run reversed), 2 flipped, 3 hidden.
            cd:SetReverse(mode~=2)
            cd:SetDrawSwipe(mode~=3)
        end
    end
    if part.glow and ApplyGlow(rec,part,ov,dry) then return true end
    if part.stack and ApplyStack(rec,part,ov,dry) then return true end
    local b=part.button
    local stacks=K.Choice(ov.stackText,rec.stackBar)
    local count=stacks and CountOpts(ov) or nil
    if part.countOn~=stacks or part.countOpts~=count then
        if dry then return true end
        local was=part.countOn
        part.countOn,part.countOpts=stacks,count
        if not stacks then
            if part.bound and was then b:ClearApplicationCount() end
            part.count:Hide()
        else
            if was==false then part.count:Show() end
            if part.bound then b:SetApplicationCount(part.count,count) end
        end
    end
    local dur=part.dur
    if dur then
        local shown=K.Choice(ov.timeText,rec.timeBar)
        if part.durOn~=shown then
            if dry then return true end
            local was=part.durOn
            part.durOn=shown
            if not shown then
                if part.bound and was then b:ClearDurationText() end
                part.textOpts=nil
                dur:Hide()
            elseif was==false then
                dur:Show()
            end
        end
        if shown and part.bound then
            local opts=TextOpts(ov.threshold or C.state.threshold)
            if part.textOpts~=opts then
                if dry then return true end
                part.textOpts=opts
                b:SetDurationText(dur,opts)
            end
        end
    end
    local top=K.Choice(ov.textTop,rec.topBar)
    if part.top~=top then
        if dry then return true end
        part.top=top
        Layer(part,top)
    end
    return false
end

-- initializeFrame: runs once per button from Blizzard's frame provider
-- (possibly in combat when a group's pool grows). Builds and styles every
-- region as a descendant of the button, binds last (bound regions are
-- sealed), and keeps our state in our own table, never on the button.
local function Init(rec,button,k)
    local part={button=button,pos=k,rec=rec}
    part.edges=Edges(button)
    part.icon=button:CreateTexture(nil,"ARTWORK")
    local lower
    if rec.role=="bar" then
        part.bg=button:CreateTexture(nil,"BACKGROUND")
        lower=CreateFrame("StatusBar",nil,button)
        lower:SetMinMaxValues(0,1)
        lower:SetValue(0)
        part.bar=lower
    else
        lower=CreateFrame("Cooldown",nil,button,"CooldownFrameTemplate")
        lower:SetAllPoints(part.icon)
        lower:SetDrawBling(false)
        lower:SetHideCountdownNumbers(true)
        lower:SetReverse(true)
        part.cd=lower
    end
    -- Glows over the icon and swipe, text above the glows.
    local level=lower:GetFrameLevel()+1
    if rec.pandemic then
        local pan=CreateFrame("Frame",nil,button)
        pan:SetAllPoints(button)
        pan:SetFrameLevel(level)
        pan:Hide()
        part.pan,part.panEdges=pan,Edges(pan)
    end
    if rec.glow then part.glow=NewGlow(button,button,level) end
    if rec.stack then part.stack=NewStack(button,level) end
    -- Stacks and countdown (with the name) on two frames above the glows,
    -- stacks on top until the entry's Text on top says otherwise.
    local stacks=CreateFrame("Frame",nil,button)
    stacks:SetAllPoints(button)
    stacks:SetFrameLevel(level+2)
    local texts=CreateFrame("Frame",nil,button)
    texts:SetAllPoints(button)
    texts:SetFrameLevel(level+1)
    part.stackFrame,part.timeFrame,part.top=stacks,texts,true
    part.count=stacks:CreateFontString(nil,"OVERLAY")
    if rec.text then part.dur=texts:CreateFontString(nil,"OVERLAY") end
    if rec.name then part.name=texts:CreateFontString(nil,"OVERLAY") end
    if rec.kit then
        -- A new button hides once it is set up: not an aura leaving.
        Hush(rec)
        local sensor=CreateFrame("Frame",nil,button)
        sensor:SetAllPoints(button)
        sensed[sensor]=part
        sensor:SetScript("OnShow",Gained)
        sensor:SetScript("OnHide",Lost)
    end
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
    if button.SetTooltipAnchorPoint then button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT") end
    -- Slots are outside the flow layout: they follow their cell or icon.
    if rec.fixed then
        button:ClearAllPoints()
        button:SetAllPoints(rec.anchors[k])
    end
    Style(rec,part)
    ApplyEntry(rec,part,rec.entry[k] or NO_ENTRY,false)
    button:SetIcon(part.icon)
    if part.cd then button:SetDurationCooldown(part.cd) end
    if part.bar then button:SetDurationBar(part.bar,BAR_OPTS[rec.fill]) end
    if part.dur and part.durOn then
        local opts=rec.topts[k] or TEXT_DEFAULT
        button:SetDurationText(part.dur,opts)
        part.textOpts=opts
    end
    if part.name then button:SetSpellName(part.name) end
    -- Without a formatter Blizzard shows stacks above 1 only; the per-spell
    -- stack color passes a shared formatter (CountOpts).
    if part.countOn then button:SetApplicationCount(part.count,part.countOpts) end
    local stack=part.stack
    if stack then
        stack.bound=stack.n or 1
        barOpts.maxApplications=stack.bound
        button:SetApplicationBar(stack.bar,barOpts)
    end
    -- 12.1.5 and Forever return nothing here; the result is never used.
    if part.pan and button.AddPandemicRegion then button:AddPandemicRegion(part.pan) end
    part.bound=true
    local parts=rec.parts
    parts[#parts+1]=part
end

------------------------------------------------------------------ groups and slots
-- A group or slot shows while the build wants it (on) and, for overlays,
-- while the layout shows its cooldown icon (not shut). Container-level
-- switches only: legal at any time, in combat too; unchanged state makes
-- no call. 12.1.0 slots have no enable flag: an off slot carries NONE as
-- its candidate filters and gets its spell list back when it comes on.
local function Apply(rec,k)
    local on=rec.on[k]==true and not rec.shut[k]
    if rec.act[k]==on then return end
    rec.act[k]=on
    local c,key=rec.frame,rec.keys[k]
    if rec.fixed then
        if c.SetAuraSlotEnabled then c:SetAuraSlotEnabled(key,on)
        elseif on then
            cand.includeSpellIDs=rec.ids[k]
            c:SetAuraSlotCandidateFilters(key,cand)
            cand.includeSpellIDs=nil
        else c:SetAuraSlotCandidateFilters(key,NONE) end
    elseif c.SetAuraGroupEnabled then c:SetAuraGroupEnabled(key,on)
    else c:SetAuraGroupMaxFrameCount(key,on and 1 or 0) end
end

local function Update(rec,k,e,f,set)
    local c,key,fixed=rec.frame,rec.keys[k],rec.fixed
    local have=rec.ids[k]
    -- Spell list first, then the filter string: the group never passes
    -- through a state without its spell list. A 12.1.0 slot that is off
    -- keeps NONE until Apply hands it the list.
    if not SameSet(have,set) then
        CopySet(have,set)
        if not fixed or c.SetAuraSlotEnabled or rec.act[k] then
            cand.includeSpellIDs=have
            if fixed then c:SetAuraSlotCandidateFilters(key,cand) else c:SetAuraGroupCandidateFilters(key,cand) end
            cand.includeSpellIDs=nil
        end
    end
    if rec.filter[k]~=f then
        rec.filter[k]=f
        if fixed then c:SetAuraSlotFilterString(key,f) else c:SetAuraGroupFilterString(key,f) end
    end
    rec.on[k],rec.entry[k]=true,e
    Apply(rec,k)
end

-- One-frame groups: the gap between them is group spacing (only positive
-- values apply), the line gap follows the bar spacing.
local function GroupLayout(rec,index)
    lay.elementWidth,lay.elementHeight=rec.gw,rec.gh
    lay.elementSpacing,lay.lineSpacing=0,rec.gc
    lay.groupSpacing,lay.groupLineSpacing=rec.gp,rec.gc
    lay.layoutIndex=index
    return lay
end

-- Brings a container to list[1..n]: compact mode keys groups by position,
-- fixed mode keys slots by their anchor (cell or cooldown icon). Returns
-- false when sealed buttons would need a write they refuse.
local function Build(rec,view,n)
    local c,fixed,over,slot=rec.frame,rec.fixed,rec.fam=="over",rec.slot
    local look=Look(rec,view)
    local parts=rec.parts
    if parts[1]==nil then rec.look=look end
    -- Bar-level glow and text choices behind the per-spell ones.
    rec.glowAll=view.auraGlow==true
    rec.gStyle,rec.gTint=view.glowStyle,view.glowTint==true
    rec.gR,rec.gG,rec.gB=view.glowR or 1,view.glowG or 1,view.glowB or 1
    rec.timeBar,rec.stackBar,rec.topBar=K.BarTime(view),K.BarStacks(view,false),K.BarStacksTop(view)
    local threshold=C.state.threshold
    local keys=rec.keys
    stamp=stamp+1
    for i=1,n do
        local e=list[i]
        local set,f=Ids(e),FilterOf(e,rec.unit)
        local k
        if fixed then
            local anchor=over and e.icon or C.Layout.Cell(slot,where[i])
            k=rec.byAnchor[anchor]
            if not k then
                k=#keys+1
                keys[k]=rec.prefix..k
                rec.byAnchor[anchor],rec.anchors[k]=k,anchor
            end
            -- An overlay starts from the layout's shown state of its icon
            -- (layShown); the layout reports every change (A.OverlayShown).
            if over then overIcon[anchor]=slot;rec.shut[k]=anchor.layShown~=true end
        else
            k=i
            if not keys[k] then keys[k]=rec.prefix..k end
        end
        rec.mark[k]=stamp
        if rec.text then rec.topts[k]=TextOpts((e.ov or EMPTY).threshold or threshold) end
        if rec.ids[k] then
            Update(rec,k,e,f,set)
            if not fixed and (rec.li[k]~=e.index or rec.lg[k]~=rec.geo) then
                rec.li[k],rec.lg[k]=e.index,rec.geo
                c:SetAuraGroupLayout(keys[k],GroupLayout(rec,e.index))
            end
        else
            rec.entry[k],rec.filter[k],rec.ids[k],rec.on[k],rec.act[k]=e,f,CopySet({},set),true,true
            cand.includeSpellIDs=set
            local function init(button) Init(rec,button,k) end
            if fixed then
                slotOpts.candidateFilters,slotOpts.initializeFrame=cand,init
                c:AddAuraSlot(keys[k],f,slotOpts)
            else
                rec.li[k],rec.lg[k]=e.index,rec.geo
                groupOpts.candidateFilters,groupOpts.initializeFrame,groupOpts.layout=cand,init,GroupLayout(rec,e.index)
                c:AddAuraGroup(keys[k],f,groupOpts)
            end
            cand.includeSpellIDs=nil
            slotOpts.initializeFrame,groupOpts.initializeFrame=nil,nil
            -- An overlay on a hidden icon starts off.
            Apply(rec,k)
        end
    end
    for k=1,#keys do
        if rec.on[k] and rec.mark[k]~=stamp then rec.on[k]=false;Apply(rec,k) end
    end
    local restyle=rec.look~=look
    local dirty=restyle
    if not dirty then
        for i=1,#parts do
            local part=parts[i]
            local e=rec.on[part.pos] and rec.entry[part.pos]
            if e and ApplyEntry(rec,part,e,true) then dirty=true;break end
        end
    end
    if not dirty then return true end
    if not Mutable(rec) then return false end
    for i=1,#parts do
        local part=parts[i]
        if restyle then Style(rec,part) end
        local e=rec.on[part.pos] and rec.entry[part.pos]
        if e then ApplyEntry(rec,part,e,false) end
    end
    rec.look=look
    return true
end

------------------------------------------------------------------ containers
-- A container shows unless its bar is hidden (SetBarMouse) or, in the
-- preview, it is a compact aura container (the preview draws every entry
-- on its cell instead). Container widget writes: legal in combat.
local function Show(rec)
    local shown=not (unseen[rec.slot] or (A.preview and rec.fam=="aura" and not rec.fixed))
    if rec.shown~=shown then
        rec.shown=shown
        Hush(rec)
        rec.frame:SetShown(shown)
    end
end

local function Bar(slot)
    local bar=C.bars[slot]
    if not bar and C.Layout and C.Layout.EnsureBar then bar=C.Layout.EnsureBar(slot) end
    return bar and bar.frame and bar or nil
end

local function Retire(slot,fam,unit)
    local fams=live[slot]
    local byUnit=fams and fams[fam]
    local rec=byUnit and byUnit[unit]
    if not rec then return end
    byUnit[unit]=nil
    rec.enabled,rec.shown=false,false
    Hush(rec)
    rec.frame:SetEnabled(false)
    rec.frame:Hide()
    -- Every retired container stays reusable: it cannot be freed, so one
    -- dropped from the pool would only be replaced by a new one.
    local pool=pools[slot]
    if not pool then pool={};pools[slot]=pool end
    pool[#pool+1]=rec
end

-- Same unit first: a unit switch costs the container a full rebuild. Taken
-- even while buttons are sealed: the structure applies at once and the
-- look follows when they open.
local function Acquire(slot,fam,bind,unit)
    local pool=pools[slot]
    if not pool then return nil end
    for pass=1,2 do
        for i=#pool,1,-1 do
            local rec=pool[i]
            if rec.fam==fam and rec.bind==bind and (pass==2 or rec.unit==unit) then tremove(pool,i);return rec end
        end
    end
end

-- The live container of one bar, family and unit. Regions are made at
-- button creation, so a change of region set (mode, countdown text, name,
-- pandemic, glow, stack glow, kit sensor, bar direction) swaps containers;
-- `need` says which the bar's entries ask for. fresh: a new container for
-- buttons that refused a restyle (a pooled one would refuse it too).
local function Ensure(slot,fam,unit,role,fixed,view,fresh)
    local bar=Bar(slot)
    if not bar then return nil end
    local fams=live[slot]
    if not fams then fams={aura={},over={}};live[slot]=fams end
    local byUnit=fams[fam]
    local text,name,fill=need.text==true,false,1
    if role=="bar" then name,fill=view.barName~=false,view.barFill==2 and 2 or 1 end
    local pan=fam=="aura" and view.pandemic==true
    local glow=fam=="aura" and (view.auraGlow==true or need.glow==true)
    local stack,kit=need.stack==true,fam=="aura" and need.kit==true
    local bind=(fixed and "s" or "g")..role..(text and 1 or 0)..(name and 1 or 0)..(pan and 1 or 0)..(glow and 1 or 0)
        ..(stack and 1 or 0)..(kit and 1 or 0)..fill
    local rec=byUnit[unit]
    if rec and rec.bind~=bind then Retire(slot,fam,unit);rec=nil end
    if not rec then
        if not fresh then rec=Acquire(slot,fam,bind,unit) end
        if not rec then
            local parent=fam=="over" and bar.frame or bar.auraHost or bar.frame
            local c=CreateFrame("AuraContainer",nil,parent,"CustomAuraContainerTemplate")
            if not c then return nil end
            -- 12.1.5 and Forever: no fake Edit Mode auras in our bars.
            if c.SetEditModePreviewEnabled then c:SetEditModePreviewEnabled(false) end
            if fixed then c:SetPoint("TOPLEFT",parent,"TOPLEFT",0,0) end
            rec={frame=c,slot=slot,fam=fam,role=role,fixed=fixed,bind=bind,prefix=fixed and "s" or "g",
                text=text,name=name,pandemic=pan,glow=glow,stack=stack,kit=kit,fill=fill,geo=0,
                keys={},on={},act={},shut={},filter={},ids={},entry={},anchors={},byAnchor={},topts={},li={},lg={},
                mark={},parts={},lk={}}
            if kit then
                local watch=CreateFrame("Frame",nil,parent)
                watch:SetAllPoints(parent)
                watching[watch]=rec
                watch:SetScript("OnShow",Woke)
                watch:SetScript("OnHide",Woke)
            end
        end
        byUnit[unit]=rec
    end
    local c=rec.frame
    local level=bar.frame:GetFrameLevel()+(fam=="over" and OVER_LEVEL or AURA_LEVEL)
    if rec.level~=level then rec.level=level;c:SetFrameLevel(level) end
    local strata=STRATA[view.strata] or "MEDIUM"
    if rec.strata~=strata then rec.strata=strata;c:SetFrameStrata(strata) end
    if rec.unit~=unit then rec.unit=unit;c:SetUnit(unit) end
    local enabled=not (unit=="target" and FriendlyTarget())
    if rec.enabled~=enabled then rec.enabled=enabled;c:SetEnabled(enabled) end
    Show(rec)
    return rec
end

-- Compact containers: flow layout and host anchor from geo; the target row
-- starts `offset` lines further in growth direction. Container writes only.
local function Place(rec,offset,split)
    local c,g=rec.frame,geo
    if rec.gw~=g.w or rec.gh~=g.h or rec.gp~=g.gp or rec.gc~=g.gc then
        rec.gw,rec.gh,rec.gp,rec.gc=g.w,g.h,g.gp,g.gc
        rec.geo=rec.geo+1
    end
    if rec.axis~=g.axis then rec.axis=g.axis;c:SetFlowLayoutAxis(g.axis) end
    local flow=g.flow
    if rec.flowPoint~=flow[1] then rec.flowPoint=flow[1];c:SetFlowLayoutAnchorPoint(flow[1]) end
    if rec.hd~=flow[2] or rec.vd~=flow[3] then rec.hd,rec.vd=flow[2],flow[3];c:SetFlowLayoutGrowthDirection(flow[2],flow[3]) end
    if rec.line~=g.line then rec.line=g.line;c:SetFlowLayoutMaximumLineSize(g.line) end
    if not rec.padded then rec.padded=true;c:SetFlowLayoutPadding(0,0,0,0) end
    local dx,dy=0,0
    local point,host=g.point,g.host
    local rel=point
    if split then
        -- Centered row with both parts: player auras end at the center,
        -- target auras start there. Blizzard sizes each container to its
        -- shown auras, so both grow from the middle.
        rel=flow[1]:find("BOTTOM") and "BOTTOM" or "TOP"
        if split=="lead" then point,dx=rel.."RIGHT",-g.gp/2 else point,dx=rel.."LEFT",g.gp/2 end
    elseif g.vertical then dx=offset*g.step else dy=offset*g.step end
    if rec.pt~=point or rec.host~=host or rec.rel~=rel or rec.dx~=dx or rec.dy~=dy then
        rec.pt,rec.host,rec.rel,rec.dx,rec.dy=point,host,rel,dx,dy
        c:ClearAllPoints()
        c:SetPoint(point,host,rel,dx,dy)
    end
end

local function RefreshTargets()
    wipe(targets)
    for _,fams in pairs(live) do
        local rec=fams.aura.target
        if rec then targets[#targets+1]=rec end
        rec=fams.over.target
        if rec then targets[#targets+1]=rec end
    end
end

local function ReleaseFam(slot,fam)
    Retire(slot,fam,"player")
    Retire(slot,fam,"target")
end

-- hideReady of a cooldown entry, as the time layer reads it; placeholders
-- never hide.
local function Hides(e,view)
    if e.src=="p" then return false end
    local hide=(e.ov or EMPTY).hideReady
    if hide==nil then hide=view.hideReady==true end
    return hide==true
end

-- Entries of one unit a container shows, in plan order, into list/where.
-- Aura bars honor maxIcons like the layout does (every entry holds a place).
-- Overlays: the layout shows the first maxIcons visible icons, so an icon
-- behind maxIcons icons that never hide can never show and gets no slot;
-- every other overlay switches with its icon (A.OverlayShown).
local function Collect(plan,unit,over,view)
    local entries,n=plan.entries,0
    local cap=#entries
    local limit=view.maxIcons
    if type(limit)~="number" or limit<=0 then limit=nil end
    if not over and limit and limit<cap then cap=limit end
    local steady=0
    for i=1,cap do
        local e=entries[i]
        local ok
        if over then
            if e.icon then
                if limit and steady>=limit then break end
                if not Hides(e,view) then steady=steady+1 end
                if e.family==1 and e.hasAura and e.src~="p" and OnUnit(e,unit) then
                    ok=(e.ov or EMPTY).showAura
                    if ok==nil then ok=view.showAura==true end
                end
            end
        elseif e.src~="p" and OnUnit(e,unit) then
            ok=e.family~=1
        end
        if ok and Ids(e) then n=n+1;list[n],where[n]=e,i end
    end
    for i=#list,n+1,-1 do list[i],where[i]=nil,nil end
    return n
end

------------------------------------------------------------------ placeholders
-- Addon-owned regions on the cell, under the slot button: a dimmed icon
-- for missing buffs (showMissing) and the sample icon in the preview.
local function Unhold(cell)
    local h=cell and holders[cell]
    if h and h.shown then
        h.shown=false
        h.icon:Hide();h.bg:Hide();h.name:Hide()
    end
end
local function Unholds(slot)
    local bar=C.bars[slot]
    if not bar or not bar.cells then return end
    local cells=bar.cells
    for i=1,#cells do Unhold(cells[i]) end
end

local function Hold(cell,e,m,dim)
    local h=holders[cell]
    if not h then
        h={bg=S.CreateTexture(cell,nil,"BACKGROUND",nil,0),icon=S.CreateTexture(cell,nil,"BACKGROUND",nil,1),
            name=S.CreateFontString(cell,nil,"ARTWORK")}
        h.name:SetWordWrap(false)
        h.name:SetJustifyH("LEFT")
        holders[cell]=h
    end
    local tex=(e.ov or EMPTY).icon or e.texture or QUESTION
    if h.shown and h.e==e and h.tex==tex and h.look==m.look and h.dim==dim then return end
    h.shown,h.e,h.tex,h.look,h.dim=true,e,tex,m.look,dim
    local lk,icon=m.lk,h.icon
    local bw=lk.bw
    icon:SetTexture(tex)
    icon:SetTexCoord(lk.l,lk.r,lk.t,lk.b)
    icon:SetDesaturated(dim)
    icon:SetAlpha(dim and .5 or 1)
    icon:ClearAllPoints()
    if m.role=="bar" then
        local left=lk.side==1
        local point=left and "TOPLEFT" or "TOPRIGHT"
        icon:SetPoint(point,cell,point,left and bw or -bw,-bw)
        icon:SetSize(lk.h-2*bw,lk.h-2*bw)
        icon:SetShown(lk.icon)
        local bg,name=h.bg,h.name
        bg:ClearAllPoints()
        bg:SetAllPoints(cell)
        bg:SetTexture(lk.tex)
        bg:SetVertexColor(lk.fr*.25,lk.fg*.25,lk.fb*.25,dim and lk.bgA*.6 or lk.bgA)
        bg:Show()
        S.SetStyledFont(name,lk.font,lk.cs,lk.flags,lk.rendering,lk.shadow,lk.shadowOpacity,lk.shadowDistance)
        name:SetTextColor(lk.cr,lk.cg,lk.cb,dim and .6 or 1)
        name:ClearAllPoints()
        local lead=lk.icon and lk.h or 0
        name:SetPoint("LEFT",cell,"LEFT",(left and lead or 0)+4*lk.px,0)
        name:SetPoint("RIGHT",cell,"RIGHT",-(left and 0 or lead)-4*lk.px,0)
        name:SetText(e.name or "")
        name:Show()
    else
        icon:SetPoint("TOPLEFT",cell,"TOPLEFT",bw,-bw)
        icon:SetPoint("BOTTOMRIGHT",cell,"BOTTOMRIGHT",-bw,bw)
        icon:Show()
        h.bg:Hide()
        h.name:Hide()
    end
end

local function Placeholders(slot,view,plan,m)
    local layout,bar=C.Layout,C.bars[slot]
    if not (layout and layout.Cell and bar and bar.cells) then return end
    local preview=A.preview==true
    local entries=plan.entries
    local cap=#entries
    local limit=view.maxIcons
    if type(limit)=="number" and limit>0 and limit<cap then cap=limit end
    for i=1,cap do
        local e=entries[i]
        local show=preview
        if not show and m.fixed and e.src~="p" then
            show=(e.ov or EMPTY).showMissing
            if show==nil then show=view.showMissing==true end
        end
        if show then Hold(layout.Cell(slot,i),e,m,not preview) else Unhold(bar.cells[i]) end
    end
    local cells=bar.cells
    for i=cap+1,#cells do Unhold(cells[i]) end
end

------------------------------------------------------------------ sync
local function Debounced()
    debounced=false
    A.FlushPending()
end
-- Buttons that refuse a restyle while auras are plain get a new container,
-- batched so slider drags do not leak one per tick.
local function Debounce()
    local timer=_G.C_Timer
    if debounced or not (timer and timer.After) then return end
    debounced=true
    timer.After(.5,Debounced)
end

-- What a bar's entries ask of its buttons (need, read by Ensure): countdown
-- regions (the bar shows the countdown or a spell asks for it), a glow while
-- active, a stack glow, a sensor for kit sounds (aura bars only).
local function Needs(entries,aura,view)
    need.glow,need.stack,need.kit=false,false,false
    need.text=K.BarTime(view)
    local alerts=C.Alerts
    local isKit=alerts and alerts.IsKit
    for i=1,#entries do
        local e=entries[i]
        local ov=e.ov
        if ov and ov~=EMPTY and e.src~="p" then
            if ov.timeText==2 then need.text=true end
            local n=ov.stackGlow
            if type(n)=="number" and n>=1 then need.stack=true end
            if aura then
                if ov.auraGlow==true then need.glow=true end
                if isKit and (isKit(ov.sound) or isKit(ov.lossSound)) then need.kit=true end
            end
        end
    end
end

local function Run(slot,fam,unit,role,fixed,view,n,force,offset,split)
    local rec=Ensure(slot,fam,unit,role,fixed,view,false)
    if not rec then return end
    -- Filters, groups and new buttons change what shows: not aura events.
    Hush(rec)
    if not fixed then Place(rec,offset,split) end
    if Build(rec,view,n) then return end
    -- Sealed buttons refused the restyle; the structure is current. While
    -- auras are secret (M+ key, PvP match) the look waits for them to open
    -- (FlushPending): a new container per change would leak, since none is
    -- ever freed.
    local quiet=Quiet()
    if not (force and quiet) then
        A.pending[slot]=true
        if quiet then Debounce() end
        return
    end
    Retire(slot,fam,unit)
    rec=Ensure(slot,fam,unit,role,fixed,view,true)
    if not rec then return end
    if not fixed then Place(rec,offset,split) end
    Build(rec,view,n)
end

local function SyncAura(slot,view,plan,force)
    local role=plan.kind==3 and "bar" or "icon"
    local m=meta[slot]
    if not m then m={lk={}};meta[slot]=m end
    m.role=role
    m.look=Look(m,view)
    local entries=plan.entries
    Needs(entries,true,view)
    local layout=C.Layout
    -- One rule for the layout and the containers (Layout.FixedAuras).
    local fixed,_,split=false,nil,false
    if layout~=nil and layout.Cell~=nil and layout.FixedAuras~=nil then fixed,_,split=layout.FixedAuras(view,entries) end
    m.fixed,m.split=fixed==true,split==true
    local bar=Bar(slot)
    if not bar then return end
    if Available() then
        local w,h,sp,per,vertical,grow,align=layout.Metrics(view)
        vertical=vertical==true
        local flow=FLOW[vertical][grow==2 and 2 or 1]
        geo.w,geo.h,geo.gp,geo.gc=w,h,max(0,sp),sp
        geo.axis=vertical and 1 or 0
        geo.flow,geo.point=flow,flow[4][align] or flow[4][1]
        local primary,cross=w,h
        if vertical then primary,cross=h,w end
        geo.line=per*primary+(per-1)*geo.gp+.01
        geo.vertical=vertical
        local dir
        if vertical then dir=grow==2 and -1 or 1 else dir=grow==2 and 1 or -1 end
        geo.step=(cross+sp)*dir
        geo.host=bar.auraHost or bar.frame
        -- Target row starts after the player lines the layout reserves
        -- (every player-row entry within maxIcons, active or not).
        local cap=#entries
        local limit=view.maxIcons
        if type(limit)=="number" and limit>0 and limit<cap then cap=limit end
        local players=0
        for i=1,cap do if not TargetRow(entries[i]) then players=players+1 end end
        local lines=ceil(players/per)
        for u=1,2 do
            local unit=UNITS[u]
            local n=Collect(plan,unit,false,view)
            if n==0 then Retire(slot,"aura",unit)
            else
                local side=m.split and (u==1 and "lead" or "tail") or nil
                Run(slot,"aura",unit,role,m.fixed,view,n,force,(u==2 and not side) and lines or 0,side)
            end
        end
    end
    Placeholders(slot,view,plan,m)
end

-- Structural sync of one bar (aura bars and cooldown overlays alike). Out
-- of combat only; in combat the bar is marked pending for FlushPending.
function A.Sync(slot,force)
    local view,plan=C.views[slot],C.plans[slot]
    if not (view and plan and view.on) then A.Release(slot);return end
    if plan.kind==1 then
        if live[slot] then ReleaseFam(slot,"aura") end
        Unholds(slot)
        return A.SyncOverlays(slot,force)
    end
    if InCombatLockdown() then A.pending[slot]=true;return end
    A.pending[slot]=nil
    if live[slot] then ReleaseFam(slot,"over") end
    SyncAura(slot,view,plan,force)
    RefreshTargets()
end

-- Aura overlays on a cooldown bar: one slot per icon whose spell has an
-- aura, anchored to that icon. Needs the bar's icons (C.Icons.Sync) first.
function A.SyncOverlays(slot,force)
    local view,plan=C.views[slot],C.plans[slot]
    if not (view and plan and view.on and plan.kind==1 and Available()) then
        if live[slot] then ReleaseFam(slot,"over");RefreshTargets() end
        return
    end
    if InCombatLockdown() then A.pending[slot]=true;return end
    A.pending[slot]=nil
    Needs(plan.entries,false,view)
    for u=1,2 do
        local unit=UNITS[u]
        local n=Collect(plan,unit,true,view)
        if n==0 then Retire(slot,"over",unit)
        else Run(slot,"over",unit,"over",true,view,n,force,0) end
    end
    RefreshTargets()
end

-- Style changes use the same diffing: unchanged structure makes no calls.
function A.Restyle(slot) return A.Sync(slot) end

function A.Release(slot)
    if live[slot] then
        ReleaseFam(slot,"aura")
        ReleaseFam(slot,"over")
    end
    Unholds(slot)
    A.pending[slot]=nil
    RefreshTargets()
end

function A.ReleaseAll()
    for slot in pairs(live) do A.Release(slot) end
    for slot in pairs(meta) do Unholds(slot) end
    for slot in pairs(A.pending) do A.pending[slot]=nil end
end

-- Target containers pause while the target is friendly (FriendlyTarget).
-- SetEnabled is container-level (legal in combat), refreshes the container
-- when it turns on and makes no call while the state holds.
local function React()
    local enabled=not FriendlyTarget()
    for i=1,#targets do
        local rec=targets[i]
        if rec.enabled~=enabled then rec.enabled=enabled;Hush(rec);rec.frame:SetEnabled(enabled) end
    end
end
-- Same-token retarget fires no UNIT_AURA: each target container is told at
-- once. A container turning on reparses inside SetEnabled; a running one
-- is marked dirty by UpdateAllAuras and parses once when it next draws, so
-- several target events in one frame still cost one parse. The pause
-- starts at once, so a friendly target is never parsed. The new target's
-- auras are no gains or losses: kit sensors stay silent.
function A.TargetChanged()
    if targets[1]==nil then return end
    local enabled=not FriendlyTarget()
    for i=1,#targets do
        local rec=targets[i]
        Hush(rec)
        if rec.enabled~=enabled then rec.enabled=enabled;rec.frame:SetEnabled(enabled)
        elseif enabled then rec.frame:UpdateAllAuras() end
    end
end
-- UNIT_FACTION for the target (a duel starts, a charm ends): work only when
-- its disposition changed.
function A.TargetReaction()
    if targets[1]~=nil then React() end
end

-- An overlay slot follows its cooldown icon's position (SetAllPoints) but
-- is the container's child, so not its visibility. The layout calls this
-- on every change of an icon's shown state, the icon pool before it pools
-- an icon (icon given; its entry may be gone). The slot shows only while
-- its icon shows and still carries the entry the slot was built for.
-- Container-level calls only, legal in combat; unchanged state makes none;
-- an icon without an overlay costs two lookups.
function A.OverlayShown(entry,on,icon)
    icon=icon or (entry and entry.icon)
    local slot=icon and overIcon[icon]
    local fams=slot and live[slot]
    if not fams then return end
    local byUnit=fams.over
    for u=1,2 do
        local rec=byUnit[UNITS[u]]
        local k=rec and rec.byAnchor[icon]
        if k then
            local shut=not (on==true and entry~=nil and rec.entry[k]==entry)
            if rec.shut[k]~=shut then rec.shut[k]=shut;Apply(rec,k) end
        end
    end
end

-- Visibility, on every edge of a bar's hidden state (its rule hides it or
-- its opacity is 0): the bar's containers hide with it, so invisible
-- buttons take no mouse or tooltip and no aura work runs; shown again, a
-- container reparses at once (OnShow). Legal in combat.
function A.SetBarMouse(slot,on)
    local hidden=on~=true or nil
    if unseen[slot]==hidden then return end
    unseen[slot]=hidden
    local fams=live[slot]
    if not fams then return end
    for _,rec in pairs(fams.aura) do Show(rec) end
    for _,rec in pairs(fams.over) do Show(rec) end
end

-- PLAYER_REGEN_ENABLED, ADDON_RESTRICTION_STATE_CHANGED while something is
-- pending, and the sealed-button debounce: runs every sync that combat or
-- sealed buttons held back, then pending aura sounds.
function A.FlushPending()
    if InCombatLockdown() then return end
    local n=0
    for slot in pairs(A.pending) do n=n+1;flushing[n]=slot end
    for i=1,n do
        local slot=flushing[i]
        flushing[i]=nil
        A.pending[slot]=nil
        A.Sync(slot,true)
    end
    local alerts=C.Alerts
    if alerts and alerts.pending and alerts.SyncAuraSounds then alerts.SyncAuraSounds() end
end

-- Edit Mode / options preview: every aura-bar entry shows its sample icon
-- on its cell; compact containers step aside so nothing is drawn twice.
function A.SetPreview(on)
    on=on==true
    if A.preview==on then return end
    A.preview=on
    for _,fams in pairs(live) do
        for _,rec in pairs(fams.aura) do Show(rec) end
    end
    for slot,m in pairs(meta) do
        local view,plan=C.views[slot],C.plans[slot]
        if view and plan and view.on and plan.kind~=1 then Placeholders(slot,view,plan,m) else Unholds(slot) end
    end
end
