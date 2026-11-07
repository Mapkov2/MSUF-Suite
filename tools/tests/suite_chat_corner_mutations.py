"""The first-move/corner/undo regressions must fail without changing source files."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
for mutation in (None, "nativeClamp", "firstMove", "adoptAnchor", "undoAnchor"):
    command = [lua, str(root / "tools/tests/suite_chat_audit_contract.lua"), str(root)]
    if mutation:
        command.append(mutation)
    result = subprocess.run(command, capture_output=True, text=True, timeout=45)
    if mutation is None and result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    if mutation and not result.returncode:
        raise AssertionError(f"corner regression survived: {mutation}")
    if mutation and "mutation site missing" in result.stderr:
        raise AssertionError(result.stderr)
print("Chat corner baseline passes; four native-margin/ownership/undo regressions fail")
