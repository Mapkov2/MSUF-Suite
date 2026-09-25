"""The bundled factory profiles name the look their colors actually use.

Both factory strings were once exported through a path that re-ran the look
renumbering migration, which shifted every renumbered look one step
(Retail: Midnight Dark 2 -> MSUF Forever 3; Forever: MSUF Forever 3 -> Custom 4).
Usage: python suite_factory_looks_smoke.py <suite root>
"""

import base64
import re
import sys
import zlib
from pathlib import Path

import cbor2

PREFIX = "MSUFM1:MSUF3:"
EXPECTED = {
    "RetailFactory.lua": ("RetailFactoryModuleCompact", {"chat": 2, "damageMeter": 2, "dataTexts": 2, "xpBar": 2}),
    "ForeverFactory.lua": ("ForeverFactoryModuleCompact", {"chat": 3, "damageMeter": 3, "dataTexts": 3, "xpBar": 3}),
}


def text(value):
    return value.decode("utf-8") if isinstance(value, bytes) else value


def modules(path, name):
    source = path.read_text(encoding="utf-8")
    match = re.search(name + r" = \[\[(.*?)\]\]", source, re.S)
    assert match and match.group(1).startswith(PREFIX), name + " missing"
    data = cbor2.loads(zlib.decompress(base64.b64decode(match.group(1)[len(PREFIX):]), -15))
    for key in ("profile", "suite", "modules"):
        data = {text(k): v for k, v in data.items()}[key]
    return {text(k): {text(field): value for field, value in v.items()} for k, v in data.items()}


def main():
    core = Path(sys.argv[1]) / "MSUF_Suite" / "Core"
    for file, (name, looks) in EXPECTED.items():
        found = modules(core / file, name)
        for module, look in looks.items():
            actual = found[module].get("look")
            assert actual == look, "%s %s look is %r, expected %r" % (file, module, actual, look)
    print("Suite factory profiles: stored looks match their colors")


if __name__ == "__main__":
    main()
