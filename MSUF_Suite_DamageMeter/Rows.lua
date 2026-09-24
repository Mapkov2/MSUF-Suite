local _,P=...;local NS,S=P.NS,P.Suite
-- Pooled bar rows. Styling (fonts, anchors, textures) runs only when the
-- style generation changes; painting writes content, memoizes plain values
-- and hands secret values straight to C sinks (StatusBar, FontString,
-- AbbreviateNumbers). Secrets are never compared, stored as memo or used as keys.
local D=P.DamageMeter
local M=D.M
local Public,Plain,Num=S.Public,D.Plain,D.Num
local floor,format=math.floor,string.format
local CLASS_SHEET="Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local WHITE="Interface\\Buttons\\WHITE8X8"
local gradientDirections={
    {"gradientLeft","HORIZONTAL",true},
    {"gradientRight","HORIZONTAL",false},
    {"gradientUp","VERTICAL",false},
    {"gradientDown","VERTICAL",true},
}
local ranks=setmetatable({},{__index=function(list,index) local text=index.."."; list[index]=text; return text end})
local separators={[3]="%s (%s)",[4]="%s | %s"}
local customOrders={{1,2,3},{1,3,2},{2,1,3},{2,3,1},{3,1,2},{3,2,1}}
local customPatterns={
    {"%s","%s %s","%s %s %s"},
    {"%s","%s (%s)","%s (%s) (%s)"},
    {"%s","%s [%s]","%s [%s] [%s]"},
    {"%s","%s | %s","%s | %s | %s"},
    {"%s","%s / %s","%s / %s / %s"},
    {"%s","%s - %s","%s - %s - %s"},
}

function D.Atlas(texture,atlas)
    local api=_G.C_Texture
    if type(api)=="table" and type(api.GetAtlasInfo)=="function" and api.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
        return true
    end
    return false
end

function D.FontStyle(fontString,size)
    local style=M.style
    local appliedFlags=S.SetFont(fontString,style.font,size,style.flags)
    local applyScaleMode=_G.MSUF_ApplyFontScaleAnimationMode
    if type(applyScaleMode)=="function" then applyScaleMode(fontString,appliedFlags) end
    fontString:SetAlpha(style.textAlpha)
    fontString:SetShadowColor(0,0,0,style.shadow and style.shadowAlpha or 0)
    if style.shadow then fontString:SetShadowOffset(style.shadowDistance,-style.shadowDistance)
    else fontString:SetShadowOffset(0,0) end
end

-- kind: "list" (meter rows), "spell" (breakdown panel) or "tip" (hover breakdown).
function D.CreateRow(parent,win,kind)
    local row=S.CreateFrame("Button",nil,parent)
    row.win,row.kind=win,kind
    local bar=S.CreateFrame("StatusBar",nil,row)
    bar:SetMinMaxValues(0,1); bar:SetValue(0)
    row.bar=bar
    row.track=S.CreateTexture(row,nil,"BACKGROUND")
    row.icon=S.CreateTexture(row,nil,"ARTWORK")
    row.rankText=S.CreateFontString(bar,nil,"OVERLAY")
    row.nameText=S.CreateFontString(bar,nil,"OVERLAY")
    row.valueText=S.CreateFontString(bar,nil,"OVERLAY")
    row.nameText:SetJustifyH("LEFT"); row.valueText:SetJustifyH("RIGHT")
    row.rankText:SetWordWrap(false); row.nameText:SetWordWrap(false); row.valueText:SetWordWrap(false)
    if kind=="tip" then
        row:EnableMouse(false)
    else
        local highlight=S.CreateTexture(row,nil,"HIGHLIGHT")
        highlight:SetAllPoints(row); highlight:SetColorTexture(1,1,1,.08)
        row:RegisterForClicks("LeftButtonUp","RightButtonUp")
        row:EnableMouseWheel(true)
        for script,handler in pairs(kind=="list" and D.listScripts or D.spellScripts) do row:SetScript(script,handler) end
    end
    return row
end

function D.AnchorRow(row,parent,slot)
    local offset=-(slot-1)*(M.style.barHeight+M.style.spacing)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT",parent,"TOPLEFT",0,offset)
    row:SetPoint("TOPRIGHT",parent,"TOPRIGHT",0,offset)
end

function D.ClearMemo(row)
    row.rank,row.rawName,row.class,row.iconKey,row.spellID=nil,nil,nil,nil,nil
    row.mA,row.mB,row.mP,row.mF,row.mO,row.mS,row.mMax,row.mVal,row.full,row.mDeath=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
end

