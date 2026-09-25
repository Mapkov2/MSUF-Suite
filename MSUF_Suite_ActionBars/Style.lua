local _,P=...;local NS,S=P.NS,P.Suite
-- Static button styling (configuration time, out of combat). Suite buttons
-- use the regions of ActionButtonTemplate; adopted stance/pet buttons are
-- Blizzard's, so only cosmetic regions are touched there and every suite
-- texture lives in the suite's own records, never on Blizzard tables.
local AB=P.ActionBars
local M=AB.M
local OUTLINES={"OUTLINE","THICKOUTLINE",""}
-- Highlight/pressed choices: 1 Border, 2 Soft fill, 3 Blizzard, 4 None.
local STYLE_BORDER,STYLE_FILL,STYLE_BLIZZARD=1,2,3

local function Class()
    if type(UnitClass)~="function" then return nil end
    local _,class=UnitClass("player")
    return S.Public(class) and class or nil
end

-- Resolved once per refresh; buttons read plain values from here.
function AB.BuildStyle()
    local c=M.config
    local style=AB.style or {}
    AB.style=style
    style.font=S.ResolveFont(c.font)
    style.flags=OUTLINES[c.fontOutline] or ""
    style.rendering,style.shadow=c.fontRendering,c.fontShadow
    style.shadowOpacity,style.shadowDistance=c.fontShadowOpacity,c.fontShadowDistance
    style.zoom=c.iconZoom/100
    style.border=c.borderSize
    local cr,cg,cb=S.ClassRGB(Class())
    if c.borderClassColor and cr then style.br,style.bg,style.bb=cr,cg,cb else style.br,style.bg,style.bb=S.RGB(c.borderColor) end
    if c.interactionClassColor and cr then style.ir,style.ig,style.ib=cr,cg,cb else style.ir,style.ig,style.ib=S.RGB(c.interactionColor) end
    style.sr,style.sg,style.sb=S.RGB(c.slotColor)
    style.slotAlpha=c.slotAlpha/100
    style.kr,style.kg,style.kb=S.RGB(c.keybindColor)
    style.mr,style.mg,style.mb=S.RGB(c.macroColor)
    style.cr,style.cg,style.cb=S.RGB(c.countColor)
    style.dr,style.dg,style.db=S.RGB(c.cooldownColor)
    style.wr,style.wg,style.wb=S.RGB(c.swipeColor)
    style.swipeAlpha=c.swipeAlpha/100
    style.highlight,style.pushed=c.highlightStyle,c.pushedStyle
    style.rr,style.rg,style.rb=S.RGB(c.rangeColor)
    return style
end

local function Edges(rec,key,layer,sublevel)
    local set=rec[key]
    if not set then
        set={}
        for i=1,4 do set[i]=S.CreateTexture(rec.button,nil,layer,nil,sublevel) end
        rec[key]=set
    end
    return set
end

-- Four edges inside the button rect; the side edges stop short of the top
-- and bottom ones so translucent colors do not double at the corners.
local function PlaceEdges(set,button,width,r,g,b,a)
    local shown=width>0
    for i=1,4 do
        local edge=set[i]
        edge:ClearAllPoints()
        edge:SetColorTexture(r,g,b,a)
        edge:SetShown(shown)
    end
    if not shown then return end
    set[1]:SetPoint("TOPLEFT",button,"TOPLEFT");set[1]:SetPoint("TOPRIGHT",button,"TOPRIGHT");set[1]:SetHeight(width)
    set[2]:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT");set[2]:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT");set[2]:SetHeight(width)
    set[3]:SetPoint("TOPLEFT",button,"TOPLEFT",0,-width);set[3]:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",0,width);set[3]:SetWidth(width)
    set[4]:SetPoint("TOPRIGHT",button,"TOPRIGHT",0,-width);set[4]:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",0,width);set[4]:SetWidth(width)
end
AB.PlaceEdges=PlaceEdges

local function ShowEdges(set,shown)
    if not set then return end
    for i=1,4 do set[i]:SetShown(shown) end
end

