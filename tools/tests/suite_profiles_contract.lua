local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Suite, combat, encodings, frameImports = {}, false, {}, 0
MSUF_NS = { Client = { Family = "Classic", Flavor = "Vanilla" } }
SlashCmdList = {}
InCombatLockdown = function() return combat end
Minimap = { SetMaskTexture = function() end }
MapkoSkin = setmetatable({}, { __index = function() error("profiles read the skin owner") end })
Enum = { CompressionMethod = { Deflate = 1 } }
C_EncodingUtil = {}
for _, name in ipairs({ "SerializeCBOR", "DeserializeCBOR", "EncodeBase64", "DecodeBase64", "CompressString", "DecompressString" }) do
    C_EncodingUtil[name] = function() error("native codec must be exercised by the MSUF codec owner") end
end
MSUF_EncodeCompactTable = function(value, prefix)
    assert(prefix == "MSUF3")
    encodings[#encodings + 1] = value
    return "MSUF3:" .. #encodings
end
MSUF_TryDecodeCompactString = function(text) return encodings[tonumber(text:match("^MSUF3:(%d+)$"))] end
MSUF_GlobalDB, MSUF_ActiveProfile = { profiles = { Default = {} } }, "Default"
MSUF_Profiles_ExportSelectionToString = function(kind) assert(kind == "all");return "MSUF3:frames" end
MSUF_Profiles_ImportIntoNewProfile = function(name, text)
    frameImports = frameImports + 1
    if text ~= "MSUF3:frames" then return false, "bad frames" end
    assert(MSUF_GlobalDB.profiles[name] == nil)
    MSUF_GlobalDB.profiles[name] = {}
    MSUF_ActiveProfile = name
    return true
end
MSUF_SwitchProfile = function(name)
    if not MSUF_GlobalDB.profiles[name] then return false end
    MSUF_ActiveProfile = name
    return true
end
MSUF_DeleteProfile = function(name) assert(name ~= MSUF_ActiveProfile);MSUF_GlobalDB.profiles[name] = nil;return true end
Support.Load(root, "MSUF_Suite", Suite, "Core/Profiles.lua", nil, "Vanilla")
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
local P, DB, IO = Suite.SuiteProfiles, Suite.Database, Suite.ProfileIO
Suite.DB.suite.modules.qol.repair = true
Suite.DB.suite.modules.combatLog.enabled = true
Suite.DB.suite.modules.minimap.enabled = true
assert(P.SaveAs(" Raid "))
assert(P.Active() == "Raid" and Suite.DB.suite.modules.qol.repair)
assert(Suite.DB ~= DB.GetProfile("Default"))
local bundle = assert(P.Export())
assert(bundle:match("^MSUFS2:MSUF3:frames\nMSUFM1:MSUF3:"))
assert(P.Import("Shared", bundle))
assert(P.Active() == "Shared" and not Suite.DB.suite.modules.qol.repair
    and not Suite.DB.suite.modules.combatLog.enabled)
assert(Suite.DB.suite.modules.minimap.enabled)
assert(DB.GetProfile("Raid").suite.modules.qol.repair)
local imports = frameImports
assert(not P.Import("Raid", bundle) and frameImports == imports)
assert(not P.Import("Broken", "MSUFS2:MSUF3:frames\nMSUFM1:MSUF3:missing"))
assert(frameImports == imports and not DB.GetProfile("Broken"))
combat = true
assert(not P.SaveAs("Combat") and not P.Activate("Default") and not P.Import("Combat", bundle))
assert(frameImports == imports and P.Active() == "Shared")
combat = false
local activate = DB.Activate
DB.Activate = function(name) if name == "Rollback" then return false, "injected activation failure" end;return activate(name) end
assert(not P.Import("Rollback", bundle))
assert(P.Active() == "Shared" and not DB.GetProfile("Rollback") and not MSUF_GlobalDB.profiles.Rollback)
DB.Activate = activate
assert(P.Activate("Default"))
local clean = assert(IO.PrepareTable({ suite = { schema = 1, modules = {
    minimap = { enabled = true, undocumented = "ignored" },
} }, theme = { arbitrary = true } }, false))
assert(clean.theme == nil and clean.suite.modules.minimap.undocumented == nil)
assert(not IO.PrepareTable({ suite = { schema = 2, modules = {} } }, true))
assert(not IO.PrepareTable({ suite = { schema = 1, modules = { minimap = { size = 0/0 } } } }, true))
encodings[#encodings + 1] = { addon = "MapkoSkin", format = 1, kind = "profile", payload = DB.GetProfile("Raid") }
assert(P.Import("Legacy", "MSUFS1:MSUF3:frames\nMSKIN1:" .. #encodings))
assert(Suite.DB.suite.modules.minimap.enabled and not Suite.DB.suite.modules.qol.repair)
-- Main MSUF has no transactional import. Its external import stores the new
-- profile without switching; a failed import or switch leaves nothing behind.
local classicImport = MSUF_Profiles_ImportIntoNewProfile
MSUF_Profiles_ImportIntoNewProfile = nil
assert(not P.Available(), "profiles claimed support without a frame import")
local external = 0
MSUF_Profiles_ImportExternal = function(text, name)
    external = external + 1
    assert(MSUF_ActiveProfile ~= name and MSUF_GlobalDB.profiles[name] == nil, "external import touched the active profile")
    if text ~= "MSUF3:frames" then return false, "bad frames" end
    MSUF_GlobalDB.profiles[name] = {}
    return true
end
assert(P.Available())
assert(P.Import("MainHost", bundle))
assert(external == 1 and P.Active() == "MainHost" and DB.GetProfile("MainHost"))
assert(not P.Import("MainBroken", (bundle:gsub("^MSUFS2:MSUF3:frames", "MSUFS2:MSUF3:broken"))))
assert(external == 2 and P.Active() == "MainHost" and not MSUF_GlobalDB.profiles.MainBroken and not DB.GetProfile("MainBroken"))
local switch = MSUF_SwitchProfile
MSUF_SwitchProfile = function(name) if name == "MainSwitch" then return false end;return switch(name) end
assert(not P.Import("MainSwitch", bundle))
assert(P.Active() == "MainHost" and not MSUF_GlobalDB.profiles.MainSwitch and not DB.GetProfile("MainSwitch"))
MSUF_SwitchProfile, MSUF_Profiles_ImportIntoNewProfile, MSUF_Profiles_ImportExternal = switch, classicImport, nil
local minimap = assert(P.ExportModule("minimap"))
assert(minimap:match("^MSUFM2:MSUF3:"), "module export has no standalone prefix")
Suite.DB.suite.modules.minimap.enabled = false
assert(P.ImportModule(minimap) and Suite.DB.suite.modules.minimap.enabled,
    "single-module import failed to restore its setting")
Suite.DB.suite.modules.dataTexts.bar1Slot4 = 11
Suite.DB.suite.modules.dataTexts.bar1StyleOverride = true
Suite.DB.suite.modules.dataTexts.bar1BackgroundTexture = "Flat"
Suite.DB.suite.modules.dataTexts.bar1TextOutline = 2
local dataTexts = assert(P.ExportModule("dataTexts"))
Suite.DB.suite.modules.dataTexts.bar1Slot4 = 1
Suite.DB.suite.modules.dataTexts.bar1StyleOverride = false
Suite.DB.suite.modules.dataTexts.bar1BackgroundTexture = ""
Suite.DB.suite.modules.dataTexts.bar1TextOutline = 1
assert(P.ImportModule(dataTexts) and Suite.DB.suite.modules.dataTexts.bar1Slot4 == 11
    and Suite.DB.suite.modules.dataTexts.bar1StyleOverride
    and Suite.DB.suite.modules.dataTexts.bar1BackgroundTexture == "Flat"
    and Suite.DB.suite.modules.dataTexts.bar1TextOutline == 2,
    "DataTexts places or own styling were not restored by module profile import")
assert(not P.ImportModule("MSUFM2:MSUF3:missing"), "invalid module import was accepted")
assert(P.ImportModuleIntoNew("ModuleCopy", minimap) and P.Active() == "ModuleCopy"
    and Suite.DB.suite.modules.minimap.enabled, "module import into a new unified profile failed")

local skinProfiles, skinActive = { Default = { look = "gold" } }, "Default"
local skin = { addonName = "MSUF_Suite_Skin", Defaults = { look = "default" } }
skin.Database = {
    GetActiveProfileName = function() return skinActive end,
    GetProfile = function(name) return skinProfiles[name] end,
    CreateProfile = function(name, copy)
        if skinProfiles[name] then return false, "exists" end
        skinProfiles[name] = { look = copy and skinProfiles[skinActive].look or "default" }
        return true, name
    end,
    SetProfile = function(name, profile)
        skinProfiles[name] = { look = profile.look }
        return true, name
    end,
    SetActiveProfile = function(name)
        if not skinProfiles[name] then return false, "missing" end
        skinActive = name
        return true, name
    end,
    DeleteProfile = function(name) skinProfiles[name] = nil; return true end,
}
skin.ProfileIO = {
    ExportProfile = function()
        encodings[#encodings + 1] = { look = skinProfiles[skinActive].look }
        return "MSKIN1:" .. #encodings
    end,
    PrepareProfile = function(text)
        local profile = encodings[tonumber(type(text) == "string" and text:match("^MSKIN1:(%d+)$"))]
        if not profile or type(profile.look) ~= "string" then return nil, "bad skin" end
        return { look = profile.look }
    end,
}
MapkoSkin = skin
assert(P.SyncActive("ModuleCopy") and skinActive == "ModuleCopy")
skinProfiles.ModuleCopy.look = "silver"
local fullSkin = assert(P.Export())
assert(fullSkin:match("^MSUFS3:MSUF3:frames\nMSUFM1:MSUF3:%d+\nMSKIN1:%d+$"),
    "full Suite export omitted skinning")
local beforeSkinImport = frameImports
assert(not P.Import("BadSkin", fullSkin:gsub("MSKIN1:%d+$", "MSKIN1:99999"))
    and frameImports == beforeSkinImport and not DB.GetProfile("BadSkin")
    and not MSUF_GlobalDB.profiles.BadSkin, "invalid skin payload mutated profiles")
skinProfiles.SkinCollision = { look = "old" }
assert(not P.Import("SkinCollision", fullSkin)
    and not DB.GetProfile("SkinCollision") and not MSUF_GlobalDB.profiles.SkinCollision
    and skinProfiles.SkinCollision.look == "old", "skin name collision was not rejected before mutation")
local skinOnly = assert(P.ExportModule("skin"))
skinProfiles.ModuleCopy.look = "blue"
assert(P.ImportModule(skinOnly) and skinProfiles.ModuleCopy.look == "silver",
    "single skin import did not restore its profile")
assert(P.Import("SkinBundle", fullSkin) and P.Active() == "SkinBundle"
    and skinActive == "SkinBundle" and skinProfiles.SkinBundle.look == "silver",
    "full Suite import did not activate skinning with the unified profile")
assert(P.ImportModuleIntoNew("SkinOnly", skinOnly) and P.Active() == "SkinOnly"
    and skinActive == "SkinOnly" and skinProfiles.SkinOnly.look == "silver",
    "skin-only import into a new profile failed")
MSUF_GlobalDB.profiles.SwitchOnly = {}
MSUF_ActiveProfile = "SwitchOnly"
assert(P.SyncActive("SwitchOnly") and P.Active() == "SwitchOnly"
    and skinActive == "SwitchOnly", "MSUF profile selection did not sync both Suite databases")
assert(P.OnLifecycle("create", "Fresh") and DB.GetProfile("Fresh")
    and skinProfiles.Fresh and skinProfiles.Fresh.look == "default",
    "MSUF profile creation did not create fresh Suite settings")
Suite.Suite.Normalize(DB.GetProfile("Fresh"))
DB.GetProfile("Fresh").suite.modules.minimap.enabled = true
skinProfiles.Fresh.look = "red"
assert(P.OnLifecycle("reset", "Fresh") and DB.GetProfile("Fresh").suite.modules.minimap.enabled
    and skinProfiles.Fresh.look == "default", "MSUF profile reset did not reset Suite settings")
assert(P.OnLifecycle("copy", "SkinBundle", "Clone")
    and DB.GetProfile("Clone") ~= DB.GetProfile("SkinBundle")
    and skinProfiles.Clone.look == skinProfiles.SkinBundle.look,
    "MSUF profile copy did not copy the matching Suite and skin profiles")
assert(DB.Activate("Clone") and skin.Database.SetActiveProfile("Clone"))
assert(P.OnLifecycle("rename", "Clone", "Renamed")
    and DB.GetProfile("Renamed") and not DB.GetProfile("Clone")
    and DB.GetActiveProfileName() == "Renamed"
    and skinProfiles.Renamed and not skinProfiles.Clone and skinActive == "Renamed",
    "MSUF profile rename left Suite settings under the old name")
assert(P.SyncActive("SwitchOnly") and P.OnLifecycle("delete", "Renamed")
    and not DB.GetProfile("Renamed") and not skinProfiles.Renamed,
    "MSUF profile delete left orphan Suite settings")
C_EncodingUtil = nil
assert(not P.Export())
assert(not DB.Delete("SwitchOnly") and DB.GetProfile("SwitchOnly"), "the active profile was deleted")
print("Standalone profiles: unified MSUF, module and skin sharing, lifecycle, migration, collision/combat guards, rollback and sanitization passed")
