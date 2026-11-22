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
do
    local W = World({ inventoryView = 4, windowMoved = true, windowX = -320, windowY = 120 })
    local resize, frame = W.P.BagResize, W.CF
    local grip = assert(resize.scaleGrip, "Blizzard grid is missing its bottom-right scale grip")
    assert(grip:IsVisible() and not W.P.InventoryView.active, "Blizzard grid needs its own visible grip")
    W.S.Set("bags", "accentColor", "181109")
    assert(grip.grip:GetTexture() == "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
        and grip.grip:GetWidth() == 20 and grip.grip:GetHeight() == 20 and not grip.grip.vertex,
        "Blizzard grid grip must use the standard square, untinted window icon")
    local function SizeWithRect(value, ignoreRect)
        -- The live rect is rounded at the current scale. The assigned size is stable.
        return (ignoreRect or frame:GetScale() == 1) and value or value + .015625
    end
    local getWidth, getHeight = frame.GetWidth, frame.GetHeight
    function frame:GetWidth(ignoreRect) return SizeWithRect(getWidth(self), ignoreRect) end
    function frame:GetHeight(ignoreRect) return SizeWithRect(getHeight(self), ignoreRect) end
    function frame:GetSize(ignoreRect) return self:GetWidth(ignoreRect), self:GetHeight(ignoreRect) end
    local width, height = frame:GetSize(true)
    local firstSlot = frame.Items[1]
    local point, owner, _, slotX, slotY = firstSlot:GetPoint()
    local columns, rows = W.config.inventoryColumns, W.config.inventoryRows
    local left, bottom, physicalWidth, physicalHeight = frame:GetScaledRect()
    local top = bottom + physicalHeight
    local function CheckGripAlignment(bagLeft, bagBottom, bagWidth)
        local gripLeft, gripBottom, gripWidth = grip.grip:GetScaledRect()
        local effective = frame:GetEffectiveScale()
        assert(math.abs(gripLeft + gripWidth - (bagLeft + bagWidth - effective)) < .01
            and math.abs(gripBottom - (bagBottom + effective)) < .01, "scale grip is detached from the bottom-right rim")
        local _, hitBottom, _, hitHeight = grip:GetScaledRect()
        assert(hitBottom + hitHeight <= bagBottom + 7 * effective + .01, "scale grip captures the Blizzard money row")
    end
    CheckGripAlignment(left, bottom, physicalWidth)
    local function Begin()
        W.mouseDown, W.mouseX, W.mouseY = true, 1000, 700
        Script(grip, "OnMouseDown", "LeftButton")
        assert(resize.active, "Blizzard-grid scaling did not start")
    end

    Begin()
    Script(grip, "OnMouseUp", "LeftButton")
    assert(not resize.active and W.config.windowScale == 1 and W.config.windowX == -320 and W.config.windowY == 120,
        "clicking the grip changed the saved geometry")
    Begin()
    W.mouseX, W.mouseY = 1080, 620
    W.Frame()
    local scaled = frame:GetScale()
    W.Frame()
    assert(resize.active and frame:GetScale() == scaled, "rect rounding cancelled a live scale drag")
    local x, y, w, h = frame:GetScaledRect()
    assert(scaled > 1 and W.config.windowScale == 1, "scale must change live and commit only on release")
    assert(math.abs(x - left) < .01 and math.abs(y + h - top) < .01, "scale drag lost the opposite corner")
    CheckGripAlignment(x, y, w)
    W.Native(UpdateContainerFrameAnchors)
    assert(frame:GetScale() == scaled, "Blizzard's anchor pass discarded the drag")
    W.mouseDown = false
    W.Frame()
    W.Settle()
    assert(not resize.active and not resize.driver:GetScript("OnUpdate"), "native scale driver survived release")
    assert(W.config.windowScale > 1 and math.abs(frame:GetScale() - scaled) < .01, "native scale was not saved")
    local savedX, savedY = frame:GetScaledRect()
    assert(math.abs(savedX - x) < .01 and math.abs(savedY - y) < .01, "releasing the grip moved the backpack")
    local newPoint, newOwner, _, newX, newY = firstSlot:GetPoint()
    assert(frame:GetWidth(true) == width and frame:GetHeight(true) == height and newPoint == point and newOwner == owner
        and newX == slotX and newY == slotY, "scaling changed the native slots or dimensions")
    assert(W.config.inventoryColumns == columns and W.config.inventoryRows == rows, "scaling rewrote the Suite grid size")

    local saved = W.config.windowScale
    Begin()
    W.mouseX, W.mouseY = 5000, -5000
    W.Frame()
    local edgeX, edgeY, edgeWidth, edgeHeight = frame:GetScaledRect()
    assert(edgeX + edgeWidth <= W.screenWidth + .01 and edgeY >= -.01 and edgeY + edgeHeight <= W.screenHeight + .01,
        "dragging to maximum pushed the backpack out of the viewport")
    W.EnterCombat()
    assert(not resize.active and W.config.windowScale == saved, "combat saved or continued a scale drag")
    W.LeaveCombat()
    assert(math.abs(frame:GetScale() - scaled) < .01, "combat cancellation did not restore the committed scale")
    Begin()
    W.nativeScale = .9
    W.Native(UpdateContainerFrameAnchors)
    assert(not resize.active and W.config.windowScale == saved and math.abs(frame:GetScale() - .9 * saved) < .01,
        "a native scale change kept a stale drag or lost the committed scale")
    W.nativeScale = 1
    W.Native(UpdateContainerFrameAnchors)
    Begin()
    W.Native(function() frame:SetSize(width, height + 42) end)
    W.Frame()
    assert(not resize.active and W.config.windowScale == saved, "a genuine native size change did not cancel the drag")
    W.Native(function() frame:UpdateFrameSize() end)
    W.CloseBags()
    W.OpenBags()
    assert(grip:IsVisible() and math.abs(frame:GetScale() - scaled) < .01, "scale did not survive reopening")
    W.S.Set("bags", "windowY", 0)
    CheckGripAlignment(frame:GetScaledRect())
    assert(select(2, grip.grip:GetScaledRect()) >= 0, "screen edge clipped the visible scale grip")
    W.S.Set("bags", "inventoryView", W.NS.BagsView.ALL)
    W.Settle()
    assert(not grip:IsVisible() and W.P.InventoryView.resize:IsVisible(), "Suite and Blizzard grips overlap")
    W.S.Set("bags", "inventoryView", W.NS.BagsView.BLIZZARD_GRID)
    assert(grip:IsVisible(), "switching back did not restore the Blizzard grip")
    assert(#W.errors == 0 and #W.taint == 0 and #W.combatLayout == 0, "native scale lifecycle error")
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
