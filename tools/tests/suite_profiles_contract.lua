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
Suite.DB.suite.modules.objectives.enabled = true
Suite.DB.suite.modules.objectives.titleSize = 21
Suite.DB.suite.modules.objectives.objectiveSize = 14
Suite.DB.suite.modules.objectives.focusedColor = "a1b2c3"
Suite.DB.suite.modules.announcements.enabled = true
Suite.DB.suite.modules.announcements.subtitleSize = 18
Suite.DB.suite.modules.announcements.zoneColor = "d4e5f6"
local bundle = assert(P.Export())
assert(bundle:match("^MSUFS2:MSUF3:frames\nMSUFM1:MSUF3:"))
assert(P.Import("Shared", bundle))
assert(P.Active() == "Shared" and not Suite.DB.suite.modules.qol.repair
    and not Suite.DB.suite.modules.combatLog.enabled)
assert(Suite.DB.suite.modules.minimap.enabled)
assert(Suite.DB.suite.modules.objectives.enabled
    and Suite.DB.suite.modules.objectives.titleSize == 21
    and Suite.DB.suite.modules.objectives.objectiveSize == 14
    and Suite.DB.suite.modules.objectives.focusedColor == "a1b2c3"
    and Suite.DB.suite.modules.announcements.enabled
    and Suite.DB.suite.modules.announcements.subtitleSize == 18
    and Suite.DB.suite.modules.announcements.zoneColor == "d4e5f6",
    "full profile export/import lost the new HUD settings")
assert(DB.GetProfile("Raid").suite.modules.qol.repair)
assert(P.InstallFactory("FactoryRetail", "MSUF3:frames", DB.GetProfile("Raid"), nil))
assert(P.Active() == "FactoryRetail" and Suite.DB.suite.modules.qol.repair
    and Suite.DB.suite.modules.combatLog.enabled,
    "trusted factory import lost its selected module values")
assert(P.Activate("Shared"))
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
assert(P.InstallFactory("RetailForever", "MSUF3:frames", DB.GetProfile("Raid"), nil))
assert(external == 2 and P.Active() == "RetailForever"
    and Suite.DB.suite.modules.qol.repair,
    "Retail host did not install the complete trusted Forever factory")
assert(not P.Import("MainBroken", (bundle:gsub("^MSUFS2:MSUF3:frames", "MSUFS2:MSUF3:broken"))))
assert(external == 3 and P.Active() == "RetailForever" and not MSUF_GlobalDB.profiles.MainBroken and not DB.GetProfile("MainBroken"))
local switch = MSUF_SwitchProfile
MSUF_SwitchProfile = function(name) if name == "MainSwitch" then return false end;return switch(name) end
assert(not P.Import("MainSwitch", bundle))
assert(P.Active() == "RetailForever" and not MSUF_GlobalDB.profiles.MainSwitch and not DB.GetProfile("MainSwitch"))
MSUF_SwitchProfile, MSUF_Profiles_ImportIntoNewProfile, MSUF_Profiles_ImportExternal = switch, classicImport, nil
local minimap = assert(P.ExportModule("minimap"))
assert(minimap:match("^MSUFM2:MSUF3:"), "module export has no standalone prefix")
Suite.DB.suite.modules.minimap.enabled = false
assert(P.ImportModule(minimap) and Suite.DB.suite.modules.minimap.enabled,
    "single-module import failed to restore its setting")
Suite.DB.suite.modules.objectives.titleSize = 23
Suite.DB.suite.modules.objectives.focusedColor = "b2c3d4"
local hudModule = assert(P.ExportModule("objectives"))
Suite.DB.suite.modules.objectives.titleSize = 12
Suite.DB.suite.modules.objectives.focusedColor = "ffffff"
assert(P.ImportModule(hudModule)
    and Suite.DB.suite.modules.objectives.titleSize == 23
    and Suite.DB.suite.modules.objectives.focusedColor == "b2c3d4",
    "single-module HUD export/import lost typography or colors")
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
        skinProfiles[name] = copy and Suite.CopyValue(skinProfiles[skinActive]) or { look = "default" }
        return true, name
    end,
    SetProfile = function(name, profile)
        skinProfiles[name] = Suite.CopyValue(profile)
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
        return Suite.CopyValue(profile)
    end,
}
MapkoSkin = skin
local addonEnabled = Suite.Client.AddOnEnabled
Suite.Client.AddOnEnabled = function() return true end
encodings[#encodings + 1] = {
    look = "modern",
    icons = { microMenu = { layoutPoint = "BOTTOM", layoutX = 900, scale = 0.7 } },
    windowControls = { positions = { CharacterFrame = { x = 1000 } } },
}
local modernSkin = "MSKIN1:" .. #encodings
local beforeModernFrames = frameImports
assert(P.InstallSuiteFactory("Default", DB.GetProfile("Raid"), modernSkin))
assert(frameImports == beforeModernFrames and MSUF_ActiveProfile == "ModuleCopy"
    and skinProfiles.Default.look == "modern", "Modern import changed MSUF frames or missed Skin")
