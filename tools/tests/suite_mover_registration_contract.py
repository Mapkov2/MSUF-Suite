"""Edit Mode movers are registered once per Enable or Refresh.

The controller (MSUF_Suite/Core/Suite.lua ApplyModule) calls S.RefreshEditMover
right after every module Enable and Refresh, and that calls the module's
RegisterMovers (MSUF_Suite_Modules/EditMode.lua). A module that also calls it
from its own Enable or Refresh registers twice per start: the DataTexts bars
even drop and re-add their whole owner each time (Movers.Register). Only the
controller hook and the DataTexts scale change, which refreshes outside the
controller, call RegisterMovers.

Usage: python tools/tests/suite_mover_registration_contract.py <tree root>

Files that another package owns are named in SKIP.
"""

import re
import sys
from pathlib import Path

ADDONS = ("MSUF_Suite_QualityOfLife", "MSUF_Suite_Modules", "MSUF_Suite_Bags", "MSUF_Suite_DataTexts",
          "MSUF_Suite_Minimap", "MSUF_Suite_Nameplates", "MSUF_Suite_BuffReminders", "MSUF_Suite_Chat",
          "MSUF_Suite_ActionBars", "MSUF_Suite_CooldownManager")
SKIP = {"MSUF_Suite_QualityOfLife/GroupBloodlust.lua", "MSUF_Suite_QualityOfLife/ActionTracker.lua"}
ALLOWED = {"MSUF_Suite_Modules/EditMode.lua": 1, "MSUF_Suite_DataTexts/DataTexts.lua": 1}
CALL = re.compile(r"[:.]RegisterMovers\(\)")
DEFINITION = re.compile(r"function\s+\w+[:.]RegisterMovers\(\)")


def calls(text):
    count = 0
    for line in text.split("\n"):
        code = line.split("--", 1)[0]
        if CALL.search(code) and not DEFINITION.search(code):
            count += 1
    return count


def main():
    root = Path(sys.argv[1]).resolve()
    assert calls("    self:RegisterMovers()") == 1 and calls("function M:RegisterMovers()") == 0
    assert calls("    self:RegisterMovers() -- the controller does it") == 1 and calls("-- self:RegisterMovers()") == 0
    problems = []
    seen = {}
    for addon in ADDONS:
        for path in sorted((root / addon).rglob("*.lua")):
            rel = path.relative_to(root).as_posix()
            if "Libs" in path.parts or rel in SKIP:
                continue
            count = calls(path.read_bytes().decode("utf-8"))
            seen[rel] = count
            if count != ALLOWED.get(rel, 0):
                problems.append("%s calls RegisterMovers %d time(s), expected %d: the controller registers the "
                                "movers after Enable and Refresh" % (rel, count, ALLOWED.get(rel, 0)))
    for rel in ALLOWED:
        if rel not in seen:
            problems.append(rel + " is missing")
    for problem in problems:
        print("FAIL " + problem)
    if problems:
        return 1
    print("suite mover registration: %d files, RegisterMovers only from the controller hook and the DataTexts scale change"
          % len(seen))
    return 0


if __name__ == "__main__":
    sys.exit(main())
