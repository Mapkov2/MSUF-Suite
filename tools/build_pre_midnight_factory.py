"""Build the Pre-Midnight layout on top of the authored Dark Raid profile."""

import argparse
from copy import deepcopy
from pathlib import Path

from build_forever_factory_preview import decode, encode
from build_modern_dark_factory import CORE, assignment, literal, put, read_host_defaults, write


NAME = "Pre-Midnight"
FRAME_PREFIX = "MSUF3:"
SUITE_PREFIX = "MSUFM1:MSUF3:"
DARK_RAID = CORE / "DarkRaidFactory.lua"
HOST = CORE.parents[2] / "MidnightSimpleUnitFrames-7.0"
GROUP_SCOPES = (b"gf_party", b"gf_raid", b"gf_mythicraid")
INDICATOR_DATA = """(function()
    local indicators = world.core.GF.SpellIndicators
    local result = {}
    for key, defaults in pairs(indicators.SpecDefaults) do
        local ordered = {}
        for _, aura in ipairs(indicators.TrackableAuras[key]) do
            local entry = defaults[aura.name]
            if entry then ordered[#ordered + 1] = { name = aura.name, entry = entry } end
        end
        result[key] = ordered
    end
    return result
end)()"""
NAMEPLATE_NAMES = {
    b"fontOverride": True, b"fontSize": 10, b"nameFontSize": 10,
    b"nameColorMode": b"CLASS", b"nameClassColor": True, b"npcNameRed": True,
    b"nameNpcClassColor": False, b"nameFormat": b"FULL",
}
# Each pair is an aura ID and the known cast that applies it. This keeps
# missing-aura slots for spells the current specialization can actually use.
TARGET_DOTS = {
    103: ((155722, 1822), (1079, 1079)),  # Feral
    258: ((589, 589), (34914, 34914)),    # Shadow
    259: ((703, 703), (1943, 1943)),      # Assassination
    262: ((188389, 188389),),             # Elemental
    263: ((188389, 188389),),             # Enhancement
    265: ((980, 980),),                   # Affliction
}


def update_settings(parent, key, values):
    current = parent.get(key)
    if not isinstance(current, dict):
        current = {}
        parent[key] = current
    current.update(values)


