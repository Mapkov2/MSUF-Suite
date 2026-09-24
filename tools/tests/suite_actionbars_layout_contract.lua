local root=assert(arg[1],"repository root required")
-- Offline contract for the action bar layout math, slot/page tables, bar 1
-- paging drivers (Mainline and Classic), visibility drivers and key text.
-- The grid is checked against an independent implementation of the layout
-- contract the menu preview shares.
local Suite={}
MSUFSuite=Suite
MSUF_NS={Client={Family="Mainline",Flavor="Mainline",SupportsEvent=function() return true end}}
SlashCmdList={}
InCombatLockdown=function() return false end
MSUF_PixelLayoutRegion=function(frame) return frame end
SecureHandlerSetFrameRef=function() end
RegisterStateDriver=function() end
local created=0
CreateFrame=function() created=created+1;return {SetScript=function() end,RegisterEvent=function() end} end
UIParent={GetEffectiveScale=function() return 1 end,GetWidth=function() return 1024 end,GetHeight=function() return 768 end}
GetPhysicalScreenSize=function() return 1024,768 end
for _,file in ipairs({"Platform","Database","SuiteCatalog","Catalog/ActionBars","Suite","Bindings"}) do
    assert(loadfile(root.."/MSUF_Suite/Core/"..file..".lua"))("MSUF_Suite",Suite)
end
assert(loadfile(root.."/MSUF_Suite/Integrations/MapkoSkin.lua"))("MSUF_Suite",Suite)
assert(Suite.Database.Initialize(nil));Suite.Suite.Normalize(Suite.DB)
local private={}
for _,file in ipairs({"Surfaces","Runtime","EditMode"}) do
    assert(loadfile(root.."/MSUF_Suite_Modules/"..file..".lua"))("MSUF_Suite_Modules",private)
end
local files={"Bootstrap","Bars","Paging","Blizzard","Visibility",
    "Bindings","Style","Paint","Controller"}
for _,file in ipairs(files) do assert(loadfile(root.."/MSUF_Suite_ActionBars/"..file..".lua"))("MSUF_Suite_ActionBars",private) end
local S,AB=Suite.Suite,private.ActionBars
assert(created==0,"loading the runtime created frames")
assert(S.instances.actionbars==AB.M,"module not installed")
for i=1,12 do
    assert(S.Config("actionbars")["bar"..i.."Visibility"]==4,
        "fallback layout did not start on mouseover: "..i)
end

------------------------------------------------------------------ tables
local expectedSlots={1,61,49,25,37,145,157,169,13,109}
for i=1,10 do assert(AB.FIRST_SLOT[i]==expectedSlots[i],"slot table changed for bar "..i) end
-- Every owned bar except bar 1 shows one whole page.
for i=2,10 do assert((AB.FIRST_SLOT[i]-1)%12==0,"bar "..i.." does not start a page") end
assert(AB.COMMANDS[1]=="ACTIONBUTTON" and AB.COMMANDS[2]=="MULTIACTIONBAR1BUTTON" and AB.COMMANDS[8]=="MULTIACTIONBAR7BUTTON")
assert(AB.COMMANDS[9]=="MSUFSUITE_BAR9_BUTTON" and AB.COMMANDS[10]=="MSUFSUITE_BAR10_BUTTON")
assert(AB.COMMANDS[11]=="SHAPESHIFTBUTTON" and AB.COMMANDS[12]=="BONUSACTIONBUTTON")
assert(BINDING_HEADER_MSUFSUITE=="MSUF Suite" and BINDING_NAME_MSUFSUITE_BAR9_BUTTON1=="Action bar 9 button 1")
assert(BINDING_NAME_MSUFSUITE_BAR10_BUTTON12=="Action bar 10 button 12" and BINDING_HEADER_MSUFSUITE_BAR10=="Action bar 10")
local xml=assert(io.open(root.."/MSUF_Suite/Bindings.xml","rb")):read("*a")
local commands=0
for bar,button in xml:gmatch('name="MSUFSUITE_BAR(%d+)_BUTTON(%d+)"') do
    commands=commands+1
    assert(_G["BINDING_NAME_MSUFSUITE_BAR"..bar.."_BUTTON"..button],"binding without a label")
end
assert(commands==24 and not xml:find("</Binding>",1,true),"Bindings.xml must declare 24 commands without bodies")
-- The page handler assigns index + (page - 1) * 12; the Lua mirror agrees.
local bar={buttons={}}
for i=1,12 do bar.buttons[i]={index=i} end
for page=1,18 do
    AB.PageSlots(bar,page)
    for i=1,12 do assert(bar.buttons[i].slot==i+(page-1)*12) end
end
AB.PageSlots(bar,"vehicle");assert(bar.page==1 and bar.buttons[12].slot==12,"a non-numeric page must fall back to page 1")
assert(AB.SNIPPET.PAGE_CHILD:find("(page-1)*12",1,true),"page rewrite formula changed")

