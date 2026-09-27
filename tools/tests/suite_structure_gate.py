"""Structure gate over every MSUF_Suite* addon (Nameplates files and Libs/ are
skipped).

Usage: python tools/tests/suite_structure_gate.py <tree root> [--list]

Checks, from Lua 5.1's own compiler listing (luac -l) and the source:
  1. every file compiles; main-chunk locals <= 150, functions <= 80 lines and
     code files <= 900 lines (data files in size_exempt);
  2. client APIs: every global name or path the code reads that is missing on
     a client a TOC declares (## Interface lines, client_api_snapshot.json)
     needs an entry; one the code calls or indexes must also be guarded on
     that line, earlier in the function, or through a tested local;
  3. guards on globals: `X and X.`, `if (not) X then`, `type(X) ==/~=`,
     `X ==/~= nil`, `_G.X or`, also through a local alias of a global, and
     method probes on locals (`type(obj.Method)`, `obj.Method and`);
  4. own-module probes: the same checks on the addon's own tables (the
     varargs namespace, `local x = P.Foo` aliases and paths below them).
Every finding of 2-4 needs an entry in suite_structure_allowlist.json with a
kind and a reason; entries nothing matches fail too. With --list the gate
prints every finding in allowlist form.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SNAPSHOT = HERE / "client_api_snapshot.json"
ALLOWLIST = HERE / "suite_structure_allowlist.json"
DEFAULT_LUAC = r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\luac.exe"
MAX_LOCALS, MAX_FUNCTION, MAX_FILE = 150, 80, 900
KINDS = {
    "client": "a version or client guard; the reason names the client that lacks the API",
    "addon": "another addon's export (MSUF, MapkoSkin, Blizzard load-on-demand UI)",
    "lod": "an export of a load-on-demand Suite addon that may not be loaded yet",
    "state": "database or runtime state that is legitimately absent at times",
    "review": "found in another pass's files and not yet confirmed by its owner",
}
CLIENT_NAMES = re.compile(r"12\.1\.0|12\.1\.5|Retail|Forever|not in (?:the|Blizzard's) UI source")
PATH = r"(?:_G\.)?[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*"
KEYWORDS = {"and", "or", "not", "nil", "true", "false", "function", "end", "local", "return", "then",
            "if", "else", "elseif", "do", "while", "for", "in", "repeat", "until", "break", "self"}
LUA_BUILTINS = {"_G", "math", "string", "table", "type", "select", "pairs", "ipairs", "next", "tostring",
                "tonumber", "assert", "error", "unpack", "rawget", "rawset", "setmetatable",
                "getmetatable", "print", "coroutine", "os", "debug", "bit", "strsplit", "format", "wipe"}


def luac_path():
    explicit = os.environ.get("MSUF_LUAC51")
    if explicit:
        return explicit
    lua = os.environ.get("MSUF_LUA51")
    if lua:
        return str(Path(lua).with_name("luac.exe"))
    return DEFAULT_LUAC


def scope_files(root):
    files = []
    for addon in sorted(os.listdir(root)):
        folder = root / addon
        if not addon.startswith("MSUF_Suite") or addon == "MSUF_Suite_Nameplates" or not folder.is_dir():
            continue
        for dirpath, dirs, names in os.walk(folder):
            dirs[:] = sorted(d for d in dirs if d != "Libs")
            for name in sorted(names):
                if name.endswith(".lua") and "Nameplate" not in name:
                    files.append(Path(dirpath) / name)
    return files


def declared_clients(root, interfaces, problems):
    clients = set()
    for toc in sorted(root.glob("MSUF_Suite*/*.toc")):
        if toc.parent.name == "MSUF_Suite_Nameplates":
            continue
        text = toc.read_text(encoding="utf-8", errors="replace")
        match = re.search(r"^## Interface:\s*(.+)$", text, re.M)
        if not match:
            problems.append("%s declares no ## Interface" % toc.relative_to(root).as_posix())
            continue
        for number in re.findall(r"\d+", match.group(1)):
            if number not in interfaces:
                problems.append("%s declares interface %s, which client_api_snapshot.json does not know; "
                                "regenerate it with client_api_snapshot_gen.py" % (toc.name, number))
            else:
                clients.add(interfaces[number])
    return clients


# ---------------------------------------------------------------- luac listing
HEADER = re.compile(r"^(main|function) <.+:(\d+),(\d+)> \(")
LOCALS = re.compile(r"(\d+) locals")
INSTRUCTION = re.compile(r"^\t\d+\t\[(\d+)\]\t(\w+)\s+([-\d ]+?)\s*(?:;\s*(.*))?$")


def listing_facts(text):
    """Main locals, function spans and the global reads of one luac -l
    listing. Each read is [line, name, used]: used is True once the value is
    called or indexed (that is what raises when a client lacks the name)."""
    main_locals, spans, reads = 0, [], []
    lines = text.splitlines()
    registers = {}

    def use(register):
        held = registers.get(register)
        if held and held[1] is not None:
            reads[held[1]][2] = True

    for index, line in enumerate(lines):
        header = HEADER.match(line)
        if header:
            registers = {}
            if header.group(1) == "main":
                main_locals = int(LOCALS.search(lines[index + 1]).group(1))
            else:
                spans.append((int(header.group(2)), int(header.group(3))))
            continue
        match = INSTRUCTION.match(line)
        if not match:
            continue
        lineno, op, args, comment = int(match.group(1)), match.group(2), match.group(3).split(), match.group(4)
        numbers = [int(a) for a in args]
        a = numbers[0]
        if op == "GETGLOBAL":
            name = (comment or "").strip()
            if name == "_G":
                registers[a] = ("_G", None)
            elif name:
                reads.append([lineno, name, False])
                registers[a] = (name, len(reads) - 1)
            else:
                registers.pop(a, None)
            continue
        if op in ("GETTABLE", "SELF"):
            use(numbers[1])
        elif op in ("CALL", "TAILCALL", "SETTABLE"):
            use(a)
        if op == "GETTABLE" and len(numbers) == 3 and numbers[2] < 0 and comment:
            key = re.match(r'^"(\w+)"', comment.strip())
            base = registers.get(numbers[1])
            if key and base and base[0].count(".") < 2:
                path = key.group(1) if base[0] == "_G" else base[0] + "." + key.group(1)
                reads.append([lineno, path, False])
                registers[a] = (path, len(reads) - 1)
                continue
        # Any other write ends what the register held.
        last = a
        if op in ("CALL", "VARARG"):
            last = a + (numbers[2] if op == "CALL" else numbers[1]) - 2
            if (op == "CALL" and numbers[2] == 0) or (op == "VARARG" and numbers[1] == 0):
                last = a + 255
        elif op == "LOADNIL":
            last = numbers[1]
        elif op == "SELF":
            last = a + 1
        elif op in ("FORPREP", "FORLOOP"):
            last = a + 3
        elif op == "TFORLOOP":
            last = a + 2 + numbers[1]
        for register in range(a, max(a, last) + 1):
            registers.pop(register, None)
    return main_locals, spans, reads


# ---------------------------------------------------------------- source scan
LONG_BRACKET = re.compile(r"\[(=*)\[")
TYPE_NAMES = {"function", "table", "number", "string", "boolean", "nil", "userdata"}


def is_export(name):
    """A module or function by naming convention: capitalized with lower-case
    letters, so neither a constant (ALL_CAPS) nor saved variables (DB, RootDB)."""
    return name[:1].isupper() and any(ch.islower() for ch in name) and not name.endswith("DB")


def strip_code(source):
    """Source with comments removed and string contents replaced by S; line
    breaks are kept so match offsets map to the original lines."""
    out, i, n = [], 0, len(source)
    while i < n:
        c = source[i]
        if c == "-" and source.startswith("--", i):
            long = LONG_BRACKET.match(source, i + 2)
            if long:
                end = source.find("]" + long.group(1) + "]", long.end())
                end = n if end < 0 else end + len(long.group(1)) + 2
                out.append("\n" * source.count("\n", i, end))
                i = end
            else:
                end = source.find("\n", i)
                i = n if end < 0 else end
            continue
        if c in "\"'":
            j = i + 1
            while j < n and source[j] != c and source[j] != "\n":
                j += 2 if source[j] == "\\" else 1
            # A type name survives, so type(x) == "function" stays readable.
            word = source[i + 1:j]
            out.append(c + (word if word in TYPE_NAMES else "S") + c)
            i = j + 1
            continue
        if c == "[":
            long = LONG_BRACKET.match(source, i)
            if long:
                end = source.find("]" + long.group(1) + "]", long.end())
                end = n if end < 0 else end + len(long.group(1)) + 2
                out.append('"S"' + "\n" * source.count("\n", i, end))
                i = end
                continue
        out.append(c)
        i += 1
    return "".join(out)


def declared_locals(code):
    names = set()
    for match in re.finditer(r"\blocal\s+function\s+(\w+)", code):
        names.add(match.group(1))
    for match in re.finditer(r"\blocal\s+((?:\w+\s*,\s*)*\w+)", code):
        names.update(n.strip() for n in match.group(1).split(","))
    for match in re.finditer(r"\bfunction\b[^(]*\(([^)]*)\)", code):
        names.update(n.strip() for n in match.group(1).split(",") if n.strip() not in ("", "..."))
    for match in re.finditer(r"\bfor\s+((?:\w+\s*,\s*)*\w+)\s*(?:=|in\b)", code):
        names.update(n.strip() for n in match.group(1).split(","))
    names.discard("function")
    return names


def assignments(code):
    """(names, values) of every `local a, b = x, y` statement."""
    for match in re.finditer(r"\blocal\s+((?:\w+\s*,\s*)*\w+)\s*=\s*([^\n]+)", code):
        names = [n.strip() for n in match.group(1).split(",")]
        values, depth, current = [], 0, ""
        for char in match.group(2):
            if char in "({[":
                depth += 1
            elif char in ")}]":
                depth -= 1
            if char == "," and depth == 0:
                values.append(current.strip())
                current = ""
            else:
                current += char
        values.append(current.strip())
        yield names, values


def roots_and_aliases(code, locals_):
    """Module tables of a file (the varargs namespace, the Suite and skin
    namespaces, and locals holding a capitalized field of one), locals that
    alias such a field (local Read = O.Read), and locals that alias a
    global path (local tooltip = GameTooltip)."""
    modules = set()
    match = re.search(r"\blocal\s+(\w+)\s*,\s*(\w+)\s*=\s*\.\.\.", code)
    if match:
        modules.update(n for n in match.groups() if n != "_")
    for name in re.findall(r"\blocal\s+(\w+)\s*=\s*(?:assert\()?_G\.(?:MSUFSuite|MapkoSkin)\b", code):
        modules.add(name)
    aliases, global_aliases = {}, {}
    statements = list(assignments(code))
    # A name declared more than once (say, in two functions) is no reliable alias.
    declarations = {}
    for names, _ in statements:
        for name in names:
            declarations[name] = declarations.get(name, 0) + 1
    for name in re.findall(r"\blocal\s+function\s+(\w+)", code):
        declarations[name] = 2
    changed = True
    while changed:
        changed = False
        for names, values in statements:
            for name, value in zip(names, values):
                if name in modules or name in aliases or name in global_aliases or declarations[name] > 1:
                    continue
                found = re.fullmatch(r"(?:assert\()?(" + PATH + r")(?:\)|\s*,.*\))?", value)
                if not found:
                    continue
                path = found.group(1)
                parts = path.split(".")
                root = parts[0]
                if root in modules and len(parts) > 1 and is_export(parts[-1]):
                    if len(parts) == 2 and not re.match(r"\w+\s*\(", value):
                        # A module table in its own right (local O = P.Objectives).
                        modules.add(name)
                    aliases[name] = path
                    changed = True
                elif root == "_G" and len(parts) > 1:
                    global_aliases[name] = ".".join(parts[1:])
                    changed = True
                elif root[:1].isupper() and root not in LUA_BUILTINS and (root not in locals_ or root == name):
                    global_aliases[name] = path
                    changed = True
    return modules, aliases, global_aliases


def probed_paths(code):
    """(offset, path, form) of every existence test in the code."""
    for match in re.finditer(r"(?<![\w.:])(" + PATH + r")\s+and\s+(?:not\s+)?\1\s*([.:\[(])", code):
        yield match.start(1), match.group(1), "call" if match.group(2) == "(" else "and"
    for match in re.finditer(r"(?<![\w.:])(\w+)\.(\w+)\s+and\s+\1:\2\s*\(", code):
        yield match.start(1), match.group(1) + "." + match.group(2), "call"
    for match in re.finditer(r"\btype\(\s*(" + PATH + r")\s*\)\s*[~=]=\s*\"(\w+)\"", code):
        yield match.start(1), match.group(1), "type" + match.group(2)
    for match in re.finditer(r"(?<![\w.:])(" + PATH + r")\s*[~=]=\s*nil\b", code):
        yield match.start(1), match.group(1), "nil"
    for match in re.finditer(r"\bnil\s*[~=]=\s*(" + PATH + r")", code):
        yield match.start(1), match.group(1), "nil"
    for match in re.finditer(r"(?<![\w.:])(_G\.\w+(?:\.\w+)*)\s+or\b", code):
        yield match.start(1), match.group(1), "nil"
    for match in re.finditer(r"\b(?:if|elseif|while)\b(.*?)\b(?:then|do)\b([^\n]*)", code, re.S):
        condition, base, body = match.group(1), match.start(1), match.group(2)
        # Calls collapse to one token (same length, so offsets stay); then the
        # pieces between and/or/not/parentheses that are bare paths are truth
        # tests (a comparison or a call is not).
        previous = None
        while previous != condition:
            previous = condition
            condition = re.sub(r"(?:" + PATH + r"(?::\w+)?|\]|#)\s*\([^()]*\)|\(\s*#+\s*\)",
                               lambda m: "#" * len(m.group(0)), condition)
        for piece in re.finditer(r"[^()]+", condition):
            start = 0
            for text in re.split(r"\b(?:and|or)\b", piece.group(0)):
                at = start
                start += len(text) + 3
                operand = re.fullmatch(r"\s*(?:not\s+)?(" + PATH + r")\s*", text)
                if not operand or operand.group(1) in KEYWORDS:
                    continue
                path = operand.group(1)
                member = path.rsplit(".", 1)
                calls = len(member) == 2 and re.search(
                    r"(?<![\w.:])%s[.:]%s\s*\(" % (re.escape(member[0]), re.escape(member[1])), body)
                offset = base + piece.start() + at + operand.start(1)
                yield offset, path, "call" if calls else "cond"


def classify(path, form, locals_, modules, aliases, global_aliases):
    """(kind, symbol) of one probed path, or None when it is plain state."""
    path = path[3:] if path.startswith("_G.") else path
    parts = path.split(".")
    root = parts[0]
    if root in KEYWORDS - {"self"} or root in LUA_BUILTINS:
        return None
    if root in modules:
        return ("probe", path) if len(parts) > 1 and is_export(parts[-1]) else None
    if root in aliases:
        effective = (aliases[root] + path[len(root):]).split(".")
        return ("probe", "%s (= %s)" % (path, aliases[root])) if is_export(effective[-1]) else None
    if root in global_aliases:
        return "guard", "%s (= %s)" % (path, global_aliases[root])
    if root in locals_ or root == "self":
        # A method probe on a local object: type(obj.Method) == "function",
        # obj.Method and obj:Method(), if obj.Method then obj:Method().
        if len(parts) > 1 and is_export(parts[-1]) and form in ("call", "typefunction"):
            return "guard", path
        return None
    return "guard", path


def in_guard(text, name):
    """Whether `name` is tested (not used) on this stripped line: X and ...,
    X or ..., if X then, not X, type(X), X ==/~= nil, ... and X, ... or X."""
    ref = r"(?:_G\.)?" + re.escape(name)
    return bool(re.search(r"(?<![\w.:])" + ref + r"\s*(?:\bor\b|\band\b|\bthen\b|==|~=|\))", text)
                or re.search(r"\b(?:and|or|not|if|elseif|while)\s+(?:not\s+)?" + ref + r"(?!\w)", text))


def guarded_read(code, lines, spans, line, name):
    """A client API missing on a declared client may only be read under a
    guard: tested on its own line, captured into a local that the file tests
    (local f = C_X.Fn ... if f then), or tested earlier in the same function."""
    text = lines[line - 1]
    if in_guard(text, name):
        return True
    capture = re.search(r"\blocal\s+(\w+)\s*=\s*(?:_G\.)?" + re.escape(name) + r"\s*$", text)
    if capture:
        alias = re.escape(capture.group(1))
        return bool(re.search(r"\b(?:if|elseif|and|or|not|while)\s+(?:not\s+)?%s\b|\b%s\s+(?:and|or|then)\b"
                              r"|\b%s\s*[~=]=\s*nil|type\(\s*%s\s*\)" % (alias, alias, alias, alias), code))
    first = 1
    for start, last in spans:
        if start <= line <= last and start > first:
            first = start
    return any(in_guard(lines[i - 1], name) for i in range(first, line))


def scan_source(code):
    """{(kind, symbol): first line} of the existence tests in stripped code."""
    locals_ = declared_locals(code)
    modules, aliases, global_aliases = roots_and_aliases(code, locals_)
    found = {}
    for offset, path, form in probed_paths(code):
        kind = classify(path, form, locals_, modules, aliases, global_aliases)
        if kind:
            found.setdefault(kind, code.count("\n", 0, offset) + 1)
    return found


# ---------------------------------------------------------------- gate
def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    listing = "--list" in sys.argv
    root = Path(args[0] if args else HERE.parents[1]).resolve()
    luac = luac_path()
    if not Path(luac).is_file():
        print("FAIL Lua 5.1 luac not found at %s (set MSUF_LUAC51); the gate never skips" % luac)
        return 1
    snapshot = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    allow = json.loads(ALLOWLIST.read_text(encoding="utf-8"))
    problems = []
    clients = declared_clients(root, snapshot["interfaces"], problems)
    partial = snapshot["partial"]

    exempt = allow.get("size_exempt", {})
    entries = {}
    for entry in allow.get("allowed", []):
        key = (entry["file"], entry["symbol"])
        if key in entries:
            problems.append("allowlist lists %s %s twice" % key)
        if entry.get("kind") not in KINDS or not entry.get("reason"):
            problems.append("allowlist entry %s %s needs a kind (%s) and a reason"
                            % (entry["file"], entry["symbol"], ", ".join(sorted(KINDS))))
        elif entry["kind"] == "client" and not CLIENT_NAMES.search(entry["reason"]):
            problems.append("client entry %s %s must name the client that lacks it" % key)
        entries[key] = entry
    used, findings = set(), []

    files = scope_files(root)
    for path in files:
        rel = path.relative_to(root).as_posix()
        run = subprocess.run([luac, "-l", "-p", str(path)], capture_output=True, text=True, errors="replace")
        if run.returncode != 0:
            problems.append("%s does not compile under Lua 5.1: %s" % (rel, run.stderr.strip()))
            continue
        main_locals, spans, reads = listing_facts(run.stdout)
        source = path.read_text(encoding="utf-8", errors="replace")
        line_count = source.count("\n") + (0 if source.endswith("\n") else 1)
        if rel not in exempt:
            if line_count > MAX_FILE:
                problems.append("%s has %d lines (limit %d)" % (rel, line_count, MAX_FILE))
            if main_locals > MAX_LOCALS:
                problems.append("%s has %d main-chunk locals (limit %d)" % (rel, main_locals, MAX_LOCALS))
            for first, last in spans:
                if last - first + 1 > MAX_FUNCTION:
                    problems.append("%s:%d function spans %d lines (limit %d)"
                                    % (rel, first, last - first + 1, MAX_FUNCTION))
        code = strip_code(source)
        code_lines = code.split("\n")
        seen = set()
        for line, name, called in reads:
            have = partial.get(name)
            if have is None:
                continue
            lacking = sorted(clients - set(have))
            if not lacking:
                continue
            note = "missing on " + ", ".join(lacking)
            if called and not guarded_read(code, code_lines, spans, line, name):
                # Calling or indexing it raises there; no allowlist entry excuses that.
                problems.append("%s:%d calls or indexes %s without a guard (%s)" % (rel, line, name, note))
            elif name not in seen:
                seen.add(name)
                findings.append((rel, name, "api", line, note))
        for (kind, symbol), line in scan_source(code).items():
            findings.append((rel, symbol, kind, line, ""))

    for rel, symbol, kind, line, note in sorted(findings):
        entry = entries.get((rel, symbol))
        if entry:
            used.add((rel, symbol))
            if kind == "api" and entry["kind"] != "client":
                problems.append("%s:%d %s is %s; its entry must be kind client" % (rel, line, symbol, note))
            continue
        if listing:
            print('    {"file": "%s", "symbol": "%s", "kind": "?", "reason": "%s:%d %s %s"},'
                  % (rel, symbol, kind, line, note, ""))
        what = {"api": "reads a client API (%s)" % note, "guard": "guards a global or method",
                "probe": "probes its own module"}[kind]
        problems.append("%s:%d %s: %s without an allowlist entry" % (rel, line, what, symbol))
    for key in sorted(set(entries) - used):
        problems.append("allowlist entry %s %s matches nothing; remove it" % key)

    for problem in problems:
        print("FAIL " + problem)
    print("suite structure gate: %d files, %d clients, %d allowlisted findings, %d problems"
          % (len(files), len(clients), len(used), len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
