local addonName, NS = ...

-- MSUF Suite can load this legacy addon once for its SavedVariables. In that
-- case the Suite-owned engine keeps the public API and this copy stays inert.
local provider = _G.MapkoSkin
NS.migrationOnly = _G.MSUFSuiteSkinMigrating == true
    or type(provider) == "table" and provider.addonName == "MSUF_Suite_Skin"
if not NS.migrationOnly then
    _G.MapkoSkin = NS
    _G.MidnightSkin = NS -- Legacy integrations; canonical API is MapkoSkin.
end

NS.addonName = addonName
NS.version = "0.35.1"
-- Legacy API v1 remains stable for existing integrations.  The versioned
-- client API is negotiated separately through MapkoSkin.GetAPI(2, 0).
NS.apiVersion = 1
NS.publicAPIMajor = 2
NS.publicAPIMinor = 1
NS.path = "Interface\\AddOns\\MSUF_Suite_Skin\\"

function NS.IsCombatLocked()
    return InCombatLockdown()
end

-- Reported like a Lua error (BugSack shows it); the caller goes on.
function NS.ReportError(context, message)
    local text = ("MSUF Suite skin %s: %s"):format(tostring(context or "error"), tostring(message or "unknown error"))
    geterrorhandler()(text)
end

-- The Suite core (MSUFSuite, published by MSUF_Suite/Core/Startup.lua).
-- MSUF_Suite is this addon's dependency and loads it, so the core is there
-- at the first use; it is resolved then, once.
local suiteCore
function NS.SuiteCore()
    if suiteCore == nil then
        local core = _G.MSUFSuite
        if type(core) ~= "table" then
            error("MSUF_Suite_Skin: the MSUF Suite core (MSUFSuite) is not loaded", 2)
        end
        suiteCore = core
    end
    return suiteCore
end

-- Chat lines go out under the Suite's name, through the Suite core's
-- printer (MSUF_Suite/Core/Platform.lua).
function NS.Print(message)
    NS.SuiteCore().Print(message or "")
end
