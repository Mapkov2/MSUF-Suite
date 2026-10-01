"""Suite locale tool: finds every English UI string of the Suite that reaches
translation, reports what a locale file lacks, merges translations into the
locale files and checks them.

The Suite shows English source text through MSUF's locale table (MSUF.L, the
key is the English text): P.Tr / M.Tr in the options pages, Suite.Text in the
core and the module addons, Menu2 widgets that translate their own labels,
and the catalog (labels, section titles, choices, help). The extractor reads
the Lua sources with a small data-flow pass: a helper whose parameter reaches
a translation (P.Text, P.Button, P.RuleSection, a page's local Row(...)) is a
translation sink itself, and so are table fields (label, title, help, ...)
and lists (choice labels) that reach one.

Usage (from the Suite root; Python 3.12, no third-party packages):
  python tools/suite_locale_tool.py extract [--out PATH] [--tsv -]
      Sorted TSV of the strings: id, class (chrome|help, +pending while a
      delta pass is due), english (\\n \\t \\\\ escaped), msuf (locales whose
      MSUF packs already translate it on both hosts), proper (1: names and
      abbreviations only), used (sink and file:line).
      Default output: _local_workflows/locale/suite_strings.tsv.
  python tools/suite_locale_tool.py missing --locale deDE|all [--format tsv|json] [--class chrome|help]
      Strings a Suite locale file still lacks (MSUF's packs cover the rest).
  python tools/suite_locale_tool.py apply --locale deDE --input FILE [--replace]
      Merges translations into MSUF_Suite/Locales/<locale>.lua. FILE is TSV
      (id<TAB>translation, `\\n` for a line break) or the JSON of `missing`
      with a "translation" field per entry (a string, or {locale: text}).
      Every entry is checked first; strings MSUF's packs cover are skipped.
  python tools/suite_locale_tool.py verify [--quiet]
      Every locale file: valid UTF-8, each key once, keys exist in the
      extraction, format specifiers, lone % signs, escape sequences and a
      trailing space match the English, scripts fit the language, coverage
      >= 99% chrome / 95% help. English sources hold no |h without a link.
  python tools/suite_locale_tool.py dynamic [--all]   text built at runtime, which cannot translate
  python tools/suite_locale_tool.py orphans      English-looking literals no sink reaches (review aid)
  python tools/suite_locale_tool.py sinks        every discovered sink and what made it one (debug aid)
  python tools/suite_locale_tool.py glossary TERM...   how MSUF's packs translate a term

Delta pass (new strings from other work):
  1. python tools/suite_locale_tool.py missing --locale all --format json > C:/tmp/delta.json
  2. translate: add "translation": {"deDE": "...", ...} to each entry, or
     write one TSV per locale with id<TAB>translation
  3. python tools/suite_locale_tool.py apply --locale deDE --input C:/tmp/delta.json   (per locale)
  4. remove the file from DELTA_PENDING below once its strings are translated
  5. python tools/suite_locale_tool.py verify && python tools/run_suite_tests.py locale
"""

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRANCH = ROOT.parent
HOST_CLASSIC = BRANCH / "MidnightSimpleUnitFrames-Classic"
HOST_MAIN = BRANCH / "MidnightSimpleUnitFrames"
LOCALE_DIR = ROOT / "MSUF_Suite" / "Locales"
DEFAULT_OUT = ROOT / "_local_workflows" / "locale" / "suite_strings.tsv"
LOCALES = ("deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW")
CORE = "MSUF_Suite"
# Files whose strings wait for a delta pass: they are extracted and listed by
# `missing`, but do not count against the coverage gate yet. Remove a file
# once its strings are translated.
DELTA_PENDING = ()

CHROME_MIN, HELP_MIN = 0.99, 0.95

# ---------------------------------------------------------------- Lua lexer
KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
            "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMBER = re.compile(r"0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
LONG_OPEN = re.compile(r"\[(=*)\[")
OPERATORS = ("...", "..", "==", "~=", "<=", ">=")
ESCAPES = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v",
           "\\": "\\", '"': '"', "'": "'", "\n": "\n"}
BLOCK_OPEN = ("function", "if", "do", "repeat")
BLOCK_CLOSE = ("end", "until")


class Token:
    __slots__ = ("kind", "value", "line")

    def __init__(self, kind, value, line):
        self.kind, self.value, self.line = kind, value, line

    def op(self, *values):
        return self.kind == "op" and self.value in values

    def kw(self, *values):
        return self.kind == "kw" and self.value in values

    def __repr__(self):
        return "%s:%r@%d" % (self.kind, self.value, self.line)


def decode_bytes(text):
    """Latin-1 text (one char per source byte) to the UTF-8 string it holds."""
    return text.encode("latin-1").decode("utf-8", errors="replace")


