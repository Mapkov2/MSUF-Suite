"""Every micro button glyph cell holds art, and no client shows a cell twice.

MicroMenuVisual.lua maps each Micro Button to a cell of the line and bold
glyph atlases (16 cells of 128 x 128). The button lists come from
Adapters/MicroMenu.lua (Forever first, then Retail). An empty cell would
draw nothing; a cell two buttons of one client share shows the same icon
twice (Forever's Talents once showed the Adventure Guide's compass).
"""
from pathlib import Path
import re
import struct
import sys
import zlib

root = Path(sys.argv[1]) / 'MSUF_Suite_Skin'
visual = (root / 'Rendering/MicroMenuVisual.lua').read_text(encoding='utf-8')
cells_block = re.search(r'local ICON_CELLS = \{(.*?)\n\}', visual, re.S).group(1)
cells = {name: int(cell) for name, cell in re.findall(r'(\w+MicroButton) = (\d+)', cells_block)}
slots = int(re.search(r'local ICON_SLOTS = (\d+)', visual).group(1))
adapter = (root / 'Adapters/MicroMenu.lua').read_text(encoding='utf-8')
lists = re.search(r'local BUTTON_NAMES = NS\.Client\.isForever and \{(.*?)\} or \{(.*?)\}', adapter, re.S)
clients = {'Forever': re.findall(r'"(\w+)"', lists.group(1)), 'Retail': re.findall(r'"(\w+)"', lists.group(2))}


def rgba_rows(path):
    """Decodes an 8-bit RGBA, non-interlaced PNG into rows of bytes."""
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    at, idat, header = 8, b'', None
    while at < len(data):
        length, kind = struct.unpack_from('>I4s', data, at)
        body = data[at + 8:at + 8 + length]
        if kind == b'IHDR':
            header = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            idat += body
        at += 12 + length
    width, height, depth, color, _, _, interlace = header
    assert (depth, color, interlace) == (8, 6, 0), '%s is not 8-bit RGBA' % path.name
    raw, stride, rows, previous = zlib.decompress(idat), width * 4, [], bytearray(width * 4)
    for y in range(height):
        kind, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            left = line[x - 4] if x >= 4 else 0
            up, corner = previous[x], previous[x - 4] if x >= 4 else 0
            if kind == 1:
                line[x] = (line[x] + left) & 255
            elif kind == 2:
                line[x] = (line[x] + up) & 255
            elif kind == 3:
                line[x] = (line[x] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - corner
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - corner)
                line[x] = (line[x] + (left if pa <= pb and pa <= pc else up if pb <= pc else corner)) & 255
        rows.append(line)
        previous = line
    return width, height, rows


for atlas in ('MapkoSkinMicroGlyphsAtlas.png', 'MapkoSkinMicroGlyphsBoldAtlas.png'):
    width, height, rows = rgba_rows(root / 'Media/MicroMenu' / atlas)
    size = width // slots
    assert width == size * slots and height == size, '%s is not %d square cells' % (atlas, slots)
    for name, cell in sorted(cells.items()):
        assert 0 <= cell < slots, '%s points outside the atlas' % name
        covered = sum(1 for row in rows for x in range(cell * size, (cell + 1) * size) if row[x * 4 + 3] > 127)
        assert covered > 1000, '%s: the cell of %s (%d) holds no glyph' % (atlas, name, cell)

for client, names in clients.items():
    seen = {}
    for name in names:
        assert name in cells, '%s button %s has no glyph cell' % (client, name)
        assert cells[name] not in seen, '%s shows one glyph twice: %s and %s (cell %d)' % (
            client, seen[cells[name]], name, cells[name])
        seen[cells[name]] = name
print('Suite skin micro glyphs: %d cells, %d Forever and %d Retail buttons, each glyph once per client passed' % (
    len(set(cells.values())), len(clients['Forever']), len(clients['Retail'])))