local meter = DB.GetProfile("Raid").suite.modules.damageMeter
local meterLeft = math.min(meter.w1X - meter.w1Width, meter.w2X - meter.w2Width)
assert(skinProfiles.Default.icons.microMenu.layoutPoint == "BOTTOMRIGHT"
    and skinProfiles.Default.icons.microMenu.layoutX == meterLeft
    and skinProfiles.Default.icons.microMenu.layoutY == 0
    and skinProfiles.Default.icons.microMenu.scale == 0.7
    and not next(skinProfiles.Default.windowControls.positions),
    "Modern Skin menu is not beside the Damage Meter")
Suite.RootDB.installation = { status = "complete", profile = "suite" }
skinProfiles.Default.icons.microMenu.layoutPoint = "BOTTOMLEFT"
skinProfiles.Default.icons.microMenu.layoutRelativePoint = "BOTTOMLEFT"
skinProfiles.Default.icons.microMenu.layoutX = 18
skinProfiles.Default.icons.microMenu.layoutY = 18
Suite.Client.AddOnEnabled = addonEnabled
assert(P.SyncActive("Default") and skinActive == "Default")
assert(skinProfiles.Default.icons.microMenu.layoutPoint == "BOTTOMRIGHT"
    and skinProfiles.Default.icons.microMenu.layoutX == meterLeft
    and skinProfiles.Default.icons.microMenu.layoutY == 0
    and Suite.RootDB.installation.frameProfileName == "Default"
    and Suite.RootDB.installation.modernMeterMenuRevision == 2,
    "previous Modern installs were not moved beside the Damage Meter")
Suite.RootDB.installation.modernMeterMenuRevision = 1
skinProfiles.Default.icons.microMenu.layoutX = meterLeft - 12
skinProfiles.Default.icons.microMenu.layoutY = 18
assert(P.SyncActive("Default")
    and skinProfiles.Default.icons.microMenu.layoutX == meterLeft
    and skinProfiles.Default.icons.microMenu.layoutY == 0
    and Suite.RootDB.installation.modernMeterMenuRevision == 2,
    "previous meter-gap correction was not updated to the supplied profile position")
assert(P.SyncActive("ModuleCopy") and skinActive == "ModuleCopy")
skinProfiles.ModuleCopy.icons = { microMenu = {
    positionPreset = "custom", layoutPoint = "BOTTOMLEFT", layoutRelativePoint = "BOTTOMLEFT",
    layoutX = 18, layoutY = 18,
} }
Suite.RootDB.installation.modernMeterMenuRevision = 1
assert(P.SyncActive("ModuleCopy") and skinActive == "ModuleCopy"
    and skinProfiles.ModuleCopy.icons.microMenu.layoutPoint == "BOTTOMLEFT",
    "unrelated MSUF profile had its micro menu moved by the Modern repair")
Suite.RootDB.installation.modernMeterMenuRevision = 2
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

-- One-time migrations never run again on a copy: export -> import -> export
-- is lossless, also for values that an older build would still migrate.
local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function Encoded(text) return encodings[tonumber(text:match("(%d+)$"))] end
local S = Suite.Suite
local live = Suite.DB.suite.modules
live.chat.look, live.damageMeter.look, live.dataTexts.look, live.xpBar.look = 2, 2, 2, 2
live.xpBar.point, live.xpBar.x, live.xpBar.y = 8, 0, 148
live.objectives.titleSize, live.objectives.sectionSize = 16, 16
live.objectives.colorStyle, live.objectives.backgroundOpacity = 1, 82
live.announcements.subtitleSize = 15
local firstExport = assert(IO.ExportProfile())
assert(DB.CreateFromProfile("RoundTrip", assert(IO.PrepareProfile(firstExport, false))))
local secondExport = assert(IO.ExportProfile("RoundTrip"))
assert(Same(Encoded(firstExport), Encoded(secondExport)), "export -> import -> export changed the profile")
local copied = DB.GetProfile("RoundTrip").suite
assert(copied.revision == S.MigrationRevision
    and copied.modules.chat.look == 2 and copied.modules.damageMeter.look == 2
    and copied.modules.dataTexts.look == 2 and copied.modules.xpBar.look == 2
    and copied.modules.xpBar.point == 8 and copied.modules.xpBar.y == 148
    and copied.modules.objectives.titleSize == 16 and copied.modules.objectives.sectionSize == 16
    and copied.modules.objectives.backgroundOpacity == 82
    and copied.modules.announcements.subtitleSize == 15,
    "a copied profile ran one-time migrations again")
