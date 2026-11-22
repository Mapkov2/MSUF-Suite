"""Verify combat text defaults through each actual Suite installer layout."""

import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA, lua_literal

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_forever_factory_preview import decode
from build_modern_dark_factory import literal


CHECK = r"""
local root, fixtures = arg[1], FIXTURES
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
for _, forever in ipairs({ true, false }) do
    local Suite = H.Setup({ root = root, forever = forever,
        addons = { MSUF_Suite_QualityOfLife = true } })
    MSUF_TryDecodeCompactString = function(text)
        local factory = assert(fixtures[text], "missing real factory: " .. text:sub(1, 40))
        return Suite.CopyValue(factory)
    end
    local S = Suite.Suite
    for _, legacyXP in ipairs({ true, false }) do
        local legacyText = { showXP = legacyXP, gainSide = 1 }
        local oldProfile = { suite = {
            revision = S.MigrationRevision - 1, modules = { floatingCombatText = legacyText },
        } }
        S.Normalize(oldProfile)
        assert(legacyText.showXP == false, "old settings still display duplicate XP")
        assert(legacyText.showLevelUp == legacyXP, "upgrade changed the old level-up preference")
        assert(legacyText.gainSide == 1 and legacyText.xpSide == 1, "upgrade lost existing progression placement")
        legacyText.showXP = true
        S.Normalize(oldProfile)
        assert(legacyText.showXP, "normalization undid XP re-enabled by the player")
    end

    local old = Suite.DB.suite.modules.floatingCombatText
    old.enabled, old.font = false, "EXPLICIT_FONT"
    Suite.Suite.Normalize(Suite.DB)
    assert(old.enabled == false and old.font == "EXPLICIT_FONT", "existing selection changed")

    assert(Suite.Installer.Open())
    local window = MSUFSuiteInstallFrame
    for _, layout in ipairs({ "suite", "classic", "forever", "modernDark", "blizzard", "darkRaid" }) do
        local staged = assert(window.previewProfile(layout))
        local config = staged.suite.modules.floatingCombatText
        assert(config.enabled and config.font == "", "wrong combat text default for " .. layout)
        assert(config.showXP == false and config.showLevelUp == true and config.xpSide == 1,
            "wrong XP defaults for " .. layout)
        assert(config.hitSide == (forever and 1 or 3) and config.hitSource == (forever and 1 or 3),
            "wrong combat text placement or hit scope for " .. layout)
    end
    assert(old.enabled == false and old.font == "EXPLICIT_FONT", "preview changed the current profile")
    assert(#H.reported == 0, table.concat(H.reported, "\n"))
end
print("Floating combat text preset defaults passed on Forever and Mainline")
"""


def main():
    root = Path(sys.argv[1]).resolve()
    core = root / "MSUF_Suite/Core"
    fixtures = {}
    for filename, name in (
        ("RetailFactory.lua", "RetailFactoryModuleCompact"),
        ("ForeverFactory.lua", "ForeverFactoryModuleCompact"),
        ("RetailProfile.lua", "RetailProfileModuleCompact"),
        ("ModernDarkFactory.lua", "ModernDarkModuleCompact"),
        ("BlizzardFactory.lua", "BlizzardModuleCompact"),
        ("DarkRaidFactory.lua", "DarkRaidModuleCompact"),
    ):
        text = literal(core / filename, "Suite." + name)
        fixtures[text[7:]] = decode(text, "MSUFM1:MSUF3:")
    script = CHECK.replace("FIXTURES", lua_literal(fixtures), 1)
    return subprocess.run([LUA, "-", str(root)], input=script, text=True, cwd=root).returncode


if __name__ == "__main__":
    sys.exit(main())