------------------------------------------------------------------ layout
-- Independent reference of the lead's contract.
local function Reference(n,rows,vertical,start)
    local r=math.min(math.max(rows,1),n)
    local columns,rowCount
    if vertical then columns,rowCount=math.ceil(n/r),math.min(r,n) else local per=math.ceil(n/r);columns,rowCount=per,math.ceil(n/per) end
    local cells={}
    for i=0,n-1 do
        local col,row
        if vertical then row,col=i%r,math.floor(i/r) else local per=math.ceil(n/r);col,row=i%per,math.floor(i/per) end
        if start==2 or start==4 then col=columns-1-col end
        if start==3 or start==4 then row=rowCount-1-row end
        cells[i+1]={col,row}
    end
    return columns,rowCount,cells
end
local checked=0
for n=1,12 do
    for rows=1,12 do
        for _,vertical in ipairs({false,true}) do
            for start=1,4 do
                local columns,rowCount,r=AB.Grid(n,rows,vertical)
                local refColumns,refRows,cells=Reference(n,rows,vertical,start)
                assert(columns==refColumns and rowCount==refRows,("grid %d/%d/%s"):format(n,rows,tostring(vertical)))
                local seen={}
                for i=0,n-1 do
                    local col,row=AB.Cell(i,columns,rowCount,r,vertical,start)
                    assert(col==cells[i+1][1] and row==cells[i+1][2],("cell %d of %d/%d/%s/%d"):format(i,n,rows,tostring(vertical),start))
                    assert(col>=0 and col<columns and row>=0 and row<rowCount)
                    local key=col..":"..row
                    assert(not seen[key],"two buttons share a cell");seen[key]=true
                end
                checked=checked+1
            end
        end
    end
end
assert(checked==12*12*2*4)
-- Spot checks: rows first fills a row before the next; columns first fills
-- a column; start corners mirror.
local c,r,rr=AB.Grid(12,5,false);assert(c==3 and r==4 and rr==5,"12 buttons in 5 rows use 4 rows of 3")
c,r=AB.Grid(12,5,true);assert(c==3 and r==5,"12 buttons, 5 per column")
assert(select(1,AB.Cell(1,3,4,5,false,1))==1 and select(2,AB.Cell(3,3,4,5,false,1))==1)
assert(select(2,AB.Cell(1,3,5,5,true,1))==1 and select(1,AB.Cell(5,3,5,5,true,1))==1)
local col,row=AB.Cell(0,12,1,1,false,4);assert(col==11 and row==0,"bottom right mirrors both axes")
col,row=AB.Cell(0,1,12,12,true,3);assert(col==0 and row==11,"bottom left mirrors rows")

