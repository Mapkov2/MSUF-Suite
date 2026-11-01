"""Build the Blizzard-inspired installer preset from the shipped factories."""
import argparse
from pathlib import Path

from build_forever_factory_preview import decode, encode
from build_modern_dark_factory import CORE, assignment, literal, put, write


def frames():
    envelope = decode(literal(CORE / "ModernDarkFactory.lua", "Suite.ModernDarkFramesCompact"), "MSUF3:")
    put(envelope, profile="MSUF Blizzard")
    db = envelope[b"payload"]
    put(db[b"general"], barMode="class", useClassColors=True, darkMode=False,
        enableHealthGradient=False, enableGradient=False, barTexture="Blizzard",
        castbarTexture="Blizzard", castbarBackgroundTexture="Solid",
        anchorToCooldown=False, anchorName="UIParent", fontKey="FRIZQT", powerColorMode="power",
        fontSize=12, nameFontSize=12, hpFontSize=11, powerFontSize=10,
        playerCastbarOverrideEnabled=False, playerCastbarOverrideMode="CLASS",
        castbarInterruptibleColor="yellow", castbarTargetDetached=False,
        castbarTargetMatchWidth=True, castbarTargetBarWidth=180, castbarTargetBarHeight=14,
        castbarTargetOffsetX=0, castbarTargetOffsetY=-26,
        castbarTargetIconPosition="LEFT", castbarTargetIconSize=14,
        castbarTargetIconSpacing=2, castbarTargetIconOffsetY=0,
        castbarTargetTimeFormat="CURRENT", castbarPlayerBarWidth=340, castbarPlayerBarHeight=16)
    put(db[b"bars"], showClassPower=True, classPowerAnchorToCooldown=True,
        classPowerCooldownTopAnchor=True, classPowerWidthMode="custom", classPowerWidth=334,
        classPowerHeight=6, classPowerOffsetX=0, classPowerOffsetY=0,
        powerBarHeight=4, barOutlineThickness=1, barBackgroundAlpha=80)
    db[b"general"][b"classPowerColorOverrides"] = {}
    for key in (b"player", b"target", b"focus", b"boss", b"arena", b"pet", b"targettarget"):
        config = db.get(key)
        if not isinstance(config, dict):
            continue
        for field in list(config):
            if field.startswith(b"direct") or field in (b"anchorToUnitframe", b"_screenRefH"):
                config.pop(field)
        put(config, anchorFrameName="UIParent", healthColorMode="CLASS", barTexture="Blizzard",
            fontKey="FRIZQT", fontOverride=False, nameFontSize=12, hpFontSize=11,
            hpTextLeftFontSize=11, hpTextCenterFontSize=11, hpTextRightFontSize=11,
            powerFontSize=10, portraitMode="OFF", showLevelIndicator=False,
            textLeft="NONE", textCenter="CURPERCENT", textRight="NONE",
            nameTextAnchor="TOP", nameOffsetX=0, nameOffsetY=13,
            hpOffsetX=0, hpOffsetY=0, powerBarDetached=False,
            screenPositionMode="relativeHeight", screenPositionHeight=1072,
            detachedPowerBarAnchorToClassPower=False, detachedPowerBarSyncClassPower=False)
    for key, x, mode in ((b"player", -380, "LEFT"), (b"target", 380, "RIGHT")):
        put(db[key], width=180, height=32, point="CENTER", relativePoint="CENTER",
            offsetX=x, offsetY=-190, portraitMode=mode, portraitRender="2D",
            portraitShape="BLIZZARD", portraitPlacement="ATTACHED", portraitSizeMode="UNIFORM",
            portraitSizeOverride=60, portraitWidth=60, portraitHeight=60,
            portraitOffsetX=0, portraitOffsetY=0, portraitAlpha=100,
            portraitBorderStyle="CUSTOM", portraitBorderThickness=2,
            portraitBorderColorR=.82, portraitBorderColorG=.67, portraitBorderColorB=.30,
            portraitBorderColorA=1, portraitBlizzardElite=key == b"target",
            showPowerBar=key == b"target", showPowerText=False, hpBarAlpha=1, hpBgAlpha=.8)
    put(db[b"player"], showPowerBar=True, powerBarDetached=True,
        detachedPowerBarAnchorToClassPower=True, detachedPowerBarSyncClassPower=True,
        detachedPowerBarHeight=6, detachedPowerBarWidth=334,
        detachedPowerBarOffsetX=0, detachedPowerBarOffsetY=-56,
        detachedPowerBarTextOnBar=False)
    # A single center row under Essential, just like the reference combat view.
    party = db[b"gf_party"]
    put(party, width=104, height=58, point="CENTER", offsetX=0, offsetY=-240,
        growth="RIGHT", spacing=4, unitsPerColumn=5, maxColumns=1, showPlayer=True,
        gfBarMode="class", healthColorMode="CLASS", nameColorMode="CUSTOM",
        nameFontSize=11, hpFontSize=10, nameAnchor="TOP", nameOffsetX=0, nameOffsetY=-2, nameColorR=1, nameColorG=1, nameColorB=1,
        powerHeight=3, portraitMode="OFF", fontKey="FRIZQT")
    put(db[b"focus"], width=180, height=28, offsetX=490, offsetY=160)
    put(db[b"boss"], width=180, height=32, offsetX=650, offsetY=130)
    for key, x in ((b"pet", -380), (b"targettarget", 380)):
        put(db[key], width=100, height=16, point="CENTER", relativePoint="CENTER", offsetX=x, offsetY=-280)
    for owner in db[b"auras3"][b"perUnit"].values():
        put(owner[b"layout"], buffGroupIconSize=24, debuffGroupIconSize=24,
            buffIconHeightPercent=100, debuffIconHeightPercent=100, buffSpacing=2, debuffSpacing=2,
            buffGroupOffsetY=30, debuffGroupOffsetY=58, buffCooldownTextSize=11, debuffCooldownTextSize=11)
    return encode(envelope, "MSUF3:")


