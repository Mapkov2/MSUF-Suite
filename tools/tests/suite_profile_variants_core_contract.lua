-- Suite profile variants against the real MSUF core.
--
-- Boots the sibling Classic MSUF checkout's real core and options (its
-- tools/tests/client_world.lua), then loads MSUF_Suite and MSUF_Suite_Options
-- into the same client. The core's own ProfileFields, ProfileVariants,
-- recording and sync code drive the Suite's provider
-- (MSUF_Suite/Core/ProfileVariants.lua):
--   * shared variant patches cannot hold automation settings (SuiteCatalog);
--   * a resolved overlay is never mistaken for the stored settings: copies,
--     exports and undo history read the base, and activation normalizes it;
--   * recording a variant never captures an automation switch, which stays a
--     change of the profile itself.
-- Only ProfileRuntime.Apply is replaced: its frame-side steps need a logged-in
-- client. The stand-in keeps the variant steps of the real one (resolve the
-- overlay, then apply the external providers).
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local classic = root .. "/../MidnightSimpleUnitFrames-Classic"

local function Check(condition, message)
    if not condition then error("suite_profile_variants_core_contract: " .. message, 2) end
    return condition
end

local function Read(path)
    local file = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

local World = assert(loadfile(classic .. "/tools/tests/client_world.lua"),
    "the Classic MSUF checkout is required next to the Suite (" .. classic .. ")")()
local world = World.New(classic, "Mainline")
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "MSUF did not boot: " .. tostring(failure and failure.file) .. " "
    .. tostring(failure and failure.message))
local env, core = world.env, world.core
env.InCombatLockdown = function() return false end
env.UnitAffectingCombat = function() return false end
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
local loaded = { MidnightSimpleUnitFrames = true, MidnightSimpleUnitFrames_Options = true }
env.C_AddOns = {
    GetAddOnMetadata = function() return nil end,
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    DoesAddOnExist = function(name) return name:find("^MSUF_Suite") ~= nil end,
    GetAddOnEnableState = function() return 2 end,
    LoadAddOn = function() return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}
-- The active MSUF profile and its sibling, as MSUF's ProfileIO publishes them.
local frames = { general = {} }
env.MSUF_GlobalDB = { profiles = { Default = frames, Other = { general = {} } }, global = {} }
env.MSUF_DB, env.MSUF_ActiveProfile = frames, "Default"

local function LoadAddOn(addon, namespace)
    for line in Read(root .. "/" .. addon .. "/" .. addon .. "_Mainline.toc"):gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local ok, message = world:LoadFile(root .. "/" .. addon .. "/" .. line:gsub("\\", "/"), addon, namespace)
            Check(ok, addon .. "/" .. line .. ": " .. tostring(message))
        end
    end
    loaded[addon] = true
