"""The Forever factory and the three-part preview carry the same compact UI."""

import base64
import os
import re
import sys
import zlib
from pathlib import Path

import cbor2


root = Path(sys.argv[1])


def literal(path, name):
    source = path.read_text(encoding="utf-8")
    return re.search(r"Suite\." + name + r" = \[\[(.*?)\]\]", source, re.S).group(1)


def decode(value, prefix):
    assert value.startswith(prefix)
    return cbor2.loads(zlib.decompress(base64.b64decode(value[len(prefix):]), -15))


factory = root / "MSUF_Suite" / "Core" / "ForeverFactory.lua"
modules_text = literal(factory, "ForeverFactoryModuleCompact")
skin_text = literal(factory, "ForeverFactorySkinCompact")
frames_text = literal(root / "MSUF_Suite" / "Core" / "ForeverFrames.lua",
                      "ForeverFactoryFramesCompact")
reference = os.environ.get("MSUF_CLASSIC_REFERENCE_ROOT")
classic_root = Path(reference) if reference is not None else root.parent / "MidnightSimpleUnitFrames-Classic"
if reference is not None:
    assert reference and classic_root.is_dir(), "MSUF_CLASSIC_REFERENCE_ROOT must name an existing directory"
classic_frames = (classic_root / "MidnightSimpleUnitFrames" / "State" / "Defaults" /
                  "MSUF_Defaults_ForeverFactory.lua")
if reference is not None:
    assert classic_frames.is_file(), "MSUF_CLASSIC_REFERENCE_ROOT is missing the Forever factory profile"
if classic_frames.exists():
    current = re.search(r"MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT = \[\[(.*?)\]\]",
                        classic_frames.read_text(encoding="utf-8"), re.S).group(1)
    assert frames_text == current, "Suite's Forever frame fallback is stale"
export = (root / "exports" / "Forever-Factory-Compact.MSUFS3.txt").read_text().strip()
assert export.split("\n") == ["MSUFS3:" + frames_text, modules_text, skin_text]
assert decode(frames_text, "MSUF3:")[b"addon"] == b"MSUF"

modules = decode(modules_text, "MSUFM1:MSUF3:")[b"profile"][b"suite"][b"modules"]
minimap = modules[b"minimap"]
texts = modules[b"dataTexts"]
tracker = modules[b"objectives"]
skin = decode(skin_text, "MSKIN1:")[b"payload"]
menu = skin[b"icons"][b"microMenu"]

assert (minimap[b"stylePreset"], minimap[b"styleTexture"], minimap[b"styleScale"]) == (10, 7, 130)
assert (minimap[b"shape"], minimap[b"borderSize"], minimap[b"shadowSize"]) == (1, 0, 0)
assert (texts[b"bar1Width"], texts[b"bar1Height"], texts[b"bar1FontSize"],
        texts[b"bar1BagBadgeSize"]) == (340, 36, 11, 38)
assert texts[b"bar1StyleOverride"] and texts[b"bar1BagBadge"]
assert (texts[b"bar1Point"], texts[b"bar1X"], texts[b"bar1Y"]) == (3, -20, -300)
assert tracker[b"y"] <= texts[b"bar1Y"] - texts[b"bar1Height"] - 40
assert (menu[b"layoutPoint"], menu[b"layoutRelativePoint"], menu[b"layoutX"],
        menu[b"layoutY"]) == (b"BOTTOMRIGHT", b"BOTTOMRIGHT", -400, 20)
assert menu[b"preset"] == b"forever" and menu[b"barMaterial"] == b"forever"
print("Forever factory: full export and compact layout match")