def frames():
    envelope = decode(literal(DARK_RAID, "Suite.DarkRaidFramesCompact"), FRAME_PREFIX)
    put(envelope, profile=NAME)
    db = envelope[b"payload"]
    # Measured in UI units at 1920 x 1080 and the pixel-perfect scale.
    # The main HUD is centered. The compact party column has a left anchor.
    db.pop(b"profileVariants", None)
    put(db[b"general"], menuFontKey="GLOBAL", barTexture="Solid", castbarTargetBarWidth=209,
        castbarTargetBarHeight=17, castbarTargetOffsetY=-52, castbarTargetIconSize=17,
        castbarPlayerMatchWidth="utility", castbarPlayerAnchorToUtility=True, castbarPlayerBarWidth=144,
        castbarPlayerBarHeight=18, castbarPlayerIconSize=18, castbarPlayerOffsetX=0, castbarPlayerOffsetY=0,
        castbarInterruptibleR=.65, castbarInterruptibleG=.18, castbarInterruptibleB=.20,
        nameColorMode="CLASS", nameClassColor=True, npcNameRed=True,
        barOutlineColorR=0, barOutlineColorG=0, barOutlineColorB=0, barOutlineColorA=1,
        anchorToCooldown=True, anchorName="EssentialCooldownViewer",
        cooldownAnchorPosition="CENTER", cooldownAnchorLayoutY=-167.5)
    put(db[b"bars"], classPowerWidthMode="cooldown", classPowerWidth=290,
        classPowerShape="BAR", classPowerHeight=7, classPowerGap=0, classPowerTickWidth=1,
        classPowerOffsetY=-7, classPowerBgAlpha=1, classPowerFilledAlpha=1, classPowerEmptyAlpha=1,
        classPowerTexture="Solid", classPowerBgTexture="Solid", classPowerShowText=False,
        showChargedComboPoints=True,
        showBarBorder=True, barOutlineThickness=1, barOutlineTexture="", barOutlineClassColor=False,
        detachedPowerBarWidthMode="cooldown", powerBarTexture="Solid", powerBarBgTexture="Solid")
    general = db[b"general"]
    update_settings(general, b"classPowerColorOverrides", {
        b"COMBO_POINTS": [0.76, 0.72, 0.31], b"CHARGED": [0.46, 0.73, 0.45],
    })
    update_settings(general, b"classPowerBgColorOverrides", {b"COMBO_POINTS": [0.12, 0.12, 0.12]})
    update_settings(general, b"powerColorOverrides", {b"ENERGY": [0.76, 0.72, 0.31]})
    update_settings(db, b"nameplates", NAMEPLATE_NAMES)
    db[b"nameplates"].pop(b"fontKey", None)
    db[b"gf_priority"].pop(b"fontKey", None)
    for unit, x in ((b"player", 0), (b"target", -1)):
        put(db[unit], width=209, height=33, offsetX=x, offsetY=-.5,
            anchorFrameName="EssentialCooldownViewer", anchorToUnitframe="GLOBAL", cooldownAnchorFrameTop=True,
            hpTextSeparator=" | ", nameFontSize=11, hpFontSize=11, hpTextRightFontSize=11,
            showLevelIndicator=False)
    put(db[b"player"], detachedPowerBarWidth=290, detachedPowerBarHeight=13,
        detachedPowerBarSyncClassPower=False, detachedPowerBarAnchorToClassPower=True,
        detachedPowerBarOffsetY=-1, powerFontSize=12, powerOffsetX=0, powerOffsetY=0,
        powerTextCenterOffsetX=0, powerTextCenterOffsetY=0,
        directPowerCenterPoint="CENTER", directPowerCenterRelativePoint="CENTER",
        directPowerCenterOffsetX=0, directPowerCenterOffsetY=0, hpBgAlpha=.83)
    player_status_icons(db[b"player"])
    put(db[b"target"], directNamePoint="TOPLEFT", directNameRelativePoint="TOPLEFT",
        nameTextAnchor="TOPLEFT", nameOffsetX=4,
        directNameOffsetX=4, directNameOffsetY=-2, directNameWidth=200, directHealthRightPoint="BOTTOMLEFT",
        directHealthRightRelativePoint="BOTTOMLEFT", directHealthRightOffsetX=4,
        directHealthRightOffsetY=3, nameColorMode="CLASS", nameClassColor=True, npcNameRed=True)
    put(db[b"focus"], width=156, height=28, anchorFrameName="", anchorToUnitframe="player",
        point="TOPLEFT", relativePoint="TOPLEFT", offsetX=-193.5, offsetY=138.5,
        directNameWidth=146, nameFontSize=12,
        showHP=True, textRight="PERCENT", nameColorMode="CLASS", nameClassColor=True, npcNameRed=True)
    put(db[b"boss"], anchorFrameName="", anchorToUnitframe="target", offsetX=118.5, offsetY=271)
    put(db[b"arena"], anchorFrameName="", anchorToUnitframe="target", offsetX=343, offsetY=-75)
    put(db[b"targettarget"], enabled=False, showToTInTargetName=True, totInlineColorMode="TOT_NAME",
        totInlineSeparator="__CUSTOM__", totInlineCustomSeparator="»",
        nameColorMode="CLASS", nameClassColor=True, npcNameRed=True)
    put(db[b"gameplay"], combatTimerAnchor="chat", combatOffsetX=3,
        combatOffsetY=24, combatFontSize=11, combatTimerBrackets=True)
    group_frames(db)
    put(db[b"gf_party"][b"auras"][b"buff"], anchor="TOPLEFT", x=-58, y=0,
        size=18, max=3, perRow=3)
    put(db[b"gf_party"][b"auras"][b"debuff"], anchor="BOTTOMLEFT", x=-39, y=0,
        size=18, max=2, perRow=2)
    defense = db[b"auras3"][b"customContainers"][b"perUnit"][b"player"][b"items"][4]
    put(db[b"auras3"][b"shared"], animateNewIcons=True)
    put(defense, enabled=True, playerDefensives=True, sourceUnit="player", portraitIcon=False,
        autoBlacklistPlayerBuffs=True)
    # The first icon touches the Player Frame; active icons fill to its left.
    defensive_size, defensive_count, defensive_spacing = 31, 5, 1
    defensive_width = defensive_count * defensive_size + (defensive_count - 1) * defensive_spacing
    # Keep the icons flush with the 33-unit Player Frame as their width changes.
    put(defense[b"placed"], anchor="LEFT", x=-defensive_width, y=0, size=defensive_size, iconHeightPercent=106,
        spacing=defensive_spacing, max=defensive_count, perRow=defensive_count, growth="LEFTDOWN",
        animateAppearance=True, showCooldown=True, showStacks=True)
    for unit in (b"player", b"target"):
        fields = db[b"auras3"][b"perUnit"][unit]
        layout, flow = fields[b"layout"], fields[b"layoutShared"]
        buff_count, buff_size, buff_y = 4, 25, -34
        if unit == b"target":
            buff_count, buff_y, buff_spacing = 8, 26, 1
            # Fit the full row between both frame edges at the existing gap.
            buff_size = (db[unit][b"width"] - (buff_count - 1) * buff_spacing) / buff_count
            put(layout, buffAnchor="TOPLEFT", buffGroupOffsetX=0, buffSpacing=buff_spacing, buffStylePadding=0)
            put(flow, buffGrowthX="RIGHT")
        put(layout, buffGroupIconSize=buff_size, debuffGroupIconSize=24,
            buffGroupOffsetY=buff_y, debuffGroupOffsetY=26)
        put(flow, buffPerRow=buff_count, maxBuffs=buff_count)
    return encode(envelope, FRAME_PREFIX)


