"""Exercise public profile/lifecycle capture paths in the real ActionBars fixture."""
import os
import subprocess
import sys
from pathlib import Path

ROOT=Path(sys.argv[1])
LUA=os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
CASES=("a_to_b_false","a_to_b_true","a_to_b_to_a","a_to_imported_b_to_a",
       "same_config_reenable","combat_retry","config_reset","refresh_dedup")
for mode in ("painted","native"):
    for scenario in CASES:
        run=subprocess.run([LUA,str(ROOT/"tools/tests/suite_actionbars_contract.lua"),
                            str(ROOT),mode,"capture",scenario],cwd=ROOT,capture_output=True,text=True)
        if run.returncode:
            print(mode,scenario,run.stdout+run.stderr)
            raise SystemExit(1)
print("ActionBars public capture lifecycle: 16 cases passed")
