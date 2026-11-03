"""Dark Raid cooldown placement, learned spells and native/shared ownership."""
import sys
import subprocess
from pathlib import Path

SUITE = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(SUITE / 'tools/tests'))
sys.path.insert(0, str(SUITE / 'tools'))
from suite_factory_profile_smoke import LUA, lua_literal
from build_modern_dark_factory import literal
from build_forever_factory_preview import decode

factory = SUITE / 'MSUF_Suite/Core/DarkRaidFactory.lua'
envelope = decode(literal(factory, 'Suite.DarkRaidModuleCompact'), 'MSUFM1:MSUF3:')
config = envelope[b'profile'][b'suite'][b'modules'][b'cooldownManager']
encoded = config[b'listsData'].decode()
lists = decode(encoded, 'MSUF3:')
frames = decode(literal(factory, 'Suite.DarkRaidFramesCompact'), 'MSUF3:')[b'payload']
dungeon_config = dict(config)
for patch in frames[b'profileVariants'][b'entries'][0][b'patch']:
    if patch[b'path'][:2] == [b'suiteModules', b'cooldownManager']:
        dungeon_config[patch[b'path'][2]] = patch[b'value']
dungeon_encoded = dungeon_config[b'listsData'].decode()
dungeon_lists = decode(dungeon_encoded, 'MSUF3:')
source = (SUITE / 'tools/tests/suite_cooldown_manager_contract.lua').read_text(encoding='utf-8-sig')
source = source.split('-- Work counters:')[0]
old = 'MSUF_TryDecodeCompactString=function(text) local n=tonumber(text:match("^MSUF3:(%d+)$"));return n and store[n] or nil end'
new = 'MSUF_TryDecodeCompactString=function(text) if text == ' + lua_literal(encoded) + ' then return ' + lua_literal(lists) + ' end local n=tonumber(text:match("^MSUF3:(%d+)$"));return n and store[n] or nil end'
new = new.replace('function(text) ', 'function(text) if text == ' + lua_literal(dungeon_encoded)
                  + ' then return ' + lua_literal(dungeon_lists) + ' end ', 1)
