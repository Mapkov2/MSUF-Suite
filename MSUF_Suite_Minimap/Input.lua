local _, P = ...
local NS, S = P.NS, P.Suite
local MM = P.Minimap
local M = MM.M
-- Mouse input lives on Blizzard's map itself. A full-size input overlay can
-- intercept map pings and native buttons even when pass-through is requested.
-- Blizzard's zoom buttons move into a mouse-transparent suite holder. A
-- motion-only catcher drives mouseover visibility without taking clicks.
local weak = { __mode = "k" }
local holder, catcher
local inputMap, inputScripts
local hoverHooked = setmetatable({}, weak)
local resetTimer, leaveTimer
local zoomShown, zoomHooked = setmetatable({}, weak), setmetatable({}, weak)
local extents = {}
local HOVER_GRACE = 0.15

local function ZoomButtons()
    local map = _G.Minimap
    local zoomIn = MM.Usable(map) and map.ZoomIn or _G.MinimapZoomIn
    local zoomOut = MM.Usable(map) and map.ZoomOut or _G.MinimapZoomOut
    return MM.Usable(zoomIn) and zoomIn or nil, MM.Usable(zoomOut) and zoomOut or nil
end
MM.ZoomButtons = ZoomButtons

local function SyncButtons(zoom, levels)
    local zoomIn, zoomOut = ZoomButtons()
    if zoomIn and type(zoomIn.SetEnabled) == "function" then zoomIn:SetEnabled(zoom < levels - 1) end
    if zoomOut and type(zoomOut.SetEnabled) == "function" then zoomOut:SetEnabled(zoom > 0) end
end
local function ResetZoom()
    resetTimer = nil
    local map = _G.Minimap
    if not M.active or not MM.Usable(map) then return end
    local zoom, levels = map:GetZoom(), map:GetZoomLevels()
    if MM.Number(zoom) and zoom > 0 then
        map:SetZoom(0)
        if MM.Number(levels) then SyncButtons(0, levels) end
    end
end
-- Every manual zoom re-arms the one-shot reset; zoom level 0 needs none.
local function ArmReset()
    if resetTimer then resetTimer:Cancel(); resetTimer = nil end
    local timer, map = _G.C_Timer, _G.Minimap
    local seconds = M.active and M.config.zoomResetSeconds or 0
    if seconds <= 0 or not timer or type(timer.NewTimer) ~= "function" or not MM.Usable(map) then return end
    local zoom = map:GetZoom()
    if MM.Number(zoom) and zoom > 0 then resetTimer = timer.NewTimer(seconds, ResetZoom) end
end
MM.ArmZoomReset = ArmReset
local function Zoom(step)
    local map = _G.Minimap
    if not MM.Usable(map) then return end
    local zoom, levels = map:GetZoom(), map:GetZoomLevels()
    if not MM.Number(zoom) or not MM.Number(levels) or levels < 1 then return end
    local target = math.max(0, math.min(levels - 1, zoom + step))
    if target == zoom then return end
    map:SetZoom(target)
    SyncButtons(target, levels)
    ArmReset()
end
local function Wheel(_, delta)
    if M.active and M.config.scrollZoom and MM.Number(delta) and delta ~= 0 then Zoom(delta > 0 and 1 or -1) end
end

-- Blizzard's own tracking dropdown (Retail, TBC, Mists); Classic Era has none.
local function TrackingButton()
    local cluster = _G.MinimapCluster
    local tracking = MM.Usable(cluster) and cluster.Tracking
    local button = MM.Usable(tracking) and tracking.Button or _G.MiniMapTrackingButton
    if MM.Usable(button) and type(button.OpenMenu) == "function" then return button end
end
MM.TrackingButton = TrackingButton
local function MouseUp(_, button)
    if button ~= "MiddleButton" or not M.active or NS.IsCombatLocked() then return end
    local action = M.config.middleClick
    if action == 2 then
        local tracking = TrackingButton()
        if not tracking then return end
        if type(tracking.IsMenuOpen) == "function" and tracking:IsMenuOpen() then tracking:CloseMenu() else tracking:OpenMenu() end
    elseif action == 3 then
        if type(_G.ToggleCalendar) == "function" then _G.ToggleCalendar() end
    elseif action == 4 and type(_G.ToggleWorldMap) == "function" then _G.ToggleWorldMap() end
end

local function RestoreMapInput()
    local map, scripts = inputMap, inputScripts
    if map and scripts and MM.Usable(map) and type(map.GetScript) == "function" then
        if map:GetScript("OnMouseUp") == scripts.mouseUp then
            map:SetScript("OnMouseUp", scripts.originalMouseUp)
        end
        if map:GetScript("OnMouseWheel") == scripts.mouseWheel then
            map:SetScript("OnMouseWheel", scripts.originalMouseWheel)
        end
    end
    inputMap, inputScripts = nil, nil
