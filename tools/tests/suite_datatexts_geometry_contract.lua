local root=assert(arg[1])
local H=dofile(root..'/tools/tests/suite_minimap_harness.lua')
local W=H.New(root,arg[2] or 'Mainline')
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
-- Bar 12 is built on demand: a profile that never showed it stores nothing for it.
assert(W.Suite.DataTextBarLimit==256 and not c.bar12Enabled
    and W.Suite.SuiteCatalog.dataTexts.rules.bar12Enabled.default==false,'configuration bounds must protect secure frame creation')
bar.vertical=false;c.bar1Layout=2;c.bar1Width=44;bar.length=44
c.bar1Slot1Placement=1;c.bar1Slot1Scale=100;bar.slots[2].source=nil
bar.slots[1].label.GetUnboundedStringWidth=function() return 60 end
-- Replacing the fixture text bypasses PaintSlot, which invalidates this cache.
bar.slots[1].layoutTextWidth = nil
for _, count in ipairs({0,1,2,32,40}) do
    local icons={};for i=1,count do icons[i]=i end
    bar.slots[1].extra={kind='profession',icons=icons,padding=5}
    Layout(bar)
    local bounded=math.min(count,32)
    local iconWidth=bounded>0 and bounded*14+(bounded-1)*2+4 or 0
    assert(bar.slots[1].w==70+iconWidth,'Fit text did not reserve visible icon width')
end
local slot = bar.slots[1]
slot.extra = nil
slot.layoutTextWidth = nil
function slot.label:GetUnboundedStringWidth() return 120 end

local function CheckFits(scale, padding, pixel, withIcon)
    c.bar1Slot1Scale, c.bar1Slot1Padding = scale, padding
    bar.pixelUnit = pixel
    slot.extra = withIcon and { kind = "profession", icons = { 123 }, padding = padding } or nil
    Layout(bar)
    local inset = withIcon and slot.iconPadding or slot.labelInset
    local iconWidth = withIcon and 18 or 0
    assert(slot.w - 2 * inset - iconWidth >= 120 - 1e-8,
        ("Fit text clipped a 120-unit label at %d%% scale and %d-unit padding"):format(scale, padding))
end

CheckFits(100, 5, 1)
CheckFits(150, 5, 1)
CheckFits(100, 12, 1)
CheckFits(125, 7, 0.7)
CheckFits(155, 12, 0.7, true)
-- A dynamic value can change measured width while the single Fit slot still
-- fits within its configured minimum. Its native placement stays valid.
slot.extra = nil
bar.length, bar.pixelUnit = 600, 1
local textWidth, placements = 67, 0
function slot.label:GetUnboundedStringWidth() return textWidth end
local nativePlace = slot.SetPoint
function slot:SetPoint(...) placements = placements + 1 return nativePlace(self, ...) end
slot.layoutTextWidth = nil
Layout(bar)
placements = 0
local instructions = 0
debug.sethook(function() instructions = instructions + 100 end, "", 100)
for i = 1, 100 do
    textWidth = 67 + i % 2
    slot.layoutTextWidth = nil
    Layout(bar, true)
end
debug.sethook()
print(("100 steady Fit layouts: %d slot placements, ~%d VM instructions"):format(placements, instructions))
assert(placements == 0, "stable Fit geometry reanchored ordinary slots after a text change: " .. placements)
textWidth, slot.layoutTextWidth = 490, nil
Layout(bar, true)
assert(placements == 1 and slot.w * 1.55 > 600, "a growing Fit slot lost its layout update")
c.bar1Slot1Scale = 100
Layout(bar)
assert(slot.w == 600 and placements == 2, "a style change did not invalidate the Fit placement")
print('datatext geometry PASS')
