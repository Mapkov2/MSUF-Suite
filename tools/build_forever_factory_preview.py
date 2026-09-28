"""Build the compact Forever factory and a complete, importable Suite preview.

Requires cbor2, as does the existing factory smoke test. The frame profile is
copied byte for byte; only the Forever Suite module and Skin factory change.
"""

import base64
import re
import zlib
from pathlib import Path

import cbor2


ROOT = Path(__file__).resolve().parents[1]
FACTORY = ROOT / "MSUF_Suite" / "Core" / "ForeverFactory.lua"
FRAMES = ROOT / "MSUF_Suite" / "Core" / "ForeverFrames.lua"
EXPORT = ROOT / "exports" / "Forever-Factory-Compact.MSUFS3.txt"


def literal(source, name):
    match = re.search(r"(Suite\." + name + r" = \[\[)(.*?)(\]\])", source, re.S)
    if not match:
        raise ValueError(f"Missing {name} factory literal")
    return match


def decode(value, prefix):
    if not value.startswith(prefix):
        raise ValueError(f"Expected {prefix} payload")
    return cbor2.loads(zlib.decompress(base64.b64decode(value[len(prefix) :]), -15))


def encode(value, prefix):
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    raw = cbor2.dumps(value)
    packed = compressor.compress(raw) + compressor.flush()
    return prefix + base64.b64encode(packed).decode("ascii")


def set_values(target, values):
    for key, value in values.items():
        target[key.encode()] = value.encode() if isinstance(value, str) else value


def main():
    source = FACTORY.read_text(encoding="utf-8")
    module_match = literal(source, "ForeverFactoryModuleCompact")
    skin_match = literal(source, "ForeverFactorySkinCompact")
    modules = decode(module_match.group(2), "MSUFM1:MSUF3:")
    skin = decode(skin_match.group(2), "MSKIN1:")
    if modules[b"addon"] != b"MSUF_Suite" or modules[b"format"] != 1:
        raise ValueError("Unexpected Suite factory envelope")
    if skin[b"addon"] not in (b"MapkoSkin", b"MidnightSkin") or skin[b"format"] != 1:
        raise ValueError("Unexpected Skin factory envelope")

    entries = modules[b"profile"][b"suite"][b"modules"]
    minimap = entries[b"minimap"]
    set_values(minimap, {
        "stylePreset": 10, "shape": 1, "borderSize": 0, "shadowSize": 0,
        "styleTexture": 7, "styleTexturePath": "", "styleColor": "ffffff",
        "styleAlpha": 100, "styleScale": 130, "styleX": 0, "styleY": 0,
        "stylePlacement": 1, "styleBlend": 1, "styleRotation": 0,
        "styleGlow": False, "styleBackdrop": False,
    })

    texts = entries[b"dataTexts"]
    set_values(texts, {
        "bar1Enabled": True, "bar1Width": 380, "bar1Height": 36,
        "bar1Layout": 1, "bar1Point": 3, "bar1X": -20, "bar1Y": -260,
        "bar1Slot1": 3, "bar1Slot2": 4, "bar1Slot3": 5,
        "bar1Slot4": 1, "bar1Slot5": 1, "bar1Slot6": 1,
        "bar1StyleOverride": True, "bar1BackgroundEnabled": True,
        "bar1BackgroundTexture": "", "bar1BackgroundOpacity": 100,
        "bar1BackgroundGradient": True, "bar1BackgroundColor": "06101c",
        "bar1BackgroundFadeColor": "153247", "bar1BorderEnabled": True,
        "bar1BorderSize": 1, "bar1BorderColor": "3c5260",
        "bar1AccentEnabled": True, "bar1AccentPosition": 2,
        "bar1AccentColor": "c49a55", "bar1SeparatorEnabled": True,
        "bar1SeparatorSize": 1, "bar1SeparatorColor": "715a3b",
        "bar1Padding": 5, "bar1Gap": 0, "bar1BagBadge": True,
        "bar1BagBadgeSize": 38, "bar1CustomColors": True,
        "bar1FontSize": 11, "bar1TextAlign": 2, "bar1ShowLabels": True,
        "bar1LabelColon": False, "bar1ClockLabel": False,
        "bar1BagsPercent": True, "bar1LabelColor": "d6aa69",
        "bar1ValueColor": "d6aa69", "bar1WarningColor": "ff8b74",
        "bar1ValueClassColor": False,
    })
    # The tracker starts below the map and compact information strip.
    set_values(entries[b"objectives"], {"y": -340})

    micro = skin[b"payload"][b"icons"][b"microMenu"]
    set_values(micro, {
        "preset": "forever", "barMaterial": "forever", "iconStyle": "bold",
        "layoutMode": "owned", "layoutPoint": "BOTTOMRIGHT",
        "layoutRelativePoint": "BOTTOMRIGHT", "layoutX": -400,
        "layoutY": 20, "positionPreset": "custom",
    })

    new_modules = encode(modules, "MSUFM1:MSUF3:")
    new_skin = encode(skin, "MSKIN1:")
    for name, old, new in (
        ("ForeverFactoryModuleCompact", module_match.group(2), new_modules),
        ("ForeverFactorySkinCompact", skin_match.group(2), new_skin),
    ):
        source = source.replace("Suite." + name + " = [[" + old + "]]",
                                "Suite." + name + " = [[" + new + "]]", 1)
    FACTORY.write_text(source, encoding="utf-8")

    frame_source = FRAMES.read_text(encoding="utf-8")
    frames = literal(frame_source, "ForeverFactoryFramesCompact").group(2)
    if not frames.startswith("MSUF3:"):
        raise ValueError("Unexpected MSUF frame factory")
    full = "MSUFS3:" + frames + "\n" + new_modules + "\n" + new_skin
    EXPORT.parent.mkdir(exist_ok=True)
    EXPORT.write_text(full + "\n", encoding="ascii")

    assert decode(new_modules, "MSUFM1:MSUF3:") == modules
    assert decode(new_skin, "MSKIN1:") == skin
    assert full.count("\n") == 2
    print(f"Wrote {FACTORY} and {EXPORT} ({len(full)} bytes)")


if __name__ == "__main__":
    main()
