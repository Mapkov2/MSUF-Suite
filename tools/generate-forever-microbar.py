"""Generate original, small Forever Micro Bar chrome assets.

The shapes are drawn from primitives, so every asset is original.
"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "MSUF_Suite_Skin" / "Media" / "MicroMenu"
SCALE = 4
SIZE = 64


def box(x0, y0, x1, y1):
    return tuple(round(value * SCALE) for value in (x0, y0, x1, y1))


def finish(image, name):
    OUT.mkdir(parents=True, exist_ok=True)
    image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(OUT / name)


plate = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE))
draw = ImageDraw.Draw(plate)
draw.rounded_rectangle(box(2, 1, 62, 63), radius=8 * SCALE, fill="#070e18")
draw.rounded_rectangle(box(3, 2, 61, 61), radius=7 * SCALE, fill="#24445f")
draw.rounded_rectangle(box(4, 4, 60, 60), radius=6 * SCALE, fill="#0d1c2b")
for y in range(6 * SCALE, 57 * SCALE):
    t = (y - 6 * SCALE) / (51 * SCALE)
    color = (
        round(24 - 11 * t),
        round(43 - 19 * t),
        round(61 - 27 * t),
        255,
    )
    draw.line((6 * SCALE, y, 58 * SCALE, y), fill=color, width=1)
draw.line((box(9, 4, 55, 4)), fill="#4c7595", width=2 * SCALE)
draw.line((box(10, 59, 54, 59)), fill="#203347", width=SCALE)
finish(plate, "ForeverMicroPlate.tga")


ring = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE))
draw = ImageDraw.Draw(ring)
draw.ellipse(box(2, 2, 62, 62), fill=(3, 8, 15, 100))
draw.ellipse(box(4, 4, 60, 60), fill="#081522")
draw.ellipse(box(5, 5, 59, 59), outline="#49647a", width=2 * SCALE)
draw.ellipse(box(8, 8, 56, 56), outline="#c9a35d", width=2 * SCALE)
draw.ellipse(box(10, 10, 54, 54), outline="#ebcf8c", width=SCALE)
draw.ellipse(box(11, 11, 53, 53), fill=(0, 0, 0, 0))
draw.arc(box(5, 5, 59, 59), 200, 323, fill="#7eabce", width=2 * SCALE)
draw.arc(box(8, 8, 56, 56), 200, 323, fill="#f2dba1", width=SCALE)
finish(ring, "ForeverPortraitRing.tga")


# Midnight uses the same authored geometry but a distinct cool-blue chrome.
# The original Blizzard button objects remain the interactive layer in game.
midnight_plate = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE))
draw = ImageDraw.Draw(midnight_plate)
draw.rounded_rectangle(box(2, 1, 62, 63), radius=8 * SCALE, fill="#06111e")
draw.rounded_rectangle(box(3, 2, 61, 61), radius=7 * SCALE, fill="#326481")
draw.rounded_rectangle(box(4, 4, 60, 60), radius=6 * SCALE, fill="#0d2031")
for y in range(6 * SCALE, 57 * SCALE):
    t = (y - 6 * SCALE) / (51 * SCALE)
    color = (round(25 - 12 * t), round(52 - 22 * t), round(73 - 28 * t), 255)
    draw.line((6 * SCALE, y, 58 * SCALE, y), fill=color, width=1)
draw.line(box(9, 4, 55, 4), fill="#65bfd1", width=2 * SCALE)
draw.line(box(10, 59, 54, 59), fill="#203b50", width=SCALE)
finish(midnight_plate, "MidnightMicroPlate.tga")

midnight_ring = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE))
draw = ImageDraw.Draw(midnight_ring)
draw.ellipse(box(2, 2, 62, 62), fill=(3, 14, 25, 110))
draw.ellipse(box(4, 4, 60, 60), fill="#071929")
draw.ellipse(box(5, 5, 59, 59), outline="#4c7892", width=2 * SCALE)
draw.ellipse(box(8, 8, 56, 56), outline="#57aeca", width=2 * SCALE)
draw.ellipse(box(10, 10, 54, 54), outline="#a8ddea", width=SCALE)
draw.ellipse(box(11, 11, 53, 53), fill=(0, 0, 0, 0))
draw.arc(box(5, 5, 59, 59), 200, 323, fill="#8cd8e7", width=2 * SCALE)
finish(midnight_ring, "MidnightPortraitRing.tga")