def lex(source):
    """Tokens of Lua 5.1 source given as latin-1 text (a char per byte).
    String tokens carry their runtime value, decoded from UTF-8."""
    tokens, i, n, line = [], 0, len(source), 1
    while i < n:
        c = source[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r\f\v":
            i += 1
            continue
        if source.startswith("--", i):
            long = LONG_OPEN.match(source, i + 2)
            if long:
                end = source.find("]" + long.group(1) + "]", long.end())
                end = n if end < 0 else end + len(long.group(1)) + 2
            else:
                end = source.find("\n", i)
                end = n if end < 0 else end
            line += source.count("\n", i, end)
            i = end
            continue
        if c in "\"'":
            j, out, start = i + 1, [], line
            while j < n and source[j] != c:
                ch = source[j]
                if ch == "\n":
                    raise SyntaxError("unfinished string at line %d" % line)
                if ch == "\\":
                    nxt = source[j + 1]
                    if nxt.isdigit():
                        digits = re.match(r"\d{1,3}", source[j + 1:j + 4]).group(0)
                        out.append(chr(int(digits)))
                        j += 1 + len(digits)
                        continue
                    if nxt == "\n":
                        line += 1
                    out.append(ESCAPES.get(nxt, nxt))
                    j += 2
                    continue
                out.append(ch)
                j += 1
            tokens.append(Token("str", decode_bytes("".join(out)), start))
            i = j + 1
            continue
        if c == "[":
            long = LONG_OPEN.match(source, i)
            if long:
                end = source.find("]" + long.group(1) + "]", long.end())
                body = source[long.end():end]
                if body.startswith("\r\n"):
                    body = body[2:]
                elif body.startswith("\n"):
                    body = body[1:]
                tokens.append(Token("str", decode_bytes(body), line))
                line += source.count("\n", i, end)
                i = end + len(long.group(1)) + 2
                continue
        match = NAME.match(source, i)
        if match:
            word = match.group(0)
            tokens.append(Token("kw" if word in KEYWORDS else "name", word, line))
            i = match.end()
            continue
        match = NUMBER.match(source, i)
        if match and (c.isdigit() or c == "."):
            tokens.append(Token("num", match.group(0), line))
            i = match.end()
            continue
        for op in OPERATORS:
            if source.startswith(op, i):
                tokens.append(Token("op", op, line))
                i += len(op)
                break
        else:
            tokens.append(Token("op", c, line))
            i += 1
    tokens.append(Token("eof", None, line))
    return tokens


def read_source(path):
    return path.read_bytes().decode("latin-1")


# ---------------------------------------------------------------- file model
BINARY = {"+", "-", "*", "/", "%", "^", "..", "==", "~=", "<", "<=", ">", ">="}


class FuncDef:
    __slots__ = ("name", "local", "params", "start", "end", "parent", "file", "scope", "returns")

    def __repr__(self):
        return "<def %s %s:%d>" % (self.name, self.file.rel, self.file.tokens[self.start].line)


class Scope:
    """Names declared directly in one function body (or the main chunk):
    parameters, loop values (for _, v in ipairs(X)), assigned values (a
    range, or (start, end, n) for the n-th result of a call) and values
    stored into a local table (X[k] = v)."""
    __slots__ = ("params", "loops", "locals", "declared", "elements")

    def __init__(self):
        self.params, self.loops, self.locals, self.declared, self.elements = {}, {}, {}, set(), {}


class Call:
    __slots__ = ("callee", "resolved", "args", "owner", "open", "method")


class LuaFile:
    def __init__(self, root, path):
        self.path = path
        self.rel = path.relative_to(root).as_posix()
        self.addon = self.rel.split("/")[0]
        self.tokens = lex(read_source(path))
        self.pair, self.open_of, self.block_end, self.inside = {}, {}, {}, []
        self.defs, self.calls, self.fields = [], [], []
        # (field, value range, owner) of `a.b.field[k] = value`, and the second
        # value of `return false, reason` / `return nil, reason`.
        self.field_elements, self.reasons = [], []
        self.call_at = {}
        self.main = Scope()
        self._match()
        self._functions()
        self._declarations()
        self._calls()
        self._fields()

    # brackets and blocks
    def _match(self):
        stack, blocks, inside = [], [], []
        opened = []   # innermost open bracket or block per token
        for k, t in enumerate(self.tokens):
            inside.append(opened[-1] if opened else None)
            if t.op("(", "{", "["):
                stack.append(k)
                opened.append(("bracket", k))
            elif t.op(")", "}", "]"):
                open_ = stack.pop()
                self.pair[open_], self.open_of[k] = k, open_
                opened.pop()
            elif t.kw(*BLOCK_OPEN):
                blocks.append(k)
                opened.append(("block", k))
            elif t.kw(*BLOCK_CLOSE):
                self.block_end[blocks.pop()] = k
                opened.pop()
        self.inside = inside

    def skip(self, k):
        """Index after the bracket or block starting at k (else k + 1)."""
        if k in self.pair:
            return self.pair[k] + 1
        if k in self.block_end:
            return self.block_end[k] + 1
        return k + 1

    def split(self, start, end, separators):
        """Top-level pieces of tokens[start:end], split at `separators`
        (operator or keyword values)."""
        pieces, k, first = [], start, start
        while k < end:
            t = self.tokens[k]
            if t.kind in ("op", "kw") and t.value in separators:
                pieces.append((first, k))
                first = k + 1
                k += 1
                continue
            k = self.skip(k)
        pieces.append((first, end))
        return pieces

    def has_top(self, start, end, values):
        k = start
        while k < end:
            t = self.tokens[k]
            if t.kind in ("op", "kw") and t.value in values:
                return True
            k = self.skip(k)
        return False

    def text(self, start, end):
        return " ".join(repr(t.value) if t.kind == "str" else str(t.value) for t in self.tokens[start:end])

    def expression_end(self, k):
        """Index after the expression starting at token k."""
        tokens = self.tokens
        while True:
            while tokens[k].op("-", "#") or tokens[k].kw("not"):
                k += 1
            t = tokens[k]
            if t.kind in ("str", "num") or t.kw("nil", "true", "false") or t.op("..."):
                k += 1
            elif t.kw("function"):
                k = self.block_end[k] + 1
            elif t.op("{"):
                k = self.pair[k] + 1
            elif t.op("(") or t.kind == "name":
                k = self.pair[k] + 1 if t.op("(") else k + 1
                while True:
                    s = tokens[k]
                    if s.op(".") and tokens[k + 1].kind == "name":
                        k += 2
                    elif s.op(":") and tokens[k + 1].kind == "name":
                        k += 2
                    elif s.op("(", "[", "{"):
                        k = self.pair[k] + 1
                    elif s.kind == "str":
                        k += 1
                    else:
                        break
            else:
                return k
            t = tokens[k]
            if (t.kind == "op" and t.value in BINARY) or t.kw("and", "or"):
                k += 1
                continue
            return k

    def expression_list(self, k):
        values = []
        while True:
            end = self.expression_end(k)
            values.append((k, end))
            if self.tokens[end].op(","):
                k = end + 1
                continue
            return values

    # function definitions
    def _functions(self):
        tokens = self.tokens
        for k, t in enumerate(tokens):
            if not t.kw("function"):
                continue
            j, name, local = k + 1, None, bool(k and tokens[k - 1].kw("local"))
            if tokens[j].kind == "name":
                parts = [tokens[j].value]
                j += 1
                while tokens[j].op(".", ":") and tokens[j + 1].kind == "name":
                    parts.append(tokens[j].value + tokens[j + 1].value)
                    j += 2
                name = "".join(parts)
            elif k >= 2 and tokens[k - 1].op("=") and tokens[k - 2].kind == "name":
                # NAME = function, local NAME = function, a.b = function, field = function
                m, parts = k - 2, [tokens[k - 2].value]
                while m >= 2 and tokens[m - 1].op(".") and tokens[m - 2].kind == "name":
                    parts.insert(0, tokens[m - 2].value + ".")
                    m -= 2
                name = "".join(parts)
                local = bool(m >= 1 and tokens[m - 1].kw("local"))
            if not tokens[j].op("("):
                continue
            close = self.pair[j]
            d = FuncDef()
            d.name, d.local, d.start, d.end, d.file = name, local, k, self.block_end[k], self
            d.params = [tok.value for tok in tokens[j + 1:close] if tok.kind == "name"]
            if ":" in (name or ""):
                d.params.insert(0, "self")
            d.scope, d.returns = Scope(), []
            for index, param in enumerate(d.params):
                d.scope.params[param] = index
                d.scope.declared.add(param)
            self.defs.append(d)
        owner = [None] * len(tokens)
        stack = []
        for d in sorted(self.defs, key=lambda d: d.start):
            while stack and stack[-1].end < d.start:
                stack.pop()
            d.parent = stack[-1] if stack else None
            stack.append(d)
            for k in range(d.start, d.end + 1):
                owner[k] = d
        self.owner = owner

    def scope_of(self, owner):
        return owner.scope if owner is not None else self.main

    def names(self, j):
        names = []
        while self.tokens[j].kind == "name":
            names.append(self.tokens[j].value)
            if self.tokens[j + 1].op(","):
                j += 2
            else:
                return names, j + 1
        return names, j

    # locals, loops and assignments
    def _declarations(self):
        tokens = self.tokens
        assigns = []
        for k, t in enumerate(tokens):
            if t.kw("for") and tokens[k + 1].kind == "name":
                names, j = self.names(k + 1)
                scope = self.scope_of(self.owner[k])
                scope.declared.update(names)
                if tokens[j].kw("in") and tokens[j + 1].kind == "name" and tokens[j + 1].value in ("ipairs", "pairs") \
                        and tokens[j + 2].op("(") and len(names) >= 2:
                    body = self.pair[j + 2] + 1
                    end = self.block_end.get(body, len(tokens) - 1) if tokens[body].kw("do") else len(tokens) - 1
                    scope.loops.setdefault(names[1], []).append(((j + 3, self.pair[j + 2]), body, end))
            elif t.kw("local") and tokens[k + 1].kw("function") and tokens[k + 2].kind == "name":
                self.scope_of(self.owner[k]).declared.add(tokens[k + 2].value)
            elif t.kw("local") and tokens[k + 1].kind == "name":
                names, j = self.names(k + 1)
                scope = self.scope_of(self.owner[k])
                scope.declared.update(names)
                if not tokens[j].op("="):
                    continue
                values = self.bind(len(names), self.expression_list(j + 1))
                for index, name in enumerate(names):
                    if index < len(values):
                        scope.locals.setdefault(name, []).append(values[index])
            elif t.kw("return") and self.owner[k] is not None and not tokens[k + 1].kw("end", "else", "elseif") \
                    and not tokens[k + 1].op(";"):
                values = self.expression_list(k + 1)
                self.owner[k].returns.append(values)
                if len(values) >= 2 and values[0][1] - values[0][0] == 1 and tokens[values[0][0]].kw("false", "nil"):
                    self.reasons.append((values[1], self.owner[k]))
            elif t.op("=") and (self.inside[k] is None or self.inside[k][0] == "block"):
                targets, before = self.targets_before(k)
                if not targets or tokens[before].kw("local", "for"):
                    continue
                values = self.bind(len(targets), self.expression_list(k + 1))
                for index, (start, end) in enumerate(targets):
                    if index >= len(values):
                        break
                    value = values[index]
                    if end - start == 1 and tokens[start].kind == "name":
                        assigns.append((start, tokens[start].value, value, False))
                    elif tokens[end - 1].kind == "name" and tokens[end - 2].op("."):
                        self.fields.append((tokens[end - 1].value, value, self.owner[k]))
                    elif tokens[end - 1].op("]") and tokens[end - 2].kind == "str" and tokens[end - 3].op("["):
                        self.fields.append((tokens[end - 2].value, value, self.owner[k]))
                    elif tokens[end - 1].op("]"):
                        # X[k] = value / a.b.X[k] = value: an element of a table.
                        base_end = self.open_of[end - 1]
                        if base_end - start == 1 and tokens[start].kind == "name":
                            assigns.append((start, tokens[start].value, value, True))
                        elif tokens[base_end - 1].kind == "name" and tokens[base_end - 2].op("."):
                            self.field_elements.append((tokens[base_end - 1].value, value, self.owner[k]))
        # NAME = value belongs to the scope that declared NAME.
        for k, name, value, element in assigns:
            owner = self.owner[k]
            while True:
                scope = self.scope_of(owner)
                if name in scope.declared or owner is None:
                    (scope.elements if element else scope.locals).setdefault(name, []).append(value)
                    break
                owner = owner.parent

    def bind(self, count, values):
        """Value ranges for `count` targets: a call in last place fills the
        remaining targets with its further results, as (start, end, n)."""
        if len(values) < count and values:
            start, end = values[-1]
            if self.tokens[end - 1].op(")"):
                values = list(values) + [(start, end, n) for n in range(1, count - len(values) + 1)]
        return values

    def targets_before(self, equals):
        """The assignment targets ending at token `equals` (an `=`), as token
        ranges, and the index of the token before the first target."""
        tokens, targets, j = self.tokens, [], equals - 1
        while j >= 0:
            end = j + 1
            while j >= 0:
                t = tokens[j]
                if t.op(")", "]"):
                    j = self.open_of[j] - 1
                    continue
                if t.kind == "name":
                    if j >= 1 and tokens[j - 1].op(".", ":"):
                        j -= 2
                        continue
                    j -= 1
                break
            if j + 1 >= end:
                return [], j
            targets.insert(0, (j + 1, end))
            if j >= 0 and tokens[j].op(","):
                j -= 1
                continue
            break
        return targets, max(j, 0)

    # calls
    def _calls(self):
        tokens = self.tokens
        for k, t in enumerate(tokens):
            if not t.op("("):
                continue
            callee = callee_before(tokens, k)
            if not callee or callee == "<def>":
                continue
            call = Call()
            call.callee, call.open = callee, k
            call.method = ":" in callee.split(".")[-1]
            call.owner = self.owner[k]
            close = self.pair[k]
            call.args = [] if close == k + 1 else self.split(k + 1, close, (",",))
            call.resolved = self.resolve_path(callee, call.owner)
            self.calls.append(call)
            self.call_at[k] = call

    def resolve_path(self, path, owner):
        """A call or value path with local aliases replaced (Tr -> P.Tr,
        B.Bool -> NS.CatalogBuild.Bool)."""
        for _ in range(6):
            head = re.match(r"[A-Za-z_]\w*", path)
            if not head:
                return path
            name = head.group(0)
            value = self.alias(name, owner)
            if value is None or value == name or value.startswith(name + "."):
                return path
            path = value + path[len(name):]
        return path

    def alias(self, name, owner):
        while True:
            scope = self.scope_of(owner)
            if name in scope.params or name in scope.loops:
                return None
            if name in scope.locals:
                values = scope.locals[name]
                if len(values) != 1 or len(values[0]) != 2:
                    return None
                start, end = values[0]
                if end > start and all(t.kind == "name" or t.op(".") for t in self.tokens[start:end]):
                    return "".join(str(t.value) for t in self.tokens[start:end])
                return None
            if name in scope.declared or owner is None:
                return None
            owner = owner.parent

    # table constructor fields (assigned fields come from _declarations)
    def _fields(self):
        tokens = self.tokens
        for k in range(1, len(tokens) - 1):
            t = tokens[k]
            if not tokens[k + 1].op("="):
                continue
            around = self.inside[k]
            if around is None or around[0] != "bracket" or not tokens[around[1]].op("{"):
                continue
            if t.kind == "name" and tokens[k - 1].op("{", ",", ";"):
                self.fields.append((t.value, (k + 2, self.expression_end(k + 2)), self.owner[k]))
            elif t.op("]") and tokens[k - 1].kind == "str" and tokens[k - 2].op("[") \
                    and tokens[k - 3].op("{", ",", ";"):
                self.fields.append((tokens[k - 1].value, (k + 2, self.expression_end(k + 2)), self.owner[k]))


def callee_before(tokens, index):
    """The dotted name ending right before tokens[index] (a call's '('),
    '<expr>' for a call on an expression, '<def>' for a definition's
    parameter list, or None when the bracket is no call."""
    j = index - 1
    if j < 0:
        return None
    t = tokens[j]
    if t.kind == "name":
        parts = [t.value]
        j -= 1
        while j >= 1 and tokens[j].op(".", ":") and tokens[j - 1].kind == "name":
            parts.insert(0, tokens[j - 1].value + tokens[j].value)
            j -= 2
        if j >= 1 and tokens[j].op(".", ":") and tokens[j - 1].op(")", "]"):
            parts.insert(0, "<expr>" + tokens[j].value)
            j -= 1
        elif j >= 1 and tokens[j].op(".", ":") and tokens[j - 1].kind == "str":
            parts.insert(0, "<str>" + tokens[j].value)
        if j >= 0 and tokens[j].kw("function"):
            return "<def>"
        return "".join(parts)
    if t.op(")", "]") or t.kind == "str":
        return "<expr>"
    return None


# ---------------------------------------------------------------- sinks
STR = ("s",)


def LIST(shape):
    return ("l", shape)


def FIELD(name, shape):
    return ("f", name, shape)


def IDX(n, shape):
    return ("i", n, shape)


def RET(n, shape):
    """Result n of a function value (a callback passed as a parameter)."""
    return ("r", n, shape)


# Only string literals: the argument of a SetText that translates.
LIT = ("t",)


# Translation sinks outside the Suite's own helpers: (resolved callee
# pattern, translated argument indexes). Menu2 widgets translate the labels
# they are given (MSUF's Menu2: T.Font's SetText, W.Dropdown, the accordion
# title, M.AddTooltip, M.ShowStatusFeedback, the search metadata label).
BASE_SINKS = [
    # Both authored help fields reach Menu2: the summary in the form, details on demand.
    ("MSUF_Suite_Options", re.compile(r"^P\.Help$"), {0: "s", 1: "s"}),
    (None, re.compile(r"(?:^|\.)Tr$"), {0: "s"}),
    (None, re.compile(r"^(?:Suite|NS|S|P\.Suite|P\.S|NS\.Suite|Private\.NS|Private\.Suite|MSUFSuite)\.Text$"), {0: "s"}),
    (None, re.compile(r"^(?:Suite|NS|P\.Suite)\.StatusText$"), {0: "s"}),
    (None, re.compile(r"(?:^|\.)FormatStatus$"), {0: "s"}),
    (None, re.compile(r"(?:^|\.)T\.Font$"), {2: "s"}),
    (None, re.compile(r"(?:^|\.)T\.Button$"), {1: "s"}),
    (None, re.compile(r"(?:^|\.)W\.TopButton$"), {1: "s"}),
    (None, re.compile(r"(?:^|\.)W\.Dropdown$"), {1: "s"}),
    (None, re.compile(r"(?:^|\.)W\.SectionSwitch$"), {1: "s", 2: "s"}),
    (None, re.compile(r"(?:^|\.)W\.SwitchAt$"), {1: "s"}),
    (None, re.compile(r"(?:^|\.)W\.TextInput$"), {1: "s"}),
    (None, re.compile(r"(?:^|\.)M\.AddTooltip$"), {1: "s", 2: "s"}),
    (None, re.compile(r"(?:^|\.)M\.ShowStatusFeedback$"), {0: "s"}),
    (None, re.compile(r"(?:^|\.)M\.BindTextInputAt$"), {2: "s"}),
    (None, re.compile(r"(?:^|\.)M\.RegisterControlMetadata$"), {2: "s"}),
    (None, re.compile(r"(?:^|\.)M\.RunWithHistory$"), {0: "s"}),
    (None, re.compile(r":CollapsibleSection$"), {1: "s"}),
    # MSUF's shared Copy To popup translates its run button label.
    (None, re.compile(r"(?:^|\.)MakeScopeCopyPopup$"), {1: ("f", "runLabel", STR)}),
    # Menu2 font strings (T.Font) translate what SetText gives them; only
    # literals count, so runtime values are never followed.
    ("MSUF_Suite_Options", re.compile(r":SetText$"), {0: "t"}),
]
SHAPES = {"s": ("s",), "t": ("t",)}
# Menu2 and other external namespaces: calls through them never match a
# Suite helper of the same name.
EXTERNAL = re.compile(r"^(?:P\.M|P\.T|P\.W|MSUF2|_G|GameTooltip|MenuUtil|C_\w+|string|table|math)[.:]")
# The Suite's own functions that look like sinks by name but are not.
NOT_SINKS = {"Suite.Text", "Suite.StatusText", "Suite.FormatStatus"}
# Fields that hold keys or runtime data. A label falls back to one of them
# (CATEGORY_LABELS[id] or id), which must not make every `id = "..."` a label.
FIELD_NOT_SINKS = {"L", "id", "key", "keys", "value", "kind", "type", "PAGE", "ID", "name", "previewKey", "anchor",
                   "default", "min", "max", "step", "color"}
OPTIONS = "MSUF_Suite_Options"
RUNTIME = "MSUF_Suite_Modules"


def is_translatable(text):
    """Text with words in it: two letters after color codes and format
    specifiers are removed; paths, media files and separators are not."""
    if "\\" in text or re.search(r"\.(?:tga|blp|ttf|otf|png|ogg|mp3)$", text, re.I):
        return False
    stripped = re.sub(r"\|c[0-9a-fA-F]{0,8}|\|r|%[-+ #0]*\d*(?:\.\d+)?[sdifgxXcq%]", "", text)
    return sum(1 for ch in stripped if ch.isalpha()) >= 2


def identifier_like(text):
    """A key, token or macro rather than prose: no space and either
    snake/camel case, ALL_CAPS with underscores, or brackets."""
    if " " in text:
        return bool(re.match(r"^\[", text))
    return bool(re.fullmatch(r"[a-z]+[A-Z]\w*|\w*_\w*|[A-Z][a-z]+(?:[A-Z][a-z0-9]+)+|[a-z0-9]+(?:-[a-z0-9]+)*"
                             r"|[0-9a-fA-F]{6}", text))


class Extractor:
    def __init__(self, root):
        self.root = root
        self.files = [LuaFile(root, path) for path in source_files(root)]
        self.defs_by_name, self.defs_by_last, self.call_targets = {}, {}, {}
        for f in self.files:
            for d in f.defs:
                if d.name:
                    self.defs_by_name.setdefault(d.name, []).append(d)
                    if "." in d.name or ":" in d.name:
                        self.defs_by_last.setdefault(re.split(r"[.:]", d.name)[-1], []).append(d)
        # A local function exported as a field (Page.Button = Button) answers
        # calls through that field name too.
        for f in self.files:
            for field, rng, _ in f.fields:
                start, end = rng[0], rng[1]
                if len(rng) == 2 and end - start == 1 and f.tokens[start].kind == "name":
                    for d in f.defs:
                        if d.local and d.name == f.tokens[start].value and d not in self.defs_by_last.get(field, ()):
                            self.defs_by_last.setdefault(field, []).append(d)
        self.param_sinks = {}      # FuncDef -> {index: set(shape)}
        self.field_sinks = {}      # addon -> {field: set(shape)}
        self.why = {}              # sink -> first place that made it one
        self.found = {}            # text -> list of (rel, line, sink)
        self.dynamic = []          # (rel, line, sink, expression)
        self.changed = False
        self.seen = set()
        self.current = None

    # registration
    def add_param_sink(self, d, index, shape):
        slot = self.param_sinks.setdefault(d, {}).setdefault(index, set())
        if shape not in slot:
            slot.add(shape)
            self.changed = True
            self.why.setdefault(("param", d.name, index, shape), self.current)

    def add_field_sink(self, addon, field, shape):
        # x.L[key] reads a translation table; its keys are English already.
        if field in FIELD_NOT_SINKS:
            return
        # The options pages render the core's catalog, so their fields reach
        # the core too; a module addon's fields stay in that addon.
        for scope in {addon, CORE} if addon == OPTIONS else {addon}:
            slot = self.field_sinks.setdefault(scope, {}).setdefault(field, set())
            if shape not in slot:
                slot.add(shape)
                self.changed = True
                self.why.setdefault(("field", scope, field, shape), self.current)

    def collect(self, f, k, sink, direct):
        text = f.tokens[k].value
        if not is_translatable(text):
            return
        # A plain lowercase word from a list that goes straight into a
        # translation call (SIDES "below", "above") is a word, not a key.
        wording = re.fullmatch(r"[a-z]+", text) and re.search(r"(?:^|[.:])(?:Tr|Text)#0$", sink)
        if not direct and identifier_like(text) and not wording:
            return
        # Keys never read as prose, even when passed straight to a sink.
        if re.fullmatch(r"[a-z]+[A-Z]\w*|\w*_\w*|[a-z0-9]+(?:-[a-z0-9]+)+", text):
            return
        entry = (f.rel, f.tokens[k].line, sink)
        uses = self.found.setdefault(text, [])
        if entry not in uses:
            uses.append(entry)

    # call targets
    def call_sinks(self, f, call):
        sinks = {}
        resolved = call.resolved
        for addon, pattern, indexes in BASE_SINKS:
            if addon and addon != f.addon:
                continue
            if pattern.search(resolved) or pattern.search(call.callee):
                for index, shape in indexes.items():
                    sinks.setdefault(index, set()).add(SHAPES.get(shape, shape))
        # Parameter p of a definition is argument p of a `.` call and
        # argument p - 1 of a `:` call (self comes first).
        shift = 1 if call.method else 0
        targets = self.call_targets.get(id(call))
        if targets is None:
            targets = self.call_targets[id(call)] = self.targets(f, call)
        for d in targets:
            for index, shapes in self.param_sinks.get(d, {}).items():
                sinks.setdefault(index - shift, set()).update(shapes)
        return sinks

    def targets(self, f, call):
        """Suite functions a call may reach."""
        callee, resolved = call.callee, call.resolved
        if "<" in callee:
            return []
        if "." not in callee and ":" not in callee:
            owner = call.owner
            while True:
                found = [d for d in f.defs if d.name == callee and d.local and d.parent is owner]
                if found:
                    return found
                if owner is None:
                    break
                owner = owner.parent
        if EXTERNAL.match(resolved) or resolved in NOT_SINKS or ("." not in resolved and ":" not in resolved):
            return []
        # Exact names reach the addon and the core; a match by the last name
        # part (B.Bool -> Build.Bool) stays inside the calling addon.
        candidates = [d for d in self.defs_by_name.get(resolved, []) if self.visible(f, d)]
        if not candidates and resolved != callee and ("." in callee or ":" in callee):
            candidates = [d for d in self.defs_by_name.get(callee, []) if self.visible(f, d)]
        if not candidates:
            last = re.split(r"[.:]", resolved)[-1]
            candidates = [d for d in self.defs_by_last.get(last, []) if d.file.addon == f.addon]
        return candidates

    @staticmethod
    def visible(f, d):
        """Every addon sees the core; the module addons also share the
        runtime of MSUF_Suite_Modules (S.BlizzardText, S.RegisterOwnedMover)."""
        if d.file.addon in (f.addon, CORE) or f.addon == CORE:
            return True
        return d.file.addon == RUNTIME and f.addon not in (OPTIONS,)

    # applying a shape to an expression
    def apply(self, shape, f, rng, owner, sink, direct=True):
        key = (f.rel, rng, shape)
        if key in self.seen:
            return
        self.seen.add(key)
        if len(rng) == 3:
            # The n-th result of a call (local ok, reason = S.Set(...)).
            self.apply_result(shape, f, (rng[0], rng[1]), rng[2], sink)
            return
        start, end = rng
        tokens = f.tokens
        while end - start >= 2 and tokens[start].op("(") and f.pair.get(start) == end - 1:
            start, end = start + 1, end - 1
        if end <= start:
            return
        for part in f.split(start, end, ("or",)):
            pieces = f.split(part[0], part[1], ("and",))
            piece = pieces[-1]
            self.apply_piece(shape, f, piece, owner, sink, direct)

    def apply_piece(self, shape, f, rng, owner, sink, direct):
        start, end = rng
        tokens = f.tokens
        while end - start >= 2 and tokens[start].op("(") and f.pair.get(start) == end - 1:
            start, end = start + 1, end - 1
        if end <= start or tokens[start].kw("not"):
            return
        if (start, end) != rng and f.has_top(start, end, ("or", "and")):
            self.apply(shape, f, (start, end), owner, sink, direct)
            return
        if f.has_top(start, end, ("==", "~=", "<", ">", "<=", ">=", "+", "-", "*", "/", "%", "#")):
            return
        if f.has_top(start, end, ("..",)):
            # A concatenation cannot translate as a whole; report English
            # literal parts that are left outside a translation.
            if shape in (STR, LIT):
                kind = None
                for piece in f.split(start, end, ("..",)):
                    first_token = tokens[piece[0]]
                    if piece[1] - piece[0] == 1 and first_token.kind == "str":
                        if is_translatable(first_token.value):
                            kind = "literal"
                            break
                    elif shape == STR and not re.search(r"\b(?:Tr|Text|BlizzardText|StatusText)\s*\(",
                                                        f.text(piece[0], piece[1])):
                        kind = kind or "variable"
                if kind:
                    self.dynamic.append((f.rel, tokens[start].line, sink, f.text(start, end), kind))
            return
        first = tokens[start]
        if end - start == 1 and first.kind == "str":
            if shape in (STR, LIT):
                self.collect(f, start, sink, direct)
            return
        if shape == LIT:
            return
        if end - start == 1:
            if first.kind == "name":
                self.resolve_name(shape, f, first.value, owner, sink, start)
            return
        if first.op("{") and f.pair.get(start) == end - 1:
            self.apply_table(shape, f, start, owner, sink)
            return
        if first.kw("function"):
            # A callback whose results reach a sink: EditLists(function() ... end)
            if shape[0] == "r":
                for d in f.defs:
                    if d.start == start:
                        self.apply_returns(d, shape[1], shape[2], sink)
            return
        if first.kind != "name" and not first.op("("):
            return
        # A postfix expression: name { .field | [index] | :method(args) | (args) }
        suffixes, k = [], start + 1
        if first.op("("):
            k = f.pair[start] + 1
        while k < end:
            t = tokens[k]
            if t.op(".") and tokens[k + 1].kind == "name":
                suffixes.append((".", tokens[k + 1].value))
                k += 2
            elif t.op("["):
                suffixes.append(("[", (k + 1, f.pair[k])))
                k = f.pair[k] + 1
            elif t.op(":") and tokens[k + 1].kind == "name":
                suffixes.append((":", tokens[k + 1].value))
                k += 2
            elif t.op("("):
                suffixes.append(("(", k))
                k = f.pair[k] + 1
            elif t.kind == "str" or t.op("{"):
                suffixes.append(("(", None))
                k = f.skip(k)
            else:
                return
        if suffixes and suffixes[-1][0] == "(":
            # ("x"):format(...) builds text at runtime; it cannot translate.
            if len(suffixes) >= 2 and suffixes[-2] == (":", "format"):
                if first.op("(") and shape == STR and tokens[start + 1].kind == "str" \
                        and is_translatable(tokens[start + 1].value):
                    self.dynamic.append((f.rel, first.line, sink, f.text(start, end), "format"))
                return
            # Any other call: what its function returns.
            if suffixes[-1][1] is not None:
                self.apply_result(shape, f, (start, end), 0, sink)
            return
        if first.op("("):
            return
        self.apply_path(shape, f, first.value, suffixes, owner, sink, start)

    def apply_result(self, shape, f, rng, index, sink):
        """Apply a shape to result `index` of the call ending at rng."""
        close = rng[1] - 1
        if not f.tokens[close].op(")"):
            return
        call = f.call_at.get(f.open_of[close])
        if call is None:
            return
        key = ("result", f.rel, rng, index, shape)
        if key in self.seen:
            return
        self.seen.add(key)
        targets = self.call_targets_of(f, call)
        if not targets and re.fullmatch(r"[A-Za-z_]\w*", call.callee):
            # A function held by a parameter or a local: its callers' functions.
            self.resolve_name(RET(index, shape), f, call.callee, call.owner, sink, call.open)
        for d in targets:
            self.apply_returns(d, index, shape, sink)

    def apply_returns(self, d, index, shape, sink):
        for values in d.returns:
            if index < len(values):
                self.apply(shape, d.file, values[index], d, sink, direct=False)

    def call_targets_of(self, f, call):
        targets = self.call_targets.get(id(call))
        if targets is None:
            targets = self.call_targets[id(call)] = self.targets(f, call)
        return targets

    def apply_path(self, shape, f, name, suffixes, owner, sink, at):
        if not suffixes:
            self.resolve_name(shape, f, name, owner, sink, at)
            return
        kind, value = suffixes[-1]
        if kind == ".":
            # rule.label, spec.title, NS.AnchorLabels: every table field and
            # assignment of that name in the addon is a sink.
            self.add_field_sink(f.addon, value, shape)
            return
        if kind == "[":
            index_tokens = f.tokens[value[0]:value[1]]
            if len(index_tokens) == 1 and index_tokens[0].kind == "num":
                inner = IDX(int(float(index_tokens[0].value)), shape)
            elif len(index_tokens) == 1 and index_tokens[0].kind == "str":
                inner = FIELD(index_tokens[0].value, shape)
            else:
                inner = LIST(shape)
            self.apply_path(inner, f, name, suffixes[:-1], owner, sink, at)

    def resolve_name(self, shape, f, name, owner, sink, at):
        scope_owner = owner
        while True:
            scope = f.scope_of(scope_owner)
            if name in scope.params and scope_owner is not None:
                self.add_param_sink(scope_owner, scope.params[name], shape)
                return
            if name in scope.loops:
                loops = scope.loops[name]
                around = [loop for loop in loops if loop[1] <= at <= loop[2]] or loops
                for expression, _, _ in around:
                    self.apply(LIST(shape), f, expression, scope_owner, sink, direct=False)
                return
            if name in scope.locals or name in scope.elements:
                for value in scope.locals.get(name, ()):
                    self.apply(shape, f, value, scope_owner, sink, direct=False)
                if shape[0] == "l":
                    for value in scope.elements.get(name, ()):
                        self.apply(shape[1], f, value, scope_owner, sink, direct=False)
                return
            if shape[0] == "r":
                found = [d for d in f.defs if d.local and d.name == name and d.parent is scope_owner]
                for d in found:
                    self.apply_returns(d, shape[1], shape[2], sink)
                if found:
                    return
            if name in scope.declared or scope_owner is None:
                return
            scope_owner = scope_owner.parent

    def apply_table(self, shape, f, open_, owner, sink):
        if shape == STR:
            return
        close = f.pair[open_]
        items = f.split(open_ + 1, close, (",", ";"))
        position = 0
        tokens = f.tokens
        for start, end in items:
            if end <= start:
                continue
            keyed = None
            if tokens[start].kind == "name" and tokens[start + 1].op("="):
                keyed, start = tokens[start].value, start + 2
            elif tokens[start].op("[") and tokens[f.pair[start] + 1].op("="):
                key_tokens = tokens[start + 1:f.pair[start]]
                keyed = key_tokens[0].value if len(key_tokens) == 1 and key_tokens[0].kind == "str" else "[]"
                start = f.pair[start] + 2
            else:
                position += 1
            kind = shape[0]
            if kind == "l":
                # Any value: X[k] reads positional and keyed entries alike.
                self.apply(shape[1], f, (start, end), owner, sink, direct=False)
            elif kind == "i" and keyed is None and position == shape[1]:
                self.apply(shape[2], f, (start, end), owner, sink, direct=False)
            elif kind == "f" and keyed == shape[1]:
                self.apply(shape[2], f, (start, end), owner, sink, direct=False)

    # the fixed point
    def run(self):
        rounds = 0
        while True:
            rounds += 1
            self.changed = False
            for f in self.files:
                for call in f.calls:
                    sinks = self.call_sinks(f, call)
                    for index, shapes in sinks.items():
                        if 0 <= index < len(call.args):
                            sink = "%s#%d" % (call.callee, index)
                            self.current = (f.rel, f.tokens[call.open].line, sink)
                            for shape in list(shapes):
                                self.apply(shape, f, call.args[index], call.owner, sink)
                table = self.field_sinks.get(f.addon, {})
                if f.addon not in (OPTIONS, CORE, RUNTIME) and RUNTIME in self.field_sinks:
                    # The shared module runtime reads its callers' tables
                    # (S.RegisterOwnedMover specs, S.Text(rule.label)).
                    merged = {k: set(v) for k, v in table.items()}
                    for k, v in self.field_sinks[RUNTIME].items():
                        merged.setdefault(k, set()).update(v)
                    table = merged
                for field, rng, owner in f.fields:
                    self.current = (f.rel, f.tokens[rng[0]].line, "field:" + field)
                    for shape in list(table.get(field, ())):
                        self.apply(shape, f, rng, owner, "field:" + field, direct=False)
                for field, rng, owner in f.field_elements:
                    self.current = (f.rel, f.tokens[rng[0]].line, "field:" + field)
                    for shape in list(table.get(field, ())):
                        if shape[0] == "l":
                            self.apply(shape[1], f, rng, owner, "field:" + field, direct=False)
                # `return false, reason`: refusal reasons are shown translated
                # (Suite.StatusText) wherever a caller displays them.
                for rng, owner in f.reasons:
                    self.current = (f.rel, f.tokens[rng[0]].line, "reason")
                    self.apply(STR, f, rng, owner, "reason", direct=False)
            if not self.changed or rounds > 40:
                break
        return self


def source_files(root):
    """Suite Lua sources that can show text through MSUF's locale table. The
    skin keeps its own locale system; Nameplates shows no translated text."""
    for folder in sorted(root.glob("MSUF_Suite*")):
        if not folder.is_dir() or folder.name.startswith("MSUF_Suite_Skin") or folder.name == "MSUF_Suite_Nameplates":
            continue
        for path in sorted(folder.rglob("*.lua")):
            parts = path.relative_to(root).parts
            if "Locales" in parts or "Libs" in parts:
                continue
            yield path


# ---------------------------------------------------------------- records
def string_id(english):
    return hashlib.sha1(english.encode("utf-8")).hexdigest()[:10]


def classify_text(english):
    """help: explanatory sentences; chrome: titles, labels, buttons, short
    statuses."""
    if len(english) >= 60:
        return "help"
    if len(english) > 30 and (english.endswith(".") or re.search(r"[.!?]\s", english)):
        return "help"
    return "chrome"


def escape_field(text):
    return text.replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n")


def unescape_field(text):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "r": "\r", "\\": "\\"}.get(m.group(1), "\\" + m.group(1)), text)


