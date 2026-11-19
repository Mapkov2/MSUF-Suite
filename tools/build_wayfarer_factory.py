"""Build the Wayfarer setup profiles from the bundled MSUF factories."""
import argparse
import re
import struct

from build_forever_factory_preview import decode, encode
from build_modern_dark_factory import CORE, assignment, literal, put, write

FONT = r"Fonts\FRIZQT__.TTF"
BRASS = "a28655"
INK = "151713"
PAPER = "efe4ca"
MAP_SIZE = 290
RIGHT_MARGIN = -28
MAP_TOP = -24
FOOTER_HEIGHT = 22
QUEST_GAP = 10
HUD_LEFT = 18
HUD_BOTTOM = 14
PLAYER_TOP = 76
PLAYER_HEIGHT = 27
PLAYER_RESOURCE_TOP = PLAYER_HEIGHT + 5
PLAYER_CAST_TOP = PLAYER_RESOURCE_TOP + 10
PLAYER_CAST_HEIGHT = 22
PLAYER_AURA_TOP = PLAYER_CAST_TOP + PLAYER_CAST_HEIGHT + 5
PLAYER_PET_TOP = PLAYER_AURA_TOP + 23 + 5
GROUP_TOP = PLAYER_TOP + PLAYER_PET_TOP + 16 + 9
BOSS_TOP = 176
BOSS_WIDTH = 208
BOSS_HEIGHT = 26
BOSS_CAST_HEIGHT = 12
BOSS_AURA_SIZE = 14
BOSS_AURA_GAP = 7  # Room for the castbar's native gap and a gutter below it.
BOSS_AURA_TOP = BOSS_HEIGHT + BOSS_CAST_HEIGHT + BOSS_AURA_GAP
BOSS_SPACING = BOSS_AURA_TOP + BOSS_AURA_SIZE + 5
FRAME_EDGE = "7c6440"
CHAT_PADDING = 4
CHAT_COLUMN_WIDTH = 272
# The native tab is 32 units high and sits two units above the chat frame.
CHAT_TAB_CLEARANCE = 36
BAR_BUTTONS = 12
BAR_BUTTON_SIZE = 32
BAR_GAP = 4
BAR_PANEL_PADDING = 2
BAR_ROW_GAP = 4
XP_HEIGHT = 10
XP_Y = HUD_BOTTOM + BAR_BUTTON_SIZE + BAR_PANEL_PADDING + BAR_ROW_GAP
SECOND_BAR_Y = XP_Y + XP_HEIGHT + BAR_ROW_GAP + BAR_PANEL_PADDING
THIRD_BAR_Y = SECOND_BAR_Y + BAR_BUTTON_SIZE + 2 * BAR_PANEL_PADDING + BAR_ROW_GAP
MAIN_BAR_WIDTH = BAR_BUTTONS * BAR_BUTTON_SIZE + (BAR_BUTTONS - 1) * BAR_GAP
PLAQUE_NAME = "WayfarerPlaque.tga"
ENDCAP_NAME = "WayfarerEndcap.tga"
MAP_FRAME_NAME = "WayfarerMinimapFrame.tga"
MEDIA = "Interface\\AddOns\\MSUF_Suite\\Media\\"


def boss_frames(db):
    boss = db[b"boss"]
    for key in (b"anchorToUnitframe", b"screenPositionMode", b"screenPositionHeight", b"_screenRefH"):
        boss.pop(key, None)
    put(boss, enabled=True, anchorFrameName="UIParent", point="TOPRIGHT", relativePoint="TOPRIGHT",
        offsetX=RIGHT_MARGIN - MAP_SIZE - 18, offsetY=-BOSS_TOP, width=BOSS_WIDTH, height=BOSS_HEIGHT,
        bossLayoutMode="VERTICAL_DOWN", spacing=-BOSS_SPACING,
        frameBarShape="SLANTED", slantedBarDirection="LEFT_DOWN", portraitMode="OFF",
        healthColorMode="CLASS", smoothFill=False, showName=True, showHP=True, showPowerBar=False,
        barBgColorOverride=True, bgR=.12, bgG=.10, bgB=.08,
        nameFontSize=12, hpTextRightFontSize=12, textLeft="NONE", textCenter="NONE", textRight="PERCENT",
        directTextLayout=True, directNamePoint="LEFT", directNameRelativePoint="LEFT", directNameWidth=118,
        directNameOffsetX=32, directNameOffsetY=0, directHealthRightPoint="RIGHT", directHealthRightRelativePoint="RIGHT",
        directHealthRightOffsetX=-8, directHealthRightOffsetY=0,
        showRaidMarker=True, raidMarkerAnchor="LEFT", raidMarkerOffsetX=16, raidMarkerOffsetY=0, raidMarkerSize=12)
    put(db[b"general"], enableBossCastbar=True, bossCastbarBackend="MSUF", bossCastbarDetached=False,
        bossCastbarMatchWidth="unitframe", bossCastbarWidth=BOSS_WIDTH, bossCastbarHeight=BOSS_CAST_HEIGHT,
        bossCastbarOffsetX=0, bossCastbarOffsetY=0, bossCastIconSize=12, bossCastIconSpacing=3,
        bossCastSpellNamePosition="LEFT", bossCastSpellNameFontSize=10, bossCastTimeFontSize=10,
        bossCastTextOffsetX=10, bossCastTimeOffsetX=-6,
        bossCastSpellNameTruncate="CLIP", bossCastSpellNameMaxWidth=118,
        showBossCastIcon=True, showBossCastName=True, showBossCastTime=True)

    for index in range(1, 6):
        aura = db[b"auras3"][b"perUnit"][f"boss{index}".encode()]
        put(aura[b"layout"], buffAnchor="TOPLEFT", debuffAnchor="TOPRIGHT",
            buffGroupOffsetX=2, debuffGroupOffsetX=-2, buffGroupOffsetY=-BOSS_AURA_TOP, debuffGroupOffsetY=-BOSS_AURA_TOP,
            buffGroupIconSize=BOSS_AURA_SIZE, debuffGroupIconSize=BOSS_AURA_SIZE,
            buffIconHeightPercent=100, debuffIconHeightPercent=100,
            buffSpacing=2, debuffSpacing=2, buffCooldownTextSize=8, debuffCooldownTextSize=8,
            buffStackTextSize=8, debuffStackTextSize=8)
        put(aura[b"layoutShared"], showBuffs=True, showDebuffs=True,
            maxBuffs=4, maxDebuffs=4, buffPerRow=4, debuffPerRow=4,
            buffGrowthX="RIGHT", debuffGrowthX="LEFT", buffGrowthY="DOWN", debuffGrowthY="DOWN",
            debuffTypeBorderMode="BORDER")


