"""Exact-tree reuse must retain native boundaries, late discovery and invalidation."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
test = root / "tools/tests/suite_skin_menu_discovery_contract.lua"
source = (root / "MSUF_Suite_Skin/Rendering/MenuMotion.lua").read_text(encoding="utf-8")
cases = [
    ("warm discovery", 'if not state.discover and Current(state) then',
     'if false then', "unchanged tree repeated discovery"),
    ("same-count identities", 'record.children[index] ~= child',
     'false', "same-count replacement was not discovered"),
    ("late capabilities", 'if not Fields(record, shapeKeys, record.shape, false) then return false end',
     '-- capability changes ignored', "late list capabilities were not discovered"),
    ("content identity", 'if not record.leaf and (not Bodies(record, false, state.owner)',
     'if not record.leaf and (false', "late content body not watched"),
    ("provider reconciliation", 'if record.target then Menus.TrackTarget(record.frame, state) end',
     '-- native provider replacement ignored', "existing list did not reconcile its native provider"),
    ("secret identity", 'if not Safety.Public(value) then return false end',
     '-- opaque identity retained', "secret content identity was cached"),
    ("show invalidation", 'for state in pairs(states) do Schedule(state, true) end',
     'for state in pairs(states) do Schedule(state) end', "show did not rediscover"),
    ("profile invalidation", 'for _, state in pairs(Menus.states) do Schedule(state, true) end',
     'for _, state in pairs(Menus.states) do Schedule(state) end', "profile change reused discovery"),
    ("partial record budget", 'state.reusable = state.buildValid',
     'state.reusable = true', "record-budget overflow hid a recovered child"),
    ("public tooltip guard", 'kind ~= "GameTooltip"',
     'true', "tooltip adopted"),
    ("shared owner release", 'if state.owners[owner] then',
     'if false then', "cross-root release lost root watch"),
    ("public result shape", 'if kind and TrackChecked(frame, owner, kind) then return true end',
     'if kind then return TrackChecked(frame, owner, kind) end', "plain target return arity changed"),
    ("reentrant discovery", '    if state.scanning then\n',
     '    if false then\n', "reentrant discovery duplicated target ownership"),
    ("retired body", 'if not kept then\n                Menus.observers[frame][state] = nil',
     'if not kept then\n                -- retired body stays subscribed', "retired body kept invalidating menu"),
    ("watch ownership", 'if not remember and record.watched[index] then',
     'if false then', "foreign unwatch was not healed"),
    ("empty child budget", 'if count ~= 1 or not Safety.Public(first) or first ~= nil then state.edges = state.edges + count end',
     'state.edges = state.edges + count', "nil-only children consumed edge budget"),
    ("temporary body protection", 'elseif state.observed[body] ~= nil then state.observed[body] = true end',
     'end', "pruned body observer missed show"),
    ("boundary completion", 'Safety.Dispatch(ScanNow, state)\n    state.scanning = false',
     'state.completed = Safety.Dispatch(ScanNow, state)\n    state.scanning = false',
     "unchanged tree repeated discovery"),
    ("late body capability", 'record.bodyMethods[index] ~= method',
     'false', "late body animation capability was missed"),
    ("released owner lifetime", 'state.owner, state.cacheOwner = next(state.owners), nil',
     'state.owner = next(state.owners)', "released owner remained in discovery cache"),
]


def run(override=None):
    environment = dict(os.environ)
    environment.pop("SUITE_MENU_DISCOVERY_MEASURE", None)
    environment.pop("SUITE_MENU_DISCOVERY_CASE", None)
    if override:
        environment["SUITE_MENU_DISCOVERY_OVERRIDE"] = str(override)
    else:
        environment.pop("SUITE_MENU_DISCOVERY_OVERRIDE", None)
    return subprocess.run([lua, str(test), str(root), "Mainline"], cwd=root,
                          env=environment, capture_output=True, text=True)


result = run()
assert result.returncode == 0, result.stdout + result.stderr
for name, old, new, expected in cases:
    assert source.count(old) == 1, (name, source.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-menu-discovery-") as temporary:
        target = Path(temporary) / "MenuMotion.lua"
        target.write_text(source.replace(old, new, 1), encoding="utf-8")
        result = run(target)
    output = result.stdout + result.stderr
    assert result.returncode != 0 and expected in output, name + ": " + output
    print("ok   " + name)
print(f"Menu discovery mutations: {len(cases)} causal regressions detected")
