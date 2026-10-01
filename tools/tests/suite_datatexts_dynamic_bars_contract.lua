-- User-created bars preserve scalar profile settings and acquire reusable
-- runtime surfaces only when needed, including IDs beyond the old pool.
local root=assert(arg[1])
local H=dofile(root.."/tools/tests/suite_minimap_harness.lua")
for _,flavor in ipairs({"Mainline","Forever"}) do
    local W=H.New(root,flavor,{beforeModules=function(world)
        world.G.GetFramerate=function() return 75 end
        world.G.PlayerHasToy=function() return false end
        world.G.C_Item={GetItemCount=function() return 0 end}
    end})
    local G,S,NS=W.G,W.S,W.Suite
    local c=S.Config("dataTexts")
    c.enabled=false;c.bar1Enabled=false;c.barIds="0"
    W.LoadAddon("MSUF_Suite_DataTexts")
    local M=S.instances.dataTexts
    S.Start();assert(S.Set("dataTexts","enabled",true))
    assert(not next(M.bars) and #M.pool==0,"empty configuration must not allocate a bar pool")
    local frames={}
    for i=1,20 do
        local id=assert(NS.DataTextNextBarID(c));assert(id==i)
        local values=NS.DataTextBarCreationValues(c,id)
        values["bar"..id.."Name"]="Named "..id
        values["bar"..id.."Slot1"]=6
        for slot=2,6 do values["bar"..id.."Slot"..slot]=1 end
        assert(S.SetMany("dataTexts",values))
        assert(M.bars[id] and M.bars[id].frame:IsShown())
        frames[M.bars[id].frame]=true
    end
    assert(#NS.DataTextBarIDs(c)==20 and M.bars[20].prefix=="bar20","the old twelve-bar boundary must not apply")
    assert(c.bar20Name=="Named 20" and M.bars[20].slots[1].text,"new bar fields must have real runtime ownership")
    assert(rawget(S.catalog.dataTexts.rules,"bar20Width")==nil and S.catalog.dataTexts.rules.bar20Width,
        "dynamic rules must not pollute physical defaults")
    local spec=S.catalog.dataTexts
    local controlCount=#spec.controls
    for id=1000,2000 do assert(spec.rules["bar"..id.."Width"]) end
    assert(#spec.controls==controlCount,"foreign rule lookups must not grow global controls")
    local constructor
    for i=1,20 do local name,value=debug.getupvalue(getmetatable(spec.rules).__index,i);if name=="DynamicRule" then constructor=value end end
    assert(constructor)
    local cache
    for i=1,20 do local name,value=debug.getupvalue(constructor,i);if name=="dynamic" then cache=value end end
    local cacheCount,ruleCount=0,0
    for _,rules in pairs(cache) do
        cacheCount=cacheCount+1
        for _ in pairs(rules) do ruleCount=ruleCount+1 end
    end
    assert(cacheCount<=256 and ruleCount<=256,"single-key lookups must remain bounded and avoid full rule expansion")
    local currentControls=spec.getControls(c)
    for _,rule in ipairs(currentControls) do
        local id=tonumber(rule.key:match("^bar(%d+)"))
        assert(not id or id<=20,"foreign rules must not appear in current controls")
    end
    for id=2,20 do assert(S.SetMany("dataTexts",NS.DataTextBarRemovalValues(c,id))) end
    assert(#NS.DataTextBarIDs(c)==1 and #M.pool==19 and not M.bars[20],"removed surfaces must be dormant and reusable")
    assert(not spec.controlAvailable(spec.rules.bar20Name,c),"cached controls must hide removed IDs")
    for _,bar in ipairs(M.pool) do assert(not bar.frame:IsShown()) end
    local values=NS.DataTextBarRemovalValues(c,1)
    assert(S.SetMany("dataTexts",values));assert(c.barIds=="0" and not next(M.bars))
    local imported={barIds="400000",bar400000Enabled=true,bar400000Slot1=6,bar400000Name="Imported strip"}
    assert(S.SetMany("dataTexts",imported))
    assert(M.bars[400000] and frames[M.bars[400000].frame],"profile IDs must reuse an existing surface")
    assert(M.bars[400000].prefix=="bar400000" and M.bars[400000].widthKey=="bar400000Width")
    local brokerChoice
    for choice,key in ipairs(NS.DataTextSourceKeys) do if key=="broker" then brokerChoice=choice end end
    assert(brokerChoice)
    local X=W.private.DataTextSources
    for cycle=1,80 do
        local id=400000+cycle
        assert(S.SetMany("dataTexts",{barIds=tostring(id),["bar"..id.."Enabled"]=true,
            ["bar"..id.."Slot1"]=brokerChoice}))
        local count=0;for _ in pairs(X.bindings) do count=count+1 end
        assert(count==1,"profile/bar replacement must prune old dynamic source bindings")
        local key=M.bars[id].slots[1].source
        assert(X.Has(key) and M.activeSources[key],"current extra source must remain active")
        assert(S.Set("dataTexts","bar"..id.."Slot1",6))
        assert(not next(X.bindings) and not X.Has(key),"kind changes must prune previous extra binding")
        assert(S.SetMany("dataTexts",NS.DataTextBarRemovalValues(c,id)))
        assert(not next(X.bindings),"deleted bars must not retain extra bindings")
    end
    assert(spec.controlAvailable(spec.rules.bar400000Name,c))
    assert(not S.catalog.dataTexts.rules.bar400000Unknown and not S.catalog.dataTexts.rules.bar1000001Width)
    local profile={suite={modules={dataTexts={barIds="13",bar13Enabled=true,bar13Name="Variant bar",bar13Width=-10,
        bar13BackgroundEnabled=false,bar13ValueColor="invalid",bar1Enabled=false}}}}
    S.Normalize(profile)
    local data=profile.suite.modules.dataTexts
    assert(data.bar13Name=="Variant bar" and data.bar13Width>=180 and data.bar13Width<=900)
    assert(data.bar13BackgroundEnabled==false and data.bar13ValueColor~="invalid","dynamic field type/format repair failed")
    local other={suite={modules={dataTexts={barIds="0",bar1Enabled=false}}}}
    S.Normalize(other)
    assert(other.suite.modules.dataTexts.bar13Width==nil and other.suite.modules.dataTexts.bar400000Width==nil,
        "unrelated profiles must not acquire dynamic defaults")
    local legacy={barIds="",bar1Enabled=false,bar12Name="Preserved old strip"}
    local found=false;for _,id in ipairs(NS.DataTextBarIDs(legacy)) do if id==12 then found=true end end
    assert(found,"customized legacy bars must remain available")
    local all={};for i=1,300 do all[i]=i end
    assert(#NS.DataTextBarIDs({barIds=table.concat(all,",")})==256,"imports must respect the secure-surface safety bound")
    print("dynamic DataTexts bars: "..flavor.." PASS")
end
