"""Gate the Suite surface against a tracked, history-independent snapshot.

Default: check tools/suite_inventory_baseline.json and its reviewed allowlist.
--diff lists all removals/additions. --freeze REV writes a new snapshot from git.
--verify-baseline re-extracts its commit when available (otherwise reports SKIP).
The legacy BEFORE_ROOT [AFTER_ROOT] --client both comparison is also supported.
See suite_inventory.md for extraction boundaries and evidence requirements.
"""

import argparse
from contextlib import contextmanager
from datetime import date
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile

from suite_inventory_source import source_inventory
import suite_locale_tool as locale

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
BASELINE = HERE / "suite_inventory_baseline.json"
ALLOWLIST = HERE / "suite_inventory_allowlist.json"
VERSION = 1
CATEGORIES = ("modules", "module_metadata", "rules", "defaults", "choices", "labels", "sections",
              "rule_metadata", "slash", "bindings", "locale", "movers", "saved_variables", "exports")
CLIENTS = ("retail", "forever")
LUA = r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe"


def item(*parts):
    return json.dumps(parts, ensure_ascii=False, separators=(",", ":"))


def catalog(root, client):
    run = subprocess.run([os.environ.get("MSUF_LUA51", LUA), str(HERE / "suite_inventory_catalog.lua"),
                          str(root), client], capture_output=True, timeout=30)
    if run.returncode or run.stderr:
        raise ValueError("catalog extraction failed: " + run.stderr.decode("utf-8", "replace").strip())
    rows = [json.loads(line) for line in run.stdout.decode("utf-8").splitlines()]
    if not rows or not any(row[0] == "rules" for row in rows):
        raise ValueError("catalog extraction returned no rules")
    return rows


def extract(root, clients=CLIENTS):
    inventory = {name: set() for name in CATEGORIES}
    constants = {}
    for client in clients:
        for category, *parts in catalog(root, client):
            if category == "constants":
                constants[parts[0]] = parts[1]
            else:
                inventory[category].add(item(*parts))
    source_inventory(root, inventory, constants)
    # Same English keys as `suite_locale_tool.py extract`, without translation
    # coverage, which would unnecessarily read sibling checkouts.
    english = set(locale.Extractor(root).run().found)
    english.update(text for text, _ in locale.skin_strings(root) if locale.is_translatable(text))
    inventory["locale"].update(english)
    return inventory


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True)


@contextmanager
def revision_tree(root, revision):
    """Extract only regular addon sources to a private temporary directory."""
    run = git(root, "archive", "--format=tar", revision)
    if run.returncode:
        raise ValueError("cannot archive revision " + revision)
    with tempfile.TemporaryDirectory(prefix="suite-inventory-") as folder:
        destination = Path(folder)
        with tarfile.open(fileobj=io.BytesIO(run.stdout)) as archive:
            for member in archive:
                path = Path(member.name)
                if (not member.isfile() or path.is_absolute() or ".." in path.parts
                        or not path.parts[0].startswith("MSUF_Suite")
                        or path.suffix not in (".lua", ".toc", ".xml") or "Libs" in path.parts):
                    continue
                target = destination / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())
        yield destination


def snapshot(root, revision):
    commit = git(root, "rev-parse", "--verify", revision + "^{commit}")
    if commit.returncode:
        raise ValueError("unknown baseline revision " + revision)
    resolved = commit.stdout.decode().strip()
    with revision_tree(root, resolved) as tree:
        inventory = extract(tree)
    return {"version": VERSION, "revision": resolved,
            "items": {key: sorted(inventory[key]) for key in CATEGORIES}}


