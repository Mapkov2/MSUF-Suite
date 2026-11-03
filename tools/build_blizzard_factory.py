"""Build the Blizzard-inspired installer preset from the shipped factories."""
import argparse
import re
from pathlib import Path

from build_forever_factory_preview import decode, encode
from build_modern_dark_factory import CORE, assignment, literal, put, write

CHASSIS = "Interface\\AddOns\\MSUF_Suite\\Media\\BlizzardFrames\\UnitFrame.tga"
HEALTH_FILL = "Interface\\AddOns\\MSUF_Suite\\Media\\BlizzardFrames\\HealthFill.tga"


def frame_chassis(config, right=False, boss=False):
    """The existing runtime and preview paint these same texture-layer settings."""
    put(config, directTextLayout=True,
        directNamePoint="CENTER", directNameRelativePoint="TOP", directNameOffsetX=0, directNameOffsetY=7,
        directNameWidth=120, directHealthCenterPoint="CENTER", directHealthCenterRelativePoint="BOTTOM",
        directHealthCenterOffsetX=0, directHealthCenterOffsetY=8,
        nameFontSize=11, hpFontSize=10, hpTextCenterFontSize=10, hpTextSeparator=" | ",
        textCenter="PERCENTCUR" if right else "CURPERCENT", hpTextReverse=False, hpFullValueShort=True,
        texLayerEnabled=True, texLayerSourceMode="CUSTOM",
        texLayerCustomTexturePath=CHASSIS.replace("UnitFrame", "BossFrame") if boss else CHASSIS,
        texLayerTexture="", texLayerAnchorTarget="FRAME", texLayerAnchor="CENTER",
        texLayerSizeMode="MANUAL", texLayerResponsiveSize=False, texLayerEdgeAttach="FREE",
        texLayerWidth=128, texLayerHeight=64, texLayerOffsetX=0, texLayerOffsetY=7,
        texLayerColorMode="CUSTOM", texLayerColorTreatment="ORIGINAL",
        texLayerColorR=1, texLayerColorG=1, texLayerColorB=1, texLayerAlpha=1,
        texLayerBlendMode="BLEND", texLayerCropMode="FULL", texLayerLevel=3,
        texLayerFollowFrameAlpha=True, texLayerVisibility="ALWAYS", texLayerTargetOnly=False,
        texLayerHealthCondition="ANY", texLayerHealthLowAlphaEnabled=False,
        texLayerGradientEnabled=False, texLayerRoundedClip=False, texLayerMirrorH=False,
        texLayerMirrorV=False, texLayerEdgeSoftness=0, texLayer2Enabled=False, texLayer3Enabled=False)


