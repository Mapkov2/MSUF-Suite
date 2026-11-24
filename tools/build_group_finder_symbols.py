"""Build the white group finder symbols of the Suite minimap (tinted at runtime).

Writes MSUF_Suite/Media/GroupFinder/{Eye,Search,Group,Dungeon}.tga: 64x64 flat
glyphs drawn from primitives at 8x and scaled down. --check fails when a file
differs from what this script draws.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw

from build_blizzard_frame_art import tga

ROOT = Path(__file__).resolve().parents[1] / "MSUF_Suite/Media/GroupFinder"
K = 8
WHITE, CLEAR = (255, 255, 255, 255), (255, 255, 255, 0)


def canvas():
    image = Image.new("RGBA", (64 * K, 64 * K), CLEAR)
    return image, ImageDraw.Draw(image)


def box(x0, y0, x1, y1):
    return [x0 * K, y0 * K, x1 * K, y1 * K]


def curve(left, right, mid_y, lift, steps=48):
    """A quadratic curve from (left, mid_y) to (right, mid_y) peaking at mid_y + lift / 2."""
    cx, cy = (left + right) / 2, mid_y + lift
    points = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * left + 2 * (1 - t) * t * cx + t * t * right
        y = (1 - t) ** 2 * mid_y + 2 * (1 - t) * t * cy + t * t * mid_y
        points.append((x * K, y * K))
    return points


def eye(draw):
    # An almond outline from two arcs, a solid iris and a clear pupil.
    for bulge in (-18, 18):
        draw.line(curve(5, 59, 32, bulge * 2), fill=WHITE, width=6 * K, joint="curve")
    for x in (5, 59):
        draw.ellipse(box(x - 3, 29, x + 3, 35), fill=WHITE)
    draw.ellipse(box(20, 20, 44, 44), fill=WHITE)
    draw.ellipse(box(27.5, 27.5, 36.5, 36.5), fill=CLEAR)


def search(draw):
    draw.ellipse(box(8, 8, 42, 42), outline=WHITE, width=7 * K)
    draw.line([37 * K, 37 * K, 55 * K, 55 * K], fill=WHITE, width=9 * K)
    draw.ellipse(box(50.5, 50.5, 59.5, 59.5), fill=WHITE)


def person(draw, cx, head, shoulders, width):
    draw.ellipse(box(cx - head, 14, cx + head, 14 + head * 2), fill=WHITE)
    top = 16 + head * 2
    draw.pieslice(box(cx - width, top, cx + width, top + shoulders * 2), 180, 360, fill=WHITE)


def group(draw):
    for cx in (15, 49):
        person(draw, cx, 6.5, 15, 12)
    # A clear gap keeps the front figure readable over the two behind it.
    draw.ellipse(box(23, 9, 41, 27), fill=CLEAR)
    draw.pieslice(box(14, 27, 50, 63), 180, 360, fill=CLEAR)
    draw.ellipse(box(25, 11, 39, 25), fill=WHITE)
    draw.pieslice(box(17, 30, 47, 60), 180, 360, fill=WHITE)
    draw.rectangle(box(17, 45, 47, 52), fill=WHITE)


def dungeon(draw):
    # An arched gate with a raised portcullis.
    draw.rounded_rectangle(box(9, 8, 55, 58), radius=23 * K, outline=WHITE, width=6 * K)
    draw.rectangle(box(9, 31, 55, 58), outline=WHITE, width=6 * K)
    draw.rectangle(box(15, 31, 49, 52), fill=CLEAR)
    for x in (21, 29.5, 38):
        draw.rectangle(box(x, 17, x + 5, 52), fill=WHITE)
    draw.rectangle(box(14, 27, 50, 31), fill=WHITE)
    draw.rectangle(box(4, 54, 60, 60), fill=WHITE)


DRAW = {"Eye": eye, "Search": search, "Group": group, "Dungeon": dungeon}


def symbol(name):
    image, draw = canvas()
    DRAW[name](draw)
    return image.resize((64, 64), Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name in DRAW:
        data, path = tga(symbol(name)), ROOT / (name + ".tga")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit("Group finder symbol is stale: " + name)
        else:
            ROOT.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print("Group finder symbols " + ("match" if args.check else "written"))


if __name__ == "__main__":
    main()
