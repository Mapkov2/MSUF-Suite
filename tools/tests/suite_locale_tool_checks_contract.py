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


# Long literals must yield the same key as Lua on CRLF worktrees and LF checkouts.
for ending in ("\n", "\r\n", "\r", "\n\r"):
    tokens = tool.lex("[[First" + ending + "Second]]")
    check([token.value for token in tokens if token.kind == "str"] == ["First\nSecond"],
          "long-string newlines differ from Lua 5.1: " + repr(ending))

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

# A catalog's summary ranks settings; help summaries on pages are visible prose.
with tempfile.TemporaryDirectory() as directory:
    tree = Path(directory)
    catalog = tree / "MSUF_Suite/Core/Catalog/Test.lua"
    catalog.parent.mkdir(parents=True)
    catalog.write_text('local _, NS = ...\nNS.Text(data.summary)\nlocal spec = { summary = "width height privateKey" }\n', encoding="utf-8")
    page = tree / "MSUF_Suite_Options/Pages/Test.lua"
    page.parent.mkdir(parents=True)
    page.write_text('local _, P = ...\nP.Tr(help.summary)\nlocal help = { summary = "Visible help summary" }\n', encoding="utf-8")
    catalog.write_text(catalog.read_text(encoding="utf-8") +
        'B.Color("accent", "Visible color label", "ffffff")\n' +
        'B.Texture("fill", "Visible texture label", "")\n' +
        'NS.Text("Complete " .. "literal sentence.")\n' +
        'NS.Text("Dynamic fragment " .. userName)\n', encoding="utf-8")
    renderer = tree / "MSUF_Suite/Core/Renderer.lua"
    renderer.write_text('local function Color(layer, role) return role end\nColor("OVERLAY", "ARTWORK")\n' +
        'local function Font(key, label) NS.Text(key) end\n', encoding="utf-8")
    catalog.write_text(catalog.read_text(encoding="utf-8") +
        'local Font = B.Font\nFont("private" .. suffix, "Visible font label")\n', encoding="utf-8")
    caption = tree / "MSUF_Suite/Core/Catalog/Caption.lua"
    caption.write_text('local function Font(text) NS.Text(text) end\nFont("Visible real font caption")\n', encoding="utf-8")
    extractor = tool.Extractor(tree).run()
    found = extractor.found
    check("Visible color label" in found and "Visible texture label" in found, "catalog color or texture labels disappeared")
    check("Visible font label" in found, "catalog font label disappeared")
    check("Visible real font caption" in found, "a real local Font caption was hidden by a builder exception")
    check(not any(row[2].endswith("Font#0") for row in extractor.dynamic), "catalog font key became translated text")
    check("Complete literal sentence." in found, "static literal concatenation lost the whole translation key")
    check(any(row[-1] == "literal" for row in extractor.dynamic), "dynamic fragment stopped being rejected")
    check("ARTWORK" not in found and "OVERLAY" not in found, "rendering color helpers were treated as catalog labels")
    check("width height privateKey" not in found, "catalog ranking keys were treated as translated prose")
    check("Visible help summary" in found, "authored help summary stopped being translated")

# A private table's named fields cannot borrow the translation shape of
# an unrelated global field. This is the real ProfileVariants UseBase shape:
# a forward function result is projected through a private snapshot wrapper.
with tempfile.TemporaryDirectory() as directory:
    tree = Path(directory)
    source = tree / "MSUF_Suite/Core/FieldOwnership.lua"
    source.parent.mkdir(parents=True)
    source.write_text("""
local _, NS = ...
local Project
local function CheckedValue(value) return value end
local function UseBase(modules)
    local snapshot
    if enabled then
        local projected = Project(modules)
        snapshot = { projectedValues = projected }
    else
        snapshot = NS.UnknownSnapshot()
        if not snapshot then return end
    end
    for _, value in pairs(snapshot.projectedValues) do Consume(value) end
end
Project = function(source)
    local result = {}
    for key, value in pairs(source) do result[key] = CheckedValue(value) end
    return result
end
CheckedValue("Private enum payload")
CheckedValue("Private setting key")
UseBase(storedModules)
for _, label in pairs(NS.visible.projectedValues) do NS.Text(label) end
NS.visible = { projectedValues = { "Visible global list label" } }

local record = { caption = "Visible local record label" }
NS.Text(record.caption)
local function Render(row) NS.Text(row.caption) end
Render({ caption = "Visible parameter record label" })
NS.Text(NS.unknown.caption)
NS.caption = "Visible opaque namespace label"
local returned = { caption = "Visible returned record label" }
local function Get() return returned end
NS.Text(Get().caption)
local exported = { caption = "Visible exported record label" }
NS.exported = exported
local passed = { caption = "Visible passed record label" }
Render(passed)
local aliased = { caption = "Visible alias record label" }
local alias = aliased
NS.Text(alias.caption)
local captured = { caption = "Visible closure record label" }
local function Callback() NS.Text(captured.caption) end
Callback()
NS.Render = function(text) NS.Text(text) end
NS.Render("Visible global callback label")
local mixed = {}
mixed = NS.GetRow()
NS.Text(mixed.opaqueCaption)
NS.opaqueCaption = "Visible opaque reassignment label"
local function RenderChild(row) NS.Text(row.childCaption) end
local nested = { items = { childCaption = "Visible escaped subtable label" } }
RenderChild(nested.items)
local written = {}
written.items = { childCaption = "Visible assigned subtable label" }
RenderChild(written.items)
""", encoding="utf-8")
    extractor = tool.Extractor(tree).run()
    for label in ("Visible global list label", "Visible local record label", "Visible parameter record label",
                  "Visible opaque namespace label", "Visible returned record label", "Visible exported record label",
                  "Visible passed record label", "Visible alias record label", "Visible closure record label",
                  "Visible global callback label", "Visible opaque reassignment label",
                  "Visible escaped subtable label", "Visible assigned subtable label"):
        check(label in extractor.found, "field ownership lost " + label)
    for value in ("Private enum payload", "Private setting key"):
        check(value not in extractor.found, "an unrelated global field tainted " + value)

