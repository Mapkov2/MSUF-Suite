local root, client = assert(arg[1]), arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local function World(config, reduced)
    local W = H.New(root, {client=client, catalogPresentation=true, config=config, reducedMotion=reduced})
    W.sizes[0] = 36
    W.Define(101, {name="Main Hand", class=2, subclass=1, equipLoc="INVTYPE_WEAPONMAINHAND"})
    W.Define(102, {name="Consumable", class=0, subclass=1})
    W.Put(0,1,101,1); W.Put(0,2,102,1)
    W.Apply()
    if W.config.enabled then W.OpenBags(); W.Settle() end
    return W
end
local function Click(W, button)
    assert(button:IsEnabled(), "disabled action")
    W.Insecure(assert(button:GetScript("OnClick")), button, "LeftButton")
end
local function Clean(W)
    assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0, "modeled native/combat failure")
end
for _, mode in ipairs({1,2,3}) do
    for _, reduced in ipairs({false,true}) do
        local W = World({inventoryView=3, windowPresentation=2, animationMode=mode, showRecent=false}, reduced)
        local V = W.P.InventoryView
        local before = assert(V.selectionView.tabSelection)
        local origin = before.y
        local rows = {}
        for _, button in ipairs(V.buttons) do
            if button:IsShown() and V.model.groupsByKey[button.categoryKey] then rows[#rows+1]=button end
        end
        assert(#rows>=2, "category sample incomplete")
        Click(W, rows[1]); W.Settle()
        local selected = V.selectionView.tabSelection
        assert(selected.selected==rows[1] and selected.frame:IsVisible(), "category fill missing")
        assert(selected.frame:GetFrameLevel()<rows[1]:GetFrameLevel(), "fill covers labels")
        if mode~=1 and not reduced then
            assert(selected.group:IsPlaying() and selected.fromY==origin, "category fill does not travel")
            selected.move.progress = .4
            local y = selected.fromY + selected.moveY * .4
            Click(W, rows[2]); W.Settle()
            assert(math.abs(selected.fromY-y)<.001, "rapid category change jumps")
        else
            assert(not selected.group or not selected.group:IsPlaying(), "Off/reduced category motion")
        end
        W.CloseBags()
        assert(not selected.group or not selected.group:IsPlaying(), "hidden category motion remains")
        Clean(W)
    end
end
-- A sub-cell pointer movement must change the actual root, without rescanning
-- items or saving settings. Releasing outside the grip still commits once.
do
    local W = World({inventoryView=1, windowPresentation=2, animationMode=1,
        autoSizeWindow=false, inventoryColumns=10, inventoryRows=5})
    local V, R = W.P.InventoryView, W.P.BagResize
    local scans, builds, saves = 0, 0, 0
    local read, build, save = W.P.InventoryIndex.ReadContainer, W.P.GridView.Build, W.S.SetMany
    W.P.InventoryIndex.ReadContainer = function(...) scans=scans+1; return read(...) end
    W.P.GridView.Build = function(...) builds=builds+1; return build(...) end
    W.S.SetMany = function(...) saves=saves+1; return save(...) end
    W.mouseDown, W.mouseX, W.mouseY = true, 1200, 800
    V.resize:GetScript("OnMouseDown")(V.resize, "LeftButton")
    local width, height = W.CF:GetWidth(), W.CF:GetHeight()
    W.mouseX, W.mouseY = 1203, 797; W.Frame()
    assert(W.CF:GetWidth()~=width or W.CF:GetHeight()~=height, "drag only draws a preview")
    W.mouseX, W.mouseY = 1300, 710; W.Frame()
    assert(scans==0 and builds==0 and saves==0, "drag does cold data/settings work")
    W.mouseDown=false; W.Frame(); W.Settle()
    assert(saves==1 and not R.active and not R.driver:GetScript("OnUpdate"), "outside release save/cleanup")
    width, height = W.CF:GetWidth(), W.CF:GetHeight()
    W.mouseDown=true; R.Begin(nil,"LeftButton")
    W.mouseX, W.mouseY = 1400, 600; W.Frame()
    W.S.SetMany=function() return false end
    W.mouseDown=false; W.Frame(); W.Settle()
    assert(W.CF:GetWidth()==width and W.CF:GetHeight()==height, "rejected save retains temporary size")
    Clean(W)
end
for _, mode in ipairs({1,2,3}) do
    for _, reduced in ipairs({false,true}) do
        local W = World({inventoryView=1, animationMode=mode, autoSizeWindow=false, inventoryRows=4}, reduced)
        local V, motion = W.P.InventoryView, W.P.BagWindowMotion
        local scans, builds = 0, 0
        W.P.InventoryIndex.ReadContainer=function() scans=scans+1 end
        W.P.GridView.Build=function() builds=builds+1 end
        local height = W.CF:GetHeight()
        W.M.config.inventoryRows=10; W.P.InventoryRendering.Suite()
        local target = V.geometry.height
        if mode~=1 and not reduced then
            assert(motion.active and W.CF:GetHeight()==height, "size change snaps")
            W.Frame()
            assert(W.CF:GetHeight()>height and W.CF:GetHeight()<target, "size lacks intermediate geometry")
        else
            assert(not motion.active and W.CF:GetHeight()==target, "Off/reduced size still animates")
        end
        W.Settle()
        assert(W.CF:GetHeight()==target and not motion.active, "size motion misses exact target")
        assert(scans==0 and builds==0, "size animation rebuilds inventory data")
        assert(not motion.driver or not motion.driver:GetScript("OnUpdate"), "idle size driver remains")
        Clean(W)
    end
end
-- Exercise actual editor, custom scrollbar and search callbacks together.
do
    local W = World({inventoryView=3, animationMode=3, customCategories="1|Gear|101\n1|Food|102"})
    local E, UI = W.P.InventoryEditor, W.P.BagWidgets
    E.Show()
    assert(UI.panels[E.frame] and UI.panels[E.name], "editor does not use shared surfaces")
    Click(W,E.rows[2])
    assert(E.selectionView.tabSelection.group:IsPlaying(), "editor category fill missing")
    E.name:SetText("Food rule"); E.rule:SetText("quality>=1"); Click(W,E.save)
    local encoded=W.config.customCategories
    E.rule:SetText("quality>="); Click(W,E.save)
    assert(W.config.customCategories==encoded and E.status:GetText()~="", "invalid category saved")
    local scroll, child = UI.Scroll(UIParent,140)
    scroll:SetSize(140,100); child:SetHeight(500); UI.UpdateScroll(scroll)
    local bar=scroll.bagScrollBar
    assert(bar.kind=="Slider" and bar.Thumb, "native slider input lost")
    bar:SetValue(210)
    scroll:GetScript("OnMouseWheel")(scroll,-1)
    for i=1,20 do W.Frame() end
    assert(scroll:GetVerticalScroll()==276 and bar:GetValue()==276, "wheel/slider diverge")
    child:SetHeight(50); UI.UpdateScroll(scroll)
    assert(not bar:IsShown() and scroll:GetVerticalScroll()==0, "short list retains scroll")
    E.Hide()
    local V, menu = W.P.InventoryView, W.P.BagFilterMenu
    V.smartSearch:SetText("is:equipment")
    W.P.InventorySearch.Menu(V.filterButton,V.smartSearch)
    assert(UI.panels[menu.frame], "filter popup does not use shared surface")
    function menu.frame:IsMouseOver() return false end
    function V.filterButton:IsMouseOver() return true end
    W.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    Click(W,V.filterButton)
    assert(not menu.frame:IsShown(), "owner click closes then immediately reopens filters")
    W.P.InventorySearch.Menu(V.filterButton,V.smartSearch)
    local action
    for _, row in ipairs(menu.rows) do
        if row.entry and row.entry.node.label=="Create category from this search" then action=row end
    end
    Click(W,assert(action))
    local categories=W.P.InventoryModel.DecodeCategories(W.config.customCategories)
    assert(E.frame:IsShown() and categories[#categories].query=="is:equipment", "search-to-category loses rule")
    W.EnterCombat()
    assert(not E.frame:IsShown() and not menu.frame:IsShown(), "combat retains editor/popup")
    Clean(W)
end
-- Cold disabled setup has no M.config; an old inactive config can also belong
-- to a previous profile. Own UI must read the public current-profile getter.
for _, cold in ipairs({false,true}) do
    local W=World({enabled=not cold, customCategories="1|Gear|101"})
    if not cold then W.S.Set("bags","enabled",false) end
    local current=W.S.Config; local fresh={}
    for key,value in pairs(current("bags")) do fresh[key]=value end
    fresh.backgroundColor, fresh.accentColor="ff0000","00ff00"
    W.S.Config=function(id) if id=="bags" then return fresh end; return current(id) end
    local E, UI=W.P.InventoryEditor,W.P.BagWidgets
    E.Show()
    local color=UI.panels[E.frame].fill.color
    assert(color[1]==1 and color[2]==0 and color[3]==0, "inactive editor palette stale")
    W.Insecure(E.rows[1]:GetScript("OnEnter"),E.rows[1])
    W.Insecure(E.rows[1]:GetScript("OnLeave"),E.rows[1])
    local thumb=E.scroll.bagScrollBar.Thumb.color
    assert(thumb[1]==0 and thumb[2]==1 and thumb[3]==0, "inactive scrollbar accent stale")
    E.Hide(); fresh.backgroundColor="0000ff"; E.Show()
    color=UI.panels[E.frame].fill.color
    assert(color[1]==0 and color[3]==1, "cached window does not repaint on reopen")
    Clean(W)
end
print("Live bag resize, category motion and themed UI passed: "..client)
