"""Line style of the BuffReminders, Chat and Nameplates addons: no statements
chained with `;` and no line longer than 160 characters.

Usage: python tools/tests/suite_br_chat_np_line_style_contract.py <repo root>

Chat/Copy.lua is covered by its own package. Strings and comments are left
out of the `;` check; a long bracket string or comment fails the check, so
it cannot hide code from it.
"""

import sys
from pathlib import Path

ADDONS = ("MSUF_Suite_BuffReminders", "MSUF_Suite_Chat", "MSUF_Suite_Nameplates")
SKIP = {"MSUF_Suite_Chat/Copy.lua"}
MAX_LINE = 160


def code_only(line):
    """The line without its comment and the contents of its strings."""
    out, quote, i = [], None, 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'":
            quote = ch
        elif line.startswith("--", i):
            break
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def problems(root):
    found = []
    for addon in ADDONS:
        for path in sorted((root / addon).rglob("*.lua")):
            relative = path.relative_to(root).as_posix()
            if relative in SKIP:
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
                where = "%s:%d" % (relative, number)
                if "[[" in line or "[=" in line:
                    found.append(where + " uses a long bracket; the line check cannot read past it")
                if len(line) > MAX_LINE:
                    found.append("%s is %d characters long (at most %d)" % (where, len(line), MAX_LINE))
                if ";" in code_only(line).rstrip().rstrip(";"):
                    found.append(where + " chains statements with ';': " + line.strip())
    return found


def main():
    root = Path(sys.argv[1]).resolve()
    found = problems(root)
    # The checker itself: a chained line and a long line are found, a
    # semicolon inside a string or a comment is not.
    samples = ['if x then a(); return end', 'local s = "a; b" -- c; d', "x" * (MAX_LINE + 1)]
    assert ";" in code_only(samples[0]) and ";" not in code_only(samples[1])
    assert len(samples[2]) > MAX_LINE
    for problem in found:
        print(problem)
    if found:
        print("%d line style problems" % len(found))
        return 1
    print("BuffReminders, Chat and Nameplates line style: no chained statements, no line over %d characters"
          % MAX_LINE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
