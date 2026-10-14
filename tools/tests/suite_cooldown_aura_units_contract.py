"""Actual entry routing over the complete pinned native specialization dataset."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("cdm_aura_units", root / "tools/generate_cdm_aura_units.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
data = generator.snapshot(root)
assert len(data["rows"]) == 3048 and len(data["specs"]) == 40
assert len(data["effects"]) == 2432
assert data["build"] == "12.1.5.70391"
players = generator.player_rows(data)
assert len(players) == 165
for record in (105493, 93076, 149268, 53326, 82624):
    assert record in players, "missing audited mixed cast/player buff"
for record in (105403, 100037, 161380, 93100, 198795, 198796):
    assert record not in players, "mixed or unresolved aura aliases must not be forced to player"
subprocess.run([sys.executable, str(root / "tools/generate_cdm_aura_units.py"), "--check"], check=True)
cases = []
for row in data["rows"]:
    if row["id"] in players:
        links = ",".join(map(str, row["linked"]))
        cases.append("{id=%d,spec=%d,base=%d,linked={%s}}" % (row["id"], row["spec"], row["spell"], links))
lua_root = json.dumps(root.as_posix())
probe = r'''
local root=ROOT_PATH
arg={root}
local original=loadfile
local world
loadfile=function(path)
    local file=path:match("MSUF_Suite_CooldownManager/EntryFill.lua$") and os.getenv("MSUF_TEST_ENTRY_FILL_FILE") or path
    local chunk=assert(original(file))
    if path:match("MSUF_Suite_CooldownManager/EntryFill.lua$") then
        return function(addon,private) world=private;return chunk(addon,private) end
    end
    return chunk
end
assert(loadfile(root.."/tools/tests/suite_cooldown_manager_data_contract.lua"))()
local C=assert(world.CDM)
local cases={CASE_ROWS}
C_Spell.IsSpellHarmful=function() return true end
C_Spell.GetSpellName=function() return "Test aura" end
C_Spell.GetSpellTexture=function() return 132287 end
assert(loadfile(root.."/MSUF_Suite_CooldownManager/EntryFill.lua"))("MSUF_Suite_CooldownManager",world)
local Fill=C.EntryFill.Fill
local checked,overlay=0,0
for _,row in ipairs(cases) do
    local rec={id=row.id,spell=row.base,override=row.base,linked=row.linked,
        family=2,category=2,known=true,hasAura=false,selfAura=false}
    C.Catalog.records[row.id]=rec
    local key="b"..row.id
    local entry={key=key}
    assert(Fill(entry,key))
    assert(entry.unit=="player" and entry.auraHelpful,
        "spec "..row.spec.." native row "..row.id.." misrouted to "..tostring(entry.unit))
    -- The same native row can be a cooldown overlay. Without hasAura it
    -- remains a cooldown and receives neither aura IDs nor a unit.
    rec.family,rec.hasAura=1,true
    assert(Fill(entry,key) and entry.unit=="player" and entry.auraIDs)
    overlay=overlay+1
    rec.hasAura=false
    assert(Fill(entry,key) and not entry.unit and not entry.auraIDs)
    -- A new talent override, tooltip or linked alias invalidates the
    -- audited identity set; it must retain the original automatic route.
    rec.family,rec.hasAura=2,false
    rec.override=2147483001
    assert(Fill(entry,key) and entry.unit=="target","unreviewed override was forced to player")
    rec.override=row.base;rec.tooltip=2147483002
    assert(Fill(entry,key) and entry.unit=="target","unreviewed tooltip was forced to player")
    rec.tooltip=nil;rec.linked={2147483003}
    assert(Fill(entry,key) and entry.unit=="target","unreviewed linked aura was forced to player")
    rec.linked=row.linked
    world.NS.Client.isForever=true
    assert(Fill(entry,key) and entry.unit=="target","Retail snapshot affected Forever")
    world.NS.Client.isForever=false
    checked=checked+1
end
for _,row in ipairs({
    {105403,385627,{}}, -- Kingsbane has both caster and enemy auras.
    {100037,12846,{12654}}, -- Ignite's caster talent marker must not win.
    {93100,274837,{274838}}, -- Feral Frenzy keeps its linked target DoT.
    {198795,228920,{1299405}}, -- Ravager has a linked target debuff.
}) do
    C.Catalog.records[row[1]]={id=row[1],spell=row[2],override=row[2],linked=row[3],family=2,known=true}
    local entry={}
    assert(Fill(entry,"b"..row[1]) and entry.unit=="target","target aura regression")
end
-- Actual native override lifecycle through Catalog and the real routing index.
assert(loadfile(root.."/MSUF_Suite_CooldownManager/Resolve.lua"))("MSUF_Suite_CooldownManager",world)
local CDM=world.NS.CDM
local info={cooldownID=105493,spellID=32645,overrideSpellID=32645,linkedSpellIDs={},
    isKnown=true,category=2,flags=0,selfAura=false,hasAura=false}
C_CooldownViewer.GetCooldownViewerCategorySet=function(category) return category==2 and {105493} or {} end
C_CooldownViewer.GetCooldownViewerCooldownInfo=function(id) return id==105493 and info end
for _,view in pairs(C.views) do view.on=false end
C.state.specID,C.state.preview,C.state.raidEssentials=259,false,false
for _,kind in ipairs({2,3}) do
    local slot=kind==2 and "buf" or "bar"
    C.lists=CDM.CleanLists({specs={[259]={[slot]={"b105493"}}},replace={[259]={[slot]=true}}})
    C.views.buf.on,C.views.bar.on=kind==2,kind==3
    for _,choice in ipairs({1,2,3,4}) do
        info.overrideSpellID=32645
        C.Catalog.Rebuild()
        C.spells=CDM.CleanSpells({v=1,e={b105493={auraUnit=choice}}})
        C.Resolve.Build();C.Index.Rebuild()
        local entry=assert(C.entries.b105493,"override setup lost Envenom on "..slot.."/"..choice)
        local configured=({"player","player","target","both"})[choice]
        assert(entry.slot==slot and entry.unit==configured and entry.auraHelpful,
            "override setup "..slot.."/"..choice..": "..tostring(entry.slot).."/"..tostring(entry.unit).."/"..tostring(entry.auraHelpful))
        assert(C.Catalog.OnOverride(32645,2147483001))
        local changed=choice==1 and "target" or configured
        assert(entry.unit==changed and not entry.auraHelpful and entry.auraIDs[2147483001],
            "unknown harmful event override retained stale player aura route")
        assert(C.Catalog.OnOverride(32645,2147483002))
        assert(not entry.auraIDs[2147483001] and entry.auraIDs[2147483002],"old override aura ID survived replacement")
        assert(C.Catalog.OnOverride(32645,nil))
        assert(entry.unit==configured and entry.auraHelpful and entry.auraIDs[32645]
            and not entry.auraIDs[2147483002],"override removal did not restore the native player identity")
    end
end
info.overrideSpellID=2147483001
C.Catalog.Rebuild()
C.spells=CDM.CleanSpells({v=1,e={b105493={auraUnit=1,timerDuration=10}}})
C.Resolve.Build();C.Index.Rebuild()
local timed=assert(C.entries.b105493)
assert(timed.unit=="target" and not timed.timer and not C.plans.bar.hasTimers)
assert(C.Catalog.OnOverride(32645,nil))
assert(timed.unit=="player" and timed.timer and C.plans.bar.hasTimers,"override gained a timer without updating its plan")
assert(C.Catalog.OnOverride(32645,2147483001))
assert(not timed.timer and not C.plans.bar.hasTimers,"override lost its last timer without updating its plan")
-- Losing this timer must preserve another timer on the same plan.
assert(C.Catalog.OnOverride(32645,nil))
local sibling={timer=true}
table.insert(C.plans.bar.entries,sibling)
assert(C.Catalog.OnOverride(32645,2147483001))
assert(not timed.timer and C.plans.bar.hasTimers,"override removed another entry's timer demand")
table.remove(C.plans.bar.entries)
print("native aura routing: "..checked.." player rows, "..overlay.." cooldown overlays; changed identities and Forever preserved")
'''.replace("ROOT_PATH", lua_root).replace("CASE_ROWS", ",\n".join(cases))
lua = os.environ.get("MSUF_LUA51", r"C:\Users\Marco\AppData\Local\Temp\msuf-lua51\portable\lua.exe")
with tempfile.TemporaryDirectory(prefix="suite-cdm-units-") as directory:
    path = Path(directory) / "probe.lua"
    path.write_text(probe, encoding="utf-8")
    subprocess.run([lua, str(path)], cwd=root, check=True)
print("all 40 native specs audited; 3048 source rows, 165 conservative player routes")
