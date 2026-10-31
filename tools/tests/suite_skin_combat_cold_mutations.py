"""Combat work stays bounded by visible windows and running animations."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
TEST = ROOT / "tools/tests/suite_skin_combat_cold_contract.lua"
MUTANTS = (
    ("hidden result scan", "ResultMotion.lua",
     "pairs(visible)", "pairs(Results.states)"),
    ("inactive animation scan", "ContentMotion.lua",
     "for record in pairs(Content.active) do Stop(record) end",
     "for _, record in pairs(Content.records) do Stop(record) end"),
    ("targeted content release", "ContentMotion.lua",
     "if frame ~= nil then return Release(Content.records[frame], owner) end",
     "-- direct lookup removed"),
    ("reopened result cancellation", "ResultMotion.lua",
     'target:HookScript("OnShow", Shown)', "-- visibility resumption removed"),
    ("completed content invalidation", "ContentMotion.lua",
     "revision = revision + 1", "-- invalidation removed"),
)


def run(environment):
    return subprocess.run([LUA, str(TEST), str(ROOT), "Mainline"], cwd=ROOT, env=environment,
                          capture_output=True, text=True)


baseline = run(os.environ.copy())
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for name, filename, old, new in MUTANTS:
    source = (ROOT / "MSUF_Suite_Skin/Rendering" / filename).read_text(encoding="utf-8")
    assert source.count(old) == 1, (name, source.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-combat-cold-") as directory:
        target = Path(directory) / "Rendering" / filename
        target.parent.mkdir()
        target.write_text(source.replace(old, new, 1), encoding="utf-8")
        result = run(dict(os.environ, SUITE_TRANSITION_OVERRIDE_ROOT=directory))
        assert result.returncode != 0, f"Undetected regression: {name}"
        assert "stack traceback" in result.stderr, result.stdout + result.stderr
    print(f"ok   {name}")
print(f"Suite combat cold mutations: {len(MUTANTS)} causal regressions detected")
