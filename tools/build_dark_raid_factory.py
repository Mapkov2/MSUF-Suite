"""Build the optional Dark Raid layout from the existing profile schema."""
import argparse
from pathlib import Path

from build_forever_factory_preview import decode, encode
from build_modern_dark_factory import CORE, assignment, literal, put, write


FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Bold.ttf"

def cooldown_lists(dungeon=False):
    havoc = {b"ess": [b"s232893", b"s188499", b"s258860", b"s198793",
                      b"s198013", b"s258920", b"s370965", b"s191427"],
             b"uti": [b"s183752", b"s179057", b"s207684", b"s185123", b"s195072"],
             b"c2": [b"a162264", b"a391215", b"a208628", b"a258920", b"a347462", b"a343312"],
             b"c3": [b"a442688", b"d442624"], b"c4": [b"a442442"]}
    if dungeon:
        havoc[b"uti"] = [b"s183752", b"s179057", b"s207684", b"s217832",
                         b"s278326", b"s185123", b"s195072"]
    return {b"v": 1, b"specs": {577: havoc}, b"hidden": {},
             b"replace": {577: {b"ess": True, b"uti": True}},
             b"shared": {b"c1": [b"s196718", b"s198589"]}}


def frames():
    envelope = decode(literal(CORE / "ModernDarkFactory.lua", "Suite.ModernDarkFramesCompact"), "MSUF3:")
    put(envelope, profile="Dark Raid")
    db = envelope[b"payload"]
    # The second meter shows overall damage in dungeons, healing elsewhere.
    # Core context variants restore the base profile and defer changes in combat.
    db[b"profileVariants"] = {b"version": 1, b"entries": [{
        b"name": b"Dungeon meter", b"conditions": {b"context": b"party"}, b"patch": [
            {b"path": [b"suiteModules", b"damageMeter", b"w2Type"], b"value": 1},
            {b"path": [b"suiteModules", b"damageMeter", b"w2Session"], b"value": 2},
            {b"path": [b"suiteModules", b"cooldownManager", b"uti_perRow"], b"value": 7},
            {b"path": [b"suiteModules", b"cooldownManager", b"listsData"],
             b"value": encode(cooldown_lists(True), "MSUF3:").encode()},
        ]}]}
    put(db[b"general"], barMode="dark", darkMode=True, useClassColors=False,
        darkBarR=.07, darkBarG=.07, darkBarB=.07, enableHealthGradient=False,
        enableGradient=False, barBgColorMode="custom", barBgClassColor=False,
        darkBgCustomColor=True, classBarBgR=.32, classBarBgG=.32, classBarBgB=.32, classBarBgA=1,
        absorbBarColorR=.24, absorbBarColorG=.44, absorbBarColorB=.54, absorbBarColorA=1,
        absorbBarTexture="Solid", absorbBarOpacity=1,
        barBgFillMode="missing", barBgMatchHPColor=False, anchorToCooldown=False,
        anchorName="UIParent", fontKey=FONT, fontSlug=False, fontMonochrome=False, fontSize=12, nameFontSize=12, hpFontSize=12,
        powerColorMode="power", nameClassColor=False, nameColorMode="CUSTOM",
        nameColorR=1, nameColorG=1, nameColorB=1, noOutline=False, boldText=False,
        barOutlineColorR=.28, barOutlineColorG=.28, barOutlineColorB=.28,
        barOutlineColorA=1, fontShadowOpacity=1, fontShadowDistance=1,
        showLeaderIcon=False, showCombatStateIndicator=False, showRestingIndicator=False, showPvpIndicator=False,
        castbarTargetDetached=False, castbarTargetMatchWidth=False,
        castbarTargetBarWidth=248, castbarTargetBarHeight=18,
        castbarTargetOffsetX=0, castbarTargetOffsetY=-57,
        castbarTargetIconPosition="LEFT", castbarTargetIconSize=18,
        castbarTargetIconSpacing=0, castbarTargetIconOffsetY=0,
        castbarTargetSpellNamePosition="LEFT", castbarTargetSpellNameAlign="LEFT",
        castbarTargetSpellNameFontSize=11, castbarTargetTimeFontSize=11,
        castbarTargetTimeFormat="CURRENT", castbarTargetShowIcon=True,
        focusCastbarOverrideEnabled=True, focusCastbarOverrideColor={1: .58, 2: .52, 3: 1},
        castbarFocusDetached=False, castbarFocusMatchWidth=False,
        castbarFocusBarWidth=156, castbarFocusBarHeight=18,
        castbarFocusOffsetX=0, castbarFocusOffsetY=-49,
        castbarFocusIconPosition="LEFT", castbarFocusIconSize=18,
        castbarFocusIconSpacing=0, castbarFocusIconOffsetX=0, castbarFocusIconOffsetY=0,
        castbarFocusSpellNamePosition="LEFT", castbarFocusSpellNameAlign="LEFT",
        castbarFocusSpellNameFontSize=11, castbarFocusTimeFontSize=11,
        castbarFocusTimeFormat="CURRENT", castbarFocusShowIcon=True,
        castbarFocusShowSpellName=True, castbarFocusShowTargetName=False,
        castbarPlayerMatchWidth=False, castbarPlayerBarWidth=314, castbarPlayerBarHeight=24,
        castbarPlayerDetached=False, castbarPlayerOffsetX=304, castbarPlayerOffsetY=11,
        castbarPlayerShowIcon=True, castbarPlayerIconPosition="LEFT", castbarPlayerIconSize=24,
        castbarPlayerIconSpacing=0, castbarPlayerIconOffsetX=0, castbarPlayerIconOffsetY=0,
        castbarPlayerSpellNameFontSize=11, castbarPlayerTimeFontSize=11,
        castbarPlayerTimeFormat="ELAPSED_MAX",
        playerCastbarOverrideEnabled=True, playerCastbarOverrideMode="CUSTOM",
        playerCastbarOverrideR=.58, playerCastbarOverrideG=.52, playerCastbarOverrideB=1,
        bossCastbarMatchWidth=False, bossCastbarWidth=192, bossCastbarHeight=18,
        bossCastbarDetached=False, bossCastbarOffsetX=0, bossCastbarOffsetY=2,
        bossCastSpellNamePosition="LEFT", bossCastSpellNameFontSize=11, bossCastTimeFontSize=11,
        showBossCastIcon=True, showBossCastName=True, showBossCastTime=True,
        castbarInterruptibleR=.25, castbarInterruptibleG=.48, castbarInterruptibleB=1,
        castbarNonInterruptibleR=1, castbarNonInterruptibleG=.3, castbarNonInterruptibleB=.3,
        castbarInterruptUnavailableR=.25, castbarInterruptUnavailableG=.48, castbarInterruptUnavailableB=1,
        kickReadyShowNameplates=True, kickReadyStyle="fill", kickReadyTimeMarker=False, kickReadyTimeSegment=False)
    bars = db[b"bars"]
    put(bars, barOutlineThickness=1, classPowerHeight=6, classPowerGap=1,
        classPowerWidthMode="custom", classPowerWidth=314, classPowerOffsetX=0, classPowerOffsetY=0,
        classPowerAnchorToCooldown=True, classPowerCooldownTopAnchor=True,
        detachedPowerBarWidthMode="manual", powerBarHeight=3)
    db[b"general"][b"classPowerColorOverrides"] = {}
    for key in (b"player", b"target", b"focus", b"boss", b"arena", b"pet", b"targettarget"):
        config = db.get(key)
        if not isinstance(config, dict):
            continue
        for field in list(config):
            if field.startswith(b"direct") or field in (b"anchorToUnitframe", b"_screenRefH",
                                                        b"screenPositionMode", b"screenPositionHeight"):
                config.pop(field)
        put(config, anchorFrameName="UIParent", point="CENTER", relativePoint="CENTER",
            width=248, height=38, healthColorMode="DARK", portraitMode="OFF",
            texLayerEnabled=False, texLayer2Enabled=False, texLayer3Enabled=False,
            nameColorMode="CUSTOM", nameColorR=1, nameColorG=1, nameColorB=1,
            nameClassColor=False, fontOverride=True, fontKey=FONT, fontSlug=False, fontMonochrome=False,
            noOutline=True, boldText=False, textBackdrop=True, fontShadowDistance=1,
            showLeaderIcon=False, showCombatStateIndicator=False, showRestingIndicator=False, showPvpIndicator=False,
            nameFontSize=12, hpFontSize=12, hpTextRightFontSize=12,
            hpBarAlpha=.85, hpBgAlpha=.9, showName=True, showHP=True, showPowerText=False,
            showPowerBar=False, textLeft="NONE", textCenter="NONE", textRight="CURPERCENT",
            hpTextSeparator=" - ", hpTextReverse=False, hpFullValueShort=True, healthTextDecimals=True,
            directTextLayout=True, directNamePoint="LEFT", directNameRelativePoint="LEFT",
            directNameOffsetX=5, directNameOffsetY=0, directNameWidth=112,
            directHealthRightPoint="RIGHT", directHealthRightRelativePoint="RIGHT",
            directHealthRightOffsetX=-5, directHealthRightOffsetY=0,
            powerBarDetached=False, detachedPowerBarAnchorToClassPower=False,
            detachedPowerBarSyncClassPower=False, showLevelIndicator=False,
            reverseFillBars=False, verticalFillBars=False)
    for key, x in ((b"player", -304), (b"target", 304)):
        put(db[key], offsetX=x, offsetY=-260)
    put(db.setdefault(b"gameplay", {}), enableCombatTimer=True, lockCombatTimer=True,
        combatTimerClickThrough=True, combatTimerAnchor="player", combatOffsetX=-101, combatOffsetY=0,
        enablePlayerTotems=False, combatFontSize=12, combatTimerKeepLast=True, combatTimerPadMinutes=True)
    put(db[b"player"], barBgColorOverride=True, bgR=.32, bgG=.32, bgB=.32,
        showName=False, showPowerText=True, powerTextCenter="CURRENT",
        powerTextLeft="NONE", powerTextRight="NONE", powerFontSize=10,
        showPowerBar=True, powerBarDetached=True,
        detachedPowerBarAnchorToClassPower=True, detachedPowerBarSyncClassPower=True,
        detachedPowerBarWidth=314, detachedPowerBarHeight=3,
        detachedPowerBarOffsetX=0, detachedPowerBarOffsetY=0, detachedPowerBarTextOnBar=True)
    put(db[b"focus"], width=156, height=30, offsetX=-486, offsetY=-115,
        directNameWidth=146, nameFontSize=11, showHP=False, textRight="NONE",
        showRaidMarker=True, raidMarkerAnchor="TOPRIGHT",
        raidMarkerOffsetX=-5, raidMarkerOffsetY=7, raidMarkerSize=14)
    put(db[b"boss"], width=192, height=36, point="RIGHT", relativePoint="RIGHT",
        offsetX=-470, offsetY=102, spacing=-58, bossLayoutMode="VERTICAL_DOWN",
        directNameWidth=92, nameFontSize=11, hpTextRightFontSize=10)
    for key, owner, edge in ((b"pet", "player", "LEFT"), (b"targettarget", "target", "RIGHT")):
        put(db[key], width=112, height=16, anchorFrameName="", anchorToUnitframe=owner,
            point="TOP" + edge, relativePoint="BOTTOM" + edge, offsetX=0, offsetY=-42,
            nameFontSize=10, directNameWidth=102, showHP=False, textRight="NONE")
    for key in (b"gf_party", b"gf_raid", b"gf_mythicraid"):
        c = db[key]
        for field in (b"screenPositionMode", b"screenPositionHeight", b"positionMigrationCount",
                      b"positionMigrationDX", b"positionMigrationDY"):
            c.pop(field, None)
        put(c, width=94, height=64, point="TOPLEFT", relativePoint="TOPLEFT", offsetX=8, offsetY=-8,
            positionMode="GRID_BOUNDS_V2", growth="RIGHT", unitsPerColumn=5,
            maxColumns=1 if key == b"gf_party" else 4 if key == b"gf_mythicraid" else 8,
            spacing=2, showPlayer=True, preserveRaidGroups=False, nameBarEnabled=False,
            gfBarMode="dark", healthColorMode="DARK", gfDarkR=.07, gfDarkG=.07, gfDarkB=.07,
            hpBarAlpha=.85, hpBgAlpha=.9, barBgColorOverride=True, bgR=.32, bgG=.32, bgB=.32,
            alphaExcludeTextPortrait=True, alphaExcludePredictionBars=True, barTextureOverride=True, barTexture="Solid",
            powerBarEnabled=True, powerHeight=2, showPowerText=False, showPower=False,
            nameColorMode="CLASS", nameClassColor=True, nameFontSize=11, fontOverride=True,
            fontOutline="NONE", fontSlug=False, fontMonochrome=False, textBackdrop=True,
            nameAnchor="TOPLEFT", nameOffsetX=3, nameOffsetY=-3, nameMaxChars=14,
            fontKey=FONT, portraitMode="OFF", roleIcon=False, showHPText=False,
            textLeft="NONE", textCenter="NONE", textRight="NONE",
            borderEnabled=True, borderSize=1, borderR=.28, borderG=.28, borderB=.28, borderA=1)
        auras = c[b"auras"]
        put(auras[b"buff"], enabled=True, anchor="CENTER", x=-8, y=0,
            size=16, max=1, perRow=1, spacing=1, growth="RIGHTDOWN")
        put(auras[b"debuff"], enabled=True, anchor="BOTTOMLEFT", x=3, y=4,
            size=18, max=2, perRow=2, spacing=1, growth="RIGHTUP")
        put(auras[b"externals"], enabled=True, anchor="BOTTOMRIGHT", x=-3, y=4,
            size=16, max=1, perRow=1, spacing=1, growth="LEFTUP")
    put(db[b"gf_party"], width=208, height=56, growth="DOWN", offsetX=470, offsetY=-540,
        showHPText=True, textRight="PERCENT", hpFontSize=11,
        showPlayer=False, hpOffsetX=0, hpOffsetY=20, hpTextRightOffsetX=0, hpTextRightOffsetY=0)
    # Missing health is neutral gray on every frame; only absorb prediction is blue.
    for key in (b"player", b"target", b"focus", b"boss", b"arena", b"pet", b"targettarget",
                b"gf_party", b"gf_raid", b"gf_mythicraid"):
        put(db[key], absorbBarTexture="Solid", absorbAnchorMode=5, absorbBarHeight=0,
            absorbBarOffsetY=0, absorbBarOpacity=1, overAbsorbOverlay=True)
    auras = db[b"auras3"]
    put(auras, showBoss=True)
    defensive = auras[b"customContainers"][b"perUnit"][b"player"][b"items"][4]
    put(defensive, enabled=False, autoBlacklistPlayerBuffs=False, portraitIcon=False)
    put(defensive[b"placed"], anchor="TOPRIGHT", x=0, y=36, size=34, spacing=1,
        max=2, perRow=2, growth="LEFTDOWN", showCooldown=True, showStacks=True)
    put(auras[b"shared"], showWeaponEnchants=False)
    for key, c in auras[b"perUnit"].items():
        put(c, overrideLayout=True, overrideStyle=True, overrideSharedLayout=True)
        put(c[b"layout"], buffGroupIconSize=34, debuffGroupIconSize=34,
            buffIconHeightPercent=100, debuffIconHeightPercent=100, buffSpacing=1, debuffSpacing=1,
            buffCooldownTextSize=11, debuffCooldownTextSize=11, buffStackTextSize=12, debuffStackTextSize=12)
        put(c[b"layoutShared"], buffPerRow=4, debuffPerRow=4, maxBuffs=4, maxDebuffs=4,
            buffGrowthX="RIGHT", debuffGrowthX="RIGHT", buffGrowthY="DOWN", debuffGrowthY="DOWN",
            buffStackCountAnchor="BOTTOMRIGHT", debuffStackCountAnchor="BOTTOMRIGHT",
            buffCooldownTextAnchor="CENTER", debuffCooldownTextAnchor="CENTER")
        if key.startswith(b"boss"):
            put(c[b"layout"], buffAnchor="TOPLEFT", buffGroupOffsetX=194, buffGroupOffsetY=0,
                debuffAnchor="TOPRIGHT", debuffGroupOffsetX=-194, debuffGroupOffsetY=0)
            put(c[b"layoutShared"], debuffGrowthX="LEFT")
        elif key in (b"player", b"target"):
            put(c[b"layout"], buffAnchor="TOPLEFT", buffGroupOffsetX=0, buffGroupOffsetY=-40,
                debuffAnchor="TOPRIGHT", debuffGroupOffsetX=0, debuffGroupOffsetY=36)
            put(c[b"layoutShared"], debuffGrowthX="LEFT")
            if key == b"player":
                put(c[b"layout"], debuffAnchor="TOPLEFT", debuffGroupOffsetX=0, debuffGroupOffsetY=36)
                put(c[b"layoutShared"], debuffGrowthX="RIGHT", maxDebuffs=4)
                # Potions, Healthstone and the racial occupy this row through the CDM.
                put(c[b"layoutShared"], showBuffs=False)
            else:
                put(c[b"layout"], buffAnchor="TOPLEFT", buffGroupOffsetX=0, buffGroupOffsetY=36)
                # Two buffs plus four debuffs fit above the 248px target without overlap.
                put(c[b"layoutShared"], maxBuffs=2, buffPerRow=2)
    return encode(envelope, "MSUF3:")


