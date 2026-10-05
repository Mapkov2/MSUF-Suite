"""Checks of tools/suite_locale_tool.py verify that reading the files alone
cannot show: strict UTF-8, a key listed twice (the runtime keeps the first
translation), lone % signs in format strings, pipes the client reads as an
escape (|h ends a link, |r resets color; || shows a pipe) and a dropped
trailing space that joins the next text.

Usage: python tools/tests/suite_locale_tool_checks_contract.py [repo root]
"""

import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("suite_locale_tool", ROOT / "tools" / "suite_locale_tool.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def problems(locale, english, text):
    return " | ".join(tool.check_entry(locale, english, text))


# A trailing space joins the following text; full-width CJK punctuation needs none.
check(problems("deDE", "Loot: ", "Beute: ") == "", "a correct translation with its trailing space was flagged")
check("ends with a space" in problems("deDE", "Loot: ", "Beute:"), "a dropped trailing space was not flagged")
check("ends with a space" not in problems("zhCN", "Loot: ", "拾取："), "a full-width colon needs no space")
# A lone % breaks string.format only in a format string.
check("lone %" in problems("deDE", "%d%% done", "%d%, fertig"), "a lone % in a format string was not flagged")
check("lone %" not in problems("ruRU", "Opacity (percent)", "Непрозрачность (%)"), "a plain label may show a %")
check(tool.specifiers("Hide % sign") == [], "plain percent prose was treated as a format")
check(tool.specifiers("At 100% health") == [], "plain health percent was treated as a format")
check(tool.specifiers("% s") == ["% s"], "a space flag on a real format was lost")
check(tool.specifiers("%.1f%% of pull") == ["%.1f", "%%"], "a doubled percent was mistaken for prose")
check(tool.specifiers("%s: %d%%") == ["%s", "%d", "%%"], "real formats were lost")
# Pipes the client reads as an escape.
check("pipes differ" in problems("deDE", "Usage: /mark tank||healer", "Verwendung: /mark tank|healer"),
      "a translation that unescaped a pipe was not flagged")
check("pipes differ" not in problems("deDE", "Usage: /mark tank||healer", "Verwendung: /mark tank||healer"),
      "an escaped pipe was flagged")
check(tool.english_problems("Usage: /mark tank|healer"), "|h without a link was not flagged in English")
check(tool.english_problems("/keys [self|raid]"), "|r without a color was not flagged in English")
check(not tool.english_problems("|cff00ff00Ready|r and a|b, Primary | secondary, Vertical bar |"),
      "complete escapes or displayed pipes were flagged")
check(not tool.english_problems("%d%% done"), "a format string with %% was flagged")

# File-level checks run against a temporary locale folder.
with tempfile.TemporaryDirectory() as folder:
    saved = tool.LOCALE_DIR, tool.LOCALES
    tool.LOCALE_DIR, tool.LOCALES = Path(folder), ("deDE",)
    try:
        head = tool.HEADER.format(name=tool.LOCALE_NAMES["deDE"], locale="deDE").encode("utf-8")
        body = 'T("Loot: ", "Beute: ")\nT("Loot: ", "Zweite: ")\nT("Bag", "Tasche \xff")\n'.encode("latin-1")
        (Path(folder) / "deDE.lua").write_bytes(head + body)
        entries = tool.read_locale("deDE")
        check(entries.get("Loot: ") == "Beute: ", "the first entry of a key must win, like the runtime's T()")
        found = " | ".join(tool.verify([], quiet=True))
        check("listed again" in found, "a duplicate key was not reported")
        check("invalid UTF-8" in found, "invalid UTF-8 was not reported")
    finally:
        tool.LOCALE_DIR, tool.LOCALES = saved

# A status a module addon writes into S.states (reloadRequired) reaches
# Suite.StatusText through the core's S.Status, directly or through a
# module constant: the extraction lists it, so verify asks every pack for it.
records, _ = tool.extract(ROOT)
extracted = {record.english for record in records}
for english in ("Reload the UI to restore Blizzard's action bars", "Reload the UI to restore Blizzard's minimap layout"):
    check(english in extracted, "the module status %r is not extracted for translation" % english)

for failure in failures:
    print("FAIL " + failure)
print("suite locale tool checks: %s" % ("ok" if not failures else "%d failures" % len(failures)))
sys.exit(1 if failures else 0)
