local root = assert(arg[1], "repository root required")
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local function check(value, message) if not value then error(message, 2) end end
local WIDE = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\Wide.tga"
local SQUARE = "Interface\\ChatFrame\\ChatFrameBackground"
local ROUND = "Interface\\AddOns\\MSUF_Suite_Modules\\Media\\Minimap\\Circle.tga"

-- Ownership: the map moves one frame late, capture waits for Edit Mode, Blizzard's
-- cluster is neutralised (never hidden) and the mover replaces MSUF's adapter.
do
    local W = H.New(root, "Mainline")
    local G, S, map, cluster = W.G, W.S, W.map, W.cluster
    local foreign = function() return "CORNER-TOPLEFT" end
    G.GetMinimapShape = foreign
    H.Enable(W)
    local MM, M, c = W.MM, W.M, W.config
    check(MM.host and MM.host:GetName() == "MSUFSuiteMinimap" and MM.host.roleset == "minimap", "host frame missing")
    check(map:GetParent() == W.container, "minimap reparented synchronously")
    W.Step()
    check(map:GetParent() == W.container and M.captureWaiting, "capture ran before Edit Mode applied its layout")
    W.editModeReady = true
    W.Event("EDIT_MODE_LAYOUTS_UPDATED")
    check(map:GetParent() == W.container, "layout event reparented synchronously")
    W.Step()
    check(map:GetParent() == MM.clip and M.mapOwned, "minimap was not claimed one frame later")
    check(c.captured and c.size == 198 and c.point == 3 and c.x == -11 and c.y == -31, "Blizzard geometry was not captured once")
    check(MM.host.width == 198 and MM.host.height == 198, "host size")
    local point, relative, relativePoint, x, y = MM.host:GetPoint(1)
    check(point == "TOPRIGHT" and relative == W.UIParent and relativePoint == "TOPRIGHT" and x == -11 and y == -31, "host position")
    check(map.width == 198 and map.height == 198 and map.scale == 1 and map.fixedStrata and map.fixedLevel, "map geometry/locks")
    check(map.strata == "LOW" and map.level == MM.mapLevel, "map strata/level")
    check(map.mask == SQUARE and map.arch == 0 and map.quest == 0 and map.task == 0, "square mask and blob scalars")
    check(W.calls.zoom == 2 and map.zoom == 0, "claim did not nudge the zoom once")
    check(cluster.shown and cluster.alpha == 0 and not cluster.mouse, "cluster must stay shown at alpha 0 without mouse")
    check(G.MinimapCompassTexture.alpha == 0 and G.MinimapBackdrop.shown and G.MinimapBackdrop.alpha == 1, "compass/backdrop handling")
    check(G.TimeManagerClockButton.alpha == 0 and not G.TimeManagerClockButton.mouse, "clock button not neutralised")
    check(cluster.ZoneTextButton.alpha == 0 and not cluster.ZoneTextButton.mouse, "zone text not neutralised")
    check(not cluster.IndicatorFrame.shown, "emptied indicator frame must not stretch the cluster")
    check(G.GetMinimapShape ~= foreign and G.GetMinimapShape() == "SQUARE", "GetMinimapShape not provided")
    local mover = W.movers["MSUFSuite.minimap/map"]
    check(mover and mover.getFrame() == MM.host and mover.isEnabled(), "mover not registered")
    check(not W.hostRecord.isEnabled(), "MSUF's duplicate minimap adapter was not claimed")
    -- Capture once: a later enable keeps the saved layout even if Blizzard's map moved.
    assert(S.Set("minimap", "enabled", false))
    check(map:GetParent() == W.container and G.GetMinimapShape == foreign and W.hostRecord.isEnabled(), "disable did not restore")
    map.center = { 300, 200 }
    assert(S.Set("minimap", "enabled", true))
    W.Step()
    check(c.point == 3 and c.x == -11 and map:GetParent() == MM.clip, "capture ran twice")
    -- Shapes: circle keeps Blizzard's round mask; wide clips a square canvas.
    local zooms = W.calls.zoom
    assert(S.Set("minimap", "shape", 2))
    check(map.mask == ROUND and map.arch == 1 and map.quest == 1 and G.GetMinimapShape() == "ROUND", "circle")
    check(not MM.clip.clips and W.calls.zoom == zooms + 2, "circle nudge/clip")
    assert(S.Set("minimap", "shape", 3))
    check(map.mask == WIDE and G.GetMinimapShape() == "SQUARE" and map.arch == 0, "wide mask")
    check(MM.host.width == 198 and MM.host.height == 132 and map.width == 198 and map.height == 198, "wide geometry")
    check(MM.clip.clips and map.hitInsets[3] == 33 and map.hitInsets[4] == 33, "wide clipping and hit insets")
    -- HybridMinimap adopts the current shape when Blizzard loads it.
    local hybrid = W.New("Frame", "HybridMinimap", map)
    hybrid.CircleMask = hybrid:CreateTexture(nil, "OVERLAY")
    hybrid.CircleMask.texture = 130871
    W.Event("ADDON_LOADED", "Blizzard_HybridMinimap")
    check(hybrid.CircleMask.texture == WIDE, "hybrid mask not adapted")
    assert(S.Set("minimap", "shape", 2))
    check(hybrid.CircleMask.texture == 130871, "hybrid circle mask")
    assert(S.Set("minimap", "shape", 1))
    check(hybrid.CircleMask.texture == SQUARE and not MM.clip.clips and map.hitInsets[3] == 0, "hybrid square")
    assert(S.Set("minimap", "enabled", false))
    check(hybrid.CircleMask.texture == 130871 and map.mask == ROUND and map.arch == 1, "hybrid/mask restore")
    print("Minimap ownership, one-frame-late claim, capture-once, shapes, masks, HybridMinimap and GetMinimapShape passed")
end

