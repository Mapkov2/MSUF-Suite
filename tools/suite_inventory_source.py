"""Static inventory of Suite interfaces outside the executable catalog.

Lua is tokenized by the locale tool so comments and string contents cannot
masquerade as declarations. Dynamic mover families are expanded from their
catalog and source bounds; unknown registration expressions fail closed.
"""

import json
import os
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from suite_locale_tool import lex, read_source


def source_paths(root):
    for addon in sorted(root.glob("MSUF_Suite*")):
        if not addon.is_dir() or addon.is_symlink() or addon.is_junction():
            continue
        for folder, dirs, files in os.walk(addon, followlinks=False):
            dirs[:] = sorted(d for d in dirs if d not in ("Libs", "Locales")
                             and not (Path(folder) / d).is_junction())
            for name in sorted(files):
                path = Path(folder) / name
                if path.suffix in (".lua", ".xml", ".toc") and not path.is_symlink():
                    yield path


def render(tokens):
    return " ".join(json.dumps(t.value, ensure_ascii=False) if t.kind == "str" else t.value for t in tokens)


def split_arguments(tokens, start):
    """Top-level comma-separated values inside the opening bracket at start."""
    depth, parts, current = 0, [], []
    for token in tokens[start + 1:]:
        if token.op(")", "}", "]"):
            if depth == 0:
                return parts + [current]
            depth -= 1
        if token.op("(", "{", "["):
            depth += 1
        if token.op(",") and depth == 0:
            parts.append(current)
            current = []
        else:
            current.append(token)
    raise ValueError("unclosed Lua argument list")


def literal_bindings(tokens):
    """Resolve local literal lists, including `local ID, M = 'id', {}`."""
    values = {}
    for index, token in enumerate(tokens):
        if not token.kw("local"):
            continue
        pos, names = index + 1, []
        while pos < len(tokens) and tokens[pos].kind == "name":
            names.append(tokens[pos].value)
            pos += 1
            if not tokens[pos].op(","):
                break
            pos += 1
        if not names or not tokens[pos].op("="):
            continue
        pos += 1
        for name in names:
            token = tokens[pos]
            if token.kind not in ("str", "num"):
                break
            if token.kind == "str":
                values[name] = token.value
            else:
                values[name] = int(token.value, 16) if token.value.lower().startswith("0x") else float(token.value)
            pos += 1
            if pos >= len(tokens) or not tokens[pos].op(","):
                break
            pos += 1
    return values


def scalar(tokens, values):
    if len(tokens) == 1:
        token = tokens[0]
        if token.kind == "str":
            return token.value
        return values.get(token.value)
    return None


def exports(tokens, inventory):
    for i in range(len(tokens) - 3):
        if tokens[i].value != "S":
            continue
        end, name = i + 3, None
        if tokens[i + 1].op(".", ":") and tokens[i + 2].kind == "name":
            name = tokens[i + 2].value
        elif tokens[i + 1].op("[") and tokens[i + 2].kind == "str" and tokens[i + 3].op("]"):
            name, end = tokens[i + 2].value, i + 4
        if not name or end >= len(tokens):
            continue
        assignment = tokens[end].op("=") and tokens[end + 1].value != "nil"
        tail = end
        while tail + 3 < len(tokens) and tokens[tail].op(","):
            if tokens[tail + 1].value != "S" or not tokens[tail + 2].op("."):
                break
            tail += 4
        assignment = assignment or (tail > end and tail < len(tokens) and tokens[tail].op("="))
        declaration = i > 0 and tokens[i - 1].kw("function")
        if assignment or declaration:
            inventory.add("S." + name)
    # Public state fields created with the Suite table itself.
    for i in range(len(tokens) - 3):
        if render(tokens[i:i + 4]) == "local S = {":
            for field in split_arguments(tokens, i + 3):
                if len(field) >= 3 and field[0].kind == "name" and field[1].op("="):
                    inventory.add("S." + field[0].value)


