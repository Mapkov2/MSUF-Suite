-- Profile data never rides in a profile variant, against the real MSUF core.
--
-- Reported 2026-11-23: a variant for dungeons ("party") had recorded the
-- cooldown manager's listsData along with its own settings. listsData holds
-- every bar's contents for every specialization in one value, so in every
-- dungeon the variant laid the contents from its recording over the profile
-- and custom bars filled since then were empty there; /reload did not help.
-- Settings flagged as profile data (SuiteCatalog Build.ProfileData) stay with
-- the profile (MSUF_Suite/Core/ProfileVariants.lua):
--   * the cooldown manager's lists, per-spell choices, layouts by
--     specialization and bookkeeping are profile data, its layout is not;
--   * a stored variant holding profile data applies its other fields only,
--     and the applied schema drops the data for good;
--   * bar contents edited under the overlay stay in the profile;
--   * a shared or imported variant with profile data validates without it;
--   * a recording never captures profile data, and data changed while
--     recording stays a change of the profile;
--   * copies, MSUF's base snapshot and undo history still carry it;
--   * a variant fills single bars through variantLists (Dark Raid: Havoc's
--     seven dungeon utilities), never another bar, specialization or the
--     other client's lists, and older Dark Raid installs are converted.
-- Boots the sibling MSUF 7.0 checkout like suite_profile_variants_core_contract.lua.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local classic = root .. "/../MidnightSimpleUnitFrames-7.0"

local function Check(condition, message)
    if not condition then error("suite_profile_variants_data_contract: " .. message, 2) end
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
-- Outside an instance and solo: a "party" variant matches only where a check
-- passes the dungeon context itself.
env.IsInInstance = function() return false, "none" end
env.IsInGroup = function() return false end
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
Check(V and F and V.Resolve and V.BeginRecording and F.RegisterExternal and F.RegisterPatchTranslator,
    "the core has no profile variants or patch translators")
Check(Suite.Database.Initialize(nil), "Suite test profile did not initialize")
Suite.Suite.Normalize(Suite.DB)
core.ProfileRuntime.Apply = function(reason)
    V.ResolveCurrent()
    if F.ApplyExternal then F.ApplyExternal(reason) end
end
Check(Suite.ProfileVariants.Register(), "the Suite provider did not register with the real core")
local cdm = Suite.Suite.Config("cooldownManager")
Check(type(cdm) == "table" and Suite.DB.suite.modules.cooldownManager == cdm, "the cooldown manager has no stored settings")

local function Field(key, value) return { path = { "suiteModules", "cooldownManager", key }, value = value } end
local function Dungeon(patch)
    return { version = 1, entries = { { name = "Dungeon meter", conditions = { context = "party" }, patch = patch } } }
end
local DUNGEON = { location = "party" }
local function Stored()
    local keys = {}
    for _, field in ipairs(frames.profileVariants.entries[1].patch) do keys[field.path[3]] = field.value end
    return keys
end

------------------------------------------------------------------ the catalog
local rules = Suite.SuiteCatalog.cooldownManager.rules
for _, key in ipairs({ "listsData", "spellsData", "positionsData", "captured", "defaultsVersion" }) do
    Check(rules[key].profileData == true, "cooldown manager " .. key .. " is not profile data")
end
Check(not rules.essOnViewer.profileData and not rules.uti_perRow.profileData and not rules.c5_on.profileData,
    "a layout setting of the cooldown manager became profile data")
Check(F.ExternalAvailable(frames, { "suiteModules", "cooldownManager", "listsData" }) == false
    and F.ExternalAvailable(frames, { "suiteModules", "cooldownManager", "uti_perRow" }) == true,
    "the variant layer may hold the bar contents, or no longer the bar layout")

------------------------------------------------------------------ a variant an older build stored
local perRow = cdm.uti_perRow
cdm.listsData = "base lists"
frames.profileVariants = Dungeon({ Field("listsData", "lists from the recording"), Field("uti_perRow", perRow + 2) })
Check(V.Resolve(frames, DUNGEON) == true and cdm.uti_perRow == perRow + 2, "the dungeon variant did not apply its other field")
Check(cdm.listsData == "base lists", "the dungeon variant laid the bar contents from its recording over the profile")
local stored = Stored()
Check(stored.uti_perRow == perRow + 2 and stored.listsData == nil, "the applied variant kept the recorded bar contents")
-- Bars filled in the dungeon stay filled outside it.
cdm.listsData = "filled in the dungeon"
V.Restore()
Check(cdm.listsData == "filled in the dungeon" and cdm.uti_perRow == perRow,
    "leaving the dungeon dropped bar contents edited there, or kept the variant's rows")
