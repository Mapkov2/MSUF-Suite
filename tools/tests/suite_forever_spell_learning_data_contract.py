"""Keep Forever trainer spells independent of stale exported talent labels."""
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
    spells = [
        (15237, "Holy Nova", 1, 20), (15430, "Holy Nova", 2, 28),
        (15407, "Mind Flay", 1, 20), (17311, "Mind Flay", 2, 28),
        (14751, "Inner Focus", 0, 20), (10060, "Power Infusion", 0, 40),
    ]
    for class_id, name in builder.CLASS_NAMES.items():
        exported = {
            "_readme": "CC BY 4.0 synthetic fixture",
            "class": name.title(),
            "spellbook": {"tabs": [], "talents": [], "gone": []},
            "spell_desc": {},
        }
        if class_id == 5:
            exported["spellbook"]["talents"] = [name for _, name, _, _ in spells]
            exported["spellbook"]["tabs"] = [{
                "name": "Priest",
                "spells": [[name, f"Rank {rank}" if rank else ""] for _, name, rank, _ in spells],
            }]
            exported["spell_desc"] = {
                f"Priest|{name}|" + (f"Rank {rank}" if rank else ""):
                    {"id": spell, "lv": f"Learned at level {level}"}
                for spell, name, rank, level in spells
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
              [{"SkillLine": 56, "Spell": spell, "ClassMask": 16, "AcquireMethod": 0,
                "RaceMasks_0": 0, "RaceMasks_1": 0} for spell, _, _, _ in spells])
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
    for spell in (15237, 15430, 15407, 17311):
        assert classes[5][spell][2] == 1, f"{spell} inherited the stale talent requirement"
    for spell in (14751, 10060):
        assert classes[5][spell][2] == 4, f"{spell} lost its genuine talent requirement"
    assert classes[5][15430][:2] == (28, 2), "trainer rank and learning level changed"
    _, evidence = builder.read_trainers(folder, "1.60.1.70938")
    costs = builder.read_training_costs(evidence)
    assert costs[15237] == 0, "an observed free price was discarded"
    assert costs[15430] == 5300, "newer base price was ignored or discounted/profession price was used"
    assert costs[17311] == 5300, "a discounted-only sample erased the observed undiscounted price"
    assert 14751 not in costs, "discounted or Legacy Bartering prices became fabricated base costs"
    assert 10060 not in costs, "conflicting current prices reused an older or arbitrary price"
print("suite_forever_spell_learning_data_contract: ok")
