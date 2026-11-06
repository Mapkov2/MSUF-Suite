local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function Inside(W, frame)
    local x,y,w,h = W.Rect(frame)
    assert(x>=-.01 and y>=-.01 and x+w<=W.screenWidth+.01 and y+h<=W.screenHeight+.01,
        "resized panel leaves screen")
end
local function World(height, scale, view)
    local W = H.New(root, {client=arg[2] or "Mainline",catalogPresentation=true,screenWidth=960,screenHeight=height,
        config={windowScale=scale,inventoryView=view}})
    W.sizes[0], W.sizes[1] = 20,22
    W.Put(0,1,101,1)
    W.Apply()
    W.OpenBags()
    W.Settle()
    W.M:RegisterMovers()
    return W
end
for _, view in ipairs({1,3}) do
    for _, height in ipairs({480,768,1440}) do
        for _, scale in ipairs({.65,1,1.5}) do
            local W = World(height,scale,view)
            local g,V = W.P.InventoryView.geometry,W.P.InventoryView
            assert(not W.config.panelFullHeight and not g.fullHeight, "auto-fit panel must be default")
            assert(g.rows==math.max(g.minimum,math.min(g.capacity,W.config.inventoryRows,V.model.lineCount)), "panel ignored content fit")
            if height==1440 then assert(W.CF:GetHeight()*W.CF:GetScale()<height/2, "screenshot's unused full-height space persists") end
            if view==3 then assert(g.height-318>=25, "short category rail is unusable") end
            Inside(W,W.CF)
            local c = W.config
            local sample = W.S.BagsNewPreview()
            local effective = W.S.BagsPreviewScale(c,W.screenWidth,W.screenHeight,24,false)
            local expected = W.S.BagsPreviewGeometry({},c,W.screenWidth/effective,W.screenHeight/effective-12,24)
            W.S.BagsPreviewLayout(sample,c,false,expected)
            W.S.BagsFitPreviewRows(expected,c,sample.model.lineCount)
            assert(expected.panel and expected.height>=expected.minimum*40+expected.top+expected.bottom, "shared preview fitting lost minimum")
            W.S.SetMany("bags",{autoSizeWindow=false,inventoryRows=8})
            W.Settle()
            assert(g.rows>=g.minimum and g.rows<=8, "manual row cap ignored")
            local before=W.CF:GetWidth()
            W.S.Set("bags","inventoryColumns",8)
            W.Settle()
            assert(W.CF:GetWidth()<=before, "width control does not resize panel")
            W.S.Set("bags","panelFullHeight",true)
            W.Settle()
            assert(g.fullHeight and math.abs(g.height-(height/W.CF:GetScale()-24))<.01, "full-height opt-in ignored")
            local rowsControl
            for _, control in ipairs(W.movers.combined.extraControls) do if control.id=="rows" then rowsControl=control end end
            assert(rowsControl,"Edit Mode lacks manual height control")
            rowsControl.set(7)
            W.Settle()
            assert(not c.autoSizeWindow and not c.panelFullHeight and g.rows<=7, "manual rows did not turn off auto/full modes")
            for _, key in ipairs({"inventoryColumns","inventoryRows","autoSizeWindow","panelFullHeight"}) do
                local found=false
                for _, saved in ipairs(W.movers.combined.historyKeys) do if saved==key then found=true end end
                assert(found,"sizing control missing mover history: "..key)
            end
            W.P.EquippedBags.Toggle()
            W.Settle()
            Inside(W,W.CF)
            W.EnterCombat()
            assert(V.layout=="combat", "sizing lost physical combat layout")
            Inside(W,W.CF)
            for _, item in ipairs(V.index.items) do Inside(W,item.button) end
            W.LeaveCombat()
            W.Settle()
            W.S.Set("bags","inventoryView",4)
            W.Settle()
            assert(not V.active,"native-grid bypass was lost")
            assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,"sizing callback/taint/lockdown regression")
        end
    end
end
for _, total in ipairs({8,148,164,236}) do
    local W = H.New(root,{client=arg[2] or "Mainline",catalogPresentation=true,screenWidth=960,screenHeight=768,
        config={inventoryView=3,inventoryColumns=20,windowScale=1.5}})
    W.sizes[0],W.sizes[1]=math.min(20,total),math.max(0,total-20)
    W.Apply()
    W.OpenBags()
    W.Settle()
    W.EnterCombat()
    Inside(W,W.CF)
    for _, item in ipairs(W.P.InventoryView.index.items) do Inside(W,item.button) end
    W.LeaveCombat()
    W.Settle()
    assert(W.M.combatScale==nil and #W.errors==0 and #W.combatLayout==0,"temporary fit did not restore")
end
print("Bags content fit, manual size, scale, full-height, preview and combat passed: "..(arg[2] or "Mainline"))
