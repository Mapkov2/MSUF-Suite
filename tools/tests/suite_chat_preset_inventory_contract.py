"""Preset extension must retain every frozen chat value and existing choice."""
import json
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(ROOT / "tools"))
import suite_inventory_diff as inventory

baseline = json.loads((ROOT / "tools/suite_inventory_baseline.json").read_text(encoding="utf-8"))["items"]
for client in ("retail", "forever"):
    rows = inventory.catalog(ROOT, client)
    current = {inventory.item(*row[1:]): row for row in rows}
    traits = {row[2]: row[3] for row in rows if row[0] == "module_traits" and row[1] == client + ":chat"}
    checked = 0
    for encoded in baseline["module_traits"]:
        owner, key, value = json.loads(encoded)
        if owner != client + ":chat" or key not in ("conflicts", "look.visualKeys", "look.presets.1",
                                                      "look.presets.2", "look.presets.3", "look.presets.5", "look.presets.6"):
            continue
        actual = dict(traits[key])
        for old_key, old_value in value:
            assert actual.get(old_key) == old_value, f"{client}:{key} lost frozen {old_key}={old_value!r}"
        checked += 1
    assert checked == 7, "not every extended chat trait was checked"
    for encoded in baseline["choices"]:
        if json.loads(encoded)[0] == client + ":chat.look":
            assert encoded in current, "a pre-existing look choice changed index or label"
    old = next(json.loads(row) for row in baseline["rule_metadata"] if json.loads(row)[0] == client + ":chat.look")
    actual = next(row[1:] for row in rows if row[0] == "rule_metadata" and row[1] == client + ":chat.look")
    assert old[4] == 6 and actual[4] == 7 and old[:4] + old[5:] == actual[:4] + actual[5:], "look limits changed beyond appending one choice"
print("Both clients retain frozen chat palette values, conflict IDs, visual keys and choice indices")
