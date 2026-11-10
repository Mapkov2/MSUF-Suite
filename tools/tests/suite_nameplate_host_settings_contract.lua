local root = (arg[1] or "."):gsub("\\", "/"):gsub("/$", "")
local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end
local combat = false
local Suite = { IsSecret = function(value) return type(value) == "table" and value.secret == true end,
    InCombat = function() return combat end, IsCombatLocked = function() return combat end }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", Suite)
assert(loadfile(arg[2] or root .. "/MSUF_Suite/Core/NameplateHostSettings.lua"))("MSUF_Suite", Suite)
local bridge = Suite.HostBridge
Check(not bridge.HasCoreAPI(), "missing Core API can arrive after initial lookup")
Check(bridge.ProfileVariantServices() == nil, "legacy absent namespace has no variant services")
MSUF_HostAPI = { version = 1, ApplyUIScaleProfile = function() end, SetResourceStack = function() end }
Check(bridge.HasCoreAPI(), "late Core API publication is discovered after a miss")
MSUF_HostAPI = nil
Check(not bridge.HasNameplateSettings() and not bridge.HasNameplateFontSettings(), "older hosts expose missing capability")
local payload = { version = 1, general = { kickReadyShowNameplates = true, kickReadyStyle = "fill" },
    nameplates = { fontOverride = true, fontKey = "EXPRESSWAY", fontSize = 16, nameFontSize = 18,
        textBackdrop = true, fontTextAlpha = 0.9 } }
local normalized = bridge.NormalizeNameplateSettings(payload)
Check(normalized and normalized ~= payload and normalized.nameplates ~= payload.nameplates, "portable payload validates without host")
local ok, reason = bridge.ApplyNameplateSettings(payload)
Check(not ok and reason == "unavailable", "older host refuses unsupported writes")
Check(bridge.ApplyNameplateSettings(nil) == true, "legacy absent payload is a no-op")
Check(bridge.CaptureNameplateSettings() == nil, "older host does not fabricate a capture")
local applied, profileName, captured = 0, nil, { version = 1 }
local provider = { version = 1, HasFontScope = function() return true end,
    Capture = function(name) profileName = name return captured, nil, { version = 1, clear = {} } end,
    Apply = function(value) applied = applied + 1 return true, { snapshot = value } end }
MSUF_HostAPI = { GetNameplateSettings = function() return provider end }
Check(bridge.HasNameplateSettings() and bridge.HasNameplateFontSettings(), "late host publication is discovered")
local capture, why, snapshot = bridge.CaptureNameplateSettings("Other")
Check(capture ~= captured and capture.version == captured.version and why == nil and snapshot and profileName == "Other", "named capture and rollback state pass through")
ok, reason = bridge.ApplyNameplateSettings(payload)
Check(ok and reason.snapshot.general.kickReadyStyle == "fill" and applied == 1, "normalized data reaches provider")
combat = true
ok, reason = bridge.ApplyNameplateSettings(payload)
Check(not ok and reason == "combat" and applied == 1, "combat edge refuses before provider writes")
combat = false
ok, reason = bridge.ApplyNameplateSettings({ general = { kickReadyShowTarget = true } })
Check(not ok and reason == "invalid" and applied == 1, "non-nameplate setting rejected before provider writes")
provider = { version = 1, HasFontScope = function() return false end,
    Apply = function() return true, { fontFallback = true } end }
Check(bridge.HasNameplateSettings() and not bridge.HasNameplateFontSettings(), "legacy typography fallback is explicit")
ok, reason = bridge.ApplyNameplateSettings(payload)
Check(ok and reason.fontFallback == true, "legacy fallback report passes through")
local stripped
provider = { version = 1,
    Apply = function(value) stripped = value return true end,
    Capture = function()
        return { version = 1, future = true,
            general = { kickReadyStyle = "fill", kickReadySize = 0, futureField = true,
                kickReadyColor = { r = 0.1, g = 0.2, b = 0.3 } },
            nameplates = { fontSize = 15, fontShadowOpacity = 0 } }, nil,
            { version = 1, general = { kickReadySize = 0, kickReadyStyle = "box" },
                clear = { "general.kickReadyOffsetX", "general.futureField" } }
    end }
Check(not bridge.HasNameplateFontSettings(), "provider without optional font capability is supported")
ok, reason = bridge.ApplyNameplateSettings(payload)
Check(ok and reason.fontFallback and stripped.nameplates == nil and stripped.general.kickReadyStyle == "fill",
    "non-font provider only receives its supported section")
ok, reason = bridge.ApplyNameplateSettings({ version = 1, clear = { "nameplates.fontKey", "general.kickReadySize" } })
Check(ok and reason.fontFallback and #stripped.clear == 1 and stripped.clear[1] == "general.kickReadySize",
    "non-font provider does not receive font clear paths")
capture, why, snapshot = bridge.CaptureNameplateSettings()
Check(capture and why == nil and capture.general.kickReadyStyle == "fill" and capture.nameplates.fontSize == 15,
    "one invalid captured field does not discard the valid capture")
Check(capture.future == nil and capture.general.futureField == nil and capture.general.kickReadySize == nil
    and capture.nameplates.fontShadowOpacity == nil, "captured future or invalid fields are omitted")
Check(capture.general.kickReadyColor[1] == 0.1 and capture.general.kickReadyColor[4] == 1,
    "captured legacy colors canonicalize for editor swatches")
Check(snapshot.general.kickReadyStyle == "box" and snapshot.general.kickReadySize == nil and #snapshot.clear == 1,
    "capture rollback retains valid stored fields and clear paths")
Check(bridge.NormalizeNameplateSettings(provider.Capture()) == nil, "pasted imports remain strict")
Suite.Public = function(value) return not Suite.IsSecret(value) end
Suite.Finite = function(value)
    return Suite.Public(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local keys = Suite.NameplateHostSettings.Keys("nameplates")
Check(#keys > 0 and keys[1] == "boldText", "editor keys are sorted and scoped")
keys[1] = "changed"
Check(Suite.NameplateHostSettings.Keys("nameplates")[1] == "boldText", "editor key lists cannot alter the schema")
Check(bridge.NPCNameColor("enemy") == nil, "missing NPC palette remains unavailable")
local kind, reaction, dead = nil, 4, false
MSUF_NS = { Public = { Colors = { GetNPCColor = function(value) kind = value return 0.1, 0.2, 0.3 end } } }
UnitIsDeadOrGhost = function() return dead end
UnitReaction = function() return reaction end
Check(bridge.NPCNameColor("nameplate1") == 0.1 and kind == "neutral", "NPC name color uses the host reaction palette")
reaction = 5
bridge.NPCNameColor("nameplate1")
Check(kind == "friendly", "friendly NPC reaction")
dead = true
bridge.NPCNameColor("nameplate1")
Check(kind == "dead", "dead NPC palette")
Check(bridge.NPCNameColor("enemy") == 0.1 and kind == "enemy", "preview kind uses no unit lookup")
dead, reaction = false, { secret = true }
Check(bridge.NPCNameColor("nameplate1") == nil, "unknown reaction leaves the inherited text color")
Check(bridge.NPCNameColor({ secret = true }) == nil, "secret unit rejected before lookup")
print("Suite nameplate host settings: " .. checks .. " checks passed")
