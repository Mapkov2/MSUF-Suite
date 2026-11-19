local root=assert(arg[1])
-- Edit Mode's first refill resets each Duration font object (BuffFrame.lua:374);
-- an aura refill (AuraButtonMixin:Update) leaves fonts alone.
local NativeAuraUpdate=function(self)
    for index, button in ipairs(self.auraFrames) do
        button.hasValidInfo = index <= #(self.auraInfo or { {} })
        button.isExample = self.editing == true
        if self.editing then button.Duration:SetFont('native.ttf',10,'');button:SetShown(true)
        elseif index <= #(self.auraInfo or { {} }) then button:SetShown(true);button:Update()
        else button:Hide() end
    end
end
local NativeBuffUpdate=function(self)
    NativeAuraUpdate(self)
    self:RefreshConsolidationFrameVisibility()
end

local captured
local function Region(w,h)
 local r={width=w or 30,height=h or 40,scale=1,alpha=1,points={},shown=true,font={'native.ttf',10,''},color={1,1,1,1},shadow={0,0,0,1},shadowOffset={0,0},coords={0,0,0,1,1,0,1,1}}
 function r:IsObjectType(kind)return self.kind==kind end
 function r:GetWidth()return self.width end
 function r:GetHeight()return self.height end
 function r:GetScale()return self.scale end
 function r:GetAlpha()return self.alpha end
 function r:SetAlpha(v)self.alpha=v end
 function r:GetNumPoints()return #self.points end
 function r:GetPoint(i)return unpack(self.points[i])end
 function r:SetPoint(...)self.points[#self.points+1]={...}end
 function r:ClearAllPoints()self.points={}end
 function r:SetSize(w,h)self.width,self.height=w,h end
 function r:SetScale(s)self.scale=s end
 function r:GetTexCoord()return unpack(self.coords)end
 function r:SetTexCoord(left,right,top,bottom,...)
    if select("#",...)==0 then self.coords={left,top,left,bottom,right,top,right,bottom}
    else self.coords={left,right,top,bottom,...} end
 end
 function r:GetFont()return unpack(self.font)end
 function r:SetFont(...)self.font={...}end
 function r:GetTextColor()return unpack(self.color)end
 function r:SetTextColor(...)self.color={...}end
 function r:GetShadowColor()return unpack(self.shadow)end
 function r:SetShadowColor(...)self.shadow={...}end
 function r:GetShadowOffset()return unpack(self.shadowOffset)end
 function r:SetShadowOffset(...)self.shadowOffset={...}end
 function r:SetAllPoints(parent)self:ClearAllPoints();self:SetPoint('TOPLEFT',parent,'TOPLEFT',0,0);self:SetPoint('BOTTOMRIGHT',parent,'BOTTOMRIGHT',0,0)end
 function r:SetFrameLevel(n)self.level=n end
 function r:GetFrameLevel()return self.level or 1 end
 function r:IsProtected()return false end
 function r:IsShown()return self.shown end
 function r:SetShown(v)self.shown=v end
 function r:Hide()self.shown=false end
 function r:EnableMouse()end
 return r
end
local function Button(shown)
 local b=Region();b.Icon=Region();b.Icon.kind="Texture";b.Count=Region();b.Duration=Region();b.DebuffBorder=Region(40,40);b.TempEnchantBorder=Region(32,32);b.shown=shown
 b.consolidatedAuraCount=shown and 1 or 0
 function b:IsEnabled()return self.enabled~=false end
 function b:ShouldShow()return self:IsEnabled() and self.consolidatedAuraCount>0 end
 function b:Update()self.Count.text='2' end
 return b
end
_G.UIParent=Region();_G.Minimap=Region()
StatusTrayManager={UpdateTrayAndBuffFrameLayout=function()end}
InputUtil={IsGamepadUIEnabled=function()return false end}
AuraFrameEditModeMixin={UpdateAuraButtons=NativeAuraUpdate}
local frame=Region();frame.AuraContainer=Region();frame.auraFrames={Button(true),Button(false)}
local container=frame.AuraContainer
container.isHorizontal,container.iconStride,container.iconPadding=true,12,5
container.addIconsToRight,container.addIconsToTop=false,false
container.currentGridLayoutInfo={isHorizontal=true,iconStride=12,iconPadding=5,
 addIconsToRight=false,addIconsToTop=false,anchor={},layout={}}
AuraContainerMixin={UpdateGridLayout=function(self,auras)
 local cache=self.currentGridLayoutInfo
 for slot,button in ipairs(auras)do
  button:SetSize(30,40)
  if cache.layout.spacing then
   button:ClearAllPoints()
   button:SetPoint('TOPRIGHT',container,'TOPRIGHT',-cache.layout.spacing*(slot-1),0)
  end
 end
 self.currentGridLayoutInfo={isHorizontal=self.isHorizontal,iconStride=self.iconStride,iconPadding=self.iconPadding,
  addIconsToRight=self.addIconsToRight,addIconsToTop=self.addIconsToTop,anchor=cache.anchor,layout=cache.layout}
end}
function frame:ShouldShowAura()return true end
function frame:IsEditing()return self.editing end
function frame:SetIsEditing(editing)self.editing=editing end
function frame:RefreshConsolidationFrameVisibility()end
frame.UpdateAuraButtons=NativeBuffUpdate
function frame:UpdateGridLayout()AuraContainerMixin.UpdateGridLayout(self.AuraContainer,self.auraFrames)end
_G.BuffFrame=frame
local combat, queued=false, nil
local P={NS={IsCombatLocked=function()return combat end,IsSecret=function(v)return type(v)=='table' and v.secret==true end,
 Dispatch=function(fn,...)
  local ok, result=pcall(fn,...)
  return ok and result or nil
 end, Finish=function(fn,...)return true,fn(...)end,
 Safety={IsForbidden=function(r)return r.forbidden==true end},
 HostBridge={PlayerAuraSkin=function()end,PaintIconSkin=function()return false end,WatchIconSkins=function()end}},Suite={}}
local S=P.Suite
S.Finite=function(v)return not P.NS.IsSecret(v) and type(v)=='number' and v==v and v>-math.huge and v<math.huge end
S.CreateFrame=function()return Region()end
S.CreateTexture=function()return Region()end
S.RGB=function()return 0,0,0 end
S.PlaceEdges=function()end
S.ResolveFont=function()return 'modern.ttf' end
S.Queue=function(id)queued=id end
S.Install=function(id,m)captured=m end
hooksecurefunc=function(obj,key,callback)local old=obj[key];obj[key]=function(self,...)local out={old(self,...)};callback(self,...);return unpack(out)end end
assert(loadfile(root .. '/MSUF_Suite_QualityOfLife/PlayerAuraSkins.lua'))('MSUF_Suite_QualityOfLife',P)
P.PlayerAuraSkins.Yield=function()end
P.PlayerAuraSkins.SetLayers=function()end
assert(loadfile(arg[3] or root .. '/MSUF_Suite_QualityOfLife/PlayerAuras.lua'))('MSUF_Suite_QualityOfLife',P)
captured.config={iconWidth=52,iconHeight=26,iconZoom=7,perRow=12,spacing=4,rowSpacing=8,x=-12,y=0,debuffOffset=80,debuffX=0,borderColor='000000',borderSize=2,font='x',fontSize=16,showDuration=true}
captured.context={Event=function()end}
if arg[2] == 'harness' then
 return { frame=frame, Region=Region, Button=Button, module=captured, private=P,
  SetCombat=function(value)combat=value end }
end
if arg[2] then
 local mode=arg[2]
 local b=frame.auraFrames[1]
 local secret={secret=true}
 local prior={GetNumPoints=b.GetNumPoints,GetPoint=b.GetPoint,GetWidth=b.GetWidth,GetScale=b.GetScale,GetFrameLevel=b.GetFrameLevel}
 b:SetPoint('TOPLEFT',frame,'TOPLEFT',7,-9)
 frame.auraFrames[2]:SetShown(true)
 if mode=='count_nil' then b.GetNumPoints=function()end
 elseif mode=='count_secret' then b.GetNumPoints=function()return secret end
 elseif mode=='count_nan' then b.GetNumPoints=function()return 0/0 end
 elseif mode=='point_empty' then b.GetPoint=function()end
 elseif mode=='point_nil' then b.GetPoint=function()return nil end
 elseif mode=='point_partial' then b.GetPoint=function()return 'TOPLEFT' end
 elseif mode=='point_coord_nil' then b.GetPoint=function()return 'TOPLEFT',frame,'TOPLEFT',nil,0 end
 elseif mode=='size_nil' then b.GetWidth=function()end
 elseif mode=='scale_nil' then b.GetScale=function()end
 elseif mode=='scale_secret' then b.GetScale=function()return secret end
 elseif mode=='level_nil' then b.GetFrameLevel=function()end
 elseif mode=='level_secret' then b.GetFrameLevel=function()return secret end
 elseif mode=='forbidden' then b.forbidden=true
 else error('Unknown geometry mode: '..mode) end
 captured:Enable()
 if mode:match('^level_') then
  assert(frame.auraFrames[2].width==52,'an unreadable frame level prevented layout')
 else
  assert(frame.auraFrames[2].width==30,'an unreadable aura left the row partly laid out')
 end
 if not mode:match('^level_') then
  assert(b.width==30 and b.scale==1 and #b.points==1 and b.points[1][4]==7,
   'unavailable original geometry was overwritten')
 end
 for key,value in pairs(prior)do b[key]=value end
 b.forbidden=nil
 frame:UpdateGridLayout()
 assert(b.width==52 and b.height==26,'readable geometry did not recover on the next native layout')
 captured:Disable()
 assert(b.width==30 and b.height==40 and b.scale==1 and #b.points==1 and b.points[1][4]==7,
  'recovered aura did not restore its original native geometry')
 print('Player aura geometry: '..mode..' preserved and recovered')
 return
end
captured:Enable()
assert(frame.auraFrames[1].width==52,'initial buff not styled')
assert(not frame.auraFrames[2].shown and frame.auraFrames[2].width==52
 and frame.auraFrames[2].Duration.font[2]==16,'the inactive physical buff slot was not prepared')
frame.auraFrames[1].IsShown=function()error('ordinary aura visibility read by Suite')end
frame.auraFrames[2].IsShown=frame.auraFrames[1].IsShown
combat=true
frame.auraInfo={{},{}}
frame:UpdateAuraButtons()
assert(frame.auraFrames[2].width==52 and frame.auraFrames[2].height==26,'newly gained buff retained native dimensions')
assert(frame.auraFrames[2].Duration.font[2]==16,'newly gained buff kept the native duration font')
combat=false
frame:SetIsEditing(true)
frame:UpdateAuraButtons()
assert(frame.auraFrames[1].Duration.font[2]==16 and frame.auraFrames[2].Duration.font[2]==16,
 'edit mode refill replaced custom duration font')
frame:SetIsEditing(false)
frame:UpdateAuraButtons()
assert(frame.auraFrames[1].DebuffBorder.width==54 and frame.auraFrames[1].DebuffBorder.height==28)
-- Native consolidation occupies the first slot, and hiding it closes the gap.
frame.ConsolidatedBuffs=Button(true)
frame:UpdateGridLayout()
assert(frame.ConsolidatedBuffs.width==52 and frame.ConsolidatedBuffs.height==26)
assert(frame.ConsolidatedBuffs.points[1][4]==0 and frame.auraFrames[1].points[1][4]==-56,
 'consolidation and first buff must occupy different slots')
frame.ConsolidatedBuffs:Hide()
frame.ConsolidatedBuffs.consolidatedAuraCount=0
frame:UpdateGridLayout()
assert(frame.auraFrames[1].points[1][4]==0,'hidden consolidated button left an empty slot')
-- A later shown button can fail after earlier buttons have already been
-- placed. Restore all of them and retry once that button is readable.
local sizeGrid=frame.UpdateGridLayout
frame.AuraContainer.currentGridLayoutInfo.layout={spacing=35}
frame.UpdateGridLayout=function(self)
 for slot, button in ipairs(self.auraFrames) do
  button:ClearAllPoints()
  button:SetPoint('TOPRIGHT', self.AuraContainer, 'TOPRIGHT', -35*(slot-1), 0)
 end
 sizeGrid(self)
end
local third=Button(false)
frame.auraFrames[3]=third
local before=third.GetScale
third.GetScale=function()return nil end
frame.auraInfo={{},{},{}}
frame:UpdateAuraButtons()
assert(frame.auraFrames[1].width==30 and frame.auraFrames[2].width==30 and third.width==30,
 'a late placement failure left Blizzard and Suite geometry mixed')
assert(frame.auraFrames[1].points[1][4]==0 and frame.auraFrames[2].points[1][4]==-35
 and third.points[1][4]==-70,'native fallback left an empty slot')
assert(frame.auraFrames[1].Duration.font[2]==10,'fallback left the custom duration style on Blizzard geometry')
frame:UpdateAuraButtons()
assert(frame.auraFrames[1].width==30,'fallback did not hold while the aura was still unreadable')
third.GetScale=before
frame:UpdateAuraButtons()
assert(frame.auraFrames[1].points[1][4]==0 and frame.auraFrames[2].points[1][4]==-56
 and third.points[1][4]==-112,'recovered row left an empty slot')
-- A new failure during combat queues a rollback. The earlier known buttons
-- must not be restored through Blizzard's grid while combat is locked.
local fourth=Button(false)
frame.auraFrames[4]=fourth
fourth.GetScale=function()return {secret=true} end
combat=true
frame.auraInfo={{},{},{},{}}
frame:UpdateAuraButtons()
assert(queued=='playerAuras' and frame.auraFrames[1].width==52 and fourth.width==30,
 'failed in-combat placement did not defer native restoration')
combat=false
captured:Refresh()
assert(frame.auraFrames[1].width==30 and third.width==30,
 'queued failure did not restore the whole native row')
frame.auraFrames[4]=nil
frame.auraInfo={{},{},{}}
fourth:Hide()
frame:UpdateAuraButtons()
assert(third.width==52 and third.points[1][4]==-112,'row did not recover after the failed buff left')
-- A malformed visible entry hiding in the pool releases its row immediately.
frame.auraFrames[3]=Button(true)
frame.auraFrames[3].Icon=nil
frame:UpdateAuraButtons()
assert(frame.auraFrames[1].width==30,'a button with no icon left the row partly laid out')
frame.auraInfo={{},{}}
combat=true
frame:UpdateAuraButtons()
assert(frame.auraFrames[3].Icon==nil and not frame.auraFrames[3].shown and frame.auraFrames[1].width==52
 and frame.auraFrames[2].points[1][4]==-56,'a failed button hiding in the pool did not allow combat layout to recover')
combat=false
frame.auraFrames[3].Icon=Region()
frame:UpdateAuraButtons()
assert(frame.auraFrames[3].width==52,'a repaired hidden pool entry did not get prepared')
frame.auraFrames[3]=Button(false)
local inactive=frame.auraFrames[3]
inactive.forbidden,inactive.hasValidInfo=true,false
inactive.IsShown=function()error('read shown on a forbidden pool entry')end
captured:Refresh()
assert(frame.auraFrames[1].width==52 and inactive.width==30,
 'a forbidden unused pool button forced healthy buffs back to native')
frame.auraFrames[3]=nil
-- A native layout error must release the re-entry guard and let the next
-- refill retry the rollback, then apply the Suite layout.
local getScale=frame.auraFrames[2].GetScale
captured:Disable()
frame.auraFrames[2].GetScale=function()return nil end
local updateGrid=AuraContainerMixin.UpdateGridLayout
local failedLayout=false
AuraContainerMixin.UpdateGridLayout=function(self)
 assert(self~=frame.AuraContainer,'fallback used the real native layout receiver')
 failedLayout=true
 error('test native layout failure')
end
captured:Enable()
assert(failedLayout,'fallback did not try the native layout')
AuraContainerMixin.UpdateGridLayout=updateGrid
frame.auraFrames[2].GetScale=getScale
frame:UpdateAuraButtons()
assert(frame.auraFrames[1].width==52 and frame.auraFrames[2].points[1][4]==-56,
 'a native layout error left the row unable to recover')
-- Temporary enchants have no DebuffBorder; their native border still resizes.
-- Native code never resizes it, so the configured size is painted with the style.
frame.auraFrames[2].DebuffBorder=nil
frame.auraFrames[2].TempEnchantBorder:SetSize(32,32)
captured:Refresh()
assert(frame.auraFrames[2].TempEnchantBorder.width==54 and frame.auraFrames[2].TempEnchantBorder.height==28)
captured:Disable()
assert(frame.auraFrames[1].width==30 and frame.auraFrames[1].Icon.width==30,'disabled native aura geometry was not restored')
assert(frame.auraFrames[1].Duration.font[2]==10 and frame.auraFrames[1].DebuffBorder.width==40,'native font/border were not restored')
-- Blizzard setup seats both native containers at the minimap, independent of saved Edit Mode positions.
local debuff=Region();debuff.AuraContainer=Region();debuff.auraFrames={Button(true)}
debuff.AuraContainer.isHorizontal,debuff.AuraContainer.iconStride,debuff.AuraContainer.iconPadding=true,12,5
debuff.AuraContainer.addIconsToRight,debuff.AuraContainer.addIconsToTop=false,false
debuff.AuraContainer.currentGridLayoutInfo={isHorizontal=true,iconStride=12,iconPadding=5,
 addIconsToRight=false,addIconsToTop=false,anchor={},layout={}}
debuff.ShouldShowAura=frame.ShouldShowAura;debuff.IsEditing=frame.IsEditing;debuff.SetIsEditing=frame.SetIsEditing
debuff.UpdateAuraButtons=NativeAuraUpdate;debuff.UpdateGridLayout=frame.UpdateGridLayout
_G.DebuffFrame=debuff
captured.config.iconWidth,captured.config.iconHeight,captured.config.fontSize=28,28,10
captured.config.x,captured.config.y,captured.config.debuffOffset,captured.config.debuffX=-10,0,88,-6
captured:Enable()
assert(frame.points[1][1]=='TOPRIGHT' and frame.points[1][2]==Minimap and frame.points[1][3]=='TOPLEFT')
assert(frame.points[1][4]==-10 and frame.points[1][5]==0,'buffs did not move beside minimap')
assert(debuff.points[1][2]==Minimap and debuff.points[1][4]==-16 and debuff.points[1][5]==-88,
 'debuffs did not follow the minimap below the buff rows, shifted by their horizontal offset')
assert(frame.auraFrames[1].width==28 and debuff.auraFrames[1].width==28)
captured:Disable()
print('player aura gain, edit mode font reset, rectangular border and disable restore: OK')
