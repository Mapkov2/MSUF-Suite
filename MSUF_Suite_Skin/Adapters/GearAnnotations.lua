local _, NS = ...

-- Equipment presentation. Wide mode reanchors the exact native slots without
-- replacing/reparenting them. Geometry is restored on exit; data and events
-- remain owned by CharacterDetails. Compact mode is the compatibility fallback.
local Gear = {}
NS.GearAnnotations = Gear
local rightSide = {[10]=true,[6]=true,[7]=true,[8]=true,[11]=true,[12]=true,[13]=true,[14]=true,[16]=true}
local compactSpec={role="input",radius=4,border=0,inset=0,allowImplicitProtected=true}
local wideSpec={role="card",radius=5,border=0,inset=0,allowImplicitProtected=true}
local columns = {
    {"HeadSlot","NeckSlot","ShoulderSlot","BackSlot","ChestSlot","WristSlot","MainHandSlot","SecondaryHandSlot"},
    {"HandsSlot","WaistSlot","LegsSlot","FeetSlot","Finger0Slot","Finger1Slot","Trinket0Slot","Trinket1Slot"},
}
-- Source: upstream/live 8ea15b61, CharacterFrameMixin:UpdateSize and
-- PaperDollFrame.xml. Only the Character page grows; sidebar collapse stays native.
local function Points(frame)
    local points={}
    for i=1,math.min(frame:GetNumPoints(),4) do points[i]={frame:GetPoint(i)} end
    return points
end
local function SamePoints(frame,points)
    if not points or frame:GetNumPoints()~=#points then return false end
    for i,point in ipairs(points) do
        local a,b,c,d,e=frame:GetPoint(i)
        if a~=point[1] or b~=point[2] or c~=point[3] or d~=point[4] or e~=point[5] then return false end
    end
    return true
end
local function RecordGeometry(v,frame)
    local record=v.geometry[frame]
    if not record then record={};v.geometry[frame]=record end
    return record
end
local function Place(v,frame,point,parent,relative,x,y,second)
    if not frame then return end
    local record=RecordGeometry(v,frame)
    if not SamePoints(frame,record.appliedPoints) then record.points=Points(frame) end
    local applied=record.appliedPoints
    if not applied then applied={{}};record.appliedPoints=applied end
    local p=applied[1];p[1],p[2],p[3],p[4],p[5]=point,parent,relative,x,y
    applied[2]=second
    if not SamePoints(frame,applied) then
        frame:ClearAllPoints()
        for _,anchor in ipairs(applied) do frame:SetPoint(unpack(anchor)) end
    end
end
local function Size(v,frame,width,height)
    if not frame then return end
    local record=RecordGeometry(v,frame)
    if width then
        local current=frame:GetWidth()
        if current~=record.appliedWidth then record.width=current end
        if current~=width then frame:SetWidth(width) end
        record.appliedWidth=width
    end
    if height then
        local current=frame:GetHeight()
        if current~=record.appliedHeight then record.height=current end
        if current~=height then frame:SetHeight(height) end
        record.appliedHeight=height
    end
end
local function Conceal(v,frame)
    if not frame or not frame.IsShown then return end
    local record=RecordGeometry(v,frame)
    if record.shown==nil then record.shown=frame:IsShown() end
    if frame:IsShown() then frame:Hide() end
end
local function Scale(v,frame,value)
    local record=RecordGeometry(v,frame)
    if frame:GetScale()~=record.appliedScale then record.scale=frame:GetScale() end
    if frame:GetScale()~=value then frame:SetScale(value) end
    record.appliedScale=value
