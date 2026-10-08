local _, NS = ...

-- The skin's saved root and its named profiles (MSUFSuiteSkinDB). The
-- profile schema, its migrations and SanitizeProfile live in Database.lua.
local Database = NS.Database
local historyEpoch, historyTarget, previousHistoryEpoch = 0

function Database.GetHistoryEpoch() return historyEpoch end
function Database.GetHistoryProfile() return historyTarget or Database.GetActiveProfileName() end
function Database.BeginHistoryProfile(name)
    previousHistoryEpoch, historyTarget = historyEpoch, name
    historyEpoch = historyEpoch + 1
end
function Database.EndHistoryProfile(committed)
    if historyTarget and not committed then historyEpoch = previousHistoryEpoch end
    historyTarget, previousHistoryEpoch = nil, nil
end

local function IsForever()
    return NS.Client.isForever
end

------------------------------------------------------------------ names
-- One profile name rule for MSUF, the Suite and the skin: the Suite's own
-- (MSUF_Suite/Core/Database.lua). A skin profile is stored under exactly the
-- name of its MSUF and Suite profile, so a lookup by that name finds it. The
-- skin depends on MSUF_Suite, which has loaded before it.
local function CoreNames()
    return _G.MSUFSuite.Database
end

function Database.IsProfileName(name)
    return CoreNames().IsProfileName(name)
end

function Database.MaxProfileNameBytes()
    return CoreNames().MAX_PROFILE_NAME_BYTES
end

local function Trimmed(name)
    return name:gsub("[%z\1-\31]", ""):match("^%s*(.-)%s*$") or ""
end

-- A name a player typed or an import string carries: control characters
-- removed, outer spaces trimmed, cut to the longest name. nil without one.
function Database.NormalizeProfileName(name)
    if type(name) ~= "string" then return nil end
    name = Trimmed(name):sub(1, Database.MaxProfileNameBytes())
    return Database.IsProfileName(name) and name or nil
end

-- What builds before the shared rule stored a name as: trimmed like above,
-- then cut to 40 bytes.
local LEGACY_NAME_BYTES = 40
local function LegacyName(name)
    if type(name) ~= "string" then return nil end
    name = Trimmed(name)
    return name ~= "" and name:sub(1, LEGACY_NAME_BYTES) or nil
end

-- The name a saved profile keeps: its own when it follows the rule, else
-- the one earlier builds gave it.
local function StoredName(name)
    if Database.IsProfileName(name) then return name end
    return LegacyName(name)
end

-- Earlier builds stored the skin profile of a long or space-padded Suite
-- profile under the cut name, so the next switch to the full name failed.
-- Each such Suite profile gets a copy under its full name; the cut entry
-- stays, so nothing saved is lost.
local function RestoreCutNames(profiles, suiteRoot)
    local suiteProfiles = type(suiteRoot) == "table" and suiteRoot.profiles
    if type(suiteProfiles) ~= "table" then return end
    for name in pairs(suiteProfiles) do
        local cut = Database.IsProfileName(name) and LegacyName(name)
        if cut and cut ~= name and profiles[cut] and not profiles[name] then
            profiles[name] = NS.CopyValue(profiles[cut])
        end
    end
end

-- Forever starts from the Suite's shipped factory skin profile when MSUF can
-- decode it; every other client starts from the defaults.
local function CreateFactoryProfile()
    local suite = _G.MSUFSuite
    local encoded = suite and suite.ForeverFactorySkinCompact
    local decode = _G.MSUF_TryDecodeCompactString
    if IsForever() and type(encoded) == "string" and type(decode) == "function" then
        local envelope = decode("MSUF3:" .. encoded:sub(8))
        if type(envelope) == "table"
            and (envelope.addon == "MapkoSkin" or envelope.addon == "MidnightSkin")
            and envelope.format == 1 and envelope.kind == "profile" then
            local profile = Database.SanitizeProfile(envelope.payload)
            if profile then return profile end
        end
    end
    return Database.Normalize(NS.CopyValue(NS.Defaults))
