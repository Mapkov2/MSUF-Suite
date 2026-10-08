local root=assert(arg[1])
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_contract.lua", [=[
local config=S.Config(ID)
module.config=config; module.context=S.NewContext(ID)
local function Activate() module.active=true;module:Enable();Run() end
local function Deactivate() module.active=false;module:Disable();module.context:Release();Run(5) end
BH3("CX7-02",function()
    Activate();Run()
    config.bar_barStacks=true;module:Refresh();Run()
    C.Flush.Reset()
    config.bar_barStacks=false;C.Settings.ReadViews(config,false,false)
    assert(C.Flush.dirty.index,"CX7-02: stack fill change did not rebuild event membership")
    Deactivate()
end)
BH3("S11-A2",function()
    Activate();Run()
    C.Flush.Reset();config.keybindStable=not config.keybindStable
    C.Settings.ReadGlobals(config,false)
    assert(C.Flush.dirty.keybinds,"S11-A2: keybind mode toggle left current labels stale")
    Deactivate()
end)
BH3("S11-A3",function()
    local before=C.state.entryGen or 0
    config.listsData=assert(Suite.CDM.Codec.EncodeLists({specs={[62]={ess={"s101"}}}}))
    C.Cold()
    assert((C.state.entryGen or 0)>before,"S11-A3: inactive settings refresh retained the cached preview entries")
end)
BH3("S03-A1",function()
    config.raidEssentials=true
    known[998877],names[998877]=true,"BH3 addition"
    known[998871],names[998871]=true,"BH3 preset 1"
    known[998872],names[998872]=true,"BH3 preset 2"
    local preset=C.Presets.RaidEssentials
    C.Presets.RaidEssentials=function() return {101,102,998871,998872} end
    config.listsData="";Activate();Run()
    local spec=C.state.specID
    local before={}
    for _,e in ipairs(C.plans.ess.entries) do before[e.key]=true end
    local list={"s998877"};list.inherit=true
    config.listsData=assert(Suite.CDM.Codec.EncodeLists({specs={[spec]={ess=list}}}))
    module:Refresh();Run()
    local after={}
    for _,e in ipairs(C.plans.ess.entries) do after[e.key]=true end
    assert(after.s998877,"S03-A1: copied addition disappeared")
    for key in pairs(before) do assert(after[key],"S03-A1: copied addition replaced a target-spec preset entry "..key) end
    for key in pairs(after) do assert(before[key] or key=="s998877","S03-A1: copy appended non-preset Blizzard entry "..key) end
    C.Presets.RaidEssentials=preset
    assert(Suite.CDM.Codec.DecodeLists(config.listsData).specs[spec].ess.inherit,
        "S03-A1: codec stripped target-spec default inheritance")
    Deactivate()
end)
]=], "------------------------------------------------------------------ enable: capture")
