"""Blizzard preset: actual data, staged previews, install, rollback and host compiler."""
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA, lua_literal
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_modern_dark_factory import literal
from build_forever_factory_preview import decode

CHECK = r'''
local root, host = arg[1], arg[2]
local fixtures, frameData, skinData = FIXTURES, FRAMES, SKIN
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, entry in pairs(value) do out[key] = Copy(entry) end
    return out
end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
for _, forever in ipairs({ false, true }) do
    for _, skin in ipairs({ false, true }) do
        MapkoSkin = nil
        local Suite = H.Setup({ root = root, forever = forever, uiWidth = 2560, uiHeight = 1072,
            addons = { MSUF_Suite_Skin = skin }, frameFactory = function() return frameData.payload end })
        MSUF_TryDecodeCompactString = function(text)
            local value = assert(fixtures[text], text)
            return Suite.CopyValue(value)
        end
        H.skin = H.FakeSkin()
        H.skin.ProfileIO.PrepareProfile = function(text)
            return text == Suite.BlizzardSkinCompact and Suite.CopyValue(skinData.payload)
                or { enabled = true, icons = {} }
        end
        local previous = Suite.CopyValue(Suite.DB)
        local oldFrames = Suite.CopyValue(MSUF_DB)
        assert(Suite.Installer.Open())
        local w = MSUFSuiteInstallFrame
        w.next.scripts.OnClick()
        assert(w.blizzard:IsShown(), "preset missing from the first installer")
        w.blizzard.scripts.OnClick()
        assert(w.blizzard.mark.text == Suite.Text("SELECTED"))
        local p = w.layoutPreview
        assert(p.screenshot:IsShown() and p.screenshot.art.texture:match("BlizzardPreviewSolo.tga$"))
        assert(p.screenshotNext:IsShown() and p.note.text:find("another UI", 1, true), "reference is misrepresented")
        assert(math.abs(p.screenshot:GetWidth() / p.screenshot:GetHeight() - 2560 / 1072) < .001)
        p.screenshotNext.scripts.OnClick()
        assert(p.screenshot.art.texture:match("BlizzardPreviewGroup.tga$"))
        p.screenshot.scripts.OnClick()
        assert(p.screenshotZoom:IsShown() and p.screenshotZoom.art.texture == p.screenshot.art.texture)
        p.screenshotToggle.scripts.OnClick()
        assert(p.canvas:IsShown() and not p.screenshot:IsShown() and not p.screenshotZoom:IsShown())
        local staged = assert(Suite.ProfileIO.PrepareProfile(Suite.BlizzardModuleCompact, false))
        local frames = assert(Suite.HostBridge.FactoryFramePreview("blizzard"))
        assert(Equal(frames, frameData.payload), "preview differs from installed frame payload")
        local modules = staged.suite.modules
        assert(modules.actionbars.bar1LeftEndcap == 4 and modules.actionbars.bar1Visibility == 1)
        assert(modules.chat.panelColor == "151310" and modules.chat.panelAlpha == 35)
        for _, height in ipairs({ 768, 1072, 1440 }) do
            local scene = Suite.InstallerPreviewModel.Build(staged, frames, "blizzard", nil,
                { width = height * 16 / 9, height = height })
            assert(scene.player and scene.target and scene.cooldowns and scene.playerPower)
            assert(scene.playerPower.y == scene.cooldowns.y + scene.cooldowns.height + 2)
            assert(math.abs(scene.cooldowns.x + scene.cooldowns.width / 2 - scene.width / 2) < .001)
        end
        assert(Equal(Suite.DB, previous) and Equal(MSUF_DB, oldFrames), "preview wrote saved settings")
        H.combat = true
        assert(not Suite.Installer.Apply(), "combat installation was allowed")
        H.combat = false
        w.next.scripts.OnClick(); w.next.scripts.OnClick(); w.next.scripts.OnClick()
        assert(w.review[1].detail.text:find("MSUF Blizzard", 1, true))
        local scaleApply = Suite.HostBridge.ApplyScale
        Suite.HostBridge.ApplyScale = function() return false, "test refusal" end
        assert(not Suite.Installer.Apply(), "failed scale did not roll back")
        assert(Equal(Suite.DB, previous) and Equal(MSUF_DB, oldFrames), "rollback changed the previous profile")
        assert(not Suite.Database.GetProfile("MSUF Blizzard"), "rollback leaked a profile")
        Suite.HostBridge.ApplyScale = scaleApply
        assert(Suite.Installer.Apply())
        assert(Suite.Database.GetActiveProfileName() == "MSUF Blizzard")
        assert(Suite.RootDB.installation.profile == "blizzard" and Suite.RootDB.installation.status == "complete")
        assert(Suite.DB.suite.modules.minimap.shape == 2 and Suite.DB.suite.modules.damageMeter.w2Y == 244)
        assert(Equal(Suite.Database.GetProfile("Default"), previous), "install changed the original Suite profile")
        if skin then assert(H.skin.Database.GetActiveProfileName() == "MSUF Blizzard") end
        assert(#H.reported == 0, table.concat(H.reported, "\n"))
    end
end
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local world = assert(loadfile(host .. "/tools/tests/client_world.lua"))().New(host, flavor)
    local loadFile = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local ok, why = loadFile(self, path, addon, namespace)
        if path:match("/State/MSUF_ProfileRuntime.lua$") then self.core.ProfileRuntime.Apply = function() end end
        return ok, why
    end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.message)
    local env, UF = world.env, world.core.UF
    local public = world.core.PublicGlobals or env
    local function Host(name) return env[name] or public[name] end
    local decode = Host("MSUF_TryDecodeCompactString")
    world.core.ExportPublic("MSUF_TryDecodeCompactString", function(text)
        if text == "MSUF3:blizzard-factory-import-test" then return Copy(frameData) end
        if fixtures[text] then return Copy(fixtures[text]) end
        return decode(text)
    end)
    Host("MSUF_InitProfiles")()
    local oldName = Host("MSUF_ActiveProfile")
    local oldProfile = Copy(Host("MSUF_GlobalDB").profiles[oldName])
    local ok, why = Host("MSUF_Profiles_ImportIntoNewProfile")("Blizzard imported", "MSUF3:blizzard-factory-import-test")
    assert(ok, tostring(why))
    assert(Host("MSUF_ActiveProfile") == "Blizzard imported", "host did not activate the imported profile")
    assert(Equal(Host("MSUF_GlobalDB").profiles[oldName], oldProfile), "host import changed the previous profile")
    UF.Config.Refresh()
    for _, unit in ipairs({ "player", "target" }) do
        local spec = assert(UF.Config.GetSpec(unit))
        assert(spec.width == 180 and spec.height == 32)
        assert(spec.portrait.shape == "BLIZZARD" and spec.portrait.width == 60)
        assert(spec.portrait.alpha == 1, "portrait became transparent")
        assert(spec.health.mode == "class" and spec.backgroundAlpha == .8, "host changed authored health colors")
    end
    local power = UF.Config.GetSpec("player").power
    assert(power.enabled and power.detached and power.detachedAnchorClass and power.mode == "power")
    assert(power.detachedY == -56 and power.detachedHeight == 6)
    local party = Host("MSUF_DB").gf_party
    assert(party.offsetX == 0 and party.growth == "RIGHT", "party import: " .. tostring(party.offsetX) .. "/" .. tostring(party.growth))
    assert(Host("MSUF_DB").general.playerCastbarOverrideEnabled == false)
end
print("Blizzard preset: both clients, optional Skin, reference gallery, pure preview, combat, rollback and host compiler passed")
'''


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
    core = root / 'MSUF_Suite/Core'
    fixtures = {}
    for filename, names in (
        ('ClassicFramesFactory.lua', ['ClassicFactoryFramesCompact']),
        ('ForeverFrames.lua', ['ForeverFactoryFramesCompact']),
        ('ForeverFactory.lua', ['ForeverFactoryModuleCompact']),
        ('RetailFactory.lua', ['RetailFactoryModuleCompact']),
        ('RetailProfile.lua', ['RetailProfileModuleCompact']),
        ('ModernDarkFactory.lua', ['ModernDarkFramesCompact', 'ModernDarkModuleCompact']),
        ('BlizzardFactory.lua', ['BlizzardFramesCompact', 'BlizzardModuleCompact'])):
        for name in names:
            text = literal(core / filename, 'Suite.' + name)
            module = 'Module' in name
            fixtures[text[7:] if module else text] = decode(text, 'MSUFM1:MSUF3:' if module else 'MSUF3:')
    frame = decode(literal(core / 'BlizzardFactory.lua', 'Suite.BlizzardFramesCompact'), 'MSUF3:')
    skin = decode(literal(core / 'BlizzardFactory.lua', 'Suite.BlizzardSkinCompact'), 'MSKIN1:')
    for name in ('MidnightSimpleUnitFrames', 'MidnightSimpleUnitFrames-7.0'):
        path = root.parent / name / 'MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Shell.lua'
        if path.exists() and 'MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT =' in path.read_text(encoding='utf-8-sig'):
            text = literal(path, 'MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT')
            fixtures[text] = decode(text, 'MSUF3:')
    script = CHECK.replace('FIXTURES', lua_literal(fixtures), 1).replace('FRAMES', lua_literal(frame), 1)
    script = script.replace('SKIN', lua_literal(skin), 1)
    for name in ('MidnightSimpleUnitFrames', 'MidnightSimpleUnitFrames-7.0'):
        host = root.parent / name
        if not host.exists():
            continue
        run = subprocess.run([LUA, '-', str(root), str(host)], input=script, text=True, capture_output=True, cwd=root)
        print(name + ': ' + run.stdout, end='')
        if run.returncode:
            print(run.stderr, file=sys.stderr, end='')
            return run.returncode
    return 0


if __name__ == '__main__':
    sys.exit(main())
