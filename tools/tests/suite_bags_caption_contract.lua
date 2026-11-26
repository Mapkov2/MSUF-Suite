-- The bag windows' Windows caption (MSUF_Suite_Bags/BagCaption.lua) against
-- the client model of suite_bags_harness.lua with the FULL Bags TOC loaded:
-- minimize, maximize and close cells as on the Blizzard windows the Skin
-- dresses, Blizzard's X faded under the close cell with its click, minimize
-- and the restore tab through secure clicks on Blizzard's own buttons (no
-- taint, no protected bag window), maximize as the side panel's full screen
-- height, combat, the Gamepad UI, the compact window and a clean release.
local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_bags_harness.lua")
local flavor = arg[2] or "Mainline"

local function Near(a, b) return math.abs(a - b) < .01 end
local function SameRect(W, a, b, why)
    local ax, ay, aw, ah = W.Rect(a)
    local bx, by, bw, bh = W.Rect(b)
    assert(ax and bx and Near(ax, bx) and Near(ay, by) and Near(aw, bw) and Near(ah, bh), why)
end

local function World(config, options)
    options = options or {}
    options.client, options.catalogPresentation, options.config = flavor, true, config or {}
    local W = H.New(root, options)
    W.sizes[0], W.sizes[1] = 20, 16
    for id = 1, 12 do
        W.Define(id, { name = "Item " .. id, class = id < 6 and 4 or 7, equipLoc = id < 6 and "INVTYPE_CHEST" or "" })
        W.Put(id <= 10 and 0 or 1, id <= 10 and id or id - 10, id, 1)
    end
    W.Apply()
    W.OpenBags()
    W.Settle()
    return W
end

-- The secure button that clicks target, or nil.
local function Delegate(W, target)
    for _, frame in ipairs(W.frames) do
        if frame:GetAttribute("clickbutton1") == target then return frame end
    end
end

local function RestoreTab(W)
    for _, frame in ipairs(W.frames) do
        if frame.label and frame.parent == W.UIParent and frame.label:GetText() == "Backpack  +" then return frame end
    end
end

local function CheckEvents(W, enter, leave, scale, why)
    for _, frame in ipairs(W.frames) do
        local handler = frame:GetScript("OnEvent")
        if handler and debug.getinfo(handler, "S").source:find("BagCaption.lua", 1, true) then
            assert(frame:IsEventRegistered("PLAYER_REGEN_DISABLED") == enter, why .. ": combat entry")
            assert(frame:IsEventRegistered("PLAYER_REGEN_ENABLED") == leave, why .. ": combat exit")
            assert(frame:IsEventRegistered("UI_SCALE_CHANGED") == scale, why .. ": UI scale")
            return
        end
    end
    assert(not enter and not leave and not scale, why .. ": no listener for visible caption")
end

local function Fill(cell) return cell.caption.fill.color end

