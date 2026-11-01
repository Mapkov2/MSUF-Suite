local root = assert(arg[1])
local W = dofile(root .. "/tools/tests/cdm_data_world.lua")(root)
local C, CDM = W.C, W.NS.CDM
W.NS.Client.isForever = arg[2] == "Forever"
W.Views()
C.views.c1.on = true
W.known[9001] = true
W.sets[0] = { 1001 }
W.infos[1001] = { cooldownID = 1001, spellID = 123, linkedSpellIDs = { 456 }, hasAura = true,
    selfAura = true, isKnown = true, category = 0, flags = 0 }
C.lists = CDM.CleanLists({ specs = { [63] = { c1 = { "s9001" } } } })
C.state.specID = 63
C.Catalog.Rebuild()
local function Resolve()
    C.Resolve.Build()
    C.Index.Rebuild()
    return C.entries.b1001, C.entries.s9001
end
local native, custom = Resolve()
assert(native.auraIDs[456] and custom.auraIDs == nil, "native baseline")
C.spells = CDM.CleanSpells({ e = { b1001 = { replaceAura = 777, auraUnit = 3 }, s9001 = { replaceAura = 778 } } })
native, custom = Resolve()
assert(native.ov.replaceAura == 777 and native.auraIDs[777] and not native.auraIDs[456], "selected aura not isolated")
assert(custom.ov.replaceAura == 778 and custom.hasAura and custom.auraIDs[778], "custom cooldown has no replacement")
assert(native.spell == 123 and custom.spell == 9001, "replacement changed cooldown identity")
assert(native.unit == "target", "replacement lost the explicit target")
C.Catalog.OnOverride(123, 124)
assert(native.spell == 124 and native.auraIDs[777] and not native.auraIDs[124], "spell override replaced selected aura")
assert(native.unit == "target", "spell override lost the explicit target")
C.spells.e.b1001.auraUnit = 4
native = Resolve()
C.Catalog.OnOverride(123, 125)
assert(native.unit == "both" and native.auraIDs[777], "spell override lost the both-units choice")
assert(CDM.SPELL_FIELDS.replaceAura(0) and not CDM.SPELL_FIELDS.replaceAura(-1), "invalid schema range")
C.spells = CDM.CleanSpells({ e = { b1001 = { replaceAura = 0 } } })
native, custom = Resolve()
assert(native.auraIDs[456] and custom.auraIDs == nil, "clearing left a replacement behind")
local name = C.Catalog.SpellName
C.Catalog.SpellName = function(id) if id == 777 then return nil end return name(id) end
C.spells = CDM.CleanSpells({ e = { b1001 = { replaceAura = 777 } } })
native = Resolve()
assert(native.auraIDs[456], "unavailable metadata replaced native binding")
C.Catalog.SpellName = name
C.spells = CDM.CleanSpells({ s = { [63] = { s9001 = { replaceAura = 779 } },
    [64] = { s9001 = { replaceAura = 780 } } } })
custom = select(2, Resolve())
assert(custom.ov.replaceAura == 779, "first specialization")
C.lists = CDM.CleanLists({ specs = { [63] = { c1 = { "s9001" } }, [64] = { c1 = { "s9001" } } } })
C.state.specID = 64
W.combat = true
local result
for i = 1, 40 do
    result = C.Resolve.Build(true, i == 1)
    if result then break end
end
assert(result and C.entries.s9001.ov.replaceAura == 780 and C.entries.s9001.auraIDs[780], "staged spec change lost replacement")
print("suite_cdm_replacement_aura_contract: ok " .. (arg[2] or "Mainline"))
