local root=assert(arg[1])
-- Edit Mode's first refill resets each Duration font object (BuffFrame.lua:374);
-- an aura refill (AuraButtonMixin:Update) leaves fonts alone.
local NativeAuraUpdate=function(self)
    for index, button in ipairs(self.auraFrames) do
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
 local r={width=w or 30,height=h or 40,scale=1,alpha=1,points={},shown=true,font={'native.ttf',10,''},color={1,1,1,1},shadow={0,0,0,1},shadowOffset={0,0},coords={0,1,0,1}}
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
 function r:SetTexCoord(...)self.coords={...}end
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
 function b:Update()self.Count.text='2' end
 return b
end
_G.UIParent=Region();_G.Minimap=Region()
StatusTrayManager={UpdateTrayAndBuffFrameLayout=function()end}
InputUtil={IsGamepadUIEnabled=function()return false end}
AuraFrameEditModeMixin={UpdateAuraButtons=NativeAuraUpdate}
local frame=Region();frame.AuraContainer=Region();frame.auraFrames={Button(true),Button(false)}
function frame:ShouldShowAura()return true end
function frame:IsEditing()return self.editing end
function frame:SetIsEditing(editing)self.editing=editing end
function frame:RefreshConsolidationFrameVisibility()end
frame.UpdateAuraButtons=NativeBuffUpdate
function frame:UpdateGridLayout()for _,b in ipairs(self.auraFrames)do b:SetSize(30,40)end end
_G.BuffFrame=frame
local P={NS={IsCombatLocked=function()return false end,IsSecret=function()return false end,
 HostBridge={IconSkinLook=function()end,PaintIconSkin=function()return false end,WatchIconSkins=function()end}},Suite={}}
local S=P.Suite
S.CreateFrame=function()return Region()end
S.CreateTexture=function()return Region()end
S.RGB=function()return 0,0,0 end
S.PlaceEdges=function()end
S.ResolveFont=function()return 'modern.ttf' end
S.Queue=function()end
S.Install=function(id,m)captured=m end
hooksecurefunc=function(obj,key,callback)local old=obj[key];obj[key]=function(self,...)local out={old(self,...)};callback(self,...);return unpack(out)end end
P.PlayerAuraSkins={Yield=function()end} -- the skin-only piece (PlayerAuraSkins.lua)
assert(loadfile(root .. '/MSUF_Suite_QualityOfLife/PlayerAuras.lua'))('MSUF_Suite_QualityOfLife',P)
captured.config={iconWidth=52,iconHeight=26,perRow=12,spacing=4,rowSpacing=8,x=-12,y=0,debuffOffset=80,borderColor='000000',borderSize=2,font='x',fontSize=16,showDuration=true}
captured.context={Event=function()end}
captured:Enable()
assert(frame.auraFrames[1].width==52,'initial buff not styled')
frame.auraInfo={{},{}}
frame:UpdateAuraButtons()
assert(frame.auraFrames[2].width==52 and frame.auraFrames[2].height==26,'newly gained buff retained native dimensions')
assert(frame.auraFrames[2].Duration.font[2]==16,'newly gained buff kept the native duration font')
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
frame:UpdateGridLayout()
assert(frame.auraFrames[1].points[1][4]==0,'hidden consolidated button left an empty slot')
-- Temporary enchants have no DebuffBorder; their native border still resizes.
-- Native code never resizes it, so the configured size is painted with the style.
frame.auraFrames[2].DebuffBorder=nil
frame.auraFrames[2].TempEnchantBorder:SetSize(32,32)
captured:Refresh()
assert(frame.auraFrames[2].TempEnchantBorder.width==54 and frame.auraFrames[2].TempEnchantBorder.height==28)
captured:Disable()
assert(frame.auraFrames[1].width==30 and frame.auraFrames[1].Icon.width==30,'disabled native aura geometry was not restored')
assert(frame.auraFrames[1].Duration.font[2]==10 and frame.auraFrames[1].DebuffBorder.width==40,'native font/border were not restored')
print('player aura gain, edit mode font reset, rectangular border and disable restore: OK')
