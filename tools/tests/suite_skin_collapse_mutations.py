"""Verify the shared native collapse lifecycle detects removal of each guard."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
LUA = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
TEST = ROOT / "tools/tests/suite_skin_collapse_contract.lua"
SKIN = ROOT / "MSUF_Suite_Skin"
MUTANTS = (
    ("native tree discovery", "Rendering/CollapseRows.lua",
     'if Safety.HasMethod(provider, "GetRootNode") then return "tree" end',
     'if false then return "tree" end', "generic native tree categories"),
    ("independent branch clips", "Adapters/AddonListGhosts.lua",
     '    if state.generic then\n        clip =', '    if false then\n        clip =', "destructive clip"),
    ("authored opacity", "Adapters/AddonListGhosts.lua",
     'effective / (base * rowAlpha)', 'effective / base', "compounded native row opacity"),
    ("provider snapshot invalidation", "Adapters/AddonListGhosts.lua",
     'copy.provider == state.provider and not copy.dirty', 'not copy.dirty', "provider replacement retained stale"),
    ("initialized row invalidation", "Adapters/AddonListGhosts.lua",
     'record.ghost.dirty = true', 'record.ghost.dirty = false', "initialization retained stale"),
    ("legacy scroll cancellation", "Adapters/AddonListMotion.lua",
     'root:HookScript("OnVerticalScroll", CollectionScrolled)', '-- native scroll cancellation removed', "legacy scrolling retained"),
    ("journal native identity", "Rendering/CollapseCollectionRows.lua",
     'Safety.Field(row, "myID") or Safety.Field(row, "sectionID")',
     'Safety.Field(row, "sectionID")', "native journal myID"),
    ("journal completed layout", "Rendering/CollapseCollections.lua",
     'if Safety.Public(doNotShift) and doNotShift ~= true then EncounterLayoutFinished() end',
     'EncounterLayoutFinished()', "recursive journal callback"),
    ("compositor row refusal", "Adapters/AddonListMotion.lua",
     'return Safety.CanCreateRegions(row) and not Safety.GetProtection(row)',
     'return not Safety.IsForbidden(row) and not Safety.GetProtection(row)', "compositor row indexed"),
    ("compositor glyph refusal", "Rendering/CollapseRows.lua",
     'if Safety.CanCreateRegions(arrow) and Safety.HasMethod(arrow, "CreateAnimationGroup")',
     'if arrow and Safety.HasMethod(arrow, "CreateAnimationGroup")', "compositor glyph indexed"),
    ("result fade cancellation", "Rendering/ResultMotion.lua",
     'if collapsed then Cancel(state) end', '-- previous result fade retained', "same-provider collapse retained"),
    ("nested transform deduplication", "Adapters/AddonListMotion.lua",
     'if parent and parent.group and Safety.Read(parent.group, "IsPlaying") then Stop(record) return end',
     '-- native child receives duplicate transform', "translation twice"),
    ("nested rendered origin", "Adapters/AddonListGhosts.lua",
     'if parent then\n        if parent.group', 'if false then\n        if parent.group', "moving parent's rendered offset"),
    ("offscreen ancestor snapshot", "Adapters/AddonListMotion.lua",
     'local value = Safety.Call(node, "IsCollapsed")', 'local value = nil', "offscreen expanded ancestor"),
    ("eight texture coordinates", "Adapters/AddonListGhosts.lua",
     'target:SetTexCoord(a, b, c, d, e, f, g, h)',
     'target:SetTexCoord(a, b, c, d)', "rotated texture coordinates"),
)


def run(env):
    return subprocess.run([LUA, str(TEST), str(ROOT), "Mainline"], cwd=ROOT,
                          env=env, text=True, capture_output=True)


baseline = run(os.environ.copy())
assert baseline.returncode == 0, baseline.stdout + baseline.stderr
for name, path, old, new, expected in MUTANTS:
    source = (SKIN / path).read_text(encoding="utf-8")
    assert source.count(old) == 1, (name, source.count(old))
    with tempfile.TemporaryDirectory(prefix="suite-collapse-") as directory:
        changed = Path(directory) / path
        changed.parent.mkdir(parents=True)
        changed.write_text(source.replace(old, new, 1), encoding="utf-8")
        result = run(dict(os.environ, SUITE_TRANSITION_OVERRIDE_ROOT=directory))
        assert result.returncode != 0 and expected in result.stderr, (name, result.stdout + result.stderr)
    print(f"ok   {name}")
print(f"Suite collapse mutations: {len(MUTANTS)} causal regressions detected")
