dofile(arg[1] .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_skin_slider_steps_contract.lua", [=[
BH3("SV14-A3",function()
    local before=setColors
    TypeHex("#FF1122GG")
    assert(setColors==before and help.text==HEX_ERROR,"SV14-A3: invalid alpha digits silently used fallback opacity")
end)
BH3("CX9-02",function()
    local epoch=10
    NS.Database.GetHistoryEpoch=function() return epoch end
    colors.accent={0.2,0.4,0.6,1};pickR,pickG,pickB=0.6,0.5,0.3
    swatch:GetScript("OnClick")(swatch)
    local cb=ColorPickerFrame.info
    cb.swatchFunc()
    local before=setColors
    local profile=NS.DB
    local other={};for key,value in pairs(profile) do other[key]=value end
    other.theme={look="other",preset="other"};NS.DB=other
    cb.swatchFunc();cb.cancelFunc()
    assert(setColors==before and NS.DB.theme.look=="other","CX9-02: stale picker wrote into another profile")
    NS.DB=profile;epoch=epoch+2;pickR=0.9
    before=setColors;cb.swatchFunc();cb.cancelFunc()
    assert(setColors==before,"CX9-02: A-B-A resurrected the stale picker transaction")
end)
BH3("CX9-02-reopen-context-shortcut",function()
    local epoch=20
    NS.Database.GetHistoryEpoch=function() return epoch end
    local captured
    MSUF2={Widgets={AttachContextColorShortcut=function(_,opts) captured=opts end}}
    local panel=O.CreatePanel
    O.CreatePanel=function(parent,...)
        local row=panel(parent,...)
        row.GetParent=function() return parent end
        return row
    end
    O.embeddedHost=Frame()
    O.CreateColorRow(O.embeddedHost,"accent","Accent")
    assert(captured,"context shortcut was not registered")
    local before=setColors
    local oldTarget=(captured.getTargets and captured.getTargets() or captured.targets)[1]
    local profile=NS.DB
    local other={}
    for key,value in pairs(profile) do other[key]=value end
    other.theme={look="midnight",preset="midnight"}
    NS.DB=other;epoch=epoch+1
    oldTarget.setRGB(.1,.2,.3,1)
    assert(setColors==before,"old picker crossed profiles")
    O.RefreshAll()
    local freshTarget=(captured.getTargets and captured.getTargets() or captured.targets)[1]
    freshTarget.setRGB(.7,.2,.3,1)
    assert(setColors==before+1,"new shortcut opening remained bound to the previous profile")
    NS.DB=profile;epoch=epoch+1;before=setColors
    oldTarget.setRGB(.1,.2,.3,1);freshTarget.setRGB(.1,.2,.3,1)
    assert(setColors==before,"returning to profile A revived an old shortcut session")
    local returnedTarget=(captured.getTargets and captured.getTargets() or captured.targets)[1]
    returnedTarget.setRGB(.4,.5,.6,1)
    assert(setColors==before+1,"new shortcut opening failed after returning to profile A")
end)
]=])
