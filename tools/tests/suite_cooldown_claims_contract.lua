-- Ownership checks against the actual CDM data plane.
local root = assert(arg[1])
local W = dofile(root .. "/tools/tests/cdm_data_world.lua")(root)
local C, CDM = W.C, W.NS.CDM
local failures = 0
local function Case(name, body)
    local ok, why = pcall(body)
    print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ": " .. tostring(why)))
    if not ok then failures = failures + 1 end
end
local function Seed()
    W.Views()
    C.views.def.on, C.views.ext.on, C.views.buf.on, C.views.bar.on = false, false, false, false
    C.views.c1.on, C.views.c1.shareContents = true, true
    C.views.c2.on, C.views.c2.shareContents = true, true
    C.state.specID, C.state.raidEssentials = 63, false
    W.infos[81] = { cooldownID=81, spellID=196718, category=1, isKnown=true, flags=0, linkedSpellIDs={}, charges=false }
    W.infos[82] = { cooldownID=82, spellID=198589, category=1, isKnown=true, flags=0, linkedSpellIDs={}, charges=true }
    W.sets[0], W.sets[1] = {}, {81,82}
    W.known[196718], W.known[198589] = true, true
    C_Spell.GetBaseSpell = function(id) return id end
    C_SpellBook.FindSpellOverrideByID = function() end
    C.lists = CDM.CleanLists({shared={c1={"s196718","s198589"}}})
    C.spells = CDM.CleanSpells({e={s196718={timeText=3,barText="Authored choice"}}})
    C.Resolve.SpellsChanged()
    C.Catalog.Rebuild()
end
local function Build()
    C.Resolve.Build()
end
local function CountSpell(id)
    local count = 0
    for slot, plan in pairs(C.plans) do
        if C.views[slot].on then
            for _, entry in ipairs(plan.entries) do if entry.spell == id then count = count + 1 end end
        end
    end
    return count
end
Case("shared s row claims Blizzard identities while preserving s choices", function()
    Seed(); Build()
    assert(CountSpell(196718)==1 and CountSpell(198589)==1, "duplicated native entries")
    local row=C.plans.c1.entries
    assert(row[1].key=="s196718" and row[2].key=="s198589", "authored spell keys remapped")
    assert(row[1].ov.timeText==3 and row[1].ov.barText=="Authored choice", "authored s choices lost")
end)
Case("ordinary same-row s then b and b then s retain both authored entries", function()
    for _, list in ipairs({{"s196718","b81"},{"b81","s196718"}}) do
        Seed(); C.views.c1.shareContents=false; C.lists=CDM.CleanLists({specs={[63]={c1=list}}}); Build()
        assert(#C.plans.c1.entries==2 and C.plans.c1.entries[1].key==list[1]
            and C.plans.c1.entries[2].key==list[2], "ordinary explicit aliases removed or reordered")
    end
end)
Case("shared first owner precedes second shared row and explicit builtin list", function()
    Seed()
    C.lists=CDM.CleanLists({specs={[63]={uti={"b81","b82"}}},shared={c1={"s196718"},c2={"s196718","s198589"}}})
    Build()
    assert(#C.plans.c1.entries==1 and C.plans.c1.entries[1].spell==196718, "first owner lost Darkness")
    assert(#C.plans.c2.entries==1 and C.plans.c2.entries[1].spell==198589, "second row stole Darkness")
    assert(#C.plans.uti.entries==0, "builtin explicit list bypassed shared claims")
end)
Case("ordinary separate bars retain independently authored aliases", function()
    Seed(); C.views.c1.shareContents, C.views.c2.shareContents=false,false
    C.lists=CDM.CleanLists({specs={[63]={ess={"b81"},c1={"s196718","s198589"}}}})
    Build()
    assert(C.plans.ess.entries[1].key=="b81", "first explicit owner changed")
    assert(#C.plans.c1.entries==2 and C.plans.c1.entries[1].spell==196718
        and C.plans.c1.entries[2].spell==198589, "independent s entry was removed")
end)
Case("shared identity does not collapse unrelated ordinary aliases", function()
    Seed(); C.views.c2.shareContents=false
    C.lists=CDM.CleanLists({shared={c1={"s196718"}},specs={[63]={c2={"s198589","b82"}}}})
    Build()
    assert(CountSpell(196718)==1, "shared identity failed to take ownership")
    assert(CountSpell(198589)==2, "shared claims leaked to unrelated spell")
end)
Case("adding and removing shared identity restores ordinary aliases", function()
    Seed(); C.views.c2.shareContents=false
    C.lists=CDM.CleanLists({specs={[63]={c2={"s196718","b81"}}}})
    Build()
    assert(#C.plans.c2.entries==2, "ordinary setup lost aliases")
    C.lists.shared.c1={"s196718"}; Build()
    assert(#C.plans.c2.entries==0 and #C.plans.c1.entries==1, "shared identity failed to take ownership")
    C.lists.shared.c1={}; Build()
    assert(#C.plans.c2.entries==2 and #C.plans.c1.entries==0, "shared identity leaked after removal")
end)
Case("changing shared cooldown row to aura kind releases native identity", function()
    Seed(); Build()
    C.views.c1.kind=CDM.KIND.AURA_ICON; Build()
    assert(#C.plans.c1.entries==0, "cooldown keys entered aura row")
    assert(#C.plans.uti.entries==2, "native identity still held after kind change")
end)
Case("override and base aliases have one owner", function()
    Seed()
    W.infos[81].overrideSpellID=296718
    W.infos[81].linkedSpellIDs={396718}
    W.known[296718],W.known[396718]=true,true
    C_Spell.GetBaseSpell=function(id) if id==296718 or id==396718 then return 196718 end return id end
    C_SpellBook.FindSpellOverrideByID=function(id) if id==196718 then return 296718 end end
    C.lists=CDM.CleanLists({shared={c1={"s396718","s296718","s196718","b81"}}})
    C.Catalog.Rebuild(); Build()
    assert(#C.plans.c1.entries==1 and C.plans.c1.entries[1].key=="s396718", "override aliases duplicated")
    assert(CountSpell(296718)==1, "override remained in native utility")
end)
Case("no native catalog still preserves authored order", function()
    Seed(); W.sets[1]={}; C.Catalog.Rebuild(); Build()
    assert(#C.plans.c1.entries==2 and C.plans.c1.entries[1].key=="s196718" and C.plans.c1.entries[2].key=="s198589")
end)
Case("non-DH unknown spells never materialize", function()
    Seed(); W.known[196718],W.known[198589]=nil,nil
    W.infos[81].isKnown,W.infos[82].isKnown=false,false
    C.Catalog.Rebuild(); C.Resolve.SpellsChanged(); Build()
    assert(#C.plans.c1.entries==0, "unknown spells materialized")
end)
assert(failures==0, tostring(failures) .. " ownership scenarios failed")
