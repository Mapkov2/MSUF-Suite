"""Vendor MapkoSkin's skin engine and editor as Suite-owned load-on-demand addons.

Run after reviewing changes in the MapkoSkin source checkout. The former
MapkoSkin_Suite feature modules are intentionally excluded: MSUF Suite owns
those modules already. No external checkout is modified by this script.
"""
from pathlib import Path
import shutil
import sys


ROOT = Path(__file__).resolve().parents[1]
SUITE_VERSION = "1.0-alpha1"
SOURCE = Path(sys.argv[1] if len(sys.argv) > 1 else r"C:\MSUF Beta Branch\MapkoSkin")
CORE_SOURCE = SOURCE / "MapkoSkin"
OPTIONS_SOURCE = SOURCE / "MapkoSkin_Options"
CORE_TARGET = ROOT / "MSUF_Suite_Skin"
OPTIONS_TARGET = ROOT / "MSUF_Suite_Skin_Options"
EXCLUDE_CORE = {
    "Core\\SuiteCatalog.lua", "Core\\Suite.lua", "Core\\SuiteProfiles.lua",
    "Shell\\Commands.lua", "Shell\\AddonCompartment.lua",
}


def entries(toc):
    return [line.strip() for line in toc.read_text(encoding="utf-8-sig").splitlines()
            if line.strip() and not line.startswith("##")]


def copy_entry(source_root, target_root, entry, transforms=None):
    relative = Path(*entry.split("\\"))
    source = source_root / relative
    target = target_root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if transforms and entry in transforms:
        content = source.read_text(encoding="utf-8-sig")
        for before, after in transforms[entry]:
            if before not in content:
                raise ValueError(f"Expected source text missing in {source}: {before}")
            content = content.replace(before, after)
        target.write_text(content, encoding="utf-8")
    else:
        shutil.copy2(source, target)


core_transforms = {
    "Core\\Bootstrap.lua": [
        ('NS.path = "Interface\\\\AddOns\\\\MapkoSkin\\\\"',
         'NS.path = "Interface\\\\AddOns\\\\MSUF_Suite_Skin\\\\"'),
    ],
    "Rendering\\MicroMenuVisual.lua": [
        ('Interface\\\\AddOns\\\\MapkoSkin\\\\Media',
         'Interface\\\\AddOns\\\\MSUF_Suite_Skin\\\\Media'),
    ],
    "Shell\\OptionsLoader.lua": [
        ('"MapkoSkin_Options"', '"MSUF_Suite_Skin_Options"'),
    ],
    "Core\\Database.lua": [
        ('local stored = _G.MapkoSkinDB',
         'local stored = _G.MSUFSuiteSkinDB\n    if type(stored) ~= "table" then stored = _G.MapkoSkinDB end'),
        ('_G.MapkoSkinDB = root', '_G.MSUFSuiteSkinDB = root'),
        ('_G.MapkoSkinDB = NS.RootDB', '_G.MSUFSuiteSkinDB = NS.RootDB'),
    ],
}

options_transforms = {
    "MSKIN_OptionsBootstrap.lua": [
        ('assert(_G.MapkoSkin, "MapkoSkin core is required")',
         'assert(_G.MapkoSkin, "Suite skin engine is required")'),
    ],
}

for flavor in ("Mainline", "Mists", "TBC", "Vanilla"):
    source_toc = CORE_SOURCE / f"MapkoSkin_{flavor}.toc"
    source_lines = source_toc.read_text(encoding="utf-8-sig").splitlines()
    interface = next(line for line in source_lines if line.startswith("## Interface:"))
    source_entries = entries(source_toc)
    copied = [entry for entry in source_entries if entry not in EXCLUDE_CORE]
    for entry in copied:
        if entry != "Core\\Lifecycle.lua":
            copy_entry(CORE_SOURCE, CORE_TARGET, entry, core_transforms)
    toc = [interface, "## Title: MSUF Suite - Skinning",
           "## Notes: Suite-owned MapkoSkin skin engine.", "## Author: Mapko",
           f"## Version: {SUITE_VERSION}", "## Dependencies: MSUF_Suite", "## Group: MSUF_Suite",
           "## LoadOnDemand: 1", "## SavedVariables: MSUFSuiteSkinDB",
           "## IconTexture: Interface\\AddOns\\MSUF_Suite\\Media\\SuiteIcon.tga", ""]
    (CORE_TARGET / f"MSUF_Suite_Skin_{flavor}.toc").write_text(
        "\n".join(toc + copied) + "\n", encoding="utf-8")

for path in (CORE_SOURCE / "Media").rglob("*"):
    if path.is_file():
        target = CORE_TARGET / path.relative_to(CORE_SOURCE)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
shutil.copy2(CORE_SOURCE / "THIRD_PARTY_NOTICES.txt", CORE_TARGET / "THIRD_PARTY_NOTICES.txt")
shutil.copy2(SOURCE / "LICENSE.txt", CORE_TARGET / "LICENSE.txt")

for flavor in ("Mainline", "Mists", "TBC", "Vanilla"):
    source_toc = OPTIONS_SOURCE / f"MapkoSkin_Options_{flavor}.toc"
    source_lines = source_toc.read_text(encoding="utf-8-sig").splitlines()
    interface = next(line for line in source_lines if line.startswith("## Interface:"))
    source_entries = entries(source_toc)
    for entry in source_entries:
        if entry != "Shell\\Embedded.lua":
            copy_entry(OPTIONS_SOURCE, OPTIONS_TARGET, entry, options_transforms)
    toc = [interface, "## Title: MSUF Suite - Skinning Options",
           "## Notes: Suite skinning pages inside MSUF.", "## Author: Mapko",
           f"## Version: {SUITE_VERSION}", "## Dependencies: MSUF_Suite_Skin, MSUF_Suite_Options",
           "## Group: MSUF_Suite", "## LoadOnDemand: 1",
           "## IconTexture: Interface\\AddOns\\MSUF_Suite\\Media\\SuiteIcon.tga", ""]
    (OPTIONS_TARGET / f"MSUF_Suite_Skin_Options_{flavor}.toc").write_text(
        "\n".join(toc + source_entries) + "\n", encoding="utf-8")

print("Vendored MapkoSkin engine and all editor pages into Suite-owned addons")
