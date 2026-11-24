"""The group finder glyphs on disk match tools/build_group_finder_symbols.py."""
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
subprocess.run([sys.executable, str(root / "tools/build_group_finder_symbols.py"), "--check"], check=True)
for name in ("Eye", "Search", "Group", "Dungeon"):
    data = (root / "MSUF_Suite/Media/GroupFinder" / (name + ".tga")).read_bytes()
    width, height = int.from_bytes(data[12:14], "little"), int.from_bytes(data[14:16], "little")
    assert data[2] == 2 and data[16] == 32 and (width, height) == (64, 64), name + " is not a 64x64 RGBA TGA"
print("Group finder symbols: generated glyphs match and load as 64x64 RGBA TGA")