def frames():
    envelope = decode(literal(CORE / "ModernDarkFactory.lua", "Suite.ModernDarkFramesCompact"), "MSUF3:")
    put(envelope, profile="MSUF Blizzard")
    db = envelope[b"payload"]
    put(db[b"general"], barMode="class", useClassColors=True, darkMode=False,
        enableHealthGradient=False, enableGradient=False, barTexture=HEALTH_FILL,
        castbarTexture=CHASSIS.replace("UnitFrame", "CastFill"), castbarBackgroundTexture="Solid",
        anchorToCooldown=False, anchorName="UIParent", fontKey="FRIZQT", powerColorMode="power",
        noOutline=True, boldText=False, fontSlug=False, fontMonochrome=False,
        textBackdrop=True, fontShadowOpacity=1, fontShadowDistance=1,
        nameColorMode="CUSTOM", nameColorR=1, nameColorG=1, nameColorB=1,
        nameClassColor=False, npcNameRed=False, nameNpcClassColor=False,
        barOutlineColorR=.5, barOutlineColorG=.48, barOutlineColorB=.4, barOutlineColorA=1,
        fontSize=12, nameFontSize=12, hpFontSize=11, powerFontSize=10,
        playerCastbarOverrideEnabled=False, playerCastbarOverrideMode="CLASS",
        castbarInterruptibleColor="yellow", castbarNonInterruptibleR=.6, castbarNonInterruptibleG=.6,
        castbarNonInterruptibleB=.6, npcClassColorBar=True, castbarTargetDetached=False,
        castbarTargetMatchWidth=False, castbarTargetBarWidth=184, castbarTargetBarHeight=14,
        castbarTargetOffsetX=0, castbarTargetOffsetY=-67,
        castbarTargetIconPosition="LEFT", castbarTargetIconSize=14,
        castbarTargetIconSpacing=2, castbarTargetIconOffsetY=0,
        castbarTargetShowIcon=False, castbarTargetSpellNamePosition="BELOW", castbarTargetTextOffsetY=0,
        castbarTargetSpellNameAlign="CENTER",
        castbarTargetSpellNameTruncate="CLIP", castbarTargetSpellNameMaxWidth=184,
        castbarTargetSpellNameFontSize=11, castbarTargetTimeFontSize=10,
        castbarTargetTimeFormat="CURRENT", castbarPlayerBarWidth=184, castbarPlayerBarHeight=14,
        castbarPlayerMatchWidth=False, castbarPlayerDetached=False,
        castbarPlayerOffsetX=-30, castbarPlayerOffsetY=-67, castbarPlayerShowIcon=False,
        castbarPlayerSpellNamePosition="BELOW", castbarPlayerTextOffsetY=0,
        castbarPlayerSpellNameAlign="CENTER",
        castbarPlayerSpellNameTruncate="CLIP", castbarPlayerSpellNameMaxWidth=184,
        castbarPlayerSpellNameFontSize=11, castbarPlayerTimeFontSize=10)
    put(db[b"bars"], showClassPower=True, classPowerAnchorToCooldown=True,
        classPowerCooldownTopAnchor=True, classPowerWidthMode="cooldown", classPowerWidth=334,
        detachedPowerBarWidthMode="cooldown",
        classPowerHeight=6, classPowerOffsetX=0, classPowerOffsetY=0,
        powerBarHeight=4, powerBarTexture="RaidPower", barOutlineThickness=0, barBackgroundAlpha=80)
    db[b"general"][b"classPowerColorOverrides"] = {}
    db[b"general"].pop(b"fontShadowStrength", None)
    for key in (b"player", b"target", b"focus", b"boss", b"arena", b"pet", b"targettarget"):
        config = db.get(key)
        if not isinstance(config, dict):
            continue
        for field in list(config):
            if field.startswith(b"direct") or field in (b"anchorToUnitframe", b"_screenRefH",
                                                        b"screenPositionMode", b"screenPositionHeight"):
                config.pop(field)
        put(config, anchorFrameName="UIParent", healthColorMode="CLASS", barTexture=HEALTH_FILL,
            showName=True, showHP=True,
            powerBarTexture="RaidPower", barBackgroundTexture="Flat",
            fontKey="FRIZQT", fontOverride=False, nameFontSize=12, hpFontSize=11,
            hpTextLeftFontSize=11, hpTextCenterFontSize=11, hpTextRightFontSize=11,
            powerFontSize=10, portraitMode="OFF", showLevelIndicator=False,
            textLeft="NONE", textCenter="CURPERCENT", textRight="NONE",
            nameTextAnchor="TOP", nameOffsetX=0, nameOffsetY=13,
            hpOffsetX=0, hpOffsetY=0, powerBarDetached=False,
            detachedPowerBarAnchorToClassPower=False, detachedPowerBarSyncClassPower=False)
    # The reference's 184-pixel silhouette INCLUDES its 60-pixel portrait.
    # Keep this center cluster in UI units; scaling x by screen height spreads
    # the two frames apart on 16:9 screens while the bars keep their width.
    for key, x, mode in ((b"player", -350, "LEFT"), (b"target", 350, "RIGHT")):
        put(db[key], width=124, height=32, point="CENTER", relativePoint="CENTER",
            offsetX=x, offsetY=-190, portraitMode=mode, portraitRender="2D",
            portraitShape="BLIZZARD", portraitPlacement="DETACHED", portraitSizeMode="UNIFORM",
            portraitDetachedPoint="LEFT" if key == b"target" else "RIGHT",
            portraitDetachedTo="RIGHT" if key == b"target" else "LEFT",
            portraitSizeOverride=60, portraitWidth=60, portraitHeight=60,
            portraitOffsetX=0, portraitOffsetY=7, portraitAlpha=100,
            portraitFlip=key == b"target", portraitBlizzardDirection="BOTTOMLEFT" if key == b"target" else "BOTTOMRIGHT",
            portraitBorderStyle="CUSTOM", portraitBorderThickness=2,
            portraitBorderColorR=.82, portraitBorderColorG=.67, portraitBorderColorB=.30,
            portraitBorderColorA=1, portraitBlizzardElite=key == b"target",
            showPowerBar=False, powerBarHeight=4, showPowerText=False, hpBarAlpha=1, hpBgAlpha=.8)
        frame_chassis(db[key], key == b"target")
    put(db[b"player"], showPowerBar=True, powerBarDetached=True,
        detachedPowerBarAnchorToClassPower=False, detachedPowerBarSyncClassPower=False,
        detachedPowerBarHeight=6, detachedPowerBarWidth=334,
        detachedPowerBarOffsetX=350, detachedPowerBarOffsetY=34,
        detachedPowerBarTextOnBar=False)
    # A single center row under Essential, just like the reference combat view.
    for group in (b"gf_party", b"gf_raid", b"gf_mythicraid"):
        config = db[group]
        put(config, nameBarEnabled=True, nameBarHeight=12, nameBarR=.035, nameBarG=.035,
            nameBarB=.03, nameBarAlpha=.94, barTextureOverride=True,
            barTexture="RaidHP", barBackgroundTexture="Flat", fontKey="FRIZQT",
            width=104, height=58, spacing=4, powerHeight=0, powerBarEnabled=False, portraitMode="OFF",
            nameColorMode="CUSTOM", nameColorR=1, nameColorG=1, nameColorB=1,
            nameClassColor=False, nameFontSize=10, showHPText=False,
            roleIconStyle="BLIZZARD", roleIconShowTank=True, roleIconShowHealer=True, roleIconShowDPS=True,
            roleIcon=True, roleIconSize=10, roleIconAnchor="TOPLEFT", roleIconX=3, roleIconY=-1, roleIconLayer=6,
            gfBarMode="class", healthColorMode="CLASS",
            textLeft="NONE", textCenter="NONE", textRight="NONE",
            borderEnabled=True, borderSize=1, borderR=.43, borderG=.42, borderB=.37, borderA=1)
    party = db[b"gf_party"]
    party.pop(b"screenPositionMode", None)
    party.pop(b"screenPositionHeight", None)
    put(party, width=104, height=58, point="CENTER", offsetX=0, offsetY=-240,
        growth="RIGHT", spacing=4, unitsPerColumn=5, maxColumns=1, showPlayer=True,
        gfBarMode="class", healthColorMode="CLASS", nameColorMode="CUSTOM",
        nameFontSize=10, hpFontSize=10, nameAnchor="TOP", nameOffsetX=0, nameOffsetY=-1,
        powerHeight=0, powerBarEnabled=False, portraitMode="OFF", auraIconSize=20, auraMaxIcons=4,
        roleIcon=True, roleIconSize=10, roleIconAnchor="TOPLEFT", roleIconX=3, roleIconY=-1, roleIconLayer=6)
    for group in (b"gf_party", b"gf_raid", b"gf_mythicraid"):
        config = db[group]
        put(config, positionMode="GRID_BOUNDS_V2")
        for key in (b"positionMigrationCount", b"positionMigrationDX", b"positionMigrationDY"):
            config.pop(key, None)
        if group != b"gf_party":
            put(config, point="TOPLEFT", relativePoint="TOPLEFT", offsetX=32, offsetY=-280,
                growth="DOWN", unitsPerColumn=5, maxColumns=8 if group == b"gf_raid" else 4)
        auras = config.setdefault(b"auras", {})
        put(auras.setdefault(b"buff", {}), enabled=True, filterToken="PLAYER", anchor="TOPLEFT", x=43, y=-16,
            size=18, max=3, perRow=3, spacing=2, growth="RIGHTDOWN")
        put(auras.setdefault(b"debuff", {}), enabled=True, anchor="BOTTOMLEFT", x=2, y=2,
            size=18, max=2, perRow=2, spacing=2, growth="RIGHTUP")
        put(auras.setdefault(b"externals", {}), enabled=True, anchor="BOTTOMRIGHT", x=-2, y=2,
            size=18, max=2, perRow=2, spacing=2, growth="LEFTUP")
    for key in (b"focus", b"boss"):
        put(db[key], width=124, height=32, portraitMode="RIGHT", portraitRender="2D",
            portraitShape="BLIZZARD", portraitPlacement="DETACHED", portraitSizeMode="UNIFORM",
            portraitDetachedPoint="LEFT", portraitDetachedTo="RIGHT",
            portraitSizeOverride=60, portraitWidth=60, portraitHeight=60, portraitOffsetY=7,
            portraitAlpha=100, portraitFlip=True, portraitBlizzardDirection="BOTTOMLEFT",
            portraitBlizzardElite=True, portraitDragonArtwork=key == b"boss", showPowerBar=True,
            powerBarHeight=8, showPowerText=False, hpBarAlpha=1, hpBgAlpha=.8)
        frame_chassis(db[key], True, key == b"boss")
        put(db[key], directHealthCenterOffsetY=20)
    put(db[b"focus"], offsetX=490, offsetY=160)
    put(db[b"boss"], height=28, point="CENTER", relativePoint="RIGHT", offsetX=-712, offsetY=220,
        bossLayoutMode="VERTICAL_DOWN", spacing=-112, portraitOffsetX=-12, portraitOffsetY=6, texLayerOffsetY=6,
        directNamePoint="LEFT", directNameRelativePoint="TOPLEFT", directNameOffsetX=4,
        directNameOffsetY=6, directNameWidth=84, textCenter="NONE", textRight="PERCENT",
        hpTextReverse=False,
        directHealthRightPoint="RIGHT", directHealthRightRelativePoint="RIGHT",
        directHealthRightOffsetX=-20, directHealthRightOffsetY=4, hpTextRightFontSize=10,
        showLevelIndicator=True, levelIndicatorSize=10, levelIndicatorAnchor="RIGHT",
        levelIndicatorOffsetX=-20, levelIndicatorOffsetY=20, levelIndicatorDifficultyColor=True)
    put(db[b"general"], bossCastbarWidth=208, bossCastbarHeight=16,
        bossCastbarDetached=False, bossCastbarMatchWidth=False, bossCastbarOffsetX=-44, bossCastbarOffsetY=-13,
        _msufBossCastbarPhysicalEdgeAnchor_v1=True,
        showBossCastIcon=False, showBossCastName=True, showBossCastTime=True,
        bossCastSpellNamePosition="BELOW", bossCastTextOffsetY=0,
        bossCastSpellNameTruncate="CLIP", bossCastSpellNameMaxWidth=208,
        bossCastSpellNameFontSize=11, bossCastTimeFontSize=10)
    for key, x in ((b"pet", -350), (b"targettarget", 350)):
        put(db[key], enabled=False, width=100, height=16, point="CENTER", relativePoint="CENTER", offsetX=x, offsetY=-280)
    for owner in db[b"auras3"][b"perUnit"].values():
        put(owner[b"layout"], buffGroupIconSize=24, debuffGroupIconSize=24,
            buffIconHeightPercent=100, debuffIconHeightPercent=100, buffSpacing=2, debuffSpacing=2,
            buffGroupOffsetY=48, debuffGroupOffsetY=76, buffCooldownTextSize=11, debuffCooldownTextSize=11)
    # The native top-right aura frames remain visible. Duplicating Player's
    # buffs above this compact frame covers its dark name header.
    put(db[b"auras3"], showPlayer=False)
    return encode(envelope, "MSUF3:")


