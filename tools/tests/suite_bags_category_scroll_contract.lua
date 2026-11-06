local root, client = assert(arg[1]), arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function World(mode, reduced)
    local W=H.New(root,{client=client,catalogPresentation=true,unprotectedBags=true,
        reducedMotion=reduced,config={inventoryView=3,animationMode=mode or 3}})
    W.sizes[0]=20;W.Put(0,1,101,1);W.Apply();W.OpenBags();W.Settle()
    return W
end
local function Canvas(W)
    local scroll,child=W.P.BagWidgets.Scroll(UIParent,140)
    scroll:SetSize(140,100);scroll:SetPoint("TOPLEFT");child:SetHeight(1000)
    W.P.BagWidgets.UpdateScroll(scroll)
    return scroll,child,scroll.bagScrollBar
end
local function Wheel(scroll,delta) scroll:GetScript("OnMouseWheel")(scroll,delta) end
local function Frames(W,count) for i=1,count or 20 do W.Frame() end end
-- Exercise the actual inventory sidebar, not only an isolated scroll canvas.
do
    local W=World(3);local categories={}
    for i=1,18 do
        W.Put(0,i,100+i,1)
        categories[i]={name="Category "..i,enabled=true,items={[100+i]=true}}
    end
    W.S.Set("bags","customCategories",W.P.InventoryModel.EncodeCategories(categories));W.Settle()
    local V=W.P.InventoryView;local scroll=V.sidebar
    assert(scroll.bagScrollBar.high>66 and scroll:IsVisible(),"category rail sample has no scroll range")
    local row=V.scroll;local parents={}
    for _,item in ipairs(V.index.items) do parents[item.button]=item.button:GetParent() end
    Wheel(scroll,-1);W.Frame()
    assert(scroll:GetVerticalScroll()>0 and scroll:GetVerticalScroll()<66,"real category rail does not interpolate")
    Frames(W)
    assert(scroll:GetVerticalScroll()==66 and V.scroll==row,"category wheel scrolls the item grid")
    for button,parent in pairs(parents) do assert(button:GetParent()==parent,"category scroll reparents native items") end
end
for _,mode in ipairs({2,3}) do
    local W=World(mode);local scroll,child,bar=Canvas(W)
    scroll:SetVerticalScroll(100);Wheel(scroll,-1)
    assert(scroll:GetVerticalScroll()==100,"category wheel jumps immediately")
    W.Frame();local middle=scroll:GetVerticalScroll()
    assert(middle>100 and middle<166,"category wheel lacks intermediate real offsets")
    assert(bar:GetValue()==middle,"thumb is out of sync during smooth scroll")
    Wheel(scroll,-2);Frames(W)
    assert(scroll:GetVerticalScroll()==298,"rapid wheel input loses accumulated distance")
    assert(not scroll:GetScript("OnUpdate"),"finished scroll keeps update loop")
    Wheel(scroll,-1);W.Frame()
    local held=scroll:GetVerticalScroll()
    local press=bar:GetScript("OnMouseDown");if press then press(bar,"LeftButton") end
    Frames(W)
    assert(scroll:GetVerticalScroll()==held and not scroll:GetScript("OnUpdate"),"pressing thumb keeps old wheel motion")
    Wheel(scroll,-1);W.Frame();bar:SetValue(77);Frames(W)
    assert(scroll:GetVerticalScroll()==77 and not scroll:GetScript("OnUpdate"),"thumb drag eases or resumes old motion")
    Wheel(scroll,-1);W.Frame();scroll:SetVerticalScroll(40);Frames(W)
    assert(scroll:GetVerticalScroll()==40,"external position resumes stale destination")
    scroll:SetVerticalScroll(0);Wheel(scroll,-10)
    child:SetHeight(200);W.P.BagWidgets.UpdateScroll(scroll);Frames(W)
    assert(scroll:GetVerticalScroll()==100 and bar:GetValue()==100,"pending destination escapes new range")
    child:SetHeight(1000);W.P.BagWidgets.UpdateScroll(scroll);Wheel(scroll,-3);W.Frame()
    child:SetHeight(50);W.P.BagWidgets.UpdateScroll(scroll);Frames(W)
    assert(scroll:GetVerticalScroll()==0 and not bar:IsShown() and not scroll:GetScript("OnUpdate"),"short list retains motion")
    child:SetHeight(1000);W.P.BagWidgets.UpdateScroll(scroll);Wheel(scroll,-1);scroll:Hide()
    assert(not scroll:GetScript("OnUpdate"),"hidden list keeps motion")
    scroll:Show();Wheel(scroll,-1);W.NS.Registry.NotifyListeners("profile")
    assert(not scroll:GetScript("OnUpdate"),"profile change keeps old scroll destination")
    local scans,builds=0,0
    W.P.InventoryIndex.ReadContainer=function() scans=scans+1 end
    W.P.GridView.Build=function() builds=builds+1 end
    Wheel(scroll,-1);Frames(W);Frames(W,60)
    assert(scans==0 and builds==0,"category scroll rebuilds gameplay inventory")
    assert(not scroll:GetScript("OnUpdate"),"idle category scroll polls")
    assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,"scroll native/combat error")
end
for _,reduced in ipairs({false,true}) do
    local W=World(reduced and 3 or 1,reduced);local scroll=Canvas(W)
    Wheel(scroll,-1)
    assert(scroll:GetVerticalScroll()==66 and not scroll:GetScript("OnUpdate"),"Off/reduced wheel still animates")
end
do
    local W=World(3);local scroll,child,bar=Canvas(W)
    Wheel(scroll,-2);W.Frame();W.EnterCombat()
    assert(scroll:GetVerticalScroll()==132 and not scroll:GetScript("OnUpdate"),"combat does not finish pending wheel intent")
    Wheel(scroll,-1)
    assert(scroll:GetVerticalScroll()==198 and not scroll:GetScript("OnUpdate"),"safe category wheel stops working in combat")
    bar:SetValue(35);assert(scroll:GetVerticalScroll()==35,"safe category thumb stops working in combat")
    scroll.protection,scroll.guarded=true,true
    Wheel(scroll,-1);assert(scroll:GetVerticalScroll()==35,"protected category frame scrolls in combat")
    child:SetHeight(120);W.P.BagWidgets.UpdateScroll(scroll)
    assert(scroll:GetVerticalScroll()==35,"protected range callback writes scroll offset")
    scroll.protection,scroll.guarded=false,false
    bar.protection,bar.guarded=true,true
    Wheel(scroll,-1)
    assert(scroll:GetVerticalScroll()==35,"protected thumb still drives category scroll")
    W.P.BagWidgets.UpdateScroll(scroll)
    assert(scroll:GetVerticalScroll()==35,"protected thumb range callback still drives category scroll")
    assert(#W.combatLayout==0 and #W.errors==0 and #W.taint==0,"combat scroll writes protected layout")
end
print("Smooth category wheel, direct thumb and finite lifecycle passed: "..client)
