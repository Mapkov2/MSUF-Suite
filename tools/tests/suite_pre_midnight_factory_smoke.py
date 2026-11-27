"""The video layout uses the regular installer and ships its authored geometry."""

import re
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA, lua_literal

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_forever_factory_preview import decode
from build_modern_dark_factory import literal


CHECK = r'''
local root = arg[1]
local fixtures = FIXTURES
local bundledSkin = BUNDLED_SKIN
local H = assert(loadfile(root .. "/tools/tests/suite_installer_harness.lua"))()
local function CheckCooldownBorders(Suite, profile, source)
    local cdm = profile.suite.modules.cooldownManager
    for _, slot in ipairs(Suite.CDM.SLOTS) do
        local key = Suite.CDM.KEYS[slot.key].showIconBorder
        assert(cdm[key] == false, source .. " enables icon borders for " .. slot.key)
    end
end
local function CheckCooldownTint(modules)
    local cd = modules.cooldownManager
    for _, slot in ipairs({ "ess", "uti", "def", "ext", "c1", "c2", "c3", "c4", "c5", "c6" }) do
        assert(cd[slot .. "_usable"] == false and cd[slot .. "_range"] == false,
            slot .. " can still darken its spell textures as availability or range changes")
    end
    assert(modules.hudVisibility.cooldownManager == false, "HUD visibility still dims the Cooldown Manager")
    assert(cd.animateNewIcons and cd.ess_desat and cd.showGCD == false, "CDM animation or cooldown feedback changed")
end
local function CheckSpellIcons(scope, topLimit)
    local si = scope.spellIndicators
    assert(si.enabled and si.spec == "auto" and si.style.cooldownSize == 7 and si.style.cooldownDecimalSeconds == 0)
    for spec, entries in pairs(si.specs) do
        local rectangles = {}
        for aura, entry in pairs(entries) do
            local p = entry.placed
            assert(p.anchor == "BOTTOMLEFT" and p.x >= 2 and p.y >= 2
                and p.x + p.size <= scope.width - 2 and p.y + p.size <= topLimit,
                spec .. "." .. aura .. " leaves its reserved space")
            for _, other in ipairs(rectangles) do
                assert(p.x >= other.x + other.size or other.x >= p.x + p.size
                    or p.y >= other.y + other.size or other.y >= p.y + p.size,
                    spec .. "." .. aura .. " overlaps another spell icon")
            end
            rectangles[#rectangles + 1] = p
        end
    end
    local holy = si.specs.HolyPaladin
    assert(holy.BeaconOfLight.placed.type == "icon" and holy.BeaconOfFaith.placed.type == "icon"
        and holy.BeaconOfVirtue.placed.type == "icon" and holy.BeaconOfTheSavior.placed.type == "square")
    assert(holy.BlessingOfProtection.frame.type == "border")
    assert(si.specs.ClassicPaladin.BlessingOfProtection.frame.type == "border"
        and not si.specs.ClassicPaladin.BeaconOfLight and si.specs.ClassicPriest.WeakenedSoul.enabled == false)
end
local function CheckRetailLayouts(Suite, preset, frames)
    local common = { NS = Suite, CDM = { Const = { SPELL_CATEGORY = {
        COMBAT_POTION = 4, HEALTH_POTION = 30, HEALTHSTONE = 1711, DEMONIC_HEALTHSTONE = 2566,
    } }, EMPTY = {} } }
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/ForeverPresets.lua"))("MSUF_Suite_CooldownManager", common)
    assert(loadfile(root .. "/MSUF_Suite_CooldownManager/Presets.lua"))("MSUF_Suite_CooldownManager", common)
    local cdm = common.CDM
    assert(#cdm.Presets.PICKER_POTIONS == 6 and #cdm.Presets.PICKER_RACIALS == 3 and not cdm.FOREVER_PRESETS)
    assert(cdm.Presets.PICKER_RACIALS[2] == cdm.FOREVER_PICKER.racials)
    local variant = Suite.CopyValue(preset)
    local cd = variant.suite.modules.cooldownManager
    local count = 0
    for spec, spells in pairs(cdm.Presets.RAID_ESSENTIALS) do
        count = count + 1
        cd.ess_perRow = #spells
        for _, width in ipairs({ 1280, 1920, 2560 }) do
            for _, utility in ipairs({ 1, 5 }) do
                cd.uti_perRow = utility
                local scene = Suite.InstallerPreviewModel.Build(variant, frames, "preMidnight", nil,
                    { width = width, height = width * 9 / 16 })
                local ess, power, class = scene.cooldowns, scene.playerPower, scene.resource
                local p, t, ext = scene.player, scene.target, scene.externalCooldowns
                assert(p.x + p.width + 20 == ess.x and t.x == ess.x + ess.width + 19, "frame anchors: " .. spec)
                assert(power.x == ess.x and class.x == ess.x and power.width == ess.width and class.width == ess.width)
                assert(ext.x == p.x and ext.y == p.y + p.height, "potions detach from player: " .. spec)
                local u, cast = scene.utilityCooldowns, scene.playerCast
                assert(u.x + u.width / 2 == ess.x + ess.width / 2
                    and u.x == cast.x and u.width == cast.width and u.y + u.height == cast.y, "utility anchors: " .. spec)
            end
        end
    end
    assert(count == 40)
end
for _, forever in ipairs({ false }) do
    _G.MapkoSkin = nil
    local installedCompact
    local Suite = H.Setup({ root = root, forever = forever, uiWidth = 1920, uiHeight = 1080,
        addons = { MSUF_Suite_Skin = false }, frameFactory = function() return {} end })
    local import = MSUF_Profiles_ImportIntoNewProfile
    MSUF_Profiles_ImportIntoNewProfile = function(name, compact, ...)
        installedCompact = compact
        return import(name, compact, ...)
    end
    MSUF_TryDecodeCompactString = function(text)
        local fixture = assert(fixtures[text], "unexpected compact factory")
        return Suite.CopyValue(fixture)
    end
    local factories = 0
    for text, fixture in pairs(fixtures) do
        if fixture.addon == "MSUF_Suite" then
            local prepared = assert(Suite.ProfileIO.PrepareProfile("MSUFM1:" .. text, false))
            CheckCooldownBorders(Suite, prepared, "Bundled profile")
            Suite.Suite.StyleProfile(prepared, "classColor")
            CheckCooldownBorders(Suite, prepared, "Profile palette")
            factories = factories + 1
        end
    end
    assert(factories >= 8, "bundled profile coverage fell")
    local prior = Suite.DB
    prior.suite.modules.cooldownManager.listsData = "personal-lists"
    assert(Suite.Installer.Open())
    local window = MSUFSuiteInstallFrame
    window.next.scripts.OnClick()
    window.preMidnight.scripts.OnClick()
    assert(window.preMidnight.mark.text == Suite.Text("SELECTED"))
    assert(MSUF_ActiveProfile == "Default" and Suite.DB == prior, "preview installed the layout")
    local frames = assert(Suite.HostBridge.FactoryFramePreview("preMidnight"))
    assert(frames.general.enablePlayerCastbar and frames.general.castbarPlayerMatchWidth == "utility"
        and frames.general.castbarPlayerAnchorToUtility,
        "Pre-Midnight Player Cast Bar must follow MSUF Utility")
    assert(frames.general.castbarPlayerBarWidth == 144, "Player Cast Bar fallback differs from the preset Utility footprint")
    assert(frames.general.castbarPlayerIconSize == frames.general.castbarPlayerBarHeight,
        "Cast Bar icon protrudes beyond the flush top or bottom edge")
    assert(frames.gameplay.combatTimerBrackets and frames.gameplay.combatTimerKeepLast)
    assert(frames.gameplay.combatTimerAnchor == "chat" and frames.gameplay.combatOffsetY == 24)
    assert(not frames.player.showLevelIndicator and not frames.target.showLevelIndicator)
    assert(frames.player.showCombatStateIndicator and frames.player.combatStateIndicatorAnchor == "CENTER")
    assert(frames.player.showRestingIndicator and frames.player.restedStateIndicatorAnchor == "CENTER"
        and frames.player.restedStateIndicatorOffsetX > frames.player.combatStateIndicatorOffsetX)
    assert(frames.player.showLeaderIcon and frames.player.showRaidMarker
        and frames.player.showIncomingResIndicator and frames.player.showPvpIndicator)
    assert(frames.general.fontKey and frames.general.menuFontKey == "GLOBAL")
    assert(not frames.nameplates.fontKey and not frames.gf_priority.fontKey)
    assert(frames.bars.showBarBorder and frames.bars.barOutlineThickness == 1
        and not frames.bars.barOutlineClassColor and frames.bars.barOutlineTexture == "")
    assert(frames.general.barOutlineColorR == 0 and frames.general.barOutlineColorG == 0
        and frames.general.barOutlineColorB == 0 and frames.general.barOutlineColorA == 1)
    assert(frames.target.directNameOffsetX == frames.target.directHealthRightOffsetX)
    local targetAuras = frames.auras3.perUnit.target
    local buffs, flow = targetAuras.layout, targetAuras.layoutShared
    assert(buffs.buffAnchor == "TOPLEFT" and buffs.buffGroupOffsetX == 0 and buffs.buffStylePadding == 0
        and flow.buffGrowthX == "RIGHT" and flow.buffPerRow == 8 and flow.maxBuffs == 8)
    local buffWidth = flow.buffPerRow * buffs.buffGroupIconSize + (flow.buffPerRow - 1) * buffs.buffSpacing
    assert(buffWidth == frames.target.width, "the full Target buff row must meet both frame edges")
    assert(not frames.gf_party.targetsEnabled and not frames.gf_party.petsEnabled and not frames.gf_party.healerManaEnabled)
    local party = frames.gf_party
    assert(party.hpOffsetY == 0 and party.hpTextRightOffsetY == 11 and party.hpTextRightOffsetX == 0)
    for _, scope in ipairs({party, frames.gf_raid, frames.gf_mythicraid}) do
        assert(scope.borderEnabled and scope.borderSize == 1 and scope.borderA == 1
            and scope.borderR == 0 and scope.borderG == 0 and scope.borderB == 0)
        assert(not scope.nameShortenEnabled and scope.nameFormat == "FULL" and scope.nameMaxChars == 0)
        assert(scope.nameClassColor and scope.nameNpcClassColor and not scope.npcNameRed)
        assert(scope.showHPText and scope.textRight == "PERCENT" and scope.healthTextDecimals)
        assert(scope.leaderIcon and scope.leaderIconX == -38 and not scope.assistIcon and not scope.roleIcon)
    end
    assert(party.nameRightInset == 36 and party.leaderIconY == -4)
    CheckSpellIcons(party, 15)
    for _, scope in ipairs({frames.gf_raid, frames.gf_mythicraid}) do
        assert(scope.width == 94 and scope.hpTextRightOffsetY == 12 and scope.leaderIconY == -20)
        CheckSpellIcons(scope, 32)
    end
    assert(frames.target.nameClassColor and frames.target.npcNameRed
        and frames.focus.nameClassColor and frames.focus.npcNameRed)
    assert(not frames.targettarget.enabled and frames.targettarget.showToTInTargetName
        and frames.targettarget.totInlineColorMode == "TOT_NAME")
    local preset = assert(Suite.ProfileIO.PrepareProfile(Suite.PreMidnightModuleCompact, false))
    local modules = preset.suite.modules
    assert(not modules.runSummary.enabled and modules.buffReminders.enabled)
    local reminders = modules.buffReminders
    assert(reminders.point == 2 and reminders.x == 0 and reminders.y == -208 and reminders.anchorTarget == ""
        and reminders.showMythicPlus and reminders.showDungeonNormal and reminders.showRaidNormal,
        "buff reminders must open within the top edge, including dungeons and raids")
    local toast = modules.bnetToast
    assert(toast.enabled and toast.moved and toast.point == 7 and toast.x >= 20 and toast.y >= 212,
        "Battle.net must be inset from the bottom-left corner")
    local banner = modules.announcements
    assert(banner.enabled and banner.zone and banner.eventToasts and banner.quests and banner.achievements
        and banner.level and banner.scenario, "Pre-Midnight should keep the existing announcement types")
    assert(banner.anchor == 1 and banner.x == 0 and banner.y == -132 and banner.scale == 75,
        "announcement placement must be inset from the top edge at every viewport height")
    assert(not banner.showBoxArt and not banner.showFrame and not banner.levelClean
        and banner.backgroundOpacity == 0 and banner.titleSize == 22 and banner.subtitleSize == 14
        and banner.subtitleOffsetY == 32 and banner.font == "",
        "announcements should use compact text in the global font")
    local chat = modules.chat
    assert(chat.inputPushMessages and not chat.inputTop and chat.inputY == 38 and chat.inputHeight == 32)
    local tooltip = modules.tooltipAppearance
    local layout = tooltip.tooltipLayout
    assert(tooltip.enabled and tooltip.configured and tooltip.itemTooltipStyle == "card" and layout.palette)
    for _, field in ipairs({ "itemStyle", "spellStyle", "unitStyle", "questStyle", "lootStyle" }) do
        assert(layout[field] == "custom", field .. " falls back to default tooltips")
    end
    assert(layout.lootSurface == "match" and layout.borderMode == "custom" and layout.borderWidth == 1)
    local minimap = modules.minimap
    local shortcuts = modules.mapLandingShortcuts
    assert(shortcuts.enabled and shortcuts.showLandingPage and shortcuts.showVault and shortcuts.showJournal
        and shortcuts.showMap and shortcuts.size >= 24 and shortcuts.offsetY == shortcuts.size
        and minimap.showLanding == 1 and minimap.landingY == 34,
        "expansion shortcuts must stay visible and sit above the map readouts")
    assert(loadfile(root .. "/MSUF_Suite/Core/MinimapElements.lua"))("MSUF_Suite", Suite)
    local size, x, y = Suite.MinimapElements.QueueLayout(minimap)
    local radius = size / 2
    assert(Suite.MinimapElements.QueuePlacement(minimap) == "minimap"
        and x - radius >= 0 and x + radius <= minimap.size
        and -y - radius >= 0 and -y + radius <= minimap.size,
        "the centered queue eye sticks out of the top-left-relative map")
    local scene = Suite.InstallerPreviewModel.Build(preset, frames, "preMidnight", nil, {width = 1920, height = 1080})
    assert(scene.player.width == 209 and scene.player.x + scene.player.width + 20 == scene.cooldowns.x)
    assert(scene.target.x == scene.cooldowns.x + scene.cooldowns.width + 19)
    assert(scene.player.y == 692.5 and scene.focus.x == scene.player.x - 193.5 and scene.focus.y == 554 and scene.boss.y == 420)
    assert(scene.cooldowns.count == 9 and scene.cooldowns.y == 692)
    assert(scene.utilityCooldowns.width == 144 and scene.playerCast.x == scene.utilityCooldowns.x
        and scene.playerCast.width == scene.utilityCooldowns.width
        and scene.playerCast.y == scene.utilityCooldowns.y + scene.utilityCooldowns.height)
    assert(scene.resource.width == scene.cooldowns.width and scene.resource.y == 671 and scene.resource.height == 7)
    assert(scene.playerPower.x == scene.resource.x and scene.playerPower.width == scene.cooldowns.width
        and scene.playerPower.y + scene.playerPower.height == scene.cooldowns.y)
    assert(frames.bars.classPowerBgAlpha == 1 and frames.bars.classPowerTickWidth == 1)
    assert(frames.bars.classPowerWidthMode == "cooldown" and frames.bars.detachedPowerBarWidthMode == "cooldown")
    assert(frames.player.powerOffsetX == 0 and frames.player.powerOffsetY == 0
        and frames.player.directPowerCenterOffsetX == 0 and frames.player.directPowerCenterOffsetY == 0)
    local combo = frames.general.classPowerColorOverrides
    local emptyCombo = frames.general.classPowerBgColorOverrides.COMBO_POINTS
    assert(combo.COMBO_POINTS[1] == .76 and combo.COMBO_POINTS[2] == .72 and combo.COMBO_POINTS[3] == .31)
    assert(frames.bars.showChargedComboPoints and combo.CHARGED[1] == .46 and combo.CHARGED[2] == .73)
    assert(emptyCombo[1] == .12 and emptyCombo[2] == .12 and emptyCombo[3] == .12)
    assert(frames.general.powerColorOverrides.ENERGY)
    local defense = frames.auras3.customContainers.perUnit.player.items[4]
    assert(frames.auras3.shared.animateNewIcons == true)
    assert(defense.enabled and defense.playerDefensives and not defense.portraitIcon and defense.sourceUnit == "player")
    assert(defense.placed.anchor == "LEFT" and defense.placed.y == 0
        and defense.placed.size == 31 and defense.placed.growth == "LEFTDOWN"
        and defense.placed.iconHeightPercent == 106 and defense.placed.animateAppearance)
    assert(scene.actions.x + 1 == scene.w1.x and scene.actions.y + scene.actions.height == scene.w1.y)
    assert(scene.w3.x == scene.w2.x and scene.w3.y + scene.w3.height + 1 == scene.w2.y)
    assert(scene.raidControl.y == 0 and scene.party1.x == scene.player.x - 193.5 and scene.party1.y == 487)
    assert(scene.playerDefensives.x + scene.playerDefensives.width == scene.player.x
        and scene.playerDefensives.y == scene.player.y and scene.playerDefensives.height == scene.player.height)
    assert(scene.playerDefensives.iconWidth == 31 and scene.playerDefensives.iconHeight == 33)
    assert(scene.defensiveCooldowns.x + scene.defensiveCooldowns.width == scene.player.x + scene.player.width
        and scene.defensiveCooldowns.y + scene.defensiveCooldowns.height == scene.player.y)
    assert(scene.externalCooldowns.x == scene.player.x and scene.externalCooldowns.y == scene.player.y + scene.player.height)
    if not forever then CheckRetailLayouts(Suite, preset, frames) end
    assert((forever and not scene.battleRes) or (not forever and scene.battleRes.x == scene.chat.x + scene.chat.config.padding
        and scene.battleRes.y + scene.battleRes.height + 2 == scene.chat.y))
    assert(scene.combatTime.x + scene.combatTime.width == scene.chat.x + scene.chat.width)
    assert(scene.chat.height == scene.chat.config.windowHeight + scene.chat.config.padding + scene.chat.config.tabHeight
        and math.abs(scene.chat.y - (scene.combatTime.y + scene.combatTime.height)) <= 1)
    local wide = Suite.InstallerPreviewModel.Build(preset, frames, "preMidnight", nil, {width = 2560, height = 1440})
    assert(wide.actions.x + 1 == wide.w1.x and (forever or wide.battleRes.x == wide.chat.x + wide.chat.config.padding))
    assert(wide.combatTime.x + wide.combatTime.width == wide.chat.x + wide.chat.width)
    assert(wide.playerCast.x == wide.utilityCooldowns.x and wide.playerCast.width == wide.utilityCooldowns.width
        and wide.playerCast.y == wide.utilityCooldowns.y + wide.utilityCooldowns.height)
    assert(frames.general.anchorToCooldown and frames.general.anchorName == "EssentialCooldownViewer"
        and frames.player.anchorFrameName == frames.general.anchorName and frames.player.cooldownAnchorFrameTop
        and frames.target.anchorFrameName == frames.general.anchorName and frames.target.cooldownAnchorFrameTop)
    assert(frames.gf_raid.anchorToFrame == "MSUF_player" and frames.gf_mythicraid.anchorToFrame == "MSUF_player")
    local moved = Suite.CopyValue(preset)
    local movedCDM = moved.suite.modules.cooldownManager
    movedCDM.ess_x, movedCDM.ess_y, movedCDM.ess_perRow = 37, -176, 6
    movedCDM.uti_x, movedCDM.uti_y, movedCDM.uti_perRow = -17, -7, 1
    moved.suite.modules.damageMeter.w1X = -185
    moved.suite.modules.chat.windowX, moved.suite.modules.chat.windowY = 30, 40
    local movedScene = Suite.InstallerPreviewModel.Build(moved, frames, "preMidnight", nil, {width = 1920, height = 1080})
    local shrink = (scene.cooldowns.width - movedScene.cooldowns.width) / 2
    assert(movedScene.utilityCooldowns.width == 28 and movedScene.playerCast.width == movedScene.utilityCooldowns.width
        and movedScene.playerCast.x == movedScene.utilityCooldowns.x
        and movedScene.playerCast.y == movedScene.utilityCooldowns.y + movedScene.utilityCooldowns.height)
    for _, key in ipairs({"player", "focus", "party1", "playerDefensives", "defensiveCooldowns"}) do
        assert(movedScene[key].x == scene[key].x + 37 + shrink and movedScene[key].y == scene[key].y + 24, key)
    end
    for _, key in ipairs({"target", "boss"}) do
        assert(movedScene[key].x == scene[key].x + 37 - shrink and movedScene[key].y == scene[key].y + 24, key)
    end
    for _, key in ipairs({"resource", "playerPower"}) do
        assert(movedScene[key].x == movedScene.cooldowns.x and movedScene[key].width == movedScene.cooldowns.width
            and movedScene[key].y == scene[key].y + 24, key)
    end
    assert(movedScene.actions.x == scene.actions.x - 33)
    assert(forever or (movedScene.battleRes.x == scene.battleRes.x + 25 and movedScene.battleRes.y == scene.battleRes.y - 35))
    H.combat = true
    assert(not Suite.Installer.Apply() and MSUF_ActiveProfile == "Default")
    H.combat = false
    local ok, why = Suite.Installer.Apply()
    assert(ok, tostring(why))
    assert(installedCompact == Suite.PreMidnightFramesCompact and MSUF_ActiveProfile == "Pre-Midnight")
    assert(Suite.RootDB.installation.profile == "preMidnight")
    assert(Suite.RootDB.profiles.Default.suite.modules.cooldownManager.listsData == "personal-lists")
    local m = Suite.DB.suite.modules
    CheckCooldownTint(m)
    for id, config in pairs(m) do
        for key, value in pairs(config) do
            if key == "font" or key:match("Font$") then
                assert(type(value) ~= "string" or value == "", id .. "." .. key .. " bypasses the global font")
            end
        end
    end
    assert(not preset.nameplateShared.nameplates.fontKey)
    assert(not m.targetDistance.enabled)
    assert(m.chat.tabPanel and m.chat.tabHeight == 18 and m.chat.tabPanelGap == 0 and m.chat.hideTabArt
        and not m.chat.headerToolbar and not m.chat.tabAccent and not m.chat.tabIndividualPanels
        and m.chat.tabActiveColor == "f1f1ed" and m.chat.tabInactiveColor == "a9aba8")
    assert(m.chat.borderColor == "000000" and m.chat.borderSize == 1 and m.chat.borderAlpha == 100
        and m.chat.borderTexture == "")
    local cd = m.cooldownManager
    assert(cd.ess_anchor == 1 and not cd.essOnViewer and cd.uti_anchor == 2 and cd.buf_anchor == 2
        and cd.c3_anchor == 2 and cd.ext_anchor == 14)
    assert(cd.raidEssentials and cd.potionStockIcon and cd.ext_on and cd.ext_gap == 0)
    assert(cd.animateNewIcons and cd.buf_on and cd.def_on and cd.def_anchor == 14 and cd.def_side == 2
        and cd.def_align == 3 and cd.def_gap == 0 and cd.def_maxIcons == 5)
    local placed = defense.placed
    local activeWidth = placed.perRow * placed.size + (placed.perRow - 1) * placed.spacing
    assert(placed.x == -activeWidth)
    assert(cd.thresholdSeconds == 5 and cd.tenthsSeconds == 5 and cd.thresholdColor == "ff2222")
    assert(not cd.c1_on and cd.c3_on and cd.c3_kind == 2 and not cd.c3_shareContents)
    local lists = Suite.CDM.Codec.DecodeLists(cd.listsData)
    local dots = Suite.CDM.Codec.DecodeSpells(cd.spellsData)
    assert(lists.specs[259].c3[1] == "d703" and lists.specs[259].c3[2] == "d1943")
    assert(lists.specs[261] == nil and lists.specs[258].c3[1] == "d589" and lists.specs[265].c3[1] == "d980")
    assert(lists.specs[103].c3[1] == "d155722" and lists.specs[103].c3[2] == "d1079")
    assert(lists.specs[258].c3[2] == "d34914"
        and lists.specs[262].c3[1] == "d188389" and lists.specs[263].c3[1] == "d188389")
    for _, spec in pairs(lists.specs) do
        for _, key in ipairs(spec.c3) do
            local options = dots.e[key]
            local cast = key == "d155722" and 1822 or Suite.CDM.EntryID(key)
            assert(options.missingGlow and options.requireSpell1 == cast
                and options.glowStyle == 4, "missing DoT marker needs a learned spell")
        end
    end
    assert(m.battleRes.textOnly and m.battleRes.textFormat == 2 and m.battleRes.visibility == 2
        and m.battleRes.anchorTarget == 2 and m.actionTracker.anchorTarget == 2)
    assert(m.groupRaidShortcuts.panelCompact and m.groupRaidShortcuts.panelPoint == 2)
    assert(m.nameplates.enemyTextMode == 4 and m.nameplates.nativeHealthFillTexture == "Solid")
    assert(m.nameplates.highlightTarget and not m.nameplates.highlightFocus and not m.nameplates.enemyTargetMarker
        and m.nameplates.selectionTargetColor == "ffffff")
    assert(m.nameplates.enemyRoleColors and m.nameplates.enemyColorsInDungeons and m.nameplates.enemyColorsOutside
        and m.nameplates.enemyMeleeEnabled and m.nameplates.enemyCasterEnabled)
    assert(preset.nameplateShared.nameplates.nameClassColor and preset.nameplateShared.nameplates.npcNameRed
        and not m.nameplates.enemyNameColorEnabled and not m.nameplates.friendlyNameColorEnabled)
    assert(m.playerAuras.x == 15 and m.playerAuras.debuffX == -15 and m.playerAuras.perRow == 12
        and m.playerAuras.timerAnchor == 2 and m.playerAuras.buffSkin == "CUSTOM")
    assert(m.actionbars.bar4Visibility == 1 and m.actionbars.bar4Size == 22
        and m.actionbars.look == 4 and m.actionbars.buttonShape == 1 and m.actionbars.borderArt == 1
        and m.actionbars.iconSkin == "CUSTOM"
        and m.actionbars.borderColor == "0b0b0b" and m.actionbars.slotAlpha == 100 and not m.actionbars.masque)
    local meter = m.damageMeter
    assert(meter.w2Type == 10 and meter.w3Type == 3 and meter.headerMouseover and meter.headerButtonStyle == 2
        and not meter.headerSelectors and not meter.headerTimer)
    local map = m.minimap
    assert(map.buttonMailX == 29 and map.buttonMailY == -2
        and map.infoClockAnchor == 7 and map.infoFPSAnchor == 9 and map.infoLatencyAnchor == 9
        and map.infoClockX + map.infoClockWidth < map.size + map.infoFPSX - map.infoFPSWidth
        and map.infoFPSX < map.infoLatencyX - map.infoLatencyWidth)

    H.addons.MSUF_Suite_Skin = true
    local skin = H.FakeSkin()
    local prepare = skin.ProfileIO.PrepareProfile
    skin.ProfileIO.PrepareProfile = function(text)
        assert(text == bundledSkin, "incorrect skin in the combined import")
        return prepare(text)
    end
    assert(Suite.Skin.EnsureEngine())
    local bundle = "MSUFS3:" .. Suite.PreMidnightFramesCompact .. "\n"
        .. Suite.PreMidnightModuleCompact .. "\n" .. bundledSkin
    local stagedBundle = assert(Suite.SuiteProfiles.WorkbenchPrepareBundle(bundle))
    assert(stagedBundle.coreText == Suite.PreMidnightFramesCompact
        and stagedBundle.modules.nameplates.highlightTarget and stagedBundle.modules.battleRes.visibility == 2
        and stagedBundle.modules.playerAuras.timerAnchor == 2)
    local border = Suite.CDM.KEYS.ess.showIconBorder
    local activeCDM = Suite.DB.suite.modules.cooldownManager
    activeCDM[border] = true
    Suite.Suite.Normalize(Suite.DB)
    assert(activeCDM[border] == true, "an explicit border choice must survive normalization")
    assert(Suite.Database.StageFactoryReset())
    CheckCooldownBorders(Suite, Suite.DB, "Factory reset")
end

do
    _G.MapkoSkin = nil
    local Suite = H.Setup({ root = root, forever = true, uiWidth = 1920, uiHeight = 1080,
        addons = { MSUF_Suite_Skin = true }, frameFactory = function() return {} end })
    assert(loadfile(root .. "/MSUF_Suite/Core/API.lua"))("MSUF_Suite", Suite)
    local cvars = {}
    C_CVar.GetCVar = function(key) return cvars[key] or "0" end
    C_CVar.SetCVar = function(key, value) cvars[key] = tostring(value) return true end
    local skin = H.FakeSkin()
    skin.ProfileIO.PrepareProfile = function(text)
        assert(text == Suite.PreMidnightForeverSkinCompact, "Forever installer must use its own Skin profile")
        return Suite.CopyValue(FOREVER_SKIN_PROFILE)
    end
    MSUF_TryDecodeCompactString = function(text)
        local fixture = assert(fixtures[text], "unexpected Forever compact factory")
        return Suite.CopyValue(fixture)
    end
    local Import, installed
    Import = MSUF_Profiles_ImportIntoNewProfile
    MSUF_Profiles_ImportIntoNewProfile = function(name, compact, ...)
        installed = compact
        return Import(name, compact, ...)
    end
    local setup
    for _, entry in ipairs(Suite.API.GetSetupFramePresets()) do
        if entry.name == "Pre-Midnight" then setup = entry.compact end
    end
    assert(setup == Suite.PreMidnightForeverFramesCompact and type(setup) == "string")
    assert(Suite.Installer.Open())
    local window = MSUFSuiteInstallFrame
    window.next.scripts.OnClick()
    window.preMidnight.scripts.OnClick()
    assert(MSUF_ActiveProfile == "Default", "preview changed the active profile")
    local ok, why = Suite.Installer.Apply()
    assert(ok, tostring(why))
    assert(installed == Suite.PreMidnightForeverFramesCompact and MSUF_ActiveProfile == "Pre-Midnight")
    local modules = Suite.DB.suite.modules
    CheckCooldownTint(modules)
    local config = modules.hudVisibility
    assert(config.enabled and config.actionBars and config.dataTexts and not config.cooldownManager,
        "Forever should dim its other HUD elements without dimming the Cooldown Manager")
    local micro = skin.Database.GetProfile("Pre-Midnight").icons.microMenu
    assert(micro.visibility == "always" and micro.layoutMode == "owned" and micro.preset == "forever"
        and micro.barMaterial == "forever" and micro.layoutPoint == "BOTTOMRIGHT" and micro.layoutX == -2)
    local meter, tracker = modules.damageMeter, modules.actionTracker
    assert(micro.layoutY > meter.w1Y + meter.w1Height + tracker.rowHeight, "Micro Bar overlaps the meter/Action Tracker")

    local hud, timer, events = nil, nil, {}
    local runtime = { Public = Suite.Public, Install = function(_, module) hud = module end }
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/HUDVisibility.lua"))("MSUF_Suite_QualityOfLife", { NS = Suite, Suite = runtime })
    IsInInstance = function() return false end
    UnitExists = function() return false end
    C_Timer.NewTimer = function(delay, callback)
        assert(delay == 2)
        timer = callback
        return { Cancel = function() timer = nil end }
    end
    hud.config, hud.active = config, true
    hud.context = { Event = function(_, event, callback) events[event] = callback end }
    hud:Enable()
    assert(timer, "the authored HUD delay is missing")
    timer()
    assert(Suite.HUDVisibility.Factor("cooldownManager", false) == 1
        and Suite.HUDVisibility.Factor("actionBars", false) == 0.25, "the configured idle fade reached CDM")
    hud.config = Suite.CopyValue(config)
    hud.config.cooldownManager = true
    hud:Refresh()
    assert(Suite.HUDVisibility.Factor("cooldownManager", false) == 0.25, "the original HUD setting must reproduce the fade")
    hud.config = config
    hud:Refresh()
    events.PLAYER_TARGET_CHANGED(hud, "PLAYER_TARGET_CHANGED")
    assert(Suite.HUDVisibility.Factor("cooldownManager", false) == 1)
    local bundle = "MSUFS3:" .. installed .. "\n" .. Suite.PreMidnightForeverModuleCompact .. "\n" .. Suite.PreMidnightForeverSkinCompact
    assert(Suite.SuiteProfiles.WorkbenchPrepareBundle(bundle), "the Forever export must go through normal bundle import")
end
'''


