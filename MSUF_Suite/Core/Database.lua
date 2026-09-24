local _, Suite = ...

-- This database belongs to MSUF_Suite. MapkoSkin is only an optional source
-- for the one-time migration of older development builds.
local Database = {}
Suite.Database = Database
local SCHEMA = 1
local historyKeys = { "suiteChat", "suiteRuns", "suiteRecovery" }

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

function Database.IsProfileName(name)
    return type(name) == "string" and #name > 0 and #name <= 80
        and not name:find("[%z\1-\31]") and name:find("%S") ~= nil
end

local function NewProfile()
    if Suite.Client and Suite.Client.isForever
        and type(Suite.ForeverFactoryModuleCompact) == "string"
        and type(_G.MSUF_TryDecodeCompactString) == "function"
        and Suite.ProfileIO then
        local ok, envelope = pcall(_G.MSUF_TryDecodeCompactString,
            Suite.ForeverFactoryModuleCompact:sub(8))
        if ok and type(envelope) == "table" and envelope.addon == "MSUF_Suite"
            and envelope.format == 1 then
            local profile = Suite.ProfileIO.PrepareTable(envelope.profile, false)
            if profile then return profile end
        end
    end
    return { suite = { schema = 1, modules = {} } }
end
Database.CreateFactoryProfile = NewProfile

-- Return a prepared copy. The caller publishes it only after all checks pass;
-- neither an existing saved root nor the legacy skin database is mutated.
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

    local root = stored and Copy(stored) or { schema = SCHEMA, profiles = {} }
    for name, profile in pairs(root.profiles) do
        if not Database.IsProfileName(name) or type(profile) ~= "table"
            or type(profile.suite) ~= "table" then
            return nil, "invalid-suite-profile"
        end
    end

    local imported = 0
    if not stored and type(legacy) == "table" and type(legacy.profiles) == "table" then
        for name, profile in pairs(legacy.profiles) do
            if type(profile) == "table" and type(profile.suite) == "table" then
                if not Database.IsProfileName(name) then
                    return nil, "invalid-legacy-profile-name"
                end
                root.profiles[name] = { suite = Copy(profile.suite) }
                imported = imported + 1
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
    return root, imported > 0 and "migrated" or "ready"
end

function Database.Initialize(stored, legacy)
    local root, reason = Database.Prepare(stored, legacy)
    if not root then return false, reason end
    Suite.RootDB = root
    Suite.DB = root.profiles[root.activeProfile]
    return true, reason
end

function Database.GetActiveProfileName()
    return Suite.RootDB and Suite.RootDB.activeProfile
end

function Database.GetProfile(name)
    return Suite.RootDB and Suite.RootDB.profiles[name]
end

function Database.Activate(name)
    if Suite.IsCombatLocked and Suite.IsCombatLocked() then return false, "combat" end
    if not Database.IsProfileName(name) or not Database.GetProfile(name) then
        return false, "missing-profile"
    end
    Suite.RootDB.activeProfile = name
    Suite.DB = Suite.RootDB.profiles[name]
    if Suite.OnProfileChanged then Suite.OnProfileChanged(name) end
    return true
end

function Database.Create(name, copyCurrent)
    if Suite.IsCombatLocked and Suite.IsCombatLocked() then return false, "combat" end
    if not Suite.RootDB then return false, "database-unavailable" end
    if not Database.IsProfileName(name) then return false, "invalid-profile-name" end
    if Database.GetProfile(name) then return false, "profile-exists" end
    Suite.RootDB.profiles[name] = copyCurrent and Copy(Suite.DB) or NewProfile()
    return true
end

-- Staged imports may create a new profile only. Existing names, including the
-- active profile, are never overwritten by a shared configuration.
function Database.CreateFromProfile(name, profile)
    if Suite.IsCombatLocked and Suite.IsCombatLocked() then return false, "combat" end
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
    if Suite.IsCombatLocked and Suite.IsCombatLocked() then return false, "combat" end
    if not Database.GetProfile(name) then return false, "missing-profile" end
    if Database.GetActiveProfileName() == name then return false, "active-profile" end
    Suite.RootDB.profiles[name] = nil
    return true
end
