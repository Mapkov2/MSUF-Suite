local addonName, NS = ...

if type(NS) ~= "table" then
    NS = {}
end

-- MSUF Suite can load this legacy addon once for its SavedVariables. In that
-- case the Suite-owned engine keeps the public API and this copy stays inert.
NS.migrationOnly = _G.MSUFSuiteSkinMigrating == true
    or type(_G.MapkoSkin) == "table" and _G.MapkoSkin.addonName == "MSUF_Suite_Skin"
if not NS.migrationOnly then
    _G.MapkoSkin = NS
    _G.MidnightSkin = NS -- Legacy integrations; canonical API is MapkoSkin.
end

NS.addonName = addonName or "MapkoSkin"
NS.version = "0.35.1"
-- Legacy API v1 remains stable for existing integrations.  The versioned
-- client API is negotiated separately through MapkoSkin.GetAPI(2, 0).
NS.apiVersion = 1
NS.publicAPIMajor = 2
NS.publicAPIMinor = 1
NS.path = "Interface\\AddOns\\MSUF_Suite_Skin\\"
NS.internal = NS.internal or {}

function NS.IsCombatLocked()
    return type(InCombatLockdown) == "function" and InCombatLockdown() or false
end

function NS.ReportError(context, message)
    local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
    local text = ("MapkoSkin %s: %s"):format(tostring(context or "error"), tostring(message or "unknown error"))
    if type(handler) == "function" then
        local ok = pcall(handler, text)
        if not ok and type(print) == "function" then
            print(text)
        end
    elseif type(print) == "function" then
        print(text)
    end
end

function NS.Print(message)
    local prefix = "|cff3b82f6MapkoSkin|r"
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. ": " .. tostring(message or ""))
    elseif type(print) == "function" then
        print("MapkoSkin: " .. tostring(message or ""))
    end
end