def modules():
    envelope = decode(literal(CORE / "RetailProfile.lua", "Suite.RetailProfileModuleCompact"), "MSUFM1:MSUF3:")
    suite = envelope[b"profile"][b"suite"]
    migrations = (CORE / "Suite.lua").read_text(encoding="utf-8").split("local MIGRATIONS = {", 1)[1].split("\n}", 1)[0]
    put(suite, revision=len(re.findall(r"\{ run =", migrations)))
    entries = suite[b"modules"]
    put(entries[b"actionbars"], look=4, borderArt=2, iconSkin="CUSTOM", buttonShape=1,
        bar1Visibility=1, bar1Point=8, bar1X=0, bar1Y=6, bar1Size=38,
        bar1Rows=1, bar1Buttons=12, bar1Spacing=2, bar1Keybind=True, bar1ShowEmpty=True,
        bar1LeftEndcap=4, bar1RightEndcap=4, bar1LeftEndcapSize=70, bar1RightEndcapSize=70,
        bar1LeftEndcapY=10, bar1RightEndcapY=10)
    for i in range(2, 13):
        put(entries[b"actionbars"], **{f"bar{i}Visibility": 6})
    put(entries[b"cooldownManager"], enabled=True, captured=True, defaultsVersion=3,
        listsData="", spellsData="", positionsData="", specPositions=False, essOnViewer=False,
        ess_x=0, ess_y=-130, ess_size=40, ess_spacing=2, ess_perRow=8,
        ess_anchor=1, ess_align=1, ess_laterSize=0, ess_laterPerRow=0, ess_height=100,
        uti_on=False, def_on=False, ext_on=False, bar_on=False,
        buf_on=True, buf_anchor=2, buf_side=2, buf_align=1, buf_x=0, buf_y=0,
        buf_size=24, buf_height=100, buf_gap=24, buf_spacing=2, buf_perRow=8, buf_maxIcons=8)
    for i in range(1, 7):
        put(entries[b"cooldownManager"], **{f"c{i}_on": False})
    put(entries[b"minimap"], enabled=True, captured=True, stylePreset=1, shape=2, size=210,
        queueStatusEnabled=True, queueStatusSize=32, queueStatusX=-2, queueStatusY=-52,
        point=3, x=-38, y=-44, borderSize=0, borderColor="c5ad6a", iconSkin="CUSTOM",
        styleTexture=8, styleColor="ffffff", styleAlpha=100, styleScale=100,
        styleGlow=False, styleBackdrop=False, outerBorderSize=0, shadowSize=0,
        specButton=False,
        infoFPS=False, infoLatency=False, infoClock=False, infoLocationAnchor=10,
        infoLocationY=28, infoLocationX=0, infoLocationWidth=190,
        infoLocationFont="Fonts\\FRIZQT__.TTF", infoLocationSize=12,
        infoLocationColor="ffffff", infoLocationZoneColor=False, infoLocationClassColor=False)
    put(entries[b"chat"], enabled=True, look=4, windowX=32, windowY=54,
        windowWidth=496, windowHeight=148, lockWindowPosition=True, lockWindowSize=True,
        fontSize=16, font="Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf",
        tabFont="Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Bold.ttf", tabFontSize=16,
        padding=4, tabPanel=True, sidebarPanel=False,
        hideNativeButtons=True, completeMessages=True,
        tabClassColor=False, tabActiveColor="ffd54a", tabInactiveColor="b5b5ad", accentColor="b69a36",
        borderColor="807865", panelColor="151310", panelAlpha=35,
        headerClock=True, headerClock24Hour=False, headerClockLocalTime=False,
        allTimestamps=False, hideNativeTimestamps=True, copyMessages=False, fontRendering=1, fontOutline=4, fontShadow=2,
        fontShadowOpacity=100, fontShadowDistance=1, tabHeight=24, tabPadding=12, tabGap=4,
        borderSize=1, borderAlpha=85, accentAlpha=65, tabAccent=True, hideTabArt=True,
        tabIndividualPanels=False, panelGradient=False, idleSeconds=0, messageFading=False)
    put(entries[b"damageMeter"], enabled=True, windowCount=2, classColors=True, look=4,
        w1X=-32, w1Y=54, w1Width=340, w1Height=172,
        w2X=-32, w2Y=244, w2Width=340, w2Height=112,
        barTexture=HEALTH_FILL, borderColor="807865", titleColor="ffd54a",
        bgColor="151310", bgAlpha=55, headerColor="242017", headerAlpha=55,
        barHeight=21, barSpacing=3, headerHeight=22, font="Fonts\\FRIZQT__.TTF",
        leftSize=11, rightSize=10, titleSize=13, leftColor="ffffff", rightColor="ffffff",
        w1Type=1, w2Type=1, w1Session=2, w2Session=2, autoCurrent=False,
        w1AutoCurrent=3, w2AutoCurrent=3,
        w1RoleTank=1, w1RoleHealer=1, w1RoleDamager=1,
        w2RoleTank=1, w2RoleHealer=1, w2RoleDamager=1)
    data = entries[b"dataTexts"]
    put(data, enabled=True, bar1Enabled=True, bar1Point=7, bar1X=32, bar1Y=6,
        bar1Width=496, bar1Height=28, bar1Visibility=1, bar1Dock=1, bar1FullScreen=False,
        bar1BackgroundEnabled=True, bar1BackgroundColor="151310", bar1BackgroundOpacity=50,
        bar1ValueColor="ffffff", bar1AccentColor="ffd54a", bar1AccentEnabled=False,
        bar1BorderEnabled=False, bar1StyleOverride=True, bar1CustomColors=True, bar1FontSize=12,
        bar1ShowLabels=False, bar1Layout=2, bar1Slot1=34, bar1Slot2=7, bar1Slot3=6,
        bar1Slot4=9, bar1Slot5=4, bar1Slot6=1,
        bar1SourceIcons=True, bar1FpsAccent=True,
        bar1Font="Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf",
        bar1FontRendering=1, bar1TextOutline=3, bar1FontShadow=True)
    for i in range(2, 13):
        put(data, **{f"bar{i}Enabled": False})
    put(entries.setdefault(b"targetDistance", {}), enabled=False)
    put(entries.setdefault(b"castbarArt", {}), enabled=True)
    put(entries.setdefault(b"playerAuras", {}), enabled=True, iconWidth=28, iconHeight=28,
        perRow=12, spacing=4, rowSpacing=8, x=-10, y=0, debuffOffset=88,
        showDuration=True, borderSize=1, borderColor="000000", font="Fonts\\FRIZQT__.TTF",
        fontSize=10, buffSkin="CUSTOM", debuffSkin="CUSTOM")
    # The references use Blizzard's gold tracker headers. Keep the native
    # tracker, including its Edit Mode position and quest interactions.
    put(entries[b"objectives"], enabled=False, x=-26, y=-285, width=270, height=510,
        colorStyle=2, font="Fonts\\FRIZQT__.TTF", groupUnderlines=True, questIconStyle=3,
        titleColor="ffd54a", titleSize=14, dividerColor="b69a36", textColor="e5c13c",
        campaignColor="ffd54a", questsColor="ffd54a", mutedColor="c3c1b5",
        sectionSize=14, entrySize=13, objectiveSize=12, backgroundOpacity=0)
    put(entries[b"buffReminders"], enabled=False)
    put(entries[b"xpBar"], enabled=False)
    plates = entries[b"nameplates"]
    for key in plates:
        if b"Offset" in key:
            plates[key] = 0
    # Style the native plates. Health-focus keeps the name above the bar;
    # percent-only text is moved into its right edge, as in the references.
    put(plates, enabled=True, look=3, nativeStyle=5, nativeSize=3, barGeometry=2,
        enemyTextMode=2, enemyMirrorHeader=False, enemyRoleColors=False,
        enemyQuestColors=False, enemyColorsInDungeons=False, enemyColorsOutside=False,
        auraColorsEnabled=False, enemyLevelEnabled=False, enemyRarityIcon=3,
        enemyTargetMarker=True, enemyTargetStyle=10, enemyTargetLayout=2,
        enemyTargetMarkerSize=22, enemyTargetColor="fff14a", enemyTargetHideFriendly=True,
        enemyTargetOffsetX=2, enemyTargetOffsetY=0, enemyEliteMarker=False, enemyQuestMarker=False,
        enemyNameFont="Fonts\\ARIALN.TTF", enemyCastFont="Fonts\\ARIALN.TTF",
        enemyNameSize=14, enemyHealthTextSize=12, enemyCastSize=13,
        enemyHealthTextOffsetY=-12, enemyCastTextOffsetY=-12,
        enemyCastTimeOffsetY=-12, enemyCastHeight=12,
        enemyCastEnabled=2, enemyCastSpellName=True, enemyCastSpellIcon=False,
        enemyCastSpellTarget=False, enemyCastImportant=False, enemyCastTargetHighlight=False,
        enemyBorderColor="807865", enemyBorderSize=1, enemyBorderEnabled=True,
        targetScaleEnabled=True, targetScalePercent=130, selectionBorder=3,
        friendlyNamesOnly=2, personalResource=3, auraScaleMode=2, auraScalePercent=70,
        enemyNpcAuraMode=2, enemyNpcBuffs=False, enemyNpcDebuffs=False, enemyNpcControl=False,
        enemyPlayerAuraMode=2, enemyPlayerBuffs=False, enemyPlayerDebuffs=False, enemyPlayerControl=False)
    return encode(envelope, "MSUFM1:MSUF3:")


