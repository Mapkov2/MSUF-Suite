"""The supplied module export is the factory on both clients, including codec fallback."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zlib

import cbor2

root = Path(sys.argv[1])


def text(value):
    if isinstance(value, bytes):
        return value.decode("utf-8")
    if isinstance(value, dict):
        return {text(k): text(v) for k, v in value.items()}
    return value


def decode(value):
    return text(cbor2.loads(zlib.decompress(base64.b64decode(value.rsplit(":", 1)[1]), -15)))


export = decode((root / "tools/fixtures/nameplates_mapko_export.txt").read_text())
assert export["module"] == "nameplates" and export["revision"] == 17
expected = dict(export["settings"], look=4, barGeometry=2, levelAppearance=1)
for flavor in ("Retail", "Forever"):
    source = (root / f"MSUF_Suite/Core/{flavor}Factory.lua").read_text(encoding="utf-8")
    compact = re.search(flavor + r"FactoryModuleCompact = \[\[(.*?)\]\]", source, re.S)[1]
    found = decode(compact)["profile"]["suite"]["modules"]["nameplates"]
    # The factory contains the export after the visibility migration. The
    # choice for world names (4) is kept, the legacy automatic choice is gone.
    migrated = expected.copy()
    if migrated.get("friendlyNPCs") != 4:
        migrated.pop("friendlyNPCs", None)
    assert found == migrated, f"{flavor} factory diverged from supplied Mapko export"


def lua(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, dict):
        return "{" + ",".join(f"[{lua(k)}]={lua(v)}" for k, v in value.items()) + "}"
    return json.dumps(value)


script = """
local root, expected = %s, %s
for _, forever in ipairs({ false, true }) do
    local ns = { Client = { isMainline = true, isForever = forever }, Text = function(v) return v end }
    for _, file in ipairs({ "SuiteCatalog", "NameplateStyle", "Catalog/Nameplates" }) do
        assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", ns)
    end
    local spec = ns.SuiteCatalog.nameplates
    -- Settings added after export revision 17 keep Blizzard's behaviour by
    -- default (the other-tank color follows tank mode, which stays off).
    local newer = { enemyCastHeight = 0, enemyCastIconSize = 0, enemyCastTimeFormat = 1,
        enemyMirrorHeader = false, plateShowAll = 1, plateStackEnemy = 1, plateStackFriendly = 1, plateEnemyMinions = 1,
        plateEnemyMinus = 1, plateFriendlyMinions = 1, plateOffscreen = 1, plateSimpleMinion = 1,
        plateSimpleMinus = 1, plateSimpleFriendlyPlayer = 1, plateSimpleFriendlyNpc = 1,
        selectionBorder = 1, selectionTargetColor = "ffffff", selectionFocusColor = "ff66ff",
        selectionDim = 1, selectionDimPercent = 50, enemyOtherTankEnabled = true, enemyOtherTankColor = "3fc77a",
        plateEnemies = 1, plateFriendlyPlayers = 1, plateEnemyPets = 1, plateEnemyGuardians = 1,
        plateEnemyTotems = 1, plateFriendlyPets = 1, plateFriendlyGuardians = 1, plateFriendlyTotems = 1,
        plateMaxDistanceMode = 1, plateMaxDistance = 60, plateOccludedMode = 1, plateOccludedPercent = 40,
        plateFadeDistance = 1, plateShrinkDistance = 1, plateSpacingMode = 1, plateOverlapV = 110, plateOverlapH = 80,
        plateMotionSpeed = 1, plateInsetMode = 1, plateTopInset = 8, plateBottomInset = 10, plateClampTarget = 1 }
    for key, default in pairs({ enemyPowerEnabled = false, enemyPowerSmooth = true, enemyPowerWidth = 0,
        enemyPowerHeight = 4, enemyPowerOffsetX = 0, enemyPowerOffsetY = 0, enemyPowerColor = "337be6",
        enemyPowerByType = true, enemyPowerBackgroundColor = "10151d", enemyPowerBackgroundAlpha = 80 }) do
        newer[key] = default
        for _, preset in pairs(spec.look.presets) do
            assert(preset[key] == nil, "a look overrides saved enemy power: " .. key)
        end
    end
    for _, text in ipairs({ "enemyName", "enemyHealthText", "friendlyName", "friendlyHealthText", "enemyPowerText" }) do
        newer[text .. "Visible"] = text ~= "enemyPowerText"
        newer[text .. "Mouseover"] = false
        newer[text .. "FadeIn"], newer[text .. "FadeOut"] = 0.35, 0.35
    end
    newer.enemyNameRelativeAnchor, newer.friendlyNameRelativeAnchor = 1, 1
    newer.friendlyHealthTextSize, newer.enemyPowerTextSize, newer.enemyPowerTextMode = 0, 10, 1
    newer.enemyPowerTextAnchor, newer.enemyPowerTextColor = 5, "ffffff"
    newer.enemyPowerTextOffsetX, newer.enemyPowerTextOffsetY = 0, 0
    newer.auraDebuffPadding = -1 -- Leave the imported game spacing intact.
    for _, key in ipairs({ "enemySkinEnabled", "neutralSkinEnabled", "friendlySkinEnabled", "friendlyNpcSkinEnabled" }) do
        newer[key] = true
        for _, preset in pairs(spec.look.presets) do
            assert(preset[key] == nil, "a look overrides the per-type skin switch: " .. key)
        end
    end
    newer.enemyPowerChunked, newer.enemyPowerEmbed, newer.enemyPowerDetached, newer.enemyPowerBorder = false, false, false, false
    newer.enemyPowerSource, newer.enemyPowerDetachedWidth, newer.enemyPowerDetachedHeight, newer.enemyPowerDetachedLayer = 1, 0, 6, 6
    newer.enemyPowerBorderSize, newer.enemyPowerBorderColor, newer.enemyPowerLossColor = 1, "000000", "ffffff"
    newer.targetScaleEnabled, newer.targetScalePercent = false, 120
    newer.enemyTargetPrimaryOffsetX, newer.enemyTargetPrimaryOffsetY = 0, 0
    newer.enemyTargetMirrorOffsetX, newer.enemyTargetMirrorOffsetY = 0, 0
    newer.hideHealthBarBorders = false
    newer.nameplateAbsorbMode, newer.nameplateHealAbsorbMode = 1, 1
    newer.nameFormattingEnabled, newer.nameTextUseCustomSettings = false, false
    newer.enemyHealthTextSizeOverride = 0
    for _, side in ipairs({ "enemy", "friendly" }) do
        newer[side .. "RaidIconSize"], newer[side .. "LevelAnchor"] = 22, 1
        if side == "friendly" then newer.friendlyRaidIcon = true end
        for _, item in ipairs(ns.NameplateStyle.Status) do
            if ns.NameplateStyle.StatusSupported(item, side) then
                local key = side .. item.key
                newer[key], newer[key .. "Size"], newer[key .. "Layer"] = false, item.sample and 11 or 16, 5
                newer[key .. "Anchor"], newer[key .. "OffsetX"], newer[key .. "OffsetY"] = item.anchor or 2, item.x or 0, item.y or 9
                if item.sample then newer[key .. "Color"] = "ffffff" end
            end
        end
        newer[side .. "CastWidthDelta"] = 0
        newer[side .. "CastWidthMode"], newer[side .. "CastManualWidth"], newer[side .. "CastTimeSize"] = 1, 160, 0
        newer[side .. "CastIconZoom"], newer[side .. "CastIconBorderSize"] = 100, 1
        newer[side .. "CastIconBorder"], newer[side .. "CastIconBorderColor"] = false, "000000"
        newer[side .. "NameSizeOverride"], newer[side .. "CastSizeOverride"] = 0, 0
        if forever then newer[side .. "NativeBorderEnabled"] = true end
        for suffix, default in pairs({ NameFormat = 2, NameMaxChars = 12, NameClipSide = 1,
            NameNoEllipsis = false, NameColorEnabled = false, NameColor = "ffffff" }) do
            newer[side .. suffix] = default
        end
    end
    for key, value in pairs(newer) do
        assert(expected[key] == nil, "the export already holds " .. key)
        assert(spec.rules[key] and spec.rules[key].default == value, "newer setting default changed: " .. key)
    end
    for _, side in ipairs({ "enemy", "friendly" }) do
        for key, value in pairs({ BorderStyle = 1, ShadowEnabled = false, GlowMode = 1,
            GlowColor = "ffffff", GlowEnabled = false, TextureEnabled = false, EffectSize = 4, OuterFrame = false, OuterFrameSize = 1,
            OuterFrameColor = "000000", FillTexture = 1 }) do newer[side .. key] = value end
    end
    newer.enemyThresholdEnabled, newer.enemyThresholdPercent, newer.enemyThresholdColor = false, 20, "ffffff"
    newer.enemyFocusMarker, newer.enemyFocusMarkerSize, newer.enemyFocusMarkerColor = false, 12, "ff66ff"
    newer.enemyFocusMarkerX, newer.enemyFocusMarkerY = -56, 0
    -- Nameplate looks: the mouseover highlight, the level color, the threshold
    -- line width and the friendly cast sizes start on today's look.
    local looks = { friendlyCastHeight = 0, friendlyCastIconSize = 0, friendlyCastTimeFormat = 1,
        mouseoverHighlight = false, mouseoverHighlightColor = "ffffff", enemyLevelColor = false, enemyThresholdWidth = 1,
        enemyOutlineMode = 1, friendlyOutlineMode = 1, highlightTarget = false, highlightFocus = false,
        highlightAggro = false, highlightAggroOverride = false, highlightMouseover = false, highlightBorderSize = 2,
        highlightPriority = false, highlightOrder = "1234", castTargetHighlightStyle = 1,
        highlightAggroColor = "ff5252", highlightMouseoverColor = "ffffff" }
    for key, value in pairs(looks) do
        assert(expected[key] == nil and spec.rules[key] and spec.rules[key].default == value, "look setting default changed: " .. key)
        newer[key] = value
    end
    for key, rule in pairs(spec.rules) do
        if rule.section == "nativeTextures" then
            assert(rule.default == "", "a native texture override must be opt-in")
        elseif not key:match("^auraColors") and newer[key] == nil then
            assert(rule.default == expected[key], "Mapko catalog default differs from export: " .. key)
        end
        if key == "auraColorsEnabled" then assert(rule.default == false) end
    end
    assert(spec.rules.look.choices[1] == "Jundies" and spec.rules.look.choices[4] == "Mapko")
    local old = spec.look.presets[1]
    assert(old.barGeometry == 2 and old.enemyHealthWidthDelta == -18 and old.enemyHealthHeightDelta == 3)
    assert(old.enemyNameFont:find("Expressway ExtraBold.ttf", 1, true)
        and old.friendlyNameFont:find("Expressway Regular.ttf", 1, true))
    assert(old.enemyLevelEnabled == forever and spec.look.presets[4].enemyLevelEnabled == false)
    assert(old.enemyNameVisible and old.enemyHealthTextVisible and not old.enemyHealthTextMouseover,
        "Jundies leaves the previous name and HP text visibility in place")
    assert(old.enemyCastWidthMode == 2 and old.enemyCastTimeSize == 0 and old.enemyCastHeight == 12 and not old.enemyCastIconBorder,
        "Jundies leaves the previous castbar presentation in place")
    assert(old.nativeHealthFillTexture == "Solid" and old.nativeFocusHealthFillTexture == ""
        and old.nativeCastBackgroundTexture == "Solid" and old.enemyOutlineMode == 3 and not old.hideHealthBarBorders,
        "Jundies leaves the previous textures and outline in place")
    assert(old.highlightTarget and old.highlightFocus and old.selectionTargetColor == "ffffff"
        and old.selectionFocusColor == "00fff5" and old.enemyBorderSize == 1 and old.enemyBackdropAlpha == 50)
    local incoming = {}
    for key, value in pairs(expected) do incoming[key] = value end
    incoming.look, incoming.barGeometry, incoming.levelAppearance = 3, nil, nil
    ns.NameplateStyle.RepairGeometry({ nameplates = incoming })
    assert(incoming.barGeometry == 2, "original Mapko string lost its portable dimensions")
    incoming.barGeometry, incoming.enemyCastTimeOffsetX = nil, 52
    ns.NameplateStyle.RepairGeometry({ nameplates = incoming })
    assert(incoming.barGeometry == 1, "unrelated old custom profile changed its base")
    for _, choice in ipairs({ 1, 2, 3, 4 }) do
        local modules = { nameplates = { look = choice, enemyHealthWidthDelta = 51 } }
        ns.NameplateStyle.RepairGeometry(modules)
        assert(modules.nameplates.barGeometry == (choice == 4 and 2 or 1))
        assert(modules.nameplates.enemyHealthWidthDelta == 51)
        modules.nameplates.barGeometry = 2
        ns.NameplateStyle.RepairGeometry(modules)
        assert(modules.nameplates.barGeometry == 2, "saved portable basis lost on next normalization")
    end
    local fresh = { nameplates = {} }
    ns.NameplateStyle.RepairGeometry(fresh)
    assert(not fresh.nameplates.barGeometry, "repair replaced new factory default")
end
""" % (lua(str(root)), lua(expected))
runtime = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
with tempfile.TemporaryDirectory(prefix="suite-mapko-") as directory:
    path = Path(directory) / "test.lua"
    path.write_text(script, encoding="utf-8")
    subprocess.run([runtime, str(path)], check=True)
print("Mapko: supplied export, both bundled factories, catalog defaults and legacy sizing passed")