-- Mouseover size is opt-in, deferred from native hover scripts, and restores
-- its original geometry on leave, in Edit Mode, and when disabled.
do
    local W = H.New(root, "Mainline")
    W.editModeReady = true
    H.Enable(W, { captured = true })
    W.Step()
    local S, MM, map, catcher = W.S, W.MM, W.map, W.MM.catcher
    check(not S.Config("minimap").hoverResize and MM.host.width == 190, "mouseover resize must default off")
    W.Fire(catcher, "OnEnter"); W.Step()
    check(MM.host.width == 190 and MM.host.height == 190, "default hover changed geometry")
    W.Fire(catcher, "OnLeave"); W.Advance(0.2)

    assert(S.SetMany("minimap", { hoverResize = true, hoverWidth = 300, hoverHeight = 240 }))
    check(MM.host.width == 190 and MM.host.height == 190, "idle hover size changed the map")
    W.Fire(catcher, "OnEnter")
    check(MM.host.width == 190, "hover resized inside the native mouse event")
    W.Step()
    check(MM.host.width == 300 and MM.host.height == 240 and map.width == 300 and map.height == 300,
        "independent hover width and height")
    check(map.mask == SQUARE and MM.clip.clips and map.hitInsets[3] == 30,
        "rectangular mouseover map needs square canvas and clipped hit area")
    S.SetEditMode(true); W.Step()
    check(MM.host.width == 190 and MM.host.height == 190, "Edit Mode must use the normal mover size")
    S.SetEditMode(false); W.Step()
    check(MM.host.width == 300 and MM.host.height == 240, "leaving Edit Mode did not restore mouseover size")
    W.Fire(catcher, "OnLeave"); W.Advance(0.2); W.Step()
    check(MM.host.width == 190 and MM.host.height == 190 and not MM.clip.clips,
        "leaving hover did not restore normal size and clipping")

    assert(S.SetMany("minimap", { hoverWidth = 120, hoverHeight = 140 }))
    W.Fire(catcher, "OnEnter"); W.Step()
    check(MM.host.width == 120 and MM.host.height == 140 and map.width == 140 and map.height == 140,
        "smaller custom rectangle must use its taller side as the square canvas")
    check(map.hitInsets[1] == 10 and map.hitInsets[2] == 10, "horizontal hidden bands must not catch clicks")
    check(catcher.points[1][4] <= -70 and catcher.points[2][5] <= -50,
        "hover catcher must retain the original footprint when the map shrinks")
    assert(S.SetMany("minimap", { styleBackdrop = true, styleBackdropPadding = 4 }))
    check(MM.style.backdrop.width == 128 and MM.style.backdrop.height == 148,
        "decorative plate must follow both mouseover dimensions")
    assert(S.Set("minimap", "shape", 2)); W.Step()
    check(MM.host.width == 120 and MM.host.height == 120 and map.mask == ROUND and not MM.clip.clips,
        "circular mouseover map must remain circular")
    assert(S.Set("minimap", "shape", 3)); W.Step()
    check(MM.host.width == 120 and MM.host.height == 140 and map.mask == SQUARE and MM.clip.clips,
        "wide shape must allow a custom hover aspect ratio")
    W.Fire(catcher, "OnLeave"); W.Advance(0.2); W.Step()
    check(MM.host.width == 190 and MM.host.height == 127 and map.mask == WIDE,
        "wide shape must restore its normal ratio and mask")
    assert(S.SetMany("minimap", { hoverWidth = 190, hoverHeight = 127 }))
    W.Fire(catcher, "OnEnter"); W.Step()
    check(map.mask == SQUARE, "hovering a wide map of equal dimensions still changes its mask")
    W.Fire(catcher, "OnLeave"); W.Advance(0.2); W.Step()
    check(map.mask == WIDE, "wide mask must return after an equal-size hover")

    assert(S.SetMany("minimap", { shape = 1, hoverWidth = 120, hoverHeight = 140 }))
    W.SetCombat(true)
    W.Fire(catcher, "OnEnter"); W.Step()
    check(MM.host.width == 190, "mouseover geometry changed in combat")
    W.SetCombat(false); W.Step()
    check(MM.host.width == 120 and MM.host.height == 140, "deferred hover size did not apply after combat")
    assert(S.Set("minimap", "hoverResize", false)); W.Step()
    check(MM.host.width == 190 and MM.host.height == 190, "disabling resize did not restore normal geometry")
    print("Minimap opt-in mouseover width/height, shapes, Edit Mode, combat and restore passed")
end

-- Border, split apply (dirty categories) and visibility modes.
do
    local W = H.New(root, "Mainline")
    W.editModeReady = true
    H.Enable(W, { captured = true })
    W.Step()
    local S, MM, map = W.S, W.MM, W.map
    check(S.Config("minimap").size == 190 and S.Config("minimap").showLanding == 2
        and S.Config("minimap").landingIcon == 1 and S.Config("minimap").shadowSize == 0,
        "minimap defaults")
    local edges, disc = MM.edges, MM.disc
    check(edges[1].shown and not disc.shown and not MM.shadows and edges[1].height == 1 and edges[3].width == 1,
        "default 1px square border creates no shadow textures")
    check(edges[1].color[1] == 0 and edges[1].color[4] == 1, "default black border")
    assert(S.SetMany("minimap", { borderSize = 3, borderColor = "ff0000" }))
    check(edges[1].height == 3 and edges[1].color[1] == 1 and edges[1].color[2] == 0, "border thickness/color")
    check(edges[1].points[1][4] == -3 and MM.host.clampInsets[1] == -3 and MM.host.clampInsets[3] == 3, "border sits outside, clamp includes it")
    assert(S.SetMany("minimap", { borderAlpha = 50, shadowSize = 9, shadowColor = "224466", shadowAlpha = 60 }))
    check(edges[1].color[4] == 0.5 and MM.shadows[1].edges[1].shown
        and MM.shadows[3].edges[4].shown and MM.host.clampInsets[1] == -12, "square border opacity and outer shadow")
    check(MM.shadows[1].edges[1].subLevel == -7 and MM.shadows[3].disc.subLevel == -5,
        "shadow draw levels must be passed after the nil texture template")
    check(H.Near(MM.shadows[1].edges[1].color[1], 0x22 / 255)
        and H.Near(MM.shadows[1].edges[1].color[4], 0.27), "shadow color and opacity")
    assert(S.Set("minimap", "showLanding", 3))
    check(W.G.ExpansionLandingPageMinimapButton:GetParent() == MM.park
        and not W.G.ExpansionLandingPageMinimapButton:IsVisible(), "Folio Never must work after applying a shadow")
    assert(S.Set("minimap", "showLanding", 2))
    assert(S.Set("minimap", "borderClassColor", true))
    check(H.Near(edges[2].color[1], 0.2) and H.Near(edges[2].color[3], 0.8), "class border")
    assert(S.Set("minimap", "shape", 2))
    local discSize = S.Config("minimap").size + 6
    check(disc.shown and not edges[1].shown and disc.width == discSize and disc.height == discSize, "round border disc")
    check(H.Near(disc.vertex[2], 0.4) and disc.texture:find("Circle.tga", 1, true), "disc art and tint")
    check(MM.shadows[1].disc.shown and not MM.shadows[1].edges[1].shown, "round shadow follows map shape")
    assert(S.Set("minimap", "shadowSize", 0))
    check(not MM.shadows[1].disc.shown and MM.host.clampInsets[1] == -3, "shadow can be removed")
    assert(S.Set("minimap", "borderSize", 0))
    check(not disc.shown and not edges[1].shown, "zero border")
    -- Split apply: only the touched category re-runs; only geometry nudges the map.
    local masks, zooms, sizes = W.calls.mask, W.calls.zoom, W.calls["SetSize:Minimap"]
    assert(S.Set("minimap", "infoClockColor", "00ff00"))
    assert(S.Set("minimap", "borderColor", "0000ff"))
    check(W.calls.mask == masks and W.calls.zoom == zooms and W.calls["SetSize:Minimap"] == sizes, "texts/border re-rendered the map")
    assert(S.Set("minimap", "elementSpacing", 6))
    check(W.calls.mask == masks and W.calls.zoom == zooms, "element spacing re-rendered the map")
    check(select(5, W.G.GameTimeFrame:GetParent():GetPoint(1)) == -27, "row spacing not applied")
    assert(S.Set("minimap", "x", -40))
    check(W.calls.mask == masks and W.calls.zoom == zooms and select(4, MM.host:GetPoint(1)) == -40, "moving re-rendered the map")
    assert(S.Set("minimap", "size", 240))
    check(W.calls.mask == masks + 1 and W.calls.zoom == zooms + 2 and map.width == 240 and MM.host.width == 240, "resize must nudge once")
    -- Visibility: combat conditions use a state driver registered out of combat only.
    local host = MM.host
    assert(S.Set("minimap", "visibility", 2))
    check(host.stateDriver == "[combat] show; hide" and not host.shown, "in-combat driver")
    W.SetCombat(true)
    check(host.shown, "driver did not show the map in combat")
    check(not S.Set("minimap", "visibility", 1), "settings must refuse combat edits")
    W.SetCombat(false)
    check(not host.shown, "driver did not hide the map after combat")
    assert(S.Set("minimap", "visibility", 3))
    check(host.stateDriver == "[combat] hide; show" and host.shown, "out-of-combat driver")
    assert(S.Set("minimap", "visibility", 5))
    check(host.stateDriver == nil and not host.shown, "never")
    S.SetEditMode(true)
    check(host.shown and host.stateDriver == nil, "edit mode must show the map")
    S.SetEditMode(false)
    check(not host.shown, "edit mode end did not restore never")
    assert(S.Set("minimap", "visibility", 4))
    local catcher = MM.catcher
    check(catcher:GetParent() == W.UIParent and catcher.shown and not host.shown, "mouseover catcher")
    check(catcher.clicks == false and catcher.motion == true and catcher.propagate == true, "catcher must pass clicks and propagate motion")
    check(catcher.level > W.map.level, "hidden mouseover map needs a wake area")
    W.Fire(catcher, "OnEnter")
    check(host.shown and catcher.level < W.map.level, "visible map must sit above its hover catcher")
    W.Fire(catcher, "OnLeave")
    check(host.shown, "leave must wait for the grace period")
    W.Advance(0.2)
    check(not host.shown and catcher.level > W.map.level, "leave did not restore the wake area")
    W.SetCombat(true)
    W.Fire(catcher, "OnEnter")
    check(not host.shown, "protected map shown in combat")
    W.SetCombat(false)
    check(host.shown, "queued mouseover state was not applied after combat")
    assert(S.Set("minimap", "visibility", 1))
    check(host.shown and catcher:GetParent() == host and catcher.level < W.map.level, "always")
    print("Minimap border, split apply categories and visibility (state driver, never, edit mode, mouseover) passed")
