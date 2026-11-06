local root, client = assert(arg[1]), arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function World(config, reduced, width, height)
    local W = H.New(root,{client=client,catalogPresentation=true,screenWidth=width or 1920,screenHeight=height or 1080,
        config=config,reducedMotion=reduced})
    W.sizes[0], W.sizes[1] = 20,22
    W.Put(0,1,101,1)
    W.Apply(); W.OpenBags(); W.Settle()
    return W
end
local function Script(button, name, ...)
    assert(button:GetScript(name),name)(button,...)
end
for _, presentation in ipairs({1,2}) do
    for _, view in ipairs({1,2,3}) do
        local W=World({windowPresentation=presentation,inventoryView=view,autoSizeWindow=true})
        local V,R=W.P.InventoryView,W.P.BagResize
        W.mouseDown,W.mouseX,W.mouseY=true,1000,700
        Script(V.resize,"OnMouseDown","RightButton")
        assert(not R.active,"right button started resize")
        local width,height=W.CF:GetWidth(),W.CF:GetHeight()
        Script(V.resize,"OnMouseDown","LeftButton")
        assert(R.active and not R.outline,"resize uses a preview outline")
        W.mouseX,W.mouseY=1123,617
        W.Frame()
        assert(W.CF:GetWidth()~=width or W.CF:GetHeight()~=height,"window does not resize live")
        assert(not W.CF.resizable and not W.CF.sizing,"native resize properties were changed")
        W.mouseDown=false
        W.Frame();W.Settle()
        assert(not R.active and not R.driver:GetScript("OnUpdate"),"live driver remains after release")
        assert(not W.config.autoSizeWindow and not W.config.panelFullHeight,"manual size was not retained")
        assert(W.CF:GetWidth()==V.geometry.width and W.CF:GetHeight()==V.geometry.height,"saved size does not match renderer")
        local columns,rows=W.config.inventoryColumns,W.config.inventoryRows
        for _,action in ipairs({"scale","config","combat","hide","disable"}) do
            W.mouseDown=true
            Script(V.resize,"OnMouseDown","LeftButton")
            assert(R.active,"cannot start another resize")
            W.mouseX=W.mouseX+40;W.Frame()
            if action=="scale" then W.Fire("UI_SCALE_CHANGED")
            elseif action=="config" then W.S.Set("bags","inventoryRows",rows)
            elseif action=="combat" then W.EnterCombat()
            elseif action=="hide" then W.CloseBags()
            else W.S.Set("bags","enabled",false) end
            assert(not R.active and not R.driver:GetScript("OnUpdate"),action.." did not cancel resize")
            assert(W.config.inventoryColumns==columns and W.config.inventoryRows==rows,"cancel saved temporary geometry")
            if action=="combat" then W.LeaveCombat()
            elseif action=="hide" then W.OpenBags() end
            W.Settle()
        end
        assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,"live resize lifecycle error")
    end
end
for _,width in ipairs({600,960}) do
    local W=World({windowPresentation=2,inventoryView=3,windowScale=1.5},false,width,768)
    local V,R=W.P.InventoryView,W.P.BagResize
    W.mouseDown=true
    Script(V.resize,"OnMouseDown","LeftButton")
    assert(R.maxW*R.effective<=width and R.maxH*R.effective<=768,"live bounds exceed viewport")
    W.mouseX,W.mouseY=5000,-5000;W.Frame()
    assert(W.CF:GetWidth()<=R.maxW and W.CF:GetHeight()<=R.maxH,"drag escaped live bounds")
    W.mouseDown=false;W.Frame();W.Settle()
end
for _, mode in ipairs({1,2,3}) do
    for _, reduced in ipairs({false,true}) do
        local W = World({animationMode=mode},reduced)
        local V, motion = W.P.InventoryView,W.P.BagMotion
        local item = V.index.items[1].button
        local alpha,parent = item:GetAlpha(),item:GetParent()
        for _, target in ipairs({2,3,1,3,2}) do
            Script(V.tabs[target],"OnClick","LeftButton")
            W.Settle()
            local selection=assert(V.tabSelection,"tab selection is missing")
            assert(not V.transition,"obsolete content veil remains")
            if mode==1 or reduced then
                assert(not selection.group,"disabled/reduced motion allocated a translation group")
            else
                -- A rapid return to the still-visible origin needs no move.
                assert(selection.group:IsPlaying() or selection.x==selection.toX and selection.y==selection.toY,
                    "tab switch neither moves nor rests on the selected tab")
                assert(selection.move.valueSetDuration==(mode==3 and .16 or .12),"wrong selection speed")
                assert(not selection.frame:IsMouseEnabled(),"selection blocks input")
            end
            assert(item:GetParent()==parent and item:GetAlpha()==alpha,"transition changed native item ownership")
        end
        if V.tabSelection.group then
            local selection=V.tabSelection
            W.EnterCombat()
            assert(not selection.group:IsPlaying(),"combat did not stop selection")
            W.LeaveCombat();W.Settle()
            Script(V.tabs[3],"OnClick","LeftButton");W.Settle()
            W.CloseBags()
            assert(not selection.group:IsPlaying(),"close did not stop selection")
        end
        assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,"tab lifecycle regression")
    end
end
print("Corner resizing and tab transitions passed: "..client)
