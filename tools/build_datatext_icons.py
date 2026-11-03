"""Build the small, neutral source symbols used by DataTexts."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw

from build_blizzard_frame_art import tga

ROOT = Path(__file__).resolve().parents[1] / "MSUF_Suite/Media/DataTextIcons"


def icon(name):
    image = Image.new("RGBA", (64, 64))
    draw = ImageDraw.Draw(image)
    gold, gray = (255, 210, 65, 255), (218, 218, 208, 255)
    if name == "Home":
        draw.line((8, 30, 32, 10, 56, 30), fill=gold, width=8, joint="curve")
        draw.polygon((15, 29, 32, 15, 49, 29, 49, 55, 37, 55, 37, 39, 27, 39, 27, 55, 15, 55), fill=gold)
    elif name == "World":
        draw.ellipse((9, 9, 55, 55), outline=gold, width=5)
        draw.ellipse((22, 9, 42, 55), outline=gold, width=4)
        draw.line((10, 25, 54, 25), fill=gold, width=4)
        draw.line((10, 39, 54, 39), fill=gold, width=4)
    elif name == "Location":
        draw.polygon((8, 16, 23, 9, 42, 16, 56, 9, 56, 48, 42, 55, 23, 48, 8, 55), fill=gray)
        draw.line((23, 11, 23, 48), fill=(105, 108, 103, 255), width=3)
        draw.line((42, 16, 42, 54), fill=(105, 108, 103, 255), width=3)
    else:
        draw.polygon((6, 15, 57, 15, 48, 28, 37, 28, 37, 41, 51, 47, 51, 54,
                      14, 54, 14, 47, 26, 41, 26, 28, 17, 28), fill=gray)
        draw.line((11, 18, 51, 18), fill=(255, 255, 246, 255), width=3)
    return image.resize((16, 16), Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name in ("Home", "World", "Location", "Durability"):
        data, path = tga(icon(name)), ROOT / (name + ".tga")
        if args.check:
            if not path.exists() or path.read_bytes() != data:
                raise SystemExit("DataText symbol is stale: " + name)
        else:
            ROOT.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print("DataText source symbols " + ("match" if args.check else "written"))


if __name__ == "__main__":
    main()
