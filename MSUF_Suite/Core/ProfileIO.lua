local _, Suite = ...
local IO = { prefix = "MSUFM1:", maxBytes = 2 * 1024 * 1024 }
Suite.ProfileIO = IO
local LEGACY_MINIMAP_KEYS = { enabled = "specButton", showSpec = "specShowSpec", showLoot = "specShowLoot",
    corner = "specCorner", size = "specSize", x = "specX", y = "specY" }

-- MSUF's codec (older MSUF builds do not export it). It runs on
-- C_EncodingUtil, which Retail and Forever both have.
local function CodecAvailable()
    return type(_G.MSUF_EncodeCompactTable) == "function"
        and type(_G.MSUF_TryDecodeCompactString) == "function"
end

-- A copy keeps the migration state of its source, so one-time migrations
-- never run again on already migrated values. Older data carries per-step
-- flags instead of a revision; those are copied as they are. A string may
-- claim any revision: it counts at most the steps this build knows, so a
-- step appended later still runs on it.
local function CopyMigrationState(source, target)
    local revision, flags = Suite.Suite.MigrationState(source)
    if revision then
        target.revision = math.min(revision, Suite.Suite.MigrationRevision)
    elseif flags then
        for key, value in pairs(flags) do target[key] = value end
    end
end

-- Character-bound settings (catalog rules marked personal: a character GUID,
-- that character's saved build, a typed note) return to defaults in an
-- export and in a shared import. A module's export choice
-- (spec.personalExport, off by default) keeps them in its exports; the
-- string then marks that module (envelope.characterBound), and a shared
-- import keeps them only for a marked module. The choice itself never
-- travels. keep: { [module id] = true } of modules whose values stay.
local function ResetPersonal(profile, keep)
    for id, settings in pairs(profile.suite.modules) do
        local spec = Suite.SuiteCatalog[id]
        if spec then
            local kept = keep and keep[id]
            for key, rule in pairs(spec.rules) do
                if rule.personal and settings[key] ~= nil and (not kept or key == spec.personalExport) then
                    settings[key] = rule.default
                end
            end
        end
    end
    return profile
end

-- The modules whose character-bound settings an export keeps: those whose
-- export choice is on, or every module with one when the caller asks
-- (options.characterBound). Returns nil when none.
local function KeptModules(profile, options)
    local keep
    for id, settings in pairs(profile.suite.modules) do
        local spec = Suite.SuiteCatalog[id]
        local choice = spec and spec.personalExport
        if choice and (settings[choice] == true or type(options) == "table" and options.characterBound == true) then
            keep = keep or {}
            keep[id] = true
        end
    end
    return keep
end

-- The marked modules of a string: only known modules with an export choice.
local function MarkedModules(marks)
    if type(marks) ~= "table" then return nil end
    local keep
    for id, marked in pairs(marks) do
        local spec = type(id) == "string" and Suite.SuiteCatalog[id]
        if marked == true and spec and spec.personalExport then
            keep = keep or {}
            keep[id] = true
        end
    end
    return keep
end

-- Copy only documented module settings. Runtime history, skin configuration,
-- unknown keys and sharing metadata cannot enter the module profile.
-- keep: modules whose character-bound settings a marked shared string keeps.
function IO.PrepareTable(profile, shared, keep)
    local data = type(profile) == "table" and profile.suite
    if type(data) ~= "table" or data.schema ~= 1 or type(data.modules) ~= "table" then
        return nil, "Unsupported suite profile"
    end
    local result = { suite = { schema = 1, modules = {} } }
    -- Only a look the Suite knows; an unknown name (or a shared string of any
    -- length) never enters the profile.
    if type(data.globalLook) == "string" and Suite.SuiteLooks.indexes[data.globalLook] then
        result.suite.globalLook = data.globalLook
    end
    CopyMigrationState(data, result.suite)
    -- Keep only the retired helper's documented settings until Normalize
    -- moves them to Minimap. Old full-profile exports must not lose them.
    local legacy = data.modules.mapQuickSwitch
    if legacy ~= nil then
        if type(legacy) ~= "table" then return nil, "Invalid module settings" end
        local target = {}
        for key, newKey in pairs(LEGACY_MINIMAP_KEYS) do
            local value = legacy[key]
            if value ~= nil then
                if type(value) ~= type(Suite.SuiteCatalog.minimap.rules[newKey].default) then
                    return nil, "Invalid module setting"
                end
                if type(value) == "number" and not Suite.Finite(value) then return nil, "Invalid module number" end
                target[key] = value
            end
        end
        result.suite.modules.mapQuickSwitch = target
    end
    for _, id in ipairs(Suite.SuiteOrder) do
        local source = data.modules[id]
        if source ~= nil and type(source) ~= "table" then return nil, "Invalid module settings" end
        local target = {}
        result.suite.modules[id] = target
        if source then
            local spec=Suite.SuiteCatalog[id]
            for key,value in pairs(source) do
                local rule=spec.rules[key]
                if rule then
                    if type(value) ~= type(rule.default) then return nil, "Invalid module setting" end
                    if type(value) == "number" and not Suite.Finite(value) then
                        return nil, "Invalid module number"
                    end
                    if type(value) == "string" and #value > rule.maxLength then
                        return nil, "Module setting is too long"
                    end
                    target[key] = value
                end
            end
            if spec.prepareConfig then spec.prepareConfig(target) end
        end
    end
    Suite.Suite.Normalize(result)
    if shared then
        Suite.Suite.SanitizeImport(result)
        ResetPersonal(result, keep)
    end
    return result
end

-- options.characterBound keeps every module's character-bound settings
-- (a caller's explicit export choice); otherwise each module's own choice.
function IO.ExportProfile(name, options)
    name=name or Suite.Database.GetActiveProfileName()
    local profile,why
    profile,why=Suite.ProfileVariants.BaseProfile(name)
    if not profile then return nil,why end
    local clean, reason = IO.PrepareTable(profile, false)
    if not clean then return nil, reason end
    if not CodecAvailable() then return nil, "Profile codec unavailable on this client" end
    local keep = KeptModules(clean, options)
    ResetPersonal(clean, keep)
    local encoded = _G.MSUF_EncodeCompactTable({ addon = "MSUF_Suite", format = 1, profile = clean,
        characterBound = keep }, "MSUF3")
    if type(encoded) ~= "string" or #encoded > IO.maxBytes then return nil, "Suite profile is too large" end
    return IO.prefix .. encoded
end

-- A module-only string carries one catalog entry and leaves every other Suite
-- module and all MSUF frame settings alone when imported. Its revision is the
-- migration state of the exported settings; strings without one migrate fully.
function IO.ExportModule(id, options)
    if not Suite.SuiteCatalog[id] then return nil, "Unknown suite module" end
    local name=Suite.Database.GetActiveProfileName()
    local profile,why
    profile,why=Suite.ProfileVariants.BaseProfile(name)
    if not profile then return nil,why end
    local clean, reason = IO.PrepareTable(profile, false)
    if not clean then return nil, reason end
    if not CodecAvailable() then return nil, "Profile codec unavailable on this client" end
    local keep = KeptModules(clean, options)
    ResetPersonal(clean, keep)
    local encoded = _G.MSUF_EncodeCompactTable({
        addon = "MSUF_Suite", format = 2, module = id, revision = clean.suite.revision,
        settings = clean.suite.modules[id], characterBound = keep and keep[id] or nil,
    }, "MSUF3")
    if type(encoded) ~= "string" or #encoded > IO.maxBytes then return nil, "Suite module profile is too large" end
    return "MSUFM2:" .. encoded
end

function IO.PrepareModuleProfile(text)
    if type(text) ~= "string" or #text > IO.maxBytes + 7 or text:sub(1, 7) ~= "MSUFM2:" then
        return nil, nil, "Invalid suite module profile"
    end
    if not CodecAvailable() then return nil, nil, "Profile codec unavailable on this client" end
    local encoded = text:sub(8)
    if encoded:sub(1, 6) ~= "MSUF3:" then return nil, nil, "Invalid suite module payload" end
    local envelope = _G.MSUF_TryDecodeCompactString(encoded)
    if type(envelope) ~= "table" or envelope.addon ~= "MSUF_Suite" or envelope.format ~= 2
        or type(envelope.module) ~= "string"
        or not (Suite.SuiteCatalog[envelope.module] or envelope.module == "mapQuickSwitch")
        or type(envelope.settings) ~= "table" then
        return nil, nil, "Unsupported suite module profile"
    end
    local id = envelope.module
    local revision = type(envelope.revision) == "number" and envelope.revision or nil
    local clean, reason = IO.PrepareTable({ suite = {
        schema = 1, revision = revision, modules = { [id] = envelope.settings },
    } }, true, MarkedModules({ [id] = envelope.characterBound }))
    if not clean then return nil, nil, reason end
    if id == "mapQuickSwitch" then
        -- A former helper-only export changes only the integrated button.
        -- It must not overwrite the user's map layout or module enable state.
        local settings = {}
        for _, key in pairs(LEGACY_MINIMAP_KEYS) do settings[key] = clean.suite.modules.minimap[key] end
        return "minimap", settings
    end
    return id, clean.suite.modules[id]
end

function IO.PrepareProfile(text, shared)
    if type(text) ~= "string" or #text > IO.maxBytes + #IO.prefix then return nil, "Invalid suite profile" end
    if text:sub(1, #IO.prefix) ~= IO.prefix then return nil, "Invalid suite profile prefix" end
    if not CodecAvailable() then return nil, "Profile codec unavailable on this client" end
    local encoded = text:sub(#IO.prefix + 1)
    if encoded:sub(1, 6) ~= "MSUF3:" then return nil, "Invalid suite profile payload" end
    local envelope = _G.MSUF_TryDecodeCompactString(encoded)
    if type(envelope) ~= "table" or envelope.addon ~= "MSUF_Suite" or envelope.format ~= 1 then
        return nil, "Unsupported suite profile"
    end
    return IO.PrepareTable(envelope.profile, shared ~= false, MarkedModules(envelope.characterBound))
end

-- Older development bundles embedded module settings in a MapkoSkin export.
-- Decode the documented envelope through MSUF's codec, then copy only modules.
-- No installed skin addon or access to its current database is needed.
function IO.PrepareLegacyProfile(text)
    if type(text) ~= "string" or #text > IO.maxBytes or text:sub(1, 7) ~= "MSKIN1:" then
        return nil, "Invalid legacy suite profile"
    end
    if not CodecAvailable() then return nil, "Profile codec unavailable on this client" end
    local envelope = _G.MSUF_TryDecodeCompactString("MSUF3:" .. text:sub(8))
    if type(envelope) ~= "table" or envelope.format ~= 1 or envelope.kind ~= "profile"
        or (envelope.addon ~= "MapkoSkin" and envelope.addon ~= "MidnightSkin") then
        return nil, "Unsupported legacy suite profile"
    end
    return IO.PrepareTable(envelope.payload, true)
end