end
Database.CreateFactoryProfile = CreateFactoryProfile

local function NewRoot(profile)
    return {
        schema = Database.rootSchema,
        activeProfile = "Default",
        profiles = { Default = Database.Normalize(profile or CreateFactoryProfile()) },
    }
end

local function NormalizeRoot(root, suiteRoot)
    root.schema = Database.rootSchema
    if type(root.profiles) ~= "table" then root.profiles = {} end
    local normalized = {}
    for rawName, profile in pairs(root.profiles) do
        local name = StoredName(rawName)
        if name and type(profile) == "table" then
            normalized[name] = Database.Normalize(profile)
        end
    end
    RestoreCutNames(normalized, suiteRoot)
    if not next(normalized) then normalized.Default = CreateFactoryProfile() end
    root.profiles = normalized
    local active = StoredName(root.activeProfile)
    if not active or not normalized[active] then
        active = normalized.Default and "Default" or next(normalized)
    end
    root.activeProfile = active
    return root
end

function Database.Initialize()
    local suiteRoot = _G.MSUFSuiteDB
    local resetPending = type(suiteRoot) == "table" and suiteRoot.pendingSkinFactoryReset == true
    local stored = _G.MSUFSuiteSkinDB
    -- MidnightSkinDB belongs to the pre-rename MidnightSkin bridge addon. It
    -- is handed over only when this engine takes its profiles from it;
    -- otherwise it stays for the standalone MapkoSkin to migrate.
    local fromBridge = false
    if resetPending then
        stored = nil
    else
        if type(stored) ~= "table" then stored = _G.MapkoSkinDB end
        if type(stored) ~= "table" then
            stored = _G.MidnightSkinDB
            fromBridge = type(stored) == "table"
        end
    end
    local root
    if type(stored) == "table" and type(stored.profiles) == "table" then
        root = NormalizeRoot(stored, suiteRoot)
    elseif type(stored) == "table" then
        -- One-time migration from the 0.7 flat SavedVariables layout. Keep the
        -- entire normalized profile; no setting is dropped.
        root = NewRoot(stored)
    else
        root = NewRoot()
    end
    _G.MSUFSuiteSkinDB = root
    if fromBridge then _G.MidnightSkinDB = nil end
    if resetPending then suiteRoot.pendingSkinFactoryReset = nil end
    NS.RootDB = root
    NS.DB = root.profiles[root.activeProfile]
    return NS.DB
end

function Database.GetRoot()
    return NS.RootDB
end

function Database.GetActiveProfileName()
    return NS.RootDB and NS.RootDB.activeProfile or "Default"
end

function Database.GetProfile(name)
    return NS.RootDB and NS.RootDB.profiles and NS.RootDB.profiles[name]
end