-- Remembers a template texture's own art once, so "Blizzard" can restore it.
local function Remember(rec,key,texture)
    rec.art=rec.art or {}
    if texture and rec.art[key]==nil then
        rec.art[key]={atlas=texture.GetAtlas and texture:GetAtlas(),file=texture:GetTexture(),blend=texture:GetBlendMode()}
    end
    return rec.art[key]
end

local function StyleInteraction(rec,key,texture,mode,alpha)
    if not texture then return end
    local art=Remember(rec,key,texture)
    local style=AB.style
    texture:ClearAllPoints()
    texture:SetAllPoints(rec.button)
    if mode==STYLE_BLIZZARD and art then
        if art.atlas then texture:SetAtlas(art.atlas) elseif art.file then texture:SetTexture(art.file) end
        texture:SetBlendMode(art.blend or "ADD")
        texture:SetVertexColor(1,1,1,1)
        texture:SetAlpha(1)
    elseif mode==STYLE_FILL then
        texture:SetColorTexture(style.ir,style.ig,style.ib,alpha)
        texture:SetBlendMode("ADD")
        texture:SetAlpha(1)
    else
        texture:SetAlpha(0)
    end
end

local function Text(fontString,size,r,g,b,shown)
    if not fontString then return end
    local style=AB.style
    S.SetStyledFont(fontString,style.font,size,style.flags,style.rendering,
        style.shadow,style.shadowOpacity,style.shadowDistance)
    fontString:SetTextColor(r,g,b)
    fontString:SetAlpha(shown and 1 or 0)
end

local function Hide(region) if region then region:SetAlpha(0) end end

-- Applies the static look to one button. Called on every refresh; all
-- writes are idempotent and nothing here runs from events.
function AB.StyleButton(rec)
    local button,style,c=rec.button,AB.style,M.config
    local k=rec.bar.key
    local size=rec.bar.size or c[k.Size]
    local border=style.border
    local icon=button.icon
    if icon then
        if button.IconMask and not rec.unmasked and icon.RemoveMaskTexture then
            icon:RemoveMaskTexture(button.IconMask)
            rec.unmasked=true
        end
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT",button,"TOPLEFT",border,-border)
        icon:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-border,border)
        icon:SetTexCoord(style.zoom,1-style.zoom,style.zoom,1-style.zoom)
    end
    Hide(button:GetNormalTexture());Hide(button.SlotArt);Hide(button.SlotBackground)
    if rec.owned then Hide(button.Flash);Hide(button.NewActionTexture);Hide(button.SpellHighlightTexture) end
    -- Empty-slot fill behind the icon; filled slots cover it.
    local slot=rec.slotTexture
    if not slot then slot=S.CreateTexture(button,nil,"BACKGROUND",nil,-8);rec.slotTexture=slot end
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT",button,"TOPLEFT",border,-border)
    slot:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-border,border)
    slot:SetColorTexture(style.sr,style.sg,style.sb,style.slotAlpha)
    PlaceEdges(Edges(rec,"borderEdges","OVERLAY",6),button,border,style.br,style.bg,style.bb,1)
    -- Mouseover: HIGHLIGHT-layer edges show on hover without scripts.
    local hover=Edges(rec,"hoverEdges","HIGHLIGHT",7)
    PlaceEdges(hover,button,style.highlight==STYLE_BORDER and math.max(1,math.floor(size/20+.5)) or 0,style.ir,style.ig,style.ib,1)
    StyleInteraction(rec,"highlight",button:GetHighlightTexture(),style.highlight,.25)
    -- Pressed: the border variant needs press state (owned buttons only);
    -- adopted buttons fall back to the fill.
    local pushed=style.pushed
    if pushed==STYLE_BORDER and not rec.owned then pushed=STYLE_FILL end
    local press=Edges(rec,"pressEdges","OVERLAY",7)
    PlaceEdges(press,button,pushed==STYLE_BORDER and math.max(1,math.floor(size/15+.5)) or 0,style.ir,style.ig,style.ib,1)
    ShowEdges(press,false)
    rec.pressBorder=pushed==STYLE_BORDER
    StyleInteraction(rec,"pushed",button:GetPushedTexture(),pushed,.35)
    StyleInteraction(rec,"checked",button:GetCheckedTexture(),style.highlight==STYLE_BLIZZARD and STYLE_BLIZZARD or STYLE_FILL,.3)
    -- Text: keybind top right, count bottom right, macro name bottom.
    local fontScale=rec.owned and 0 or 2
    local hotkey=rec.owned and not rec.native and button.HotKey or rec.keyText
    if not rec.owned or rec.native then
        Hide(button.HotKey)
        if not hotkey then hotkey=S.CreateFontString(button,nil,"OVERLAY");rec.keyText=hotkey end
    end
    if hotkey then
        hotkey:ClearAllPoints()
        hotkey:SetPoint("TOPRIGHT",button,"TOPRIGHT",-1-border,-2-border)
        local keySize=math.max(6,c[k.KeybindSize]-fontScale)
        hotkey:SetJustifyH("RIGHT")
        hotkey:SetWordWrap(false)
        hotkey:SetSize(math.max(1,size-2),keySize+2)
        Text(hotkey,keySize,style.kr,style.kg,style.kb,c[k.Keybind])
    end
    local count=button.Count
    if count then
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-1-border,2+border)
        Text(count,c[k.CountSize],style.cr,style.cg,style.cb,true)
    end
    local name=button.Name
    if name then
        name:ClearAllPoints()
        name:SetPoint("BOTTOMLEFT",button,"BOTTOMLEFT",1,2+border)
        name:SetPoint("BOTTOMRIGHT",button,"BOTTOMRIGHT",-1,2+border)
        name:SetHeight(c[k.MacroSize]+2)
        name:SetWordWrap(false)
        Text(name,c[k.MacroSize],style.mr,style.mg,style.mb,rec.owned and c[k.Macro])
    end
    local cooldown=button.cooldown
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetAllPoints(icon or button)
        cooldown:SetSwipeColor(style.wr,style.wg,style.wb,style.swipeAlpha)
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawBling(false)
        cooldown:SetHideCountdownNumbers(not c.cooldownNumbers)
        local text=cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
        if text then Text(text,math.max(6,c[k.CooldownSize]-fontScale),style.dr,style.dg,style.db,true) end
    end
    for _,key in ipairs({"chargeCooldown","lossOfControlCooldown"}) do
        local extra=button[key]
        if extra then
            extra:ClearAllPoints()
            extra:SetAllPoints(icon or button)
            extra:SetHideCountdownNumbers(key=="lossOfControlCooldown" or not (c.cooldownNumbers and c.rechargeNumbers))
        end
    end
    if rec.owned and button.Border then
        button.Border:ClearAllPoints()
        button.Border:SetAllPoints(button)
    end
    local alert=button.SpellActivationAlert
    if alert and rec.owned then
        alert:SetSize(size*1.4,size*1.4)
        if rec.native then alert:SetAlpha(c.procGlow==1 and 1 or 0) end
    end
