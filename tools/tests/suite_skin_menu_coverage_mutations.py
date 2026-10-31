"""Causal regressions for explicitly registered menu boundaries and native reuse."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
TEST = ROOT / "tools/tests/suite_skin_menu_coverage_contract.lua"
CASES = (
    ("owner handoff", "Rendering/MenuMotion.lua", 'state.owner, state.cacheOwner = next(state.owners), nil',
     '-- stale owner retained', 'menu retained released latest owner'),
    ("nested content exclusion", "Rendering/ContentMotion.lua",
     'if Descendant(frame, active.target) then return false end',
     '-- active ancestor ignored', 'child faded under active ancestor'),
    ("foreign content owner", "Rendering/ContentMotion.lua",
     'if record and record.owner ~= nil and record.owner ~= owner then return false end',
     '-- foreign ownership ignored', "refused foreign owner stopped another owner's descendant"),
    ("pooled list boundary", "Rendering/MenuMotion.lua",
     'if leaf then\n',
     'if false then\n', 'pooled row was scanned for full-menu rediscovery'),
    ("modern ScrollFrame delegation", "Rendering/LegacyScrollMotion.lua",
     'if Safety.HasMethod(bar, "CanInterpolateScroll") then',
     'if false then', 'native modern ScrollFrame controller was smoothed twice'),
    ("legacy thumb drag", "Rendering/LegacyScrollMotion.lua",
     'if Safety.Read(bar, "IsMouseOver") == true then',
     'if false then', 'legacy thumb drag retained smoothing'),
    ("legacy bar mouse handler", "Rendering/LegacyScrollMotion.lua",
     'bar:HookScript("OnHide", BarHidden)',
     'bar:HookScript("OnHide", BarHidden) bar:HookScript("OnMouseUp", BarHidden)',
     "legacy bar got a mouse handler Forever's SmartNavigation reads"),
    ("legacy hidden press watch", "Rendering/LegacyScrollMotion.lua",
     'if not combat and next(shownBars) and ', 'if not combat and ',
     'hiding the last legacy bar kept watching every mouse press'),
    ("legacy combat press watch", "Rendering/LegacyScrollMotion.lua",
     'StopAll() Watch(true)', 'StopAll()', 'combat kept watching every mouse press'),
    ("legacy released press watch", "Rendering/LegacyScrollMotion.lua",
     '        if not Owned(bar) then shownBars[bar] = nil end\n', '',
     'a released legacy owner kept watching every mouse press'),
    ("legacy drag release", "Rendering/LegacyScrollMotion.lua",
     'events:UnregisterEvent("GLOBAL_MOUSE_UP")',
     '-- release watch left registered', 'legacy drag kept watching after the mouse release'),
    ("Ace root classification", "Adapters/AddonMenus.lua",
     'state.root = state.root or force == true or roots[Safety.Field(widget, "type")] == true',
     'state.root = true', 'ordinary Ace widget was styled as an independent window'),
    ("Ace in-place upgrade", "Adapters/AddonMenus.lua",
     'if hooks[key] == method then return end',
     'if hooks[key] ~= nil then return end', 'in-place Ace upgrade lost menu observers'),
    ("Ace child pool owner", "Adapters/AddonMenus.lua",
     'NS.ContentMotion.Unwatch(state.contentOwner, Safety.Field(widget, "content"))',
     '-- pooled child retains stale content owner', 'pooled Ace TabGroup cannot fade under a different config root'),
    ("Ace master disable", "Adapters/AddonMenus.lua",
     'if not Enabled() then Release(state) return end',
     '-- disable boundary ignored', 'master disable retained external menu skins'),
)


def run(environment):
    return subprocess.run([LUA, str(TEST), str(ROOT), "Mainline"], cwd=ROOT,
                          env=environment, capture_output=True, text=True)


baseline = run(dict(os.environ))
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for name, path, old, new, expected in CASES:
    source = (ROOT / "MSUF_Suite_Skin" / path).read_text(encoding="utf-8")
    assert source.count(old) == 1, (name, source.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-menu-coverage-") as temporary:
        target = Path(temporary) / path
        target.parent.mkdir(parents=True)
        target.write_text(source.replace(old, new, 1), encoding="utf-8")
        result = run(dict(os.environ, SUITE_TRANSITION_OVERRIDE_ROOT=temporary))
        output = result.stdout + result.stderr
        assert result.returncode != 0 and expected in output, name + ": " + output
    print("ok   " + name)
print(f"Suite menu coverage mutations: {len(CASES)} causal regressions detected")
