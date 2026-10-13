"""Long-term engine regressions, with real product loads and positive controls.

Usage: python tools/tests/suite_longterm_engine_contract.py ROOT [LUA51]
An optional case argument after LUA51 selects one regression for original-red
verification. Secret-return injection is conditional defensive sink evidence.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
lua = (sys.argv[2] if len(sys.argv) > 2 else os.environ.get("MSUF_LUA")
       or shutil.which("lua5.1") or shutil.which("lua"))
if not lua:
    raise SystemExit("Lua 5.1 required; pass its executable as arg2")
cases = [sys.argv[3]] if len(sys.argv) > 3 else [
    "run_summary", "meter", "profile_catalog", "timer_pool", "datatext_style", "preview_font", "feedback",
]
env = os.environ.copy()
for key in ("MSUF_TEST_AURAS_FILE", "MSUF_TEST_AURA_TIMERS_FILE", "MSUF_TEST_ALERTS_FILE"):
    env.pop(key, None)
runner = Path(__file__).with_name("longterm_engine_cases.lua")

def run(*args):
    result = subprocess.run(args, env=env, text=True, capture_output=True)
    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)
    if result.returncode:
        raise SystemExit(result.returncode)

run(lua, "-e", "assert(_VERSION=='Lua 5.1','Lua 5.1 required')")
for case in cases:
    print("CASE", case, flush=True)
    if case == "feedback":
        with tempfile.TemporaryDirectory(prefix="suite-feedback-") as folder:
            blob = str(Path(folder) / "feedback.luac")
            run(lua, str(runner), str(root).replace('\\','/'), "feedback_dump", blob)
            run(sys.executable, str(Path(__file__).with_name("longterm_feedback_vm.py")), blob)
    elif case == "datatext_style":
        for flavor in ("Mainline", "Forever"):
            run(lua, str(runner), str(root).replace('\\','/'), case, flavor)
    else:
        run(lua, str(runner), str(root).replace('\\','/'), case)
print("suite_longterm_engine_contract: ok")