end

-- Press state for native keys, routed keys and mouse presses; also drives
-- the "Border" pressed style. Visual only, allowed in combat.
function AB.SetPushed(rec,down)
    if rec.owned then rec.button:SetButtonState(down and "PUSHED" or "NORMAL") end
    if rec.pressBorder then ShowEdges(rec.pressEdges,down) end
end

local function MouseDown(button) local rec=AB.records[button];if rec and M.active then AB.SetPushed(rec,true) end end
local function MouseUp(button) local rec=AB.records[button];if rec and M.active then AB.SetPushed(rec,false) end end
-- Routed keys arrive as "Keybind" clicks, which do not change the button
-- state themselves.
local function PreClick(button,mouse,down)
    local rec=AB.records[button]
    if rec and M.active and mouse=="Keybind" then AB.SetPushed(rec,down) end
end
function AB.HookPress(rec)
    if rec.pressHooked or not rec.owned then return end
    rec.pressHooked=true
    local button=rec.button
    button:HookScript("OnMouseDown",MouseDown)
    button:HookScript("OnMouseUp",MouseUp)
    button:HookScript("PreClick",PreClick)
end

function AB.StyleAll()
    AB.BuildStyle()
    for index=1,AB.BAR_COUNT do
        local bar=AB.bars[index]
        if bar then
            for i=1,#bar.buttons do
                local rec=bar.buttons[i]
                AB.StyleButton(rec)
                AB.HookPress(rec)
            end
        end
    end
end
