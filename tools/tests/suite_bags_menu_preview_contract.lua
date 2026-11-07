local root=assert(arg[1])
local H=dofile(root.."/tools/tests/suite_bags_harness.lua")
local W=H.New(root,{client=arg[2] or "Mainline",config={inventoryView=3,inventoryRows=5,groupEquipmentSlots=true,compactGroups=false}})
local combat,loads,paints,focused=true,0,0,nil
local P={ S=W.S,Suite=W.NS,Tr=function(s) return s end,catalog={bags=W.NS.SuiteCatalog.bags},
 T={colors={text={1,1,1}}},HM={SkipHistoryCheckpoint=function() end},
 Combat=function() return combat end,StylePreviewFont=function() end,
 SetTranslatedText=function(label,text) label:SetText(text) end }
P.Text=function(parent,text,x,y,width)
 local r=parent:CreateFontString(nil,"OVERLAY");r:SetText(text);r:SetHeight(12)
 r:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);r:SetWidth(width);return r
end
P.M={TrackRefresh=function(ctx,fn) ctx.refreshers[#ctx.refreshers+1]=fn end}
local exact, exactAvailable = nil, true
function W.NS.HostBridge.OpenExactMenuSetting(menu, page, section, key)
 assert(menu==P.M,"gold preview used the wrong host menu")
 exact={page,section,key}
 return exactAvailable
end
P.MenuWorkspace={FitHeader=function(ui,height) ui.header:SetHeight(height) end}
assert(loadfile(root.."/MSUF_Suite_Options/Menu/PreviewInteraction.lua"))("Options",P)
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
local function GuideIs(target, thickness)
 local guide=assert(preview.guide,"bags preview has no guide")
 assert(guide:IsShown()==(target~=nil) and guide:IsMouseEnabled()==false,"guide visibility or input is wrong")
 if target then
  local _,anchor=guide:GetPoint(1)
  local edges=guide._suitePreviewSelectionEdges
  assert(anchor==target and edges.thickness==thickness,"guide points at the wrong target or uses the wrong emphasis")
 end
end
GuideIs(nil)
local slot=preview.slots[9]
slot:GetScript("OnEnter")();GuideIs(slot,1)
slot:GetScript("OnClick")();assert(focused=="suite_bags_itemLevels","slot misses item levels")
slot:GetScript("OnLeave")();GuideIs(slot,2)
preview.search:GetScript("OnEnter")();GuideIs(preview.search,1)
preview.search:GetScript("OnLeave")();GuideIs(slot,2)
W.config.qualityColor=not W.config.qualityColor;ui.refreshPreview();GuideIs(slot,2)
preview.window:Hide();GuideIs(nil)
preview.window:Show();GuideIs(nil)
W.config.showFreeSlots=true;ui.refreshPreview()
preview.freeJump:GetScript("OnClick")();GuideIs(preview.freeJump,2)
W.config.showFreeSlots=false;ui.refreshPreview();GuideIs(nil)
assert(not preview.freeJump:IsShown(),"hidden free-slot count retains its hit target")
W.config.showFreeSlots=true;ui.refreshPreview()
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
  assert(preview.sessionJump:IsShown()==preview.session:IsShown(),"gold period target visibility differs from its text")
  InsideContent(preview.sessionJump)
  Disjoint(preview.freeJump,preview.sessionJump)
  if presentation==2 and view~=4 then
   assert(preview.geometry.panel and preview.chrome.feather:IsShown() and not preview.title:IsShown(), "sample lost panel style")
  else assert(not preview.geometry.panel, "compact/native sample uses panel") end
  preview.categories:GetScript("OnClick")();assert(focused=="suite_bags_categories","category target misses Categories tab")
  preview.goldJump:GetScript("OnClick")();assert(focused=="suite_bags_finance","gold target misses finance")
  preview.cleanup:GetScript("OnClick")();assert(focused=="suite_bags_organisation","bag cleanup target misses bag settings")
 end
end
end
ui.selected="bags";W.config.inventoryView=1;ui.refreshPreview()
focused=nil
preview.sessionJump:GetScript("OnEnter")();GuideIs(preview.sessionJump,1)
preview.sessionJump:GetScript("OnClick")();GuideIs(preview.sessionJump,2)
assert(exact[1]=="suite_bags" and exact[2]=="suite_bags_finance" and exact[3]=="msufsuite.bags.goldPeriod" and not focused,
 "session gold misses the exact gold period setting")
exactAvailable=false
preview.sessionJump:GetScript("OnClick")()
assert(focused=="suite_bags_finance","session gold misses the finance fallback on older hosts")
W.config.goldPeriod=2;ui.refreshPreview()
assert(preview.session:GetText():match("^Today ") and preview.sessionJump:IsShown(),"Today loses the gold period target")
W.config.goldPeriod=3;ui.refreshPreview()
assert(preview.session:GetText():match("^Session .+\nToday ") and preview.sessionJump:IsShown(),
 "Both does not show both periods in the clickable preview")
InsideContent(preview.sessionJump)
Disjoint(preview.sessionJump,preview.freeJump)
Disjoint(preview.sessionJump,preview.categories)
W.config.showSessionGold=false;ui.refreshPreview();GuideIs(nil)
assert(not preview.sessionJump:IsShown(),"hidden gold period retains its hit target")
W.config.showSessionGold=true;ui.refreshPreview()
preview.equipped:GetScript("OnClick")();GuideIs(preview.equipped,2)
ui.selected="bank";ui.refreshPreview();GuideIs(nil)
for _,view in ipairs({1,2,3,4}) do
 ui.selected="bank";W.config.bankView=view;ui.refreshPreview();CurrentItems()
 assert(not preview.equipped:IsShown() and not preview.goldJump:IsShown() and not preview.chrome.goldLabel:IsShown(),
 "bank preview retains bag-only targets")
 assert(not preview.sessionJump:IsShown(),"bank preview retains the gold period target")
 for _,button in ipairs(preview.viewButtons) do assert(not button:IsShown(),"bank preview retains bag tabs") end
 if view==1 then
  local native=assert(preview.nativeBank,"Bank tabs still previews the combined bank")
  assert(native.frame:IsVisible() and #native.slots==12 and preview.title:GetText()==(BANK or "Bank"),
   "Bank tabs has no native sample")
  local firstX,firstY=W.Rect(native.slots[1]);local secondX,secondY=W.Rect(native.slots[2])
  local thirdX=W.Rect(native.slots[3])
  assert(firstY==secondY and thirdX-secondX>secondX-firstX,"Bank tabs lost Blizzard's paired columns")
  assert(not preview.cleanupLabel:IsShown() and not preview.free:IsShown(),"Bank tabs retains the organized bank footer")
 else
  assert(not preview.nativeBank.frame:IsShown(),"organized view retains the native sample")
  assert(preview.cleanupLabel:GetText()=="Manage bank tabs","organized bank footer shows bag cleanup")
 end
 preview.search:GetScript("OnClick")();assert(focused=="suite_bags_bank","bank search opens bag settings")
 GuideIs(preview.search,2)
 preview.categories:GetScript("OnClick")();assert(focused=="suite_bags_bank","bank categories open bag settings")
 preview.cleanup:GetScript("OnClick")();assert(focused=="suite_bags_bank","bank footer opens bag settings")
 InsideContent(preview.search);InsideContent(preview.cleanup)
end
before=paints;ui.header:Hide();W.config.accentColor="00ff00";ui.refreshPreview()
assert(paints==before,"hidden preview repaints")
ui.header:Show();ui.refreshPreview();assert(paints>before,"reshown preview fails to refresh")
assert(W.calls.info==0 and W.calls.quest==0,"representative menu preview scans inventory")
print("independent Bags menu geometry/routing/cold/hidden/provider checks passed: "..(arg[2] or "Mainline"))
