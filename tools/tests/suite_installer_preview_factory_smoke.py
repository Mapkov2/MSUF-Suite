"""Actual compact factories: both layouts on Retail and Forever, read only."""
import re
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA, lua_literal
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_forever_factory_preview import decode


def compact(core, name):
    for path in core.glob("*.lua"):
        source = path.read_text(encoding="utf-8-sig")
        if name == "RetailProfileModuleCompact" and "Suite." + name + " =" in source:
            block = source.split("Suite." + name + " =", 1)[1].split("Suite.RetailProfileSkinCompact", 1)[0]
            return "".join(re.findall(r"\[\[(.*?)\]\]", block, re.S))
        match = re.search(r"Suite\." + name + r'\s*=\s*(?:\[\[(.*?)\]\]|"([^"]*)")', source, re.S)
        if match:
            return match.group(1) or match.group(2)
    raise AssertionError("missing factory " + name)


CHECK = r'''
local root = assert(arg[1])
local fixtures = FIXTURES
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
for _, forever in ipairs({ false, true }) do
    local Suite = H.Setup({ root = root, forever = forever })
    MSUF_TryDecodeCompactString = function(text)
        return Suite.CopyValue((assert(fixtures[text], "unexpected compact input")))
    end
    for _, layout in ipairs({ "classic", "forever" }) do
        local modules = layout == "classic" and Suite.RetailProfileModuleCompact or Suite.ForeverFactoryModuleCompact
        local profile = assert(Suite.ProfileIO.PrepareProfile(modules, false))
        local frames = assert(Suite.HostBridge.FactoryFramePreview(layout))
        local cachedX, cachedY = frames.bars.classPowerOffsetX, frames.bars.classPowerOffsetY
        local sourceBars = profile.suite.modules.actionbars
        local sourceX, sourcePoint = sourceBars.bar3X, sourceBars.bar3Point
        local scene = Suite.InstallerPreviewModel.Build(profile, frames, layout)
        assert(scene.player.x == 816.5 and scene.player.y == 880 and scene.player.width == 275,
            "bundled player position was not decoded")
        if layout == "classic" or forever then
            assert(scene.resource.x == 816.5 and scene.resource.y == 923 and scene.resource.width == 275,
                "bundled resource does not follow the player's TOPLEFT")
            assert(not scene.playerPower, "factory-only client/layout received a Retail follow-up")
        else
            assert(scene.resource.x == scene.cooldowns.x and scene.resource.width == scene.cooldowns.width,
                "Retail Forever misses its installed resource stack")
            assert(scene.playerPower.y + scene.playerPower.height == scene.cooldowns.y - 4,
                "Retail Forever power stack loses its visible gap")
        end
        if layout == "classic" then
            assert(scene.bar3.x == 2480 and scene.bar3.width == 40 and scene.bar3.height == 502,
                "Modern right bar lost its authored edge position")
            assert(scene.data1.x == 2039 and scene.data1.width == 521, "Modern panel is misplaced")
        else
            assert(not scene.bar5, "Forever permanently hidden bar5 is visible")
            assert(scene.bar3.x == 1039 and scene.bar3.width == 502 and scene.bar3.height == 40,
                "Forever horizontal bar3 is misplaced")
        end
        assert(sourceBars.bar3X == sourceX and sourceBars.bar3Point == sourcePoint
            and frames.bars.classPowerOffsetX == cachedX and frames.bars.classPowerOffsetY == cachedY,
            "overview mutated a source factory")
        assert(Suite.RootDB.installation.status == "pending" and next(H.loaded) == nil
            and #H.appliedScales == 0 and #H.reported == 0, "preview performed installation work")
    end
end
print("installer actual factories: both layouts on both clients, geometry and read-only state passed")
'''


def main():
    root = Path(sys.argv[1])
    fixtures = {}
    for name in ("ClassicFactoryFramesCompact", "ForeverFactoryFramesCompact",
                 "RetailProfileModuleCompact", "ForeverFactoryModuleCompact"):
        value = compact(root / "MSUF_Suite/Core", name)
        modules = "Module" in name
        fixtures[value[7:] if modules else value] = decode(value, "MSUFM1:MSUF3:" if modules else "MSUF3:")
    script = CHECK.replace("FIXTURES", lua_literal(fixtures), 1)
    run = subprocess.run([LUA, "-", str(root)], input=script, text=True,
                         capture_output=True, cwd=root)
    print(run.stdout, end="")
    if run.returncode:
        print(run.stderr, file=sys.stderr, end="")
    return run.returncode


if __name__ == "__main__":
    sys.exit(main())
