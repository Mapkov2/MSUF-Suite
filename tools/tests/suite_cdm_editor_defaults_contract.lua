local root = assert(arg[1])
local originalLoad, private = loadfile
loadfile = function(path)
    local chunk = assert(originalLoad(path))
    return function(addon, ns)
        if path:find('MSUF_Suite_CooldownManager/Editor.lua', 1, true) then private = ns end
        return chunk(addon, ns)
    end
end
assert(originalLoad(root .. '/tools/tests/suite_cooldown_manager_contract.lua'))()
loadfile = originalLoad
local C, S, NS = assert(private).CDM, private.Suite, private.NS
local CDM = NS.CDM
UnitClass = function() return 'Warrior', 'WARRIOR', 1 end
C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
    if id == 101 then return {spellID=871} end
end
C_Spell.GetSpellName = function(id) return 'Spell' .. id end
C_Spell.GetSpellTexture = function(id) return id+1000 end
C_SpellBook.IsSpellKnownOrInSpellBook = function() return true end
C.state.specID, C.state.raidEssentials = 71, false
C.Catalog.records = {[101]={id=101,key='b101',spell=871,family=1,bar='ess',category=0,known=true}}
C.Catalog.order = {101}
C.Catalog.defaultByBar = {ess={'b101'},uti={},buf={},bar={},ext={}}
C.Catalog.generation = (C.Catalog.generation or 0)+1
C.Catalog.content = (C.Catalog.content or 0)+1
C.lists = CDM.CleanLists({})
for _, def in ipairs(CDM.SLOTS) do
    C.views[def.key] = {kind=def.kind,on=def.key=='ess' or def.key=='def'}
end
local config = S.Config('cooldownManager')
config[CDM.KEYS.def.on] = true
config.listsData, config.spellsData, config.raidEssentials = '', '', false
local profile = NS.Database.GetActiveProfileName()
NS.RootDB.cdmEditorCatalog = {[profile]={[71]={{key='b101',name='Shield Wall',texture=1871,spell=871,family=1,slot='ess',known=true,hasAura=true}}}}
local function Keys(rows)
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = row.key end
    return table.concat(out, ',')
end
local function Parity(lists, raid, defensive)
    C.lists = CDM.CleanLists(lists or {})
    config.listsData = assert(CDM.Codec.EncodeLists(C.lists))
    C.state.raidEssentials, config.raidEssentials = raid, raid
    C.views.def.on, config[CDM.KEYS.def.on] = defensive, defensive
    local context = C.Editor.Context(71, 1, config)
    for _, slot in ipairs({'ess', 'def', 'uti'}) do
        assert(Keys(context.bars[slot]) == table.concat(C.Resolve.Keys(slot), ','),
            'foreign defaults differ from runtime in ' .. slot .. ': editor=' .. Keys(context.bars[slot]) .. '; runtime=' .. table.concat(C.Resolve.Keys(slot), ','))
    end
    return context
end
local first = Parity(nil, false, true)
assert(first.bars.def[1].key == 'b101' and first.bars.def[1].hasAura,
    'native preset identity or aura controls were lost')
local off = Parity(nil, false, false)
assert(off ~= first and off.bars.ess[1].key == 'b101', 'bar enable state retained stale default claims')
Parity({specs={[71]={ess={'b101'}}}, hidden={[71]={b101=true}}}, false, true)
Parity({specs={[71]={ess={'s133',inherit=true}}}}, true, true)
Parity({specs={[71]={ess={}}}, replace={[71]={ess=true}}}, true, true)
config[CDM.KEYS.c1.shareContents], config[CDM.KEYS.c1.kind] = true, CDM.KIND.COOLDOWN
C.views.c1.shareContents, C.views.c1.kind = true, CDM.KIND.COOLDOWN
local shared = Parity({specs={[71]={ess={'s871'}}}, shared={c1={'s871'}}}, false, true)
assert(shared.bars.c1[1].key == 's871', 'shared list lost claim precedence')
print('CDM editor defaults: real resolver parity, native identity, aura metadata, enable invalidation, inherit, replace, hidden and shared claims passed')
