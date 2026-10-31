"""Hidden-window deferral and duplicate native reset work have behavioral guards."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
CASES = [
    ("hidden-major", "MajorWindows.lua",
     'if Kit.DeferHidden(root, spec, ApplyGroupForOwners, spec, nil, nil, 10) then', 'if false then',
     "hidden major window performed initial cosmetic traversal", False),
    ("hidden-catalog", "GenericWindowsCatalog.lua",
     'and Kit.DeferHidden(frame, request, DeferredEntryFrame, request, index) then', 'and false then',
     "hidden catalog frame performed a tree pass", False),
    ("protected-catalog-root", "GenericWindowsCatalog.lua",
     ' and CanSkin(frame)\n', '\n',
     "a hidden protected root waited for its OnShow instead of reading protected", False),
    ("hud-catalog-root", "GenericWindowsCatalog.lua",
     'if entry.category ~= "hud" and ', 'if ',
     "a hidden HUD root waited for an OnShow in combat instead of painting at once", False),
    ("hidden-row", "GenericWindowsFrames.lua",
     '''    if Kit.IsHidden(registration.box[1]) then
        registration.catchUp = true
        Kit.DeferHidden(registration.box[1], registration, RefreshVisibleRows, registration)
        return
    end
    if registration.catchUp then
        RefreshVisibleRows(registration)
        return
    end
''', '' ,
     "hidden row initializations painted", False),
    ("canceled-owner", "AdapterKit.lua",
     '    for _, requests in pairs(hiddenRequests) do requests[owner] = nil end', '',
     "same-show cancellation dispatched a canceled owner", False),
    ("clean-reopen-allocation", "AdapterKit.lua",
     'not requests or not next(requests) or Hidden(frame)', 'not requests or Hidden(frame)',
     "clean OnShow allocated pending request tables", False),
    ("retained-scrollbox", "GenericWindowsFrames.lua",
     'registration.box = setmetatable({ scrollBox }, { __mode = "v" })', 'registration.box = { scrollBox }',
     "hidden row registration retained a discarded ScrollBox", False),
    ("sibling-reapply", "GenericWindowsCatalog.lua",
     'Kit.Isolate(RefreshEntryFrame, request, index)', 'Kit.Isolate(GenericWindows.ApplyEntry, request.entry, request.owner)',
     "showing a sibling repeated the visible sibling's generic pass", False),
    ("lost-row-combat", "GenericWindowsFrames.lua",
     '        NS.CombatGate.RunOrDefer(registration.key, registration.refreshRows)', '',
     "combat first show lost the pending ScrollBox catchup", False),
    ("common-final-order", "CommonArt.lua",
     'if Kit.DeferHidden(Resolve("PVEFrame"), state, ApplyDeferred, state, nil, nil, 20) then return true, "waiting" end',
     'if Kit.DeferHidden(Resolve("PVEFrame"), state, ApplyDeferred, state, nil, nil, -20) then return true, "waiting" end',
     "hidden Group Finder reversed the final CommonArt navigation style", False),
    ("common-lost-combat", "CommonArt.lua",
     '        NS.CombatGate.RunOrDefer(registration.key, registration.refreshRows)', '',
     "CommonArt did not restore every deferred row after combat", False),
    ("incomplete-entry-error", "GenericWindowsCatalog.lua",
     'if not request.complete or request.error then state = "error"', 'if request.error then state = "error"',
     "reveal erased an incomplete catalog entry failure", False),
    ("deferred-entry-error", "GenericWindowsCatalog.lua",
     '        request.error = true\n', '',
     "sibling reveal erased a deferred frame error", False),
    ("common-card-cancellation", "CommonArt.lua",
     '''    if Kit.IsHidden(root) then
        Kit.DeferHidden(root, state, ApplyDeferred, state, nil, nil, 20)
        return
    end''',
     '    if Kit.DeferHidden(root, state, ApplyDeferred, state, nil, nil, 20) then return end',
     "hidden Group Finder reversed the final CommonArt navigation style", False),
    ("retained-catalog-metrics", "GenericWindowsCatalog.lua",
     '    result.applied, result.reason = applied, reason',
     '    result.applied, result.reason = applied, reason\n    result.retained = metrics',
     "catalog retained a frame pass's scratch metrics", False),
    ("catalog-global-scan", "GenericWindowsCatalog.lua",
     '    request.entry, request.frames, request.complete, request.error = entry, {}, false, false',
     '    request.entry, request.frames, request.complete, request.error = entry, {}, false, false\n    Kit.CancelHidden(request)',
     "catalog apply scanned unrelated hidden windows", False),
    ("duplicate-full-reset", "MicroMenu.lua",
     'if resetRoot == root and root == activeRoot', 'if false and root == activeRoot',
     "duplicate reset did not reduce VM and native protection work", True),
    ("stale-reset-permission", "MicroMenu.lua",
     '    resetRoot, resetExpiryPending = nil, false', '    resetExpiryPending = false',
     "later-frame reset reused stale skin permission", True),
    ("partial-reset-reuse", "MicroMenu.lua",
     'if applied and result == "applied" and root == activeRoot', 'if applied and root == activeRoot',
     "partial native reset suppressed the next full retry", True),
]


def run(scratch, micro):
    env = dict(os.environ)
    env.pop("SUITE_SKIN_COLD_BASELINE", None)
    env.pop("SUITE_MICRO_BASELINE", None)
    env.pop("SUITE_MICRO_FOREVER", None)
    env.pop("SUITE_MICRO_PORTRAIT_ONLY", None)
    if scratch:
        env["SUITE_MICRO_BASELINE" if micro else "SUITE_SKIN_COLD_BASELINE"] = str(scratch)
    contract = "suite_skin_micro_bar_combat_end_contract.lua" if micro else "suite_skin_generic_windows_contract.lua"
    return subprocess.run([LUA, str(ROOT / "tools/tests" / contract), str(ROOT)], cwd=ROOT,
                          env=env, capture_output=True, text=True, errors="replace")


for micro in (False, True):
    result = run(None, micro)
    assert result.returncode == 0, result.stdout + result.stderr
with tempfile.TemporaryDirectory(prefix="suite-skin-cold-") as temporary:
    for name, file, before, after, expected, micro in CASES:
        source = (ROOT / "MSUF_Suite_Skin/Adapters" / file).read_text(encoding="utf-8")
        assert source.count(before) == 1, name + ": mutation anchor changed"
        scratch = Path(temporary) / name
        target = scratch / "MSUF_Suite_Skin/Adapters" / file
        target.parent.mkdir(parents=True)
        target.write_text(source.replace(before, after), encoding="utf-8")
        result = run(scratch, micro)
        assert result.returncode != 0 and expected in result.stdout + result.stderr, name + ": " + result.stdout + result.stderr
print("Suite skin cold paths: %d behavioral mutations rejected" % len(CASES))
