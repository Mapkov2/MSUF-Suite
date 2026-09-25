"""Generate the MSUF Suite addon-list icon.

A sibling of MSUF's own M badge (MidnightSimpleUnitFrames\\Media\\MSUF_MinimapIcon.tga):
the same dark disc, top-lit ring and blue, with a 2x2 module grid instead of the M.
The addon list draws it at 20x20, so the grid is sized to stay four blocks there.
Run with Pillow from the repository root; runtime does not depend on Python.
"""
from pathlib import Path
from struct import pack
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "MSUF_Suite" / "Media"
OUT.mkdir(parents=True, exist_ok=True)
SIZE = 64
K = 16  # supersampling factor
S = SIZE * K
C = S / 2

OUTSIDE = (4, 10, 23)
# Interior brightness by row, measured from the MSUF badge (row in 64 px space).
INTERIOR = [(4, (28, 41, 68)), (12, (20, 30, 50)), (19, (14, 23, 40)),
            (40, (7, 16, 29)), (45, (5, 12, 24)), (60, (4, 11, 22))]
RING_DIM = (8, 42, 58)
RING_LIT = (93, 118, 148)
TILE = (40, 151, 226)   # the core blue of MSUF's M
TILE_LIT = (204, 224, 255)  # cce0ff, the second colour of the MSUF title


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def interior(row):
    for (r0, c0), (r1, c1) in zip(INTERIOR, INTERIOR[1:]):
        if row <= r1:
            return lerp(c0, c1, max(0.0, (row - r0) / (r1 - r0)))
    return INTERIOR[-1][1]


def badge():
    image = Image.new("RGBA", (S, S), OUTSIDE + (255,))
    disc = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(disc)
    for y in range(S):
        draw.line((0, y, S, y), fill=interior(y / K) + (255,))
    mask = Image.new("L", (S, S))
    ImageDraw.Draw(mask).ellipse((C - 27.5 * K, C - 27.5 * K, C + 27.5 * K, C + 27.5 * K), fill=255)
    image.paste(disc, (0, 0), mask)

    ring = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(ring)
    for y in range(S):
        lit = max(0.0, (C - y) / (28 * K)) ** 2
        draw.line((0, y, S, y), fill=lerp(RING_DIM, RING_LIT, lit) + (255,))
    band = Image.new("L", (S, S))
    ImageDraw.Draw(band).ellipse((C - 28 * K, C - 28 * K, C + 28 * K, C + 28 * K),
                                 outline=255, width=round(1.6 * K))
    band = band.filter(ImageFilter.GaussianBlur(0.35 * K))
    image.paste(ring, (0, 0), band)
    return image


def grid(image):
    tile, gap, radius = 12 * K, 4 * K, 3 * K
    x0 = y0 = C - (2 * tile + gap) / 2
    layer = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(layer)
    colours = (TILE, TILE, TILE, TILE_LIT)
    for i, colour in enumerate(colours):
        x = x0 + (i % 2) * (tile + gap)
        y = y0 + (i // 2) * (tile + gap)
        draw.rounded_rectangle((x, y, x + tile, y + tile), radius=radius, fill=colour + (255,))
    glow = layer.filter(ImageFilter.GaussianBlur(1.6 * K))
    glow.putalpha(glow.getchannel("A").point(lambda a: a * 0.55))
    image.alpha_composite(glow)
    image.alpha_composite(layer)
    return image


def save(image, name):
    resized = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    # Soft 1 px edge like the MSUF badge: border 236, corners 219.
    alpha = resized.getchannel("A")
    for i in range(SIZE):
        for x, y in ((i, 0), (i, SIZE - 1), (0, i), (SIZE - 1, i)):
            alpha.putpixel((x, y), 236)
    for x, y in ((0, 0), (SIZE - 1, 0), (0, SIZE - 1), (SIZE - 1, SIZE - 1)):
        alpha.putpixel((x, y), 219)
    resized.putalpha(alpha)
    # Same writer as the Suite's other WoW-tested TGA files: uncompressed
    # top-left BGRA pixels, eight alpha bits, and no TGA 2.0 footer.
    header = bytes((0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0)) + pack("<HHBB", SIZE, SIZE, 32, 0x28)
    (OUT / name).write_bytes(header + resized.tobytes("raw", "BGRA"))


save(grid(badge()), "SuiteIcon.tga")
print("Wrote MSUF_Suite/Media/SuiteIcon.tga")
