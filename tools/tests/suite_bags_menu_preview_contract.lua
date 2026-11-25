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
W.config.inventoryView = W.NS.BagsView.BLIZZARD_GRID
combat=false;W.Fire("PLAYER_REGEN_ENABLED");W.Settle()
assert(loads==1 and paints==1 and preview.nativeBackpack and preview.nativeBackpack.frame:IsVisible(),
 "visible regen never paints a cold Blizzard grid preview")
assert(not preview.categories:IsShown(), "cold Blizzard grid shows Suite categories")
assert(not preview.caption[2].previewMuted, "Blizzard-grid preview dims the working maximize control")
W.config.inventoryView = W.NS.BagsView.CATEGORIES
ui.refreshPreview()
assert(next(preview.slots), "switching from the cold Blizzard grid never paints Suite slots")
assert(not W.M.active and not W.CF:IsShown(),"preview activated bag replacement")
local before=paints;ui.refreshPreview();assert(paints==before,"unchanged preview repainted")
local borderStyle = W.NS.BagsBorderStyle
W.config.backpackBorderStyle = borderStyle.CUSTOM
W.config.backpackBorderWidth = 3
W.config.backpackBorderColor = "ff0000"
W.config.backpackBorderOpacity = 40
ui.refreshPreview()
assert(preview.chrome[6]:GetHeight() == 3 and preview.chrome[6].color[1] == 1 and preview.chrome[6].color[4] == .4,
    "custom Backpack border did not update in the preview")