end
-- Called by the existing exact-provider hooks too, after it refreshes a slot.
-- Keep its content intact; only suppress duplicate annotations in list mode.
function Gear.SuppressListProvider(element,slotID)
    local v=NS.CharacterDetails and NS.CharacterDetails.views[_G.CharacterFrame]
    if not v or not v.list or not v.host:IsVisible() or NS.IsCombatLocked() then return end
    local provider=_G.EnhanceQoL
    local slots=provider and provider.variables and provider.variables.itemSlots
    local row=slotID and v.bySlot[slotID]
    if not slots or not row or slots[slotID]~=element or element~=_G["Character"..row.slotName] then return end
    Conceal(v,element.enchant);Conceal(v,element.trackLabel);Conceal(v,element.enchantWarningTooltip)
    if type(element.gems)=="table" then for i=1,math.min(#element.gems,4) do Conceal(v,element.gems[i]) end end
end
function Gear.IsWide()
    local v=NS.CharacterDetails and NS.CharacterDetails.views[_G.CharacterFrame]
    return v and v.wide==true or false
end
function Gear.RestoreLayout(v)
    if not v or not v.geometry then return end
    if NS.IsCombatLocked() then
        NS.CombatGate.RunOrDefer("character-gear-layout",function()
            if not v.active or not v.host:IsVisible() then Gear.RestoreLayout(v) else Gear.ApplyLayout(v) end
        end)
        return
    end
    local oldWidth,oldHeight=v.root:GetWidth(),v.root:GetHeight()
    for frame,record in pairs(v.geometry) do
        if SamePoints(frame,record.appliedPoints) then
            frame:ClearAllPoints()
            for _,point in ipairs(record.points) do frame:SetPoint(unpack(point)) end
        end
        if record.width and frame:GetWidth()==record.appliedWidth then frame:SetWidth(record.width) end
        if record.height and frame:GetHeight()==record.appliedHeight then frame:SetHeight(record.height) end
        if record.scale and frame:GetScale()==record.appliedScale then frame:SetScale(record.scale) end
        if record.shown~=nil and not frame:IsShown() then frame:SetShown(record.shown) end
        v.geometry[frame]=nil
    end
    if (v.wide or v.list) and v.root.Inset then NS.Surface.SetVisible(v.root.Inset,true) end
    if v.wideInfo then v.wideInfo:Hide() end
    v.wide=false;v.list=false;v.layoutMode=nil
    for _,row in ipairs(v.rows) do row.icon:Show() end
    if v.root:IsVisible() and type(UpdateUIPanelPositions)=="function"
        and (v.root:GetWidth()~=oldWidth or v.root:GetHeight()~=oldHeight) then UpdateUIPanelPositions(v.root) end
end
function Gear.ApplyLayout(v)
    if not v or v.kind~="character" or NS.IsCombatLocked() then return end
    local config=NS.DB.characterDetails
    local mode=config.view or "modern"
    local enabled=v.active and NS.DB.enabled and mode~="classic"
        and (config.view~=nil or (config.enabled and config.inlineGear and config.wideLayout~=false))
        and NS.DB.skins.blizzardWindows~=false and NS.GenericWindows.IsCategoryEnabled("character")
        and v.host:IsVisible() and v.root.activeSubframe=="PaperDollFrame"
        and type(v.root.UpdateSize)=="function" and v.root.InsetRight and _G.CharacterModelScene
    if not enabled then Gear.RestoreLayout(v);return end
    if v.layoutMode and v.layoutMode~=mode then Gear.RestoreLayout(v) end
    v.geometry=v.geometry or {};v.layoutMode=mode
    local oldWidth,oldHeight=v.root:GetWidth(),v.root:GetHeight()
    if mode=="list" then
        v.list=true;v.wide=false
        Size(v,v.root,380,694)
        Place(v,v.panel,"TOPLEFT",v.root,"TOPLEFT",14,-36)
        Size(v,v.panel,352,644)
        if v.root.Inset then NS.Surface.SetVisible(v.root.Inset,false) end
        Conceal(v,v.root.InsetRight);Conceal(v,_G.CharacterStatsPane)
        Conceal(v,_G.CharacterModelScene);Conceal(v,_G.CharacterLevelText)
        Conceal(v,_G.PaperDollSidebarTabs)
        Conceal(v,_G.PaperDollFrame.TitleManagerPane);Conceal(v,_G.PaperDollFrame.EquipmentManagerPane)
        for _,row in ipairs(v.rows) do
            local slot=_G["Character"..row.slotName]
            if slot and slot:GetWidth()>0 then
                local scale=24/slot:GetWidth()
                Scale(v,slot,scale)
                Place(v,slot,"LEFT",row.frame,"LEFT",2/scale,0)
                row.icon:Hide();Gear.SuppressListProvider(slot,row.slot)
            end
        end
        -- Cosmetic equipment remains accessible, outside the audited 16 rows.
        local shirt,tabard=_G.CharacterShirtSlot,_G.CharacterTabardSlot
        if shirt and shirt:GetWidth()>0 then
            local scale=24/shirt:GetWidth();Scale(v,shirt,scale)
            Place(v,shirt,"TOPLEFT",v.panel,"TOPLEFT",14/scale,-568/scale)
        end
        if tabard and tabard:GetWidth()>0 then
            local scale=24/tabard:GetWidth();Scale(v,tabard,scale)
            Place(v,tabard,"TOPLEFT",v.panel,"TOPLEFT",46/scale,-568/scale)
        end
        if type(UpdateUIPanelPositions)=="function" and (oldWidth~=v.root:GetWidth() or oldHeight~=v.root:GetHeight()) then UpdateUIPanelPositions(v.root) end
        return
    end
    v.wide=true;v.list=false
    Size(v,v.root,v.root.Expanded and 920 or 704,540)
    v.rightBottom=v.rightBottom or {"BOTTOMRIGHT",v.root,"BOTTOMRIGHT",-8,14}
    Place(v,v.root.InsetRight,"TOPLEFT",v.root,"TOPLEFT",704,-80,v.rightBottom)
    if v.root.Inset then NS.Surface.SetVisible(v.root.Inset,false) end
    Place(v,_G.CharacterModelScene,"TOPLEFT",v.root,"TOPLEFT",242,-108)
    Size(v,_G.CharacterModelScene,220,350)
    for side,list in ipairs(columns) do
        for i,name in ipairs(list) do
            Place(v,_G["Character"..name],"TOPLEFT",v.root,"TOPLEFT",side==1 and 18 or 645,-90-(i-1)*50)
        end
    end
    Place(v,_G.CharacterShirtSlot,"TOPLEFT",v.root,"TOPLEFT",306,-478)
    Place(v,_G.CharacterTabardSlot,"TOPLEFT",v.root,"TOPLEFT",356,-478)
    if type(UpdateUIPanelPositions)=="function" and (oldWidth~=v.root:GetWidth() or oldHeight~=v.root:GetHeight()) then
        UpdateUIPanelPositions(v.root)
    end
end
local function Font(parent,size)
    local font=parent:CreateFontString(nil,"OVERLAY")
    font.gearSize=size
    font:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",size,"")
    font:SetWordWrap(false);return font
end
function Gear.UpdateSummary(v)
    if not v.wide then return end
    if not v.wideInfo then
        local host=CreateFrame("Frame",nil,v.host);v.wideInfo=host
        host:SetAllPoints(v.root);host:EnableMouse(false)
        v.wideSummary=Font(host,11);v.wideSummary:SetPoint("TOPLEFT",18,-65);v.wideSummary:SetWidth(660);v.wideSummary:SetJustifyH("LEFT")
        v.wideFooter=Font(host,10);v.wideFooter:SetPoint("BOTTOMLEFT",18,8);v.wideFooter:SetWidth(666);v.wideFooter:SetJustifyH("CENTER")
    end
    local path=GameFontNormal and GameFontNormal:GetFont() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if v.wideInfoPath~=path then
        v.wideSummary:SetFont(path,11,"");v.wideFooter:SetFont(path,10,"");v.wideInfoPath=path
    end
    v.wideSummary:SetText(v.summary:GetText() or "")
    v.wideFooter:SetText(v.footer:GetText() or "")
    v.wideSummary:SetTextColor(NS.Theme.GetColor("muted"));v.wideFooter:SetTextColor(NS.Theme.GetColor("muted"))
    v.wideInfo:Show()
end
local function Leave(owner)
    if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
local function Hide(a)
    if not a then return end
    a.host:Hide();Leave(a.status)
    for _,gem in ipairs(a.gems) do Leave(gem) end
end
local function ShowDetails(v,row,owner)
    if not row.link or not v.unit or not GameTooltip then return end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    GameTooltip:SetInventoryItem(v.unit,row.slot)
    NS.EquipmentInfo.AddTooltip(row.audit);GameTooltip:Show()
end
local function ProviderText(element,key)
    local region=element and element[key]
    if not region or type(region.GetText)~="function" or not region:IsShown() then return false end
    local text=region:GetText()
    if type(issecretvalue)=="function" and issecretvalue(text) then return false end
    return type(text)=="string" and text~=""
end
local function SetText(font,text)
    if font.gearText~=text then font:SetText(text);font.gearText=text end
end
local function Layout(a,row,legacy,wide)
    if a.legacy==legacy and a.wide==wide then return end
    a.legacy,a.wide=legacy,wide
    if wide then
        local right=rightSide[row.slot] and row.slot~=16
        a.host:SetSize(222,46);a.host:ClearAllPoints()
        a.host:SetPoint(right and "TOPRIGHT" or "TOPLEFT",a.slot,right and "TOPRIGHT" or "TOPLEFT",right and 4 or -4,4)
        -- The real item button and any provider labels remain ABOVE our card.
        a.host:SetFrameLevel(math.max(1,a.slot:GetFrameLevel()-1))
        a.status:SetFrameLevel(a.host:GetFrameLevel())
        a.levelHost:SetFrameLevel(a.slot:GetFrameLevel()+2)
        a.status:SetSize(222,46);a.status:EnableMouse(true)
        NS.Surface.SkinOwnedButton(a.status,wideSpec)
        local x=right and 9 or 49
        a.name:ClearAllPoints();a.name:SetPoint("TOPLEFT",x,-5);a.name:SetSize(164,14)
        a.enchant:ClearAllPoints();a.enchant:SetPoint("TOPLEFT",x+14,-21);a.enchant:SetSize(150,12)
        a.track:ClearAllPoints();a.track:SetPoint("TOPLEFT",x+14,-32);a.track:SetSize(84,10)
        a.enchantMark:ClearAllPoints();a.enchantMark:SetPoint("TOPLEFT",x,-21)
        a.enchantCheck:ClearAllPoints();a.enchantCheck:SetPoint("TOPLEFT",x,-21)
        a.upgradeMark:ClearAllPoints();a.upgradeMark:SetPoint("TOPLEFT",x,-32)
        a.upgradeCheck:ClearAllPoints();a.upgradeCheck:SetPoint("TOPLEFT",x,-32)
        a.upgradeBack:ClearAllPoints();a.upgradeBack:SetPoint("TOPLEFT",x+14,-43)
        a.upgradeFill:ClearAllPoints();a.upgradeFill:SetPoint("TOPLEFT",x+14,-43)
        a.qualityRail:ClearAllPoints();a.qualityRail:SetPoint(right and "TOPRIGHT" or "TOPLEFT",right and -1 or 1,-4)
        a.qualityRail:Show();a.upgradeBack:Show()
        a.enchant:SetJustifyH("LEFT");a.track:SetJustifyH("LEFT")
        for i,gem in ipairs(a.gems) do
            gem:SetSize(12,12);gem:ClearAllPoints()
            gem:SetPoint("TOPLEFT",a.host,"TOPLEFT",x+109+(i-1)*14,-33)
        end
        a.name:Show()
        return
    end
    a.name:Hide();a.qualityRail:Hide();a.enchantMark:Hide();a.enchantCheck:Hide()
    a.upgradeMark:Hide();a.upgradeCheck:Hide();a.upgradeBack:Hide();a.upgradeFill:Hide()
    a.host:SetFrameLevel(a.slot:GetFrameLevel()+10)
    a.status:SetFrameLevel(a.host:GetFrameLevel()+1)
    a.levelHost:SetFrameLevel(a.slot:GetFrameLevel()+12)
    local right=rightSide[row.slot]
    local weapon=row.slot==16 or row.slot==17
    local width=legacy and 96 or 82
    a.host:SetSize(width,30);a.host:ClearAllPoints()
    -- PaperDollFrame.xml: head/hands align to Inset; the model controls sit
    -- below their top edge. Keep our first strip above those controls and the
    -- socket dock within 43px of the item edge (4*10px + 3*1px gaps).
    -- Weapons use the bottom of their own slot, below the wrist info dock.
    a.host:SetPoint(right and "TOPRIGHT" or "TOPLEFT",a.slot,right and "TOPLEFT" or "TOPRIGHT",right and -6 or 6,
        legacy and -1 or weapon and (14-a.slot:GetHeight()) or (row.slot==1 or row.slot==10) and 3 or -2)
    a.status:SetSize(width,14)
    a.enchant:ClearAllPoints();a.track:ClearAllPoints()
    if legacy then
        a.enchant:SetPoint("TOPLEFT",0,-17);a.enchant:SetSize(96,14)
        a.track:SetPoint("TOPLEFT",right and 0 or 54,0);a.track:SetSize(42,14)
    else
        a.enchant:SetPoint(right and "TOPRIGHT" or "TOPLEFT",right and -2 or 2,0);a.enchant:SetSize(50,14)
        a.track:SetPoint(right and "TOPLEFT" or "TOPRIGHT",right and 2 or -2,0);a.track:SetSize(26,14)
    end
    a.enchant:SetJustifyH(right and "RIGHT" or "LEFT")
    a.track:SetJustifyH(right and "LEFT" or "RIGHT")
    for i,gem in ipairs(a.gems) do
        local size,step=legacy and 12 or 10,legacy and 13 or 11
        gem:SetSize(size,size);gem:ClearAllPoints()
        gem:SetPoint(right and "TOPRIGHT" or "TOPLEFT",a.host,right and "TOPRIGHT" or "TOPLEFT",
            (i-1)*step*(right and -1 or 1),legacy and 0 or weapon and 12 or -17)
    end
    a.status:EnableMouse(not legacy)
    NS.Surface.SkinOwnedButton(a.status,compactSpec)
    NS.Surface.SetVisible(a.status,not legacy)
end
local function Create(v,row,slot)
    local a={fonts={},gems={},slot=slot};row.annotation=a
    local host=CreateFrame("Frame",nil,v.host);a.host=host
    host:EnableMouse(false);host:SetFrameLevel(slot:GetFrameLevel()+10)
    local status=CreateFrame("Button",nil,host);a.status=status;status:SetPoint("TOPLEFT")
    if status.SetPropagateMouseClicks then status:SetPropagateMouseClicks(true) end
    NS.Surface.SkinOwnedButton(status,compactSpec)
    status:SetScript("OnEnter",function() ShowDetails(v,row,status) end)
    status:SetScript("OnLeave",function() Leave(status) end)
    a.name=Font(status,12);a.name:SetJustifyH("LEFT");a.name:Hide()
    a.enchant=Font(status,10);a.track=Font(status,9)
    -- Shape + color convey the state even with provider-owned annotation text.
    -- The small native atlas is verified in upstream/live ContentTrackingElement.xml.
    a.enchantMark=Font(status,11);a.upgradeMark=Font(status,11)
    a.enchantMark:SetSize(10,12);a.upgradeMark:SetSize(10,12)
    a.enchantCheck=status:CreateTexture(nil,"OVERLAY");a.enchantCheck:SetAtlas("checkmark-minimal")
    a.upgradeCheck=status:CreateTexture(nil,"OVERLAY");a.upgradeCheck:SetAtlas("checkmark-minimal")
    a.enchantCheck:SetDesaturated(true);a.upgradeCheck:SetDesaturated(true)
    a.enchantCheck:SetSize(10,10);a.upgradeCheck:SetSize(10,10)
    a.qualityRail=status:CreateTexture(nil,"ARTWORK");a.qualityRail:SetSize(2,38)
    a.upgradeBack=status:CreateTexture(nil,"ARTWORK");a.upgradeBack:SetSize(84,2)
    a.upgradeFill=status:CreateTexture(nil,"OVERLAY");a.upgradeFill:SetSize(84,2)
    local levelHost=CreateFrame("Frame",nil,host);a.levelHost=levelHost
    levelHost:SetSize(1,1);levelHost:SetPoint("TOPLEFT",slot,"TOPLEFT",0,0);levelHost:EnableMouse(false)
    a.levelBack=levelHost:CreateTexture(nil,"BACKGROUND");a.levelBack:SetSize(28,14)
    a.levelBack:SetPoint("TOPRIGHT",slot,"TOPRIGHT",-1,0)
    a.level=Font(levelHost,12);a.level:SetPoint("TOPRIGHT",slot,"TOPRIGHT",-2,-1);a.level:SetJustifyH("RIGHT")
    a.fonts={a.name,a.enchant,a.track,a.level,a.enchantMark,a.upgradeMark}
    for i=1,4 do
        local gem=CreateFrame("Button",nil,host);a.gems[i]=gem
        if gem.SetPropagateMouseClicks then gem:SetPropagateMouseClicks(true) end
        gem.icon=gem:CreateTexture(nil,"ARTWORK");gem.icon:SetAllPoints()
        gem:SetScript("OnEnter",function()
            if not GameTooltip then return end
            GameTooltip:SetOwner(gem,"ANCHOR_RIGHT")
            if gem.link then GameTooltip:SetHyperlink(gem.link)
            else GameTooltip:SetText(gem.status=="empty" and NS.L.GEAR_SOCKET_EMPTY or NS.L.GEAR_GEM_UNKNOWN) end
            GameTooltip:Show()
        end)
        gem:SetScript("OnLeave",function() Leave(gem) end)
    end
    return a
end
function Gear.Paint(v,row)
    local a=row.annotation
    if not a then return end
    local path=GameFontNormal and GameFontNormal:GetFont() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if path~=a.path then
        for _,font in ipairs(a.fonts) do font:SetFont(path,font.gearSize,"") end
        a.path=path
    end
    local info=row.audit
    if info then
        a.enchant:SetTextColor(NS.Theme.GetColor(a.statusToken or "muted"))
        a.track:SetTextColor(NS.Theme.GetColor(a.wide and a.upgradeToken or (info.upgradeCurrent==info.upgradeMax and "dim" or "muted")))
        local r,g,b,alpha=NS.Theme.GetColor("ink")
        a.levelBack:SetColorTexture(r,g,b,alpha*NS.Theme.GetMaterialOpacity(NS.Materials.input))
        local color=info.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality]
        if color then a.level:SetTextColor(color.r,color.g,color.b,1) else a.level:SetTextColor(NS.Theme.GetColor("text")) end
        if color then
            a.name:SetTextColor(color.r,color.g,color.b,1)
            a.qualityRail:SetColorTexture(color.r,color.g,color.b,.9)
        else
            a.name:SetTextColor(NS.Theme.GetColor("text"))
            a.qualityRail:SetColorTexture(NS.Theme.GetColor("muted"))
        end
        a.enchantMark:SetTextColor(NS.Theme.GetColor(a.statusToken or "muted"))
        a.enchantCheck:SetVertexColor(NS.Theme.GetColor(a.statusToken or "muted"))
        a.upgradeMark:SetTextColor(NS.Theme.GetColor(a.upgradeToken or "muted"))
        a.upgradeCheck:SetVertexColor(NS.Theme.GetColor(a.upgradeToken or "muted"))
        a.upgradeFill:SetColorTexture(NS.Theme.GetColor(a.upgradeToken or "muted"))
        local br,bg,bb=NS.Theme.GetColor("muted")
        a.upgradeBack:SetColorTexture(br,bg,bb,.2)
    end
