local root = assert(arg[1])
local NS = {}
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Nameplates.lua"))("MSUF_Suite", NS)
local spec = assert(NS.SuiteCatalog.nameplates)
NS.Public = function(value) return value ~= "secret" end
local nativeValue = "0.00"
C_CVar = { GetCVar = function() return nativeValue end }
assert(NS.NameplateStyle.NativeToggle("SoftTargetNameplateSize", false) == false)
nativeValue = "1.25"
assert(NS.NameplateStyle.NativeToggle("SoftTargetNameplateSize", false) == true)
nativeValue = "secret"
assert(NS.NameplateStyle.NativeToggle("SoftTargetNameplateSize", false) == false)
-- Removed on request: native cast appearance cannot be reenabled by a preset
-- or offered through the menu/import schema. Cast text and dragging remain.
for _, key in ipairs({ "enemyCastSkin", "enemyCastFollowMSUF", "enemyCastTexture", "enemyCastBorderSize",
    "enemyCastBackdropAlpha", "enemyCastFillAlpha", "enemyCastBorderColor", "enemyCastBackdropColor", "enemyCastFillColor",
    "enemyHealthTexture", "enemyFocusHealthTexture", "friendlyHealthTexture", "friendlyFocusHealthTexture" }) do
    assert(not spec.rules[key], "retired cast appearance control remains: " .. key)
    for _, preset in pairs(spec.look.presets) do assert(preset[key] == nil, "preset restores retired cast appearance: " .. key) end
end
local fixture = dofile(root .. "/tools/fixtures/nameplates_eqol_features.lua")
local count = 0
for feature, keys in pairs(fixture) do
    count = count + 1
    for _, key in ipairs(keys) do
        assert(spec.rules[key], feature .. " has no Suite setting: " .. key)
        assert(spec.rules[key].section, key .. " has no options section")
    end
end
assert(count == 49, "EQoL coverage must retain the requested controls except retired health textures")

local function Default(key, expected)
    assert(spec.rules[key].default == expected, key .. " diverged from the confirmed Platynator DEFAULT")
    assert(spec.look.presets[1][key] == expected, key .. " Jundies reset diverged from fresh defaults")
end
for key, value in pairs({
    enemyMeleeColor = "be301d", enemyCasterColor = "00bfff", enemyMinibossColor = "9370db",
    enemyBossColor = "ff00ff", enemyTappedColor = "6e6e6e", enemyQuestColor = "ff7e00",
    enemyNeutralColor = "e5db00", enemyTrivialColor = "be301d",
    enemyThreatLostColor = "dd6f00", enemyThreatWarningColor = "ffe93a",
    enemyNeutralEnabled = true, enemyTrivialEnabled = true, enemyBorderSize = 1,
    enemyBorderEnabled = true, enemyBackdropEnabled = true,
    friendlyBorderEnabled = true, friendlyBackdropEnabled = true,
    enemyBackdropAlpha = 50, enemyCastEnabled = 2, enemyTextMode = 4,
    enemyTextOutline = 4, enemyCastOutline = 4, enemyTextShadow = false, friendlyTextShadow = true,
    enemyQuestMarker = true, enemyQuestMarkerAnchor = 5, enemyQuestOffsetX = -14, enemyQuestOffsetY = 0,
    enemyNpcAuraMode = 1, enemyPlayerAuraMode = 1, friendlyPlayerAuraMode = 1,
    threatSignalMode = 1, softTargetIconGate = 1, personalPowerSkin = false,
    threatFlashColorEnabled = false, threatFlashColor = "ffff00",
    threatHighlightColorEnabled = false, threatHighlightColor = "ffe93a",
}) do Default(key, value) end
assert(NS.NameplateStyle.FontFlags(4) == "OUTLINE,SLUG")
assert(#spec.rules.enemyTargetStyle.choices == 15 and #spec.rules.enemyEliteMarkerAnchor.choices == 10)
assert(#NS.NameplateStyle.TargetAtlases == 8)
assert(NS.NameplateStyle.TargetAtlases[8][1] == "pvptalents-selectedarrow")
assert(spec.rules.enemyEliteMarkerSize.max == 48 and spec.rules.enemyCastSize.max == 32)
for _, key in ipairs({ "enemyBorderEnabled", "enemyBackdropEnabled",
    "friendlyBorderEnabled", "friendlyBackdropEnabled" }) do
    assert(spec.look.presets[2][key] == false,
        key .. " leaves an MSUF skin layer active in Blizzard look")
end
for key, rule in pairs(spec.rules) do
    if key:match("Offset[XY]$") then
        assert(rule.min == -2048 and rule.max == 2048,
            key .. " constrains preview drag before the element leaves the screen")
    end
end

-- The concrete runtime test covers behavior. Keep engine ownership and the
-- no-polling constraint visible here when adding new files to the addon.
for _, name in ipairs({ "Skin", "Layout", "Roles", "Text", "Power", "Threat" }) do
    local file = assert(io.open(root .. "/MSUF_Suite_Nameplates/" .. name .. ".lua", "rb"))
    local source = file:read("*a"); file:close()
    for _, forbidden in ipairs({ '"OnUpdate"', "NewTicker", '"UNIT_HEALTH"', '"COMBAT_LOG_EVENT_UNFILTERED"',
        "CompactUnitFrame_SetUpFrame(", "CompactUnitFrame_UpdateAll(", "CompactUnitFrame_SetUnit(",
        "UnitHealth(", "UnitHealthMax(", "UnitCastingInfo(" }) do
        assert(not source:find(forbidden, 1, true), name .. " bypasses Blizzard ownership: " .. forbidden)
    end
end
print("Suite nameplate coverage: 45 EQoL setting groups + 4 other controls, Jundies defaults and ownership passed")
