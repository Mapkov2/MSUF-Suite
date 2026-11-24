local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
local VISIBILITY, ZOOM, ROTATE = NS.MinimapVisibility, NS.MinimapZoomButtons, NS.MinimapRotate
local MIDDLE = NS.MinimapMiddleClick
-- Mouse input lives on Blizzard's map itself. A full-size input overlay can
-- intercept map pings and native buttons even when pass-through is requested.
-- Blizzard's zoom buttons move into a mouse-transparent suite holder. A
-- motion-only catcher drives mouseover visibility without taking clicks.
local Finite = S.Finite
local weak = { __mode = "k" }
local holder, catcher
local zoomOutOverlay, zoomOutGlyph, zoomOutTarget
local inputMap, inputScripts
local hoverHooked = setmetatable({}, weak)
local leaveJob
local zoomShown, zoomHooked = setmetatable({}, weak), setmetatable({}, weak)
local extents = {}
local HOVER_GRACE = 0.15

local Native = NS.MinimapElements
local ZoomButtons = Native.ZoomButtons
MM.ZoomButtons = ZoomButtons

local function SyncButtons(zoom, levels)
    local zoomIn, zoomOut = ZoomButtons()
    if zoomIn then zoomIn:SetEnabled(zoom < levels - 1) end
    if zoomOut then zoomOut:SetEnabled(zoom > 0) end
end
local function ResetZoom()
    local map = _G.Minimap
    if not M.active or not MM.Usable(map) then return end
    local zoom, levels = map:GetZoom(), map:GetZoomLevels()
    if Finite(zoom) and zoom > 0 then
        map:SetZoom(0)
        if Finite(levels) then SyncButtons(0, levels) end
    end
end
-- Every manual zoom re-arms the one-shot reset; zoom level 0 needs none.
local function ArmReset()
    local map = _G.Minimap
    local seconds = M.active and M.config.zoomResetSeconds or 0
    local zoom = seconds > 0 and MM.Usable(map) and map:GetZoom()
    -- ctx:After moves a pending deadline; at zoom level 0 nothing waits.
    if Finite(zoom) and zoom > 0 then M.context:After(seconds, ResetZoom) else M.context:Cancel(ResetZoom) end
end
local function Zoom(step)
    local map = _G.Minimap
    if not MM.Usable(map) then return end
    local zoom, levels = map:GetZoom(), map:GetZoomLevels()
    if not Finite(zoom) or not Finite(levels) or levels < 1 then return end
    local target = math.max(0, math.min(levels - 1, zoom + step))
    if target == zoom then return end
    map:SetZoom(target)
    SyncButtons(target, levels)
    ArmReset()
end
local function Wheel(_, delta)
    if M.active and M.config.scrollZoom and Finite(delta) and delta ~= 0 then Zoom(delta > 0 and 1 or -1) end
end

-- Blizzard's own tracking DropdownButton.
local function TrackingButton()
    local cluster = _G.MinimapCluster
    local tracking = MM.Usable(cluster) and cluster.Tracking
    local button = MM.Usable(tracking) and tracking.Button
    if MM.Usable(button) then return button end
end

-- The middle click always runs its action (Nothing included); the right
-- click only while it has one, otherwise Blizzard keeps its ping.
local function ClickAction(button)
    if button == "MiddleButton" then return M.config.middleClick end
    if button == "RightButton" then
        local action = M.config.rightClick
        if action and action ~= MIDDLE.NOTHING then return action end
    end
end
MM.ClickAction = ClickAction

