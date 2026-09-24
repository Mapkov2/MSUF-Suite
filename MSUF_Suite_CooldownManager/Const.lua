local _,P=...
local NS,S=P.NS,P.Suite
local C=P.CDM
-- Shared constants and cold-path factories for the render plane: glow
-- styles and their flipbook animations, step curves for desaturation and
-- cooldown opacity (cached per value pair), pixel snapping, the 9-point
-- anchor table, tint colors and the hardcoded spell-category icons.
local K={}
C.Const=K
local floor,max=math.floor,math.max

-- Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY; 133 on every client.
local consts=_G.Constants and _G.Constants.SpellCooldownConsts
K.GCD_CATEGORY=consts and consts.GLOBAL_RECOVERY_CATEGORY or 133
K.QUESTION_ICON=134400

-- Blizzard's viewers use these file paths for bag-item categories (potions,
-- healthstones); the space in the Warlock paths is part of the file name.
K.CATEGORY_ICONS={
    [4]="Interface/ICONS/INV_POTION_114",
    [30]="Interface/ICONS/INV_POTION_54",
    [1711]="Interface/ICONS/Warlock_ Healthstone",
    [2566]="Interface/ICONS/Warlock_ Bloodstone",
}

------------------------------------------------------------------ anchors
-- Index = catalog 9-point choice. X/Y are inward signs for text insets.
K.POINTS=NS.CDM.POINTS
K.POINT_X={1,0,-1,1,0,-1,1,0,-1}
K.POINT_Y={-1,-1,-1,0,0,0,1,1,1}
K.JUSTIFY={"LEFT","CENTER","RIGHT","LEFT","CENTER","RIGHT","LEFT","CENTER","RIGHT"}

-- Frame levels above the icon frame: swipe, recharge edge, glow, text.
K.LEVEL={cd=1,charge=2,glow=3,assist=4,text=5}

------------------------------------------------------------------ tints
-- Usable/range codes: 1 usable, 2 not enough power, 3 unusable,
-- 4 out of range (bar color, read from the view).
K.TINT={{1,1,1},{.5,.5,1},{.4,.4,.4}}
K.GLOW_GOLD={1,.82,0}

------------------------------------------------------------------ glows
-- 1 Blizzard alert and 2 marching ants are 6x5 flipbooks (30 frames, 1 s
-- loop) scaled around the icon; 3 pulses a border, 4 is a static border.
K.GLOW={
    {atlas="UI-HUD-ActionBar-Proc-Loop-Flipbook",rows=6,cols=5,frames=30,duration=1,scale=1.4},
    {atlas="rotationhelper_ants_flipbook",rows=6,cols=5,frames=30,duration=1,scale=1.2},
    {edge=2,pulse=.6},
    {edge=2},
}
K.ASSIST_STYLE=2

-- One looping FlipBook group per texture; the group only runs while played.
function K.FlipBook(texture,style)
    local group=texture:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local flip=group:CreateAnimation("FlipBook")
    group.flip=flip
    K.SetFlipBook(group,style)
    return group
end

function K.SetFlipBook(group,style)
    local flip=group.flip
    if group.style==style then return end
    group.style=style
    flip:SetFlipBookRows(style.rows)
    flip:SetFlipBookColumns(style.cols)
    flip:SetFlipBookFrames(style.frames)
    flip:SetFlipBookFrameWidth(0)
    flip:SetFlipBookFrameHeight(0)
    flip:SetDuration(style.duration)
end

-- Alpha bounce for the pulse style; animates the region it is created on.
function K.Pulse(region,duration)
    local group=region:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local fade=group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(.25)
    fade:SetDuration(duration)
    group.fade=fade
    return group
end

------------------------------------------------------------------ curves
-- Step curves from plain setting percentages: y0 while nothing remains,
-- y1 from 1 ms remaining on. Numeric cache key, built only on refresh.
local curves={}
function K.StepCurve(from,to)
    from,to=floor(from+.5),floor(to+.5)
    local key=from*1000+to
    local curve=curves[key]
    if curve~=nil then return curve or nil end
    local util=_G.C_CurveUtil
    if type(util)~="table" or type(util.CreateCurve)~="function" then curves[key]=false;return nil end
    curve=util.CreateCurve()
    local step=_G.Enum and _G.Enum.LuaCurveType and _G.Enum.LuaCurveType.Step
    if step then curve:SetType(step) end
    curve:AddPoint(0,from/100)
    curve:AddPoint(.001,to/100)
    curves[key]=curve
    return curve
end
function K.DesatCurve() return K.StepCurve(0,100) end

------------------------------------------------------------------ pixels
-- C.state.px = UI units per physical pixel (Layout keeps it current).
function K.Px()
    local px=C.state.px
    if type(px)~="number" or px<=0 then
        local layout=C.Layout
        px=layout and layout.PixelScale and layout.PixelScale() or 1
        if type(px)~="number" or px<=0 then px=1 end
    end
    return px
end
function K.Snap(value)
    local px=K.Px()
    return floor(value/px+.5)*px
end
function K.Pixels(count) return count*K.Px() end

-- Icon footprint in UI units, snapped to whole physical pixels.
function K.IconSize(view)
    local px=K.Px()
    local size=view.size or 36
    local w=max(px,K.Snap(size))
    local h=max(px,K.Snap(size*(view.height or 100)/100))
    return w,h
end

-- Four edges inside owner's rect; the side edges stop short of the top and
-- bottom ones so translucent colors do not double at the corners. No width
-- only hides them: points and color are written when they show again.
function K.PlaceEdges(set,owner,width,r,g,b,a)
    if not (width>0) then
        for i=1,4 do set[i]:SetShown(false) end
        return
    end
    for i=1,4 do
        local edge=set[i]
        edge:ClearAllPoints()
        edge:SetColorTexture(r,g,b,a or 1)
        edge:SetShown(true)
    end
    set[1]:SetPoint("TOPLEFT",owner,"TOPLEFT");set[1]:SetPoint("TOPRIGHT",owner,"TOPRIGHT");set[1]:SetHeight(width)
    set[2]:SetPoint("BOTTOMLEFT",owner,"BOTTOMLEFT");set[2]:SetPoint("BOTTOMRIGHT",owner,"BOTTOMRIGHT");set[2]:SetHeight(width)
    set[3]:SetPoint("TOPLEFT",owner,"TOPLEFT",0,-width);set[3]:SetPoint("BOTTOMLEFT",owner,"BOTTOMLEFT",0,width);set[3]:SetWidth(width)
    set[4]:SetPoint("TOPRIGHT",owner,"TOPRIGHT",0,-width);set[4]:SetPoint("BOTTOMRIGHT",owner,"BOTTOMRIGHT",0,width);set[4]:SetWidth(width)
end

-- Hex -> rgb for per-spell glow colors; each distinct hex decoded once.
local hexCache={}
function K.HexRGB(hex)
    local rgb=hexCache[hex]
    if not rgb then
        local r,g,b=S.RGB(hex)
        rgb={r,g,b}
        hexCache[hex]=rgb
    end
    return rgb[1],rgb[2],rgb[3]
end
