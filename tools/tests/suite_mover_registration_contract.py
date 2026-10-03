"""Edit Mode movers are registered once per Enable or Refresh.

The controller (MSUF_Suite/Core/Suite.lua ApplyModule) calls S.RefreshEditMover
right after every module Enable and Refresh, and that calls the module's
RegisterMovers (MSUF_Suite_Modules/EditMode.lua). A module that also calls it
from its own Enable or Refresh registers twice per start: the DataTexts bars
even drop and re-add their whole owner each time (Movers.Register). Only the
controller hook and the DataTexts scale change, which refreshes outside the
controller, call RegisterMovers.

The registrations themselves (S.RegisterOwnedMover) live in a module's
RegisterMovers, or in a helper that only RegisterMovers calls (HELPERS): a
registration from Enable or from a refresh helper bypasses the controller's
one registration per start, and the check above cannot see it.

Usage: python tools/tests/suite_mover_registration_contract.py <tree root>

Files that another package owns would be named in SKIP (none since the wave-4 merge).
"""

import re
import sys
from pathlib import Path

ADDONS = ("MSUF_Suite_QualityOfLife", "MSUF_Suite_Modules", "MSUF_Suite_Bags", "MSUF_Suite_DataTexts",
          "MSUF_Suite_Minimap", "MSUF_Suite_Nameplates", "MSUF_Suite_BuffReminders", "MSUF_Suite_Chat",
          "MSUF_Suite_ActionBars", "MSUF_Suite_CooldownManager", "MSUF_Suite_DamageMeter")
SKIP = set()
ALLOWED = {"MSUF_Suite_Modules/EditMode.lua": 1, "MSUF_Suite_DataTexts/DataTexts.lua": 1}
CALL = re.compile(r"[:.]RegisterMovers\(\)")
DEFINITION = re.compile(r"function\s+\w+[:.]RegisterMovers\(\)")
# Helpers that register movers for their module's RegisterMovers and are
# called from nowhere else: the DataTexts bars (DataTexts.lua M:RegisterMovers).
HELPERS = {"MSUF_Suite_DataTexts/Movers.lua": {"Movers.Register"}}
REGISTER = re.compile(r"\bS\.RegisterOwnedMover\(")
REGISTER_DEFINITION = re.compile(r"function\s+S\.RegisterOwnedMover\(")
FUNCTION = re.compile(r"^(?:local\s+)?function\s+([\w.:]+)\s*\(")


def calls(text):
    count = 0
    for line in text.split("\n"):
        code = line.split("--", 1)[0]
        if CALL.search(code) and not DEFINITION.search(code):
            count += 1
    return count


def registrations(text):
    """(line, enclosing function) of every S.RegisterOwnedMover call: the
    nearest top-level function definition above it, or None in the main chunk."""
    found, current = [], None
    for number, line in enumerate(text.split("\n"), 1):
        code = line.split("--", 1)[0]
        match = FUNCTION.match(code)
        if match:
            current = match.group(1)
        if REGISTER.search(code) and not REGISTER_DEFINITION.search(code):
            found.append((number, current))
    return found


def misplaced(rel, text):
    allowed = HELPERS.get(rel, set())
    return [(line, name) for line, name in registrations(text)
            if not (name and (name.endswith(":RegisterMovers") or name.endswith(".RegisterMovers")
                              or name in allowed))]


def self_test():
    assert calls("    self:RegisterMovers()") == 1 and calls("function M:RegisterMovers()") == 0
    assert calls("    self:RegisterMovers() -- the controller does it") == 1 and calls("-- self:RegisterMovers()") == 0
    body = "\n    S.RegisterOwnedMover(ID, 'a', {})\nend"
    assert misplaced("x.lua", "function M:RegisterMovers()" + body) == []
    assert misplaced("x.lua", "function M:Enable()" + body) == [(2, "M:Enable")]
    assert misplaced("x.lua", "local function RefreshPanel(self)" + body) == [(2, "RefreshPanel")]
    assert misplaced("x.lua", "S.RegisterOwnedMover(ID, 'a', {})") == [(1, None)]
    assert misplaced("x.lua", "function S.RegisterOwnedMover(id, elementID, spec)\nend") == []
    assert misplaced("x.lua", "function M:Enable()\n    -- S.RegisterOwnedMover(ID, 'a', {})\nend") == []
    assert misplaced("MSUF_Suite_DataTexts/Movers.lua", "function Movers.Register(module)" + body) == []


def main():
    root = Path(sys.argv[1]).resolve()
    self_test()
    problems = []
    seen = {}
    for addon in ADDONS:
        for path in sorted((root / addon).rglob("*.lua")):
            rel = path.relative_to(root).as_posix()
            if "Libs" in path.parts or rel in SKIP:
                continue
            text = path.read_bytes().decode("utf-8")
            count = calls(text)
            seen[rel] = count
            if count != ALLOWED.get(rel, 0):
                problems.append("%s calls RegisterMovers %d time(s), expected %d: the controller registers the "
                                "movers after Enable and Refresh" % (rel, count, ALLOWED.get(rel, 0)))
            for line, name in misplaced(rel, text):
                problems.append("%s:%d registers a mover from %s: S.RegisterOwnedMover belongs in the module's "
                                "RegisterMovers, which the controller calls" % (rel, line, name or "the main chunk"))
    for rel in list(ALLOWED) + list(HELPERS):
        if rel not in seen:
            problems.append(rel + " is missing")
    for problem in problems:
        print("FAIL " + problem)
    if problems:
        return 1
    print("suite mover registration: %d files, RegisterMovers only from the controller hook and the DataTexts scale"
          " change, S.RegisterOwnedMover only inside RegisterMovers" % len(seen))
    return 0


if __name__ == "__main__":
    sys.exit(main())