def player_status_icons(player):
    put(player, showCombatStateIndicator=True, combatStateIndicatorSize=14,
        combatStateIndicatorAnchor="CENTER", combatStateIndicatorOffsetX=-13, combatStateIndicatorOffsetY=0,
        showRestingIndicator=True, restedStateIndicatorSize=14, restedStateIndicatorAnchor="CENTER",
        restedStateIndicatorOffsetX=10, restedStateIndicatorOffsetY=0,
        showIncomingResIndicator=True, incomingResIndicatorSize=14, incomingResIndicatorAnchor="CENTER",
        incomingResIndicatorOffsetX=32, incomingResIndicatorOffsetY=0,
        showLeaderIcon=True, leaderIconSize=11, leaderIconAnchor="TOPLEFT", leaderIconOffsetX=4, leaderIconOffsetY=-3,
        showRaidMarker=True, raidMarkerSize=14, raidMarkerAnchor="LEFT", raidMarkerOffsetX=18, raidMarkerOffsetY=0,
        showPvpIndicator=True, pvpIndicatorSize=12, pvpIndicatorAnchor="BOTTOMLEFT",
        pvpIndicatorOffsetX=4, pvpIndicatorOffsetY=3)


def group_frames(db):
    for key in (b"gf_party", b"gf_raid", b"gf_mythicraid"):
        group = db[key]
        group.pop(b"relativePoint", None)
        put(group, anchorToFrame="MSUF_player", anchorPoint="TOPLEFT", point="TOPLEFT",
            powerBarEnabled=False, nameFontSize=11, hpTextRightFontSize=11,
            hpOffsetX=0, hpOffsetY=0, hpTextRightOffsetX=0,
            fontOverride=True, nameFormat="FULL", nameMaxChars=0, nameClipSide="RIGHT",
            nameNoEllipsis=False, nameShortenEnabled=False, nameColorMode="CLASS",
            nameClassColor=True, nameNpcClassColor=True, npcNameRed=False,
            borderEnabled=True, borderSize=1, borderR=0, borderG=0, borderB=0, borderA=1,
            showHPText=True, textRight="PERCENT", healthTextDecimals=True,
            leaderIcon=True, leaderIconSize=8, leaderIconX=-38, assistIcon=False, roleIcon=False)
    put(db[b"gf_party"], width=156, height=38, spacing=1, offsetX=-193.5, offsetY=205.5,
        nameRightInset=36, hpTextRightOffsetY=11, leaderIconY=-4,
        targetsEnabled=False, petsEnabled=False, healerManaEnabled=False)
    # Put the percent below the name on narrower raid cells.
    for key in (b"gf_raid", b"gf_mythicraid"):
        put(db[key], offsetX=-579.5, offsetY=684.5, hpTextRightOffsetY=12, leaderIconY=-20)
    group_spell_indicators(db)


