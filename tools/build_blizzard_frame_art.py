"""Build the compact frame's transparent chassis and dark name strip."""
import argparse
import math
import struct
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "MSUF_Suite/Media/BlizzardFrames"
WIDTH, HEIGHT = 128, 64


def health_fill():
    """A continuous dark-to-light ramp with the broad glow below the centre."""
    image = Image.new("RGBA", (256, 64))
    stops = ((0, .35), (.065, .52), (.13, .67), (.23, .77), (.42, .86),
             (.61, .92), (.77, 1), (.83, .99), (.88, .96), (.94, .67), (1, .35))
    pixels = image.load()
    for y in range(image.height):
        t = y / (image.height - 1)
        for (a, low), (b, high) in zip(stops, stops[1:]):
            if a <= t <= b:
                value = low + (high - low) * (t - a) / (b - a)
                break
        for x in range(image.width):
            edge = min(x, image.width - 1 - x) * 124 / image.width
            shade = round(255 * value * (1 - .55 * math.exp(-edge / 2.2)))
            pixels[x, y] = (shade, shade, shade, 255)
    return image


def chassis(boss=False):
    image = Image.new("RGBA", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    top, bottom, name_top = (24, 52, 12) if boss else (23, 55, 9)
    for y in range(name_top, top):
        t = (y - name_top) / (top - name_top - 1)
        color = (round(105 - 25 * t), 0, 0) if boss else (0, 0, 0)
        draw.line((2, y, 125, y), fill=(*color, round(125 + 85 * t)))
    draw.rounded_rectangle((0, top - 1, 127, bottom + 2), radius=3, fill=(0, 0, 0, 100))
    draw.rounded_rectangle((0, top - 2, 127, bottom + 1), radius=3, fill=(0, 0, 0, 245))
    bevel = Image.new("RGBA", image.size)
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).rounded_rectangle((1, top - 1, 126, bottom), radius=2, fill=255)
    pen = ImageDraw.Draw(bevel)
    light, dark = ((116, 114, 105), (54, 55, 51)) if boss else ((119, 102, 78), (64, 56, 42))
    for y in range(top - 1, bottom + 1):
        t = (y - top + 1) / (bottom - top + 1)
        shade = tuple(round(a + (b - a) * t) for a, b in zip(light, dark))
        pen.line((1, y, 126, y), fill=(*shade, 255))
    image.paste(bevel, (0, 0), mask)
    draw = ImageDraw.Draw(image)
    # The game paints health/power through this opening. No colored bar or
    # sample text is baked into the decoration.
    if boss:
        draw.rectangle((2, top, 125, bottom - 1), fill=(0, 0, 0, 0))
    else:
        draw.rounded_rectangle((2, top, 125, bottom - 1), radius=3, fill=(0, 0, 0, 0))
    return image


def tga(image):
    header = bytearray(18)
    header[2] = 2
    struct.pack_into("<HH", header, 12, *image.size)
    header[16], header[17] = 32, 0x28
    return bytes(header) + image.tobytes("raw", "BGRA")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    assets = (("UnitFrame", chassis()), ("BossFrame", chassis(True)), ("HealthFill", health_fill()))
    for name, artwork in assets:
        data, path = tga(artwork), OUTPUT / (name + ".tga")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit("Blizzard frame artwork is stale: " + name)
        else:
            OUTPUT.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print("Blizzard frame chassis, name strips and smooth health fill " + ("match" if args.check else "written"))


if __name__ == "__main__":
    main()
