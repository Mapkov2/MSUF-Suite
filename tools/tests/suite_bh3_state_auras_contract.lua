local root=assert(arg[1])
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_auras_contract.lua", [=[
BH3("CX7-01",function()
    COMBAT,ACCESS,AURAS_SECRET,FRIENDLY=false,true,false,false
    local normal=Aura("bar","a9001","a","player",Set(9001),{ov={}})
    local timed=Aura("bar","a9002","a","player",Set(9002),{base=9002,ov={timerDuration=7,timerSpell=9003}})
    C.views.bar=View("bar",3); C.state.preview=false
    Plan("bar",3,{timed,normal});A.Sync("bar")
    Plan("bar",3,{normal,timed});A.Sync("bar")
    local rec=C.AuraContainers.live.bar.aura.player
    local first=R[Acquired(rec.frame,rec.keys[1])].bind
    local second=R[Acquired(rec.frame,rec.keys[2])].bind
    assert(first.bar and not second.bar and not second.text,
        "CX7-01: timer/ordinary swap retained the previous slot's duration ownership")
    A.ReleaseAll()
end)
BH3("CX7-04",function()
    COMBAT,ACCESS,AURAS_SECRET,FRIENDLY=false,true,false,true
    C.views.buf=View("buf",2)
    local helpful=Aura("buf","b9201","b","target",Set(9201),{auraHelpful=true})
    local harmful=Aura("buf","b9202","b","target",Set(9202))
    Plan("buf",2,{helpful,harmful});A.Sync("buf")
    local rec=C.AuraContainers.live.buf.aura.target
    assert(R[rec.frame].enabled,"CX7-04: own helpful friend aura container was disabled")
    local help=R[rec.frame].groups[rec.keys[1]] or R[rec.frame].slots[rec.keys[1]]
    assert(help.filter:find("HELPFUL|PLAYER",1,true),"CX7-04: friend buff was assigned a harmful filter")
    FRIENDLY=false;A.TargetChanged(); FRIENDLY=true;A.TargetChanged()
    assert(R[rec.frame].enabled,"CX7-04: friend/enemy/friend transition dropped helpful aura")
    FRIENDLY=false;A.ReleaseAll()
end)
BH3("SV15-A3",function()
    C.views.bar=View("bar",3);C.views.bar.barName=false;C.views.bar.showMissing=true
    local normal=Aura("bar","a9301","a","player",Set(9301),{ov={showMissing=true}})
    Plan("bar",3,{normal});A.Sync("bar")
    local names,seen=0,0
    for _,child in ipairs(R[C.bars.bar.cells[1]].kids or {}) do
        local text=Args(child,"SetText")
        if R[child].kind=="FontString" and text and text[1]==normal.name then
            seen=seen+1;if R[child].shown~=false then names=names+1 end
        end
    end
    assert(seen>0 and names==0,"SV15-A3: missing-aura placeholder displayed a disabled name")
    A.ReleaseAll()
end)
BH3("S10-A1",function()
    C.state.threshold,C.state.cdR,C.state.cdG,C.state.cdB=12,0.1,0.2,0.3
    C.state.thR,C.state.thG,C.state.thB=1,0,0
    C.views.bar=View("bar",3)
    local timed=Aura("bar","a9551","a","player",Set(9551),{base=9551,ov={timerDuration=30,timerSpell=9552}})
    Plan("bar",3,{timed});A.Sync("bar")
    local found
    for _,child in ipairs(R[C.bars.bar.cells[1]].kids or {}) do
        for _,gate in ipairs(R[child].kids or {}) do if gate.timerRow and gate.timerRow.key==timed.key then found=gate.timerRow end end
    end
    local color=Args(assert(found).frame.part.dur,"SetTextColor")
    assert(color and color[1]==0.1 and color[2]==0.2 and color[3]==0.3,
        "S10-A1: native countdown retained the placeholder's warning tint")
    A.ReleaseAll()
end)
]=])