-- Gradient textures are allocated once per used direction, and only restyled
-- when the meter style changes. Anchoring to the fill clips them to its value.
local function StyleGradient(bar,style)
    local overlays=bar.gradientOverlays
    local fill=style.gradientEnabled and bar:GetStatusBarTexture()
    if not fill then
        if overlays then for _,texture in pairs(overlays) do texture:Hide() end end
        return
    end
    if not overlays then overlays={}; bar.gradientOverlays=overlays end
    for i=1,#gradientDirections do
        local direction=gradientDirections[i]
        local key,orientation,reverse=direction[1],direction[2],direction[3]
        local texture=overlays[key]
        if style[key] then
            if not texture then
                texture=S.CreateTexture(bar,nil,"ARTWORK",nil,1)
                texture:SetTexture(WHITE)
                texture:SetBlendMode("BLEND")
                overlays[key]=texture
            end
            texture:ClearAllPoints()
            texture:SetAllPoints(fill)
            texture:SetAlpha(style.barAlpha)
            local first,second=style.gradientClear,style.gradientTint
            local minAlpha,maxAlpha=0,style.gradientStrength
            if reverse then first,second=second,first; minAlpha,maxAlpha=maxAlpha,minAlpha end
            if texture.SetGradient and first and second then
                texture:SetGradient(orientation,first,second)
            elseif texture.SetGradientAlpha then
                local r,g,b=style.gradientR,style.gradientG,style.gradientB
                texture:SetGradientAlpha(orientation,r,g,b,minAlpha,r,g,b,maxAlpha)
            else
                texture:SetColorTexture(style.gradientR,style.gradientG,style.gradientB,style.gradientStrength)
            end
            texture:Show()
        elseif texture then texture:Hide() end
    end
end

function D.StyleRow(row)
    local style=M.style
    row.styleGen=M.styleGen
    local tip,list=row.kind=="tip",row.kind=="list"
    local height=tip and 16 or style.barHeight
    local left,right=tip and 11 or style.leftSize,tip and 11 or style.rightSize
    local hasIcon=not list or style.iconStyle~=1
    row:SetHeight(height)
    local icon,bar=row.icon,row.bar
    icon:ClearAllPoints(); bar:ClearAllPoints()
    if hasIcon then
        icon:SetSize(height,height); icon:SetPoint("LEFT",row,"LEFT",0,0)
        bar:SetPoint("TOPLEFT",row,"TOPLEFT",height+1,0)
    else
        icon:Hide(); bar:SetPoint("TOPLEFT",row,"TOPLEFT",0,0)
    end
    bar:SetPoint("BOTTOMRIGHT",row,"BOTTOMRIGHT",0,0)
    bar:SetStatusBarTexture(style.texture)
    StyleGradient(bar,style)
    row.track:ClearAllPoints(); row.track:SetAllPoints(bar)
    row.track:SetColorTexture(style.trackR,style.trackG,style.trackB,style.trackA)
    row.hasIcon=hasIcon
    local rank,name,value=row.rankText,row.nameText,row.valueText
    D.FontStyle(rank,left); D.FontStyle(name,left); D.FontStyle(value,right)
    rank:ClearAllPoints(); name:ClearAllPoints(); value:ClearAllPoints()
    value:SetPoint("RIGHT",bar,"RIGHT",-3,style.baseline)
    if list and style.rank then
        rank:SetPoint("LEFT",bar,"LEFT",3,style.baseline); rank:Show()
        name:SetPoint("LEFT",rank,"RIGHT",2,0)
    else
        rank:Hide(); name:SetPoint("LEFT",bar,"LEFT",3,style.baseline)
    end
    name:SetPoint("RIGHT",value,"LEFT",-6,0)
    D.ClearMemo(row)
end

-- Bar and text colors follow the NeverSecret class token.
function D.RowColors(row,class)
    local style=M.style
    local r,g,b
    if class~="" then r,g,b=S.ClassRGB(class) end
    if style.classColors and r then row.bar:SetStatusBarColor(r,g,b,style.barAlpha)
    else row.bar:SetStatusBarColor(style.barR,style.barG,style.barB,style.barAlpha) end
    if style.leftClass and r then
        row.nameText:SetTextColor(r,g,b); row.rankText:SetTextColor(r,g,b)
    else
        row.nameText:SetTextColor(style.leftR,style.leftG,style.leftB); row.rankText:SetTextColor(style.leftR,style.leftG,style.leftB)
    end
    if style.rightClass and r then row.valueText:SetTextColor(r,g,b)
    else row.valueText:SetTextColor(style.rightR,style.rightG,style.rightB) end
end

