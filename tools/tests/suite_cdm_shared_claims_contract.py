"""Read-only inactive-spec editor cases using its saved catalog, not current spellbook."""
import subprocess
import sys
from pathlib import Path

root=Path(sys.argv[1]).resolve()
from suite_factory_profile_smoke import LUA as lua
source=(root/'tools/tests/suite_cdm_editor_defaults_contract.lua').read_text(encoding='utf-8-sig')
checks=r'''
do (function()
    local nativeInfo, baseSpell, knownSpell = C_CooldownViewer.GetCooldownViewerCooldownInfo,
        C_Spell.GetBaseSpell, C_SpellBook.IsSpellKnownOrInSpellBook
    C_CooldownViewer.GetCooldownViewerCooldownInfo = function() return nil end
    C_Spell.GetBaseSpell = function() error("foreign editor consulted current base spell") end
    C_SpellBook.IsSpellKnownOrInSpellBook = function() error("foreign editor consulted current spellbook") end
    NS.RootDB.cdmEditorCatalog[profile][72] = {
        {key='b101',name='Foreign defensive',texture=1871,spell=871,override=1871,linked={2871},family=1,slot='ess',known=true},
        {key='b102',name='Foreign second',texture=198589,spell=198589,family=1,slot='ess',known=true},
        defaults={ess={'b101','b102'},uti={},buf={},bar={},ext={}},
    }
    C.state.specID = 63
    local failures = 0
    local function Case(name, body)
        local ok, why = pcall(body)
        print((ok and 'PASS ' or 'FAIL ') .. name .. (ok and '' or ': ' .. tostring(why)))
        if not ok then failures=failures+1 end
    end
    local function Context(lists)
        config.listsData = assert(CDM.Codec.EncodeLists(CDM.CleanLists(lists)))
        config.raidEssentials,config.def_on=false,false
        config.c1_shareContents,config.c2_shareContents=true,false
        config.c1_kind,config.c2_kind=CDM.KIND.COOLDOWN,CDM.KIND.COOLDOWN
        return C.Editor.Context(72,1,config)
    end
    Case('foreign shared row owns saved native identity without live spellbook',function()
        local ctx=Context({shared={c1={'s871'}}})
        assert(Keys(ctx.bars.c1)=='s871' and Keys(ctx.bars.ess)=='b102',Keys(ctx.bars.ess))
    end)
    Case('foreign ordinary aliases stay distinct alongside unrelated shared spell',function()
        local ctx=Context({shared={c1={'s198589'}},specs={[72]={c2={'s871','b101'}}}})
        assert(Keys(ctx.bars.c2)=='s871,b101' and Keys(ctx.bars.ess)=='',Keys(ctx.bars.c2))
    end)
    Case('foreign override linked alias takes one saved native home',function()
        local ctx=Context({shared={c1={'s2871','s1871','s871'}}})
        assert(Keys(ctx.bars.c1)=='s2871' and Keys(ctx.bars.ess)=='b102',Keys(ctx.bars.c1))
    end)
    Case('foreign removing shared entry releases native entry',function()
        local ctx=Context({shared={c1={}}})
        assert(Keys(ctx.bars.ess)=='b101,b102',Keys(ctx.bars.ess))
    end)
    Case('foreign changing shared cooldown row to aura kind releases native identity',function()
        Context({shared={c1={'s871'}}})
        config.c1_kind=CDM.KIND.AURA_ICON
        local ctx=C.Editor.Context(72,1,config)
        assert(Keys(ctx.bars.ess)=='b101,b102','native lost after kind change: '..Keys(ctx.bars.ess))
    end)
    C_CooldownViewer.GetCooldownViewerCooldownInfo,C_Spell.GetBaseSpell,C_SpellBook.IsSpellKnownOrInSpellBook =
        nativeInfo,baseSpell,knownSpell
    assert(failures==0,tostring(failures)..' editor scenarios failed')
end)() end
'''
result=subprocess.run([lua,'-',str(root)],input=source+checks,text=True,capture_output=True,cwd=root)
print(result.stdout,end='')
print(result.stderr,end='')
sys.exit(result.returncode)
