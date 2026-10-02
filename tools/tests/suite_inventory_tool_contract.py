"""Synthetic inventory contracts; --mutations checks the guards themselves."""

import contextlib
import copy
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import suite_inventory_diff as inventory
import suite_inventory_source as source
import run_suite_tests as runner
from suite_locale_tool import lex


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def tokens(text):
    return [token for token in lex(text) if token.value is not None]


MODULE = '''{ title = "Test module", page = "suite_test", addon = "MSUF_Suite",
    defaultEnabled = true, conflicts = { "OtherAddon" }, cvars = { testCvar = 1 }, editElement = "main",
    look = { key = "look", global = true, presets = { { accent = "ff0000" }, { accent = "00ff00" } },
        extra = function() end },
    controls = { { key = "setting", default = false, label = "Setting", choices = { "One", "Two" },
        section = "general", sectionTitle = "General", min = 1, max = 2, step = 1,
        enableKey = "enabled", requiresChoice = { key = "mode", values = { [2] = true } } } } }'''


def fixture(root, modules=("test",)):
    addon = root / "MSUF_Suite"
    write(addon / "MSUF_Suite_Mainline.toc", "## SavedVariables: MSUFSuiteDB\n"
          "Core\\SuiteCatalog.lua\nCore\\Suite.lua\n")
    write(addon / "Core/SuiteCatalog.lua", '''local _, ns = ...
ns.ActionBarCount, ns.DataTextBarLimit, ns.DamageMeterMaxWindows = 2, 3, 2
ns.CDM = { SLOTS = { { key = "ess" }, { key = "c1" } } }
ns.SuiteOrder = { %s }
ns.SuiteCatalog = { %s }
ns.FinalizeCatalog = function() end
_G.BINDING_NAME_TEST = "Test binding"
''' % (", ".join('"%s"' % name for name in modules), ", ".join("%s = %s" % (name, MODULE) for name in modules)))
    write(addon / "Core/Suite.lua", '''local S = { states = {} }
function S.Keep() end
S.Assigned = function() end
local root = NS.RootDB
root.savedKey = true
SLASH_TEST1 = "/primary"
local COMMAND, ALIAS = "TEST", "/alias"
S.RegisterSlash(COMMAND, handler, "/long", ALIAS)
S.RegisterOwnedMover("test", "main", {})
S.Text("Visible text")
''')
    write(addon / "Bindings.xml", '<Bindings><Binding name="TEST"/></Bindings>\n')
    return root