def group_frames(db):
    for key, groups in ((b"gf_party", 1), (b"gf_raid", 8), (b"gf_mythicraid", 4)):
        party = key == b"gf_party"
        frame = db[key]
        for field in (b"screenPositionMode", b"screenPositionHeight", b"positionMigrationCount",
                      b"positionMigrationDX", b"positionMigrationDY"):
            frame.pop(field, None)
        put(frame, enabled=True, anchorToFrame="UIParent", point="TOPLEFT", anchorPoint="TOPLEFT",
            relativePoint="TOPLEFT", offsetX=HUD_LEFT, offsetY=-GROUP_TOP, positionMode="GRID_BOUNDS_V2",
            width=186 if party else 74, height=40 if party else 30, spacing=5 if party else 3,
            growth="DOWN" if party else "RIGHT", groupGrowth="DOWN", unitsPerColumn=5, maxColumns=groups,
            showPlayer=not party, showSolo=False, centerSolo=False, preserveRaidGroups=not party, showGroupNumber=False,
            collapseEmptyGroups=not party, layoutTiersEnabled=False, frameScaleMode="off",
            gfBarMode="class" if party else "dark", healthColorMode="CLASS" if party else "DARK",
            gfDarkR=.18, gfDarkG=.145, gfDarkB=.105, barBgColorOverride=True, bgR=.09, bgG=.085, bgB=.065,
            hpBarAlpha=.94, hpBgAlpha=.88, smoothFill=False, chunkedFill=False,
            frameBarShape="SLANTED", slantedBarDirection="RIGHT_UP",
            barTextureOverride=True, barTexture="MSUF Smooth", borderEnabled=True, borderSize=1,
            borderR=.43, borderG=.34, borderB=.22, borderA=1, portraitMode="OFF", nameBarEnabled=False,
            fontOverride=True, fontKey="FRIZQT", fontSlug=False, fontOutline="OUTLINE",
            showName=True, nameColorMode="CUSTOM" if party else "CLASS", nameClassColor=not party,
            nameColorR=.94, nameColorG=.89, nameColorB=.79, nameAnchor="TOPLEFT",
            nameOffsetX=21 if party else 4, nameOffsetY=-5 if party else -3,
            nameMaxChars=14 if party else 8, nameFontSize=12 if party else 10,
            showHPText=party, textLeft="NONE", textCenter="NONE", textRight="PERCENT" if party else "NONE",
            hpFontSize=11, hpOffsetX=-16, hpOffsetY=10, hpTextRightOffsetX=0, hpTextRightOffsetY=0,
            powerBarEnabled=True, powerHeight=3 if party else 2, showPowerText=False,
            powerSmoothFill=False, powerChunkedFill=False,
            roleIcon=party, roleIconAnchor="TOPLEFT", roleIconX=4, roleIconY=-4, roleIconSize=12,
            leaderIcon=party, leaderIconAnchor="TOPRIGHT", leaderIconX=-42, leaderIconY=-4, leaderIconSize=12,
            raidMarker=True, raidMarkerAnchor="LEFT" if party else "TOPRIGHT", raidMarkerSize=10,
            raidMarkerX=-7 if party else -6, raidMarkerY=0 if party else -6,
            dispelOverlayEnabled=True, dispelOverlayTrigger="DISPEL_TYPE", dispelOverlayOnHealth=True,
            dispelOverlayAlpha=.32)

        auras = frame[b"auras"]
        size = 14 if party else 10
        y = 5 if party else 4
        text_size = 8 if party else 7
        buffs, debuffs = (3, 3) if party else (1, 2)
        put(auras, enabled=True)
        for lane in (b"buff", b"debuff", b"externals"):
            put(auras[lane], cooldownSize=text_size, stackSize=text_size, stackOffsetX=0, stackOffsetY=0)
        put(auras[b"buff"], enabled=True, anchor="BOTTOMLEFT", x=size + 8, y=y,
            size=size, max=buffs, perRow=buffs, spacing=2, growth="RIGHTUP")
        put(auras[b"debuff"], enabled=True, anchor="BOTTOMRIGHT", x=-10, y=y,
            size=size, max=debuffs, perRow=debuffs, spacing=2, growth="LEFTUP")
        put(auras[b"externals"], enabled=True, anchor="BOTTOMLEFT", x=4, y=y,
            size=size, max=1, perRow=1, spacing=2, growth="RIGHTUP")


