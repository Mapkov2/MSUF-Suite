local root=assert(arg[1])
local H=dofile(root.."/tools/tests/suite_bags_harness.lua")
local W=H.New(root,{client=arg[2] or "Mainline",config={inventoryView=3,inventoryRows=5,groupEquipmentSlots=true,compactGroups=false}})
local combat,loads,paints,focused=true,0,0,nil
local P={ S=W.S,Suite=W.NS,Tr=function(s) return s end,catalog={bags=W.NS.SuiteCatalog.bags},
 T={colors={text={1,1,1}}},HM={SkipHistoryCheckpoint=function() end},PreviewInteraction={Outline=function() end},
 Combat=function() return combat end,StylePreviewFont=function() end,
 SetTranslatedText=function(label,text) label:SetText(text) end }
P.Text=function(parent,text,x,y,width)
 local r=parent:CreateFontString(nil,"OVERLAY");r:SetText(text);r:SetHeight(12)
 r:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);r:SetWidth(width);return r
end
P.M={TrackRefresh=function(ctx,fn) ctx.refreshers[#ctx.refreshers+1]=fn end}
P.MenuWorkspace={FitHeader=function(ui,height) ui.header:SetHeight(height) end}
assert(loadfile(root.."/MSUF_Suite_Options/Menu/PreviewCanvas.lua"))("Options",P)
local createPreview=W.S.BagsNewPreview
W.S.BagsNewPreview=nil
C_AddOns.LoadAddOn=function(addon)
 assert(not combat and addon=="MSUF_Suite_Bags","cold-combat preview tried loading runtime")
 loads=loads+1;W.S.BagsNewPreview=createPreview;return true
end
local paintWindow=W.S.BagsPaintPreviewWindow
W.S.BagsPaintPreviewWindow=function(...) paints=paints+1;return paintWindow(...) end
local uiWidth=tonumber(arg[3]) or 720
local ui={width=uiWidth,selected="bags",ctx={wrapper=CreateFrame("Frame",nil,UIParent),refreshers={}},
 header=CreateFrame("Frame",nil,UIParent),Focus=function(_,section) focused=section;return true end}
ui.header:SetSize(uiWidth,220);ui.header:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,0)
assert(loadfile(root.."/MSUF_Suite_Options/Pages/BagsPreview.lua"))("Options",P)
P.BuildBagsMenuPreview(ui)
local preview=ui.bagsPreview
assert(loads==0 and paints==0 and ui.header:GetHeight()>=406,
 "cold-combat fallback extends outside reserved header")
combat=false;W.Fire("PLAYER_REGEN_ENABLED");W.Settle()
assert(loads==1 and paints==1 and next(preview.slots),"visible regen never paints cold preview")
assert(not W.M.active and not W.CF:IsShown(),"preview activated bag replacement")
local before=paints;ui.refreshPreview();assert(paints==before,"unchanged preview repainted")
local function CurrentItems()
 local visible={}
 for _,cell in ipairs(W.S.BagsPreviewLayout(preview.snapshot,W.config,ui.selected=="bank")) do
  if cell.row and cell.line<preview.rows then visible[cell.row.item.itemID]=true end
 end
 for id,slot in pairs(preview.slots) do
  assert(not slot:IsShown() or visible[id],"stale preview item persists: "..id)
 end
end
assert(preview.slots[9] and preview.slots[9]:IsShown() and not preview.slots[4],"fixture needs sparse cold category pool")
W.config.category_equipment=false;ui.refreshPreview();CurrentItems()
W.config.category_equipment=true
local function InsideContent(frame)
 if not frame:IsVisible() then return end
 local x,y,w,h=W.Rect(frame)
 local cx,cy,cw,ch=W.Rect(preview.content)
 assert(x>=cx-.01 and x+w<=cx+cw+.01 and y>=cy-.01 and y+h<=cy+ch+.01,
 "visible preview hit target exceeds canvas")
end
local function Disjoint(a,b)
 if not a:IsVisible() or not b:IsVisible() then return end
 local ax,ay,aw,ah=W.Rect(a);local bx,by,bw,bh=W.Rect(b)
 assert(ax+aw<=bx or bx+bw<=ax or ay+ah<=by or by+bh<=ay,
 "finance hit target intercepts cleanup")
end
for _, presentation in ipairs({1,2}) do
W.config.windowPresentation=presentation
for _,columns in ipairs({8,12,20}) do
 for _,view in ipairs({1,2,3,4}) do
  ui.selected="bags";W.config.inventoryColumns=columns;W.config.inventoryView=view;ui.refreshPreview();CurrentItems()
  if view==4 then
   assert(not preview.equipped:IsShown(),"native-grid sample retains Suite equipped drawer")
   for _,button in ipairs(preview.viewButtons) do assert(not button:IsShown(),"native-grid sample retains Suite view tabs") end
  else assert(preview.equipped:IsShown(),"Suite sample loses equipped drawer") end
  InsideContent(preview.search);InsideContent(preview.equipped);InsideContent(preview.cleanup);InsideContent(preview.goldJump)
  Disjoint(preview.cleanup,preview.goldJump)
  if presentation==2 and view~=4 then
   assert(preview.geometry.panel and preview.chrome.feather:IsShown() and not preview.title:IsShown(), "sample lost panel style")
  else assert(not preview.geometry.panel, "compact/native sample uses panel") end
  preview.categories:GetScript("OnClick")();assert(focused=="suite_bags_categories","category target misses Categories tab")
  preview.goldJump:GetScript("OnClick")();assert(focused=="suite_bags_finance","gold target misses finance")
  preview.cleanup:GetScript("OnClick")();assert(focused=="suite_bags_organisation","bag cleanup target misses bag settings")
 end
end
end
for _,view in ipairs({1,2,3,4}) do
 ui.selected="bank";W.config.bankView=view;ui.refreshPreview();CurrentItems()
 assert(not preview.equipped:IsShown() and not preview.goldJump:IsShown() and not preview.chrome.goldLabel:IsShown(),
 "bank preview retains bag-only targets")
 for _,button in ipairs(preview.viewButtons) do assert(not button:IsShown(),"bank preview retains bag tabs") end
 assert(preview.cleanupLabel:GetText()=="Manage bank tabs","bank footer shows bag cleanup")
 preview.search:GetScript("OnClick")();assert(focused=="suite_bags_bank","bank search opens bag settings")
 preview.categories:GetScript("OnClick")();assert(focused=="suite_bags_bank","bank categories open bag settings")
 preview.cleanup:GetScript("OnClick")();assert(focused=="suite_bags_bank","bank footer opens bag settings")
 InsideContent(preview.search);InsideContent(preview.cleanup)
end
before=paints;ui.header:Hide();W.config.accentColor="00ff00";ui.refreshPreview()
assert(paints==before,"hidden preview repaints")
ui.header:Show();ui.refreshPreview();assert(paints>before,"reshown preview fails to refresh")
assert(W.calls.info==0 and W.calls.quest==0,"representative menu preview scans inventory")
print("independent Bags menu geometry/routing/cold/hidden/provider checks passed: "..(arg[2] or "Mainline"))
