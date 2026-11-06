local root,client=assert(arg[1]),arg[2] or "Mainline"
local H=dofile(root.."/tools/tests/suite_bags_harness.lua")
for _,host in ipairs({false,true}) do
    local W=H.New(root,{client=client,catalogPresentation=true,config={customCategories="1|Gear|101"}})
    local checks,inputs=0,0
    if host then
        W.NS.HostBridge.MenuCheckbox=function(parent,label)
            checks=checks+1
            assert(label=="Show this category","host checkbox loses label")
            local check=W.P.ChildFrame("CheckButton",parent)
            check:SetSize(28,28);check.hostStyled=true
            return check
        end
        W.NS.HostBridge.MenuInput=function(edit) inputs=inputs+1;edit.hostStyled=true;return true end
    end
    W.Apply();W.P.InventoryEditor.Show()
    local E=W.P.InventoryEditor
    if host then
        assert(checks==1 and inputs>=3 and E.enabled.hostStyled and E.name.hostStyled,"editor bypasses MSUF host controls")
    else
        local check=E.enabled
        assert(check.bagCheckArms and check.bagCheckLabel:GetText()=="Show this category","fallback checkbox keeps native style")
        assert(check:GetCheckedTexture():GetAlpha()==0,"legacy yellow tick remains visible")
        check:SetChecked(true)
        assert(check.bagCheckArms[1]:IsShown() and check.bagCheckArms[2]:IsShown(),"programmatic check is not painted")
        check:SetChecked(false)
        assert(not check.bagCheckArms[1]:IsShown() and not check.bagCheckArms[2]:IsShown(),"uncheck leaves mark visible")
        check:SetChecked(true);check:Disable()
        assert(check.bagCheckArms[1]:GetAlpha()==.4 and check.bagCheckLabel.textColor[1]==.5,"disabled check/label not dimmed")
        check:Enable();assert(check.bagCheckArms[1]:GetAlpha()==1,"enable retains disabled styling")
        assert(check.hitInsets[2]<0,"fallback label has no click target")
    end
    E.Hide();E.Show()
    assert(E.enabled:GetChecked()==true and E.frame:IsShown(),"reopen loses category checkbox state")
    assert(#W.errors==0 and #W.taint==0 and #W.combatLayout==0,"editor UI error")
end
print("MSUF editor host/fallback checkbox and input styling passed: "..client)
