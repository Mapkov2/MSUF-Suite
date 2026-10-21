"""Causal regressions for automatic specialization layout saving."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
automatic = "suite_cdm_automatic_spec_layout_contract.lua"
cases = [
    ("default-off", "MSUF_Suite/Core/Catalog/CooldownManager.lua",
     'Bool("specPositions", "Save bar layout per specialization", true)',
     'Bool("specPositions", "Save bar layout per specialization", false)', automatic,
     "spec layouts must save automatically without opting in"),
    ("migration-missing", "MSUF_Suite/Core/Suite.lua",
     '    { run = Steps.CooldownSpecLayouts },', '', automatic,
     "the installed false/empty profile must start saving automatically"),
    ("migration-repeats", "MSUF_Suite/Core/Suite.lua",
     '    Steps.ObjectivesCollapseState, NS.NameplateStyle.RepairGeometry,',
     '    Steps.ObjectivesCollapseState, NS.NameplateStyle.RepairGeometry, Steps.CooldownSpecLayouts,', automatic,
     "a later explicit shared-layout choice survives normalization"),
    ("event-missing", "MSUF_Suite_CooldownManager/Events.lua",
     '    Settings.SpecPositions()', '', automatic,
     "the switch itself saves the outgoing layout"),
    ("restore-missing", "MSUF_Suite_CooldownManager/Settings.lua",
     'if saved[suffix] ~= nil then values[key] = saved[suffix] end',
     'if saved[suffix] ~= nil then values[key] = nil end', automatic,
     "the first spec's position, rows and size return without any menu action"),
    ("capture-forgets-choice", "MSUF_Suite/Core/Catalog/CooldownManager.lua",
     'essOnViewer = true, specPositions = true }', 'essOnViewer = true }',
     "suite_cooldown_manager_spec_positions_contract.lua", "first-run capture must preserve an explicit shared-layout choice"),
]

for name, relative, before, after, contract, message in cases:
    source = (root / relative).read_text(encoding="utf-8")
    assert source.count(before) == 1, (name, "mutation anchor drifted")
    with tempfile.TemporaryDirectory(prefix="suite-cdm-spec-mutation-") as scratch:
        target = Path(scratch) / relative
        target.parent.mkdir(parents=True)
        target.write_text(source.replace(before, after), encoding="utf-8")
        env = dict(os.environ, BH3_BASELINE=scratch, BH3_FILE=relative)
        result = subprocess.run([lua, str(root / "tools/tests" / contract), str(root)],
                                cwd=root, env=env, capture_output=True, text=True, errors="replace")
        output = result.stdout + result.stderr
        assert result.returncode != 0 and message in output, (name, result.returncode, output)
        print("caught " + name)
print(f"suite_cdm_automatic_spec_layout_mutations: {len(cases)} causal mutations detected")