W.config.backpackBorderStyle = borderStyle.DEFAULT
ui.refreshPreview()
assert(preview.chrome[6]:GetHeight() == 1 and preview.chrome[6].color[1] < .1, "preview did not restore the dark standard border")
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
local originalLook = {}
for key in pairs(W.NS.BagsLookVisualKeys) do originalLook[key] = W.config[key] end
originalLook.look = W.config.look
W.config.inventoryView = W.NS.BagsView.BLIZZARD_GRID
W.config.windowPresentation = W.NS.BagsPresentation.PANEL
ui.refreshPreview()
local grid = assert(preview.nativeBackpack, "Blizzard grid lacks a combined backpack sample")
local scaleGrip = assert(grid.scaleGrip, "Blizzard-grid preview is missing the window scale grip")
assert(scaleGrip.icon:GetTexture() == "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up", "preview uses the wrong scale icon")
InsideContent(scaleGrip)
Disjoint(scaleGrip, preview.goldJump)
scaleGrip:GetScript("OnClick")()
assert(focused == "suite_bags_window", "preview grip does not open the layout settings")
assert(grid.frame:IsShown() and #grid.slots == 66 and not preview.geometry.panel, "Blizzard grid lost its compact shape")
assert(not preview.slots[9]:IsShown(), "Suite slots remain visible in the Blizzard grid")
local x, y = W.Rect(grid.slots[1])
local tenthX, tenthY = W.Rect(grid.slots[10])
local nextX, nextY = W.Rect(grid.slots[11])
assert(x > tenthX and y == tenthY and x == nextX and nextY > y, "Blizzard slots do not fill from the bottom right")
assert(grid.slots[1].icon:IsShown() and not grid.slots[4].icon:IsShown(), "Blizzard grid lacks item and empty-slot samples")
InsideContent(preview.search)
InsideContent(preview.cleanup)
Disjoint(preview.search,preview.cleanup)
for _, nativeSlot in ipairs(grid.slots) do
 InsideContent(nativeSlot)
 Disjoint(nativeSlot,preview.search)
 Disjoint(nativeSlot,preview.cleanup)
end
InsideContent(preview.sessionJump)
Disjoint(preview.sessionJump,preview.goldJump)
assert(preview.chrome[2].sublevel > preview.chrome[1].sublevel and preview.chrome[3].layer == "BORDER"
 and preview.chrome[6].layer == "ARTWORK", "preview chrome does not follow the live draw order")
for _, look in ipairs({1, 3, 2, 5, 6}) do
 W.config.look = look
 for key, value in pairs(W.NS.BagsLookPresets[look]) do W.config[key] = value end
 ui.refreshPreview()
 local body, line = preview.chrome[2], preview.chrome[4].color
 local r, g, b = W.S.RGB(W.config.backgroundColor)
 local ar, ag, ab = W.S.RGB(W.config.accentColor)
 local opacity = W.config.backgroundOpacity / 100
 assert(line[1] == ar and line[2] == ag and line[3] == ab, "preview kept the old preset accent")
 if look == 3 then
  local gradient = body.gradient
  assert(gradient[1] == "VERTICAL" and gradient[2].r == r and gradient[2].a == opacity * .88
   and gradient[3].r == r * .85, "Forever preset lacks the live glass gradient")
 elseif body.gradient then
  local flat = body.gradient[2]
  assert(flat == body.gradient[3] and flat.r == r and flat.g == g and flat.b == b and flat.a == opacity,
   "live preset color or opacity did not replace the glass gradient")
 else
  assert(body.color[1] == r and body.color[2] == g and body.color[3] == b and body.color[4] == opacity,
   "preview kept the old preset background")
 end
end
for key, value in pairs(originalLook) do W.config[key] = value end
W.config.inventoryView = W.NS.BagsView.CATEGORIES
ui.refreshPreview()
assert(not grid.frame:IsShown() and preview.slots[9]:IsShown(), "Blizzard grid survives a return to Suite categories")
assert(not scaleGrip:IsVisible(), "Blizzard grip survives in the Suite preview")
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
ui.selected="appearance"
W.config.slotBorderWidth=0;W.config.emptySlotBorderWidth=0
ui.refreshPreview()
local examples=preview.borderExamples
assert(examples and examples:IsShown(),"border samples are missing")
for _,sample in ipairs({examples.item,examples.empty}) do
 for _,edge in ipairs(sample.slotEdges) do assert(not edge:IsShown(),"zero border is still drawn in preview") end
end
local ix,iy,iw,ih=W.Rect(examples.item.icon)
local sx,sy,sw,sh=W.Rect(examples.item)
assert(ix==sx and iy==sy and iw==sw and ih==sh,"zero border preview retains an inset outline")
W.config.slotBorderWidth=2;W.config.emptySlotBorderWidth=4
ui.refreshPreview()
assert(examples.item.slotEdges[1]:GetHeight()==2 and examples.empty.slotEdges[1]:GetHeight()==4,
 "preview ignores independent border widths")
W.config.combineReagentBag=true;ui.refreshPreview()
assert(preview.snapshot.model.groupsByKey.reagentBag,"combined reagent section missing from preview")
W.config.combineReagentBag=false;ui.refreshPreview()
assert(not preview.snapshot.model.groupsByKey.reagentBag,"disabled integration persists in preview")
W.config.inventoryView = W.NS.BagsView.REAGENT_SECTION
W.config.inventoryRows = 8
ui.refreshPreview()
local groups = preview.snapshot.model.groups
assert(groups[1].key == "all" and groups[2].key == "reagentBag", "sectioned preview did not place reagents below the bags")
if W.NS.Client.isForever then
 assert(groups[3] and groups[3].key == "keyring", "Forever preview did not place the keyring below reagents")
 local key = preview.snapshot.keyringItem
 local slot = preview.slots[key.itemID]
 assert(slot and slot:IsVisible() and slot.icon:GetTexture() == key.icon, "the preview did not render the key")
 assert(slot.level:GetText() == "", "the preview key showed an item level")
else
 assert(#groups == 2, "Retail preview showed a keyring")
end
assert(W.calls.info==0 and W.calls.quest==0,"representative menu preview scans inventory")
print("independent Bags menu geometry/routing/cold/hidden/provider checks passed: "..(arg[2] or "Mainline"))