def group_spell_indicators(db):
    defaults = HOST / "MidnightSimpleUnitFrames/State/Defaults"
    retail = literal(defaults / "MSUF_Defaults_FactoryData.lua", "MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT")
    forever = literal(defaults / "MSUF_Defaults_ForeverFactory.lua", "MSUF.MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT")
    factory_scopes = [decode(value, FRAME_PREFIX)[b"msuf6"][b"payload"] for value in (retail, forever)]
    spec_sets = [read_host_defaults(HOST, INDICATOR_DATA, flavor) for flavor in ("Mainline", "Forever")]
    for scope in GROUP_SCOPES:
        group = db[scope]
        style = deepcopy(factory_scopes[0][scope][b"spellIndicators"])
        assert style == factory_scopes[1][scope][b"spellIndicators"], scope
        put(style[b"style"], cooldownSize=7, stackSize=7, cooldownDecimalSeconds=0)
        put(style, enabled=True, specs={}, _autoSeededSpecs={})
        cell_size = 13 if scope == b"gf_party" else 14
        max_rows = 1 if scope == b"gf_party" else 2
        for catalog in spec_sets:
            for spec, ordered in catalog.items():
                style[b"specs"][spec] = place_spell_icons(ordered, group[b"width"], cell_size, max_rows)
        group[b"spellIndicators"] = style


def place_spell_icons(ordered, width, cell_size, max_rows):
    inset, gap = 2, 2
    stride = cell_size + gap
    columns = (width - 2 * inset + gap) // stride
    entries = {}
    index = 0
    for record in ordered:
        entry = deepcopy(record[b"entry"])
        placed = entry.get(b"placed")
        if placed and placed.get(b"type") != b"none":
            assert placed[b"type"] in (b"icon", b"square"), placed
            row, col = divmod(index, columns)
            assert row < max_rows, "Spell icons exceed the reserved space above the lower edge"
            size = min(placed[b"size"], cell_size)
            centering = (cell_size - size) // 2
            put(placed, anchor="BOTTOMLEFT", x=inset + col * stride + centering,
                y=inset + row * stride + centering, size=size)
            index += 1
        entries[record[b"name"]] = entry
    return entries


def cooldowns(config):
    # Use MSUF's current learned spell lists for each specialization. Dark
    # Raid's authored Havoc lists and aura sequence do not belong to the Rogue.
    put(config, enabled=True, animateNewIcons=True, raidEssentials=True, potionStockIcon=True,
        listsData="", spellsData="", ess_x=0, ess_y=-152,
        ess_size=31, ess_perRow=9, ess_maxIcons=9,
        uti_size=28, uti_perRow=5, uti_maxIcons=5,
        thresholdSeconds=5, thresholdColor="ff2222", tenthsSeconds=5,
        urgentSeconds=0, def_on=True, def_anchor=14, def_side=2, def_align=3,
        def_gap=0, def_x=0, def_y=0, def_vertical=False, def_grow=2,
        def_size=24, def_perRow=4, def_maxIcons=5, def_cdText=True,
        def_charges=True, def_readyAlpha=100, ext_on=True, ext_anchor=14,
        ext_side=1, ext_align=2, ext_gap=0, ext_size=25, ext_perRow=4,
        buf_on=True, buf_size=24, buf_perRow=7, buf_maxIcons=7)
    for index in range(1, 7):
        put(config, **{f"c{index}_on": False})
    dots = {f"d{aura}".encode(): {b"missingGlow": True, b"glowStyle": 4,
                                  b"glowColor": b"d9b454", b"requireSpell1": cast}
            for spec_spells in TARGET_DOTS.values() for aura, cast in spec_spells}
    specs = {spec: {b"c3": [f"d{aura}".encode() for aura, _ in spec_spells]}
             for spec, spec_spells in TARGET_DOTS.items()}
    lists = {b"v": 1, b"specs": specs, b"hidden": {}, b"replace": {}, b"shared": {}}
    spells = {b"v": 1, b"e": dots, b"s": {}}
    put(config, listsData=encode(lists, FRAME_PREFIX), spellsData=encode(spells, FRAME_PREFIX),
        c3_on=True, c3_name="Target DoTs", c3_kind=2, c3_shareContents=False,
        c3_anchor=2, c3_side=2, c3_align=1, c3_gap=60, c3_x=0, c3_y=0,
        c3_size=24, c3_perRow=6, c3_maxIcons=6, c3_keepSlots=True, c3_showMissing=False)


