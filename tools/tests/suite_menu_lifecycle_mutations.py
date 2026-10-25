"""Each A7 regression must fail in a source overlay, without changing the checkout."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
motion = "suite_menu_lifecycle_budget_contract.lua"
options = "suite_options_load_budget_contract.lua"
cases = [
    ("page-tree", "MSUF_Suite_Options/Menu/Register.lua",
     '    if client and client.AnimateContent then client:AnimateContent(frame, token) end',
     '    Suite.Skin.RegisterMenu(frame, "menuContent")\n'
     '    if client and client.AnimateContent then client:AnimateContent(frame, token) end',
     motion, "page switch walked descendants"),
    ("page-reopen", "MSUF_Suite/Core/HostBridgeMenu.lua",
     '        frame:HookScript("OnShow", Shown)', '', motion, "cached page reopen lost or duplicated its fade"),
    ("secret-menu-mode", "MSUF_Suite_Skin/Core/PublicAPIMethods.lua",
     '    if not NS.Safety.Public(contentOnly) then return false, "invalid-options" end', '',
     motion, "secret menu mode was accepted"),
    ("hidden-skin", "MSUF_Suite_Skin/Core/PublicAPI.lua",
     '    if DeferHidden(scope, target, entry) then return true, "applied" end', '',
     motion, "hidden window built skin art"),
    ("first-selection", "MSUF_Suite_Skin/Core/PublicAPI.lua",
     '        entry.control.spec.active = entry.active', '',
     motion, "first show repeated the pending selection paint"),
    ("summary-eager", "MSUF_Suite_Options/Menu/Controls.lua",
     '-- One W.SettingsRows row for a catalog rule.',
     'for id in pairs(P.catalog) do P.SummaryPriority(id, "") end\n\n'
     '-- One W.SettingsRows row for a catalog rule.', options, "Options load execution budget exceeded"),
    ("categories-eager", "MSUF_Suite_Options/Pages/QualityOfLife.lua",
     'P.QualityOfLifeCategories = CATEGORIES',
     'P.SortQualityOfLifeCategories()\nP.QualityOfLifeCategories = CATEGORIES',
     options, "hidden QoL categories were sorted during load"),
]
for name, relative, old, new, fixture, expected in cases:
    source = (root / relative).read_text(encoding="utf-8")
    assert source.count(old) == 1, f"{name}: mutation anchor changed"
    with tempfile.TemporaryDirectory(prefix="suite-a7-") as directory:
        target = Path(directory) / relative
        target.parent.mkdir(parents=True)
        target.write_text(source.replace(old, new, 1), encoding="utf-8")
        env = dict(os.environ, SUITE_A7_BASELINE=directory)
        env.pop("SUITE_A7_MEASURE_ONLY", None)
        env.pop("SUITE_A7_RECEIPT", None)
        result = subprocess.run([lua, str(root / "tools/tests" / fixture), str(root), "Mainline"],
                                cwd=root, env=env, capture_output=True, text=True, errors="replace")
        output = result.stdout + result.stderr
        assert result.returncode and expected in output, f"{name}: expected causal failure {expected!r}\n{output}"
        print(f"rejected {name}: {expected}")
print("A7 menu lifecycle: 7 causal mutations rejected")
