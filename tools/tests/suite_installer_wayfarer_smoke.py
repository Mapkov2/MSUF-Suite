"""Verify the Wayfarer installer and the shipped frame profile on both Suite clients."""
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA, lua_literal

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_forever_factory_preview import decode
from build_modern_dark_factory import literal

CHECK = r"""
local root, host = arg[1], arg[2]
local fixtures = FIXTURES
local H = dofile(root .. "/tools/tests/suite_installer_harness.lua")
local Copy

for _, forever in ipairs({ false, true }) do
    _G.MapkoSkin = nil
    local Suite = H.Setup({ root = root, forever = forever, uiWidth = 1280, uiHeight = 720,
        addons = { MSUF_Suite_Skin = true } })
    local skin = H.FakeSkin()
    skin.ProfileIO.PrepareProfile = function(text)
        assert(text == Suite.WayfarerSkinCompact)
        return Suite.CopyValue(assert(fixtures[text]).payload)
    end
    MSUF_TryDecodeCompactString = function(text)
        local envelope = fixtures[text]
        if envelope then return Suite.CopyValue(envelope) end
    end
    assert(loadfile(root .. "/MSUF_Suite/Core/API.lua"))("MSUF_Suite", Suite)
    Copy = Suite.CopyValue
    local previous = MSUF_DB
    local frameCompact = Suite.WayfarerFramesCompact
    local frames = assert(Suite.HostBridge.FactoryFramePreview("wayfarer"))
    local offered
    for _, preset in ipairs(Suite.API.GetSetupFramePresets()) do
        if preset.name == "Wayfarer" then offered = preset.compact end
    end
    assert(offered == frameCompact, "Quick Setup and Suite Setup use different frames")
    MSUF_Profiles_ImportIntoNewProfile = function(name, text)
        assert(text == frameCompact, "Suite installer imported another layout")
        local copy = Suite.CopyValue(assert(fixtures[text].payload))
        MSUF_GlobalDB.profiles[name], MSUF_ActiveProfile, MSUF_DB = copy, name, copy
        return true
    end
    assert(Suite.Installer.Open())
    local window = MSUFSuiteInstallFrame
    window.next.scripts.OnClick()
    window.colors[2].scripts.OnClick()
    window.wayfarer.scripts.OnClick()
    assert(window.wayfarer:IsShown() and window.wayfarer.mark:GetText() == Suite.Text("SELECTED"))
    assert(not window.colors[2]:IsShown() and window.colorChoice == "authored")
    assert(MSUF_DB == previous and Suite.Database.GetActiveProfileName() == "Default")

    local profile = assert(Suite.ProfileIO.PrepareProfile(Suite.WayfarerModuleCompact, false))
    local navigation = profile.suite.modules.navigationHUD
    assert(navigation and navigation.enabled and navigation.showCompass, "Wayfarer omitted the compass")
    for _, width in ipairs({ 1024, 1280, 1920, 2560 }) do
        local scene = Suite.InstallerPreviewModel.Build(profile, frames, "wayfarer", nil,
            { width = width, height = math.max(720, width * 9 / 16) })
        assert(scene.player.x < scene.target.x and scene.target.x + scene.target.width < scene.minimap.x)
        local compass = assert(scene.compass, "Wayfarer did not preview its compass")
        assert(compass.module == "navigationHUD" and compass.width == 260 and compass.fillColor == "a28655")
        assert(compass.x + compass.width / 2 == width / 2)
        assert(compass.y >= 0 and compass.y + compass.height <= scene.target.y - 18,
            "compass covers the target name")
        assert(compass.x > scene.player.x + scene.player.width and compass.x + compass.width < scene.minimap.x)
        assert(scene.playerCast.x == scene.player.x and scene.playerCast.width == scene.player.width)
        assert(scene.playerCast.height == 22 and scene.playerCast.y >= scene.resource.y + scene.resource.height + 4)
        local playerAuras = frames.auras3.perUnit.player.layout
        local auraTop = scene.player.y - playerAuras.buffGroupOffsetY
        assert(scene.playerCast.y + scene.playerCast.height + 4 <= auraTop)
        assert(auraTop + playerAuras.debuffGroupIconSize < scene.pet.y)
        assert(scene.targetCast.y >= scene.target.y + scene.target.height + 18)
        assert(scene.target.fillColor == "b84038", "the Wayfarer preview sampled a friendly target")
        assert(scene.minimap.x == scene.data1.x and scene.data1.x == scene.quests.x)
        assert(scene.minimap.width == 290 and scene.minimap.artwork:match("WayfarerMinimapFrame%.tga$"))
        assert(scene.minimap.y + scene.minimap.height == scene.data1.y)
        assert(scene.data1.y + scene.data1.height < scene.quests.y)
        assert(scene.quests.y + scene.quests.height <= scene.height)
        assert(scene.raid.kind == "grid" and scene.raid.columns == 5 and scene.raid.count == 40)
        assert(scene.raid.barMask:match("right_up%.png$") and scene.playerCast.barEdge:match("right_up%.png$"))
        assert(scene.raid.x >= 0 and scene.raid.x + scene.raid.width < scene.boss.x)
        assert(scene.pet.y + scene.pet.height < scene.raid.y, "pet covered the lead raid row")
        assert(scene.targettarget.y + scene.targettarget.height < scene.boss.y, "target of target covered the boss stack")
        assert(scene.raid.y + scene.raid.height < scene.chat.y, "raid preview covered chat")
        assert(scene.boss.x + scene.boss.width < scene.minimap.x, "boss preview covered the right column")
        for index = 1, 5 do
            local boss = index == 1 and scene.boss or scene["boss" .. index]
            local cast = scene["boss" .. index .. "Cast"]
            assert(boss.x == scene.boss.x and boss.y == scene.boss.y + (index - 1) * 64)
            assert(cast.x == boss.x and cast.width == boss.width and cast.y == boss.y + boss.height + 3)
            assert(boss.barMask:match("left_down%.png$") and cast.barEdge == boss.barEdge)
        end
        assert(scene.bar1 and scene.bar2 and scene.bar3 and not scene.bar4 and not scene.w1)
        assert(scene.cooldowns.y + scene.cooldowns.height + 60 == scene.bar3.y)
        local bossAura = frames.auras3.perUnit.boss5.layout
        assert(scene.boss5.y - bossAura.buffGroupOffsetY + bossAura.buffGroupIconSize < scene.cooldowns.y,
            "boss auras cover the centered cooldown row")
        local noCooldowns = Suite.InstallerPreviewModel.Build(profile, frames, "wayfarer", { cooldownManager = false },
            { width = width, height = scene.height })
        assert(not noCooldowns.cooldowns and noCooldowns.bar3.y == scene.bar3.y)
        assert(scene.experience.x == scene.bar1.x and scene.experience.width == scene.bar1.width)
        for _, bar in ipairs({ scene.bar1, scene.bar2, scene.bar3 }) do
            assert(bar.x == scene.bar1.x and bar.width == scene.bar1.width and bar.count == 12,
                "action rows must share one centered grid")
        end
        local bars = profile.suite.modules.actionbars
        local gap = scene.bar1.y - bars.bar1BackgroundPaddingY - scene.experience.y - scene.experience.height
        assert(gap == 4 and scene.experience.y - scene.bar2.y - scene.bar2.height - bars.bar2BackgroundPaddingY == gap)
        assert(scene.bar2.y - bars.bar2BackgroundPaddingY - scene.bar3.y - scene.bar3.height
            - bars.bar3BackgroundPaddingY == gap, "the visible rows have uneven spacing")
        assert(scene.chat.x + scene.chat.width < scene.bar1.x or scene.chat.y + scene.chat.height < scene.bar3.y)
        local noXP = Suite.InstallerPreviewModel.Build(profile, frames, "wayfarer", { xpBar = false },
            { width = width, height = scene.height })
        assert(not noXP.experience and noXP.bar1.y == scene.bar1.y)
        local noFooter = Suite.InstallerPreviewModel.Build(profile, frames, "wayfarer", { dataTexts = false },
            { width = width, height = scene.height })
        assert(noFooter.quests.y == noFooter.minimap.y + noFooter.minimap.height + 10 and not noFooter.data1)
    end

    local ok, reason = Suite.Installer.Apply()
    assert(ok, reason)
    assert(MSUF_DB ~= previous and MSUF_ActiveProfile == "Wayfarer")
    assert(MSUF_GlobalDB.profiles.Default == previous)
    local receipt = Suite.RootDB.installation
    assert(receipt.profile == "wayfarer" and receipt.look == "authored")
    local modules = Suite.DB.suite.modules
    local compass = modules.navigationHUD
    assert(compass.enabled and compass.showCompass and compass.hideInCombat and compass.shortcutMode == 2)
    assert(compass.compassX == 0 and compass.compassY == -10 and compass.accentColor == "a28655")
    assert(modules.minimap.infoCoordinates and modules.minimap.infoClock and modules.minimap.infoLocation)
    assert(modules.minimap.styleTexture == Suite.MinimapStyleTexture.CUSTOM and modules.minimap.styleRotation == 0)
    local tracker = modules.objectives
    assert(tracker.dockBelowMinimap and tracker.groupQuestsByHeader and tracker.showQuestLogCount)
    assert(tracker.showQuestLevel and tracker.questDifficultyColor and tracker.showDungeonBadge and tracker.compactQuestRows)
    assert(tracker.questProgressColumn and tracker.groupUnderlines and tracker.objectiveSize == 13 and tracker.entrySize == 15)
    assert(tracker.animateQuestCollapse == false and modules.characterPanel.showReputationBars == true)
    local skinProfile = skin.Database.GetProfile("Wayfarer")
    assert(skin.Database.GetActiveProfileName() == "Wayfarer")
    local menu = skinProfile.icons.microMenu
    assert(menu.layoutPoint == "BOTTOMLEFT" and menu.layoutMode == "owned"
        and menu.visibility == "always" and menu.barBackground)
    local plates = modules.nameplates
    assert(plates.enabled and plates.targetClassResource and plates.targetUnitFrameResource and plates.enemySlantedHealth)
    assert(plates.enemy and plates.enemyCastEnabled == 2 and plates.enemyCastDisplay == 2)
    assert(plates.enemyCastWidthMode == 2 and plates.enemyCastHeight == 15 and plates.enemyCastSpellIcon
        and plates.enemyCastSpellName and plates.enemyCastTimeEnabled and plates.enemyCastTextOffsetY == 0)
    assert(plates.targetClassResourceY <= -2 * plates.enemyCastHeight
        and plates.nativeCastFillColor == "c7873d" and plates.nativeCastLockedColor == "8f4238")
    local data = modules.dataTexts
    assert(data.bar1MinimapDock and data.bar1MinimapDockGap == 0)
    assert(data.bar1Slot1Weight == 80 and data.bar1Slot2Weight == 75 and data.bar1Slot3Weight == 100
        and data.bar1Slot4Weight == 145)
    local bars, xp = modules.actionbars, modules.xpBar
    assert(bars.imported and not bars.profileKeybinds)
    assert(bars.bar1Visibility == 1 and bars.bar2Visibility == 1 and bars.bar3Visibility == 1
        and bars.bar4Visibility == 6 and not bars.bar3Vertical)
    assert(xp.enabled and xp.point == 8 and xp.displayStyle == 2 and xp.hideBlizzard and xp.hideBlizzardTracking
        and xp.xpTextVisibility == 2 and xp.xpTextFormat == 2)
    assert(Suite.ExperienceBarLayout.BottomPadding(xp) == 0)
    assert(bars.borderArt == Suite.ActionBarEnum.BORDER_ART.PIXEL and bars.borderSize == 1 and bars.borderColor == xp.customBorder)
    for index = 1, 3 do
        local prefix = "bar" .. index
        assert(bars[prefix .. "ShowEmpty"] and bars[prefix .. "Background"] and bars[prefix .. "BackgroundPaddingX"] == 0)
        assert(bars[prefix .. "LeftEndcap"] == Suite.ActionBarEnum.ENDCAP.NONE
            and bars[prefix .. "RightEndcap"] == Suite.ActionBarEnum.ENDCAP.NONE)
    end
    local cooldowns = modules.cooldownManager
    assert(cooldowns.enabled and cooldowns.ess_on and not cooldowns.uti_on and cooldowns.ess_vis == Suite.CDM.VIS.COMBAT)
    assert(bars.bar12Y + bars.bar12Size + 4 <= bars.bar3Y + bars.bar3Size + cooldowns.ess_gap)
    assert(modules.nativeCooldownVisibility.enabled)
    assert(modules.announcements.enabled and modules.announcements.quests and modules.announcements.level
        and not modules.announcements.animateBanner)
    local chat = modules.chat
    assert(chat.minimalChrome and not chat.animateInput and not chat.messageFading)
    assert(chat.windowX - chat.padding == menu.layoutX and menu.layoutY == bars.bar1Y)
    assert(chat.windowWidth + chat.padding * 2 == menu.layoutWidth, "chat and Micro Menu have different outside widths")
    assert(chat.inputTop and chat.inputX == 0 and chat.inputWidth == 0 and chat.inputY >= 36,
        "the edit box must clear the native tab row and align to the chat column")
    assert(modules.tooltipVisibility.enabled and modules.tooltipVisibility.itemHeaderIcon)
    assert(modules.floatingCombatText.enabled == false and modules.selfCombatText.enabled == false)
    local sources = Suite.DataTextSourceKeys
    assert(sources[data.bar1Slot1] == "gold" and sources[data.bar1Slot2] == "durability"
        and sources[data.bar1Slot3] == "bags" and sources[data.bar1Slot4] == "fpsLatency")

    local installed = MSUF_DB
    assert(Suite.Installer.Open(function() end))
    window.next.scripts.OnClick()
    window.wayfarer.scripts.OnClick()
    ok, reason = Suite.Installer.Apply()
    assert(ok, reason)
    assert(MSUF_DB == installed and MSUF_GlobalDB.profiles["Wayfarer 2"] == nil)
    assert(Suite.DB.suite.modules.minimap.shape == 1)
    assert(Suite.Installer.Open())
    window.next.scripts.OnClick()
    window.wayfarer.scripts.OnClick()
    ok, reason = Suite.Installer.Apply()
    assert(ok, reason)
    assert(MSUF_ActiveProfile == "Wayfarer 2" and MSUF_GlobalDB.profiles.Wayfarer == installed)
    assert(Suite.DB.suite.modules.chat.inputTop and MSUF_DB.player.healthColorMode == "CLASS")
    assert(#H.reported == 0, H.reported[1])
end

for _, client in ipairs({ "Mainline", "Forever" }) do
    local World = dofile(host .. "/tools/tests/client_world.lua")
    local world = World.New(host, client)
    local env = world.env
    env.GetNumSubgroupMembers = function() return 0 end
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local ok, message = load(self, path, addon, namespace)
        if path:match("/State/MSUF_ProfileRuntime.lua$") then self.core.ProfileRuntime.Apply = function() end end
        return ok, message
    end
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.message)
    local core = world.core
    local function Public(name)
        return core[name] or (core.PublicGlobals and core.PublicGlobals[name]) or env[name]
    end
    core.ExportPublic("MSUF_TryDecodeCompactString", function(text)
        local envelope = fixtures[text]
        if envelope then return Copy(envelope) end
    end)
    Public("MSUF_InitProfiles")()
    local ok, reason = Public("MSUF_Profiles_ImportIntoNewProfile")("Wayfarer import", FRAME_COMPACT)
    assert(ok, reason)
    Public("MSUF_EnsureDB")()
    local config = core.UF.Config
    config.Refresh()
    local player, target = config.GetSpec("player"), config.GetSpec("target")
    assert(player.point == "TOPLEFT" and player.width == 218 and player.health.mode == "class")
    assert(target.point == "TOP" and target.width == 318 and target.health.mode == "class")
    local npcColor = Public("MSUF_UFCore_GetNPCReactionColorFast")
    local enemyR, enemyG, enemyB = npcColor("enemy")
    assert(enemyR == .72 and enemyG == .25 and enemyB == .22)
    local friendlyR, friendlyG = npcColor("friendly")
    assert(friendlyG > friendlyR)
    assert(player.portrait.side == "LEFT" and target.portrait.side == "RIGHT")
    assert(player.portrait.shape == "CIRCLE" and target.portrait.shape == "CIRCLE")
    assert(player.portrait.border.art == "RELIEF" and target.portrait.border.art == "RELIEF")
    assert(player.text.healthRight == "CURRENT" and target.text.healthLeft == "CURRENT")
    assert(target.text.directHealthLeftPoint == "BOTTOMLEFT" and target.text.directHealthLeftRelativePoint == "TOPLEFT")
    assert(player.power.enabled and not player.power.detached and target.power.enabled and not target.power.detached)
    local general = env.MSUF_DB.general
    assert(general.enablePlayerCastbar and not general.castbarPlayerDetached
        and general.castbarPlayerMatchWidth == "unitframe" and general.castbarTargetMatchWidth == "unitframe")
    assert(general.castbarPlayerBarHeight == 22 and general.castbarPlayerIconSize == 22 and general.castbarSpellNameFontSize == 13)
    assert(general.castbarOutlineThickness == 2 and not general.castbarShowGlow and not general.castbarShowSpark
        and not general.castbarInterruptShake)
    local bars = env.MSUF_DB.bars
    local playerCastTop = -general.castbarPlayerOffsetY - general.castbarPlayerBarHeight
    assert(general.castbarPlayerBackend == "MSUF" and playerCastTop >= 2 - bars.classPowerOffsetY + bars.classPowerHeight + 4,
        "player castbar covered the class resources")
    assert(general.castbarTargetTextOffsetX >= 12 and general.castbarPlayerTimeOffsetX <= -10)
    assert(general.castbarTargetOffsetY + general.castbarTargetBarHeight < -target.height - 13,
        "target castbar overlaps the class resource row")
    local canvas = env.CreateFrame("Frame", nil, env.UIParent)
    canvas:SetSize(600, 200)
    local casts = core.GF.NewPreviewScene(canvas)
    casts:Activate()
    for _, test in ipairs({ { "player", player.width, 8, -12 }, { "target", target.width, 16, -10 } }) do
        local unit, width, gutter, timeX = unpack(test)
        local view = casts:Castbar(unit, { width = width, sample = { name = "Heal", duration = 3, progress = .5 } })
        local bar = view:Frame()
        local point, relative, _, x = bar.castText:GetPoint(1)
        assert(bar.castText:GetText() == "Heal" and point == "LEFT" and relative == bar.statusBar and x == gutter)
        assert(select(4, bar.timeText:GetPoint(1)) == timeX)
        assert(gutter + bar.castText:GetWidth() + 44 <= bar.statusBar:GetWidth() + timeX,
            "spell label overran the timer's space")
    end
    casts:Deactivate()
    assert(general.enableBossCastbar and general.bossCastbarMatchWidth == "unitframe" and not general.bossCastbarDetached)
    local playerAuras = env.MSUF_DB.auras3.perUnit.player.layout
    local targetAuras = env.MSUF_DB.auras3.perUnit.target.layout
    assert(playerAuras.buffGroupOffsetY < general.castbarPlayerOffsetY and playerAuras.buffGroupIconSize == 22)
    assert(targetAuras.buffGroupOffsetY < general.castbarTargetOffsetY and targetAuras.debuffGroupOffsetY == targetAuras.buffGroupOffsetY)
    local db = env.MSUF_DB
    assert(db.player.frameBarShape == "SLANTED" and db.target.frameBarShape == "SLANTED")
    assert(db.bars.slantedCastbars and db.bars.slantedGroupFrames and db.boss.frameBarShape == "SLANTED")
    local surfaces = core.RoundedSurfaceKit
    surfaces.UpdateSlantedBarState()
    assert(db.auras3.shared.hideBlizzardBuffFrame and db.auras3.shared.hideBlizzardDebuffFrame)
    local auras = Public("MSUF_Auras3")
    local playerAuraConfig = auras.ResolveUnitFrameConfig("player", player)
    local targetAuraConfig = auras.ResolveUnitFrameConfig("target", target)
    assert(playerAuraConfig.lanes.buff.enabled and playerAuraConfig.lanes.debuff.enabled)
    assert(targetAuraConfig.lanes.buff.enabled and targetAuraConfig.lanes.debuff.enabled)
    assert(playerAuraConfig.sensors.dispelOverlay and playerAuraConfig.sensors.dispelOverlay.enabled,
        "the enabled player Dispel Overlay did not reach the aura runtime")
    local effects = targetAuraConfig.laneEffectsHostile or targetAuraConfig.laneEffects or targetAuraConfig.laneEffectsAssist
    assert(effects and effects.slots[1].frameEffect.type == "healthtint", "target debuff health tint did not compile")
    local firstBoss = config.GetSpec("boss1")
    for index = 1, 5 do
        local unit = "boss" .. index
        local boss = config.GetSpec(unit)
        assert(boss.enabled and boss.point == "TOPRIGHT" and boss.width == 208 and boss.height == 26)
        assert(boss.x == -336 and boss.y == -176 - (index - 1) * 64 and boss.health.mode == "class")
        local lanes = auras.ResolveUnitFrameConfig(unit, boss).lanes
        local buff, debuff = lanes.buff, lanes.debuff
        assert(buff.enabled and buff.anchor == "TOPLEFT" and debuff.enabled and debuff.anchor == "TOPRIGHT")
        assert(buff.size == 14 and debuff.size == 14 and buff.max == 4 and debuff.max == 4)
        assert(buff.x + buff.width < boss.width + debuff.x - debuff.width, "boss aura lanes overlap")
        local castBottom = boss.height + core.Castbars.Pools.UNITFRAME_GAP + general.bossCastbarHeight
            - general.bossCastbarOffsetY
        assert(-buff.y > castBottom and debuff.y == buff.y)
        assert(-buff.y + buff.height < -db.boss.spacing and -debuff.y + debuff.height < -db.boss.spacing,
            "boss aura lane reaches the following frame")
    end
    local groups = core.GF
    groups.EnsureDB()
    for _, case in ipairs({ { "party", 4, 1, 186, 175 }, { "raid", 40, 8, 382, 261 },
        { "mythicraid", 20, 4, 382, 129 } }) do
        local kind, count, maxGroups, expectedWidth, expectedHeight = unpack(case)
        local conf = groups.GetConf(kind)
        assert(conf.enabled and conf.anchorToFrame == "UIParent" and conf.anchorPoint == "TOPLEFT")
        assert(conf.offsetX == 18 and conf.offsetY == -198 and conf.maxColumns == maxGroups)
        local _, _, width, height = groups.GetGridMetrics(kind, count, maxGroups)
        assert(width == expectedWidth and height == expectedHeight, kind .. " has the wrong runtime footprint")
        assert(conf.offsetX + width < 1024 + firstBoss.x - firstBoss.width and -conf.offsetY + height < 464)
        assert(conf.showPlayer == (kind ~= "party") and conf.preserveRaidGroups == (kind ~= "party"))
        assert(conf.auras.buff.enabled and conf.auras.debuff.enabled and conf.auras.externals.enabled)
        local sample = { _msufIsGroupFrame = true, _msufGFKind = kind }
        assert(surfaces.RoundedFrameEnabled(sample) and surfaces.SurfaceMaskPath(sample):match("right_up%.png$"),
            "group renderer did not select the Wayfarer slant")
    end
    assert(db.player.texLayerEnabled and db.player.texLayerLevel < player.text.nameLayer)
    local plaquePath = core.TextureLayer.ResolveLayerTexture(db.player, "texLayer")
    assert(plaquePath:match("MSUF_Suite.*WayfarerPlaque%.tga$"))
    local sample = env.CreateFrame("Frame", nil, env.UIParent)
    sample:SetSize(player.width, player.height)
    core.TextureLayer.PaintSample(sample, "player", 100, 100, "ROGUE")
    local plaque = sample._msufTexLayers[1]
    assert(plaque:IsShown() and plaque:GetWidth() == 188 and plaque:GetHeight() == 18,
        "the Core texture layer did not paint the name plaque")
    if client == "Forever" then
        assert(core.SwingTimer.Get("main", "visibility") == "combat")
        assert(core.SwingTimer.Get("main", "height") == 12)
    end
    local slanted = core.RoundedSurface.ResolveSlantedMedia
    assert(slanted(nil, db.player):match("right_up%.png") and slanted(nil, db.target):match("left_down%.png"))
end
print("Wayfarer setup, preview geometry, profile imports and compiled frames passed on Retail and Forever.")
"""