end

local function InstallMapInput(map)
    if not MM.Usable(map) or type(map.GetScript) ~= "function"
        or type(map.SetScript) ~= "function" then return end
    if inputMap == map and inputScripts
        and map:GetScript("OnMouseUp") == inputScripts.mouseUp
        and map:GetScript("OnMouseWheel") == inputScripts.mouseWheel then return end
    RestoreMapInput()
    local originalMouseUp = map:GetScript("OnMouseUp")
    local originalMouseWheel = map:GetScript("OnMouseWheel")
    local mouseUp = function(self, button, ...)
        if button == "MiddleButton" then return MouseUp(self, button) end
        if originalMouseUp then return originalMouseUp(self, button, ...) end
    end
    map:SetScript("OnMouseUp", mouseUp)
    map:SetScript("OnMouseWheel", Wheel)
    inputMap = map
    inputScripts = {
        originalMouseUp = originalMouseUp, originalMouseWheel = originalMouseWheel,
        mouseUp = mouseUp, mouseWheel = Wheel,
    }
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
    leaveTimer = nil
    if M.active and not Inside() then SetHovered(false) end
end
function MM.HoverEnter()
    if leaveTimer then leaveTimer:Cancel(); leaveTimer = nil end
    if M.active and catcher and catcher:IsShown() then SetHovered(true) end
end
-- A short grace bridges the gap between the map and its rows or drawer.
function MM.HoverLeave()
    if leaveTimer or not MM.hovered then return end
    local timer = _G.C_Timer
    if timer and type(timer.NewTimer) == "function" then leaveTimer = timer.NewTimer(HOVER_GRACE, LeaveCheck) else LeaveCheck() end
end

-- Native buttons stay above the passive hover area. Observe their own motion
-- so moving from the map into a Blizzard button keeps mouseover controls open.
function MM.HookHover(frame)
    if not MM.Usable(frame) or hoverHooked[frame]
        or type(frame.HookScript) ~= "function" then return end
    hoverHooked[frame] = true
    frame:HookScript("OnEnter", MM.HoverEnter)
    frame:HookScript("OnLeave", MM.HoverLeave)
end

local function LayerCatcher()
    if not catcher or not MM.host then return end
    -- Only a hidden mouseover minimap needs the catcher above the map to wake
    -- it. Once visible, the catcher is below Blizzard's map and every button.
    local waking = M.config.visibility == 4 and not MM.host:IsShown()
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
        if not M.active or M.config.zoomButtons == 3 then return end
        local zoomIn, zoomOut = ZoomButtons()
        if zoomIn and MM.owned[zoomIn] and not zoomIn:IsShown() then zoomIn:Show() end
        if zoomOut and MM.owned[zoomOut] and not zoomOut:IsShown() then zoomOut:Show() end
    end)
    catcher = S.CreateFrame("Frame", nil, host)
    if type(catcher.SetMouseMotionEnabled) == "function" and type(catcher.SetMouseClickEnabled) == "function"
        and type(catcher.SetPropagateMouseMotion) == "function" then
        catcher:SetMouseClickEnabled(false)
        catcher:SetMouseMotionEnabled(true)
        catcher:SetPropagateMouseMotion(true)
        catcher:SetScript("OnEnter", MM.HoverEnter)
        catcher:SetScript("OnLeave", MM.HoverLeave)
        MM.hoverCapable = true
    end
    catcher:Hide()
    MM.zoomHolder, MM.catcher = holder, catcher
end

local function ZoomClicked(button)
    if M.active and MM.owned[button] then ArmReset() end
end
-- Retail's map hides its zoom buttons when the cursor leaves the round map;
-- inside the suite holder they stay shown and the holder decides.
local function ZoomHidden(button)
    if M.active and MM.owned[button] and M.config.zoomButtons ~= 3 and not button:IsShown() then button:Show() end
end
local function Adopt(button, mode)
    if not button then return end
    if not zoomHooked[button] then
        zoomHooked[button] = true
        button:HookScript("OnClick", ZoomClicked)
        button:HookScript("OnHide", ZoomHidden)
    end
    if zoomShown[button] == nil then zoomShown[button] = button:IsShown() == true end
    -- Parked buttons sit in a hidden frame, so Blizzard's hover show never renders them.
    if mode == 3 then MM.Place(button, MM.park, "CENTER", MM.park, "CENTER", 0, 0) end
