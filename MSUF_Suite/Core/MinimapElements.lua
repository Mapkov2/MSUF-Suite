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
    local source, button = nil, frame
    if key == "Tracking" then button = frame.Button end
    if key == "Tracking" or key == "Calendar" or key == "Compartment" then
        if Usable(button) then source = button.StateTexture or button:GetNormalTexture() end
    elseif key == "Mail" then
        source = frame.MailIcon or Global("MiniMapMailIcon")
    elseif key == "Crafting" then
        source = Global("MiniMapCraftingOrderIcon")
    elseif key == "ExternalEvent" then
        source = frame.Icon
    end
    local add = Usable(button) and button.AddTexture
    local border = key == "ExternalEvent" and frame.Border
    return frame, Usable(source) and source or nil, Usable(add) and add or nil, Usable(border) and border or nil
end