def main():
    root = Path(sys.argv[1]).resolve()
    core = root / "MSUF_Suite/Core"
    factories = (
        ("RetailProfile.lua", "RetailProfileModule"),
        ("ForeverFactory.lua", "ForeverFactoryModule"),
        ("ModernDarkFactory.lua", "ModernDarkModule"),
        ("BlizzardFactory.lua", "BlizzardModule"),
        ("DarkRaidFactory.lua", "DarkRaidModule"),
        ("WayfarerFactory.lua", "WayfarerModule"),
    )
    fixtures = {}
    for file, name in factories:
        compact = literal(core / file, f"Suite.{name}Compact")
        fixtures[compact[7:]] = decode(compact, "MSUFM1:MSUF3:")
    frames = literal(core / "WayfarerFactory.lua", "Suite.WayfarerFramesCompact")
    fixtures[frames] = decode(frames, "MSUF3:")
    skin = literal(core / "WayfarerFactory.lua", "Suite.WayfarerSkinCompact")
    fixtures[skin] = decode(skin, "MSKIN1:")
    host = root.parent / "MidnightSimpleUnitFrames-7.0"
    defaults = host / "MidnightSimpleUnitFrames/State/Defaults"
    for file, key in (
        ("MSUF_Defaults_FactoryData.lua", "MSUF_FACTORY_DEFAULT_PROFILE_COMPACT"),
        ("MSUF_Defaults_ForeverFactory.lua", "MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT"),
    ):
        compact = literal(defaults / file, f"MSUF.{key}")
        fixtures[compact] = decode(compact, "MSUF3:")
    script = CHECK.replace("FIXTURES", lua_literal(fixtures), 1).replace("FRAME_COMPACT", lua_literal(frames), 1)
    return subprocess.run([LUA, "-", str(root), str(host)], input=script, text=True, cwd=root).returncode


if __name__ == "__main__":
    sys.exit(main())
