"""Cold tool actions reject stale input and preserve bounded notification semantics."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
test = "tools/tests/suite_everyday_tools_contract.lua"
mutations = [
    ("CurrencyGoals.lua", "if goals[id] ~= initial then", "if false then", "stale currency editor"),
    ("CurrencyGoals.lua", "            Update()", "            -- seed omitted", "first goal crossing"),
    ("CurrencyGoals.lua", "if lifetime == true then amount = info.totalEarned end", "-- wrong balance", "earned-total cap"),
    ("KeywordAlerts.lua", "if self.config ~= config or self.config.words ~= initial then", "if false then", "stale keyword editor"),
    ("KeywordAlerts.lua", "plain:find(phrase.key, 1, true)", "plain:find(phrase.key)", "literal phrase matching"),
    ("WaypointLists.lua", "NS.DB ~= profile or NS.InCombat()", "NS.InCombat()", "stale waypoint confirmation"),
    ("SoundProfiles.lua", "if not M.active or NS.InCombat() then", "if not M.active then", "combat sound deferral"),
]
files = [test, "tools/tests/comfort_fixture.lua", "MSUF_Suite_Modules/SuiteNotices.lua",
         "MSUF_Suite_QualityOfLife/SharedItems.lua"]
files += ["MSUF_Suite_QualityOfLife/" + name for name in {entry[0] for entry in mutations}]
with tempfile.TemporaryDirectory(prefix="suite-everyday-mutations-") as directory:
    tree = Path(directory)
    for name in files:
        destination = tree / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / name, destination)
    def run():
        return subprocess.run([lua, str(tree / test), str(tree)], capture_output=True, text=True, errors="replace")
    baseline = run()
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
    for name, old, new, reason in mutations:
        path = tree / "MSUF_Suite_QualityOfLife" / name
        original = path.read_bytes()
        text = original.decode("utf-8")
        assert old in text, reason + ": mutation anchor changed"
        path.write_bytes(text.replace(old, new, 1).encode("utf-8"))
        result = run()
        path.write_bytes(original)
        assert result.returncode and "syntax" not in result.stderr.lower(), reason + ": mutation survived"
        print("rejected " + reason)
print("Everyday safety: 7/7 mutations rejected")
