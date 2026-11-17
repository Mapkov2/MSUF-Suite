"""Generate the Forever spellbook learning index from public game data.

Download SkillLineAbility, SpellLevels, Spell and SpellName as CSV from
https://wago.tools/db2/ for the requested build. Download trainers.json and
any earlier same-product trainers-*.json from Efficient Games into that folder.
Save https://talentsforever.com/export/<class>.json as class-<class>.json.
Only the spell IDs and acquisition metadata are used from the CC BY 4.0 exports.
"""
import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

CLASSES = {
    1: (26, 256, 257), 2: (184, 267, 594), 3: (50, 51, 163),
    4: (38, 39, 253), 5: (56, 78, 613), 7: (373, 374, 375),
    8: (6, 8, 237), 9: (354, 355, 593), 11: (134, 573, 574),
}
TELEPORTS = {3561, 3562, 3563, 3565, 3566, 3567, 10059, 11416, 11417, 11418, 11419, 11420}
# The spells awarded by the class quest chains, including the follow-up
# commands taught alongside taming. Client SpellLevels supplies the level.
QUESTS = {
    71, 883, 982, 1066, 1515, 2458, 2641, 5487, 688, 697, 712, 691,
    1122, 18540, 7328, 7376, 7381, 768, 8946,
}
# Ignore pet profession/subspell lines and spells with no confirmed way to
# acquire them, even if their base-effect level is in the level 1-60 range.
RANK = re.compile(r"Rank ([0-9]+)$", re.I)
REQUIRED_LEVEL = re.compile(r"Learned at level ([0-9]+)$")
CLASS_NAMES = dict(zip(CLASSES, ("warrior", "paladin", "hunter", "rogue", "priest",
                                 "shaman", "mage", "warlock", "druid"), strict=True))


def spellbook_index(folder, class_id):
    name = CLASS_NAMES[class_id]
    exported = json.loads((folder / f"class-{name}.json").read_text(encoding="utf-8"))
    assert "CC BY 4.0" in exported["_readme"]
    book = exported["spellbook"]
    index = {}
    for tab in book["tabs"]:
        if tab["name"] == "Poisons":
            continue
        for spell_name, subtext in tab["spells"]:
            description = exported["spell_desc"].get(f"{exported['class']}|{spell_name}|{subtext}", {})
            spell = description.get("id")
            if not spell:
                continue
            rank = RANK.fullmatch(subtext)
            level = REQUIRED_LEVEL.fullmatch(description.get("lv") or "")
            source = 2 if description.get("ns") == "quest" else 4 if spell_name in book["talents"] else 3
            index[spell] = (int(level[1]) if level else 0, int(rank[1]) if rank else 0, source)
    return index, set(book.get("gone", ()))


def rows(folder, table):
    with (folder / f"{table}.csv").open(encoding="utf-8-sig", newline="") as stream:
        yield from csv.DictReader(stream)


def read_trainers(folder, build):
    outcomes = {}
    evidence = sorted(folder.glob("trainers-*.json"))
    evidence.append(folder / "trainers.json")
    assert json.loads(evidence[-1].read_text(encoding="utf-8-sig"))["meta"]["clientBuild"] == build
    for path in evidence:
        snapshot = json.loads(path.read_text(encoding="utf-8-sig"))
        assert snapshot["meta"]["product"] == "wowf"
        observed = defaultdict(set)
        for trainer in snapshot["trainers"].values():
            if trainer.get("tradeskill"):
                continue
            for service in trainer["services"].values():
                if service.get("spellId") and isinstance(service.get("level"), int):
                    observed[service["spellId"]].add(service["level"])
        for spell, levels in observed.items():
            positive = {level for level in levels if 1 <= level <= 60}
            if len(positive) == 1:
                outcomes[spell] = positive.pop()
            elif len(positive) > 1 or spell not in outcomes:
                outcomes[spell] = 0
    return outcomes, evidence