class Record:
    __slots__ = ("id", "english", "cls", "uses", "pending", "msuf")

    def used(self, limit=3):
        return "; ".join("%s %s:%d" % (sink, rel, line) for rel, line, sink in self.uses[:limit])


def extract(root=ROOT):
    """Records sorted by English text, plus the extractor for reports."""
    ex = Extractor(root).run()
    coverage = msuf_coverage()
    records = []
    for english in sorted(ex.found):
        r = Record()
        r.english, r.id, r.cls = english, string_id(english), classify_text(english)
        r.uses = sorted(ex.found[english])
        r.pending = all(rel in DELTA_PENDING for rel, _, _ in r.uses)
        r.msuf = [loc for loc in LOCALES if english in coverage[loc]]
        records.append(r)
    return records, ex


# ---------------------------------------------------------------- MSUF packs
def pack_keys(source):
    """English keys a host locale pack defines: L["key"] = "value"."""
    tokens, keys = lex(source), set()
    for k in range(len(tokens) - 5):
        t = tokens[k]
        if t.kind == "name" and t.value == "L" and tokens[k + 1].op("[") and tokens[k + 2].kind == "str" \
                and tokens[k + 3].op("]") and tokens[k + 4].op("=") and tokens[k + 5].kind == "str":
            keys.add(tokens[k + 2].value)
    return keys


