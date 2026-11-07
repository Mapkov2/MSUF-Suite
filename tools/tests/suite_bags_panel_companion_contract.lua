local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function Inside(W, frame)
    local x, y, w, h = W.Rect(frame)
    assert(x >= -.01 and y >= -.01 and x + w <= W.screenWidth + .01 and y + h <= W.screenHeight + .01,
        "native companion or full panel leaves screen")
    return x, y, w, h
end
for _, width in ipairs({600,960,1920}) do
    for _, scale in ipairs({.65,1,1.5}) do
        local W = H.New(root, {client=arg[2] or "Mainline", catalogPresentation=true,screenWidth=width,screenHeight=768,
            config={windowScale=scale,inventoryColumns=20}})
        W.sizes[0], W.sizes[5] = 20, 32
        W.Put(0,1,101,1)
        W.Apply()
        W.OpenBags()
        W.Settle()
        -- Blizzard opens the reagent root even in combined mode. Simulate
        -- the native size/show and anchor pass before its Suite post-hook.
        W.Native(function()
            ContainerFrame6:SetSize(430,200)
            ContainerFrame6:Show()
            UpdateContainerFrameAnchors()
        end)
        W.Settle()
        local x = Inside(W,W.CF)
        local rx, _, rw = Inside(W,ContainerFrame6)
        assert(rx+rw < x, "default reagent companion overlaps the panel rail")
        assert(W.CF:GetScale()==ContainerFrame6:GetScale(), "companion and panel scales disagree")
        local height, columns, fitted = W.CF:GetHeight(), W.P.InventoryView.geometry.columns, W.CF:GetScale()
        for i=1,5 do W.Native(UpdateContainerFrameAnchors);W.Settle() end
        assert(W.CF:GetHeight()==height and W.P.InventoryView.geometry.columns==columns and W.CF:GetScale()==fitted,
            "native anchor pass causes companion sizing feedback")
        W.screenWidth = 1920
        W.Fire("DISPLAY_SIZE_CHANGED")
        W.Settle()
        Inside(W,W.CF)
        Inside(W,ContainerFrame6)
        W.screenWidth = width
        W.Fire("UI_SCALE_CHANGED")
        W.Settle()
        Inside(W,W.CF)
        Inside(W,ContainerFrame6)
        W.S.SetMany("bags",{windowMoved=true,windowX=-4096,windowY=-4096})
        W.Settle()
        Inside(W,W.CF)
        Inside(W,ContainerFrame6)
        W.EnterCombat()
        W.Native(UpdateContainerFrameAnchors)
        W.Settle()
        W.LeaveCombat()
        W.Settle()
        Inside(W,W.CF)
        Inside(W,ContainerFrame6)
        W.S.SetMany("bags",{reagentWindowMoved=true,reagentWindowX=-200,reagentWindowY=80})
        W.Settle()
        local point, _, _, px, py=ContainerFrame6:GetPoint()
        assert(point=="BOTTOMRIGHT" and px==-200 and py==80, "panel overwrites custom reagent placement")
        W.S.Set("bags","reagentWindowMoved",false)
        W.Settle()
        W.Native(function() ContainerFrame6:Hide();UpdateContainerFrameAnchors() end)
        W.Settle()
        assert(math.abs(W.CF:GetScale()-W.P.BagPresentation.Scale(W.config,0))<.001, "closing companion leaves panel at fitted companion scale")
        W.Native(function() ContainerFrame6:SetSize(430,900);ContainerFrame6:Show();UpdateContainerFrameAnchors() end)
        W.Settle()
        Inside(W,W.CF)
        Inside(W,ContainerFrame6)
        W.Native(function() ContainerFrame6:Hide();UpdateContainerFrameAnchors() end)
        W.Settle()
        W.S.Set("bags","windowPresentation",W.NS.BagsPresentation.WINDOW)
        W.Settle()
        assert(W.M.context.properties[ContainerFrame6]==nil or W.M.context.properties[ContainerFrame6].SetScale==nil,
            "compact window retains companion scale ownership")
        W.S.Set("bags","enabled",false)
        W.Settle()
        assert(#W.taint==0 and #W.combatLayout==0 and #W.errors==0, "companion taint/lockdown/error regression")
    end
end
do
    local W = H.New(root, { client = arg[2] or "Mainline", config = { backgroundOpacity = 82 } })
    local reagent = W.Reagent
    reagent.Bg:SetFrameLevel(600)
    W.Apply()
    W.Native(function() reagent:Show() end)
    W.Settle()
    local skin = W.M.windows[reagent]
    assert(skin[2]:GetParent() == reagent and skin[2].layer == "BACKGROUND",
        "reagent fill follows a child frame level and can cover native contents")
    assert(skin[3]:GetParent() == reagent and skin[3].layer == "BORDER",
        "reagent header can cover the native title")
    assert(skin[2].color[4] == .82 and skin[2]:IsShown(), "reagent fill does not use the configured opacity")
    W.M:RestoreWindows()
    assert(reagent:IsShown() and not skin[2]:IsShown() and not skin[3]:IsShown(),
        "restoring the skin must hide owned art and leave the native bag visible")
    W.M:StyleWindows()
    assert(skin[2]:IsShown() and skin[3]:IsShown(), "re-enabling skin leaves reagent art hidden")
end
print("Default reagent companion fit, native anchor stability, custom placement and restoration passed: "..(arg[2] or "Mainline"))
