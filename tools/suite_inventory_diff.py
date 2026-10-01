"""Compares the user-visible settings surface of two Suite trees.

Usage (from the Suite root; Python 3.12 and the Lua 5.1 interpreter):
  python tools/suite_inventory_diff.py BEFORE_ROOT [AFTER_ROOT] [--client retail|forever|both]

BEFORE_ROOT is another checkout or an extracted snapshot, for example
`git archive <rev> | tar -x -C <dir>`. AFTER_ROOT defaults to this tree.

Reports, per client:
  * catalog modules added, removed or retitled;
  * catalog rules removed and added per module (key, section, label, kind);
  * rules whose label, kind, choices, range or hidden flag changed;
  * key binding names (MSUF_Suite/Bindings.xml) removed or added;
  * slash commands ("/name" literals next to SLASH_ or RegisterSlash) removed
    or added.
A removed rule or binding is not proof of a removed feature: check whether an
added rule took its function (renamed or replaced) before calling it removed.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LUA = r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe"

# Loads SuiteCatalog.lua and every catalog file the core TOC lists after it
# (up to Core\Suite.lua) with permissive client stubs, then prints one line
# per module and per rule.
DUMPER = r'''
local root, client = arg[1], arg[2]
local function permissive(name)
    return setmetatable({}, {
        __index = function(_, k) return permissive(name .. "." .. tostring(k)) end,
        __call = function() return nil end,
    })
end
setmetatable(_G, { __index = function(_, k) return permissive(k) end })
UnitClass = function() return "Warrior", "WARRIOR" end
C_ClassColor = { GetClassColor = function() return { r = 1, g = .5, b = .2 } end }
local ns = { Client = { isForever = client == "forever", isRetail = client ~= "forever" },
    Text = function(text) return text end, Defaults = {} }
setmetatable(ns, { __index = function(_, k) return permissive("NS." .. k) end })
local toc = assert(io.open(root .. "/MSUF_Suite/MSUF_Suite_Mainline.toc", "rb")):read("*a")
local started = false
for line in toc:gmatch("[^\r\n]+") do
    local file = line:match("^(Core\\[%w\\]+%.lua)$")
    if file then
        if file == "Core\\SuiteCatalog.lua" then started = true end
        if started then
            if file == "Core\\Suite.lua" then break end
            local chunk, err = loadfile(root .. "/MSUF_Suite/" .. file:gsub("\\", "/"))
            if not chunk then io.stderr:write("load " .. file .. ": " .. tostring(err) .. "\n")
            else
                local ok, failure = xpcall(function() chunk("MSUF_Suite", ns) end, debug.traceback)
                if not ok then io.stderr:write("run " .. file .. ": " .. tostring(failure) .. "\n") end
            end
        end
    end
end
local catalog, order = rawget(ns, "SuiteCatalog"), rawget(ns, "SuiteOrder")
for i = 1, #order do
    local id = order[i]
    local spec = catalog[id]
    print(table.concat({ "M", id, tostring(spec.title), tostring(spec.page) }, "\t"))
    for j = 1, #spec.controls do
        local rule = spec.controls[j]
        local kind = rule.choices and ("choice" .. #rule.choices) or rule.color and "color" or rule.font and "font"
            or rule.texture and "texture" or type(rule.default)
        print(table.concat({ "R", id, rule.key, tostring(rule.section), tostring(rule.label), kind,
            tostring(rule.hidden or ""), rule.choices and table.concat(rule.choices, "|") or "",
            tostring(rule.min or ""), tostring(rule.max or "") }, "\t"))
    end
end
'''

FIELDS = ("label", "kind", "choices", "hidden", "min", "max")


def lua_path():
    return os.environ.get("MSUF_LUA51") or DEFAULT_LUA


def dump_catalog(root, client):
    run = subprocess.run([lua_path(), "-", str(root), client], input=DUMPER.encode("utf-8"),
                         capture_output=True, check=False)
    if run.stderr:
        sys.stderr.write(run.stderr.decode("utf-8", "replace"))
    modules, rules = {}, {}
    for line in run.stdout.decode("utf-8", "replace").splitlines():
        part = line.split("\t")
        if part[0] == "M":
            modules[part[1]] = (part[2], part[3])
        elif part[0] == "R":
            rules[(part[1], part[2])] = dict(zip(("section",) + FIELDS, part[3:]))
    return modules, rules


def bindings(root):
    path = root / "MSUF_Suite" / "Bindings.xml"
    text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    return set(re.findall(r'<Binding\s+name="([^"]+)"', text))


SLASH = re.compile(r'^(?!\s*--).*(?:SLASH_|SlashCmdList|RegisterSlash\s*\().*$', re.M)
COMMAND = re.compile(r'"(/[A-Za-z][\w-]*)"')


def slash_commands(root):
    found = set()
    for addon in sorted(os.listdir(root)):
        folder = root / addon
        if not addon.startswith("MSUF_Suite") or not folder.is_dir():
            continue
        for path in folder.rglob("*.lua"):
            if "Libs" in path.parts:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for line in SLASH.findall(text):
                found.update(COMMAND.findall(line))
            # Aliases kept in a local before the registration line.
            for line in re.findall(r'^\s*local\s[^=\n]*ALIAS[^=\n]*=.*$', text, re.M):
                found.update(COMMAND.findall(line))
    return found


def report_catalog(before, after, client):
    (bm, br), (am, ar) = dump_catalog(before, client), dump_catalog(after, client)
    print("== catalog (%s): %d -> %d modules, %d -> %d rules" % (client, len(bm), len(am), len(br), len(ar)))
    for module in bm:
        if module not in am:
            print("  MODULE REMOVED %s %r" % (module, bm[module][0]))
        elif bm[module] != am[module]:
            print("  MODULE CHANGED %s %r -> %r" % (module, bm[module], am[module]))
    for module in am:
        if module not in bm:
            print("  MODULE ADDED %s %r" % (module, am[module][0]))
    by_module = {}
    for key in br:
        if key not in ar:
            by_module.setdefault(key[0], ([], []))[0].append(key[1])
    for key in ar:
        if key not in br:
            by_module.setdefault(key[0], ([], []))[1].append(key[1])
    for module, (removed, added) in by_module.items():
        print("  -- %s" % module)
        for key in removed:
            rule = br[(module, key)]
            print("     - %s [%s] %r %s" % (key, rule["section"], rule["label"], rule["kind"]))
        for key in added:
            rule = ar[(module, key)]
            print("     + %s [%s] %r %s" % (key, rule["section"], rule["label"], rule["kind"]))
    for key, rule in br.items():
        other = ar.get(key)
        if not other:
            continue
        changed = [f for f in FIELDS if rule[f] != other[f]]
        if changed:
            print("  ~ %s.%s: %s" % (key[0], key[1], "; ".join("%s %r -> %r" % (f, rule[f], other[f]) for f in changed)))


def report_set(title, before, after):
    print("== %s: %d -> %d" % (title, len(before), len(after)))
    for name in sorted(before - after):
        print("  - " + name)
    for name in sorted(after - before):
        print("  + " + name)


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    client = "both"
    if "--client" in argv:
        client = argv[argv.index("--client") + 1]
        args = [a for a in args if a != client]
    if not args:
        print(__doc__)
        return 2
    before = Path(args[0]).resolve()
    after = Path(args[1]).resolve() if len(args) > 1 else ROOT
    for flavor in (("retail", "forever") if client == "both" else (client,)):
        report_catalog(before, after, flavor)
    report_set("key bindings", bindings(before), bindings(after))
    report_set("slash commands", slash_commands(before), slash_commands(after))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