def pack_entries(source):
    tokens, entries = lex(source), {}
    for k in range(len(tokens) - 5):
        t = tokens[k]
        if t.kind == "name" and t.value == "L" and tokens[k + 1].op("[") and tokens[k + 2].kind == "str" \
                and tokens[k + 3].op("]") and tokens[k + 4].op("=") and tokens[k + 5].kind == "str":
            entries[tokens[k + 2].value] = tokens[k + 5].value
    return entries


def host_pack_source(host, locale):
    """A host pack as latin-1 text: the Classic checkout's file, or the Main
    (Retail) repository's committed file, read with `git show` only."""
    rel = "MidnightSimpleUnitFrames/Locales/%s.lua" % locale
    if host == "classic":
        path = HOST_CLASSIC / rel
        return path.read_bytes().decode("latin-1") if path.is_file() else None
    if not (HOST_MAIN / ".git").exists():
        return None
    run = subprocess.run(["git", "-C", str(HOST_MAIN), "show", "HEAD:" + rel], capture_output=True)
    return run.stdout.decode("latin-1") if run.returncode == 0 else None


_COVERAGE = {}


def msuf_coverage():
    """{locale: keys MSUF translates on both hosts}. A key only one host has
    stays the Suite's to translate (its entry never overwrites MSUF's)."""
    if _COVERAGE:
        return _COVERAGE
    for locale in LOCALES:
        sets = []
        for host in ("classic", "main"):
            source = host_pack_source(host, locale)
            if source is not None:
                sets.append(pack_keys(source))
        _COVERAGE[locale] = set.intersection(*sets) if sets else set()
    return _COVERAGE


