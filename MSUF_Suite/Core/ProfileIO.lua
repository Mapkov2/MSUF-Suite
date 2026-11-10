local _, Suite = ...
-- MSUF's profile string box holds 200,000 characters (Menu2 W.TextInput), so
-- a longer export could never be pasted back (it also stays below MSUF's
-- 192 KiB decode cap). Imports keep maxBytes.
local IO = { prefix = "MSUFM1:", modulePrefix = "MSUFM2:", maxBytes = 2 * 1024 * 1024, maxExportBytes = 200000 }
Suite.ProfileIO = IO
local NAMEPLATES = "nameplates"

-- Array CVars carry Blizzard's version byte and six-bit data bytes. Keep
-- their raw representation, including flags that the Suite does not edit.
local NAMEPLATE_ARRAY_CVARS = {
    nameplateStackingTypes = true, nameplateSimplifiedTypes = true, nameplateInfoDisplay = true,
    nameplateCastBarDisplay = true, nameplateThreatDisplay = true, nameplateEnemyNpcAuraDisplay = true,
    nameplateEnemyPlayerAuraDisplay = true, nameplateFriendlyPlayerAuraDisplay = true,
}

local function NativeValue(key, value)
    if not Suite.Public(value) or type(value) ~= "string" or #value >= 64 then return nil end
    if NAMEPLATE_ARRAY_CVARS[key] then
        if value:match("^.[\64-\127]*$") then return value end
    elseif Suite.Finite(tonumber(value)) then
        return value
    end
end

local function CleanNameplateCVars(values)
    if type(values) ~= "table" then return nil end
    local spec = Suite.SuiteCatalog[NAMEPLATES]
    local clean = {}
    for key, value in pairs(values) do
        if spec.cvars[key] or spec.nativeProfileCVars[key] then clean[key] = NativeValue(key, value) end
    end
    return next(clean) and clean or nil
end

local function ReadNameplateCVar(key)
    local value = C_CVar.GetCVar(key)
    local readBaseline = Suite.Suite.CVarBaseline
    if readBaseline then return readBaseline(NAMEPLATES, key, value) end
    if Suite.Public(value) then return value end
end

function IO.CaptureNameplateCVars()
    local spec = Suite.SuiteCatalog[NAMEPLATES]
    local values = {}
    for key in pairs(spec.cvars) do values[key] = NativeValue(key, ReadNameplateCVar(key)) end
    for key in pairs(spec.nativeProfileCVars) do values[key] = NativeValue(key, C_CVar.GetCVar(key)) end
    return next(values) and values or nil
end

local function NativeEqual(left, right)
    if not Suite.Public(left) then return false end
    if left == right then return true end
    local a, b = tonumber(left), tonumber(right)
    return a ~= nil and b ~= nil and a == b
end

local function ResetNameplateBaseline()
    local runtime = Suite.Suite
    if runtime.RestoreSaved then runtime.RestoreSaved(NAMEPLATES) end
    local instance = runtime.instances[NAMEPLATES]
    if instance and instance.active then instance:ResetCVarBaseline() end
end

local function WriteNameplateValues(values)
    ResetNameplateBaseline()
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local value = values[key]
        if not NativeEqual(C_CVar.GetCVar(key), value) then
            C_CVar.SetCVar(key, value)
            if not NativeEqual(C_CVar.GetCVar(key), value) then
                return false, "Blizzard rejected a nameplate setting", key
            end
        end
    end
    Suite.Suite.Apply(NAMEPLATES)
    return true
end

