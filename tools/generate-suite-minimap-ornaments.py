"""Generate original, tintable minimap ornaments for MSUF Suite.

The files are white alpha masks so profile colors can tint them in WoW. Run
with Pillow from the repository root; runtime does not depend on Python.
"""
from pathlib import Path
from math import cos, sin, pi
from struct import pack
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[1] / "MSUF_Suite_Modules" / "Media" / "Minimap"
OUT.mkdir(parents=True, exist_ok=True)
S = 1024
C = S / 2


def xy(radius, degrees):
    angle = degrees * pi / 180
    return C + cos(angle) * radius, C + sin(angle) * radius


def ring(draw, radius, width, alpha, start=0, end=360):
    box = (C - radius, C - radius, C + radius, C + radius)
    draw.arc(box, start=start, end=end, fill=(255, 255, 255, alpha), width=width)


def line(draw, radius1, radius2, angle, width, alpha):
    draw.line((*xy(radius1, angle), *xy(radius2, angle)), fill=(255, 255, 255, alpha), width=width)


def diamond(draw, radius, angle, half, alpha):
    cx, cy = xy(radius, angle)
    draw.polygon([(cx, cy - half), (cx + half, cy), (cx, cy + half), (cx - half, cy)],
                 outline=(255, 255, 255, alpha), width=5)


def save(image, name):
    resized = image.resize((256, 256), Image.Resampling.LANCZOS)
    # Match the Suite's existing WoW-tested TGA files exactly: uncompressed
    # top-left BGRA pixels, eight alpha bits, and no TGA 2.0 footer.
    header = bytes((0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0)) + pack("<HHBB", 256, 256, 32, 0x28)
    (OUT / name).write_bytes(header + resized.tobytes("raw", "BGRA"))


arcane = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(arcane)
ring(d, 446, 7, 215)
ring(d, 422, 4, 165)
for i in range(8):
    start = i * 45 + 8
    ring(d, 459, 10, 220, start, start + 29)
    ring(d, 406, 3, 120, start + 4, start + 25)
    diamond(d, 446, i * 45, 17 if i % 2 == 0 else 10, 245)
for i in range(48):
    line(d, 431, 438 if i % 3 else 448, i * 7.5, 3, 155 if i % 3 else 210)
save(arcane, "ArcaneRing.tga")

ember = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(ember)
ring(d, 439, 8, 215)
ring(d, 410, 5, 180)
for i in range(12):
    angle = i * 30
    a = xy(414, angle - 9)
    b = xy(468, angle)
    c = xy(414, angle + 9)
    d.polygon([a, b, c], outline=(255, 255, 255, 220), width=6)
    line(d, 440, 475 if i % 3 == 0 else 460, angle, 4, 185)
for i in range(4):
    ring(d, 453, 7, 215, i * 90 + 22, i * 90 + 67)
save(ember, "EmberRing.tga")

astral = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(astral)
ring(d, 441, 5, 210)
ring(d, 411, 3, 165)
for i in range(6):
    ring(d, 468, 7, 205, i * 60 + 9, i * 60 + 41)
    diamond(d, 446, i * 60 + 48, 11, 245)
for i in range(36):
    angle = i * 10
    line(d, 418, 430 if i % 3 else 440, angle, 3, 145)
for i in range(4):
    angle = 45 + i * 90
    x, y = xy(474, angle)
    d.line((x - 10, y, x + 10, y), fill=(255, 255, 255, 245), width=5)
    d.line((x, y - 10, x, y + 10), fill=(255, 255, 255, 245), width=5)
save(astral, "AstralRing.tga")

frame = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(frame)
d.rounded_rectangle((62, 62, S - 62, S - 62), radius=26, outline=(255, 255, 255, 230), width=11)
d.rounded_rectangle((78, 78, S - 78, S - 78), radius=17, outline=(255, 255, 255, 125), width=4)
for cx in (73, S - 73):
    for cy in (73, S - 73):
        d.rectangle((cx - 19, cy - 19, cx + 19, cy + 19), outline=(255, 255, 255, 220), width=6)
for i in range(4):
    x = 200 + i * 208
    d.line((x, 61, x + 22, 61), fill=(255, 255, 255, 185), width=5)
    d.line((x, S - 62, x + 22, S - 62), fill=(255, 255, 255, 185), width=5)
save(frame, "SteelFrame.tga")

glow = Image.new("RGBA", (S, S))
p = glow.load()
for y in range(S):
    for x in range(S):
        radius = ((x - C) ** 2 + (y - C) ** 2) ** 0.5
        alpha = round(120 * max(0, 1 - abs(radius - 438) / 65) ** 2)
        if alpha:
            p[x, y] = (255, 255, 255, alpha)
save(glow, "Halo.tga")

print("Wrote original minimap ornaments to", OUT)
