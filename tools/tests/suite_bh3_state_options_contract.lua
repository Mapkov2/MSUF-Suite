local root=assert(arg[1])
dofile(root .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_cooldown_manager_options_contract.lua", [=[
BH3("SV13-A1",function()
    local config=Config()
    config.ess_size=30
    assert(Page.WithUndo("BH3",{"ess_size"},function() config.ess_size=40;return true end))
    local undo=assert(Page.undo)
    Suite.DB.suite.modules.cooldownManager=Suite.CopyValue(config)
    assert(not undo() and Config().ess_size==40,"SV13-A1: old profile's timed undo wrote into the new profile")
    Suite.DB.suite.modules.cooldownManager=config
end)
BH3("CX6-02",function()
    local full={};for i=1,CDM.LIMITS.entries do full[i]="s"..(10000+i) end
    Config().c1_shareContents=false
    Config().listsData=assert(CDM.Codec.EncodeLists({specs={[63]={c1=full},[64]={c1=full}}}))
    local before=Config().listsData
    local ok,why=Page.CopyToSpecs("c1","s133")
    assert(not ok and why=="This bar is full." and Config().listsData==before,
        "CX6-02: full targets were reported as successful/already copied")
end)
BH3("S03-A4",function()
    Config().c1_kind,Config().c2_kind=1,1
    Config().c1_shareContents,Config().c2_shareContents=true,false
    assert(Page.CopyBarSettings("c1","c2"))
    assert(not Config().c2_shareContents,"S03-A4: appearance copy switched contents to shared")
end)
BH3("S03-A2",function()
    Config().c1_kind,Config().c1_shareContents,Config().c1_on=1,true,true
    Config().listsData="";Page.selected="c1"
    Page.ClosePopups();assert(Page.TogglePicker(ui.handle))
    local picker=Page.picker
    picker.idBox:SetText("382440");Fire(picker.idBox,"OnTextChanged",true);Fire(picker.addA,"OnClick")
    local list=CDM.Codec.DecodeLists(Config().listsData).shared.c1
    assert(list and list[1]=="s382440","S03-A2: shared picker replaced explicit spell with a rejected spec-local Blizzard ID")
    Page.ClosePopups()
end)
BH3("S03-A3",function()
    local calls=0
    Page.ClosePopups()
    assert(Page.OpenSoundPicker(ui.handle,"",function() calls=calls+1 end))
    assert(Page.OpenSoundPicker(ui.chips.c1,"",function() calls=calls+10 end))
    assert(Page.soundPicker.onPick,"S03-A3: reopening sounds at another row erased its callback")
    Page.soundPicker.onPick("kit:1")
    assert(calls==10,"S03-A3: reopened sound picker retained the wrong row")
    Page.ClosePopups()
end)
BH3("S03-A5",function()
    Config().raidEssentials=true;Config().listsData=""
    assert(Page.RemoveEntry("ess","s998877"))
    assert(CDM.Codec.DecodeLists(Config().listsData).hidden[62].s998877,
        "S03-A5: an implicit preset-only spell was not hidden by Remove")
end)
BH3("S03-K2",function()
    Config().ess_anchor=CDM.ANCHOR.FREE;Config().ess_on=true
    L["%s - placed freely"]="frei platziert: %s"
    assert(Page.Summary("ess"):find("frei platziert:",1,true),"S03-K2: summary bypassed its complete localized sentence")
    L["%s - placed freely"]=nil
end)
BH3("S03-A6",function()
    Page.selected="ess"
    Config().ess_anchor=CDM.SLOT_INDEX.uti+CDM.ANCHOR.FREE
    Config().ess_x,Config().ess_y=83,17
    local called=0;local previous=S.CooldownManagerConvertAnchor
    S.CooldownManagerConvertAnchor=function(slot,anchor)
        called=called+1;return {ess_anchor=anchor,ess_x=355,ess_y=-240}
    end
    assert(ui.sections.basics._msufSuiteSectionReset())
    assert(called==1 and Config().ess_x==355 and Config().ess_y==-240,
        "S03-A6: Basics reset changed anchor without converting its coordinate space")
    S.CooldownManagerConvertAnchor=previous
end)
BH3("S06-A1",function()
    local old=MapkoSkin
    local root={activeProfile="Previous",profiles={Previous={color=1},Target={color=2}}}
    MapkoSkin={addonName="MSUF_Suite_Skin",Database={GetRoot=function() return root end,
        GetHistoryProfile=function() return "Target" end,GetHistoryEpoch=function() return 7 end,
        SetActiveProfile=function(name) root.activeProfile=name;return true end}}
    local before=P.CaptureHistoryState()
    assert(before.skinRoot.profiles.Target and before.skinRoot.profiles.Target.color==2
        and not before.skinRoot.profiles.Previous,"S06-A1: embedded replace captured the previous profile instead of the replaced target")
    root.activeProfile="Target";root.profiles.Target.color=3
    assert(P.RestoreHistoryState(before) and root.profiles.Target.color==2,
        "S06-A1: embedded undo did not restore the replaced target")
    MapkoSkin=old
end)
]=], "-- Attached to a bar that is off: the summary")
