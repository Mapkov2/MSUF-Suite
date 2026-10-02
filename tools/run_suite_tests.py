"""Run every Suite contract test with its required arguments.

Usage: python tools/run_suite_tests.py [name-filter]
Exit code 0 only when every selected test passes. After the contracts it runs the
quality ratchet (tools/quality_ratchet.py --check) and prints its one summary line;
a filter selects it with "ratchet".
"""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRANCH = ROOT.parent
RATCHET = ROOT / "tools" / "quality_ratchet.py"
LUA =os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
HELPERS = {"suite_test_support.lua", "suite_minimap_harness.lua", "suite_bags_harness.lua"}
# The Suite supports Retail and WoW Forever only (Forever loads the Mainline TOC).
FLAVORS = ("Mainline", "Forever")
EXTRA = {
    "suite_hud_contract.lua": [[], ["Forever"]],
    "suite_options_menu_contract.lua": [[], ["Forever"]],
    "suite_search_provider_contract.lua": [[], ["Forever"], ["Mainline", str(BRANCH / "MidnightSimpleUnitFrames")]],
    "suite_skin_absorption_contract.lua": [[str(BRANCH / "MapkoSkin"), str(BRANCH / "MidnightSimpleUnitFrames")],
                                           [str(BRANCH / "MapkoSkin"), "Forever"]],
    "suite_skin_msuf_bridge_contract.lua": [[str(BRANCH / "MidnightSimpleUnitFrames"),
                                             str(BRANCH / "MidnightSimpleUnitFrames-Classic")]],
    "suite_load_graph_contract.lua": [[flavor] for flavor in FLAVORS],
    "suite_datatexts_contract.lua": [[flavor] for flavor in FLAVORS],
    "suite_datatexts_security_contract.lua": [[flavor] for flavor in FLAVORS],
    "suite_datatexts_load_conditions_contract.lua": [[flavor] for flavor in FLAVORS],
    "suite_actionbars_contract.lua": [[], ["native"]],
    # The locale contract reads the live extraction through the same Python.
    "suite_locale_contract.lua": [[sys.executable]],
}


def commands(test):
    if test.suffix == ".py":
        return [[sys.executable, str(test), str(ROOT)]]
    if test.name == "suite_skin_msuf_bridge_contract.lua":
        return [[LUA, str(test)] + EXTRA[test.name][0]]
    return [[LUA, str(test), str(ROOT)] + extra for extra in EXTRA.get(test.name, [[]])]


def run_ratchet(failed):
    """The quality ratchet is one more check; its one summary line is its output."""
    env = dict(os.environ)
    env.setdefault("MSUF_LUA51", LUA)
    run = subprocess.run([sys.executable, str(RATCHET), "--check"], cwd=ROOT, capture_output=True, text=True,
                         errors="replace", env=env)
    lines = (run.stdout + run.stderr).strip().splitlines()
    if run.returncode == 0:
        print("ok   " + (lines[-1] if lines else "quality ratchet"))
        return
    failed.append("quality_ratchet.py --check")
    print("FAIL quality_ratchet.py --check")
    print("\n".join(lines[-12:]))


def main():
    wanted = sys.argv[1] if len(sys.argv) > 1 else ""
    tests = sorted(p for p in (ROOT / "tools" / "tests").glob("suite_*")
                   if p.suffix in (".lua", ".py") and p.name not in HELPERS and wanted in p.name)
    ratchet = RATCHET.is_file() and wanted in "quality_ratchet"
    failed = []
    total = sum(len(commands(test)) for test in tests)
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
    if ratchet:
        total += 1
        run_ratchet(failed)
    if wanted in "suite_inventory_diff.py":
        total += 1
        label = "suite_inventory_diff.py"
        run = subprocess.run([sys.executable, str(ROOT / "tools" / label)], cwd=ROOT,
                             capture_output=True, text=True, errors="replace")
        if run.returncode:
            failed.append(label)
            print("FAIL " + label)
        # The inventory owns its single summary line and names every open loss.
        print((run.stdout + run.stderr).strip())
    print("\n%d passed, %d failed" % (total - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
