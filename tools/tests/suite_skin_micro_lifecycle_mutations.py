"""Micro Bar lifecycle batching and portrait invalidation must reject regressions."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
CONTRACT = ROOT / "tools/tests/suite_skin_micro_bar_combat_end_contract.lua"
CASES = [
    ("eager-lifecycle", "MicroMenu.lua",
     "        C_Timer.After(0, FlushButtonVisuals)", "        FlushButtonVisuals()",
     "lifecycle burst painted before its flush", False),
    ("duplicate-flush", "MicroMenu.lua",
     "        if visualRefreshPending then return end", "        -- Missing coalescing guard.",
     "lifecycle burst scheduled more than one flush", False),
    ("delayed-hover", "MicroMenu.lua",
     "local function OnButtonEnter(button)\n    OnButtonInteraction(button)",
     "local function OnButtonEnter(button)\n    OnButtonVisualLifecycle(button)",
     "OnEnter delayed input feedback", False),
    ("delayed-press", "MicroMenu.lua",
     'button:HookScript("OnMouseDown", OnButtonInteraction)',
     'button:HookScript("OnMouseDown", OnButtonVisualLifecycle)',
     "OnMouseDown delayed input feedback", False),
    ("duplicate-input", "MicroMenu.lua",
     "local function RefreshButtonState(button)\n    pendingButtons[button] = nil",
     "local function RefreshButtonState(button)",
     "OnEnter left a duplicate lifecycle repaint", False),
    ("duplicate-full-pass", "MicroMenu.lua",
     "    for button in pairs(pendingButtons) do pendingButtons[button] = nil end",
     "    -- Pending lifecycle work incorrectly survives a full pass.",
     "a full pass left a duplicate lifecycle repaint", False),
    ("lost-combat-burst", "MicroMenu.lua",
     "        OnButtonInteraction(button)\n    end\nend\n\nlocal function OnButtonVisualLifecycle",
     "        if not NS.IsCombatLocked() then OnButtonInteraction(button) end\n"
     "    end\nend\n\nlocal function OnButtonVisualLifecycle",
     "a lifecycle burst meeting combat lost its stale button", False),
    ("eager-portrait", "OwnedMicroBar.lua",
     "    if portraitEnabled and portraitDirty then", "    if portraitEnabled then",
     "quiet combat end resolved an unchanged portrait", True),
    ("lost-portrait", "OwnedMicroBar.lua",
     "        portraitDirty = true\n        if portraitEnabled", "        portraitDirty = false\n        if portraitEnabled",
     "combat end did not refresh the portrait an in-combat update skipped", True),
    ("flashing-highlight", "MicroMenu.lua",
     "        Dispatch(FadeCleanHighlight, button)\n", "",
     "a lifecycle call left the clean highlight visible until its flush", False),
    ("blizzard-highlight", "MicroMenu.lua",
     "    if activeButtons[button] and UsesCleanStyle(Settings()) then", "    if activeButtons[button] then",
     "a lifecycle call faded a Blizzard-style highlight", False),
    ("unregistered-portraits", "OwnedMicroBar.lua",
     '        eventFrame:RegisterEvent("PORTRAITS_UPDATED")\n', "",
     "combat end did not refresh the portrait a PORTRAITS_UPDATED in combat invalidated", True),
    ("unhandled-portraits", "OwnedMicroBar.lua",
     ' or event == "PORTRAITS_UPDATED" then', " then",
     "a PORTRAITS_UPDATED in combat deferred the bar's full pass", True),
    ("dirty-immediate-portrait", "OwnedMicroBar.lua",
     '            SetPortraitTexture(portrait, "player")\n            portraitDirty = false',
     '            SetPortraitTexture(portrait, "player")',
     "an immediate portrait update stayed dirty", True),
    ("warm-shell-portrait", "OwnedMicroBar.lua",
     '    if portraitDirty then', '    if true then',
     "warm layout resolved an unchanged portrait", False),
    ("hidden-portrait-invalidation", "OwnedMicroBar.lua",
     '        portraitDirty = true\n        if portraitEnabled',
     '        if portraitEnabled then portraitDirty = true end\n        if portraitEnabled',
     "re-enabled portrait lost its hidden invalidation", False),
    ("disabled-portrait-invalidation", "OwnedMicroBar.lua",
     '    portraitEnabled = false\n    portraitDirty = true',
     '    portraitEnabled = false\n    portraitDirty = false',
     "reacquisition reused a portrait from before disable", False),
    ("world-portrait-invalidation", "OwnedMicroBar.lua",
     '        if event == "PLAYER_ENTERING_WORLD" then portraitDirty = true end', '',
     "world entry reused the previous world portrait", False),
    ("dirty-shell-portrait", "OwnedMicroBar.lua",
     '    if portraitDirty then\n        SetPortraitTexture(portrait, "player")\n        portraitDirty = false',
     '    if portraitDirty then\n        SetPortraitTexture(portrait, "player")',
     "warm layout resolved an unchanged portrait", False),
]


def run(overrides=None, portrait_only=False, forever=False):
    environment = dict(os.environ)
    environment.pop("SUITE_MICRO_BASELINE", None)
    environment.pop("SUITE_MICRO_PORTRAIT_ONLY", None)
    environment["SUITE_MICRO_FOREVER"] = "1" if forever else "0"
    if overrides:
        environment["SUITE_MICRO_BASELINE"] = str(overrides)
    if portrait_only:
        environment["SUITE_MICRO_PORTRAIT_ONLY"] = "1"
    return subprocess.run([LUA, str(CONTRACT), str(ROOT)], cwd=ROOT, env=environment,
                          capture_output=True, text=True, errors="replace")


for forever in (False, True):
    baseline = run(forever=forever)
    assert baseline.returncode == 0, baseline.stdout + baseline.stderr
with tempfile.TemporaryDirectory(prefix="suite-micro-lifecycle-") as temporary:
    for name, file, before, after, expected, portrait_only in CASES:
        original = (ROOT / "MSUF_Suite_Skin/Adapters" / file).read_text(encoding="utf-8")
        assert original.count(before) == 1, name + ": mutation anchor changed"
        scratch = Path(temporary) / name
        target = scratch / "MSUF_Suite_Skin/Adapters" / file
        target.parent.mkdir(parents=True)
        target.write_text(original.replace(before, after), encoding="utf-8")
        result = run(scratch, portrait_only)
        output = result.stdout + result.stderr
        assert result.returncode != 0 and expected in output, name + ": " + output
print("Suite skin Micro Bar lifecycle: %d red-without-fix cases passed" % len(CASES))
