"""Update the bundled Wayfarer preset from a local MSUFS3 export and build its media."""
import argparse
import struct
from copy import deepcopy
from pathlib import Path

from build_forever_factory_preview import decode, encode
from build_modern_dark_factory import CORE, assignment, literal, write

FACTORY = CORE / "WayfarerFactory.lua"
BUNDLE_PREFIX = "MSUFS3:"
PARTS = (("Frames", "MSUF3:"), ("Module", "MSUFM1:MSUF3:"), ("Skin", "MSKIN1:"))
AURA_CLIENTS = b"_msufAuraClients"
GROUP_AURA_KEYS = (
    b"auras", b"privateAuras", b"spellIndicators", b"ciCustomTL", b"ciCustomTR", b"ciCustomBL",
    b"ciCustomBR", b"ciCustomC", b"ciSlotTL", b"ciSlotTR", b"ciSlotBL", b"ciSlotBR", b"ciSlotC",
)


def without_ui_scale(frames):
    payloads = [frames[b"payload"]]
    if b"msuf6" in frames:
        payloads.append(frames[b"msuf6"][b"payload"])
    for payload in payloads:
        general = payload[b"general"]
        general[b"UIScale"] = {b"Scale": 1, b"_migratedFromGlobalPreset_v1": True, b"Enabled": False}
        general[b"globalUiScalePreset"] = b"auto"
        general[b"disableScaling"] = False
        general[b"msufUiScale"] = 1
        general.pop(b"uiScale", None)
        general.pop(b"globalUiScaleValue", None)
        # The exporter stamps its scaled UIParent height. Keep factory offsets
        # in UI units so the MSUF frames still line up with the Suite layout.
        for frame in payload.values():
            if isinstance(frame, dict) and frame.get(b"screenPositionMode") == b"relativeHeight":
                frame.pop(b"screenPositionHeight", None)
                frame.pop(b"screenPositionMode")
    return frames


def keep_retail_auras(frames, previous):
    native = frames.get(b"msuf6", frames)
    if native.get(b"auraClient") != b"Forever":
        return
    clients = native[b"payload"].setdefault(AURA_CLIENTS, {b"version": 1, b"clients": {}})[b"clients"]
    if b"Mainline" in clients:
        return
    old_native = previous.get(b"msuf6", previous)
    payload = old_native[b"payload"]
    if old_native.get(b"auraClient") == b"Forever":
        clients[b"Mainline"] = payload[AURA_CLIENTS][b"clients"][b"Mainline"]
        return
    # Early Wayfarer presets shipped a shared snapshot. Preserve the aura
    # settings it installed on Retail in the Core profile's per-client format.
    section = {b"auras3": payload[b"auras3"]}
    for unit in (b"gf_party", b"gf_raid", b"gf_mythicraid", b"gf_priority"):
        group = payload.get(unit, {})
        if entries := {key: group[key] for key in GROUP_AURA_KEYS if key in group}:
            section[unit] = entries
    clients[b"Mainline"] = section


def profile_parts(profile):
    if profile is None:
        return tuple(literal(FACTORY, "Suite.Wayfarer" + name + "Compact") for name, _ in PARTS)
    source = profile.read_text(encoding="utf-8-sig").strip()
    if not source.startswith(BUNDLE_PREFIX):
        raise ValueError("Expected an MSUFS3 profile with Frames, Suite and Skin")
    frames, modules, skin = source.removeprefix(BUNDLE_PREFIX).splitlines()
    return frames, modules, skin


def factory_source(profile):
    frames_text, modules_text, skin_text = profile_parts(profile)
    frames = decode(frames_text, PARTS[0][1])
    modules = decode(modules_text, PARTS[1][1])
    skin = decode(skin_text, PARTS[2][1])
    if (frames.get(b"addon") != b"MSUF" or frames.get(b"kind") != b"all"
            or frames.get(b"profile") != b"Wayfarer" or modules.get(b"addon") != b"MSUF_Suite"
            or modules.get(b"format") != 1 or skin.get(b"addon") not in (b"MapkoSkin", b"MidnightSkin")
            or skin.get(b"format") != 1 or skin.get(b"kind") != b"profile"):
        raise ValueError("Unexpected Wayfarer profile components")
    unscaled = without_ui_scale(deepcopy(frames))
    if profile is not None:
        previous = literal(FACTORY, "Suite.WayfarerFramesCompact")
        keep_retail_auras(unscaled, decode(previous, PARTS[0][1]))
    if frames != unscaled:
        if profile is None:
            raise ValueError("The bundled Wayfarer frames carry UI scaling")
        frames_text = encode(unscaled, PARTS[0][1])
    source = "local _, Suite = ...\n-- Updated by tools/build_wayfarer_factory.py from an MSUFS3 Wayfarer export.\n"
    for (name, _), value in zip(PARTS, (frames_text, modules_text, skin_text)):
        source += assignment("Suite.Wayfarer" + name + "Compact", value)
    return source