end
local function CompactStatus(info)
    if info.missingEnchant then return NS.L.GEAR_ENCHANT_MISSING_SHORT,"danger" end
    if info.emptySockets and info.emptySockets>0 then return string.format(NS.L.GEAR_EMPTY_COMPACT,info.emptySockets),"danger" end
    if info.enchantRank then return string.format(NS.L.GEAR_ENCHANT_COMPACT,info.enchantRank,2),info.lowEnchant and "warning" or "muted" end
    if info.enchanted then return NS.L.GEAR_ENCHANT_PRESENT_SHORT,"muted" end
    if info.pending or info.enchantApplicable==nil then return NS.L.GEAR_UNKNOWN_COMPACT,"muted" end
    return "","muted"
end
local function WideState(a,info)
    local mark,token,state="?","muted","unknown"
    if info.missingEnchant then mark,token,state="!","danger","missing"
    elseif info.enchanted then
        mark,token,state=info.lowEnchant and "!" or "",info.lowEnchant and "warning" or "success",info.lowEnchant and "low" or "present"
    elseif info.enchantApplicable==false then mark,state="-","not-needed" end
    a.enchantState,a.statusToken=state,token
    SetText(a.enchantMark,mark);a.enchantMark:SetShown(state~="present");a.enchantCheck:SetShown(state=="present")

    -- Only exposed, validated current/max levels imply a completion percentage.
    -- Missing metadata is not proof of MAX or of a non-upgradeable item.
    local current,maximum=info.upgradeCurrent,info.upgradeMax
    local valid=type(current)=="number" and type(maximum)=="number" and current>=0 and maximum>0 and current<=maximum
    local complete=valid and current==maximum
    a.upgradeState=valid and (complete and "max" or "available") or "unknown"
    a.upgradeToken=valid and (complete and "success" or "warning") or "muted"
    SetText(a.upgradeMark,valid and "+" or "?")
    a.upgradeMark:SetShown(not complete);a.upgradeCheck:SetShown(complete)
    local ratio=valid and current/maximum or 0
    if ratio~=a.upgradeRatio then a.upgradeFill:SetWidth(math.max(1,84*ratio));a.upgradeRatio=ratio end
    a.upgradeFill:SetShown(valid and ratio>0)