def frames():
    envelope = decode(literal(CORE / "ModernDarkFactory.lua", "Suite.ModernDarkFramesCompact"), "MSUF3:")
    put(envelope, profile="Wayfarer")
    db = envelope[b"payload"]
    put(db[b"general"], anchorToCooldown=False, anchorName="UIParent",
        fontKey="FRIZQT", noOutline=False, fontSlug=False, fontShadowOpacity=1,
        barMode="class", useClassColors=True, darkMode=False,
        unifiedBarR=.86, unifiedBarG=.65, unifiedBarB=.32,
        barTexture="MSUF Smooth", barBackgroundTexture="Solid", barBgColorMode="custom",
        barOutlineColorR=.22, barOutlineColorG=.17, barOutlineColorB=.10, barOutlineColorA=1,
        portraitBorderColorR=.62, portraitBorderColorG=.52, portraitBorderColorB=.36, portraitBorderColorA=1,
        npcClassColorBar=False, npcTypeColorBar=True, npcColorMode="reaction", nameClassColor=False,
        nameColorMode="CUSTOM", nameColorR=.94, nameColorG=.89, nameColorB=.79,
        powerColorMode="power",
        enablePlayerCastbar=True, enableTargetCastbar=True,
        castbarTexture="MSUF Smooth", castbarBackgroundTexture="Solid", castbarOutlineThickness=2,
        castbarBgR=.068, castbarBgG=.052, castbarBgB=.04, castbarBgA=.96,
        castbarBorderR=.47, castbarBorderG=.35, castbarBorderB=.22, castbarBorderA=1,
        castbarInterruptibleR=.78, castbarInterruptibleG=.53, castbarInterruptibleB=.24,
        castbarNonInterruptibleR=.56, castbarNonInterruptibleG=.26, castbarNonInterruptibleB=.22,
        castbarFontR=.98, castbarFontG=.94, castbarFontB=.85,
        castbarSpellNameFontSize=13, castbarTimeFontSize=12,
        castbarShowGlow=False, castbarShowSpark=False, castbarInterruptShake=False, castbarArtworkEnabled=False,
        castbarPlayerBackend="MSUF", castbarPlayerDetached=False, castbarPlayerMatchWidth="unitframe",
        castbarPlayerOffsetX=0, castbarPlayerOffsetY=-(PLAYER_CAST_TOP + PLAYER_CAST_HEIGHT),
        castbarPlayerBarHeight=PLAYER_CAST_HEIGHT, castbarPlayerIconSize=PLAYER_CAST_HEIGHT, castbarPlayerIconSpacing=4,
        castbarPlayerTextOffsetX=6, castbarPlayerTimeOffsetX=-12,
        castbarPlayerSpellNameTruncate="CLIP", castbarPlayerSpellNameMaxWidth=116,
        castbarPlayerIconBorderThickness=1, castbarPlayerTimeFormat="CURRENT",
        castbarTargetDetached=False, castbarTargetMatchWidth="unitframe", castbarTargetOffsetX=0, castbarTargetOffsetY=-66,
        castbarTargetBarHeight=20, castbarTargetIconSize=20, castbarTargetIconSpacing=4,
        castbarTargetTextOffsetX=14, castbarTargetTimeOffsetX=-10,
        castbarTargetSpellNameTruncate="CLIP", castbarTargetSpellNameMaxWidth=212,
        castbarTargetIconOffsetY=0, castbarTargetTimeFormat="CURRENT")
    db[b"npcColors"] = {
        b"enemy": [.72, .25, .22],
        b"neutral": [.79, .63, .27],
        b"friendly": [.36, .64, .32],
    }
    put(db[b"bars"], slantedBarsEnabled=True, slantedUnitFrames=True, slantedGroupFrames=True,
        slantedPowerBars=True, slantedCastbars=True, slantedBarDirection="RIGHT_UP",
        smoothPowerBar=False, classPowerSmoothFill=False,
        showClassPower=True, classPowerAnchorToCooldown=False, classPowerWidthMode="custom",
        classPowerWidth=126, classPowerHeight=5, classPowerOffsetX=64, classPowerOffsetY=2 - PLAYER_RESOURCE_TOP,
        barOutlineThickness=2)

    for unit, side, width, height, point, x, y, shape, mode in (
        (b"player", "LEFT", 218, PLAYER_HEIGHT, "TOPLEFT", 64, -PLAYER_TOP, "RIGHT_UP", "CLASS"),
        (b"target", "RIGHT", 318, 25, "TOP", -12, -66, "LEFT_DOWN", "CLASS"),
    ):
        frame = db[unit]
        for key in (b"anchorToUnitframe", b"screenPositionMode", b"screenPositionHeight", b"_screenRefH"):
            frame.pop(key, None)
        player = unit == b"player"
        outer, inner = ("LEFT", "RIGHT") if player else ("RIGHT", "LEFT")
        put(frame, anchorFrameName="UIParent", point=point, relativePoint=point, offsetX=x, offsetY=y,
            width=width, height=height, healthColorMode=mode, smoothFill=False, powerSmoothFill=False,
            frameBarShape="SLANTED", slantedBarDirection=shape,
            fontOverride=False, nameFontSize=13, hpFontSize=16, hpTextLeftFontSize=17, hpTextRightFontSize=16,
            barBgColorOverride=True, bgR=.12, bgG=.10, bgB=.08,
            showName=True, showHP=True, showPowerBar=True, showPowerText=False,
            textLeft="NONE" if player else "CURRENT", textCenter="NONE",
            textRight="CURRENT" if player else "NONE", hpFullValueShort=True,
            directTextLayout=True, directNamePoint="CENTER", directNameRelativePoint="TOP",
            directNameWidth=width - (38 if player else 106), directNameOffsetX=0, directNameOffsetY=10,
            directHealthLeftPoint="BOTTOMLEFT", directHealthLeftRelativePoint="TOPLEFT",
            directHealthLeftOffsetX=4, directHealthLeftOffsetY=0,
            directHealthRightPoint="RIGHT", directHealthRightRelativePoint="RIGHT",
            directHealthRightOffsetX=-16, directHealthRightOffsetY=2,
            powerBarDetached=False, powerBarHeight=5,
            detachedPowerBarAnchorToClassPower=False, detachedPowerBarSyncClassPower=False,
            portraitMode=side, portraitRender="2D", portraitShape="CIRCLE",
            portraitPlacement="DETACHED", portraitDetachedPoint=inner, portraitDetachedTo=outer,
            portraitSizeMode="UNIFORM", portraitSizeOverride=47,
            portraitOffsetX=8 if player else -7, portraitOffsetY=0,
            portraitAlpha=100, portraitLevelOffset=7, portraitBorderStyle="CUSTOM",
            portraitBorderArt="RELIEF", portraitBorderThickness=2,
            showLevelIndicator=unit == b"target", levelIndicatorSize=10, levelIndicatorAnchor="BOTTOMRIGHT",
            levelIndicatorOffsetX=35, levelIndicatorOffsetY=-6, levelIndicatorDifficultyColor=True)
        if player:
            put(frame, unitDispelOverlayEnabled=True, unitDispelOverlayTrigger="DISPEL_TYPE",
                unitDispelOverlayOnHealth=True, unitDispelOverlayAlpha=.40)
            put(frame, texLayerEnabled=True, texLayerSourceMode="CUSTOM", texLayerCustomTexturePath=MEDIA + PLAQUE_NAME,
                texLayerVisibility="ALWAYS", texLayerColorMode="CUSTOM", texLayerLevel=2,
                texLayerAnchorTarget="FRAME", texLayerAnchor="TOP", texLayerSizeMode="MANUAL",
                texLayerWidth=width - 30, texLayerHeight=18, texLayerOffsetX=0, texLayerOffsetY=19,
                texLayerAlpha=1)
    put(db[b"pet"], offsetY=PLAYER_HEIGHT - PLAYER_PET_TOP, frameBarShape="SLANTED", slantedBarDirection="RIGHT_UP")
    put(db[b"targettarget"], width=90, height=16, point="TOP", relativePoint="BOTTOM", offsetX=0, offsetY=-52,
        frameBarShape="SLANTED", slantedBarDirection="LEFT_DOWN",
        healthColorMode="DARK", nameFontSize=11, fontOverride=True,
        nameColorMode="CUSTOM", nameColorR=.91, nameColorG=.78, nameColorB=.52)

    # The native timers already supply progress. Keep idle bars off the world
    # view and use the same compact colors and type as the rest of the HUD.
    swing = db.setdefault(b"swingTimers", {})
    put(swing, enabled=True)
    for hand, y in ((b"main", -135), (b"off", -149), (b"ranged", -135)):
        put(swing.setdefault(hand, {}), visibility="combat", y=y, width=196, height=12,
            fontSize=10, nextSwingCue=False,
            color=[.78, .58, .30], backgroundColor=[.09, .085, .067], textColor=[.94, .89, .79])
    auras = db[b"auras3"]
    put(auras[b"shared"], showBuffs=True, showDebuffs=True,
        hideBlizzardBuffFrame=True, hideBlizzardDebuffFrame=True)
    for unit in (b"player", b"target"):
        aura = auras[b"perUnit"][unit]
        player = unit == b"player"
        aura_y = -PLAYER_AURA_TOP if player else -76
        put(aura[b"layout"], buffAnchor="TOPLEFT", debuffAnchor="TOPRIGHT",
            buffGroupOffsetX=-33 if player else 5, buffGroupOffsetY=aura_y,
            debuffGroupOffsetX=-5, debuffGroupOffsetY=aura_y,
            buffGroupIconSize=22, debuffGroupIconSize=23, buffIconHeightPercent=100, debuffIconHeightPercent=100,
            buffSpacing=4, debuffSpacing=4, buffCooldownTextSize=10, debuffCooldownTextSize=10)
        put(aura[b"layoutShared"], showBuffs=True, showDebuffs=True,
            maxBuffs=4, maxDebuffs=4, buffPerRow=4, debuffPerRow=4,
            buffGrowthX="RIGHT", debuffGrowthX="LEFT", debuffTypeBorderMode="BORDER",
            debuffFrameEffectType="border" if player else "healthtint",
            debuffFrameEffectColor=[.72, .30, .20, .74 if player else .24],
            debuffFrameEffectThickness=1)
    boss_frames(db)
    group_frames(db)
    return encode(envelope, "MSUF3:")


