"""Build the original MSUF chat glyph strip. Run with Python and Pillow."""

from pathlib import Path
from PIL import Image, ImageDraw

SCALE = 4
CELL = 32
OUT = Path(__file__).resolve().parents[1] / "MSUF_Suite_Chat" / "Media" / "MSUFChatGlyphs.png"
image = Image.new("RGBA", (CELL * 8 * SCALE, CELL * SCALE), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)
white = (255, 255, 255, 255)


def box(slot, xy, width=2):
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle(
        ((slot * CELL + x1) * SCALE, y1 * SCALE,
         (slot * CELL + x2) * SCALE, y2 * SCALE),
        radius=2 * SCALE, outline=white, width=width * SCALE,
    )


def line(slot, points, width=2, joint="curve"):
    coords = [((slot * CELL + x) * SCALE, y * SCALE) for x, y in points]
    draw.line(coords, fill=white, width=width * SCALE, joint=joint)


def ellipse(slot, xy, width=2):
    x1, y1, x2, y2 = xy
    draw.ellipse(((slot * CELL + x1) * SCALE, y1 * SCALE,
                  (slot * CELL + x2) * SCALE, y2 * SCALE),
                 outline=white, width=width * SCALE)


# Friends: two people in the compact MSUF outline style.
ellipse(0, (12, 5, 20, 13))
line(0, [(8, 25), (8, 21), (11, 17), (16, 16), (21, 17), (24, 21), (24, 25)])
line(0, [(6, 12), (9, 9), (11, 9)])
line(0, [(26, 12), (23, 9), (21, 9)])

# Channels: a pair of chat bubbles, with the front bubble kept open at its tail.
box(1, (5, 6, 25, 21))
line(1, [(10, 21), (10, 26), (16, 21)])
for x in (11, 16, 21):
    draw.ellipse(((CELL + x - 1) * SCALE, 13 * SCALE,
                  (CELL + x + 1) * SCALE, 15 * SCALE), fill=white)

# Text to speech: speaker and two sound waves.
line(2, [(5, 12), (10, 12), (16, 7), (16, 25), (10, 20), (5, 20), (5, 12)])
draw.arc((19 * SCALE, 9 * SCALE, 27 * SCALE, 23 * SCALE),
         start=-70, end=70, fill=white, width=2 * SCALE)
draw.arc((17 * SCALE, 5 * SCALE, 31 * SCALE, 27 * SCALE),
         start=-65, end=65, fill=white, width=2 * SCALE)

# Chat menu: three unequal control rails and their knobs.
for y in (9, 16, 23):
    line(3, [(5, y), (27, y)])
for x, y in ((11, 9), (21, 16), (15, 23)):
    draw.ellipse(((3 * CELL + x - 2) * SCALE, (y - 2) * SCALE,
                  (3 * CELL + x + 2) * SCALE, (y + 2) * SCALE),
                 fill=(20, 24, 27, 255), outline=white, width=2 * SCALE)

# Return to the newest chat line.
line(4, [(8, 11), (16, 19), (24, 11)])
line(4, [(8, 18), (16, 26), (24, 18)])

OUT.parent.mkdir(parents=True, exist_ok=True)
image.resize((CELL * 8, CELL), Image.Resampling.LANCZOS).save(OUT, optimize=True)
print(OUT)
