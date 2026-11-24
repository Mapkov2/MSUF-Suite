-- Retail and WoW Forever keep their own cooldown manager and action bars in
-- profile strings (MSUF_Suite/Core/ProfileClients.lua). Two worlds model the
-- two clients, each with its own saved variables and MSUF frame profiles:
-- every import path, round trips in both directions, the fallback to the
-- profile's own data and to the defaults, older strings, malformed parts,
-- factory installs, resets and the action bars a string offers.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
C_CVar = { GetCVar = function() return nil end }
local Suite, encodings = {}, {}
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return false end
UnitGUID = function(unit) return unit == "player" and "Player-1-00000001" or nil end
Minimap = { SetMaskTexture = function() end }
C_AddOns = { DoesAddOnExist = function() return false end, IsAddOnLoaded = function() return false end }
MapkoSkin = setmetatable({}, { __index = function() error("profiles read the skin owner") end })
Enum = { CompressionMethod = { Deflate = 1 } }
C_Timer = { After = function() end }
MSUF_EncodeCompactTable = function(value, prefix)
    assert(prefix == "MSUF3")
    encodings[#encodings + 1] = value
    return "MSUF3:" .. #encodings
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end
-- Decoding gives a new table, as MSUF's codec does; "MSUF3:frames" is an
-- MSUF frame profile without variants.
MSUF_TryDecodeCompactString = function(text)
    if text == "MSUF3:frames" then return {} end
    return Copy(encodings[tonumber(text:match("^MSUF3:(%d+)$"))])
end
-- MSUF's frame strings carry the MSUF frame profile (its profile variants too).
local frameImports = {}
MSUF_Profiles_ExportSelectionToString = function(kind)
    assert(kind == "all")
    return MSUF_EncodeCompactTable(Copy(MSUF_GlobalDB.profiles[MSUF_ActiveProfile]), "MSUF3")
end
MSUF_Profiles_ImportIntoNewProfile = function(name, text)
    local profile = MSUF_TryDecodeCompactString(text)
    if type(profile) ~= "table" or profile.refused then return false, "bad frames" end
    assert(MSUF_GlobalDB.profiles[name] == nil)
    frameImports[#frameImports + 1] = text
    MSUF_GlobalDB.profiles[name] = profile
    MSUF_ActiveProfile = name
    return true
end
MSUF_SwitchProfile = function(name)
    if not MSUF_GlobalDB.profiles[name] then return false end
    MSUF_ActiveProfile = name
    return true
end
MSUF_DeleteProfile = function(name) assert(name ~= MSUF_ActiveProfile) MSUF_GlobalDB.profiles[name] = nil return true end
MSUF_GlobalDB, MSUF_ActiveProfile = { profiles = { Default = {} } }, "Default"
Support.Load(root, "MSUF_Suite", Suite, "Core/ProfileVariants.lua")
local P, DB, IO, Clients = Suite.SuiteProfiles, Suite.Database, Suite.ProfileIO, Suite.ProfileClients
assert(Clients, "ProfileClients.lua is not in the Suite's TOC before ProfileIO.lua")
local S = Suite.Suite
local CDM = "cooldownManager"

local function Check(condition, message)
    if not condition then error(message, 2) end
end

------------------------------------------------------------------ two clients
local worlds, current = {}, nil
local function World(client)
    if current then
        worlds[current] = { root = Suite.RootDB, global = MSUF_GlobalDB, active = MSUF_ActiveProfile }
    end
    current = client
    Suite.Client.isForever = client == "forever"
    local world = worlds[client]
    if world then
        MSUF_GlobalDB, MSUF_ActiveProfile = world.global, world.active
        assert(DB.Initialize(world.root))
    else
        MSUF_GlobalDB, MSUF_ActiveProfile = { profiles = { Default = {} } }, "Default"
        assert(DB.Initialize(nil))
        S.Normalize(Suite.DB)
    end
end

local function Cooldowns(name)
    local profile = name and DB.GetProfile(name) or Suite.DB
    profile.suite.modules[CDM] = profile.suite.modules[CDM] or {}
    return profile.suite.modules[CDM]
end

-- A recognizable cooldown manager: its bar contents, per-spell choices,
-- layouts and one flat setting.
local function SetCooldowns(tag, perRow, name)
    local config = Cooldowns(name)
    config.listsData, config.spellsData, config.positionsData = tag .. "-lists", tag .. "-spells", tag .. "-layouts"
    config.uti_perRow = perRow
end

local function Same(config, tag, perRow)
    return config.listsData == tag .. "-lists" and config.spellsData == tag .. "-spells"
        and config.positionsData == tag .. "-layouts" and config.uti_perRow == perRow
end

local function Parked(config)
    local text = config.clientParked
    if text == nil or text == "" then return nil end
    return encodings[tonumber(text:match("^MSUF3:(%d+)$"))]
end

local function Envelope(text)
    return encodings[tonumber(text:match("MSUFM[12]:MSUF3:(%d+)"))]
end

------------------------------------------------------------------ catalog
local rules = Suite.SuiteCatalog[CDM].rules
Check(rules.clientParked and rules.clientParked.hidden and rules.clientParked.profileData and rules.clientParked.otherClient
    and rules.clientParked.maxLength == IO.maxExportBytes, "the cooldown manager has no hidden, parked setting for the other client")
Check(Suite.CDM.DEFAULTS_KEEP.clientParked, "a defaults migration would reset the other client's cooldown manager")
local barRules = Suite.SuiteCatalog.actionbars.rules
Check(barRules.parkedSetup and barRules.parkedSetup.hidden and barRules.parkedSetup.profileData
    and barRules.parkedSetup.otherClient, "the action bars have no hidden, parked setup for the other client")
Check(barRules.profileKeybinds.hidden, "the retired key binding choice is still shown")

------------------------------------------------------------------ round trip
-- Retail exports; WoW Forever imports into a new profile and keeps its own
-- cooldown manager; WoW Forever exports; Retail imports and is back at the
-- state it exported, with WoW Forever's parked; and once more the other way.
World("retail")
SetCooldowns("R0", 5)
Suite.DB.suite.modules.minimap.size = 211
local retailString = assert(P.Export())
local envelope = Envelope(retailString)
Check(envelope.client == "retail" and envelope.profile.suite.modules[CDM].listsData == "R0-lists",
    "the Retail string did not name its client or lost its cooldown manager")

World("forever")
SetCooldowns("F0", 8)
assert(P.Import("From Retail", retailString))
Check(DB.GetActiveProfileName() == "From Retail", "the import did not activate its profile")
Check(Same(Cooldowns(), "F0", 8), "WoW Forever lost its own cooldown manager to the Retail string")
local parked = Parked(Cooldowns())
Check(parked and parked.client == "retail" and Same(parked.settings, "R0", 5) and parked.settings.clientParked == nil
    and parked.revision == envelope.profile.suite.revision, "WoW Forever did not park Retail's cooldown manager")
Check(Suite.DB.suite.modules.minimap.size == 211, "the import lost the string's other settings")
Check(Same(Cooldowns("Default"), "F0", 8) and Parked(Cooldowns("Default")) == nil, "the import changed the profile it came from")
SetCooldowns("F1", 9)
local foreverString = assert(P.Export())
Check(Envelope(foreverString).client == "forever", "the WoW Forever string did not name its client")

World("retail")
SetCooldowns("R9", 3)
assert(P.Import("Back", foreverString))
Check(Same(Cooldowns(), "R0", 5), "Retail was not back at the state it exported")
parked = Parked(Cooldowns())
Check(parked and parked.client == "forever" and Same(parked.settings, "F1", 9), "Retail did not park WoW Forever's cooldown manager")
Check(Same(Cooldowns("Default"), "R9", 3), "the import changed Retail's other profile")
local again = assert(P.Export())

World("forever")
assert(P.Import("Again", again))
Check(Same(Cooldowns(), "F1", 9) and Same(Parked(Cooldowns()).settings, "R0", 5),
    "the second round trip lost a client's cooldown manager")

------------------------------------------------------------------ fallbacks
-- Without its own part in the string a client keeps the profile's, and a
-- profile without one has the defaults; a string without the other
-- client's part keeps the profile's parked one.
-- A Retail string that carries no WoW Forever part.
local plain = { addon = "MSUF_Suite", format = 1, client = "retail",
    profile = { suite = { schema = 1, revision = S.MigrationRevision, modules = { [CDM] = { listsData = "R5-lists",
        spellsData = "R5-spells", positionsData = "R5-layouts", uti_perRow = 6 } } } } }
local fresh = "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(plain, "MSUF3")
World("forever")
local defaults = Suite.Defaults.suite.modules[CDM]
assert(P.Activate("Default"))
SetCooldowns("F4", 7)
Suite.DB.suite.modules[CDM] = nil
assert(P.Import("Defaults", fresh))
Check(Cooldowns().listsData == defaults.listsData and Cooldowns().uti_perRow == defaults.uti_perRow
    and Same(Parked(Cooldowns()).settings, "R5", 6), "a client without data of its own did not get the defaults")
local raw = Parked(Cooldowns()).settings
local count = 0
for _ in pairs(raw) do count = count + 1 end
Check(count == 4 and raw.ess_size == nil, "the other client's part was not parked as it came")
World("retail")
assert(P.Activate("Back"))
local stored = Cooldowns().clientParked
assert(P.Import("Plain", fresh))
Check(Same(Cooldowns(), "R5", 6) and Cooldowns().clientParked == stored,
    "a string without the other client's part did not keep the profile's parked one as it was")

------------------------------------------------------------------ module strings
-- A WoW Forever cooldown manager string parks only: Retail's stays; one
-- that carries Retail's part sets it.
World("forever")
assert(P.Activate("From Retail"))
Cooldowns().clientParked = ""
SetCooldowns("F7", 11)
local foreverModule = assert(P.ExportModule(CDM))
Check(Envelope(foreverModule).client == "forever", "a module string did not name its client")
World("retail")
assert(P.Activate("Default"))
SetCooldowns("R9", 3)
assert(P.ImportModule(foreverModule))
Check(Same(Cooldowns(), "R9", 3) and Same(Parked(Cooldowns()).settings, "F7", 11),
    "a WoW Forever module string changed Retail's cooldown manager or was not parked")
World("forever")
assert(P.Activate("Again"))
local carrying = assert(P.ExportModule(CDM))
World("retail")
assert(P.ImportModule(carrying))
Check(Same(Cooldowns(), "R0", 5) and Same(Parked(Cooldowns()).settings, "F1", 9),
    "a module string with Retail's part did not bring it back")
-- The stepped import and the import into a new profile take the same way.
SetCooldowns("R9", 3)
Cooldowns().clientParked = ""
local job = assert(P.BeginImport(foreverModule))
local done, ok
repeat done, ok = job:Step() until done
Check(ok and Same(Cooldowns(), "R9", 3) and Same(Parked(Cooldowns()).settings, "F7", 11), "the stepped module import differs")
assert(P.ImportModuleIntoNew("Module copy", carrying))
Check(DB.GetActiveProfileName() == "Module copy" and Same(Cooldowns(), "R0", 5)
    and Same(Parked(Cooldowns()).settings, "F1", 9), "the module import into a new profile differs")
job = assert(P.BeginImport(foreverString, "Stepped"))
repeat done, ok = job:Step() until done
Check(ok and DB.GetActiveProfileName() == "Stepped" and Same(Cooldowns(), "R0", 5)
    and Same(Parked(Cooldowns()).settings, "F1", 9), "the stepped full import differs")

------------------------------------------------------------------ older strings
-- A string of an older build names no client: with a key map it belongs to
-- that map's client, else to the importing one (as before).
World("forever")
assert(P.Activate("Default"))
SetCooldowns("F2", 4)
Cooldowns().clientParked = ""
local untagged = { addon = "MSUF_Suite", format = 1, profile = plain.profile }
assert(P.Import("Untagged", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(untagged, "MSUF3")))
Check(Same(Cooldowns(), "R5", 6) and Parked(Cooldowns()) == nil, "an untagged string did not import as before")
assert(P.Activate("Default"))
local keyed = { addon = "MSUF_Suite", format = 1, profile = plain.profile, actionBarKeys = { retail = { Q = "ACTIONBUTTON1" } } }
assert(P.Import("Keyed", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(keyed, "MSUF3")))
Check(Same(Cooldowns(), "F2", 4) and Same(Parked(Cooldowns()).settings, "R5", 6),
    "an older Retail string with a key map replaced WoW Forever's cooldown manager")

------------------------------------------------------------------ malformed parts
-- A malformed part of a string fails the import and changes nothing; a
-- malformed parked value of the profile itself counts as none.
assert(P.Activate("Default"))
local profiles = 0
for _ in pairs(Suite.RootDB.profiles) do profiles = profiles + 1 end
local broken = Suite.CopyValue(plain)
broken.profile.suite.modules[CDM].clientParked = "MSUF3:" .. #encodings + 100
local brokenText = "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(broken, "MSUF3")
local imported, why = P.Import("Broken", brokenText)
local after = 0
for _ in pairs(Suite.RootDB.profiles) do after = after + 1 end
Check(not imported and why == "Invalid settings of the other WoW version" and after == profiles
    and DB.GetActiveProfileName() == "Default", "a malformed parked part was imported: " .. tostring(why))
local badBars = Suite.CopyValue(plain)
badBars.actionBars = { forever = { keys = "not a map" } }
imported, why = P.Import("Broken", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(badBars, "MSUF3"))
Check(not imported and why == "Invalid action bars", "malformed action bars were imported")
local future = Suite.CopyValue(plain)
future.actionBars = { classic = { keys = "unknown client" } }
assert(P.Import("Future", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(future, "MSUF3")),
    "the action bars of a client this build does not know failed the import")
assert(P.Activate("Default"))
Cooldowns().clientParked = "MSUF3:" .. #encodings + 200
assert(P.Import("Own broken", fresh), "a malformed parked value of the profile failed the import")
local stale = MSUF_EncodeCompactTable({ v = 1, client = "retail", settings = { listsData = "x" } }, "MSUF3")
broken.profile.suite.modules[CDM].clientParked = stale
broken.client = "forever"
-- The other client's part travels on as it came; only that client checks it.
assert(P.Import("Stale", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(broken, "MSUF3")),
    "a readable parked part of the other client failed the import")
Check(Cooldowns().clientParked == stale, "the other client's parked part was changed on the way")
-- A Retail string's own parked value names Forever; one naming Retail is not
-- the string's other part and gives way to the string's settings.
broken.client = "retail"
assert(P.Import("Stale 2", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(broken, "MSUF3")))
Check(Cooldowns().clientParked ~= stale and Cooldowns().clientParked ~= "",
    "a Retail string's own settings were not parked")

------------------------------------------------------------------ migrations
-- Parked settings run the migrations their revision still lacks when they
-- come back.
local old = MSUF_EncodeCompactTable({ v = 1, client = "retail", revision = 0, settings = { listsData = "R3-lists",
    spellsData = "R3-spells", positionsData = "R3-layouts", uti_perRow = 2 } }, "MSUF3")
local carryOld = Suite.CopyValue(plain)
carryOld.client = "forever"
carryOld.profile.suite.modules[CDM].clientParked = old
World("retail")
assert(P.Import("Migrated", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(carryOld, "MSUF3")))
Check(Same(Cooldowns(), "R3", 2) and Cooldowns().clientParked ~= "", "an old parked part did not come back")
-- Migration step 23 (CooldownSpecLayouts) starts per-spec layouts for a
-- shared layout without saved layouts: it runs only on parts made before it.
local function Unpark(revision)
    carryOld.profile.suite.modules[CDM].clientParked = MSUF_EncodeCompactTable({ v = 1, client = "retail",
        revision = revision, settings = { listsData = "R4-lists", specPositions = false, positionsData = "" } }, "MSUF3")
    assert(P.Import("Spec " .. revision, "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(carryOld, "MSUF3")))
    return Cooldowns().listsData == "R4-lists" and Cooldowns().specPositions
end
Check(Unpark(22) == true, "a parked part skipped a migration its revision still lacks")
Check(Unpark(S.MigrationRevision) == false, "a parked part ran a migration it already had")

------------------------------------------------------------------ resets and factories
-- A module reset keeps the other client's parked settings (and whether the
-- module runs); a factory profile keeps the parked values of the profile it
-- replaces or starts from.
assert(P.Activate("Back"))
local before = Cooldowns().clientParked
Check(before ~= "" and S.Reset(CDM), "the reset fixture has no parked settings")
Check(Cooldowns().clientParked == before and Cooldowns().listsData == defaults.listsData,
    "the reset dropped the other client's cooldown manager or kept this client's lists")
local parkedBars = MSUF_EncodeCompactTable({ v = 1, client = "forever", setup = { keys = { E = "ACTIONBUTTON3" } } }, "MSUF3")
Suite.DB.suite.modules.actionbars.parkedSetup = parkedBars
local factory = { suite = { schema = 1, revision = S.MigrationRevision, modules = { [CDM] = { listsData = "Factory-lists" } } } }
assert(P.InstallFactory("Factory", "MSUF3:frames", factory))
Check(Cooldowns().listsData == "Factory-lists" and Cooldowns().clientParked == before
    and Suite.DB.suite.modules.actionbars.parkedSetup == parkedBars,
    "a factory profile dropped the other client's parked values")
assert(P.InstallSuiteFactory("Back", factory))
Check(DB.GetActiveProfileName() == "Back" and Cooldowns().clientParked == before,
    "a factory installed over a profile dropped its parked values")
-- Parked values a factory itself brings never count: the profile's stay, or none.
local baked = MSUF_EncodeCompactTable({ v = 1, client = "forever", revision = S.MigrationRevision,
    settings = { listsData = "Baked" } }, "MSUF3")
local bakedBars = MSUF_EncodeCompactTable({ v = 1, client = "forever", setup = { keys = { R = "ACTIONBUTTON4" } } }, "MSUF3")
local bakedFactory = Suite.CopyValue(factory)
bakedFactory.suite.modules[CDM].clientParked = baked
bakedFactory.suite.modules.actionbars = { parkedSetup = bakedBars }
assert(P.InstallFactory("Factory 2", "MSUF3:frames", bakedFactory))
Check(Cooldowns().clientParked == before and Suite.DB.suite.modules.actionbars.parkedSetup == parkedBars,
    "a factory's own parked values replaced the profile's")
Cooldowns().clientParked, Suite.DB.suite.modules.actionbars.parkedSetup = "", ""
assert(P.InstallFactory("Factory 3", "MSUF3:frames", bakedFactory))
Check(Cooldowns().clientParked == "" and Suite.DB.suite.modules.actionbars.parkedSetup == "",
    "a factory brought parked values of its own")
-- The action bar reset keeps the other client's action bars; MSUF's profile
-- reset keeps both parked values.
assert(P.Activate("Back"))
Check(Suite.DB.suite.modules.actionbars.parkedSetup == parkedBars and S.Reset("actionbars")
    and Suite.DB.suite.modules.actionbars.parkedSetup == parkedBars, "the action bar reset dropped the other client's action bars")
Cooldowns().listsData = "Before reset"
assert(P.OnLifecycle("reset", "Back"))
Check(Cooldowns().clientParked == before and Cooldowns().listsData == defaults.listsData
    and Suite.DB.suite.modules.actionbars.parkedSetup == parkedBars, "MSUF's profile reset dropped the parked values")

------------------------------------------------------------------ unknown clients and limits
-- A string of a client this build does not know has no part of this one:
-- this client's settings stay those of the profile it starts from.
local unknown = Suite.CopyValue(plain)
unknown.client = "classic"
unknown.profile.suite.modules[CDM].listsData = "Classic-lists"
assert(P.Import("Unknown", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(unknown, "MSUF3")))
Check(Cooldowns().listsData == defaults.listsData and Cooldowns().clientParked == before,
    "a string of an unknown client changed this client's cooldown manager or its parked one")
-- A stored parked value nobody can read is dropped, not carried on.
assert(P.Activate("Back"))
Cooldowns().clientParked = "MSUF3:" .. #encodings + 300
local own = Suite.CopyValue(plain)
own.profile.suite.modules[CDM].clientParked = ""
assert(P.Import("Own unreadable", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(own, "MSUF3")))
Check(Cooldowns().clientParked == "", "an unreadable stored parked value was carried on")
assert(P.Activate("Back"))
Cooldowns().clientParked = before
-- A parked value longer than its setting fails the import instead of
-- being cut.
local rule = Suite.SuiteCatalog[CDM].rules.clientParked
local limit = rule.maxLength
rule.maxLength = #"MSUF3:"
World("forever")
local tooLarge, large = P.Import("Too large", fresh)
rule.maxLength = limit
Check(not tooLarge and large == "Suite profile is too large", "a parked value over its limit was imported: " .. tostring(large))
World("retail")
assert(P.Activate("Back"))

------------------------------------------------------------------ profile variants
-- What an MSUF profile variant sets of the cooldown manager belongs to its
-- client: a bundle of the other client parks the string's own fields with
-- its cooldown manager and brings this client's back into the variants of
-- the same name, from the string's parked part, else from the MSUF profile
-- the import starts from. Every other variant field imports as it is.
local function Variant(name, fields)
    local patch = { { path = { "general", "x" }, value = 4, remove = false } }
    for key, value in pairs(fields) do
        patch[#patch + 1] = { path = { "suiteModules", CDM, key }, value = value, remove = false }
    end
    return { name = name, enabled = true, conditions = { context = "party" }, patch = patch }
end
local function SetVariants(entries)
    MSUF_GlobalDB.profiles[MSUF_ActiveProfile].profileVariants = { version = 1, entries = entries }
end
-- The cooldown manager fields of variant name of an MSUF profile, and how
-- many other fields it has.
local function VariantFields(profile, name)
    local fields, others = {}, 0
    for _, entry in ipairs(MSUF_GlobalDB.profiles[profile].profileVariants.entries) do
        if entry.name == name then
            for _, field in ipairs(entry.patch) do
                if field.path[1] == "suiteModules" and field.path[2] == CDM then
                    fields[field.path[3]] = field.value
                else
                    others = others + 1
                end
            end
        end
    end
    return fields, others
end
local function ParkedVariant(name)
    local value = {}
    for _, field in ipairs(((Parked(Cooldowns()) or {}).variants or {})[name] or {}) do value[field.key] = field.value end
    return value
end
World("retail")
assert(P.Activate("Default"))
Cooldowns().clientParked = ""
SetVariants({ Variant("Dungeon", { cdColor = "ff0000" }), Variant("Raid", { stackColor = "00ff00" }) })
local retailVariants = assert(P.Export())
World("forever")
assert(P.Activate("Default"))
SetVariants({ Variant("Dungeon", { cdColor = "0000ff" }) })
assert(P.Import("Var F", retailVariants))
local dungeon, others = VariantFields("Var F", "Dungeon")
local raid, raidOthers = VariantFields("Var F", "Raid")
Check(dungeon.cdColor == "0000ff" and others == 1 and next(raid) == nil and raidOthers == 1,
    "WoW Forever's variants took Retail's cooldown manager fields or lost their own or other fields")
Check(ParkedVariant("Dungeon").cdColor == "ff0000" and ParkedVariant("Raid").stackColor == "00ff00",
    "WoW Forever did not park the cooldown manager fields of Retail's variants")
local foreverVariants = assert(P.Export())
World("retail")
SetVariants({ Variant("Dungeon", { cdColor = "123456" }) })
assert(P.Import("Var R", foreverVariants))
dungeon, others = VariantFields("Var R", "Dungeon")
raid = VariantFields("Var R", "Raid")
Check(dungeon.cdColor == "ff0000" and others == 1 and raid.stackColor == "00ff00",
    "Retail's variants did not get their cooldown manager fields back from the round trip")
Check(ParkedVariant("Dungeon").cdColor == "0000ff" and next(ParkedVariant("Raid")) == nil,
    "Retail did not park the cooldown manager fields of WoW Forever's variants")
-- A string of this client imports its frame profile as it is.
local sameClient = assert(P.Export())
assert(P.Import("Var R2", sameClient))
Check(frameImports[#frameImports] == sameClient:match("^MSUFS2:([^\n]+)"), "a string of this client had its frames rewritten")
-- A cooldown manager string has no variants: the parked fields stay.
World("forever")
local foreverModule = assert(P.ExportModule(CDM))
World("retail")
assert(P.Activate("Var R"))
assert(P.ImportModule(foreverModule))
Check(ParkedVariant("Dungeon").cdColor == "0000ff", "a cooldown manager string dropped the parked variant fields")
-- The parked fields go with the variants an import brings: without them
-- (MSUF's Import profile variants off, a frame string without variants, a
-- module string, also of this client) the stored ones stay.
local function Bundle(frames, envelope)
    return "MSUFS2:" .. MSUF_EncodeCompactTable(frames, "MSUF3") .. "\nMSUFM1:" .. MSUF_EncodeCompactTable(envelope, "MSUF3")
end
local function ParkFields(color)
    Cooldowns().clientParked = MSUF_EncodeCompactTable({ v = 1, client = "forever", revision = S.MigrationRevision,
        settings = { listsData = "F9-lists" }, variants = { Dungeon = { { key = "cdColor", value = color } } } }, "MSUF3")
end
ParkFields("abcdef")
local importVariants = true
MSUF_NS.ProfileImportReview = { ImportOptions = function() return importVariants, true end }
importVariants = false
assert(P.Import("Var off", foreverVariants))
Check(ParkedVariant("Dungeon").cdColor == "abcdef" and frameImports[#frameImports] == foreverVariants:match("^MSUFS2:([^\n]+)"),
    "with variants not imported, the string's variant fields were parked or its frames rewritten")
importVariants = true
local retailModule = assert(P.ExportModule(CDM))
ParkFields("fedcba")
assert(P.ImportModule(retailModule))
Check(ParkedVariant("Dungeon").cdColor == "fedcba", "a cooldown manager string of this client replaced the parked variant fields")
local plainFrames = Copy(Envelope(sameClient))
assert(P.Import("Var plain", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(plainFrames, "MSUF3")))
Check(ParkedVariant("Dungeon").cdColor == "fedcba", "a string without variants replaced the parked variant fields")
-- A string of this client with variants brings its parked fields along.
local withParked = Copy(Envelope(sameClient))
withParked.profile.suite.modules[CDM].clientParked = MSUF_EncodeCompactTable({ v = 1, client = "forever",
    revision = S.MigrationRevision, settings = { listsData = "F8-lists" },
    variants = { Dungeon = { { key = "cdColor", value = "0a0a0a" } } } }, "MSUF3")
assert(P.Import("Var own", Bundle({ profileVariants = { version = 1, entries = { Variant("Dungeon", { cdColor = "111111" }) } } },
    withParked)))
Check(ParkedVariant("Dungeon").cdColor == "0a0a0a" and VariantFields("Var own", "Dungeon").cdColor == "111111",
    "a string of this client did not bring its parked variant fields or changed its own")
-- Only fields this client's variants may set come back; a variant MSUF
-- keeps waiting (its aura part, _msufAuraClients) gets a variant of its own
-- name, place and conditions, without a key binding another one has.
local waiting = Copy(Envelope(foreverVariants))
waiting.profile.suite.modules[CDM].clientParked = MSUF_EncodeCompactTable({ v = 1, client = "retail",
    revision = S.MigrationRevision, settings = { listsData = "R7-lists" }, variants = {
        Dungeon = { { key = "cdColor", value = "ff0000" }, { key = "listsData", value = "x" }, { key = "noSuchKey", value = 1 } },
        Arena = { { key = "stackColor", value = "00ff00" } } } }, "MSUF3")
local frames = { profileVariants = { version = 1, entries = { Variant("Dungeon", { cdColor = "0000ff" }),
    { name = "Other", enabled = true, conditions = {}, hotkey = 2, patch = { { path = { "general", "x" }, value = 1, remove = false } } } } },
    _msufAuraClients = { version = 1, clients = { Mainline = { profileVariants = { version = 1, entries = { { name = "Arena",
        enabled = true, conditions = { context = "arena" }, hotkey = 2, auraOrder = 1,
        patch = { { path = { "auras3", "shared", "iconSize" }, value = 49, remove = false } } } } } } } } }
assert(P.Import("Var wait", Bundle(frames, waiting)))
dungeon = VariantFields("Var wait", "Dungeon")
local arena = MSUF_GlobalDB.profiles["Var wait"].profileVariants.entries[1]
Check(dungeon.cdColor == "ff0000" and dungeon.listsData == nil and dungeon.noSuchKey == nil,
    "a field this client's variants may not set came back")
Check(arena.name == "Arena" and arena.hotkey == nil and arena.conditions.context == "arena" and #arena.patch == 1
    and arena.patch[1].path[3] == "stackColor" and arena.patch[1].value == "00ff00",
    "a variant MSUF keeps waiting did not get its cooldown manager fields back")
-- Also when the string has no variants besides the waiting ones.
frames.profileVariants = nil
assert(P.Import("Var wait 2", Bundle(frames, waiting)))
arena = (MSUF_GlobalDB.profiles["Var wait 2"].profileVariants or { entries = {} }).entries[1]
Check(arena and arena.name == "Arena" and arena.patch[1].path[3] == "stackColor",
    "a waiting variant of a string without other variants did not get its cooldown manager fields back")
assert(P.Activate("Back"))

------------------------------------------------------------------ action bars
-- Full profiles carry the exporting character's action bars. Their spells
-- belong to the client: the other client parks them, and they are offered
-- back on their own. The exporter's key bindings come along on either
-- client (offered, never written without the player's answer).
local asked = 0
local live = { keys = { Q = "ACTIONBUTTON1" }, slots = { [1] = 133 }, class = "MAGE", spec = 63, label = "Fire" }
Suite.ActionBarSnapshots = {
    ProfileSetup = function() return Suite.CopyValue(live) end,
    AskProfileSetup = function() asked = asked + 1 return true end,
}
local function Offer()
    local offer = Suite.RootDB.actionBarOffer
    Suite.RootDB.actionBarOffer = nil
    return offer and offer.setup, offer
end
local function ParkedBars()
    return encodings[tonumber(Suite.DB.suite.modules.actionbars.parkedSetup:match("^MSUF3:(%d+)$"))]
end
Suite.RootDB.actionBarOffer = nil
-- A Retail string with WoW Forever's parked action bars: WoW Forever is
-- offered its own spells back with the exporter's key bindings, and parks
-- Retail's bars.
Suite.DB.suite.modules.actionbars.parkedSetup = MSUF_EncodeCompactTable({ v = 1, client = "forever",
    setup = { keys = { E = "ACTIONBUTTON3" }, slots = { [2] = 5143 }, class = "MAGE", group = 1, label = "Primary" } }, "MSUF3")
local carriedBars = assert(P.Export())
World("forever")
Suite.RootDB.actionBarOffer = nil
assert(P.Import("Bars first", carriedBars))
local setup, offer = Offer()
Check(asked == 1 and offer.client == "forever" and setup.slots[2] == 5143 and setup.class == "MAGE" and setup.group == 1
    and setup.label == "Primary", "WoW Forever was not offered its own parked spells")
Check(setup.keys.Q == "ACTIONBUTTON1" and setup.keys.E == nil and setup.slots[1] == nil,
    "the exporter's key bindings did not come along, or Retail's spells did")
Check(ParkedBars().client == "retail" and ParkedBars().setup.slots[1] == 133 and ParkedBars().setup.keys.Q == "ACTIONBUTTON1",
    "WoW Forever did not park Retail's action bars")
-- A Retail string without a part for WoW Forever: the key bindings alone
-- are offered there, the bars are parked.
World("retail")
asked = 0
Suite.DB.suite.modules.actionbars.parkedSetup = ""
local withBars = assert(P.Export())
Check(Envelope(withBars).actionBars.retail.slots[1] == 133, "the full Retail profile lost its action bars")
World("forever")
live = { keys = { E = "ACTIONBUTTON3" }, slots = { [2] = 5143 }, class = "MAGE", group = 1 }
assert(P.Import("Bars", withBars))
setup, offer = Offer()
Check(asked == 1 and offer.client == "forever" and setup.keys.Q == "ACTIONBUTTON1" and setup.slots == nil
    and setup.independentSlots == nil and setup.class == nil,
    "WoW Forever was not offered the Retail key bindings alone")
Check(ParkedBars().client == "retail" and ParkedBars().setup.slots[1] == 133, "WoW Forever did not park Retail's action bars")
-- Back on Retail: its own spells from the parked part, the key bindings of
-- the WoW Forever exporter.
local foreverBars = assert(P.Export())
World("retail")
assert(P.Import("Bars back", foreverBars))
setup, offer = Offer()
Check(asked == 2 and offer.client == "retail" and offer.guid == "Player-1-00000001"
    and setup.slots[1] == 133 and setup.spec == 63 and setup.slots[2] == nil, "Retail's own spells were not offered back")
Check(setup.keys.E == "ACTIONBUTTON3" and setup.keys.Q == nil, "the WoW Forever exporter's key bindings did not come along")
Check(ParkedBars().client == "forever" and ParkedBars().setup.slots[2] == 5143, "Retail did not park WoW Forever's action bars")
-- An exporter without key bindings: the ones this client parked stand in.
World("forever")
live = { keys = {}, slots = { [2] = 5143 }, class = "MAGE", group = 1 }
local noKeys = assert(P.Export())
World("retail")
assert(P.Import("Bars no keys", noKeys))
setup = Offer()
Check(setup and setup.keys.Q == "ACTIONBUTTON1" and setup.slots[1] == 133,
    "without key bindings of the exporter the parked ones did not stand in")
-- Key maps of older builds: one per client stays with its client; one of the
-- other client alone comes along like an exporter's.
local older = Suite.CopyValue(plain)
older.client = nil
older.actionBarKeys = { retail = { R = "ACTIONBUTTON4" }, forever = { F = "ACTIONBUTTON5" } }
assert(P.Import("Bars old", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(older, "MSUF3")))
setup = Offer()
Check(setup and setup.keys.R == "ACTIONBUTTON4" and setup.keys.F == nil, "an older string's key map of this client was not offered")
older.actionBarKeys = { forever = { F = "ACTIONBUTTON5" } }
assert(P.Import("Bars old 2", "MSUFS2:MSUF3:frames\nMSUFM1:" .. MSUF_EncodeCompactTable(older, "MSUF3")))
setup = Offer()
Check(setup and setup.keys.F == "ACTIONBUTTON5" and setup.slots == nil, "an older string's key map of the other client did not come along")
asked = 1
-- An import that fails offers nothing.
Suite.RootDB.actionBarOffer = nil
-- MSUF refuses the string's frames after the Suite routed them.
local failing = foreverBars:gsub("^MSUFS2:[^\n]+", "MSUFS2:" .. MSUF_EncodeCompactTable({ refused = true }, "MSUF3"))
Check(failing ~= foreverBars and not P.Import("Bars failed", failing) and asked == 1 and Suite.RootDB.actionBarOffer == nil,
    "a failed import offered its action bars")
Suite.ActionBarSnapshots = nil

Check(#reported == 0, "an import step raised: " .. table.concat(reported, "\n"))
print("suite_profile_clients_contract: ok (round trips, fallbacks, module strings, older strings, malformed parts, "
    .. "migrations, resets, factories, unknown clients, limits, profile variants, action bars)")
