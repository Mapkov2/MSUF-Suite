local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function Near(a, b) return math.abs(a - b) < .01 end
local function Inside(W, child, parent)
    if not child:IsVisible() then return end
    local x, y, w, h = W.Rect(child)
    local px, py, pw, ph = W.Rect(parent)
    assert(x >= px - .01 and x + w <= px + pw + .01 and y >= py - .01 and y + h <= py + ph + .01,
        "control outside full panel footprint")
end
local function Fill(W)
    W.sizes[0], W.sizes[1] = 20, 36
    for i = 1, 35 do
        W.Define(i, { name = "Item " .. i, class = i < 16 and 4 or 7, equipLoc = i < 16 and "INVTYPE_CHEST" or "" })
        W.Put(i <= 20 and 0 or 1, i <= 20 and i or i - 20, i, 1)
    end
    W.Apply(); W.OpenBags(); W.Settle()
end
for _, height in ipairs({600, 768, 1080}) do
    for _, scale in ipairs({.65, 1, 1.5}) do
        for _, columns in ipairs({8, 12, 20}) do
            local W = H.New(root, { client = arg[2] or "Mainline", catalogPresentation = true,
                screenHeight = height, screenWidth = 960, config = { panelFullHeight = true, windowScale = scale, inventoryColumns = columns,
                inventoryView = 3, showRecent = false, showPinned = false } })
            assert(W.config.windowPresentation == W.NS.BagsPresentation.PANEL, "catalog must default to side panel")
            Fill(W)
            local V, E, g = W.P.InventoryView, W.P.EquippedBags, W.P.InventoryView.geometry
            local t = W.M.windows[W.CF]
            assert(g.panel and not g.compact and g.rail == 112, "side panel uses a reserved rail and vertical sections")
            local fitted = W.P.BagPresentation.Scale(W.config, 0)
            assert(Near(W.CF:GetScale(), fitted), "native bag scale must follow deterministic viewport fit")
            assert(Near(W.CF:GetWidth(), g.rail + g.columns * 40 + 32), "root must contain body and rail")
            assert(Near(W.CF:GetHeight(), height / fitted - 24), "panel fills available screen height")
            assert(t.feather:IsShown() and t.heading:IsShown() and not t[1]:IsShown(), "panel decoration missing")
            assert(W.CF.TitleContainer.TitleText:GetAlpha() == 0, "native title duplicates own panel title")
            for _, control in pairs(V.tabs) do Inside(W, control, W.CF) end
            for _, control in ipairs({V.equipped,V.cleanup,V.manage,V.clearRecent}) do Inside(W, control, W.CF) end
            for _, cell in ipairs(V.model.layout) do
                if not cell.row then assert(cell.column == 0, "panel categories must stack vertically") end
            end
            for i = 1, V.labelCount do assert(not V.labels[i].plate.fill:IsShown(), "panel section still has a card fill") end
            for button in pairs(V.visibleButtons) do
                assert(button:GetParent() == W.CF and V.slotState[button].x >= g.rail + 16, "item invades the rail or changes owner")
                Inside(W, button, W.CF)
            end
            W.S.Set("bags", "accentColor", "ff0000"); W.Settle()
            assert(not t[1]:IsShown() and t.feather:IsShown(), "same-mode restyle resurrects compact shadow")
            W.S.Set("bags", "backgroundOpacity", 40); W.Settle()
            assert(not t[1]:IsShown() and t.feather.gradient[3].a == .4, "panel opacity restyle loses feather")
            Inside(W, V.free, W.CF)
            Inside(W, t.goldLabel, W.CF)
            local initialHeight, initialWidth = W.CF:GetHeight(), W.CF:GetWidth()
            for i = 1, 3 do W.Native(UpdateContainerFrameAnchors); W.Settle() end
            assert(Near(W.CF:GetHeight(), initialHeight) and Near(W.CF:GetWidth(), initialWidth), "native anchoring feedback changes panel size")
            E.Toggle(); W.Settle()
            assert(g.top == 144 and not E.hint:IsShown(), "panel drawer geometry")
            for _, button in ipairs(E.buttons) do Inside(W, button, W.CF) end
            W.EnterCombat()
            assert(V.layout == "combat" and not t.feather:IsShown() and not t.heading:IsShown(), "combat must use physical-slot surface")
            for _, item in ipairs(V.index.items) do assert(item.button:IsShown(), "combat lost a physical slot") end
            W.CloseBags(); W.OpenBags(); W.Settle()
            assert(not V.chrome:IsShown() and not t.feather:IsShown(), "combat reopen retains panel over native slots")
            W.LeaveCombat(); W.Settle()
            assert(t.feather:IsShown() and V.layout == "suite", "combat end does not restore panel")
            W.CF.movable = true
            local oldHeight = W.CF:GetHeight()
            local cursorY = 500
            GetCursorPosition = function() return 500, cursorY end
            W.M:BeginWindowDrag(W.CF)
            cursorY = cursorY - 40
            W.M:EndWindowDrag(W.CF)
            W.Settle()
            assert(Near(W.CF:GetHeight(), oldHeight), "drag feeds moved bottom back into full-height dock")
            Inside(W, W.CF, W.UIParent)
            W.S.SetMany("bags", {windowX=-4096,windowY=-4096,windowMoved=true}); W.Settle()
            Inside(W, W.CF, W.UIParent)
            W.S.SetMany("bags", {windowX=4096,windowY=4096}); W.Settle()
            Inside(W, W.CF, W.UIParent)
            W.S.Set("bags", "windowMoved", false); W.Settle()
            local frames = #W.frames
            for i = 1, 3 do W.Fire("BAG_UPDATE_DELAYED"); W.Settle() end
            assert(#W.frames == frames, "warm panel refresh allocates frames or decorations")
            W.S.Set("bags", "windowPresentation", W.NS.BagsPresentation.WINDOW); W.Settle()
            assert(not g.panel and not t.feather:IsShown() and W.CF.TitleContainer.TitleText:GetAlpha() == 1, "compact switch fails restoration")
            W.S.Set("bags", "windowPresentation", W.NS.BagsPresentation.PANEL); W.Settle()
            W.S.Set("bags", "inventoryView", W.NS.BagsView.BLIZZARD_GRID); W.Settle()
            assert(not V.active and not t.feather:IsShown(), "native grid keeps panel chrome")
            W.S.Set("bags", "enabled", false); W.Settle()
            assert(not t.shell:IsShown() and not E.frame:IsShown(), "disable retains owned panel")
            assert(#W.taint == 0 and #W.combatLayout == 0 and #W.errors == 0, "panel introduces taint, protected writes or errors")
        end
    end
end
do
    local W = H.New(root, {catalogPresentation=true})
    W.CF.TitleContainer.TitleText:SetAlpha(.4)
    Fill(W)
    W.S.Set("bags", "windowPresentation", W.NS.BagsPresentation.WINDOW)
    W.Settle()
    assert(W.CF.TitleContainer.TitleText:GetAlpha()==.4, "compact handback overwrites native title's previous alpha")
end
print("Side panel footprint/scale/native transitions/combat/warm reuse passed: " .. (arg[2] or "Mainline"))