-- Read back the native values before the skin reapplies its own overrides.
-- A rejected setter and a raising setter both restore the previous baseline.
function IO.ApplyNameplateCVars(values, transition)
    if not values then return true end
    if Suite.InCombat(transition) or Suite.IsCombatLocked() then return false, "Finish combat before importing" end
    values = CleanNameplateCVars(values)
    if not values then return true end
    local changes = {}
    local report = { applied = {}, skipped = {}, unchanged = 0 }
    for key, value in pairs(values) do
        local current = ReadNameplateCVar(key)
        if current == nil then
            report.skipped[key] = "Unavailable on this client"
        elseif NAMEPLATE_ARRAY_CVARS[key] and current:byte(1) ~= value:byte(1) then
            report.skipped[key] = "Different Blizzard setting version"
        elseif not NativeEqual(current, value) then
            changes[key] = value
            report.applied[#report.applied + 1] = key
        else
            report.unchanged = report.unchanged + 1
        end
    end
    table.sort(report.applied)
    if not next(changes) then
        IO.lastNameplateReport = report
        return true, nil, report
    end
    local before = IO.CaptureNameplateCVars()
    local ran, ok, reason, key = Suite.Dispatch(Suite.Finish, WriteNameplateValues, changes)
    if not ran or not ok then
        local restored, restoreOK = Suite.Dispatch(Suite.Finish, WriteNameplateValues, before or {})
        report.failed, report.rollbackFailed = key, not restored or not restoreOK
        IO.lastNameplateReport = report
        if report.rollbackFailed then return false, "Nameplate restore failed; restore the previous settings", report end
        return false, reason or "Nameplate settings could not be applied", report
    end
    IO.lastNameplateReport = report
    return true, nil, report
end

function IO.ReportNameplateImport()
    local report = IO.lastNameplateReport
    if not report or report.reported then return end
    report.reported = true
    local lines = {}
    for key, reason in pairs(report.skipped or {}) do lines[#lines + 1] = key .. " - " .. Suite.Text(reason) end
    for _, reason in pairs(report.skippedShared or {}) do lines[#lines + 1] = Suite.Text(reason) end
    table.sort(lines)
    for _, line in ipairs(lines) do Suite.Dispatch(Suite.Print, line) end
end

function IO.NameplateSnapshot(stored)
    local values = CleanNameplateCVars(stored) or {}
    for key, value in pairs(IO.CaptureNameplateCVars() or {}) do values[key] = value end
    return next(values) and values or nil
end

function IO.RememberNameplateCVars(profile, imported)
    profile = profile or Suite.DB
    if not profile then return end
    local values = CleanNameplateCVars(profile.nameplateCVars) or {}
    for key, value in pairs(CleanNameplateCVars(imported) or {}) do values[key] = value end
    profile.nameplateCVars = IO.NameplateSnapshot(values)
end

function IO.DefaultNameplateCVars()
    local values, spec = {}, Suite.SuiteCatalog[NAMEPLATES]
    for key in pairs(spec.cvars) do
        if NativeValue(key, C_CVar.GetCVar(key)) then values[key] = NativeValue(key, C_CVar.GetCVarDefault(key)) end
    end
    for key in pairs(spec.nativeProfileCVars) do
        if NativeValue(key, C_CVar.GetCVar(key)) then values[key] = NativeValue(key, C_CVar.GetCVarDefault(key)) end
    end
    return values
end

function IO.CaptureNameplateShared(name)
    name = name or Suite.Database.GetActiveProfileName()
    local shared, _, snapshot = Suite.HostBridge.CaptureNameplateSettings(name)
    local profile = Suite.Database.GetProfile(name)
    local stored = Suite.NameplateHostSettings.Capture(profile and profile.nameplateShared)
    if not shared and stored then shared = Suite.CopyValue(stored) end
    if stored and stored.nameplates and next(stored.nameplates) and stored.nameplates.fontOverride ~= false
        and not Suite.HostBridge.HasNameplateFontSettings() then
        shared = shared or { version = 1 }
        shared.nameplates = Suite.HostBridge.ResolveNameplateTypography(stored.nameplates, name)
            or Suite.CopyValue(stored.nameplates)
    end
    return shared, snapshot
end

function IO.CaptureNameplateUndo()
    local shared, exact = IO.CaptureNameplateShared()
    if not exact then return shared end
    if not Suite.HostBridge.HasNameplateFontSettings() then
        local stored = Suite.NameplateHostSettings.Capture(Suite.DB and Suite.DB.nameplateShared)
        exact.nameplates = stored and stored.nameplates or {}
        local clear = {}
        for _, path in ipairs(exact.clear or {}) do
            if path:sub(1, 8) == "general." then clear[#clear + 1] = path end
        end
        exact.clear = clear
        for _, key in ipairs(Suite.NameplateHostSettings.Keys("nameplates")) do
            if exact.nameplates[key] == nil then exact.clear[#exact.clear + 1] = "nameplates." .. key end
        end
    end
    return exact
end

function IO.MergeNameplateShared(stored, shared)
    stored = Suite.NameplateHostSettings.Capture(stored) or { version = 1 }
    local clear = {}
    for _, path in ipairs(stored.clear or {}) do clear[path] = true end
    for _, section in ipairs({ "general", "nameplates" }) do
        if shared[section] then
            stored[section] = stored[section] or {}
            for key, value in pairs(shared[section]) do
                stored[section][key] = Suite.CopyValue(value)
                clear[section .. "." .. key] = nil
            end
        end
    end
    for _, path in ipairs(shared.clear or {}) do
        local section, key = path:match("^(%a+)%.(%w+)$")
        if stored[section] then stored[section][key] = nil end
        clear[path] = true
    end
    stored.clear = {}
    for path in pairs(clear) do stored.clear[#stored.clear + 1] = path end
    table.sort(stored.clear)
    if #stored.clear == 0 then stored.clear = nil end
    return stored
end

function IO.ApplyNameplateShared(shared, transition)
    if not shared then return true end
    shared = Suite.NameplateHostSettings.Normalize(shared)
    if not shared then return false, "Invalid nameplate settings" end
    local sections = {}
    for _, section in ipairs({ "general", "nameplates" }) do
        if shared[section] then sections[section] = true end
    end
    for _, path in ipairs(shared.clear or {}) do sections[path:match("^(%a+)%.")] = true end
    local pending = Suite.DB.nameplateSharedPending
    pending = type(pending) == "table" and Suite.CopyValue(pending) or (pending and { general = true, nameplates = true } or {})
    local ok, result = Suite.HostBridge.ApplyNameplateSettings(shared, transition)
    if not ok and result == "unavailable" then
        IO.lastNameplateReport = IO.lastNameplateReport or { applied = {}, skipped = {}, unchanged = 0 }
        if sections.general then
            IO.lastNameplateReport.skippedShared = { general = "Update MSUF Core to apply imported interrupt settings." }
        end
        for section in pairs(sections) do pending[section] = true end
        ok = true
    elseif ok then
        for section in pairs(sections) do
            pending[section] = section == "nameplates" and type(result) == "table" and result.fontFallback or nil
        end
    end
    if not ok then return false, "Nameplate text or interrupt settings could not be applied" end
    Suite.DB.nameplateSharedPending = next(pending) and pending or nil
    Suite.DB.nameplateShared = IO.MergeNameplateShared(Suite.DB.nameplateShared, shared)
    Suite.Suite.Apply(NAMEPLATES)
    return true, result
end

function IO.ActivateNameplateCVars(profile, force, transition)
    local settings = profile.suite and profile.suite.modules and profile.suite.modules[NAMEPLATES]
    if not force and settings and settings.nativeProfileMode == 2 then return true end
    return IO.ApplyNameplateCVars(profile.nameplateCVars, transition)
end

-- Only explicitly imported pending sections replay after the host gains a
-- capability. Ordinary profile switches use the Core profile's own settings.
function IO.ActivateNameplatePending(profile, transition)
    local pending = profile.nameplateSharedPending
    if not pending or not Suite.HostBridge.HasNameplateSettings() then return true end
    local shared = Suite.NameplateHostSettings.Capture(profile.nameplateShared)
    if not shared then return true end
    local selected = {}
    for _, section in ipairs({ "general", "nameplates" }) do
        local ready = section == "general" or Suite.HostBridge.HasNameplateFontSettings()
        selected[section] = ready and (type(pending) ~= "table" or pending[section])
        if not selected[section] then shared[section] = nil end
    end
    local clear = {}
    for _, path in ipairs(shared.clear or {}) do
        if selected[path:match("^(%a+)%.")] then clear[#clear + 1] = path end
    end
    shared.clear = #clear > 0 and clear or nil
    if not shared.general and not shared.nameplates and not shared.clear then return true end
    return IO.ApplyNameplateShared(shared, transition)
end

function IO.ActivateNameplateProfile(profile, force, transition)
    if not profile.nameplateSharedPending or not Suite.HostBridge.HasNameplateSettings() then
        return IO.ActivateNameplateCVars(profile, force, transition)
    end
    local native, shared = IO.CaptureNameplateCVars(), IO.CaptureNameplateUndo()
    local stored, pending = Suite.CopyValue(profile.nameplateShared), Suite.CopyValue(profile.nameplateSharedPending)
    local ok, reason = IO.ActivateNameplateCVars(profile, force, transition)
    if not ok then return false, reason end
    local ran
    ran, ok, reason = Suite.Dispatch(Suite.Finish, IO.ActivateNameplatePending, profile, transition)
    if ran and ok then return true end
    local hostRan, hostOK = Suite.Dispatch(Suite.Finish, Suite.HostBridge.ApplyNameplateSettings, shared, transition)
    local nativeRan, nativeOK = Suite.Dispatch(Suite.Finish, IO.ApplyNameplateCVars, native, transition)
    profile.nameplateShared, profile.nameplateSharedPending = stored, pending
    if not hostRan or not hostOK or not nativeRan or not nativeOK then
        return false, "Nameplate restore failed; restore the previous settings"
    end
    return false, reason or "Nameplate settings could not be applied"
end

local nameplateSaveFrame, pendingNameplateStartup
function IO.StartNameplateProfile(transition)
    local profile = Suite.DB
    if not profile then return true end
    if not nameplateSaveFrame then
        nameplateSaveFrame = CreateFrame("Frame")
        nameplateSaveFrame:RegisterEvent("PLAYER_LOGOUT")
        nameplateSaveFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_LOGOUT" then
                -- A combat reload has not applied its stored baseline yet.
                if pendingNameplateStartup ~= Suite.DB then IO.RememberNameplateCVars() end
            elseif pendingNameplateStartup then
                local ran, ok, reason = Suite.Dispatch(Suite.Finish, IO.StartNameplateProfile, event)
                if not ran or not ok then Suite.Dispatch(Suite.Print, reason or "Nameplate settings could not be applied") end
            end
        end)
    end
    if Suite.InCombat(transition) or Suite.IsCombatLocked() then
        pendingNameplateStartup = profile
        nameplateSaveFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return true
    end
    local ok, reason = IO.ActivateNameplateProfile(profile, nil, transition)
    if not ok then return false, reason end
    pendingNameplateStartup = nil
    nameplateSaveFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    IO.RememberNameplateCVars(profile)
    return true
end

local LEGACY_MINIMAP_KEYS = { enabled = "specButton", showSpec = "specShowSpec", showLoot = "specShowLoot",
    corner = "specCorner", size = "specSize", x = "specX", y = "specY" }

-- MSUF's codec (older MSUF builds do not export it). It runs on
-- C_EncodingUtil, which Retail and Forever both have.
local function CodecAvailable()
    return type(_G.MSUF_EncodeCompactTable) == "function"
        and type(_G.MSUF_TryDecodeCompactString) == "function"
end

local function EncodeCompact(value)
    return _G.MSUF_EncodeCompactTable(value, "MSUF3")
end

-- A copy keeps the migration state of its source, so one-time migrations
-- never run again on already migrated values. Older data carries per-step
-- flags instead of a revision (or after it, when its legacy migration
-- stopped at a step); those are copied as they are. A string may claim any
-- revision: it counts at most the steps this build knows, so a step
-- appended later still runs on it.
local function CopyMigrationState(source, target)
    local revision, flags = Suite.Suite.MigrationState(source)
    if revision then
        target.revision = math.min(revision, Suite.Suite.MigrationRevision)
    end
    if flags then
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
-- current (optional): the module settings of the profile an import goes
-- into; that profile keeps its own values instead of the defaults.
local function ResetPersonal(profile, keep, current)
    for id, settings in pairs(profile.suite.modules) do
        local spec = Suite.SuiteCatalog[id]
        if spec then
            local kept, own = keep and keep[id], current and current[id]
            for key, rule in pairs(spec.rules) do
                if rule.personal and settings[key] ~= nil and (not kept or key == spec.personalExport) then
                    settings[key] = rule.default
                    if own and own[key] ~= nil then settings[key] = own[key] end
                end
            end
        end
    end
    return profile
end

-- A prepared shared profile imported into an existing one: its modules keep
-- that profile's character-bound settings, as a module import does
-- (PrepareModuleProfile leaves them out), except where the string marked them.
function IO.KeepPersonal(profile, current, keep)
    return ResetPersonal(profile, keep, current)
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

-- A plain value an older string may carry under a key the catalog has
-- retired since. It stays only until the migrations, which may read it, ran.
local RETIRED_TEXT_BYTES = 256
local function PlainValue(value)
    local kind = type(value)
    return kind == "boolean" or kind == "number" and Suite.Finite(value)
        or kind == "string" and #value <= RETIRED_TEXT_BYTES
end

-- One module's settings: every documented setting with its type checked,
-- and the plain values of retired keys. nil and why for a malformed setting.
local function CopySettings(spec, source)
    local target = {}
    for key, value in pairs(source) do
        local rule = spec.rules[key]
        if rule then
            if type(value) ~= type(rule.default) then return nil, "Invalid module setting" end
            if type(value) == "number" and not Suite.Finite(value) then return nil, "Invalid module number" end
            if type(value) == "string" and #value > rule.maxLength then return nil, "Module setting is too long" end
            target[key] = value
        elseif type(key) == "string" and PlainValue(value) then
            target[key] = value
        end
    end
    return target
end

local function DropRetired(spec, settings)
    for key in pairs(settings) do
        if not spec.rules[key] then settings[key] = nil end
    end
end

-- Copy only documented module settings. Runtime history, skin configuration,
-- unknown keys and sharing metadata cannot enter the module profile. The
-- migrations run first: a step may read a key the catalog has retired since
-- the string was made.
-- keep: modules whose character-bound settings a marked shared string keeps.
function IO.PrepareTable(profile, shared, keep)
    local data = type(profile) == "table" and profile.suite
    if type(data) ~= "table" or data.schema ~= 1 or type(data.modules) ~= "table" then
        return nil, "Unsupported suite profile"
    end
    local hostSettings, sharedWhy = Suite.HostBridge.NormalizeNameplateSettings(profile.nameplateShared)
    if sharedWhy then return nil, "Invalid nameplate text or interrupt settings" end
    local result = { suite = { schema = 1, modules = {} },
        nameplateCVars = CleanNameplateCVars(profile.nameplateCVars), nameplateShared = hostSettings }
    -- Only a look the Suite knows; an unknown name (or a shared string of any
    -- length) never enters the profile.
    if type(data.globalLook) == "string" and Suite.SuiteLooks.indexes[data.globalLook] then
        result.suite.globalLook = data.globalLook
    end
    -- Which looks the modules' appearance already answered (SuiteCatalog.lua):
    -- known modules and looks only.
    result.suite.moduleLooks = Suite.SuiteLooks.CleanRecords(data.moduleLooks)
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
    local modules = result.suite.modules
    for _, id in ipairs(Suite.SuiteOrder) do
        local source = data.modules[id]
        if source ~= nil and type(source) ~= "table" then return nil, "Invalid module settings" end
        local target, why = {}, nil
        if source then
            target, why = CopySettings(Suite.SuiteCatalog[id], source)
            if not target then return nil, why end
        end
        modules[id] = target
    end
    Suite.Suite.Migrate(result.suite)
    for _, id in ipairs(Suite.SuiteOrder) do
        local spec = Suite.SuiteCatalog[id]
        DropRetired(spec, modules[id])
        if data.modules[id] and spec.prepareConfig then spec.prepareConfig(modules[id]) end
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
    if name == Suite.Database.GetActiveProfileName() then clean.nameplateCVars = IO.NameplateSnapshot(clean.nameplateCVars) end
    clean.nameplateShared = IO.CaptureNameplateShared(name)
    local encoded = EncodeCompact({ addon = "MSUF_Suite", format = 1, profile = clean,
        characterBound = keep })
    if type(encoded) ~= "string" or #IO.prefix + #encoded > IO.maxExportBytes then return nil, "Suite profile is too large" end
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
    local selected = id == NAMEPLATES and Suite.NameplateProfiles.Selection(options) or nil
    local settings, native, shared = clean.suite.modules[id]
    if id == NAMEPLATES then
        settings = Suite.NameplateProfiles.FilterSettings(settings, selected)
        native = (not selected or selected.blizzard) and IO.NameplateSnapshot(clean.nameplateCVars) or nil
        shared = Suite.NameplateProfiles.FilterShared(IO.CaptureNameplateShared(), selected)
    end
    local encoded = EncodeCompact({
        addon = "MSUF_Suite", format = 2, module = id, revision = clean.suite.revision,
        settings = settings, characterBound = keep and keep[id] or nil,
        nameplateCVars = native, nameplateShared = shared, nameplateSections = selected,
    })
    if type(encoded) ~= "string" or #IO.modulePrefix + #encoded > IO.maxExportBytes then
        return nil, "Suite module profile is too large"
    end
    return IO.modulePrefix .. encoded
end

function IO.EncodeNameplateProfile(settings, native, shared, options)
    if not CodecAvailable() then return nil, "Profile codec unavailable on this client" end
    local selected = Suite.NameplateProfiles.Selection(options)
    local profile, reason = IO.PrepareTable({ suite = { schema = 1,
        revision = Suite.Suite.MigrationRevision, modules = { [NAMEPLATES] = settings } },
        nameplateCVars = native, nameplateShared = shared }, false)
    if not profile then return nil, reason end
    local encoded = EncodeCompact({ addon = "MSUF_Suite", format = 2, module = NAMEPLATES,
        revision = profile.suite.revision,
        settings = Suite.NameplateProfiles.FilterSettings(profile.suite.modules[NAMEPLATES], selected),
        nameplateCVars = (not selected or selected.blizzard) and profile.nameplateCVars or nil,
        nameplateShared = Suite.NameplateProfiles.FilterShared(profile.nameplateShared, selected),
        nameplateSections = selected,
    })
    if type(encoded) ~= "string" or #IO.modulePrefix + #encoded > IO.maxExportBytes then
        return nil, "Suite module profile is too large"
    end
    return IO.modulePrefix .. encoded
end

function IO.PrepareModuleProfile(text, preservePersonal)
    local prefix = IO.modulePrefix
    -- MSUF matches ^%s* and passes the pasted text as it is.
    text = type(text) == "string" and #text <= IO.maxBytes + #prefix and text:match("^%s*(.-)%s*$")
    if not text or text:sub(1, #prefix) ~= prefix then
        return nil, nil, "Invalid suite module profile"
    end
    if not CodecAvailable() then return nil, nil, "Profile codec unavailable on this client" end
    local encoded = text:sub(#prefix + 1)
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
    local settings, spec = clean.suite.modules[id], Suite.SuiteCatalog[id]
    for key, rule in pairs(spec.rules) do
        if preservePersonal and rule.personal and (envelope.characterBound ~= true or key == spec.personalExport) then settings[key] = nil end
    end
    -- Old Daily UI comforts exports carried both the interface and chat choices.
    if id == "dailyComfort" then
        local chat = {}
        for key, rule in pairs(Suite.SuiteCatalog.chatComfort.rules) do
            if key ~= "enabled" and not rule.personal and envelope.settings[key] ~= nil then
                chat[key] = clean.suite.modules.chatComfort[key]
            end
        end
        if next(chat) then return id, settings, nil, chat end
    end
    local native, shared, selected
    if id == NAMEPLATES then
        native = CleanNameplateCVars(envelope.nameplateCVars)
        local why
        shared, why = Suite.HostBridge.NormalizeNameplateSettings(envelope.nameplateShared)
        if why then return nil, nil, "Invalid nameplate text or interrupt settings" end
        if envelope.nameplateSections ~= nil and type(envelope.nameplateSections) ~= "table" then
            return nil, nil, "Invalid nameplate import selection"
        end
        selected = Suite.NameplateProfiles.Selection({ nameplateSections = envelope.nameplateSections })
        settings = Suite.NameplateProfiles.FilterSettings(settings, selected)
        shared = Suite.NameplateProfiles.FilterShared(shared, selected)
        if selected and not selected.blizzard then native = nil end
    end
    return id, settings, nil, nil, native, shared, selected
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
    -- The marks go back too, for an import into an existing profile (KeepPersonal).
    local keep = MarkedModules(envelope.characterBound)
    local profile, why = IO.PrepareTable(envelope.profile, shared ~= false, keep)
    return profile, why, keep
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
