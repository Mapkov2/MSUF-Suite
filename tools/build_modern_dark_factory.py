"""Build the opt-in Modern Dark design from the existing authored factories.

Only bundled profile data changes. Runtime ownership, native nameplates and
the user's active profiles stay with their existing owners.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import textwrap
from pathlib import Path

from build_forever_factory_preview import decode, encode

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "MSUF_Suite/Core"
FRAME_PATH = "MidnightSimpleUnitFrames_Options/State/MSUF_Defaults_ModernDark.lua"
FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf"


def literal(path, name):
    source = path.read_text(encoding="utf-8-sig")
    block = source.split(name + " =", 1)[1]
    block = re.split(r"\n(?:Suite|MSUF)\.", block)[0]
    return "".join(re.findall(r"\[\[(.*?)\]\]", block, re.S))


def put(target, **values):
    for key, value in values.items():
        target[key.encode()] = value.encode() if isinstance(value, str) else value


def canonical_auras(classic):
    """Materialize current lane owners through the shipped defaults, not legacy exports."""
    lua = os.environ.get("MSUF_LUA51") or shutil.which("lua") or (
        r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
    source = r'''
local root = arg[1]
local world = assert(loadfile(root .. "/tools/tests/client_world.lua"))().New(root, "Mainline")
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
local function String(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
        if char == '\\' then return '\\\\' end
        if char == '"' then return '\\"' end
        return string.format('\\u%04x', char:byte())
    end) .. '"'
end
local function JSON(value)
    local kind = type(value)
    if kind == "string" then return String(value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    assert(kind == "table", "unsupported canonical value")
    local count, array, out = 0, true, {}
    for key in pairs(value) do count = count + 1; array = array and type(key) == "number" end
    array = array and count > 0 and count == #value
    if array then for index = 1, count do out[index] = JSON(value[index]) end
    else for key, entry in pairs(value) do
        out[#out + 1] = String((type(key) == "number" and "n:" or "s:") .. tostring(key)) .. ":" .. JSON(entry)
    end end
    return (array and "[" or "{") .. table.concat(out, ",") .. (array and "]" or "}")
end
io.write(JSON(world.env.MSUF_CreateCanonicalUnitAuras()))
'''
    result = subprocess.run([lua, "-", str(classic)], input=source, text=True,
                            capture_output=True, check=True)
    def byte_strings(value):
        if isinstance(value, str): return value.encode()
        if isinstance(value, dict):
            return {(int(k[2:]) if k.startswith("n:") else k[2:].encode()): byte_strings(v)
                    for k, v in value.items()}
        if isinstance(value, list): return [byte_strings(v) for v in value]
        return value
    return byte_strings(json.loads(result.stdout))


def frames(classic):
    base = classic / "MidnightSimpleUnitFrames/State/Defaults/MSUF_Defaults_Shell.lua"
    envelope = decode(literal(base, "MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT"), "MSUF3:")
    # MSUF imports the lossless msuf6 snapshot when a Wago wrapper contains
    # both payloads. Publish one canonical snapshot, so preview and import
    # cannot select different layouts.
    full = envelope.get(b"msuf6", envelope)
    envelope = {b"addon": b"MSUF", b"fmt": 2, b"schema": full[b"schema"],
                b"kind": b"all", b"profile": b"Modern Dark", b"payload": full[b"payload"]}
    db = envelope[b"payload"]
    put(db[b"general"], barMode="dark", useClassColors=False, darkMode=True,
        darkBarR=.025, darkBarG=.031, darkBarB=.035, darkBgCustomColor=True,
        barBgColorMode="custom", barBgMatchHPColor=False, barBgClassColor=False,
        classBarBgR=.07, classBarBgG=.08, classBarBgB=.09, classBarBgA=1,
        barTexture="Solid", castbarTexture="Solid", castbarBackgroundTexture="Solid",
        enableGradient=False, enableHealthGradient=True, enablePowerGradient=False,
        healthGradientLowR=.70, healthGradientLowG=.025, healthGradientLowB=.025,
        healthGradientMidR=.025, healthGradientMidG=.031, healthGradientMidB=.035,
        healthGradientHighR=.025, healthGradientHighG=.031, healthGradientHighB=.035,
        fontKey=FONT, fontSize=16, nameFontSize=18, hpFontSize=18, powerFontSize=14,
        powerColorMode="static", powerBarColorR=.10, powerBarColorG=.43, powerBarColorB=.42,
        nameClassColor=True, nameNpcClassColor=False, npcTypeColorText=True,
        nameColorMode="DEFAULT", textBackdrop=False, fontShadowOpacity=1,
        barOutlineColorR=0, barOutlineColorG=0, barOutlineColorB=0, barOutlineColorA=1,
        anchorToCooldown=True, anchorName="EssentialCooldownViewer", playerCastbarOverrideMode="CLASS")
    bars = db[b"bars"]
    # Essence has a white native fallback. The reference uses muted teal
    # segments; other class resources keep their class-specific defaults.
    db[b"general"][b"classPowerColorOverrides"] = {b"ESSENCE": [.2, 147 / 255, 127 / 255]}
    put(bars, roundedFramesEnabled=False, roundedUnitFrames=False, roundedGroupFrames=False,
        slantedUnitFrames=False, slantedGroupFrames=False, barOutlineThickness=1,
        barOutlineTexture="", showBarBorder=True, barBackgroundAlpha=84,
        powerBarHeight=4, roundedPowerBars=False, classPowerHeight=10, classPowerGap=3, classPowerOutline=1,
        classPowerAnchorToCooldown=True, classPowerCooldownTopAnchor=True,
        classPowerWidthMode="custom", classPowerWidth=392, detachedPowerBarWidthMode="manual",
        classPowerOffsetX=0, classPowerOffsetY=0, classPowerBgAlpha=1,
        classPowerEmptyAlpha=.30, classPowerFilledAlpha=1, classPowerTexture="Solid",
        classPowerBgTexture="Solid", detachedPowerBarOutline=1)
    for key in (b"player", b"target", b"focus", b"boss", b"arena", b"pet", b"targettarget"):
        config = db.get(key)
        if not isinstance(config, dict): continue
        put(config, healthColorMode="GRADIENT", portraitMode="OFF", barTexture="Solid",
            showName=True, nameClassColor=True, showLevelIndicator=False, nameFontSize=14,
            nameColorMode="DEFAULT", fontKey=FONT, hpFontSize=13, powerFontSize=11,
            textBackdrop=False, hpBarAlpha=.94, hpBgAlpha=.84, hlOverride=False,
            nameTextAnchor="TOPLEFT", nameOffsetX=7, nameOffsetY=-5,
            hpOffsetX=-7, hpOffsetY=-5, textRight="PERCENT", textLeft="NONE",
            textCenter="NONE", powerTextRight="CURPERCENT", powerOffsetY=5,
            reverseFillBars=False, verticalFillBars=False, frameBarShape="SQUARE")
    # The 1440p close-up and 1080p combat image have the same 340:54
    # silhouette. Names/percentages straddle its upper edge; current health
    # and power occupy the inner row, mirrored on the target. Use the host's
    # existing CDM edge anchors so this entire center group stays together.
    for key, x in ((b"player", -40), (b"target", 40)):
        put(db[key], width=340, height=54, point="CENTER", relativePoint="CENTER",
            offsetX=x, offsetY=12, anchorFrameName="EssentialCooldownViewer", cooldownAnchorFrameTop=True,
            nameFontSize=18, hpFontSize=18, powerFontSize=14,
            hpTextLeftFontSize=20, hpTextRightFontSize=20, hpTextCenterFontSize=16,
            showPowerText=True, textCenter="CURRENT", directTextLayout=True, directNameWidth=248,
            fontOverride=True, powerTextColorByType=False,
            detachedPowerBarTextOnBar=False, directNameRelativePoint="TOPLEFT" if key == b"player" else "TOPRIGHT",
            directNamePoint="BOTTOMLEFT" if key == b"player" else "BOTTOMRIGHT",
            directNameOffsetX=6 if key == b"player" else -10, directNameOffsetY=-4,
            directHealthCenterRelativePoint="TOPRIGHT" if key == b"player" else "TOPLEFT",
            directHealthCenterPoint="TOPRIGHT" if key == b"player" else "TOPLEFT",
            directHealthCenterOffsetX=-10 if key == b"player" else 12, directHealthCenterOffsetY=-18)
        put(db[key], portraitMode="LEFT" if key == b"player" else "RIGHT",
            portraitRender="2D", portraitShape="SQUARE", portraitPlacement="OVERLAY",
            portraitOverlayAlign="CENTER", portraitSizeMode="SEPARATE",
            portraitWidth=112, portraitHeight=52, portraitLevelOffset=2,
            portraitAlpha=28, portraitBgEnabled=False, portraitBorderStyle="NONE")
        db[key].pop(b"anchorToUnitframe", None)
        for field in (b"_screenRefH", b"screenPositionMode", b"screenPositionHeight"):
            db[key].pop(field, None)
    put(db[b"player"], textLeft="NONE", textRight="PERCENT",
        powerTextLeft="PERCENT", powerTextRight="NONE", powerTextCenter="NONE",
        directHealthRightPoint="BOTTOMRIGHT", directHealthRightRelativePoint="TOPRIGHT",
        directHealthRightOffsetX=-10, directHealthRightOffsetY=-4,
        directPowerLeftPoint="TOPLEFT", directPowerLeftRelativePoint="TOPLEFT",
        directPowerLeftOffsetX=12, directPowerLeftOffsetY=-18)
    db[b"player"][b"directPowerLeftColor"] = [.28, .55, .78, 1]
    put(db[b"target"], textLeft="PERCENT", textRight="NONE", nameTextAnchor="TOPRIGHT",
        powerTextLeft="NONE", powerTextRight="PERCENT", powerTextCenter="NONE",
        directHealthLeftPoint="BOTTOMLEFT", directHealthLeftRelativePoint="TOPLEFT",
        directHealthLeftOffsetX=8, directHealthLeftOffsetY=-4,
        directPowerRightPoint="TOPRIGHT", directPowerRightRelativePoint="TOPRIGHT",
        directPowerRightOffsetX=-12, directPowerRightOffsetY=-18)
    db[b"target"][b"directPowerRightColor"] = [.28, .55, .78, 1]
    put(db[b"player"], powerBarDetached=True, detachedPowerBarAnchorToClassPower=True,
        detachedPowerBarSyncClassPower=True, detachedPowerBarAnchorMode="CENTER",
        detachedPowerBarOffsetX=0, detachedPowerBarOffsetY=-4, detachedPowerBarHeight=10, detachedPowerBarWidth=392)
    # Small companion frames sit below the outer ends, not in the resource row.
    for key, owner, point in ((b"pet", "player", "TOPLEFT"), (b"targettarget", "target", "TOPRIGHT")):
        put(db[key], width=138, height=16, anchorFrameName="", anchorToUnitframe=owner,
            point=point, relativePoint=point.replace("TOP", "BOTTOM"), offsetX=0, offsetY=-68,
            nameTextAnchor=point, nameOffsetX=4, nameOffsetY=14, nameFontSize=14,
            showHP=False, showPowerText=False, showPowerBar=False,
            textLeft="NONE", textCenter="NONE", textRight="NONE")
    for key in (b"focus", b"boss", b"arena"):
        if isinstance(db.get(key), dict): put(db[key], anchorFrameName="UIParent")
    # Target cast: full frame width, directly underneath, square spell icon
    # outside its right edge. RIGHT includes the icon in the owner's width.
    put(db[b"general"], castbarTargetDetached=False, castbarTargetMatchWidth=False,
        castbarTargetBarWidth=392, castbarTargetBarHeight=28,
        castbarTargetOffsetX=-1, castbarTargetOffsetY=-88,
        castbarTargetIconPosition="RIGHT", castbarTargetIconSize=48,
        castbarTargetIconSpacing=4, castbarTargetIconOffsetY=10,
        castbarTargetIconBorderThickness=1, castbarTargetTimeFormat="CURRENT_MAX")
    for key in (b"gf_party", b"gf_raid", b"gf_mythicraid", b"gf_priority"):
        config = db.get(key)
        if isinstance(config, dict):
            put(config, gfBarMode="dark", healthColorMode="DARK", gfDarkR=.025,
                gfDarkG=.031, gfDarkB=.035, portraitMode="OFF", nameColorMode="CLASS",
                borderEnabled=True, borderSize=1, borderR=0, borderG=0, borderB=0,
                fontKey=FONT, nameFontSize=12, hpFontSize=11, powerHeight=4)
    db.pop(b"auras2", None)
    db[b"auras3"] = canonical_auras(classic)
    put(db[b"auras3"], showPlayer=True, showTarget=True)
    # The default defensive container occupies the upper inner corner, where
    # this layout displays health percent. Keep those buffs in the normal row.
    defensive = db[b"auras3"][b"customContainers"][b"perUnit"][b"player"][b"items"][4]
    put(defensive, enabled=False, autoBlacklistPlayerBuffs=False)
    for owner in db[b"auras3"][b"perUnit"].values():
        layout = owner.get(b"layout", {})
        put(layout, buffGroupIconSize=52, debuffGroupIconSize=52, buffIconHeightPercent=50, debuffIconHeightPercent=50, buffSpacing=4, debuffSpacing=4,
            buffCooldownTextSize=12, debuffCooldownTextSize=12,
            buffStackTextSize=11, debuffStackTextSize=11)
    for key in (b"player", b"target"):
        owner = db[b"auras3"][b"perUnit"][key]
        put(owner, overrideLayout=True, overrideStyle=True, overrideSharedLayout=True, overrideFilters=True)
        put(owner[b"layout"], buffAnchor="TOPLEFT", debuffAnchor="TOPLEFT",
            buffGroupOffsetX=0, debuffGroupOffsetX=0,
            buffGroupOffsetY=46 if key == b"player" else 80,
            debuffGroupOffsetY=80 if key == b"player" else 46)
        put(owner[b"layoutShared"], buffPerRow=6, debuffPerRow=6, maxBuffs=6, maxDebuffs=6,
            buffGrowthX="RIGHT", debuffGrowthX="RIGHT", buffGrowthY="DOWN", debuffGrowthY="DOWN")
    return encode(envelope, "MSUF3:")


def modules():
    envelope = decode(literal(CORE / "RetailProfile.lua", "Suite.RetailProfileModuleCompact"), "MSUFM1:MSUF3:")
    profile = envelope[b"profile"][b"suite"]
    entries = profile[b"modules"]
    # Keep the existing look's per-module customization records. This is a
    # full layout with its own authored colors, like the other bundled layouts.
    for config in entries.values():
        if b"font" in config: config[b"font"] = FONT.encode()
    cd = entries[b"cooldownManager"]
    put(cd, listsData="", spellsData="", ess_x=0, ess_y=-310, ess_size=36,
        ess_perRow=8, uti_size=30, uti_perRow=10, uti_x=0, uti_y=0, uti_gap=12,
        buf_size=28, buf_perRow=10, buf_x=0, buf_y=0, buf_gap=3, buf_side=1, def_side=1, def_align=3, def_gap=6, def_x=0, def_y=0, ext_side=1, ext_align=2, ext_gap=2, ext_x=1, ext_y=1)
    for prefix in ("ess", "uti", "def", "ext", "buf", "c1", "c2", "c3", "c4", "c5", "c6"):
        put(cd, **{prefix + "_height": 100, prefix + "_spacing": 3,
                   prefix + "_border": 1, prefix + "_borderColor": "080b0d",
                   prefix + "_zoom": 6})
    plates = entries[b"nameplates"]
    # Native Legacy supplies thin bars and reaction-colored names. Only the
    # two native header regions are mirrored; combat/casts/auras stay native.
    for key in plates:
        if key.endswith((b"OffsetX", b"OffsetY")): plates[key] = 0
    put(plates, look=3, nativeStyle=7, nativeSize=4, barGeometry=2,
        enemyTextMode=2, enemyMirrorHeader=True, enemyRoleColors=False, enemyQuestColors=False,
        selectionBorder=3, selectionDim=3,
        enemyHealthWidthDelta=10, enemyHealthHeightDelta=0, enemyNameSize=16, enemyHealthTextSize=16,
        enemyNameFont=FONT, enemyCastFont=FONT, friendlyNameFont=FONT,
        enemyTargetMarker=True, enemyTargetStyle=10, enemyTargetLayout=2,
        enemyTargetMarkerSize=16, enemyTargetColor="33bfff", enemyTargetOffsetX=0, enemyTargetOffsetY=0,
        enemyBorderEnabled=True, enemyBorderSize=1, enemyBorderColor="000000",
        enemyLevelEnabled=False, enemyEliteMarker=False, enemyQuestMarker=False,
        enemyCastSize=14, enemyCastTextEnabled=True, enemyCastTimeEnabled=True,
        enemyCastHeight=28, enemyCastIconSize=40, enemyCastTimeFormat=2,
        enemyCastEnabled=2, enemyCastDisplay=2, enemyCastSpellName=True,
        enemyCastSpellIcon=True, enemyCastSpellTarget=False,
        enemyCastIconOffsetX=262, enemyCastIconOffsetY=34,
        enemyCastShieldOffsetX=262, enemyCastShieldOffsetY=34,
        enemyCastTextOffsetX=-38, enemyCastTextOffsetY=34,
        enemyCastTimeOffsetX=-100, enemyCastTimeOffsetY=0)
    ab = entries[b"actionbars"]
    put(ab, borderSize=1, borderColor="080b0d", bar1X=0, bar1Y=176,
        bar2X=0, bar2Y=212, bar1Size=48, bar2Size=48, bar1HeightPercent=67, bar2HeightPercent=67,
        bar1Spacing=4, bar2Spacing=4,
        bar1Point=8, bar2Point=8, bar1Visibility=1, bar2Visibility=1,
        bar3Point=9, bar3X=-640, bar3Y=12, bar3Size=28, bar3Rows=6, bar3Buttons=6,
        bar4Point=8, bar4X=0, bar4Y=130, bar4Size=36, bar4HeightPercent=89, bar4Spacing=2, bar4Rows=1,
        bar4Buttons=12, bar4Vertical=False, bar4Visibility=1,
        bar5Visibility=6, bar1Background=True, bar2Background=True,
        bar1BackgroundColor="080b0d", bar2BackgroundColor="080b0d",
        bar1BackgroundAlpha=80, bar2BackgroundAlpha=80)
    for index in range(1, 6):
        put(ab, **{f"bar{index}ShowEmpty": False, f"bar{index}Keybind": False,
                   f"bar{index}Macro": False})
    meter = entries[b"damageMeter"]
    put(meter, look=4, windowCount=1, w1Width=620, w1Height=250, w1X=-12, w1Y=32,
        bgColor="080b0d", bgAlpha=60, borderColor="000000", borderSize=2,
        classColors=True, barAlpha=100, barHeight=26, barSpacing=2, w1Type=1,
        headerOutside=True, headerSelectors=False, headerMouseover=False,
        headerHeight=38, headerIconSize=30, headerAlpha=0,
        leftSize=18, rightSize=18, titleSize=20, refreshRate=1.5)
    # General HUD tooltips grow upward from above the meter's outside header.
    put(entries[b"tooltipDetails"], enabled=True, anchor=3, growth=1,
        fixedX=-12, fixedY=340, inspectHovered=False)
    chat = entries[b"chat"]
    put(chat, look=4, panelColor="080b0d", panelAlpha=55, borderColor="000000",
        borderSize=2, borderAlpha=100, accentColor="58b9b0", tabActiveColor="479a94", tabClassColor=True,
        tabInactiveColor="a5a5a5", fontSize=20, fontOutline=2, tabFontSize=20,
        tabPanel=False, sidebarPanel=False, hideNativeButtons=True, inputColor="080b0d", inputAlpha=85,
        lockWindowSize=True, windowWidth=600, windowHeight=240, padding=10, completeMessages=True, hideTabArt=True, tabAccent=False,
        lockWindowPosition=True, windowX=22, windowY=42)
    put(entries[b"minimap"], stylePreset=1, shape=1, size=240, point=3, x=-16, y=-16,
        borderColor="000000", borderSize=2, borderAlpha=100, borderClassColor=False, shadowSize=0,
        styleGlow=False, styleBackdrop=True, styleBackdropColor="16191b", styleBackdropAlpha=100,
        styleBackdropPadding=6, infoLocationSource=4, infoLocationColor="62cce8",
        infoLocation=True, infoLocationAnchor=2, infoLocationX=0, infoLocationY=4,
        infoLocationSize=18, infoLocationFont=FONT, infoLocationZoneColor=False,
        infoClock=True, infoClockAnchor=8, infoClockX=0, infoClockY=14, infoClockSize=24,
        infoClockFont=FONT, infoClockColor="ffffff", infoClockBox=1,
        infoFPS=False, infoLatency=False, infoCoordinates=False, infoDurability=False,
        middleClick=5, dungeonButton=True, dungeonStyle=2, dungeonWidth=48, dungeonHeight=26, dungeonAnchor=1, dungeonX=8, dungeonY=-16, outerBorderSize=2, outerBorderGap=4, outerBorderColor="000000",
        showCalendar=False, showTracking=False, showCrafting=False, showCompartment=False,
        drawerMouseover=True, zoomButtons=3, infoCalendarDay=True, infoCalendarDaySize=18,
        infoCalendarDayAnchor=3, infoCalendarDayX=-24, infoCalendarDayY=-30,
        infoCalendarDayClassColor=True, infoCalendarDayFont=FONT)
    entries[b"playerAuras"] = {}
    put(entries[b"playerAuras"], enabled=True, iconWidth=52, iconHeight=26, perRow=12,
        spacing=4, rowSpacing=8, x=-12, y=0, borderSize=2, borderColor="000000",
        font=FONT, fontSize=16, showDuration=True)
    put(entries[b"objectives"], x=-12, y=-450, width=400, showHeader=False, groupUnderlines=True,
        colorStyle=2, textColor="f2cc30", campaignColor="f2cc30", questsColor="f2cc30",
        focusedColor="f2cc30", mutedColor="d6d8da", dividerColor="276b68",
        titleSize=18, sectionSize=18, entrySize=16, objectiveSize=14,
        questIconStyle=3, backgroundOpacity=0)
    # Oversized reminders at the top of the screen are not part of this
    # authored layout. The module remains available from its ordinary switch.
    put(entries[b"buffReminders"], enabled=False, size=36)
    put(entries[b"xpBar"], enabled=True, look=4, displayStyle=2, width=560, height=14,
        point=2, x=0, y=-12, customFill="9d14bd", customRested="668db8",
        customPanel="103b3d", customBorder="000000", customText="ffffff",
        separateTextColor=True, borderSize=2, hideBlizzard=True, hideBlizzardTracking=True, showSegments=False,
        showSession=False, showRate=False, showETA=False)
    put(entries[b"skyriding"], enabled=True, look=4, displayStyle=2, width=320,
        panelColor="080b0d", borderColor="080b0d", trackColor="191f23",
        accentColor="58b9b0", windColor="668db8", textColor="dce8e8",
        mutedColor="a9b7ba", thrillColor="e2c57c", barTexture="Solid", barHeight=7)
    dt = entries[b"dataTexts"]
    for key in dt:
        if b"LoadCond" in key: dt[key] = False
    for index, x, width, source, color in (
        (1, 0, 900, 27, "ff9b00"), (2, -200, 300, 13, "35e65b"), (3, 200, 220, 4, "f3d72d")):
        prefix = f"bar{index}"
        put(dt, **{prefix + "Enabled": True, prefix + "Point": 8,
            prefix + "Dock": 1, prefix + "X": x, prefix + "Y": 0,
            prefix + "Width": width, prefix + "Height": 24, prefix + "Visibility": 1,
            prefix + "Slot1": source, prefix + "Slot2": 1, prefix + "Slot3": 1, prefix + "Slot4": 1,
            prefix + "FullScreen": index == 1,
            prefix + "BackgroundEnabled": index == 1, prefix + "BorderEnabled": index == 1,
            prefix + "BackgroundColor": "080b0d", prefix + "BackgroundOpacity": 65,
            prefix + "BorderColor": "000000", prefix + "BorderSize": 1,
            prefix + "ShowLabels": index != 1, prefix + "PerformanceLabels": index == 2,
            prefix + "MemoryUnitColor": "28a6a1", prefix + "ColorMemoryUnit": True,
            prefix + "AccentEnabled": False, prefix + "SeparatorEnabled": False,
            prefix + "StyleOverride": True, prefix + "LabelColor": "e9ebed",
            prefix + "ValueColor": color, prefix + "CustomColors": True,
            prefix + "FontSize": 18, prefix + "Font": FONT, prefix + "TextOutline": 1})
    put(dt, enabled=True)
    return encode(envelope, "MSUFM1:MSUF3:")


def skin():
    envelope = decode(literal(CORE / "RetailSkinFactory.lua", "Suite.RetailFactorySkinCompact"), "MSKIN1:")
    db = envelope[b"payload"]
    # Preserve the accepted flat Modern Dark menu style independently of
    # changes to the Retail or Forever factory palettes.
    theme = db[b"theme"]
    put(theme, look="custom", preset="midnightDark", materialDepth=0,
        gradient=False, shellOpacity=.94, panelOpacity=.9, borderOpacity=.85)
    for role in ("accent", "accentAlt", "checkmark", "microIconPressed"):
        theme[b"colors"][role.encode()] = [.345, .725, .69, 1]
    for role in ("background", "ink", "input", "microBarFill"):
        theme[b"colors"][role.encode()] = [.031, .043, .051, .92]
    for role in ("border", "borderSoft", "rim", "microBarBorder"):
        theme[b"colors"][role.encode()] = [.06, .08, .09, .85]
    put(db[b"typography"], sharedMediaFont="MapkoSkin - Expressway")
    # Window geometry from the author's personal export does not belong to
    # this design. Native panels keep their saved positions and normal scale.
    put(db[b"icons"][b"microMenu"], preset="blizzard", layoutMode="owned", visibility="mouseover", orientation="horizontal", buttonsPerLine=14,
        positionPreset="custom", layoutPoint="BOTTOM", layoutRelativePoint="BOTTOM", layoutX=0, layoutY=44,
        barBackground=False, barBorder=0, barMaterial="theme", buttonBackground=False,
        buttonBorder=0, shape="global", radius=8, iconStyle="blizzard", buttonSize=32,
        iconSize=24, hoverStyle="off", tint="native", spacing=0, scale=1, padding=0,
        normalOpacity=1, hoverOpacity=1, pressedOpacity=1, disabledOpacity=1)
    db[b"windowControls"][b"positions"] = {}
    db[b"windowControls"][b"scales"] = {}
    return encode(envelope, "MSKIN1:")


def assignment(name, value):
    chunks = textwrap.wrap(value, 128)
    groups = [chunks[i:i + 32] for i in range(0, len(chunks), 32)]
    blocks = ["(\n        " + " ..\n        ".join("[[" + line + "]]" for line in group) + "\n    )" for group in groups]
    return name + " =\n    " + " ..\n    ".join(blocks) + "\n"


def write(path, text, check):
    data = text.replace("\n", "\r\n").encode()
    if check:
        if path.read_bytes() != data: raise SystemExit("Factory differs: " + str(path))
    else:
        path.write_bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--classic-root", type=Path, default=ROOT.parent / "MidnightSimpleUnitFrames")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    frame = frames(args.classic_root)
    header = "-- Opt-in Modern Dark design. Factory data is read only until explicitly installed.\n"
    write(args.classic_root / FRAME_PATH, "local _, MSUF = ...\n" + header
          + assignment("MSUF.MSUF_MODERN_DARK_PROFILE_COMPACT", frame), args.check)
    write(CORE / "ModernDarkFactory.lua", "local _, Suite = ...\n" + header
          + assignment("Suite.ModernDarkFramesCompact", frame)
          + assignment("Suite.ModernDarkModuleCompact", modules())
          + assignment("Suite.ModernDarkSkinCompact", skin()), args.check)
    print("Modern Dark frame, Suite and Skin factories " + ("match" if args.check else "written"))


if __name__ == "__main__":
    main()
