-- One profile name rule for MSUF, the Suite and the skin: the real Suite
-- core (Profiles.lua) drives the real skin profile store. A name the Suite
-- accepts (up to 80 bytes, outer spaces allowed) reaches the skin unchanged,
-- so switching, copying, renaming and deleting keep both stores in step.
-- Skin profiles that earlier builds stored under a cut name get their full
-- name back at load.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

-- The client's securecallfunction reports an error and returns nothing.
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
Minimap = { SetMaskTexture = Noop }
C_AddOns = { DoesAddOnExist = function() return false end, IsAddOnLoaded = function() return false end }
MSUF_GlobalDB, MSUF_ActiveProfile = { profiles = { Default = {} } }, "Default"

------------------------------------------------------------------ core
local Suite = Support.Load(root, "MSUF_Suite", {}, "Core/ProfileVariants.lua")
_G.MSUFSuite = Suite
local P, DB = Suite.SuiteProfiles, Suite.Database

------------------------------------------------------------------ skin
local skin = {
    Client = { isForever = false, isMainline = true },
    IsCombatLocked = function() return false end,
    FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
    Theme = { RefreshDynamicLook = Noop },
    Typography = { Restore = Noop, ApplyConfigured = Noop },
    Adapters = { ApplyAll = Noop },
    Registry = { RefreshAll = Noop, NotifyListeners = Noop },
}
for _, file in ipairs({ "Defaults", "DefaultsLooks", "Database", "DatabaseProfiles", "ProfileIO", "Safety" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/" .. file .. ".lua"))("MSUF_Suite_Skin", skin)
end
skin.addonName = "MSUF_Suite_Skin"
MapkoSkin = skin
local Skin = skin.Database
local function Marked(marker)
    local profile = skin.CopyValue(skin.Defaults)
    profile.theme.colors.accent[1] = marker
    return profile
end
local function Marker(name)
    local profile = Skin.GetProfile(name)
    return profile and profile.theme.colors.accent[1]
end

local function Boot(suiteRoot, skinRoot)
    MSUFSuiteDB, MSUFSuiteSkinDB = nil, skinRoot
    assert(DB.Initialize(suiteRoot))
    MSUFSuiteDB = Suite.RootDB
    Skin.Initialize()
end

------------------------------------------------------------------ switching
local long = string.rep("L", 50)
local padded = "  Raid team "
Boot(nil, nil)
Check(P.SyncActive(long) and DB.GetActiveProfileName() == long and Skin.GetActiveProfileName() == long,
    "a 50-byte profile did not reach the skin under its own name")
Check(P.SyncActive("Default") and Skin.GetActiveProfileName() == "Default", "the switch back failed")
Check(P.SyncActive(long) and Skin.GetActiveProfileName() == long,
    "the second switch to a long profile failed in the skin")
Check(P.SyncActive(padded) and Skin.GetActiveProfileName() == padded and Skin.GetProfile(padded),
    "a space-padded Suite name reached the skin under another name")
Check(P.SyncActive("Default") and P.SyncActive(padded), "the second switch to a padded profile failed")
local names = Skin.GetProfileNames()
Check(#names == 3, "the skin gained profiles that no Suite profile uses: " .. table.concat(names, "|"))

------------------------------------------------------------------ lifecycle
local copy, renamed = string.rep("C", 60), string.rep("R", 70)
P.SyncActive("Default")
Skin.SetProfile(long, Marked(0.31))
Check(P.OnLifecycle("copy", long, copy) and Marker(copy) == 0.31 and Marker(long) == 0.31,
    "copying a long profile did not copy its skin profile")
Check(P.OnLifecycle("rename", copy, renamed) and Marker(renamed) == 0.31 and not Skin.GetProfile(copy),
    "renaming a long profile orphaned its skin profile")
Check(P.OnLifecycle("delete", renamed) and not Skin.GetProfile(renamed) and not DB.GetProfile(renamed),
    "deleting a long profile left its skin profile behind")
Check(not Skin.GetProfile(string.rep("C", 40)) and not Skin.GetProfile(string.rep("R", 40)),
    "a lifecycle step stored a skin profile under a cut name")

------------------------------------------------------------------ names the skin refuses
Check(not Skin.CreateProfile(string.rep("x", 81)) and not Skin.CreateProfile("   ")
    and not Skin.CreateProfile("bad\nname"), "the skin took a name the Suite refuses")
for _, name in ipairs({ string.rep("x", 80), " a ", "Raid", string.rep("x", 81), "", "\t", "a\1b" }) do
    Check(Skin.IsProfileName(name) == DB.IsProfileName(name), "the skin and the Suite disagree on " .. name)
end
Check(Skin.NormalizeProfileName("  Typed\1 name  ") == "Typed name"
    and #Skin.NormalizeProfileName(string.rep("y", 100)) == DB.MAX_PROFILE_NAME_BYTES,
    "a typed or imported name was not trimmed to a valid name")

------------------------------------------------------------------ earlier cut names
-- Saved by a build that cut names to 40 bytes and trimmed outer spaces.
local cutLong = long:sub(1, 40)
local savedSuite = { schema = 1, activeProfile = long, profiles = {
    Default = { suite = { schema = 1, modules = {} } },
    [long] = { suite = { schema = 1, modules = {} } },
    [padded] = { suite = { schema = 1, modules = {} } },
} }
local savedSkin = { schema = 1, activeProfile = cutLong, profiles = {
    Default = Marked(0.1), [cutLong] = Marked(0.4), ["Raid team"] = Marked(0.6),
} }
Boot(savedSuite, savedSkin)
Check(Marker(long) == 0.4 and Marker(padded) == 0.6,
    "a skin profile saved under a cut name did not get its full name back")
Check(Marker(cutLong) == 0.4 and Marker("Raid team") == 0.6 and Marker("Default") == 0.1,
    "restoring full names dropped a saved skin profile")
Check(P.SyncActive(long) and Skin.GetActiveProfileName() == long,
    "the restored long profile did not activate")
Check(#reported == 0, "a profile step raised: " .. tostring(reported[1]))
print("Suite skin profile names: " .. checks .. " checks passed")
