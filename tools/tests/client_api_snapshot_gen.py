"""Regenerate client_api_snapshot.json from the Blizzard UI source mirror.

Usage: python tools/tests/client_api_snapshot_gen.py [mirror]

suite_structure_gate.py reads only the snapshot, never the mirror. The
snapshot lists every client API name that exists on some, but not all, of
the clients the Suite TOCs declare, with the clients that have it. Names on
every declared client are left out: the gate only has to know which
references a client lacks.

Judged names come from the generated API documentation (namespaced
functions, global functions, enums, constants), from what FrameXML Lua
defines (functions, globals, table fields, deprecation shims) and from named
XML frames. A client also has a name its own Lua uses: undocumented C
functions appear only there. Other game flavors' files are skipped, because
Retail and WoW Forever load Mainline and shared code only.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

MIRROR = r"C:\MSUF Beta Branch\MidnightSimpleUnitFrames\_local_workflows\references\wow-ui-source"
# TOC interface number -> (client name, mirror ref). The snapshot covers the
# numbers the Suite TOCs declare (read from their ## Interface lines); a new
# number needs its mirror ref here first.
KNOWN_CLIENTS = {
    "120007": ("12.0.7", "12.0.7"),
    "120100": ("12.1.0", "12.1.0"),
    "120105": ("12.1.5", "12.1.5"),
    "16001": ("Forever", "upstream/forever"),
}
ROOT = Path(__file__).resolve().parents[2]
CLIENTS = {}
OUT = Path(__file__).with_name("client_api_snapshot.json")
DOCS = "Interface/AddOns/Blizzard_APIDocumentationGenerated"
FLAVORS = ("Classic", "Mists", "Cata", "Wrath", "Vanilla", "TBC")
NOT_OTHER_FLAVORS = [":!*/%s/*" % f for f in FLAVORS] + [":!*_%s.*" % f for f in FLAVORS]
LUA = ["Interface/*.lua", ":!" + DOCS + "/*"] + NOT_OTHER_FLAVORS
NAME = r"[A-Za-z_][A-Za-z0-9_]*"
USED = r"(?<![\w.:])(?:C_\w+|[A-Z]\w*)(?:\.\w+){0,2}"
# Client API names start with a capital or C_ (Lua's own libraries do not).
API_NAME = re.compile(r"(?:C_|[A-Z])")


def git(mirror, *args):
    run = subprocess.run(["git", "-C", mirror] + list(args), capture_output=True, text=True,
                         encoding="utf-8", errors="replace")
    if run.returncode not in (0, 1):
        sys.exit("git %s failed: %s" % (args[0], run.stderr.strip()))
    return run.stdout


def grep(mirror, ref, pattern, paths):
    return git(mirror, "grep", "-h", "-o", "-P", pattern, ref, "--", *paths).splitlines()


def prefixes(names):
    # Every prefix of a dotted name exists too (C_Foo of C_Foo.Bar).
    for name in list(names):
        parts = name.split(".")
        for size in range(1, len(parts)):
            names.add(".".join(parts[:size]))
    return names


def documented(mirror, ref):
    names = set()
    for path in git(mirror, "ls-tree", "--name-only", ref, DOCS + "/").split():
        text = git(mirror, "show", ref + ":" + path)
        namespace = re.search(r'^\tNamespace = "(\w+)"', text, re.M)
        prefix = namespace.group(1) + "." if namespace else ""
        for match in re.finditer(r'^\t\t\{\n\t\t\tName = "(\w+)",\n\t\t\tType = "(\w+)",(.*?)^\t\t\},?$',
                                 text, re.M | re.S):
            name, kind, body = match.groups()
            if kind == "Function":
                names.add(prefix + name)
            elif kind in ("Enumeration", "Constants"):
                root = "Enum." if kind == "Enumeration" else "Constants."
                names.add(root + name)
                for field in re.findall(r'^\t\t\t\t\{ Name = "(\w+)"', body, re.M):
                    names.add(root + name + "." + field)
    return prefixes(names)


def defined(mirror, ref):
    names = set()
    for line in grep(mirror, ref, r"^\s*function %s(?:[.:]%s)*\s*\(" % (NAME, NAME), LUA):
        names.add(re.match(r"\s*function ([\w.:]+)", line).group(1).replace(":", "."))
    for line in grep(mirror, ref, r"^%s(?:\.%s)*\s*=(?!=)" % (NAME, NAME), LUA):
        names.add(re.match(r"[\w.]+", line).group(0))
    for line in grep(mirror, ref, r'\bname="%s"' % NAME, ["Interface/*.xml"] + NOT_OTHER_FLAVORS):
        names.add(line[6:-1])
    return prefixes(names)


def used(mirror, ref):
    return prefixes(set(grep(mirror, ref, USED, LUA)))


def declared_clients():
    """Interface numbers of every MSUF_Suite* TOC but the Nameplates one (its
    own session keeps it)."""
    numbers = set()
    for toc in sorted(ROOT.glob("MSUF_Suite*/*.toc")):
        if toc.parent.name == "MSUF_Suite_Nameplates":
            continue
        line = re.search(r"^## Interface:\s*(.+)$", toc.read_text(encoding="utf-8", errors="replace"), re.M)
        if line:
            numbers.update(re.findall(r"\d+", line.group(1)))
    unknown = sorted(numbers - set(KNOWN_CLIENTS))
    if unknown:
        sys.exit("add a mirror ref to KNOWN_CLIENTS for interface " + ", ".join(unknown))
    return {number: KNOWN_CLIENTS[number] for number in sorted(numbers)}


def main():
    mirror = sys.argv[1] if len(sys.argv) > 1 else MIRROR
    CLIENTS.update(declared_clients())
    present, judged = {}, set()
    for client, ref in CLIENTS.values():
        known = documented(mirror, ref) | defined(mirror, ref)
        judged |= known
        present[client] = known | used(mirror, ref)
        print("%-8s %d names" % (client, len(present[client])))
    partial = {}
    for name in sorted(judged):
        if not API_NAME.match(name):
            continue
        have = [client for client, _ in CLIENTS.values() if name in present[client]]
        if len(have) != len(CLIENTS):
            partial[name] = have
    snapshot = {
        "about": "Client API names missing on at least one declared client, with the clients that have them. "
                 "Regenerate with tools/tests/client_api_snapshot_gen.py.",
        "interfaces": {number: client for number, (client, _) in CLIENTS.items()},
        "refs": {client: ref for client, ref in CLIENTS.values()},
        "partial": partial,
    }
    OUT.write_text(json.dumps(snapshot, indent=0, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print("wrote %s: %d partial names" % (OUT.name, len(partial)))


if __name__ == "__main__":
    main()