local function MouseUp(_, button)
    if not M.active or NS.IsCombatLocked() then return end
    local action = ClickAction(button)
    if not action then return end
    if action == MIDDLE.TRACKING then
        -- Blizzard's tracking menu opens on the press of its own
        -- DropdownButton (OnMouseDown_Intrinsic), which no secure click
        -- reaches; opened from here under WoW Forever's Gamepad UI it would
        -- run MenuProxy.OnShow's focus code in the Suite's call
        -- (S.GamepadUI). There the tracking button itself and the gamepad
        -- radial's Tracking segment open it.
        local tracking = not S.GamepadUI() and TrackingButton()
        if not tracking then return end
        if tracking:IsMenuOpen() then
            tracking:CloseMenu()
        else
            tracking:OpenMenu()
        end
    elseif action == MIDDLE.CALENDAR then
        if S.GamepadUI() then MM.OpenWindowFlyout("calendar", S.Text("Calendar")) else ToggleCalendar() end
    elseif action == MIDDLE.WORLD_MAP then
        -- No secure click reaches the map's own mouse handler: the world map
        -- opens through Blizzard's panel manager (MicroMenu.lua), under the
        -- Gamepad UI through a one-row secure flyout (MicroMenu.lua here).
        if S.GamepadUI() then MM.OpenWindowFlyout("worldMap", S.Text("World map")) else S.TogglePanel("worldMap") end
    elseif action == MIDDLE.MICRO_MENU then
        -- A secure flyout clicks Blizzard's own micro buttons (MicroMenu.lua).
        MM.OpenMicroMenu()
    end
end

