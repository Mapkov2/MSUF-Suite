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
all_bytes, largest = 0, 0
for locale in locales:
    name = "MSUF_Suite_Locale_" + locale
    manifest = name + "/" + name + "_Mainline.toc"
    assert name in addons and manifest in files, "locale companion omitted from tracked package"
    catalog = "MSUF_Suite/Locales/" + locale + ".lua"
    assert catalog in files, "canonical locale catalog omitted from tracked package"
    text = (root / manifest).read_text(encoding="utf-8-sig")
    assert builder.field(text, "Dependencies") == "MidnightSimpleUnitFrames", "mid-load Suite dependency cycle"
    assert builder.field(text, "LoadOnDemand") == "1"
    assert builder.field(text, "Version") == version
    source = (root / ("MSUF_Suite/Locales/" + locale + ".lua")).read_bytes().replace(b"\r\n", b"\n")
    size = len(source)
    all_bytes += size
    largest = max(largest, size)
    for omitted in ({manifest}, {manifest, catalog}, {catalog}):
        try:
            builder.validate_addons(root, [path for path in files if path not in omitted], version)
        except ValueError:
            pass
        else:
            raise AssertionError("Package accepted incomplete locale: " + locale)
assert largest < all_bytes * .20, "selected pack no longer removes at least 80 percent of locale compilation input"
print(f"Suite locale manifests: all10 companions/versions/dependencies/references packaged; largest {largest}/{all_bytes} locale bytes")
