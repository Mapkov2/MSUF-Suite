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
    assert found == expected, f"{flavor} factory diverged from supplied Mapko export"


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
        selectionDim = 1, selectionDimPercent = 50, enemyOtherTankEnabled = true, enemyOtherTankColor = "3fc77a" }
    for key, value in pairs(newer) do
        assert(expected[key] == nil, "the export already holds " .. key)
        assert(spec.rules[key] and spec.rules[key].default == value, "newer setting default changed: " .. key)
    end
    newer.targetScaleEnabled, newer.targetScalePercent = false, 120
    for _, side in ipairs({ "enemy", "friendly" }) do
        for key, value in pairs({ BorderStyle = 1, ShadowEnabled = false, GlowMode = 1,
            GlowColor = "ffffff", GlowEnabled = false, TextureEnabled = false, EffectSize = 4, OuterFrame = false, OuterFrameSize = 1,
            OuterFrameColor = "000000", FillTexture = 1 }) do newer[side .. key] = value end
    end
    newer.enemyThresholdEnabled, newer.enemyThresholdPercent, newer.enemyThresholdColor = false, 20, "ffffff"
    newer.enemyFocusMarker, newer.enemyFocusMarkerSize, newer.enemyFocusMarkerColor = false, 12, "ff66ff"
    newer.enemyFocusMarkerX, newer.enemyFocusMarkerY = -56, 0
    for key, rule in pairs(spec.rules) do
        if not key:match("^auraColors") and newer[key] == nil then
            assert(rule.default == expected[key], "Mapko catalog default differs from export: " .. key)
        end
        if key == "auraColorsEnabled" then assert(rule.default == false) end
    end
    assert(spec.rules.look.choices[1] == "Jundies" and spec.rules.look.choices[4] == "Mapko")
    local old = spec.look.presets[1]
    assert(old.barGeometry == 1 and old.enemyCastTextOffsetY == 0 and old.enemyNameFont == "")
    assert(old.enemyLevelEnabled == forever and spec.look.presets[4].enemyLevelEnabled == false)
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
