"""A4 budgets and cold-motion safety must fail when each change is removed."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
CONTRACT = ROOT / "tools/tests/suite_skin_surface_budget_contract.lua"
CASES = [
    ("selection-pass", "Rendering/Surface.lua",
     '    state.active = active\n    state.refresh(state, true)',
     '    state.active = active\n    state.refresh(state)',
     "selection protection pass budget exceeded"),
    ("visibility", "Rendering/Surface.lua",
     'if state.visible == (visible == true) and state.paintGeneration == paintGeneration',
     'if false and state.visible == (visible == true) and state.paintGeneration == paintGeneration',
     "unchanged visibility budget exceeded"),
    ("eager-palette", "Rendering/PaletteMotion.lua",
     'record = { state = state, to = {}, current = {}, palette = true }',
     'record = Motion.New(state, Paint, Safe, Reset)\n'
     '        record.to, record.current, record.palette = {}, {}, true',
     "cold menu lazy motion budget exceeded"),
    ("eager-surface", "Rendering/SurfaceMotion.lua",
     'local record = { state = state, paint = Paint, reset = Motion.Restore }',
     'local record = Motion.New(state, Paint, Safe, Motion.Restore)',
     "cold surface allocated spring channels"),
    ("duplicate-protection", "Rendering/SurfaceMotion.lua",
     'if not Motion.Enabled(state.spec) or not Safety.CanCreateRegions(state.target) then',
     'if not Motion.Enabled(state.spec) or not Safety.CanCreateRegions(state.target)\n'
     '        or Safety.GetProtection(state.target) then',
     "surface refresh safety budget exceeded"),
    ("duplicate-safety", "Core/Safety.lua",
     'function Safety.ReadUnprotected(target, name)\n',
     'function Safety.ReadUnprotected(target, name)\n'
     '    if IsForbidden(target) or Safety.GetProtection(target) then return nil end\n',
     "single object safety pass budget exceeded"),
    ("cold-hide-guard", "Rendering/SurfaceMotion.lua",
     'if record.channels then Motion.Clear(record) else Motion.Restore(record) end',
     'if record.channels then Motion.Clear(record) else Paint(record) end',
     "cold forbidden hide wrote artwork"),
    ("motion-reuse", "Rendering/Motion.lua",
     '    if record.channels then return record end',
     '    -- incorrectly recreate channels',
     "palette did not reuse its channels"),
]


def run(env, flavor="Mainline"):
    return subprocess.run([LUA, str(CONTRACT), str(ROOT), flavor], cwd=ROOT,
                          env=env, capture_output=True, text=True, errors="replace")


environment = dict(os.environ)
for key in ("SUITE_A4_BASELINE", "SUITE_A4_MEASURE_ONLY", "SUITE_A4_RECEIPT"):
    environment.pop(key, None)
for flavor in ("Mainline", "Forever"):
    baseline = run(environment, flavor)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
with tempfile.TemporaryDirectory(prefix="suite-surface-budget-") as temporary:
    for name, relative, before, after, expected in CASES:
        original = (ROOT / "MSUF_Suite_Skin" / relative).read_text(encoding="utf-8")
        assert original.count(before) == 1, name + ": mutation anchor changed"
        scratch = Path(temporary) / name
        target = scratch / "MSUF_Suite_Skin" / relative
        target.parent.mkdir(parents=True)
        target.write_text(original.replace(before, after), encoding="utf-8")
        result = run(dict(environment, SUITE_A4_BASELINE=str(scratch)))
        output = result.stdout + result.stderr
        assert result.returncode != 0 and expected in output, name + ": " + output
print("Suite skin surface budgets: %d red-without-fix cases passed" % len(CASES))