def skin():
    envelope = decode(literal(CORE / "ModernDarkFactory.lua", "Suite.ModernDarkSkinCompact"), "MSKIN1:")
    db = envelope[b"payload"]
    put(db, enabled=True)
    put(db[b"icons"][b"microMenu"], preset="custom", layoutMode="owned", tint="native",
        iconStyle="blizzard", orientation="horizontal", buttonsPerLine=14, scale=1,
        layoutPoint="BOTTOMRIGHT", layoutRelativePoint="BOTTOMRIGHT", layoutX=-32, layoutY=4,
        positionPreset="custom", visibility="always", buttonSize=24, iconSize=20,
        spacing=1, padding=0, barBackground=False, barBorder=0, barMaterial="theme",
        hoverStyle="off", shape="global", buttonBackground=False, buttonBorder=0)
    for key in (b"positions", b"scales"):
        db[b"windowControls"][key] = {}
    put(db[b"typography"], enabled=True, followMSUF=False, applyChat=False,
        sharedMediaFont="MapkoSkin - Expressway")
    put(db[b"geometry"], family="continuous", radius=8, border=1, controlShape="continuous")
    put(db[b"theme"], look="custom", preset="midnightDark", gradient=False, materialDepth=0,
        borderOpacity=.85, shellOpacity=.96, panelOpacity=.9)
    for role in (b"accent", b"accentAlt", b"title", b"checkmark", b"microIconPressed"):
        db[b"theme"][b"colors"][role] = [.84, .7, .36, 1]
    for role in (b"accentBright", b"microIconHover"):
        db[b"theme"][b"colors"][role] = [.96, .84, .56, 1]
    # Window adapters share the modern dark shell; the native quest tracker
    # and the Suite chat module keep their authored layout and typography.
    for key in db[b"skins"]:
        db[b"skins"][key] = key not in (b"objectiveTracker", b"objectiveTrackerAccents", b"chatFrames")
    return encode(envelope, "MSKIN1:")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source = "local _, Suite = ...\n-- Optional Blizzard-inspired installer design; applied only on Install.\n"
    for name, value in (("Frames", frames()), ("Module", modules()), ("Skin", skin())):
        source += assignment("Suite.Blizzard" + name + "Compact", value)
    write(CORE / "BlizzardFactory.lua", source, args.check)
    print("Blizzard frame, module and Skin factories " + ("match" if args.check else "written"))


if __name__ == "__main__":
    main()
