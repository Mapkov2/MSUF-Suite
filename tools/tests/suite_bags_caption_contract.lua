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

local function Fill(cell) return cell.caption.fill.color end

-- The anchor of frame at point (a two-point anchor's one side).
local function Point(frame, name)
    for _, point in ipairs(frame.points) do
        if point[1] == name then return point end
    end
end

---------------------------------------------------------------- the caption
local W = World()
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
for _, tool in ipairs({ V.equipped, V.cleanup, V.manage, V.clearRecent }) do
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
W.RunScript(minimize, "OnEnter")
local delegate = assert(Delegate(W, X), "minimize has no secure click on Blizzard's X")
assert(delegate:IsShown() and delegate:GetParent() == W.UIParent and delegate.points[1][2] == minimize
    and delegate:GetAttribute("type1") == "click", "the secure minimize click is not over the minimize cell")
assert(minimize.caption.hover, "the minimize cell does not light under the pointer")
W.SecureClick(delegate)
assert(not W.CF:IsShown() and #W.taint == 0, "minimize did not close the bag through Blizzard's X")
local tab = assert(RestoreTab(W), "minimize left no restore tab")
assert(tab:IsShown() and tab:GetFrameStrata() == "DIALOG", "the restore tab does not show")
assert(not delegate:IsShown() and delegate:GetNumPoints() == 0, "the secure minimize click outlived its click")
local tx, ty, _, th = W.Rect(tab)
assert(Near(tx, fx) and Near(ty + th, fy + fh), "the restore tab does not take the window's place")
W.RunScript(tab, "OnEnter")
local reopen = assert(Delegate(W, W.Backpack), "the restore tab has no secure click on Blizzard's backpack button")
assert(reopen == delegate and reopen.points[1][2] == tab, "the restore click is not over the tab")
W.SecureClick(reopen)
W.Settle()
assert(W.CF:IsShown() and not tab:IsShown() and #W.taint == 0, "the restore tab did not reopen the bag cleanly")
assert(not reopen:IsShown(), "the restore click outlived its click")
-- The right button dismisses the tab and leaves the bag closed.
W.RunScript(minimize, "OnEnter")
W.SecureClick(delegate)
assert(tab:IsShown(), "a second minimize left no tab")
W.RunScript(tab, "OnEnter")
W.SecureClick(delegate, "RightButton")
assert(not tab:IsShown() and not W.CF:IsShown() and #W.taint == 0, "the right button did not dismiss the tab")
-- The player's own key opens the bag: the tab goes.
W.RunScript(minimize, "OnLeave")
W.OpenBags(); W.Settle()
W.RunScript(minimize, "OnEnter")
W.SecureClick(delegate)
assert(tab:IsShown(), "minimize left no tab")
W.OpenBags(); W.Settle()
assert(not tab:IsShown(), "the restore tab outlived the bag's own opening")

---------------------------------------------------------------- combat
W.RunScript(minimize, "OnEnter")
assert(delegate:IsShown(), "minimize lost its secure click")
local layout = #W.combatLayout
W.EnterCombat()
assert(not delegate:IsShown() and delegate:GetNumPoints() == 0, "the secure click survived the combat start")
assert(close:IsVisible() and X.alpha == 0, "combat brought Blizzard's X back over the caption")
assert(minimize.bagDisabled and maximize.bagDisabled and not minimize:IsMouseEnabled() and not maximize:IsMouseEnabled(),
    "minimize and maximize take clicks in combat")
assert(minimize.caption.bars[1].color[1] < .6, "disabled cells keep their bright glyphs")
W.RunScript(minimize, "OnEnter")
assert(not delegate:IsShown(), "minimize attached its secure click in combat")
X:SetAlpha(.5)
assert(X.alpha == 0, "a combat alpha write brought Blizzard's X art back")
W.CloseBags(); W.OpenBags(); W.Settle()
assert(close:IsVisible() and #W.combatLayout == layout, "the caption moved the protected bag window in combat")
W.LeaveCombat(); W.Settle()
assert(not minimize.bagDisabled and not maximize.bagDisabled and minimize:IsMouseEnabled(),
    "minimize and maximize stayed disabled after combat")

---------------------------------------------------------------- MSUF Edit Mode
W.S.editMode = true
W.M:Refresh()
assert(minimize.bagDisabled and maximize.bagDisabled, "MSUF Edit Mode can minimize or maximize the bag")
W.S.editMode = false
W.M:Refresh()
assert(not minimize.bagDisabled, "minimize stayed disabled after MSUF Edit Mode")

---------------------------------------------------------------- the Gamepad UI
-- Blizzard hides its X there (ContainerFrameCombinedBagsMixin:InitializeGamepad).
W.S.GamepadUI = function() return true end
W.Native(function() X:Hide() end)
assert(not close:IsShown() and not maximize:IsShown() and not minimize:IsShown(), "the caption stayed under the Gamepad UI")
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
assert(X.alpha == 1 and X:GetWidth() == (flavor == "Forever" and 28 or 24), "the stop kept Blizzard's X faded or resized")
local point = X.points[1]
assert(point[1] == "TOPRIGHT" and point[4] == (flavor == "Forever" and 0 or 1) and point[5] == (flavor == "Forever" and 3 or 0),
    "the stop did not give Blizzard's X its own place back")
assert(not close:IsShown() and not minimize:IsShown(), "the caption outlived the module")
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

-- Blizzard's own grid keeps the caption with its maximize unavailable.
local G = World({ inventoryView = 4 })
local grid = G.P.BagCaption.states[G.CF]
assert(grid.close:IsVisible() and grid.maximize.bagDisabled and not grid.minimize.bagDisabled,
    "Blizzard's bag grid lost its caption or offers the full height")

print("Bags caption " .. flavor .. ": cells, close, maximize, minimize, restore, combat, gamepad, reagent and release passed")
