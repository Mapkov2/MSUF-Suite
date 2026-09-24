local _, Suite = ...
local MSUF = assert(_G.MSUF_NS, "MSUF_Suite requires MSUF")

-- Classic MSUF publishes MSUF.Client; Main (Retail-only) MSUF does not. The
-- suite derives the same facts from the client when its host does not provide
-- them, so it runs unchanged under either MSUF build.
local host = type(MSUF.Client) == "table" and MSUF.Client or nil

local function ProjectFlavor()
    local project = _G.WOW_PROJECT_ID
    if project == nil then return "Unknown" end
    if project == _G.WOW_PROJECT_MAINLINE then return "Mainline" end
    if project == _G.WOW_PROJECT_CLASSIC then return "Vanilla" end
    if project == _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC then return "TBC" end
    if project == _G.WOW_PROJECT_MISTS_CLASSIC then return "Mists" end
    return "Unknown"
end

-- WoW Forever runs Blizzard's Mainline code. Blizzard_Game defines this camelot
-- marker before any addon loads, and only on Forever (same probe as Classic MSUF).
local function HasForeverMarker()
    local gameEvent = _G.GameEvent
    return type(gameEvent) == "table" and type(gameEvent.RegisterCamelotEvents) == "function"
end

local flavor, family, isForever, isRetail
if host and type(host.Flavor) == "string" then
    isForever = host.IsForever == true
    flavor = host.Flavor
    family = host.Family or (flavor == "Mainline" and "Mainline" or "Classic")
    isRetail = host.IsRetail == true
else
    flavor = ProjectFlavor()
    isForever = HasForeverMarker() and flavor ~= "Vanilla" and flavor ~= "TBC" and flavor ~= "Mists"
    if isForever then flavor = "Mainline" end
    family = flavor == "Mainline" and "Mainline" or flavor == "Unknown" and "Unknown" or "Classic"
    isRetail = flavor == "Mainline"
end

local eventValidity = {}
local function SupportsEvent(event)
    if type(event) ~= "string" or event == "" then return false end
    local valid = eventValidity[event]
    if valid ~= nil then return valid end
    local utils = _G.C_EventUtils
    if type(utils) ~= "table" or type(utils.IsEventValid) ~= "function" then return true end
    valid = utils.IsEventValid(event) == true
    eventValidity[event] = valid
    return valid
end

Suite.Client = {
    flavor = isForever and "Forever" or flavor,
    family = family,
    isMainline = family == "Mainline",
    isClassic = family == "Classic",
    isForever = isForever,
    modernEquipment = isRetail and not isForever,
    hasSecrets = type(_G.issecretvalue) == "function",
    SupportsEvent = host and type(host.SupportsEvent) == "function" and host.SupportsEvent or SupportsEvent,
}

-- Which MSUF build hosts the suite. Only used for status text and diagnostics;
-- every integration below probes the capability it needs instead.
local getMetadata = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
Suite.Host = {
    build = host and "Classic" or "Main",
    version = type(getMetadata) == "function" and getMetadata("MidnightSimpleUnitFrames", "Version") or nil,
}

Suite.Defaults = {}
Suite.L = type(MSUF.L) == "table" and MSUF.L or {}
Suite.Safety = {}

function Suite.IsCombatLocked()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

function Suite.Safety.IsForbidden(frame)
    return frame and type(frame.IsForbidden) == "function" and frame:IsForbidden() == true
end

function Suite.Client.IsAddOnLoaded(name)
    local query = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if not query then return false end
    local loaded, finished = query(name)
    if finished ~= nil then return finished == true end
    return loaded == true
end

function Suite.Client.HasAddOn(name)
    if C_AddOns and type(C_AddOns.DoesAddOnExist) == "function" then
        return C_AddOns.DoesAddOnExist(name) == true
    end
    local query = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    if query then return query(name) ~= nil end
    return Suite.Client.IsAddOnLoaded(name)
end

-- Match Blizzard's current-character AddOns checkbox. The GUID argument is
-- used by upstream/live's Blizzard_SharedXMLBase/AddOnUtil.lua; nil means the
-- all-characters list, so avoid it when a player GUID is available.
function Suite.Client.AddOnEnabled(name)
    if not Suite.Client.HasAddOn(name) then return false, "Install " .. name .. " to use this module" end
    local query = C_AddOns and C_AddOns.GetAddOnEnableState or GetAddOnEnableState
    if type(query) ~= "function" then return true end
    local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
    if type(issecretvalue) == "function" and issecretvalue(guid) then return false, "AddOn state unavailable in combat" end
    local state = query(name, guid)
    local none = Enum and Enum.AddOnEnableState and Enum.AddOnEnableState.None or 0
    if type(state) == "number" and state > none then return true end
    return false, "Disabled in Blizzard's AddOns list: " .. name
end

function Suite.Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("MSUF Suite: " .. tostring(message))
    end
end

function Suite.ReportError(label, message)
    if type(MSUF.ReportError) == "function" then return MSUF.ReportError(label, message) end
    geterrorhandler()("MSUF Suite " .. tostring(label) .. ": " .. tostring(message))
end

-- Listeners are configuration-only. Registering one allocates no frame and
-- profile notifications never pass through MapkoSkin's registry.
local listeners = {}
Suite.Registry = {}
function Suite.Registry.AddListener(owner, callback)
    assert(type(callback) == "function", "profile listener must be callable")
    listeners[owner] = callback
end
function Suite.Registry.RemoveListener(owner)
    listeners[owner] = nil
end
function Suite.Registry.NotifyListeners(domain, reason)
    for owner, callback in pairs(listeners) do callback(owner, domain, reason) end
end
function Suite.OnProfileChanged(name)
    Suite.Registry.NotifyListeners("profile", name)
end