def msuf_translations(locale):
    source = host_pack_source("classic", locale)
    return pack_entries(source) if source else {}


# ---------------------------------------------------------------- Suite locale files
HEADER = """-- MSUF Suite: {name} ({locale}) text for the Suite's English UI strings.
-- Maintained with tools/suite_locale_tool.py (missing / apply / verify);
-- one T(english, translation) line per string, sorted by the English text.
local MSUF = _G.MSUF_NS or _G.MSUF
if not MSUF or MSUF.LOCALE ~= "{locale}" then return end
local L = MSUF.RegisterLocale and MSUF.RegisterLocale("{locale}") or MSUF.L
if type(L) ~= "table" then return end
-- MSUF's own translation of a string always wins.
local function T(english, text)
    if rawget(L, english) == nil then L[english] = text end
end

"""
LOCALE_NAMES = {"deDE": "German", "esES": "Spanish (EU)", "esMX": "Spanish (Latin America)", "frFR": "French",
                "itIT": "Italian", "koKR": "Korean", "ptBR": "Portuguese (Brazil)", "ruRU": "Russian",
                "zhCN": "Simplified Chinese", "zhTW": "Traditional Chinese"}


def locale_path(locale):
    return LOCALE_DIR / ("%s.lua" % locale)


def locale_pairs(source):
    """(english, translation, line) of every T(...) entry, in file order."""
    tokens, pairs = lex(source), []
    for k in range(len(tokens) - 5):
        if tokens[k].kind == "name" and tokens[k].value == "T" and tokens[k + 1].op("(") \
                and tokens[k + 2].kind == "str" and tokens[k + 3].op(",") and tokens[k + 4].kind == "str" \
                and tokens[k + 5].op(")"):
            pairs.append((tokens[k + 2].value, tokens[k + 4].value, tokens[k].line))
    return pairs


