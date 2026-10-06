local _, Suite = ...

-- The Suite's documented entry points for MSUF (MSUFSuite.API, version 1):
-- everything an MSUF host calls on the Suite, in one versioned table, so a
-- refactor of the Suite's own modules cannot silently remove a host feature.
-- Hosts prefer this table and keep their by-path reads of MSUFSuite for
-- older Suites, which is why the namespace itself stays published (Startup).
-- Every function looks its owner up when it is called: the load-on-demand
-- options and the cooldown manager module attach later than this file.
--
--   version                                   1
--   StageFactoryReset() -> ok, reason         Menu2 dashboard: factory reset
--   GetOverview() -> table | nil              the dashboard card summary
--   GetChangelog() -> table                   the Suite's release history
--   OpenInstaller() -> opened                 the Suite setup window
--   MaybeShowInstaller(reason)                after MSUF's own first run
--   IsInstallerPending() -> bool              setup not finished yet
--   IsInstallerOpen() -> bool
--   OnMSUFProfileChanged(name, reason)        MSUF switched its profile
--   OnMSUFProfileLifecycle(kind, source, target) -> allowed
--   ApplyFontsFromMSUF()                      MSUF's global font changed
--   HasCooldownAnchor() -> bool               the cooldown manager is loaded
--   GetCooldownAnchorFrame(viewerName) -> frame | nil
--   HasColorsCategory() -> bool               the Suite options are loaded
--   BuildColorsCategory(ctx, builder)         MSUF Colors: the Suite category
--   Profiles = { Available, Export, ExportModule, Import, ImportModule,
--                ImportModuleIntoNew }        MSUF's profile import/export
--   GetProfileModules() -> { { id, title }, ... }   in Suite order (new table)
--   IsSkinAddOnEnabled() -> bool
local API = { version = 1 }
Suite.API = API

------------------------------------------------------------------ dashboard
function API.StageFactoryReset() return Suite.Database.StageFactoryReset() end
function API.GetOverview() return Suite.GetOverview() end
function API.GetChangelog() return Suite.Changelog end

------------------------------------------------------------------ setup
function API.OpenInstaller() return Suite.Installer.Open() end
function API.MaybeShowInstaller(reason) return Suite.Installer.MaybeShow(reason) end
function API.IsInstallerPending() return Suite.Installer.IsFirstRunPending() end
function API.IsInstallerOpen() return Suite.Installer.IsOpen() end

------------------------------------------------------------------ MSUF state
function API.OnMSUFProfileChanged(name, reason) return Suite.OnMSUFProfileChanged(name, reason) end
function API.OnMSUFProfileLifecycle(kind, source, target)
    return Suite.OnMSUFProfileLifecycle(kind, source, target)
end
function API.ApplyFontsFromMSUF() return Suite.Suite.ApplyGlobalFont() end

------------------------------------------------------------------ cooldown anchor
-- MSUF_Suite_CooldownManager publishes Suite.CooldownManager when it loads.
function API.HasCooldownAnchor() return Suite.CooldownManager ~= nil end
function API.GetCooldownAnchorFrame(viewerName)
    local manager = Suite.CooldownManager
    if manager then return manager.GetAnchorFrame(viewerName) end
    return nil
end

------------------------------------------------------------------ options
-- MSUF_Suite_Options (load-on-demand) publishes Suite.Options when it loads.
function API.HasColorsCategory() return Suite.Options ~= nil end
function API.BuildColorsCategory(ctx, builder) return Suite.Options.BuildColorsCategory(ctx, builder) end

------------------------------------------------------------------ profiles
API.Profiles = {
    Available = function() return Suite.SuiteProfiles.Available() end,
    Export = function(options) return Suite.SuiteProfiles.Export(options) end,
    ExportModule = function(id, options) return Suite.SuiteProfiles.ExportModule(id, options) end,
    Import = function(name, text) return Suite.SuiteProfiles.Import(name, text) end,
    ImportModule = function(text) return Suite.SuiteProfiles.ImportModule(text) end,
    ImportModuleIntoNew = function(name, text) return Suite.SuiteProfiles.ImportModuleIntoNew(name, text) end,
}

function API.GetProfileModules()
    local modules, catalog = {}, Suite.SuiteCatalog
    for _, id in ipairs(Suite.SuiteOrder) do
        local spec = catalog[id]
        if spec then modules[#modules + 1] = { id = id, title = spec.title } end
    end
    return modules
end

function API.IsSkinAddOnEnabled() return Suite.Client.AddOnEnabled("MSUF_Suite_Skin") == true end

return API
