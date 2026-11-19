local _, Suite = ...

-- This database belongs to MSUF_Suite. MapkoSkin is only an optional source
-- for the one-time migration of older development builds.
local Database = {}
Suite.Database = Database
local SCHEMA = 1
local Storage = Suite.ProfileStorage
local historyKeys = { "suiteChat", "suiteRuns", "suiteRecovery" }
-- The settings in this database: these root keys and these keys of a
-- profile's suite table. Everything else is runtime data the modules keep
-- for themselves (chat history, gold ledgers, run and XP history, saved
-- CVars, the per-profile moduleState), which undo history never copies or
-- restores (MSUF_Suite_Options/Menu/Bridge.lua).
Database.ROOT_SETTINGS = { "activeProfile", "skinEnabled" }
Database.PROFILE_SETTINGS = { "schema", "revision", "globalLook", "moduleLooks", "modules" }
-- Module state that is layout the player arranges in MSUF Edit Mode (the
-- detached minimap addon buttons): undo and Edit Mode Cancel restore it
-- with the settings. Other module state is runtime data and never rides.
Database.PROFILE_LAYOUT_STATE = { minimap = { "detachedButtons" } }
-- These root caches belong to a profile name. They never enter settings
-- exports or undo, but a rename moves them and deletion releases them.
local PROFILE_RUNTIME_ROOTS = { "cdmEditorCatalog" }

local function CopyTable(value, seen)
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        if type(key) == "table" then key = CopyTable(key, seen) end
        if type(item) == "table" then item = CopyTable(item, seen) end
        result[key] = item
    end
    return result
end

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    return CopyTable(value, seen or {})
end
Suite.CopyValue = Copy

-- The one profile name rule of MSUF, the Suite and its skin: the skin stores
-- its profiles under exactly these names (MSUF_Suite_Skin/Core/
-- DatabaseProfiles.lua asks this function).
Database.MAX_PROFILE_NAME_BYTES = 80
function Database.IsProfileName(name)
    return type(name) == "string" and #name > 0 and #name <= Database.MAX_PROFILE_NAME_BYTES
        and not name:find("[%z\1-\31]") and name:find("%S") ~= nil
end

-- New profiles start from the bundled factory of this client when MSUF's
-- codec can read it, otherwise from catalog defaults at the current
-- migration revision.
function Database.PrepareFactory(profile)
    local modules = profile.suite.modules
    local config = modules.cooldownManager
    if config then
        config.captured = true
        config.defaultsVersion = Suite.CDM.DEFAULTS_VERSION
    end
    if modules.characterPanel then modules.characterPanel.mode = Suite.CharacterPanelMode.SUITE end
    return profile
end

local function NewProfile()
    local function StyleFactory(profile)
        Suite.Suite.StyleProfile(profile, "cleanModern")
        return profile
    end
    local compact = Suite.Client.isForever and Suite.ForeverFactoryModuleCompact
        or Suite.RetailFactoryModuleCompact
    -- Older MSUF builds do not export the codec.
    if type(compact) == "string" and type(_G.MSUF_TryDecodeCompactString) == "function" then
        -- The bundled string is known-good; the codec returns nil on bad input.
        local envelope = _G.MSUF_TryDecodeCompactString(compact:sub(8))
        if type(envelope) == "table" and envelope.addon == "MSUF_Suite" and envelope.format == 1 then
            local profile = Suite.ProfileIO.PrepareTable(envelope.profile, false)
            if profile then return StyleFactory(Database.PrepareFactory(profile)) end
        end
    end
    local profile = { suite = { schema = 1, revision = Suite.Suite.MigrationRevision, modules = {} } }
    Suite.Suite.Normalize(profile)
    return StyleFactory(profile)
end
Database.CreateFactoryProfile = NewProfile

