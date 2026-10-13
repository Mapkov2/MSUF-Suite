"""Exercise retained callback, native ownership and profile lifecycle boundaries."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(sys.argv[1]).resolve()
LUA = (os.environ.get("MSUF_LUA51") or os.environ.get("MSUF_LUA") or shutil.which("lua5.1")
       or r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
GROUPS = {
    "bank_cursor": ("foreign", "unreadable", "empty", "original"),
    "bank_disable": ("module_disabled", "view_disabled", "original"),
    "currency_menu": ("profile", "clear_profile", "reopen", "disabled", "combat", "original"),
    "datatext_movers": ("bounded",),
    "hybrid_epoch": ("reenable",),
    "hybrid_replacement": ("mask", "frame"),
    "keystone": ("no_guild", "secret_guild", "ungrouped", "guild", "group"),
    "merchant_refund": ("accept_replaced", "cancel_foreign", "cancel_unreadable", "cancel_empty",
                        "cancel_original", "accept_disabled", "accept_profile", "original"),
    "nameplate_flags": ("stacking", "simplified", "all_keep", "unchanged"),
    "options_color": ("retarget", "profile", "original", "default", "removed"),
    "options_secure": ("disabled_macro", "macro_original", "click_disabled", "click_retarget", "click_original"),
    "options_source": ("profile", "profile_aba", "combat", "original"),
    "options_copy": ("profile", "profile_aba", "original", "save_profile", "save_aba", "save_original"),
    "options_crests": ("profile", "profile_aba", "clear_profile", "original", "stage_profile", "stage_clear", "stage_original"),
}
cases = [(case, variant, "") for case, variants in GROUPS.items() for variant in variants]
cases += [("datatext_overlay", variant, flavor) for flavor in ("Mainline", "Forever")
          for variant in ("plain", "secure", "hidden_slot", "hidden_bar")]
cases += [("meter_drag", variant, "") for variant in
          ("original", "profile", "profile_aba", "combat", "hidden", "configswap")]
cases += [("skin_colors", schema + "_" + variant, "") for schema in ("appearance", "inline", "shortcut")
          for variant in ("original", "profile", "profile_aba", "reopen")]
failures = []
cases_script = Path(__file__).with_name("longterm_modules_cases.lua")
for case, variant, flavor in cases:
    script = cases_script.with_name("longterm_meter_drag.lua") if case == "meter_drag" else cases_script
    if case == "skin_colors":
        script = cases_script.with_name("longterm_skin_colors.lua")
    result = subprocess.run([LUA, str(script), str(ROOT),
                             case, variant, flavor], cwd=ROOT, capture_output=True, text=True, timeout=60)
    if result.returncode:
        failures.append((case, variant, flavor, result.stdout + result.stderr))
for case, variant, flavor, output in failures:
    print(f"FAIL {case}/{variant}/{flavor}:\n{output}")
print(f"Suite long-term module lifecycle: {len(cases)-len(failures)}/{len(cases)} cases passed")
raise SystemExit(1 if failures else 0)
