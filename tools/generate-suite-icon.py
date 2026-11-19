"""Generate the MSUF Suite addon-list icon and circular minimap variants.

A sibling of MSUF's own M badge (MidnightSimpleUnitFrames\\Media\\MSUF_MinimapIcon.tga):
the same dark disc, top-lit ring and blue, with a 2x2 module grid instead of the M.
The palette changes while the shape and proportions stay readable at 20x20.
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
RIM_BOUNDS = (C - 28 * K, C - 28 * K, C + 28 * K, C + 28 * K)

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


def interior(row, stops):
    for (r0, c0), (r1, c1) in zip(stops, stops[1:]):
        if row <= r1:
            return lerp(c0, c1, max(0.0, (row - r0) / (r1 - r0)))
    return stops[-1][1]


def badge(outside, stops, ring_dim, ring_lit):
    image = Image.new("RGBA", (S, S), outside + (255,))
    disc = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(disc)
    for y in range(S):
        draw.line((0, y, S, y), fill=interior(y / K, stops) + (255,))
    mask = Image.new("L", (S, S))
    ImageDraw.Draw(mask).ellipse((C - 27.5 * K, C - 27.5 * K, C + 27.5 * K, C + 27.5 * K), fill=255)
    image.paste(disc, (0, 0), mask)

    ring = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(ring)
    for y in range(S):
        lit = max(0.0, (C - y) / (28 * K)) ** 2
        draw.line((0, y, S, y), fill=lerp(ring_dim, ring_lit, lit) + (255,))
    band = Image.new("L", (S, S))
    ImageDraw.Draw(band).ellipse(RIM_BOUNDS, outline=255, width=round(1.6 * K))
    band = band.filter(ImageFilter.GaussianBlur(0.35 * K))
    image.paste(ring, (0, 0), band)
    return image


def grid(image, tile_color, accent):
    tile, gap, radius = 12 * K, 4 * K, 3 * K
    x0 = y0 = C - (2 * tile + gap) / 2
    layer = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(layer)
    colours = (tile_color, tile_color, tile_color, accent)
    for i, colour in enumerate(colours):
        x = x0 + (i % 2) * (tile + gap)
        y = y0 + (i // 2) * (tile + gap)
        draw.rounded_rectangle((x, y, x + tile, y + tile), radius=radius, fill=colour + (255,))
    glow = layer.filter(ImageFilter.GaussianBlur(1.6 * K))
    glow.putalpha(glow.getchannel("A").point(lambda a: a * 0.55))
    image.alpha_composite(glow)
    image.alpha_composite(layer)
    return image


def addon_list_icon(image):
    resized = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    # Soft 1 px edge like the MSUF badge: border 236, corners 219.
    alpha = resized.getchannel("A")
    for i in range(SIZE):
        for x, y in ((i, 0), (i, SIZE - 1), (0, i), (SIZE - 1, i)):
            alpha.putpixel((x, y), 236)
    for x, y in ((0, 0), (SIZE - 1, 0), (0, SIZE - 1), (SIZE - 1, SIZE - 1)):
        alpha.putpixel((x, y), 219)
    resized.putalpha(alpha)
    return resized


def minimap_icon(image):
    alpha = Image.new("L", image.size)
    ImageDraw.Draw(alpha).ellipse(RIM_BOUNDS, fill=255)
    image.putalpha(alpha)
    return image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def save(image, name):
    # Same writer as the Suite's other WoW-tested TGA files: uncompressed
    # top-left BGRA pixels, eight alpha bits, and no TGA 2.0 footer.
    header = bytes((0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0)) + pack("<HHBB", SIZE, SIZE, 32, 0x28)
    (OUT / name).write_bytes(header + image.tobytes("raw", "BGRA"))


modern = grid(badge(OUTSIDE, INTERIOR, RING_DIM, RING_LIT), TILE, TILE_LIT)
save(addon_list_icon(modern), "SuiteIcon.tga")
save(minimap_icon(modern), "SuiteIconModern.tga")
forever = badge((22, 15, 9),
                [(4, (66, 48, 32)), (19, (42, 28, 17)), (60, (20, 13, 8))],
                (112, 80, 43), (204, 171, 108))
save(minimap_icon(grid(forever, (214, 177, 110), (255, 233, 185))), "SuiteIconForever.tga")
dark = badge((0, 0, 0), [(4, (40, 40, 40)), (19, (20, 20, 20)), (60, (5, 5, 5))],
             (65, 65, 65), (151, 151, 151))
save(minimap_icon(grid(dark, (214, 214, 214), (255, 255, 255))), "SuiteIconDark.tga")
print("Wrote the Suite addon-list icon and three round minimap icons")