-- The anchor of frame at point (a two-point anchor's one side).
local function Point(frame, name)
    for _, point in ipairs(frame.points) do
        if point[1] == name then return point end
    end
end

do
    local W = World({ inventoryView = 4, windowScale = .9, windowMoved = true, windowX = -220, windowY = 110 })
    local frame = W.CF
    local button = W.P.BagCaption.states[frame].maximize
    assert(button:IsMouseEnabled() and not button.bagDisabled, "Blizzard grid cannot maximize")
    local x, y, width, height = frame:GetScaledRect()
    local nativeWidth, nativeHeight = frame:GetSize(true)
    local slotPoint, slotOwner, _, slotX, slotY = frame.Items[1]:GetPoint()
    W.RunScript(button, "OnClick", "LeftButton")
    W.Settle()
    local left, bottom, fittedWidth, fittedHeight = frame:GetScaledRect()
    assert(button.caption.kind == "restore" and fittedWidth > width and fittedHeight > height, "Blizzard grid did not fit")
    assert(Near(left + fittedWidth / 2, W.screenWidth / 2) and Near(bottom + fittedHeight / 2, W.screenHeight / 2)
        and fittedWidth <= W.screenWidth and fittedHeight <= W.screenHeight, "maximized grid exceeds the viewport")
    local point, owner, _, itemX, itemY = frame.Items[1]:GetPoint()
    assert(frame:GetWidth() == nativeWidth and frame:GetHeight() == nativeHeight and point == slotPoint and owner == slotOwner
        and itemX == slotX and itemY == slotY, "maximize changed the native item layout")
    assert(not W.P.BagResize.scaleGrip:IsVisible() and W.config.windowScale == .9 and not W.config.panelFullHeight,
        "maximize changed saved dimensions or left the scale grip active")
    local screenWidth = W.screenWidth
    W.screenWidth = 600
    W.Fire("UI_SCALE_CHANGED")
    local resizedX, _, resizedWidth = frame:GetScaledRect()
    assert(resizedWidth <= W.screenWidth and Near(resizedX + resizedWidth / 2, W.screenWidth / 2),
        "maximized bag did not refit the changed viewport")
    W.S.GamepadUI = function() return true end
    W.Native(frame.CloseButton.Hide, frame.CloseButton)
    CheckEvents(W, false, false, true, "visible maximized native grid under gamepad UI")
    W.S.GamepadUI = function() return false end
    W.Native(frame.CloseButton.Show, frame.CloseButton)
    W.CloseBags()
    CheckEvents(W, false, false, false, "hidden maximized bag")
    W.screenWidth = screenWidth
    W.Fire("UI_SCALE_CHANGED")
    W.OpenBags()
    W.Settle()
    local shownX, _, shownWidth = frame:GetScaledRect()
    assert(Near(shownX + shownWidth / 2, W.screenWidth / 2),
        "reopening a maximized bag used the viewport from before it closed")
    W.EnterCombat()
    assert(button.bagDisabled, "maximize still takes input in combat")
    W.LeaveCombat()
    W.Settle()
    W.RunScript(button, "OnClick", "LeftButton")
    W.Settle()
    local restoredX, restoredY, restoredWidth, restoredHeight = frame:GetScaledRect()
    assert(button.caption.kind == "maximize" and Near(restoredX, x) and Near(restoredY, y)
        and Near(restoredWidth, width) and Near(restoredHeight, height), "restore lost the original bag geometry")
    assert(W.P.BagResize.scaleGrip:IsVisible() and #W.taint == 0 and #W.combatLayout == 0,
        "restoring the Blizzard grid changed protected layout or lost its grip")
    W.RunScript(button, "OnClick", "LeftButton")
    W.S.Set("bags", "inventoryView", W.NS.BagsView.ALL)
    W.Settle()
    W.S.Set("bags", "inventoryView", W.NS.BagsView.BLIZZARD_GRID)
    W.Settle()
    assert(button.caption.kind == "maximize" and W.P.BagResize.scaleGrip:IsVisible(),
        "switching views retained an old maximized bag")
end

---------------------------------------------------------------- the caption
local W = World()
local dataTexts = { showMinimizedWindows = false }
local readConfig = W.S.Config
function W.S.Config(id)
    if id == "dataTexts" then return dataTexts end
    return readConfig(id)
end
assert(loadfile(root .. "/MSUF_Suite/Core/MinimizedWindows.lua"))("MSUF_Suite", W.NS)
local taskbar = W.NS.MinimizedWindows
local Caption, X = W.P.BagCaption, W.CF.CloseButton
local state = assert(Caption.states[W.CF], "the combined bag has no caption")
local close, maximize, minimize = state.close, state.maximize, state.minimize
assert(close and maximize and minimize, "the combined bag lacks a caption cell")
assert(close:IsVisible() and maximize:IsVisible() and minimize:IsVisible(), "the caption does not show on the open bag")
assert(close.caption.kind == "close" and maximize.caption.kind == "maximize" and minimize.caption.kind == "minimize",
    "the caption cells show the wrong glyphs")
assert(X.alpha == 0 and X:IsShown(), "Blizzard's X still shows its own art under the caption")
SameRect(W, close, X, "Blizzard's X does not lie exactly under the close cell")
assert(X:GetWidth() == 30 and X:GetHeight() == 24, "the close cell is not Blizzard's X's whole hit area")
assert(not close:IsMouseEnabled() and X:IsMouseEnabled(), "the close cell takes the X's click away")
assert(close:GetFrameLevel() > X:GetFrameLevel(), "Blizzard's X draws over the close cell")
-- Right to left, flush in the top right corner one pixel inside the edge.
local fx, fy, fw, fh = W.Rect(W.CF)
local cx, cy, cw, ch = W.Rect(close)
local mx, _, mw = W.Rect(maximize)
local nx, _, nw = W.Rect(minimize)
assert(Near(cx + cw, fx + fw - 1) and Near(cy + ch, fy + fh - 1), "the caption is not in the window's top right corner")
assert(Near(mx + mw, cx) and Near(nx + nw, mx) and cw == mw and mw == nw, "the caption cells are not one row of equal cells")
-- The side panel's tools, heading and drag strip end left of the caption.
local V, t = W.P.InventoryView, W.M.windows[W.CF]
for _, tool in ipairs({ V.equipped, V.cleanup, V.manage, V.listToggle }) do
    local tx, _, tw = W.Rect(tool)
    assert(tx + tw <= nx - 8 + .01, "a panel tool lies under the caption")
end
local heading = assert(Point(t.heading, "TOPRIGHT"), "the panel heading has no right end")
assert(-heading[4] >= Caption.PANEL_TITLE, "the panel heading runs under the tools or the caption")
local dx, _, dw = W.Rect(t.dragHandle)
assert(dx + dw <= nx - 8 + .01, "the panel's drag strip covers the caption")

---------------------------------------------------------------- close
-- Blizzard's X lights the close cell: red under the pointer, white cross.
W.Hover(X)
assert(close.caption.hover and Fill(close)[4] > .8 and close.caption.bars[1].color[1] == 1, "the X's hover leaves the close cell dark")
W.Native(function() X.scripts.OnLeave(X) end)
assert(not close.caption.hover and Fill(close)[4] == 0, "the close cell stays lit after the pointer left")
X:SetAlpha(1)
assert(X.alpha == 0, "an alpha write brought Blizzard's X art back over the caption")
W.Native(function() X:Click("LeftButton") end)
assert(not W.CF:IsShown() and #W.taint == 0, "Blizzard's X did not close the bag cleanly")
assert(not RestoreTab(W) or not RestoreTab(W):IsShown(), "closing the bag left a restore tab")
W.OpenBags(); W.Settle()
assert(close:IsVisible() and X.alpha == 0, "the caption did not come back with the bag")

---------------------------------------------------------------- maximize
assert(maximize:IsMouseEnabled() and not maximize.bagDisabled, "the side panel's maximize is unavailable")
W.RunScript(maximize, "OnClick", "LeftButton")
W.Settle()
assert(W.config.panelFullHeight == true and V.geometry.fullHeight, "maximize did not give the panel the full screen height")
assert(maximize.caption.kind == "restore", "a full height panel does not offer its restore glyph")
W.RunScript(maximize, "OnClick", "LeftButton")
W.Settle()
assert(W.config.panelFullHeight == false and not V.geometry.fullHeight and maximize.caption.kind == "maximize",
    "restore did not give the panel its own height back")

---------------------------------------------------------------- minimize
local function Click(frame, button, x, y)
    local left, bottom, width, height = W.Rect(frame)
    W.mouseX, W.mouseY = x or left + width / 2, y or bottom + height / 2
    W.SecureClick(frame, button)
end
local delegate = assert(Delegate(W, X), "minimize is unarmed until the mouse moves")
assert(delegate:IsShown() and delegate:GetParent() == W.UIParent and delegate.points[1][2] == W.UIParent
    and delegate:GetAttribute("type1") == "click", "the secure minimize click anchors to the native bag")
assert(delegate:IsMouseEnabled() and not minimize:IsMouseEnabled(), "the painted minus can take the secure click")
assert(delegate:GetFrameStrata() == "HIGH", "the native bag header can cover the minimize click")
SameRect(W, delegate, minimize, "the secure click is not over the minimize cell")
Click(delegate, "LeftButton", -10, -10)
assert(W.CF:IsShown(), "an old hit rectangle minimized the bag")
W.RunScript(delegate, "OnEnter")
assert(minimize.caption.hover, "the minimize cell does not light under the pointer")
W.RunScript(delegate, "OnLeave")
assert(delegate:IsShown() and not minimize.caption.hover, "moving off the minus unarmed it or left it highlighted")
Click(delegate)
assert(not W.CF:IsShown() and #W.taint == 0, "minimize did not close the bag through Blizzard's X")
local tab = assert(RestoreTab(W), "minimize left no restore tab")
CheckEvents(W, true, true, true, "restore tab without the bag")
W.EnterCombat()
assert(not delegate:IsShown(), "the standalone restore delegate was left armed at combat entry")
W.LeaveCombat()
W.Settle()
assert(Delegate(W, W.Backpack) == delegate, "combat exit did not rearm a standalone restore tab")
W.Fire("UI_SCALE_CHANGED")
SameRect(W, delegate, tab, "restoring after a scale notification left the secure hit rectangle behind")
assert(tab:IsShown() and tab:GetFrameStrata() == "DIALOG", "the restore tab does not show")
assert(delegate:IsShown() and Delegate(W, W.Backpack) == delegate and not Delegate(W, X),
    "the secure input did not move to the restore tab")
local tx, ty, _, th = W.Rect(tab)
assert(Near(tx, fx) and Near(ty + th, fy + fh), "the restore tab does not take the window's place")
dataTexts.showMinimizedWindows = true
taskbar.Refresh()
assert(taskbar.IsDocked(tab), "the Bags restore button did not appear on the DataTexts taskbar")
local reopen = assert(Delegate(W, W.Backpack), "the restore tab has no secure click on Blizzard's backpack button")
assert(reopen == delegate and reopen.points[1][2] == W.UIParent, "the restore uses a secure anchor to the tab")
SameRect(W, reopen, tab, "the restore click is not over the tab")
W.NS.AnchorPoints = { "TOPLEFT" }
dataTexts.minimizedWindowsPoint = 1
taskbar.Refresh()
local _, strip = tab:GetPoint(1)
assert(strip:GetPoint(1) == "TOPLEFT", "the bag tab did not follow the taskbar to the top-left corner")
SameRect(W, reopen, tab, "moving the taskbar left the bag's secure hit area behind")
Click(reopen)
W.Settle()
assert(W.CF:IsShown() and not tab:IsShown() and #W.taint == 0, "the restore tab did not reopen the bag cleanly")
assert(reopen:IsShown() and Delegate(W, X) == reopen and not taskbar.IsDocked(tab),
    "restoring did not rearm minimize or left a docked entry")
dataTexts.showMinimizedWindows = false
-- The right button dismisses the tab and leaves the bag closed.
Click(delegate)
assert(tab:IsShown(), "a second minimize left no tab")
Click(delegate, "RightButton")
assert(not tab:IsShown() and not W.CF:IsShown() and not delegate:IsShown() and #W.taint == 0,
    "the right button did not dismiss the tab and its click area")
CheckEvents(W, false, false, false, "dismissed restore tab")
-- The player's own key opens the bag: the tab goes.
W.OpenBags(); W.Settle()
Click(delegate)
assert(tab:IsShown(), "minimize left no tab")
W.OpenBags(); W.Settle()
assert(not tab:IsShown(), "the restore tab outlived the bag's own opening")

---------------------------------------------------------------- combat
assert(delegate:IsShown(), "minimize lost its secure click")
local layout = #W.combatLayout
local px, py, pw, ph = W.Rect(delegate)
W.mouseX, W.mouseY = px + pw / 2, py + ph / 2
W.RunScript(delegate, "OnMouseDown", "LeftButton")
W.EnterCombat()
assert(not delegate:IsShown() and delegate:GetNumPoints() == 0, "the secure click survived the combat start")
assert(close:IsVisible() and X.alpha == 0, "combat brought Blizzard's X back over the caption")
assert(minimize.bagDisabled and maximize.bagDisabled and not minimize:IsMouseEnabled() and not maximize:IsMouseEnabled(),
    "minimize and maximize take clicks in combat")
assert(minimize.caption.bars[1].color[1] < .6, "disabled cells keep their bright glyphs")
assert(not delegate:IsShown(), "minimize armed its secure click in combat")
X:SetAlpha(.5)
assert(X.alpha == 0, "a combat alpha write brought Blizzard's X art back")
W.CloseBags(); W.OpenBags(); W.Settle()
assert(close:IsVisible() and #W.combatLayout == layout, "the caption moved the protected bag window in combat")
W.LeaveCombat(); W.Settle()
assert(not minimize.bagDisabled and not maximize.bagDisabled and delegate:IsShown() and Delegate(W, X) == delegate,
    "minimize or maximize failed to resume after combat")

---------------------------------------------------------------- MSUF Edit Mode
W.S.editMode = true
W.M:Refresh()
assert(minimize.bagDisabled and maximize.bagDisabled and not delegate:IsShown(), "MSUF Edit Mode can minimize or maximize the bag")
W.S.editMode = false
W.M:Refresh()
assert(not minimize.bagDisabled, "minimize stayed disabled after MSUF Edit Mode")

---------------------------------------------------------------- the Gamepad UI
-- Blizzard hides its X there (ContainerFrameCombinedBagsMixin:InitializeGamepad).
W.S.GamepadUI = function() return true end
W.Native(function() X:Hide() end)
assert(not close:IsShown() and not maximize:IsShown() and not minimize:IsShown() and not delegate:IsShown(),
    "the caption or its click area stayed under the Gamepad UI")
W.S.GamepadUI = function() return false end
W.Native(function() X:Show() end)
assert(close:IsShown() and minimize:IsShown(), "the caption did not return with Blizzard's X")

---------------------------------------------------------------- the reagent bag
W.Native(function() W.Reagent:Show() end)
W.Settle()
local reagent = assert(Caption.states[W.Reagent], "the reagent bag has no caption")
assert(reagent.close:IsVisible(), "the open reagent bag shows no close cell")
assert(reagent.close and not reagent.maximize and not reagent.minimize and #reagent.cells == 1,
    "the reagent bag's caption is not its close cell alone")
assert(W.Reagent.CloseButton.alpha == 0, "the reagent bag's X still shows its own art")
SameRect(W, reagent.close, W.Reagent.CloseButton, "the reagent bag's X does not lie under its close cell")

---------------------------------------------------------------- release
W.S.Set("bags", "enabled", false)
assert(not W.M.active, "Bags did not stop")
CheckEvents(W, false, false, false, "disabled bag profile")
assert(X.alpha == 1 and X:GetWidth() == (flavor == "Forever" and 28 or 24), "the stop kept Blizzard's X faded or resized")
local point = X.points[1]
assert(point[1] == "TOPRIGHT" and point[4] == (flavor == "Forever" and 0 or 1) and point[5] == (flavor == "Forever" and 3 or 0),
    "the stop did not give Blizzard's X its own place back")
assert(not close:IsShown() and not minimize:IsShown(), "the caption outlived the module")
assert(not delegate:IsShown() and delegate:GetNumPoints() == 0, "the secure click outlived the module")
X:SetAlpha(.4)
assert(X.alpha == .4, "a stopped caption still fades Blizzard's X")

---------------------------------------------------------------- the compact window
local C = World({ windowPresentation = 1 })
local compact = C.P.BagCaption.states[C.CF]
assert(compact.minimize:IsVisible() and compact.close:IsVisible(), "the compact window lost its caption")
assert(compact.maximize.bagDisabled and not compact.maximize:IsMouseEnabled(),
    "the compact window offers the side panel's full height")
local title = assert(Point(C.CF.TitleContainer, "TOPRIGHT"), "the compact window's title has no right end")
assert(title[4] == -C.P.BagCaption.WIDE, "the compact window's title runs under the caption")
C.RunScript(compact.maximize, "OnClick", "LeftButton")
assert(C.config.panelFullHeight == false, "the compact window's disabled maximize changed a setting")

-- The native grid exposes fit independently of the Suite panel's height.
local G = World({ inventoryView = 4 })
local grid = G.P.BagCaption.states[G.CF]
assert(grid.close:IsVisible() and grid.maximize:IsMouseEnabled() and not grid.minimize.bagDisabled,
    "Blizzard's bag grid lost a caption control")

do
    local Q = World({ inventoryView = 4 })
    local cap = Q.P.BagCaption
    local originalSync, hiddenPaints = cap.Sync, 0
    cap.Sync = function(entry, event)
        if event and not entry.frame:IsVisible() then hiddenPaints = hiddenPaints + 1 end
        return originalSync(entry, event)
    end
    Q.Native(Q.Reagent.Show, Q.Reagent)
    Q.Native(Q.Reagent.Hide, Q.Reagent)
    Q.CloseBags()
    CheckEvents(Q, false, false, false, "all previously created bag windows closed")
    Q.Fire("UI_SCALE_CHANGED")
    Q.EnterCombat()
    Q.LeaveCombat()
    assert(hiddenPaints == 0, "closed combat edges repainted historical caption states")
    Q.OpenBank()
    CheckEvents(Q, false, false, false, "bank without a backpack caption")
    Q.CloseBank()
    Q.Native(Q.Reagent.Show, Q.Reagent)
    CheckEvents(Q, false, false, true, "independent reagent close glyph")
    Q.EnterCombat()
    Q.LeaveCombat()
    assert(cap.states[Q.Reagent].close:IsVisible() and hiddenPaints == 0, "reagent combat processing reached a hidden bag")
    Q.Native(Q.Reagent.Hide, Q.Reagent)
    if flavor == "Forever" then
        local standalone = Q.NewIndividualBag("CaptionStandalone", 1)
        Q.Native(standalone.Show, standalone)
        cap.Attach(Q.M, standalone, { shell = standalone })
        CheckEvents(Q, false, false, true, "independent standalone close glyph")
        Q.Native(standalone.Hide, standalone)
    end
    CheckEvents(Q, false, false, false, "last independently shown bag closed")
    Q.OpenBags()
    Q.Settle()
    CheckEvents(Q, true, true, true, "backpack reopened")
    local proxy = assert(Delegate(Q, Q.CF.CloseButton))
    -- Model the edge where protected writes have already locked before the
    -- caption can release an armed proxy. The secure state driver owns hiding.
    Q.combat, Q.fighting = true, true
    Q.CloseBags()
    CheckEvents(Q, false, true, false, "locked delegate cleanup")
    Q.M.active = false
    cap.Release()
    CheckEvents(Q, false, true, false, "profile release while cleanup is blocked")
    Q.LeaveCombat()
    assert(not proxy:IsShown() and proxy:GetNumPoints() == 0 and not proxy:GetAttribute("clickbutton1"),
        "protected delegate was not released when combat ended")
    CheckEvents(Q, false, false, false, "protected cleanup complete")
    assert(#Q.taint == 0 and #Q.combatLayout == 0, "visibility routing triggered a protected write")
end

print("Bags caption " .. flavor .. ": cells, close, maximize, minimize, restore, combat, gamepad, reagent and release passed")