def modules():
    envelope = decode(literal(CORE / "RetailProfile.lua", "Suite.RetailProfileModuleCompact"), "MSUFM1:MSUF3:")
    suite = envelope[b"profile"][b"suite"]
    migrations = (CORE / "Suite.lua").read_text(encoding="utf-8").split("local MIGRATIONS = {", 1)[1].split("\n}", 1)[0]
    put(suite, revision=len(re.findall(r"\{ run =", migrations)))
    entries = suite[b"modules"]
    put(entries.setdefault(b"navigationHUD", {}), enabled=True, showCompass=True,
        compassWidth=260, compassX=0, compassY=-10, accentColor=BRASS,
        hideInCombat=True, shortcutMode=2)
    footer_top = MAP_TOP - MAP_SIZE
    put(entries[b"minimap"], enabled=True, captured=True, stylePreset=1, shape=1, point=3,
        size=MAP_SIZE, x=RIGHT_MARGIN, y=MAP_TOP, hoverResize=False,
        styleTexture=6, styleTexturePath=MEDIA + MAP_FRAME_NAME, styleScale=100, styleAlpha=100,
        stylePlacement=1, styleBlend=1, styleRotation=0, styleColor="ffffff", styleX=0, styleY=0,
        styleGlow=False, styleBackdrop=False, borderSize=1, borderColor="352b20",
        outerBorderSize=0, borderClassColor=False, shadowSize=5, shadowColor="100e0b", shadowAlpha=50,
        infoLocation=True, infoLocationSource=4, infoLocationAnchor=2, infoLocationX=0, infoLocationY=-9,
        infoLocationFont=FONT, infoLocationSize=17, infoLocationWidth=260, infoLocationColor=PAPER,
        infoLocationZoneColor=False, infoLocationOutline=1, infoLocationShadow=True,
        infoCoordinates=True, infoCoordinatesMode=2, infoCoordinatesAnchor=2,
        infoCoordinatesX=0, infoCoordinatesY=-31, infoCoordinatesFont=FONT, infoCoordinatesSize=11,
        infoCoordinatesColor="cfbc99", infoCoordinatesDecimals=1, infoCoordinatesOutline=1, infoCoordinatesShadow=True,
        infoClock=True, infoClockAnchor=8, infoClockX=0, infoClockY=9, infoClockFont=FONT,
        infoClockSize=14, infoClockColor=PAPER, infoClockDate=False, infoClock24Hour=False,
        infoClockOutline=1, infoClockShadow=True,
        infoFPS=False, infoLatency=False, infoDurability=False, infoWeather=False, infoCalendarDay=False,
        showTracking=True, trackingMouseover=True, showCalendar=False, showCompartment=False,
        zoomButtons=3, middleClick=2, infoClockClick=1)

    texts = entries[b"dataTexts"]
    put(texts, enabled=True, barIds="1", trackAltGold=False, hideBlizzardBagBar=False,
        bar1Enabled=True, bar1Point=3, bar1X=RIGHT_MARGIN, bar1Y=footer_top,
        bar1Width=MAP_SIZE, bar1Height=FOOTER_HEIGHT, bar1Visibility=1, bar1LoadCondHideInCombat=False,
        bar1Dock=1, bar1MinimapDock=True, bar1MinimapDockGap=0, bar1FullScreen=False, bar1Vertical=False, bar1StyleOverride=True, bar1CustomColors=True,
        bar1BackgroundEnabled=True, bar1BackgroundColor=INK, bar1BackgroundOpacity=94,
        bar1BackgroundGradient=False, bar1BorderEnabled=True, bar1BorderColor="59462c",
        bar1AccentEnabled=False, bar1SeparatorEnabled=True, bar1SeparatorColor="4c4030",
        bar1Font=FONT, bar1FontSize=11, bar1Padding=2, bar1TextOutline=1, bar1ValueColor=PAPER,
        bar1ShowLabels=False, bar1SourceIcons=True, bar1BagBadge=False, bar1Layout=1, bar1Gap=0,
        bar1FpsAccent=True, bar1PerformanceLabels=True,
        bar1Slot1=2, bar1Slot2=4, bar1Slot3=3, bar1Slot4=13, bar1Slot5=1, bar1Slot6=1,
        bar1Slot1Weight=80, bar1Slot2Weight=75, bar1Slot3Weight=100, bar1Slot4Weight=145,
        bar1Slot1Padding=2, bar1Slot2Padding=2, bar1Slot3Padding=2, bar1Slot4Padding=2)
    put(entries[b"objectives"], enabled=True, x=RIGHT_MARGIN, y=footer_top - FOOTER_HEIGHT - QUEST_GAP,
        width=MAP_SIZE, height=370, scale=100, dockBelowMinimap=True, minimapDockGap=QUEST_GAP,
        groupQuestsByZone=False, groupQuestsByHeader=True, hideCompletedObjectives=True, animateQuestCollapse=False,
        showQuestLevel=True, questDifficultyColor=True, showDungeonBadge=True, showQuestLogCount=True,
        compactQuestRows=True, questProgressColumn=True,
        focusedTitleColor=True, groupUnderlines=True, questIconStyle=3, showHeader=True,
        titleSize=17, sectionSize=13, entrySize=15, objectiveSize=13, font=FONT,
        fontOutline=1, fontRendering=1, fontShadow=True, fontShadowOpacity=95, fontShadowDistance=1,
        colorStyle=2, backgroundColor=INK, backgroundOpacity=28, titleColor=PAPER, textColor=PAPER, mutedColor="e6dac0",
        dividerColor=BRASS, focusedColor="e5bc79", campaignColor="cfab67", questsColor="ddbd8b",
        completeColor="b8d4aa", completeGroupColor="a9c398")

    bars = entries[b"actionbars"]
    put(bars, enabled=True, imported=True, look=4, borderArt=1, iconSkin="CUSTOM", buttonShape=1,
        borderColor=FRAME_EDGE, borderSize=1, borderClassColor=False, iconZoom=8,
        slotColor="29241a", slotAlpha=55, interactionColor="d0aa67",
        keybindColor=PAPER, macroColor=PAPER, countColor=PAPER, procGlow=2, swipeAlpha=0,
        rangeIndicator=2, profileKeybinds=False, pageArrows=False)
    for index, y in enumerate((HUD_BOTTOM, SECOND_BAR_Y, THIRD_BAR_Y), 1):
        put(bars, **{f"bar{index}{key}": value for key, value in dict(
            Visibility=1, Point=8, X=0, Y=y, Rows=1, Buttons=BAR_BUTTONS, Size=BAR_BUTTON_SIZE, Spacing=BAR_GAP,
            Vertical=False, HeightPercent=100, ShowEmpty=True, FadeDuration=0, KeybindSize=10, CountSize=11,
            Background=True, BackgroundColor=INK, BackgroundAlpha=85, BackgroundBorder=1,
            BackgroundPaddingX=0, BackgroundPaddingY=BAR_PANEL_PADDING, BackgroundX=0, BackgroundY=0,
            LeftEndcap=1, RightEndcap=1, Macro=False).items()})
    for index in range(4, 11):
        put(bars, **{f"bar{index}Visibility": 6})
    stance_y = THIRD_BAR_Y + BAR_BUTTON_SIZE + BAR_PANEL_PADDING + BAR_ROW_GAP
    for index, y in ((11, stance_y), (12, stance_y + 28)):
        put(bars, **{f"bar{index}{key}": value for key, value in dict(
            Visibility=1, Point=8, X=0, Y=y, Rows=1, Size=22, Spacing=3, Vertical=False,
            ShowEmpty=False, FadeDuration=0).items()})

    plates = entries[b"nameplates"]
    put(plates, enabled=True, look=3, nativeStyle=5, nativeSize=3, barGeometry=2,
        enemyTextMode=5, enemyMirrorHeader=False, enemyNameFont=FONT, enemyNameSize=13, enemyTextShadow=True,
        enemyHealthHeightDelta=3, enemyLevelEnabled=True, enemyLevelSize=10, enemyLevelColor=True,
        enemyBorderEnabled=True, enemyBorderSize=1, enemyBorderColor=FRAME_EDGE,
        enemyOutlineMode=3, selectionBorder=3, enemySlantedHealth=True,
        highlightTarget=True, highlightBorderSize=1, selectionTargetColor=BRASS,
        barsOverride=True, enemyRoleColors=False, nativeHealthFillTexture="MSUF Smooth", nativeHealthBackgroundTexture="Solid",
        nativeCastFillTexture="MSUF Smooth", nativeCastBackgroundTexture="Solid",
        nativeCastFillColor="c7873d", nativeCastLockedColor="8f4238",
        enemyCastEnabled=2, enemyCastDisplay=2, enemyCastSpellName=True, enemyCastSpellIcon=True,
        enemyCastWidthMode=2, enemyCastHeight=15, enemyCastIconSize=15,
        enemyCastIconBorder=True, enemyCastIconBorderSize=1, enemyCastIconBorderColor=FRAME_EDGE,
        enemyCastTextEnabled=True, enemyCastCustomFont=True, enemyCastFont=FONT, enemyCastSize=11,
        enemyCastOutline=1, enemyCastTextShadow=True, enemyCastTimeEnabled=True, enemyCastTimeFormat=1, enemyCastTimeSize=10,
        enemyCastOffsetX=0, enemyCastOffsetY=0, enemyCastTextOffsetX=0, enemyCastTextOffsetY=0,
        enemyCastIconOffsetX=0, enemyCastIconOffsetY=0, enemyCastTimeOffsetX=0, enemyCastTimeOffsetY=0,
        targetScaleEnabled=True, targetScalePercent=110,
        enemyTargetMarker=True, enemyTargetColor=BRASS,
        targetClassResource=True, targetClassResourceWidth=88, targetClassResourceHeight=5,
        targetClassResourceY=-38, targetUnitFrameResource=True, targetUnitFrameResourceWidth=114,
        targetUnitFrameResourceHeight=5, targetUnitFrameResourceY=-8)
    put(entries[b"damageMeter"], enabled=False, barColor=BRASS, borderColor="30291d", bgColor=INK, leftColor=PAPER)
    # Anchor Essential to the top action row. The gap clears the optional
    # stance and pet rows when they have populated buttons.
    put(entries[b"cooldownManager"], enabled=True, captured=True, defaultsVersion=3,
        blizzard=1, essOnViewer=False, specPositions=False, positionsData="",
        assistIcon=False, raidEssentials=False, showGCD=False, muteSounds=True,
        ess_on=True, ess_anchor=16, ess_anchorFrame="MSUFSuiteBar3", ess_side=2, ess_gap=60, ess_align=2,
        ess_x=0, ess_y=0, ess_vis=2, ess_size=24, ess_height=100, ess_spacing=3, ess_perRow=6, ess_maxIcons=6,
        ess_fadeTime=0, ess_hiddenAlpha=0, ess_hoverShow=False, ess_procGlow=False, ess_readyGlow=False,
        ess_iconSkin="CUSTOM", ess_borderColor=BRASS, ess_swipeAlpha=0,
        uti_on=False, buf_on=False, bar_on=False, def_on=False, ext_on=False,
        c1_on=False, c2_on=False, c3_on=False, c4_on=False, c5_on=False, c6_on=False)
    put(entries.setdefault(b"nativeCooldownVisibility", {}), enabled=True)
    put(entries[b"xpBar"], enabled=True, point=8, x=0, y=XP_Y, width=MAIN_BAR_WIDTH, height=XP_HEIGHT, scale=100,
        look=4, displayStyle=2, track=1, borderSize=1, hideBlizzard=True, hideBlizzardTracking=True,
        separateTextColor=True, customText=PAPER, customPanel=INK, customBorder=FRAME_EDGE,
        customFill="477b8a", customRested="59607b", showSegments=False, showSession=False,
        showRate=False, showETA=False, showLevelTime=False, showRested=True, hideAtMax=True,
        levelTextVisibility=3, percentTextVisibility=3, xpTextVisibility=2, xpTextAnchor=6,
        xpTextSize=10, xpTextFont=FONT, xpTextFormat=2, xpTextNumbers=3)
    put(entries[b"chat"], enabled=True, look=4, minimalChrome=True,
        lockWindowSize=True, lockWindowPosition=True, windowWidth=CHAT_COLUMN_WIDTH - 2 * CHAT_PADDING, windowHeight=112,
        windowX=HUD_LEFT + CHAT_PADDING, windowY=72, padding=CHAT_PADDING,
        font=FONT, fontSize=12, panelAlpha=18, panelColor=INK, panelGradient=True,
        borderSize=1, borderColor=FRAME_EDGE, borderAlpha=65,
        headerToolbar=False, headerClock=False, sidebarPanel=False, hideNativeButtons=True, tabPanel=False, tabAccent=False,
        hideTabArt=True, idleSeconds=0, idleFadeDuration=0, messageFading=False,
        inputTop=True, inputX=0, inputY=CHAT_TAB_CLEARANCE, inputWidth=0, inputHeight=0,
        inputPanel=True, inputColor=INK, inputAlpha=92, animateInput=False)
    put(entries[b"tooltipVisibility"], enabled=True, itemHeaderIcon=True)
    put(entries.setdefault(b"characterPanel", {}), showReputationBars=True)
    put(entries[b"announcements"], enabled=True, animateBanner=False, eventToasts=True,
        quests=True, level=True, zone=True, achievements=True, scenario=True,
        levelClean=False, levelHealth=True, levelPower=True, levelTalents=True, levelAttributes=False,
        duration=4, scale=75, anchor=1, x=0, y=-188, font=FONT, titleSize=27, subtitleSize=15,
        showBoxArt=True, artStyle=3, artOpacity=70, showFrame=True, frameStyle=3,
        frameColorSource=3, frameColor=BRASS, frameOpacity=70,
        colorStyle=2, backgroundColor=INK, backgroundOpacity=82, subtitleColor=PAPER,
        questColor="f1ca80", levelColor="f0dcad", zoneColor=PAPER, achievementColor="dfbc82",
        noticeColor="ccdfda", scenarioColor="c4d9bd")
    for module in (b"floatingCombatText", b"selfCombatText", b"afkScreen", b"buffReminders"):
        put(entries.setdefault(module, {}), enabled=False)
    return encode(envelope, "MSUFM1:MSUF3:")


