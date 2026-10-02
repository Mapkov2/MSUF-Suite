"""Chat prints and composed menu texts reach the reader translated.

* Every Print of the Suite core and addons passes translated text: a string
  literal as its first argument stays English (a slash command is a name).
* Text the locale tool sees built at runtime and handed to a translation
  sink (`suite_locale_tool.py dynamic`) cannot translate. Only the entries
  below may do that: catalog enableKey fields hold setting keys, and the chat
  preview joins texts that are each translated (a chat line has no grammar).
* Menu2's font strings and buttons translate what they are given (T.Font's
  SetText, T.Button). The options pages hand them English text; text in the
  reader's language already goes through P.SetTranslatedText or
  P.SetButtonText, so it is never looked up a second time.
"""
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1])
failures = []

PRINT = re.compile(r"\bPrint\(\s*(['\"])(.*?)\1")
for path in sorted(root.glob("MSUF_Suite*/**/*.lua")):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = PRINT.search(line)
        if match and not match.group(2).startswith("/"):
            failures.append("%s:%d prints English text: %s" % (path.relative_to(root).as_posix(), number, line.strip()))

ALLOWED = (
    ("MSUF_Suite/Core/Catalog/", "field:enableKey"),
    ("MSUF_Suite_Options/Pages/Chat.lua:", "lines:SetText#0"),
)
run = subprocess.run([sys.executable, str(root / "tools" / "suite_locale_tool.py"), "dynamic"],
                     cwd=root, capture_output=True, text=True, encoding="utf-8")
if run.returncode != 0:
    failures.append("suite_locale_tool.py dynamic failed: " + run.stderr.strip()[-400:])
for line in run.stdout.splitlines():
    fields = line.split("\t")
    if len(fields) < 3:
        continue
    where, sink = fields[0], fields[2]
    if not any(where.startswith(prefix) and sink == allowed for prefix, allowed in ALLOWED):
        failures.append("runtime-built text reaches a translation: " + line)

# Creators that translate their text argument, and the widgets they make.
CREATOR = r"(?:P\.T\.Font|T\.Font|P\.T\.Button|T\.Button|W\.TopButton|W\.RoleButton|P\.Text|Label|Button)"
CALL = re.compile(r"(?<![\w.:])" + CREATOR + r"\(")
MADE = re.compile(r"(?:local\s+)?([\w.]+)\s*=\s*\(?" + CREATOR + r"\(")
TRANSLATED = re.compile(r"\b(?:Tr|StatusText)\(")
# The section popup's title comes from callers in either form (some pass
# English, some a translated title).
CREATOR_ALLOWED = {("MSUF_Suite_Options/Menu/SectionActions.lua", "local heading = T.Font(popup")}


def Arguments(line, start):
    depth, at = 0, start
    while at < len(line):
        if line[at] == "(":
            depth += 1
        elif line[at] == ")":
            depth -= 1
            if depth == 0:
                return line[start:at + 1]
        at += 1
    return line[start:]


for path in sorted((root / "MSUF_Suite_Options").glob("**/*.lua")):
    rel = path.relative_to(root).as_posix()
    lines = path.read_text(encoding="utf-8").splitlines()
    made = {"entry.label"}
    for line in lines:
        for match in MADE.finditer(line):
            made.add(match.group(1))
    for number, line in enumerate(lines, 1):
        for match in CALL.finditer(line):
            if TRANSLATED.search(Arguments(line, match.end() - 1)) and not any(
                    rel == file and line.strip().startswith(text) for file, text in CREATOR_ALLOWED):
                failures.append("%s:%d a Menu2 creator gets translated text: %s" % (rel, number, line.strip()))
        for name in made:
            at = line.find(name + ":SetText(")
            if at >= 0 and (at == 0 or not (line[at - 1].isalnum() or line[at - 1] in "_.")) \
                    and TRANSLATED.search(Arguments(line, at + len(name) + len(":SetText"))):
                failures.append("%s:%d translated text is looked up again: %s" % (rel, number, line.strip()))

if failures:
    sys.exit("\n".join(failures))
print("Suite locale sites: prints translated, no runtime-built text reaches a translation,"
      " menu text translated once passed")
