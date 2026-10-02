"""Readability rules for the shared runtime, Quality of Life and the chat copy
chooser: one statement per line (no `;` between statements) and at most 160
characters of code per line; a long string literal (a help text) is data.

Usage: python tools/tests/suite_qol_modules_style_smoke.py <tree root>
"""

import re
import sys
from pathlib import Path

MAX_CODE = 160
LONG_OPEN = re.compile(r"\[(=*)\[")


def scope(root):
    files = sorted((root / "MSUF_Suite_QualityOfLife").glob("*.lua"))
    files += sorted((root / "MSUF_Suite_Modules").glob("*.lua"))
    files.append(root / "MSUF_Suite_Chat" / "Copy.lua")
    return files


def code_lines(text):
    """Each line with comments removed and every string literal (short or
    long, which secure snippets use) collapsed to S."""
    closing = None
    for line in text.split("\n"):
        out, i = [], 0
        while i < len(line):
            if closing:
                end = line.find(closing, i)
                if end < 0:
                    i = len(line)
                    break
                i, closing = end + len(closing), None
                out.append("S")
                continue
            if line.startswith("--", i):
                opened = LONG_OPEN.match(line, i + 2)
                if opened:
                    closing = "]" + opened.group(1) + "]"
                    i = opened.end()
                    continue
                break
            opened = LONG_OPEN.match(line, i)
            if opened:
                closing = "]" + opened.group(1) + "]"
                i = opened.end()
                continue
            char = line[i]
            if char in "\"'":
                j = i + 1
                while j < len(line) and line[j] != char:
                    j += 2 if line[j] == "\\" else 1
                out.append("S")
                i = j + 1
                continue
            out.append(char)
            i += 1
        yield line, "".join(out)


def main():
    root = Path(sys.argv[1])
    problems = []
    for path in scope(root):
        rel = path.relative_to(root).as_posix()
        text = path.read_bytes().decode("utf-8").replace("\r\n", "\n")
        for number, (line, code) in enumerate(code_lines(text), 1):
            if ";" in code:
                problems.append("%s:%d chains statements with ';'" % (rel, number))
            if len(code.rstrip()) > MAX_CODE:
                problems.append("%s:%d has %d characters of code (at most %d)" % (rel, number, len(code), MAX_CODE))
    for problem in problems:
        print("FAIL " + problem)
    if problems:
        return 1
    print("suite QoL/Modules style: %d files, one statement per line, code lines <= %d" % (len(scope(root)), MAX_CODE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