def modules():
    envelope = decode(literal(CORE / "ModernDarkFactory.lua", "Suite.ModernDarkModuleCompact"), "MSUFM1:MSUF3:")
    entries = envelope[b"profile"][b"suite"][b"modules"]
    cd = entries[b"cooldownManager"]
    put(cd, font=FONT)
    put(cd, listsData="", spellsData="", ess_x=0, ess_y=-240, ess_size=38, ess_perRow=8, ess_spacing=1,
        ess_maxIcons=0, ess_laterPerRow=0, ess_laterSize=0, ess_centerFirst=False, ess_align=1, uti_align=1,
        uti_maxIcons=0, uti_laterPerRow=0, uti_laterSize=0, uti_centerFirst=False,
        def_on=False, ext_on=True, buf_on=False, bar_on=False,
        ext_anchor=14, ext_side=1, ext_align=2, ext_gap=1, ext_x=0, ext_y=0,
        ext_size=34, ext_perRow=4, ext_maxIcons=0, ext_vis=1, ext_oocAlpha=100,
        ext_readyAlpha=100, ext_cdText=True, ext_charges=True, ext_stackText=True,
        ext_stackPos=9, ext_showAura=False, potionStockIcon=False,
        uti_size=32, uti_perRow=5, uti_gap=1, uti_x=0, uti_y=0,
        buf_size=34, buf_perRow=4, buf_maxIcons=0, buf_anchor=2,
        buf_side=2, buf_align=1, buf_grow=2, buf_gap=34, buf_x=0, buf_y=0,
        buf_keepSlots=False, buf_showMissing=False, def_gap=2)
    for prefix in ("ess", "uti", "def", "ext", "buf", "c1", "c2", "c3", "c4", "c5", "c6"):
        put(cd, **{prefix + "_height": 100, prefix + "_spacing": 1,
                   prefix + "_border": 1, prefix + "_borderColor": "333333",
                   prefix + "_cdSize": 12, prefix + "_stackSize": 12})
    # The two persistent icons in Kuro's reference are Darkness and Blur,
    # including Blur charges. They are spell cooldowns, not active aura icons.
    # Havoc follows the two rows in the reference, not the short raid defaults.
    # Spell keys survive native cooldown-ID changes and follow learned overrides.
    lists = cooldown_lists()
    put(cd, listsData=encode(lists, "MSUF3:"), c1_on=True, c1_kind=1,
        c1_shareContents=True, c1_anchor=14, c1_side=2, c1_align=3, c1_gap=1,
        c1_x=0, c1_y=0, c1_size=34, c1_perRow=2, c1_maxIcons=0,
        c1_vertical=False, c1_grow=1, c1_laterPerRow=0, c1_laterSize=0,
        c1_cdText=True, c1_charges=True, c1_stackText=True, c1_stackPos=9,
        c1_showAura=False, c1_vis=1, c1_oocAlpha=100, c1_readyAlpha=100)
    # Player procs form one native compact row. The upper row tracks Thrill
    # of the Fight and Reaver's Mark on the target, not Tactical Retreat.
    # Mixed-unit native containers retain their half-row anchors independently.
    for prefix, count, gap in (("c2", 6, 34), ("c3", 2, 69), ("c4", 1, 69)):
        put(cd, **{prefix + "_on": True, prefix + "_kind": 2,
            prefix + "_shareContents": False, prefix + "_anchor": 2,
            prefix + "_side": 2, prefix + "_align": 1, prefix + "_gap": 34,
            prefix + "_x": 0, prefix + "_y": gap - 34, prefix + "_size": 34,
            prefix + "_perRow": count, prefix + "_maxIcons": 0,
            prefix + "_vertical": False, prefix + "_grow": 1,
            prefix + "_laterPerRow": 0, prefix + "_laterSize": 0,
            prefix + "_centerFirst": False, prefix + "_keepSlots": False,
            prefix + "_showMissing": False, prefix + "_cdText": True,
            prefix + "_stackText": True, prefix + "_vis": 1})
    # Native visibility lets Rending Strike cover the Mark cell while active.
    # The observed glaive sequence needs no addon reads of protected aura state.
    put(cd, c4_anchor=10, c4_side=1, c4_align=3, c4_gap=0, c4_x=0, c4_y=34,
        c4_strata=4, c4_alpha=100, c4_oocAlpha=100)
    ab = entries[b"actionbars"]
    put(ab, font=FONT, borderSize=1, borderColor="333333")
    for index in range(1, 6):
        put(ab, **{f"bar{index}Visibility": 1 if index <= 3 else 6,
            f"bar{index}Point": 8, f"bar{index}X": (index - 2) * 180, f"bar{index}Y": 2,
            f"bar{index}Size": 29, f"bar{index}HeightPercent": 100, f"bar{index}Spacing": 1,
            f"bar{index}Buttons": 12, f"bar{index}Rows": 2, f"bar{index}ShowEmpty": True, f"bar{index}Vertical": False,
            f"bar{index}Keybind": True, f"bar{index}Macro": False, f"bar{index}Background": False})
    put(entries[b"damageMeter"], windowCount=2, w1Width=208, w2Width=208,
        w1Height=196, w2Height=196, w1X=-210, w2X=-2, w1Y=2, w2Y=2,
        w1Type=1, w2Type=3, w1Session=1, w2Session=1, numberFormat=3, englishNumbers=True, englishDecimals=2, englishKDecimals=1, headerTimer=False,
        bgColor="080808", bgAlpha=85, borderSize=1,
        borderColor="333333", barHeight=20, barSpacing=1, classColors=True,
        headerOutside=True, overallTitlePrefix=True, headerHeight=16, headerIconSize=12, headerSelectors=False,
        headerMouseover=True, headerAlpha=0, titleOffsetX=-6, leftSize=11, rightSize=11, titleSize=11,
        font=FONT, nameMaxChars=16, nameEllipsis=False, rank=False, barTexture="Solid",
        gradientEnabled=False, shadowDistance=1, rendering=1, namesRendering=1,
        detailsRendering=1, headerRendering=1)
    put(entries[b"minimap"], size=208, point=3, x=-2, y=-2, shape=1,
        borderSize=1, borderColor="333333", outerBorderSize=0, styleBackdropPadding=0,
        infoLocation=True, infoLocationColor="e9d34b", infoLocationSize=11,
        infoLocationAnchor=1, infoLocationX=3, infoLocationY=-4,
        infoClock=True, infoClockSize=12, infoClockAnchor=7, infoClockX=3, infoClockY=16,
        infoFPS=True, infoLatency=True, infoCalendarDay=False, dungeonButton=False, middleClick=5,
        queueStatusEnabled=True, queueStatusSize=32, queueStatusX=187, queueStatusY=-167)
    put(entries[b"chat"], fontSize=12, tabFontSize=12, panelColor="080808", panelAlpha=65,
        windowWidth=400, windowHeight=196, windowX=8, windowY=8, padding=3,
        borderSize=1, borderColor="333333", tabAccent=False, hideNativeButtons=True)
    put(entries[b"playerAuras"], iconWidth=30, iconHeight=30, perRow=14, spacing=1,
        rowSpacing=2, x=-222, y=-2, fontSize=11, borderSize=1, borderColor="333333")
    put(entries[b"tooltipDetails"], fixedX=-2, fixedY=228)
    put(entries[b"objectives"], x=-4, y=-228, width=300, titleSize=12,
        sectionSize=12, entrySize=11, objectiveSize=11)
    # Keep the native bag-bar owner active without visible information strips.
    data_texts = entries[b"dataTexts"]
    put(data_texts, enabled=True, hideBlizzardBagBar=True, trackAltGold=False, barIds="1")
    for key in data_texts:
        if key.startswith(b"bar") and key.endswith(b"Enabled"):
            data_texts[key] = False
    put(entries[b"xpBar"], enabled=False)
    put(entries[b"battleRes"], enabled=True, textOnly=True, font=FONT, fontSize=11,
        width=70, height=16, scale=100, point=5, x=-310, y=-260, glossEnabled=False)
    np = entries[b"nameplates"]
    for key in np:
        if key.endswith((b"OffsetX", b"OffsetY")):
            np[key] = 0
    put(np, look=3, nativeStyle=2, nativeSize=3, barGeometry=2,
        enemyTextMode=4, enemyMirrorHeader=False, enemyRoleColors=False, enemyQuestColors=False,
        enemyColorsInDungeons=False, enemyColorsOutside=False,
        enemyHealthWidthDelta=0, enemyHealthHeightDelta=0,
        enemyNameSize=11, enemyHealthTextSize=10, enemyCastSize=11,
        enemyTargetMarker=True, enemyTargetStyle=10, enemyTargetLayout=2,
        enemyTargetMarkerSize=14, enemyTargetColor="ffffff",
        enemyBorderEnabled=True, enemyBorderSize=1, enemyBorderColor="aaaaaa",
        enemyCastHeight=16, enemyCastIconSize=16, enemyCastTimeFormat=1,
        enemyCastTextEnabled=True, enemyCastTimeEnabled=True,
        enemyCastEnabled=2, enemyCastDisplay=2, enemyCastSpellName=True,
        enemyCastSpellIcon=True, enemyCastSpellTarget=False,
        auraScaleMode=2, auraScalePercent=80, friendlyNameSize=11)
    return encode(envelope, "MSUFM1:MSUF3:")


