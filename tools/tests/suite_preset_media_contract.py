"""Media used by setup presets must resolve in the shipping addon paths."""

import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root / "tools"))
from build_suite_release import tracked_files, validate_preset_media

# Verify the indexed package paths, including files pending addition. The
# independent release test also covers the ZIP and its metadata.
sources = {"MSUF_Suite_Modules/ObjectivesVoice.lua", "MSUF_Suite_Nameplates/SlantedHealth.lua"}
payload = {path: (root / path).read_bytes() for path in tracked_files(root)
           if (path.startswith("MSUF_Suite/Core/") or "/Media/" in path or path in sources)
           and (root / path).is_file()}
validate_preset_media(payload)

for asset in ("WayfarerPlaque.tga", "WayfarerEndcap.tga", "WayfarerPreview.tga", "WayfarerMinimapFrame.tga",
              "QuestVoiceControls.tga",
              "BlizzardFrames/UnitFrame.tga", "Nameplates/SlantedHealthMask.tga",
              "Nameplates/SlantedHealthEdge.tga"):
    key = f"MSUF_Suite/Media/{asset}"
    without_asset = dict(payload)
    without_asset.pop(key)
    try:
        validate_preset_media(without_asset)
    except ValueError as error:
        assert "Missing packaged preset media" in str(error) and key in str(error), str(error)
    else:
        raise AssertionError(f"Preset passed with missing media: {key}")
print("Bundled preset paths and missing media checks passed")
