"""Micro button structural reuse preserves cold creation, native text and safety."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
REL = "MSUF_Suite_Skin/Adapters/MicroMenuStates.lua"
CASES = [
    ("warm-reseed", "    if NS.Registry.GetSurface(button) then", "    if false then",
     "warm clean Micro Bar painted structural button surfaces"),
    ("lost-native-text", "        NS.BlizzardYellow.TrackFrame(button)", "",
     "warm clean Micro Bar lost its late-native-text scan"),
    ("cold-unseeded",
     '    return ApplySurface(button, "microButton", true, settings.buttonBorder, settings, false, true)',
     "    return true", "owned reparent preceded structural surface creation"),
    ("stale-permission", "        if not NS.Safety.CanCreateRegions(button, true) then return false end", "",
     "implicit protected surface bypassed combat"),
    ("lost-implicit-exception", "NS.Safety.CanCreateRegions(button, true)",
     "NS.Safety.CanCreateRegions(button)", "surface reuse returned a partial result"),
]


def run(override, forever):
    env = dict(os.environ)
    env.pop("SUITE_MICRO_SURFACE_BASELINE", None)
    if override:
        env["SUITE_MICRO_SURFACE_BASELINE"] = str(override)
    return subprocess.run([LUA, str(ROOT / "tools/tests/suite_skin_absorption_contract.lua"), str(ROOT),
                           str(ROOT.parent / "MapkoSkin"),
                           "Forever" if forever else str(ROOT.parent / "_repo_backups/6.22")],
                          cwd=ROOT, env=env, capture_output=True, text=True, errors="replace")


for forever in (False, True):
    baseline = run(None, forever)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
source = (ROOT / REL).read_text(encoding="utf-8")
with tempfile.TemporaryDirectory(prefix="suite-micro-surface-") as temporary:
    for name, before, after, expected in CASES:
        assert source.count(before) == 1, name + ": mutation anchor changed"
        scratch = Path(temporary) / name
        target = scratch / REL
        target.parent.mkdir(parents=True)
        target.write_text(source.replace(before, after), encoding="utf-8")
        for forever in (False, True):
            result = run(scratch, forever)
            assert result.returncode != 0 and expected in result.stdout + result.stderr, (
                name + ": " + result.stdout + result.stderr)
print("Suite Micro surface reuse: 5 mutations rejected on each of Mainline/Forever (10 cases)")
