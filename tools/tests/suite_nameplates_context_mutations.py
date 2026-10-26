"""Causal regressions for context-only nameplate painting and font reads."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
SKIN = ROOT / "MSUF_Suite_Nameplates/Skin.lua"
TEXT = ROOT / "MSUF_Suite_Nameplates/Text.lua"
CONTEXT_TEST = ROOT / "tools/tests/suite_nameplates_context_contract.lua"
TEXT_TEST = ROOT / "tools/tests/suite_nameplates_text_contract.lua"
MUTANTS = (
    (SKIN, CONTEXT_TEST, "roster presentation", 'not FULL_CONTEXT[event], event == "PLAYER_SPECIALIZATION_CHANGED"', "false"),
    (SKIN, CONTEXT_TEST, "quest invalidation", "Roles.ClearQuest()\n    RefreshActive(module", "RefreshActive(module"),
    (SKIN, CONTEXT_TEST, "group name filtering", "                    FilterFriendlyName(uf, prefix)", "                    -- filter omitted"),
    (SKIN, CONTEXT_TEST, "lieutenant second pass", "RefreshActive(self, contextOnly)", "RefreshActive(self)"),
    (SKIN, CONTEXT_TEST, "lieutenant discovery", "RefreshActive(self, true)", "RefreshActive(self)"),
    (SKIN, CONTEXT_TEST, "specialization colors", 'if auraColors then AuraColors.Apply(uf, unit, prefix == "enemy") end', ""),
    (SKIN, CONTEXT_TEST, "forbidden specialization plate", '    RefreshActive(module, not FULL_CONTEXT[event], event == "PLAYER_SPECIALIZATION_CHANGED")',
     '    RefreshActive(module, not FULL_CONTEXT[event])\n    if event == "PLAYER_SPECIALIZATION_CHANGED" then RepaintAuraColors(module) end'),
    (SKIN, CONTEXT_TEST, "cold specialization fallback", "if styled and not visual then Paint(uf)",
     'if styled and not visual then Paint(uf)\n                    if auraColors then AuraColors.Apply(uf, unit, prefix == "enemy") end'),
    (SKIN, CONTEXT_TEST, "cold friendly name queries", "if styled and not visual then Paint(uf)",
     "if styled and not visual then\n                    FilterFriendlyName(uf, prefix)\n                    Paint(uf)"),
    (SKIN, CONTEXT_TEST, "level transition", "PLAYER_LEVEL_UP = true", "PLAYER_LEVEL_UP = false"),
    (SKIN, CONTEXT_TEST, "specialization kick-ready", 'if event == "PLAYER_SPECIALIZATION_CHANGED" then RepaintCasts() end', ""),
    (TEXT, TEXT_TEST, "no-write font read", "local appliedPath, appliedSize, appliedFlags = path, nativeSize, flags",
     "local appliedPath, appliedSize, appliedFlags = region:GetFont()"),
    (TEXT, TEXT_TEST, "post-write font read", "        appliedPath, appliedSize, appliedFlags = region:GetFont()", ""),
    (TEXT, TEXT_TEST, "pooled recapture", "elseif original.restored then", "elseif false then"),
)


def run(test, environment):
    return subprocess.run([LUA, str(test), str(ROOT)], cwd=ROOT, env=environment, capture_output=True, text=True)


for test in (CONTEXT_TEST, TEXT_TEST):
    baseline = run(test, os.environ.copy())
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for source, test, name, old, new in MUTANTS:
    code = source.read_text(encoding="utf-8")
    assert code.count(old) == 1, (name, code.count(old))
    before, match, after = code.rpartition(old)
    assert match
    with tempfile.TemporaryDirectory(prefix="suite-nameplate-context-") as directory:
        target = Path(directory) / source.name
        target.write_text(before + new + after, encoding="utf-8")
        key = "SUITE_NAMEPLATES_SKIN_OVERRIDE" if source == SKIN else "SUITE_NAMEPLATES_TEXT_OVERRIDE"
        result = run(test, dict(os.environ, **{key: str(target)}))
        assert result.returncode != 0, f"Undetected regression: {name}"
        assert "stack traceback" in result.stderr, result.stdout + result.stderr
    print(f"ok   {name}")
print(f"Suite nameplate mutations: {len(MUTANTS)} causal regressions detected")
