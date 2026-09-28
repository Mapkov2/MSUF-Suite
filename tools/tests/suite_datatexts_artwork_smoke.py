"""The optional DataTexts medallion is a valid transparent WoW texture."""
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1])
data = (root / 'MSUF_Suite_DataTexts/Media/BagMedallion.tga').read_bytes()
width, height = struct.unpack_from('<HH', data, 12)
assert data[:3] == bytes((0, 0, 2))
assert (width, height, data[16], data[17]) == (256, 256, 32, 0x28)
assert len(data) == 18 + width * height * 4
alpha = data[21::4]
assert alpha[0] == alpha[width - 1] == alpha[(height - 1) * width] == 0
assert alpha[128 * width + 128] > 240
assert sum(value > 127 for value in alpha) > 20000
print('DataTexts bag medallion format and transparency passed')