-- Header geometry through LayoutBar with plain frame stubs.
local function Region()
    local region={points={}}
    function region:SetSize(w,h) self.width,self.height=w,h end
    function region:ClearAllPoints() self.points={} end
    function region:SetPoint(...) self.points[#self.points+1]={...} end
    function region:GetCenter() return 512,100 end
    function region:SetAttribute(k,v) self[k]=v end
    function region:GetAttribute(k) return self[k] end
    function region:EnableMouse(v) self.mouse=v end
    function region:Hide() self.shown=false end
    function region:Show() self.shown=true end
    function region:SetColorTexture(...) self.color={...} end
    return region
end
AB.M.config=S.Config("actionbars")
local config=AB.M.config
local header=Region()
local layout={index=4,key=AB.KEYS[4],header=header,buttons={},owned=false,background=Region()}
for i=1,12 do layout.buttons[i]={button=Region(),index=i} end
config.bar4Buttons,config.bar4Rows,config.bar4Size,config.bar4Spacing=7,3,20,-4
config.bar4Vertical,config.bar4Start=false,4
config.bar4Point,config.bar4X,config.bar4Y=9,-12,34
AB.LayoutBar(layout)
-- 7 buttons in 3 rows: 3 per row, 3 rows; step 16; bar 3*20-2*4 wide.
assert(header.width==52 and header.height==52,"bar size uses size and negative spacing")
assert(header.points[1][1]=="BOTTOMRIGHT" and header.points[1][2]==UIParent and header.points[1][3]=="BOTTOMRIGHT")
assert(header.points[1][4]==-12 and header.points[1][5]==34,"anchor offsets")
local first=layout.buttons[1].button.points[1]
assert(first[1]=="TOPLEFT" and first[4]==32 and first[5]==-32,"bottom right start places button 1 in the last cell")
local seventh=layout.buttons[7].button.points[1]
assert(seventh[4]==32 and seventh[5]==0,"row 2 (0-based) mirrored to the top row")
assert(#layout.buttons[8].button.points==0,"buttons beyond the count keep no layout")
assert(layout.buttons[1].button.width==20 and layout.count==7)
assert(layout.background.shown==false,"background hidden while disabled")
config.bar4Background,config.bar4BackgroundPadding,config.bar4BackgroundColor,config.bar4BackgroundAlpha=true,3,"ff0000",40
AB.LayoutBar(layout)
local bg=layout.background
assert(bg.shown and bg.points[1][4]==-3 and bg.points[1][5]==3 and bg.color[1]==1 and bg.color[4]==.4)
-- Pixel snapping rounds to physical pixels (here 1.5 UI units per pixel).
GetPhysicalScreenSize=function() return 800,512 end
assert(AB.Snap(40)==40.5 and AB.Snap(-4)==-4.5 and AB.Snap(0)==0)
GetPhysicalScreenSize=function() return 1024,768 end

-- Menu preview uses the same math without frames.
local info=S.ActionBarPreviewInfo(4)
assert(info.buttons==7 and info.rows==3 and info.columns==3 and info.rowCount==3 and info.width==52 and info.height==52 and info.start==4)
assert(S.ActionBarPreviewInfo(13)==nil and not S.ActionBarAvailable(0) and not S.ActionBarAvailable(1.5))

------------------------------------------------------------------ paging drivers
local base="[vehicleui] vehicle; [overridebar] override; [possessbar] possess; [shapeshift] shapeshift; "
local manual="[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
local forms="[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; "
local c2={pagingModifiers=false,disableFormPaging=false,disableSkyridingPaging=false,pageShift=2,pageCtrl=3,pageAlt=4}
assert(AB.PageDriver(c2)==base..manual..forms.."[bonusbar:5] 11; 1","default Mainline driver")
assert(not AB.CustomPaging(c2))
c2.disableFormPaging=true
assert(AB.PageDriver(c2)==base..manual.."[bonusbar:5] 11; 1" and AB.CustomPaging(c2))
c2.disableFormPaging,c2.disableSkyridingPaging=false,true
assert(AB.PageDriver(c2)==base..manual..forms.."1" and AB.CustomPaging(c2),"skyriding opt-out")
c2.disableSkyridingPaging,c2.pagingModifiers,c2.pageShift=false,true,6
assert(AB.PageDriver(c2)==base.."[mod:shift] 6; [mod:ctrl] 3; [mod:alt] 4; "..manual..forms.."[bonusbar:5] 11; 1")
assert(AB.CustomPaging(c2),"modifier paging must route bar 1 keys to suite buttons")
-- Classic: bonus bar 5 is the possess bar and always pages.
local flavor=Suite.Client.flavor
Suite.Client.flavor="Vanilla"
c2.pagingModifiers,c2.disableSkyridingPaging=false,true
assert(AB.PageDriver(c2)==base..manual..forms.."[bonusbar:5] 11; 1" and not AB.CustomPaging(c2),"Classic keeps possess paging")
Suite.Client.flavor=flavor

------------------------------------------------------------------ visibility drivers
local modes={"show","[combat] show; hide","[combat] hide; show","fade","[combat] show; fade"}
for mode=1,5 do
    assert(AB.VisibilityDriver(1,mode,true)=="[petbattle][vehicleui] hide; "..modes[mode])
    assert(AB.VisibilityDriver(9,mode,false)=="[petbattle][vehicleui] hide; "..modes[mode])
    assert(AB.VisibilityDriver(11,mode,true)=="[petbattle][vehicleui][possessbar] hide; "..modes[mode])
    assert(AB.VisibilityDriver(12,mode,false)=="[petbattle][nopet] hide; "..modes[mode])
    assert(AB.VisibilityDriver(11,mode,false)=="hide","stance bar without forms")
end
for index=1,12 do assert(AB.VisibilityDriver(index,6,true)=="hide","Never") end

------------------------------------------------------------------ key text
GetBindingText=function(key) return "<"..key..">" end
local keyText={["SHIFT-1"]="S1",["CTRL-ALT-2"]="CA2",["BUTTON4"]="M4",["SHIFT-BUTTON5"]="SM5",["MOUSEWHEELUP"]="MwU",
    ["MOUSEWHEELDOWN"]="MwD",["CAPSLOCK"]="Caps",["NUMPAD5"]="N5",["NUMPADPLUS"]="N+",["NUMPADDECIMAL"]="N.",
    ["META-Q"]="MQ",["F"]="F",["SHIFT--"]="S-",["PAD1"]="<PAD1>",["SHIFT-PADLTRIGGER"]="<SHIFT-PADLTRIGGER>"}
for key,text in pairs(keyText) do assert(AB.KeyText(key)==text,key.." -> "..tostring(AB.KeyText(key))) end
assert(AB.KeyText(nil)=="" and AB.KeyText("")=="")
print("Action bars: slot/page tables, binding commands, layout contract (all 1152 grids), geometry, pixel snap, preview, paging and visibility drivers, key text passed")
