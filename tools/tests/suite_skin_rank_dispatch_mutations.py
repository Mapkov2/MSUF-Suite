"""Reject native row rebuilds and stale preference reads in the rank footer."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
SOURCE = ROOT / "MSUF_Suite_Skin/Adapters/PlayerSpells.lua"
TEST = ROOT / "tools/tests/suite_skin_rank_dispatch_contract.lua"
CASES = (
    ("rebuild on addon click", "    SetCVar(RANKS_CVAR, not GetCVarBool(RANKS_CVAR))",
     "    SetCVar(RANKS_CVAR, not GetCVarBool(RANKS_CVAR))\n    button:GetParent():UpdateDisplayedSpells()",
     "the Suite footer rebuilt native spell rows during its click"),
    ("stale preference", "    SetCVar(RANKS_CVAR, not GetCVarBool(RANKS_CVAR))",
     "    SetCVar(RANKS_CVAR, not button.on)", "the next click used stale selection state"),
)


def run(environment):
    return subprocess.run([LUA, str(TEST), str(ROOT)], cwd=ROOT, env=environment, capture_output=True, text=True)


baseline = run(dict(os.environ))
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
source = SOURCE.read_text(encoding="utf-8")
for name, old, new, expected in CASES:
    assert source.count(old) == 1, (name, source.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-rank-dispatch-") as directory:
        path = Path(directory) / "PlayerSpells.lua"
        path.write_text(source.replace(old, new, 1), encoding="utf-8")
        result = run(dict(os.environ, SUITE_PLAYER_SPELLS_SOURCE=str(path)))
        output = result.stdout + result.stderr
        assert result.returncode != 0 and expected in output, name + ": " + output
    print("ok   " + name)
print("Rank menu dispatch: 2 causal regressions detected")