Check(Stored().listsData == nil, "bar contents edited under the overlay went into the variant")

------------------------------------------------------------------ shared and imported variants
local clean, why = V.ValidateForProfile(frames, Dungeon({ Field("spellsData", "shared choices"), Field("uti_perRow", 8) }))
Check(clean, "a shared variant with per-spell choices was refused: " .. tostring(why))
local patch = clean.entries[1].patch
Check(#patch == 1 and patch[1].path[3] == "uti_perRow", "a shared variant kept the per-spell choices")

------------------------------------------------------------------ recording a variant
frames.profileVariants = Dungeon({ Field("uti_perRow", perRow + 2) })
Check(V.BeginRecording("Dungeon meter"), "recording did not start")
Check(cdm.uti_perRow == perRow + 2, "recording did not show the variant's value")
cdm.uti_perRow = perRow + 3
cdm.listsData, cdm.positionsData = "filled while recording", "layouts while recording"
Check(V.SaveRecording(), "recording did not save")
stored = Stored()
Check(stored.uti_perRow == perRow + 3, "the variant lost the recorded utility rows")
Check(stored.listsData == nil and stored.positionsData == nil, "the recording captured profile data")
V.Restore(false)
Check(cdm.uti_perRow == perRow and cdm.listsData == "filled while recording" and cdm.positionsData == "layouts while recording",
    "profile data changed while recording did not stay a change of the profile")
-- A cancelled recording keeps them too; the variant's own fields go back.
Check(V.BeginRecording("Dungeon meter"), "the second recording did not start")
cdm.uti_perRow, cdm.listsData = perRow + 5, "filled before a cancel"
Check(V.CancelRecording(), "recording did not cancel")
V.Restore(false)
Check(cdm.uti_perRow == perRow and cdm.listsData == "filled before a cancel" and Stored().uti_perRow == perRow + 3,
    "a cancelled recording reverted the bar contents or changed the variant")

------------------------------------------------------------------ copies, exports and undo
Check(V.Resolve(frames, DUNGEON) == true and cdm.uti_perRow == perRow + 3, "the overlay for the copy checks is missing")
local copy = Suite.ProfileVariants.BaseProfile("Default")
Check(copy and copy.suite.modules.cooldownManager.listsData == "filled before a cancel"
    and copy.suite.modules.cooldownManager.uti_perRow == perRow, "a profile copy lost the bar contents or kept the variant")
local snapshot = V.BaseSnapshot(frames, true)
Check(snapshot and snapshot.suiteModules.cooldownManager.listsData == "filled before a cancel",
    "MSUF's base snapshot (exports, sync, restore points) lost the bar contents")
local settings = Suite.ProfileVariants.BaseSettings("Default")
Check(settings and settings.modules.cooldownManager.listsData == "filled before a cancel", "undo history lost the bar contents")
V.Restore(false)

------------------------------------------------------------------ bars a variant fills
-- Dark Raid's dungeon variant fills Havoc's utility row through variantLists:
-- that bar of that specialization only. Retail (577) and WoW Forever (1484)
-- keep their own lists, and so does every other bar.
local CDM, Codec = Suite.CDM, Suite.CDM.Codec
local BARS = Suite.DarkRaidDungeonLists
-- The client world has no native CBOR or compression, so MSUF's compact codec
-- is a table store here. Dark Raid's encoded bars decode to what the factory
-- holds (suite_dark_raid_cooldowns_smoke.py decodes the real strings).
local store = {}
env.MSUF_EncodeCompactTable = function(t, prefix) store[#store + 1] = t; return prefix .. ":stored" .. #store end
env.MSUF_TryDecodeCompactString = function(text) return store[tonumber(text:match("^MSUF3:stored(%d+)$")) or text] end
store[BARS] = { v = 1, hidden = {}, shared = {}, replace = { [577] = { uti = true } }, specs = { [577] = {
    uti = { "s183752", "s179057", "s207684", "s217832", "s278326", "s185123", "s195072" } } } }
Check(type(BARS) == "string" and rules.variantLists and not rules.variantLists.profileData
    and F.ExternalAvailable(frames, { "suiteModules", "cooldownManager", "variantLists" }) == true,
    "the variant layer cannot fill single bars")
local dungeonUti = Codec.DecodeLists(BARS).specs[577].uti
Check(#dungeonUti == 7, "Dark Raid's dungeon variant lost its seven utilities")
local function Keys(list) return table.concat(list or {}, ",") end
local own = { v = 1, hidden = {}, shared = { c1 = { "s196718" } }, replace = { [577] = { ess = true } },
    specs = { [577] = { ess = { "s232893" }, uti = { "s183752", "s185123" }, c5 = { "s1", "s2" } }, [1484] = { ess = { "s12" } } } }
local effective = CDM.VariantLists(Codec.DecodeLists(Codec.EncodeLists(own)), BARS)
-- A filled bar is a complete selection: Blizzard's own entries stay off it.
Check(Keys(effective.specs[577].uti) == Keys(dungeonUti) and effective.replace[577].uti == true,
    "the dungeon variant did not fill Havoc's utility row as a complete selection")
Check(Keys(effective.specs[577].ess) == "s232893" and Keys(effective.specs[577].c5) == "s1,s2"
    and Keys(effective.specs[1484].ess) == "s12" and Keys(effective.shared.c1) == "s196718",
    "the dungeon variant changed another bar, another specialization or the other client's lists")
Check(CDM.VariantLists(own, "") == own and CDM.VariantLists(own, nil) == own, "an empty variant changed the lists")

-- A Dark Raid install from before keeps the whole lists in its variant; the
-- lists become the bar they were for. Other recorded lists are dropped.
local legacy = Codec.EncodeLists({ v = 1, hidden = {}, shared = { c1 = { "s196718", "s198589" } },
    replace = { [577] = { ess = true, uti = true } },
    specs = { [577] = { ess = { "s232893", "s188499" }, uti = dungeonUti, c2 = { "a162264" } } } })
cdm.listsData, cdm.variantLists = "the player's lists", ""
frames.profileVariants = Dungeon({ Field("listsData", legacy), Field("uti_perRow", 7) })
Check(V.Resolve(frames, DUNGEON) == true and cdm.variantLists == BARS and cdm.listsData == "the player's lists",
    "an older Dark Raid install did not get Havoc's dungeon utilities, or lost the player's lists")
stored = Stored()
Check(stored.variantLists == BARS and stored.listsData == nil and stored.uti_perRow == 7,
    "an older Dark Raid variant was not converted to the bar it fills")
V.Restore(false)
Check(cdm.variantLists == "" and cdm.listsData == "the player's lists", "leaving the dungeon kept the filled bar")
local other = Codec.EncodeLists({ v = 1, hidden = {}, shared = {}, replace = {},
    specs = { [577] = { uti = { "s183752" } }, [62] = { c5 = { "s1" } } } })
clean = V.ValidateForProfile(frames, Dungeon({ Field("listsData", other), Field("uti_perRow", 7) }))
Check(clean and #clean.entries[1].patch == 1 and clean.entries[1].patch[1].path[3] == "uti_perRow",
    "recorded lists that are not Dark Raid's became a filled bar")
clean = V.ValidateForProfile(frames, Dungeon({ Field("listsData", legacy), Field("variantLists", "") }))
Check(clean and #clean.entries[1].patch == 1 and clean.entries[1].patch[1].path[3] == "variantLists"
    and clean.entries[1].patch[1].value == "", "a variant that fills bars itself got a second variantLists field")
frames.profileVariants = nil

------------------------------------------------------------------ what the variant layer reports as its own
-- As an older build stored it, before the core validated it again.
frames.profileVariants = Dungeon({ Field("listsData", "lists from the recording"), Field("uti_perRow", perRow + 2) })
local held = Suite.ProfileVariants.VariantKeys("cooldownManager")
Check(held.uti_perRow == true and held.listsData == nil, "the variant layer reported the bar contents as its own")
frames.profileVariants = nil

print("suite_profile_variants_data_contract: ok (catalog, stored variants, edits under the overlay, shared variants, recording, copies, filled bars)")
