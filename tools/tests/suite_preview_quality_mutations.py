"""Run scoped in-memory regressions without editing the checkout."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
expected = {
    "meterText": "meter value text opened bar settings",
    "bank": "bank search opened inventory settings",
    "icons": "bag preview still contains question marks",
    "warm": "unchanged bag preview redrew its chrome",
    "skinHidden": "hidden skin preview repainted runtime surfaces",
    "cdmHidden": "hidden CDM canvas rendered",
    "chatReady": "cold-combat Chat preview never retried its runtime font painter",
    "chatRegen": "Chat preview has no visible post-combat retry event",
}
for case, message in expected.items():
    run = subprocess.run([lua, str(root / "tools/tests/suite_preview_quality_contract.lua"), str(root), "Mainline", case],
                         cwd=root, capture_output=True, text=True, errors="replace")
    assert run.returncode and message in run.stderr, f"{case}: unexpected result\n{run.stderr}"
print("Preview quality: 8 focused regressions rejected")
