local _,P=...;local NS,S=P.NS,P.Suite
-- Action bars. Bars 1-10 are suite-owned SecureHandlerStateTemplate headers
-- holding twelve "ActionButtonTemplate, SecureActionButtonTemplate" buttons.
-- That pair is the combination Blizzard's own flyout code supports: the
-- template supplies the visual regions and the secure flyout plumbing, but
-- not ActionBarActionButtonMixin, so no suite button ever joins Blizzard's
-- broadcaster lists or runs Blizzard's paint code under suite taint. The
-- suite paints every region itself (Paint.lua). Bars 11/12 adopt Blizzard's
-- stance and pet buttons, which Blizzard keeps painting untainted.
-- ActionBars/*.lua share this table. Loading touches nothing in the client:
-- frames exist only after the module is first enabled.
local AB={M={},SNIPPET={},bars={},records={},owned={},adopted={}}
P.ActionBars=AB
local M=AB.M
S.Install("actionbars",M)
local floor,ceil,max,min=math.floor,math.ceil,math.max,math.min
local BAR_COUNT,BUTTONS=12,12
AB.BAR_COUNT,AB.BUTTONS=BAR_COUNT,BUTTONS

-- Slot of button 1 per owned bar; bar 1 pages from slot 1.
AB.FIRST_SLOT={1,61,49,25,37,145,157,169,13,109}
-- Binding command prefix per bar. Bars 9/10 have no Blizzard counterpart.
AB.COMMANDS={"ACTIONBUTTON","MULTIACTIONBAR1BUTTON","MULTIACTIONBAR2BUTTON","MULTIACTIONBAR3BUTTON",
    "MULTIACTIONBAR4BUTTON","MULTIACTIONBAR5BUTTON","MULTIACTIONBAR6BUTTON","MULTIACTIONBAR7BUTTON",
    "MSUFSUITE_BAR9_BUTTON","MSUFSUITE_BAR10_BUTTON","SHAPESHIFTBUTTON","BONUSACTIONBUTTON"}
-- Blizzard bar and button prefix replaced by bars 1-8.
AB.NATIVE_BARS={"MainActionBar","MultiBarBottomLeft","MultiBarBottomRight","MultiBarRight","MultiBarLeft",
    "MultiBar5","MultiBar6","MultiBar7"}
AB.NATIVE_BUTTONS={"ActionButton","MultiBarBottomLeftButton","MultiBarBottomRightButton","MultiBarRightButton",
    "MultiBarLeftButton","MultiBar5Button","MultiBar6Button","MultiBar7Button"}

-- Setting names per bar, built once so hot paths never concatenate keys.
local SUFFIXES={"Visibility","Alpha","FadeAlpha","Buttons","Rows","Size","Spacing","Vertical","Start","ShowEmpty",
    "ClickThrough","Point","X","Y","Keybind","KeybindSize","Macro","MacroSize","CountSize","CooldownSize",
    "Background","BackgroundColor","BackgroundAlpha","BackgroundPadding"}
AB.KEYS={}
for i=1,BAR_COUNT do
    local keys={}
    for _,suffix in ipairs(SUFFIXES) do keys[suffix]="bar"..i..suffix end
    AB.KEYS[i]=keys
end

function AB.Frame(name)
    local frame=_G[name]
    if frame and not NS.Safety.IsForbidden(frame) then return frame end
end

local function ToggleCount()
    if type(GetActionBarToggles)~="function" then return 4 end
    return select("#",GetActionBarToggles())
end

-- Whether a bar exists on this client. Slots 145-180 (bars 6-8) exist only
-- where the client ships MultiBar5-7 and offers their seven visibility toggles.
function AB.Available(index)
    if type(index)~="number" or index<1 or index>BAR_COUNT or index~=floor(index) then return false end
    if index==11 then return AB.Frame("StanceBar")~=nil and AB.Frame("StanceButton1")~=nil end
    if index==12 then return AB.Frame("PetActionBar")~=nil and AB.Frame("PetActionButton1")~=nil end
    if index>=6 and index<=8 then return AB.Frame(AB.NATIVE_BARS[index])~=nil and ToggleCount()>=index-1 end
    return true
end
S.ActionBarAvailable=AB.Available

-- Layout contract shared with the menu preview. n buttons, R = clamp(rows).
-- Rows first: perRow = ceil(n/R), rows = ceil(n/perRow). Columns first:
-- perColumn = R, columns = ceil(n/R), rows = min(R, n).
function AB.Grid(n,rows,vertical)
    n=max(1,floor(n))
    local r=min(max(floor(rows),1),n)
    if vertical then return ceil(n/r),min(r,n),r end
    local per=ceil(n/r)
    return per,ceil(n/per),r
end
-- Cell of 0-based button i. Row 0 is the top row and column 0 the left
-- column for "Top left"; 2 mirrors columns, 3 mirrors rows, 4 both.
function AB.Cell(i,columns,rows,r,vertical,start)
    local col,row
    if vertical then row,col=i%r,floor(i/r) else col,row=i%columns,floor(i/columns) end
    if start==2 or start==4 then col=columns-1-col end
    if start==3 or start==4 then row=rows-1-row end
    return col,row
end

-- Rounds UI units to whole physical pixels at the root scale.
function AB.Snap(value)
    local height=type(GetPhysicalScreenSize)=="function" and select(2,GetPhysicalScreenSize())
    local scale=UIParent and UIParent:GetEffectiveScale()
    if not S.Public(height) or not S.Public(scale) or type(height)~="number" or type(scale)~="number"
        or height<=0 or scale<=0 then return value end
    local unit=768/height/scale
    return floor(value/unit+.5)*unit
end

-- Stance buttons follow the class's forms; everything else the setting.
function AB.Count(bar,config)
    local n=config[bar.key.Buttons]
    if bar.index==11 then
        local forms=type(GetNumShapeshiftForms)=="function" and GetNumShapeshiftForms() or 0
        n=min(n,S.Public(forms) and type(forms)=="number" and forms or 0)
    end
    return n
end

-- Menu preview description; plain values, no frames.
function S.ActionBarPreviewInfo(index)
    if not AB.Available(index) then return nil end
    local c,k=S.Config("actionbars"),AB.KEYS[index]
    local n,size,spacing,vertical=c[k.Buttons],c[k.Size],c[k.Spacing],c[k.Vertical]
    local columns,rows,r=AB.Grid(n,c[k.Rows],vertical)
    return {buttons=n,rows=r,columns=columns,rowCount=rows,size=size,spacing=spacing,vertical=vertical,
        start=c[k.Start],width=columns*size+(columns-1)*spacing,height=rows*size+(rows-1)*spacing}
end

-- Restricted snippets. Button visibility: inside the button count, and
-- filled unless empty slots are shown or a drag reveal bit (2 and up) is
-- set. Press-and-hold follows the spell and keeps its value when the
-- action identity is unreadable, so empower casts never flip mid-fight.
AB.SNIPPET.BUTTON=[[
local bar=self:GetParent()
local action=self:GetAttribute("action")
local show=action and (self:GetAttribute("index") or 1)<=(bar:GetAttribute("count") or 12)
if show and not bar:GetAttribute("showempty") and (bar:GetAttribute("gridmask") or 0)<2 and not HasAction(action) then show=false end
if show then self:Show() else self:Hide() end
if action and IsPressHoldReleaseSpell then
    local kind,id=GetActionInfo(action)
    local hold
    if kind=="spell" and id then hold=IsPressHoldReleaseSpell(id) and true or false elseif kind then hold=false end
    if hold~=nil and self:GetAttribute("pressAndHoldAction")~=hold then self:SetAttribute("pressAndHoldAction",hold) end
end
]]
-- Header visibility from its "vis" driver state; placement previews and
-- drag reveals (both set out of combat) keep the bar shown.
AB.SNIPPET.VIS=[[
if self:GetAttribute("state-vis")~="hide" or self:GetAttribute("forceshow") or self:GetAttribute("dragshow") then self:Show() else self:Hide() end
]]
-- Grid controller: sets or clears one reveal bit on every owned bar. The
-- restricted environment has no bit library, so bits use division.
AB.SNIPPET.REVEAL=[[
local bit,on=...
for i=1,10 do
    local bar=self:GetFrameRef("bar"..i)
    if bar then
        local mask=bar:GetAttribute("gridmask") or 0
        if (floor(mask/bit)%2==1)~=on then
            bar:SetAttribute("gridmask",on and mask+bit or mask-bit)
            bar:ChildUpdate("grid")
        end
    end
end
]]
-- Mouse clicks act on release like Blizzard's buttons; key clicks (routed
-- with the "Keybind" button) follow ActionButtonUseKeyDown. Press-and-hold
-- spells still start on the press through SecureActionButton_OnClick.
AB.SNIPPET.CLICK=[[
local key=button=="Keybind"
local wanted=key and control:GetAttribute("keydown") and true or false
if self:GetAttribute("useOnKeyDown")~=wanted then self:SetAttribute("useOnKeyDown",wanted) end
if key then return "LeftButton" end
]]
-- Pickups mirror Blizzard's rule (unlocked bars or the pickup modifier)
-- and reveal empty slots on every owned bar, also in combat.
AB.SNIPPET.DRAG=[[
if control:GetAttribute("unlocked") or IsModifiedClick("PICKUPACTION") then
    local action=self:GetAttribute("action")
    if action and HasAction(action) then
        control:RunAttribute("msuf-reveal",4,true)
        return "action",action
    end
end
return false
]]
-- Drops place the cursor into the slot. Dropping on an empty slot ends the
-- drag, so the reveal clears; the target itself stays shown for its action.
AB.SNIPPET.RECEIVE=[[
local action=self:GetAttribute("action")
if kind and action then
    if not HasAction(action) then
        control:RunAttribute("msuf-reveal",4,false)
        self:Show()
    end
    return "action",action
end
]]

-- Runs a snippet against a header out of combat, so any Blizzard script a
-- secure Show/Hide/SetParent triggers runs untainted.
function AB.Execute(frame,body)
    if not frame or NS.IsCombatLocked() or type(SecureHandlerExecute)~="function" then return false end
    SecureHandlerExecute(frame,body)
    return true
end

local function HeaderAttribute(header,name,value)
    local bar=AB.headers and AB.headers[header]
    if bar and AB.OnHeaderAttribute then AB.OnHeaderAttribute(bar,name,value) end
end

local function NewHeader(index)
    local header=S.CreateFrame("Frame","MSUFSuiteBar"..index,UIParent,"SecureHandlerStateTemplate")
    header:SetFrameStrata("MEDIUM")
    header:SetSize(1,1)
    header:SetPoint("CENTER",UIParent,"CENTER",0,0)
    header:SetAttribute("_onstate-vis",AB.SNIPPET.VIS)
    local background=S.CreateTexture(header,nil,"BACKGROUND",nil,-8)
    background:Hide()
    local bar={index=index,header=header,buttons={},filled={},background=background,key=AB.KEYS[index],owned=index<=10}
    AB.bars[index]=bar
    AB.headers=AB.headers or {}
    AB.headers[header]=bar
    -- Insecure post-hook: learns page and visibility changes the restricted
    -- handlers make in combat. It only paints and never touches attributes.
    header:HookScript("OnAttributeChanged",HeaderAttribute)
    return bar
end

local function NewButton(bar,index)
    local name="MSUFSuiteBar"..bar.index.."Button"..index
    local button=S.CreateFrame("CheckButton",name,bar.header,"ActionButtonTemplate, SecureActionButtonTemplate")
    local slot=AB.FIRST_SLOT[bar.index]+index-1
    button:SetAttribute("type","action")
    button:SetAttribute("typerelease","actionrelease")
    button:SetAttribute("checkselfcast",true)
    button:SetAttribute("checkfocuscast",true)
    button:SetAttribute("checkmouseovercast",true)
    button:SetAttribute("index",index)
    button:SetAttribute("action",slot)
    button:SetAttribute("_childupdate-grid",AB.SNIPPET.BUTTON)
    button:RegisterForClicks("AnyDown","AnyUp")
    button:RegisterForDrag("LeftButton","RightButton")
    SecureHandlerWrapScript(button,"OnClick",AB.grid,AB.SNIPPET.CLICK)
    SecureHandlerWrapScript(button,"OnDragStart",AB.grid,AB.SNIPPET.DRAG)
    SecureHandlerWrapScript(button,"OnReceiveDrag",AB.grid,AB.SNIPPET.RECEIVE)
    local rec={button=button,bar=bar,index=index,slot=slot,base=slot,name=name,owned=true,
        command=AB.COMMANDS[bar.index]..index}
    AB.records[button]=rec
    bar.buttons[index]=rec
    AB.owned[#AB.owned+1]=rec
    return rec
end

-- Creates every suite frame once per session (out of combat, on enable).
function AB.Build()
    if AB.built then return end
    AB.built=true
    local grid=S.CreateFrame("Frame",nil,UIParent,"SecureHandlerBaseTemplate")
    grid:SetAttribute("msuf-reveal",AB.SNIPPET.REVEAL)
    AB.grid=grid
    for index=1,10 do
        if AB.Available(index) then
            local bar=NewHeader(index)
            SecureHandlerSetFrameRef(grid,"bar"..index,bar.header)
            for i=1,BUTTONS do NewButton(bar,i) end
        end
    end
    for index=11,12 do if AB.Available(index) then NewHeader(index) end end
end

local function FlyoutDirection(header,columns,rows)
    local x,y=header:GetCenter()
    local width,height=UIParent:GetWidth(),UIParent:GetHeight()
    if not (S.Public(x) and S.Public(y) and S.Public(width) and S.Public(height)) or type(x)~="number" or type(y)~="number" then
        return columns>=rows and "UP" or "LEFT"
    end
    if columns>=rows then return y>height/2 and "DOWN" or "UP" end
    return x>width/2 and "LEFT" or "RIGHT"
end

-- Positions a bar and its buttons from the layout contract. Protected
-- geometry: callers run it out of combat only.
function AB.LayoutBar(bar)
    local c,k,header=M.config,bar.key,bar.header
    local count=AB.Count(bar,c)
    local vertical,start=c[k.Vertical],c[k.Start]
    local columns,rows,r=AB.Grid(max(count,1),c[k.Rows],vertical)
    local size,spacing=AB.Snap(c[k.Size]),AB.Snap(c[k.Spacing])
    local step=size+spacing
    header:SetSize(columns*size+(columns-1)*spacing,rows*size+(rows-1)*spacing)
    local point=NS.ActionBarAnchorPoints[c[k.Point]] or "CENTER"
    header:ClearAllPoints()
    header:SetPoint(point,UIParent,point,AB.Snap(c[k.X]),AB.Snap(c[k.Y]))
    for i=1,min(count,#bar.buttons) do
        local button=bar.buttons[i].button
        local col,row=AB.Cell(i-1,columns,rows,r,vertical,start)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT",header,"TOPLEFT",col*step,-row*step)
        button:SetSize(size,size)
    end
    bar.count,bar.size=count,size
    local mouse=not c[k.ClickThrough]
    if bar.owned then
        local direction=FlyoutDirection(header,columns,rows)
        for i=1,#bar.buttons do
            local button=bar.buttons[i].button
            if button:GetAttribute("flyoutDirection")~=direction then button:SetAttribute("flyoutDirection",direction) end
            button:EnableMouse(mouse)
        end
        header:SetAttribute("count",count)
        header:SetAttribute("showempty",c[k.ShowEmpty] and true or false)
        AB.Execute(header,[[self:ChildUpdate("grid")]])
    else
        for i=1,#bar.buttons do bar.buttons[i].button:EnableMouse(mouse) end
    end
    local background=bar.background
    if c[k.Background] then
        local pad=AB.Snap(c[k.BackgroundPadding])
        local red,green,blue=S.RGB(c[k.BackgroundColor])
        background:ClearAllPoints()
        background:SetPoint("TOPLEFT",header,"TOPLEFT",-pad,pad)
        background:SetPoint("BOTTOMRIGHT",header,"BOTTOMRIGHT",pad,-pad)
        background:SetColorTexture(red,green,blue,c[k.BackgroundAlpha]/100)
        background:Show()
    else
        background:Hide()
    end
end
