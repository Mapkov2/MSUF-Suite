local _, NS = ...

local OPTIONS_ADDON = "MSUF_Suite_Skin_Options"
local IsAddOnLoadedAPI = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
local LoadAddOnAPI = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn

local function IsOptionsLoaded()
    if type(IsAddOnLoadedAPI) ~= "function" then
        return false
    end
    -- C_AddOns.IsAddOnLoaded returns loadedOrLoading, loaded; the legacy
    -- global returns only the first value.
    local first, second = IsAddOnLoadedAPI(OPTIONS_ADDON)
    if second ~= nil then
        return second == true
    end
    return first == true
end

function NS.EnsureOptionsLoaded()
    if NS.IsCombatLocked() then
        NS.Print(NS.L.OPEN_BLOCKED_COMBAT)
        return false
    end

    if not IsOptionsLoaded() then
        if type(LoadAddOnAPI) ~= "function" then
            NS.Print(NS.L.LOAD_OPTIONS_FAILED:format("C_AddOns unavailable"))
            return false
        end
        local loaded, reason = LoadAddOnAPI(OPTIONS_ADDON)
        if not loaded and not NS.OptionsReady and not IsOptionsLoaded() then
            NS.Print(NS.L.LOAD_OPTIONS_FAILED:format(tostring(reason or "unknown")))
            return false
        end
    end

    if not NS.OptionsReady or not NS.Options or type(NS.Options.Open) ~= "function" then
        NS.Print(NS.L.OPTIONS_NOT_READY)
        return false
    end
    return true
end

-- The Suite menu owns the Skinning page; the standalone window is the
-- fallback when the MSUF menu cannot open it.
function NS.OpenOptions()
    local suite = _G.MSUFSuite
    if suite and suite.Menu and type(suite.Menu.Open) == "function"
        and suite.Menu.Open("suite_skin") then
        return true
    end
    if not NS.EnsureOptionsLoaded() then return false end
    return NS.Options.Open()
end

function NS.MountOptions(parent, width, height)
    if not NS.EnsureOptionsLoaded() or not NS.Options.Mount then return nil end
    return NS.Options.Mount(parent, width, height)
end
