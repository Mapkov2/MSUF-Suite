local root=assert(arg[1])
local originalLoad, private=loadfile
loadfile=function(path)
 local chunk=assert(originalLoad(path))
 return function(addon,ns)
  if path:find('MSUF_Suite_CooldownManager/Editor.lua',1,true) then private=ns end
  return chunk(addon,ns)
 end
end
assert(originalLoad(root..'/tools/tests/suite_cooldown_manager_contract.lua'))()
loadfile=originalLoad
local C,S,NS=private.CDM,private.Suite,private.NS
local CDM=NS.CDM
UnitClass=function() return 'Warrior','WARRIOR',1 end
C_Spell.GetSpellName=function(id) return 'Spell'..id end
C_Spell.GetSpellTexture=function(id) return id+1000 end
C_SpellBook.IsSpellKnownOrInSpellBook=function(id) return id==871 or id>=10001 and id<=10006 end
C_CooldownViewer.GetCooldownViewerCooldownInfo=function(id)
 local rec=C.Catalog.records[id]
 return rec and {spellID=rec.spell,hasAura=rec.hasAura}
end
C.state.specID=71
local records,order,rows={},{},{}
for i=1,6 do
 local id=100+i
 records[id]={id=id,key='b'..id,spell=10000+i,family=1,bar='ess',category=0,known=true}
 order[#order+1]=id
end
records[107]={id=107,key='b107',spell=871,family=1,bar='uti',category=1,known=true,hasAura=true}
order[#order+1]=107
records[108]={id=108,key='b108',spell=20000,family=1,bar='ess',category=0,known=true,equipSlot=13}
order[#order+1]=108
for _,id in ipairs(order) do
 local rec=records[id]
 rows[#rows+1]={key=rec.key,name=rec.key,texture=rec.spell+1000,spell=rec.spell,family=rec.family,slot=rec.bar,known=rec.known,equipSlot=rec.equipSlot,hasAura=rec.hasAura}
end
local defaults={ess={'b106','b105','b104','b103','b102','b101'},uti={'b107'},buf={},bar={}}
rows.defaults=defaults
rows.knownSpells={}
for _,ids in ipairs({C.Presets.RaidEssentials(71),C.Presets.Defensives(1),C.Presets.RACIALS}) do
 for _,id in ipairs(ids) do rows.knownSpells[id]=id==871 end
end
C.Catalog.records,C.Catalog.order,C.Catalog.defaultByBar=records,order,defaults
C.Catalog.generation=C.Catalog.generation+1
C.Catalog.content=C.Catalog.content+1
local config=S.Config('cooldownManager')
config.listsData,config.spellsData='',''
local profile=NS.Database.GetActiveProfileName()
NS.RootDB.cdmEditorCatalog={[profile]={[71]=rows}}
local function Keys(items)
 local keys={}
 for _,row in ipairs(items) do keys[#keys+1]=row.key end
 return table.concat(keys,',')
end
local function Case(label,lists,raid,defOn,shared)
 C.state.raidEssentials,config.raidEssentials=raid,raid
 for _,def in ipairs(CDM.SLOTS) do
  local on=def.key=='ess' or def.key=='uti' or def.key=='def' and defOn
  config[CDM.KEYS[def.key].on]=on
  C.views[def.key]={on=on,kind=def.kind}
 end
 config.c1_shareContents=shared or false
 C.views.c1.shareContents=shared or false
 C.lists=CDM.CleanLists(lists or {})
 config.listsData=assert(CDM.Codec.EncodeLists(C.lists))
 local context=C.Editor.Context(71,1,config)
 local equal=true
 for _,slot in ipairs({'ess','uti','def','c1'}) do
  local runtime=table.concat(C.Resolve.Keys(slot),',')
  local editor=Keys(context.bars[slot])
  if runtime~=editor then print(label,slot,'runtime='..runtime,'editor='..editor);equal=false end
 end
 return equal
end
local results={
 Case('raid-default',nil,true,true),
 Case('blizzard-stock',nil,false,true),
 Case('def-off',nil,false,false),
 Case('legacy-explicit',{specs={[71]={ess={'b101'}}}},true,true),
 Case('inherit',{specs={[71]={ess={'b101',inherit=true}}}},true,true),
 Case('replace',{specs={[71]={ess={'b101'}}},replace={[71]={ess=true}}},true,true),
 Case('shared-home',{shared={c1={'b101'}}},false,true,true),
 Case('equipment-slot-home',{specs={[71]={ess={'e13'}}}},false,true),
}
for _,result in ipairs(results) do assert(result,'OFFLINE_EDITOR_RESOLVER_MATRIX_MISMATCH') end
print('Independent resolver matrix passed')local guide=assert(C.GuideProfiles[63])
assert(guide.moves[6101]==nil)
local present=false
for _,id in ipairs(guide.order) do if id==6101 then present=true end end
assert(present,'Fire guide does not exercise the sparse-move case')
NS.RootDB.cdmEditorCatalog[profile][63]=nil
C.Catalog.records={[6101]={id=6101,key='b6101',spell=2139,family=1,bar='uti',category=1,defaultCategory=1,known=true}}
C.Catalog.order={6101}
C.Catalog.defaultByBar={ess={},uti={'b6101'},buf={},bar={}}
C.Catalog.content=C.Catalog.content+1
C.Catalog.generation=C.Catalog.generation+1
C_CooldownViewer.GetCooldownViewerCooldownInfo=function(id)
 if id==6101 then return {spellID=2139,category=1,hasAura=false,linkedSpellIDs={}} end
end
C.state.specID,C.state.raidEssentials=63,true
C.lists=CDM.CleanLists({})
config.listsData,config.raidEssentials='',true
local actual=table.concat(C.Resolve.Keys('uti'),',')
assert(actual=='b6101','native-default fixture did not exercise the runtime fallback')
local editor=C.Editor.Context(63,8,config)
print('sparse guide fallback','runtime='..actual,'editor='..Keys(editor.bars.uti))
assert(Keys(editor.bars.uti)==actual,'OFFLINE_SPARSE_GUIDE_DROPS_READABLE_NATIVE_CATEGORY')

-- Shipped guides may omit the entire move map or even the order. Exercise
-- the unobserved-spec path, before any character metadata has been saved.
local arms=assert(C.GuideProfiles[71])
assert(arms.moves==nil and arms.order[1]==27 and arms.order[2]==28,
 'Arms guide must exercise the missing-move-map case')
NS.RootDB.cdmEditorCatalog[profile][71]=nil
C_CooldownViewer.GetCooldownViewerCooldownInfo=function(id)
 if id==27 then return {spellID=10001,category=0,hasAura=false} end
 if id==28 then return {spellID=10002,category=1,hasAura=false} end
end
C.Catalog.generation=C.Catalog.generation+1
local warrior=C.Editor.Context(71,1,config,'WARRIOR')
assert(warrior.catalogCount==2,'Unresolved guide entries must be omitted')
assert(table.concat(warrior.defaultByBar.ess,',')=='b27','Arms essential native category lost')
assert(table.concat(warrior.defaultByBar.uti,',')=='b28','Arms utility native category lost')
assert(arms.moves==nil,'Editor must not mutate the shipped guide')
assert(C.Editor.Context(71,1,config,'WARRIOR')==warrior,'Repeated selection must reuse the context')

-- No native entries are available, as can happen for an unobserved spec.
C_CooldownViewer.GetCooldownViewerCooldownInfo=function() end
C.Catalog.generation=C.Catalog.generation+1
assert(C.Editor.Context(71,1,config,'WARRIOR').catalogCount==0,
 'Missing native metadata must not fabricate guide entries')
local disc=assert(C.GuideProfiles[256])
assert(disc.order==nil and disc.moves==nil,'Discipline guide must exercise the empty-guide case')
NS.RootDB.cdmEditorCatalog[profile][256]=nil
local priest=C.Editor.Context(256,5,config,'PRIEST')
assert(priest.catalogCount==0,'Empty guide must not fabricate catalog entries')
assert(disc.order==nil and disc.moves==nil,'Editor must not populate the empty guide')
print('Optional guide fields passed: Arms native fallback, missing metadata, empty Discipline guide')
