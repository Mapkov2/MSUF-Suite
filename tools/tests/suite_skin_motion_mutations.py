"""The lifecycle contract must fail when each reviewed defect is restored."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
CONTRACT = ROOT / "tools/tests/suite_skin_motion_contract.lua"
CASES = [
    ("idle-driver", "Rendering/Motion.lua", 'clock:SetScript("OnUpdate", nil)',
     '-- driver wrongly left attached', "hover leave retained a driver"),
    ("combat-pressed", "Rendering/Motion.lua",
     'for record in pairs(Motion.engaged) do Motion.Clear(record) end',
     '-- settled gestures wrongly left pressed', "combat left an idle pressed control stuck"),
    ("disabled-hover", "Rendering/SurfaceMotion.lua",
     'and (not Safety.HasMethod(target, "IsEnabled") or Safety.Read(target, "IsEnabled") == true)',
     '', "disabled tooltip hover restarted motion"),
    ("late-visible-adoption", "Rendering/SurfaceMotion.lua",
     '    Paint(record)\nend\nNS.Surface.SetMotionProvider',
     '    Paint(record)\n    if record.window then Show(state.target) end\nend\nNS.Surface.SetMotionProvider',
     "late visible-window adoption restarted a fade without OnShow"),
    ("single-opening-alpha", "Rendering/SurfaceMotion.lua",
     'Motion.Set(record, 7, 1, completeFade and 1 or 0)', 'Motion.Set(record, 7, 1, 0)',
     "native opening multiplied root and surface alpha fades"),
    ("content-retarget-opacity", "Rendering/ContentMotion.lua",
     'record.alpha:SetFromAlpha(from)', 'record.alpha:SetFromAlpha(0)',
     "content-ready retarget flashed back to transparent"),
    ("repaint-reveal-alpha", "Rendering/SurfaceMotion.lua",
     'record.fillAlpha = record.fillAlpha or tonumber(Safety.Read(state.fill, "GetAlpha")) or 1',
     'record.fillAlpha = tonumber(Safety.Read(state.fill, "GetAlpha")) or 1',
     "material repaint compounded reveal opacity"),
    ("repaint-highlight-alpha", "Rendering/SurfaceMotion.lua",
     'record.nativeHighlightAlpha = record.nativeHighlightAlpha or tonumber(Safety.Read(state.highlight, "GetAlpha")) or 1',
     'record.nativeHighlightAlpha = tonumber(Safety.Read(state.highlight, "GetAlpha")) or 1',
     "off did not restore native static hover"),
    ("native-update-order", "Rendering/SurfaceMotion.lua", 'Travel(group.selected, record)',
     '-- native new-before-old updates wrongly ignored', "new-before-old selection skipped travel"),
    ("current-position", "Rendering/SurfaceMotion.lua", '(previous.carryX or 0) * ratio',
     '0', "rapid selection jumped"),
    ("static-hover", "Rendering/SurfaceMotion.lua",
     'if state.kind ~= "button" then NS.Surface.RefreshInteractiveHover(state, state.geometry) end',
     '-- static hover wrongly left transparent', "turning off motion erased ordinary standalone hover"),
    ("host-duplicate", "Core/PublicAPIMethods.lua", 'scope.client.name == "MidnightSimpleUnitFrames" and spec.motion == nil',
     'false', "host shell received duplicate open motion"),
    ("content-release", "Core/PublicAPIMethods.lua", 'local content = PublicAPI.StopContent(ContentOwner(scope, target), target)',
     'local content = false', "content-only target release was asymmetric"),
    ("content-pending", "Rendering/ContentMotion.lua", 'record.group:Stop()\n    record.token = nil',
     'record.token = nil', "pending results kept fading"),
    ("content-dedup", "Rendering/ContentMotion.lua", 'local unchanged = record and record.token == token',
     'local unchanged = false', "duplicate completed paint restarted fade"),
    ("palette-retarget", "Rendering/Motion.lua", 'if not (preservePalette and record.palette) then',
     'if true then', "rapid palette retarget lost the displayed color"),
    ("descendant-owner", "Core/PublicAPIMethods.lua",
     'if entry and entry.menu then return entry.owner end',
     'if false then return entry.owner end', "descendant signal and watcher used different owners"),
    ("host-palette-policy", "Rendering/PaletteMotion.lua",
     ' or state.spec.paletteMotion == true and Motion.Enabled()',
     '', "host palette motion duplicated host gestures"),
    ("palette-picker", "Rendering/PaletteMotion.lua", 'record.epoch ~= Palette.epoch and ',
     '',  "direct color-picker edit retained palette interpolation"),
]


def run(env):
    return subprocess.run([LUA, str(CONTRACT), str(ROOT), "Mainline"], cwd=ROOT,
                          env=env, capture_output=True, text=True, errors="replace")


baseline = run(dict(os.environ))
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
with tempfile.TemporaryDirectory(prefix="suite-motion-red-") as temporary:
    scratch = Path(temporary).resolve()
    assert scratch.parent == Path(tempfile.gettempdir()).resolve()
    for name, file, before, after, expected in CASES:
        original = (ROOT / "MSUF_Suite_Skin" / file).read_text(encoding="utf-8")
        assert original.count(before) == 1, name + ": mutation anchor changed"
        override = scratch / name
        target = override / file
        target.parent.mkdir(parents=True)
        target.write_text(original.replace(before, after), encoding="utf-8")
        env = dict(os.environ, SUITE_MOTION_OVERRIDE_ROOT=str(override))
        result = run(env)
        output = result.stdout + result.stderr
        assert result.returncode != 0 and expected in output, name + ": " + output
print("Suite skin motion: %d red-without-fix cases passed" % len(CASES))
