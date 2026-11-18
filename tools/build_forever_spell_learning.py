"""Generate the Forever spellbook learning index from public game data.

Download SkillLineAbility, SpellLevels, Spell and SpellName as CSV from
https://wago.tools/db2/ for the requested build. Download trainers.json and
any earlier same-product trainers-*.json from Efficient Games into that folder.
Save https://talentsforever.com/export/<class>.json as class-<class>.json.
Only the spell IDs and acquisition metadata are used from the CC BY 4.0 exports.
Reviewed class-quest variants and prerequisite facts live in
tools/data/forever_spell_sources.json, with their pinned sources and licences.
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
    index, families = {}, defaultdict(list)
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
            source = 2 if description.get("ns") == "quest" else {1: 6, 2: 5, 4: 3}.get(description.get("nt"), 1)
            index[spell] = (int(level[1]) if level else 0, int(rank[1]) if rank else 0, source, 0)
            families[spell_name].append((spell, description.get("nt") == 3))
    for spell_name in book["talents"]:
        family = families.get(spell_name, [])
        if not family:
            continue
        grants = [spell for spell, direct in family if direct]
        # Some exports omit nt=3 on an active talent (e.g. Mutilate).
        # Use this class's first spell rank, never a passive talent with a
        # similar effect or an old ID from a different client branch.
        root = min(grants or [spell for spell, _ in family], key=lambda spell: (index[spell][1], index[spell][0], spell))
        for spell, _ in family:
            level, rank, _, _ = index[spell]
            index[spell] = (level, rank, 4 if spell == root else 1, 0 if spell == root else root)
    return index, set(book.get("gone", ()))


def read_sources(path=None):
    path = path or Path(__file__).with_name("data") / "forever_spell_sources.json"
    catalog = json.loads(path.read_text(encoding="utf-8"))
    assert set(map(int, catalog["classes"])) == set(CLASSES)
    return catalog


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


def read_training_costs(evidence):
    """Retain observed undiscounted copper prices, never infer a discount."""
    prices = {}
    for path in evidence:
        snapshot = json.loads(path.read_text(encoding="utf-8-sig"))
        assert snapshot["meta"]["product"] == "wowf"
        observed = defaultdict(set)
        for trainer in snapshot["trainers"].values():
            if trainer.get("tradeskill"):
                continue
            for service in trainer["services"].values():
                spell = service.get("spellId")
                if type(spell) is not int or spell <= 0:
                    continue
                # The dataset separates Legacy Bartering. Neutral/Friendly
                # observations have no reputation discount; higher ranks do.
                for standing, copper in service.get("costs", {}).items():
                    if standing in {"4", "5"} and type(copper) is int and 0 <= copper <= 2**53 - 1:
                        observed[spell].add(copper)
        for spell, costs in observed.items():
            if len(costs) == 1:
                prices[spell] = costs.pop()
            else:
                prices.pop(spell, None)
    return prices


def generate(folder, build, catalog=None):
    catalog = catalog or read_sources()
    assert catalog["build"] == build
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
        for spell, (level, rank, source, talent) in index.items():
            if spell not in player_spells[class_id] or spell not in spell_names or spell_names[spell] in removed:
                continue
            # These IDs were identified in the class spellbook, including
            # racial spells (race masks are applied from the DB2 join below).
            level = level or spell_levels.get(spell, 0)
            if 1 <= level <= 60:
                classes[class_id][spell] = (level, rank or spell_ranks.get(spell, 0), source, 0, 0, talent, 0)
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
        if source in {0, 1, 3} and spell in trainers:
            source = 1
        elif spell in TELEPORTS:
            source = 6
        elif source in {1, 3} and row["AcquireMethod"] == "2" and not (preview and preview[3]):
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
            old_low, old_high = previous[3:5]
            if (race_low or race_high) and (old_low or old_high):
                race_low, race_high = race_low | old_low, race_high | old_high
            else:
                race_low, race_high = 0, 0
        classes[class_id][spell] = (level, rank, source, race_low, race_high, preview[3] if preview else 0, 0)
        seen_races.add((class_id, spell))
    apply_sources(classes, catalog, spell_names, spell_ranks)
    # When the verified spellbook chose an ID for a name/rank, drop trainer
    # duplicates for that exact rank unless they belong to a different race.
    for class_id, items in classes.items():
        index, _ = books[class_id]
        verified = {(spell_names[spell], value[1], value[3], value[4]) for spell, value in items.items()
                    if spell in index}
        for spell, value in list(items.items()):
            if spell not in index and (spell_names[spell], value[1], value[3], value[4]) in verified:
                del items[spell]
    return classes, evidence


def apply_sources(classes, catalog, names, ranks):
    for class_id, metadata in catalog["classes"].items():
        class_id = int(class_id)
        items = classes[class_id]
        for spell, variants in metadata["quests"].items():
            spell = int(spell)
            if spell not in names:
                continue
            only_races = spell in metadata["quest_only_for_listed_races"]
            level = min(variant["level"] for variant in variants)
            old = items.get(spell, (level, ranks.get(spell, 0), 3, 0, 0, 0, 0))
            # Per-race quest exceptions are applied by ReadIndex. Other
            # races retain the native automatic/trainer source and level.
            items[spell] = (old[0] if only_races else level, old[1], old[2] if only_races else 2, *old[3:])
        for spell, level in metadata["extra_training"].items():
            spell = int(spell)
            if spell in names:
                items[spell] = (level, 0, 1, 0, 0, 0, 0)
        quest_families = {names[int(spell)]: int(spell) for spell in metadata["quests"]
                          if int(spell) in items and items[int(spell)][1] == 1}
        for spell, value in list(items.items()):
            level, rank, source, low, high, talent, _ = value
            quest = metadata["quest_requirements"].get(str(spell), 0)
            family_root = quest_families.get(names[spell])
            if family_root and family_root != spell and rank > 1:
                quest = family_root
            items[spell] = (level, rank, source, low, high, talent, quest if quest in items and source in {1, 6} else 0)


def packed_lines(entries):
    chunk = []
    for entry in entries:
        if chunk and len(" ".join([*chunk, entry])) > 140:
            yield '        .. "' + " ".join(chunk) + ' "'
            chunk = []
        chunk.append(entry)
    if chunk:
        yield '        .. "' + " ".join(chunk) + ' "'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--build", required=True)
    parser.add_argument("--output", type=Path, default=Path("MSUF_Suite_Skin/Adapters/ForeverSpellLearningData.lua"))
    args = parser.parse_args()
    classes, evidence = generate(args.folder, args.build)
    costs = read_training_costs(evidence)
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
        "-- Quest variants/prerequisites adapted from and cross-checked with What's Training (MIT),",
        "-- revision 6e289b0c2acd1c933f5a6317d960ff67a01da118.",
        "-- https://github.com/fusionpit/WhatsTraining -- see THIRD_PARTY_NOTICES.txt.",
        "-- Sources: 0 automatic, 1 trainer, 2 quest, 3 unconfirmed, 4 talent grant, 5 item/tome, 6 portal trainer.",
        "-- Fields: spell ID, level, rank, source, race masks, required talent ID, required quest-spell ID.",
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
        lines.extend(packed_lines(entries))
        lines[-1] += ","
    lines += ["}", "", "-- Observed class-training prices in copper, before reputation or Legacy discounts.",
              "-- Missing entries have no confirmed undiscounted price; zero is an observed free service.",
              "NS.ForeverSpellLearningCosts = {"]
    for class_id, items in sorted(classes.items()):
        entries = [f"{spell}:{costs[spell]}" for spell, values in sorted(items.items())
                   if spell in costs and values[2] in {1, 6}]
        lines.append(f'    [{class_id}] = ""')
        for index in range(0, len(entries), 8):
            lines.append('        .. "' + " ".join(entries[index:index + 8]) + ' "')
        lines[-1] += ","
    # A single encoded string per class keeps the index small and defers work
    # to the first time this character opens the preview.
    catalog = read_sources()
    lines += ["}", "", "-- ChrRaces.PlayableRaceBit is independent of race ID (Skyborne IDs are 95/96).",
              "NS.ForeverSpellLearningRaceBits = { " + ", ".join(f"[{race}] = {bit}" for race, bit in catalog["race_bits"].items()) + " }",
              "", "-- Per-race quest source and minimum level: spell ID, race ID, level.",
              "NS.ForeverSpellLearningQuestSources = {"]
    for class_id, metadata in catalog["classes"].items():
        entries = sorted({(int(spell), race, variant["level"]) for spell, variants in metadata["quests"].items()
                          for variant in variants for race in variant["races"]})
        lines.append(f'    [{class_id}] = ""')
        for index in range(0, len(entries), 7):
            lines.append('        .. "' + " ".join(":".join(map(str, value)) for value in entries[index:index + 7]) + ' "')
        lines[-1] += ","
    lines += ["}", "", "-- Quest rewards whose availability is not confirmed by current server observations.",
              "-- Keep these red until active acquisition is verified; a client record alone is insufficient.",
              "NS.ForeverSpellLearningPendingQuests = {"]
    for class_id, metadata in catalog["classes"].items():
        pending = metadata.get("pending_quests", {})
        if pending:
            entries = [f"{spell}:{quest}" for spell, quest in sorted(pending.items(), key=lambda row: int(row[0]))]
            lines.append(f'    [{class_id}] = "' + " ".join(entries) + ' ",')
    args.output.write_text("\n".join(lines + ["}", ""]), encoding="utf-8")
    print(", ".join(f"{key}={len(items)}" for key, items in sorted(classes.items())))
    print("Trainer snapshots:", ", ".join(path.name for path in evidence))


if __name__ == "__main__":
    main()
