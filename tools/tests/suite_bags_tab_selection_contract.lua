local root, client = assert(arg[1]), arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local W = H.New(root,{client=client,catalogPresentation=true,config={animationMode=3}})
W.sizes[0]=20;W.sizes[1]=22;W.Put(0,1,101,1)
W.Apply();W.OpenBags();W.Settle()
local V = W.P.InventoryView
for _, button in pairs(V.tabs) do
    assert(button.normalFontObject=="GameFontHighlightSmall" and button.highlightFontObject==button.normalFontObject,
        "hover still switches the small label to native large font")
    assert(button.disabledFontObject=="GameFontDisableSmall","disabled font has a different size")
end
local tab=V.tabs[1]
tab:GetScript("OnEnter")(tab)
local hover=assert(W.P.BagMotion.records[tab.surface],"hover fill has no animation")
assert(hover.fade.valueSetDuration==.12 and hover.group:IsPlaying(),"hover fill is not eased")
hover.fade.progress=.5
tab:GetScript("OnLeave")(tab)
assert(math.abs(hover.from-.85)<.001,"hover reversal lost visible alpha")
hover.group:Finish()
W.NS.HostBridge.MenuReducedMotion=function() return true end
tab:GetScript("OnEnter")(tab)
tab:GetScript("OnLeave")(tab)
W.P.BagMotion.StopAll()
assert(tab.surface:GetAlpha()==.7,"reduced motion stop restored stale hover alpha")
W.NS.HostBridge.MenuReducedMotion=function() return false end
assert(tab.surface:GetAlpha()==.7,"hover fill did not settle at rest opacity")
assert(tab.highlightFontObject==tab.normalFontObject,"hover changed font size")
local s = assert(V.tabSelection,"traveling filled tab selection is missing")
assert(s.frame:GetParent()==V.chrome and s.frame:GetFrameLevel()<V.tabs[1]:GetFrameLevel(),"selection is above labels")
assert(not s.frame:IsMouseEnabled(),"selection intercepts tab input")
assert(not V.transition,"obsolete content veil remains")
local function Click(id)
    V.tabs[id]:GetScript("OnClick")(V.tabs[id],"LeftButton")
    W.Settle()
end
local initialX,initialY=s.x,s.y
Click(2)
assert(s.group:IsPlaying() and s.move.valueSetDuration==.16,"selection did not animate to second tab")
assert(s.fromX==initialX and s.fromY==initialY,"selection does not start at previous tab")
s.move.progress=.4
local x,y=s.fromX+s.move.x*.4,s.fromY+s.move.y*.4
Click(3)
assert(math.abs(s.fromX-x)<.001 and math.abs(s.fromY-y)<.001,"rapid click lost its current visible position")
local group,frame=s.group,s.frame
s.group:Finish()
assert(not s.group:IsPlaying() and s.x==s.toX and s.y==s.toY,"native finish did not settle on selected tab")
for _, id in ipairs({1,3,2,1,2}) do Click(id);s.group:Finish() end
assert(s.group==group and s.frame==frame,"tab switching churns visual objects")
W.EnterCombat()
assert(not s.group:IsPlaying(),"combat did not stop selection")
W.LeaveCombat();W.Settle()
Click(3);W.CloseBags()
assert(not s.group:IsPlaying(),"closing did not stop selection")
W.OpenBags();W.Settle()
V.tabs[1]:GetScript("OnClick")(V.tabs[1],"LeftButton")
V.resize:GetScript("OnMouseDown")(V.resize,"LeftButton")
assert(not W.P.BagResize.active,"resize started with stale pending-tab geometry")
W.Settle()
assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,"selection lifecycle raised a callback/ownership error")
print("Fixed-size fonts and traveling filled tab selection passed: "..client)