def read_locale(locale):
    """{english: translation} of a Suite locale file (empty when absent).
    Like the runtime's T(), the first entry of a key wins."""
    path = locale_path(locale)
    if not path.is_file():
        return {}
    entries = {}
    for english, text, _ in locale_pairs(read_source(path)):
        entries.setdefault(english, text)
    return entries


def lua_quote(text):
    out = ['"']
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append("\\%03d" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def write_locale(locale, entries):
    lines = [HEADER.format(name=LOCALE_NAMES[locale], locale=locale)]
    for english in sorted(entries):
        lines.append("T(%s, %s)\n" % (lua_quote(english), lua_quote(entries[english])))
    data = "".join(lines).encode("utf-8")
    LOCALE_DIR.mkdir(parents=True, exist_ok=True)
    locale_path(locale).write_bytes(data)


# ---------------------------------------------------------------- checks
SPECIFIER = re.compile(r"%(?:%|[-+ #0]*\d*(?:\.\d+)?[a-zA-Z])")
CJK = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\u3000-\u303f\uff00-\uffef]")
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
HANGUL = re.compile(r"[\uac00-\ud7af\u1100-\u11ff\u3130-\u318f]")
CYRILLIC = re.compile(r"[\u0400-\u04ff]")
LATIN_LOCALES = ("deDE", "esES", "esMX", "frFR", "itIT", "ptBR")
# Words that stay as they are in every language: product and addon names,
# Blizzard's own English acronyms, units. English made only of these (plus
# numbers, ALL-CAPS abbreviations and punctuation) is proper-noun-like.
PROPER_WORDS = {
    "msuf", "suite", "forever", "midnight", "blue", "dark", "modern", "elvui", "bartender4", "dominos",
    "ellesmereuiactionbars", "arkinventory", "bagnon", "baganator", "adibags", "inventorian", "details",
    "skada", "recount", "prat", "chattynator", "sexymap", "basicminimap", "minimapbuttonbag",
    "midnightcooldownmanager", "cooldownmanagercentered", "mapkoskin", "mapko", "midnightskin", "jundies", "slug",
    "px", "ctrl", "shift", "alt", "wow", "blizzard", "edit", "mode", "datatexts", "antique", "footer",
}


def specifiers(text):
    return [s for s in SPECIFIER.findall(text) if s != "%%"] + ["%%"] * text.count("%%")