def slash_commands(tokens, values, inventory):
    for i, token in enumerate(tokens):
        if token.value.startswith("SLASH_") and i + 2 < len(tokens):
            end = i + 1
            if tokens[end].op("]"):
                end += 1
            if tokens[end].op("=") and tokens[end + 1].kind == "str":
                inventory.add(tokens[end + 1].value)
        if (token.value == "RegisterSlash" and i + 1 < len(tokens) and tokens[i + 1].op("(")
                and not (i >= 3 and tokens[i - 3].kw("function"))):
            args = split_arguments(tokens, i + 1)
            for arg in args[2:]:
                command = scalar(arg, values)
                if not isinstance(command, str) or not command.startswith("/"):
                    raise ValueError("unresolved slash alias: " + render(arg))
                inventory.add(command)


def saved_keys(code, tokens, path, inventory):
    """Root fields, not profile leaves (catalog rules cover those separately)."""
    skin = path.parts[0].startswith("MSUF_Suite_Skin")
    default = "MSUFSuiteSkinDB" if skin else "MSUFSuiteDB"
    if "RootDB" not in code and "MSUFSuite" not in code and not path.name.startswith("Database"):
        return
    aliases = {"NS . RootDB": default, "Suite . RootDB": default}
    for name in re.findall(r"\bMSUFSuite\w*(?:DB|History|Looks)\b", code):
        aliases[name] = name
        aliases["_G . " + name] = name
    if path.name.startswith("Database"):
        aliases.update(root=default, stored=default)
    # Follow direct local aliases and assignments to the saved globals, in
    # both directions. Limit to simple names, never nested profile tables.
    for _ in range(4):
        for expression, owner in list(aliases.items()):
            for match in re.finditer(r"\blocal ([\w ,]+) = ([^\n]+)", code):
                names = match[1].split(" , ")
                rhs = match[2].split(" , ")
                for name, value in zip(names, rhs):
                    if value.strip() == expression:
                        aliases[name.strip()] = owner
            for name in re.findall(r"(?<![\w.])" + re.escape(expression) + r" = (\w+)\b(?!\s*[.\[(])", code):
                if name not in ("nil", "true", "false"):
                    aliases[name] = owner
    literals = literal_bindings(tokens)
    for expression, owner in aliases.items():
        for key in re.findall(r"(?<![\w.])" + re.escape(expression) + r" \. (\w+)", code):
            inventory.add(owner + "." + key)
        for key in re.findall(r"(?<![\w.])" + re.escape(expression) + r' \[ "([^"\\]+)" \]', code):
            inventory.add(owner + "." + key)
        for name, key in literals.items():
            if not isinstance(key, str):
                continue
            if (expression + " [ " + name + " ]" in code
                    or "Table ( " + expression + " , " + name + " )" in code):
                inventory.add(owner + "." + key)
        for index, token in enumerate(tokens[:-2]):
            if token.value == expression and tokens[index + 1].op("=") and tokens[index + 2].op("{"):
                for field in split_arguments(tokens, index + 2):
                    if len(field) >= 3 and field[0].kind == "name" and field[1].op("="):
                        inventory.add(owner + "." + field[0].value)
    # Migration lists copy root[key]; preserve their literal source keys.
    if "historyKeys" in code and "root [ key ]" in code:
        match = re.search(r"local historyKeys = \{(.*?)\}", code)
        if match:
            inventory.update(default + "." + key for key in re.findall(r'"([^"\\]+)"', match[1]))


def mover_ids(tokens, values, code, addon_code, constants, inventory):
    for index, token in enumerate(tokens):
        if token.value != "RegisterOwnedMover" or not tokens[index + 1].op("("):
            continue
        if index >= 3 and tokens[index - 3].kw("function"):
            continue
        args = split_arguments(tokens, index + 1)
        owner = scalar(args[0], values)
        if render(args[0]) == "self . id":
            installs = re.findall(r'S \. Install \( "([^"\\]+)"', addon_code)
            if len(set(installs)) == 1:
                owner = installs[0]
        if not isinstance(owner, str):
            raise ValueError("unresolved mover owner: " + render(args[0]))
        value = scalar(args[1], values)
        if isinstance(value, str):
            ids = [value]
        else:
            preceding = render(tokens[:index])
            boundary = preceding.rfind("function ")
            ids = dynamic_movers(owner, args[1], preceding[boundary + 1:], code, addon_code, constants)
        inventory.update("MSUFSuite." + owner + ":" + name for name in ids)
    # The skin registers directly with the host API.
    for index, token in enumerate(tokens):
        if token.value != "RegisterElement" or not tokens[index + 1].op("("):
            continue
        args = split_arguments(tokens, index + 1)
        owner = scalar(args[0], values)
        if owner and "EDIT_ID" in values and re.search(r"\bid = EDIT_ID\b", code):
            inventory.add(owner + ":" + str(values["EDIT_ID"]))


