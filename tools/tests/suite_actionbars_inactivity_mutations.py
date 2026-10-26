"""Causal regressions in the native cooldown inactivity gate."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
TEST = ROOT / "tools/tests/suite_actionbars_inactivity_contract.lua"
SOURCE = (ROOT / "MSUF_Suite_ActionBars/NativeButtons.lua").read_text(encoding="utf-8")
MUTANTS = (
    ("inactive walk gate", "if rec.feedbackInactive and rec.feedbackSlot == rec.slot then", "if false then"),
    ("neutral once", "if not rec.feedbackNeutral then", "if true then"),
    ("charge fallback", "Inactive(info) and Inactive(chargeInfo) and Inactive(lossInfo)",
     "Inactive(info) and Inactive(lossInfo)"),
    ("loss of control fallback", "Inactive(info) and Inactive(chargeInfo) and Inactive(lossInfo)",
     "Inactive(info) and Inactive(chargeInfo)"),
    ("secret table guard", 'if IsSecret(info) or type(info) ~= "table" then return false end',
     'if type(info) ~= "table" then return false end'),
    ("unknown flag fallback", "active == false", "active ~= true"),
    ("secret activity guard", "not IsSecret(active) and active == false", "active == false"),
    ("activity transition", "rec.feedbackInactive, rec.feedbackSlot = inactive, rec.slot",
     "rec.feedbackInactive, rec.feedbackSlot = true, rec.slot"),
    ("slot walk stamp", "rec.feedbackInactive and rec.feedbackSlot == rec.slot", "rec.feedbackInactive"),
    ("new slot neutral stamp", "if not inactive or rec.feedbackSlot ~= rec.slot then",
     "if not inactive then"),
    ("settings invalidation", "    InvalidateFeedback(rec)\n    cooldownOwners", "    cooldownOwners"),
    ("action/page invalidation", 'hooksecurefunc(rec.button, "UpdateAction", NativeInvalidateHook)',
     "-- action invalidation removed"),
    ("show invalidation", 'rec.button:HookScript("OnShow", NativeInvalidateHook)',
     "-- show invalidation removed"),
    ("native usability desaturation", "    rec.feedbackNeutral = nil\n    -- Blizzard has already painted",
     "    -- Blizzard has already painted"),
    ("normal frame secret guard", "or IsSecret(normal)", ""),
    ("disabled feedback hook", "or AB.directDuration or IsSecret(normal)", "or IsSecret(normal)"),
)


def run(environment):
    return subprocess.run([LUA, str(TEST), str(ROOT)], cwd=ROOT, env=environment,
                          capture_output=True, text=True)


baseline = run(os.environ.copy())
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for name, old, new in MUTANTS:
    assert SOURCE.count(old) == 1, (name, SOURCE.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-actionbar-inactivity-") as directory:
        target = Path(directory) / "NativeButtons.lua"
        target.write_text(SOURCE.replace(old, new, 1), encoding="utf-8")
        result = run(dict(os.environ, SUITE_ACTIONBARS_NATIVE_SOURCE=str(target)))
        assert result.returncode != 0, f"Undetected regression: {name}"
        assert "stack traceback" in result.stderr, result.stdout + result.stderr
    print(f"ok   {name}")
print(f"ActionBars inactivity mutations: {len(MUTANTS)} regressions detected")