end
local function EnchantName(a,info)
    local text=info.enchantText or info.enchantLabel or ""
    if a.fullEnchant~=text then
        a.fullEnchant=text
        -- Strip only the exact localized Blizzard tooltip prefix, never guess
        -- item/enchant names. Full unmodified text is retained in the snapshot.
        local format=ENCHANTED_TOOLTIP_LINE
        local prefix=type(format)=="string" and format:match("^(.-)%%s")
        if prefix and text:sub(1,#prefix)==prefix then text=text:sub(#prefix+1) end
        a.enchantName=text:match("^%s*(.-)%s*$")
    end
    return a.enchantName
end
function Gear.Update(v,row,slotName)
    if NS.IsCombatLocked() then return end
    local slot=v.kind=="character" and _G["Character"..slotName]
    local config=NS.DB.characterDetails
    local inline=config.view and config.view=="modern" or (not config.view and config.inlineGear)
    if not inline or not slot or not NS.Safety.CanCreateRegions(slot,true) then
        Hide(row.annotation);return
    end
    local info=row.audit
    if not info or not info.link then Hide(row.annotation);return end
    local a=row.annotation or Create(v,row,slot)
    local provider=_G.EnhanceQoL
    local element=provider and provider.variables and provider.variables.itemSlots and provider.variables.itemSlots[row.slot]
    if element~=slot then element=nil end
    -- Coexist field-by-field. Never cover an existing provider annotation.
    local externalEnchant,externalTrack=ProviderText(element,"enchant"),ProviderText(element,"trackLabel")
    local wide=v.wide==true
    local legacy=not wide and (externalEnchant or externalTrack) or false
    Layout(a,row,legacy,wide)
    local status,token=CompactStatus(info);a.statusToken=token
    local progress=info.upgradeText and (info.upgradeCurrent==info.upgradeMax and NS.L.GEAR_UPGRADE_MAX or info.upgradeText) or ""
    if wide then
        WideState(a,info)
        status=info.missingEnchant and NS.L.GEAR_ENCHANT_MISSING or info.enchanted and EnchantName(a,info)
            or info.enchantApplicable==false and NS.L.GEAR_ENCHANT_NOT_NEEDED or NS.L.GEAR_UNVERIFIED
        if a.enchantState=="low" then
            if a.lowName~=status then a.lowName=status;a.lowText="1/2  "..status end
            status=a.lowText
        end
        if a.upgradeState=="unknown" then progress=NS.L.GEAR_UPGRADE_UNKNOWN
        elseif info.upgradeTrack and progress~="" then progress=info.upgradeTrack.."  "..progress end
        SetText(a.name,info.name or NS.L.DOSSIER_LOADING)
    end
    SetText(a.enchant,status)
    SetText(a.track,progress)
    SetText(a.level,info.itemLevel and string.format("%d",info.itemLevel) or "--")
    a.enchant:SetShown(not externalEnchant);a.track:SetShown(not externalTrack)
    a.status:SetShown(wide or (not externalEnchant and status~="") or (not externalTrack and info.upgradeText~=nil))
    if not a.status:IsShown() then Leave(a.status) end
    local showLevel=not ProviderText(element,"ilvl")
    a.level:SetShown(showLevel);a.levelBack:SetShown(showLevel)
    for i,gem in ipairs(a.gems) do
        local source=info.gemInfo and info.gemInfo[i]
        local external=element and element.gems and element.gems[i]
        local visible=info.sockets and i<=info.sockets and not (external and external:IsShown())
        gem.link=source and source.link
        gem.status=source and source.id and "filled" or info.gemSlotsKnown and "empty" or "unknown"
        gem:SetShown(visible==true)
        if visible then
            gem.icon:SetTexture(source and source.texture or (gem.status=="empty"
                and "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic" or "Interface\\Icons\\INV_Misc_QuestionMark"))
            if gem.status=="empty" then gem.icon:SetVertexColor(NS.Theme.GetColor("danger"))
            else gem.icon:SetVertexColor(1,1,1,1) end
        elseif GameTooltip and GameTooltip:IsOwned(gem) then GameTooltip:Hide() end
    end
    Gear.Paint(v,row);a.host:Show()
end
function Gear.Hide(v)
    for _,row in ipairs(v.rows) do
        Hide(row.annotation)
    end
end
return Gear
