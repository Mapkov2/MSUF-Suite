"""Verify acquisition and prerequisites independently for all Forever classes."""
import csv
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("learning_builder", root / "tools/build_forever_spell_learning.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def write_csv(folder, table, columns, records):
    with (folder / (table + ".csv")).open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        writer.writerows(records)


with tempfile.TemporaryDirectory(prefix="suite-learning-data-") as temporary:
    folder = Path(temporary)
    priest = [(15237, "Holy Nova", 1, 20), (15430, "Holy Nova", 2, 28),
              (15407, "Mind Flay", 1, 20), (17311, "Mind Flay", 2, 28),
              (14751, "Inner Focus", 0, 20), (10060, "Power Infusion", 0, 40)]
    talents = {1: (12294, 21551, "Mortal Strike"), 2: (20925, 20927, "Holy Shield"),
               3: (19306, 20909, "Counterattack"), 4: (16511, 17347, "Hemorrhage"),
               7: (16190, 17354, "Mana Tide Totem"), 8: (11113, 13018, "Blast Wave"),
               9: (18265, 18879, "Siphon Life"), 11: (5570, 24974, "Insect Swarm")}
    quest_spells = {1: 355, 2: 7328, 3: 1515, 4: 2842, 5: 10797, 7: 8071, 8: 10140, 9: 688, 11: 768}
    spells = []
    class_spells = {}
    for class_id, name in builder.CLASS_NAMES.items():
        active = priest if class_id == 5 else [(talents[class_id][0], talents[class_id][2], 1, 20),
                                               (talents[class_id][1], talents[class_id][2], 2, 28)]
        normal = (1082 if class_id == 11 else 8000000 + class_id, "Claw" if class_id == 11 else "Trainer Spell", 1, 20)
        records = active + [normal, (quest_spells[class_id], "Quest Unlock", 0, 10)]
        if class_id == 8:
            records.append((1297659, "Teleport: Dalaran", 0, 50))
        class_spells[class_id] = records
        spells.extend(records)
        exported = {
            "_readme": "CC BY 4.0 synthetic fixture",
            "class": name.title(),
            "spellbook": {"tabs": [], "talents": [], "gone": []},
            "spell_desc": {},
        }
        exported["spellbook"]["talents"] = sorted({name for _, name, _, _ in active})
        exported["spellbook"]["tabs"] = [{
            "name": "Class",
            "spells": [[name, f"Rank {rank}" if rank else ""] for _, name, rank, _ in records],
        }]
        exported["spell_desc"] = {
            f"{exported['class']}|{name}|" + (f"Rank {rank}" if rank else ""):
                {"id": spell, "lv": f"Learned at level {level}"}
            for spell, name, rank, level in records
        }
        (folder / f"class-{name}.json").write_text(json.dumps(exported), encoding="utf-8")
    write_csv(folder, "SpellName", ["ID", "Name_lang"],
              [{"ID": spell, "Name_lang": name} for spell, name, _, _ in spells])
    write_csv(folder, "Spell", ["ID", "NameSubtext_lang"],
              [{"ID": spell, "NameSubtext_lang": f"Rank {rank}" if rank else ""} for spell, _, rank, _ in spells])
    write_csv(folder, "SpellLevels", ["SpellID", "DifficultyID", "SpellLevel"],
              [{"SpellID": spell, "DifficultyID": 0, "SpellLevel": level} for spell, _, _, level in spells])
    write_csv(folder, "SkillLineAbility",
              ["SkillLine", "Spell", "ClassMask", "AcquireMethod", "RaceMasks_0", "RaceMasks_1"],
              [{"SkillLine": builder.CLASSES[class_id][0], "Spell": spell,
                "ClassMask": 1 << (class_id - 1), "AcquireMethod": 0, "RaceMasks_0": 0, "RaceMasks_1": 0}
               for class_id, records in class_spells.items() for spell, _, _, _ in records])
    (folder / "trainers.json").write_text(json.dumps({
        "meta": {"clientBuild": "1.60.1.70938", "product": "wowf"},
        "trainers": {"priest": {"services": {
            "nova1": {"spellId": 15237, "level": 20, "costs": {"5": 0}},
            "nova2": {"spellId": 15430, "level": 28, "costs": {"5": 5300, "6": 4770}},
            "flay2": {"spellId": 17311, "level": 28, "costs": {"6": 4770}},
            "focus": {"spellId": 14751, "level": 20, "costs": {"6": 90}, "bartered": {"1": {"5": 1}}},
            "power": {"spellId": 10060, "level": 40, "costs": {"5": 1000}},
        }}, "other": {"services": {"power": {"spellId": 10060, "costs": {"5": 2000}}}},
            "profession": {"tradeskill": True, "services": {
                "nova2": {"spellId": 15430, "costs": {"5": 1}},
            }}},
    }), encoding="utf-8")
    (folder / "trainers-previous.json").write_text(json.dumps({
        "meta": {"product": "wowf"}, "trainers": {"priest": {"services": {
            "nova1": {"spellId": 15237, "costs": {"5": 100}},
            "nova2": {"spellId": 15430, "costs": {"5": 5000}},
            "flay2": {"spellId": 17311, "costs": {"4": 5300}},
            "power": {"spellId": 10060, "costs": {"5": 999}},
        }}},
    }), encoding="utf-8")
    classes, _ = builder.generate(folder, "1.60.1.70938")
    for spell in (15237, 15407):
        assert classes[5][spell][2] == 4, f"{spell} lost its direct talent acquisition"
    for spell, required in ((15430, 15237), (17311, 15407)):
        assert classes[5][spell][2] == 1 and classes[5][spell][5] == required, "trainer rank lost its actual talent prerequisite"
    for spell in (14751, 10060):
        assert classes[5][spell][2] == 4, f"{spell} lost its genuine talent requirement"
    assert classes[5][15430][:2] == (28, 2), "trainer rank and learning level changed"
    for class_id, (base, higher, _) in talents.items():
        assert classes[class_id][base][2] == 4, f"class {class_id} talent root was classified as training"
        assert classes[class_id][higher][2] == 1 and classes[class_id][higher][5] == base, f"class {class_id} trainer prerequisite wrong"
    for class_id, quest in quest_spells.items():
        assert classes[class_id][quest][2] == 2, f"class {class_id} quest unlock became a talent or trainer spell"
        normal = 1082 if class_id == 11 else 8000000 + class_id
        assert classes[class_id][normal][2] == 1 and classes[class_id][normal][5] == 0, "a normal trainer spell acquired a talent prerequisite"
    catalog = builder.read_sources()
    assert classes[8][1297659][0:3] == (50, 0, 2), "Teleport: Dalaran was assigned a trainer or talent source"
    assert catalog['classes']['8']['pending_quests'] == {'1297659': 96828}, "Dalaran's unconfirmed quest became confirmed"
    assert catalog["race_bits"]["95"] == 32 and catalog["race_bits"]["96"] == 33, "race IDs were mistaken for playable mask bits"
    assert catalog["classes"]["2"]["quest_only_for_listed_races"] == [635], "Holy Light quest was applied to every Paladin race"
    assert catalog["classes"]["3"]["quests"]["883"] == catalog["classes"]["3"]["quests"]["1515"], "Call Pet attached to the wrong hunter quest"
    _, evidence = builder.read_trainers(folder, "1.60.1.70938")
    costs = builder.read_training_costs(evidence)
    assert costs[15237] == 0, "an observed free price was discarded"
    assert costs[15430] == 5300, "newer base price was ignored or discounted/profession price was used"
    assert costs[17311] == 5300, "a discounted-only sample erased the observed undiscounted price"
    assert 14751 not in costs, "discounted or Legacy Bartering prices became fabricated base costs"
    assert 10060 not in costs, "conflicting current prices reused an older or arbitrary price"
print("suite_forever_spell_learning_data_contract: ok")
