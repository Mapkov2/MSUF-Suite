"""Reject armor reminder regressions without editing product files."""
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
test = root / "tools/tests/suite_buff_reminders_class_contract.lua"
for case, expected in {
    "armorStandalone": "standalone armor preview depends on the class master",
    "armorOptOut": "a reminder ignored its switch",
    "armorPreview": "standalone armor preview ignored opt-out with the class master off",
    "innerFireDismiss": "learning Inner Fire lost dismissal",
    "armorMemory": "remember the armor family",
    "armorLate": "late character storage was not adopted",
    "armorRank": "remembered armor's highest known rank",
    "armorBind": "armor icon did not follow its action",
    "armorExpiry": "any active armor rank must satisfy",
    "armorSecret": "restricted absence became a reminder",
}.items():
    run = subprocess.run([lua, str(test), str(root), case], cwd=root,
                         capture_output=True, text=True, errors="replace")
    assert run.returncode != 0 and expected in run.stderr, f"{case}: unexpected result\n{run.stderr}"
print("Forever armor reminders: ten behavioral mutations rejected")