# One token per percent use: "%%", a specifier, or a lone "%". Text with a
# specifier goes through string.format, where a lone "%" raises; plain labels
# may show a percent sign as it is.
PERCENT = re.compile(r"%%|%[-+ #0]*\d*(?:\.\d+)?[a-zA-Z]|%")
# WoW escape sequences; || shows a pipe. A pipe before one of the escape
# letters that is no complete sequence is stray: the client reads |h as a
# link end and |r as a color reset, so "tank|healer" shows "tankealer".
ESCAPE = re.compile(r"\|\||\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t|\|A[^|]*\|a|\|H[^|]*\|h[^|]*\|h|\|n|\|K[^|]*\|k|\|")
COMPLETE_ESCAPE = re.compile(r"\|\||\|c[0-9a-fA-F]{8}|\|T[^|]*\|t|\|A[^|]*\|a|\|H[^|]*\|h[^|]*\|h|\|n|\|K[^|]*\|k")
ESCAPE_LETTERS = "cCrRhHtTaAkKn"
FULL_WIDTH_END = ("\uff1a", "\u3002", "\uff0c", "\uff01", "\uff1f")


def lone_percents(text):
    return sum(1 for token in PERCENT.findall(text) if token == "%")


def escape_kinds(text):
    """The escape sequences of a text by kind; a stray pipe is kind '|'."""
    kinds = []
    for token in ESCAPE.findall(text):
        kinds.append(token[:2] if len(token) > 1 else "|")
    return sorted(kinds)


def stray_pipes(text):
    """Pipes the client would read as an escape the text does not mean: one
    before an escape letter that starts no complete sequence, and a color
    reset without a color."""
    stray, index, colors = 0, text.find("|"), 0
    while index >= 0:
        match = COMPLETE_ESCAPE.match(text, index)
        if match:
            colors += match.group(0).startswith("|c")
            index = text.find("|", match.end())
            continue
        following = text[index + 1:index + 2]
        if following in ("r", "R") and colors > 0:
            colors -= 1
        elif following and following in ESCAPE_LETTERS:
            stray += 1
        index = text.find("|", index + 1)
    return stray


def english_problems(english):
    """Problems of an English source string itself."""
    problems = []
    if stray_pipes(english):
        problems.append("a pipe the client reads as an escape (|h ends a link, |r resets color; || shows a pipe)")
    if specifiers(english) and lone_percents(english):
        problems.append("a lone % in a format string breaks string.format (write %%)")
    return problems


def proper_noun_like(english):
    stripped = re.sub(r"\|c[0-9a-fA-F]{8}|\|r|%[-+ #0]*\d*(?:\.\d+)?[a-zA-Z%]", " ", english)
    for word in re.findall(r"[A-Za-z][A-Za-z0-9']*", stripped):
        if word.lower() in PROPER_WORDS or re.fullmatch(r"[A-Z0-9]{2,}s?", word):
            continue
        return False
    return True


def check_entry(locale, english, text):
    """Problems of one translation (empty list when fine)."""
    problems = []
    if not text.strip():
        return ["empty translation"]
    if specifiers(english) != specifiers(text):
        problems.append("format specifiers %s differ from the English %s" % (specifiers(text), specifiers(english)))
    if re.search(r"%\d+\$", text):
        problems.append("positional specifiers (%1$s) do not exist in Lua 5.1")
    if text.count("|r") != english.count("|r") or len(re.findall(r"\|c[0-9a-fA-F]{8}", text)) != \
            len(re.findall(r"\|c[0-9a-fA-F]{8}", english)):
        problems.append("color codes differ from the English")
    if re.findall(r"\|T[^|]*\|t", text) != re.findall(r"\|T[^|]*\|t", english):
        problems.append("icon escapes differ from the English")
    if specifiers(english) and lone_percents(text):
        problems.append("a lone % in a format string breaks string.format (write %%)")
    if escape_kinds(text) != escape_kinds(english) or stray_pipes(text) != stray_pipes(english):
        problems.append("escape sequences or pipes differ from the English (|| shows a pipe)")
    if english.endswith(" ") and not text.endswith(" ") and not text.endswith(FULL_WIDTH_END):
        problems.append("the English ends with a space that joins the next text; the translation does not")
    if locale in LATIN_LOCALES:
        if CJK.search(text) or HANGUL.search(text) or CYRILLIC.search(text):
            problems.append("CJK, Hangul or Cyrillic characters in a Latin-script locale")
        if text == english and len(english.split()) >= 3 and not proper_noun_like(english):
            problems.append("identical to the English text")
    elif locale == "ruRU":
        if CJK.search(text) or HANGUL.search(text):
            problems.append("CJK or Hangul characters in Russian")
        if not CYRILLIC.search(text) and not proper_noun_like(english):
            problems.append("no Cyrillic text although the English is no proper name")
    elif locale == "koKR":
        if CYRILLIC.search(text):
            problems.append("Cyrillic characters in Korean")
        if not HANGUL.search(text) and not proper_noun_like(english):
            problems.append("no Hangul text although the English is no proper name")
    else:
        if CYRILLIC.search(text) or HANGUL.search(text):
            problems.append("Cyrillic or Hangul characters in Chinese")
        if not HAN.search(text) and not proper_noun_like(english):
            problems.append("no Chinese text although the English is no proper name")
    return problems


def coverage(records, locale, entries):
    """(chrome covered, chrome total, help covered, help total) over the
    strings that are not waiting for a delta pass."""
    counts = {"chrome": [0, 0], "help": [0, 0]}
    for r in records:
        if r.pending:
            continue
        slot = counts[r.cls]
        slot[1] += 1
        if locale in r.msuf or r.english in entries:
            slot[0] += 1
    return counts["chrome"][0], counts["chrome"][1], counts["help"][0], counts["help"][1]


def verify(records, quiet=False):
    problems = []
    english_set = {r.english for r in records}
    for r in records:
        for problem in english_problems(r.english):
            problems.append("English %r (%s): %s" % (r.english, r.used(1), problem))
    for locale in LOCALES:
        path = locale_path(locale)
        if not path.is_file():
            problems.append("%s: MSUF_Suite/Locales/%s.lua is missing" % (locale, locale))
            continue
        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            problems.append("%s: the file starts with a byte order mark" % locale)
        try:
            raw.decode("utf-8")
        except UnicodeDecodeError as error:
            problems.append("%s: invalid UTF-8 at byte %d" % (locale, error.start))
        seen = {}
        for english, _, line in locale_pairs(read_source(path)):
            if english in seen:
                problems.append("%s:%d: %r is listed again (line %d); the runtime keeps the first"
                                % (locale, line, english, seen[english]))
            else:
                seen[english] = line
        head = HEADER.format(name=LOCALE_NAMES[locale], locale=locale).encode("utf-8")
        if not raw.startswith(head):
            problems.append("%s: the header (namespace, locale guard, T helper) differs from the tool's" % locale)
        entries = read_locale(locale)
        for english, text in sorted(entries.items()):
            if english not in english_set:
                problems.append("%s: %r is no current Suite string (removed or renamed?)" % (locale, english))
                continue
            for problem in check_entry(locale, english, text):
                problems.append("%s: %r: %s" % (locale, english, problem))
        chrome, chrome_total, help_, help_total = coverage(records, locale, entries)
        if chrome_total and chrome / chrome_total < CHROME_MIN:
            problems.append("%s: chrome coverage %d/%d (%.1f%%) is below %d%%"
                            % (locale, chrome, chrome_total, 100.0 * chrome / chrome_total, CHROME_MIN * 100))
        if help_total and help_ / help_total < HELP_MIN:
            problems.append("%s: help coverage %d/%d (%.1f%%) is below %d%%"
                            % (locale, help_, help_total, 100.0 * help_ / help_total, HELP_MIN * 100))
        if not quiet:
            shadowed = sum(1 for r in records if locale in r.msuf and r.english in entries)
            pending = sum(1 for r in records if r.pending and locale not in r.msuf and r.english not in entries)
            print("%s: %d entries; chrome %d/%d, help %d/%d; %d waiting for a delta pass; %d shadowed by MSUF's pack"
                  % (locale, len(entries), chrome, chrome_total, help_, help_total, pending, shadowed))
    return problems


# ---------------------------------------------------------------- commands
def write_tsv(records, stream):
    """Columns: id, class (+pending while a delta pass is due), english
    (\\n, \\t and \\\\ escaped), msuf (locales MSUF's packs already cover),
    proper (1: proper names and abbreviations only, may stay Latin), used."""
    stream.write("id\tclass\tenglish\tmsuf\tproper\tused\n")
    for r in records:
        cls = r.cls + ("+pending" if r.pending else "")
        stream.write("%s\t%s\t%s\t%s\t%d\t%s\n" % (r.id, cls, escape_field(r.english), ",".join(r.msuf),
                                                 1 if proper_noun_like(r.english) else 0, r.used()))


