"""Causal regressions execute in memory; no product file is changed."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
test = root / "tools/tests/suite_chat_toolbar_contract.lua"
for mutation in (None, "nativeDock", "hover", "combat", "profile", "inputToggle", "inputIM", "inputSquash", "inputSnap"):
    command = [lua, str(test), str(root)] + ([mutation] if mutation else [])
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    if mutation is None and result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    if mutation and not result.returncode:
        raise AssertionError(f"regression survived: {mutation}")
    if mutation and "mutation site missing" in result.stderr:
        raise AssertionError(result.stderr)
print("Chat header baseline passes; eight native-layout/combat/profile/hover/animation regressions fail")
