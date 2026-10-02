"""Line style of the Quality of Life, Modules, Bags, DataTexts, Minimap,
Nameplates, BuffReminders, Chat, ActionBars and Cooldown Manager addons: one
statement per line, so no statement chained with `;`, no statement on the
line of an `else` or `elseif ... then`, no `statement return end` line, and
no line with more than 160 characters of code. A long string literal (a help
text, a secure snippet) is data.

Usage: python tools/tests/suite_area_line_style_contract.py <tree root>

Files that another package owns are named in SKIP and covered by the style
checks of that package.
"""

import re
import sys
from pathlib import Path

ADDONS = ("MSUF_Suite_QualityOfLife", "MSUF_Suite_Modules", "MSUF_Suite_Bags", "MSUF_Suite_DataTexts",
          "MSUF_Suite_Minimap", "MSUF_Suite_Nameplates", "MSUF_Suite_BuffReminders", "MSUF_Suite_Chat",
          "MSUF_Suite_ActionBars", "MSUF_Suite_CooldownManager")
SKIP = {
    "MSUF_Suite_QualityOfLife/GroupBloodlust.lua", "MSUF_Suite_QualityOfLife/GroupDeathAlert.lua",
    "MSUF_Suite_QualityOfLife/ActionTracker.lua", "MSUF_Suite_Modules/Raid.lua",
    "MSUF_Suite_Nameplates/Text.lua", "MSUF_Suite_Chat/Messages.lua",
    "MSUF_Suite_ActionBars/Paint.lua", "MSUF_Suite_ActionBars/Events.lua", "MSUF_Suite_ActionBars/Flush.lua",
    "MSUF_Suite_CooldownManager/Effects.lua", "MSUF_Suite_CooldownManager/Events.lua",
    "MSUF_Suite_CooldownManager/Flush.lua", "MSUF_Suite_CooldownManager/Time.lua",
}
MAX_CODE = 160
LONG_OPEN = re.compile(r"\[(=*)\[")
ELSE_STATEMENT = re.compile(r"^\s*(else\s+\S|elseif\b.*\bthen\s+\S)")
# `if x then Call() return end`: a statement, then the return, in one line.
STATEMENT_RETURN = re.compile(r"\bthen\s+(?!return\b)\S.*[\w)\]}S]\s+return\b.*\bend\s*$")


def scope(root):
    files = []
    for addon in ADDONS:
        for path in sorted((root / addon).rglob("*.lua")):
            if "Libs" not in path.parts and path.relative_to(root).as_posix() not in SKIP:
                files.append(path)
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


def findings(rel, text):
    found = []
    for number, (line, code) in enumerate(code_lines(text), 1):
        where = "%s:%d" % (rel, number)
        code = code.rstrip()
        if ";" in code.rstrip(";"):
            found.append(where + " chains statements with ';'")
        if len(code) > MAX_CODE:
            found.append("%s has %d characters of code (at most %d)" % (where, len(code), MAX_CODE))
        if ELSE_STATEMENT.match(code):
            found.append(where + " puts a statement on its else line: " + line.strip())
        if STATEMENT_RETURN.search(code):
            found.append(where + " puts a statement before its return: " + line.strip())
    return found


def self_check():
    bad = ["a(); b()", "    else b() end", "    elseif y then b()", "if x then Show(self) return end",
           'if x then Status("a") return end', "if x then y = 1 return end"]
    good = ["if x then return end", "if x then return a, b end", "    if x then a() else b() end", "    else",
            "if x then Show(self) end", 'local s = "a; b" -- c; d', "    elseif y then", "if a then return end",
            'if x then S.Hide() end return', "local function Frame() return SpecFrame(spec) end"]
    for line in bad:
        assert findings("t", line), line
    for line in good:
        assert not findings("t", line), line
    assert findings("t", "x" * (MAX_CODE + 1))


def main():
    root = Path(sys.argv[1]).resolve()
    self_check()
    problems = []
    files = scope(root)
    for path in files:
        text = path.read_bytes().decode("utf-8").replace("\r\n", "\n")
        problems += findings(path.relative_to(root).as_posix(), text)
    for problem in problems:
        print("FAIL " + problem)
    if problems:
        print("%d line style problems" % len(problems))
        return 1
    print("suite area line style: %d files, one statement per line, code lines <= %d" % (len(files), MAX_CODE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
