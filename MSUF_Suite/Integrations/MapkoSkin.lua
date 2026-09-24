local _, Suite = ...

-- The Suite owns the embedded skin engine's load boundary and uses its public
-- surface API for Suite modules. Legacy standalone MapkoSkin can finish a
-- running session, but the embedded engine is the normal next-login owner.
local Skin = { enabled = false }
Suite.Skin = Skin
local clients = {}

function Skin.IsAvailable()
    local provider = _G.MapkoSkin
    return type(provider) == "table" and type(provider.GetAPI) == "function"
end

function Skin.LoadLegacyDatabase()
    if type(_G.MapkoSkinDB) == "table" then return true end
    if type(_G.MapkoSkin) == "table" and not _G.MapkoSkin.migrationOnly then return false end
    if not (Suite.Client and Suite.Client.HasAddOn and Suite.Client.HasAddOn("MapkoSkin")) then return false end
    local loader = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn
    if type(loader) ~= "function" then return false end
    _G.MSUFSuiteSkinMigrating = true
    pcall(loader, "MapkoSkin")
    _G.MSUFSuiteSkinMigrating = nil
    return type(_G.MapkoSkinDB) == "table"
end

function Skin.EnsureEngine()
    local provider = _G.MapkoSkin
    if type(provider) == "table" and provider.addonName == "MSUF_Suite_Skin" then
        if type(provider.EnsureDatabaseReady) == "function" then provider.EnsureDatabaseReady() end
        return true
    end
    if Skin.IsAvailable() and not provider.migrationOnly then return true, "legacy-session" end
    local loader = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn
    if type(loader) ~= "function" then return false, "loader-unavailable" end
    local importedLegacy = type(_G.MapkoSkinDB) == "table"
    -- The old addon is now load-on-demand. Load it only once as a data bridge:
    -- its skin hooks are suppressed by migrationOnly before PLAYER_LOGIN.
    if Suite.RootDB and not Suite.RootDB.skinMigrationDone then
        importedLegacy = Skin.LoadLegacyDatabase() or importedLegacy
    end
    local ok, loaded, reason = pcall(loader, "MSUF_Suite_Skin")
    if type(_G.MapkoSkin) == "table" and _G.MapkoSkin.addonName == "MSUF_Suite_Skin"
        and Skin.IsAvailable() then
        if type(_G.MapkoSkin.EnsureDatabaseReady) == "function" then
            _G.MapkoSkin.EnsureDatabaseReady()
        end
        if importedLegacy and Suite.RootDB then Suite.RootDB.skinMigrationDone = true end
        return true -- Forever may return a diagnostic.
    end
    return false, ok and tostring(reason or loaded or "skin-engine-unavailable") or tostring(loaded)
end

function Skin.Acquire(moduleID)
    if not Skin.enabled or type(moduleID) ~= "string" or not moduleID:match("^[%a][%w_]*$") then
        return nil
    end
    if clients[moduleID] then return clients[moduleID] end
    if not Skin.EnsureEngine() then return nil end
    local api = _G.MapkoSkin.GetAPI(2, 0)
    if not api or type(api.RegisterAddon) ~= "function" then return nil end
    local client = api:RegisterAddon("MSUF_Suite_" .. moduleID)
    if client then clients[moduleID] = client end
    return client
end

function Skin.Release(moduleID)
    local client = clients[moduleID]
    if not client then return end
    client:ReleaseAll()
    clients[moduleID] = nil
end

function Skin.SetEnabled(enabled)
    if Suite.IsCombatLocked and Suite.IsCombatLocked() then return false, "combat" end
    enabled = enabled == true
    if enabled then Skin.EnsureEngine() end
    if not enabled then
        for moduleID in pairs(clients) do Skin.Release(moduleID) end
    end
    Skin.enabled = enabled
    if Suite.RootDB then Suite.RootDB.skinEnabled = enabled end
    if Suite.Suite and Suite.Suite.started then Suite.Suite.ApplyAll() end
    if Suite.Suite and Suite.Suite.RefreshCopySkin then Suite.Suite.RefreshCopySkin() end
    return true
end

function Skin.OpenEditor(parent, width, height)
    if Suite.IsCombatLocked and Suite.IsCombatLocked() then return false, "combat" end
    Skin.EnsureEngine()
    local provider = _G.MapkoSkin
    if type(provider) ~= "table" or type(provider.MountOptions) ~= "function" then
        return false, "skin-editor-unavailable"
    end
    return provider.MountOptions(parent, width, height)
end