class InventoryContract(unittest.TestCase):
    def setUp(self):
        self.before = {name: {name + " keep"} for name in inventory.CATEGORIES}
        self.after = copy.deepcopy(self.before)
        self.entry = {"category": "rules", "item": "rules keep", "basis": "moved",
                      "evidence": "abc123 replacement at same setting path", "reason": "Renamed", "date": "2026-10-02"}

    def result(self, entries=()):
        return inventory.compare(self.before, self.after, {"removed": list(entries)})

    def test_every_category_removal_fails(self):
        for category in inventory.CATEGORIES:
            with self.subTest(category=category):
                self.after = copy.deepcopy(self.before)
                self.after[category].clear()
                self.assertEqual(len(self.result()[3]), 1)

    def test_allowlisted_removal_passes(self):
        self.after["rules"].clear()
        removed, _, covered, problems = self.result([self.entry])
        self.assertEqual(problems, [])
        self.assertEqual(removed, covered)

    def test_addition_passes(self):
        self.after["rules"].add("new setting")
        removed, added, _, problems = self.result()
        self.assertEqual(problems, [])
        self.assertEqual(inventory.count(removed), 0)
        self.assertEqual(added["rules"], {"new setting"})

    def test_stale_allowlist_fails(self):
        self.assertTrue(any("stale" in p for p in self.result([self.entry])[3]))

    def test_each_entry_must_match(self):
        self.after["rules"].clear()
        stale = dict(self.entry, item="no longer removed")
        self.assertEqual(len(self.result([self.entry, stale])[3]), 1)

    def test_allowlist_metadata_required(self):
        self.after["rules"].clear()
        for key in ("category", "item", "basis", "evidence", "reason", "date"):
            entry = dict(self.entry)
            del entry[key]
            with self.subTest(key=key):
                self.assertTrue(self.result([entry])[3])
        self.assertTrue(self.result([dict(self.entry, date="2026-99-45")])[3])
        self.assertTrue(self.result([dict(self.entry, evidence=" ")])[3])

    def test_wildcard_and_literal_brackets(self):
        value = inventory.item("retail:module.key", "Label")
        self.before["labels"] = {value}
        self.after["labels"].clear()
        entry = dict(self.entry, category="labels", item=value)
        self.assertEqual(self.result([entry])[3], [])
        self.assertEqual(self.result([dict(entry, item='["*:module.key","Label"]')])[3], [])
        self.after["rules"].clear()
        self.assertTrue(self.result([dict(entry, item="*")])[3])

    def test_status_and_single_summary(self):
        self.after["rules"].clear()
        with contextlib.redirect_stdout(io.StringIO()) as output:
            code = inventory.check(self.before, self.after, {"removed": []}, "abc1234")
        self.assertEqual(code, 1)
        self.assertEqual(output.getvalue().count("feature inventory ("), 1)

    def test_static_declarations_ignore_comments_and_reads(self):
        text = '''-- function S.Fake() end
local text = "S.Fake = true"
function S.Real() end
function S:Method() end
S.Alias = other
S["Bracket"] = other
S.First, S.Second = one, two
local called = S.ReadOnly()
S.Cleared = nil
'''
        found = set()
        source.exports(tokens(text), found)
        self.assertEqual(found, {"S.Real", "S.Method", "S.Alias", "S.Bracket", "S.First", "S.Second"})

    def test_unknown_mover_or_alias_fails_closed(self):
        with self.assertRaises(ValueError):
            source.mover_ids(tokens('S.RegisterOwnedMover("test", unknown, {})'), {}, "", "", {}, set())
        with self.assertRaises(ValueError):
            source.slash_commands(tokens('S.RegisterSlash("TEST", handler, unknown)'), {}, set())

    def test_literal_alias_after_numeric_constant(self):
        values = source.literal_bindings(tokens('local COUNT, ID = 2, "test"\nlocal HEX, RATE = 0x10, 0.5'))
        self.assertEqual(values, {"COUNT": 2, "ID": "test", "HEX": 16, "RATE": 0.5})
        found = set()
        source.mover_ids(tokens('S.RegisterOwnedMover(ID, "main", {})'), values, "", "", {}, found)
        self.assertEqual(found, {"MSUFSuite.test:main"})

    def test_dynamic_mover_limits(self):
        found = set()
        text = 'for i = 1, 2 do S.RegisterOwnedMover("test", "bar" .. i, {}) end'
        source.mover_ids(tokens(text), {}, text, "", {}, found)
        self.assertEqual(found, {"MSUFSuite.test:bar1", "MSUFSuite.test:bar2"})
        text = 'for i = 1, 1 do S.RegisterOwnedMover("test", "bar" .. i, {}) end'
        smaller = set()
        source.mover_ids(tokens(text), {}, text, "", {}, smaller)
        self.assertEqual(found - smaller, {"MSUFSuite.test:bar2"})

    def test_saved_alias_does_not_capture_namespace(self):
        text = ('local root = NS.RootDB\nroot.keep = true\nNS.RuntimeOnly = true\n_G.MSUFSuiteDB = root\n'
                'local record = root and root.keep\nrecord.child = true\n'
                'local ROOT_KEY = "characters"\nTable(root, ROOT_KEY)\nroot = {seed = true}')
        code = "\n".join(source.render(tokens(line)) for line in text.splitlines())
        found = set()
        source.saved_keys(code, tokens(text), Path("MSUF_Suite/Core/Example.lua"), found)
        self.assertEqual(found, {"MSUFSuiteDB.keep", "MSUFSuiteDB.characters", "MSUFSuiteDB.seed"})

    def test_dynamic_catalog_mover_families(self):
        constants = {"CDMSlots": ["ess", "c1"], "DataTextBarLimit": 3}
        cases = (
            ('S.RegisterOwnedMover("cdm", SLOTS[i].key, {})', 'for i = 1, #SLOTS do ', '',
             {"MSUFSuite.cdm:ess", "MSUFSuite.cdm:c1"}),
            ('S.RegisterOwnedMover("dataTexts", "bar" .. i, {})', 'for _, i in ipairs(self.barIDs) do ', '',
             {"MSUFSuite.dataTexts:bar1", "MSUFSuite.dataTexts:bar2", "MSUFSuite.dataTexts:bar3"}),
            ('S.RegisterOwnedMover("meter", list[i].elementID, {})', 'for i = 1, D.MAX do ',
             'MAX = 2 elementID = "window" .. i', {"MSUFSuite.meter:window1", "MSUFSuite.meter:window2"}),
        )
        for call, loop, declarations, expected in cases:
            text = loop + call + " end"
            code = source.render(tokens(declarations))
            found = set()
            source.mover_ids(tokens(text), {}, code, code, constants, found)
            self.assertEqual(found, expected)

    def source_pass(self, root):
        found = {name: set() for name in inventory.CATEGORIES}
        source.source_inventory(root, found, {})
        return found

    def test_comments_strings_and_xml_comments_declare_nothing(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
            root = Path(tmp)
            addon = root / "MSUF_Suite"
            write(addon / "Core/Comments.lua", '''-- SLASH_GONE1 = "/gone"
--[[ S.RegisterSlash("GONE", handler, "/gone2")
function S.Gone() end ]]
--[==[ S.RegisterOwnedMover("test", "gonemover", {}) ]==]
local text = "function S.StringGone() end SLASH_STR1 = '/str'"
local long = [[ root.longStringKey = 1
S.LongString = true ]]
local root = NS.RootDB
-- root.ghostKey = true
function S.Live() end
SLASH_LIVE1 = "/live"
root.liveKey = true
S.RegisterOwnedMover("test", "live", {})
''')
            write(addon / "Bindings.xml", '<Bindings><!-- <Binding name="GONE"/> --><Binding name="LIVE"/></Bindings>')
            write(addon / "MSUF_Suite_Mainline.toc", "## SavedVariables: LiveDB\n# ## SavedVariables: GoneDB\n"
                  "## Notes: x\n## SavedVariablesPerCharacter: CharDB\n")
            found = self.source_pass(root)
        self.assertEqual(found["exports"], {"S.Live"})
        self.assertEqual(found["slash"], {"/live"})
        self.assertEqual(found["movers"], {"MSUFSuite.test:live"})
        self.assertEqual(found["bindings"], {"LIVE"})
        self.assertEqual(found["saved_variables"], {"MSUFSuiteDB.liveKey", "SavedVariables:LiveDB",
                                                    "SavedVariablesPerCharacter:CharDB"})

    def test_generated_file_headers_are_not_exempt(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
            root = Path(tmp)
            for header in ("-- Generated by tools/example.py. Do not edit.", "-- Auto-generated", "-- @generated"):
                name = "Gen%d" % abs(hash(header) % 1000)
                write(root / "MSUF_Suite/Core" / (name + ".lua"), header + "\nfunction S.From%s() end\n" % name)
            found = self.source_pass(root)
        self.assertEqual(len(found["exports"]), 3)

    def catalog_items(self, root):
        found = {name: set() for name in inventory.CATEGORIES}
        for client in inventory.CLIENTS:
            for category, *parts in inventory.catalog(root, client):
                if category != "constants":
                    found[category].add(inventory.item(*parts))
        return found

    def test_labels_keep_their_owner(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
            root = fixture(Path(tmp), ("test", "twin"))
            both = self.catalog_items(root)
            fixture(root, ("test",))
            only = self.catalog_items(root)
        twin, kept = inventory.item("retail:twin.setting", "Setting"), inventory.item("retail:test.setting", "Setting")
        self.assertEqual({twin, kept} - both["labels"], set())
        removed, _, _, problems = inventory.compare(both, only, {"removed": []})
        self.assertIn(twin, removed["labels"])
        self.assertNotIn(kept, removed["labels"])
        self.assertTrue(problems)

    def test_catalog_link_removals_fail(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
            root = fixture(Path(tmp))
            path = root / "MSUF_Suite/Core/SuiteCatalog.lua"
            text = path.read_text()
            before = self.catalog_items(root)
            for label, old, new, category in (
                    ("enable link", 'enableKey = "enabled"', "unused = 1", "rule_traits"),
                    ("visibility link", "values = { [2] = true }", "values = { [3] = true }", "rule_traits"),
                    ("module default", "defaultEnabled = true", "defaultEnabled = false", "module_traits"),
                    ("conflict list", 'conflicts = { "OtherAddon" }', "conflicts = {}", "module_traits"),
                    ("cvars", "cvars = { testCvar = 1 }", "unused = 1", "module_traits"),
                    ("edit element", 'editElement = "main"', "unused = 1", "module_traits"),
                    ("look preset", '{ accent = "00ff00" }', "{}", "module_traits")):
                with self.subTest(label=label):
                    self.assertIn(old, text)
                    write(path, text.replace(old, new))
                    removed = inventory.compare(before, self.catalog_items(root), {"removed": []})[0]
                    self.assertTrue(removed[category], label)
            write(path, text)

    def test_blanket_wildcards_are_not_exceptions(self):
        self.after["rules"].clear()
        for pattern in ("*", "**", " * "):
            with self.subTest(pattern=pattern):
                self.assertTrue(any("invalid" in p for p in self.result([dict(self.entry, item=pattern)])[3]))
        self.assertEqual(self.result([dict(self.entry, item="rules *")])[3], [])

    def test_freeze_never_hides_a_loss(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
            root = fixture(Path(tmp))
            found = inventory.extract(root)
            baseline, allowed = root / "baseline.json", root / "allowed.json"
            write(allowed, '{"removed": []}')
            args = ["--root", str(root), "--baseline", str(baseline), "--allowlist", str(allowed)]
            lossy = {k: set(v) for k, v in found.items()}
            lossy["exports"].add("S.Lost")
            for label, items, flags, status, written in (("refused", lossy, [], 1, False),
                                                         ("accepted", lossy, ["--accept-problems"], 1, True),
                                                         ("clean", found, [], 0, True)):
                data = {"version": inventory.VERSION, "revision": "b" * 40,
                        "items": {k: sorted(v) for k, v in items.items()}}
                with self.subTest(label):
                    if baseline.exists():
                        baseline.unlink()
                    with patch.object(inventory, "snapshot", return_value=data):
                        with contextlib.redirect_stdout(io.StringIO()) as output:
                            code = inventory.main(["--freeze", "b" * 40] + flags + args)
                    self.assertEqual(code, status, output.getvalue())
                    self.assertEqual(baseline.exists(), written, output.getvalue())
                    if status:
                        self.assertIn("unapproved removal: exports S.Lost", output.getvalue())
            frozen = baseline.read_text()
            self.assertEqual(json.loads(frozen)["revision"], "b" * 40)
            self.assertNotIn(chr(13), frozen)

    def test_extraction_errors_fail_closed(self):
        for name, text in (("Core/Broken.lua", 'local text = "unfinished\n'), ("Bindings.xml", "<Bindings><Binding")):
            with self.subTest(name=name), tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
                root = fixture(Path(tmp))
                found = inventory.extract(root)
                baseline, allowed = root / "baseline.json", root / "allowed.json"
                write(baseline, json.dumps({"version": inventory.VERSION, "revision": "a" * 40,
                                            "items": {k: sorted(v) for k, v in found.items()}}))
                write(allowed, '{"removed": []}')
                write(root / "MSUF_Suite" / name, text)
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    code = inventory.main(["--root", str(root), "--baseline", str(baseline),
                                           "--allowlist", str(allowed)])
                self.assertEqual(code, 1)
                self.assertIn("FAIL feature inventory", output.getvalue())

    def test_synthetic_extraction_and_no_git_gate(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
            root = fixture(Path(tmp))
            found = inventory.extract(root)
            self.assertEqual(found, inventory.extract(root), "extraction must be deterministic")
            self.assertIn(inventory.item("retail:test.setting", "boolean", False), found["defaults"])
            self.assertIn(inventory.item("forever:test.setting", 2, "Two"), found["choices"])
            self.assertIn(inventory.item("retail:test.setting", "general", "General"), found["sections"])
            self.assertIn(inventory.item("retail:test.setting", "Setting"), found["labels"])
            self.assertIn(inventory.item("retail:test.setting", "enableKey", "enabled"), found["rule_traits"])
            self.assertIn(inventory.item("forever:test.setting", "requiresChoice",
                                         [["key", "mode"], ["values", [[2, True]]]]), found["rule_traits"])
            self.assertIn(inventory.item("retail:test", "defaultEnabled", True), found["module_traits"])
            self.assertIn(inventory.item("retail:test", "conflicts", [[1, "OtherAddon"]]), found["module_traits"])
            self.assertIn(inventory.item("retail:test", "cvars", [["testCvar", 1]]), found["module_traits"])
            self.assertIn(inventory.item("forever:test", "editElement", "main"), found["module_traits"])
            self.assertIn(inventory.item("retail:test", "look.presets.2", [["accent", "00ff00"]]),
                          found["module_traits"])
            self.assertIn(inventory.item("retail:test", "look.extra", "<function>"), found["module_traits"])
            self.assertIn("Visible text", found["locale"])
            self.assertIn("MSUFSuite.test:main", found["movers"])
            self.assertIn("MSUFSuiteDB.savedKey", found["saved_variables"])
            self.assertIn("TEST", found["bindings"])
            self.assertIn(inventory.item("BINDING_NAME_TEST"), found["bindings"])
            self.assertIn("S.Keep", found["exports"])
            self.assertEqual(found["slash"], {"/primary", "/alias", "/long"})
            baseline, allowed = root / "baseline.json", root / "allowed.json"
            data = {"version": inventory.VERSION, "revision": "a" * 40,
                    "items": {k: sorted(v) for k, v in found.items()}}
            write(baseline, json.dumps(data))
            write(allowed, '{"removed": []}')
            args = ["--root", str(root), "--baseline", str(baseline), "--allowlist", str(allowed)]
            with patch.object(inventory, "git", side_effect=AssertionError("gate must not call git")):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(inventory.main(args), 0)
            path = root / "MSUF_Suite/Core/Suite.lua"
            write(path, path.read_text().replace('"/alias"', '"/newalias"'))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(inventory.main(args), 1)
            write(allowed, json.dumps({"removed": [dict(self.entry, category="slash", item="/alias")]}))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(inventory.main(args), 0)
            data["items"]["slash"] = sorted(inventory.extract(root)["slash"])
            write(baseline, json.dumps(data))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(inventory.main(args), 1)

    def test_broken_catalog_fails(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
            root = fixture(Path(tmp))
            write(root / "MSUF_Suite/Core/SuiteCatalog.lua", 'error("broken catalog")')
            with self.assertRaises(ValueError):
                inventory.extract(root)

    def test_verify_detects_tampering_and_skips_missing_commit(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
            root = fixture(Path(tmp))
            found = inventory.extract(root)
            data = {"version": inventory.VERSION, "revision": "a" * 40,
                    "items": {k: sorted(v) for k, v in found.items()}}
            path = root / "baseline.json"
            write(path, json.dumps(data))
            args = ["--verify-baseline", "--baseline", str(path), "--root", str(root)]
            with patch.object(inventory, "git", return_value=subprocess.CompletedProcess([], 1)):
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(inventory.main(args), 0)
                self.assertIn("SKIP", output.getvalue())
            changed = copy.deepcopy(data)
            changed["items"]["exports"].append("S.Tampered")
            with patch.object(inventory, "git", return_value=subprocess.CompletedProcess([], 0)):
                with patch.object(inventory, "snapshot", return_value=changed):
                    with contextlib.redirect_stdout(io.StringIO()):
                        self.assertEqual(inventory.main(args), 1)

    def test_runner_propagates_inventory_status_once(self):
        summary = "feature inventory (synthetic): summary"
        with tempfile.TemporaryDirectory(prefix="suite-inventory-runner-") as tmp:
            root = Path(tmp)
            (root / "tools/tests").mkdir(parents=True)
            for status in (0, 1):
                with self.subTest(status=status), patch.object(runner, "ROOT", root):
                    result = subprocess.CompletedProcess([], status, summary, "")
                    with patch.object(runner.subprocess, "run", return_value=result) as call:
                        with patch.object(sys, "argv", ["run_suite_tests.py"]):
                            with contextlib.redirect_stdout(io.StringIO()) as output:
                                self.assertEqual(runner.main(), status)
                    self.assertEqual(call.call_count, 1)
                    self.assertEqual(Path(call.call_args.args[0][1]).name, "suite_inventory_diff.py")
                    self.assertEqual(output.getvalue().count(summary), 1)
                    self.assertIn("%d passed, %d failed" % (1 - status, status), output.getvalue())

    def test_runner_respects_name_filter(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-runner-") as tmp:
            root = Path(tmp)
            (root / "tools/tests").mkdir(parents=True)
            with patch.object(runner, "ROOT", root), patch.object(runner.subprocess, "run") as call:
                with patch.object(sys, "argv", ["run_suite_tests.py", "unrelated"]):
                    with contextlib.redirect_stdout(io.StringIO()):
                        self.assertEqual(runner.main(), 0)
                call.assert_not_called()


MUTANTS = (
    ("lost removals", "suite_inventory_diff.py", "set(before[name]) - set(after[name])", "set()"),
    ("lost additions", "suite_inventory_diff.py", "set(after[name]) - set(before[name])", "set()"),
    ("ignored exceptions", "suite_inventory_diff.py", "covered[category].update(matches)", "pass"),
    ("stale exceptions", "suite_inventory_diff.py", "if not matches:", "if False:"),
    ("open removals pass", "suite_inventory_diff.py", "removed[name] - covered[name]", "set()"),
    ("blanket wildcard", "suite_inventory_diff.py", 'bool(pattern.replace("*", "").strip())',
     "bool(pattern.strip())"),
    ("success status", "suite_inventory_diff.py", "return 1 if problems else 0", "return 0"),
    ("tampered snapshot", "suite_inventory_diff.py", 'snapshot(args.root, data["revision"]) != data', "False"),
    ("unchecked freeze", "suite_inventory_diff.py", "if status and not args.accept_problems:", "if False:"),
    ("uncaught syntax errors", "suite_inventory_diff.py", "OSError, ValueError, SyntaxError, subprocess",
     "OSError, ValueError, subprocess"),
    ("lost locales", "suite_inventory_diff.py", 'inventory["locale"].update(english.result())', "pass"),
    ("lost defaults", "suite_inventory_catalog.lua", 'emit("defaults", key, type(rule.default), rule.default)', ""),
    ("lost choices", "suite_inventory_catalog.lua", 'emit("choices", key, index, choice)', ""),
    ("lost sections", "suite_inventory_catalog.lua", 'emit("sections", key, rule.section, rule.sectionTitle or "")', ""),
    ("lost labels", "suite_inventory_catalog.lua", 'emit("labels", key, rule.label or "")', ""),
    ("lost rule links", "suite_inventory_catalog.lua", 'emitTraits("rule_traits", key, rule, RULE_TRAITS)', ""),
    ("lost module links", "suite_inventory_catalog.lua",
     'emitTraits("module_traits", client .. ":" .. id, spec, SPEC_TRAITS)', ""),
    ("lost looks", "suite_inventory_catalog.lua", 'emitLook(client .. ":" .. id, spec.look)', ""),
    ("lost slash globals", "suite_inventory_source.py", "inventory.add(tokens[end + 1].value)", "pass"),
    ("lost aliases", "suite_inventory_source.py", "inventory.add(command)", "pass"),
    ("lost exports", "suite_inventory_source.py", 'inventory.add("S." + name)', "pass"),
    ("lost saved keys", "suite_inventory_source.py", 'inventory.add(owner + "." + key)', "pass"),
    ("lost saved roots", "suite_inventory_source.py",
     'inventory["saved_variables"].update(kind + ":" + name.strip() for name in names.split(","))', "pass"),
    ("lost bindings", "suite_inventory_source.py", 'node.attrib["name"] for node in tree.iter()',
     "() for node in []"),
    ("lost movers", "suite_inventory_source.py", 'inventory.update("MSUFSuite." + owner + ":" + name for name in ids)',
     "pass"),
    ("numeric literal prefix", "suite_inventory_source.py", '("str", "num")', '("str", "number")'),
    ("toc comments declare", "suite_inventory_source.py", 'r"^## (SavedVariables', 'r"## (SavedVariables'),
    ("xml comments declare", "suite_inventory_source.py", "tree = ET.fromstring(path.read_bytes())",
     'tree = ET.fromstring(path.read_bytes().replace(b"<!--", b"").replace(b"-->", b""))'),
    ("generated headers exempt", "suite_inventory_source.py",
     'if not SOURCE_CANDIDATE.search(source) and not path.name.startswith("Database"):',
     'if "enerated" in source[:200] or (not SOURCE_CANDIDATE.search(source) and not path.name.startswith("Database")):'),
    ("missing runner gate", "run_suite_tests.py", 'if wanted in "suite_inventory_diff.py":', "if False:"),
)


def mutations():
    survived = []
    with tempfile.TemporaryDirectory(prefix="suite-inventory-mutants-") as tmp:
        tools = Path(tmp) / "tools"
        tools.mkdir()
        names = ("suite_inventory_diff.py", "suite_inventory_source.py", "suite_inventory_catalog.lua",
                 "suite_locale_tool.py", "run_suite_tests.py")
        for name in names:
            shutil.copyfile(TOOLS / name, tools / name)
        test = tools / "tests" / Path(__file__).name
        test.parent.mkdir()
        shutil.copyfile(__file__, test)
        for label, name, old, new in MUTANTS:
            original = (TOOLS / name).read_text(encoding="utf-8")
            if old not in original:
                raise AssertionError("mutation target missing: " + label)
            write(tools / name, original.replace(old, new))
            run = subprocess.run([sys.executable, "-B", str(test), "--failfast"], capture_output=True)
            if run.returncode == 0:
                survived.append(label)
            write(tools / name, original)
    print("inventory mutations: %d/%d killed" % (len(MUTANTS) - len(survived), len(MUTANTS)))
    if survived:
        raise AssertionError("survived: " + ", ".join(survived))


if __name__ == "__main__":
    if "--mutations" in sys.argv:
        mutations()
    else:
        unittest.main(argv=[sys.argv[0]] + [a for a in sys.argv[1:] if a == "--failfast"], verbosity=1)
