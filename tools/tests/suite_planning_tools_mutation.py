"""Executable negative guards: every removed boundary must turn the behavior contract red."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
test = root / "tools/tests/suite_planning_tools_contract.lua"
cases = [
    ("disabled owner", "PlanningTools.lua", "return owner ~= nil and owner.active == true", "return owner ~= nil"),
    ("combat refusal", "PlanningTools.lua",
     "return Plan.Active() and not Plan.owner.suspended and not Plan.owner.leaving and not NS.InCombat()",
     "return Plan.Active() and not Plan.owner.suspended"),
    ("snapshot bound", "PlanningWeekly.lua", "while Plan.Count(characters) > Plan.LIMIT.characters do", "while false do"),
    ("reset freshness", "PlanningWeekly.lua", "local fresh = reset ~= nil and entry.reset == reset", "local fresh = true"),
    ("vault secret", "PlanningWeekly.lua", 'if not S.Public(activities) or type(activities) ~= "table" then return nil end',
     'if type(activities) ~= "table" then return nil end'),
    ("manual eligible apply", "PlanningLFG.lua", "or not m.CanApplyFilters() then", "then"),
    ("bounded attempts", "PlanningHistory.lua", "while #list > limit do table.remove(list) end", "-- mutation: bound removed"),
    ("context notes", "PlanningNotes.lua", "(not contextOnly or instance and instance.id == entry.instanceID)", "true"),
]
with tempfile.TemporaryDirectory(prefix="suite-planning-mutation-") as temp:
    target = Path(temp)
    folder = target / "MSUF_Suite_AdventurePlanner"
    folder.mkdir()
    for source in (root / "MSUF_Suite_AdventurePlanner").glob("Planning*.lua"):
        shutil.copyfile(source, folder / source.name)
    for label, name, old, new in cases:
        path = folder / name
        original = path.read_text(encoding="utf-8")
        assert original.count(old) == 1, (label, "mutation anchor is not unique")
        path.write_text(original.replace(old, new), encoding="utf-8")
        result = subprocess.run([lua, str(test), str(target)], capture_output=True, text=True)
        path.write_text(original, encoding="utf-8")
        assert result.returncode != 0, (label, "unsafe mutant survived")
        assert "expected" in result.stderr or "assertion failed" in result.stderr, (label, result.stderr)
        print("rejected:", label)
print("suite_planning_tools_mutation: 8 unsafe mutations rejected")
