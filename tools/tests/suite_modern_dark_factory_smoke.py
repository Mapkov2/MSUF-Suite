"""Modern Dark: real data, pure preview and a transactional full install on both clients."""
import copy
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA, lua_literal
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_modern_dark_factory import literal
from build_forever_factory_preview import decode

CHECK = r'''
local root, classic, fixtures, frameData, skinData = arg[1], arg[2], FIXTURES, FRAME, SKIN
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
    for _, withSkin in ipairs({ false, true }) do
        MapkoSkin = nil
        local Suite = H.Setup({ root = root, forever = forever, uiWidth = 1920, uiHeight = 1080,
            addons = { MSUF_Suite_Skin = withSkin }, frameFactory = function() return frameData.payload end })
        MSUF_TryDecodeCompactString = function(text)
            local envelope = assert(fixtures[text], "unexpected factory")
            return Suite.CopyValue(envelope)
        end
        H.skin = H.FakeSkin()
        H.skin.ProfileIO.PrepareProfile = function(text)
            if text == "MSKIN1:x" then return { enabled = true, icons = {} } end
            assert(text == Suite.ModernDarkSkinCompact)
            return Suite.CopyValue(skinData.payload)
        end
        local originalFrames, originalModules = Suite.CopyValue(MSUF_DB), Suite.CopyValue(Suite.DB)
        local oldCD = Suite.DB.suite.modules.cooldownManager
        oldCD.listsData, oldCD.spellsData = "user-lists", "user-spells"
        originalModules = Suite.CopyValue(Suite.DB)
        assert(Suite.Installer.Open())
        local window = MSUFSuiteInstallFrame
        window.next.scripts.OnClick()
        window.modernDark.scripts.OnClick()
        assert(window.modernDark.mark.text == Suite.Text("SELECTED"))
        local preview = assert(Suite.HostBridge.FactoryFramePreview("modernDark"))
        assert(Equal(preview, frameData.payload), "preview differs from installed frame payload")
        local staged = assert(Suite.ProfileIO.PrepareProfile(Suite.ModernDarkModuleCompact, false))
        for _, height in ipairs({ 768, 1080, 1440 }) do
            local scene = Suite.InstallerPreviewModel.Build(staged, preview, "modernDark", nil,
                { width = height * 16 / 9, height = height })
            assert(scene.cooldowns.x - scene.player.x - scene.player.width == 60
                and scene.target.x - scene.cooldowns.x - scene.cooldowns.width == 60,
                "preview lost the physical gaps beside the resource block")
            assert(scene.player.y == scene.target.y and scene.resource.y == scene.player.y - 16,
                "frame/resource vertical alignment differs from the reference")
            assert(scene.resource.width == 392 and scene.playerPower.width == 392
                and scene.resource.x - scene.player.x - scene.player.width == 18.5
                and scene.target.x - scene.resource.x - scene.resource.width == 18.5,
                "resource bars no longer span the space between the unit frames")
            assert(scene.pet.x == scene.player.x and scene.targettarget.x + scene.targettarget.width == scene.target.x + scene.target.width)
            assert(scene.bar1.width == 620 and scene.bar4.width == 454 and scene.w1.width == 620)
            assert(scene.chat and scene.chat.module == "chat" and scene.chat.width == 620
                and scene.chat.height == 250 and scene.chat.x == 12
                and scene.chat.y == scene.height - 282, "chat preview lost the authored screen margins")
            assert(scene.bar1.height == 32 and scene.bar2.height == 32 and scene.bar4.height == 32,
                "action bars lost the reference's flat silhouette")
        end
        do
            local chat = staged.suite.modules.chat
            chat.lockWindowSize = false
            assert(not Suite.InstallerPreviewModel.Build(staged, preview, "modernDark").chat,
                "position-only chat preview invented a fixed size")
            chat.lockWindowSize = true
            chat.lockWindowPosition = false
            assert(not Suite.InstallerPreviewModel.Build(staged, preview, "modernDark").chat,
                "size-only chat preview invented a fixed position")
            chat.lockWindowPosition = true
        end
        local paintWindow = H.Widget("Frame")
        paintWindow:SetSize(580, 500)
        Suite.InstallerPreview.Build(paintWindow, function() return staged end, function() return preview end)
        Suite.InstallerPreview.Show(paintWindow, true, "modernDark")
        local painted = Suite.InstallerPreviewModel.Build(staged, preview, "modernDark", nil,
            Suite.InstallerPreviewModel.Viewport())
        for index, item in ipairs(painted) do
            if item.key == "bar1" or item.key == "cooldowns" then
                local texture = paintWindow.layoutPreview.regions[index].details[1]
                local coords = texture.texCoords
                assert(coords and math.abs((coords[2]-coords[1])/(coords[4]-coords[3])
                    - texture:GetWidth()/texture:GetHeight()) < .001, "preview icons are stretched")
                assert(item.key ~= "bar1" or texture:GetWidth() > texture:GetHeight(), "flat preview uses square icons")
                assert(item.key ~= "cooldowns" or math.abs(texture:GetWidth()-texture:GetHeight()) < .001,
                    "cooldown preview lost square icons")
            end
        end
        assert(Equal(MSUF_DB, originalFrames) and Equal(Suite.DB, originalModules), "preview wrote live settings")
        H.combat = true
        assert(not Suite.Installer.Apply(), "combat install was not refused")
        H.combat = false
        local ok, reason = Suite.Installer.Apply()
        assert(ok, tostring(reason))
        assert(Suite.RootDB.installation.profile == "modernDark")
        assert(MSUF_ActiveProfile == "Modern Dark" and Suite.Database.GetActiveProfileName() == "Modern Dark")
        assert(Equal(MSUF_GlobalDB.profiles.Default, originalFrames), "previous frame profile was overwritten")
        assert(Equal(Suite.RootDB.profiles.Default, originalModules), "previous Suite profile was overwritten")
        local cd = Suite.DB.suite.modules.cooldownManager
        if not forever then
            assert(cd.listsData == "user-lists" and cd.spellsData == "user-spells", "personal cooldown lists were replaced")
        end
        for _, prefix in ipairs({ "ess", "uti", "def", "ext", "buf", "c1", "c2", "c3", "c4", "c5", "c6" }) do
            assert(cd[prefix .. "_height"] == 100 and cd[prefix .. "_spacing"] == 3, "non-square or uneven cooldown icons")
        end
        assert(MSUF_DB.general.barMode == "dark" and MSUF_DB.general.nameClassColor, "frame design lost its color policy")
        assert(MSUF_DB.player.width == 340 and MSUF_DB.player.height == 54
            and MSUF_DB.player.textRight == "PERCENT" and MSUF_DB.target.textLeft == "PERCENT"
            and MSUF_DB.player.powerTextLeft == "PERCENT" and MSUF_DB.target.powerTextRight == "PERCENT",
            "reference silhouette or mirrored text hierarchy was lost")
        local np = Suite.DB.suite.modules.nameplates
        assert(np.look == 3 and np.nativeStyle == 7 and np.nativeSize == 4 and np.barGeometry == 2
            and np.enemyTextMode == 2 and np.enemyMirrorHeader and not np.enemyRoleColors
            and np.enemyTargetStyle == 10 and np.enemyTargetLayout == 2,
            "native plate header or inward cyan arrows lost their reference settings")
        assert(np.enemyCastIconOffsetX == 262 and np.enemyCastIconOffsetY == 34
            and np.enemyCastTextOffsetX == -38 and np.enemyCastTextOffsetY == 34
            and np.enemyCastTimeOffsetX == -100 and np.enemyCastSpellIcon and not np.enemyCastSpellTarget
            and np.enemyCastHeight == 28 and np.enemyCastIconSize == 40 and np.enemyCastTimeFormat == 2,
            "native cast icon and text no longer use the reference's right-icon layout")
        assert(Suite.DB.suite.modules.damageMeter.classColors and Suite.DB.suite.modules.damageMeter.refreshRate == 1.5)
        local data = Suite.DB.suite.modules.dataTexts
        local paint = { Suite = Suite, NS = Suite }
        assert(loadfile(root .. "/MSUF_Suite_DataTexts/Appearance.lua"))("MSUF_Suite_DataTexts", paint)
        for index = 1, 3 do
            local style = Suite.DataTextEffectiveStyle(data, index)
            local bar = { style = style, frame = H.Widget(), background = H.Widget(), gradient = H.Widget(),
                accent = H.Widget(), badge = H.Widget(), border = {}, dividers = {} }
            for edge = 1, 4 do bar.border[edge] = H.Widget() end
            paint.Appearance.Paint(bar)
            assert(bar.background:IsShown() == (index == 1) and not bar.gradient:IsShown() and not bar.accent:IsShown()
                and bar.border[1]:IsShown() == (index == 1) and not bar.badge:IsShown(), "reference footer background differs")
            assert(style.fontSize == 18 and style.valueColor == (index == 1 and "ff9b00" or index == 2 and "35e65b" or "f3d72d")
                and not data["bar" .. index .. "LoadCondHideInCombat"], "footer lost combat visibility or source colors")
        end
        local actions = Suite.DB.suite.modules.actionbars
        assert(not actions.bar1ShowEmpty and not actions.bar4ShowEmpty and not actions.bar1Keybind
            and not Suite.DB.suite.modules.buffReminders.enabled, "empty hotkey slots or oversized reminders returned")
        if withSkin then assert(H.skin.Database.GetActiveProfileName() == "Modern Dark") end
        assert(#H.reported == 0, tostring(H.reported[1]))
    end
end
-- Resolve the authored data through Classic's shipped compiler and real text
-- layout, so profile key presence alone cannot stand in for actual anchors.
for _, flavor in ipairs({ "Mainline", "Forever" }) do
    local world = assert(loadfile(classic .. "/tools/tests/client_world.lua"))().New(classic, flavor)
    local loadFile = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local ok, message = loadFile(self, path, addon, namespace)
        if path:match("/State/MSUF_ProfileRuntime.lua$") then
            -- This test owns profile selection/storage and compiles/paints
            -- the resulting frames below. Native Blizzard window takeover
            -- is a separate runtime boundary with its own contracts.
            self.core.ProfileRuntime.Apply = function() end
        end
        return ok, message
    end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.message)
    local env, UF = world.env, world.core.UF
    -- Exercise the shipped selector, import transaction and profile switch.
    -- A Wago wrapper may carry a different lossless msuf6 payload: copying
    -- its outer payload directly would hide exactly that installation bug.
    local decode = env.MSUF_TryDecodeCompactString
    world.core.ExportPublic("MSUF_TryDecodeCompactString", function(text)
        if text == "MSUF3:modern-dark-test" then return Copy(frameData) end
        if fixtures[text] then return Copy(fixtures[text]) end
        return decode(text)
    end)
    env.MSUF_InitProfiles()
    local previousName, previousProfile = env.MSUF_ActiveProfile, Copy(env.MSUF_DB)
    local imported, why = env.MSUF_Profiles_ImportIntoNewProfile("Modern Dark imported", "MSUF3:modern-dark-test")
    assert(imported, tostring(why))
    assert(env.MSUF_ActiveProfile == "Modern Dark imported")
    assert(Equal(env.MSUF_GlobalDB.profiles[previousName], previousProfile), "actual import changed the previous profile")
    assert(env.MSUF_DB.player.width == 340 and env.MSUF_DB.player.height == 54
        and env.MSUF_DB.player.portraitMode == "LEFT" and env.MSUF_DB.player.portraitPlacement == "OVERLAY" and env.MSUF_DB.general.barMode == "dark",
        "actual MSUF import selected stale unit-frame data instead of Modern Dark")
    env.MSUF_EnsureDB()
    local containers = env.MSUF_DB.auras3.customContainers.perUnit.player.items
    assert(containers[4] and not containers["4"], "canonical defensive container lost its numeric slot")
    assert(not containers[4].enabled and not containers[4].autoBlacklistPlayerBuffs,
        "defensive icons still cover the player's health percentage")
    for _, unit in ipairs({ "player", "target" }) do
        local aura = env.MSUF_NS.MSUF_Auras3
        local compiled = assert(aura.ResolveUnitFrameConfig(unit))
        local lane = assert(compiled.lanes.buff)
        assert(lane.buttonWidth == 52 and lane.buttonHeight == 26 and lane.stepY == 30,
            "runtime aura lane ignored its height setting")
        local owner = assert(env.MSUF_DB.auras3.perUnit[unit])
        local a, shared = owner.layout, owner.layoutShared
        assert(a.buffGroupIconSize == 52 and a.debuffGroupIconSize == 52
            and a.buffIconHeightPercent == 50 and a.debuffIconHeightPercent == 50
            and a.buffAnchor == "TOPLEFT" and a.debuffAnchor == "TOPLEFT"
            and a.buffGroupOffsetY == (unit == "player" and 46 or 80)
            and a.debuffGroupOffsetY == (unit == "player" and 80 or 46),
            "actual defaults/migration changed the reference aura row")
        assert(a.buffGroupOffsetX == 0 and a.debuffGroupOffsetX == 0
            and shared.buffPerRow == 6 and shared.debuffPerRow == 6
            and shared.buffGrowthX == "RIGHT" and shared.debuffGrowthX == "RIGHT",
            "buff/debuff groups can overlap after migration")
    end
    UF.Config.Refresh()
    for _, unit in ipairs({ "player", "target" }) do
        local spec = UF.Config.GetSpec(unit)
        local player = unit == "player"
        assert(spec.width == 340 and spec.height == 54)
        assert(spec.health.mode == "gradient" and spec.health.gradient
            and spec.health.gradientLowR == .70 and spec.health.gradientHighR == .025
            and spec.health.gradientMidG == .031 and spec.health.gradientHighB == .035,
            "combat health colors lost the dark-red-to-black curve")
        if player then
            assert(spec.power.detachedWidthExplicit == 392 and spec.power.detachedClassWidth == 392
                and not spec.power.detachedWidthFrameName, "player power still shrinks to the square cooldown row")
            assert(spec.power.mode == "static" and spec.power.r == .10
                and spec.power.g == .43 and spec.power.b == .42, "mana fill lost the teal palette")
        end
        assert(spec.anchorFrameName == "EssentialCooldownViewer" and spec.point == (player and "TOPRIGHT" or "TOPLEFT")
            and spec.relativePoint == (player and "TOPLEFT" or "TOPRIGHT") and spec.x == (player and -60 or 60)
            and spec.y == 12, "unit frames still move down when Essential wraps to a second row")
        local frame = env.CreateFrame("Frame", nil, env.UIParent)
        frame:SetSize(spec.width, spec.height); frame.MSUFUnitKey, frame.unit, frame.MSUFSpec = unit, unit, spec
        UF.elements.Text.Apply(frame, spec)
        assert(frame.nameText:GetWidth() == 248, "a long unit name can cross the HP percentage")
        local function Point(region, point, relative, x, y)
            assert(region, "missing text region")
            local actual, _, rel, ax, ay = region:GetPoint()
            assert(actual == point and rel == relative and ax == x and ay == y,
                unit .. " text anchor differs: " .. tostring(actual) .. "/" .. tostring(rel) .. "/" .. tostring(ax) .. "/" .. tostring(ay))
        end
        Point(frame.nameText, player and "BOTTOMLEFT" or "BOTTOMRIGHT", player and "TOPLEFT" or "TOPRIGHT", player and 6 or -10, -4)
        Point(player and frame.hpTextRight or frame.hpTextLeft, player and "BOTTOMRIGHT" or "BOTTOMLEFT",
            player and "TOPRIGHT" or "TOPLEFT", player and -10 or 8, -4)
        Point(frame.hpTextCenter, player and "TOPRIGHT" or "TOPLEFT", player and "TOPRIGHT" or "TOPLEFT", player and -10 or 12, -18)
        Point(player and frame.powerTextLeft or frame.powerTextRight, player and "TOPLEFT" or "TOPRIGHT",
            player and "TOPLEFT" or "TOPRIGHT", player and 12 or -12, -18)
        for _, width in ipairs({ 180, 0, 248 }) do
            env.MSUF_DB[unit].directNameWidth = width
            UF.Config.Refresh(); frame.MSUFSpec = UF.Config.GetSpec(unit)
            UF.elements.Text.Apply(frame, frame.MSUFSpec)
            assert(frame.nameText:GetWidth() == width, "direct name width did not refresh or reset: " .. width .. "/" .. frame.nameText:GetWidth())
        end
        for _, direct in ipairs({ false, true, false }) do
            env.MSUF_DB[unit].directTextLayout = direct
            UF.Config.Refresh(); frame.MSUFSpec = UF.Config.GetSpec(unit)
            UF.elements.Text.Apply(frame, frame.MSUFSpec)
            assert(frame.nameText:GetWidth() == (direct and 248 or 0), "name width leaked across layout/profile changes")
        end
    end
    local pet, tot = UF.Config.GetSpec("pet"), UF.Config.GetSpec("targettarget")
    assert(pet.width == 138 and pet.height == 16 and pet.anchorToUnitframe == "player" and pet.y == -68)
    assert(tot.width == 138 and tot.height == 16 and tot.anchorToUnitframe == "target" and tot.y == -68)
    local width, height = env.MSUF_GetCastbarDesiredSize("target", env.MSUF_DB.general, nil, 340, 28)
    assert(width == 392 and height == 28, "castbar no longer reserves its exterior right icon")
end
print("Modern Dark: real factory preview, combat refusal, full installs on Retail/Forever with/without Skin; original profiles and CDM lists preserved")
'''