def tga_header(width, height):
    return struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)


def plaque():
    """A small beveled plate drawn at 2x for the Core texture layer."""
    width, height = 256, 32
    pixels = bytearray()
    for y in range(height):
        cut = max(0, 8 - min(y, height - 1 - y))
        for x in range(width):
            edge = min(x - cut, width - 1 - cut - x, y, height - 1 - y)
            if edge < 0:
                rgba = (0, 0, 0, 0)
            elif edge < 2:
                rgba = (18, 15, 11, 255)
            elif edge < 4:
                rgba = (119, 99, 64, 255) if y < height / 2 else (61, 48, 32, 255)
            else:
                shade = 34 - y // 3
                rgba = (shade, shade + 1, shade + 3, 250)
                if abs(y - 15) + min(abs(x - 13), abs(x - 242)) <= 3:
                    rgba = (147, 119, 73, 255)
            red, green, blue, alpha = rgba
            pixels.extend((blue, green, red, alpha))
    return tga_header(width, height) + pixels


def endcap():
    """Beveled brass with an inset diamond, mirrored for the right end."""
    size = 64
    pixels = bytearray()
    for y in range(size):
        outer = abs(y - 32)
        for x in range(size):
            left, right = 6 + outer, 61 - outer // 4
            edge = min(x - left, right - x, 25 - outer)
            diamond = abs(x - 36) + outer
            if edge < 0:
                color = (0, 0, 0, 0)
            elif edge <= 2:
                color = (14, 13, 11, 255)
            elif edge <= 5:
                color = (165, 128, 77, 255) if y < 32 else (91, 64, 39, 255)
            elif 10 <= diamond <= 14:
                color = (148, 113, 66, 255)
            else:
                shade = max(22, 48 - y // 2)
                color = (shade + 7, shade + 3, shade, 255)
            red, green, blue, alpha = color
            pixels.extend((blue, green, red, alpha))
    return tga_header(size, size) + pixels


def minimap_frame():
    size = 256
    pixels = bytearray()
    for y in range(size):
        vertical_edge = min(y, size - 1 - y)
        shade = round(max(0, 178 * (1 - y / 65), 158 * (1 - (size - 1 - y) / 39)))
        for x in range(size):
            horizontal_edge = min(x, size - 1 - x)
            edge = min(horizontal_edge, vertical_edge)
            if edge == 0:
                color = (19, 16, 12, 255)
            elif edge == 1:
                color = (124, 100, 64, 255) if x < 2 or y < 2 else (79, 60, 38, 255)
            elif edge == 2:
                corner = max(horizontal_edge, vertical_edge) <= 15
                color = (168, 135, 82, 255) if corner else (54, 43, 30, 255)
            elif edge == 3:
                color = (24, 20, 16, 230)
            else:
                color = (15, 14, 12, shade)
            red, green, blue, alpha = color
            pixels.extend((blue, green, red, alpha))
    return tga_header(size, size) + pixels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, help="new Wayfarer MSUFS3 export")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    write(FACTORY, factory_source(args.profile), args.check)
    for name, art in (("WayfarerPlaque.tga", plaque()), ("WayfarerEndcap.tga", endcap()),
                      ("WayfarerMinimapFrame.tga", minimap_frame())):
        asset = CORE.parent / "Media" / name
        if args.check:
            if not asset.is_file() or asset.read_bytes() != art:
                raise SystemExit(f"{asset} is out of date")
        else:
            asset.write_bytes(art)
    print("Wayfarer profile and media " + ("match" if args.check else "written"))


if __name__ == "__main__":
    main()