def skin():
    envelope = decode(literal(CORE / "ModernDarkFactory.lua", "Suite.ModernDarkSkinCompact"), "MSKIN1:")
    # The reference has no visible micro strip. Keep access through the minimap menu.
    # A later edit-mode reveal sits clear of the two action-bar rows.
    put(envelope[b"payload"][b"icons"][b"microMenu"], visibility="never", layoutY=64)
    return encode(envelope, "MSKIN1:")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--export-dir", type=Path)
    args = parser.parse_args()
    frame, module = frames(), modules()
    skin_profile = skin()
    write(CORE / "DarkRaidFactory.lua", "local _, Suite = ...\n-- Optional Dark Raid layout; applied only by the installer.\n"
          + assignment("Suite.DarkRaidFramesCompact", frame)
          + assignment("Suite.DarkRaidModuleCompact", module)
          + assignment("Suite.DarkRaidSkinCompact", skin_profile), args.check)
    if args.export_dir:
        args.export_dir.mkdir(parents=True, exist_ok=True)
        (args.export_dir / "Dark-Raid-UF-GF.txt").write_text(frame + "\n", encoding="utf-8")
        (args.export_dir / "Dark-Raid-Suite.txt").write_text(module + "\n", encoding="utf-8")
        (args.export_dir / "Dark-Raid-Skin.txt").write_text(skin_profile + "\n", encoding="utf-8")
    print("Dark Raid factories " + ("match" if args.check else "written"))


if __name__ == "__main__":
    main()
