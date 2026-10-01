local _, Suite = ...

-- This database belongs to MSUF_Suite. MapkoSkin is only an optional source
-- for the one-time migration of older development builds.
local Database = {}
Suite.Database = Database
local SCHEMA = 1
local historyKeys = { "suiteChat", "suiteRuns", "suiteRecovery" }
-- The settings in this database: these root keys and these keys of a
-- profile's suite table. Everything else is runtime data the modules keep
-- for themselves (chat history, gold ledgers, run and XP history, saved
-- CVars, the per-profile moduleState), which undo history never copies or
-- restores (MSUF_Suite_Options/Menu/Bridge.lua).
Database.ROOT_SETTINGS = { "activeProfile", "skinEnabled" }
Database.PROFILE_SETTINGS = { "schema", "revision", "globalLook", "modules" }
-- Module state that is layout the player arranges in MSUF Edit Mode (the
-- detached minimap addon buttons): undo and Edit Mode Cancel restore it
-- with the settings. Other module state is runtime data and never rides.
Database.PROFILE_LAYOUT_STATE = { minimap = { "detachedButtons" } }

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[Copy(key, seen)] = Copy(item, seen)
    end
    return result
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
            if profile then return StyleFactory(profile) end
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
    if list == nil or stored and list == stored.quarantinedProfiles then
        list = type(list) == "table" and Copy(list) or {}
        root.quarantinedProfiles = list
    end
    list[#list + 1] = { name = name, profile = profile }
end

-- Return a prepared copy, the reason and the number of profiles set aside.
-- The caller publishes it only after all checks pass; neither an existing
-- saved root nor the legacy skin database is mutated.
function Database.Prepare(stored, legacy)
    if stored ~= nil and type(stored) ~= "table" then
        return nil, "invalid-suite-database"
    end
    if stored and stored.schema ~= SCHEMA then
        return nil, "unsupported-suite-database-schema"
    end
    if stored and type(stored.profiles) ~= "table" then
        return nil, "invalid-suite-profiles"
    end

    -- Initialize publishes the prepared root in place of the stored one. The
    -- profiles are copied, so neither validation nor a later normalization
    -- writes into the stored tables; runtime data (chat history, ledgers,
    -- run history) is carried over as it is instead of being copied at login.
    local root = { schema = SCHEMA, profiles = {} }
    if stored then
        for key, value in pairs(stored) do root[key] = value end
        root.profiles = Copy(stored.profiles)
    end
    local quarantined = 0
    for name, profile in pairs(root.profiles) do
        if not Database.IsProfileName(name) or type(profile) ~= "table"
            or type(profile.suite) ~= "table" then
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

    if not next(root.profiles) then root.profiles.Default = NewProfile() end
    if not Database.IsProfileName(root.activeProfile) or not root.profiles[root.activeProfile] then
        local names = {}
        for name in pairs(root.profiles) do names[#names + 1] = name end
        table.sort(names)
        root.activeProfile = root.profiles.Default and "Default" or names[1]
    end
    return root, imported > 0 and "migrated" or "ready", quarantined
end

function Database.Initialize(stored, legacy)
    local root, reason, quarantined = Database.Prepare(stored, legacy)
    if not root then return false, reason end
    Suite.RootDB = root
    Suite.DB = root.profiles[root.activeProfile]
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
    -- The skin addon is load-on-demand and may be disabled when this runs.
    -- Its SavedVariables might therefore not be loaded or written this session.
    root.pendingSkinFactoryReset = true
    _G.MSUFSuiteDB = root
    _G.MSUFSuiteSkinDB = {}
    Suite.RootDB = root
    Suite.DB = root.profiles[root.activeProfile]
    return true
end

function Database.GetActiveProfileName()
    return Suite.RootDB and Suite.RootDB.activeProfile
end

function Database.GetProfile(name)
    return Suite.RootDB and Suite.RootDB.profiles[name]
end

function Database.Activate(name)
    if Suite.IsCombatLocked() then return false, "combat" end
    local allowed,why=Suite.ProfileVariants.CanMutate()
    if not allowed then return false,why end
    if not Database.IsProfileName(name) or not Database.GetProfile(name) then
        return false, "missing-profile"
    end
    Suite.RootDB.activeProfile = name
    Suite.DB = Suite.RootDB.profiles[name]
    Suite.ProfileVariants.OnActivated(name)
    Suite.OnProfileChanged(name)
    return true
end

function Database.Create(name, copyCurrent)
    if Suite.IsCombatLocked() then return false, "combat" end
    if not Suite.RootDB then return false, "database-unavailable" end
    if not Database.IsProfileName(name) then return false, "invalid-profile-name" end
    if Database.GetProfile(name) then return false, "profile-exists" end
    local profile
    if copyCurrent then
        local why
        profile,why=Suite.ProfileVariants.BaseProfile(Database.GetActiveProfileName())
        if not profile then return false,why end
    end
    Suite.RootDB.profiles[name] = profile or NewProfile()
    return true
end

-- Staged imports may create a new profile only. Existing names, including the
-- active profile, are never overwritten by a shared configuration.
function Database.CreateFromProfile(name, profile)
    if Suite.IsCombatLocked() then return false, "combat" end
    if not Suite.RootDB then return false, "database-unavailable" end
    if not Database.IsProfileName(name) then return false, "invalid-profile-name" end
    if Database.GetProfile(name) then return false, "profile-exists" end
    if type(profile) ~= "table" or type(profile.suite) ~= "table"
        or profile.suite.schema ~= 1 or type(profile.suite.modules) ~= "table" then
        return false, "invalid-suite-profile"
    end
    Suite.RootDB.profiles[name] = Copy(profile)
    return true
end

function Database.Delete(name)
    if Suite.IsCombatLocked() then return false, "combat" end
    if not Database.GetProfile(name) then return false, "missing-profile" end
    if Database.GetActiveProfileName() == name then return false, "active-profile" end
    Suite.RootDB.profiles[name] = nil
    return true
end