end

-- Input: wheel zoom, reset timer, middle click, zoom buttons and hover reveal.
do
    local W = H.New(root, "Mainline")
    W.editModeReady = true
    local calendar, worldMap = 0, 0
    W.G.ToggleCalendar = function() calendar = calendar + 1 end
    W.G.ToggleWorldMap = function() worldMap = worldMap + 1 end
    local nativeClicks = {}
    local nativeMouseUp = function(_, button)
        nativeClicks[button] = (nativeClicks[button] or 0) + 1
    end
    local nativeWheel = function() error("native wheel should be replaced while enabled") end
    W.map:SetScript("OnMouseUp", nativeMouseUp)
    W.map:SetScript("OnMouseWheel", nativeWheel)
    H.Enable(W, { captured = true })
    W.Step()
    local S, MM, map = W.S, W.MM, W.map
    local holder, catcher = MM.zoomHolder, MM.catcher
    check(MM.overlay == nil and map.mouse and map.wheel, "native map must own clicks and wheel")
    check(not MM.host.mouse and not MM.clip.mouse and not holder.mouse,
        "passive minimap layers must not intercept clicks")
    check(catcher.level < map.level and #map.hookedScripts.OnEnter == 1,
        "map must stay above its motion catcher and drive hover itself")
    local wheel = map:GetScript("OnMouseWheel")
    wheel(map, 1)
    check(map.zoom == 1 and W.Pending(5) == 0, "wheel zoom without reset")
    assert(S.Set("minimap", "zoomResetSeconds", 5))
    wheel(map, 1)
    check(map.zoom == 2 and W.Pending(5) == 1, "reset armed by wheel")
    wheel(map, -1)
    check(map.zoom == 1 and W.Pending(5) == 1, "re-arm must cancel the previous timer")
    for _ = 1, 8 do wheel(map, 1) end
    check(map.zoom == 5, "zoom capped at the last level")
    local before = W.Pending(5)
    wheel(map, 1)
    check(W.Pending(5) == before, "a no-op wheel re-armed the reset")
    W.Advance(5)
    check(map.zoom == 0 and map.ZoomOut.enabled == false, "zoom reset / button state")
    -- Blizzard's zoom buttons live in the suite holder; their clicks re-arm the reset.
    local zoomIn, zoomOut = map.ZoomIn, map.ZoomOut
    check(zoomIn:GetParent() == holder and zoomOut:GetParent() == holder and zoomIn.shown and zoomOut.shown, "zoom buttons adopted")
    assert(S.SetMany("minimap", { zoomInX = 30, zoomInY = 10 }))
    check(select(4, zoomIn:GetPoint(1)) == 28 and select(5, zoomIn:GetPoint(1)) == 37
        and select(4, zoomOut:GetPoint(1)) == -2, "zoom buttons need independent offsets")
    assert(S.SetMany("minimap", { zoomInX = 0, zoomInY = 0 }))
    check(not holder.shown and catcher.shown, "mouseover zoom buttons start hidden")
    zoomIn:SetScript("OnClick", function() map:SetZoom(map:GetZoom() + 1) end)
    zoomIn:Click()
    check(map.zoom == 1 and W.Pending(5) == 1, "zoom button click did not arm the reset")
    W.Fire(catcher, "OnEnter")
    check(holder.shown, "hover did not reveal zoom buttons")
    W.Blizzard(function() zoomIn:Hide() end)
    check(zoomIn.shown, "Blizzard's leave-hide must not win inside the holder")
    W.Fire(catcher, "OnLeave"); W.Advance(0.2)
    check(not holder.shown, "leave did not hide zoom buttons")
    assert(S.Set("minimap", "zoomButtons", 2))
    check(holder.shown, "always-shown zoom buttons")
    assert(S.Set("minimap", "zoomButtons", 3))
    check(zoomIn:GetParent() == MM.park and not MM.park.shown, "hidden zoom buttons must be parked")
    W.Blizzard(function() zoomIn:Show() end)
    check(not zoomIn:IsVisible(), "parked zoom buttons rendered")
    -- Scroll zoom off hands the wheel to the camera.
    assert(S.Set("minimap", "scrollZoom", false))
    check(not map.wheel, "wheel not released")
    wheel(map, 1)
    check(map.zoom == 1, "disabled wheel zoomed")
    assert(S.Set("minimap", "scrollZoom", true))
    check(map.wheel, "wheel not restored")
    -- Middle click: tracking menu, calendar, world map; nothing in combat.
    local mouseUp = map:GetScript("OnMouseUp")
    local tracking = W.cluster.Tracking.Button
    mouseUp(map, "MiddleButton")
    check(tracking.menuOpen, "tracking menu not opened")
    mouseUp(map, "MiddleButton")
    check(not tracking.menuOpen, "tracking menu not toggled")
    mouseUp(map, "LeftButton")
    mouseUp(map, "RightButton")
    check(not tracking.menuOpen and nativeClicks.LeftButton == 1 and nativeClicks.RightButton == 1,
        "native map clicks were swallowed")
    check(nativeClicks.MiddleButton == nil, "middle action also pinged the map")
    assert(S.Set("minimap", "middleClick", 3)); mouseUp(map, "MiddleButton")
    assert(S.Set("minimap", "middleClick", 4)); mouseUp(map, "MiddleButton")
    check(calendar == 1 and worldMap == 1, "calendar/world map actions")
    W.SetCombat(true); mouseUp(map, "MiddleButton"); W.SetCombat(false)
    check(worldMap == 1, "middle click acted in combat")
    assert(S.Set("minimap", "middleClick", 1)); mouseUp(map, "MiddleButton")
    check(worldMap == 1, "middle click nothing")
    -- Rotation: 1 leaves Blizzard's CVar alone and returns a suite write.
    assert(S.Set("minimap", "rotate", 2))
    check(W.cvars.rotateMinimap == "1", "rotate with player")
    W.cvars.rotateMinimap = "0" -- Blizzard Edit Mode applies its layout's rotation
    W.Event("EDIT_MODE_LAYOUTS_UPDATED")
    check(W.cvars.rotateMinimap == "0", "rotation re-applied inside Blizzard's handler")
    W.Step()
    check(W.cvars.rotateMinimap == "1", "an Edit Mode layout overrode the suite rotation")
    assert(S.Set("minimap", "rotate", 1))
    check(W.cvars.rotateMinimap == "0", "rotation not returned to Blizzard's value")
    assert(S.Set("minimap", "rotate", 3))
    W.cvars.rotateMinimap = "1"
    assert(S.Set("minimap", "enabled", false))
    check(map:GetScript("OnMouseUp") == nativeMouseUp and map:GetScript("OnMouseWheel") == nativeWheel,
        "native map scripts not restored")
    check(W.cvars.rotateMinimap == "1", "a later user change must survive disable")
    check(zoomIn:GetParent() == map and not zoomIn.shown and not zoomOut.shown, "zoom buttons not restored")
    print("Minimap wheel zoom, zoom reset, zoom buttons, middle click, rotation and hover reveal passed")
