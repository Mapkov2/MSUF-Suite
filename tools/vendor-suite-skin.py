"""Vendor MapkoSkin's skin engine and editor as Suite-owned load-on-demand addons.

The Suite copy (MSUF_Suite_Skin, MSUF_Suite_Skin_Options) is canonical now and
carries fixes the MapkoSkin checkout does not have. Running this overwrites it
with the upstream files and reverts those fixes, so the script refuses unless
it is started with --force-overwrite-suite. The former MapkoSkin_Suite feature
modules are intentionally excluded: MSUF Suite owns those modules already. No
external checkout is modified by this script.

Usage: python tools/vendor-suite-skin.py [MapkoSkin checkout] --force-overwrite-suite
"""
from pathlib import Path
import shutil
import sys


ROOT = Path(__file__).resolve().parents[1]
FORCE_FLAG = "--force-overwrite-suite"
REFUSAL = ("Refusing to vendor: the Suite copy is canonical; running this reverts the Suite skin. "
           "Pass " + FORCE_FLAG + " only to overwrite it on purpose.")
SUITE_VERSION = "1.0-alpha1"
# The Suite supports Retail and WoW Forever, which both load the Mainline TOC.
# Only that TOC is written, so a rerun cannot bring back Classic TOCs.
FLAVORS = ("Mainline",)
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


def vendor_core(source):
    core_source = source / "MapkoSkin"
    for flavor in FLAVORS:
        source_toc = core_source / f"MapkoSkin_{flavor}.toc"
        source_lines = source_toc.read_text(encoding="utf-8-sig").splitlines()
        interface = next(line for line in source_lines if line.startswith("## Interface:"))
        source_entries = entries(source_toc)
        copied = [entry for entry in source_entries if entry not in EXCLUDE_CORE]
        for entry in copied:
            if entry != "Core\\Lifecycle.lua":
                copy_entry(core_source, CORE_TARGET, entry, core_transforms)
        toc = [interface, "## Title: MSUF Suite - Skinning",
               "## Notes: Suite-owned MapkoSkin skin engine.", "## Author: Mapko",
               f"## Version: {SUITE_VERSION}", "## Dependencies: MSUF_Suite", "## Group: MSUF_Suite",
               "## LoadOnDemand: 1", "## SavedVariables: MSUFSuiteSkinDB",
               "## IconTexture: Interface\\AddOns\\MSUF_Suite\\Media\\SuiteIcon.tga", ""]
        (CORE_TARGET / f"MSUF_Suite_Skin_{flavor}.toc").write_text(
            "\n".join(toc + copied) + "\n", encoding="utf-8")

    for path in (core_source / "Media").rglob("*"):
        if path.is_file():
            target = CORE_TARGET / path.relative_to(core_source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    shutil.copy2(core_source / "THIRD_PARTY_NOTICES.txt", CORE_TARGET / "THIRD_PARTY_NOTICES.txt")
    shutil.copy2(source / "LICENSE.txt", CORE_TARGET / "LICENSE.txt")


def vendor_options(source):
    options_source = source / "MapkoSkin_Options"
    for flavor in FLAVORS:
        source_toc = options_source / f"MapkoSkin_Options_{flavor}.toc"
        source_lines = source_toc.read_text(encoding="utf-8-sig").splitlines()
        interface = next(line for line in source_lines if line.startswith("## Interface:"))
        source_entries = entries(source_toc)
        for entry in source_entries:
            if entry != "Shell\\Embedded.lua":
                copy_entry(options_source, OPTIONS_TARGET, entry, options_transforms)
        toc = [interface, "## Title: MSUF Suite - Skinning Options",
               "## Notes: Suite skinning pages inside MSUF.", "## Author: Mapko",
               f"## Version: {SUITE_VERSION}", "## Dependencies: MSUF_Suite_Skin, MSUF_Suite_Options",
               "## Group: MSUF_Suite", "## LoadOnDemand: 1",
               "## IconTexture: Interface\\AddOns\\MSUF_Suite\\Media\\SuiteIcon.tga", ""]
        (OPTIONS_TARGET / f"MSUF_Suite_Skin_Options_{flavor}.toc").write_text(
            "\n".join(toc + source_entries) + "\n", encoding="utf-8")


def main(arguments):
    # The refusal comes first: without the flag nothing is read or written.
    if FORCE_FLAG not in arguments:
        print(REFUSAL, file=sys.stderr)
        return 2
    paths = [argument for argument in arguments if argument != FORCE_FLAG]
    source = Path(paths[0] if paths else r"C:\MSUF Beta Branch\MapkoSkin")
    if not (source / "MapkoSkin").is_dir() or not (source / "MapkoSkin_Options").is_dir():
        print(f"No MapkoSkin checkout at {source}", file=sys.stderr)
        return 1
    vendor_core(source)
    vendor_options(source)
    print("Vendored MapkoSkin engine and all editor pages into Suite-owned addons")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
