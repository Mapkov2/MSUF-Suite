local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local defaultCVars = { GetCVar = function() return nil end }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
C_CVar = defaultCVars
local Suite, combat, encodings, frameImports = {}, false, {}, 0
-- The client's securecallfunction reports an error to the error handler and
-- returns nothing; this harness models exactly that.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2)
end
-- Main MSUF (Retail-only) publishes no client model.
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
InCombatLockdown = function() return combat end
Minimap = { SetMaskTexture = function() end }
-- Neither MapkoSkin nor the Suite skin is installed.
C_AddOns = { DoesAddOnExist = function() return false end, IsAddOnLoaded = function() return false end }
MapkoSkin = setmetatable({}, { __index = function() error("profiles read the skin owner") end })
Enum = { CompressionMethod = { Deflate = 1 } }
C_EncodingUtil = {}
for _, name in ipairs({ "SerializeCBOR", "DeserializeCBOR", "EncodeBase64", "DecodeBase64", "CompressString", "DecompressString" }) do
    C_EncodingUtil[name] = function() error("native codec must be exercised by the MSUF codec owner") end
end
MSUF_EncodeCompactTable = function(value, prefix)
    assert(prefix == "MSUF3")
    encodings[#encodings + 1] = Suite.CopyValue(value)
    return "MSUF3:" .. #encodings
end
MSUF_TryDecodeCompactString = function(text) return Suite.CopyValue(encodings[tonumber(text:match("^MSUF3:(%d+)$"))]) end
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
Support.Load(root, "MSUF_Suite", Suite, "Core/ProfileVariants.lua")
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
local P, DB, IO = Suite.SuiteProfiles, Suite.Database, Suite.ProfileIO
local profiles, S = Suite.NameplateProfiles, Suite.Suite
local live = { nameplateDebuffPadding = "4", nameplateAuraScale = "1", nameplateEnemyNpcAuraDisplay = string.char(1) .. "A" }
C_CVar = {
    GetCVar = function(key) return live[key] end,
    GetCVarDefault = function(key) return key == "nameplateEnemyNpcAuraDisplay" and string.char(1) .. "G" or "1" end,
    SetCVar = function(key, value) assert(live[key] ~= nil) live[key] = value end,
}
S.Apply = function() return true end
local host = { general = { kickReadyStyle = "border", kickReadyShowNameplates = true },
    nameplates = { fontOverride = true, fontKey = "EXPRESSWAY", fontSize = 12, nameFontSize = 14, nameFormat = "FULL" } }
local available, fail, fontScope = true, false, true
Suite.HostBridge.HasNameplateSettings = function() return available end
Suite.HostBridge.HasNameplateFontSettings = function() return fontScope end
Suite.HostBridge.CaptureNameplateSettings = function()
    if not available then return nil, "unavailable" end
    local copy = Suite.CopyValue(host) copy.version = 1
    local exact = Suite.CopyValue(copy)
    exact.clear = {}
    for _, section in ipairs({ "general", "nameplates" }) do
        for _, key in ipairs(Suite.NameplateHostSettings.Keys(section)) do
            if exact[section][key] == nil then exact.clear[#exact.clear + 1] = section .. "." .. key end
        end
    end
    return copy, nil, exact
end
Suite.HostBridge.ApplyNameplateSettings = function(payload)
    if not available then return false, "unavailable" end
    if not payload then return true end
    if fail and payload.nameplates and payload.nameplates.fontSize == 44 then return false, "injected" end
    for _, section in ipairs({ "general", "nameplates" }) do
        for key, value in pairs(payload[section] or {}) do host[section][key] = Suite.CopyValue(value) end
    end
    for _, path in ipairs(payload.clear or {}) do
        local section, key = path:match("^(%a+)%.(%w+)$") host[section][key] = nil
    end
    return true
end
local function Decode(text)
    return assert(MSUF_TryDecodeCompactString(text:match("MSUFM2:(.+)")))
end
local function Encode(payload)
    return "MSUFM2:" .. MSUF_EncodeCompactTable(payload, "MSUF3")
end
local config = S.Config("nameplates")
config.enemyAurasOffsetX, config.enemyAurasOffsetY, config.auraDisplayEnabled = 37, -11, true
config.auraEnemyDotsSize, config.enemyHealthWidthDelta, config.enemyRoleColors = 29, 177, true
local original = assert(IO.ExportModule("nameplates"))
local packet = Decode(original)
assert(packet.nameplateShared.nameplates.fontSize == 12 and packet.nameplateShared.general.kickReadyStyle == "border",
    "full export dropped shared typography or interrupt settings")
local casting = Decode(assert(IO.ExportModule("nameplates", { nameplateSections = { casts = true } })))
assert(casting.settings.interruptFeedbackEnabled ~= nil and casting.settings.enemyNameDuringCast ~= nil
    and casting.settings.enemyHealthWidthDelta == nil, "cast feedback escaped its transfer group")
local selection = { nameplateSections = { auras = true } }
local partial = Decode(assert(IO.ExportModule("nameplates", selection)))
assert(partial.settings.enemyAurasOffsetX == 37 and partial.settings.enemyAurasOffsetY == -11)
assert(partial.settings.enemyHealthWidthDelta == nil and partial.nameplateCVars == nil and partial.nameplateShared == nil,
    "aura-only export included other scopes")
config.enemyAurasOffsetX, config.enemyHealthWidthDelta = 0, 200
assert(profiles.Apply(Encode(partial)))
assert(S.Config("nameplates").enemyAurasOffsetX == 37 and S.Config("nameplates").enemyHealthWidthDelta == 200,
    "aura-only import reset unselected layout settings")
local clear = profiles.FilterShared({ version = 1, clear = { "general.kickReadyStyle", "nameplates.fontKey" } }, { text = true })
assert(#clear.clear == 1 and clear.clear[1] == "nameplates.fontKey", "partial reset lost scope or reset an unrelated owner")
assert(IO.ApplyNameplateShared({ version = 1, nameplates = { fontSize = 18, nameFontSize = 19 } }))
assert(IO.ApplyNameplateShared({ version = 1, general = { kickReadyStyle = "fill" } }))
assert(Suite.DB.nameplateShared.nameplates.fontSize == 18, "cast-only import erased portable typography")
local changed = Decode(original)
changed.settings.enemyAurasOffsetX, changed.nameplateShared.nameplates.fontSize = 111, 44
changed.nameplateCVars.nameplateDebuffPadding = "22"
local beforeX, beforePadding, beforeFont = S.Config("nameplates").enemyAurasOffsetX, live.nameplateDebuffPadding, host.nameplates.fontSize
fail = true
assert(not P.ImportModule(Encode(changed)), "rejected shared settings were reported as successful")
assert(S.Config("nameplates").enemyAurasOffsetX == beforeX and live.nameplateDebuffPadding == beforePadding
    and host.nameplates.fontSize == beforeFont, "shared failure left partial module or native state")
local failedPoint = assert(P.CaptureWorkbenchSkin())
failedPoint.nameplateSharedExact = nil
failedPoint.nameplateShared.nameplates.fontSize = 44
failedPoint.nameplateCVars.nameplateDebuffPadding = "29"
failedPoint.suite.modules.nameplates.enemyAurasOffsetX = 222
assert(not P.RestoreWorkbenchSkin(failedPoint, nil, "profile-workbench"), "workbench accepted rejected shared settings")
assert(S.Config("nameplates").enemyAurasOffsetX == beforeX and live.nameplateDebuffPadding == beforePadding
    and host.nameplates.fontSize == beforeFont, "workbench shared failure left partial state")
fail = false
available, fontScope = false, false
assert(P.ImportModule(original), "older host cannot import a nameplate setup")
assert(Suite.DB.nameplateSharedPending and Suite.DB.nameplateShared.nameplates.fontSize == 12
    and IO.lastNameplateReport.skippedShared.general, "older host lost portable values or skipped-status feedback")
local portable = Suite.NameplatePortableText.Resolve()
assert(portable.fontSize == 12 and portable.nameDisplayMax == 12)
local oldFormatter = Suite.HostBridge.NameFormatter
Suite.HostBridge.NameFormatter = function() return { Shared = function() error("legacy shared font override") end } end
assert(Suite.NameplateText.Shared(S.Config("nameplates")).fontSize == 12,
    "a legacy shared formatter masked the portable nameplate font")
Suite.HostBridge.NameFormatter = oldFormatter
local formatted = Suite.NameplatePortableText.Format({}, "Ravenous Twilight Shadowcaster", "ABBREV", 12, true, "RIGHT")
assert(formatted == "R. T. Shadowcaster", "portable name formatting failed")
local umlaut = string.char(195, 132)
local same = Suite.NameplatePortableText.Format({}, umlaut .. "rgerliches Land", "CUT", 4, false, "RIGHT")
assert(same == umlaut .. "rge", "portable truncation split a UTF-8 character")
available, fontScope = true, true
CreateFrame = function() return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end } end
assert(IO.StartNameplateProfile())
assert(not Suite.DB.nameplateSharedPending and host.nameplates.fontSize == 12, "pending host settings were not applied on upgrade")
assert(DB.Create("Other", true))
local other = DB.GetProfile("Other")
other.nameplateCVars = { nameplateDebuffPadding = "16" }
other.suite.modules.nameplates.nativeProfileMode = 2
assert(DB.Activate("Other") and live.nameplateDebuffPadding ~= "16", "current-Blizzard mode was ignored")
other.nameplateCVars.nameplateDebuffPadding = "16"
assert(IO.ActivateNameplateCVars(other, true) and live.nameplateDebuffPadding == "16", "explicit import ignored native data")
local unavailable = Decode(assert(IO.ExportModule("nameplates")))
unavailable.nameplateCVars.nameplateMaxDistance = "48"
assert(P.ImportModule(Encode(unavailable)))
assert(Suite.DB.nameplateCVars.nameplateMaxDistance == "48"
    and Decode(assert(IO.ExportModule("nameplates"))).nameplateCVars.nameplateMaxDistance == "48",
    "unavailable native settings did not survive import and re-export")
assert(profiles.Save("Personal"))
local saved = assert(profiles.Read("saved:Personal"))
assert(profiles.Save("Duplicate", saved))
assert(profiles.Read("saved:Duplicate") == saved)
assert(profiles.Delete("saved:Personal") and not profiles.Read("saved:Personal"))
assert(not profiles.Delete("compact"), "built-in template was deleted")
local distinct = {}
for _, key in ipairs({ "compact", "tank", "dots", "pvp" }) do
    local builtin = Decode(assert(profiles.Read(key)))
    assert(builtin.nameplateShared.nameplates.fontKey == "EXPRESSWAY" and builtin.nameplateShared.general.kickReadyStyle == "border")
    assert(builtin.nameplateCVars.nameplateDebuffPadding == "1", "built-in inherited a native setting")
    distinct[key] = builtin.settings
end
assert(distinct.compact.enemyHealthWidthDelta == 120 and distinct.tank.enemyTankMode and distinct.dots.auraDisplayEnabled
    and distinct.pvp.focusScaleEnabled, "built-in templates are incomplete")
fontScope = false
fontScope = false
local beforeTypography = Suite.CopyValue(Suite.DB.nameplateShared)
Suite.DB.nameplateShared = { version = 1, nameplates = { fontOverride = false, fontSize = 35 } }
assert(Suite.NameplatePortableText.Stored() == nil, "inherited typography still used an imported override")
Suite.DB.nameplateShared = { version = 1, nameplates = {
    fontOverride = true, fontSlug = true, boldText = true, fontMonochrome = true, textBackdrop = true } }
local slug = Suite.NameplatePortableText.Resolve()
assert(slug.fontFlags == "OUTLINE,SLUG" and not slug.fontShadow, "portable SLUG differs from the host resolver")
Suite.DB.nameplateShared = beforeTypography
-- Template history is local to the profile and preserves sparse inheritance.
do
    local fontCapability = Suite.HostBridge.HasNameplateFontSettings
    Suite.HostBridge.HasNameplateFontSettings = function() return true end
    available = true
    host.nameplates = { fontSize = 17 }
    host.general = { kickReadyStyle = "border" }
    Suite.DB.nameplateShared = nil
    Suite.DB.nameplateSharedPending = nil
    Suite.DB.suite.moduleLooks = Suite.DB.suite.moduleLooks or {}
    Suite.DB.suite.moduleLooks.nameplates = "midnightDark"
    config = S.Config("nameplates")
    config.protectImport, config.nativeProfileMode = true, 2
    local ownerName = DB.GetActiveProfileName()
    assert(profiles.Apply(assert(profiles.Read("compact"))))
    assert(S.Config("nameplates").protectImport and S.Config("nameplates").nativeProfileMode == 2,
        "template changed profile import preferences")
    assert(profiles.CanRestore() and host.nameplates.fontKey == "EXPRESSWAY")
    assert(DB.Create("UndoOther", true) and DB.Activate("UndoOther"))
    assert(not profiles.CanRestore() and not profiles.RestorePrevious(), "template undo crossed profile ownership")
    assert(DB.Activate(ownerName) and profiles.RestorePrevious())
    assert(host.nameplates.fontSize == 17 and host.nameplates.fontKey == nil and host.general.kickReadyAutoSize == nil,
        "template undo pinned inherited host settings")
    assert(Suite.DB.nameplateShared == nil and Suite.DB.nameplateSharedPending == nil
        and Suite.DB.suite.moduleLooks.nameplates == "midnightDark", "template undo retained added metadata")
    assert(profiles.RestorePrevious() and host.nameplates.fontKey == "EXPRESSWAY", "template redo lost new settings")
    assert(profiles.RestorePrevious())
    Suite.HostBridge.HasNameplateFontSettings = fontCapability
end
-- Unsupported host sections retain exact stored history and merge into new profiles.
do
    available = false
    Suite.DB.nameplateShared = { version = 1, nameplates = { fontSize = 21 }, general = { kickReadyStyle = "border" } }
    Suite.DB.nameplateSharedPending = { nameplates = true }
    local point = assert(P.CaptureWorkbenchSkin())
    assert(IO.ApplyNameplateShared({ version = 1, nameplates = { fontSize = 44, fontKey = "EXPRESSWAY" } }))
    assert(P.RestoreWorkbenchSkin(point, nil, "profile-workbench"))
    assert(Suite.DB.nameplateShared.nameplates.fontSize == 21 and Suite.DB.nameplateShared.nameplates.fontKey == nil
        and Suite.DB.nameplateSharedPending.nameplates and not Suite.DB.nameplateSharedPending.general,
        "old-host Workbench restore retained later stored settings")
    assert(profiles.Apply(assert(profiles.Read("compact"))))
    assert(profiles.RestorePrevious())
    assert(Suite.DB.nameplateShared.nameplates.fontSize == 21 and Suite.DB.nameplateShared.nameplates.fontKey == nil
        and Suite.DB.nameplateSharedPending.nameplates and not Suite.DB.nameplateSharedPending.general,
        "old-host template undo retained later stored settings")
    casting.nameplateShared = { version = 1, general = { kickReadyStyle = "fill" }, clear = { "general.kickReadyOffsetX" } }
    assert(P.ImportModuleIntoNew("CastsOnlyNew", Encode(casting)))
    assert(Suite.DB.nameplateShared.nameplates.fontSize == 21 and Suite.DB.nameplateShared.general.kickReadyStyle == "fill"
        and Suite.DB.nameplateShared.clear[1] == "general.kickReadyOffsetX", "new-profile cast import erased inherited typography")
    local job = assert(P.BeginImport(Encode(casting), "CastsOnlyStaged"))
    local done, ok
    repeat done, ok = job:Step() until done
    assert(ok and Suite.DB.nameplateShared.nameplates.fontSize == 21, "staged cast import erased inherited typography")
    available = true
end
local textureRule = Suite.SuiteCatalog.nameplates.rules.enemyFillTexture
assert(profiles.SettingGroup("enemyFillTexture", textureRule) == "layout", "health textures exported as typography")
assert(not profiles.Save("Duplicate", saved), "save silently overwrote a named template")
assert(profiles.Save("Duplicate", saved, true), "explicit template update failed")
do
    local notify = Suite.ProfileVariants.AfterMutation
    local previousWidth = S.Config("nameplates").enemyHealthWidthDelta
    Suite.ProfileVariants.AfterMutation = function() error("injected post-commit redraw failure") end
    assert(profiles.Apply(assert(profiles.Read("compact"))) and profiles.CanRestore(),
        "post-commit redraw failure discarded committed template undo")
    assert(profiles.RestorePrevious() and S.Config("nameplates").enemyHealthWidthDelta == previousWidth,
        "post-commit redraw failure discarded completed template restore")
    Suite.ProfileVariants.AfterMutation = notify
end
do
    local oldProfile = DB.GetActiveProfileName()
    local oldMode = S.Config("nameplates").nativeProfileMode
    S.Config("nameplates").nativeProfileMode = 2
    local before = live.nameplateDebuffPadding
    local rejected = Decode(original)
    rejected.nameplateCVars.nameplateDebuffPadding = "37"
    rejected.nameplateShared.nameplates.fontSize = 44
    fail = true
    assert(not P.ImportModuleIntoNew("RejectedModeTwo", Encode(rejected)))
    assert(DB.GetActiveProfileName() == oldProfile and live.nameplateDebuffPadding == before
        and not DB.GetProfile("RejectedModeTwo"), "new-profile failure lost the live mode-two Blizzard baseline")
    local job = assert(P.BeginImport(Encode(rejected), "RejectedModeTwoStaged"))
    local done, ok
    repeat done, ok = job:Step() until done
    assert(not ok and DB.GetActiveProfileName() == oldProfile and live.nameplateDebuffPadding == before
        and not DB.GetProfile("RejectedModeTwoStaged"), "staged failure lost the live mode-two Blizzard baseline")
    fail = false
    S.Config("nameplates").nativeProfileMode = oldMode
end
do
    local look, global = Suite.DB.suite.moduleLooks.nameplates, Suite.DB.suite.globalLook
    Suite.DB.suite.globalLook, Suite.DB.suite.moduleLooks.nameplates = "midnight", "midnightDark"
    assert(profiles.Apply(assert(profiles.Read("compact"))))
    Suite.DB.suite.moduleLooks.nameplates = "cleanModern"
    local apply, broken = S.Apply, false
    S.Apply = function()
        if Suite.DB.suite.moduleLooks.nameplates == "midnightDark" then broken = true end
        if broken then error("injected repeating nameplate repaint failure") end
        return true
    end
    assert(not profiles.RestorePrevious(), "repeating renderer failure was accepted")
    S.Apply = apply
    assert(broken and Suite.DB.suite.moduleLooks.nameplates == "cleanModern", "failed undo leaked its look record")
    assert(profiles.RestorePrevious())
    Suite.DB.suite.globalLook, Suite.DB.suite.moduleLooks.nameplates = global, look
end
local npcColor = Suite.HostBridge.NPCNameColor
Suite.HostBridge.NPCNameColor = function(kind) assert(kind == "enemy") return .7, .2, .1 end
local red, green, blue = Suite.NameplatePortableText.SampleColor({ sampleNPC = true,
    MSUFSpec = { portable = { npcNameRed = true }, textColor = { r = 1, g = 1, b = 1, a = .8 } } })
assert(red == .7 and green == .2 and blue == .1, "NPC color preview ignored the host reaction palette")
Suite.HostBridge.NPCNameColor = npcColor
local encoder = MSUF_EncodeCompactTable
MSUF_EncodeCompactTable = function() return string.rep("X", IO.maxExportBytes) end
assert(not IO.ExportProfile(), "full Suite export exceeds the actual import text limit")
MSUF_EncodeCompactTable = encoder
combat = true
assert(not profiles.Save("Combat") and not profiles.Apply(original), "template edit bypassed combat refusal")
combat = false
print("Nameplate profiles: scoped round trips, shared rollback, old hosts, UTF-8, native modes and deterministic templates passed")
