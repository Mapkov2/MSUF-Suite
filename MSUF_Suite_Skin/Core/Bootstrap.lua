local addonName, NS = ...

-- MSUF Suite can load this legacy addon once for its SavedVariables. In that
-- case the Suite-owned engine keeps the public API and this copy stays inert.
NS.migrationOnly = _G.MSUFSuiteSkinMigrating == true
    or type(_G.MapkoSkin) == "table" and _G.MapkoSkin.addonName == "MSUF_Suite_Skin"
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
    local text = ("MapkoSkin %s: %s"):format(tostring(context or "error"), tostring(message or "unknown error"))
    geterrorhandler()(text)
end

function NS.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff3b82f6MapkoSkin|r: " .. tostring(message or ""))
end
