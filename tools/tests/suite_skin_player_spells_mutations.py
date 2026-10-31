"""Hidden-window, theme and combat-job regressions against the real adapter."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
SOURCE = (ROOT / "MSUF_Suite_Skin/Adapters/PlayerSpells.lua").read_text(encoding="utf-8")
TEST = ROOT / "tools/tests/suite_skin_generic_windows_contract.lua"
MUTANTS = (
    ("completed combat job", "current.active and current.pendingRefresh and", "current.active and"),
    ("hidden combat job", ' and Safety.Read(current.frame, "IsShown") ~= false', ""),
    ("show refresh", "if state and state.pendingRefresh then PlayerSpellsSkin:QueueRefresh(frame) end", "return"),
    ("burst page request", "state.pendingPageRefresh or refreshPages == true", "refreshPages == true"),
    ("consumed refresh", "current.pendingRefresh, current.pendingPageRefresh = nil, nil", "current.pendingPageRefresh = nil"),
    ("hidden theme", 'if Safety.Read(state.frame, "IsShown") == false then\n            state.pendingRefresh',
     'if false then\n            state.pendingRefresh'),
)


def run(env):
    return subprocess.run([LUA, str(TEST), str(ROOT)], cwd=ROOT, env=env, capture_output=True, text=True)


baseline = run(os.environ.copy())
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for name, old, new in MUTANTS:
    assert SOURCE.count(old) == 1, (name, SOURCE.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-spellbook-") as folder:
        target = Path(folder) / "PlayerSpells.lua"
        target.write_text(SOURCE.replace(old, new), encoding="utf-8")
        result = run(dict(os.environ, SUITE_PLAYER_SPELLS_SOURCE=str(target)))
        assert result.returncode != 0 and "stack traceback" in result.stderr, name
    print("ok  " + name)
print(f"PlayerSpells: {len(MUTANTS)} regressions detected")
