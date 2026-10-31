"""Selected locale loading, canonical catalog reachability and package completeness."""
import importlib.util
import sys
from pathlib import Path

root = Path(sys.argv[1])
toc_path = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "MSUF_Suite/MSUF_Suite_Mainline.toc"
locales = ("deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW")
core_entries = [line.strip().replace("\\", "/") for line in toc_path.read_text(encoding="utf-8-sig").splitlines()
                if line.strip() and not line.lstrip().startswith("#")]
assert core_entries[0] == "Core/Platform.lua", "locale catalogs still compile unconditionally before Platform"
assert not any(line.startswith("Locales/") for line in core_entries), "inactive catalogs remain on the core load graph"
spec = importlib.util.spec_from_file_location("suite_release", root / "tools/build_suite_release.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
files = builder.tracked_files(root)
version = builder.field(toc_path.read_text(encoding="utf-8-sig"), "Version")
addons = builder.validate_addons(root, files, version)
name = "MSUF_Suite_Locales"
manifest = name + "/" + name + "_Mainline.toc"
assert name in addons and manifest in files, "combined locale addon omitted from tracked package"
assert not any(addon.startswith("MSUF_Suite_Locale_") for addon in addons), "individual languages still installed"
text = (root / manifest).read_text(encoding="utf-8-sig")
assert builder.field(text, "Dependencies") == "MidnightSimpleUnitFrames", "mid-load Suite dependency cycle"
assert builder.field(text, "LoadOnDemand") == "1"
assert builder.field(text, "Version") == version
entries = [line.strip().replace("\\", "/") for line in text.splitlines()
           if line.strip() and not line.lstrip().startswith("#")]
assert entries == ["../MSUF_Suite/Locales/" + locale + ".lua" for locale in locales]
for locale in locales:
    catalog = "MSUF_Suite/Locales/" + locale + ".lua"
    assert catalog in files, "canonical locale catalog omitted from tracked package"
    source = (root / catalog).read_text(encoding="utf-8-sig")
    assert 'MSUF.LOCALE ~= "' + locale + '" then return end' in source, "inactive catalog can populate translations"
    for omitted in ({manifest}, {manifest, catalog}, {catalog}):
        try:
            builder.validate_addons(root, [path for path in files if path not in omitted], version)
        except ValueError:
            pass
        else:
            raise AssertionError("Package accepted incomplete locale: " + locale)
print("Suite locale manifests: one optional addon, all10 guarded catalogs/versions/dependencies/references packaged")