local saved = assert(IO.PrepareTable(Suite.DB, false))
assert(Same(saved.suite.modules, live), "Save As copy ran one-time migrations again")
local chatModule = assert(IO.ExportModule("chat"))
live.chat.look = 1
assert(P.ImportModule(chatModule) and live.chat.look == 2, "module import ran one-time migrations again")
-- Strings from older builds still migrate exactly once: without any state
-- (all steps) or with the per-step flags they were saved with.
encodings[#encodings + 1] = { addon = "MSUF_Suite", format = 1, profile = { suite = { schema = 1, modules = {
    chat = { look = 2, panelColor = "14181b" }, objectives = { titleSize = 16 },
} } } }
local legacyText = IO.prefix .. "MSUF3:" .. #encodings
local legacy = assert(IO.PrepareProfile(legacyText, false))
assert(legacy.suite.revision == S.MigrationRevision and legacy.suite.modules.chat.look == 3
    and legacy.suite.modules.objectives.titleSize == 18, "an old profile string was not migrated")
assert(DB.CreateFromProfile("LegacyOnce", legacy))
local legacyAgain = assert(IO.PrepareProfile(assert(IO.ExportProfile("LegacyOnce")), false))
assert(legacyAgain.suite.modules.chat.look == 3 and legacyAgain.suite.modules.objectives.titleSize == 18,
    "an imported old profile migrated twice")