def main():
    root = Path(sys.argv[1]).resolve()
    core = root / "MSUF_Suite/Core"
    fixtures = {}
    for filename, name in (("ClassicFramesFactory.lua", "ClassicFactoryFramesCompact"),
                           ("ForeverFrames.lua", "ForeverFactoryFramesCompact"),
                           ("RetailProfile.lua", "RetailProfileModuleCompact"),
                           ("ForeverFactory.lua", "ForeverFactoryModuleCompact"),
                           ("RetailFactory.lua", "RetailFactoryModuleCompact"),
                           ("ModernDarkFactory.lua", "ModernDarkModuleCompact"),
                           ("ModernDarkFactory.lua", "ModernDarkFramesCompact")):
        value = literal(core / filename, "Suite." + name)
        is_module = "Module" in name
        fixtures[value[7:] if is_module else value] = decode(value, "MSUFM1:MSUF3:" if is_module else "MSUF3:")
    value = literal(core / "ModernDarkFactory.lua", "Suite.ModernDarkFramesCompact")
    frame = fixtures[value]
    native_path = root.parent / "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Options/State/MSUF_Defaults_ModernDark.lua"
    default_path = root.parent / "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Shell.lua"
    default_text = literal(default_path, "MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT")
    fixtures[default_text] = decode(default_text, "MSUF3:")
    if native_path.exists():
        native = literal(native_path, "MSUF.MSUF_MODERN_DARK_PROFILE_COMPACT")
        assert native == value, "Classic and bundled fallback must have identical bytes"
    skin = decode(literal(core / "ModernDarkFactory.lua", "Suite.ModernDarkSkinCompact"), "MSKIN1:")
    script = CHECK.replace("FIXTURES", lua_literal(fixtures), 1).replace("FRAME", lua_literal(copy.deepcopy(frame)), 1)
    script = script.replace("SKIN", lua_literal(skin), 1)
    run = subprocess.run([LUA, "-", str(root), str(root.parent / "MidnightSimpleUnitFrames")], input=script, text=True, capture_output=True, cwd=root)
    print(run.stdout, end="")
    if run.returncode: print(run.stderr, file=sys.stderr, end="")
    return run.returncode


if __name__ == "__main__":
    sys.exit(main())
