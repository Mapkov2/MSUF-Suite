"""Run every Suite contract test with its required arguments.

Usage: python tools/run_suite_tests.py [name-filter]
Exit code 0 only when every selected test passes.
"""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRANCH = ROOT.parent
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
HELPERS = {"suite_test_support.lua", "suite_minimap_harness.lua"}
FLAVORS = ("Mainline", "Forever", "Vanilla", "TBC", "Mists")
EXTRA = {
    "suite_skin_absorption_contract.lua": [[str(BRANCH / "MapkoSkin")]],
    "suite_skin_msuf_bridge_contract.lua": [[str(BRANCH / "MidnightSimpleUnitFrames"),
                                             str(BRANCH / "MidnightSimpleUnitFrames-Classic")]],
    "suite_load_graph_contract.lua": [[flavor] for flavor in FLAVORS],
    "suite_actionbars_contract.lua": [[], ["native"]],
}


def commands(test):
    if test.suffix == ".py":
        return [[sys.executable, str(test), str(ROOT)]]
    if test.name == "suite_skin_msuf_bridge_contract.lua":
        return [[LUA, str(test)] + EXTRA[test.name][0]]
    return [[LUA, str(test), str(ROOT)] + extra for extra in EXTRA.get(test.name, [[]])]


def main():
    wanted = sys.argv[1] if len(sys.argv) > 1 else ""
    tests = sorted(p for p in (ROOT / "tools" / "tests").glob("suite_*")
                   if p.suffix in (".lua", ".py") and p.name not in HELPERS and wanted in p.name)
    failed = []
    for test in tests:
        for command in commands(test):
            run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, errors="replace")
            label = " ".join([test.name] + [Path(a).name for a in command[2:] if a != str(ROOT)])
            if run.returncode == 0:
                print("ok   " + label)
            else:
                failed.append(label)
                print("FAIL " + label)
                print("\n".join((run.stdout + run.stderr).strip().splitlines()[-6:]))
    print("\n%d passed, %d failed" % (sum(len(commands(t)) for t in tests) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
