local _, NS = ...

-- Read once. Forever uses the Mainline engine and a Camelot game layer, not
-- the Classic Era frame tree. Sources are recorded in docs/SUITE-SOURCES.md.
local project = WOW_PROJECT_ID
local forever = type(GameEvent) == "table" and type(GameEvent.RegisterCamelotEvents) == "function"
local function Project(id) return id ~= nil and project == id end
local mainline = forever or Project(WOW_PROJECT_MAINLINE)
local flavor = forever and "Forever" or mainline and "Mainline"
    or Project(WOW_PROJECT_CLASSIC) and "Vanilla"
    or Project(WOW_PROJECT_BURNING_CRUSADE_CLASSIC) and "TBC"
    or Project(WOW_PROJECT_MISTS_CLASSIC) and "Mists"
    or Project(WOW_PROJECT_WRATH_CLASSIC) and "Wrath"
    or Project(WOW_PROJECT_CATACLYSM_CLASSIC) and "Cata" or "Unknown"
NS.Client = {
    flavor = flavor, isForever = forever, isMainline = mainline,
    -- Modern equipment annotations contain Retail-specific upgrade/rating
    -- contracts. Other clients retain their native character layout and skin.
    modernEquipment = mainline and not forever,
}

function NS.Client.IsAddOnLoaded(name)
    local fn = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local first, second = fn(name)
    if second ~= nil then return second == true end
    return first == true
end

function NS.Client.HasAddOn(name)
    if C_AddOns and type(C_AddOns.DoesAddOnExist) == "function" then
        return C_AddOns.DoesAddOnExist(name) == true
    end
    local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    if type(info) == "function" then return info(name) ~= nil end
    if NS.Client.IsAddOnLoaded(name) then return true end
    return nil -- no inventory API: unknown, not evidence of an absent addon
end

function NS.Client.SupportsEvent(event)
    if C_EventUtils and type(C_EventUtils.IsEventValid) == "function" then
        return C_EventUtils.IsEventValid(event) == true
    end
    return true
end