def dynamic_movers(owner, expression, preceding, code, addon_code, constants):
    text = render(expression)
    if text == "SLOTS [ i ] . key":
        if not re.search(r"for i = 1 , # SLOTS do", preceding):
            raise ValueError("unrecognized slot mover loop")
        return constants["CDMSlots"]
    if text == "list [ i ] . elementID":
        prefix = re.search(r'elementID = "([^"\\]+)" \.\. i', code)
        bound = re.search(r"\bMAX = (\d+)\b", addon_code)
        if prefix and bound and "for i = 1 , D . MAX do" in preceding:
            return [prefix[1] + str(i) for i in range(1, int(bound[1]) + 1)]
    if len(expression) == 3 and expression[0].kind == "str" and expression[1].op(".."):
        prefix, variable = expression[0].value, expression[2].value
        loops = list(re.finditer(r"for " + variable + r" = (\d+) , ([\w .]+?) do", preceding))
        if loops:
            start, bound = int(loops[-1][1]), loops[-1][2]
            if bound.isdigit():
                limit = int(bound)
            elif bound in ("AB . BAR_COUNT", "BAR_COUNT"):
                found = re.search(r"\bBAR_COUNT = (\d+)\b", addon_code)
                limit = int(found[1]) if found else constants["ActionBarCount"]
            else:
                raise ValueError("unresolved mover loop bound: " + bound)
            return [prefix + str(i) for i in range(start, limit + 1)]
        if owner == "dataTexts" and re.search(r"ipairs \( (?:module|self) \. barIDs \)", preceding):
            return [prefix + str(i) for i in range(1, constants["DataTextBarLimit"] + 1)]
    if len(expression) == 1:
        loops = list(re.finditer(r"for _ , " + re.escape(text) + r" in ipairs \( \{(.*?)\} \) do", preceding))
        if loops:
            return re.findall(r'"([^"\\]+)"', loops[-1][1])
    raise ValueError("unresolved mover ID: " + owner + " " + text)


def source_inventory(root, inventory, constants):
    files = []
    addon_sources = {}
    for path in source_paths(root):
        rel = path.relative_to(root)
        if path.suffix == ".xml":
            tree = ET.fromstring(path.read_bytes())
            inventory["bindings"].update(node.attrib["name"] for node in tree.iter()
                                         if node.tag.rsplit("}", 1)[-1] == "Binding" and "name" in node.attrib)
        elif path.suffix == ".toc":
            text = path.read_text(encoding="utf-8-sig")
            for kind, names in re.findall(r"^## (SavedVariables(?:PerCharacter)?):\s*(.+)$", text, re.M):
                inventory["saved_variables"].update(kind + ":" + name.strip() for name in names.split(","))
        else:
            tokens = [token for token in lex(read_source(path)) if token.value is not None]
            # Keep statement line boundaries for simple saved-root aliases.
            lines = {}
            for token in tokens:
                lines.setdefault(token.line, []).append(token)
            code = "\n".join(render(line) for line in lines.values())
            files.append((rel, tokens, code))
            addon_sources.setdefault(rel.parts[0], []).append(code)
    for path, tokens, code in files:
        values = literal_bindings(tokens)
        exports(tokens, inventory["exports"])
        slash_commands(tokens, values, inventory["slash"])
        saved_keys(code, tokens, path, inventory["saved_variables"])
        mover_ids(tokens, values, code, "\n".join(addon_sources[path.parts[0]]), constants, inventory["movers"])
