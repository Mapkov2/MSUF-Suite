"""Chat prints and composed menu texts reach the reader translated.

* Every Print of the Suite core and addons passes translated text: a string
  literal as its first argument stays English (a slash command is a name).
* Text the locale tool sees built at runtime and handed to a translation
  sink (`suite_locale_tool.py dynamic`) cannot translate. Only the entries
  below may do that: catalog enableKey fields hold setting keys, and the chat
  preview joins texts that are each translated (a chat line has no grammar).
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

if failures:
    sys.exit("\n".join(failures))
print("Suite locale sites: prints translated, no runtime-built text reaches a translation passed")
