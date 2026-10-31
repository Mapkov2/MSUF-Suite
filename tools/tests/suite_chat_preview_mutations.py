"""Causal regressions run in Lua's isolated loader; never replace live source."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
expected = {
    "follow": "drag has no visible follow",
    "previewCombat": "combat repaint lost the saved sample tab position",
    "static": "prefix",
    "clipping": "selection toolbar is clipped below its own viewport",
    "resize": "resize during drag committed a stale position",
    "origin": "unmoved icon did not read its automatic position",
    "reset": "reset did not restore automatic sidebar layout",
    "profile": "profile epoch revived a stale drag",
    "legacy": "legacy preview click did not open its accordion",
    "inputProfile": "pending coordinate text wrote into another profile",
    "axisProfile": "pending toolbar text wrote into another profile",
}
for case, message in expected.items():
    command = [lua, str(root / "tools/tests/suite_chat_preview_contract.lua"), str(root), "Mainline",
               str(root.parent / "MidnightSimpleUnitFrames"), case]
    result = subprocess.run(command, cwd=root, capture_output=True, text=True, errors="replace")
    assert result.returncode and message in result.stderr, f"{case}: unexpected result\n{result.stdout}\n{result.stderr}"
print("Chat interactive preview: eleven causal regressions rejected")

for case, message in {
    "messageRestore": "insertion corner after reset",
    "tabRecovery": "combat native tab rebuild",
    "floatingGap": "gap reset retains independent floating offset",
    "messageOffset": "initial text offset",
    "inputOffset": "input offset preserves native origin",
}.items():
    command = [lua, str(root / "tools/tests/suite_chat_positions_contract.lua"), str(root), "Mainline",
               str(root.parent / "MidnightSimpleUnitFrames"), case]
    result = subprocess.run(command, cwd=root, capture_output=True, text=True, errors="replace")
    assert result.returncode and message in result.stdout, f"{case}: unexpected result\n{result.stdout}\n{result.stderr}"
print("Chat native positions: five causal regressions rejected")
