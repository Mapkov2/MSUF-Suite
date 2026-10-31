"""Each journal regression must turn the native-template contract red."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
TEST = ROOT / "tools/tests/suite_skin_encounter_contract.lua"
PANELS = (ROOT / "MSUF_Suite_Skin/Adapters/EncounterJournalPanels.lua").read_text(encoding="utf-8")
ADAPTER = (ROOT / "MSUF_Suite_Skin/Adapters/EncounterJournal.lua").read_text(encoding="utf-8")
MUTANTS = (
    ("unkeyed parchment", "panels", 'name .. "BG"', 'name .. "WrongBG"'),
    ("native normal", "panels", 'Fade(state, Safety.Read(button, "GetNormalTexture"))', '-- native art left visible'),
    ("lore path", "panels", '"FontStringContainer", "FontString"', '"FontStringContainer", "WrongText"'),
    ("loot parchment", "panels", 'Fade(state, Field(row, "bossTexture"))', '-- loot parchment left visible'),
    ("row reuse", "adapter", 'Kit.Ensure(state, row, ROW_SPEC)', 'Attach(state, row, ROW_SPEC)'),
    ("control reuse", "panels", 'state.journalControls[button] ~= spec', 'true'),
    ("hidden navigation", "panels", 'if Kit.DeferHidden(state.frame, state, Panels.Controls, state) then return end\n    local nav',
     '-- hidden work\n    local nav'),
    ("combat navigation", "panels", 'if NS.IsCombatLocked() then\n        if not state.deferred[NAV_JOB]',
     'if false then\n        if not state.deferred[NAV_JOB]'),
    ("theme selection", "panels", 'Control(state, button, active and NAV_ACTIVE or NAV)\n    Kit.FadeFields',
     'Control(state, button, NAV)\n    Kit.FadeFields'),
    ("side tab selection", "panels", 'selected == Safety.Read(button, "GetID")', 'selected == -1'),
    ("side tab event", "panels", 'Kit.HookGlobal("EncounterJournal_SetTab", OnSideTabChanged)', 'true'),
    ("combat side tabs", "panels", 'if NS.IsCombatLocked() then\n        if not state.deferred[TABS_JOB]',
     'if false then\n        if not state.deferred[TABS_JOB]'),
    ("hidden side tabs", "panels", 'if Kit.DeferHidden(state.frame, state, Panels.Controls, state) then return end\n    local info',
     '-- hidden work\n    local info'),
    ("chrome restoration", "adapter", 'NS.EncounterJournalPanels.Reset(state)', '-- stale cache'),
)


def run(env):
    return subprocess.run([LUA, str(TEST), str(ROOT)], cwd=ROOT, env=env, capture_output=True, text=True)


baseline = run(os.environ.copy())
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for label, source_name, old, new in MUTANTS:
    source = PANELS if source_name == "panels" else ADAPTER
    assert source.count(old) == 1, (label, source.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-journal-") as folder:
        path = Path(folder) / "mutant.lua"
        path.write_text(source.replace(old, new), encoding="utf-8")
        variable = "SUITE_EJ_PANELS_SOURCE" if source_name == "panels" else "SUITE_EJ_SOURCE"
        result = run(dict(os.environ, **{variable: str(path)}))
        assert result.returncode != 0 and "stack traceback" in result.stderr, label
    print("ok  " + label)
print(f"EncounterJournal: {len(MUTANTS)} regressions detected")