def generate(folder, build):
    trainers, evidence = read_trainers(folder, build)
    spell_levels = {int(row["SpellID"]): int(row["SpellLevel"]) for row in rows(folder, "SpellLevels")
                    if row["DifficultyID"] == "0"}
    spell_names = {int(row["ID"]): row["Name_lang"] for row in rows(folder, "SpellName")}
    spell_ranks = {}
    for row in rows(folder, "Spell"):
        match = RANK.fullmatch(row["NameSubtext_lang"].strip())
        if match:
            spell_ranks[int(row["ID"])] = int(match[1])
    class_lines = {line: class_id for class_id, lines in CLASSES.items() for line in lines}
    class_abilities = list(rows(folder, "SkillLineAbility"))
    player_spells = defaultdict(set)
    for row in class_abilities:
        class_id = class_lines.get(int(row["SkillLine"]))
        if class_id:
            player_spells[class_id].add(int(row["Spell"]))
    classes = defaultdict(dict)
    books = {class_id: spellbook_index(folder, class_id) for class_id in CLASSES}
    for class_id, (index, removed) in books.items():
        for spell, (level, rank, source) in index.items():
            if spell not in player_spells[class_id] or spell not in spell_names or spell_names[spell] in removed:
                continue
            # These IDs were identified in the class spellbook, including
            # racial spells (race masks are applied from the DB2 join below).
            level = level or spell_levels.get(spell, 0)
            if 1 <= level <= 60:
                classes[class_id][spell] = (level, rank or spell_ranks.get(spell, 0), source, 0, 0)
    seen_races = set()
    for row in class_abilities:
        class_id = class_lines.get(int(row["SkillLine"]))
        spell = int(row["Spell"])
        if not class_id or not int(row["ClassMask"]) & (1 << (class_id - 1)) or spell not in spell_names:
            continue
        index, removed = books[class_id]
        if spell_names[spell] in removed:
            continue
        preview = index.get(spell)
        if not preview and row["AcquireMethod"] not in {"0", "2"}:
            continue
        source = preview[2] if preview else 0
        if spell in QUESTS:
            source = 2
        elif source in {0, 3} and (spell in trainers or spell in TELEPORTS):
            source = 1
        elif source == 3 and row["AcquireMethod"] == "2":
            source = 0
        if source == 0 and row["AcquireMethod"] != "2":
            continue
        observed = trainers.get(spell) if source == 1 else None
        level = observed or (preview and preview[0]) or spell_levels.get(spell, 0)
        if not 1 <= level <= 60:
            continue
        rank = (preview and preview[1]) or spell_ranks.get(spell, 0)
        race_low = int(row["RaceMasks_0"]) & 0xffffffff
        race_high = int(row["RaceMasks_1"]) & 0xffffffff
        previous = classes[class_id].get(spell)
        if previous and (class_id, spell) in seen_races:
            old_low, old_high = previous[3:]
            if (race_low or race_high) and (old_low or old_high):
                race_low, race_high = race_low | old_low, race_high | old_high
            else:
                race_low, race_high = 0, 0
        classes[class_id][spell] = (level, rank, source, race_low, race_high)
        seen_races.add((class_id, spell))
    # When the verified spellbook chose an ID for a name/rank, drop trainer
    # duplicates for that exact rank unless they belong to a different race.
    for class_id, items in classes.items():
        index, _ = books[class_id]
        verified = {(spell_names[spell], rank, low, high) for spell, (_, rank, _, low, high) in items.items()
                    if spell in index}
        for spell, (_, rank, _, low, high) in list(items.items()):
            if spell not in index and (spell_names[spell], rank, low, high) in verified:
                del items[spell]
    return classes, evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--build", required=True)
    parser.add_argument("--output", type=Path, default=Path("MSUF_Suite_Skin/Adapters/ForeverSpellLearningData.lua"))
    args = parser.parse_args()
    classes, evidence = generate(args.folder, args.build)
    assert set(classes) == set(CLASSES)
    lines = [
        "local _, NS = ...",
        "if not NS.Client.isForever then return end",
        "",
        f"-- Forever {args.build}. Generated by tools/build_forever_spell_learning.py.",
        "-- Blizzard DB2 via https://wago.tools/ (spell IDs, levels, rank and race flags).",
        "-- Trainer observations by Efficient Games (https://efficient.games), CC BY 4.0",
        "-- https://creativecommons.org/licenses/by/4.0/",
        "-- https://github.com/JIVESCORP/eg-link-output-wowf/tree/6ff5612b54191f297eb77ca8eda81de029d9d6f0/data/wowf",
        "-- Class spellbook IDs and learn requirements adapted from Talents Forever (Chris Baldwin),",
        "-- https://talentsforever.com/ (CC BY 4.0). Cross-checked against the client ID table.",
        "-- Spell ID, required level, rank, source (0 automatic, 1 trainer, 2 quest, 3 unspecified, 4 talent), race masks.",
        "NS.ForeverSpellLearningData = {",
    ]
    for key, items in sorted(classes.items()):
        lines.append(f'    [{key}] = ""')
        entries = []
        for spell, values in sorted(items.items(), key=lambda entry: (entry[1][0], entry[0])):
            compact = [spell, *values]
            while compact[-1] == 0 and len(compact) > 4:
                compact.pop()
            entries.append(":".join(str(value) for value in compact))
        for index in range(0, len(entries), 6):
            lines.append("        .. " + '"' + " ".join(entries[index:index + 6]) + ' "')
        lines[-1] += ","
    # A single encoded string per class keeps the index small and defers work
    # to the first time this character opens the preview.
    args.output.write_text("\n".join(lines + ["}", ""]), encoding="utf-8")
    print(", ".join(f"{key}={len(items)}" for key, items in sorted(classes.items())))
    print("Trainer snapshots:", ", ".join(path.name for path in evidence))


if __name__ == "__main__":
    main()
