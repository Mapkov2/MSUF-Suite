local root, client = assert(arg[1]), arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local secret = {}
local function World(view, presentation)
    local W=H.New(root,{client=client,catalogPresentation=true,unprotectedBags=true,isSecret=function(value) return value==secret end,
        config={inventoryView=view,windowPresentation=presentation,autoSizeWindow=false,inventoryRows=4,animationMode=3}})
    W.sizes[0],W.sizes[1]=36,32
    for i=1,36 do W.Put(0,i,100+i,1) end
    W.Apply();W.OpenBags();W.Settle()
    return W
end
for _,presentation in ipairs({1,2}) do
    for _,view in ipairs({1,2,3}) do
        local W=World(view,presentation)
        local V=W.P.InventoryView
        local style=W.M.windows[W.CF]
        local width,height,scale=W.CF:GetWidth(),W.CF:GetHeight(),W.CF:GetScale()
        local native=V.index.items[1].button
        local click,parent,id=native:GetScript("OnClick"),native:GetParent(),native:GetID()
        W.EnterCombat();W.Settle()
        assert(V.layout=="suite" and V.chrome:IsShown(),"combat swaps away from Suite view")
        assert(style.panel==(presentation==2),"combat changes configured skin")
        assert(W.CF:GetWidth()==width and W.CF:GetHeight()==height and W.CF:GetScale()==scale,"combat entry changes geometry")
        assert(native:GetScript("OnClick")==click and native:GetParent()==parent and native:GetID()==id,"native item action ownership changed")
        local uses=#W.calls.uses
        W.Native(native:GetScript("OnClick"),native,"RightButton")
        assert(#W.calls.uses==uses+1, "native right-click item use fails in combat")
        local before=V.scroll
        V.MoveScroll(1)
        assert(V.scroll>before,"combat inventory cannot scroll")
        W.Put(0,1,101,3);W.Fire("BAG_UPDATE",0);W.Fire("BAG_UPDATE_DELAYED");W.Settle()
        assert(V.layout=="suite" and V.chrome:IsShown(),"combat update loses style")
        W.CloseBags();W.OpenBags();W.Settle()
        assert(V.layout=="suite" and V.chrome:IsShown() and style.panel==(presentation==2),"combat reopen loses skin")
        assert(W.NativeSearch:GetAlpha()==0 and not W.NativeSearch:IsMouseEnabled(),"native search overlaps Suite search")
        assert(not W.P.BagWindowMotion.active and not W.P.BagResize.active,"combat retains animation/resize driver")
        W.LeaveCombat();W.Settle()
        W.S.Set("bags","enabled",false);W.Settle()
        assert(not V.active and W.NativeSearch:GetAlpha()==1 and W.NativeSearch:IsMouseEnabled(),"combat ownership not restored on disable")
        assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,"modeled protected/taint error")
    end
end
-- First opening during combat also creates the configured own slot styling.
do
    local W=H.New(root,{client=client,catalogPresentation=true,unprotectedBags=true,
        config={inventoryView=3,windowPresentation=2,windowScale=1.2,windowMoved=true,windowX=-80,windowY=120}})
    W.sizes[0]=20;W.Put(0,1,101,1);W.Apply();W.EnterCombat();W.OpenBags();W.Settle()
    local V,style=W.P.InventoryView,W.M.windows[W.CF]
    assert(V.layout=="suite" and style.panel and style.heading:IsShown(), "cold combat open loses shell")
    assert(W.CF.TitleContainer.TitleText:GetAlpha()==0, "native title overlaps cold combat heading")
    for _,item in ipairs(V.index.items) do
        local overlay=W.M.overlays[item.button]
        assert(overlay and overlay.slotOuter and overlay.slotOuter:IsShown(), "cold combat slot uses another skin")
    end
    assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,"cold combat native error")
end
-- Protection, secrecy and forbidden access are independent refusal cases.
for _, kind in ipairs({"root","slot","secret","forbidden"}) do
    local W=World(3,2)
    if kind=="slot" then W.CF.Items[1].protection=true; W.CF.Items[1].guarded=true
    elseif kind=="forbidden" then W.CF.IsForbidden=function() return true end
    else W.CF.protection=kind=="secret" and secret or true; W.CF.guarded=true end
    W.EnterCombat();W.Settle()
    assert(not W.P.BagLayout.CanRender(), "unsafe pool allowed: "..kind)
    local frame=kind=="slot" and W.CF.Items[1] or W.CF
    local ctx=W.M.context
    local scale=frame:GetScale()
    assert(ctx:UnprotectedProperty(frame,"GetScale","SetScale",2)==false, "unsafe owned property allowed")
    assert(ctx:UnprotectedAnchor(frame,"CENTER",UIParent,"CENTER",0,0)==false, "unsafe owned anchor allowed")
    assert(frame:GetScale()==scale and #W.combatLayout==0, "unsafe combat layout write")
    W.CloseBags();W.OpenBags();W.Settle()
    assert(not W.P.InventoryView.chrome:IsShown(), "unsafe reopen paints custom slots")
    W.LeaveCombat();W.Settle()
    assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0, "unsafe fallback native error")
end
-- Bursts coalesce once, protection checks remain linear, and idle frames do
-- not rescan inventory or continue a custom animation driver.
do
    local W=World(3,2);W.EnterCombat();W.Settle()
    local scans,queries=0,0
    local read=W.P.InventoryIndex.ReadContainer
    W.P.InventoryIndex.ReadContainer=function(...) scans=scans+1; return read(...) end
    local widget=getmetatable(W.CF).__index
    local protected=widget.IsProtected
    function widget:IsProtected() queries=queries+1; return protected(self) end
    for i=1,30 do W.Fire("BAG_UPDATE",0);W.Fire("BAG_UPDATE_DELAYED") end
    W.Settle()
    assert(scans==1, "combat burst does not coalesce")
    assert(queries<=#W.CF.Items+8, "combat repeats protection scans in one render")
    local previous=queries
    for i=1,60 do W.Frame() end
    assert(scans==1 and queries==previous, "idle combat polls layout/protection")
    assert(not W.P.BagWindowMotion.active and not W.P.BagResize.active, "combat owns a live update driver")
end
print("Consistent unprotected combat bag view and ownership passed: "..client)