def read_snapshot(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("version") != VERSION or not re.fullmatch(r"[0-9a-f]{40}", data.get("revision", "")):
        raise ValueError("invalid baseline metadata")
    if set(data.get("items", {})) != set(CATEGORIES):
        raise ValueError("baseline categories are incomplete")
    for name, values in data["items"].items():
        if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
            raise ValueError("invalid baseline category " + name)
        if not values or values != sorted(set(values)):
            raise ValueError("empty, duplicated or unsorted baseline category " + name)
    return data


def compare(before, after, allowlist):
    removed = {name: set(before[name]) - set(after[name]) for name in CATEGORIES}
    added = {name: set(after[name]) - set(before[name]) for name in CATEGORIES}
    covered = {name: set() for name in CATEGORIES}
    problems = []
    if not isinstance(allowlist, dict) or not isinstance(allowlist.get("removed"), list):
        return removed, added, covered, ["invalid allowlist: expected removed array"]
    for index, entry in enumerate(allowlist["removed"], 1):
        label = "allowlist entry %d" % index
        if not isinstance(entry, dict):
            problems.append(label + " is not an object")
            continue
        category, pattern = entry.get("category"), entry.get("item")
        valid = category in CATEGORIES and isinstance(pattern, str) and bool(pattern.strip())
        valid = valid and entry.get("basis") in ("migration", "owner", "dead", "moved")
        valid = valid and all(isinstance(entry.get(k), str) and entry[k].strip()
                              for k in ("evidence", "reason", "date"))
        try:
            valid = valid and date.fromisoformat(entry["date"]).isoformat() == entry["date"]
        except (KeyError, ValueError, TypeError):
            valid = False
        if not valid:
            problems.append(label + " has invalid category, item, basis, evidence, reason or date")
            continue
        # Literal items include JSON brackets; only '*' is a wildcard.
        expression = "^" + re.escape(pattern).replace(r"\*", ".*") + "$"
        matches = {value for value in removed[category] if re.fullmatch(expression, value, re.S)}
        if not matches:
            problems.append(label + " is stale: " + category + " " + pattern)
        covered[category].update(matches)
    for name in CATEGORIES:
        problems.extend("unapproved removal: " + name + " " + value for value in sorted(removed[name] - covered[name]))
    return removed, added, covered, problems


def count(inventory):
    return sum(map(len, inventory.values()))


def check(before, after, allowlist, revision, verbose=False):
    removed, added, covered, problems = compare(before, after, allowlist)
    if verbose:
        for category in CATEGORIES:
            for value in sorted(removed[category]):
                print("- %s %s [%s]" % (category, value, "allowed" if value in covered[category] else "OPEN"))
            for value in sorted(added[category]):
                print("+ %s %s" % (category, value))
    for problem in problems:
        print("FAIL " + problem)
    print("feature inventory (baseline %s, %d items): %d removed (%d allowlisted, %d open), "
          "%d added, %d problems" % (revision[:7], count(before), count(removed), count(covered),
                                     count(removed) - count(covered), count(added), len(problems)))
    return 1 if problems else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", nargs="?", type=Path)
    parser.add_argument("after", nargs="?", type=Path)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--baseline", type=Path, default=BASELINE)
    parser.add_argument("--allowlist", type=Path, default=ALLOWLIST)
    parser.add_argument("--client", choices=(*CLIENTS, "both"), default="both")
    parser.add_argument("--diff", action="store_true")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--freeze", metavar="REV")
    modes.add_argument("--verify-baseline", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.freeze:
            data = snapshot(args.root, args.freeze)
            args.baseline.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                                     encoding="utf-8", newline="\n")
            print("frozen baseline %s: %d items" % (data["revision"], count(data["items"])))
            return 0
        if args.before:
            if args.verify_baseline:
                raise ValueError("--verify-baseline requires the frozen snapshot")
            clients = CLIENTS if args.client == "both" else (args.client,)
            before, revision = extract(args.before, clients), "checkout"
            after = extract(args.after or args.root, clients)
            return check(before, after, {"removed": []}, revision, True)
        data = read_snapshot(args.baseline)
        if args.verify_baseline:
            if git(args.root, "cat-file", "-e", data["revision"] + "^{commit}").returncode:
                print("SKIP baseline verification: commit unavailable; frozen gate still works")
                return 0
            if snapshot(args.root, data["revision"]) != data:
                raise ValueError("frozen baseline differs from its commit")
            print("verified frozen baseline " + data["revision"])
            return 0
        if args.client != "both":
            raise ValueError("the frozen gate always checks both clients")
        allowlist = json.loads(args.allowlist.read_text(encoding="utf-8"))
        return check(data["items"], extract(args.root), allowlist, data["revision"], args.diff)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("FAIL feature inventory: " + str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