encodings[#encodings + 1] = { addon = "MSUF_Suite", format = 1, profile = { suite = {
    schema = 1, lookPresetRevision = 1, modules = { chat = { look = 3 }, objectives = { titleSize = 16 } },
} } }
local flagged = assert(IO.PrepareProfile(IO.prefix .. "MSUF3:" .. #encodings, false))
assert(flagged.suite.modules.chat.look == 3 and flagged.suite.modules.objectives.titleSize == 18
    and flagged.suite.lookPresetRevision == nil and flagged.suite.revision == S.MigrationRevision,
    "per-step flags of an older string were not honored")
-- Forever-only steps do not re-enable modules on a copy either.
Suite.Client.isForever = true
live.actionbars.enabled, live.objectives.enabled, live.announcements.enabled = false, false, false
local foreverCopy = assert(IO.PrepareTable(Suite.DB, false)).suite.modules
Suite.Client.isForever = false
assert(not foreverCopy.actionbars.enabled and not foreverCopy.objectives.enabled
    and not foreverCopy.announcements.enabled, "a Forever copy switched modules back on")

C_EncodingUtil = nil
assert(not P.Export())
assert(not DB.Delete("SwitchOnly") and DB.GetProfile("SwitchOnly"), "the active profile was deleted")
encodings[#encodings + 1] = {
    look = "forever",
    icons = { microMenu = {
        layoutPoint = "BOTTOMLEFT", layoutRelativePoint = "BOTTOMLEFT",
        layoutX = 1791, layoutY = 20, positionPreset = "custom",
    } },
    windowControls = { positions = { CharacterFrame = { x = 333 } } },
}
local foreverSkin = "MSKIN1:" .. #encodings
assert(P.InstallFactory("ForeverFactorySkin", "MSUF3:frames", DB.GetProfile("Raid"), foreverSkin))
local factoryMenu = skinProfiles.ForeverFactorySkin.icons.microMenu
assert(factoryMenu.layoutPoint == "BOTTOMLEFT" and factoryMenu.layoutRelativePoint == "BOTTOMLEFT"
    and factoryMenu.layoutX == 1791 and factoryMenu.layoutY == 20
    and not next(skinProfiles.ForeverFactorySkin.windowControls.positions),
    "Forever installer overwrote the supplied Skin menu position")
-- The first Suite install repairs a character that MSUF already bound to
-- Default, then leaves deliberate account defaults and later changes alone.
local newCharacterDefault
MSUF_GetDefaultProfileForNewCharacters = function() return newCharacterDefault end
MSUF_SetDefaultProfileForNewCharacters = function(name)
    assert(MSUF_GlobalDB.profiles[name])
    newCharacterDefault = name
    return true
end
MSUF_ProfileWasUnboundAtLogin = true
MSUF_SwitchProfile("Default")
Suite.RootDB.installation = { status = "complete", profile = "suite", frameProfileName = "Raid" }
assert(P.EnsureNewCharacterProfile() and newCharacterDefault == "Raid"
    and MSUF_ActiveProfile == "Raid" and Suite.RootDB.installation.newCharacterProfileRevision == 1,
    "new character did not receive the installed frame profile")
assert(Suite.RootDB.installation.newCharacterProfileOwned == true)
newCharacterDefault = nil
MSUF_SwitchProfile("Default")
assert(not P.EnsureNewCharacterProfile() and newCharacterDefault == nil
    and MSUF_ActiveProfile == "Default", "a cleared preference was overwritten")
newCharacterDefault = "Shared"
Suite.RootDB.installation = { status = "complete", profile = "suite", frameProfileName = "Raid" }
assert(not P.EnsureNewCharacterProfile() and newCharacterDefault == "Shared"
    and MSUF_ActiveProfile == "Default" and Suite.RootDB.installation.newCharacterProfileRevision == 1,
    "an existing MSUF new-character preference was overwritten")
assert(Suite.RootDB.installation.newCharacterProfileOwned ~= true)
Suite.Client.isMainline = true
Suite.DB.suite.modules.cooldownManager = { enabled = true }
MSUF_DB = { bars = { classPowerAnchorToCooldown = false, classPowerOffsetY = 280 },
    player = { powerBarDetached = true, detachedPowerBarAnchorToClassPower = true } }
local resourceRefresh = 0
MSUF_ClassPower_Apply = function() resourceRefresh = resourceRefresh + 1 end
Suite.RootDB.installation = { status = "complete", profile = "suite" }
assert(P.EnsureRetailResourceStack(false) and MSUF_DB.bars.classPowerAnchorToCooldown
    and MSUF_DB.bars.classPowerCooldownTopAnchor and MSUF_DB.bars.classPowerOffsetY == 0
    and MSUF_DB.player.detachedPowerBarAnchorToClassPower
    and resourceRefresh == 1 and Suite.RootDB.installation.resourceStackRevision == 1,
    "old Modern setup did not attach the resource stack above Essential")
MSUF_DB.bars.classPowerOffsetY = 12
assert(not P.EnsureRetailResourceStack(false) and MSUF_DB.bars.classPowerOffsetY == 12,
    "a later personal resource offset was overwritten")
assert(P.EnsureRetailResourceStack(true) and MSUF_DB.bars.classPowerOffsetY == 0,
    "rerunning Modern did not restore its resource defaults")
MSUF_DB = { bars = { classPowerOffsetY = -41 }, player = {} }
Suite.RootDB.installation = { status = "complete", profile = "forever" }
assert(P.EnsureRetailResourceStack(false) and MSUF_DB.bars.classPowerAnchorToCooldown
    and MSUF_DB.player.powerBarDetached and MSUF_DB.player.detachedPowerBarAnchorToClassPower,
    "old Retail Forever did not receive the CDM resource stack")
Suite.Client.isForever = true
MSUF_DB = { bars = { classPowerOffsetY = -41 }, player = {} }
Suite.RootDB.installation = { status = "complete", profile = "forever" }
assert(not P.EnsureRetailResourceStack(false) and MSUF_DB.bars.classPowerAnchorToCooldown == nil,
    "actual Forever client received a Retail-only resource migration")
Suite.Client.isForever = false
Suite.CDM = { DEFAULTS_VERSION = 3, FRAME_ANCHORS = { [14] = "player" } }
local foreverCooldowns = { enabled = true, ext_anchor = 3, ext_y = -380, defaultsVersion = 0 }
Suite.DB.suite.modules.cooldownManager = foreverCooldowns
Suite.RootDB.installation = { status = "complete", profile = "forever" }
assert(P.EnsureRetailForeverCooldownLayout() and foreverCooldowns.ext_anchor == 14
    and foreverCooldowns.ext_y == 0 and foreverCooldowns.def_anchor == 14
    and foreverCooldowns.captured == true and foreverCooldowns.defaultsVersion == 3,
    "old Retail Forever Potions did not move to Player")
foreverCooldowns.ext_anchor, foreverCooldowns.ext_y = 3, -100
Suite.RootDB.installation = { status = "complete", profile = "forever" }
assert(not P.EnsureRetailForeverCooldownLayout() and foreverCooldowns.ext_y == -100,
    "personal Forever Potions position was overwritten")
Suite.Client.isForever = true
foreverCooldowns.ext_y = -380
Suite.RootDB.installation = { status = "complete", profile = "forever" }
assert(not P.EnsureRetailForeverCooldownLayout() and foreverCooldowns.ext_anchor == 3,
    "actual Forever client received a Retail-only CDM anchor migration")
print("Standalone profiles: unified MSUF, module and skin sharing, lifecycle, migration, collision/combat guards, rollback and sanitization passed")
