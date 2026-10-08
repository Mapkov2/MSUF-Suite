local root=assert(arg[1])
local H=dofile(root..'/tools/tests/suite_minimap_harness.lua')
local W=H.New(root,'Mainline')
local G,S=W.G,W.S
W.LoadAddon('MSUF_Suite_DataTexts')
local M=S.instances.dataTexts
local Layout
for i=1,60 do local name,value=debug.getupvalue(M.UpdateSource,i);if name=='Layout' then Layout=value;break end end
assert(Layout)
M.config=S.Config('dataTexts')
local c=M.config
c.bar1Width=600;c.bar1Height=30;c.bar1Layout=1;c.bar1Slot2Placement=2;c.bar1Slot1Placement=3
local function Widget()
    return {CreateTexture=function() return G.CreateFrame("Frame"):CreateTexture() end,
        GetHeight=function(self) return self.h or 20 end,
        ClearAllPoints=function() end,SetPoint=function(self,p,rel,rp,x,y) self.x=x;self.y=y end,
        SetSize=function(self,w,h) self.w=w;self.h=h end,Show=function() end,Hide=function() end,
        GetUnboundedStringWidth=function() return 1000 end}
end
local bar={prefix='bar1',widthKey='bar1Width',heightKey='bar1Height',layoutKey='bar1Layout',length=600,
    style={gap=6,padding=5,separatorEnabled=false},slots={},dividers={},frame={
        GetWidth=function() return 600 end,SetWidth=function() end,SetHeight=function() end}}
for i=1,6 do local b=Widget();b.label=Widget();b.slot=i;bar.slots[i]=b;if i<=3 then b.source='fps' end end
bar.slots[1].extra={kind='broker',maxWidth=80,icons={}}
for _,mode in ipairs({1,2}) do
    c.bar1Layout=mode;Layout(bar)
    local a,b,d=bar.slots[1],bar.slots[2],bar.slots[3]
    assert(a.w<=80,'broker max width must survive redistribution')
    assert(math.abs(b.x+b.w/2-bar.layoutLength/2)<1,'middle slot must stay exactly centered')
    assert(a.x+a.w<=b.x and d.x>=b.x+b.w,'center/fill slots overlap')
end
c.bar1Layout=1;c.bar1Slot2Placement=1;bar.slots[1].extra=nil
bar.slots[3].source=nil;bar.slots[2].extra={kind='broker',maxWidth=80,icons={}}
Layout(bar)
assert(bar.slots[1].w>300 and bar.slots[1].x+bar.slots[1].w+6<=bar.slots[2].x+1,'fill must consume remaining space')
bar.vertical=true;c.bar1Slot1Scale=150;Layout(bar)
assert(bar.slots[1].w==20 and bar.slots[1].h>200 and bar.slots[2].y<0,'vertical sizing must account for block scale')
assert(W.Suite.DataTextBarLimit==256 and c.bar12Enabled==false,'configuration bounds must protect secure frame creation')
bar.vertical=false;c.bar1Layout=2;c.bar1Width=44;bar.length=44
c.bar1Slot1Placement=1;c.bar1Slot1Scale=100;bar.slots[2].source=nil
bar.slots[1].label.GetUnboundedStringWidth=function() return 60 end
for _, count in ipairs({0,1,2,32,40}) do
    local icons={};for i=1,count do icons[i]=i end
    bar.slots[1].extra={kind='profession',icons=icons}
    Layout(bar)
    local bounded=math.min(count,32)
    local iconWidth=bounded>0 and bounded*14+(bounded-1)*2+4 or 0
    assert(bar.slots[1].w==70+iconWidth,'Fit text did not reserve visible icon width')
end
print('datatext geometry PASS')
