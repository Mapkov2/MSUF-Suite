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


def fixture(root):
    addon = root / "MSUF_Suite"
    write(addon / "MSUF_Suite_Mainline.toc", "## SavedVariables: MSUFSuiteDB\n"
          "Core\\SuiteCatalog.lua\nCore\\Suite.lua\n")
    write(addon / "Core/SuiteCatalog.lua", '''local _, ns = ...
ns.ActionBarCount, ns.DataTextBarLimit, ns.DamageMeterMaxWindows = 2, 3, 2
ns.CDM = { SLOTS = { { key = "ess" }, { key = "c1" } } }
ns.SuiteOrder = { "test" }
ns.SuiteCatalog = { test = { title = "Test module", page = "suite_test", addon = "MSUF_Suite",
    controls = { { key = "setting", default = false, label = "Setting", choices = { "One", "Two" },
        section = "general", sectionTitle = "General", min = 1, max = 2, step = 1 } } } }
ns.FinalizeCatalog = function() end
_G.BINDING_NAME_TEST = "Test binding"
''')
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

    def test_synthetic_extraction_and_no_git_gate(self):
        with tempfile.TemporaryDirectory(prefix="suite-inventory-test-") as tmp:
            root = fixture(Path(tmp))
            found = inventory.extract(root)
            self.assertIn(inventory.item("retail:test.setting", "boolean", False), found["defaults"])
            self.assertIn(inventory.item("forever:test.setting", 2, "Two"), found["choices"])
            self.assertIn(inventory.item("retail:test.setting", "general", "General"), found["sections"])
            self.assertIn(inventory.item("retail:test.setting", "Setting"), found["labels"])
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
    ("success status", "suite_inventory_diff.py", "return 1 if problems else 0", "return 0"),
    ("tampered snapshot", "suite_inventory_diff.py", 'snapshot(args.root, data["revision"]) != data', "False"),
    ("lost defaults", "suite_inventory_catalog.lua", 'emit("defaults", key, type(rule.default), rule.default)', ""),
    ("lost choices", "suite_inventory_catalog.lua", 'emit("choices", key, index, choice)', ""),
    ("lost sections", "suite_inventory_catalog.lua", 'emit("sections", key, rule.section, rule.sectionTitle or "")', ""),
    ("lost labels", "suite_inventory_catalog.lua", 'emit("labels", key, rule.label or "")', ""),
    ("lost aliases", "suite_inventory_source.py", "inventory.add(command)", "pass"),
    ("lost exports", "suite_inventory_source.py", 'inventory.add("S." + name)', "pass"),
    ("lost saved keys", "suite_inventory_source.py", 'inventory.add(owner + "." + key)', "pass"),
    ("lost locales", "suite_inventory_diff.py", 'inventory["locale"].update(english)', "pass"),
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
            run = subprocess.run([sys.executable, "-B", str(test)], capture_output=True)
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
        unittest.main(argv=[sys.argv[0]], verbosity=1)
