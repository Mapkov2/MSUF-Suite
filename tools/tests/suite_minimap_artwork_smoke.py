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

data = (root / 'AntiqueScrollFrame.tga').read_bytes()
width, height = struct.unpack_from('<HH', data, 12)
assert data[:3] == bytes((0, 0, 2))
assert (width, height, data[16], data[17]) == (512, 512, 32, 0x28)
assert len(data) == 18 + width * height * 4
alpha = data[21::4]
assert alpha[256 * width + 256] == 0  # live terrain remains visible
assert max(alpha) == 255 and sum(value > 0 for value in alpha) > 10000
assert alpha[256 * width + 460] > 200  # the rolled parchment on the right
assert alpha[256 * width + 128] == 0  # no painted terrain in the opening
assert alpha[460 * width + 256] > 200  # lower torn paper edge
print('Antique Map scroll TGA format and transparent opening passed')

weather_root = Path(sys.argv[1]) / 'MSUF_Suite/Media/Weather'
for name in ('Clear', 'Rain', 'Snow', 'Sandstorm'):
    data = (weather_root / (name + '.tga')).read_bytes()
    width, height = struct.unpack_from('<HH', data, 12)
    assert data[:3] == bytes((0, 0, 2))
    assert (width, height, data[16], data[17]) == (128, 128, 32, 0x28)
    assert len(data) == 18 + width * height * 4
    alpha = data[21::4]
    assert alpha[0] == alpha[127] == alpha[-128] == alpha[-1] == 0
    assert max(alpha) == 255 and 1000 < sum(value > 127 for value in alpha) < 12000
print('Forever weather artwork: WoW texture dimensions, format and transparency passed')