def option(args, name, default=None):
    if name in args:
        index = args.index(name)
        if index + 1 < len(args):
            return args[index + 1]
    return default


def cmd_extract(args):
    records, _ = extract()
    target = option(args, "--tsv") or option(args, "--out")
    if target == "-":
        write_tsv(records, sys.stdout)
        return 0
    path = Path(target) if target else DEFAULT_OUT
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as stream:
        write_tsv(records, stream)
    chrome = sum(1 for r in records if r.cls == "chrome")
    print("%d strings (%d chrome, %d help, %d waiting for a delta pass) -> %s"
          % (len(records), chrome, len(records) - chrome, sum(1 for r in records if r.pending), path))
    return 0


def missing_entries(records, locale, wanted_class=None):
    entries = read_locale(locale)
    out = []
    for r in records:
        if locale in r.msuf or r.english in entries:
            continue
        if wanted_class and r.cls != wanted_class:
            continue
        out.append(r)
    return out


def cmd_missing(args):
    records, _ = extract()
    locale = option(args, "--locale", "all")
    locales = LOCALES if locale == "all" else (locale,)
    if any(loc not in LOCALES for loc in locales):
        print("unknown locale %s; use one of %s or all" % (locale, ", ".join(LOCALES)))
        return 2
    fmt, wanted = option(args, "--format", "tsv"), option(args, "--class")
    per = {loc: missing_entries(records, loc, wanted) for loc in locales}
    if fmt == "json":
        merged = {}
        for loc in locales:
            for r in per[loc]:
                entry = merged.setdefault(r.id, {"id": r.id, "class": r.cls, "english": r.english,
                                                 "pending": r.pending, "used": r.used(), "locales": []})
                entry["locales"].append(loc)
        json.dump({"locales": list(locales), "strings": list(merged.values())}, sys.stdout, ensure_ascii=False, indent=1)
        sys.stdout.write("\n")
        return 0
    sys.stdout.write("locale\tid\tclass\tenglish\tused\n")
    for loc in locales:
        for r in per[loc]:
            sys.stdout.write("%s\t%s\t%s\t%s\t%s\n" % (loc, r.id, r.cls, escape_field(r.english), r.used()))
    return 0


def read_batch(path, locale):
    """{id: translation} from a TSV (id<TAB>translation) or the JSON of
    `missing` with a translation per entry (a string, or {locale: text})."""
    text = Path(path).read_text(encoding="utf-8-sig")
    out = {}
    if text.lstrip().startswith("{") or text.lstrip().startswith("["):
        data = json.loads(text)
        items = data["strings"] if isinstance(data, dict) else data
        for item in items:
            value = item.get("translation")
            if isinstance(value, dict):
                value = value.get(locale)
            if isinstance(value, str):
                out[item["id"]] = value
        return out
    for line in text.splitlines():
        if not line.strip() or line.startswith("#") or line.startswith("id\t"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            raise ValueError("line without a tab: %r" % line)
        out[parts[0].strip()] = unescape_field(parts[-1])
    return out


def cmd_apply(args):
    locale, source = option(args, "--locale"), option(args, "--input")
    if locale not in LOCALES or not source:
        print("usage: apply --locale <%s> --input FILE [--replace]" % "|".join(LOCALES))
        return 2
    records, _ = extract()
    by_id = {r.id: r for r in records}
    batch = read_batch(source, locale)
    entries = read_locale(locale)
    replace = "--replace" in args
    problems, added, replaced, skipped, msuf = [], 0, 0, 0, 0
    for sid, text in batch.items():
        r = by_id.get(sid)
        if r is None:
            problems.append("%s: unknown id (re-run `missing`)" % sid)
            continue
        if locale in r.msuf:
            # MSUF's own packs translate it; the pack never redefines their keys.
            msuf += 1
            continue
        found = check_entry(locale, r.english, text)
        if found:
            problems.extend("%s %r: %s" % (sid, r.english, p) for p in found)
            continue
        if r.english in entries and entries[r.english] != text:
            if not replace:
                skipped += 1
                continue
            replaced += 1
        elif r.english not in entries:
            added += 1
        entries[r.english] = text
    for problem in problems:
        print("REJECTED " + problem)
    write_locale(locale, entries)
    print("%s: %d added, %d replaced, %d kept (use --replace), %d left to MSUF's pack, %d rejected; %d entries"
          % (locale, added, replaced, skipped, msuf, len(problems), len(entries)))
    return 1 if problems else 0


def cmd_verify(args):
    records, _ = extract()
    problems = verify(records, quiet="--quiet" in args)
    for problem in problems:
        print("FAIL " + problem)
    print("suite locales: %d strings, %d locale files, %d problems" % (len(records), len(LOCALES), len(problems)))
    return 1 if problems else 0


def cmd_dynamic(args):
    """Text built at runtime that reaches a translation as a whole: `literal`
    has English parts outside a translation (make it a format key),
    `variable` joins values that may be untranslated, `format` formats an
    English literal before translating it. Use --all for `variable` too."""
    _, ex = extract()
    seen = set()
    for rel, line, sink, expression, kind in sorted(ex.dynamic):
        if (rel, line, expression) in seen or (kind == "variable" and "--all" not in args):
            continue
        seen.add((rel, line, expression))
        print("%s:%d\t%s\t%s\t%s" % (rel, line, kind, sink, expression))
    return 0


NON_UI_CALLS = re.compile(
    r"(?:SetScript|HookScript|GetScript|SetPoint|CreateFrame|CreateTexture|CreateFontString|RegisterEvent|"
    r"UnregisterEvent|hooksecurefunc|RegisterForClicks|SetAttribute|GetAttribute|SetCVar|GetCVar|assert|error|"
    r"SetTexture|SetAtlas|CreateAnimation|IsAddOnLoaded|AddOnEnabled|LoadAddOn|:match|:find|:gsub|:sub|"
    r"P\.Get|P\.Set|P\.Meta|S\.Config|SectionRules|ResetPrefix|OpenEditMode|MoveOnScreen|Property|Tuple|"
    r"SetFont|SetJustify\w|SetDrawLayer|SetBlendMode|RegisterUnitEvent|Frame|Global|Install)", re.I)


def cmd_orphans(args):
    """English-looking literals that no sink reaches, for review."""
    records, ex = extract()
    known = {r.english for r in records}
    for f in ex.files:
        inner = {}
        for call in f.calls:
            for index, (start, end) in enumerate(call.args):
                for k in range(start, end):
                    inner[k] = "%s#%d" % (call.callee, index)
        for k, t in enumerate(f.tokens):
            if t.kind != "str" or t.value in known or not is_translatable(t.value) or identifier_like(t.value):
                continue
            if not (" " in t.value or re.match(r"[A-Z][a-z]", t.value)):
                continue
            prev, nxt = f.tokens[k - 1], f.tokens[k + 1]
            if prev.op("==", "~=", "[") or nxt.op("==", "~="):
                continue
            context = inner.get(k, "-")
            if NON_UI_CALLS.search(context):
                continue
            print("%s:%d\t%s\t%r" % (f.rel, t.line, context, t.value))
    return 0


def cmd_sinks(args):
    """Every discovered sink with the place that made it one (debug aid)."""
    _, ex = extract()
    for key, where in sorted(ex.why.items(), key=str):
        print("%s\t%s" % (key, where))
    return 0


def cmd_glossary(args):
    terms = [a for a in args if not a.startswith("--")]
    packs = {loc: msuf_translations(loc) for loc in LOCALES}
    for term in terms:
        print("== %s" % term)
        for loc in LOCALES:
            pack = packs[loc]
            exact = pack.get(term)
            if exact is not None:
                print("  %s  %s" % (loc, exact))
                continue
            near = [(k, v) for k, v in pack.items() if re.search(r"\b%s\b" % re.escape(term), k, re.I)][:3]
            print("  %s  ~ %s" % (loc, " | ".join("%s = %s" % kv for kv in near)))
    return 0


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    if not argv:
        print(__doc__)
        return 2
    commands = {"extract": cmd_extract, "missing": cmd_missing, "apply": cmd_apply, "verify": cmd_verify,
                "dynamic": cmd_dynamic, "orphans": cmd_orphans, "glossary": cmd_glossary, "sinks": cmd_sinks}
    command = commands.get(argv[0])
    if not command:
        print(__doc__)
        return 2
    return command(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