def skin():
    envelope = decode(literal(CORE / "ModernDarkFactory.lua", "Suite.ModernDarkSkinCompact"), "MSKIN1:")
    db = envelope[b"payload"]
    put(db[b"theme"], look="custom", preset="midnightDark", gradient=False,
        materialDepth=0, borderOpacity=.88)
    colors = db[b"theme"][b"colors"]
    colors[b"accent"] = [.64, .53, .33, 1]
    colors[b"title"] = [.94, .89, .79, 1]
    colors[b"popup"] = [.065, .092, .116, .96]
    colors[b"microBarFill"] = [.087, .078, .061, .87]
    colors[b"microBarFillAlt"] = [.051, .048, .04, .90]
    colors[b"microBarBorder"] = [.49, .40, .26, .94]
    put(db[b"icons"][b"microMenu"], positionPreset="custom", layoutMode="owned",
        layoutPoint="BOTTOMLEFT", layoutRelativePoint="BOTTOMLEFT", layoutX=HUD_LEFT, layoutY=HUD_BOTTOM,
        layoutWidth=CHAT_COLUMN_WIDTH,
        orientation="horizontal", buttonsPerLine=16, buttonSize=22, iconSize=17,
        padding=3, spacing=1, barBackground=True, barBorder=1, barMaterial="theme",
        tint="native", visibility="always")
    for role in (b"accentAlt", b"accentBright", b"checkmark", b"microIconPressed", b"microIconHover"):
        colors[role] = [.83, .67, .43, 1]
    return encode(envelope, "MSKIN1:")


