"""Draw the Windows caption glyphs of the skin's window actions.

Writes MSUF_Suite_Skin/Media/WindowActions/MapkoSkinWindowCaption{Fine,Bold}.png:
a 256x128 atlas of two 128px cells, drawn from primitives (rectangles only).
Cell 0 is maximize (one square), cell 1 is restore (two overlapping squares).
The fine and bold strokes match MapkoSkinWindowActions{Fine,Bold}.png.

Usage: python tools/generate-window-caption-glyphs.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "MSUF_Suite_Skin" / "Media" / "WindowActions"
SUPERSAMPLE = 8
WHITE, CLEAR = (255, 255, 255, 255), (255, 255, 255, 0)


def draw(stroke, corner, offset, gap_factor):
    size = (256 * SUPERSAMPLE, 128 * SUPERSAMPLE)
    image = Image.new("RGBA", size, CLEAR)
    canvas = ImageDraw.Draw(image)
    s, k = stroke * SUPERSAMPLE, SUPERSAMPLE

    def box(x0, y0, x1, y1):
        canvas.rounded_rectangle([x0 * k - s / 2, y0 * k - s / 2, x1 * k + s / 2, y1 * k + s / 2],
                                 radius=int((corner + stroke / 2) * k), outline=WHITE, width=int(s))

    low, high = 30 + stroke / 2, 98 - stroke / 2
    box(low, low, high, high)
    left = 128
    box(left + low + offset, low, left + high, high - offset)
    gap = stroke * gap_factor * k
    canvas.rectangle([(left + low) * k - s / 2 - gap, (low + offset) * k - s / 2 - gap,
                      (left + high - offset) * k + s / 2 + gap, high * k + s / 2 + gap], fill=CLEAR)
    box(left + low, low + offset, left + high - offset, high)
    return image.resize((256, 128), Image.LANCZOS)


def main():
    draw(11, 3, 15, 0.75).save(OUT / "MapkoSkinWindowCaptionFine.png")
    draw(15, 3, 15, 0.6).save(OUT / "MapkoSkinWindowCaptionBold.png")


if __name__ == "__main__":
    main()
