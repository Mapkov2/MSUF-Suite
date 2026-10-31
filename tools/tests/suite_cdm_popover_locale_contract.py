"""The per-spell popover's fields (CooldownManagerPopoverFields.lua) keep every
label and help text a whole literal, so the locale extraction finds each one
as its complete key: a help sentence split across source lines would lose
its translation."""
import importlib.util
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("suite_locale_tool", ROOT / "tools/suite_locale_tool.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

source = (ROOT / "MSUF_Suite_Options/Pages/CooldownManagerPopoverFields.lua").read_text(encoding="utf-8")
with tempfile.TemporaryDirectory() as directory:
    addon = Path(directory) / "MSUF_Suite_Options"
    addon.mkdir()
    (addon / "Fields.lua").write_text(source, encoding="utf-8")
    # The popover translates these fields when it paints (P.Tr).
    (addon / "Sink.lua").write_text('''local _, P = ...
for _, field in ipairs(P.CDMPage.FIELDS) do P.Tr(field.label); P.Tr(field.auraLabel); P.Tr(field.help) end
for _, section in ipairs(P.CDMPage.POPOVER_SECTIONS) do P.Tr(section.label) end
''', encoding="utf-8")
    extractor = tool.Extractor(Path(directory)).run()
keys = set(extractor.found)

literals = set(re.findall(r'\b(?:label|auraLabel|help)\s*=\s*"((?:[^"\\]|\\.)*)"', source))
literals |= set(re.findall(r'local \w+_HELP\s*=\s*"((?:[^"\\]|\\.)*)"', source, re.S))
literals = {text.replace('\\"', '"') for text in literals}
assert len(literals) > 50, "the field table moved: %d literals" % len(literals)
# The long help sentences, whole (they are longer than a source line).
literals |= {
    "Fade the charge spell while at least one charge is usable. Its space stays reserved; "
    "the native cooldown controls the opacity without exposing charge counts.",
    "Enter a spell name or ID on MSUF action bars. Its buttons glow from the aura and unit selected below. "
    "A page change in combat pauses the glow until combat ends.",
    "Enter a talent or spell name or ID, then press Enter. The entry is hidden while any excluded spell "
    "is learned. Conditions update outside combat.",
}
missing = sorted(literals - keys)
assert not missing, "popover fields lost their locale keys: " + repr(missing)
assert not extractor.dynamic, "popover fields build text the locale cannot translate: " + repr(extractor.dynamic)
print("PASS popover locale: %d field and section literals are whole locale keys" % len(literals))
