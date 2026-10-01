"""The structure gate's pcall check (suite_structure_gate.py, check 5).

Every Lua file of every MSUF_Suite* addon, Nameplates included, may not use
pcall or xpcall. Comments, strings, other identifiers containing the word and
vendored Libs/ do not count, and the check has no allowlist. Runs the gate's
own function over a small throwaway tree.

Usage: python tools/tests/suite_structure_gate_pcall_contract.py [repo root]
"""

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import suite_structure_gate as gate  # noqa: E402

FILES = {
    "MSUF_Suite_Example/Code.lua": "local ok = pcall(print)\nlocal guarded = xpcall\n",
    "MSUF_Suite_Example/Clean.lua": "-- pcall(print) in a comment\n--[[ xpcall(print) ]]\n"
                                    "local text = \"pcall(\" .. [[xpcall(]]\nlocal mypcall, pcallCount = 1, 2\n",
    "MSUF_Suite_Nameplates/NameplateSkin.lua": "local a = 1\nreturn pcall(error)\n",
    "MSUF_Suite_Skin/Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua": "return xpcall(error, print)\n",
    "OtherAddon/Code.lua": "return pcall(error)\n",
}
EXPECTED = [
    "MSUF_Suite_Example/Code.lua:1 uses pcall",
    "MSUF_Suite_Example/Code.lua:2 uses xpcall",
    "MSUF_Suite_Nameplates/NameplateSkin.lua:2 uses pcall",
]


def main():
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        for rel, text in FILES.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="\n")
        found = sorted(problem.split(";")[0] for problem in gate.pcall_problems(root))
    if found != EXPECTED:
        print("FAIL the gate's pcall check found %s, expected %s" % (found, EXPECTED))
        return 1
    print("suite structure gate pcall check: ok (%d uses found, comments, strings and Libs/ ignored)" % len(found))
    return 0


if __name__ == "__main__":
    sys.exit(main())
