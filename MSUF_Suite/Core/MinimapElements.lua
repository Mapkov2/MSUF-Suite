local _, NS = ...
-- Read-only native sources shared by the minimap runtime and its preview.
-- Available before the optional runtime loads, including on older builds.
local Native = {}
NS.MinimapElements = Native
local Forbidden = NS.Safety.IsForbidden
local function Usable(frame)
    return type(frame) == "table" and not Forbidden(frame)
end
local function Cluster(first, second)
    local frame = _G.MinimapCluster
    frame = Usable(frame) and frame[first]
    if second then frame = Usable(frame) and frame[second] end
    return Usable(frame) and frame or nil
end
local function Global(name)
    local frame = _G[name]
    return Usable(frame) and frame or nil
end
function Native.Ready() return Usable(_G.MinimapCluster) end
function Native.Tracking() return Cluster("Tracking") end
function Native.Calendar() return Global("GameTimeFrame") end
function Native.Mail() return Cluster("IndicatorFrame", "MailFrame") end
function Native.Crafting() return Cluster("IndicatorFrame", "CraftingOrderFrame") end
function Native.Compartment() return Global("AddonCompartmentFrame") end
function Native.ZoomButtons()
    local map = Global("Minimap")
    if not map then return end
    local zoomIn, zoomOut = map.ZoomIn, map.ZoomOut
    return Usable(zoomIn) and zoomIn or nil, Usable(zoomOut) and zoomOut or nil
end

local ZOOM_LAYOUT = NS.MinimapZoomLayout
local ZOOM_RULES = NS.SuiteCatalog.minimap.rules
local ZOOM_IN_Y, ZOOM_OUT_Y, ZOOM_X = 27, 2, -2
local ZOOM_GAP = 16
local function ZoomSize(frame, defaultHeight)
    if not frame then return 17, defaultHeight end
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not (NS.Finite(width) and NS.Finite(height) and width > 0 and height > 0) then return 17, defaultHeight end
    local scale = frame.GetScale and frame:GetScale()
    if not NS.Finite(scale) or scale <= 0 then scale = 1 end
    return width * scale, height * scale
end

local function FitZoomShift(shift, first, second, rule)
    return math.max(rule.min - math.min(first, second), math.min(rule.max - math.max(first, second), shift))
end

-- The native anchors use each button's bottom-right. Align their visual centers
-- while keeping the center of the user's previous pair, including old offsets.
function Native.ZoomOffsets(c, zoomIn, zoomOut)
    local iw, ih = ZoomSize(zoomIn, 17)
    local ow, oh = ZoomSize(zoomOut, 9)
    local ix, iy, ox, oy = c.zoomInX or 0, c.zoomInY or 0, c.zoomOutX or 0, c.zoomOutY or 0
    local layout = c.zoomLayout or ZOOM_LAYOUT.FREE
    if layout == ZOOM_LAYOUT.FREE then return ix, iy, ox, oy, iw, ih, ow, oh end

    local horizontal = layout == ZOOM_LAYOUT.LEFT or layout == ZOOM_LAYOUT.RIGHT
    local pitchX, pitchY = (iw + ow) / 4, (ih + oh) / 4
    local dx = horizontal and (pitchX + ZOOM_GAP / 2) * (layout == ZOOM_LAYOUT.LEFT and -1 or 1) or 0
    local dy = not horizontal and (pitchY + ZOOM_GAP / 2) * (layout == ZOOM_LAYOUT.BELOW and -1 or 1) or 0
    local middleY = (ZOOM_IN_Y + ZOOM_OUT_Y) / 2
    local baseIX, baseOX = iw / 2 - pitchX + dx, ow / 2 - pitchX - dx
    local baseIY = middleY - ZOOM_IN_Y + pitchY - ih / 2 + dy
    local baseOY = middleY - ZOOM_OUT_Y + pitchY - oh / 2 - dy
    local shiftX = FitZoomShift((ix + ox) / 2, baseIX, baseOX, ZOOM_RULES.zoomInX)
    local shiftY = FitZoomShift((iy + oy) / 2, baseIY, baseOY, ZOOM_RULES.zoomInY)
    return baseIX + shiftX, baseIY + shiftY, baseOX + shiftX, baseOY + shiftY, iw, ih, ow, oh
end

function Native.ZoomPosition(c, isZoomIn, x, y)
    return ZOOM_X + x + (c.zoomGroupX or 0), (isZoomIn and ZOOM_IN_Y or ZOOM_OUT_Y) + y + (c.zoomGroupY or 0)
end

function Native.ButtonTexture(button)
    if not Usable(button) then return end
    local enabled = button:IsEnabled()
    if NS.Public(enabled) and enabled == false then
        local disabled = button:GetDisabledTexture()
        if Usable(disabled) then return disabled end
    end
    local normal = button.StateTexture
    if not Usable(normal) then normal = button:GetNormalTexture() end
    return Usable(normal) and normal or nil
end
function Native.QueueStatus() return Global("QueueStatusButton") end
function Native.QueueLayout(config) return config.queueStatusSize, config.queueStatusX, config.queueStatusY end
function Native.Difficulty() return Cluster("InstanceDifficulty") end
function Native.DayNight() return Cluster("DielFrame") end
function Native.DayNightContainer() return Cluster("MinimapContainer") end
function Native.Landing()
    if not NS.Client.isForever then return Global("ExpansionLandingPageMinimapButton") end
end
function Native.ExternalEvent()
    local backdrop = Global("MinimapBackdrop")
    local frame = backdrop and backdrop.ExternalEventURLButton
    return Usable(frame) and frame or nil
end
local READERS = {
    Tracking = Native.Tracking, Calendar = Native.Calendar, Mail = Native.Mail,
    Crafting = Native.Crafting, Compartment = Native.Compartment, Difficulty = Native.Difficulty,
    Landing = Native.Landing, ExternalEvent = Native.ExternalEvent,
    QueueStatus = Native.QueueStatus,
}
function Native.Frame(key)
    local read = READERS[key]
    return read and read() or nil
end
function Native.Available(key) return Native.Frame(key) ~= nil end

-- StateTexture is used by 70425's ButtonStateBehavior templates; the normal
-- texture remains the source on earlier builds. Return native regions without
-- reading or caching their potentially restricted geometry or colors.
function Native.Source(key)
    local frame = Native.Frame(key)
    if not frame then return end
    local source, label, button = nil, nil, frame
    if key == "Tracking" then button = frame.Button end
    if key == "Tracking" or key == "Calendar" or key == "Compartment" or key == "Landing" then
        source = Native.ButtonTexture(button)
        if key == "Compartment" then label = frame.Text end
    elseif key == "Mail" then
        source = frame.MailIcon or Global("MiniMapMailIcon")
    elseif key == "Crafting" then
        source = Global("MiniMapCraftingOrderIcon")
    elseif key == "ExternalEvent" then
        source = frame.Icon
    elseif key == "QueueStatus" then
        source = frame.Eye and frame.Eye.texture
    end
    local add = Usable(button) and button.AddTexture
    local border = key == "ExternalEvent" and frame.Border
    return frame, Usable(source) and source or nil, Usable(add) and add or nil,
        Usable(border) and border or nil, Usable(label) and label or nil
end
