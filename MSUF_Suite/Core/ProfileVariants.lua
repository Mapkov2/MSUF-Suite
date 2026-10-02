-- A shared MSUF profile owns its variant metadata; Suite remains the sole owner
-- of module settings. Core sees a synthetic snapshot root, never a saved alias.
-- That root holds every catalog rule except the nameplates module and the
-- automation settings (SuiteCatalog.lua): variants, sync groups and shared
-- variant patches never change what acts on the player's behalf.
local _, Suite = ...
local P = {}
Suite.ProfileVariants = P
local core, F, V, S
local hadOverlay = false

local function Allowed(id)
    local spec = Suite.SuiteCatalog[id]
    return id ~= "nameplates" and spec ~= nil and not spec.automation
end

-- The rule of a setting the variant layer may hold, or nil.
local function VariantRule(id, key)
    local rule = Allowed(id) and Suite.SuiteCatalog[id].rules[key]
    if rule and not rule.automation then return rule end
end

local function FrameProfile(name)
    local profiles = _G.MSUF_GlobalDB and _G.MSUF_GlobalDB.profiles
    return profiles and profiles[name]
end

local function HasVariants(db)
    local schema = type(db) == "table" and db.profileVariants
    local entries = type(schema) == "table" and schema.entries
    if type(entries) ~= "table" then return false end
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and type(entry.patch) == "table" then
            for _, field in ipairs(entry.patch) do
                if type(field) == "table" and type(field.path) == "table" and field.path[1] == "suiteModules" then
                    return true
                end
            end
        end
    end
    return false
end

-- The core journals the overlay of the active MSUF profile only, so only the
-- Suite profile of that name can hold variant values instead of its own.
local function Overlaid(name)
    local frames = FrameProfile(name)
    return V ~= nil and frames ~= nil and frames == _G.MSUF_DB and V.HasExternalOverlay("suiteModules")
end

-- Puts the base values the core keeps for the overlaid settings into
-- `modules`, a copy of the stored module settings. Automation settings never
-- enter the overlay, so they keep their stored values.
local function UseBase(modules, name)
    local snapshot, why = V.BaseSnapshot(FrameProfile(name), true)
    if not snapshot then return false, why end
    for id, config in pairs(snapshot.suiteModules or {}) do
        local stored = modules[id]
        if type(stored) == "table" then
            local rules = Suite.SuiteCatalog[id].rules
            for key, value in pairs(stored) do
                local rule = rules[key]
                if rule and rule.automation then config[key] = value end
            end
        end
        modules[id] = config
    end
    return true
end

-- A copy of a stored Suite profile without the variant overlay. A failed core
-- snapshot never falls back to the overlaid values.
function P.BaseProfile(name)
    local source = Suite.Database.GetProfile(name)
    if not source then return nil, "Missing suite profile" end
    local out = Suite.CopyValue(source)
    if Overlaid(name) then
        local ok, why = UseBase(out.suite.modules, name)
        if not ok then return nil, why end
    end
    return out
end

-- Only the settings of a stored Suite profile (Database.PROFILE_SETTINGS of
-- its suite table) without the variant overlay, for undo history.
function P.BaseSettings(name)
    local source = Suite.Database.GetProfile(name)
    local db = source and source.suite
    if type(db) ~= "table" then return nil, "Missing suite profile" end
    local out = {}
    for _, key in ipairs(Suite.Database.PROFILE_SETTINGS) do out[key] = Suite.CopyValue(db[key]) end
    if Overlaid(name) and type(out.modules) == "table" then
        local ok, why = UseBase(out.modules, name)
        if not ok then return nil, why end
    end
    return out
end

local function Resolve(name, create)
    if not Suite.RootDB then return end
    local profile = Suite.Database.GetProfile(name)
    -- Existing stores remain readable while the core peels its old journal.
    -- Only the not-yet-published import target must stay unresolved.
    if Suite.suppressProfileSync and not profile then return end
    if not profile and create and not Suite.IsCombatLocked() then
        local source = P.BaseProfile(Suite.Database.GetActiveProfileName())
        if source and Suite.Database.CreateFromProfile(name, source) then profile = Suite.Database.GetProfile(name) end
    end
    return profile and profile.suite and profile.suite.modules
end

-- A patch outside the variant layer is invalid, so a shared variant that
-- names an automation setting is refused before it can be stored.
local function Check(path, value, remove)
    local rule = #path == 3 and VariantRule(path[2], path[3])
    if not rule then return nil, false end
    if remove then return rule.default, true end
    local checked = Suite.Suite.CheckProfileValue(rule, value)
    return checked, checked ~= nil
end

