"""Sensitivity checks for native smooth-scroll ownership and input lifecycles."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
TEST = ROOT / "tools/tests/suite_skin_scroll_motion_contract.lua"
PATH = Path("Rendering/ScrollMotion.lua")
SOURCE = (ROOT / "MSUF_Suite_Skin" / PATH).read_text(encoding="utf-8")
MUTANTS = (
    ("off switch", "db.theme.smoothScrolling ~= false", "true"),
    ("reduced motion", "db.theme.reduceMotion ~= true", "true"),
    ("immediate thumb drag", "enabled and not state.dragging", "enabled"),
    ("combat edge flag read", "local valid, current = SafeFlag(target)", "local valid, current = Flag(target)"),
    ("combat edge configuration read", "else Update(state, enabled) end", "else Update(state) end"),
    ("paired thumb drag", "paired.dragging = true", "paired.dragging = false"),
    ("same-value foreign ownership", "if state and not state.writing then", "if false then"),
    ("nil native preference", "Write(state, state.original)", "Write(state, false)"),
    ("cold cancellation allocation", 'Safety.Field(target, "interpolator")',
     'Safety.Read(target, "GetScrollInterpolator")'),
    ("hidden-position safety", "Cancel(target, false)\n        state.dragging = false",
     "Cancel(target, true)\n        state.dragging = false"),
    ("combat edge", "and not NS.Motion.combat and not NS.IsCombatLocked()", "and not NS.IsCombatLocked()"),
    ("native baseline retention", "acquire and not state.captured and next(state.leases)",
     "acquire and next(state.leases)"),
    ("one active native interpolator", 'hooksecurefunc(target, "Interpolate", Safety.Isolated(Interpolating))',
     "-- partner cancellation removed"),
    ("provider/layout invalidation", 'target:RegisterCallback(ScrollBoxListMixin.Event.OnLayout, LayoutChanged, state)',
     "-- layout cancellation removed"),
    ("explicit immediate jump", 'hooksecurefunc(target, "ScrollToOffset", Safety.Isolated(ScrollToOffset))',
     "-- explicit jump cancellation removed"),
    ("immediate beginning jump", 'hooksecurefunc(target, "ScrollToBegin", Safety.Isolated(ScrollToBoundary))',
     "-- explicit beginning cancellation removed"),
    ("native mouse-down payload", "local function ThumbDown(state, button)",
     "local function ThumbDown(state, _, button)"),
    ("native mouse-up payload", "local function ThumbUp(state, button)",
     "local function ThumbUp(state, _, button)"),
)


def run(environment):
    return subprocess.run([LUA, str(TEST), str(ROOT), "Mainline"], cwd=ROOT, env=environment,
                          capture_output=True, text=True)


baseline = run(os.environ.copy())
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for name, old, new in MUTANTS:
    assert SOURCE.count(old) == 1, (name, SOURCE.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-native-scroll-") as directory:
        target = Path(directory) / PATH
        target.parent.mkdir(parents=True)
        target.write_text(SOURCE.replace(old, new, 1), encoding="utf-8")
        result = run(dict(os.environ, SUITE_SCROLL_OVERRIDE_ROOT=directory))
        assert result.returncode != 0, f"Undetected regression: {name}"
        assert "stack traceback" in result.stderr, result.stdout + result.stderr
    print(f"ok   {name}")
print(f"Suite smooth-scroll mutations: {len(MUTANTS)} causal regressions detected")
