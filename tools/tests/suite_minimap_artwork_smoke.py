"""Check the shipped masks' format and visible geometry independently."""
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1]) / 'MSUF_Suite_Modules/Media/Minimap'
for shape in ('Square', 'Circle', 'Wide'):
    data = (root / (shape + '.tga')).read_bytes()
    width, height = struct.unpack_from('<HH', data, 12)
    assert data[:3] == bytes((0, 0, 2))
    assert (width, height, data[16], data[17]) == (128, 128, 32, 0x28)
    assert len(data) == 18 + width * height * 4
    def alpha(x, y):
        return data[18 + (y * width + x) * 4 + 3]
    assert alpha(64, 64) == 255
    if shape == 'Square':
        assert all(alpha(x, y) == 255 for x, y in ((0, 0), (127, 0), (0, 127), (127, 127)))
    else:
        assert alpha(0, 0) == alpha(127, 127) == 0
    if shape == 'Circle':
        assert alpha(64, 16) == 255 and alpha(16, 16) == 0
    if shape == 'Wide':
        assert alpha(64, 16) == 0 and alpha(0, 64) == 255
        assert 84 <= sum(alpha(64, y) > 127 for y in range(height)) <= 86
print('Minimap mask geometry and TGA format passed')

for name in ('ArcaneRing', 'EmberRing', 'AstralRing', 'SteelFrame', 'Halo'):
    data = (root / (name + '.tga')).read_bytes()
    width, height = struct.unpack_from('<HH', data, 12)
    assert data[:3] == bytes((0, 0, 2))
    assert (width, height, data[16], data[17]) == (256, 256, 32, 0x28)
    assert len(data) == 18 + width * height * 4
    alpha = data[21::4]
    assert alpha[128 * width + 128] == 0  # artwork leaves the map visible
    assert max(alpha) > 100 and sum(value > 0 for value in alpha) > 100
print('Minimap ornament TGA format and alpha geometry passed')