assert old in source
source = source.replace(old, new, 1)
checks = r'''
do (function()
    names[196718], names[198589] = "Darkness", "Blur"
    known[196718], known[198589] = true, true
    chargeState[198589] = {isActive = false}
    -- Both spells are also present in Blizzard's utility list, as learned cooldowns.
    Info(81, 196718, 1)
    Info(82, 198589, 1, {charges = true})
    sets[1] = {81,82}
    MSUF_player = New("Frame", UIParent, "MSUF_player")
    MSUF_player.rect = {850, 444, 248, 38}
    Suite.DB.suite.modules.cooldownManager = PAYLOAD
    S.Normalize(Suite.DB)
    local config = S.Config(ID)
    module.config, module.context, module.active = config, S.NewContext(ID), true
    module:Enable()
    Run()
    S.states[ID].active = true
    module:Refresh()
    Run()
    assert(not C.views.buf.on, "native buff block duplicates the authored rows")
    for _, row in ipairs({ {"c2", 6, 34}, {"c3", 2, 69} }) do
        local slot, count, gap = row[1], row[2], row[3]
        local view = C.views[slot]
        assert(view.on and view.kind == 2 and C.Layout.Parent(slot) == "ess")
        assert(view.side == 2 and view.gap + view.y == gap and view.align == 1)
        assert(not view.keepSlots and not view.showMissing and not view.centerFirst)
        for active = 1, count do
            local width, height, actual = C.Layout.Offsets(view, active, {})
            assert(width == active * 35 - 1 and height == 34 and actual == active,
                "single active row does not compact to its own visible width")
        end
        local point = C.bars[slot].frame.point
        assert(point[1] == "BOTTOM" and point[2] == C.bars.ess.frame and point[3] == "TOP"
            and point[4] == 0 and point[5] == gap, "aura row is not independently centered")
    end
    local utilityPoint = C.bars.uti.frame.point
    assert(utilityPoint[1] == "TOP" and utilityPoint[2] == C.bars.ess.frame and utilityPoint[3] == "BOTTOM"
        and utilityPoint[4] == 0 and utilityPoint[5] == -1, "utility row is not centered below essential cooldowns")
    print("PASS: separate aura row hosts; player row compacts, mixed upper row retains native unit anchors")
    local c1 = assert(C.plans.c1)
    assert(#c1.entries == 2, "the custom row does not materialize two learned spells")
    assert(c1.entries[1].spell == 196718 and c1.entries[2].spell == 198589, "wrong Darkness/Blur ordering")
    assert(c1.entries[2].charges == true, "Blur lost charges")
    local bar = C.bars.c1
    assert(bar.frame.w == 69 and bar.frame.h == 34, "wrong custom row footprint")
    local point = bar.frame.point
    assert(point[1] == "BOTTOMRIGHT" and point[2] == UIParent and point[3] == "BOTTOMLEFT"
        and point[4] == 1098 and point[5] == 483, "row not aligned one pixel above player top right")
    assert(c1.entries[1].icon.shown and c1.entries[2].icon.shown, "ready cooldown row not visible")
    print("PASS: learned row order, charges, visible while ready; 69x34 at player's right edge +1px above")
    for slot, plan in pairs(C.plans) do
        if C.views[slot].on then
            for _, entry in ipairs(plan.entries) do
                if slot ~= "c1" then
                    assert(entry.spell ~= 196718 and entry.spell ~= 198589,
                        "duplicate Darkness/Blur remains in " .. slot .. " via " .. entry.key)
                end
            end
        end
    end
    print("PASS: both spells have a single visible home")
    known[196718], infos[81].isKnown = nil, false
    assert(Fire("SPELLS_CHANGED"))
    Run(2)
    assert(#C.plans.c1.entries == 1 and C.plans.c1.entries[1].spell == 198589, "unlearned Darkness stays visible")
    assert(C.bars.c1.frame.w == 34 and C.bars.c1.frame.point[4] == 1098, "one remaining icon loses right alignment")
    known[198589], infos[82].isKnown = nil, false
    assert(Fire("SPELLS_CHANGED"))
    Run(2)
    assert(#C.plans.c1.entries == 0, "unknown class spells still materialize")
    print("PASS: missing Darkness collapses to one right-aligned icon; neither known -> empty row")
end)() end

do (function()
    local expectedEss={232893,188499,258860,198793,198013,258920,370965,191427}
    local expectedUti={183752,179057,207684,185123,195072}
    UnitClass=function() return 'Demon Hunter','DEMONHUNTER',12 end
    SPEC_IDS[specIndex]=577
    wipe(infos)
    for category in pairs(sets) do sets[category]={} end
    wipe(known)
    for _,id in ipairs({162264,391215,208628,258920,347462,343312,442688,442624,442442}) do
        names[id]='Aura'..id
    end
    for row,category in pairs({[expectedEss]=0,[expectedUti]=1}) do
        for i,id in ipairs(row) do
            names[id],known[id]='Spell'..id,true
            local native=category*100+i+80
            Info(native,id,category)
            table.insert(sets[category],native)
        end
    end
    -- Unselected native extras must not expand the authored 8+5 rows.
    names[278326],known[278326]='Consume Magic',true
    Info(299,278326,1);table.insert(sets[1],299)
    names[196718],names[198589],names[202719]='Darkness','Blur','Arcane Torrent'
    known[196718],known[198589],known[202719]=true,true,true
    Info(301,196718,1);Info(302,198589,1);Info(303,202719,1)
    table.insert(sets[1],301);table.insert(sets[1],302);table.insert(sets[1],303)
    Info(401,nil,5,{spellCategoryID=4})
    Info(402,nil,5,{spellCategoryID=30})
    sets[5]={401,402}
    local icon,name=C_Item.GetItemIconByID,C_Item.GetItemNameByID
    C_Item.GetItemIconByID=function(id) if id==5512 or id==224464 then return 538745 end return icon(id) end
    C_Item.GetItemNameByID=function(id) if id==5512 then return 'Healthstone' end
        if id==224464 then return 'Demonic Healthstone' end return name(id) end
    bagCounts[5512],bagCounts[224464]=3,0
    MSUF_player=New('Frame',UIParent,'MSUF_player')
    MSUF_player.rect={850,444,248,38}
    Suite.DB.suite.modules.cooldownManager=PAYLOAD
    S.Normalize(Suite.DB)
    module.config,module.context,module.active=S.Config(ID),S.NewContext(ID),true
    module:Enable();Run()
    S.states[ID].active=true
    module:Refresh();Run()
    assert(C.state.specID==577,'fixture did not select Havoc')
    for slot,expected in pairs({ess=expectedEss,uti=expectedUti}) do
        local plan=C.plans[slot]
        assert(#plan.entries==#expected,slot..' count '..#plan.entries..' expected '..#expected)
        for i,id in ipairs(expected) do
            assert(plan.entries[i].spell==id,slot..' index '..i..' spell '..tostring(plan.entries[i].spell)..' expected '..id)
        end
    end
    for slot,expected in pairs({c2={162264,391215,208628,258920,347462,343312},c3={442688,442624},c4={442442}}) do
        local plan=assert(C.plans[slot],slot..' has no authored aura plan')
        assert(#plan.entries==#expected,slot..' omitted authored auras')
        for i,id in ipairs(expected) do
            assert(plan.entries[i].spell==id,slot..' aura order differs')
        end
    end
    assert(C.plans.c3.entries[1].unit=='player' and C.plans.c3.entries[2].unit=='target',
        "Reaver's Mark must track the target rather than a player buff")
    local overlay = C.views.c4
    local frame = C.bars.c4.frame
    assert(overlay.on and overlay.kind == 2 and C.Layout.Parent('c4') == 'c3',
        'Rending Strike must overlay the target mark through its own native player container')
    assert(C.plans.c4.entries[1].unit == 'player', 'Rending Strike is a player buff')
    assert(frame.w == 34 and frame.h == 34 and C.bars.c3.frame.w == 69,
        'Rending overlay must match exactly one upper-row icon')
    local point = frame.point
    assert(point[1] == 'TOPRIGHT' and point[2] == C.bars.c3.frame and point[3] == 'BOTTOMRIGHT'
        and point[4] == 0 and point[5] == 34, 'Rending overlay does not cover the right-hand Mark cell')
    assert(overlay.strata == 4 and overlay.alpha == 100 and overlay.oocAlpha == 100
        and not overlay.showMissing and not overlay.keepSlots, 'Rending overlay exposes the icon beneath it')
    print('PASS: Rending Strike native player overlay matches the upper target-mark cell')
    assert(C.views.ext.on,'consumables are disabled')
    local visible={}
    for _,entry in ipairs(C.plans.ext.entries) do
        if entry.icon and entry.icon.shown then visible[#visible+1]=entry end
    end
    assert(#visible==4,'consumable row visible count '..#visible..' expected four')
    assert(visible[1].spellCategory==4 and visible[2].spellCategory==30
        and visible[3].itemID==5512 and visible[4].spell==202719,'expected combat potion, health potion, Healthstone, racial')
    local point=C.bars.ext.frame.point
    assert(point[1]=='TOPLEFT' and point[2]==UIParent and point[3]=='BOTTOMLEFT'
        and point[4]==850 and point[5]==443,'consumables not one pixel below player left')
    print('PASS: Havoc577 exact8+5, extra native cooldown excluded, potions/Healthstone/racial visible below player')
end)() end
'''.replace('PAYLOAD', lua_literal(config))
result = subprocess.run([LUA, '-', str(SUITE)], input=source + checks, text=True, capture_output=True, cwd=SUITE)
print(result.stdout, end='')
print(result.stderr, end='')
if result.returncode:
    sys.exit(result.returncode)
dungeon_checks = checks.replace(lua_literal(config), lua_literal(dungeon_config)).replace(
    'local expectedUti={183752,179057,207684,185123,195072}',
    'local expectedUti={183752,179057,207684,217832,278326,185123,195072}')
dungeon_checks = dungeon_checks.replace('Havoc577 exact8+5', 'Havoc577 dungeon exact8+7')
result = subprocess.run([LUA, '-', str(SUITE)], input=source + dungeon_checks,
                        text=True, capture_output=True, cwd=SUITE)
print(result.stdout, end='')
print(result.stderr, end='')
sys.exit(result.returncode)
