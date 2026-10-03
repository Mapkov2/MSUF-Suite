-- MSUF profile rename across the three profile stores: MSUF's own, the Suite's
-- and the skin's (each keeps one profile per MSUF profile name).
--
--   lua tools/tests/suite_profile_rename_contract.lua <Suite root> <Classic MSUF root>
--
-- Loads the real MSUF State/MSUF_Profiles.lua of the Classic sibling, the real
-- MSUF_Suite Core/Database.lua and Core/Profiles.lua and the real skin
-- Core/DatabaseProfiles.lua. MSUF asks the Suite before it renames its own
-- profile; a Suite or skin profile that already has the new name is refused
-- there before anything moves (no store keeps the old settings behind, and
-- the next switch does not activate another profile's skin). A rename in
-- combat is refused the same way. An older MSUF that renames first and ignores
-- the answer keeps the previous best-effort move.

local root = assert(arg[1], "Suite root required"):gsub("\\", "/")
local hostRoot = assert(arg[2], "Classic MSUF root required"):gsub("\\", "/")
local function noop() end
local write = io.write

-- The client's securecallfunction reports an error and returns nothing.
local function dispatch(fn, ...)
    local results = { pcall(fn, ...) }
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, table.maxn(results))
end
local combat = false
InCombatLockdown = function() return combat end
UnitAffectingCombat = function() return combat end
GetRealmName = function() return "Realm" end
UnitName = function() return "Player" end
MSUF_GF_InvalidateConfCache = noop
local chat = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    chat[#chat + 1] = table.concat(parts, " ")
end
local function Said(fragment)
    for i = 1, #chat do if chat[i]:find(fragment, 1, true) then return true end end
    return false
end

-- MSUF: the real profile store with its runtime apply idle.
local host = {
    StateHelpers = {}, ProfileIOImportLimits = {},
    ProfileRuntime = { Apply = noop },
    Translate = function(text) return text end,
    ProfileNormalize = {},
    Require = function(name)
        assert(name == "MSUF_EnsureDB", name)
        return noop
    end,
    ExportPublic = function(name, value) _G[name] = value end,
    EventBus = { Register = noop },
}
MSUF_NS = host
assert(loadfile(hostRoot .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"))("MidnightSimpleUnitFrames", host)

-- The Suite and its skin store.
local suite = {
    Dispatch = dispatch, Finish = function(fn, ...) return true, fn(...) end,
    IsCombatLocked = InCombatLockdown,
    ProfileIO = {},
    OnProfileChanged = noop,
    Client = { AddOnEnabled = function() return false end },
}
suite.ProfileVariants = {
    CanMutate = function() return true end, OnActivated = noop,
    BaseProfile = function(name) return suite.CopyValue(suite.Database.GetProfile(name)) end,
}
MSUFSuite = suite
assert(loadfile(root .. "/MSUF_Suite/Core/Database.lua"))("MSUF_Suite", suite)
local skin = {
    addonName = "MSUF_Suite_Skin", Client = { isForever = false }, ProfileIO = {},
    Database = {}, CopyValue = suite.CopyValue, IsCombatLocked = InCombatLockdown,
    Safety = { Dispatch = dispatch },
    Typography = { Restore = noop, ApplyConfigured = noop },
    Theme = { RefreshDynamicLook = noop }, Adapters = { ApplyAll = noop },
    Registry = { RefreshAll = noop, NotifyListeners = noop },
}
-- Database.lua's schema check; the stores here hold valid profiles only.
skin.Database.SanitizeProfile = function(profile) return type(profile) == "table" and suite.CopyValue(profile) or nil end
MapkoSkin = skin
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DatabaseProfiles.lua"))("MSUF_Suite_Skin", skin)
assert(loadfile(root .. "/MSUF_Suite/Core/Profiles.lua"))("MSUF_Suite", suite)

local function Accent(r, g, b) return { theme = { colors = { accent = { r, g, b, 1 } } } } end
local function Fixture()
    suite.RootDB = { activeProfile = "A", profiles = {
        A = { suite = { schema = 1, modules = { chat = { marker = "A" } } } },
        Leftover = { suite = { schema = 1, modules = { chat = { marker = "Leftover" } } } },
    } }
    suite.DB = suite.RootDB.profiles.A
    skin.RootDB = { activeProfile = "A", profiles = { A = Accent(1, 0, 0), B = Accent(0, 0, 1) } }
    skin.DB = skin.RootDB.profiles.A
    MSUF_GlobalDB = { profiles = { Default = {}, A = { player = { width = 222 } } }, char = {
        ["Player-Realm"] = { activeProfile = "A", specProfileMap = { [1] = "A" } },
    }, global = { defaultProfileForNewChars = "A" } }
    MSUF_ActiveProfile, MSUF_DB = "A", MSUF_GlobalDB.profiles.A
    chat = {}
end
local function Unchanged(label)
    local frames, char = MSUF_GlobalDB.profiles, MSUF_GlobalDB.char["Player-Realm"]
    assert(frames.A == MSUF_DB and frames.A.player.width == 222 and MSUF_ActiveProfile == "A"
        and char.activeProfile == "A" and char.specProfileMap[1] == "A"
        and MSUF_GlobalDB.global.defaultProfileForNewChars == "A",
        label .. ": the MSUF profile moved although the rename was refused")
    assert(suite.Database.GetProfile("A").suite.modules.chat.marker == "A"
        and suite.Database.GetProfile("Leftover").suite.modules.chat.marker == "Leftover"
        and suite.Database.GetActiveProfileName() == "A",
        label .. ": the Suite profile moved although the rename was refused")
    assert(skin.Database.GetProfile("A").theme.colors.accent[1] == 1 and skin.Database.GetProfile("B").theme.colors.accent[3] == 1
        and skin.Database.GetActiveProfileName() == "A",
        label .. ": the skin profile moved although the rename was refused")
end

-- 1. A skin-only profile already has the new name: refused before anything
--    moves, and MSUF names the reason.
Fixture()
local renamed, why = MSUF_RenameProfile("A", "B")
assert(renamed == false and why == "profile-exists",
    "a rename onto a skin-only profile was not refused: " .. tostring(renamed) .. ", " .. tostring(why))
assert(not MSUF_GlobalDB.profiles.B and Said("Profile 'B' already exists."), "MSUF did not report the taken name")
Unchanged("skin-only collision")

-- 2. A Suite-only profile already has the new name: refused the same way.
Fixture()
renamed, why = MSUF_RenameProfile("A", "Leftover")
assert(renamed == false and why == "profile-exists" and not MSUF_GlobalDB.profiles.Leftover,
    "a rename onto a Suite-only profile was not refused")
Unchanged("Suite-only collision")

-- 3. In combat the Suite refuses every rename; MSUF stops with its combat line.
Fixture()
combat = true
renamed = MSUF_RenameProfile("A", "C")
combat = false
assert(renamed == false and not MSUF_GlobalDB.profiles.C and Said("Cannot change profiles while in combat."),
    "a rename in combat was not refused with the combat message")
Unchanged("combat")

-- 4. A free name: all three stores rename together and stay active.
Fixture()
assert(MSUF_RenameProfile("A", "C") == true, "a rename to a free name failed")
local char = MSUF_GlobalDB.char["Player-Realm"]
assert(MSUF_GlobalDB.profiles.C == MSUF_DB and not MSUF_GlobalDB.profiles.A and MSUF_ActiveProfile == "C"
    and char.activeProfile == "C" and char.specProfileMap[1] == "C"
    and MSUF_GlobalDB.global.defaultProfileForNewChars == "C", "MSUF did not rename its profile")
assert(suite.Database.GetProfile("C").suite.modules.chat.marker == "A" and not suite.Database.GetProfile("A")
    and suite.Database.GetActiveProfileName() == "C", "the Suite profile was not renamed with MSUF's")
assert(skin.Database.GetProfile("C").theme.colors.accent[1] == 1 and not skin.Database.GetProfile("A")
    and skin.Database.GetActiveProfileName() == "C", "the skin profile was not renamed with MSUF's")

-- 5. An older MSUF renames its own profile first, tells the Suite after and
--    ignores the answer: the Suite keeps the previous best-effort move.
Fixture()
MSUF_GlobalDB.profiles.B, MSUF_GlobalDB.profiles.A = MSUF_GlobalDB.profiles.A, nil
assert(suite.OnMSUFProfileLifecycle("rename", "A", "B") == true, "an older MSUF's rename was refused after the fact")
assert(suite.Database.GetProfile("B").suite.modules.chat.marker == "A" and not suite.Database.GetProfile("A")
    and skin.Database.GetProfile("A").theme.colors.accent[1] == 1 and skin.Database.GetProfile("B").theme.colors.accent[3] == 1,
    "an older MSUF's rename lost the previous best-effort move")

-- 6. An MSUF profile without a Suite or skin twin (made before the Suite was
--    installed) is refused a name the Suite or the skin holds just the same:
--    switching to it would activate that profile's settings.
for _, taken in ipairs({ "Leftover", "B" }) do
    Fixture()
    MSUF_GlobalDB.profiles.Pre = { player = { width = 99 } }
    renamed, why = MSUF_RenameProfile("Pre", taken)
    assert(renamed == false and why == "profile-exists" and MSUF_GlobalDB.profiles.Pre and not MSUF_GlobalDB.profiles[taken]
        and Said("Profile '" .. taken .. "' already exists."),
        "a profile without a twin was renamed onto the occupied name " .. taken)
    Unchanged("no twin, " .. taken)
end

-- 7. An over-long name from an older MSUF build (the Suite cannot store it)
--    can still be renamed to a valid one: the Suite has nothing to move, and
--    the switch gives the new name its Suite and skin profiles.
Fixture()
local long = string.rep("L", 81)
MSUF_GlobalDB.profiles[long], MSUF_GlobalDB.profiles.A = MSUF_GlobalDB.profiles.A, nil
MSUF_GlobalDB.char["Player-Realm"].activeProfile, MSUF_ActiveProfile = long, long
assert(MSUF_RenameProfile(long, "Recovered") == true, "an over-long older profile could not be renamed")
assert(MSUF_GlobalDB.profiles.Recovered == MSUF_DB and not MSUF_GlobalDB.profiles[long] and MSUF_ActiveProfile == "Recovered"
    and suite.Database.GetActiveProfileName() == "Recovered" and skin.Database.GetActiveProfileName() == "Recovered",
    "the recovered profile is not active in all three stores")

-- 8. A new name the Suite cannot store is refused with MSUF's name rule.
Fixture()
renamed, why = MSUF_RenameProfile("A", "Bad\1Name")
assert(renamed == false and why == "invalid-profile-name" and Said("Profile names can be at most 80 bytes long."),
    "a name the Suite cannot store was not refused with a reason")
Unchanged("invalid name")

-- 9. Without its database the Suite has nothing to keep aligned: the rename
--    goes ahead as it did before MSUF asked first.
Fixture()
suite.RootDB = nil
assert(MSUF_RenameProfile("A", "C") == true and MSUF_GlobalDB.profiles.C and MSUF_ActiveProfile == "C",
    "a rename was refused while the Suite had no database")

write("suite_profile_rename_contract: ok\n")