-- iconStyle 2 prefers the spec icon, 3 (and a missing spec) uses the class sprite.
function D.UnitIcon(row,spec,class,iconStyle)
    local key=iconStyle==2 and spec~=0 and spec or class
    if key==row.iconKey then return end
    row.iconKey=key
    local icon,zoom=row.icon,M.style.zoom
    if iconStyle==2 and spec~=0 then
        icon:SetTexture(spec); icon:SetTexCoord(zoom,1-zoom,zoom,1-zoom); icon:Show()
        return
    end
    local coords=class~="" and type(CLASS_ICON_TCOORDS)=="table" and CLASS_ICON_TCOORDS[class]
    if type(coords)~="table" then icon:Hide(); return end
    local l,r,t,b=coords[1],coords[2],coords[3],coords[4]
    local dx,dy=(r-l)*zoom,(b-t)*zoom
    icon:SetTexture(CLASS_SHEET); icon:SetTexCoord(l+dx,r-dx,t+dy,b-dy); icon:Show()
end

function D.SetBar(row,maxValue,value)
    local bar=row.bar
    row.full=nil
    maxValue,value=Num(maxValue),Num(value)
    if Public(maxValue) then
        if maxValue~=row.mMax then row.mMax=maxValue; bar:SetMinMaxValues(0,maxValue) end
    else row.mMax=nil; bar:SetMinMaxValues(0,maxValue) end
    if Public(value) then
        if value~=row.mVal then row.mVal=value; bar:SetValue(value) end
    else row.mVal=nil; bar:SetValue(value) end
end

local function Abbreviate(value)
    local abbreviate=_G.AbbreviateNumbers
    if type(abbreviate)=="function" then return abbreviate(value) end
    return value
end
-- Custom layout keeps values in their chosen order. A secret value is only
-- passed through AbbreviateNumbers and SetFormattedText, never formatted in Lua.
local function SetCustomValueText(row,meterType,total,perSecond,denominator,alwaysPercent)
    local style=M.style
    local countOnly=D.countOnly[meterType]
    local rate
    if not countOnly then rate=perSecond end
    local percent
    if alwaysPercent or style.percent then
        denominator=Num(denominator)
        if Public(total) and Public(denominator) and denominator>0 then percent=floor(total/denominator*100+.5) end
    end
    local order,separator=style.valueOrder or 1,style.valueSeparator or 2
    local allPlain=Public(total) and (countOnly or Public(rate))
    if allPlain and total==row.mA and rate==row.mB and percent==row.mP
        and row.mF==5 and order==row.mO and separator==row.mS then return end
    if allPlain then row.mA,row.mB,row.mP,row.mF,row.mO,row.mS=total,rate,percent,5,order,separator
    else row.mA,row.mB,row.mP,row.mF,row.mO,row.mS=nil,nil,nil,nil,nil,nil end
    local percentText=percent and format("%d%%",percent)
    local first,second,third,count=nil,nil,nil,0
    for _,kind in ipairs(customOrders[order] or customOrders[1]) do
        if kind==1 or (kind==2 and not countOnly) or (kind==3 and percent~=nil) then
            local value
            if kind==1 then value=total elseif kind==2 then value=rate else value=percentText end
            value=kind==3 and value or (Public(value) and D.Compact(value) or Abbreviate(value))
            count=count+1
            if count==1 then first=value elseif count==2 then second=value else third=value end
        end
    end
    local pattern=(customPatterns[separator] or customPatterns[2])[count]
    if allPlain then
        if count==1 then row.valueText:SetText(format(pattern,first))
        elseif count==2 then row.valueText:SetText(format(pattern,first,second))
        else row.valueText:SetText(format(pattern,first,second,third)) end
    elseif count==1 then row.valueText:SetFormattedText(pattern,first)
    elseif count==2 then row.valueText:SetFormattedText(pattern,first,second)
    else row.valueText:SetFormattedText(pattern,first,second,third) end
end

-- Legacy value formats: 1 per second, 2 primary only, 3 "a (b)", 4 "a | b".
-- The primary value is the rate for Dps/Hps; interrupts/dispels show counts.
function D.SetValueText(row,meterType,total,perSecond,denominator,alwaysPercent)
    local style=M.style
    local fmt=style.numberFormat
    total,perSecond=Num(total),Num(perSecond)
    if fmt==5 then return SetCustomValueText(row,meterType,total,perSecond,denominator,alwaysPercent) end
    local a,b,two
    if D.countOnly[meterType] then a=total
    else
        local main,second=total,perSecond
        if D.perSecond[meterType] then main,second=perSecond,total end
        if fmt==1 then a=perSecond elseif fmt==2 then a=main else a,b,two=main,second,true end
    end
    local text=row.valueText
    if Public(a) and (not two or Public(b)) then
        local percent
        if alwaysPercent or style.percent then
            denominator=Num(denominator)
            if Public(total) and Public(denominator) and denominator>0 then percent=floor(total/denominator*100+.5) end
        end
        if a==row.mA and b==row.mB and percent==row.mP and fmt==row.mF then return end
        row.mA,row.mB,row.mP,row.mF=a,b,percent,fmt
        local value=D.Compact(a)
        if two then value=format(separators[fmt],value,D.Compact(b)) end
        if percent then value=format("%s %d%%",value,percent) end
        text:SetText(value)
        return
    end
    row.mA,row.mB,row.mP,row.mF=nil,nil,nil,nil
    local first=Public(a) and D.Compact(a) or Abbreviate(a)
    if two then text:SetFormattedText(separators[fmt],first,Public(b) and D.Compact(b) or Abbreviate(b))
    else text:SetText(first) end
