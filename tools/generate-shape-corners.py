"""Generate the Skin's sliced corner textures in MSUF_Suite_Skin/Media/Shapes.

Each asset is a white rounded rectangle that fills its whole square texture.
Families are superellipse corners: round (n=2), continuous (n=4) and
squircle (n=6). A fill is the solid shape; an edgeN asset is the N-pixel rim
between the shape and its parallel curve N pixels further in. Shapes are
drawn at SUPERSAMPLE times the size and reduced with Lanczos.

Usage:
  python tools/generate-shape-corners.py              write the window radii
  python tools/generate-shape-corners.py --radius 16  write one radius
  python tools/generate-shape-corners.py --check      check the shape and focus assets
"""

import argparse
import bisect
import math
import sys
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SHAPES = ROOT / "MSUF_Suite_Skin" / "Media" / "Shapes"
FAMILIES = {"round": 2.0, "continuous": 4.0, "squircle": 6.0}
BORDERS = (1, 2)
SUPERSAMPLE = 16
# The 4-12 px radii are the original factory assets.
FACTORY_RADII = (4, 6, 8, 12)
WINDOW_RADII = (16, 20, 24)
FOCUS_RADII = (8, 12) + WINDOW_RADII
# Mean and worst alpha difference a regenerated factory asset may show.
CHECK_MEAN_LIMIT = 1.0
CHECK_PEAK_LIMIT = 12


def texture_size(radius):
    """Return the square texture size. Geometry.lua slices it at (size - 1) / 2."""
    return 20 if radius <= 8 else 2 * radius + 8


def inside(x, y, size, radius, exponent):
    """Whether a point lies inside the rounded rectangle of this size."""
    if radius <= 0:
        return 0 <= x <= size and 0 <= y <= size
    dx = max(radius - x, x - (size - radius), 0.0)
    dy = max(radius - y, y - (size - radius), 0.0)
    if dx == 0.0 or dy == 0.0:
        return dx <= radius and dy <= radius and 0 <= x <= size and 0 <= y <= size
    return (dx / radius) ** exponent + (dy / radius) ** exponent <= 1.0


CURVE_STEPS = 720


def corner_offset(radius, exponent, border, angle):
    """Point of the top-left corner curve moved `border` along its inward normal."""
    cos, sin = math.cos(angle), math.sin(angle)
    dx = radius * cos ** (2.0 / exponent)
    dy = radius * sin ** (2.0 / exponent)
    # Gradient of (dx / r)^n + (dy / r)^n; it points away from the center.
    gx, gy = dx ** (exponent - 1.0), dy ** (exponent - 1.0)
    length = math.hypot(gx, gy) or 1.0
    return radius - dx + border * gx / length, radius - dy + border * gy / length


class InnerCurve:
    """Region bounded by the parallel curve `border` pixels inside the shape.

    The top-left curve runs from (border, radius) to (radius, border) with x
    rising as y falls, so one x per height describes it. Other corners fold
    onto it by symmetry.
    """

    def __init__(self, size, radius, exponent, border):
        self.size, self.radius, self.border = size, radius, border
        samples = [corner_offset(radius, exponent, border, math.pi / 2 * step / CURVE_STEPS)
                   for step in range(CURVE_STEPS + 1)]
        samples.sort(key=lambda point: point[1])
        self.heights = [point[1] for point in samples]
        self.widths = [point[0] for point in samples]

    def boundary(self, y):
        index = bisect.bisect_left(self.heights, y)
        if index <= 0:
            return self.widths[0]
        if index >= len(self.heights):
            return self.widths[-1]
        y0, y1 = self.heights[index - 1], self.heights[index]
        x0, x1 = self.widths[index - 1], self.widths[index]
        return x0 if y1 == y0 else x0 + (x1 - x0) * (y - y0) / (y1 - y0)

    def contains(self, x, y):
        x, y = min(x, self.size - x), min(y, self.size - y)
        if x < self.border or y < self.border:
            return False
        if x >= self.radius or y >= self.radius:
            return True
        return x >= self.boundary(y)


def render(size, radius, exponent, border):
    """Render one fill (border 0) or rim asset as an RGBA image."""
    scale = SUPERSAMPLE
    big = size * scale
    mask = Image.new("L", (big, big), 0)
    pixels = mask.load()
    inner = InnerCurve(size, radius, exponent, border) if border > 0 else None
    for py in range(big):
        y = (py + 0.5) / scale
        for px in range(big):
            x = (px + 0.5) / scale
            if inside(x, y, size, radius, exponent) and not (inner and inner.contains(x, y)):
                pixels[px, py] = 255
    alpha = mask.resize((size, size), Image.LANCZOS)
    image = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    image.putalpha(alpha)
    return image


def asset_name(family, radius, border):
    suffix = "fill" if border == 0 else "edge%d" % border
    return "%s_r%d_%s.png" % (family, radius, suffix)


def assets(radii):
    for family, exponent in FAMILIES.items():
        for radius in radii:
            for border in (0,) + BORDERS:
                yield family, exponent, radius, border


def write(radii):
    for family, exponent, radius, border in assets(radii):
        path = SHAPES / asset_name(family, radius, border)
        image = render(texture_size(radius), radius, exponent, border)
        image.save(path, optimize=True)
        print("wrote", path.relative_to(ROOT))


def focus_cutouts(radii, verify=False):
    passed = True
    for family in FAMILIES:
        for radius in radii:
            fill = SHAPES / asset_name(family, radius, 0)
            path = SHAPES / ("%s_r%d_outside.png" % (family, radius))
            with Image.open(fill) as source:
                alpha = ImageOps.invert(source.convert("RGBA").getchannel("A"))
            if verify:
                matches = False
                if path.is_file():
                    with Image.open(path) as cutout:
                        matches = cutout.size == alpha.size and cutout.convert("RGBA").getchannel("A").tobytes() == alpha.tobytes()
                passed = passed and matches
                print("ok  " if matches else "FAIL", path.name)
            else:
                image = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
                image.putalpha(alpha)
                image.save(path, optimize=True)
                print("wrote", path.relative_to(ROOT))
    return passed


def check():
    failed = False
    for family, exponent, radius, border in assets(FACTORY_RADII + WINDOW_RADII):
        name = asset_name(family, radius, border)
        tracked = Image.open(SHAPES / name).convert("RGBA").getchannel("A")
        size = texture_size(radius)
        if tracked.size != (size, size):
            print("FAIL", name, "size", tracked.size, "expected", size)
            failed = True
            continue
        made = render(size, radius, exponent, border).getchannel("A")
        diffs = [abs(a - b) for a, b in zip(tracked.tobytes(), made.tobytes())]
        mean, peak = sum(diffs) / len(diffs), max(diffs)
        verdict = "ok" if mean <= CHECK_MEAN_LIMIT and peak <= CHECK_PEAK_LIMIT else "FAIL"
        failed = failed or verdict == "FAIL"
        print("%-4s %-28s mean %.2f peak %d" % (verdict, name, mean, peak))
    return focus_cutouts(FOCUS_RADII, verify=True) and not failed


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--radius", type=int, action="append",
                        help="radius to write (repeatable); default: the window radii")
    parser.add_argument("--check", action="store_true",
                        help="compare regenerated shape and focus assets with the checked-in files")
    args = parser.parse_args()
    if args.check:
        return 0 if check() else 1
    write(tuple(args.radius) if args.radius else WINDOW_RADII)
    focus_cutouts(tuple(radius for radius in args.radius if radius in FOCUS_RADII) if args.radius else FOCUS_RADII)
    return 0


if __name__ == "__main__":
    sys.exit(main())