def steady_cooldown_icons(entries):
    cooldowns = entries[b"cooldownManager"]
    # Keep the spell texture bright when usability or range changes.
    for slot in ("ess", "uti", "def", "ext", "c1", "c2", "c3", "c4", "c5", "c6"):
        put(cooldowns, **{f"{slot}_usable": False, f"{slot}_range": False})
    put(entries.setdefault(b"hudVisibility", {}), cooldownManager=False)


def action_bars(config):
    put(config, enabled=True, look=4, buttonShape=1, borderArt=1, iconSkin="CUSTOM",
        borderSize=1, borderColor="0b0b0b", borderClassColor=False, mediaBorder="",
        slotColor="090909", slotAlpha=100, iconZoom=8, masque=False,
        keybindColor="ffffff", macroColor="dedede", countColor="ffffff", cooldownColor="ffffff")
    for slot, (x, y) in enumerate(((-138, 25), (138, 25), (-138, 2), (138, 2)), 1):
        put(config, **{f"bar{slot}{key}": value for key, value in dict(
            Visibility=1, Point=8, X=x, Y=y, Size=22, Spacing=1, Rows=1,
            Buttons=12, Keybind=True, KeybindSize=9, Macro=True, MacroSize=8,
            CooldownSize=11, CountSize=10, Background=False).items()})


def meters(config):
    # Damage spans the full panel. Healing and deaths share the other column.
    put(config, enabled=True, windowCount=3, w1Width=150, w2Width=150, w3Width=150,
        w1Height=160, w2Height=52, w3Height=107, w1X=-152, w2X=-2, w3X=-2,
        w1Y=2, w2Y=2, w3Y=55, w1Type=1, w2Type=10, w3Type=3,
        w1Session=1, w2Session=1, w3Session=1, w1AnchorWindow=1,
        w2AnchorWindow=2, w2AnchorSide=3, w2AnchorGap=0,
        w3AnchorWindow=3, w3AnchorSide=2, w3AnchorGap=1,
        headerHeight=15, headerOutside=False, headerMouseover=True, headerButtonStyle=2,
        headerSelectors=False, headerTimer=False, headerAlpha=100,
        overallTitlePrefix=False, titleOffsetX=2, barHeight=17, barSpacing=1,
        leftSize=11, rightSize=11, titleSize=11, barTexture="Solid", bgAlpha=78,
        gradientEnabled=False, numberFormat=1, englishNumbers=True)


