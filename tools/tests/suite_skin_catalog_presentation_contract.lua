-- Run from the real catalog entry points. Native members and globals follow
-- Blizzard's Mainline MerchantFrame/GossipFrame XML and PortraitFrameTemplate.
local root=assert(arg[1],"Suite root required")
local f=assert(io.open(root.."/tools/tests/suite_skin_generic_windows_contract.lua","rb"))
local source=f:read("*a"); f:close()
local stop=assert(source:find("local rowChild = Frame(nil)",1,true))
local body=[======[
assert(loadfile(ColdSource("../MSUF_Suite/Appearance/Cosmetics.lua")))("MSUF_Suite_Skin",NS)
assert(loadfile(ColdSource("Adapters/LegacyWindows.lua")))("MSUF_Suite_Skin",NS)
assert(loadfile(ColdSource("Adapters/DeepWindows.lua")))("MSUF_Suite_Skin",NS)
assert(loadfile(ColdSource("Adapters/CommonMenus.lua")))("MSUF_Suite_Skin",NS)
NS.DB={enabled=true,skins={blizzardWindows=true},blizzardWindowsEnabled=true,
    skinCategories={quest=true,npc=true,economy=true,inventory=false,calendar=false,journal=false}}
local jobs={}
NS.Registry.QueueJob=function(cb) jobs[cb]=true end
C_Timer={After=function(delay,cb) assert(delay==0); jobs[cb]=true end}
local function Settle()
    for _=1,5 do
        if not next(jobs) then break end
        local batch=jobs; jobs={}
        for cb in pairs(batch) do cb() end
    end
    assert(not next(jobs),"repeated paint without further input")
    assert(#reported==0,table.concat(reported,"\n"))
end
local function Widget(name,parent,kind)
    local n=Frame(name)
    n.parent,n.kind,n.shown,n.alpha,n.vertex=parent,kind or "Frame",true,1,{1,1,1,1}
    n.scripts,n.hooks,n.regions={},{},{}
    if name then _G[name]=n end
    if parent then
        local list=kind=="Texture" and parent.regions or parent.children
        list[#list+1]=n
    end
    function n:GetParent() return self.parent end
    function n:GetObjectType() return self.kind end
    function n:IsObjectType(k) return self.kind==k end
    function n:IsShown() return self.shown end
    function n:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function n:IsProtected() return self.protected==true,self.protected==true end
    function n:IsForbidden() return self.forbidden==true end
    function n:GetAlpha() return self.alpha end
    function n:SetAlpha(v) self.alpha=v; self.vertex[4]=v end
    function n:SetVertexColor(r,g,b,a)
        self.vertex={r,g,b,a or 1}
        self.alpha=a or 1
    end
    function n:GetVertexColor() return unpack(self.vertex) end
    function n:GetRegions() return unpack(self.regions) end
    function n:GetTexture() return self.texture end
    function n:GetTextureFileID() return self.fileID end
    function n:GetAtlas() return self.atlas end
    function n:SetAtlas(value) self.atlas=value end
    function n:SetTexture(value) self.texture=value end
    function n:GetWidth() return self.width or 338 end
    function n:GetHeight() return self.height or 496 end
    function n:HookScript(key,cb)
        assert(key~="OnUpdate","catalog installed per-frame polling")
        self.hooks[key]=self.hooks[key] or {}
        table.insert(self.hooks[key],cb)
    end
    function n:GetScript(key) return self.scripts[key] end
    function n:Fire(key,...)
        if self.scripts[key] then self.scripts[key](self,...) end
        for _,cb in ipairs(self.hooks[key] or {}) do cb(self,...) end
    end
    function n:Show() if not self.shown then self.shown=true; self:Fire("OnShow") end end
    function n:Hide() if self.shown then self.shown=false; self:Fire("OnHide") end end
    function n:SetShown(v) if v then self:Show() else self:Hide() end end
    return n
end
local function Art(owner,key,name)
    local region=Widget(name,owner,"Texture")
    if key then owner[key]=region end
    return region
end
local function Suppressed(region)
    return not region.shown or region.alpha==0 or region.vertex[4]==0
end
local function NativeRoot(name)
    local q=Widget(name,UIParent)
    q.layoutType="PortraitFrameTemplate"
    q.Bg=Art(q,"Bg")
    q.NineSlice=Widget(nil,q)
    Art(q.NineSlice,"TopEdge")
    Art(q.NineSlice,"TopLeftCorner")
    q.Inset=Widget(name.."Inset",q)
    Art(q.Inset,"Bg")
    Art(q,"TopTileStreaks")
    q.shown=false
    return q
end
local function Button(name,parent)
    local btn=Widget(name,parent,"Button")
    for _,field in ipairs({"Left","Middle","Right"}) do Art(btn,field) end
    return btn
end
local function Style(control) control.suiteControl=true; return {} end
NS.ControlSkin.ApplyButton,NS.ControlSkin.ApplyThreeSliceButton=Style,Style
NS.IconSkin.Apply=function() return {} end
NS.ScrollBarSkin.Apply=Style
NS.Registry.GetSurface=function(w) if w and w.surfaceSpec then return {spec=w.surfaceSpec,target=w} end end
NS.WindowControls.Attach=function(w) w.suiteCaption=true end
UIParent=Widget("UIParent"); UIParent.width,UIParent.height=1920,1080
local merchant=NativeRoot("MerchantFrame")
local gossip=NativeRoot("GossipFrame")
local auction=NativeRoot("AuctionHouseFrame")
local auctionPortrait=Art(auction,"Portrait")
local vendorPortrait=Art(merchant,nil,"MerchantFramePortrait")
local bottom=Art(merchant,nil,"MerchantFrameBottomLeftBorder"); bottom.atlas="UI-Merchant-BotFrame"
local buyback=Art(merchant,nil,"BuybackBG"); buyback:Hide()
local vendorItems={}
for i=1,12 do
    local row=Widget("MerchantItem"..i,merchant)
    Art(row,"SlotTexture","MerchantItem"..i.."SlotTexture")
    Art(row,nil,"MerchantItem"..i.."NameFrame")
    local btn=Widget("MerchantItem"..i.."ItemButton",row,"ItemButton")
    row.ItemButton=btn
    Art(btn,"icon"); Art(btn,"IconBorder")
    vendorItems[i]=row
end
local vendor=vendorItems[2]
local bought
local vendorClick=function(self) bought=self:GetParent() end
vendor.ItemButton.scripts.OnClick=vendorClick
gossip.Background=Art(gossip,"Background")
local greeting=Widget(nil,gossip); gossip.GreetingPanel=greeting
Art(greeting,"MaterialTopLeft")
local right=Art(greeting,"MaterialTopRight")
Art(greeting,"MaterialBotLeft")
Art(greeting,"MaterialBotRight")
greeting.GoodbyeButton=Button(nil,greeting)
local selected
local gbutton=Widget(nil,greeting,"Button")
local gossipClick=function(self) selected=self end
gbutton.scripts.OnClick=gossipClick
local protected=gossip.NineSlice.TopLeftCorner
protected.protected=true
local secret=auction.NineSlice.TopLeftCorner
local marker={}
local originalSecret=issecretvalue
issecretvalue=function(value) if value==marker then return true end return false end
secret.GetAlpha=function() return marker end
local function ApplyEntry(w)
    local entry=assert(NS.BlizzardCatalog.FindByFrame(w.name))
    GenericWindows.ApplyEntry(entry,"blizzardWindows")
end
for _,w in ipairs({merchant,gossip,auction}) do ApplyEntry(w) end
NS.LegacyWindows.Apply("blizzardWindows")
NS.DeepWindows.Apply("blizzardWindows")
NS.CommonMenus.Apply("blizzardWindows")
for _,w in ipairs({merchant,gossip,auction}) do w:Show() end
Settle()
for _,w in ipairs({merchant,gossip,auction}) do
    Expect(w.surfaceSpec and w.suiteCaption,"missing catalog shell or caption "..w.name)
    Expect(Suppressed(w.Bg) and Suppressed(w.NineSlice.TopEdge),"frame shows its native chrome "..w.name)
end
Expect(vendor.surfaceSpec and Suppressed(MerchantItem2NameFrame) and Suppressed(vendor.SlotTexture),
    "vendor goods did not get the existing Suite row style")
-- Native MH merchant: UpdateMerchantInfo shows the bottom border and
-- UpdateBuybackInfo shows BuybackBG. Neither texture has a parentKey.
bottom:Show(); buyback:Show()
-- GossipFrameMixin:HandleShow registers the actual .Background texture,
-- then UIThemeContainerFrame/other addons can repaint it in their own pass.
gossip.Background:SetAtlas("QuestBG-Parchment"); gossip.Background:Show()
Settle()
Expect(Suppressed(bottom) and Suppressed(buyback),"global-only Merchant bottom or buyback decoration is visible")
Expect(Suppressed(gossip.Background) and Suppressed(greeting.MaterialTopLeft) and Suppressed(right),
    "Gossip theme/greeting surfaces were not covered")
-- A writer runs after all native page callbacks and after the skin's settle.
for _,w in ipairs({merchant,gossip,auction}) do
    for _,region in ipairs({w.Bg,w.Inset.Bg,w.NineSlice.TopEdge}) do
        region:SetVertexColor(0.2,0.4,0.6,0.91); region:SetAlpha(0.76); region:Show()
        Expect(Suppressed(region),"late write re-exposed root, inset or border on "..w.name)
    end
end
bottom:SetAlpha(0.59); buyback:SetShown(false)
gossip.Background:SetAlpha(0.49); right:SetVertexColor(0.2,0.3,0.4,0.81)
merchant.TopTileStreaks:SetVertexColor(0.42,0.52,0.62,0)
Expect(Suppressed(bottom) and Suppressed(gossip.Background) and Suppressed(right),"late writes re-exposed named decoration")
MerchantItem2NameFrame:SetAlpha(0.88); vendor.SlotTexture:SetAlpha(0.72)
Expect(Suppressed(MerchantItem2NameFrame) and Suppressed(vendor.SlotTexture),
    "late writes re-exposed the parchment nameplate or slot behind a vendor item")
Expect(vendorPortrait.alpha==1 and auctionPortrait.alpha==1 and vendor.ItemButton.icon.alpha==1 and vendor.ItemButton.IconBorder.alpha==1,
    "portrait or native item icon and quality border was suppressed")
Expect(not NS.Cosmetics.GetOwner(protected),"claimed explicitly protected decoration")
Expect(not NS.Cosmetics.GetOwner(secret),"claimed decoration with a secret alpha")
vendor.ItemButton:Fire("OnClick"); gbutton:Fire("OnClick")
Expect(bought==vendor and selected==gbutton and vendor.ItemButton:GetScript("OnClick")==vendorClick
    and gbutton:GetScript("OnClick")==gossipClick,"vendor purchase or native gossip selection was intercepted")
NS.CommonMenus.Disable("blizzardWindows"); NS.DeepWindows.Disable("blizzardWindows")
NS.LegacyWindows.Disable("blizzardWindows"); GenericWindows.Disable("blizzardWindows"); Settle()
Expect(bottom.alpha==0.59 and not buyback.shown and gossip.Background.alpha==0.49
    and right.vertex[1]==0.2 and right.vertex[4]==0.81 and right.alpha==0.81,
    "native latest show, alpha or vertex color state was lost on disable")
Expect(merchant.Bg.alpha==0.76 and auction.Bg.shown and auction.Bg.vertex[4]==0.76
    and merchant.TopTileStreaks.alpha==0,"catalog chrome was not restored")
Expect(MerchantItem2NameFrame.alpha==0.88 and vendor.SlotTexture.alpha==0.72,
    "vendor row decoration lost the most recent native state")
merchant.Bg:SetAlpha(0.67); merchant.Bg:Show(); Settle()
Expect(merchant.Bg.alpha==0.67 and merchant.Bg.shown,"disabled catalog hook reclaimed native chrome")
NS.DB.skinCategories.npc=false; ApplyEntry(merchant); Settle()
Expect(GenericWindows.GetStatus("merchant")=="disabled" and merchant.Bg.alpha==0.67,"disabled merchant category unexpectedly painted")
issecretvalue=originalSecret
assert(#failures==0,table.concat(failures,"\n"))
print("suite_skin_catalog_presentation_contract: "..checks.." checks passed")
]======]
assert(loadstring(source:sub(1,stop-1)..body,"@suite_skin_catalog_presentation_contract"))()
