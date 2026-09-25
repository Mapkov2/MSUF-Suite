local _, NS = ...
-- Every Core/Catalog file has loaded before this one (see the TOC order).
NS.FinalizeCatalog()
local S = { states = {}, instances = {}, catalog = NS.SuiteCatalog, order = NS.SuiteOrder, started = false }
NS.Suite = S
local pending, pendingFrame, pendingListening = {}, nil, false
local RUNTIME_ADDON = "MSUF_Suite_Modules"
for i = 1, #S.order do S.states[S.order[i]] = { active = false } end

------------------------------------------------------------------ setting rules
local function ValidText(rule, value)
    return #value <= rule.maxLength
        and not ((rule.spells or rule.items or rule.ids) and value:find("[^%d%s,]"))
        and not (rule.color and (#value ~= 6 or value:find("[^%x]")))
end

local function Finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

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

local function RepairedValue(rule, value)
    if type(value) ~= type(rule.default) then value = rule.default end
    if type(value) == "number" then
        if not Finite(value) then value = rule.default end
        return ClampNumber(rule, value)
    end
    if type(value) == "string" then
        value = value:sub(1, rule.maxLength)
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
local function Module(modules, id)
    local config = modules[id]
    return type(config) == "table" and config or nil
end

local function EnsureModule(modules, id)
    local config = Module(modules, id)
    if not config then
        config = {}
        modules[id] = config
    end
    return config
end

local function HasSettings(config)
    return config ~= nil and next(config) ~= nil
end

local function ObjectivesTransparent(modules)
    -- The original tracker factory used an opaque card; its exact standard
    -- value moves to the transparent HUD look.
    local objectives = Module(modules, "objectives")
    if objectives and objectives.backgroundOpacity == 82
        and (objectives.colorStyle == nil or objectives.colorStyle == 1) then
        objectives.backgroundOpacity = 0
    end
end

local function HudTypography(modules)
    -- Grow only the previous HUD factory text sizes. Different user choices stay.
    local objectives = Module(modules, "objectives")
    if objectives then
        local title, section = objectives.titleSize, objectives.sectionSize
        if title == nil or title == 16 or title == 17 then objectives.titleSize = 18 end
        if section == nil or section == 10 or section == 16 then objectives.sectionSize = 14 end
        if objectives.entrySize == nil or objectives.entrySize == 13 then objectives.entrySize = 15 end
        if objectives.objectiveSize == nil or objectives.objectiveSize == 11 then objectives.objectiveSize = 13 end
    end
    local announcements = Module(modules, "announcements")
    if announcements and (announcements.subtitleSize == nil or announcements.subtitleSize == 15) then
        announcements.subtitleSize = 16
    end
end

local function ExperienceBarTop(modules)
    -- The former Suite and Forever XP factory positions were at the bottom of
    -- the screen. Move only those known positions to the top center.
    local xp = Module(modules, "xpBar")
    if xp and (xp.point == nil or xp.point == 8)
        and (xp.x == nil or xp.x == 0 or xp.x == 12)
        and (xp.y == nil or xp.y == 148 or xp.y == 1040) then
        xp.point, xp.x, xp.y = 2, 0, -24
    end
end

local function AnnouncementsAnchor(modules)
    -- Older announcement positions were offsets from screen center. Keep them
    -- when new profiles start from the top-center anchor.
    local announcements = Module(modules, "announcements")
    if announcements and announcements.anchor == nil and type(announcements.y) == "number" then
        announcements.anchor = 2
    end
end

local function AnnouncementsFactory(modules)
    -- The first announcements factory showed zones only. It now also replaces
    -- Blizzard's quest, achievement, level and scenario banners.
    local old = Module(modules, "announcements")
    if old and old.eventToasts == nil and old.zone == true
        and old.quests == false and old.achievements == false
        and old.level == false and old.scenario == false
        and old.duration == 4 and old.scale == 100 and old.x == 0 and old.y == -170 then
        old.quests, old.achievements, old.level, old.scenario = true, true, true, true
    end
end

local function DataTextsBagButtons(modules)
    -- An older Retail profile may have DataTexts without a Bag space slot.
    -- Keep Blizzard's bag buttons until that player explicitly chooses this.
    local data = Module(modules, "dataTexts")
    if not NS.Client.isMainline or not data or data.hideBlizzardBagBar ~= nil then return end
    local anySlot = false
    for bar = 1, 3 do
        for slot = 1, 6 do
            local source = data["bar" .. bar .. "Slot" .. slot]
            if source == 3 then return end
            if source ~= nil then anySlot = true end
        end
    end
    if anySlot then data.hideBlizzardBagBar = false end
end

local function ActionBarsCustomLook(modules)
    -- Action bar looks are newer than the bars. Existing profiles keep their
    -- exact button colors and spacing and show them as Custom.
    local bars = Module(modules, "actionbars")
    if HasSettings(bars) and bars.look == nil then bars.look = S.catalog.actionbars.look.custom end
end

local function BagsCustomLook(modules)
    -- The previous bag appearance was the Forever palette on every client.
    -- Keep it, including missing visual fields in partial saved profiles.
    local bags = Module(modules, "bags")
    if not HasSettings(bags) or bags.look ~= nil then return end
    local look = S.catalog.bags.look
    for key, value in pairs(look.presets[3]) do
        if bags[key] == nil then bags[key] = value end
    end
    bags.look = look.custom
end

local function LookRenumbering(modules)
    -- Preset 2 used to mean Forever and preset 3 meant Custom. Translate the
    -- stored choices before catalog defaults can fill new fields.
    local legacyDefault = NS.Client.isForever and 3 or 1
    for _, id in ipairs({ "chat", "damageMeter" }) do
        local config = Module(modules, id)
        if HasSettings(config) then
            if config.look == nil then
                local custom = false
                for key, value in pairs(S.catalog[id].look.presets[legacyDefault]) do
                    if config[key] == nil then
                        config[key] = value
                    elseif config[key] ~= value then
                        custom = true
                    end
                end
                config.look = custom and 4 or legacyDefault
            elseif config.look == 2 then
                config.look = 3
            elseif config.look == 3 then
                config.look = 4
            end
        end
    end
    local data = Module(modules, "dataTexts")
    if HasSettings(data) then
        if data.look == nil then
            data.look = legacyDefault
        elseif data.look == 2 then
            data.look = 3
        end
        for bar = 1, 3 do
            local key = "bar" .. bar .. "Look"
            if data[key] == 2 then
                data[key] = 3
            elseif data[key] == nil and data["bar" .. bar .. "StyleOverride"] then
                data[key] = legacyDefault
            end
        end
    end
    local xp = Module(modules, "xpBar")
    if HasSettings(xp) then
        if xp.look == nil then
            xp.look = legacyDefault
        elseif xp.look == 2 then
            xp.look = 3
        end
    end
end

local function SkyridingColors(modules)
    -- Older Skyriding profiles have a selected look but no editable colors.
    -- Seed only missing fields from that look before defaults apply.
    local sky = Module(modules, "skyriding")
    if not sky then return end
    local presets = S.catalog.skyriding.look.presets
    for key, value in pairs(presets[sky.look] or presets[1]) do
        if sky[key] == nil then sky[key] = value end
    end
end

local function ForeverHud(modules)
    -- Forever previously exposed these HUD settings while marking both modules
    -- unavailable. Activate them once now that the runtime is supported.
    EnsureModule(modules, "objectives").enabled = true
    EnsureModule(modules, "announcements").enabled = true
end

local function ForeverActionBars(modules)
    -- Forever profiles normalized with the old disabled default start the bars.
    EnsureModule(modules, "actionbars").enabled = true
end

local PREVIOUS_FOREVER_VISIBILITY = { 1, 1, 4, 1, 4, 6, 6, 6, 6, 6, 1, 1 }
local function ForeverLayout(modules)
    -- Repair the original Forever factory stack without moving bars whose
    -- position or size was customized.
    local data = Module(modules, "dataTexts")
    if data and data.bar1Width == 270 and data.bar1Layout == 1
        and data.bar1Point == 9 and data.bar1X == -20 and data.bar1Y == 20
        and data.bar1Slot1 == 3 and data.bar1Slot2 == 4 and data.bar1Slot3 == 5 then
        data.bar1Width, data.bar1Layout = 340, 2
    end
    local meter = Module(modules, "damageMeter")
    if meter and meter.windowCount == 2
        and meter.w1Width == 260 and meter.w1Height == 170 and meter.w1X == -20 and meter.w1Y == 20
        and meter.w2Width == 260 and meter.w2Height == 170 and meter.w2X == -20 and meter.w2Y == 210 then
        meter.w1Width, meter.w1Y = 340, 60
        meter.w2Width, meter.w2Y = 340, 250
    end
    local bars = Module(modules, "actionbars")
    if not bars or bars.imported ~= false then return end
    for i, visibility in ipairs(PREVIOUS_FOREVER_VISIBILITY) do
        if bars["bar" .. i .. "Visibility"] ~= visibility
            or bars["bar" .. i .. "ResumeVisibility"] ~= (visibility == 6 and 1 or visibility) then
            return
        end
    end
    for i = 1, #PREVIOUS_FOREVER_VISIBILITY do
        bars["bar" .. i .. "Visibility"] = 4
        bars["bar" .. i .. "ResumeVisibility"] = 4
    end
end

local function ForeverPalette(modules)
    local chat = Module(modules, "chat")
    if chat and chat.look == 3 and chat.inputColor == "1a1a1b" then chat.inputColor = "111517" end
    local reminders = Module(modules, "buffReminders")
    if reminders and reminders.borderColor == "e8b855" then reminders.borderColor = "d8b66a" end
    local cooldowns = Module(modules, "cooldownManager")
    if cooldowns then
        for key, color in pairs(cooldowns) do
            if type(key) == "string" and key:sub(-8) == "barColor" and color == "e8b855" then
                cooldowns[key] = "d8b66a"
            end
        end
    end
end

local function ObjectivesCollapseState(modules, db)
    -- Collapsed tracker groups used to live inside the settings. They are
    -- runtime state the tracker owns (see S.ModuleState).
    local objectives = Module(modules, "objectives")
    if not objectives then return end
    local groups, entries = objectives.collapsedGroups, objectives.collapsedEntries
    if groups == nil and entries == nil then return end
    objectives.collapsedGroups, objectives.collapsedEntries = nil, nil
    if type(groups) ~= "table" and type(entries) ~= "table" then return end
    db.moduleState = type(db.moduleState) == "table" and db.moduleState or {}
    local state = type(db.moduleState.objectives) == "table" and db.moduleState.objectives or {}
    db.moduleState.objectives = state
    if type(groups) == "table" then state.collapsedGroups = groups end
    if type(entries) == "table" then state.collapsedEntries = entries end
end

-- legacy: flag key of profiles saved before suite.revision; done: flag value
-- that marked the step as applied. forever: step applies only on WoW Forever.
local MIGRATIONS = {
    { run = ObjectivesTransparent, legacy = "objectivesTransparentRevision" },
    { run = HudTypography, legacy = "hudTypographyRevision" },
    { run = ExperienceBarTop, legacy = "xpTopRevision" },
    { run = ActionBarsCustomLook, legacy = "actionBarLookRevision" },
    { run = BagsCustomLook, legacy = "bagsLookRevision" },
    { run = LookRenumbering, legacy = "lookPresetRevision" },
    { run = ForeverHud, legacy = "foreverHudRevision", forever = true },
    { run = ForeverActionBars, legacy = "actionBarsDefaultRevision", done = 2, forever = true },
    { run = ForeverLayout, legacy = "layoutRevision", done = 2, forever = true },
    { run = ForeverPalette, legacy = "paletteRevision", forever = true },
}
S.MigrationRevision = #MIGRATIONS

local REPAIRS = {
    AnnouncementsAnchor, AnnouncementsFactory, DataTextsBagButtons, SkyridingColors, ObjectivesCollapseState,
}

-- The migration revision a copy of this suite table must keep. A table from
-- before suite.revision returns nil and its legacy flags instead.
function S.MigrationState(db)
    if type(db) ~= "table" then return nil end
    local revision = db.revision
    if type(revision) == "number" and revision == revision and revision >= 0 then
        return math.floor(revision)
    end
    local flags
    for _, step in ipairs(MIGRATIONS) do
        local value = step.legacy and db[step.legacy]
        if type(value) == "number" then
            flags = flags or {}
            flags[step.legacy] = value
        end
    end
    return nil, flags
end

local function StepPending(db, revision, index, step)
    if step.forever and not NS.Client.isForever then return false end
    if revision then return index > revision end
    return not step.legacy or (tonumber(db[step.legacy]) or 0) < (step.done or 1)
end

local function RunMigrations(db)
    local revision = S.MigrationState(db)
    for index, step in ipairs(MIGRATIONS) do
        if StepPending(db, revision, index, step) then step.run(db.modules, db) end
    end
    db.revision = math.max(revision or 0, #MIGRATIONS)
    for _, step in ipairs(MIGRATIONS) do
        if step.legacy then db[step.legacy] = nil end
    end
end

------------------------------------------------------------------ normalization
-- Idempotent: every module table exists and every rule holds a valid value.
local function ApplyCatalogRules(modules)
    for i = 1, #S.order do
        local id = S.order[i]
        local config = EnsureModule(modules, id)
        for key, rule in pairs(S.catalog[id].rules) do
            config[key] = RepairedValue(rule, config[key])
        end
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
    return db
end

function S.Normalize(profile)
    local db = SuiteTable(profile)
    if not db then return end
    RunMigrations(db)
    for i = 1, #REPAIRS do REPAIRS[i](db.modules, db) end
    ApplyCatalogRules(db.modules)
end

------------------------------------------------------------------ looks
-- The Skinning look is a deliberate suite-wide gesture. Keep the choice in
-- this profile so an optional module adopts it when it is enabled later.
-- Catalog entries describe their part in spec.look (see SuiteCatalog.lua).
local GLOBAL_LOOKS = { midnight = 1, midnightDark = 2, foreverGlass = 3 }

local function LookValues(id, lookIndex, config)
    local look = S.catalog[id].look
    if not look or not (look.global or look.extra) then return nil end
    local values = {}
    if look.global then
        local choice = look.global == true and lookIndex or look.global[lookIndex]
        values[look.key] = choice
        local preset = look.presets and look.presets[choice]
        if preset then
            for key, value in pairs(preset) do values[key] = value end
        end
    end
    if look.extra then look.extra(values, lookIndex, config) end
    return values
end

local function ApplyLookToConfig(id, config, lookName)
    local index = GLOBAL_LOOKS[lookName]
    local values = index and LookValues(id, index, config)
    if not values then return false end
    local rules = S.catalog[id].rules
    local changed = false
    for key, value in pairs(values) do
        local rule = rules[key]
        if rule and type(value) == type(rule.default) and config[key] ~= value then
            config[key] = value
            changed = true
        end
    end
    return changed
end

------------------------------------------------------------------ profile access
function S.SanitizeImport(profile)
    -- Sharing a visual setup never authorizes spending or automation.
    local modules = type(profile) == "table" and type(profile.suite) == "table" and profile.suite.modules
    if type(modules) ~= "table" then return end
    if type(modules.qol) == "table" then
        modules.qol.enabled, modules.qol.repair, modules.qol.autoJunk = false, false, false
    end
    if type(modules.quests) == "table" then modules.quests.enabled = false end
    if type(modules.loot) == "table" then modules.loot.quickLoot = false end
    if type(modules.combatLog) == "table" then modules.combatLog.enabled = false end
end

local function ActiveSuite()
    local db = NS.DB and NS.DB.suite
    return db and db.schema == 1 and db or nil
end

function S.Config(id)
    local db = ActiveSuite()
    return db and db.modules and db.modules[id] or NS.Defaults.suite.modules[id]
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
        if NS.Client.IsAddOnLoaded(spec.conflicts[i]) then return false, "Managed by " .. spec.conflicts[i] end
    end
    return true
end

------------------------------------------------------------------ lifecycle
local function Changed()
    if NS.Options and NS.Options.RefreshAll then NS.Options.RefreshAll() end
end

local function Stop(id)
    local state, instance = S.states[id], S.instances[id]
    if S.CloseMovers then S.CloseMovers(id) end
    if S.UnregisterEditElements then S.UnregisterEditElements(id) end
    state.active = false
    if instance then
        instance.active = false
        instance:Disable()
        if instance.context then instance.context:Release() end
    end
end

local function Flush(self)
    if NS.IsCombatLocked() then return end
    self:UnregisterAllEvents()
    pendingListening = false
    for id in pairs(pending) do
        pending[id] = nil
        S.Apply(id)
    end
    Changed()
end

function S.Queue(id)
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

local function LoadAddOnByName(name)
    local loader = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if type(loader) ~= "function" then return nil end
    return loader(name)
end

-- Loads the shared runtime and the module's addon. Returns false after
-- recording why the module could not register.
local function LoadInstance(id, state)
    local spec = S.catalog[id]
    local loaded, why
    if not NS.Client.IsAddOnLoaded(RUNTIME_ADDON) then loaded, why = LoadAddOnByName(RUNTIME_ADDON) end
    if type(S.NewContext) == "function" then loaded, why = LoadAddOnByName(spec.addon) end
    -- Some Forever builds return an empty/diagnostic result even after the
    -- addon ran. Successful registration is the authoritative outcome.
    if S.instances[id] then return true end
    if NS.Client.IsAddOnLoaded(spec.addon) then
        state.error = spec.title .. " is missing from " .. spec.addon
    else
        state.error = "Cannot load " .. spec.addon .. ": " .. tostring(why or loaded or "not installed")
    end
    return false
end

-- Blizzard surfaces a running module replaces or hides. The skin leaves them
-- to the module and styles Blizzard's original again once the module is off.
local SURFACE_MODULES = {
    damageMeter = "damageMeter", bagWindows = "bags",
    cooldownViewers = "cooldownManager", bagBar = "dataTexts",
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
    -- DataTexts hides the bag bar only on request, and only where it exists.
    if surface == "bagBar" and (config.hideBlizzardBagBar ~= true or not NS.Client.isMainline) then
        return false
    end
    return S.Availability(id) == true
end

local function ApplyModule(id)
    local state, config = S.states[id], S.Config(id)
    local supported, reason = S.Availability(id)
    state.unavailable = not supported and reason or nil
    if not ActiveSuite() or not config.enabled or not supported or state.error then
        if state.active or (S.instances[id] and S.instances[id].active) then Stop(id) end
        if S.RestoreSaved then S.RestoreSaved(id) end
        return
    end
    if not S.instances[id] and not LoadInstance(id, state) then return end
    local instance = S.instances[id]
    -- A previous callback may have raised a client-visible error after taking
    -- ownership. Release that partial activation before a deliberate retry.
    if instance.active and not state.active then Stop(id) end
    instance.config = config
    instance.active = true
    instance.context = instance.context or S.NewContext(id)
    -- Follow MSUF error reporting: Lua errors reach the client error handler.
    -- A successful callback is required before publishing an active state.
    if state.active then instance:Refresh() else instance:Enable() end
    if instance.context.RefreshOwnedSkins then instance.context:RefreshOwnedSkins() end
    state.active = true
    if S.RefreshEditMover then S.RefreshEditMover(id) end
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
    local skin = SURFACE_OWNERS[id] and NS.Skin
    if skin then skin.SurfacesChanged("before") end
    ApplyModule(id)
    if skin then skin.SurfacesChanged("after") end
end

function S.ApplyAll()
    for i = 1, #S.order do S.Apply(S.order[i]) end
end

function S.ApplyGlobalLook(lookName)
    local db = ActiveSuite()
    if NS.IsCombatLocked() or not GLOBAL_LOOKS[lookName] or not db then return false end
    db.globalLook = lookName
    for i = 1, #S.order do
        local id = S.order[i]
        local config = S.Config(id)
        if config.enabled and ApplyLookToConfig(id, config, lookName) then
            S.states[id].error = nil
            S.Apply(id)
        end
    end
    Changed()
    return true
end

------------------------------------------------------------------ settings
function S.Set(id, key, value)
    if NS.IsCombatLocked() then return false, "Finish combat before editing the suite" end
    local db = ActiveSuite()
    if not db then return false, "Unsupported suite profile" end
    local reason
    value, reason = CheckedValue(S.catalog[id] and S.catalog[id].rules[key], value)
    if value == nil then return false, reason end
    local config, state = S.Config(id), S.states[id]
    if config[key] == value and not state.error and not state.unavailable then return true end
    config[key] = value
    if key == "enabled" and value == true then ApplyLookToConfig(id, config, db.globalLook) end
    state.error = nil
    S.Apply(id)
    Changed()
    return true
end

function S.SetMany(id, values)
    if NS.IsCombatLocked() then return false, "Finish combat before editing the suite" end
    local db = ActiveSuite()
    if not db or type(values) ~= "table" then return false, "Invalid settings" end
    local spec = S.catalog[id]
    if not spec then return false, "Unknown module" end
    local clean = {}
    for key, value in pairs(values) do
        local checked, reason = CheckedValue(spec.rules[key], value)
        if checked == nil then return false, reason end
        clean[key] = checked
    end
    local config = S.Config(id)
    for key, value in pairs(clean) do config[key] = value end
    if clean.enabled == true then ApplyLookToConfig(id, config, db.globalLook) end
    S.states[id].error = nil
    S.Apply(id)
    Changed()
    return true
end

-- Section resets restore only their owned keys. Enabling a module through the
-- normal setter applies the active look to unrelated appearance settings;
-- that behavior is intentionally skipped for a scoped reset.
function S.ResetKeys(id, values)
    if NS.IsCombatLocked() then return false, "Finish combat before editing the suite" end
    local db = ActiveSuite()
    local spec = S.catalog[id]
    if not db or not spec or type(values) ~= "table" then return false, "Invalid settings" end
    local clean = {}
    for key, value in pairs(values) do
        local checked, reason = CheckedValue(spec.rules[key], value)
        if checked == nil then return false, reason end
        clean[key] = checked
    end
    local config = S.Config(id)
    for key, value in pairs(clean) do config[key] = value end
    S.states[id].error = nil
    S.Apply(id)
    Changed()
    return true
end

function S.AddSpellFromCursor(id, key)
    local rule = S.catalog[id] and S.catalog[id].rules[key]
    if not rule or not (rule.spells or rule.items) or NS.IsCombatLocked()
        or type(GetCursorInfo) ~= "function" then
        return false
    end
    local kind, cursorID, _, spellID = GetCursorInfo()
    if type(issecretvalue) == "function"
        and (issecretvalue(kind) or issecretvalue(cursorID) or issecretvalue(spellID)) then
        return false
    end
    if rule.items then
        if kind ~= "item" then return false end
        spellID = cursorID
    elseif kind ~= "spell" then
        return false
    end
    if type(spellID) ~= "number" then return false end
    local text = S.Config(id)[key]
    for token in text:gmatch("%d+") do
        if tonumber(token) == spellID then return false end
    end
    local ok = S.Set(id, key, text == "" and tostring(spellID) or text .. " " .. tostring(spellID))
    if ok and type(ClearCursor) == "function" then ClearCursor() end
    return ok
end

function S.Reset(id)
    local db = ActiveSuite()
    if NS.IsCombatLocked() or not S.catalog[id] or not db then return false end
    db.modules[id] = NS.CopyValue(NS.Defaults.suite.modules[id])
    local config = S.Config(id)
    if config.enabled then ApplyLookToConfig(id, config, db.globalLook) end
    S.states[id].error = nil
    S.Apply(id)
    Changed()
    return true
end

-- "core" enables available core modules; "off" disables every module. Setup
-- never enables spending or automation: opt-in modules keep their own choice.
function S.Preset(kind)
    local db = ActiveSuite()
    if NS.IsCombatLocked() or not db then return false end
    if kind ~= "core" and kind ~= "off" then return false end
    for i = 1, #S.order do
        local id = S.order[i]
        if S.catalog[id].core or kind == "off" then
            local config = S.Config(id)
            config.enabled = kind == "core" and S.Availability(id) == true
            if config.enabled then ApplyLookToConfig(id, config, db.globalLook) end
            S.states[id].error = nil
        end
    end
    S.ApplyAll()
    Changed()
    return true
end

function S.Start()
    if S.started then return end
    S.started = true
    if NS.DB then S.Normalize(NS.DB) end
    -- Saved CVars wait in the runtime until their owner hands them back.
    if NS.RootDB and type(NS.RootDB.suiteRecovery) == "table" and next(NS.RootDB.suiteRecovery) then
        LoadAddOnByName(RUNTIME_ADDON)
    end
    NS.Registry.AddListener(S, function(_, domain)
        if domain == "profile" then
            if S.CloseMovers then S.CloseMovers() end
            if NS.DB then S.Normalize(NS.DB) end
            S.ApplyAll()
        end
    end)
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
    local page = spec and (spec.page or ("suite_" .. id)) or "suite_actionbars"
    if NS.Menu and NS.Menu.Open and NS.Menu.Open(page) then return end
    NS.Print("Open the MSUF menu to find the Suite pages. MSUF must be installed and enabled.")
end

SLASH_MSUFSUITE1 = "/msuite"
SlashCmdList.MSUFSUITE = function() S.Open() end