def main():
    root = Path(sys.argv[1]).resolve()
    fixtures = {}
    for path in (root / "MSUF_Suite/Core").glob("*.lua"):
        source = path.read_text(encoding="utf-8-sig")
        for name in re.findall(r"Suite\.(\w+Compact)\s*=", source):
            value = literal(path, "Suite." + name)
            if value.startswith("MSUFM1:MSUF3:"):
                fixtures[value[7:]] = decode(value, "MSUFM1:MSUF3:")
                if name == "PreMidnightModuleCompact":
                    cd = fixtures[value[7:]][b"profile"][b"suite"][b"modules"][b"cooldownManager"]
                    for key in (b"listsData", b"spellsData"):
                        compact = cd[key].decode()
                        fixtures[compact] = decode(compact, "MSUF3:")
            elif value.startswith("MSUF3:"):
                fixtures[value] = decode(value, "MSUF3:")
    host_factory = (root.parent / "MidnightSimpleUnitFrames-7.0/MidnightSimpleUnitFrames/State/Defaults"
                    / "MSUF_Defaults_FactoryData.lua")
    default = literal(host_factory, "MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT")
    fixtures[default] = decode(default, "MSUF3:")
    bundled_skin = literal(root / "MSUF_Suite/Core/DarkRaidFactory.lua", "Suite.DarkRaidSkinCompact")
    assert decode(bundled_skin, "MSKIN1:")[b"payload"][b"enabled"]
    forever_skin = literal(root / "MSUF_Suite/Core/PreMidnightForeverFactory.lua", "Suite.PreMidnightForeverSkinCompact")
    forever_skin_profile = decode(forever_skin, "MSKIN1:")[b"payload"]
    source = (CHECK.replace("FIXTURES", lua_literal(fixtures), 1).replace("BUNDLED_SKIN", lua_literal(bundled_skin), 1)
              .replace("FOREVER_SKIN_PROFILE", lua_literal(forever_skin_profile), 1))
    return subprocess.run([LUA, "-", str(root)], input=source, text=True, cwd=root).returncode


if __name__ == "__main__":
    sys.exit(main())
