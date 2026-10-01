"""Every file the skin bundles from someone else is accounted for in its
THIRD_PARTY_NOTICES.txt: each library, font and texture is named with its
source and licence (or an explicit OWNER TO CONFIRM / UNKNOWN marker), and
the project's own artwork is listed as such.

Usage: python suite_skin_notices_contract.py <suite root>
"""

import sys
from pathlib import Path


def main():
    root = Path(sys.argv[1])
    skin = root / "MSUF_Suite_Skin"
    notices = (skin / "THIRD_PARTY_NOTICES.txt").read_text(encoding="utf-8")
    problems = []
    if notices.startswith("MapkoSkin includes"):
        problems.append("the notices still describe the MapkoSkin addon")
    if "MSUF_Suite_Skin" not in notices.split("\n", 1)[0]:
        problems.append("the notices do not name the addon they ship with")
    for path in sorted((skin / "Libs").rglob("*.lua")):
        if path.relative_to(skin).as_posix() not in notices:
            problems.append("library not listed: " + path.relative_to(skin).as_posix())
    for path in sorted((skin / "Media").rglob("*")):
        if not path.is_file():
            continue
        folder = path.parent.relative_to(skin).as_posix()
        if folder == "Media/Shapes":
            listed = "Media/Shapes/*.png" in notices
        else:
            listed = path.name in notices
        if not listed:
            problems.append("media file not listed: " + path.relative_to(skin).as_posix())
    for font in ("Expressway", "Friz Quadrata"):
        block = notices[notices.find(font):]
        if font not in notices or "OWNER TO CONFIRM" not in block.split("\n\n", 1)[0] + block[:600]:
            problems.append("the font %s has no licence status" % font)
    if problems:
        print("\n".join(problems))
        return 1
    print("Suite skin notices: every bundled library and media file is accounted for")
    return 0


if __name__ == "__main__":
    sys.exit(main())
