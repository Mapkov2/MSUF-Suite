-- Native MerchantFrame.xml uses four special texture slots plus an anonymous
-- stone backplate. The state slots belong to the original 32 x 32 buttons.
local root=assert(arg[1])
local file=assert(io.open(root.."/tools/tests/suite_skin_generic_windows_contract.lua","rb"))
local source=file:read("*a"); file:close()
local stop=assert(source:find("local rowChild = Frame(nil)",1,true))
local body=[======[
NS.path="Interface\\AddOns\\MSUF_Suite_Skin\\"
NS.Checkmarks.UntrackDropdown=function() end
NS.Checkmarks.DetectWindowAction=function() end
assert(loadfile(ColdSource("../MSUF_Suite/Appearance/Cosmetics.lua")))("MSUF_Suite_Skin",NS)
assert(loadfile(ColdSource("Rendering/WindowActionSkin.lua")))("MSUF_Suite_Skin",NS)
assert(loadfile(ColdSource("Rendering/WindowActionSettings.lua")))("MSUF_Suite_Skin",NS)
assert(loadfile(ColdSource("Rendering/ControlSkin.lua")))("MSUF_Suite_Skin",NS)
assert(loadfile(ColdSource("Adapters/LegacyWindows.lua")))("MSUF_Suite_Skin",NS)
local roles={muted={0.50,0.57,0.64,1}, accent={0.12,0.70,0.91,1},accentBright={0.25,0.77,1,1}, text={0.92,0.95,0.98,1}}
NS.Theme.GetColor=function(role) return unpack(roles[role] or {0.1,0.1,0.1,1}) end
NS.DB={enabled=true,blizzardWindowsEnabled=true,skinCategories={npc=true,calendar=false,journal=false},
    icons={windowActions={style="native",weight="fine",glyphSize=9,glyphOffsetX=3,glyphOffsetY=-3}}}
local function Region(parent,kind,layer)
    local r={parent=parent,kind=kind,layer=layer,shown=true,alpha=1,points={},rgba={1,1,1,1},uv={0,1,0,1}}
    function r:GetObjectType() return self.kind end
    function r:GetParent() return self.parent end
    function r:Show() self.shown=true end
    function r:Hide() self.shown=false end
    function r:IsShown() return self.shown end
    function r:SetShown(show) self.shown=show end
    function r:GetAlpha() return self.alpha end
    function r:SetAlpha(a) self.alpha=a; self.rgba[4]=a end
    function r:SetVertexColor(red,green,blue,alpha)
        self.rgba={red,green,blue,alpha or 1}; self.alpha=alpha or 1
    end
    r.SetTextColor,r.SetColorTexture=r.SetVertexColor,r.SetVertexColor
    function r:GetVertexColor() return unpack(self.rgba) end
    function r:SetPoint(...) table.insert(self.points,{...}) end
    function r:ClearAllPoints() self.points={} end
    function r:SetAllPoints(target) self.allPoints=target or parent end
    function r:SetStartPoint(...) self.start={...} end
    function r:SetEndPoint(...) self.finish={...} end
    function r:SetThickness(v) self.thickness=v end
    function r:SetTexCoord(...) self.uv={...} end
    function r:SetSize(w,h) self.w,self.h=w,h end
    function r:SetWidth(v) self.w=v end
    function r:SetHeight(v) self.h=v end
    function r:SetTexture(asset) self.asset=asset end
    function r:GetTexture() return self.asset end
    function r:GetTextureFilePath() return self.asset end
    function r:SetAtlas(asset) self.atlas=asset end
    function r:GetAtlas() return self.atlas end
    function r:SetRotation(x) self.rotation=x end
    function r:SetText(x) self.text=x end
    function r:SetBlendMode(x) self.blend=x end
    function r:GetBlendMode() return self.blend or "BLEND" end
    function r:SetDrawLayer(x) self.layer=x end
    function r:SetSnapToPixelGrid(x) self.snap=x end
    function r:SetTexelSnappingBias(x) self.bias=x end
    table.insert(parent.regions,r)
    return r
end
local function Native(name,parent)
    local w=Frame(name)
    if parent then table.insert(parent.children,w) end
    w.parent,w.shown,w.regions,w.hooks=parent,true,{},{}
    function w:GetParent() return self.parent end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function w:GetRegions() return unpack(self.regions) end
    function w:CreateTexture(_,layer) return Region(self,"Texture",layer) end
    function w:CreateFontString(_,layer) return Region(self,"FontString",layer) end
    function w:CreateLine(_,layer) return Region(self,"Line",layer) end
    function w:HookScript(key,cb)
        self.hooks[key]=self.hooks[key] or {}
        table.insert(self.hooks[key],cb)
    end
    function w:Fire(key,...)
        if self.scripts and self.scripts[key] then self.scripts[key](self,...) end
        for _,cb in ipairs(self.hooks[key] or {}) do cb(self,...) end
    end
    return w
end
local stateNames={"Normal","Pushed","Disabled","Highlight"}
local function Pager(name,direction)
    local b=Native(name,MerchantFrame)
    _G[name]=b
    b.width,b.height,b.mouse,b.enabled=32,32,true,true
    b.slots,b.original,b.scripts={},{},{}
    function b:GetWidth() return self.width end
    function b:GetHeight() return self.height end
    function b:GetObjectType() return "Button" end
    function b:IsEnabled() return self.enabled end
    function b:GetScript(key) return self.scripts[key] end
    function b:Enable() if not self.enabled then self.enabled=true; self:Fire("OnEnable") end end
    function b:Disable() if self.enabled then self.enabled=false; self:Fire("OnDisable") end end
    function b:SetEnabled(value) if value then self:Enable() else self:Disable() end end
    local files={Normal="Up",Pushed="Down",Disabled="Disabled"}
    for _,name in ipairs(stateNames) do
        local t=b:CreateTexture(nil,"ARTWORK")
        local slot=name
        b.original[slot],b.slots[slot]=t,t
        t.asset=files[slot] and ("Interface\\Buttons\\UI-SpellbookIcon-"..direction.."Page-"..files[slot])
            or "Interface\\Buttons\\UI-Common-MouseHilight"
        if slot=="Highlight" then t.blend="ADD" end
        b["Get"..slot.."Texture"]=function(self) return self.slots[slot] end
        b["Set"..slot.."Texture"]=function(self,r,blend)
            self.slots[slot]=r
            if blend then r.blend=blend end
        end
    end
    b.plate=b:CreateTexture(nil,"BACKGROUND")
    b.plate.asset="Interface\\Buttons\\UI-PageButton-Background"
    b.label=b:CreateFontString(nil,"BACKGROUND")
    b.label.text=direction
    return b
end
local function PageState()
    if MerchantFrame.page==1 then MerchantPrevPageButton:Disable() else MerchantPrevPageButton:Enable() end
    if MerchantFrame.page==2 then MerchantNextPageButton:Disable() else MerchantNextPageButton:Enable() end
end
function MerchantFrame_UpdateMerchantInfo() PageState() end
function MerchantFrame_Update() MerchantFrame_UpdateMerchantInfo() end
local function PageClick(b)
    if not b:IsShown() or not b:IsEnabled() then return end
    MerchantFrame.page=MerchantFrame.page+(b==MerchantNextPageButton and 1 or -1)
    MerchantFrame_Update()
end
local states={}
NS.Registry.GetSurface=function(target) return states[target] end
NS.Surface.Attach=function(target,spec)
    local s=states[target] or {target=target,edge={SetDrawLayer=function() end}}
    s.spec,s.visible=spec,true; states[target]=s
    return s
end
NS.Surface.SkinOwnedButton=function(b,spec)
    local s=states[b]
    if not s then
        s={kind="button",target=b}; states[b]=s
        for _,key in ipairs({"pushed","disabled","highlight"}) do
            s[key]=b:CreateTexture(nil,"ARTWORK")
        end
    end
    s.spec=spec
    return s
end
NS.Surface.EnsureOwnedButtonHighlightLayer=function() end
NS.Surface.SetNativeStateSync=function() end
UIParent=Native("UIParent")
MerchantFrame=Native("MerchantFrame",UIParent)
local prev=Pager("MerchantPrevPageButton","Prev")
local nextPage=Pager("MerchantNextPageButton","Next")
prev.scripts.OnClick,nextPage.scripts.OnClick=PageClick,PageClick
MerchantFrame.page=1; PageState()
local e=assert(NS.BlizzardCatalog.FindByFrame("MerchantFrame"))
GenericWindows.ApplyEntry(e,"blizzardWindows")
NS.LegacyWindows.Apply("blizzardWindows")
assert(#reported==0,table.concat(reported,"\n"))
-- The engine paints the selected slot and can retain its old Texture as a
-- normal child after a slot is rebound. Owner must suppress both the current
-- special slot and any still-shown detached native arrow artwork.
local function NoStockArt(b)
    if b.plate:IsShown() and b.plate.alpha>0 then return false end
    for _,slot in ipairs(stateNames) do
        local original=b.original[slot]
        if original.shown and original.alpha>0 and original.asset and original.asset:find("Interface\\Buttons",1,true) then return false end
    end
    return true
end
local function SameColor(t,role)
    local c=roles[role]
    return t.rgba[1]==c[1] and t.rgba[2]==c[2] and t.rgba[3]==c[3]
end
local function ActiveArt(b)
    return b:IsEnabled() and b:GetNormalTexture() or b:GetDisabledTexture()
end
local function Chevron(b,t,left)
    local l,r=3/8,4/8
    local uv=left and {r,0,l,0,r,1,l,1} or {l,1,r,1,l,0,r,0}
    if not t.asset or not t.asset:find("MapkoSkinWindowActionsBold.png",1,true) or #t.uv~=8 then return false end
    for i=1,8 do if t.uv[i]~=uv[i] then return false end end
    local p=t.points[1]
    return t.w==18 and t.h==18 and p and #t.points==1 and p[1]=="CENTER" and p[2]==b and p[3]=="CENTER"
        and (p[4] or 0)==0 and (p[5] or 0)==0
end
for _,b in ipairs({prev,nextPage}) do
    for _,slot in ipairs(stateNames) do
        Expect(Chevron(b,b.slots[slot],b==prev),b.name.." "..slot.." is not a centered matched chevron")
    end
    local surface=NS.Registry.GetSurface(b)
    Expect(surface and surface.spec and surface.spec.inset==4 and b.width==32 and b.height==32,
        b.name.." did not retain its hit rect around the compact surface")
    for _,r in ipairs(b.regions) do
        if r.kind=="FontString" and r~=b.label then Expect(not r.shown or not r.text or r.text=="",
            "generic text-arrow remained drawn on top of the chevron") end
    end
end
local function StateCheck(b,other,msg)
    Expect(NoStockArt(b) and NoStockArt(other), msg..": native button art can leak over Suite paging")
    Expect(b.enabled and not other.enabled, msg..": native enable/disable state was changed")
    Expect(SameColor(ActiveArt(b),"text") and SameColor(ActiveArt(other),"muted")
        and ActiveArt(other).alpha>=0.5 and ActiveArt(other).alpha<ActiveArt(b).alpha,
        msg..": state slots did not immediately show active/muted glyphs")
end
StateCheck(nextPage,prev,"page 1")
nextPage:Fire("OnEnter"); nextPage:Fire("OnMouseDown","LeftButton")
Expect(NoStockArt(nextPage),"pressed or hovered pager revealed the native yellow arrow")
Expect((SameColor(nextPage:GetPushedTexture(),"accent") or SameColor(nextPage:GetPushedTexture(),"accentBright"))
    and (SameColor(nextPage:GetHighlightTexture(),"accent") or SameColor(nextPage:GetHighlightTexture(),"accentBright")),
    "hovered or pressed state did not use the accent chevron")
nextPage:Fire("OnClick","LeftButton"); nextPage:Fire("OnMouseUp","LeftButton"); nextPage:Fire("OnLeave")
StateCheck(prev,nextPage,"page 2"); Expect(MerchantFrame.page==2,"next click failed")
nextPage:Fire("OnClick","LeftButton"); Expect(MerchantFrame.page==2,"disabled next advanced beyond the last page")
prev:Fire("OnClick","LeftButton")
StateCheck(nextPage,prev,"page 1 again"); Expect(MerchantFrame.page==1,"previous click failed")
for _,b in ipairs({prev,nextPage}) do
    for _,slot in ipairs(stateNames) do
        local detached=b.original[slot]
        detached:SetAlpha(1); detached:Show()
    end
    b.plate:SetAlpha(1); b.plate:Show()
    Expect(NoStockArt(b),"late native state paint re-exposed the Blizzard art")
    Expect(b.label.shown and b.label.text and b.label.alpha==1,"the native page label disappeared")
end
Expect(prev.mouse and nextPage.mouse and prev:GetScript("OnClick")==PageClick and nextPage:GetScript("OnClick")==PageClick
    and not prev.hooks.OnClick and not nextPage.hooks.OnClick and not prev.hooks.OnEnable and not nextPage.hooks.OnDisable,
    "pager replaced input or installed a native button-state handler")
NS.LegacyWindows.Disable("blizzardWindows"); GenericWindows.Disable("blizzardWindows")
for _,b in ipairs({prev,nextPage}) do
    for _,slot in ipairs(stateNames) do
        local t=b.original[slot]
        Expect(b.slots[slot]==t and t.shown and t.alpha==1,"disable did not restore "..b.name.." "..slot)
    end
    Expect(b.plate.shown and b.plate.alpha==1 and b.label.shown and b.label.alpha==1,"native pager label or plate was not restored")
end
-- Reopening after a profile toggle must reuse one returnable set of glyphs.
local before=#prev.regions+#nextPage.regions
NS.LegacyWindows.Apply("blizzardWindows")
GenericWindows.ApplyEntry(e,"blizzardWindows")
StateCheck(nextPage,prev,"re-enabled")
Expect(#prev.regions+#nextPage.regions==before,"re-enable stacked new glyphs on existing controls")
NS.LegacyWindows.Disable("blizzardWindows"); GenericWindows.Disable("blizzardWindows")
assert(#failures==0,table.concat(failures,"\n"))
print("suite_skin_merchant_pager_contract: "..checks.." checks passed")
]======]
assert(loadstring(source:sub(1,stop-1)..body,"@suite_skin_merchant_pager_contract"))()