end

local function Anchor(frame)
    local point, relative, relativePoint, x, y = frame:GetPoint(1)
    return point, relative, relativePoint, x, y
end

-- Retail element row: Blizzard's own buttons in suite slots, packed by visibility.
do
    local W = H.New(root, "Mainline")
    W.editModeReady = true
    H.Enable(W, { captured = true })
    W.Step()
    local G, S, MM, cluster = W.G, W.S, W.MM, W.cluster
    local host = MM.host
    local tracking, calendar = cluster.Tracking, G.GameTimeFrame
    local mail, crafting = cluster.IndicatorFrame.MailFrame, cluster.IndicatorFrame.CraftingOrderFrame
    local compartment, difficulty, landing = G.AddonCompartmentFrame, cluster.InstanceDifficulty, G.ExpansionLandingPageMinimapButton
    check(S.MinimapElementAvailable("Tracking") and S.MinimapElementAvailable("Crafting") and S.MinimapElementAvailable("Landing"), "retail availability")
    check(S.MinimapElementAvailable("Compartment") and S.MinimapElementAvailable("Difficulty") and not S.MinimapElementAvailable("Bogus"), "availability")
    local defaultMode, guildMode = W.New("Frame", "DifficultyDefault", difficulty), W.New("Frame", "DifficultyGuild", difficulty)
    difficulty.ContentModes = { defaultMode, guildMode }
    defaultMode:Hide(); guildMode:Hide()
    check(S.MinimapElementPreviewShown("Difficulty") == false,
        "preview must hide an empty difficulty banner even while its outer frame is shown")
    defaultMode:Show()
    local previewFrame, previewMode = S.MinimapDifficultyPreviewSource()
    check(previewFrame == difficulty and previewMode == defaultMode and S.MinimapElementPreviewShown("Difficulty") == true,
        "preview must use the active Blizzard difficulty content")
    difficulty.ContentModes = nil
    local trackingSlot, calendarSlot = tracking:GetParent(), calendar:GetParent()
    check(trackingSlot:GetParent() == host and trackingSlot ~= calendarSlot, "tracking/calendar slots")
    check(MM.catcher.level < tracking.level and MM.catcher.level < calendar.level
        and #tracking.Button.hookedScripts.OnEnter == 1 and #calendar.hookedScripts.OnEnter == 1,
        "native tracking and calendar buttons must be above the hover catcher")
    W.Fire(MM.catcher, "OnEnter")
    W.Fire(W.map, "OnLeave")
    W.Fire(tracking.Button, "OnEnter")
    W.Advance(0.2)
    check(MM.hovered, "entering tracking button lost hover reveal")
    W.Fire(tracking.Button, "OnLeave")
    W.Advance(0.2)
    W.Fire(calendar, "OnEnter")
    check(MM.hovered, "calendar button did not drive hover reveal")
    W.Fire(calendar, "OnLeave")
    W.Advance(0.2)
    check(H.Near(tracking.scale, 21 / 17) and H.Near(calendar.scale, 21 / 19), "buttons scaled to the element size")
    local p, rel, rp, x, y = Anchor(trackingSlot)
    check(p == "TOPRIGHT" and rel == host and rp == "TOPLEFT" and x == -5 and y == 0, "row mode 1 starts outside the top-left corner")
    check(select(5, Anchor(calendarSlot)) == -23, "second row button")
    check(mail:GetParent() ~= cluster.IndicatorFrame and not mail.shown, "hidden mail keeps an empty slot")
    check(S.MinimapElementPreviewShown("Mail") == false, "hidden native mail must stay hidden in the preview")
    check(compartment:GetParent() == MM.park, "compartment is off by default")
    -- Blizzard shows mail and asks its parent to lay out (MailFrame:GetParent():Layout()).
    W.Blizzard(function() mail:Show(); mail:GetParent():Layout() end)
    check(select(5, Anchor(mail:GetParent())) ~= -46, "row re-packed synchronously inside Blizzard's call")
    W.Step()
    check(select(5, Anchor(mail:GetParent())) == -46, "mail not placed in the row")
    check(S.MinimapElementPreviewShown("Mail") == true, "visible native mail must appear in the preview")
    W.Blizzard(function() crafting:Show() end)
    W.Step()
    check(select(5, Anchor(crafting:GetParent())) == -69, "crafting not appended")
    W.Blizzard(function() mail:Hide() end)
    W.Step()
    check(select(5, Anchor(crafting:GetParent())) == -46, "row not re-packed after hide")
    assert(S.Set("minimap", "showCrafting", false))
    check(crafting:GetParent() == MM.park and not crafting:IsVisible(), "crafting toggle")
    assert(S.Set("minimap", "elementRow", 6))
    p, rel, rp, x, y = Anchor(trackingSlot)
    check(p == "TOPLEFT" and rp == "BOTTOMLEFT" and x == 0 and y == -5 and select(4, Anchor(calendarSlot)) == 23, "row mode 6")
    assert(S.SetMany("minimap", { buttonTrackingX = 31, buttonTrackingY = 12 }))
    p, rel, rp, x, y = Anchor(trackingSlot)
    check(x == 31 and y == 7 and select(4, Anchor(calendarSlot)) == 23,
        "tracking offset moves only its native slot")
    assert(S.SetMany("minimap", { buttonTrackingX = 0, buttonTrackingY = 0 }))
    -- Corners: difficulty flag top-right, landing button bottom-left.
    local difficultySlot = difficulty:GetParent()
    p, rel, rp, x, y = Anchor(difficultySlot)
    check(difficultySlot:GetParent() == host and p == "TOPRIGHT" and rp == "TOPRIGHT" and x == -2 and y == -2, "difficulty corner")
    local landingSlot = landing:GetParent()
    check(not landingSlot.shown, "expansion button defaults to mouseover")
    assert(S.Set("minimap", "showLanding", 1))
    check(select(1, Anchor(landingSlot)) == "BOTTOMLEFT" and H.Near(landing.scale, 0.8) and landingSlot.shown, "landing corner")
    assert(S.SetMany("minimap", { landingX = 18, landingY = 12, difficultyButtonX = -16, difficultyButtonY = 10 }))
    check(select(4, Anchor(landingSlot)) == 20 and select(5, Anchor(landingSlot)) == 14,
        "Folio preview offsets did not reach the native slot")
    check(select(4, Anchor(difficultySlot)) == -18 and select(5, Anchor(difficultySlot)) == 8,
        "difficulty preview offsets did not reach the native slot")
    assert(S.SetMany("minimap", { landingX = 0, landingY = 0, difficultyButtonX = 0, difficultyButtonY = 0 }))
    assert(S.Set("minimap", "landingIcon", 2))
    check(MM.landingBadge and MM.landingBadge.shown and MM.landingBadge:GetParent() == landing
        and MM.landingBadge.mouse == false, "alternative expansion icon keeps native button interactive")
    local landingClicks = 0
    landing:SetScript("OnClick", function() landingClicks = landingClicks + 1 end)
    landing:Click()
    check(landingClicks == 1, "alternative icon must not replace the native click handler")
    landing.protected = true
    W.SetCombat(true)
    W.Event("ADDON_LOADED", "Blizzard_ExpansionLandingPage")
    W.Step()
    W.SetCombat(false)
    W.Step()
    check(MM.landingBadge.shown, "protected expansion icon must defer safely in combat")
    landing.protected = nil
    assert(S.Set("minimap", "landingIcon", 1))
    check(not MM.landingBadge.shown, "Blizzard expansion artwork restores")
    assert(S.Set("minimap", "infoDifficulty", true))
    check(difficulty:GetParent() == MM.park, "difficulty text must suppress Blizzard's flag")
    -- Blizzard re-anchors or reparents the landing button after loading screens.
    W.Blizzard(function() landing:SetPoint("TOPLEFT", -3, -150) end)
    W.Blizzard(function() landing:SetParent(G.MinimapBackdrop) end)
    check(landing:GetParent() == G.MinimapBackdrop, "re-assert ran inside Blizzard's call")
    W.Step()
    check(landing:GetParent() == landingSlot and landing:GetNumPoints() == 1 and Anchor(landing) == "BOTTOMLEFT", "landing not re-asserted")
    W.Blizzard(function() tracking:SetPoint("RIGHT", cluster.BorderTop, "LEFT", -2, 0) end)
    W.Event("PLAYER_ENTERING_WORLD")
    W.Step()
    check(tracking:GetNumPoints() == 1 and select(2, Anchor(tracking)) == trackingSlot, "tracking not re-asserted")
    -- A button that turns protected cannot move in combat; it is re-placed after combat.
    tracking.protected = true
    W.SetCombat(true)
    W.Blizzard(function() tracking:SetPoint("CENTER", W.UIParent, "CENTER", 0, 0) end)
    W.Step()
    check(select(2, Anchor(tracking)) == W.UIParent, "protected button moved in combat")
    W.SetCombat(false)
    W.Step()
    check(tracking:GetNumPoints() == 1 and select(2, Anchor(tracking)) == trackingSlot, "protected button not re-placed after combat")
    tracking.protected = nil
    assert(S.Set("minimap", "showLanding", 2))
    check(not landingSlot.shown and MM.catcher.shown, "landing mouseover waits for hover")
    W.Fire(MM.catcher, "OnEnter")
    check(landingSlot.shown and landing.shown, "hover did not reveal landing")
    W.Fire(MM.catcher, "OnLeave"); W.Advance(0.2)
    check(not landingSlot.shown, "landing stayed after leave")
    assert(S.Set("minimap", "showLanding", 3))
    check(landing:GetParent() == MM.park, "landing never")
    assert(S.Set("minimap", "landingIcon", 2))
    check(not MM.landingBadge.shown, "hidden expansion button has no badge")
    assert(S.Set("minimap", "showCompartment", true))
    W.Blizzard(function() compartment:Show() end)
    W.Step()
    check(compartment:GetParent():GetParent() == host and select(4, Anchor(compartment:GetParent())) == 46, "compartment row slot")
    check(MM.catcher.points[1][4] == 0 and MM.catcher.points[2][5] == -26, "catcher must cover the row below the map")
    print("Minimap element row (Retail names), packing, corners, re-assert hooks and toggles passed")
