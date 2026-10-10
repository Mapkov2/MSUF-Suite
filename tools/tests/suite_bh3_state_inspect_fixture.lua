BH3("S08-A2",function()
    local function noop() end
    local hooks, painted={},{}
    local ns={Client={isForever=true},IsCombatLocked=function() return false end,
        Safety={Field=function(t,k) return t and t[k] end,Public=function() return true end,Read=noop},
        Surface={SetActive=noop},
        -- Forever's ModeTabs are Frames (LargeSideTabButtonTemplate): they take a surface (FV-9).
        AdapterKit={SkinControl=function(_,target) if target then painted[target]=true end end,
            Ensure=function(_,target) if target then painted[target]=true end return target~=nil end,
            SuppressVertexAlpha=noop,HookFunction=function() return true end}}
    local chrome={Spec=function() return {} end,Fade=noop,Attach=noop}
    chrome.New=function()
        return {owners={},exactSlots={},Activate=function() end,
            ForActiveOwners=function(_,_,callback) callback({active=true,owner="test"}) end}
    end
    ns.PaperDollChrome=chrome
    InspectFrame={ModeTabs={CharacterTab={},GuildTab={}}}
    PanelTemplates_GetSelectedTab=function() return 1 end
    InspectSwitchTabs=noop;hooksecurefunc=function(name,callback) hooks[name]=callback end
    -- Resolve the installed native post-hook without driving unrelated dossier rendering.
    local panel=assert(loadfile(arg[1] .. "/MSUF_Suite_Skin/Adapters/InspectPanel.lua"))("MSUF_Suite_Skin",ns)
    local owner
    for i=1,20 do local name,value=debug.getupvalue(panel.Apply,i);if name=="panel" then owner=value end end
    assert(owner);owner.InstallHooks();hooks.InspectSwitchTabs()
    assert(painted[InspectFrame.ModeTabs.CharacterTab] and painted[InspectFrame.ModeTabs.GuildTab],
        "S08-A2: Forever Inspect skinned hidden legacy tabs instead of visible ModeTabs")
end)
