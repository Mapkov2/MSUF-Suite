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
    ("cold record footprint", "record = { children = emptyChildren }",
     "record = { children = emptyChildren, {}, {}, {}, {} }", "plain nodes allocated empty discovery tables"),
    ("empty provider signature", 'if kind ~= "ScrollFrame" and NoMotionBinding(frame) then',
     'if false then', "plain nodes entered collection provider"),
    ("sparse tuple invalidation", 'if record and state.buildValid and record.children ~= emptyChildren then',
     'if record and state.buildValid and child ~= nil then', "an absent middle child stayed in a sparse snapshot"),
    ("warm discovery", 'if not state.discover and Current(state) then',
     'if false then', "unchanged tree repeated discovery"),
    ("same-count identities", 'record.children[index] ~= select(index, ...)',
     'false', "same-count replacement was not discovered"),
    ("warm protection", 'if not Safety.CanCreateRegions(record.frame) then return false end',
     '-- protection change ignored', "show retained a discovery snapshot after a protection change"),
    ("warm late safety", 'elseif Safe(record.frame) then return false end',
     'end', "protection recovery did not discover subtree"),
    ("late capabilities", 'if not ShapeFields(record, false) then return false end',
     '-- capability changes ignored', "sparse cold records missed a late list"),
    ("content identity", 'if content ~= nil or lower ~= nil or panel ~= nil or container ~= nil then return false end',
     '-- lost named body', "late content body not watched"),
    ("provider reconciliation", 'Menus.TrackTarget(targets[index], state)',
     '-- native provider replacement ignored', "existing list did not reconcile its native provider"),
    ("secret identity", 'if HasSecret(content, lower, panel, container) then return false end',
     '-- opaque identity retained', "secret content identity was cached"),
    ("warm secret identity", 'HasSecret(provider, callback, animation, scroll, headers, titles, buttons, channels, content, lower, panel, container)',
     'HasSecret(provider, callback, animation, nil, headers, titles, buttons, channels, content, lower, panel, container)', "warm snapshot compared a secret identity"),
    ("late capability secret", 'HasSecret(provider, callback, animation, scroll, headers, titles, buttons, channels, content, lower, panel, container)',
     'HasSecret(provider, callback, animation, scroll, headers, titles, buttons, nil, content, lower, panel, container)', "late secret slot escaped validation: communityChannelButtonPool"),
    ("late child secret", 'if HasSecret(...) then return false end',
     'if false then return false end', "late secret slot escaped validation: 7"),
    ("child getter permission", 'if not Safety.IsForbidden(frame) then\n        local getter = Safety.ReadableMethod',
     'if true then\n        local getter = Safety.ReadableMethod', "GetChildren ignored a fresh forbidden answer"),
    ("hidden native notification", 'if not visible then return end', '-- schedule hidden sender',
     "resize preceded the hidden root notification and queued work"),
    ("pooled menu scheduling", 'if relation ~= "descendant" or NS.AdapterKit.IsDescendantOf(frame, state.root) then Schedule(state) end',
     'Schedule(state)', "pooled body scheduled the wrong visible menu"),
    ("pooled menu ownership", 'if next(state.owners) and (relation ~= "descendant" or NS.AdapterKit.IsDescendantOf(frame, state.root)) then return state end',
     'if next(state.owners) then return state end', "pooled body retained its old menu owner"),
    ("show verification", 'fade.\n    NotifyObservers(frame)',
     'fade.\n    -- opening left unobserved', "warm show/re-track missed a child identity check"),
    ("redundant show discovery", 'fade.\n    NotifyObservers(frame)',
     'fade.\n    for state in pairs(Menus.observers[frame]) do Schedule(state, true) end', "unchanged show/re-track repeated discovery"),
    ("redundant explicit discovery", 'Observe(state, root)\n    if not state.scanning',
     'Observe(state, root)\n    state.discover = true\n    if not state.scanning', "unchanged show/re-track repeated discovery"),
    ("profile invalidation", 'for _, state in pairs(Menus.states) do Schedule(state, true) end',
     'for _, state in pairs(Menus.states) do Schedule(state) end', "profile change reused discovery"),
    ("partial record budget", 'state.reusable = state.buildValid\n    if state.reusable then',
     'state.reusable = true\n    if state.reusable then', "record-budget overflow hid a recovered child"),
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
    ("boundary completion", 'else Safety.Dispatch(ScanNow, state) end',
     'else state.completed = Safety.Dispatch(ScanNow, state) end',
     "unchanged tree repeated discovery"),
    ("late body capability", 'record.bodyMethods[index] ~= method',
     'false', "late body animation capability was missed"),
    ("released owner lifetime", 'state.owner, state.cacheOwner = next(state.owners), nil',
     'state.owner = next(state.owners)', "released owner remained in discovery cache"),
]


def run(override=None, flavor="Mainline"):
    environment = dict(os.environ)
    environment.pop("SUITE_MENU_DISCOVERY_MEASURE", None)
    environment.pop("SUITE_MENU_DISCOVERY_CASE", None)
    if override:
        environment["SUITE_MENU_DISCOVERY_OVERRIDE"] = str(override)
    else:
        environment.pop("SUITE_MENU_DISCOVERY_OVERRIDE", None)
    return subprocess.run([lua, str(test), str(root), flavor], cwd=root,
                          env=environment, capture_output=True, text=True)


result = run()
assert result.returncode == 0, result.stdout + result.stderr
pane_cases = [
    ("initially visible pane", '    if not paneHooks[frame] then frame:HookScript("OnShow", PaneShown) end',
     '    if hidden and not paneHooks[frame] then frame:HookScript("OnShow", PaneShown) end',
     "initially visible pane missed a child inserted while hidden"),
    ("cold visible budget", "for pane in pairs(state.panes) do state.panes[pane] = true end",
     'for pane, status in pairs(state.panes) do if status ~= "active" then state.panes[pane] = true end end',
     "genuine root rebuild spent its budget on an already visited hidden pane"),
    ("hidden Communities partition", "if depth == 1 and state.panes and state.panes[frame] and HiddenPane(state, frame) then",
     "if false then", "hidden authored Communities pane was traversed on first open"),
    ("late native pane binding", "or not adapter.CanDeferMotionPane(active, keys[index], pane) then",
     "then", "unbound native Communities list was pruned"),
    ("child-first pane discovery", '        Scan(state, pane)\n    elseif status == "active"',
     '        Schedule(state, true)\n    elseif status == "active"', "child-before-parent show missed the first visible list"),
    ("local subtree", '    walk(state, pane, 1)',
     '    walk(state, state.root, 0)', "first pane show synchronously walked a sibling"),
    ("reentrant pane discovery", '            state.pendingPanes[pane] = true',
     '            -- missed nested show', "reentrant pane show lost a late native target"),
]
for case in cases + pane_cases:
    name, old, new, expected = case
    assert source.count(old) == 1, (name, source.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-menu-discovery-") as temporary:
        target = Path(temporary) / "MenuMotion.lua"
        target.write_text(source.replace(old, new, 1), encoding="utf-8")
        result = run(target, "Forever" if case in pane_cases else "Mainline")
    output = result.stdout + result.stderr
    assert result.returncode != 0 and expected in output, name + ": " + output
    print("ok   " + name)
print(f"Menu discovery mutations: {len(cases) + len(pane_cases)} causal regressions detected")
