"""Rebuild cold player-aura identities from the pinned public DB2 snapshot."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
START = "-- BEGIN NATIVE PLAYER AURA IDENTITIES"
END = "-- END NATIVE PLAYER AURA IDENTITIES"


def snapshot(root=ROOT):
    path = root / "tools/tests/data/suite_cdm_aura_units.json"
    return json.loads(path.read_text(encoding="utf-8"))


def player_rows(data):
    result = {}
    for row in data["rows"]:
        if row["category"] not in (0, 1, 2, 3) or not row["spec"]:
            continue
        ids = sorted(set([row["spell"]] + row["linked"]) - {0})
        effects = [data["effects"].get(str(spell), []) for spell in ids]
        if not ids or any(not group for group in effects):
            continue
        effects = [effect for group in effects for effect in group]
        auras = [effect for effect in effects if effect[1] > 0]
        if not auras or any(effect[2:] != [1, 0] for effect in auras):
            continue
        # Only rows whose casts/aliases could mislead a cast-target heuristic.
        # Every actual aura target in the complete identity set is the caster.
        if not any(not effect[1] and any(target not in (0, 1) for target in effect[2:]) for effect in effects):
            continue
        result[row["id"]] = ids
    return result


def render(data):
    lines = [START, "-- Blizzard DB2 " + data["build"] + "; all 40 Retail specs audited.",
             "-- Complete base/linked identity sets with caster-only aura effects.",
             "-- Regenerate: python tools/generate_cdm_aura_units.py", "K.PLAYER_AURA_IDS = {"]
    for record, spells in sorted(player_rows(data).items()):
        values = ", ".join("[%d] = true" % spell for spell in spells)
        lines.append("    [%d] = { %s }," % (record, values))
    lines.extend(["}", END])
    return "\n".join(lines)


def main():
    path = ROOT / "MSUF_Suite_CooldownManager/Const.lua"
    raw = path.read_bytes()
    source = raw.decode("utf-8").replace("\r\n", "\n")
    begin = source.index(START)
    end = source.index(END, begin) + len(END)
    generated = render(snapshot())
    if "--check" in sys.argv:
        if source[begin:end] != generated:
            raise SystemExit("native player aura identities are stale")
    else:
        source = source[:begin] + generated + source[end:]
        encoded = source.encode("utf-8")
        path.write_bytes(encoded.replace(b"\n", b"\r\n") if b"\r\n" in raw else encoded)
    print("native player aura identities: %d reviewed rows" % len(player_rows(snapshot())))


if __name__ == "__main__":
    main()
