"""The Modern Retail selection retains the supplied Suite layout on both clients.

The original unitframe factory stays in the host; this selection bundles only
Suite and Skin settings. Existing factory seeding remains covered separately.
"""
import re
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import HARNESS as SETUP, LUA, lua_literal
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_forever_factory_preview import decode


CHECK = r"""
local function Check(profile)
    local m = profile.suite.modules
    assert(m.actionTracker.enabled == false, "Action Tracker must be opt-in")
    assert(m.actionbars.bar1Point == 8 and m.actionbars.bar1X == 10 and m.actionbars.bar1Y == 0
        and m.actionbars.bar2X == 9 and m.actionbars.bar2Y == 40
        and m.actionbars.bar3Point == 7 and m.actionbars.bar3X == 2480 and m.actionbars.bar3Y == 236
        and m.actionbars.bar5X == 2520 and m.actionbars.bar5Y == 233, "authored action bars moved")
    assert(m.dataTexts.bar1X == 1020 and m.dataTexts.bar1Y == 170
        and m.dataTexts.bar1Width == 521 and m.dataTexts.bar1Slot4 == 5, "authored DataTexts changed")
    assert(m.minimap.point == 3 and m.minimap.x == 0
        and m.minimap.y == -10 and m.minimap.size == 198, "authored Minimap changed")
    assert(m.damageMeter.w1Width == 260 and m.damageMeter.w2Width == 260
        and m.damageMeter.w1X == 0 and m.damageMeter.w2X == -260
        and math.abs(m.damageMeter.refreshRate - 1) < 0.00001, "authored meters changed")
    assert(m.objectives.x == 0 and m.objectives.y == -250 and m.objectives.width == 310
        and m.bags.inventoryView == 1, "authored tracker or Bags view changed")
end
local compact = Suite.RetailProfileModuleCompact
local profile = assert(Suite.ProfileIO.PrepareProfile(compact, false))
assert(profile.suite.globalLook == "cleanModern" and profile.suite.modules.minimap.stylePreset == 11)
Check(profile)
for _, look in ipairs({ "midnight", "midnightDark", "foreverGlass", "cleanModern", "classColor" }) do
    local staged = Suite.CopyValue(profile)
    assert(Suite.Suite.StyleProfile(staged, look))
    Check(staged)
    assert(staged.suite.globalLook == look and profile.suite.globalLook == "cleanModern",
        "restyling a staged profile changed its source")
end
assert(#reported == 0, tostring(reported[1]))
print("Modern Retail on " .. client .. ": authored positions, module choices and five palettes preserved")
"""


def main():
    root = Path(sys.argv[1])
    source = (root / "MSUF_Suite/Core/RetailProfile.lua").read_text(encoding="utf-8")
    blocks = source.split("Suite.RetailProfileSkinCompact =")
    modules = "".join(re.findall(r"\[\[(.*?)\]\]", blocks[0], re.S))
    skin = "".join(re.findall(r"\[\[(.*?)\]\]", blocks[1], re.S))
    envelope = decode(modules, "MSUFM1:MSUF3:")
    skin_profile = decode(skin, "MSKIN1:")[b"payload"]
    micro = skin_profile[b"icons"][b"microMenu"]
    assert micro[b"layoutPoint"] == b"BOTTOMRIGHT" and micro[b"layoutRelativePoint"] == b"BOTTOMRIGHT"
    assert micro[b"layoutX"] == -520 and micro[b"layoutY"] == 0 and micro[b"positionPreset"] == b"custom"
    assert skin_profile[b"windowControls"][b"positions"], "authored window positions disappeared"
    setup = SETUP.split("local S, defaults")[0]
    for client in ("retail", "forever"):
        script = setup.replace("ENVELOPE", lua_literal(envelope), 1) + CHECK
        run = subprocess.run([LUA, "-", str(root), client, "RetailProfile.lua"], input=script,
                             text=True, capture_output=True, errors="replace", cwd=root)
        if run.returncode:
            raise SystemExit(run.stdout + run.stderr)
        print(run.stdout.strip())


if __name__ == "__main__":
    main()
