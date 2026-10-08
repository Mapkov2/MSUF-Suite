dofile(arg[1] .. "/tools/tests/suite_bh3_state_support.lua").Run("suite_skin_class_style_contract.lua", [=[
BH3("CX9-01",function()
    assert(theme.ApplyLook("cleanModern"))
    local color=ns.CopyValue(theme.GetColorTable("accent"))
    local micro,preset,look=ns.DB.icons.microMenu.preset,ns.DB.theme.preset,ns.DB.theme.look
    assert(theme.SetColor("accent",0.1,0.2,0.3,1))
    theme.RestoreColor("accent",color[1],color[2],color[3],color[4],preset,look,micro)
    assert(ns.DB.icons.microMenu.preset==micro,"CX9-01: cancel did not restore the implicit Micro Bar preset")
end)
BH3("S05-A1",function()
    ns.DB.theme.look,ns.DB.theme.preset="custom","classColor"
    ns.DB.theme.colors.accent={0,0,0,1}
    assert(theme.RefreshDynamicLook(),"S05-A1: class palette did not refresh for a custom look")
    SameColor(ns.DB.theme.colors.accent,classes.ROGUE,"S05-A1: stale previous-character class palette")
end)
end
]=], "    assert(ns.LookOrder[5]")