function Database.GetProfileNames()
    local names = {}
    for name in pairs(NS.RootDB and NS.RootDB.profiles or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- Applies the active profile everywhere after it was replaced, and tells the
-- listeners (domain "profile" unless given; the factory reset says "theme").
-- Each stage is its own boundary: a stage that raises is reported and the
-- later stages still apply the profile and notify the listeners.
function Database.ApplyActiveSettings(reason, domain)
    local dispatch = NS.Safety.Dispatch
    dispatch(NS.Theme.RefreshDynamicLook)
    dispatch(NS.Typography.ApplyConfigured)
    dispatch(NS.Adapters.ApplyAll)
    dispatch(NS.Registry.RefreshAll)
    NS.Registry.NotifyListeners(domain or "profile", reason or "changed")
end
local ApplyActiveSettings = Database.ApplyActiveSettings

-- The store takes names as they are: the Suite and MSUF hand it theirs.
local function ExactName(name)
    return Database.IsProfileName(name) and name or nil
end

-- Replacing the active profile swaps the settings every skin reads, so it
-- waits out combat like every other skin write.
function Database.SetProfile(name, profile)
    if NS.IsCombatLocked() then return false, "combat" end
    name = ExactName(name)
    profile = Database.SanitizeProfile(profile)
    if not name or not profile or not NS.RootDB then return false, "invalid-profile" end
    NS.RootDB.profiles[name] = profile
    if NS.RootDB.activeProfile == name then NS.DB = profile end
    return true, name
end

function Database.CreateProfile(name, copyCurrent)
    name = ExactName(name)
    if not name then return false, "invalid-name" end
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.RootDB then return false, "database-not-ready" end
    if NS.RootDB.profiles[name] then return false, "profile-exists" end
    NS.RootDB.profiles[name] = copyCurrent and Database.SanitizeProfile(NS.DB)
        or CreateFactoryProfile()
    return true, name
end

function Database.SetActiveProfile(name)
    name = ExactName(name)
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.RootDB then return false, "database-not-ready" end
    if not name or not NS.RootDB.profiles[name] then return false, "missing-profile" end
    NS.Typography.Restore()
    if NS.RootDB.activeProfile ~= name and historyTarget ~= name then historyEpoch = historyEpoch + 1 end
    NS.RootDB.activeProfile = name
    NS.DB = NS.RootDB.profiles[name]
    ApplyActiveSettings("activate")
    return true, name
end

function Database.DeleteProfile(name)
    name = ExactName(name)
    if NS.IsCombatLocked() then return false, "combat" end
    if not NS.RootDB then return false, "database-not-ready" end
    if not name or not NS.RootDB.profiles[name] then return false, "missing-profile" end
    local count = 0
    for _ in pairs(NS.RootDB.profiles) do count = count + 1 end
    if count <= 1 then return false, "last-profile" end
    historyEpoch = historyEpoch + 1
    local wasActive = name == NS.RootDB.activeProfile
    NS.RootDB.profiles[name] = nil
    if wasActive then
        local replacement = NS.RootDB.profiles.Default and "Default" or next(NS.RootDB.profiles)
        NS.RootDB.activeProfile = replacement
        NS.DB = NS.RootDB.profiles[replacement]
        ApplyActiveSettings("delete")
    end
    return true, wasActive and NS.RootDB.activeProfile or name
end

function Database.ReplaceProfiles(profiles, activeName)
    if NS.IsCombatLocked() then return false, "combat" end
    if type(profiles) ~= "table" then return false, "invalid-profiles" end
    if not NS.RootDB then return false, "database-not-ready" end
    local clean = {}
    local count = 0
    for rawName, profile in pairs(profiles) do
        count = count + 1
        if count > 64 then return false, "too-many-profiles" end
        local name = Database.NormalizeProfileName(rawName)
        if name and type(profile) == "table" then clean[name] = Database.SanitizeProfile(profile) end
    end
    if not next(clean) then return false, "empty-profiles" end
    activeName = Database.NormalizeProfileName(activeName)
    if not activeName or not clean[activeName] then
        activeName = clean.Default and "Default" or next(clean)
    end
    NS.Typography.Restore()
    historyEpoch = historyEpoch + 1
    NS.RootDB.profiles = clean
    NS.RootDB.activeProfile = activeName
    NS.DB = clean[activeName]
    ApplyActiveSettings("import-all")
    return true, activeName
end

function Database.ResetColors()
    NS.DB.theme.colors = NS.CopyValue(NS.Defaults.theme.colors)
    NS.DB.theme.preset = NS.Defaults.theme.preset
end

function Database.ResetAll()
    local profile = CreateFactoryProfile()
    local name = Database.GetActiveProfileName()
    if not NS.RootDB then NS.RootDB = NewRoot(profile) end
    NS.RootDB.profiles[name] = profile
    NS.DB = profile
    _G.MSUFSuiteSkinDB = NS.RootDB
    return profile
end
