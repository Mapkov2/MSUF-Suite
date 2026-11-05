"""Real installer factories keep Glimmer enabled only on Forever, with opt-out."""
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA, lua_literal

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_modern_dark_factory import literal
from build_forever_factory_preview import decode

CHECK = r'''
local root, fixtures = arg[1], FIXTURES
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
for _, forever in ipairs({ false, true }) do
    for _, layout in ipairs({ "forever", "classic", "blizzard" }) do
        local Suite = H.Setup({ root = root, forever = forever,
            addons = { MSUF_Suite_QualityOfLife = true } })
        MSUF_TryDecodeCompactString = function(text)
            if text == "MSUF3:frames" then return Suite.CopyValue(MSUF_DB) end
            return Suite.CopyValue((assert(fixtures[text], "missing real factory fixture: " .. text:sub(1, 40))))
        end
        -- An old profile's deliberate opt-out must survive preparing/installing
        -- a separate factory profile, whose own defaults are independent.
        local old = Suite.DB.suite.modules.glimmer
        old.enabled, old.foreverDefaultApplied, old.style = false, true, 5
        assert(Suite.Installer.Open())
        local window = MSUFSuiteInstallFrame
        window.next.scripts.OnClick()
        window[layout].scripts.OnClick()
        local staged = window.previewProfile(layout).suite.modules.glimmer
        assert(staged.enabled == forever and staged.questSparkle and staged.style == 3,
            layout .. " has incorrect Glimmer defaults")
        assert(Suite.Suite.Availability("glimmer") == forever, "Glimmer availability escaped Forever")
        window.next.scripts.OnClick()
        local row
        for _, candidate in ipairs(window.moduleRows) do
            if candidate.id == "glimmer" then row = candidate end
        end
        assert(row and row.state.text == Suite.Text(forever and "ON" or "OFF"),
            "installer picker disagrees with factory Glimmer default")
        local ok, why = Suite.Installer.Apply()
        assert(ok, why)
        local installed = Suite.DB.suite.modules.glimmer
        assert(installed.enabled == forever and installed.questSparkle and installed.style == 3,
            layout .. " install lost Glimmer defaults")
        assert(old.enabled == false and old.style == 5, "installer changed the previous Glimmer profile")
        assert(#H.reported == 0, table.concat(H.reported, "\n"))

        -- Opening an existing profile or re-normalizing it never re-enables a
        -- deliberate opt-out; a Retail import cannot bypass the runtime gate.
        installed.enabled = false
        Suite.Suite.Normalize(Suite.DB)
        assert(installed.enabled == false, "normalization overwrote the Glimmer opt-out")
        installed.enabled = true
        assert(Suite.Suite.Availability("glimmer") == forever, "imported On bypassed the client gate")
        if not forever then
            Suite.Suite.started = true
            Suite.Suite.Apply("glimmer")
            Suite.Suite.started = nil
            assert(not Suite.Suite.ModuleState("glimmer").active, "Retail activated Glimmer")
        end

        if forever then
            assert(Suite.Installer.Open())
            window = MSUFSuiteInstallFrame
            window.next.scripts.OnClick()
            window[layout].scripts.OnClick()
            window.next.scripts.OnClick()
            for _, candidate in ipairs(window.moduleRows) do
                if candidate.id == "glimmer" then candidate.scripts.OnClick() end
            end
            assert(window.previewProfile(layout).suite.modules.glimmer.enabled,
                "picker modified the cached factory")
            ok, why = Suite.Installer.Apply()
            assert(ok, why)
            assert(Suite.DB.suite.modules.glimmer.enabled == false, "installer ignored Glimmer opt-out")
        end
        print("glimmer installer: " .. (forever and "Forever" or "Mainline") .. " " .. layout .. " ok")
    end
end
'''


def main():
    root = Path(sys.argv[1]).resolve()
    core = root / "MSUF_Suite/Core"
    fixtures = {}
    for filename, name in (
        ("ForeverFrames.lua", "ForeverFactoryFramesCompact"),
        ("BlizzardFactory.lua", "BlizzardFramesCompact"),
        ("ModernDarkFactory.lua", "ModernDarkFramesCompact"),
        ("ClassicFramesFactory.lua", "ClassicFactoryFramesCompact"),
        ("ForeverFactory.lua", "ForeverFactoryModuleCompact"),
        ("RetailFactory.lua", "RetailFactoryModuleCompact"),
        ("RetailProfile.lua", "RetailProfileModuleCompact"),
        ("ModernDarkFactory.lua", "ModernDarkModuleCompact"),
        ("BlizzardFactory.lua", "BlizzardModuleCompact"),
        ("DarkRaidFactory.lua", "DarkRaidModuleCompact"),
    ):
        text = literal(core / filename, "Suite." + name)
        module = "Module" in name
        fixtures[text[7:] if module else text] = decode(text, "MSUFM1:MSUF3:" if module else "MSUF3:")
    script = CHECK.replace("FIXTURES", lua_literal(fixtures), 1)
    result = subprocess.run([LUA, "-", str(root)], input=script, text=True, cwd=root)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