end
LoadAddOn("MSUF_Suite", {})
local Suite = env.MSUFSuite
local V, F = core.ProfileVariants, core.ProfileFields
Check(V and F and V.Resolve and V.BeginRecording and F.RegisterExternal, "the core has no profile variants")
Check(Suite.Database.Initialize(nil), "Suite test profile did not initialize")
Suite.Suite.Normalize(Suite.DB)
local applies = {}
core.ProfileRuntime.Apply = function(reason)
    applies[#applies + 1] = reason
    V.ResolveCurrent()
    if F.ApplyExternal then F.ApplyExternal(reason) end
end
Check(Suite.ProfileVariants.Register(), "the Suite provider did not register with the real core")
local modules = Suite.DB.suite.modules

local function Schema(patch)
    return { version = 1, entries = { { name = "Healer", conditions = {}, patch = patch } } }
end

------------------------------------------------------------------ shared variant patches
-- A shared MSUF profile may carry variants. An automation patch is refused
-- before it can be stored; an ordinary one is accepted.
for _, path in ipairs({ { "suiteModules", "quests", "enabled" }, { "suiteModules", "loot", "quickLoot" },
    { "suiteModules", "trustedPartyInvites", "guild" }, { "suiteModules", "groupRaidShortcuts", "autoMarkTank" } }) do
    local clean, why = V.ValidateForProfile(frames, Schema({ { path = path, value = true } }))
    Check(clean == nil and why == "invalid setting value",
        "a shared variant patch could hold automation: " .. table.concat(path, "."))
end
Check(V.ValidateForProfile(frames, Schema({ { path = { "suiteModules", "objectives", "width" }, value = 420 } })),
    "an ordinary Suite variant patch was refused")

------------------------------------------------------------------ resolved overlay vs. stored settings
local snapshots, baseSnapshot = 0, V.BaseSnapshot
V.BaseSnapshot = function(...) snapshots = snapshots + 1; return baseSnapshot(...) end
local base = modules.objectives.width
modules.loot.quickLoot = true
-- A variant that names automation (stored by an older build) never applies.
frames.profileVariants = Schema({
    { path = { "suiteModules", "objectives", "width" }, value = base + 100 },
    { path = { "suiteModules", "quests", "enabled" }, value = true },
})
local quests = modules.quests.enabled
Check(V.Resolve(frames) == true and modules.objectives.width == base + 100,
    "the core did not lay the Suite overlay")
Check(modules.quests.enabled == quests, "an automation patch was applied")
Check(V.HasExternalOverlay("suiteModules"), "the core does not journal the Suite overlay")
local copy = Suite.ProfileVariants.BaseProfile("Default")
Check(copy and copy.suite.modules.objectives.width == base and copy.suite.modules.loot.quickLoot == true,
    "a copy of the overlaid profile carried the variant or lost an automation setting")
local settings = Suite.ProfileVariants.BaseSettings("Default")
Check(settings and settings.modules.objectives.width == base and settings.moduleState == nil,
    "undo history captured the variant instead of the stored settings")
Check(snapshots == 2, "the overlaid profile was not read through the core's base snapshot")
V.Restore(false)
Check(modules.objectives.width == base and not V.HasExternalOverlay("suiteModules"), "the overlay did not lift")
snapshots = 0
Check(Suite.ProfileVariants.BaseProfile("Default") and snapshots == 0,
    "without an overlay the base profile still took an MSUF profile snapshot")
frames.profileVariants = nil
V.BaseSnapshot = baseSnapshot

------------------------------------------------------------------ recording a variant
frames.profileVariants = Schema({ { path = { "suiteModules", "objectives", "width" }, value = base + 100 } })
Check(V.BeginRecording("Healer"), "recording did not start")
Check(modules.objectives.width == base + 100, "recording did not show the variant's value")
Check(not Suite.ProfileVariants.CanMutate(), "profile changes were allowed while recording")
modules.objectives.width = base + 150
modules.loot.quickLoot = false
Check(V.SaveRecording(), "recording did not save")
local saved = {}
for _, field in ipairs(frames.profileVariants.entries[1].patch) do saved[table.concat(field.path, ".")] = field.value end
Check(saved["suiteModules.objectives.width"] == base + 150, "the variant lost the recorded setting")
Check(saved["suiteModules.loot.quickLoot"] == nil, "the variant captured an automation switch")
-- Saving lays the variant again; under it the stored width is unchanged.
Check(modules.objectives.width == base + 150, "the saved variant did not apply")
V.Restore(false)
Check(modules.loot.quickLoot == false and modules.objectives.width == base,
    "an automation switch changed while recording did not stay a change of the profile")
frames.profileVariants = nil

------------------------------------------------------------------ activation normalizes the stored settings
-- A migration rewrites the stored value under a variant's overlay: the old
-- opaque tracker factory value (82) moves to the transparent look (0).
local db = Suite.DB.suite
modules.objectives.backgroundOpacity, modules.objectives.colorStyle = 82, 1
db.revision = 0
frames.profileVariants = Schema({ { path = { "suiteModules", "objectives", "backgroundOpacity" }, value = 50 } })
applies = {}
Suite.ProfileVariants.OnActivated("Default")
Check(applies[1] == "SUITE_PROFILE_VARIANT_ACTIVATE" and modules.objectives.backgroundOpacity == 50,
    "activation did not lay the overlay again")
V.Restore(false)
Check(modules.objectives.backgroundOpacity == 0 and db.revision == Suite.Suite.MigrationRevision,
    "a migration ran on the overlaid value instead of the stored one")
frames.profileVariants = nil

------------------------------------------------------------------ undo history under an overlay
-- MSUF's own history restore lays the overlay before the Suite's provider
-- runs. The Suite captures the stored settings and restores them under the
-- overlay, never the variant's values as the profile's own.
local P = {}
LoadAddOn("MSUF_Suite_Options", P)
frames.profileVariants = Schema({ { path = { "suiteModules", "objectives", "width" }, value = base + 100 } })
Check(V.Resolve(frames) and modules.objectives.width == base + 100, "the overlay for the history check is missing")
local title = modules.objectives.titleSize
local state = Check(P.CaptureHistoryState(), "the Suite history provider captured nothing")
Check(state.root.profiles.Default.suite.modules.objectives.width == base,
    "undo history captured the variant's value as the profile's own")
modules.objectives.titleSize = title + 4
Check(P.RestoreHistoryState(state), "the Suite history provider did not restore")
modules = Suite.DB.suite.modules
Check(modules.objectives.titleSize == title and modules.objectives.width == base + 100,
    "undo lost the restored setting or the overlay")
V.Restore(false)
Check(modules.objectives.width == base, "undo wrote the variant's value under the overlay")
frames.profileVariants = nil

print("suite_profile_variants_core_contract: ok (real core: validation, resolve, base copies, recording, activation, undo)")