# File-level checks run against a temporary locale folder.
with tempfile.TemporaryDirectory() as folder:
    saved = tool.LOCALE_DIR, tool.LOCALES
    tool.LOCALE_DIR, tool.LOCALES = Path(folder), ("deDE",)
    try:
        head = tool.HEADER.format(name=tool.LOCALE_NAMES["deDE"], locale="deDE").encode("utf-8")
        body = 'T("Loot: ", "Beute: ")\nT("Loot: ", "Zweite: ")\nT("Bag", "Tasche \xff")\n'.encode("latin-1")
        (Path(folder) / "deDE.lua").write_bytes(head + body)
        for ending in (b"\n", b"\r\n"):
            (Path(folder) / "deDE.lua").write_bytes(head.replace(b"\n", ending))
            found = " | ".join(tool.verify([], quiet=True))
            check("the header" not in found, "a correct LF/CRLF locale header was rejected")
        (Path(folder) / "deDE.lua").write_bytes(head.replace(b"MSUF Suite", b"Broken namespace", 1))
        found = " | ".join(tool.verify([], quiet=True))
        check("the header" in found, "a changed namespace header was accepted")
        (Path(folder) / "deDE.lua").write_bytes(head + body)
        entries = tool.read_locale("deDE")
        check(entries.get("Loot: ") == "Beute: ", "the first entry of a key must win, like the runtime's T()")
        found = " | ".join(tool.verify([], quiet=True))
        check("listed again" in found, "a duplicate key was not reported")
        check("invalid UTF-8" in found, "invalid UTF-8 was not reported")
        for newline in (b"\n", b"\r\n"):
            canonical = head.replace(b"\n", newline)
            (Path(folder) / "deDE.lua").write_bytes(canonical)
            check(not tool.verify([], quiet=True), "canonical LF/CRLF header rejected")
            changed = canonical.replace(b"_G.MSUF_NS", b"_G.OTHER_NS", 1)
            (Path(folder) / "deDE.lua").write_bytes(changed)
            found = " | ".join(tool.verify([], quiet=True))
            check("header" in found, "changed namespace accepted after newline normalization")
    finally:
        tool.LOCALE_DIR, tool.LOCALES = saved

# A status a module addon writes into S.states (reloadRequired) reaches
# Suite.StatusText through the core's S.Status, directly or through a
# module constant: the extraction lists it, so verify asks every pack for it.
records, _ = tool.extract(ROOT)
extracted = {record.english for record in records}
for english in ("Reload the UI to restore Blizzard's action bars", "Reload the UI to restore Blizzard's minimap layout"):
    check(english in extracted, "the module status %r is not extracted for translation" % english)

# A squircle is a rounded square; prior packs called it a squirrel or a circle.
shape_labels = {"deDE": "Abgerundetes Quadrat", "esES": "Cuadrado redondeado",
                "esMX": "Cuadrado redondeado", "frFR": "Carré arrondi",
                "itIT": "Quadrato arrotondato", "ptBR": "Quadrado arredondado"}
for locale, label in shape_labels.items():
    entries = tool.read_locale(locale)
    for key in ("Squircle", "Squircle n=6", "Squircle  n=6"):
        suffix = " n=6" if "n=6" in key else ""
        check(" ".join(entries[key].split()) == label + suffix,
              "%s: %s is not the translated rounded-square shape" % (locale, key))
# The retired skin-only Preset key has no current Suite reader; it must not
# linger as an orphan overriding a host-owned label.
check("Preset" not in tool.read_locale("deDE"), "retired skin preset key remained in the Suite pack")

# Localized native features must not leave their English names inside translated help.
native_terms = ("Burning Rush", "Great Vault", "Raid Manager")
for locale in tool.LOCALES:
    for english, text in tool.read_locale(locale).items():
        for term in native_terms:
            if term in english:
                check(term not in text, "%s leaves %s inside translated text: %s" % (locale, term, english))

for failure in failures:
    print("FAIL " + failure)
print("suite locale tool checks: %s" % ("ok" if not failures else "%d failures" % len(failures)))
sys.exit(1 if failures else 0)