def panels(entries):
    put(entries[b"chat"], enabled=True, windowWidth=294, windowHeight=157,
        windowX=5, windowY=5, lockWindowPosition=True, lockWindowSize=True,
        padding=3, panelAlpha=74, fontSize=11, tabFontSize=11,
        borderColor="000000", borderSize=1, borderAlpha=100, borderTexture="",
        tabPanel=True, tabHeight=18, tabPanelGap=0, tabAccent=False, tabClassColor=False,
        headerToolbar=False, tabIndividualPanels=False, hideTabArt=True, panelGradient=False,
        tabActiveColor="f1f1ed", tabInactiveColor="a9aba8",
        inputPushMessages=True, inputAnimationDuration=0.18, inputHeight=32, inputY=38)
    put(entries[b"announcements"], enabled=True, anchor=1, x=0, y=-132,
        scale=75, duration=3, titleSize=22, subtitleSize=14, subtitleOffsetY=32,
        showBoxArt=False, showFrame=False, backgroundOpacity=0, levelClean=False)
    put(entries.setdefault(b"runSummary", {}), enabled=False)
    put(entries.setdefault(b"buffReminders", {}), enabled=True, anchorTarget="", point=2, x=0, y=-208)
    put(entries.setdefault(b"bnetToast", {}), enabled=True, moved=True, point=7, x=22, y=212, look=3)
    put(entries.setdefault(b"mapLandingShortcuts", {}), enabled=True, size=24, offsetX=4, offsetY=24)
    tooltip = entries.setdefault(b"tooltipAppearance", {})
    put(tooltip, enabled=True, configured=True, itemTooltipStyle="card")
    put(tooltip.setdefault(b"tooltipLayout", {}), preset="custom",
        itemStyle="custom", spellStyle="custom", unitStyle="custom",
        questStyle="custom", lootStyle="custom", lootSurface="match",
        cardSurface="unified", iconSize=24, height=40, x=8, rule=True,
        palette=True, paletteGradient=False,
        fillColor=[0.035, 0.039, 0.039, 0.98], endColor=[0.035, 0.039, 0.039, 0.98],
        titleColor=[0.945, 0.945, 0.929, 1], accentColor=[0.64, 0.65, 0.61, 0.85],
        borderMode="custom", borderWidth=1, borderColor=[0.22, 0.23, 0.22, 1])
    put(entries[b"targetDistance"], enabled=False)
    put(entries[b"actionTracker"], enabled=True, displayPreset=2, growth=3,
        rows=5, rowHeight=26, rowGap=0, scale=100, anchorTarget=2, point=9, x=-173, y=162,
        hideAfter=15, pauseInCombat=True, glossEnabled=False)
    put(entries[b"battleRes"], enabled=True, textOnly=True, textFormat=2, visibility=2,
        fontSize=11, width=86, height=16, anchorTarget=2, point=7, x=5, y=181)
    put(entries[b"groupRaidShortcuts"], enabled=True, showPanel=True, panelCompact=True,
        panelPoint=2, panelX=-300, panelY=0, panelScale=100)
    put(entries[b"minimap"], enabled=True, size=168, x=-2, y=-2,
        borderColor="242424", buttonMailX=29, buttonMailY=-2,
        showLanding=1, landingX=2, landingY=34,
        queueStatusEnabled=True, queueStatusHidden=False, queueStatusSize=26,
        queueStatusX=147, queueStatusY=-50,
        infoLocation=False, infoClockAnchor=7,
        infoClockX=12, infoClockY=3, infoClockWidth=56, infoClockSize=10,
        infoFPSAnchor=9, infoFPSX=-49, infoFPSY=3, infoFPSWidth=40, infoFPSSize=10,
        infoLatencyAnchor=9, infoLatencyX=-6, infoLatencyY=3, infoLatencyWidth=40, infoLatencySize=10)
    put(entries[b"playerAuras"], enabled=True, iconWidth=24, iconHeight=24, perRow=12,
        spacing=1, rowSpacing=1, x=15, y=0, debuffX=-15, debuffOffset=138,
        debuffIconWidth=28, debuffIconHeight=28, timerAnchor=2, fontSize=10,
        buffSkin="CUSTOM", debuffSkin="CUSTOM", borderSize=1, borderColor="242424")
    put(entries[b"objectives"], enabled=True, x=-2, y=-211, width=220,
        titleSize=12, sectionSize=11, entrySize=11, objectiveSize=11)


def nameplates(config):
    # Only the cosmetic options of the native Blizzard skin belong here.
    put(config, enabled=True, look=3, nativeStyle=2, nativeSize=3, targetScaleEnabled=False,
        nativeHealthFillTexture="Solid", nativeHealthBackgroundTexture="Solid",
        nativeCastFillTexture="Solid", nativeCastBackgroundTexture="Solid",
        nativeCastFillColor="a62e33", nativeCastLockedColor="676767",
        enemyTextMode=4, enemyTextEnabled=True,
        enemyNameSize=10, enemyHealthTextSize=10, enemyCastSize=10,
        enemyBorderSize=1, enemyBorderColor="262626", enemyTargetMarker=False,
        highlightTarget=True, highlightFocus=False, highlightBorderSize=1,
        selectionBorder=2, selectionTargetColor="ffffff",
        enemyRoleColors=True, enemyColorsInDungeons=True, enemyColorsOutside=True,
        enemyMeleeEnabled=True, enemyMeleeColor="4e498d", enemyCasterEnabled=True,
        enemyCasterColor="466782", enemyMinibossEnabled=True, enemyMinibossColor="6050ab",
        enemyBossEnabled=True, enemyBossColor="8a536b", enemyTrivialEnabled=True,
        enemyTrivialColor="7d5a58", enemyNeutralEnabled=True, enemyNeutralColor="8b8056",
        classColors=2, friendlyNameClassColor=2, enemyNameColorEnabled=False,
        neutralNameColorEnabled=False, friendlyNameColorEnabled=False,
        enemyCastHeight=16, enemyCastIconSize=16, enemyCastSpellIcon=True,
        enemyCastSpellTarget=True, auraScaleMode=2, auraScalePercent=80)


