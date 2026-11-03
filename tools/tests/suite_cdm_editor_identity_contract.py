"""Inactive-spec native rows keep one saved identity, with bounded live fallback."""
import subprocess
import sys
from pathlib import Path

from suite_factory_profile_smoke import LUA as lua

root = Path(sys.argv[1]).resolve()
source = (root / 'tools/tests/suite_cdm_editor_defaults_contract.lua').read_text(encoding='utf-8-sig')
checks = r'''
do (function()
    local failures, nativeCalls = 0, 0
    C.state.specID = 63
    C.GuideProfiles[72] = nil
    C_Spell.GetBaseSpell = function() error('inactive editor queried current base spell') end
    C_SpellBook.IsSpellKnownOrInSpellBook = function() error('inactive editor queried current spellbook') end
    GetInventoryItemID = function() error('inactive editor queried current equipment') end
    C_Item.GetItemNameByID = function(id) return 'Item' .. id end
    C_Item.GetItemIconByID = function(id) return id + 2000 end
    local function Case(name, body)
        local ok, why = pcall(body)
        print((ok and 'PASS ' or 'FAIL ') .. name .. (ok and '' or ': ' .. tostring(why)))
        if not ok then failures = failures + 1 end
    end
    local function Saved(override, linked, aura)
        return {key='b101',name='Saved talent',texture=970001,spell=700001,override=override,
            linked=linked,family=1,slot='ess',known=true,hasAura=aura}
    end
    local live = {spellID=800001,overrideSpellID=800002,linkedSpellIDs={800003},hasAura=true}
    local function Context(saved, info, entries, shared)
        nativeCalls = 0
        C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
            nativeCalls = nativeCalls + 1
            if id == 101 or id == 102 then return info end
        end
        local rows = saved and {saved,defaults={ess={'b101'}}} or nil
        NS.RootDB.cdmEditorCatalog[profile][72] = rows
        config.listsData = assert(CDM.Codec.EncodeLists(CDM.CleanLists({
            specs={[72]={ess=entries}},shared=shared and {c1=shared} or nil})))
        config.raidEssentials, config[CDM.KEYS.def.on] = false, false
        config[CDM.KEYS.c1.shareContents], config[CDM.KEYS.c1.kind] = shared ~= nil, CDM.KIND.COOLDOWN
        config[CDM.KEYS.c2.shareContents] = false
        C.Catalog.generation = C.Catalog.generation + 1
        return C.Editor.Context(72, 1, config)
    end
    Case('saved override, linked aliases, name and icon survive different current talents', function()
        local saved = Saved(700002, {700003}, true)
        local ctx = Context(saved, live)
        local row = assert(ctx.records.b101)
        assert(row.spell == 700002 and row.base == 700001 and row.override == 700002, 'mixed spell identity')
        assert(row.name == saved.name and row.texture == saved.texture, 'current name or icon substituted')
        assert(row.linked == saved.linked and row.hasAura == true, 'saved linked or aura metadata lost')
        assert(ctx.spellKey[700001] == 'b101' and ctx.spellKey[700002] == 'b101'
            and ctx.spellKey[700003] == 'b101', 'saved claim aliases missing')
        assert(not ctx.spellKey[800001] and not ctx.spellKey[800002] and not ctx.spellKey[800003], 'current aliases leaked')
        assert(nativeCalls == 0, 'saved row queried current native metadata')
        assert(saved.spell == 700001 and saved.override == 700002 and saved.linked[1] == 700003, 'saved catalog mutated')
    end)
    Case('saved absence of override, linked and aura is authoritative', function()
        local ctx = Context(Saved(nil, nil, false), live)
        local row = ctx.records.b101
        assert(row.spell == 700001 and row.base == 700001 and row.override == nil, 'new current override leaked')
        assert(row.linked == nil and row.hasAura == false, 'current linked or aura presence leaked')
        assert(not ctx.spellKey[800002] and not ctx.spellKey[800003], 'absent saved aliases enriched from current spec')
    end)
    Case('removed current override leaves saved effective spell intact', function()
        local row = Context(Saved(700002, {}, true), {spellID=700001,hasAura=false}).records.b101
        assert(row.spell == 700002 and row.override == 700002 and row.hasAura, 'current override removal changed saved row')
    end)
    Case('missing live native record still uses saved override', function()
        local row = Context(Saved(700002, {700003}, false), nil).records.b101
        assert(row.spell == 700002 and row.name == 'Saved talent' and row.texture == 970001,
            'missing native record fell back to saved base instead of effective identity')
    end)
    Case('missing saved display uses saved effective spell metadata only', function()
        local saved = Saved(700002, {}, false)
        saved.name, saved.texture = nil, nil
        local row = Context(saved, live).records.b101
        assert(row.name == 'Spell700002' and row.texture == 701002 and not row.unavailable, 'wrong display fallback')
        assert(nativeCalls == 0, 'display fallback consulted current native record')
    end)
    Case('native equipment and category rows retain remembered display without a spell', function()
        local saved = Saved(nil, {}, false)
        saved.spell, saved.name, saved.texture, saved.equipSlot, saved.spellCategory = nil, 'Saved trinket', 970013, 13, 9
        local row = Context(saved, live).records.b101
        assert(row.spell == nil and row.base == nil and row.override == nil, 'current gear spell substituted')
        assert(row.name == 'Saved trinket' and row.texture == 970013 and row.equipSlot == 13 and row.spellCategory == 9,
            'saved equipment or category display lost')
        assert(nativeCalls == 0, 'saved gear queried current native metadata')
    end)
    Case('synthetic current spell ID cannot claim the remembered native row', function()
        local ctx = Context(Saved(700002, {700003}, false), live, nil, {'s800002'})
        assert(Keys(ctx.bars.ess) == 'b101' and Keys(ctx.bars.c1) == 's800002', 'current alias stole saved native home')
    end)
    Case('saved linked and override aliases still claim one native home', function()
        local ctx = Context(Saved(700002, {700003}, false), live, nil, {'s700003','s700002','s700001'})
        assert(Keys(ctx.bars.ess) == '' and Keys(ctx.bars.c1) == 's700003', 'saved native claim equivalence changed')
    end)
    Case('native entry without saved metadata retains live fallback', function()
        local ctx = Context(nil, live, {'b102'})
        local row = assert(ctx.records.b102)
        assert(row.base == 800001 and row.spell == 800002 and row.override == 800002, 'live fallback spell identity lost')
        assert(row.name == 'Spell800002' and row.texture == 801002 and row.hasAura and row.linked[1] == 800003,
            'live fallback display or linked metadata lost')
        assert(nativeCalls == 1, 'unexpected native metadata query count')
        assert(C.Editor.Context(72, 1, config) == ctx and nativeCalls == 1, 'warm editor cache repeated native work')
    end)
    Case('direct spell, aura, duration, item and equipped-slot entries keep their safe paths', function()
        local ctx = Context(nil, live, {'s900001','a900002','d900003','i900004','e13'})
        assert(ctx.records.s900001.spell == 900001 and ctx.records.s900001.name == 'Spell900001', 'direct spell changed')
        assert(ctx.records.a900002.spell == 900002 and ctx.records.a900002.texture == 901002, 'direct aura changed')
        assert(ctx.records.d900003.spell == 900003, 'duration identity changed')
        assert(ctx.records.i900004.name == 'Item900004' and ctx.records.i900004.texture == 902004, 'item lookup changed')
        assert(ctx.records.e13.name == 'Trinket slot 1' and ctx.records.e13.spell == nil, 'current equipped item substituted')
        assert(nativeCalls == 0, 'direct entry queried native metadata')
    end)
    assert(failures == 0, failures .. ' inactive-spec identity failures')
end)() end
'''
result = subprocess.run([lua, '-', str(root)], input=source + checks, text=True,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
print(result.stdout, end='')
raise SystemExit(result.returncode)
