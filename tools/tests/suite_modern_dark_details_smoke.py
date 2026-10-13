"""Reference details must survive the real bundled profile envelopes."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_modern_dark_factory import literal
from build_forever_factory_preview import decode

root = Path(__file__).resolve().parents[2]
path = root / 'MSUF_Suite/Core/ModernDarkFactory.lua'
frames = decode(literal(path, 'Suite.ModernDarkFramesCompact'), 'MSUF3:')[b'payload']
modules = decode(literal(path, 'Suite.ModernDarkModuleCompact'), 'MSUFM1:MSUF3:')[b'profile'][b'suite'][b'modules']
skin = decode(literal(path, 'Suite.ModernDarkSkinCompact'), 'MSKIN1:')[b'payload']
micro = skin[b'icons'][b'microMenu']
assert micro[b'visibility'] == b'mouseover' and micro[b'iconStyle'] == b'blizzard' and micro[b'tint'] == b'native'
assert modules[b'xpBar'][b'hideBlizzardTracking'], 'native bottom progress chrome remains'
assert modules[b'chat'][b'tabPanel'] is False and modules[b'chat'][b'fontOutline'] == 2
assert modules[b'damageMeter'][b'headerOutside'] and not modules[b'damageMeter'][b'headerMouseover']
assert modules[b'dataTexts'][b'bar1FullScreen'] and modules[b'dataTexts'][b'bar1Slot1'] == 27
assert modules[b'playerAuras'][b'iconHeight'] * 2 == modules[b'playerAuras'][b'iconWidth']
assert modules[b'minimap'][b'infoClockAnchor'] == 8 and not modules[b'minimap'][b'infoFPS']
for unit in (b'player', b'target'):
    assert frames[unit][b'portraitPlacement'] == b'OVERLAY' and frames[unit][b'portraitMode'] != b'OFF'
    assert frames[b'auras3'][b'perUnit'][unit][b'layout'][b'buffIconHeightPercent'] == 50
print('Modern Dark reference details: all eight requested areas authored')

assert micro[b'orientation'] == b'horizontal' and micro[b'layoutY'] == 44
assert modules[b'chat'][b'completeMessages'] and modules[b'chat'][b'tabClassColor']
assert modules[b'chat'][b'windowY'] == 42 and modules[b'damageMeter'][b'w1Y'] == 32
assert modules[b'minimap'][b'outerBorderSize'] == 2 and modules[b'minimap'][b'outerBorderGap'] == 4
assert modules[b'minimap'][b'infoCalendarDay'] and modules[b'minimap'][b'infoCalendarDayClassColor']
mm = modules[b'minimap']
assert mm[b'dungeonButton'] and mm[b'dungeonY'] == -16 and mm[b'dungeonX'] == 8
assert mm[b'dungeonWidth'] == 48 and mm[b'dungeonHeight'] == 26 and mm[b'dungeonStyle'] == 2
assert mm[b'size'] == 240 and mm[b'x'] == -16 and mm[b'y'] == -16
assert mm[b'borderAlpha'] == 100 and mm[b'infoLocationSource'] == 4
assert mm[b'styleBackdrop'] and mm[b'styleBackdropColor'] == b'16191b'
assert mm[b'styleBackdropAlpha'] == 100 and mm[b'styleBackdropPadding'] == 6
assert skin[b'theme'][b'preset'] == b'midnightDark'
assert modules[b'chat'][b'hideTabArt']
assert modules[b'xpBar'][b'hideBlizzard']

cd = modules[b'cooldownManager']
assert cd[b'def_side'] == 1 and cd[b'def_align'] == 3 and cd[b'def_gap'] == 6

assert cd[b'ext_align'] == 2 and cd[b'ext_gap'] == 2 and cd[b'ext_x'] == 1 and cd[b'ext_y'] == 1
# Frozen menu style from the owner's accepted flat Modern Dark design.
import json
def plain(value):
    if isinstance(value, bytes): return value.decode('utf-8')
    if isinstance(value, dict): return {plain(k): plain(v) for k, v in value.items()}
    if isinstance(value, list): return [plain(v) for v in value]
    return value
golden = json.loads((root / 'tools/tests/modern_dark_menu_style_golden.json').read_text(encoding='utf-8'))
assert {key: plain(skin[key.encode()]) for key in ('theme', 'typography')} == golden, 'accepted flat menu style regressed'