end

-- Addon button drawer: collection rules, owner visibility, single button, rescans, restore.
do
    local lib, created = { names = {}, refreshed = {} }, nil
    function lib:GetButtonList() return self.names end
    function lib:Refresh(name) self.refreshed[#self.refreshed + 1] = name end
    function lib.RegisterCallback(owner, event, callback) lib.owner, lib.event, created = owner, event, callback end
    function lib.UnregisterCallback(owner, event) if owner == lib.owner and event == lib.event then created = nil end end
    local W = H.New(root, "Mainline", { beforeModules = function(W)
        W.G.LibStub = { GetLibrary = function(_, name) if name == "LibDBIcon-1.0" then return lib end end }
    end })
    W.editModeReady = true
    local map = W.map
    local function Icon(name, protected)
        local button = W.Button(name, map, 31, 31)
        button.strata, button.fixedStrata, button.level, button.fixedLevel = "MEDIUM", true, 8, true
        button.points = {}
        button:SetPoint("CENTER", map, "CENTER", 80, 10)
        button.protected = protected
        return button
    end
    local alpha, beta, own = Icon("LibDBIcon10_Alpha"), Icon("LibDBIcon10_Beta"), Icon("MyAddonMinimapButton")
    local pin, arrow, quest, secure = Icon("HandyNotesPin12"), Icon("TomTomArrow"), Icon("QuestieNote"), Icon("SecureAddonButton", true)
    local unnamed, plain, note = Icon(nil), Icon("SomeAddonFrame"), Icon("MapNote7")
    plain.kind = "Frame"
    lib.names = { "Alpha", "Beta" }
    H.Enable(W, { captured = true })
    W.Step()
    local S, MM = W.S, W.MM
    local panel = MM.panel
    for _, excluded in ipairs({ pin, arrow, quest, secure, unnamed, plain, note }) do
        check(excluded == nil or excluded:GetParent() == map, "excluded button was collected: " .. tostring(excluded and excluded.name))
    end
    check(alpha:GetParent() == panel and beta:GetParent() == panel and own:GetParent() == panel, "addon buttons not collected")
    check(alpha.strata == "DIALOG" and alpha.fixedStrata and alpha.fixedLevel and H.Near(alpha.scale, 24 / 31), "drawer button layering")
    check(panel.width == 96 and panel.height == 40 and not panel.shown, "drawer grid size")
    local _, relative, relativePoint, x, y = Anchor(alpha)
    check(relative == panel and relativePoint == "TOPLEFT" and H.Near(x * alpha.scale, 20) and H.Near(y * alpha.scale, -20), "grid cell")
    check(H.Near(select(4, Anchor(own)) * own.scale, 76), "sorted by label")
    local toggle
    for _, frame in ipairs(MM.host.children) do if frame.kind == "Button" and frame.dots then toggle = frame end end
    check(toggle and toggle.shown and select(1, Anchor(toggle)) == "BOTTOMRIGHT" and select(4, Anchor(toggle)) == -5
        and toggle.strata == "MEDIUM" and toggle.clicks[1] == "LeftButtonUp", "toggle placement and click layer")
    assert(S.SetMany("minimap", { drawerX = 20, drawerY = 11 }))
    check(select(4, Anchor(toggle)) == 15 and select(5, Anchor(toggle)) == 11,
        "drawer preview offsets need to reach the native toggle")
    assert(S.SetMany("minimap", { drawerX = 0, drawerY = 0 }))
    toggle:Click()
    check(panel.shown and W.M.context.frame.events.GLOBAL_MOUSE_DOWN, "panel/click-away")
    local iconClicks = 0
    alpha:SetScript("OnClick", function() iconClicks = iconClicks + 1 end)
    alpha.mouseOver = true
    W.Event("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(panel.shown, "clicking a collected button must not close the drawer before OnClick")
    alpha:Click()
    check(iconClicks == 1 and panel.shown, "collected addon button lost its click")
    alpha.mouseOver = false
    W.Event("GLOBAL_MOUSE_DOWN", "LeftButton")
    check(not panel.shown and not W.M.context.frame.events.GLOBAL_MOUSE_DOWN, "click-away did not close")
    beta:Hide()
    W.Step()
    check(panel.width == 68 and beta:GetParent() == panel, "owner hide not tracked")
    own:Hide()
    W.Step()
    check(not toggle.shown and alpha:GetParent() ~= panel and alpha:GetParent():GetParent() == MM.host, "single-button rule")
    check(H.Near(alpha.scale, 21 / 31), "single button uses the element size")
    beta:Show()
    W.Step()
    check(toggle.shown and alpha:GetParent() == panel, "toggle not restored")
    -- Late icons: ADDON_LOADED is debounced and always followed by a relayout.
    local gamma = Icon("LibDBIcon10_Gamma")
    W.Event("ADDON_LOADED", "Gamma"); W.Event("ADDON_LOADED", "Gamma")
    check(W.Pending(0.1) == 1 and gamma:GetParent() == map, "rescan not debounced")
    W.Advance(0.1)
    check(gamma:GetParent() == panel and panel.width == 96, "late icon not laid out")
    local delta = Icon("LibDBIcon10_Delta")
    check(created ~= nil, "LibDBIcon callback not registered")
    created("LibDBIcon_IconCreated", delta, "Delta")
    W.Advance(0.1)
    check(delta:GetParent() == panel, "icon-created callback")
    -- LibDBIcon repositions its icons around the map; the drawer keeps them.
    alpha:SetPoint("CENTER", map, "CENTER", 12, 12)
    W.Step()
    check(alpha:GetNumPoints() == 1 and select(2, Anchor(alpha)) == panel, "drawer button not re-asserted")
    assert(S.Set("minimap", "drawerMouseover", true))
    check(not toggle.shown, "mouseover toggle")
    W.Fire(MM.catcher, "OnEnter")
    check(toggle.shown, "hover did not reveal the toggle")
    W.SetCombat(true)
    check(not S.MinimapRescanButtons(), "rescan in combat")
    W.SetCombat(false)
    check(S.MinimapRescanButtons(), "rescan")
    assert(S.Set("minimap", "collectButtons", false))
    for _, button in ipairs({ alpha, beta, own, gamma, delta }) do
        local point, rel, relPoint, bx, by = Anchor(button)
        check(button:GetParent() == map and button.strata == "MEDIUM" and button.level == 8 and button.fixedStrata and button.scale == 1, "button not restored")
        check(point == "CENTER" and rel == map and relPoint == "CENTER" and bx == 80 and by == 10, "button points not restored")
    end
    check(#lib.refreshed == 2 and created == nil and not toggle.shown, "icons not refreshed or callback leaked")
    print("Minimap drawer collection/exclusion, owner visibility, single button, debounced rescans and restore passed")
end

-- MBB collects and locks addon buttons itself. Its presence must not disable
-- the map, and loading it after the Suite must release our drawer ownership.
do
    local mbbLoaded = true
    local W = H.New(root, "Mists", { beforeModules = function(W)
        W.G.C_AddOns.IsAddOnLoaded = function(name) return name == "MinimapButtonButton" and mbbLoaded end
    end })
    local icon = W.Button("LibDBIcon10_MBBStartup", W.map, 31, 31)
    H.Enable(W, { captured = true })
    W.Step()
    check(W.S.Availability("minimap") and W.M.active and W.M.mapOwned, "MBB blocked the Suite minimap")
    check(icon:GetParent() == W.map and W.MM.panel == nil and not W.S.MinimapRescanButtons(),
        "Suite drawer claimed MBB's buttons at startup")

    mbbLoaded = false
    local late = H.New(root, "Mists", { beforeModules = function(W)
        W.G.C_AddOns.IsAddOnLoaded = function(name) return name == "MinimapButtonButton" and mbbLoaded end
    end })
    local button = late.Button("LibDBIcon10_MBBLate", late.map, 31, 31)
    H.Enable(late, { captured = true })
    late.Step()
    check(button:GetParent() ~= late.map, "Suite did not collect the button before MBB loaded")
    mbbLoaded = true
    late.Event("ADDON_LOADED", "MinimapButtonButton")
    late.Step()
    check(late.S.Availability("minimap") and late.M.active and late.M.mapOwned,
        "late MBB load disabled the Suite minimap")
    check(button:GetParent() == late.map and not late.S.MinimapRescanButtons(),
        "Suite did not yield addon buttons to late MBB")
    print("MinimapButtonButton startup and late-load button ownership passed")
end

-- Reclaim: another SetParent is undone one frame later, after combat when locked.
do
    local W = H.New(root, "Mainline")
    W.editModeReady = true
    H.Enable(W, { captured = true })
    W.Step()
    local MM, map = W.MM, W.map
    W.Blizzard(function() map:SetParent(W.UIParent) end)
    check(map:GetParent() == W.UIParent and not W.M.mapOwned, "reclaim ran inside Blizzard's SetParent")
    W.Step()
    check(map:GetParent() == MM.clip and W.M.mapOwned, "minimap not reclaimed")
    W.SetCombat(true)
    W.Blizzard(function() map:SetParent(W.container) end)
    W.Step()
    check(map:GetParent() == W.container, "protected minimap reclaimed in combat")
    check(W.S.Status("minimap") == "Waiting for combat to end", "reclaim not queued")
    W.SetCombat(false)
    W.Step()
    check(map:GetParent() == MM.clip and W.M.mapOwned, "reclaim after combat")
    print("Minimap SetParent reclaim: deferred one frame, queued in combat passed")
end

-- Full restore on disable (Retail), Edit Mode mover and host suppression.
do
    local W = H.New(root, "Mainline")
    W.editModeReady = true
    local G, map, cluster = W.G, W.map, W.cluster
    local tracking, mail = cluster.Tracking, cluster.IndicatorFrame.MailFrame
    local trackingPoint = { Anchor(tracking) }
    H.Enable(W, { captured = true, visibility = 2, scrollZoom = false, shape = 3 })
    W.Step()
    local S, MM = W.S, W.MM
    local mover = W.movers["MSUFSuite.minimap/map"]
    local state = mover.captureState()
    check(state.values.x == -20 and state.values.point == 3, "mover state")
    check(state.values.size == W.config.size and #mover.extraControls == 1
        and mover.extraControls[1].get() == W.config.size,
        "minimap popup did not expose size with Edit Mode history")
    check(mover.extraControls[1].set(230) and W.config.size == 230
        and mover.restoreState(state) and W.config.size == state.values.size,
        "minimap popup size did not apply and restore")
    check(mover.movePosition({ state = state, deltaX = 10, deltaY = -5, phase = "preview" }), "mover preview")
    check(select(4, Anchor(MM.host)) == -10 and select(5, Anchor(MM.host)) == -25, "preview did not move the host")
    check(mover.movePosition({ state = state, deltaX = 10, deltaY = -5, phase = "commit" }) and W.config.x == -10 and W.config.y == -25, "commit")
    check(mover.resetPosition() and W.config.x == -20 and W.config.point == 3, "reset")
    assert(S.Set("minimap", "enabled", false))
    check(map:GetParent() == W.container and Anchor(map) == "CENTER" and select(2, Anchor(map)) == W.container, "map parent/points")
    check(map.width == 198 and map.scale == 1 and not map.fixedStrata and not map.fixedLevel and map.hitInsets[3] == 0, "map geometry/locks")
    check(map.mask == ROUND and map.arch == 1 and map.task == 1 and map.wheel, "map mask/blobs/wheel")
    check(cluster.alpha == 1 and cluster.mouse and cluster.IndicatorFrame.shown, "cluster restore")
    check(G.MinimapCompassTexture.alpha == 1 and G.TimeManagerClockButton.alpha == 1 and G.TimeManagerClockButton.mouse, "decoration restore")
    check(cluster.ZoneTextButton.alpha == 1 and cluster.ZoneTextButton.mouse, "zone text restore")
    local point, relative, relativePoint, x, y = Anchor(tracking)
    check(tracking:GetParent() == cluster and tracking.scale == 1 and point == trackingPoint[1] and relative == trackingPoint[2]
        and relativePoint == trackingPoint[3] and x == trackingPoint[4] and y == trackingPoint[5], "tracking restore")
    check(mail:GetParent() == cluster.IndicatorFrame and G.AddonCompartmentFrame:GetParent() == cluster, "indicator/compartment restore")
    check(G.ExpansionLandingPageMinimapButton:GetParent() == G.MinimapBackdrop and G.GameTimeFrame:GetParent() == cluster, "landing/calendar restore")
    check(MM.host.stateDriver == nil and not MM.host.shown and G.GetMinimapShape == nil, "host/shape restore")
    check(not next(W.M.context.frame.events) and W.hostRecord.isEnabled() and not W.movers["MSUFSuite.minimap/map"], "events/claims released")
    check(W.S.states.minimap.reloadRequired == nil, "exact restore must not ask for a reload")
    -- A lost original parent can only be repaired by a reload.
    assert(S.Set("minimap", "enabled", true))
    W.Step()
    W.container.IsForbidden = function() return true end
    assert(S.Set("minimap", "enabled", false))
    check(W.S.Status("minimap") == "Reload the UI to restore Blizzard's minimap layout", "reload message")
    print("Minimap full restore on disable, Edit Mode mover, suppression and reload fallback passed")
end

-- Classic family: per-client names, Classic decorations and dropdown differences.
for _, client in ipairs({ "Vanilla", "TBC", "Mists" }) do
    local W = H.New(root, client)
    W.editModeReady = true
    H.Enable(W, { captured = true, collectButtons = true })
    W.Step()
    local G, S, MM, map = W.G, W.S, W.MM, W.map
    check(map:GetParent() == MM.clip and map.width == S.Config("minimap").size and map.mask == SQUARE, client .. " claim")
    check(G.MinimapBorder.alpha == 0 and G.MinimapNorthTag.alpha == 0 and G.MinimapCompassTexture.alpha == 0, client .. " decorations")
    check(G.TimeManagerClockButton.alpha == 0 and not G.TimeManagerClockButton.mouse, client .. " clock button")
    check(G.MinimapZoneTextButton.alpha == 0 and not G.MinimapToggleButton.mouse and G.MinimapBackdrop.shown, client .. " cluster controls")
    local tracking, calendar = G.MiniMapTracking, G.GameTimeFrame
    check(tracking:GetParent():GetParent() == MM.host and calendar:GetParent():GetParent() == MM.host, client .. " tracking/calendar slots")
    check(H.Near(tracking.scale, 21 / 33) and G.MinimapZoomIn:GetParent() == MM.zoomHolder, client .. " scale/zoom holder")
    check(G.MiniMapMailFrame:GetParent() ~= map and G.MiniMapBattlefieldFrame:GetParent() ~= map, client .. " mail/battlefield moved")
    check(not S.MinimapElementAvailable("Crafting") and not S.MinimapElementAvailable("Landing") and not S.MinimapElementAvailable("Compartment"), client .. " availability")
    check(S.MinimapElementAvailable("Difficulty") == (client == "Mists"), client .. " difficulty availability")
    local mouseUp = map:GetScript("OnMouseUp")
    mouseUp(map, "MiddleButton")
    if client == "Vanilla" then
        check(G.MiniMapTrackingButton == nil, "era has no tracking dropdown")
    else
        check(G.MiniMapTrackingButton.menuOpen, client .. " tracking dropdown")
    end
    if client == "Mists" then
        check(G.MiniMapInstanceDifficulty:GetParent() == G.GuildInstanceDifficulty:GetParent(), "mists difficulty frames share a corner")
        check(select(1, Anchor(G.MiniMapInstanceDifficulty:GetParent())) == "TOPRIGHT", "mists difficulty corner")
        check(select(5, Anchor(G.MiniMapWorldMapButton:GetParent())) == -46, "mists world map button in the row")
    end
    W.Blizzard(function() G.MiniMapMailFrame:Show() end)
    W.Step()
    check(G.MiniMapMailFrame:IsVisible(), client .. " mail shown in its slot")
    assert(S.Set("minimap", "enabled", false))
    check(map:GetParent() == W.container and map.width == 140 and tracking:GetParent() == G.MinimapBackdrop, client .. " restore")
    check(G.MiniMapMailFrame:GetParent() == map and G.MinimapZoomIn:GetParent() == G.MinimapBackdrop and G.MinimapZoomIn.shown, client .. " restore buttons")
    check(G.MinimapBorder.alpha == 1 and G.MinimapToggleButton.mouse, client .. " restore decorations")
end
print("Minimap Classic-family adapter (Era, TBC, Mists names) passed")

-- WoW Forever: Mainline names with the Camelot skin deltas.
do
    local W = H.New(root, "Forever")
    W.editModeReady = true
    local defaults = W.config
    check(defaults.enabled and defaults.captured and defaults.point == 3
        and defaults.x == -20 and defaults.y == -20 and defaults.size == 205
        and defaults.stylePreset == 7 and not defaults.infoClock,
        "forever map and footer defaults did not resolve")
    H.Enable(W)
    W.Step()
    local G, S, MM, map = W.G, W.S, W.MM, W.map
    local point, _, _, x, y = MM.host:GetPoint(1)
    check(point == "TOPRIGHT" and x == -20 and y == -20,
        "forever map did not use the authored anchor")
    local landing, coords = G.ExpansionLandingPageMinimapButton, W.container.PlayerCoords
    check(not S.MinimapElementAvailable("Landing") and landing:GetParent() == G.MinimapBackdrop, "forever landing left alone")
    check(not coords.shown and G.MinimapCompassTextureUnderlay.alpha == 0, "forever coordinates/underlay")
    W.Blizzard(function() map:SetMaskTexture("ui-hud-minimap-frame-generic-mask") end)
    W.Event("CVAR_UPDATE", "rotateMinimap", "1")
    check(map.mask ~= SQUARE, "mask re-applied inside the CVar callback")
    W.Step()
    check(map.mask == SQUARE, "forever skin mask not overridden")
    assert(S.Set("minimap", "enabled", false))
    check(map.mask == "ui-hud-minimap-frame-generic-mask" and coords.shown, "forever restore")
print("Minimap WoW Forever deltas (landing, coordinates, skin mask) passed")

-- Original ornamental art uses the same saved values as the options preview;
-- Blizzard's map remains owned by the existing host and animation is native.
do
    local W = H.New(root, "Mainline")
    W.editModeReady = true
    H.Enable(W, { captured = true })
    W.Step()
    local S, MM, c = W.S, W.MM, W.config
    check(MM.style and not MM.style.artOver.shown and not MM.style.glow.shown,
        "clean default unexpectedly paints an ornament")
    assert(W.Suite.MinimapStylePresets[8].borderColor == "41627a"
        and W.Suite.MinimapStylePresets[9].borderColor == "575b58",
        "Minimap Blue and Dark looks are missing")
    assert(S.SetMany("minimap", W.Suite.MinimapStylePresets[5]))
    check(c.stylePreset == 5 and c.shape == 2 and MM.style.artOver.shown
        and MM.style.artOver.texture:find("AstralRing.tga", 1, true), "Astral preset did not paint original art")
    check(MM.style.glow.shown and MM.style.backdrop.shown and MM.style.artOver.blend == "BLEND",
        "preset glow, plate or blend missing")
    check(MM.style.artOver._msufStyleRotation:IsPlaying()
        and MM.style.artOver._msufStyleRotationAnimation.duration == 60, "native art rotation not running")
    assert(S.Set("minimap", "stylePlacement", 2))
    check(MM.style.artUnder.shown and not MM.style.artOver.shown
        and not MM.style.artOver._msufStyleRotation:IsPlaying(), "moving art behind map left overlay animation running")
    assert(S.SetMany("minimap", { styleTexture = 6, styleTexturePath = "123456", styleRotation = 0, styleGlow = false }))
    check(MM.style.artUnder.texture == 123456 and not MM.style.glow.shown
        and not MM.style.artUnder._msufStyleRotation:IsPlaying(), "custom file ID or rotation stop failed")
    assert(S.Set("minimap", "enabled", false))
    check(not MM.style.artUnder.shown and not MM.style.backdrop.shown, "ornament remained after disable")
    print("Minimap presets, layered art, native rotation and release passed")
end
end
