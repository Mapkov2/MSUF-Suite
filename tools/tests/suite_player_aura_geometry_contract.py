"""Restricted or unavailable native aura geometry stays untouched and recovers."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
for mode in ("count_nil", "count_secret", "count_nan", "point_empty", "point_nil", "point_partial", "point_coord_nil", "size_nil",
             "scale_nil", "scale_secret", "level_nil", "level_secret", "forbidden"):
    subprocess.run([lua, str(root / "tools/tests/suite_player_auras_contract.lua"), str(root), mode],
                   cwd=root, check=True)
