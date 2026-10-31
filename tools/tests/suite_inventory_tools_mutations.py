"""Real behavior contracts must reject lost inventory safety boundaries."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
test = "tools/tests/suite_inventory_tools_contract.lua"
mutations = [
    ("MSUF_Suite_QualityOfLife/InventoryArchive.lua", "if not complete or not S.Finite(now)", "if not S.Finite(now)", "partial snapshot"),
    ("MSUF_Suite_QualityOfLife/RestockPlanner.lua", "if not complete then", "if false then", "unknown stock"),
    ("MSUF_Suite_QualityOfLife/CraftShopping.lua", "if not complete then", "if false then", "unknown shopping"),
    ("MSUF_Suite_QualityOfLife/Merchant.lua", "S.InventoryProtection:HasProtectedJunk()", "false", "native bulk exclusion"),
    ("MSUF_Suite_QualityOfLife/InventoryTransfers.lua", "not S.Public(refundable) or refundable ~= false", "false", "refundable bank item"),
    ("MSUF_Suite_QualityOfLife/InventoryTransfers.lua", "if not HasSpace(destination) then", "if false then", "full destination"),
    ("MSUF_Suite_QualityOfLife/MailTemplates.lua", "if address ~= entry.recipient then", "if false then", "changed recipient"),
    ("MSUF_Suite_QualityOfLife/MailTemplates.lua", "math.min(item.count, need)", "item.count", "exact attachment quantity"),
    ("MSUF_Suite_Modules/ToolListWindow.lua", "window.profile == NS.DB", "true", "stale profile action"),
]
with tempfile.TemporaryDirectory(prefix="suite-inventory-mutations-") as directory:
    tree = Path(directory)
    paths = ["MSUF_Suite/Core/InventoryRules.lua", "MSUF_Suite/Core/InventoryLists.lua", "MSUF_Suite_Modules/ToolListWindow.lua",
             test, "tools/tests/suite_inventory_tools_fixture.lua"]
    paths += ["MSUF_Suite_QualityOfLife/" + name + ".lua" for name in ["SharedItems", "InventoryToolsUI", "InventoryData",
        "InventoryArchive", "InventoryProtection", "RestockPlanner", "CraftShopping", "InventoryTransfers", "MailTemplates", "Merchant"]]
    for relative in paths:
        dest = tree / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / relative, dest)
    def run():
        return subprocess.run([lua, str(tree / test), str(tree)], capture_output=True, text=True)
    baseline = run()
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
    for relative, before, after, label in mutations:
        path = tree / relative
        original = path.read_bytes()
        text = original.decode("utf-8")
        assert before in text, label + " anchor disappeared"
        path.write_bytes(text.replace(before, after, 1).encode("utf-8"))
        result = run()
        path.write_bytes(original)
        assert result.returncode != 0, label + " survived regression"
        assert "syntax" not in result.stderr.lower(), label + " only broke syntax"
        print("rejected " + label)
print("inventory safety mutations: %d/%d rejected" % (len(mutations), len(mutations)))
