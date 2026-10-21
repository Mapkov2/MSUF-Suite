"""Prove the native transition lifecycle tests fail when each guard is removed."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
TEST = ROOT / "tools/tests/suite_skin_menu_transitions_contract.lua"
SKIN = ROOT / "MSUF_Suite_Skin"
MUTANTS = (
    ("native close callback", "Core/CheckmarksMenus.lua",
     "button:RegisterCallback(closeEvent, OnMenuClose, state)", "-- close observer removed"),
    ("closing lease release", "Rendering/FocusVeil.lua",
     " or FocusVeil.closingLease == lease", ""),
    ("pooled popup identity", "Rendering/FocusVeil.lua",
     "if FocusVeil.lease ~= lease or menu and FocusVeil.menu ~= menu then return end",
     "if false then return end"),
    ("open menu focus cue", "Rendering/FocusVeil.lua",
     "if not Allowed() or domain == \"profile\" or not surface or surface.visible == false",
     "if true or not Allowed() or domain == \"profile\" or not surface or surface.visible == false"),
    ("reduced motion dimming", "Rendering/FocusVeil.lua",
     "if not Motion.Enabled() then", "if false then"),
    ("provider rebuild snap", "Adapters/AddonListMotion.lua",
     "provider ~= nil and provider == state.provider", "provider ~= nil"),
    ("pooled row release", "Adapters/AddonListMotion.lua",
     '        Stop(record)\n        record.node = nil', '        record.node = nil'),
    ("native alpha preservation", "Adapters/AddonListMotion.lua",
     'local alpha = Safety.Read(record.row, "GetAlpha")', "local alpha = 1"),
    ("protected row stop", "Adapters/AddonListMotion.lua",
     "if state.count >= 128 or not SafeRow(row) then", "if state.count >= 128 then"),
    ("legacy pooled owner", "Core/CheckmarksMenus.lua",
     "and Safety.Public(dropdown) and dropdown == state.dropdown then",
     "and Safety.Public(dropdown) then"),
    ("legacy root close", "Core/CheckmarksMenus.lua",
     "listFrame:HookScript(\"OnHide\", LegacyHidden)", "-- root hide observer removed"),
    ("mixed dropdown generation", "Core/CheckmarksMenus.lua",
     "state.active and state.serial == focusSerial and Checkmarks.legacyRegistered",
     "state.active and Checkmarks.legacyRegistered"),
    ("native nil-open category", "Adapters/AddonListMotion.lua",
     'if Safety.Public(collapsed) then record.collapsed = collapsed == true end',
     'if type(collapsed) == "boolean" then record.collapsed = collapsed end'),
    ("ghost idle scroll", "Adapters/AddonListGhosts.lua",
     'if state.ghostCategory and not state.ghostPending then Ghost.Stop(state) end',
     'if not state.ghostPending then Ghost.Stop(state) end'),
    ("ghost recycled snapshot", "Adapters/AddonListGhosts.lua",
     'and Safety.Read(record.row, "IsVisible") == true then Ghost.Capture(state, record) end',
     'and false then Ghost.Capture(state, record) end'),
    ("native uninitialized view", "Rendering/ResultMotion.lua",
     'if Safety.HasMethod(target, "GetView") and Safety.Read(target, "GetView") == nil then return nil end',
     '-- uninitialized native GetDataProvider called'),
    ("native result before paint", "Rendering/ResultMotion.lua",
     'Content.Play(state.target, state, provider)',
     'C_Timer.NewTimer(0.08, function() Content.Play(state.target, state, provider) end)'),
    ("native result layout identity", "Rendering/ResultMotion.lua",
     'if provider == state.provider then return end', '-- all layouts wrongly restart results'),
)


def run(env):
    return subprocess.run([LUA, str(TEST), str(ROOT), "Mainline"], cwd=ROOT,
                          env=env, text=True, capture_output=True)


baseline = run(os.environ.copy())
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for name, path, old, new in MUTANTS:
    source = (SKIN / path).read_text(encoding="utf-8")
    assert source.count(old) == 1, (name, source.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-menu-transition-") as directory:
        changed = Path(directory) / path
        changed.parent.mkdir(parents=True)
        changed.write_text(source.replace(old, new, 1), encoding="utf-8")
        environment = dict(os.environ, SUITE_TRANSITION_OVERRIDE_ROOT=directory)
        result = run(environment)
        assert result.returncode != 0, f"Undetected mutation: {name}"
        assert "stack traceback" in result.stderr, result.stdout + result.stderr
    print(f"ok   {name}")
print(f"Suite menu transition mutations: {len(MUTANTS)} causal regressions detected")