def modules():
    envelope = decode(literal(CORE / "RetailProfile.lua", "Suite.RetailProfileModuleCompact"), "MSUFM1:MSUF3:")
    entries = envelope[b"profile"][b"suite"][b"modules"]
    put(entries[b"actionbars"], look=4, borderArt=2, iconSkin="CUSTOM", buttonShape=1,
        bar1Visibility=1, bar1Point=8, bar1X=0, bar1Y=6, bar1Size=38,
        bar1Rows=1, bar1Buttons=12, bar1Spacing=2, bar1Keybind=True, bar1ShowEmpty=True,
        bar1LeftEndcap=4, bar1RightEndcap=4, bar1LeftEndcapSize=70, bar1RightEndcapSize=70,
        bar1LeftEndcapY=10, bar1RightEndcapY=10)
    for i in range(2, 13):
        put(entries[b"actionbars"], **{f"bar{i}Visibility": 6})
    put(entries[b"cooldownManager"], enabled=True, captured=True, listsData="", spellsData="",
        ess_x=0, ess_y=-130, ess_size=40, ess_spacing=2, ess_perRow=8,
        uti_x=0, uti_y=0, uti_size=28, uti_perRow=10, uti_gap=8,
        buf_size=24, buf_gap=3, def_size=26, ext_size=26)
    put(entries[b"minimap"], enabled=True, captured=True, stylePreset=1, shape=2, size=210,
        point=3, x=-26, y=-44, borderSize=2, borderColor="c5ad6a", iconSkin="CUSTOM",
        styleTexture=1, styleGlow=False, styleBackdrop=False, outerBorderSize=0, shadowSize=0)
    put(entries[b"chat"], enabled=True, look=4, windowX=32, windowY=54,
        windowWidth=496, windowHeight=176, lockWindowPosition=True, lockWindowSize=True,
        fontSize=14, padding=4, tabPanel=True, borderColor="807865", panelColor="151310", panelAlpha=35)
    put(entries[b"damageMeter"], enabled=True, windowCount=2, classColors=True, look=4,
        w1X=-32, w1Y=54, w1Width=340, w1Height=172,
        w2X=-32, w2Y=244, w2Width=340, w2Height=112,
        barTexture="Blizzard", borderColor="807865", titleColor="ffd54a",
        bgColor="151310", bgAlpha=55, headerColor="242017", rowHeight=21, rowGap=3)
    data = entries[b"dataTexts"]
    put(data, enabled=True, bar1Enabled=True, bar1Point=7, bar1X=32, bar1Y=6,
        bar1Width=496, bar1Height=28, bar1Visibility=1, bar1Dock=1, bar1FullScreen=False,
        bar1BackgroundEnabled=True, bar1BackgroundColor="151310", bar1BackgroundOpacity=50,
        bar1ValueColor="ffffff", bar1AccentColor="ffd54a", bar1AccentEnabled=False,
        bar1BorderEnabled=False, bar1StyleOverride=True, bar1CustomColors=True, bar1FontSize=12)
    for i in range(2, 13):
        put(data, **{f"bar{i}Enabled": False})
    put(entries[b"objectives"], x=-26, y=-285, width=270, height=510,
        titleColor="ffd54a", sectionSize=14, entrySize=13, objectiveSize=12, backgroundOpacity=0)
    put(entries[b"buffReminders"], enabled=False)
    # Retain Blizzard's nameplate owner and settings; this preset places no replacement.
    return encode(envelope, "MSUFM1:MSUF3:")


def skin():
    envelope = decode(literal(CORE / "RetailSkinFactory.lua", "Suite.RetailFactorySkinCompact"), "MSKIN1:")
    db = envelope[b"payload"]
    put(db[b"icons"][b"microMenu"], preset="blizzard", layoutMode="owned", tint="native",
        iconStyle="blizzard", orientation="horizontal", buttonsPerLine=14, scale=1,
        layoutPoint="BOTTOMRIGHT", layoutRelativePoint="BOTTOMRIGHT", layoutX=-32, layoutY=4,
        positionPreset="custom", visibility="always", buttonSize=24, iconSize=22,
        spacing=1, padding=0, barBackground=False, barBorder=0, buttonBackground=False, buttonBorder=0)
    for key in (b"positions", b"scales"):
        db[b"windowControls"][key] = {}
    put(db[b"typography"], enabled=False)
    put(db[b"theme"], look="custom", gradient=False, materialDepth=0,
        borderOpacity=.65, shellOpacity=.8, panelOpacity=.65)
    for role in (b"accent", b"accentAlt", b"title", b"checkmark"):
        db[b"theme"][b"colors"][role] = [1, .82, .26, 1]
    # Native Blizzard windows, quest tracker and chat retain their own chrome.
    for key in db[b"skins"]:
        db[b"skins"][key] = key == b"microMenu"
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