-- A saved profile this build cannot read must not keep the others from
-- starting. It is set aside with its data untouched, in
-- root.quarantinedProfiles as { name = saved key, profile = saved value }.
local function Quarantine(root, stored, name, profile)
    local list = root.quarantinedProfiles
    if type(list) ~= "table" or stored and list == stored.quarantinedProfiles then
        list = type(list) == "table" and Copy(list) or {}
        root.quarantinedProfiles = list
    end
    list[#list + 1] = { name = name, profile = profile }
end

local function PlainProfile(profile)
    return type(profile) == "table" and type(profile.suite) == "table"
end

local function EntryProfile(profile)
    if PlainProfile(profile) then return profile end
    if Storage then return Storage.Decode(profile) end
end

local function RestorePackedProfiles(root)
    local recovery = root.recoveryPackedProfiles
    root.recoveryPackedProfiles = type(recovery) == "table" and Copy(recovery) or nil
    if not root.recoveryPackedProfiles or not Storage or not Storage.Available() then return end
    for name, value in pairs(root.recoveryPackedProfiles) do
        if root.profiles[name] == nil and Database.IsProfileName(name) and Storage.IsPacked(value) then
            root.profiles[name], root.recoveryPackedProfiles[name] = value, nil
        end
    end
    if not next(root.recoveryPackedProfiles) then root.recoveryPackedProfiles = nil end
end

local function ChooseActive(root)
    local name = root.activeProfile
    local active = EntryProfile(root.profiles[name])
    if active then return name, active end
    local default = EntryProfile(root.profiles.Default)
    if default then return "Default", default end
    local names = {}
    for key in pairs(root.profiles) do names[#names + 1] = key end
    table.sort(names)
    for _, key in ipairs(names) do
        active = EntryProfile(root.profiles[key])
        if active then return key, active end
    end
end

-- Return a prepared copy, the reason and the number of profiles set aside.
-- The caller publishes it only after all checks pass; neither an existing
-- saved root nor the legacy skin database is mutated.
function Database.Prepare(stored, legacy)
    if stored ~= nil and type(stored) ~= "table" then
        return nil, "invalid-suite-database"
    end
    local legacyPacked = stored and Storage and stored.schema == Storage.LEGACY_SCHEMA
    if stored and stored.schema ~= SCHEMA and not legacyPacked then
        return nil, "unsupported-suite-database-schema"
    end
    if stored and type(stored.profiles) ~= "table" then
        return nil, "invalid-suite-profiles"
    end

    -- Initialize publishes the prepared root in place of the stored one. The
    -- profile tables are copied so neither validation nor a later normalization
    -- writes into them. Packed values stay opaque. Runtime data (chat history, ledgers,
    -- run history) is carried over as it is instead of being copied at login.
    local root = { schema = SCHEMA, profiles = {} }
    if stored then
        for key, value in pairs(stored) do root[key] = value end
        root.profiles = Copy(stored.profiles)
        root.schema = SCHEMA
        RestorePackedProfiles(root)
    end
    local quarantined = 0
    for name, profile in pairs(root.profiles) do
        if not Database.IsProfileName(name) or not PlainProfile(profile)
            and not (Storage and Storage.IsPacked(profile)) then
            Quarantine(root, stored, name, profile)
            root.profiles[name] = nil
            quarantined = quarantined + 1
        end
    end

    local imported = 0
    if not stored and type(legacy) == "table" and type(legacy.profiles) == "table" then
        for name, profile in pairs(legacy.profiles) do
            if type(profile) == "table" and type(profile.suite) == "table" then
                if Database.IsProfileName(name) then
                    root.profiles[name] = { suite = Copy(profile.suite) }
                    imported = imported + 1
                else
                    Quarantine(root, nil, name, { suite = Copy(profile.suite) })
                    quarantined = quarantined + 1
                end
            end
        end
        if imported > 0 then
            root.activeProfile = legacy.activeProfile
            for _, key in ipairs(historyKeys) do
                if type(legacy[key]) == "table" then root[key] = Copy(legacy[key]) end
            end
            root.migration = { source = "MapkoSkinDB", version = 1 }
        end
    end

    if not next(root.profiles) then
        if root.recoveryPackedProfiles and next(root.recoveryPackedProfiles) then return nil, "invalid-suite-profiles" end
        root.profiles.Default = NewProfile()
    end
    local name, profile = ChooseActive(root)
    if not name then return nil, "invalid-suite-profiles" end
    root.activeProfile, root.profiles[name] = name, profile
    return root, imported > 0 and "migrated" or "ready", quarantined
end

function Database.Initialize(stored, legacy)
    local root, reason, quarantined = Database.Prepare(stored, legacy)
    if not root then return false, reason end
    Suite.RootDB = root
    Suite.DB = root.profiles[root.activeProfile]
    if Storage then
        Storage.Pin(Suite.DB)
        for name, value in pairs(root.profiles) do
            if Storage.IsPacked(value) then Storage.WatchSave() else Storage.Queue(root, name) end
        end
    end
    return true, reason, quarantined
end

-- Stage a clean Suite installation for the next UI load. Publish a real root
-- instead of nil so legacy MapkoSkin data cannot be imported again on reload.
-- The marker makes the load-on-demand skin engine rebuild its own factory
-- profile even when its old SavedVariables load after this function returns.
function Database.StageFactoryReset()
    if Suite.IsCombatLocked() then return false, "combat" end
    if not Suite.RootDB then return false, "database-unavailable" end
    local root, reason = Database.Prepare(nil, nil)
    if not root then return false, reason end
    -- Only the settings start over (the profiles, the root settings and the
    -- setup state). Runtime data the modules keep in the root stays: saved
    -- CVars a module still has to hand back, gold, run and XP history.
    local settings = { profiles = true, installation = true, characterInstallations = true,
        quarantinedProfiles = true, recoveryPackedProfiles = true, migration = true }
    for _, key in ipairs(Database.ROOT_SETTINGS) do settings[key] = true end
    for key, value in pairs(Suite.RootDB) do
        if root[key] == nil and not settings[key] then root[key] = value end
    end
    -- The skin addon is load-on-demand and may be disabled when this runs.
    -- Its SavedVariables might therefore not be loaded or written this session.
    root.pendingSkinFactoryReset = true
    _G.MSUFSuiteDB = root
    _G.MSUFSuiteSkinDB = {}
    Suite.RootDB = root
    Suite.DB = root.profiles[root.activeProfile]
    if Storage then Storage.Pin(Suite.DB) end
    return true
end

-- Setup completion belongs to one player, independently of shared profiles.
-- Unknown identity never borrows the account's old installation receipt.
function Database.GetCharacterInstallationStatus()
    local guid = Suite.PublicText(UnitGUID("player"))
    local records = Suite.RootDB and Suite.RootDB.characterInstallations
    return guid and type(records) == "table" and records[guid] or nil, guid
end

function Database.SetCharacterInstallationStatus(status)
    local root = Suite.RootDB
    local _, guid = Database.GetCharacterInstallationStatus()
    if not root or not guid then return false end
    if type(root.characterInstallations) ~= "table" then root.characterInstallations = {} end
    root.characterInstallations[guid] = status
    return true
end

function Database.GetActiveProfileName()
    return Suite.RootDB and Suite.RootDB.activeProfile
end

function Database.HasProfile(name)
    local root = Suite.RootDB
    return root ~= nil and (root.profiles[name] ~= nil
        or root.recoveryPackedProfiles ~= nil and root.recoveryPackedProfiles[name] ~= nil)
end

function Database.ReadProfile(name)
    return Suite.RootDB and EntryProfile(Suite.RootDB.profiles[name])
end

local function StoreNewProfile(name, profile)
    local root = Suite.RootDB
    root.profiles[name] = profile
    if Storage then Storage.Queue(root, name) end
end

function Database.StoreProfile(name, profile)
    Suite.RootDB.profiles[name] = profile
    if Storage then Storage.Pin(profile) end
end

function Database.GetProfile(name)
    local profile = Database.ReadProfile(name)
    if not profile then return nil end
    -- A write-through reference may outlive a timer, profile switch or rename.
    Database.StoreProfile(name, profile)
    return profile
end

function Database.CompactInactive(name)
    if Storage then Storage.Queue(Suite.RootDB, name) end
end

local function ApplyProfile(attempt, forceNative)
    local profileIO = attempt.profileIO
    if profileIO then attempt.liveNative = profileIO.RememberNameplateCVars(attempt.previous) end
    attempt.root.activeProfile, Suite.DB = attempt.name, attempt.profile
    attempt.bound = true
    Suite.ProfileVariants.OnActivated(attempt.name)
    if profileIO then return profileIO.ActivateNameplateProfile(attempt.profile, forceNative) end
    return true
end

local function RestoreProfile(attempt)
    local previous, name = attempt.previous, attempt.previousName
    attempt.root.activeProfile, Suite.DB = name, previous
    if previous then previous.nameplateCVars = attempt.previousNative end
    if not attempt.bound then return true end
    local variantRestored = Suite.Dispatch(Suite.Finish, Suite.ProfileVariants.OnActivated, name)
    local nativeRestored = true
    if attempt.liveNative then
        local ran, ok = Suite.Dispatch(Suite.Finish, attempt.profileIO.ApplyNameplateCVars, attempt.liveNative)
        nativeRestored = ran and ok
    end
    Suite.Dispatch(Suite.OnProfileChanged, name)
    return variantRestored and nativeRestored
end

function Database.Activate(name, forceNative)
    if Suite.IsCombatLocked() then return false, "combat" end
    local checked, allowed, why = Suite.Dispatch(Suite.Finish, Suite.ProfileVariants.CanMutate)
    if not checked or not allowed then return false, why or "Profile switch failed" end
    local profile = Database.IsProfileName(name) and Database.GetProfile(name)
    if not profile then return false, "missing-profile" end
    local previous = Suite.DB
    local attempt = {
        root = Suite.RootDB, profileIO = Suite.ProfileIO, name = name, profile = profile,
        previousName = Database.GetActiveProfileName(), previous = previous,
        previousNative = previous and Copy(previous.nameplateCVars),
    }
    local ran, ok, reason = Suite.Dispatch(Suite.Finish, ApplyProfile, attempt, forceNative)
    if not ran or not ok then
        if not RestoreProfile(attempt) then return false, "Profile switch failed; restore the previous profiles manually" end
        return false, reason or "Profile switch failed"
    end
    if attempt.profileIO then Suite.Dispatch(attempt.profileIO.RememberNameplateCVars) end
    Suite.Dispatch(Suite.OnProfileChanged, name)
    Database.CompactInactive(attempt.previousName)
    return true
end

function Database.Create(name, copyCurrent)
    if Suite.IsCombatLocked() then return false, "combat" end
    if not Suite.RootDB then return false, "database-unavailable" end
    if not Database.IsProfileName(name) then return false, "invalid-profile-name" end
    if Database.HasProfile(name) then return false, "profile-exists" end
    local profile
    if copyCurrent then
        local why
        profile,why=Suite.ProfileVariants.BaseProfile(Database.GetActiveProfileName())
        if not profile then return false,why end
    end
    StoreNewProfile(name, profile or NewProfile())
    return true
end

-- Staged imports may create a new profile only. Existing names, including the
-- active profile, are never overwritten by a shared configuration.
function Database.CreateFromProfile(name, profile)
    if Suite.IsCombatLocked() then return false, "combat" end
    if not Suite.RootDB then return false, "database-unavailable" end
    if not Database.IsProfileName(name) then return false, "invalid-profile-name" end
    if Database.HasProfile(name) then return false, "profile-exists" end
    if type(profile) ~= "table" or type(profile.suite) ~= "table"
        or profile.suite.schema ~= 1 or type(profile.suite.modules) ~= "table" then
        return false, "invalid-suite-profile"
    end
    StoreNewProfile(name, Copy(profile))
    return true
end

function Database.RenameRuntimeData(source, target)
    for _, key in ipairs(PROFILE_RUNTIME_ROOTS) do
        local records = Suite.RootDB[key]
        if type(records) == "table" and records[source] ~= nil then
            records[target], records[source] = records[source], nil
        end
    end
end

function Database.Delete(name)
    if Suite.IsCombatLocked() then return false, "combat" end
    if not Database.HasProfile(name) then return false, "missing-profile" end
    if Database.GetActiveProfileName() == name then return false, "active-profile" end
    local root = Suite.RootDB
    -- An older Suite may have created a plain profile with the same name.
    -- Deleting the visible profile must leave the distinct parked data intact.
    if root.profiles[name] ~= nil then
        root.profiles[name] = nil
    elseif root.recoveryPackedProfiles then
        root.recoveryPackedProfiles[name] = nil
    end
    for _, key in ipairs(PROFILE_RUNTIME_ROOTS) do
        local records = Suite.RootDB[key]
        if type(records) == "table" then records[name] = nil end
    end
    return true
end