-- Under WoW Forever's Gamepad UI the map keeps Blizzard's own OnMouseUp and
-- OnMouseWheel. There SmartNavigation scans the panels the frame controls
-- manager focuses (FrameControlsManager.lua FrameShown returns at once
-- outside the Gamepad UI; Blizzard_GamepadSmartNavigation/Utility.lua
-- SmartNavigation_CanFocusFrame reads GetScript("OnMouseUp") and
-- ("OnMouseDown") of every non-Button it finds): a Suite function there would
-- be a Suite-tainted value in that secure scan. The middle-click then arrives
-- as GLOBAL_MOUSE_UP while the map itself holds the pointer (Blizzard pings
-- on it as well), and the wheel zooms through Blizzard's zoom buttons with
-- their sound; their clicks arm the reset (ZoomClicked). The mode follows
-- INPUT_DEVICE_INTERFACE_TRANSITION (Blizzard_SharedXML/InputUtil.lua, the
-- event Forever's own interface switch listens to).
local padInput, modeWatch
local function MapMouseUp(_, _, button)
    local map = inputMap
    if not M.active or not ClickAction(button) or not padInput or not MM.Usable(map) then return end
    local over = map:IsMouseMotionFocus()
    if S.Public(over) and over == true then MouseUp(map, button) end
end

-- Puts back Blizzard's own handlers where the Suite's wrappers still sit.
local function UnwrapMap()
    local map, scripts = inputMap, inputScripts
    if map and scripts and MM.Usable(map) then
        if map:GetScript("OnMouseUp") == scripts.mouseUp then
            map:SetScript("OnMouseUp", scripts.originalMouseUp)
        end
        if map:GetScript("OnMouseWheel") == scripts.mouseWheel then
            map:SetScript("OnMouseWheel", scripts.originalMouseWheel)
        end
    end
    inputScripts = nil
end

local function StopPadInput()
    if not padInput then return end
    padInput = nil
    if M.context then MM.Unlisten("GLOBAL_MOUSE_UP", "middleClick") end
end

local function RestoreMapInput()
    UnwrapMap()
    StopPadInput()
    if modeWatch and M.context then MM.Unlisten("INPUT_DEVICE_INTERFACE_TRANSITION", "mapInput") end
    modeWatch, inputMap = nil, nil
end

-- Elsewhere the map's own OnMouseUp and OnMouseWheel are wrapped, not hooked: Blizzard
-- pings on every mouse button (middle-click is the suite's action) and zooms
-- through its zoom buttons with a sound; a post-hook could not suppress either.
-- Other buttons still reach Blizzard's handler, and disable restores both.
local function WrapMap(map)
    if inputMap == map and inputScripts
        and map:GetScript("OnMouseUp") == inputScripts.mouseUp
        and map:GetScript("OnMouseWheel") == inputScripts.mouseWheel then
        return
    end
    UnwrapMap()
    local originalMouseUp = map:GetScript("OnMouseUp")
    local originalMouseWheel = map:GetScript("OnMouseWheel")
    local mouseUp = function(self, button, ...)
        if M.active and ClickAction(button) then return MouseUp(self, button) end
        if originalMouseUp then return originalMouseUp(self, button, ...) end
    end
    map:SetScript("OnMouseUp", mouseUp)
    map:SetScript("OnMouseWheel", Wheel)
    inputScripts = {
        originalMouseUp = originalMouseUp,
        originalMouseWheel = originalMouseWheel,
        mouseUp = mouseUp,
        mouseWheel = Wheel,
    }
end

local InstallMapInput
-- The protected map takes no script change in combat: the switch waits.
local function InputModeChanged()
    if not M.active or not inputMap then return end
    if NS.IsCombatLocked() then
        MM.Force("input")
        S.Queue("minimap")
        return
    end
    InstallMapInput(inputMap)
end

function InstallMapInput(map)
    if not MM.Usable(map) then return end
    if NS.Client.isForever and not modeWatch then
        modeWatch = true
        MM.Listen("INPUT_DEVICE_INTERFACE_TRANSITION", "mapInput", InputModeChanged)
    end
    if inputMap ~= map then UnwrapMap() end
    inputMap = map
    if S.GamepadUI() then
        UnwrapMap()
        if not padInput then
            padInput = true
            MM.Listen("GLOBAL_MOUSE_UP", "middleClick", MapMouseUp)
        end
    else
        StopPadInput()
        WrapMap(map)
    end
    MM.HookHover(map)
end

local function SetHovered(value)
    if MM.hovered == value then return end
    MM.hovered = value
    MM.NotifyHover()
end
local function Inside()
    local over = catcher and catcher:IsVisible() and catcher:IsMouseOver()
    if S.Public(over) and over then return true end
    local panel = MM.panel
    over = panel and panel:IsVisible() and panel:IsMouseOver()
    return S.Public(over) and over == true
end
local function LeaveCheck()
    if M.active and not Inside() then SetHovered(false) end
end
function MM.HoverEnter()
    if leaveJob then leaveJob:Cancel() end
    if M.active and catcher and catcher:IsShown() then SetHovered(true) end
end

-- A short grace bridges the gap between the map and its rows or drawer: the
-- first leave starts it (a ctx:Coalesce job), later leaves ride along.
function MM.HoverLeave()
    if not MM.hovered then return end
    leaveJob = leaveJob or M.context:Coalesce(HOVER_GRACE, LeaveCheck)
    leaveJob:Request()
end

-- Native buttons stay above the passive hover area. Observe their own motion
-- so moving from the map into a Blizzard button keeps mouseover controls open.
function MM.HookHover(frame)
    if not MM.Usable(frame) or hoverHooked[frame] then return end
    hoverHooked[frame] = true
    frame:HookScript("OnEnter", MM.HoverEnter)
    frame:HookScript("OnLeave", MM.HoverLeave)
end

local function LayerCatcher()
    if not catcher or not MM.host then return end
    -- Only a hidden mouseover minimap needs the catcher above the map to wake
    -- it. Once visible, the catcher is below Blizzard's map and every button.
    local waking = M.config.visibility == VISIBILITY.MOUSEOVER and not MM.host:IsShown()
    catcher:SetFrameLevel(MM.mapLevel + (waking and 30 or -1))
end
MM.UpdateCatcherLayer = LayerCatcher

local function EnsureInput()
    if holder then return end
    local host = MM.host
    holder = S.CreateFrame("Frame", nil, host)
    holder:SetAllPoints(host)
    holder:SetFrameLevel(MM.mapLevel + 12)
    holder:EnableMouse(false)
    holder:SetScript("OnShow", function()
        -- Blizzard may have hidden its buttons while the holder was hidden.
        if not M.active or M.config.zoomButtons == ZOOM.HIDE then return end
        local zoomIn, zoomOut = ZoomButtons()
        if zoomIn and MM.owned[zoomIn] and not zoomIn:IsShown() then zoomIn:Show() end
        if zoomOut and MM.owned[zoomOut] and not zoomOut:IsShown() then zoomOut:Show() end
    end)
    catcher = S.CreateFrame("Frame", nil, host)
    catcher:SetMouseClickEnabled(false)
    catcher:SetMouseMotionEnabled(true)
    catcher:SetPropagateMouseMotion(true)
    catcher:SetScript("OnEnter", MM.HoverEnter)
    catcher:SetScript("OnLeave", MM.HoverLeave)
    catcher:Hide()
    MM.zoomHolder, MM.catcher = holder, catcher
end

local function ZoomClicked(button)
    if M.active and MM.owned[button] then ArmReset() end
end
-- Retail's map hides its zoom buttons when the cursor leaves the round map;
-- inside the suite holder they stay shown and the holder decides.
local function ZoomHidden(button)
    if M.active and MM.owned[button] and M.config.zoomButtons ~= ZOOM.HIDE and not button:IsShown() then button:Show() end
end

local function PaintZoomOut(button)
    if button ~= zoomOutTarget then return end
    local scale, enabled = button:GetScale(), button:IsEnabled()
    NS.MinimapStyle.PaintZoomOutGlyph(zoomOutGlyph, Finite(scale) and scale > 0 and scale or 1, S.Public(enabled) and enabled == true)
end

local function PlaceZoomOutGlyph(button)
    if not button then
        if zoomOutOverlay then zoomOutOverlay:Hide() end
        zoomOutTarget = nil
        return
    end
    if not zoomOutOverlay then
        zoomOutOverlay = S.CreateFrame("Frame", nil, holder)
        zoomOutOverlay:EnableMouse(false)
        zoomOutGlyph = NS.MinimapStyle.CreateZoomOutGlyph(zoomOutOverlay)
    end
    if zoomOutTarget ~= button then
        zoomOutTarget = button
        zoomOutOverlay:ClearAllPoints()
        zoomOutOverlay:SetAllPoints(button)
    end
    zoomOutOverlay:SetFrameLevel(button:GetFrameLevel() + 1)
    PaintZoomOut(button)
    zoomOutOverlay:Show()
end

local function Adopt(button, mode, zoomOut)
    if not button then return end
    if not zoomHooked[button] then
        zoomHooked[button] = true
        button:HookScript("OnClick", ZoomClicked)
        button:HookScript("OnHide", ZoomHidden)
        if zoomOut then
            button:HookScript("OnEnable", PaintZoomOut)
            button:HookScript("OnDisable", PaintZoomOut)
        end
    end
    if zoomShown[button] == nil then zoomShown[button] = button:IsShown() == true end
    -- Parked buttons sit in a hidden frame, so Blizzard's hover show never renders them.
    if mode == ZOOM.HIDE then MM.Place(button, MM.park, "CENTER", MM.park, "CENTER", 0, 0) end
end
local function PlaceZoom(mode)
    local zoomIn, zoomOut = ZoomButtons()
    local host = MM.host
    Adopt(zoomIn, mode)
    Adopt(zoomOut, mode, true)
    if mode == ZOOM.HIDE or not zoomIn or not zoomOut then
        PlaceZoomOutGlyph(nil)
        MM.SetExtent("zoom", 0, 0, 0, 0)
        return
    end
    local c, level = M.config, MM.mapLevel + 13
    local ix, iy, ox, oy, iw, ih, ow, oh = Native.ZoomOffsets(c, zoomIn, zoomOut)
    ix, iy = Native.ZoomPosition(c, true, ix, iy)
    ox, oy = Native.ZoomPosition(c, false, ox, oy)
    local placed = MM.Place(zoomOut, holder, "BOTTOMRIGHT", host, "BOTTOMRIGHT", ox, oy, nil, nil, level)
    PlaceZoomOutGlyph(placed and zoomOut or nil)
    MM.Place(zoomIn, holder, "BOTTOMRIGHT", host, "BOTTOMRIGHT", ix, iy, nil, nil, level)
    local width, height = MM.width or 0, MM.height or 0
    MM.SetExtent("zoom", math.max(0, iw - width - ix, ow - width - ox), math.max(0, ix, ox),
        math.max(0, iy + ih - height, oy + oh - height), math.max(0, -iy, -oy))
    if not zoomIn:IsShown() then zoomIn:Show() end
    if not zoomOut:IsShown() then zoomOut:Show() end
end

------------------------------------------------------------------ visibility conditions
-- Host.lua applies the map's visibility; these decide its conditions. Pet
-- battles and vehicles are macro conditions: they join the state driver ahead
-- of the mode, and a hidden mouseover map asks them before it wakes.
-- Instances are not a macro condition: zone changes re-apply them, which
-- happens outside combat; a change during lockdown waits for its end. The
-- key binding hides the map for this session. MSUF Edit Mode ignores all of it.
local INSTANCE_HIDE = NS.MinimapInstanceHide
function MM.VisibilityConditions(c)
    if S.editMode then return "" end
    -- The vehicle clauses match the bag bar's and data bars' "In vehicle" rule.
    return (c.hidePetBattle and "[petbattle] hide; " or "")
        .. (c.hideVehicle and "[@player,unithasvehicleui] hide; [vehicleui] hide; " or "")
end
local function InstanceHidden(c)
    local mode = c.hideInstances
    if not mode or mode == INSTANCE_HIDE.NEVER then return false end
    local inside, kind = IsInInstance()
    if not S.Public(inside) or inside ~= true or not S.Public(kind) then return false end
    if kind == "raid" then return mode ~= INSTANCE_HIDE.DUNGEONS end
    return kind == "party" and mode ~= INSTANCE_HIDE.RAIDS
end
function MM.HiddenByCondition()
    return M.userHidden == true or InstanceHidden(M.config)
end
-- The conditions hide the map right now (mouseover reads them when it wakes).
function MM.ConditionsHide(prefix)
    return prefix ~= "" and SecureCmdOptionParse(prefix .. "show") == "hide"
end
local function Reapply()
    if not M.active then return end
    if NS.IsCombatLocked() then S.Queue("minimap") else MM.ApplyVisibility() end
end
local CONDITION_EVENTS = { "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }
local ZONE_EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }
-- Only a configured condition listens; the signature avoids re-registering.
function MM.SyncVisibilityEvents(c, mode)
    local conditions = mode == VISIBILITY.MOUSEOVER and MM.VisibilityConditions(c) ~= ""
    local zones = c.hideInstances ~= nil and c.hideInstances ~= INSTANCE_HIDE.NEVER
    local signature = (conditions and 1 or 0) + (zones and 2 or 0)
    if M.visibilityEvents == signature then return end
    M.visibilityEvents = signature
    for i = 1, #CONDITION_EVENTS do
        if conditions then MM.Listen(CONDITION_EVENTS[i], "visibility", Reapply)
        else MM.Unlisten(CONDITION_EVENTS[i], "visibility") end
    end
    for i = 1, #ZONE_EVENTS do
        if zones then MM.Listen(ZONE_EVENTS[i], "visibilityZone", Reapply)
        else MM.Unlisten(ZONE_EVENTS[i], "visibilityZone") end
    end
end
-- The key binding; the protected map waits for combat to end.
function MM.ToggleShown()
    if not M.active or NS.InCombat() then return false end
    M.userHidden = not M.userHidden or nil
    MM.ApplyVisibility()
    return true
end

local function NeedsHover(c)
    return c.visibility == VISIBILITY.MOUSEOVER or c.zoomButtons == ZOOM.MOUSEOVER
        or (c.showTracking and c.trackingMouseover and not S.GamepadUI())
        or (c.hoverResize and c.visibility ~= VISIBILITY.NEVER)
        or (MM.CollectsButtons() and c.drawerMouseover)
        or MM.TextsNeedHover(c)
        or (c.showLanding == NS.MinimapLanding.MOUSEOVER and S.MinimapElementAvailable("Landing"))
end
-- In mouseover visibility the host is hidden, so the catcher cannot be its child.
local function ApplyCatcher()
    local c, host = M.config, MM.host
    local parent = c.visibility == VISIBILITY.MOUSEOVER and UIParent or host
    if catcher:GetParent() ~= parent then catcher:SetParent(parent) end
    catcher:SetFrameStrata(host:GetFrameStrata())
    LayerCatcher()
    local wanted = NeedsHover(c) and true or false
    catcher:SetShown(wanted)
    if not wanted then
        if leaveJob then leaveJob:Cancel() end
        SetHovered(false)
    end
    MM.Queue("hover")
end
MM.ApplyCatcher = ApplyCatcher

-- Rows outside the map report how far they reach so the catcher covers them.
function MM.SetExtent(key, left, right, top, bottom)
    local extent = extents[key]
    if not extent then
        extent = {}
        extents[key] = extent
    end
    extent[1], extent[2], extent[3], extent[4] = left or 0, right or 0, top or 0, bottom or 0
    MM.Queue("hover")
end

MM.flushers.hover = function()
    if not catcher then return end
    local left, right, top, bottom = 0, 0, 0, 0
    for _, extent in pairs(extents) do
        left, right = math.max(left, extent[1]), math.max(right, extent[2])
        top, bottom = math.max(top, extent[3]), math.max(bottom, extent[4])
    end
    catcher:ClearAllPoints()
    catcher:SetPoint("TOPLEFT", MM.host, "TOPLEFT", -left, top)
    catcher:SetPoint("BOTTOMRIGHT", MM.host, "BOTTOMRIGHT", right, -bottom)
end

MM.OnHover(function(shown)
    LayerCatcher()
    if holder and M.active and M.config.zoomButtons == ZOOM.MOUSEOVER then holder:SetShown(shown) end
end)

function S.MinimapZoomPreviewShown()
    if not M.active or not holder then return end
    local zoomIn, zoomOut = ZoomButtons()
    return zoomIn ~= nil and zoomOut ~= nil and M.config.zoomButtons ~= ZOOM.HIDE and holder:IsVisible()
end

-- Edit Mode writes its own rotation when it applies a layout (at login); an
-- explicit suite choice goes back on after Blizzard's handler has run.
MM.flushers.rotate = function()
    local rotate = M.config.rotate
    if rotate == ROTATE.BLIZZARD then return end
    if NS.IsCombatLocked() then
        MM.Force("input")
        S.Queue("minimap")
        return
    end
    M.context:CVar("rotateMinimap", rotate == ROTATE.ROTATE and "1" or "0")
end
local function LayoutApplied() MM.Queue("rotate") end

------------------------------------------------------------------ north marker
-- Blizzard's compass ring fades with the cluster decorations (Host.lua), so a
-- rotating map would no longer show north. A small N rides the map's edge
-- instead. It follows the shared heading watch (S.CompassHeading) only while
-- it is visible: shown while the map rotates, hidden with the host.
local north
local NORTH_INSET = 7
local function Rotating(c)
    if c.rotate == ROTATE.ROTATE then return true end
    if c.rotate ~= ROTATE.BLIZZARD then return false end
    local value = C_CVar.GetCVar("rotateMinimap")
    return S.Public(value) and value == "1"
end
-- Bearings grow clockwise; north sits opposite the player's turn.
local function PlaceNorth(_, bearing)
    if not north or not Finite(bearing) or bearing == north.bearing then return end
    north.bearing = bearing
    local radians = math.rad(bearing)
    local dx, dy = -math.sin(radians), math.cos(radians)
    local halfWidth = math.max(0, (MM.width or 0) / 2 - NORTH_INSET)
    local halfHeight = math.max(0, (MM.height or 0) / 2 - NORTH_INSET)
    local reach
    if M.config.shape == NS.MinimapShape.CIRCLE then
        reach = math.min(halfWidth, halfHeight)
    else
        local ax, ay = math.abs(dx), math.abs(dy)
        reach = math.min(ax > 0 and halfWidth / ax or halfWidth, ay > 0 and halfHeight / ay or halfHeight)
    end
    north:ClearAllPoints()
    north:SetPoint("CENTER", MM.host, "CENTER", dx * reach, dy * reach)
end
local function WatchNorth() S.CompassHeading.Watch(north, PlaceNorth) end
local function StopNorth() S.CompassHeading.Watch(north, nil) end
local function NorthChanged(_, _, name)
    if name == "rotateMinimap" and M.active then MM.ApplyNorth() end
end
function MM.ApplyNorth()
    local c = M.config
    local wanted = M.active and c.showNorth and Rotating(c) or false
    if c.showNorth and c.rotate == ROTATE.BLIZZARD then
        MM.Listen("CVAR_UPDATE", "north", NorthChanged)
    elseif M.context then
        MM.Unlisten("CVAR_UPDATE", "north")
    end
    if not wanted then
        if north then north:Hide() end
        return
    end
    if not north then
        north = S.CreateFrame("Frame", nil, MM.host)
        north:SetSize(16, 16)
        north:EnableMouse(false)
        north.label = S.CreateFontString(north, nil, "OVERLAY", "GameFontNormalSmall")
        north.label:SetAllPoints(north)
        -- The localized letter the Suite compass uses (Core/Compass.lua).
        north.label:SetText((S.Text("N E S W")):match("^(%S+)") or "N")
        north:SetScript("OnShow", WatchNorth)
        north:SetScript("OnHide", StopNorth)
        north:Hide()
    end
    north:SetFrameLevel(MM.mapLevel + 13)
    north.bearing = nil
    north:Show()
    PlaceNorth(nil, S.CompassHeading.Read())
end
local trackingGamepad
local function TrackingInputChanged()
    local pad = S.GamepadUI()
    if pad == trackingGamepad then return end
    trackingGamepad = pad
    MM.Force("input")
    MM.Force("elements")
    S.Apply("minimap")
end

function MM.ApplyInput()
    local c, ctx, map = M.config, M.context, _G.Minimap
    EnsureInput()
    -- The map keeps its own hit target and Blizzard button children stay clickable.
    if MM.Usable(map) then
        InstallMapInput(map)
        ctx:Property(map, "IsMouseWheelEnabled", "EnableMouseWheel", c.scrollZoom)
    end
    if c.zoomResetSeconds <= 0 then ctx:Cancel(ResetZoom) end
    PlaceZoom(c.zoomButtons)
    holder:SetShown(c.zoomButtons == ZOOM.ALWAYS or (c.zoomButtons == ZOOM.MOUSEOVER and MM.Revealed()))
    if c.showTracking and c.trackingMouseover and NS.Client.isForever then
        trackingGamepad = S.GamepadUI()
        MM.Listen("GAME_PAD_ACTIVE_CHANGED", "trackingHover", TrackingInputChanged)
    else
        MM.Unlisten("GAME_PAD_ACTIVE_CHANGED", "trackingHover")
    end
    -- 1 leaves Blizzard's own rotation setting alone (and returns a suite write).
    if c.rotate == ROTATE.BLIZZARD then
        S.RestoreCVar("minimap", "rotateMinimap")
        MM.Unlisten("EDIT_MODE_LAYOUTS_UPDATED", "rotate")
    else
        ctx:CVar("rotateMinimap", c.rotate == ROTATE.ROTATE and "1" or "0")
        MM.Listen("EDIT_MODE_LAYOUTS_UPDATED", "rotate", LayoutApplied)
    end
    ApplyCatcher()
end

function MM.ReleaseInput()
    MM.Unlisten("GAME_PAD_ACTIVE_CHANGED", "trackingHover")
    MM.Unlisten("CVAR_UPDATE", "north")
    if north then north:Hide() end
    M.context:Cancel(ResetZoom)
    if leaveJob then leaveJob:Cancel() end
    MM.hovered = false
    MM.CloseMicroMenu()
    PlaceZoomOutGlyph(nil)
    for button in pairs(zoomShown) do
        if MM.owned[button] then
            MM.Release(button)
            button:SetShown(zoomShown[button])
        end
        zoomShown[button] = nil
    end
    for key in pairs(extents) do extents[key] = nil end
    RestoreMapInput()
    if holder then holder:Hide() end
    if catcher then
        catcher:Hide()
        if catcher:GetParent() ~= MM.host then catcher:SetParent(MM.host) end
    end
end
