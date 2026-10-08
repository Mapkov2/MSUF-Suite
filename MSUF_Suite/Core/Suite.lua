local _, NS = ...
-- Every Core/Catalog file has loaded before this one (see the TOC order).
NS.FinalizeCatalog()
local S = { states = {}, instances = {}, catalog = NS.SuiteCatalog, order = NS.SuiteOrder, started = false }
NS.Suite = S
S.ApplyOwnedLayer = NS.ApplyOwnedLayer
S.ApplyOwnedChildLayer = NS.ApplyOwnedChildLayer
local pending, pendingFrame, pendingListening = {}, nil, false
local RUNTIME_ADDON = "MSUF_Suite_Modules"
-- Code that must not stop its caller runs isolated (NS.Dispatch): an error
-- reaches the client error handler and the caller goes on.
local Dispatch, Finish = NS.Dispatch, NS.Finish
for i = 1, #S.order do S.states[S.order[i]] = { active = false } end

------------------------------------------------------------------ setting rules
local function ValidText(rule, value)
    return #value <= rule.maxLength
        and not ((rule.spells or rule.items or rule.ids) and value:find("[^%d%s,]"))
        and not (rule.color and (#value ~= 6 or value:find("[^%x]")))
end

local Finite = NS.Finite

local function ClampNumber(rule, value)
    value = math.max(rule.min, math.min(rule.max, value))
    if rule.choices or rule.step == 1 then value = math.floor(value) end
    return value
end

-- Setters reject invalid input; stored profiles are repaired instead.
local function CheckedValue(rule, value)
    if not rule or type(value) ~= type(rule.default) then return nil, "Invalid setting" end
    if type(value) == "number" then
        if not Finite(value) then return nil, "Invalid number" end
        return ClampNumber(rule, value)
    end
    if type(value) == "string" and not ValidText(rule, value) then return nil, "Invalid setting text" end
    return value
end
S.CheckProfileValue = CheckedValue
local function RepairedValue(rule, value)
    if type(value) ~= type(rule.default) then value = rule.default end
    if type(value) == "number" then
        if not Finite(value) then value = rule.default end
        return ClampNumber(rule, value)
    end
    if type(value) == "string" then
        if #value > rule.maxLength then
            -- Cut at a character boundary, never inside a UTF-8 character.
            local edge = rule.maxLength + 1
            while edge > 1 and value:byte(edge) >= 128 and value:byte(edge) < 192 do edge = edge - 1 end
            value = value:sub(1, edge - 1)
        end
        if not ValidText(rule, value) then value = rule.default end
    end
    return value
end

------------------------------------------------------------------ saved data upgrades
-- Migrations rewrite values of an older build and must run exactly once.
-- Profiles record the number of migrations they have seen in suite.revision;
-- copies, exports and imports carry that number (see ProfileIO), so a copy is
-- never migrated again. Append new steps at the end; never reorder or remove
-- one. Profiles saved before suite.revision existed kept one flag per step
-- (legacy); such a profile runs exactly the steps its flags have not marked.
-- Repairs only fill settings an older format did not have. They are
-- idempotent and run at every normalization.
-- The step functions live in SuiteMigrations.lua.
local Steps = NS.SuiteMigrationSteps
local EnsureModule = Steps.EnsureModule
-- legacy: flag key of profiles saved before suite.revision; done: flag value
-- that marked the step as applied. forever: step applies only on WoW Forever.
local MIGRATIONS = {
    { run = Steps.ObjectivesTransparent, legacy = "objectivesTransparentRevision" },
    { run = Steps.HudTypography, legacy = "hudTypographyRevision" },
    { run = Steps.ExperienceBarTop, legacy = "xpTopRevision" },
    { run = Steps.ActionBarsCustomLook, legacy = "actionBarLookRevision" },
    { run = Steps.BagsCustomLook, legacy = "bagsLookRevision" },
    { run = Steps.LookRenumbering, legacy = "lookPresetRevision" },
    { run = Steps.ForeverHud, legacy = "foreverHudRevision", forever = true },
    { run = Steps.ForeverActionBars, legacy = "actionBarsDefaultRevision", done = 2, forever = true },
    { run = Steps.ForeverLayout, legacy = "layoutRevision", done = 2, forever = true },
    { run = Steps.ForeverPalette, legacy = "paletteRevision", forever = true },
    { run = Steps.JundiesNameplateSize },
    { run = Steps.JundiesNameplateMarkers },
    { run = Steps.NameplateCastVisibility },
    { run = Steps.JundiesNameplatePalette },
    { run = Steps.NameplateNativeCastOpacity },
    { run = Steps.FriendlyPlayerDisplay },
    { run = NS.CenterDefaultDataTexts },
    { run = NS.MigrateMinimapSpecialization },
    { run = NS.MigrateLootContainersWarbound },
    { run = NS.MigrateBagsInventoryView },
    { run = NS.MoveRunRecordsToCharacter },
    { run = Steps.RecordModuleLooks },
}
S.MigrationRevision = #MIGRATIONS
local REPAIRS = {
    Steps.AnnouncementsAnchor, Steps.AnnouncementsFactory, Steps.DataTextsBagButtons, Steps.SkyridingColors,
    Steps.ObjectivesCollapseState, NS.NameplateStyle.RepairGeometry,
}
-- The migration revision a copy of this suite table must keep (nil for a
-- table from before suite.revision) and the legacy flags it still carries:
-- all of them before suite.revision, those of the steps after its revision
-- when a legacy migration stopped at a step.
function S.MigrationState(db)
    if type(db) ~= "table" then return nil end
    local flags
    for _, step in ipairs(MIGRATIONS) do
        local value = step.legacy and db[step.legacy]
        if type(value) == "number" then
            flags = flags or {}
            flags[step.legacy] = value
        end
    end
    local revision = db.revision
    if type(revision) == "number" and revision == revision and revision >= 0 then
        return math.floor(revision), flags
    end
    return nil, flags
end

-- True when the step's legacy flag marks it as applied.
local function LegacyDone(db, step)
    return step.legacy ~= nil and (tonumber(db[step.legacy]) or 0) >= (step.done or 1)
end

local function StepPending(db, revision, index, step)
    if step.forever and not NS.Client.isForever then return false end
    if revision and index <= revision then return false end
    return not LegacyDone(db, step)
end

-- A step that raises (reported), or returns false because it cannot finish
-- yet, holds the revision before it: that step and the ones after it run
-- again at the next normalization. The revision covers the legacy flags up
-- to it; the flags after it stay, so a step they mark is not run again.
local function RunMigrations(db)
    local revision = S.MigrationState(db)
    local reached = #MIGRATIONS
    for index, step in ipairs(MIGRATIONS) do
        if StepPending(db, revision, index, step) then
            local finished, done = Dispatch(Finish, step.run, db.modules, db)
            if not finished or done == false then
                reached = index - 1
                break
            end
        end
    end
    db.revision = math.max(revision or 0, reached)
    for index, step in ipairs(MIGRATIONS) do
        if step.legacy and index <= db.revision then db[step.legacy] = nil end
    end
end
-- The pending migrations of a suite table (profile.suite) alone: imports run
-- them before only documented settings stay (ProfileIO.lua).
S.Migrate = RunMigrations

------------------------------------------------------------------ normalization
-- Idempotent: every module table exists and every rule holds a valid value.
-- A raising prepareConfig or look refresh is reported; the rules still
-- repair every value, so the module starts from a valid config.
local function ApplyCatalogRules(modules)
    Dispatch(NS.SuiteLooks.RefreshClassColor)
    for i = 1, #S.order do
        local id = S.order[i]
        local config, spec = EnsureModule(modules, id), S.catalog[id]
        if spec.prepareConfig then Dispatch(spec.prepareConfig, config) end
        for key, rule in pairs(spec.rules) do
            config[key] = RepairedValue(rule, config[key])
        end
        Dispatch(NS.SuiteLooks.RefreshConfig, id, config)
    end
end
-- Returns the suite table of a profile, or nil when a newer build owns it.
local function SuiteTable(profile)
    local db = profile.suite
    if type(db) ~= "table" then
        db = {}
        profile.suite = db
    end
    -- Preserve future-version data intact. Apply fails closed on its schema.
    if type(db.schema) == "number" and db.schema > 1 then return nil end
    db.schema = 1
    if type(db.modules) ~= "table" then db.modules = {} end
    if db.moduleState ~= nil and type(db.moduleState) ~= "table" then db.moduleState = nil end
    db.moduleLooks = NS.SuiteLooks.CleanRecords(db.moduleLooks)
    return db
end

function S.Normalize(profile)
    local db = SuiteTable(profile)
    if not db then return end
    RunMigrations(db)
    for i = 1, #REPAIRS do Dispatch(REPAIRS[i], db.modules, db) end
    ApplyCatalogRules(db.modules)
end

------------------------------------------------------------------ looks
-- The Skinning look is a deliberate suite-wide gesture. Keep the choice in
-- this profile so an optional module adopts it when it is enabled later.
-- Catalog entries describe their part in spec.look (see SuiteCatalog.lua).
local Looks = NS.SuiteLooks
local ApplyLookToConfig = Looks.ApplyToConfig

-- Enabling a module adopts the global look only while the module's record
-- (db.moduleLooks, see SuiteCatalog.lua) differs from it: the first enable,
-- or one after the global look changed while the module was off. A module
-- the player styled keeps its look through off and on.
local function AdoptLook(db, id, config)
    if not Looks.Supports(id) then return false end
    local records = Looks.Records(db)
    if records[id] == db.globalLook then return false end
    records[id] = db.globalLook
    return ApplyLookToConfig(id, config, db.globalLook)
end

-- An explicit appearance (a colour, the module's own look choice or one of
-- its visual settings) settles the module under the active global look.
local function AppearanceKey(spec, key)
    local rule, look = spec.rules[key], spec.look
    if key == "enabled" or not rule then return false end
    return (rule.color or look and (key == look.key or look.visualKeys and look.visualKeys[key])) and true or false
end
local function ExplicitAppearance(spec, values)
    for key in pairs(values) do
        if AppearanceKey(spec, key) then return true end
    end
    return false
end
local function KeepLook(db, id)
    if Looks.Supports(id) then Looks.Records(db)[id] = db.globalLook end
end

S.StyleProfile = Looks.StyleProfile

------------------------------------------------------------------ profile access
-- Sharing a visual setup never authorizes spending or automation: the
-- catalog's automation switches arrive off (SuiteCatalog.lua).
S.SanitizeImport = NS.SanitizeAutomation

local function ActiveSuite()
    local db = NS.DB and NS.DB.suite
    return db and db.schema == 1 and db or nil
end

-- The catalog defaults only fill in, never get handed out: a profile that
-- lacks a module's settings gets its own copy, and without an active profile
-- readers see a copy too, so no setter can write into the shared defaults.
local defaultsCopies = {}
function S.Config(id)
    local defaults = NS.Defaults.suite.modules[id]
    local db = ActiveSuite()
    local modules = db and db.modules
    if modules then
        local config = modules[id]
        if config ~= nil or not defaults then return config end
        config = NS.CopyValue(defaults)
        modules[id] = config
        return config
    end
    if not defaults then return nil end
    local copy = defaultsCopies[id]
    if not copy then
        copy = NS.CopyValue(defaults)
        defaultsCopies[id] = copy
    end
    return copy
end

-- Per-profile state a module keeps for itself (for example collapsed tracker
-- groups). It is not a setting: never exported, validated or offered in the
-- menu, and the module may change it at any time, also in combat.
function S.ModuleState(id)
    local db = ActiveSuite()
    if not db or not S.catalog[id] then return nil end
    if type(db.moduleState) ~= "table" then db.moduleState = {} end
    local state = db.moduleState[id]
    if type(state) ~= "table" then
        state = {}
        db.moduleState[id] = state
    end
    return state
end

function S.Availability(id)
    local spec = S.catalog[id]
    if not spec then return false, "Unknown module" end
    if NS.Client.flavor == "Unknown" then return false, "This client has not been identified" end
    local enabled, addonReason = NS.Client.AddOnEnabled(spec.addon)
    if not enabled then return false, addonReason end
    -- Each catalog entry may declare its own client requirement.
    if spec.available then
        local ok, why = spec.available()
        if not ok then return false, why or "Unavailable on this client" end
    end
    for i = 1, #spec.conflicts do
        local conflict = spec.conflicts[i]
        if NS.Client.IsAddOnLoaded(conflict) then return false, NS.FormatStatus("Managed by %s", conflict) end
    end
    return true
end

------------------------------------------------------------------ lifecycle
-- Module code runs isolated (Dispatch): an error reaches the client error
-- handler and stops only the module that raised it.
-- Statuses are English source text; the menu translates them once, when it
-- shows them (NS.StatusText through MSUF_Suite_Options/Menu/Bridge.lua).
local FAILED = "Stopped after an error"

-- Repaints the menu. A menu error is reported without failing the change
-- that was already applied.
-- NS.Options exists once the load-on-demand options addon has loaded.
local function Changed()
    local options = NS.Options
    if options then Dispatch(options.RefreshAll) end
end

-- Hands a module's saved CVars back. The load-on-demand runtime defines
-- S.RestoreSaved; before it loads, no module has saved a CVar this session.
local function RestoreCVars(id)
    if S.RestoreSaved then S.RestoreSaved(id) end
end

-- Every step runs isolated, so a raising Disable or release never skips the
-- steps after it, and the module's CVars are always handed back.
local function Stop(id)
    local state, instance = S.states[id], S.instances[id]
    state.active = false
    Dispatch(S.UnregisterEditElements, id)
    if instance then
        instance.active = false
        Dispatch(instance.Disable, instance)
        local context = instance.context
        if context then Dispatch(context.Release, context) end
    end
    RestoreCVars(id)
end

-- A failed module releases what it took and stays off until the player
-- changes one of its settings or the profile (both clear state.error).
local function Fail(id)
    local state, instance = S.states[id], S.instances[id]
    state.error = state.error or FAILED
    if state.active or (instance and instance.active) then Dispatch(Stop, id) end
end

-- Applies the modules queued in combat, in catalog order like S.ApplyAll.
-- S.Apply isolates each module; the listener stays until the queue is empty.
local function Flush(frame)
    if NS.IsCombatLocked() then return end
    local order = S.order
    for i = 1, #order do
        local id = order[i]
        if pending[id] then
            pending[id] = nil
            S.Apply(id)
        end
    end
    if pendingListening and not next(pending) then
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        pendingListening = false
    end
    Changed()
end

function S.Queue(id)
    if not S.catalog[id] then return end
    pending[id] = true
    if not pendingFrame then
        pendingFrame = CreateFrame("Frame")
        pendingFrame:SetScript("OnEvent", Flush)
    end
    if not pendingListening then
        pendingFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        pendingListening = true
    end
end

-- Loads the shared runtime and the module's addon. Returns false after
-- recording why the module could not register.
local function LoadInstance(id, state)
    local spec = S.catalog[id]
    local loaded, why
    if not NS.Client.IsAddOnLoaded(RUNTIME_ADDON) then loaded, why = C_AddOns.LoadAddOn(RUNTIME_ADDON) end
    -- A runtime that could not load leaves S.NewContext unset.
    if type(S.NewContext) == "function" then loaded, why = C_AddOns.LoadAddOn(spec.addon) end
    -- Some Forever builds return an empty/diagnostic result even after the
    -- addon ran. Successful registration is the authoritative outcome.
    if S.instances[id] then return true end
    if NS.Client.IsAddOnLoaded(spec.addon) then
        state.error = NS.FormatStatus("%s is missing from %s", NS.Text(spec.title), spec.addon)
    else
        local reason = NS.Client.LoadReasonText(why or loaded, NS.Text("not installed"))
        state.error = NS.FormatStatus("Cannot load %s: %s", spec.addon, reason)
    end
    return false
end

-- Blizzard surfaces a running module replaces or hides. The skin leaves them
-- to the module and styles Blizzard's original again once the module is off.
local SURFACE_MODULES = {
    damageMeter = "damageMeter", bagWindows = "bags",
    cooldownViewers = "cooldownManager", bagBar = "dataTexts", staticPopups = "popupAttention",
}
local SURFACE_OWNERS = {}
for _, id in pairs(SURFACE_MODULES) do SURFACE_OWNERS[id] = true end
-- True while the owning module is set to run: enabled in the active profile,
-- available on this client and not failed. It answers before S.Start too, so
-- the skin's first pass already leaves the surface alone.
function S.OwnsBlizzardSurface(surface)
    local id = SURFACE_MODULES[surface]
    if not id or not ActiveSuite() or S.states[id].error then return false end
    local config = S.Config(id)
    if config.enabled ~= true then return false end
    -- DataTexts hides the bag bar only on request.
    if surface == "bagBar" and config.hideBlizzardBagBar ~= true then return false end
    if surface == "staticPopups" and config.skin ~= true and config.dialogFont ~= true then return false end
    return S.Availability(id) == true
end

local function ApplyModule(id)
    local state, config = S.states[id], S.Config(id)
    local supported, reason = S.Availability(id)
    state.unavailable = not supported and reason or nil
    if not ActiveSuite() or not config.enabled or not supported or state.error then
        if state.active or (S.instances[id] and S.instances[id].active) then
            Stop(id)
        else
            RestoreCVars(id)
        end
        return
    end
    if not S.instances[id] and not LoadInstance(id, state) then return end
    local instance = S.instances[id]
    instance.config = config
    instance.active = true
    instance.context = instance.context or S.NewContext(id)
    -- A completed callback is required before publishing an active state.
    if state.active then instance:Refresh() else instance:Enable() end
    instance.context:RefreshOwnedSkins()
    state.active = true
    S.RefreshEditMover(id)
end

function S.Apply(id)
    if not S.started or not S.catalog[id] then return end
    if NS.IsCombatLocked() then
        S.Queue(id)
        return
    end
    pending[id] = nil
    if pendingListening and not next(pending) then
        pendingFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        pendingListening = false
    end
    -- The skin lets go of a surface before its module starts and takes it back
    -- after the module stopped, so neither side records the other's change as
    -- Blizzard's original.
    local surface = SURFACE_OWNERS[id]
    if surface then Dispatch(NS.Skin.SurfacesChanged, "before") end
    if not Dispatch(Finish, ApplyModule, id) then Fail(id) end
    if surface then Dispatch(NS.Skin.SurfacesChanged, "after") end
end

function S.ApplyAll()
    for i = 1, #S.order do S.Apply(S.order[i]) end
end

-- The public setters refuse from the start of combat: the client sends
-- PLAYER_REGEN_DISABLED while InCombatLockdown() is still false, and
-- NS.InCombat counts that dispatch as combat. S.Apply keeps its own
-- protected-write guard (lockdown), and S.CommitEditPosition is the one write
-- the combat start still accepts.
function S.ApplyGlobalLook(lookName)
    local db = ActiveSuite()
    if NS.InCombat() or not Looks.indexes[lookName] or not db then return false end
    db.globalLook = lookName
    for i = 1, #S.order do
        local id = S.order[i]
        local config = S.Config(id)
        if config.enabled then
            if Looks.Supports(id) then Looks.Records(db)[id] = lookName end
            if ApplyLookToConfig(id, config, lookName) then
                S.states[id].error = nil
                S.Apply(id)
            end
        end
    end
    Changed()
    return true
end

------------------------------------------------------------------ settings
function S.Set(id, key, value)
    if NS.InCombat() then return false, "Finish combat before editing the suite" end
    local db = ActiveSuite()
    if not db then return false, "Unsupported suite profile" end
    local reason
    value, reason = CheckedValue(S.catalog[id] and S.catalog[id].rules[key], value)
    if value == nil then return false, reason end
    local config, state = S.Config(id), S.states[id]
    if config[key] == value and not state.error and not state.unavailable then return true end
    config[key] = value
    if S.catalog[id].rules.classStyle and S.catalog[id].rules[key].color then config.classStyle = false end
    if key == "enabled" and value == true then
        AdoptLook(db, id, config)
    elseif AppearanceKey(S.catalog[id], key) then
        KeepLook(db, id)
    end
    state.error = nil
    S.Apply(id)
    Changed()
    return true
end

-- Checks every value against its rule before storing any: a batch is written
-- completely or not at all. Returns the config and the stored values, or nil
-- and why.
local function StoreValues(spec, id, values)
    local clean = {}
    for key, value in pairs(values) do
        local checked, reason = CheckedValue(spec.rules[key], value)
        if checked == nil then return nil, reason end
        clean[key] = checked
    end
    local config = S.Config(id)
    for key, value in pairs(clean) do config[key] = value end
    if spec.rules.classStyle and clean.classStyle == nil then
        for key in pairs(clean) do
            if spec.rules[key].color then
                config.classStyle = false
                break
            end
        end
    end
    return config, clean
end

local function SetMany(id, values)
    local db = ActiveSuite()
    if not db or type(values) ~= "table" then return false, "Invalid settings" end
    local spec = S.catalog[id]
    if not spec then return false, "Unknown module" end
    local config, clean = StoreValues(spec, id, values)
    if not config then return false, clean end
    -- A module import carries its own palette. The global look is only a
    -- default for a newly enabled module without explicit appearance data.
    if ExplicitAppearance(spec, clean) then
        KeepLook(db, id)
    elseif clean.enabled == true then
        AdoptLook(db, id, config)
    end
    Looks.RefreshClassColor()
    Looks.RefreshConfig(id, config)
    S.states[id].error = nil
    S.Apply(id)
    Changed()
    return true
end

function S.SetMany(id, values)
    if NS.InCombat() then return false, "Finish combat before editing the suite" end
    return SetMany(id, values)
end

-- MSUF Edit Mode commits a drag the player still holds when Edit Mode closes
-- for combat, inside PLAYER_REGEN_DISABLED and before lockdown, and gives a
-- refused commit its start state back (MSUF_Suite_Modules/EditMode.lua:
-- movePosition's commit and restoreState). Only lockdown refuses these
-- writes; the public setters refuse from the combat start.
function S.CommitEditPosition(id, values)
    if NS.IsCombatLocked() then return false, "Finish combat before editing the suite" end
    return SetMany(id, values)
end

-- Section resets restore only their owned keys. Enabling a module through the
-- normal setter applies the active look to unrelated appearance settings;
-- that behavior is intentionally skipped for a scoped reset.
function S.ResetKeys(id, values)
    if NS.InCombat() then return false, "Finish combat before editing the suite" end
    local db = ActiveSuite()
    local spec = S.catalog[id]
    if not db or not spec or type(values) ~= "table" then return false, "Invalid settings" end
    local config, reason = StoreValues(spec, id, values)
    if not config then return false, reason end
    S.states[id].error = nil
    S.Apply(id)
    Changed()
    return true
end

function S.Reset(id)
    local db = ActiveSuite()
    if NS.InCombat() or not S.catalog[id] or not db then return false end
    db.modules[id] = NS.CopyValue(NS.Defaults.suite.modules[id])
    if type(db.moduleLooks) == "table" then db.moduleLooks[id] = nil end
    local config = S.Config(id)
    if id == "cooldownManager" then config.defaultsVersion = NS.CDM.DEFAULTS_VERSION end
    if config.enabled then AdoptLook(db, id, config) end
    S.states[id].error = nil
    S.Apply(id)
    Changed()
    return true
end

-- "core" enables available core modules; "off" disables every module. Setup
-- never enables spending or automation: opt-in modules keep their own choice.
function S.Preset(kind)
    local db = ActiveSuite()
    if NS.InCombat() or not db then return false end
    if kind ~= "core" and kind ~= "off" then return false end
    for i = 1, #S.order do
        local id = S.order[i]
        if S.catalog[id].core or kind == "off" then
            local config = S.Config(id)
            config.enabled = kind == "core" and S.Availability(id) == true
            if config.enabled then AdoptLook(db, id, config) end
            S.states[id].error = nil
        end
    end
    S.ApplyAll()
    Changed()
    return true
end

-- A profile switch starts every module afresh: a module stopped after an
-- error in the previous profile is tried again with the new settings.
local function ApplyProfile(_, domain)
    if domain ~= "profile" then return end
    if NS.DB then Dispatch(S.Normalize, NS.DB) end
    for i = 1, #S.order do S.states[S.order[i]].error = nil end
    S.ApplyAll()
end

function S.Start()
    if S.started then return end
    S.started = true
    -- Normalization never keeps the listener or the modules from starting.
    if NS.DB then Dispatch(S.Normalize, NS.DB) end
    -- Saved CVars wait in the runtime until their owner hands them back.
    if NS.RootDB and type(NS.RootDB.suiteRecovery) == "table" and next(NS.RootDB.suiteRecovery) then
        C_AddOns.LoadAddOn(RUNTIME_ADDON)
    end
    NS.Registry.AddListener(S, ApplyProfile)
    S.ApplyAll()
end

function S.Status(id)
    local state = S.states[id]
    if state.error then return state.error end
    if pending[id] then return "Waiting for combat to end" end
    -- Modules set a specific message when Blizzard frames return only on reload.
    if state.reloadRequired then
        return type(state.reloadRequired) == "string" and state.reloadRequired
            or "Reload the UI to finish this change"
    end
    if state.unavailable then return state.unavailable end
    return state.active and "Active" or "Off"
end

function S.Open(id)
    local spec = type(id) == "string" and S.catalog[id]
    local page = spec and (spec.page or ("suite_" .. id)) or "home"
    if NS.Menu.Open(page, spec and id) then return true end
    NS.Print(NS.Text("Open the MSUF menu to find the Suite pages. MSUF must be installed and enabled."))
    return false
end

SLASH_MSUFSUITE1 = "/msuite"
SlashCmdList.MSUFSUITE = function() S.Open() end