local function Snapshot(source)
    local out = {}
    for id, config in pairs(source) do
        if Allowed(id) then
            if type(config) ~= "table" then return nil, false end
            local values = {}
            for key, value in pairs(config) do
                local rule = VariantRule(id, key)
                if rule then
                    local checked = Suite.Suite.CheckProfileValue(rule, value)
                    if checked == nil then return nil, false end
                    values[key] = checked
                end
            end
            local spec = Suite.SuiteCatalog[id]
            if spec.prepareConfig then spec.prepareConfig(values) end
            out[id] = values
        end
    end
    return out, true
end

-- Automation settings are not part of the snapshot, so a restore leaves them
-- as they are.
local function Restore(target, source)
    local prepared, valid = Snapshot(source)
    if not valid then return false, "invalid setting value" end
    for id, values in pairs(prepared) do
        local config = target[id]
        if type(config) ~= "table" then
            config = {}
            target[id] = config
        end
        for key in pairs(config) do
            if VariantRule(id, key) and values[key] == nil then config[key] = nil end
        end
        for key, value in pairs(values) do config[key] = value end
    end
    return true
end

local function Apply(reason)
    if Suite.suppressProfileSync or Suite.Database.GetActiveProfileName() ~= _G.MSUF_ActiveProfile then return end
    local overlay = V.HasExternalOverlay("suiteModules")
    local relevant = overlay or hadOverlay or V.IsRecording()
        or (type(reason) == "string" and reason:match("^PROFILE_VARIANT_EDIT_"))
    hadOverlay = overlay
    if reason == "SUITE_PROFILE_VARIANT_ACTIVATE" or not Suite.Suite.started then return end
    if relevant then Suite.Suite.ApplyAll() end
end

-- Every core export this adapter uses. A core without them (Main MSUF, an
-- older Classic build) leaves the adapter off and the Suite works without it.
local function CoreReady()
    return F and F.RegisterExternal and V and V.BaseSnapshot and V.HasExternalOverlay
        and V.IsRecording and V.IsMaterialized and V.Restore and V.ResolveCurrent
        and S and S.RegisterModule and S.RebaseExternal
        and core.ProfileRuntime and core.ProfileRuntime.Apply and Suite.Suite.CheckProfileValue
end

function P.Register()
    if V then return true end
    core = _G.MSUF_NS
    F, V, S = core.ProfileFields, core.ProfileVariants, core.ProfileSync
    if not CoreReady() then
        V = nil
        return false
    end
    F.RegisterExternal("suiteModules", {
        Resolve = Resolve,
        Allows = function(path) return #path == 3 and VariantRule(path[2], path[3]) ~= nil end,
        Owner = function(path) if Allowed(path[2]) then return "suite:" .. path[2] end end,
        Check = Check,
        Snapshot = Snapshot,
        Restore = Restore,
        Apply = Apply,
    })
    for _, id in ipairs(Suite.SuiteOrder) do
        if Allowed(id) then
            local title = Suite.SuiteCatalog[id].title
            S.RegisterModule("suite:" .. id, "Suite: " .. (Suite.L[title] or title))
        end
    end
    return true
end

function P.CanMutate()
    if P.Register() and V.IsRecording() then return false, "finish editing the variant first" end
    return true
end

function P.BeforeMutation(name)
    local ok, why = P.CanMutate()
    if not ok then return false, why end
    if V and name == _G.MSUF_ActiveProfile then V.Restore() end
    return true
end

function P.AfterMutation(name)
    if V and name == _G.MSUF_ActiveProfile and not Suite.suppressProfileSync then
        core.ProfileRuntime.Apply("SUITE_PROFILE_VARIANT_MUTATE", false)
    end
end

-- Undo writes stored settings. MSUF's own history restore has already
-- discarded live variant edits and laid the overlay again, so it is lifted
-- without capturing anything and laid once more after the write.
function P.LiftOverlay(name)
    if not Overlaid(name) then return false end
    V.Restore(false)
    return true
end

function P.LayOverlay()
    V.ResolveCurrent()
end

function P.OnActivated(name)
    if Suite.suppressProfileSync or not P.Register() then return end
    if name ~= _G.MSUF_ActiveProfile then return end
    if HasVariants(FrameProfile(name)) or V.IsMaterialized(_G.MSUF_DB) then
        -- Migrations and repairs belong to the stored settings: lift the
        -- overlay, normalize the base, then let the core lay it again.
        V.Restore()
        Suite.Suite.Normalize(Suite.Database.GetProfile(name))
        core.ProfileRuntime.Apply("SUITE_PROFILE_VARIANT_ACTIVATE", false)
    end
    S.RebaseExternal("suiteModules")
end

function P.Start()
    if not P.Register() then return end
    P.OnActivated(Suite.Database.GetActiveProfileName())
end
