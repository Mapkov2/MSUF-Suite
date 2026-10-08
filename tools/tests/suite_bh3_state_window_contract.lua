dofile(arg[1] .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_window_controls_contract.lua", [=[
NS.DB.enabled,NS.DB.skins.blizzardWindows,NS.DB.windowControls.enabled=true,true,true
NS.Client.isForever=false;_G.combat=false;_G.combatEdge=false
BH3("CX9-04",function()
    local map=Frame("WorldMapFrame",UIParent)
    UIPanelWindows.WorldMapFrame={area="left",pushable=0}
    map.IsMaximized=function(self) return self.maximized end
    NS.DB.windowControls.scales.WorldMapFrame=1.5
    assert(NS.WindowControls.Attach(map,"bh3-map"))
    map.maximized=true;NS.WindowControls.Refresh()
    assert(map.scale==1 and not NS.WindowControls.states[map].grip.shown,
        "CX9-04: maximized map kept the saved window scale/grip")
    map.maximized=false;NS.WindowControls.Refresh()
    assert(map.scale==1.5,"CX9-04: leaving fullscreen lost the saved scale")
end)
BH3("CX9-05",function()
    local frame=Frame("GameMenuFrame",UIParent)
    assert(NS.WindowControls.Attach(frame,"bh3-combat"))
    frame:Hide();NS.DB.windowControls.scales.GameMenuFrame=1.4
    _G.combat=true;frame:Show()
    assert(frame.scale~=1.4,"CX9-05: panel geometry changed in combat")
    _G.combat=false
    local callback=assert(combatJobs["windowControls:show:GameMenuFrame"],"CX9-05: combat reopen queued no replay")
    combatJobs["windowControls:show:GameMenuFrame"]=nil;callback()
    assert(frame.scale==1.4,"CX9-05: queued reopen did not restore the saved layout")
end)
BH3("S06-A3",function()
    local frame=Frame("AddonList",UIParent)
    frame.CloseButton=Frame(nil,frame,"Button")
    UIPanelWindows.AddonList={area="center",pushable=0}
    AddonList_HasAnyChanged=function() return true end
    assert(NS.WindowControls.Attach(frame,"bh3-addons"))
    local button=assert(NS.WindowControls.states[frame].minimize)
    button.scripts.OnClick(button)
    assert(frame.shown,"S06-A3: minimizing unsaved AddonList edits invoked its destructive native OnHide")
    AddonList_HasAnyChanged=nil
end)
BH3("S06-A4",function()
    local frame=Frame("GameMenuFrame",UIParent)
    NS.DB.windowControls.positions.GameMenuFrame={x=470,y=-300}
    assert(NS.WindowControls.Attach(frame,"bh3-position"))
    assert(frame.point[1]=="TOPLEFT")
    NS.WindowControls.DisableOwner("bh3-position")
    assert(frame.point and frame.point[1]=="CENTER","S06-A4: disabling controls left the saved custom anchor")
end)
]=], "-- Inspect skips the generic window adapter")