end

function D.PaintSource(row,source,index,session,win)
    if row.styleGen~=M.styleGen then D.StyleRow(row) end
    local style,meterType=M.style,win.meterType
    if style.rank and row.rank~=index then row.rank=index; row.rankText:SetText(ranks[index]) end
    local name=source.name
    if Public(name) then
        if name~=row.rawName then row.rawName=name; row.nameText:SetText(D.Short(name)) end
    else
        row.rawName=nil; row.nameText:SetText(D.Short(name))
    end
    local class=source.classFilename
    if not Public(class) or type(class)~="string" then class="" end
    if class~=row.class then row.class=class; D.RowColors(row,class) end
    if row.hasIcon then
        local spec=source.specIconID
        D.UnitIcon(row,Plain(spec) and spec or 0,class,style.iconStyle)
    end
    if meterType==D.DEATHS then
        if not row.full then row.full,row.mMax,row.mVal=true,nil,nil; row.bar:SetMinMaxValues(0,1); row.bar:SetValue(1) end
        row.mA=nil
        local seconds=source.deathTimeSeconds
        seconds=(Plain(seconds) and seconds>=0 and not win.overall) and floor(seconds) or -1
        if seconds~=row.mDeath then row.mDeath=seconds; row.valueText:SetText(seconds>=0 and D.Clock(seconds) or "") end
        return
    end
    row.mDeath=nil
    D.SetBar(row,session.maxAmount,source.totalAmount)
    D.SetValueText(row,meterType,source.totalAmount,source.amountPerSecond,session.totalAmount,false)
end

local function SpellTexture(id)
    local api=_G.C_Spell
    if type(api)=="table" and type(api.GetSpellTexture)=="function" then return api.GetSpellTexture(id) end
    if type(GetSpellTexture)=="function" then return GetSpellTexture(id) end
end
local function SpellName(id)
    local api=_G.C_Spell
    if type(api)=="table" and type(api.GetSpellName)=="function" then return api.GetSpellName(id) end
    if type(GetSpellInfo)=="function" then return (GetSpellInfo(id)) end
end
-- Breakdown spell row; percent of the source total whenever values are plain.
function D.PaintSpell(row,spell,source,meterType,class)
    if row.styleGen~=M.styleGen then D.StyleRow(row) end
    if class~=row.class then row.class=class; D.RowColors(row,class) end
    row.rawName,row.iconKey=nil,nil
    local id=spell.spellID
    if Plain(id) then
        if id~=row.spellID then
            row.spellID=id
            local texture,zoom=SpellTexture(id),M.style.zoom
            if texture then row.icon:SetTexture(texture); row.icon:SetTexCoord(zoom,1-zoom,zoom,1-zoom); row.icon:Show()
            else row.icon:Hide() end
            local name,pet=SpellName(id),spell.creatureName
            if not Public(name) or type(name)~="string" then name="" end
            if name~="" and Public(pet) and type(pet)=="string" and pet~="" then name=format("%s (%s)",name,pet) end
            row.nameText:SetText(name)
        end
    else
        -- Secret spell IDs never reach texture lookups (reported to raise on
        -- some clients); C_Spell.GetSpellName accepts them and returns a secret.
        row.spellID=nil
        row.icon:Hide()
        local api=_G.C_Spell
        if not Public(id) and type(api)=="table" and type(api.GetSpellName)=="function" then row.nameText:SetText(api.GetSpellName(id))
        else row.nameText:SetText("") end
    end
    D.SetBar(row,source.maxAmount,spell.totalAmount)
    D.SetValueText(row,meterType,spell.totalAmount,spell.amountPerSecond,source.totalAmount,true)
end

-- EnemyDamageTaken breakdown row: one attacking unit (plain data only).
function D.PaintGroup(row,entry,maxAmount,total,duration,meterType)
    if row.styleGen~=M.styleGen then D.StyleRow(row) end
    if entry.class~=row.class then row.class=entry.class; D.RowColors(row,entry.class) end
    row.spellID=nil
    D.UnitIcon(row,entry.spec,entry.class,2)
    if entry.name~=row.rawName then row.rawName=entry.name; row.nameText:SetText(D.Short(entry.name)) end
    D.SetBar(row,maxAmount,entry.amount)
    D.SetValueText(row,meterType,entry.amount,duration>0 and entry.amount/duration or 0,total,true)
end