end
local function PlaceZoom(mode)
    local zoomIn, zoomOut = ZoomButtons()
    local host = MM.host
    Adopt(zoomIn, mode)
    Adopt(zoomOut, mode)
    if mode == 3 or not zoomIn or not zoomOut then
        MM.SetExtent("zoom", 0, 0, 0, 0)
        return
    end
    local inset, level = 2, MM.mapLevel + 13
    local c = M.config
    MM.Place(zoomOut, holder, "BOTTOMRIGHT", host, "BOTTOMRIGHT",
        -inset + (c.zoomOutX or 0), inset + (c.zoomOutY or 0), nil, nil, level)
    MM.Place(zoomIn, holder, "BOTTOMRIGHT", host, "BOTTOMRIGHT",
        -inset + (c.zoomInX or 0), 27 + (c.zoomInY or 0), nil, nil, level)
    local left, right, top, bottom = 0, 0, 0, 0
    for _, item in ipairs({ { zoomIn, c.zoomInX or 0, 27 + (c.zoomInY or 0) },
        { zoomOut, c.zoomOutX or 0, inset + (c.zoomOutY or 0) } }) do
        local width, height = item[1]:GetSize()
        if MM.Number(width) and MM.Number(height) then
            local x, y = -inset + item[2], item[3]
            left = math.max(left, width - (MM.width or 0) - x)
            right = math.max(right, x)
            top = math.max(top, y + height - (MM.height or 0))
            bottom = math.max(bottom, -y)
        end
    end
    MM.SetExtent("zoom", left, right, top, bottom)
    if not zoomIn:IsShown() then zoomIn:Show() end
    if not zoomOut:IsShown() then zoomOut:Show() end
end

local function NeedsHover(c)
    return c.visibility == 4 or c.zoomButtons == 1 or (c.hoverResize and c.visibility ~= 5)
        or (c.collectButtons and c.drawerMouseover)
        or (c.infoCoordinates and c.infoCoordinatesMode == 1)
        or (c.showLanding == 2 and S.MinimapElementAvailable and S.MinimapElementAvailable("Landing"))
end
-- In mouseover visibility the host is hidden, so the catcher cannot be its child.
local function ApplyCatcher()
    local c, host = M.config, MM.host
    local parent = c.visibility == 4 and UIParent or host
    if catcher:GetParent() ~= parent then catcher:SetParent(parent) end
    catcher:SetFrameStrata(host:GetFrameStrata())
    LayerCatcher()
    local wanted = MM.hoverCapable and NeedsHover(c) and true or false
    catcher:SetShown(wanted)
    if not wanted then
        if leaveTimer then leaveTimer:Cancel(); leaveTimer = nil end
        SetHovered(false)
    end
    MM.Queue("hover")
end
MM.ApplyCatcher = ApplyCatcher

-- Rows outside the map report how far they reach so the catcher covers them.
function MM.SetExtent(key, left, right, top, bottom)
    local extent = extents[key]
    if not extent then extent = {}; extents[key] = extent end
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
    if holder and M.active and M.config.zoomButtons == 1 then holder:SetShown(shown) end
end)

-- Edit Mode writes its own rotation when it applies a layout (at login); an
-- explicit suite choice goes back on after Blizzard's handler has run.
MM.flushers.rotate = function()
    local rotate = M.config.rotate
    if rotate == 1 then return end
    if NS.IsCombatLocked() then MM.Force("input"); S.Queue("minimap"); return end
    M.context:CVar("rotateMinimap", rotate == 2 and "1" or "0")
end
local function LayoutApplied() MM.Queue("rotate") end

function MM.ApplyInput()
    local c, ctx, map = M.config, M.context, _G.Minimap
    EnsureInput()
    -- The map keeps its own hit target and Blizzard button children stay clickable.
    if MM.Usable(map) then
        InstallMapInput(map)
        ctx:Property(map, "IsMouseWheelEnabled", "EnableMouseWheel", c.scrollZoom)
    end
    if c.zoomResetSeconds <= 0 and resetTimer then resetTimer:Cancel(); resetTimer = nil end
    PlaceZoom(c.zoomButtons)
    holder:SetShown(c.zoomButtons == 2 or (c.zoomButtons == 1 and MM.Revealed()))
    -- 1 leaves Blizzard's own rotation setting alone (and returns a suite write).
    if c.rotate == 1 then
        S.RestoreCVar("minimap", "rotateMinimap")
        MM.Unlisten("EDIT_MODE_LAYOUTS_UPDATED", "rotate")
    else
        ctx:CVar("rotateMinimap", c.rotate == 2 and "1" or "0")
        MM.Listen("EDIT_MODE_LAYOUTS_UPDATED", "rotate", LayoutApplied)
    end
    ApplyCatcher()
end

function MM.ReleaseInput()
    if resetTimer then resetTimer:Cancel(); resetTimer = nil end
    if leaveTimer then leaveTimer:Cancel(); leaveTimer = nil end
    MM.hovered = false
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
