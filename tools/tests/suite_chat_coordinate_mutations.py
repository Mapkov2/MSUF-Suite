"""Run causal coordinate regressions in isolated Lua processes."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
host = root.parent / "MidnightSimpleUnitFrames-7.0"
expected = {
    "rawFields": "Chat still replaces shared screen coordinates",
    "scale": "typed coordinate did not land on the requested visible pixel",
    "bounds": "Chat coordinates disagree with an ordinary Edit Mode frame",
    "precision": "scaled nudge accumulated coordinate drift",
    "integerSchema": "typed coordinate did not land on the requested visible pixel",
}
for mode, message in expected.items():
    run = subprocess.run([lua, str(root / "tools/tests/suite_chat_screen_coordinates_contract.lua"),
                          str(root), "Mainline", str(host), mode], cwd=root, capture_output=True,
                         text=True, errors="replace", timeout=60)
    assert run.returncode and message in run.stdout + run.stderr, f"{mode}: unexpected result\n{run.stdout}\n{run.stderr}"
print("Chat screen coordinates: five causal regressions rejected")
