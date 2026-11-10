local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local locked, fighting, writes, hostWrites, fonts, fail = false, true, 0, 0, false, false
InCombatLockdown = function() return locked end
UnitAffectingCombat = function() return fighting end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
securecallfunction = function(callback, ...) return callback(...) end
MSUF_NS = {}
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
SlashCmdList = {}
Minimap = { SetMaskTexture = function() end }
C_AddOns = { DoesAddOnExist = function() return false end, IsAddOnLoaded = function() return false end }
local live = { nameplateDebuffPadding = "4" }
C_CVar = {
    GetCVar = function(key) return live[key] end,
    SetCVar = function(key, value) writes = writes + 1 live[key] = value end,
}
MSUF_GlobalDB, MSUF_ActiveProfile = { profiles = { Default = {} } }, "Default"
local Suite = {}
Support.Load(root, "MSUF_Suite", Suite, "Core/ProfileVariants.lua")
if arg[2] then assert(loadfile(arg[2]))("MSUF_Suite", Suite) end
assert(Suite.Database.Initialize(nil))
Suite.Suite.Normalize(Suite.DB)
Suite.Suite.Apply = function() return true end
local frames = Support.EventFrames()
CreateFrame = frames.Create
local available = true
local host = { general = {} }
local provider = { version = 1,
    HasFontScope = function() return fonts end,
    Capture = function() return Suite.CopyValue(host), nil, Suite.CopyValue(host) end,
    Apply = function(payload)
        assert(not locked, "host writes while locked")
        assert(fonts or payload.nameplates == nil, "non-font host received typography")
        if fail and payload.nameplates and payload.nameplates.fontSize == 39 then return false, "injected" end
        hostWrites = hostWrites + 1
        for section, values in pairs(payload) do
            if section ~= "version" and section ~= "clear" then host[section] = Suite.CopyValue(values) end
        end
        for _, path in ipairs(payload.clear or {}) do
            local section, key = path:match("^(%a+)%.(%w+)$")
            if host[section] then host[section][key] = nil end
        end
        return true
    end,
}
MSUF_HostAPI = { GetNameplateSettings = function() return available and provider or nil end }
local IO, profile, checks = Suite.ProfileIO, Suite.DB, 0
local function Check(value, reason) checks = checks + 1 assert(value, reason) end
profile.nameplateCVars = { nameplateDebuffPadding = "22" }
profile.nameplateShared = { version = 1, general = { kickReadyStyle = "fill" }, nameplates = { fontSize = 18 } }
profile.nameplateSharedPending = true
Check(IO.StartNameplateProfile(), "combat reload should defer successfully")
Check(writes == 0 and hostWrites == 0, "pre-lock combat startup wrote settings")
Check(#frames.list == 1 and frames.list[1].events.PLAYER_REGEN_ENABLED, "startup retry was not registered")
frames.Fire("PLAYER_LOGOUT")
Check(profile.nameplateCVars.nameplateDebuffPadding == "22", "logout replaced unapplied startup baseline")
locked = true
frames.Fire("PLAYER_REGEN_ENABLED")
Check(writes == 0 and hostWrites == 0, "regen transition bypassed actual lockdown")
locked = false
frames.Fire("PLAYER_REGEN_ENABLED")
Check(writes == 1 and hostWrites == 1 and live.nameplateDebuffPadding == "22", "regen did not apply exactly once")
Check(host.general.kickReadyStyle == "fill", "startup did not restore shared interrupts")
Check(profile.nameplateSharedPending.nameplates and not profile.nameplateSharedPending.general,
    "non-font host lost pending typography or retained applied interrupts")
Check(not frames.list[1].events.PLAYER_REGEN_ENABLED, "successful startup left a retry event")
frames.Fire("PLAYER_REGEN_ENABLED")
Check(writes == 1 and hostWrites == 1, "completed startup replayed on later regen")
Check(not IO.ApplyNameplateCVars({ nameplateDebuffPadding = "8" }), "normal import bypassed player combat flag")
Check(not Suite.HostBridge.ApplyNameplateSettings({ version = 1, general = { kickReadySize = 18 } }),
    "normal host edit bypassed player combat flag")
live.nameplateDebuffPadding = "37"
frames.Fire("PLAYER_LOGOUT")
Check(profile.nameplateCVars.nameplateDebuffPadding == "37", "logout did not capture applied profile baseline")
fighting = false
fonts = true
Check(IO.StartNameplateProfile(), "font-capable host upgrade failed")
Check(hostWrites == 2 and host.nameplates.fontSize == 18 and profile.nameplateSharedPending == nil,
    "font-capable upgrade did not consume pending typography")
host.general.kickReadyStyle = "border"
Check(IO.StartNameplateProfile(), "later startup failed")
Check(hostWrites == 2 and host.general.kickReadyStyle == "border", "ordinary startup replayed stale shared values")
local DB = Suite.Database
Check(DB.Create("Upgrade", true), "inactive upgrade profile could not be created")
local upgrade = DB.GetProfile("Upgrade")
upgrade.nameplateCVars = { nameplateDebuffPadding = "11" }
upgrade.nameplateShared = { version = 1, nameplates = { fontSize = 39 } }
upgrade.nameplateSharedPending = { nameplates = true }
fail = true
Check(not DB.Activate("Upgrade"), "inactive pending failure was accepted")
Check(DB.GetActiveProfileName() == "Default" and Suite.DB == profile and live.nameplateDebuffPadding == "37",
    "failed activation did not restore the active profile and native values")
Check(upgrade.nameplateSharedPending.nameplates and host.nameplates.fontSize == 18,
    "failed activation lost pending typography or host settings")
fail = false
Check(DB.Activate("Upgrade"), "inactive pending profile did not activate after upgrade")
Check(host.nameplates.fontSize == 39 and upgrade.nameplateSharedPending == nil and live.nameplateDebuffPadding == "11",
    "activation did not apply and consume pending typography")
local activatedWrites = hostWrites
host.nameplates.fontSize = 25
Check(DB.Activate("Default") and DB.Activate("Upgrade"), "normal profile switch failed")
Check(hostWrites == activatedWrites and host.nameplates.fontSize == 25, "normal switching replayed stale stored typography")
host.general.kickReadyOffsetX = 19
available = false
Check(IO.ApplyNameplateShared({ version = 1, clear = { "general.kickReadyOffsetX" } }), "old host rejected clear intent")
Check(upgrade.nameplateSharedPending.general and upgrade.nameplateShared.clear[1] == "general.kickReadyOffsetX",
    "old host lost pending clear intent")
available = true
Check(IO.StartNameplateProfile() and host.general.kickReadyOffsetX == nil and upgrade.nameplateSharedPending == nil,
    "upgraded host did not apply a clear-only reset")
local merged = IO.MergeNameplateShared(upgrade.nameplateShared, { version = 1, general = { kickReadyOffsetX = 7 } })
Check(merged.general.kickReadyOffsetX == 7 and merged.clear == nil, "explicit value did not replace an older clear intent")
provider.HasFontScope = nil
provider.Capture = function()
    return { version = 1 }, nil, { version = 1, nameplates = { fontKey = "EXPRESSWAY" },
        clear = { "general.kickReadySize", "nameplates.fontOverride", "nameplates.fontSize" } }
end
upgrade.nameplateShared = { version = 1, nameplates = { fontOverride = false, fontSize = 23 } }
local undo = IO.CaptureNameplateUndo()
Check(Suite.NameplateHostSettings.Normalize(undo) ~= nil, "legacy provider font clears conflict with portable undo values")
local clears = {}
for _, path in ipairs(undo.clear) do clears[path] = (clears[path] or 0) + 1 end
Check(undo.nameplates.fontSize == 23 and undo.nameplates.fontOverride == false and clears["nameplates.fontKey"] == 1
    and not clears["nameplates.fontOverride"] and not clears["nameplates.fontSize"] and clears["general.kickReadySize"] == 1,
    "portable undo did not replace the complete unsupported font snapshot")
provider.Capture = function()
    return { version = 1, nameplates = { fontOverride = true, fontKey = "EXPRESSWAY", fontSize = 21 } }, nil,
        { version = 1, general = {} }
end
local exported = IO.CaptureNameplateShared()
Check(exported.nameplates.fontSize == 21 and exported.nameplates.fontOverride == true,
    "disabled portable typography replaced the host's effective inherited font in exports")
upgrade.nameplateShared.nameplates = {}
exported = IO.CaptureNameplateShared()
Check(exported.nameplates.fontSize == 21, "empty portable typography replaced the host's inherited font")
upgrade.nameplateShared.nameplates = { fontOverride = true, fontSize = 26 }
exported = IO.CaptureNameplateShared()
Check(exported.nameplates.fontSize == 26, "active portable typography did not override the host capture")
local inheritedSize, typographyReads = 17, 0
provider.ResolveTypography = function(overrides)
    typographyReads = typographyReads + 1
    return { fontOverride = true, fontSize = overrides.fontSize, nameFontSize = inheritedSize,
        boldText = true, textBackdrop = true, fontShadowOpacity = 0.55, fontShadowDistance = 2,
        fontColorR = 0.2, fontColorG = 0.4, fontColorB = 0.6 }
end
local first = Suite.NameplatePortableText.Resolve()
inheritedSize = 19
local second = Suite.NameplatePortableText.Resolve()
Check(first.nameFontSize == 17 and second.nameFontSize == 19 and typographyReads == 2,
    "cold typography compilation cached stale host settings behind an unchanged stored profile")
Check(second.fontSize == 26 and second.fontFlags == "THICKOUTLINE" and second.fontShadow
    and second.fontShadowAlpha == 0.55 and second.textColor.g == 0.4, "portable text ignored effective host style")
exported = IO.CaptureNameplateShared()
Check(exported.nameplates.fontSize == 26 and exported.nameplates.nameFontSize == 19,
    "partial portable export lost the host's inherited settings")
print("Suite nameplate startup: " .. checks .. " checks passed")