def modules():
    envelope = decode(literal(DARK_RAID, "Suite.DarkRaidModuleCompact"), SUITE_PREFIX)
    profile = envelope[b"profile"]
    profile[b"nameplateShared"] = {b"version": 1, b"nameplates": NAMEPLATE_NAMES}
    suite = profile[b"suite"]
    entries = suite[b"modules"]
    cooldowns(entries[b"cooldownManager"])
    steady_cooldown_icons(entries)
    action_bars(entries[b"actionbars"])
    suite[b"moduleLooks"][b"actionbars"] = suite[b"globalLook"]
    meters(entries[b"damageMeter"])
    panels(entries)
    nameplates(entries[b"nameplates"])
    for config in entries.values():
        for key, value in config.items():
            if isinstance(value, bytes) and (key == b"font" or key.endswith(b"Font") or key.startswith(b"bubbleFont")):
                config[key] = b""
    for role in ("keybind", "macro", "count", "cooldown"):
        put(entries[b"actionbars"], **{f"{role}FontOverride": False})
    for role in ("names", "values", "header", "details", "timer"):
        put(entries[b"damageMeter"], **{f"{role}FontCustom": False})
    return encode(envelope, SUITE_PREFIX)


def forever_profiles(source):
    frames, modules, skin = source.read_text(encoding="utf-8-sig").strip().splitlines()
    if not frames.startswith("MSUFS3:MSUF3:"):
        raise ValueError("Expected a complete Pre-Midnight export")
    profile = decode(modules, SUITE_PREFIX)
    if profile[b"addon"] != b"MSUF_Suite" or profile[b"client"] != b"forever":
        raise ValueError("Expected a Suite profile exported on Forever")
    steady_cooldown_icons(profile[b"profile"][b"suite"][b"modules"])
    skin_profile = decode(skin, "MSKIN1:")
    forever_skin = decode(literal(CORE / "ForeverFactory.lua", "Suite.ForeverFactorySkinCompact"), "MSKIN1:")
    menu = forever_skin[b"payload"][b"icons"][b"microMenu"]
    # Clear the meter and its Action Tracker, keeping the horizontal Forever bar.
    put(menu, visibility="always", layoutX=-2, layoutY=206)
    skin_profile[b"payload"][b"icons"][b"microMenu"] = menu
    return frames.removeprefix("MSUFS3:"), encode(profile, SUITE_PREFIX), encode(skin_profile, "MSKIN1:")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--export-dir", type=Path)
    parser.add_argument("--forever-source", type=Path, help="Build the Forever layout from an authored MSUFS3 bundle")
    args = parser.parse_args()
    if args.forever_source:
        frames_text, modules_text, skin_text = forever_profiles(args.forever_source)
        write(CORE / "PreMidnightForeverFactory.lua", "local _, Suite = ...\n"
              "-- Pre-Midnight layout authored on WoW Forever.\n"
              "if not Suite.Client.isForever then return end\n"
              f"Suite.PreMidnightForeverFramesCompact = [[{frames_text}]]\n"
              f"Suite.PreMidnightForeverModuleCompact = [[{modules_text}]]\n"
              f"Suite.PreMidnightForeverSkinCompact = [[{skin_text}]]\n", args.check)
        if args.export_dir:
            args.export_dir.mkdir(parents=True, exist_ok=True)
            (args.export_dir / "Pre-Midnight-Forever.txt").write_text(
                "MSUFS3:" + "\n".join((frames_text, modules_text, skin_text)) + "\n", encoding="ascii")
        return
    frame_profile, suite_profile = frames(), modules()
    write(CORE / "PreMidnightFactory.lua", "local _, Suite = ...\n"
          "-- Optional Pre-Midnight layout for the full Suite installer.\n"
          + assignment("Suite.PreMidnightFramesCompact", frame_profile)
          + assignment("Suite.PreMidnightModuleCompact", suite_profile), args.check)
    if args.export_dir:
        args.export_dir.mkdir(parents=True, exist_ok=True)
        skin = literal(DARK_RAID, "Suite.DarkRaidSkinCompact")
        bundle = "MSUFS3:" + "\n".join((frame_profile, suite_profile, skin))
        (args.export_dir / "Pre-Midnight-Komplett.txt").write_text(bundle + "\n", encoding="utf-8")
        for label, profile in (("Core", frame_profile), ("Suite", suite_profile), ("Skin", skin)):
            (args.export_dir / f"Pre-Midnight-{label}.txt").write_text(profile + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