def tga_header(width, height):
    return struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)


def plaque():
    """A small beveled plate drawn at 2x for the Core texture layer."""
    width, height = 256, 32
    pixels = bytearray()
    for y in range(height):
        cut = max(0, 8 - min(y, height - 1 - y))
        for x in range(width):
            edge = min(x - cut, width - 1 - cut - x, y, height - 1 - y)
            if edge < 0:
                rgba = (0, 0, 0, 0)
            elif edge < 2:
                rgba = (18, 15, 11, 255)
            elif edge < 4:
                rgba = (119, 99, 64, 255) if y < height / 2 else (61, 48, 32, 255)
            else:
                shade = 34 - y // 3
                rgba = (shade, shade + 1, shade + 3, 250)
                if abs(y - 15) + min(abs(x - 13), abs(x - 242)) <= 3:
                    rgba = (147, 119, 73, 255)
            red, green, blue, alpha = rgba
            pixels.extend((blue, green, red, alpha))
    return tga_header(width, height) + pixels


def endcap():
    """Beveled brass with an inset diamond, mirrored for the right end."""
    size = 64
    pixels = bytearray()
    for y in range(size):
        outer = abs(y - 32)
        for x in range(size):
            left, right = 6 + outer, 61 - outer // 4
            edge = min(x - left, right - x, 25 - outer)
            diamond = abs(x - 36) + outer
            if edge < 0:
                color = (0, 0, 0, 0)
            elif edge <= 2:
                color = (14, 13, 11, 255)
            elif edge <= 5:
                color = (165, 128, 77, 255) if y < 32 else (91, 64, 39, 255)
            elif 10 <= diamond <= 14:
                color = (148, 113, 66, 255)
            else:
                shade = max(22, 48 - y // 2)
                color = (shade + 7, shade + 3, shade, 255)
            red, green, blue, alpha = color
            pixels.extend((blue, green, red, alpha))
    return tga_header(size, size) + pixels


def minimap_frame():
    size = 256
    pixels = bytearray()
    for y in range(size):
        vertical_edge = min(y, size - 1 - y)
        shade = round(max(0, 178 * (1 - y / 65), 158 * (1 - (size - 1 - y) / 39)))
        for x in range(size):
            horizontal_edge = min(x, size - 1 - x)
            edge = min(horizontal_edge, vertical_edge)
            if edge == 0:
                color = (19, 16, 12, 255)
            elif edge == 1:
                color = (124, 100, 64, 255) if x < 2 or y < 2 else (79, 60, 38, 255)
            elif edge == 2:
                corner = max(horizontal_edge, vertical_edge) <= 15
                color = (168, 135, 82, 255) if corner else (54, 43, 30, 255)
            elif edge == 3:
                color = (24, 20, 16, 230)
            else:
                color = (15, 14, 12, shade)
            red, green, blue, alpha = color
            pixels.extend((blue, green, red, alpha))
    return tga_header(size, size) + pixels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source = "local _, Suite = ...\n-- Built by tools/build_wayfarer_factory.py.\n"
    for name, value in (("Frames", frames()), ("Module", modules()), ("Skin", skin())):
        source += assignment("Suite.Wayfarer" + name + "Compact", value)
    write(CORE / "WayfarerFactory.lua", source, args.check)
    for name, art in ((PLAQUE_NAME, plaque()), (ENDCAP_NAME, endcap()), (MAP_FRAME_NAME, minimap_frame())):
        asset = CORE.parent / "Media" / name
        if args.check:
            if not asset.is_file() or asset.read_bytes() != art:
                raise SystemExit(f"{asset} is out of date")
        else:
            asset.write_bytes(art)
    print("Wayfarer profiles and media " + ("match" if args.check else "written"))


if __name__ == "__main__":
    main()
