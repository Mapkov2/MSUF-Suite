"""Causal invalidation checks for derived catalog reuse; native reads remain live."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
SOURCE = (ROOT / "MSUF_Suite_CooldownManager/Catalog.lua").read_text(encoding="utf-8")
TEST = ROOT / "tools/tests/suite_cooldown_manager_data_contract.lua"
MUTANTS = (
    ("fresh metadata", "reusable and not changed and", "reusable and"),
    ("native order", "and not orderChanged and", "and"),
    ("saved layout", "and built.layout == layout", ""),
    ("specialization", "and Catalog.specTag == tag", ""),
    ("guide defaults", "and built.guide == guide", ""),
    ("interrupted pass", "    built.valid = false", "    -- cache not invalidated"),
    ("pending changes", "if reusable then changed, orderChanged = false, false end", "changed, orderChanged = false, false"),
    ("generation", "        Catalog.generation = Catalog.generation + 1\n        return false", "        return false"),
    ("settled result", "        return false\n    end\n    local order = ApplyLayout(layout)",
     "        return true\n    end\n    local order = ApplyLayout(layout)"),
)


def run(env):
    return subprocess.run([LUA, str(TEST), str(ROOT)], cwd=ROOT, env=env, capture_output=True, text=True)


baseline = run(os.environ.copy())
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for name, old, new in MUTANTS:
    assert SOURCE.count(old) == 1, (name, SOURCE.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-catalog-reuse-") as folder:
        target = Path(folder) / "Catalog.lua"
        target.write_text(SOURCE.replace(old, new), encoding="utf-8")
        result = run(dict(os.environ, SUITE_CDM_CATALOG_SOURCE=str(target)))
        assert result.returncode != 0 and "stack traceback" in result.stderr, name
    print("ok  " + name)
print(f"Catalog reuse: {len(MUTANTS)} regressions detected")
