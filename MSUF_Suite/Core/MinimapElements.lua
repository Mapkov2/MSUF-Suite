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
